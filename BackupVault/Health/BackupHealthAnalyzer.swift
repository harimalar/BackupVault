//
//  BackupHealthAnalyzer.swift
//  BackupVault
//
//  Analyzes backup health and returns a score (0–100) and component breakdown.
//

import Foundation

/// Production health analyzer: delegates to HealthEngine and returns BackupHealthSnapshot.
final class BackupHealthAnalyzer {
    
    private let engine = HealthEngine()
    
    /// Compute health for a destination (optionally with resolved path if already mounted).
    func analyze(destination: BackupDestination, resolvedPath: URL? = nil) async -> BackupHealthSnapshot {
        await engine.computeHealth(destination: destination, resolvedPath: resolvedPath)
    }
    
    /// Overall score (0–100) for the given snapshot.
    func overallScore(from snapshot: BackupHealthSnapshot) -> Double {
        snapshot.overallScore
    }
}
