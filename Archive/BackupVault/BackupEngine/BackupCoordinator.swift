//
//  BackupCoordinator.swift
//  BackupVault
//
//  Orchestrates: resolve destination (mount NAS if needed), scan, incremental filter, copy, verify, save manifest.
//

import Foundation

/// Live progress for UI.
struct BackupProgress: Sendable {
    var phase: BackupPhase
    var filesScanned: Int
    var filesToCopy: Int
    var filesCopied: Int
    var filesHardLinked: Int
    var filesSkipped: Int
    var bytesCopied: Int64
    var logicalBytesProtected: Int64
    var currentFile: String?
    var bytesPerSecond: Double
    var estimatedTimeRemaining: TimeInterval?
    var errorMessage: String?
}

enum BackupPhase: Sendable {
    case resolvingDestination
    case scanning
    case copying
    case verifying
    case completed
    case failed
}

/// One scanned file with its source root index (for multi-folder backup).
struct ScannedFileWithRoot: Sendable {
    let rootIndex: Int
    let file: ScannedFile
}

private struct SourceRootDescriptor {
    let rootURL: URL
    let snapshotFolderName: String
}

final class BackupCoordinator: @unchecked Sendable {
    
    private let scanner = FileScanner()
    private let copyEngine = FileCopyEngine()
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH-mm"
        return f
    }()
    
    private static let stateFileName = ".backupvault_state.json"
    
    /// Run full backup: resolve destination, scan sources, incremental filter, copy, verify.
    func runBackup(
        sourceRoots: [URL],
        destination: BackupDestination,
        verifyWithChecksum: Bool,
        runStartedAt: Date? = nil,
        lastCopiedPath: String?,
        exclusions: BackupExclusions? = nil,
        progress: @escaping (BackupProgress) -> Void
    ) async throws {
        progress(BackupProgress(phase: .resolvingDestination, filesScanned: 0, filesToCopy: 0, filesCopied: 0, filesHardLinked: 0, filesSkipped: 0, bytesCopied: 0, logicalBytesProtected: 0, currentFile: nil, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: nil))
        
        let destinationBase = try await resolveDestination(destination)
        Logger.shared.info("Backup started to \(destination.name)")
        
        let computerName = Host.current().localizedName ?? "Mac"
        let now = runStartedAt ?? Date()
        let snapshotFolderName = "\(dateFormatter.string(from: now))_\(timeFormatter.string(from: now))"
        let backupBase = destinationBase
            .appendingPathComponent("BackupVault")
            .appendingPathComponent(computerName)
            .appendingPathComponent(snapshotFolderName)
        
        try FileManager.default.createDirectory(at: backupBase, withIntermediateDirectories: true)
        
        let sourceDescriptors = makeSourceRootDescriptors(for: sourceRoots)
        var allScanned: [SnapshotFileCandidate] = []
        var scannedLogicalBytes: Int64 = 0
        try scanner.scan(sourceRoots: sourceRoots, skipHidden: true, exclusions: exclusions) { rootIndex, scanned in
            let descriptor = sourceDescriptors[rootIndex]
            scannedLogicalBytes += scanned.size
            allScanned.append(
                SnapshotFileCandidate(
                    sourceRootName: descriptor.snapshotFolderName,
                    sourceRootPath: descriptor.rootURL.path,
                    relativePath: scanned.relativePath,
                    snapshotRelativePath: descriptor.snapshotFolderName + "/" + scanned.relativePath,
                    url: scanned.url,
                    size: scanned.size,
                    modifiedDate: scanned.modifiedDate
                )
            )
            if allScanned.count % 100 == 0 {
                progress(BackupProgress(phase: .scanning, filesScanned: allScanned.count, filesToCopy: 0, filesCopied: 0, filesHardLinked: 0, filesSkipped: 0, bytesCopied: 0, logicalBytesProtected: scannedLogicalBytes, currentFile: descriptor.snapshotFolderName + "/" + scanned.relativePath, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: nil))
            }
        } onError: { _, _ in }
        
        let logicalBytesProtected = scannedLogicalBytes
        progress(BackupProgress(phase: .scanning, filesScanned: allScanned.count, filesToCopy: 0, filesCopied: 0, filesHardLinked: 0, filesSkipped: 0, bytesCopied: 0, logicalBytesProtected: logicalBytesProtected, currentFile: nil, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: nil))
        
        let parentBase = backupBase.deletingLastPathComponent()
        var previousRecords: [FileRecord] = []
        var previousSnapshotBase: URL?
        if let lastRun = DestinationStore.shared.lastCompletedRun(forDestinationID: destination.id) {
            let prevFolderName = lastRun.snapshotFolderName(dateFormatter: dateFormatter, timeFormatter: timeFormatter)
            previousSnapshotBase = parentBase.appendingPathComponent(prevFolderName)
            let previousManifestPath = previousSnapshotBase!.appendingPathComponent("manifest.json")
            if let data = try? Data(contentsOf: previousManifestPath),
               let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) {
                previousRecords = manifest.files
            }
        }
        
        _ = lastCopiedPath
        let previousMap = IncrementalLogic.previousRecordMap(previousRecords)
        let filesToCopy: [FileCopyEngine.FileToCopy] = allScanned.map { item in
            let previousRecord = previousMap[item.snapshotRelativePath]
            let previousFileURL: URL? = {
                guard let base = previousSnapshotBase,
                      !IncrementalLogic.fileHasChanged(item, previousRecord: previousRecord) else {
                    return nil
                }
                let previousFile = base.appendingPathComponent(item.snapshotRelativePath)
                return fileManager.fileExists(atPath: previousFile.path) ? previousFile : nil
            }()
            return FileCopyEngine.FileToCopy(
                sourceURL: item.url,
                displayPath: item.snapshotRelativePath,
                destinationRelativePath: item.snapshotRelativePath,
                fileSize: item.size,
                previousFileURL: previousFileURL
            )
        }
        let totalTransferBytes = filesToCopy
            .filter { $0.previousFileURL == nil }
            .reduce(into: Int64(0)) { $0 += $1.fileSize }
        let filesSkippedCount = 0
        
        progress(BackupProgress(phase: .copying, filesScanned: allScanned.count, filesToCopy: filesToCopy.count, filesCopied: 0, filesHardLinked: 0, filesSkipped: filesSkippedCount, bytesCopied: 0, logicalBytesProtected: logicalBytesProtected, currentFile: nil, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: nil))
        
        var lastCopyBytes: Int64 = 0
        var lastHardLinked: Int = 0
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var config = FileCopyEngine.CopyConfig()
                    config.verifyWithChecksum = verifyWithChecksum
                    config.lockSourceFile = true
                    config.maxConcurrent = 6
                    try self.copyEngine.copy(files: filesToCopy, destinationBase: backupBase, config: config) { copyProg in
                        lastCopyBytes = copyProg.bytesCopied
                        lastHardLinked = copyProg.filesHardLinked
                        if let path = copyProg.currentFile {
                            self.saveResumeState(BackupResumeState(lastCopiedPath: path, filesCopiedCount: copyProg.filesCopied + copyProg.filesHardLinked, bytesCopied: copyProg.bytesCopied), to: backupBase)
                        }
                        let remainingBytes = totalTransferBytes - copyProg.bytesCopied
                        let eta: TimeInterval? = copyProg.bytesPerSecond > 0 && remainingBytes > 0
                            ? Double(remainingBytes) / copyProg.bytesPerSecond
                            : nil
                        progress(BackupProgress(
                            phase: .copying,
                            filesScanned: copyProg.filesScanned,
                            filesToCopy: copyProg.filesToCopy,
                            filesCopied: copyProg.filesCopied,
                            filesHardLinked: copyProg.filesHardLinked,
                            filesSkipped: filesSkippedCount,
                            bytesCopied: copyProg.bytesCopied,
                            logicalBytesProtected: logicalBytesProtected,
                            currentFile: copyProg.currentFile,
                            bytesPerSecond: copyProg.bytesPerSecond,
                            estimatedTimeRemaining: eta,
                            errorMessage: nil
                        ))
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        let currentManifestPath = backupBase.appendingPathComponent("manifest.json")
        let manifest = BackupManifest(
            backupDatePath: snapshotFolderName,
            computerName: computerName,
            recordedAt: Date(),
            files: IncrementalLogic.toRecords(allScanned)
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try AtomicFileWriter.write(manifestData, to: currentManifestPath)
        
        saveResumeState(nil, to: backupBase)
        let duration = Date().timeIntervalSince(now)
        Logger.shared.logFilesCopied(count: filesToCopy.count, bytes: lastCopyBytes, duration: duration)
        if verifyWithChecksum { Logger.shared.logVerificationResult(success: true, fileCount: filesToCopy.count) }
        
        progress(BackupProgress(phase: .completed, filesScanned: allScanned.count, filesToCopy: filesToCopy.count, filesCopied: filesToCopy.count - lastHardLinked, filesHardLinked: lastHardLinked, filesSkipped: filesSkippedCount, bytesCopied: lastCopyBytes, logicalBytesProtected: logicalBytesProtected, currentFile: nil, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: nil))
    }
    
    private struct BackupResumeState: Codable {
        var lastCopiedPath: String?
        var filesCopiedCount: Int
        var bytesCopied: Int64
    }
    
    private func loadResumeState(from snapshotBase: URL) -> BackupResumeState? {
        let url = snapshotBase.appendingPathComponent(Self.stateFileName)
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(BackupResumeState.self, from: data) else { return nil }
        return state
    }
    
    /// Crash-safe: write to .tmp then rename so state is never half-written.
    private func saveResumeState(_ state: BackupResumeState?, to snapshotBase: URL) {
        let url = snapshotBase.appendingPathComponent(Self.stateFileName)
        if let state = state, let data = try? JSONEncoder().encode(state) {
            try? AtomicFileWriter.write(data, to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
            let tmpURL = snapshotBase.appendingPathComponent(Self.stateFileName + ".tmp")
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }
    
    private func resolveDestination(_ destination: BackupDestination) async throws -> URL {
        switch destination.type {
        case .externalDrive:
            guard destination.path.hasDirectoryPath,
                  (try? destination.path.checkResourceIsReachable()) == true else {
                throw BackupError.destinationUnavailable(destination)
            }
            return destination.path
        case .nas:
            guard let host = destination.nasHost, let share = destination.nasShare, let username = destination.nasUsername else {
                throw BackupError.nasMountFailed("Missing NAS configuration")
            }
            let password = try KeychainService.shared.getPassword(forDestinationID: destination.id) ?? ""
            let mounted = try await NASMountService.shared.mount(host: host, share: share, username: username, password: password)
            return mounted
        }
    }
    
    func cancel() {
        scanner.cancel()
        copyEngine.cancel()
    }

    private func makeSourceRootDescriptors(for sourceRoots: [URL]) -> [SourceRootDescriptor] {
        var seenNames: [String: Int] = [:]
        return sourceRoots.map { root in
            let rawName = root.lastPathComponent.isEmpty ? "Root" : root.lastPathComponent
            let count = seenNames[rawName, default: 0]
            seenNames[rawName] = count + 1
            let snapshotName = count == 0 ? rawName : "\(rawName)-\(count + 1)"
            return SourceRootDescriptor(rootURL: root, snapshotFolderName: snapshotName)
        }
    }
}
