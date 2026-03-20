//
//  RestoreViewModel.swift
//  BackupVault
//
//  MVVM: state and actions for Restore (browse backups, search, restore).
//

import Foundation
import SwiftUI

/// Snapshots grouped by date for the restore browser.
struct SnapshotsByDate: Identifiable {
    let label: String
    let locations: [BackupLocation]
    let sortOrder: Int
    var id: String { label }
}

private struct SnapshotGroupKey: Hashable {
    let label: String
    let sortOrder: Int
}

@MainActor
final class RestoreViewModel: ObservableObject {
    
    @Published var backupLocations: [BackupLocation] = []
    @Published var selectedLocation: BackupLocation?
    @Published var currentManifest: BackupManifest?
    
    /// Snapshots grouped into reassuring relative date buckets.
    var snapshotsByDate: [SnapshotsByDate] {
        let grouped = Dictionary(grouping: backupLocations) { snapshotGroup(for: $0.date) }
        return grouped
            .map { key, locations in
                SnapshotsByDate(
                    label: key.label,
                    locations: locations.sorted { $0.date > $1.date },
                    sortOrder: key.sortOrder
                )
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return ($0.locations.first?.date ?? .distantPast) > ($1.locations.first?.date ?? .distantPast)
            }
    }
    @Published var currentPath: URL?
    @Published var currentItems: [BackupItem] = []
    @Published var searchQuery = ""
    @Published var searchResults: [BackupItem] = []
    @Published var selectedItems: Set<String> = []
    @Published var restoreDestination: URL?
    @Published var restoreToOriginal = true
    @Published var isRestoring = false
    @Published var errorMessage: String?
    
    private let restoreService = RestoreService()
    
    func loadBackupLocations() {
        let dests = DestinationStore.shared.loadDestinations()
        let roots = dests.compactMap { dest -> URL? in
            switch dest.type {
            case .externalDrive: return dest.path
            case .nas: return dest.path
            }
        }
        backupLocations = restoreService.listBackupLocations(destinationRoots: roots)
        if selectedLocation == nil, let first = backupLocations.first {
            selectLocation(first)
        } else if backupLocations.isEmpty {
            selectedLocation = nil
            currentManifest = nil
            currentPath = nil
            currentItems = []
        }
    }
    
    func selectLocation(_ location: BackupLocation) {
        selectedLocation = location
        currentManifest = restoreService.loadManifest(for: location.path)
        currentPath = location.path
        refreshCurrentItems()
        searchResults = []
        searchQuery = ""
        selectedItems.removeAll()
    }
    
    func refreshCurrentItems() {
        guard let path = currentPath, let snapshotRoot = selectedLocation?.path else { currentItems = []; return }
        currentItems = restoreService.listContents(of: path, snapshotRoot: snapshotRoot)
    }
    
    func navigate(to item: BackupItem) {
        guard item.isDirectory else { return }
        currentPath = item.url
        refreshCurrentItems()
    }
    
    func navigateUp() {
        guard let path = currentPath else { return }
        if path.path == selectedLocation?.path.path {
            return
        }
        let parent = path.deletingLastPathComponent()
        if parent.path == selectedLocation?.path.path ?? "" {
            currentPath = selectedLocation?.path
        } else {
            currentPath = parent
        }
        refreshCurrentItems()
    }
    
    func performSearch() {
        guard let root = selectedLocation?.path else { searchResults = []; return }
        searchResults = restoreService.search(query: searchQuery, in: root)
    }
    
    func toggleSelection(_ item: BackupItem) {
        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }
    }
    
    func restoreSelected() {
        let items = selectedRestoreItems()
        if items.isEmpty {
            errorMessage = "Select at least one file or folder to restore."
            return
        }
        isRestoring = true
        errorMessage = nil
        do {
            if restoreToOriginal {
                guard let manifest = currentManifest else {
                    throw RestoreError.cannotResolveOriginalLocation("the selected items")
                }
                try restoreService.restore(items: items, using: manifest)
            } else {
                guard let restoreDestination else {
                    errorMessage = "Choose a restore destination."
                    isRestoring = false
                    return
                }
                try restoreService.restore(items: items, to: restoreDestination)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isRestoring = false
        selectedItems.removeAll()
    }
    
    func restoreEntireSnapshot() {
        guard let location = selectedLocation else {
            errorMessage = "Select a snapshot first."
            return
        }
        isRestoring = true
        errorMessage = nil
        do {
            if restoreToOriginal {
                guard let manifest = currentManifest else {
                    throw RestoreError.cannotResolveOriginalLocation(location.displayName)
                }
                try restoreService.restoreEntireSnapshot(snapshotRoot: location.path, using: manifest)
            } else {
                guard let restoreDestination else {
                    errorMessage = "Choose a restore destination for the snapshot."
                    isRestoring = false
                    return
                }
                try restoreService.restoreEntireSnapshot(snapshotRoot: location.path, to: restoreDestination)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isRestoring = false
    }
    
    func clearError() {
        errorMessage = nil
    }

    private func selectedRestoreItems() -> [BackupItem] {
        let combined = currentItems + searchResults
        var seen = Set<String>()
        return combined.filter { item in
            guard selectedItems.contains(item.id), !seen.contains(item.id) else { return false }
            seen.insert(item.id)
            return true
        }
    }
    
    private func snapshotGroup(for date: Date) -> SnapshotGroupKey {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return SnapshotGroupKey(label: "Today", sortOrder: 0)
        }
        if calendar.isDateInYesterday(date) {
            return SnapshotGroupKey(label: "Yesterday", sortOrder: 1)
        }
        if let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date >= oneWeekAgo {
            return SnapshotGroupKey(label: "Last Week", sortOrder: 2)
        }
        return SnapshotGroupKey(label: "Earlier", sortOrder: 3)
    }
}
