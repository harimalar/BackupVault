//
//  HealthEngine.swift
//  BackupVault
//
//  Computes Backup Health & Risk: freshness, storage, integrity, coverage, reachability.
//

import Foundation

/// Thresholds for health status (aligned with spec).
enum HealthThresholds {
    /// Freshness: last backup age.
    static let freshnessGoodHours = 24.0
    static let freshnessWarningDays = 3.0
    static let freshnessCriticalDays = 7.0
    
    /// Storage: free space % on destination volume.
    static let storageGoodFreePercent = 30.0
    static let storageWarningFreePercent = 20.0
    static let storageCriticalFreePercent = 10.0
    
    /// Integrity: last full verification age.
    static let verificationGoodDays = 7.0
    static let verificationWarningDays = 30.0
}

final class HealthEngine {
    
    private let store = DestinationStore.shared
    private let fileManager = FileManager.default
    
    /// Compute health snapshot for a destination. Use optional resolvedPath if already mounted (e.g. after backup).
    func computeHealth(destination: BackupDestination, resolvedPath: URL? = nil) async -> BackupHealthSnapshot {
        let lastRun = store.lastCompletedRun(forDestinationID: destination.id)
        // Use separate verified run so a plain backup never erases verification status
        let lastVerifiedRun = store.lastVerifiedRun(forDestinationID: destination.id)
        let hasInterrupted = store.lastIncompleteRun(forDestinationID: destination.id) != nil
        
        var checks: [HealthCheckItem] = []
        var warnings: [String] = []
        var scores = HealthScores(
            freshness: 0,
            storage: 100,
            integrity: 0,
            coverage: hasInterrupted ? 50 : 100,
            reachability: 0
        )
        
        let lastBackupAt = lastRun?.completedAt ?? lastRun?.startedAt
        let filesProtected = lastRun?.totalFilesScanned ?? 0
        let backupSizeBytes = lastRun?.totalLogicalBytes ?? lastRun?.totalBytesCopied ?? 0
        
        // —— Freshness ——
        if let date = lastBackupAt {
            let hours = Date().timeIntervalSince(date) / 3600
            let days = hours / 24
            if hours < HealthThresholds.freshnessGoodHours {
                scores.freshness = 100
                checks.append(HealthCheckItem(id: "freshness", title: "Last backup", status: .good, detail: formatLastBackupAge(date)))
            } else if days < HealthThresholds.freshnessWarningDays {
                scores.freshness = 70
                checks.append(HealthCheckItem(id: "freshness", title: "Last backup", status: .warning, detail: formatLastBackupAge(date)))
                warnings.append("Last backup was \(formatLastBackupAge(date).lowercased())")
            } else {
                scores.freshness = days < HealthThresholds.freshnessCriticalDays ? 40 : 0
                checks.append(HealthCheckItem(id: "freshness", title: "Last backup", status: .critical, detail: formatLastBackupAge(date)))
                warnings.append("Last backup was \(formatLastBackupAge(date).lowercased()) — run a backup soon")
            }
        } else {
            checks.append(HealthCheckItem(id: "freshness", title: "Last backup", status: .critical, detail: "Never"))
            warnings.append("No backup has been completed yet")
        }
        
        // —— Destination reachability & storage ——
        let pathToCheck = resolvedPath ?? destination.path
        if destination.type == .externalDrive || pathToCheck.path.hasPrefix("/Volumes") || pathToCheck.path == destination.path.path {
            var reachable = false
            if let _ = try? pathToCheck.checkResourceIsReachable(), pathToCheck.hasDirectoryPath {
                reachable = true
            }
            if reachable {
                scores.reachability = 100
                checks.append(HealthCheckItem(id: "reach", title: "Destination reachable", status: .good, detail: "Yes"))
                
                // Volume capacity (works on any URL on the volume)
                if let total = try? pathToCheck.resourceValues(forKeys: [.volumeTotalCapacityKey]).volumeTotalCapacity,
                   let free = try? pathToCheck.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
                   total > 0 {
                    let freePercent = Double(free) / Double(total) * 100
                    if freePercent >= HealthThresholds.storageGoodFreePercent {
                        scores.storage = 100
                        checks.append(HealthCheckItem(id: "storage", title: "Drive space", status: .good, detail: String(format: "%.0f%% free", freePercent)))
                    } else if freePercent >= HealthThresholds.storageWarningFreePercent {
                        scores.storage = 60
                        checks.append(HealthCheckItem(id: "storage", title: "Drive space", status: .warning, detail: String(format: "%.0f%% free", freePercent)))
                        warnings.append("Backup drive \(String(format: "%.0f", freePercent))% full — consider freeing space")
                    } else {
                        scores.storage = freePercent >= HealthThresholds.storageCriticalFreePercent ? 30 : 0
                        checks.append(HealthCheckItem(id: "storage", title: "Drive space", status: .critical, detail: String(format: "%.0f%% free", freePercent)))
                        warnings.append("Backup drive nearly full (\(String(format: "%.0f", freePercent))% free)")
                    }
                }
            } else {
                checks.append(HealthCheckItem(id: "reach", title: "Destination reachable", status: .critical, detail: "No — connect drive"))
                warnings.append("Destination not reachable — connect the backup drive")
            }
        } else {
            // NAS: we don't have a path until mounted; show generic status
            scores.reachability = 50
            checks.append(HealthCheckItem(id: "reach", title: "NAS destination", status: .warning, detail: "Reachability checked when backup runs"))
        }
        
        // —— Integrity (verification) ——
        // Use lastVerifiedRun so plain backups don't reset verification status
        let verifiedAt = lastVerifiedRun?.verifiedAt
        if let date = verifiedAt {
            let days = Date().timeIntervalSince(date) / 86400
            if days <= HealthThresholds.verificationGoodDays {
                scores.integrity = 100
                checks.append(HealthCheckItem(id: "integrity", title: "Files verified", status: .good, detail: "\(Int(days)) days ago"))
            } else if days <= HealthThresholds.verificationWarningDays {
                scores.integrity = 70
                checks.append(HealthCheckItem(id: "integrity", title: "Files verified", status: .warning, detail: "\(Int(days)) days ago"))
                warnings.append("Last full verification \(Int(days)) days ago")
            } else {
                scores.integrity = 40
                checks.append(HealthCheckItem(id: "integrity", title: "Files verified", status: .warning, detail: "\(Int(days)) days ago"))
                warnings.append("Last full verification \(Int(days)) days ago — consider verifying again")
            }
        } else if lastBackupAt != nil {
            // Has backups but no verification run yet
            scores.integrity = 50
            checks.append(HealthCheckItem(id: "integrity", title: "Files verified", status: .warning, detail: "No full verification yet"))
            // Only warn if the user hasn't dismissed verification already
        } else {
            // No backup at all — don't penalise for missing verification
            scores.integrity = 100
            checks.append(HealthCheckItem(id: "integrity", title: "Files verified", status: .good, detail: "—"))
        }
        
        // —— Coverage ——
        if hasInterrupted {
            checks.append(HealthCheckItem(id: "coverage", title: "Some files not backed up", status: .warning, detail: "Last run was interrupted"))
        } else if lastBackupAt != nil {
            checks.append(HealthCheckItem(id: "coverage", title: "Coverage", status: .good, detail: "Last backup completed"))
        }
        
        let overall = scores.overall
        let status: HealthStatus = overall >= 80 ? .good : (overall >= 50 ? .warning : .critical)
        
        return BackupHealthSnapshot(
            id: destination.id,
            overallScore: overall,
            status: status,
            scores: scores,
            checks: checks,
            destinationName: destination.name,
            destinationID: destination.id,
            lastBackupAt: lastBackupAt,
            filesProtected: filesProtected,
            backupSizeBytes: backupSizeBytes,
            warnings: warnings
        )
    }
    
    private func formatLastBackupAge(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 {
            let m = Int(interval / 60)
            return m <= 1 ? "Just now" : "\(m) minutes ago"
        }
        if interval < 86400 {
            let h = Int(interval / 3600)
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        }
        let d = Int(interval / 86400)
        return d == 1 ? "1 day ago" : "\(d) days ago"
    }
}
