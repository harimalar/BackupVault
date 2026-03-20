//
//  BackupHealthStatus.swift
//  BackupVault
//
//  Health status model for the backup health system (aligns with BackupHealth snapshot).
//

import Foundation

/// Health status level for a component or overall backup.
enum BackupHealthLevel: String, Codable, CaseIterable {
    case good = "Good"
    case warning = "Warning"
    case critical = "Critical"
}

/// Health component scores (0–100) that roll into overall score.
struct BackupHealthScore: Codable, Equatable {
    var freshness: Double
    var storage: Double
    var integrity: Double
    var coverage: Double
    var reachability: Double
    
    var overall: Double {
        (freshness + storage + integrity + coverage + reachability) / 5.0
    }
    
    init(freshness: Double = 0, storage: Double = 0, integrity: Double = 0, coverage: Double = 0, reachability: Double = 0) {
        self.freshness = freshness
        self.storage = storage
        self.integrity = integrity
        self.coverage = coverage
        self.reachability = reachability
    }
}
