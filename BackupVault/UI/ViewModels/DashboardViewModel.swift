//
//  DashboardViewModel.swift
//  BackupVault
//
//  MVVM: loads health snapshots for dashboard.
//

import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    
    @Published var snapshots: [BackupHealthSnapshot] = []
    @Published var selectedDestinationID: UUID?
    @Published var isRefreshing = false
    @Published var recentRuns: [BackupRun] = []
    @Published var destinations: [BackupDestination] = []
    
    private let healthEngine = HealthEngine()
    
    func destinationName(for id: UUID) -> String {
        destinations.first { $0.id == id }?.name ?? "Destination"
    }

    func latestRun(for destinationID: UUID?) -> BackupRun? {
        guard let destinationID else { return recentRuns.first }
        return recentRuns.first { $0.destinationID == destinationID }
    }

    /// Most recent run with verifiedAt set — used for the verification card.
    func latestVerifiedRun(for destinationID: UUID?) -> BackupRun? {
        guard let destinationID else { return nil }
        return DestinationStore.shared.lastVerifiedRun(forDestinationID: destinationID)
    }
    
    var primarySnapshot: BackupHealthSnapshot? {
        if let id = selectedDestinationID {
            return snapshots.first { $0.destinationID == id }
        }
        return snapshots.first
    }
    
    func refresh(showLoading: Bool = true) async {
        if showLoading && snapshots.isEmpty {
            isRefreshing = true
        }
        defer { isRefreshing = false }
        
        let loadedDests = DestinationStore.shared.loadDestinations()
        var results: [BackupHealthSnapshot] = []
        for dest in loadedDests {
            let snapshot = await healthEngine.computeHealth(destination: dest, resolvedPath: nil)
            results.append(snapshot)
        }
        snapshots = results.sorted { $0.overallScore > $1.overallScore }
        destinations = loadedDests
        if selectedDestinationID == nil, let first = loadedDests.first {
            selectedDestinationID = first.id
        }
        recentRuns = Array(DestinationStore.shared.loadBackupRuns()
            .filter { $0.state == .completed }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
            .prefix(10))
    }
}
