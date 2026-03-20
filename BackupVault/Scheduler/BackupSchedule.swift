//
//  BackupSchedule.swift
//  BackupVault
//
//  Schedule type: manual, daily, or when drive connected.
//

import Foundation

enum BackupScheduleType: String, Codable, CaseIterable {
    case manual = "Manual only"
    case daily = "Daily"
    case whenDriveConnected = "When drive connected"
}

struct BackupSchedule: Codable {
    var type: BackupScheduleType
    var dailyTime: Date  // Only used when type == .daily
}
