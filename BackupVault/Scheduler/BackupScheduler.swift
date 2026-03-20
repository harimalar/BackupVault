//
//  BackupScheduler.swift
//  BackupVault
//
//  Schedules backups: manual, daily, or when drive connected.
//

import Foundation

/// Scheduler facade: delegates to ScheduleManager and VolumeObserver.
enum BackupScheduler {
    
    static var schedule: BackupSchedule {
        get { ScheduleManager.shared.schedule }
        set { ScheduleManager.shared.schedule = newValue }
    }
    
    static func applySchedule() {
        ScheduleManager.shared.applySchedule()
    }
    
    /// Post this notification to trigger a scheduled backup (e.g. from daily timer or drive connection).
    static let triggerNotificationName = Notification.Name("BackupVault.triggerScheduledBackup")
}
