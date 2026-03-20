//
//  RestoreView.swift
//  BackupVault
//
//  Browse backups, search files, restore to original or custom folder.
//

import SwiftUI

struct RestoreView: View {
    @StateObject private var viewModel = RestoreViewModel()
    @State private var showRestoreDestinationPicker = false
    @State private var showError = false
    
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Snapshots")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                List(selection: $viewModel.selectedLocation) {
                    ForEach(viewModel.snapshotsByDate) { group in
                        Section(group.label) {
                            ForEach(group.locations) { loc in
                                BackupLocationRow(location: loc)
                                    .tag(loc)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 240)
            .onAppear { viewModel.loadBackupLocations() }
            .onChange(of: viewModel.selectedLocation?.id) { newId in
                if let id = newId, let loc = viewModel.backupLocations.first(where: { $0.id == id }) {
                    viewModel.selectLocation(loc)
                }
            }
            
            // Right: browser + search
            VStack(alignment: .leading, spacing: 0) {
                if let location = viewModel.selectedLocation {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(location.snapshotDateString)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("\(location.computerName) at \(location.snapshotTimeString)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search files…", text: $viewModel.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .onSubmit { viewModel.performSearch() }
                    Button("Search") { viewModel.performSearch() }
                        .controlSize(.large)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                
                if !viewModel.searchResults.isEmpty {
                    List(viewModel.searchResults) { item in
                        RestoreItemRow(
                            item: item,
                            isSelected: viewModel.selectedItems.contains(item.id),
                            onToggleSelection: { viewModel.toggleSelection(item) },
                            onBrowse: item.isDirectory ? { viewModel.navigate(to: item) } : nil
                        )
                    }
                    .listStyle(.inset)
                } else {
                    if viewModel.currentPath?.path != viewModel.selectedLocation?.path.path {
                        HStack {
                            Button(action: { viewModel.navigateUp() }) {
                                Image(systemName: "chevron.left")
                            }
                            .buttonStyle(.borderless)
                            Text(viewModel.currentPath?.lastPathComponent ?? "")
                                .font(.system(size: 15, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    
                    List(viewModel.currentItems) { item in
                        RestoreItemRow(
                            item: item,
                            isSelected: viewModel.selectedItems.contains(item.id),
                            onToggleSelection: { viewModel.toggleSelection(item) },
                            onBrowse: item.isDirectory ? { viewModel.navigate(to: item) } : nil
                        )
                    }
                    .listStyle(.inset)
                }
                
                Divider()
                
                // Restore destination and actions
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("Restore to original location", isOn: $viewModel.restoreToOriginal)
                            .font(.system(size: 16, weight: .medium))
                        if !viewModel.restoreToOriginal {
                            Button(viewModel.restoreDestination?.path ?? "Choose folder…") {
                                showRestoreDestinationPicker = true
                            }
                            .controlSize(.large)
                        }
                    }
                    HStack(spacing: 12) {
                        Button("Restore Selected") {
                            viewModel.restoreSelected()
                        }
                        .controlSize(.large)
                        .disabled(viewModel.selectedItems.isEmpty)
                        Button("Restore entire snapshot") {
                            viewModel.restoreEntireSnapshot()
                        }
                        .controlSize(.large)
                        .disabled(viewModel.selectedLocation == nil || viewModel.isRestoring)
                        if viewModel.isRestoring {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .padding(8)
            }
            .frame(minWidth: 360)
        }
        .frame(minWidth: 600, minHeight: 400)
        .fileImporter(
            isPresented: $showRestoreDestinationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                viewModel.restoreDestination = url
            }
        }
        .onChange(of: viewModel.errorMessage) { new in
            showError = (new != nil)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { viewModel.clearError(); showError = false }
        } message: {
            if let m = viewModel.errorMessage { Text(m) }
        }
    }
}

struct BackupLocationRow: View {
    let location: BackupLocation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(location.snapshotTimeString)
                .font(.system(size: 16, weight: .semibold))
            Text(location.computerName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct RestoreItemRow: View {
    let item: BackupItem
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onBrowse: (() -> Void)?
    
    var body: some View {
        HStack {
            Button(action: onToggleSelection) {
                HStack {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(item.isDirectory ? .yellow : .secondary)
                    Text(item.name)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    if let size = item.size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            
            if let onBrowse {
                Button(action: onBrowse) {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Browse folder")
            }
        }
    }
}
