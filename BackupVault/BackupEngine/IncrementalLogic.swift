//
//  IncrementalLogic.swift
//  BackupVault
//
//  Decides which files need to be copied based on path, size, and modified date.
//

import Foundation

struct SnapshotFileCandidate {
    let sourceRootName: String
    let sourceRootPath: String
    let relativePath: String
    let snapshotRelativePath: String
    let url: URL
    let size: Int64
    let modifiedDate: Date
}

/// Compares current scan with previous manifest using file size and modified date.
struct IncrementalLogic {
    
    static func previousRecordMap(_ previousManifest: [FileRecord]) -> [String: FileRecord] {
        Dictionary(uniqueKeysWithValues: previousManifest.map { ($0.storageKey, $0) })
    }

    static func fileHasChanged(_ file: SnapshotFileCandidate, previousRecord: FileRecord?) -> Bool {
        guard let previousRecord else { return true }
        if previousRecord.size != file.size { return true }
        if abs(previousRecord.modifiedDate.timeIntervalSince(file.modifiedDate)) > 1 { return true }
        return false
    }
    
    /// Convert scanned files to FileRecord for saving manifest.
    static func toRecords(_ scanned: [SnapshotFileCandidate]) -> [FileRecord] {
        scanned.map {
            FileRecord(
                sourceRootName: $0.sourceRootName,
                sourceRootPath: $0.sourceRootPath,
                relativePath: $0.relativePath,
                snapshotRelativePath: $0.snapshotRelativePath,
                size: $0.size,
                modifiedDate: $0.modifiedDate
            )
        }
    }
}
