//
//  DestinationStore.swift
//  BackupVault
//
//  Persists backup destinations and backup run metadata to UserDefaults / app support.
//

import Foundation

final class DestinationStore {
    static let shared = DestinationStore()
    
    private let defaults = UserDefaults.standard
    private let destinationsKey = "BackupVault.destinations"
    private let runsKey = "BackupVault.backupRuns"
    private let selectedSourceFoldersKey = "BackupVault.selectedSourceFolders"
    private let exclusionsKey = "BackupVault.exclusions"
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {}
    
    // MARK: - Destinations
    
    func loadDestinations() -> [BackupDestination] {
        guard let data = defaults.data(forKey: destinationsKey),
              let list = try? decoder.decode([BackupDestination].self, from: data) else {
            return []
        }
        return list
    }
    
    func saveDestinations(_ destinations: [BackupDestination]) {
        guard let data = try? encoder.encode(destinations) else { return }
        defaults.set(data, forKey: destinationsKey)
    }
    
    func addDestination(_ destination: BackupDestination) {
        var list = loadDestinations()
        list.append(destination)
        saveDestinations(list)
    }
    
    func removeDestination(id: UUID) {
        var list = loadDestinations()
        list.removeAll { $0.id == id }
        saveDestinations(list)
        try? KeychainService.shared.deletePassword(forDestinationID: id)
    }
    
    func updateDestination(_ destination: BackupDestination) {
        var list = loadDestinations()
        if let i = list.firstIndex(where: { $0.id == destination.id }) {
            list[i] = destination
            saveDestinations(list)
        }
    }
    
    // MARK: - Selected source folders
    
    func loadSelectedSourceFolders() -> [URL] {
        guard let bookmarks = defaults.array(forKey: selectedSourceFoldersKey) as? [Data] else {
            return []
        }
        return bookmarks.compactMap { data -> URL? in
            var isStale = false
            return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        }
    }
    
    func saveSelectedSourceFolders(_ urls: [URL]) {
        let bookmarks = urls.compactMap { url -> Data? in
            try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        defaults.set(bookmarks, forKey: selectedSourceFoldersKey)
    }
    
    // MARK: - Exclusions
    
    func loadExclusions() -> BackupExclusions {
        guard let data = defaults.data(forKey: exclusionsKey),
              let ex = try? decoder.decode(BackupExclusions.self, from: data) else {
            return .default
        }
        return ex
    }
    
    func saveExclusions(_ exclusions: BackupExclusions) {
        guard let data = try? encoder.encode(exclusions) else { return }
        defaults.set(data, forKey: exclusionsKey)
    }
    
    // MARK: - Backup runs (for resume and history)
    
    func loadBackupRuns() -> [BackupRun] {
        guard let data = defaults.data(forKey: runsKey),
              let list = try? decoder.decode([BackupRun].self, from: data) else {
            return []
        }
        return list
    }
    
    func saveBackupRuns(_ runs: [BackupRun]) {
        guard let data = try? encoder.encode(runs) else { return }
        defaults.set(data, forKey: runsKey)
    }
    
    func appendRun(_ run: BackupRun) {
        var runs = loadBackupRuns()
        runs.append(run)
        saveBackupRuns(runs)
    }
    
    func updateRun(_ run: BackupRun) {
        var runs = loadBackupRuns()
        if let i = runs.firstIndex(where: { $0.id == run.id }) {
            runs[i] = run
            saveBackupRuns(runs)
        }
    }
    
    func lastIncompleteRun(forDestinationID destinationID: UUID) -> BackupRun? {
        loadBackupRuns()
            .filter { $0.destinationID == destinationID && $0.state == .interrupted }
            .max(by: { $0.startedAt < $1.startedAt })
    }
    
    /// Latest completed backup run for a destination (for health dashboard).
    func lastCompletedRun(forDestinationID destinationID: UUID) -> BackupRun? {
        loadBackupRuns()
            .filter { $0.destinationID == destinationID && $0.state == .completed }
            .max(by: { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) })
    }
}
