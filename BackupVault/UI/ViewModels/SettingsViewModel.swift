//
//  SettingsViewModel.swift
//  BackupVault
//
//  MVVM: schedule and app settings.
//

import Foundation
import SwiftUI

struct AdvancedBackupDetail: Identifiable {
    let id: UUID
    let destinationName: String
    let copiedFiles: Int
    let hardLinkedFiles: Int
    let skippedFiles: Int
    let transferredBytes: Int64
    let duration: TimeInterval?
    let speedBytesPerSecond: Double
    let completedAt: Date?
}

@MainActor
final class SettingsViewModel: ObservableObject {
    
    @Published var schedule: BackupSchedule {
        didSet {
            ScheduleManager.shared.schedule = schedule
        }
    }
    
    @Published var verifyWithChecksum: Bool {
        didSet { UserDefaults.standard.set(verifyWithChecksum, forKey: "BackupVault.verifyWithChecksum") }
    }
    
    @Published var advancedBackupDetails: [AdvancedBackupDetail] = []
    
    init() {
        schedule = ScheduleManager.shared.schedule
        verifyWithChecksum = UserDefaults.standard.bool(forKey: "BackupVault.verifyWithChecksum")
        reloadBackupDetails()
    }
    
    func reloadBackupDetails() {
        let destinations = DestinationStore.shared.loadDestinations()
        let runs = DestinationStore.shared.loadBackupRuns()
            .filter { $0.state == .completed }
        
        advancedBackupDetails = destinations.compactMap { destination in
            guard let run = runs
                .filter({ $0.destinationID == destination.id })
                .max(by: { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) }) else {
                return nil
            }
            
            return AdvancedBackupDetail(
                id: destination.id,
                destinationName: destination.name,
                copiedFiles: run.totalFilesCopied,
                hardLinkedFiles: run.totalFilesHardLinked,
                skippedFiles: run.totalFilesSkipped,
                transferredBytes: run.totalBytesCopied,
                duration: run.durationSeconds,
                speedBytesPerSecond: run.transferSpeedBytesPerSecond,
                completedAt: run.completedAt
            )
        }
        .sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }
}
