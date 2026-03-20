//
//  SettingsView.swift
//  BackupVault
//
//  Simple settings with an advanced backup details section.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    
    var body: some View {
        Form {
            Section {
                Picker("Backup schedule", selection: $viewModel.schedule.type) {
                    ForEach(BackupScheduleType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.radioGroup)
                .controlSize(.large)

                if viewModel.schedule.type == .daily {
                    DatePicker("Daily at", selection: $viewModel.schedule.dailyTime, displayedComponents: .hourAndMinute)
                        .controlSize(.large)
                }
            } header: {
                Text("Schedule")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            
            Section {
                Toggle("Verify backups with SHA256", isOn: $viewModel.verifyWithChecksum)
                    .font(.system(size: 16, weight: .medium))
                Text("This is slower, but it checks that copied files are intact.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Verification")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            
            Section {
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Backup Details")
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                        if viewModel.advancedBackupDetails.isEmpty {
                            Text("Detailed backup metrics will appear here after your first completed backup.")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.advancedBackupDetails) { detail in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(detail.destinationName)
                                        .font(.system(size: 17, weight: .semibold))
                                    detailRow("Files copied", formatCount(detail.copiedFiles))
                                    detailRow("Files hard linked", formatCount(detail.hardLinkedFiles))
                                    detailRow("Files skipped", formatCount(detail.skippedFiles))
                                    detailRow("Data transferred", ByteCountFormatter.string(fromByteCount: detail.transferredBytes, countStyle: .file))
                                    if let duration = detail.duration {
                                        detailRow("Backup duration", formatDuration(duration))
                                    }
                                    if detail.speedBytesPerSecond > 0 {
                                        detailRow("Transfer speed", ByteCountFormatter.string(fromByteCount: Int64(detail.speedBytesPerSecond), countStyle: .file) + "/s")
                                    }
                                }
                                .padding(.vertical, 4)
                                
                                if detail.id != viewModel.advancedBackupDetails.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            
            Section {
                Text("BackupVault keeps backups in BackupVault/ComputerName/Date. No cloud, no accounts.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            viewModel.reloadBackupDetails()
        }
    }
    
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.system(size: 15, weight: .medium))
    }
    
    private func formatCount(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        if minutes == 0 {
            return "\(remainingSeconds)s"
        }
        if minutes < 60 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
}
