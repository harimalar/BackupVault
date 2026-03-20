//
//  HealthView.swift
//  BackupVault
//
//  Backup health dashboard (spec: HealthView). Uses same content as Dashboard.
//

import SwiftUI

/// Health view: shows backup health score, statistics, and warnings.
/// Matches spec "HealthView"; content is the Dashboard.
struct HealthView: View {
    @StateObject private var backupViewModel = BackupViewModel()
    
    var body: some View {
        DashboardView(backupViewModel: backupViewModel)
    }
}
