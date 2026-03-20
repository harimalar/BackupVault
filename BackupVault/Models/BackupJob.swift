//
//  BackupJob.swift
//  BackupVault
//
//  Represents a backup job: source folders, destination, and run type (full vs incremental).
//

import Foundation

/// Type of backup run.
enum BackupRunType: String, Codable, CaseIterable {
    case full = "Full"
    case incremental = "Incremental"
}

/// A backup job definition: what to back up and where.
struct BackupJob: Identifiable, Codable, Equatable {
    let id: UUID
    var sourceFolderURLs: [URL]
    var destinationID: UUID
    var runType: BackupRunType
    var verifyWithChecksum: Bool
    var createdAt: Date
    var lastRunAt: Date?
    
    init(
        id: UUID = UUID(),
        sourceFolderURLs: [URL] = [],
        destinationID: UUID,
        runType: BackupRunType = .incremental,
        verifyWithChecksum: Bool = false,
        createdAt: Date = Date(),
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.sourceFolderURLs = sourceFolderURLs
        self.destinationID = destinationID
        self.runType = runType
        self.verifyWithChecksum = verifyWithChecksum
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id, destinationID, runType, verifyWithChecksum, createdAt, lastRunAt
        case sourceFolderPaths
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let paths = try c.decodeIfPresent([String].self, forKey: .sourceFolderPaths) ?? []
        sourceFolderURLs = paths.map { URL(fileURLWithPath: $0) }
        destinationID = try c.decode(UUID.self, forKey: .destinationID)
        runType = try c.decode(BackupRunType.self, forKey: .runType)
        verifyWithChecksum = try c.decode(Bool.self, forKey: .verifyWithChecksum)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastRunAt = try c.decodeIfPresent(Date.self, forKey: .lastRunAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sourceFolderURLs.map(\.path), forKey: .sourceFolderPaths)
        try c.encode(destinationID, forKey: .destinationID)
        try c.encode(runType, forKey: .runType)
        try c.encode(verifyWithChecksum, forKey: .verifyWithChecksum)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(lastRunAt, forKey: .lastRunAt)
    }
}
