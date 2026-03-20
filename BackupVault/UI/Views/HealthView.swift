//
//  HealthView.swift
//  BackupVault
//
//  Health view delegates to DashboardView (same content, consistent with spec).
//

import SwiftUI

struct HealthView: View {
    @StateObject private var backupViewModel = BackupViewModel()

    var body: some View {
        DashboardView(backupViewModel: backupViewModel)
    }
}
