//
//  DashboardView.swift
//  BackupVault
//
//  Dashboard layout:
//  1. Hero with summary metrics and embedded actions
//  2. Actionable warning banners
//  3. Rebalanced cards with stronger NAS destination details
//

import SwiftUI

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = DashboardViewModel()
    @ObservedObject var backupViewModel: BackupViewModel
    var onConfigureBackup: (() -> Void)? = nil

    @AppStorage("BackupVault.dashboardVerificationBannerDismissed")
    private var verificationBannerDismissed = false
    @AppStorage("BackupVault.dashboardVerificationBannerRemindAfter")
    private var verificationBannerRemindAfter = 0.0

    @State private var showSuccessBurst = false
    @State private var ringPulse = false
    @State private var showMoreDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isRefreshing {
                    loadingState
                } else if let snapshot = currentSnapshot {
                    let selectedDestination = viewModel.destinations.first(where: { $0.id == snapshot.destinationID })
                    let issues = dashboardWarnings(snapshot)
                    pageHeader
                    if viewModel.destinations.count > 1 { destinationPicker }
                    healthHero(snapshot, destination: selectedDestination, warnings: issues)
                    statGrid(snapshot: snapshot, destination: selectedDestination)
                } else {
                    emptyState
                }
            }
            .padding(28)
            .padding(.bottom, 16)
            .frame(maxWidth: 1360, alignment: .leading)
        }
        .frame(minWidth: 760)
        .background(canvasBackground)
        .overlay(successBurstOverlay)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .onAppear {
            backupViewModel.loadState()
            Task {
                await viewModel.refresh(showLoading: viewModel.snapshots.isEmpty)
                syncDashboardSelectionFromBackupModel()
                if let score = viewModel.primarySnapshot.map({ Int($0.overallScore) }) {
                    MenuBarController.shared.updateHealthScore(score)
                }
            }
        }
        .onChange(of: backupViewModel.selectedDestination?.id) { newID in
            guard viewModel.selectedDestinationID != newID else { return }
            viewModel.selectedDestinationID = newID
        }
        .onChange(of: viewModel.selectedDestinationID) { newID in
            syncBackupSelectionFromDashboard(newID)
        }
        .onChange(of: backupViewModel.destinations.map { $0.id }) { _ in
            Task {
                await viewModel.refresh(showLoading: false)
                syncDashboardSelectionFromBackupModel()
            }
        }
        .onChange(of: backupViewModel.isBackingUp) { isRunning in
            if !isRunning {
                Task {
                    await viewModel.refresh(showLoading: false)
                    syncDashboardSelectionFromBackupModel()
                    if let score = viewModel.primarySnapshot.map({ Int($0.overallScore) }) {
                        MenuBarController.shared.updateHealthScore(score)
                        if score >= 100 && !backupViewModel.isBackingUp {
                            withAnimation(.spring(response: 0.5)) { showSuccessBurst = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                withAnimation(.easeOut(duration: 0.4)) { showSuccessBurst = false }
                            }
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refresh(showLoading: false)
            syncDashboardSelectionFromBackupModel()
            if let score = viewModel.primarySnapshot.map({ Int($0.overallScore) }) {
                MenuBarController.shared.updateHealthScore(score)
            }
        }
    }

    private var currentSnapshot: BackupHealthSnapshot? {
        let activeID = backupViewModel.selectedDestination?.id ?? viewModel.selectedDestinationID
        if let activeID {
            return viewModel.snapshots.first { $0.destinationID == activeID }
        }
        return viewModel.snapshots.first
    }

    private func syncDashboardSelectionFromBackupModel() {
        viewModel.selectedDestinationID = backupViewModel.selectedDestination?.id
    }

    private func syncBackupSelectionFromDashboard(_ destinationID: UUID?) {
        guard let destinationID,
              backupViewModel.selectedDestination?.id != destinationID,
              let destination = backupViewModel.destinations.first(where: { $0.id == destinationID }) else {
            return
        }
        backupViewModel.selectedDestination = destination
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Dashboard")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Your file protection at a glance")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var destinationPicker: some View {
        Picker("Backup destination", selection: selectedDestinationBinding) {
            ForEach(viewModel.snapshots) { item in
                Text(item.destinationName).tag(item.destinationID as UUID?)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 240)
        .controlSize(.large)
    }

    private var selectedDestinationBinding: Binding<UUID?> {
        Binding(
            get: {
                backupViewModel.selectedDestination?.id ?? viewModel.selectedDestinationID
            },
            set: { newID in
                viewModel.selectedDestinationID = newID
                syncBackupSelectionFromDashboard(newID)
            }
        )
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView().scaleEffect(0.85)
            Text("Checking your backup status…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(cardSurface)
    }

    private func healthHero(
        _ snapshot: BackupHealthSnapshot,
        destination: BackupDestination?,
        warnings: [String]
    ) -> some View {
        let score = min(100, max(0, snapshot.overallScore))
        let isRunning = backupViewModel.isBackingUp
        let progress = backupViewModel.progress
        let displayFraction: Double = isRunning
            ? (progress?.filesToCopy ?? 0 > 0
               ? Double(progress?.filesCopied ?? 0) / Double(progress?.filesToCopy ?? 1)
               : 0.0)
            : score / 100.0
        let color = isRunning
            ? Color(red: 0.28, green: 0.50, blue: 1.0)
            : scoreColor(snapshot.status)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.09), lineWidth: 14)
                        .frame(width: 96, height: 96)

                    Circle()
                        .trim(from: 0, to: displayFraction)
                        .stroke(
                            LinearGradient(
                                colors: [color, color.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .frame(width: 96, height: 96)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.4), value: displayFraction)

                    if isRunning {
                        Circle()
                            .stroke(color.opacity(ringPulse ? 0.25 : 0), lineWidth: 6)
                            .frame(width: 112, height: 112)
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: ringPulse)
                            .onAppear { ringPulse = true }
                            .onDisappear { ringPulse = false }
                    }

                    VStack(spacing: 1) {
                        if isRunning {
                            Text("\(Int(displayFraction * 100))%")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(color)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.3), value: displayFraction)
                        } else {
                            Text("\(Int(round(score)))")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(color)
                            Text("/ 100")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    if isRunning {
                        Text(backupPhaseLabel(progress?.phase))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(color.opacity(0.14)))
                        Text(progress?.currentFile != nil ? "Copying files…" : "Preparing backup…")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                        Text(progressSummary(progress))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(statusTitle(for: snapshot.status))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(color.opacity(0.14)))
                        Text(statusMessage(for: snapshot.status))
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(heroSupportLine(snapshot: snapshot, destination: destination))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        if isRunning {
                            Button {
                                backupViewModel.cancelBackup()
                            } label: {
                                Label("Stop Backup", systemImage: "stop.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button {
                                backupViewModel.lastCompletedSnapshotURL = nil
                                backupViewModel.startBackup()
                            } label: {
                                Label("Run Backup", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!backupViewModel.canStartBackup)
                        }

                        if let onConfigureBackup {
                            Button("Review Setup") { onConfigureBackup() }
                                .controlSize(.large)
                        }

                        if !isRunning, backupViewModel.selectedDestination != nil {
                            Button {
                                backupViewModel.openSelectedDestinationFolder()
                            } label: {
                                Label("View Backups", systemImage: "folder")
                            }
                            .controlSize(.large)
                        }
                    }

                    if let warning = warnings.first {
                        compactHeroWarning(warning)
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
        }
        .padding(20)
        .background(cardSurface)
        .animation(.easeInOut(duration: 0.35), value: isRunning)
    }

    private func backupPhaseLabel(_ phase: BackupPhase?) -> String {
        switch phase {
        case .scanning:             return "⟳ SCANNING"
        case .copying:              return "↑ COPYING"
        case .verifying:            return "✓ VERIFYING"
        case .resolvingDestination: return "⟳ CONNECTING"
        default:                    return "● RUNNING"
        }
    }

    @ViewBuilder
    private var successBurstOverlay: some View {
        if showSuccessBurst {
            ZStack {
                ForEach(0..<12) { i in
                    Circle()
                        .fill(Color(red: 0.17, green: 0.73, blue: 0.51).opacity(0.7))
                        .frame(width: 8, height: 8)
                        .offset(y: -80)
                        .rotationEffect(.degrees(Double(i) * 30))
                        .scaleEffect(showSuccessBurst ? 1 : 0)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.6)
                                .delay(Double(i) * 0.04),
                            value: showSuccessBurst
                        )
                }

                Circle()
                    .fill(Color(red: 0.17, green: 0.73, blue: 0.51).opacity(0.15))
                    .frame(width: 200, height: 200)
                    .scaleEffect(showSuccessBurst ? 1 : 0.2)
                    .opacity(showSuccessBurst ? 1 : 0)
                    .animation(.spring(response: 0.4), value: showSuccessBurst)

                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Color(red: 0.17, green: 0.73, blue: 0.51))
                    Text("Backup Complete!")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.17, green: 0.73, blue: 0.51))
                }
                .scaleEffect(showSuccessBurst ? 1 : 0.6)
                .opacity(showSuccessBurst ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.1), value: showSuccessBurst)
            }
            .allowsHitTesting(false)
        }
    }

    private func statGrid(snapshot: BackupHealthSnapshot, destination: BackupDestination?) -> some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    destinationActivityCard(destination, snapshot: snapshot)
                    protectionDetailsCard(snapshot)
                }

                VStack(spacing: 14) {
                    destinationActivityCard(destination, snapshot: snapshot)
                    protectionDetailsCard(snapshot)
                }
            }

            ViewThatFits(in: .horizontal) {
                detailsDisclosure(snapshot: snapshot, destination: destination)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func destinationCard(_ destination: BackupDestination?, snapshot: BackupHealthSnapshot) -> some View {
        let volumeInfo = destination.flatMap {
            $0.type == .externalDrive ? DiskSpaceMonitor.volumeInfo(for: $0.path, connectionLabel: "External drive") : nil
        }
        let accent = Color(red: 0.97, green: 0.50, blue: 0.15)
        let reachabilityGood = snapshot.scores.reachability >= 80
        let reachabilityColor: Color = reachabilityGood ? Color(red: 0.17, green: 0.73, blue: 0.51) : .orange

        return VStack(alignment: .leading, spacing: 12) {
            cardLabel(title: "Destination", symbol: "externaldrive.fill", accent: accent)
            Text(destinationHeadline(destination, snapshot: snapshot))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let destination, destination.type == .nas {
                HStack(spacing: 8) {
                    detailPill(
                        text: destination.nasHost ?? destination.name,
                        symbol: "network",
                        tint: accent
                    )
                    if let share = destination.nasShare, !share.isEmpty {
                        detailPill(
                            text: share,
                            symbol: "folder.fill",
                            tint: accent
                        )
                    }
                    detailPill(
                        text: reachabilityGood ? "Reachable" : "Needs reconnect",
                        symbol: reachabilityGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: reachabilityColor
                    )
                }
                Text(snapshot.backupSizeBytes > 0
                     ? "Last snapshot size: \(ByteCountFormatter.string(fromByteCount: snapshot.backupSizeBytes, countStyle: .file))"
                     : "No snapshot yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                HStack(spacing: 4) {
                    Text("\(volumeInfo?.freeFormatted ?? "—") free")
                        .font(.system(size: 13, weight: .semibold))
                    Text("·").foregroundStyle(.tertiary)
                    Text(volumeInfo?.connectionType ?? "External drive")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if volumeInfo == nil {
                    Text(destinationSubheadline(destination, snapshot: snapshot))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
        .padding(18)
        .background(cardSurface)
    }

    private func destinationActivityCard(_ destination: BackupDestination?, snapshot: BackupHealthSnapshot) -> some View {
        let accent = Color(red: 0.97, green: 0.50, blue: 0.15)
        let reachabilityGood = snapshot.scores.reachability >= 80
        let reachabilityColor: Color = reachabilityGood ? Color(red: 0.17, green: 0.73, blue: 0.51) : .orange
        let volumeInfo = destination.flatMap {
            $0.type == .externalDrive ? DiskSpaceMonitor.volumeInfo(for: $0.path, connectionLabel: "External drive") : nil
        }

        return VStack(alignment: .leading, spacing: 16) {
            cardLabel(title: "Destination & Activity", symbol: "externaldrive.fill.badge.checkmark", accent: accent)

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(destinationHeadline(destination, snapshot: snapshot))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .lineLimit(1)

                    if let destination, destination.type == .nas {
                        detailPill(
                            text: reachabilityGood ? "Ready" : "Needs reconnect",
                            symbol: reachabilityGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            tint: reachabilityColor
                        )
                        if !reachabilityGood {
                            Text("Reconnect the NAS to continue.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text("\(volumeInfo?.freeFormatted ?? "—") free")
                                .font(.system(size: 13, weight: .semibold))
                            Text("·").foregroundStyle(.tertiary)
                            Text(volumeInfo?.connectionType ?? "External drive")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if volumeInfo == nil {
                            Text(destinationSubheadline(destination, snapshot: snapshot))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    activityHighlight(
                        title: "Last backup",
                        value: snapshot.lastBackupAt.map(formatBackupTimestamp) ?? "Not yet",
                        detail: snapshot.lastBackupAt.map(formatRelativeDate) ?? "Run your first backup",
                        accent: Color(red: 0.28, green: 0.50, blue: 1.0)
                    )

                    HStack(spacing: 10) {
                        activityMiniMetric(
                            title: "Files",
                            value: formatCount(snapshot.filesProtected),
                            detail: snapshot.filesProtected > 0 ? "Included" : "No files yet"
                        )
                        activityMiniMetric(
                            title: "Size",
                            value: snapshot.backupSizeBytes > 0
                                ? ByteCountFormatter.string(fromByteCount: snapshot.backupSizeBytes, countStyle: .file)
                                : "—",
                            detail: snapshot.backupSizeBytes > 0 ? "Latest snapshot" : "No snapshot yet"
                        )
                    }
                }
                .frame(width: 320, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                        )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardSurface)
    }

    private func verificationCard(_ snapshot: BackupHealthSnapshot) -> some View {
        let latestRun = viewModel.latestVerifiedRun(for: snapshot.destinationID)
        let isVerified = snapshot.scores.integrity >= 80
        let accent: Color = isVerified ? Color(red: 0.17, green: 0.73, blue: 0.51) : .orange

        return VStack(alignment: .leading, spacing: 10) {
            cardLabel(
                title: "Verification",
                symbol: isVerified ? "checkmark.shield.fill" : "shield.slash.fill",
                accent: accent
            )

            if isVerified {
                Text("Files verified ✓")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                Text(latestRun?.verifiedAt.map { "Last checked \(formatRelativeDate($0))" } ?? "Integrity is up to date.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Not yet verified")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                Text("Confirm all files copied correctly.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Button {
                    backupViewModel.startBackupWithVerification()
                } label: {
                    Label("Run Verification", systemImage: "checkmark.shield")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .padding(.top, 2)
                .disabled(backupViewModel.isBackingUp)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
        .padding(18)
        .background(cardSurface)
    }

    private func protectionDetailsCard(_ snapshot: BackupHealthSnapshot) -> some View {
        let latestRun = viewModel.latestVerifiedRun(for: snapshot.destinationID)
        let isVerified = snapshot.scores.integrity >= 80
        let verificationAccent: Color = isVerified ? Color(red: 0.17, green: 0.73, blue: 0.51) : .orange

        return VStack(alignment: .leading, spacing: 14) {
            cardLabel(title: "Protection Details", symbol: "waveform.path.ecg", accent: scoreColor(snapshot.status))

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isVerified ? "Files verified ✓" : "Verification needed")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(verificationAccent)
                    Text(latestRun?.verifiedAt.map { "Checked \(formatRelativeCompact($0))" } ?? "Run a verification check")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !isVerified {
                    Button {
                        backupViewModel.startBackupWithVerification()
                    } label: {
                        Label("Verify", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                    .disabled(backupViewModel.isBackingUp)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 140), spacing: 10),
                    GridItem(.flexible(minimum: 140), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                scoreTile(title: "Freshness", score: snapshot.scores.freshness, tint: Color(red: 0.28, green: 0.50, blue: 1.0))
                scoreTile(title: "Storage", score: snapshot.scores.storage, tint: .orange)
                scoreTile(title: "Integrity", score: snapshot.scores.integrity, tint: Color(red: 0.17, green: 0.73, blue: 0.51))
                scoreTile(title: "Reachability", score: snapshot.scores.reachability, tint: Color(red: 0.62, green: 0.35, blue: 0.95))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardSurface)
    }

    private func detailsDisclosure(snapshot: BackupHealthSnapshot, destination: BackupDestination?) -> some View {
        DisclosureGroup(isExpanded: $showMoreDetails) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        detailLine("Destination path", destination?.path.path ?? snapshot.destinationName)
                        if let host = destination?.nasHost {
                            detailLine("Host", host)
                        }
                        if let share = destination?.nasShare {
                            detailLine("Share", share)
                        }
                        if let username = destination?.nasUsername {
                            detailLine("User", username)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        detailLine("Freshness", "\(Int(round(snapshot.scores.freshness)))%")
                        detailLine("Storage", "\(Int(round(snapshot.scores.storage)))%")
                        detailLine("Integrity", "\(Int(round(snapshot.scores.integrity)))%")
                        detailLine("Reachability", "\(Int(round(snapshot.scores.reachability)))%")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 10) {
                    detailLine("Destination path", destination?.path.path ?? snapshot.destinationName)
                    if let host = destination?.nasHost {
                        detailLine("Host", host)
                    }
                    if let share = destination?.nasShare {
                        detailLine("Share", share)
                    }
                    if let username = destination?.nasUsername {
                        detailLine("User", username)
                    }
                    detailLine("Freshness", "\(Int(round(snapshot.scores.freshness)))%")
                    detailLine("Storage", "\(Int(round(snapshot.scores.storage)))%")
                    detailLine("Integrity", "\(Int(round(snapshot.scores.integrity)))%")
                    detailLine("Reachability", "\(Int(round(snapshot.scores.reachability)))%")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 14)
        } label: {
            HStack {
                Text("More details")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(showMoreDetails ? "Hide" : "Show")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(cardSurface)
    }

    private var verificationBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Verification recommended")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Run a quick check to confirm your files were copied correctly.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button("Later") {
                    verificationBannerRemindAfter = Date().addingTimeInterval(86400).timeIntervalSince1970
                }
                .controlSize(.small)
                Button("Run Check") {
                    verificationBannerDismissed = false
                    verificationBannerRemindAfter = 0
                    backupViewModel.startBackupWithVerification()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.28, green: 0.50, blue: 1.0).opacity(0.08))
                    .frame(width: 88, height: 88)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color(red: 0.28, green: 0.50, blue: 1.0).opacity(0.5))
            }
            VStack(spacing: 6) {
                Text("No backup destination yet")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text("Configure your backup to start protecting your files.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let onConfigureBackup {
                Button("Configure Backup") { onConfigureBackup() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(52)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if backupViewModel.isBackingUp, let progress = backupViewModel.progress {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.72).controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(progress.currentFile ?? "Backing up your files…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if progress.filesToCopy > 0 {
                            Text("\(progress.filesCopied) of \(progress.filesToCopy) files")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else if let errorMessage = backupViewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 13))
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            if backupViewModel.isBackingUp == false,
               backupViewModel.errorMessage != nil {
                Button {
                    backupViewModel.clearError()
                } label: {
                    Text("Dismiss")
                }
                .controlSize(.large)
            }

            if backupViewModel.isBackingUp,
               backupViewModel.selectedDestination != nil {
                Button {
                    backupViewModel.openSelectedDestinationFolder()
                } label: {
                    Label("View Backups", systemImage: "folder")
                }
                .controlSize(.large)
            }

            if backupViewModel.isBackingUp {
                Button {
                    backupViewModel.cancelBackup()
                } label: {
                    Label("Stop Backup", systemImage: "stop.fill").frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            ZStack(alignment: .top) {
                Color(nsColor: .windowBackgroundColor).opacity(0.97).background(.ultraThinMaterial)
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            }
        )
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(cardFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.05 : 0.075), radius: colorScheme == .dark ? 4 : 14, y: colorScheme == .dark ? 2 : 8)
    }

    private var canvasBackground: Color {
        if colorScheme == .dark {
            return Color(nsColor: .windowBackgroundColor)
        }
        return Color(red: 0.965, green: 0.968, blue: 0.975)
    }

    private var cardFillColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: .controlBackgroundColor)
        }
        return Color.white.opacity(0.92)
    }

    private func cardLabel(title: String, symbol: String, accent: Color) -> some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent.opacity(0.13))
                    .frame(width: 26, height: 26)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    private func compactHeroWarning(_ warning: String) -> some View {
        let content = warningPresentation(for: warning)

        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(content.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let detail = content.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func activityHighlight(title: String, value: String, detail: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accent.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func activityMiniMetric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func heroSummaryTile(title: String, value: String, detail: String, symbol: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.45)
            }
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accent.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func heroWarningTile(_ warning: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Needs Attention")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.45)
            }

            Text("Review destination")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(warning)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let onConfigureBackup {
                Button(issuesBannerActionTitle(for: [warning])) {
                    onConfigureBackup()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private func detailPill(text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.11)))
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private func recentActivityCard(_ snapshot: BackupHealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            cardLabel(title: "Recent Activity", symbol: "clock.arrow.circlepath", accent: Color(red: 0.28, green: 0.50, blue: 1.0))
            HStack(alignment: .top, spacing: 18) {
                metricColumn(
                    title: "Last backup",
                    value: snapshot.lastBackupAt.map(formatBackupTimestamp) ?? "Not yet",
                    detail: snapshot.lastBackupAt.map(formatRelativeDate) ?? "Run your first backup"
                )
                metricColumn(
                    title: "Files protected",
                    value: formatCount(snapshot.filesProtected),
                    detail: snapshot.filesProtected > 0 ? "Included in last backup" : "No files protected yet"
                )
                metricColumn(
                    title: "Backup size",
                    value: snapshot.backupSizeBytes > 0
                        ? ByteCountFormatter.string(fromByteCount: snapshot.backupSizeBytes, countStyle: .file)
                        : "—",
                    detail: snapshot.backupSizeBytes > 0 ? "Stored in the latest snapshot" : "No snapshot stored yet"
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
        .padding(18)
        .background(cardSurface)
    }

    private func healthBreakdownCard(_ snapshot: BackupHealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            cardLabel(title: "Protection Details", symbol: "waveform.path.ecg", accent: scoreColor(snapshot.status))
            breakdownRow(title: "Freshness", score: snapshot.scores.freshness, tint: Color(red: 0.28, green: 0.50, blue: 1.0))
            breakdownRow(title: "Storage", score: snapshot.scores.storage, tint: .orange)
            breakdownRow(title: "Integrity", score: snapshot.scores.integrity, tint: Color(red: 0.17, green: 0.73, blue: 0.51))
            breakdownRow(title: "Reachability", score: snapshot.scores.reachability, tint: Color(red: 0.62, green: 0.35, blue: 0.95))
        }
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
        .padding(18)
        .background(cardSurface)
    }

    private func metricColumn(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func breakdownRow(title: String, score: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Int(round(score)))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            }
            GeometryReader { proxy in
                let railWidth = min(proxy.size.width, 176.0)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, railWidth * CGFloat(min(max(score, 0), 100) / 100)))
                }
                .frame(width: railWidth, alignment: .leading)
            }
            .frame(height: 6)
        }
    }

    private func scoreTile(title: String, score: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Int(round(score)))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
            GeometryReader { proxy in
                let railWidth = min(proxy.size.width, 168.0)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.72)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, railWidth * CGFloat(min(max(score, 0), 100) / 100)))
                }
                .frame(width: railWidth, alignment: .leading)
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func shouldShowVerificationBanner(_ snapshot: BackupHealthSnapshot) -> Bool {
        guard snapshot.scores.integrity < 80 else { return false }
        if verificationBannerDismissed { return false }
        return Date(timeIntervalSince1970: verificationBannerRemindAfter) <= Date()
    }

    private func dashboardWarnings(_ snapshot: BackupHealthSnapshot) -> [String] {
        var warnings = nonVerificationWarnings(snapshot)
        if shouldShowVerificationBanner(snapshot) {
            warnings.append("Verification recommended")
        }
        return warnings
    }

    private func nonVerificationWarnings(_ snapshot: BackupHealthSnapshot) -> [String] {
        snapshot.warnings.filter { warning in
            !warning.lowercased().contains("verification") &&
            !warning.lowercased().contains("verified") &&
            !isStorageCapacityWarning(warning)
        }
    }

    private func isStorageCapacityWarning(_ warning: String) -> Bool {
        let text = warning.lowercased()
        return (text.contains("full") || text.contains("free")) &&
            (text.contains("drive") || text.contains("destination") || text.contains("storage"))
    }

    private func statusTitle(for status: HealthStatus) -> String {
        switch status {
        case .good: return "● PROTECTED"
        case .warning: return "⚠ ATTENTION"
        case .critical: return "✕ AT RISK"
        }
    }

    private func statusMessage(for status: HealthStatus) -> String {
        switch status {
        case .good: return "Your files are protected."
        case .warning: return "Your backup is available, but needs review."
        case .critical: return "Take action to keep your files protected."
        }
    }

    private func scoreColor(_ status: HealthStatus) -> Color {
        switch status {
        case .good: return Color(red: 0.17, green: 0.73, blue: 0.51)
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func progressSummary(_ progress: BackupProgress?) -> String {
        guard let progress else { return "Preparing your backup." }
        if progress.filesToCopy > 0 {
            return "\(progress.filesCopied) of \(progress.filesToCopy) files copied"
        }
        return progress.currentFile ?? "Preparing your backup."
    }

    private func heroSupportLine(snapshot: BackupHealthSnapshot, destination: BackupDestination?) -> String {
        let lastBackup = snapshot.lastBackupAt.map(formatRelativeCompact) ?? "No backup yet"
        return "\(lastBackup) • \(destinationSubheadline(destination, snapshot: snapshot))"
    }

    private func destinationHeadline(_ destination: BackupDestination?, snapshot: BackupHealthSnapshot) -> String {
        destination?.name ?? snapshot.destinationName
    }

    private func destinationSubheadline(_ destination: BackupDestination?, snapshot: BackupHealthSnapshot) -> String {
        if let destination, destination.type == .nas {
            let host = nasHostLabel(destination)
            let share = (destination.nasShare?.isEmpty == false ? destination.nasShare! : "Network share")
            return "\(host) · \(share)"
        }
        return snapshot.scores.reachability >= 80 ? "Drive connected" : "Reconnect drive to back up"
    }

    private func nasHostLabel(_ destination: BackupDestination) -> String {
        let raw = (destination.nasHost?.isEmpty == false ? destination.nasHost! : destination.name)
        if raw.lowercased().hasSuffix(".local") {
            return String(raw.dropLast(6))
        }
        return raw
    }

    private func warningPresentation(for warning: String) -> (title: String, detail: String?) {
        if let open = warning.firstIndex(of: "("), let close = warning.lastIndex(of: ")"), open < close {
            let title = warning[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = warning[warning.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, detail.isEmpty ? nil : detail)
        }
        return (warning, nil)
    }

    private func verificationDetailText(_ snapshot: BackupHealthSnapshot) -> String {
        if let verifiedAt = viewModel.latestVerifiedRun(for: snapshot.destinationID)?.verifiedAt {
            return "Checked \(formatRelativeCompact(verifiedAt))"
        }
        return snapshot.scores.integrity >= 80 ? "Integrity looks current" : "Run a verification check"
    }

    private func issuesBannerActionTitle(for warnings: [String]) -> String {
        let first = warnings.first?.lowercased() ?? ""
        if first.contains("full") || first.contains("space") {
            return "Review Destination"
        }
        if first.contains("reach") || first.contains("connect") || first.contains("unavailable") {
            return "Check Backup Setup"
        }
        return "Review Setup"
    }

    private func formatBackupTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday at' h:mm a"
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

    private func formatRelativeCompact(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatCount(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}
