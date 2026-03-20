//
//  FileScanner.swift
//  BackupVault
//
//  Recursively scans folders and collects file metadata for incremental comparison.
//

import Foundation
import UniformTypeIdentifiers

/// Result of scanning a single file (path relative to source root, size, modified date).
struct ScannedFile: Sendable {
    let relativePath: String
    let url: URL
    let size: Int64
    let modifiedDate: Date
}

/// Recursively scans directory trees and reports files with metadata.
final class FileScanner: @unchecked Sendable {
    
    private let fileManager = FileManager.default
    private var isCancelled = false
    
    /// Scan all source roots and yield (sourceRootIndex, ScannedFile) for each file.
    /// Uses efficient enumeration; optional exclusions (folder names, file patterns).
    func scan(
        sourceRoots: [URL],
        skipHidden: Bool = true,
        exclusions: BackupExclusions? = nil,
        onFile: @escaping (Int, ScannedFile) -> Void,
        onError: ((URL, Error) -> Void)? = nil
    ) throws {
        isCancelled = false
        for (index, root) in sourceRoots.enumerated() {
            guard !isCancelled else { return }
            try scanOne(root: root, rootIndex: index, basePath: "", skipHidden: skipHidden, exclusions: exclusions, onFile: onFile, onError: onError)
        }
    }
    
    func cancel() {
        isCancelled = true
    }
    
    private func scanOne(
        root: URL,
        rootIndex: Int,
        basePath: String,
        skipHidden: Bool,
        exclusions: BackupExclusions? = nil,
        onFile: @escaping (Int, ScannedFile) -> Void,
        onError: ((URL, Error) -> Void)?
    ) throws {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                onError?(url, error)
                return true
            }
        ) else {
            throw BackupError.cannotEnumerateDirectory(root)
        }
        
        while let url = enumerator.nextObject() as? URL, !isCancelled {
            let resourceValues: URLResourceValues
            do {
                resourceValues = try url.resourceValues(forKeys: resourceKeys)
            } catch {
                onError?(url, error)
                continue
            }
            
            if resourceValues.isDirectory == true {
                if skipHidden && url.lastPathComponent.hasPrefix(".") {
                    enumerator.skipDescendants()
                }
                if let ex = exclusions, ex.shouldExcludeFolder(name: url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            
            guard resourceValues.isRegularFile == true else { continue }
            if skipHidden && url.lastPathComponent.hasPrefix(".") { continue }
            if let ex = exclusions, ex.shouldExcludeFile(name: url.lastPathComponent) { continue }
            
            let size = Int64(resourceValues.fileSize ?? 0)
            let modified = resourceValues.contentModificationDate ?? Date()
            let relative: String = {
                let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
                guard url.path.hasPrefix(rootPath) else { return url.lastPathComponent }
                return String(url.path.dropFirst(rootPath.count))
            }()
            let scanned = ScannedFile(relativePath: relative, url: url, size: size, modifiedDate: modified)
            onFile(rootIndex, scanned)
        }
    }
}
