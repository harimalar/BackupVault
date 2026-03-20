//
//  BackupMetadata.swift
//  BackupVault
//
//  Tracks backup runs and file metadata for incremental backup and resume.
//

import Foundation

/// Single backup run (one snapshot folder).
struct BackupRun: Identifiable, Codable {
    let id: UUID
    let destinationID: UUID
    let startedAt: Date
    var completedAt: Date?
    var snapshotFolderName: String?
    var totalFilesScanned: Int
    var totalFilesCopied: Int
    var totalFilesHardLinked: Int
    var totalFilesSkipped: Int
    var totalBytesCopied: Int64
    var totalLogicalBytes: Int64
    var lastCopiedPath: String?  // For resume: relative path of last successfully copied file
    var state: BackupRunState
    /// When a full verification (e.g. SHA256) was last run for this backup.
    var verifiedAt: Date?
    
    init(
        id: UUID = UUID(),
        destinationID: UUID,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        snapshotFolderName: String? = nil,
        totalFilesScanned: Int = 0,
        totalFilesCopied: Int = 0,
        totalFilesHardLinked: Int = 0,
        totalFilesSkipped: Int = 0,
        totalBytesCopied: Int64 = 0,
        totalLogicalBytes: Int64 = 0,
        lastCopiedPath: String? = nil,
        state: BackupRunState = .inProgress,
        verifiedAt: Date? = nil
    ) {
        self.id = id
        self.destinationID = destinationID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.snapshotFolderName = snapshotFolderName
        self.totalFilesScanned = totalFilesScanned
        self.totalFilesCopied = totalFilesCopied
        self.totalFilesHardLinked = totalFilesHardLinked
        self.totalFilesSkipped = totalFilesSkipped
        self.totalBytesCopied = totalBytesCopied
        self.totalLogicalBytes = totalLogicalBytes
        self.lastCopiedPath = lastCopiedPath
        self.state = state
        self.verifiedAt = verifiedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id, destinationID, startedAt, completedAt, snapshotFolderName, totalFilesScanned, totalFilesCopied
        case totalFilesHardLinked, totalFilesSkipped, totalBytesCopied, totalLogicalBytes, lastCopiedPath, state, verifiedAt
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        destinationID = try c.decode(UUID.self, forKey: .destinationID)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        snapshotFolderName = try c.decodeIfPresent(String.self, forKey: .snapshotFolderName)
        totalFilesScanned = try c.decode(Int.self, forKey: .totalFilesScanned)
        totalFilesCopied = try c.decode(Int.self, forKey: .totalFilesCopied)
        totalFilesHardLinked = try c.decodeIfPresent(Int.self, forKey: .totalFilesHardLinked) ?? 0
        totalFilesSkipped = try c.decodeIfPresent(Int.self, forKey: .totalFilesSkipped) ?? 0
        totalBytesCopied = try c.decodeIfPresent(Int64.self, forKey: .totalBytesCopied) ?? 0
        totalLogicalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalLogicalBytes) ?? totalBytesCopied
        lastCopiedPath = try c.decodeIfPresent(String.self, forKey: .lastCopiedPath)
        state = try c.decode(BackupRunState.self, forKey: .state)
        verifiedAt = try c.decodeIfPresent(Date.self, forKey: .verifiedAt)
    }
    
    /// Snapshot folder name for this run (e.g. 2026-03-15_10-30).
    func snapshotFolderName(dateFormatter: DateFormatter, timeFormatter: DateFormatter) -> String {
        snapshotFolderName ?? "\(dateFormatter.string(from: startedAt))_\(timeFormatter.string(from: startedAt))"
    }
    
    /// Transfer speed in bytes per second (0 if duration unknown).
    var transferSpeedBytesPerSecond: Double {
        guard let end = completedAt else { return 0 }
        let duration = end.timeIntervalSince(startedAt)
        return duration > 0 ? Double(totalBytesCopied) / duration : 0
    }
    
    /// Backup duration in seconds (nil if not completed).
    var durationSeconds: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }
}

enum BackupRunState: String, Codable {
    case inProgress
    case completed
    case interrupted
}

/// Per-file metadata we compare for incremental backup.
struct FileRecord: Codable, Equatable {
    let sourceRootName: String
    let sourceRootPath: String
    let relativePath: String
    let snapshotRelativePath: String
    let size: Int64
    let modifiedDate: Date
    
    init(
        sourceRootName: String,
        sourceRootPath: String,
        relativePath: String,
        snapshotRelativePath: String? = nil,
        size: Int64,
        modifiedDate: Date
    ) {
        self.sourceRootName = sourceRootName
        self.sourceRootPath = sourceRootPath
        self.relativePath = relativePath
        self.snapshotRelativePath = snapshotRelativePath ?? relativePath
        self.size = size
        self.modifiedDate = modifiedDate
    }

    var storageKey: String {
        snapshotRelativePath.isEmpty ? relativePath : snapshotRelativePath
    }

    enum CodingKeys: String, CodingKey {
        case sourceRootName
        case sourceRootPath
        case relativePath
        case snapshotRelativePath
        case size
        case modifiedDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = try c.decode(String.self, forKey: .relativePath)
        snapshotRelativePath = try c.decodeIfPresent(String.self, forKey: .snapshotRelativePath) ?? relativePath
        sourceRootName = try c.decodeIfPresent(String.self, forKey: .sourceRootName)
            ?? snapshotRelativePath.split(separator: "/").first.map(String.init)
            ?? ""
        sourceRootPath = try c.decodeIfPresent(String.self, forKey: .sourceRootPath) ?? ""
        size = try c.decode(Int64.self, forKey: .size)
        modifiedDate = try c.decode(Date.self, forKey: .modifiedDate)
    }
}

/// Manifest of files in a previous backup (by BackupDate folder path).
struct BackupManifest: Codable {
    let backupDatePath: String  // e.g. "2026-03-15"
    let computerName: String
    let recordedAt: Date
    var files: [FileRecord]
    
    init(backupDatePath: String, computerName: String, recordedAt: Date = Date(), files: [FileRecord]) {
        self.backupDatePath = backupDatePath
        self.computerName = computerName
        self.recordedAt = recordedAt
        self.files = files
    }
}
