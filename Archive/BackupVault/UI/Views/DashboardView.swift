//
//  DashboardView.swift
//  BackupVault
//
//  Backup status dashboard with fixed primary actions.
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @ObservedObject var backupViewModel: BackupViewModel
    var onConfigureBackup: (() -> Void)? = nil

    @AppStorage("BackupVault.dashboardVerificationBannerDismissed")
    private var verificationBannerDismissed = false
    @AppStorage("BackupVault.dashboardVerificationBannerRemindAfter")
    private var verificationBannerRemindAfter = 0.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isRefreshing {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.85)
                        Text("Checking your backup status…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .background(tileBackground)
                } else if let snapshot = viewModel.primarySnapshot {
                    let selectedDestination = viewModel.destinations.first(where: { $0.id == snapshot.destinationID })
                    dashboardHeader
                    if viewModel.snapshots.count > 1 {
                        destinationPicker
                    }
                    if shouldShowVerificationBanner(snapshot) {
                        verificationBanner
                    } else if !snapshot.warnings.isEmpty {
                        issuesBanner(snapshot.warnings)
                    }
                    healthHero(snapshot)
                    tileGrid(snapshot: snapshot, destination: selectedDestination)
                } else {
                    emptyState
                }
            }
            .padding(24)
            .padding(.bottom, 12)
        }
        .frame(minWidth: 520)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            dashboardActionBar
        }
        .onAppear {
            backupViewModel.loadState()
            Task { await viewModel.refresh() }
        }
        .refreshable { await viewModel.refresh() }
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Backup Status")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("A quick view of how well your files are protected.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var destinationPicker: some View {
        Picker("Backup destination", selection: $viewModel.selectedDestinationID) {
            ForEach(viewModel.snapshots) { item in
                Text(item.destinationName).tag(item.destinationID as UUID?)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 220)
        .controlSize(.large)
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )
    }

    private func healthHero(_ snapshot: BackupHealthSnapshot) -> some View {
        let score = min(100, max(0, snapshot.overallScore))
        let fraction = score / 100.0
        return HStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 12)
                    .frame(width: 116, height: 116)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(scoreColor(snapshot.status), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 116, height: 116)
                    .rotationEffect(.degrees(-90))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(statusTitle(for: snapshot.status))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(snapshot.status))
                Text(statusMessage(for: snapshot.status))
                    .font(.system(size: 20, weight: .semibold))
                Text("\(Int(round(score)))% overall health")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(22)
        .background(tileBackground)
    }

    private func tileGrid(snapshot: BackupHealthSnapshot, destination: BackupDestination?) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                summaryTile(
                    title: "Last Backup",
                    primary: snapshot.lastBackupAt.map(formatBackupTimestamp) ?? "Not yet",
                    secondary: snapshot.lastBackupAt.map(formatRelativeDate) ?? "Run your first backup to get started",
                    symbol: "clock.fill"
                )
                summaryTile(
                    title: "Files Protected",
                    primary: formatCount(snapshot.filesProtected),
                    secondary: snapshot.filesProtected > 0 ? "Included in the most recent backup" : "No files protected yet",
                    symbol: "doc.on.doc.fill"
                )
            }

            HStack(alignment: .top, spacing: 14) {
                destinationTile(destination, snapshot: snapshot)
                verificationTile(snapshot)
            }
        }
    }

    private func summaryTile(title: String, primary: String, secondary: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            tileHeader(title: title, symbol: symbol)
            Text(primary)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .lineLimit(2)
            Text(secondary)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 134, alignment: .leading)
        .padding(18)
        .background(tileBackground)
    }

    private func destinationTile(_ destination: BackupDestination?, snapshot: BackupHealthSnapshot) -> some View {
        let volumeInfo = destination.flatMap {
            $0.type == .externalDrive ? DiskSpaceMonitor.volumeInfo(for: $0.path, connectionLabel: "External drive") : nil
        }
        let title = volumeInfo?.name ?? snapshot.destinationName
        let freeSpace = volumeInfo?.freeFormatted ?? "—"
        let destinationType = destination?.type == .nas ? "Network location" : "External drive"

        return VStack(alignment: .leading, spacing: 8) {
            tileHeader(title: "Destination", symbol: "externaldrive.fill")
            Text(title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("\(freeSpace) free")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            Text(destinationType)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 134, alignment: .leading)
        .padding(18)
        .background(tileBackground)
    }

    private func verificationTile(_ snapshot: BackupHealthSnapshot) -> some View {
        let latestRun = viewModel.latestRun(for: snapshot.destinationID)
        let integrity = snapshot.scores.integrity
        let title: String
        let message: String
        let color: Color

        if integrity >= 80 {
            title = "Verified"
            message = latestRun?.verifiedAt.map { "Last verified \(formatRelativeDate($0))" } ?? "Verification is up to date."
            color = .green
        } else {
            title = verificationBannerDismissed ? "Verification needed" : "Verification recommended"
            message = latestRun?.verifiedAt.map { "Last verified \(formatRelativeDate($0))" } ?? "Run a full verification to ensure backup integrity."
            color = .orange
        }

        return VStack(alignment: .leading, spacing: 8) {
            tileHeader(title: "Verification", symbol: "checkmark.shield.fill")
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 134, alignment: .leading)
        .padding(18)
        .background(tileBackground)
    }

    private func tileHeader(title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var verificationBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Verification recommended", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Run a full verification to ensure backup integrity.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Run Verification") {
                    verificationBannerDismissed = false
                    verificationBannerRemindAfter = 0
                    backupViewModel.startBackupWithVerification()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Remind Later") {
                    verificationBannerDismissed = false
                    verificationBannerRemindAfter = Date().addingTimeInterval(60 * 60 * 24).timeIntervalSince1970
                }
                .controlSize(.large)

                Button("Dismiss") {
                    verificationBannerDismissed = true
                    verificationBannerRemindAfter = 0
                }
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }

    private func issuesBanner(_ warnings: [String]) -> some View {
        let copy = warningCopy(for: warnings)
        return VStack(alignment: .leading, spacing: 8) {
            Label(copy.title, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.orange)
            Text(copy.message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }

    private var dashboardActionBar: some View {
        HStack(spacing: 12) {
            if backupViewModel.isBackingUp, let progress = backupViewModel.progress {
                Text(progress.currentFile ?? "Backing up your files…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            } else if let errorMessage = backupViewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
            } else {
                Spacer()
            }

            if let onConfigureBackup {
                Button("Configure Backup") {
                    onConfigureBackup()
                }
                .controlSize(.large)
            }

            Button {
                backupViewModel.startBackup()
            } label: {
                Label(backupViewModel.isBackingUp ? "Running Backup…" : "Run Backup", systemImage: "play.fill")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!backupViewModel.canStartBackup)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            ZStack(alignment: .top) {
                Color(nsColor: .windowBackgroundColor).opacity(0.98)
                Divider()
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No backup destination yet")
                .font(.system(size: 21, weight: .semibold))
            Text("Configure your backup to start protecting your files.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let onConfigureBackup {
                Button("Configure Backup") {
                    onConfigureBackup()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func shouldShowVerificationBanner(_ snapshot: BackupHealthSnapshot) -> Bool {
        guard snapshot.scores.integrity < 80 else {
            return false
        }
        if verificationBannerDismissed {
            return false
        }
        let remindAfter = Date(timeIntervalSince1970: verificationBannerRemindAfter)
        return remindAfter <= Date()
    }

    private func statusTitle(for status: HealthStatus) -> String {
        switch status {
        case .good: return "SAFE"
        case .warning: return "CHECK"
        case .critical: return "AT RISK"
        }
    }

    private func statusMessage(for status: HealthStatus) -> String {
        switch status {
        case .good:
            return "Your files are protected."
        case .warning:
            return "Your backup is available, but one item should be reviewed."
        case .critical:
            return "Take action soon to keep your files protected."
        }
    }

    private func scoreColor(_ status: HealthStatus) -> Color {
        switch status {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func formatBackupTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "'Today' h:mm a"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday' h:mm a"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatCount(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func warningCopy(for warnings: [String]) -> (title: String, message: String) {
        (
            title: "Needs attention",
            message: warnings.first ?? "Something needs your attention."
        )
    }
}
