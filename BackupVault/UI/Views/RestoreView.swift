//
//  RestoreView.swift
//  BackupVault
//
//  Redesigned restore: single page, "Restore Snapshot" as hero action,
//  folder browsing as a secondary expand-in-place panel.
//  All ViewModel functionality preserved exactly.
//

import SwiftUI

// MARK: - Destination Choice

private enum RestoreDestinationChoice: Equatable {
    case original
    case custom
}

// MARK: - Main View

struct RestoreView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = RestoreViewModel()
    @State private var showFileBrowser = false
    @State private var showDestinationPicker = false
    @State private var destinationChoice: RestoreDestinationChoice = .original
    @State private var showError = false

    private let restoreAccent = Color(red: 0.29, green: 0.55, blue: 0.98)
    private let highlightAccent = Color(red: 0.93, green: 0.62, blue: 0.22)
    private let secondaryRestoreAccent = Color(red: 0.54, green: 0.44, blue: 0.95)
    private let contentMaxWidth: CGFloat = 1260

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeader

            HSplitView {
                snapshotList
                    .frame(minWidth: 230, maxWidth: 280)
                rightPanel
                    .frame(minWidth: 460)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 520)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cardFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(panelBorderColor, lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(28)
        .frame(maxWidth: contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(canvasBackground)
        .onAppear { viewModel.loadBackupLocations() }
        .onChange(of: viewModel.selectedLocation?.id) { newId in
            if let id = newId,
               let loc = viewModel.backupLocations.first(where: { $0.id == id }) {
                viewModel.selectLocation(loc)
                showFileBrowser = false
            }
        }
        .onChange(of: destinationChoice) { choice in
            viewModel.restoreToOriginal = (choice == .original)
        }
        .fileImporter(
            isPresented: $showDestinationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                viewModel.restoreDestination = url
            }
        }
        .onChange(of: viewModel.errorMessage) { new in showError = (new != nil) }
        .alert("Restore Error", isPresented: $showError) {
            Button("OK") { viewModel.clearError(); showError = false }
        } message: {
            if let m = viewModel.errorMessage { Text(m) }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RESTORE FILES")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(restoreAccent)

            VStack(alignment: .leading, spacing: 6) {
                Text("Restore")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Choose a backup snapshot and decide where the restored files should go.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                headerBadge(
                    title: viewModel.selectedLocation == nil ? "No snapshot selected" : "Snapshot ready",
                    tint: highlightAccent
                )
                headerBadge(
                    title: destinationChoice == .original ? "Original location" : "Different folder",
                    tint: restoreAccent
                )
            }
        }
    }

    // MARK: - Snapshot List (left)

    private var snapshotList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(restoreAccent)
                Text("Snapshots")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 6)

            if viewModel.backupLocations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No snapshots yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Run a backup first.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $viewModel.selectedLocation) {
                    ForEach(viewModel.snapshotsByDate) { group in
                        Section {
                            ForEach(Array(group.locations.enumerated()), id: \.element.id) { index, loc in
                                // Only the very first snapshot across all groups gets "LATEST"
                                let isLatest = loc.id == viewModel.snapshotsByDate.first?.locations.first?.id
                                SnapshotRow(
                                    location: loc,
                                    isSelected: viewModel.selectedLocation?.id == loc.id,
                                    isLatest: isLatest,
                                    position: index + 1,
                                    totalInGroup: group.locations.count
                                )
                                .tag(loc)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                            }
                        } header: {
                            Text(group.label)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.6)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }
        }
        .background(snapshotSidebarFill)
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let location = viewModel.selectedLocation {
                    // Snapshot identity header
                    snapshotHeader(location)

                    Divider().padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 20) {
                        // ── Section 1: Where to restore ──
                        destinationSection

                        // ── Section 2: Hero action ──
                        heroRestoreCard

                        // ── Section 3: Restore specific folders ──
                        specificFilesSection
                    }
                    .padding(24)
                } else {
                    emptySelection
                }
            }
        }
        .background(canvasBackground)
    }

    // MARK: - Snapshot Header

    private func snapshotHeader(_ location: BackupLocation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(location.snapshotTimeString)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(headerRelativeDate(location.date))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    if viewModel.backupLocations.first?.id == location.id {
                        Text("LATEST")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(highlightAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(highlightAccent.opacity(0.12)))
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(location.computerName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(location.snapshotDateString)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func headerRelativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Section 1: Destination

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Compact segmented toggle row
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Restore to")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()

                // Segmented-style picker
                HStack(spacing: 0) {
                    destinationSegment(
                        title: "Original location",
                        symbol: "house",
                        isSelected: destinationChoice == .original
                    ) { destinationChoice = .original }

                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 1, height: 20)

                    destinationSegment(
                        title: destinationChoice == .custom && viewModel.restoreDestination != nil
                            ? viewModel.restoreDestination!.lastPathComponent
                            : "Different folder",
                        symbol: "folder",
                        isSelected: destinationChoice == .custom
                    ) {
                        destinationChoice = .custom
                        if viewModel.restoreDestination == nil { showDestinationPicker = true }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if destinationChoice == .custom {
                    Button {
                        showDestinationPicker = true
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(restoreAccent)
                    .help("Change destination folder")
                }
            }
        }
    }

    private func destinationSegment(title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(isSelected ? restoreAccent : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? restoreAccent.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 180)
    }



    // MARK: - Section 2: Hero Restore Card

    private var heroRestoreCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                // Info column
                VStack(alignment: .leading, spacing: 6) {
                    Text("Restore everything from this snapshot")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(destinationChoice == .original
                         ? "Everything will be put back in its original place."
                         : "Everything in this snapshot will be copied into the folder you chose.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("All files and folders in this snapshot")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: destinationChoice == .original ? "house.fill" : "folder.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(destinationChoice == .original
                             ? "Restored to original location"
                             : (viewModel.restoreDestination.map { "Copied to: \($0.lastPathComponent)" } ?? "Choose a destination above"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Hero button
                if viewModel.isRestoring {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.85)
                        Text("Restoring…")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                } else {
                    Button {
                        restoreEntireSnapshot()
                    } label: {
                        Label("Restore Snapshot", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(restoreAccent)
                    .controlSize(.large)
                    .disabled(!canRestore)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(restoreAccent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(restoreAccent.opacity(0.18), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Section 3: Specific Files

    private var specificFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showFileBrowser.toggle()
                    if !showFileBrowser {
                        viewModel.selectedItems.removeAll()
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        secondaryRestoreAccent.opacity(0.24),
                                        secondaryRestoreAccent.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(secondaryRestoreAccent.opacity(0.24), lineWidth: 1)
                    }
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(secondaryRestoreAccent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore specific folders or files")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("Browse the snapshot and choose only what you want to restore.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    HStack(spacing: 4) {
                        if !viewModel.selectedItems.isEmpty {
                            Text("\(viewModel.selectedItems.count) selected")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(secondaryRestoreAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(secondaryRestoreAccent.opacity(0.12)))
                        }
                        Image(systemName: showFileBrowser ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(showFileBrowser ? 0.055 : 0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    showFileBrowser
                                        ? secondaryRestoreAccent.opacity(0.18)
                                        : Color.primary.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showFileBrowser {
                fileBrowserPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var fileBrowserPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose items to restore")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Search or browse inside this snapshot, then restore only the items you need.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !viewModel.selectedItems.isEmpty {
                    Text("\(viewModel.selectedItems.count) ready")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(secondaryRestoreAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(secondaryRestoreAccent.opacity(0.12)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryRestoreAccent)
                TextField("Search files and folders…", text: $viewModel.searchQuery)
                    .font(.system(size: 14, weight: .medium))
                    .textFieldStyle(.plain)
                    .onSubmit { viewModel.performSearch() }
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        viewModel.searchResults = [BackupItem]()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button("Search") { viewModel.performSearch() }
                    .controlSize(.small)
                    .disabled(viewModel.searchQuery.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            // Breadcrumb nav
            if viewModel.currentPath?.path != viewModel.selectedLocation?.path.path {
                HStack(spacing: 6) {
                    Button {
                        viewModel.navigateUp()
                        viewModel.searchResults = [BackupItem]()
                        viewModel.searchQuery = ""
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .bold))
                            Text("Back")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(secondaryRestoreAccent)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    Text(viewModel.currentPath?.lastPathComponent ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.03))

                Divider()
            }

            // File list
            let displayItems = viewModel.searchResults.isEmpty
                ? viewModel.currentItems
                : viewModel.searchResults

            if displayItems.isEmpty {
                HStack {
                    Spacer()
                    Text(viewModel.searchQuery.isEmpty ? "This folder is empty." : "No results.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(displayItems) { item in
                        FileBrowserRow(
                            item: item,
                            isSelected: viewModel.selectedItems.contains(item.id),
                            onToggle: { viewModel.toggleSelection(item) },
                            onBrowse: item.isDirectory ? { viewModel.navigate(to: item) } : nil
                        )
                        if item.id != displayItems.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }

            // Restore selected bar
            if !viewModel.selectedItems.isEmpty {
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(restoreAccent)
                        .font(.system(size: 14))
                    Text("\(viewModel.selectedItems.count) item\(viewModel.selectedItems.count == 1 ? "" : "s") selected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        viewModel.selectedItems.removeAll()
                    }
                    .controlSize(.small)
                    .foregroundStyle(.secondary)

                    Button {
                        restoreSelected()
                    } label: {
                        Label("Restore Selected", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(secondaryRestoreAccent)
                    .controlSize(.regular)
                    .disabled(!canRestore)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Empty State

    private var emptySelection: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(restoreAccent.opacity(0.42))
            VStack(spacing: 4) {
                Text("Select a snapshot to restore")
                    .font(.system(size: 15, weight: .semibold))
                Text("Pick a backup from the list on the left.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }

    // MARK: - Shared label

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private func headerBadge(title: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(tint.opacity(0.10))
                .overlay(
                    Capsule()
                        .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Actions

    private var canRestore: Bool {
        guard !viewModel.isRestoring else { return false }
        if destinationChoice == .custom && viewModel.restoreDestination == nil { return false }
        return true
    }

    private func restoreEntireSnapshot() {
        viewModel.restoreToOriginal = (destinationChoice == .original)
        viewModel.restoreEntireSnapshot()
    }

    private func restoreSelected() {
        viewModel.restoreToOriginal = (destinationChoice == .original)
        viewModel.restoreSelected()
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

    private var snapshotSidebarFill: Color {
        if colorScheme == .dark {
            return Color(nsColor: .controlBackgroundColor)
        }
        return Color(red: 0.952, green: 0.956, blue: 0.965)
    }

    private var panelBorderColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.10)
    }
}

// MARK: - Snapshot Row

struct SnapshotRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let location: BackupLocation
    let isSelected: Bool
    var isLatest: Bool = false
    var position: Int = 1
    var totalInGroup: Int = 1

    private let accent = Color(red: 0.29, green: 0.55, blue: 0.98)

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(location.snapshotTimeString)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                    if isLatest {
                        Text("LATEST")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(accent.opacity(0.12)))
                    }
                }
                HStack(spacing: 4) {
                    Text(relativeTime)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    // Show position when multiple snapshots share the same time
                    if totalInGroup > 1 {
                        Text("· #\(position)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? accent.opacity(colorScheme == .dark ? 0.16 : 0.12) : rowFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? accent.opacity(colorScheme == .dark ? 0.28 : 0.24) : rowBorderColor, lineWidth: 1)
                )
        )
    }

    private var relativeTime: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: location.date, relativeTo: Date())
    }

    private var rowFillColor: Color {
        colorScheme == .dark
            ? Color.primary.opacity(0.04)
            : Color.white.opacity(0.72)
    }

    private var rowBorderColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.08)
    }
}

// MARK: - File Browser Row

struct FileBrowserRow: View {
    let item: BackupItem
    let isSelected: Bool
    let onToggle: () -> Void
    let onBrowse: (() -> Void)?
    @State private var isHovered = false

    private let accent = Color(red: 0.29, green: 0.55, blue: 0.98)

    var body: some View {
        HStack(spacing: 0) {
            // Tap entire row to toggle
            Button(action: onToggle) {
                HStack(spacing: 11) {
                    // Checkbox
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isSelected ? accent : Color.primary.opacity(0.2), lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                        if isSelected {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(accent)
                                .frame(width: 18, height: 18)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                    // Icon
                    Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))
                        .font(.system(size: 15, weight: item.isDirectory ? .semibold : .regular))
                        .foregroundStyle(item.isDirectory ? .yellow : Color.secondary.opacity(0.7))
                        .frame(width: 18)

                    // Name
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    // Size
                    if let size = item.size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                isHovered
                    ? Color.primary.opacity(0.04)
                    : (isSelected ? accent.opacity(0.05) : Color.clear)
            )

            // Browse chevron for folders
            if let onBrowse {
                Divider()
                    .frame(height: 20)
                    .padding(.vertical, 10)
                Button(action: onBrowse) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHovered ? accent : Color.secondary.opacity(0.5))
                        .frame(width: 36, height: 38)
                }
                .buttonStyle(.plain)
                .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
                .help("Browse folder contents")
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo.fill"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "mp3", "aac", "wav", "flac", "m4a": return "music.note"
        case "zip", "gz", "tar", "rar", "7z": return "archivebox.fill"
        case "swift", "py", "js", "ts", "html", "css", "json": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "doc", "docx": return "doc.fill"
        default: return "doc.fill"
        }
    }
}
