//
//  BackupSnapshot.swift
//  BackupVault
//
//  Represents a single backup snapshot (one point-in-time backup folder).
//

import Foundation

/// A backup snapshot: one dated folder under BackupVault/ComputerName/.
struct BackupSnapshot: Identifiable, Codable, Equatable {
    let id: UUID
    let computerName: String
    /// Snapshot folder name, e.g. "2026-03-15_10-30".
    let snapshotFolderName: String
    let path: URL
    let createdAt: Date
    var fileCount: Int
    var totalBytes: Int64
    var verifiedAt: Date?
    
    init(
        id: UUID = UUID(),
        computerName: String,
        snapshotFolderName: String,
        path: URL,
        createdAt: Date = Date(),
        fileCount: Int = 0,
        totalBytes: Int64 = 0,
        verifiedAt: Date? = nil
    ) {
        self.id = id
        self.computerName = computerName
        self.snapshotFolderName = snapshotFolderName
        self.path = path
        self.createdAt = createdAt
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.verifiedAt = verifiedAt
    }
    
    var displayName: String {
        snapshotFolderName.replacingOccurrences(of: "_", with: " ")
    }
}
