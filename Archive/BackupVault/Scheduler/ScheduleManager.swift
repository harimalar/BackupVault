//
//  ScheduleManager.swift
//  BackupVault
//
//  Persists schedule and runs daily timer; drive connection triggers are in VolumeObserver.
//

import Foundation
import AppKit

final class ScheduleManager: ObservableObject {
    static let shared = ScheduleManager()
    
    @Published var schedule: BackupSchedule {
        didSet { persist() }
    }
    
    private var dailyTimer: Timer?
    private let defaults = UserDefaults.standard
    private let key = "BackupVault.schedule"
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(BackupSchedule.self, from: data) {
            schedule = decoded
        } else {
            schedule = BackupSchedule(type: .manual, dailyTime: Calendar.current.date(from: DateComponents(hour: 2, minute: 0)) ?? Date())
        }
        applySchedule()
    }
    
    func applySchedule() {
        dailyTimer?.invalidate()
        dailyTimer = nil
        
        guard schedule.type == .daily else { return }
        
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        let timeComponents = cal.dateComponents([.hour, .minute], from: schedule.dailyTime)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        
        var next = cal.date(from: components) ?? Date()
        if next <= Date() {
            next = cal.date(byAdding: .day, value: 1, to: next) ?? next
        }
        
        let interval = next.timeIntervalSinceNow
        guard interval > 0 else { return }
        dailyTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            NotificationCenter.default.post(name: BackupScheduler.triggerNotificationName, object: nil)
            self?.applySchedule()
        }
        RunLoop.main.add(dailyTimer!, forMode: .common)
    }
    
    private func persist() {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        defaults.set(data, forKey: key)
        applySchedule()
    }
}

extension Notification.Name {
    static let backupVaultTriggerScheduledBackup = Notification.Name("BackupVault.triggerScheduledBackup")
}
