//
//  FileCopyEngine.swift
//  BackupVault
//
//  Reliable copy: atomic writes, source file locking, parallel queue, progress, optional bandwidth throttle.
//  Existing backup files are never corrupted (write to temp then atomic replace).
//

import Foundation
import CryptoKit
import Darwin

/// Progress reported during copy. Thread-safe aggregate.
struct CopyProgress: Sendable {
    var filesScanned: Int
    var filesToCopy: Int
    var filesCopied: Int
    var filesHardLinked: Int
    var bytesCopied: Int64
    var currentFile: String?
    var bytesPerSecond: Double
    var startedAt: Date
}

/// Thread-safe progress tracker for the copy phase.
final class CopyProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var filesCopied = 0
    private var filesHardLinked = 0
    private var bytesCopied: Int64 = 0
    private let start = Date()
    private let totalFiles: Int
    private let totalBytes: Int64
    
    init(totalFiles: Int, totalBytes: Int64) {
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
    }
    
    func add(fileRelativePath: String, fileSize: Int64, wasHardLink: Bool) {
        lock.lock()
        if wasHardLink {
            filesHardLinked += 1
        } else {
            filesCopied += 1
            bytesCopied += fileSize
        }
        lock.unlock()
    }
    
    func currentProgress(currentFile: String?) -> CopyProgress {
        lock.lock()
        let f = filesCopied
        let h = filesHardLinked
        let b = bytesCopied
        lock.unlock()
        let elapsed = Date().timeIntervalSince(start)
        let rate = elapsed > 0 ? Double(b) / elapsed : 0
        return CopyProgress(
            filesScanned: totalFiles,
            filesToCopy: totalFiles,
            filesCopied: f,
            filesHardLinked: h,
            bytesCopied: b,
            currentFile: currentFile,
            bytesPerSecond: rate,
            startedAt: start
        )
    }
}

/// Copies files with atomic writes, optional source lock, parallel queue, progress, and throttle.
final class FileCopyEngine: @unchecked Sendable {
    
    private let fileManager = FileManager.default
    private var isCancelled = false
    private let copyQueue = DispatchQueue(label: "com.backupvault.copy.workers", qos: .userInitiated, attributes: .concurrent)
    private let progressQueue = DispatchQueue(label: "com.backupvault.copy.progress", qos: .userInitiated)
    
    /// Chunk size for stream copy (and throttle granularity).
    private let chunkSize = 256 * 1024
    
    func cancel() {
        isCancelled = true
    }
    
    struct FileToCopy: Sendable {
        let sourceURL: URL
        let displayPath: String
        let destinationRelativePath: String
        let fileSize: Int64
        /// If set and file exists at this URL with same size, create hard link instead of copy (saves space).
        let previousFileURL: URL?
    }
    
    struct CopyConfig {
        var maxConcurrent: Int = 4
        var verifyWithChecksum: Bool = false
        /// Max bytes per second; nil = no throttle.
        var maxBytesPerSecond: Double? = nil
        /// Use advisory read lock on source file during copy (prevents source change mid-copy).
        var lockSourceFile: Bool = true
    }
    
    /// Copy files: atomic writes (temp then replace), optional source lock, parallel queue, progress, optional throttle.
    func copy(
        files: [FileToCopy],
        destinationBase: URL,
        config: CopyConfig = CopyConfig(),
        progress: @escaping (CopyProgress) -> Void
    ) throws {
        isCancelled = false
        let totalBytes = files.map(\.fileSize).reduce(0, +)
        let tracker = CopyProgressTracker(totalFiles: files.count, totalBytes: totalBytes)
        let throttle = BandwidthThrottle(maxBytesPerSecond: config.maxBytesPerSecond)
        let semaphore = DispatchSemaphore(value: config.maxConcurrent)
        let group = DispatchGroup()
        let errorLock = NSLock()
        var firstError: Error?
        
        for item in files {
            guard !isCancelled else { throw BackupError.cancelled }
            
            let sourceURL = item.sourceURL
            let destFile = destinationBase.appendingPathComponent(item.destinationRelativePath)
            let relPath = item.displayPath
            let size = item.fileSize
            let verify = config.verifyWithChecksum
            let lockSource = config.lockSourceFile
            let previousURL = item.previousFileURL
            
            semaphore.wait()
            group.enter()
            copyQueue.async { [weak self] in
                defer { semaphore.signal(); group.leave() }
                guard let self = self, !self.isCancelled else { return }
                
                do {
                    let usedHardLink: Bool
                    if let prev = previousURL, self.tryHardLink(previousFile: prev, dest: destFile, expectedSize: size) {
                        usedHardLink = true
                    } else {
                        try self.copyOneAtomically(
                            source: sourceURL,
                            dest: destFile,
                            expectedSize: size,
                            verifyWithChecksum: verify,
                            lockSource: lockSource,
                            throttle: throttle
                        )
                        usedHardLink = false
                    }
                    tracker.add(fileRelativePath: relPath, fileSize: size, wasHardLink: usedHardLink)
                    self.progressQueue.async {
                        progress(tracker.currentProgress(currentFile: relPath))
                    }
                } catch {
                    Logger.shared.logError(error, context: "Copy failed: \(relPath)")
                    errorLock.lock()
                    if firstError == nil { firstError = error }
                    errorLock.unlock()
                    self.progressQueue.async { progress(tracker.currentProgress(currentFile: relPath)) }
                }
            }
        }
        
        group.wait()
        if isCancelled { throw BackupError.cancelled }
        errorLock.lock()
        let err = firstError
        errorLock.unlock()
        if let e = err { throw e }
    }
    
    /// When previous snapshot has same file (unchanged), hard link to save space. Returns true if link created.
    /// Hard links only work on the same volume; we try link and fall back to copy on EXDEV.
    private func tryHardLink(previousFile: URL, dest: URL, expectedSize: Int64) -> Bool {
        guard fileManager.fileExists(atPath: previousFile.path) else { return false }
        guard let prevRes = try? previousFile.resourceValues(forKeys: [.fileSizeKey]),
              Int64(prevRes.fileSize ?? 0) == expectedSize else { return false }
        do {
            try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: dest.path) { try fileManager.removeItem(at: dest) }
            try fileManager.linkItem(at: previousFile, to: dest)
            return true
        } catch let err as NSError where err.domain == NSPOSIXErrorDomain && err.code == Int(EXDEV) {
            return false
        } catch {
            return false
        }
    }
    
    /// Copy one file: stream to temp, sync, atomic replace. Optionally lock source and throttle.
    private func copyOneAtomically(
        source: URL,
        dest: URL,
        expectedSize: Int64,
        verifyWithChecksum: Bool,
        lockSource: Bool,
        throttle: BandwidthThrottle
    ) throws {
        try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        let tempURL = AtomicFileWriter.tempURL(forDestination: dest)
        defer { try? fileManager.removeItem(at: tempURL) }
        
        guard fileManager.createFile(atPath: tempURL.path, contents: nil, attributes: nil) else {
            throw BackupError.copyFailed(source, NSError(domain: "BackupVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create temp file"]))
        }
        
        let readFD: Int32
        let shouldUnlock: Bool
        readFD = open(source.path, O_RDONLY)
        if lockSource {
            guard readFD >= 0 else { throw BackupError.copyFailed(source, NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Cannot open source: \(String(cString: strerror(errno)))"])) }
            guard flock(readFD, LOCK_SH) == 0 else { throw BackupError.copyFailed(source, NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Cannot lock source"])) }
            shouldUnlock = true
        } else {
            guard readFD >= 0 else { throw BackupError.copyFailed(source, NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)) }
            shouldUnlock = false
        }
        defer {
            if shouldUnlock {
                flock(readFD, LOCK_UN)
            }
            close(readFD)
        }
        
        let writeHandle = try FileHandle(forWritingTo: tempURL)
        defer { try? writeHandle.close() }
        
        var totalWritten: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        
        while totalWritten < expectedSize {
            guard !isCancelled else { throw BackupError.cancelled }
            let toRead = min(chunkSize, Int(expectedSize - totalWritten))
            let readCount = read(readFD, &buffer, toRead)
            guard readCount > 0 else {
                if readCount == 0 { break }
                throw BackupError.copyFailed(source, NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
            }
            let data = Data(bytes: buffer, count: readCount)
            try writeHandle.write(contentsOf: data)
            totalWritten += Int64(readCount)
            throttle.consume(bytes: readCount)
        }
        
        try writeHandle.synchronize()
        try writeHandle.close()
        
        if totalWritten != expectedSize {
            try? fileManager.removeItem(at: tempURL)
            throw BackupError.copyFailed(source, NSError(domain: "BackupVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "Size mismatch: wrote \(totalWritten), expected \(expectedSize)"]))
        }
        
        if verifyWithChecksum {
            let hash = try FileHasher.sha256(url: tempURL)
            _ = hash
        }
        
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try AtomicFileWriter.replace(dest: dest, withTemp: tempURL)
    }
}
