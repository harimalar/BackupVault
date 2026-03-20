//
//  ContentView.swift
//  BackupVault
//
//  Main window: sidebar (Backup, Restore, Settings) and detail.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .dashboard
    @StateObject private var volumeObserver = VolumeObserver.shared
    @StateObject private var backupViewModel = BackupViewModel()
    
    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                NavigationLink(value: item) {
                    HStack(spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(item.iconColor)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 22)
                        Text(item.title)
                            .font(.system(size: 16.5, weight: .medium))
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 42)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard:
                DashboardView(
                    backupViewModel: backupViewModel,
                    onConfigureBackup: { selection = .backup }
                )
            case .backup:
                BackupView(viewModel: backupViewModel)
            case .restore:
                RestoreView()
            case .settings:
                SettingsView()
            }
        }
        .alert("Backup drive connected", isPresented: $volumeObserver.showDriveConnectedAlert) {
            Button("Run Backup") {
                selection = .dashboard
                backupViewModel.startBackup()
                volumeObserver.clearDriveAlert()
            }
            Button("Later", role: .cancel) {
                volumeObserver.clearDriveAlert()
            }
        } message: {
            Text("A backup destination drive was detected. Start a backup now?")
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case backup = "Backup Setup"
    case restore = "Restore"
    case settings = "Settings"
    
    var id: String { rawValue }
    var title: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "shield.lefthalf.filled"
        case .backup: return "externaldrive.fill.badge.plus"
        case .restore: return "arrow.uturn.backward"
        case .settings: return "gearshape"
        }
    }
    /// Pro colorful icon tint per section.
    var iconColor: Color {
        switch self {
        case .dashboard: return Color.blue
        case .backup: return Color.orange
        case .restore: return Color.green
        case .settings: return Color.purple
        }
    }
}
