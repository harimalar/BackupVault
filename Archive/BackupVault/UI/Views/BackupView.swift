//
//  BackupView.swift
//  BackupVault
//
//  Backup setup with fixed actions and compact cards.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct BackupView: View {
    @ObservedObject var viewModel: BackupViewModel
    @StateObject private var scheduleManager = ScheduleManager.shared
    @State private var showNASSheet = false
    @State private var nasHost = ""
    @State private var nasShare = ""
    @State private var nasUsername = ""
    @State private var nasPassword = ""
    @State private var nasName = ""
    @State private var newExcludedFolder = ""
    @State private var newExcludedPattern = ""
    @State private var showExclusions = false
    @State private var showSchedule = false
    @State private var showVerification = false
    @State private var saveFeedback: String?

    private let pageAccent = Color(red: 0.37, green: 0.62, blue: 0.98)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headerCard

                configurationSection(
                    title: "Folders",
                    subtitle: "Choose the folders BackupVault protects.",
                    symbol: "folder.badge.plus"
                ) {
                    folderSectionContent
                }

                configurationSection(
                    title: "Destination",
                    subtitle: "Pick where your snapshots are stored.",
                    symbol: "externaldrive.fill"
                ) {
                    destinationSectionContent
                }

                configurationSection(
                    title: "Estimate",
                    subtitle: "A quick view of what this backup will include.",
                    symbol: "chart.bar.xaxis"
                ) {
                    estimateSectionContent
                }

                configurationSection(
                    title: "Advanced Options",
                    subtitle: "Optional settings for exclusions, schedule, and verification.",
                    symbol: "slider.horizontal.3"
                ) {
                    advancedOptionsContent
                }
            }
            .padding(24)
            .padding(.bottom, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
        }
        .fileImporter(
            isPresented: $viewModel.showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    _ = url.startAccessingSecurityScopedResource()
                    viewModel.addFolder(url)
                }
            }
        }
        .onAppear {
            viewModel.loadState()
            viewModel.updateDestinationFreeSpace()
            viewModel.refreshEstimates()
        }
        .sheet(isPresented: $showNASSheet) {
            NASConfigSheet(
                host: $nasHost,
                share: $nasShare,
                username: $nasUsername,
                password: $nasPassword,
                name: $nasName,
                onSave: {
                    let destination = BackupDestination(
                        name: nasName.isEmpty ? "NAS \(nasHost)" : nasName,
                        type: .nas,
                        path: URL(string: "smb://\(nasHost)/\(nasShare)")!,
                        nasHost: nasHost,
                        nasShare: nasShare,
                        nasUsername: nasUsername
                    )
                    viewModel.addDestination(destination, password: nasPassword)
                    nasPassword = ""
                    nasHost = ""
                    nasShare = ""
                    nasUsername = ""
                    nasName = ""
                    showNASSheet = false
                },
                onCancel: {
                    showNASSheet = false
                }
            )
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backup Setup")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Choose what to protect and where BackupVault stores it.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(cardBackground)
    }

    private var folderSectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.sourceFolders.isEmpty {
                Text("No folders selected yet.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Button("Add Folder…") {
                    viewModel.showFolderPicker = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(pageAccent)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.sourceFolders, id: \.path) { url in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.yellow)
                            Text(url.lastPathComponent)
                                .font(.system(size: 17, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.removeFolder(url)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                        }
                        if url.path != viewModel.sourceFolders.last?.path {
                            Divider()
                        }
                    }
                }

                Button("Add Another Folder…") {
                    viewModel.showFolderPicker = true
                }
                .controlSize(.large)
            }
        }
    }

    private var destinationSectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                Text("Destination")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Picker("Destination", selection: $viewModel.selectedDestination) {
                    Text("None").tag(nil as BackupDestination?)
                    ForEach(viewModel.destinations) { destination in
                        Text(destination.name).tag(destination as BackupDestination?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 280)
                .controlSize(.large)
            }

            Divider()

            HStack(spacing: 12) {
                Button("Add External Drive…") {
                    addExternalDrive()
                }
                .controlSize(.large)
                Button("Add NAS (SMB)…") {
                    showNASSheet = true
                }
                .controlSize(.large)
            }

            Divider()

            if let destination = viewModel.selectedDestination {
                VStack(alignment: .leading, spacing: 6) {
                    Text(destination.name)
                        .font(.system(size: 19, weight: .semibold))
                    Text(destination.type == .nas ? "Network location" : "External drive")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let freeSpace = viewModel.destinationFreeSpaceBytes,
                       destination.type == .externalDrive {
                        Text("\(ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file)) free")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Choose a destination to store your snapshots.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var estimateSectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.isEstimating {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Calculating folder size…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if let count = viewModel.estimatedFileCount, let bytes = viewModel.estimatedSizeBytes {
                HStack(spacing: 14) {
                    estimatePill(title: "Estimated files", value: formatCount(count))
                    estimatePill(
                        title: "Estimated size",
                        value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                    )
                }

                if let freeSpace = viewModel.destinationFreeSpaceBytes,
                   bytes > freeSpace,
                   viewModel.selectedDestination != nil {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("This backup is larger than the free space on the selected destination.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.orange.opacity(0.10))
                    )
                }
            } else {
                Text("Add folders to calculate an estimate.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedOptionsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup("Exclusions", isExpanded: $showExclusions) {
                VStack(alignment: .leading, spacing: 16) {
                    exclusionFolderEditor
                    Divider()
                    exclusionPatternEditor
                }
                .padding(.top, 10)
            }
            .font(.system(size: 17, weight: .semibold))
            .tint(pageAccent)

            Divider()

            DisclosureGroup("Schedule", isExpanded: $showSchedule) {
                Picker("Backup schedule", selection: Binding(
                    get: { scheduleManager.schedule.type },
                    set: { newValue in
                        scheduleManager.schedule = BackupSchedule(
                            type: newValue,
                            dailyTime: scheduleManager.schedule.dailyTime
                        )
                    }
                )) {
                    ForEach(BackupScheduleType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.radioGroup)
                .controlSize(.large)
                .padding(.top, 10)
            }
            .font(.system(size: 17, weight: .semibold))
            .tint(pageAccent)

            Divider()

            DisclosureGroup("Verification", isExpanded: $showVerification) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Verify with SHA256 after copy", isOn: $viewModel.verifyWithChecksum)
                        .toggleStyle(.switch)
                        .font(.system(size: 16, weight: .medium))
                    Text("Useful when you want extra confidence that copied files are intact.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 10)
            }
            .font(.system(size: 17, weight: .semibold))
            .tint(pageAccent)
        }
    }

    private func configurationSection<Content: View>(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(pageAccent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(cardBackground)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )
    }

    private func estimatePill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if let saveFeedback {
                Text(saveFeedback)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if viewModel.isBackingUp, let progress = viewModel.progress {
                Text(progress.currentFile ?? "Backing up your files…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Changes are saved locally on this Mac.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Save Configuration") {
                saveConfiguration()
            }
            .controlSize(.large)

            Button {
                viewModel.startBackup()
            } label: {
                Label(viewModel.isBackingUp ? "Running Backup…" : "Run Backup", systemImage: "play.fill")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canStartBackup)
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

    private var exclusionFolderEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exclude folders")
                .font(.system(size: 16, weight: .semibold))
            Text("Skip folders by name, such as `node_modules` or `.cache`.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                TextField("Folder name", text: $newExcludedFolder)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                Button("Add") {
                    viewModel.addExcludedFolder(newExcludedFolder)
                    newExcludedFolder = ""
                }
                .controlSize(.large)
                .disabled(newExcludedFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(viewModel.exclusions.excludedFolderNames, id: \.self) { name in
                HStack {
                    Text(name)
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.removeExcludedFolder(named: name)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var exclusionPatternEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exclude file types")
                .font(.system(size: 16, weight: .semibold))
            Text("Skip files by pattern, such as `*.tmp` or `*.log`.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                TextField("Pattern", text: $newExcludedPattern)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                Button("Add") {
                    viewModel.addExcludedPattern(newExcludedPattern)
                    newExcludedPattern = ""
                }
                .controlSize(.large)
                .disabled(newExcludedPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(viewModel.exclusions.excludedFilePatterns, id: \.self) { pattern in
                HStack {
                    Text(pattern)
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.removeExcludedPattern(pattern)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func saveConfiguration() {
        viewModel.saveConfiguration()
        saveFeedback = "Configuration saved"
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                if saveFeedback == "Configuration saved" {
                    saveFeedback = nil
                }
            }
        }
    }

    private func addExternalDrive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the external drive or folder to use as backup destination"
        panel.runModal()
        if let url = panel.url {
            let destination = BackupDestination(
                name: url.lastPathComponent,
                type: .externalDrive,
                path: url
            )
            viewModel.addDestination(destination, password: nil)
        }
    }

    private func formatCount(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

// MARK: - NAS config sheet
struct NASConfigSheet: View {
    @Binding var host: String
    @Binding var share: String
    @Binding var username: String
    @Binding var password: String
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("NAS address", text: $host)
                TextField("Share name", text: $share)
                TextField("Display name (optional)", text: $name)
            }
            Section {
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
            }
            Section {
                HStack {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                    Spacer()
                    Button("Save") {
                        onSave()
                    }
                    .disabled(host.isEmpty || share.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
