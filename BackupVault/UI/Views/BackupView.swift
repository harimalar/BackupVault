//
//  BackupView.swift
//  BackupVault
//
//  Clean form-style layout: every section is a compact row, not a big card.
//  All functionality preserved exactly.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct BackupView: View {
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var showAdvanced = false
    @State private var saveFeedback: String?
    @State private var isDroppingFolder = false
    @State private var showDrivePicker = false
    @State private var pickerMode: PickerMode = .folder

    private enum PickerMode { case folder, drive }
    private let sourceAccent = Color(red: 0.95, green: 0.62, blue: 0.20)
    private let destinationAccent = Color(red: 0.31, green: 0.55, blue: 0.98)
    private let integrityAccent = Color(red: 0.58, green: 0.43, blue: 0.96)
    private let contentMaxWidth: CGFloat = 1120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                pageHeader
                contentLayout
            }
            .padding(28)
            .padding(.bottom, 16)
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(canvasBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .fileImporter(
            isPresented: Binding(
                get: { viewModel.showFolderPicker || showDrivePicker },
                set: { if !$0 { viewModel.showFolderPicker = false; showDrivePicker = false } }
            ),
            allowedContentTypes: [.folder],
            allowsMultipleSelection: pickerMode == .folder
        ) { result in
            if case .success(let urls) = result {
                if pickerMode == .folder {
                    for url in urls {
                        _ = url.startAccessingSecurityScopedResource()
                        viewModel.addFolder(url)
                    }
                } else if let url = urls.first {
                    let accessed = url.startAccessingSecurityScopedResource()
                    viewModel.addDestination(
                        BackupDestination(name: url.lastPathComponent, type: .externalDrive, path: url),
                        password: nil
                    )
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
        .onAppear {
            viewModel.loadState()
            viewModel.updateDestinationFreeSpace()
            viewModel.refreshEstimates()
        }
        .sheet(isPresented: $showNASSheet) { nasSheet }
        .animation(.easeInOut(duration: 0.18), value: showAdvanced)
    }

    private var contentLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    sectionCard {
                        foldersSection
                    }

                    sectionCard {
                        destinationSection
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    sectionCard {
                        foldersSection
                    }

                    sectionCard {
                        destinationSection
                    }
                }
            }

            sectionCard {
                VStack(spacing: 0) {
                    estimateRow
                    panelDivider
                    advancedSection
                }
            }
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    pageHeaderCopy
                    Spacer(minLength: 16)
                    headerActions
                }

                VStack(alignment: .leading, spacing: 12) {
                    pageHeaderCopy
                    headerActions
                }
            }
            HStack(spacing: 8) {
                headerBadge(
                    title: viewModel.sourceFolders.isEmpty ? "No sources yet" : "\(viewModel.sourceFolders.count) source\(viewModel.sourceFolders.count == 1 ? "" : "s")",
                    tint: sourceAccent
                )
                headerBadge(
                    title: viewModel.selectedDestination?.name ?? "No destination",
                    tint: destinationAccent
                )
                headerBadge(
                    title: viewModel.verifyWithChecksum ? "Verification on" : "Fast copy mode",
                    tint: integrityAccent
                )
            }
        }
    }

    private var pageHeaderCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Configure Backup")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(destinationAccent)

            VStack(alignment: .leading, spacing: 6) {
                Text("Backup Setup")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Choose what to protect, where it should live, and how strict the backup should be.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        if viewModel.isBackingUp {
            backupStatusHeader
        } else {
            HStack(spacing: 10) {
                if viewModel.selectedDestination != nil {
                    Button {
                        viewModel.openSelectedDestinationFolder()
                    } label: {
                        Label("View Backups", systemImage: "folder")
                    }
                    .controlSize(.large)
                }

                Button("Save") { saveConfiguration() }
                    .controlSize(.large)

                Button {
                    viewModel.lastCompletedSnapshotURL = nil
                    viewModel.startBackup()
                } label: {
                    Label("Run Backup", systemImage: "play.fill")
                        .frame(minWidth: 132)
                }
                .buttonStyle(.borderedProminent)
                .tint(destinationAccent)
                .controlSize(.large)
                .disabled(!viewModel.canStartBackup)
            }
        }
    }

    private var backupStatusHeader: some View {
        let fraction = backupProgressFraction
        let tint = destinationAccent

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.09), lineWidth: 6)
                    .frame(width: 42, height: 42)

                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 42, height: 42)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: fraction)

                Text("\(Int(fraction * 100))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.25), value: fraction)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(backupStatusTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(backupStatusDetail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                viewModel.cancelBackup()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.regular)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(destinationAccent.opacity(0.16), lineWidth: 1)
                )
        )
    }

    // MARK: - Folders Section

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                symbol: "folder.badge.plus",
                title: "Source Folders",
                detail: viewModel.sourceFolders.isEmpty ? "Choose folders to protect" : "\(viewModel.sourceFolders.count) selected",
                accent: sourceAccent
            )

            panelDivider

            if viewModel.sourceFolders.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No folders selected yet.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    accentActionButton(
                        title: "Add Folder…",
                        systemImage: "plus",
                        tint: sourceAccent,
                        prominent: true
                    ) {
                        pickerMode = .folder
                        viewModel.showFolderPicker = true
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(viewModel.sourceFolders.enumerated()), id: \.element.path) { index, url in
                        sourceFolderRow(url: url, showDivider: index < viewModel.sourceFolders.count - 1)
                    }

                    HStack {
                        Spacer()
                        Button {
                            pickerMode = .folder
                            viewModel.showFolderPicker = true
                        } label: {
                            Label("Add Another Folder…", systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(sourceAccent)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
        }
        .overlay(
            Group {
                if isDroppingFolder {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            sourceAccent,
                            style: StrokeStyle(lineWidth: 2, dash: [6])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(sourceAccent.opacity(0.07))
                        )
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.down.to.line.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(sourceAccent)
                                Text("Drop folder to add")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(sourceAccent)
                            }
                        )
                }
            }
        )
        .onDrop(of: [.fileURL], isTargeted: $isDroppingFolder) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.hasDirectoryPath else { return }
                    Task { @MainActor in
                        _ = url.startAccessingSecurityScopedResource()
                        viewModel.addFolder(url)
                    }
                }
            }
            return true
        }
    }

    // MARK: - Destination Section

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                symbol: "externaldrive.fill",
                title: "Destination",
                detail: viewModel.selectedDestination.map { $0.type == .nas ? "Network target selected" : "External drive selected" } ?? "Choose where snapshots are stored",
                accent: destinationAccent
            )

            panelDivider

            if viewModel.destinations.isEmpty {
                HStack(alignment: .center) {
                    Text("No destination added yet.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    addDriveButtons
                }
                .padding(18)
            } else {
                // Active destination picker (only shows if multiple)
                if viewModel.destinations.count > 1 {
                    HStack {
                        Text("Active")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $viewModel.selectedDestination) {
                            Text("None").tag(nil as BackupDestination?)
                            ForEach(viewModel.destinations) { d in
                                Text(d.name).tag(d as BackupDestination?)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }

                VStack(spacing: 12) {
                    ForEach(viewModel.destinations) { destination in
                        destinationRow(destination)
                    }

                    HStack(spacing: 10) {
                        addDriveButtons
                        Spacer()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    private var addDriveButtons: some View {
        HStack(spacing: 8) {
            accentActionButton(
                title: "Add Drive…",
                systemImage: "externaldrive.badge.plus",
                tint: destinationAccent
            ) {
                pickerMode = .drive
                showDrivePicker = true
            }

            accentActionButton(
                title: "Add NAS…",
                systemImage: "network.badge.shield.half.filled",
                tint: integrityAccent
            ) {
                showNASSheet = true
            }
        }
    }

    // MARK: - Estimate Row

    private var estimateRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text("Estimate")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Spacer()

            if viewModel.isEstimating {
                ProgressView().scaleEffect(0.7).controlSize(.small)
                Text("Calculating…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if let count = viewModel.estimatedFileCount, let bytes = viewModel.estimatedSizeBytes {
                if let free = viewModel.destinationFreeSpaceBytes,
                   bytes > free, viewModel.selectedDestination != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("Destination needs more space")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text("\(formatCount(count)) files")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 12))
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
            } else {
                Text("Add folders to estimate")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        VStack(spacing: 0) {
            // Toggle row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text("Advanced Options")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.7)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvanced {
                panelDivider

                // Verification toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verify after copy")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("SHA256 check on every file — slower but ensures integrity")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.verifyWithChecksum)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                panelDivider

                // Exclusions
                VStack(alignment: .leading, spacing: 10) {
                    Text("Exclude folders")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("e.g. node_modules", text: $newExcludedFolder)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .controlSize(.small)
                        Button("Add") {
                            viewModel.addExcludedFolder(newExcludedFolder)
                            newExcludedFolder = ""
                        }
                        .controlSize(.small)
                        .disabled(newExcludedFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !viewModel.exclusions.excludedFolderNames.isEmpty {
                        FlowTagList(tags: viewModel.exclusions.excludedFolderNames) { name in
                            viewModel.removeExcludedFolder(named: name)
                        }
                    }

                    Text("Exclude file types")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    HStack(spacing: 8) {
                        TextField("e.g. *.tmp", text: $newExcludedPattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .controlSize(.small)
                        Button("Add") {
                            viewModel.addExcludedPattern(newExcludedPattern)
                            newExcludedPattern = ""
                        }
                        .controlSize(.small)
                        .disabled(newExcludedPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !viewModel.exclusions.excludedFilePatterns.isEmpty {
                        FlowTagList(tags: viewModel.exclusions.excludedFilePatterns) { pattern in
                            viewModel.removeExcludedPattern(pattern)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(symbol: String, title: String, detail: String, accent: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.75)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func externalDestinationFolderLabel(_ destination: BackupDestination) -> String {
        let standardized = destination.path.standardizedFileURL
        let components = standardized.pathComponents
        guard let volumesIndex = components.firstIndex(of: "Volumes"),
              components.count > volumesIndex + 1 else {
            return standardized.lastPathComponent
        }
        if components.count == volumesIndex + 2 {
            return "the drive root"
        }
        return standardized.lastPathComponent
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.10), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.07), radius: colorScheme == .dark ? 12 : 18, y: colorScheme == .dark ? 6 : 10)
            )
    }

    private func accentActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(prominent ? tint : tint.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(tint.opacity(prominent ? 0 : 0.20), lineWidth: 1)
                        )
                )
                .foregroundStyle(prominent ? Color.white : tint)
        }
        .buttonStyle(.plain)
    }

    private func headerBadge(title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(tint.opacity(0.10))
                .overlay(
                    Capsule()
                        .strokeBorder(tint.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private func summaryCard(title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var estimateSummaryValue: String {
        if let bytes = viewModel.estimatedSizeBytes {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        return "Not ready"
    }

    private var estimateSummaryDetail: String {
        if let count = viewModel.estimatedFileCount {
            return "\(formatCount(count)) file\(count == 1 ? "" : "s") in the next backup"
        }
        return "Add folders and destination to calculate"
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.09))
            .frame(height: 1)
    }

    private func sourceFolderRow(url: URL, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(sourceAccent.opacity(0.10))
                        .frame(width: 34, height: 34)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.yellow)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(url.path)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(role: .destructive) {
                    viewModel.removeFolder(url)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if showDivider {
                panelDivider
                    .padding(.leading, 58)
            }
        }
        .background(insetRowBackground(tint: sourceAccent))
    }

    private func destinationRow(_ destination: BackupDestination) -> some View {
        let isSelected = viewModel.selectedDestination?.id == destination.id

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill((isSelected ? destinationAccent : integrityAccent).opacity(0.10))
                    .frame(width: 34, height: 34)
                Image(systemName: destination.type == .nas ? "network" : "externaldrive.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? destinationAccent : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(destination.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                HStack(spacing: 4) {
                    Text(destination.type == .nas ? "Network" : "External drive")
                    if let free = viewModel.destinationFreeSpaceBytes,
                       isSelected,
                       destination.type == .externalDrive {
                        Text("·").foregroundStyle(.tertiary)
                        Text(ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " free")
                    }
                    if destination.type == .externalDrive && !destination.isAvailable {
                        Text("·").foregroundStyle(.tertiary)
                        Text("Disconnected")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

                if destination.type == .externalDrive {
                    Text("Backups in \(externalDestinationFolderLabel(destination))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 10)

            if destination.type == .externalDrive && destination.isAvailable {
                Button("Choose Folder…") {
                    viewModel.chooseFolderWithinExternalDrive(destination)
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(destinationAccent)
            }

            if destination.type == .externalDrive && destination.isAvailable {
                Button("Eject") {
                    viewModel.ejectDestination(destination)
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if isSelected {
                Text("Selected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(destinationAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(destinationAccent.opacity(0.10))
                            .overlay(
                                Capsule()
                                    .strokeBorder(destinationAccent.opacity(0.18), lineWidth: 1)
                            )
                    )
            } else {
                Button("Select") {
                    viewModel.selectedDestination = destination
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                viewModel.removeDestination(id: destination.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(insetRowBackground(tint: destinationAccent, selected: isSelected))
    }

    private func insetRowBackground(tint: Color, selected: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(selected ? tint.opacity(colorScheme == .dark ? 0.085 : 0.10) : Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? tint.opacity(colorScheme == .dark ? 0.18 : 0.24) : Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.09), lineWidth: 1)
            )
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

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Group {
                if let saveFeedback {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12))
                        Text(saveFeedback).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.system(size: 12))
                        Text(errorMessage).font(.system(size: 12, weight: .medium)).foregroundStyle(.red).lineLimit(1)
                    }
                } else if viewModel.isBackingUp, let progress = viewModel.progress {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.72).controlSize(.small)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(progress.currentFile ?? "Backing up…")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                            if progress.filesToCopy > 0 {
                                Text("\(progress.filesCopied) of \(progress.filesToCopy) files")
                                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else {
                    Text("Changes are saved locally on this Mac.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if viewModel.isBackingUp {
                Button { viewModel.cancelBackup() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            }
        }
        .frame(maxWidth: contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(
            ZStack(alignment: .top) {
                Color(nsColor: .windowBackgroundColor).opacity(0.97).background(.ultraThinMaterial)
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            }
        )
    }

    // MARK: - NAS Sheet

    private var nasSheet: some View {
        NASDiscoverySheet(
            isPresented: $showNASSheet,
            onAdd: { destination, password in
                viewModel.addDestination(destination, password: password)
            }
        )
    }

    // MARK: - Helpers

    private func saveConfiguration() {
        viewModel.saveConfiguration()
        saveFeedback = "Saved"
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run { if saveFeedback == "Saved" { saveFeedback = nil } }
        }
    }

    private func formatCount(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private var backupProgressFraction: Double {
        guard viewModel.isBackingUp else { return 0 }
        guard let progress = viewModel.progress else { return 0 }
        guard progress.filesToCopy > 0 else {
            switch progress.phase {
            case .completed: return 1
            case .failed: return 0
            default: return 0.08
            }
        }
        return min(1, max(0, Double(progress.filesCopied) / Double(max(progress.filesToCopy, 1))))
    }

    private var backupStatusTitle: String {
        guard let progress = viewModel.progress else { return "Preparing backup…" }
        switch progress.phase {
        case .resolvingDestination: return "Connecting destination…"
        case .scanning: return "Scanning files…"
        case .copying: return "Backing up files…"
        case .verifying: return "Verifying files…"
        case .completed: return "Backup complete"
        case .failed: return "Backup failed"
        }
    }

    private var backupStatusDetail: String {
        guard let progress = viewModel.progress else { return "Preparing your backup." }
        if progress.filesToCopy > 0 {
            return "\(progress.filesCopied) of \(progress.filesToCopy) files"
        }
        return progress.currentFile ?? "Working…"
    }
}

// MARK: - Flow tag list for exclusions

struct FlowTagList: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        // Simple wrapping layout using LazyVGrid
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Button(role: .destructive) {
                        onRemove(tag)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.primary.opacity(0.08))
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - NAS Discovery Sheet (inlined)

struct NASDiscoverySheet: View {
    private enum FocusField: Hashable {
        case manualHost
        case username
        case password
        case shareName
    }

    @Binding var isPresented: Bool
    let onAdd: (BackupDestination, String) -> Void

    @StateObject private var scanner = NASScanner()
    @State private var selected: DiscoveredNAS?
    @State private var mode: SheetMode = .scan

    // Manual entry
    @State private var manualHost = ""
    @State private var manualName = ""

    // Credentials
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var isAddingDestination = false
    @State private var connectError: String?

    // Share picker
    @State private var availableShares: [String] = []
    @State private var selectedShare: String?
    @FocusState private var focusedField: FocusField?

    private let orange = Color(red: 0.97, green: 0.50, blue: 0.15)

    enum SheetMode { case scan, manual, credentials, sharePicker }

    private func normalizedShareName(from raw: String) -> String? {
        let normalized = NASMountService.normalizeShareName(raw)
        return normalized.isEmpty ? nil : normalized
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Add Network Drive")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(modeSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if mode != .scan {
                    Button {
                        withAnimation {
                            connectError = nil
                            switch mode {
                            case .manual:      mode = .scan
                            case .credentials: mode = selected != nil ? .scan : .manual
                            case .sharePicker: mode = .credentials
                            default:           mode = .scan
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Back")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Body
            Group {
                switch mode {
                case .scan:        scanBody
                case .manual:      manualBody
                case .credentials: credentialsBody
                case .sharePicker: sharePickerBody
                }
            }
            .frame(minHeight: 280)

            Divider()

            // Footer
            HStack {
                Button("Cancel", role: .cancel) {
                    scanner.stopScan()
                    isPresented = false
                }
                .controlSize(.large)
                Spacer()

                switch mode {
                case .scan:
                    Button("Enter manually") { withAnimation { mode = .manual } }
                        .controlSize(.large)
                case .manual:
                    Button("Next") { withAnimation { mode = .credentials } }
                        .buttonStyle(.borderedProminent).tint(orange).controlSize(.large)
                        .disabled(manualHost.isEmpty)
                case .credentials:
                    if isConnecting {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Connecting…").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Connect & Browse Shares") { fetchShares() }
                            .buttonStyle(.borderedProminent).tint(orange).controlSize(.large)
                            .disabled(username.isEmpty || password.isEmpty)
                    }
                case .sharePicker:
                    if isAddingDestination {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Choose destination folder…").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Add Destination") {
                            completeDestinationSelection()
                        }
                        .buttonStyle(.borderedProminent).tint(orange).controlSize(.large)
                        .disabled(selectedShare == nil)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            scanner.startScan()
            scheduleFocus(for: mode)
        }
        .onDisappear { scanner.stopScan() }
        .onChange(of: mode) { newMode in
            scheduleFocus(for: newMode)
        }
    }

    // MARK: Scan body

    private var scanBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scan status bar
            HStack(spacing: 8) {
                if scanner.isScanning {
                    ProgressView().scaleEffect(0.7).controlSize(.small)
                    Text("Scanning your local network…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(scanner.discovered.isEmpty ? "No devices found on this network" : "\(scanner.discovered.count) device\(scanner.discovered.count == 1 ? "" : "s") found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Scan again") { scanner.startScan() }
                        .font(.system(size: 12))
                        .buttonStyle(.plain)
                        .foregroundStyle(orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))

            Divider()

            if scanner.discovered.isEmpty && !scanner.isScanning {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("No SMB shares found")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Make sure your NAS is on and connected to the same Wi-Fi.\nYou can also enter the address manually.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(scanner.discovered) { nas in
                            Button {
                                selected = nas
                                selectedShare = nil
                                withAnimation { mode = .credentials }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(orange.opacity(0.10))
                                            .frame(width: 34, height: 34)
                                        Image(systemName: "server.rack")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(orange)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(nas.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(nas.host)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(selected?.id == nas.id ? orange.opacity(0.07) : Color.clear)

                            Divider().padding(.leading, 62)
                        }
                    }
                }
            }
        }
    }

    // MARK: Manual body

    private var manualBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Network address")
                    .font(.system(size: 13, weight: .semibold))
                TextField(
                    "",
                    text: $manualHost,
                    prompt: Text("DS220.local or 192.168.1.100")
                )
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .manualHost)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Display name")
                    .font(.system(size: 13, weight: .semibold))
                TextField(
                    "",
                    text: $manualName,
                    prompt: Text("My NAS (optional)")
                )
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            Text("After entering the address, you'll sign in and choose which share to use.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    // MARK: Credentials body — just username/password, no share name needed

    private var credentialsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Server identity banner
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 13)).foregroundStyle(orange)
                Text(selected?.displayName ?? manualHost)
                    .font(.system(size: 13, weight: .semibold))
                if let host = selected?.host {
                    Text("·").foregroundStyle(.tertiary)
                    Text(host).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Sign in to browse available shares")
                    .font(.system(size: 13, weight: .semibold))

                VStack(spacing: 0) {
                    TextField(
                        "",
                        text: $username,
                        prompt: Text("Username")
                    )
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .username)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    Divider()
                        .padding(.horizontal, 14)

                    SecureField(
                        "",
                        text: $password,
                        prompt: Text("Password")
                    )
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .password)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .padding(16)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(orange)
                    Text("Important for NAS backups")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("If macOS later asks to connect to this server after a restart, choose “Remember this password in my keychain.” You should only need to do that once.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if let err = connectError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.system(size: 12))
                    Text(err).font(.system(size: 12, weight: .medium)).foregroundStyle(.red)
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }

    // MARK: Share picker body

    private var sharePickerBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: availableShares.isEmpty ? "pencil.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(availableShares.isEmpty ? orange : .green)
                    .font(.system(size: 12))
                Text(availableShares.isEmpty
                     ? "Enter the share name on \(selected?.displayName ?? manualHost)"
                     : "Select a share to back up to")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))

            Divider()

            if availableShares.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Share name")
                        .font(.system(size: 13, weight: .semibold))

                    TextField("", text: Binding(
                            get: { selectedShare ?? "" },
                            set: { selectedShare = normalizedShareName(from: $0) }
                        ), prompt: Text("Data")
                    )
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .shareName)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )

                    Text("BackupVault could not automatically list shares on this server. Enter the share name directly — you can find it in your NAS admin panel.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(availableShares, id: \.self) { share in
                            Button {
                                withAnimation { selectedShare = share }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(selectedShare == share ? orange.opacity(0.14) : Color.primary.opacity(0.07))
                                            .frame(width: 30, height: 30)
                                        Image(systemName: "externaldrive.fill.badge.wifi")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(selectedShare == share ? orange : Color.secondary)
                                    }
                                    Text(share).font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    if selectedShare == share {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(orange).font(.system(size: 14))
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(selectedShare == share ? orange.opacity(0.06) : Color.clear)

                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var modeSubtitle: String {
        switch mode {
        case .scan:        return "Find a NAS or SMB server on your network"
        case .manual:      return "Enter the server address manually"
        case .credentials: return "Sign in to \(selected?.displayName ?? manualHost)"
        case .sharePicker: return "Choose which share to use"
        }
    }

    private func fetchShares() {
        let host = selected?.host ?? manualHost
        guard !host.isEmpty, !username.isEmpty, !password.isEmpty else { return }
        connectError = nil
        isConnecting = true
        Task {
            do {
                let shares = try await NASMountService.shared.listShares(
                    host: host, username: username, password: password)
                await MainActor.run {
                    availableShares = shares
                    selectedShare = shares.first
                    isConnecting = false
                    withAnimation { mode = .sharePicker }
                }
            } catch {
                // If share listing fails (sandbox restriction), fall back to
                // a manual share entry field directly in credentials view
                await MainActor.run {
                    isConnecting = false
                    // Show manual share entry instead of an error
                    availableShares = []
                    withAnimation { mode = .sharePicker }
                }
            }
        }
    }

    private func completeDestinationSelection() {
        guard let share = selectedShare else { return }
        let host = selected?.host ?? manualHost
        let cleanShare = NASMountService.normalizeShareName(share)
        let destinationName = manualName.isEmpty ? (selected?.displayName ?? host) : manualName
        guard !host.isEmpty, !username.isEmpty, !password.isEmpty else { return }

        connectError = nil
        isAddingDestination = true

        Task {
            do {
                let mountedURL = try await NASMountService.shared.mount(
                    host: host,
                    share: cleanShare,
                    username: username,
                    password: password
                )
                let selectedFolder = try requestDestinationFolder(
                    for: destinationName.isEmpty ? host : destinationName,
                    mountedURL: mountedURL
                )
                let destination = BackupDestination(
                    name: destinationName.isEmpty ? "NAS \(host)" : destinationName,
                    type: .nas,
                    path: selectedFolder,
                    nasHost: host,
                    nasShare: cleanShare,
                    nasUsername: username
                )
                await MainActor.run {
                    onAdd(destination, password)
                    scanner.stopScan()
                    isAddingDestination = false
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    isAddingDestination = false
                    if !(error is CancellationError) {
                        connectError = error.localizedDescription
                    }
                }
            }
        }
    }

    @MainActor
    private func requestDestinationFolder(for destinationName: String, mountedURL: URL) throws -> URL {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder on \(destinationName) where BackupVault should store backups."
        panel.prompt = "Use This Folder"
        panel.directoryURL = mountedURL
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true

        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else {
            throw BackupError.cancelled
        }
        guard selectedURL.path.hasPrefix(mountedURL.path) else {
            throw BackupError.nasMountFailed("Choose a folder inside the mounted \(mountedURL.lastPathComponent) share.")
        }
        return selectedURL
    }

    private func scheduleFocus(for mode: SheetMode) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            switch mode {
            case .manual:
                focusedField = .manualHost
            case .credentials:
                focusedField = .username
            case .sharePicker:
                focusedField = availableShares.isEmpty ? .shareName : nil
            case .scan:
                focusedField = nil
            }
        }
    }
}
