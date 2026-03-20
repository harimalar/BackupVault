//
//  BackupHealth.swift
//  BackupVault
//
//  Models for Backup Health & Risk Detection dashboard.
//

import Foundation

/// Overall health status for the backup system.
enum HealthStatus: String, CaseIterable {
    case good = "Good"
    case warning = "Warning"
    case critical = "Critical"
    
    var colorName: String {
        switch self {
        case .good: return "green"
        case .warning: return "orange"
        case .critical: return "red"
        }
    }
    
    var symbol: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }
}

/// A single health check result (e.g. "Last backup: 3 hours ago").
struct HealthCheckItem: Identifiable {
    let id: String
    let title: String
    let status: HealthStatus
    let detail: String?
    let symbol: String?
    
    init(id: String, title: String, status: HealthStatus, detail: String? = nil, symbol: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.symbol = symbol ?? status.symbol
    }
}

/// Component scores that roll up into overall health (0–100 each).
struct HealthScores {
    var freshness: Double   // Last backup age: 100% if < 24h, lower if older
    var storage: Double     // Free space % on destination
    var integrity: Double   // Verification recency
    var coverage: Double    // No interrupted backups, all sources covered
    var reachability: Double // Destination reachable = 100, else 0
    
    var overall: Double {
        let count = 5.0
        return (freshness + storage + integrity + coverage + reachability) / count
    }
}

/// Full health snapshot for the dashboard.
struct BackupHealthSnapshot: Identifiable {
    let id: UUID
    let overallScore: Double
    let status: HealthStatus
    let scores: HealthScores
    let checks: [HealthCheckItem]
    let destinationName: String
    let destinationID: UUID
    let lastBackupAt: Date?
    let filesProtected: Int
    let backupSizeBytes: Int64
    let warnings: [String]
    
    static func empty(destinationName: String, destinationID: UUID) -> BackupHealthSnapshot {
        BackupHealthSnapshot(
            id: UUID(),
            overallScore: 0,
            status: .critical,
            scores: HealthScores(freshness: 0, storage: 0, integrity: 0, coverage: 0, reachability: 0),
            checks: [],
            destinationName: destinationName,
            destinationID: destinationID,
            lastBackupAt: nil,
            filesProtected: 0,
            backupSizeBytes: 0,
            warnings: ["No backup data yet"]
        )
    }
}
