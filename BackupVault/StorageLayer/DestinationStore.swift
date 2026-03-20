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
    private let fileManager = FileManager.default
    private let destinationsKey = "BackupVault.destinations"
    private let runsKey = "BackupVault.backupRuns"
    private let selectedSourceFoldersKey = "BackupVault.selectedSourceFolders"
    private let exclusionsKey = "BackupVault.exclusions"
    private let destinationBookmarksKey = "BackupVault.destinationBookmarks"
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {}
    
    // MARK: - Destinations
    
    func loadDestinations() -> [BackupDestination] {
        guard let data = defaults.data(forKey: destinationsKey),
              let list = try? decoder.decode([BackupDestination].self, from: data) else {
            return []
        }
        // Deduplicate by path, keeping the first occurrence of each unique path.
        // This retroactively fixes any duplicates accumulated from previous sessions.
        var seen = Set<String>()
        let deduped = list.filter { seen.insert($0.path.path).inserted }
        // If we removed duplicates, persist the cleaned list immediately
        if deduped.count != list.count {
            saveDestinations(deduped)
        }
        return deduped
    }
    
    func saveDestinations(_ destinations: [BackupDestination]) {
        guard let data = try? encoder.encode(destinations) else { return }
        defaults.set(data, forKey: destinationsKey)
    }
    
    func addDestination(_ destination: BackupDestination) {
        var list = loadDestinations()
        // Dedup: don't add if a destination with the same path already exists
        guard !list.contains(where: { $0.path == destination.path }) else { return }
        list.append(destination)
        saveDestinations(list)
        if destination.path.isFileURL {
            saveBookmark(for: destination.path, destinationID: destination.id)
        }
    }

    /// Resolve a security-scoped bookmark for a destination and start accessing it.
    /// Returns the resolved URL (may differ from stored path if volume remounts).
    func startAccessing(destination: BackupDestination) -> URL {
        guard let data = loadBookmark(for: destination.id) else {
            if destination.path.isFileURL {
                _ = destination.path.startAccessingSecurityScopedResource()
            }
            return destination.path
        }
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            if destination.path.isFileURL {
                _ = destination.path.startAccessingSecurityScopedResource()
            }
            return destination.path
        }
        if isStale {
            saveBookmark(for: resolved, destinationID: destination.id)
        }
        _ = resolved.startAccessingSecurityScopedResource()
        return resolved
    }

    func stopAccessing(url: URL) {
        if url.isFileURL {
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    func removeDestination(id: UUID) {
        var list = loadDestinations()
        let removed = list.first { $0.id == id }
        list.removeAll { $0.id == id }
        saveDestinations(list)
        removeBookmark(for: id)
        if let removed, removed.type == .nas {
            try? KeychainService.shared.deleteNASPassword(for: removed)
        } else {
            try? KeychainService.shared.deletePassword(forDestinationID: id)
        }
    }

    func updateDestination(_ destination: BackupDestination) {
        var list = loadDestinations()
        if let i = list.firstIndex(where: { $0.id == destination.id }) {
            list[i] = destination
            saveDestinations(list)
            if destination.path.isFileURL {
                saveBookmark(for: destination.path, destinationID: destination.id)
            } else {
                removeBookmark(for: destination.id)
            }
        }
    }

    func hasBookmark(for destinationID: UUID) -> Bool {
        loadBookmark(for: destinationID) != nil
    }

    @discardableResult
    func saveBookmark(for url: URL, destinationID: UUID) -> Bool {
        guard url.isFileURL else { return false }
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return false
        }
        var bookmarks = (defaults.dictionary(forKey: destinationBookmarksKey) as? [String: Data]) ?? [:]
        bookmarks[destinationID.uuidString] = bookmark
        defaults.set(bookmarks, forKey: destinationBookmarksKey)
        return true
    }

    func isReachableDirectory(_ url: URL) -> Bool {
        url.isFileURL && url.hasDirectoryPath && (try? url.checkResourceIsReachable()) == true
    }

    func canWrite(in directory: URL) -> Bool {
        guard isReachableDirectory(directory) else { return false }
        let probe = directory.appendingPathComponent(".backupvault_access_probe_\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: probe, withIntermediateDirectories: false)
            try fileManager.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    private func loadBookmark(for destinationID: UUID) -> Data? {
        let bookmarks = (defaults.dictionary(forKey: destinationBookmarksKey) as? [String: Data]) ?? [:]
        return bookmarks[destinationID.uuidString]
    }

    private func removeBookmark(for destinationID: UUID) {
        var bookmarks = (defaults.dictionary(forKey: destinationBookmarksKey) as? [String: Data]) ?? [:]
        bookmarks.removeValue(forKey: destinationID.uuidString)
        defaults.set(bookmarks, forKey: destinationBookmarksKey)
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

    /// Most recent completed run that has a verifiedAt date, for integrity score.
    /// Separate from lastCompletedRun so a normal backup doesn't erase verification status.
    func lastVerifiedRun(forDestinationID destinationID: UUID) -> BackupRun? {
        loadBackupRuns()
            .filter { $0.destinationID == destinationID && $0.state == .completed && $0.verifiedAt != nil }
            .max(by: { ($0.verifiedAt ?? .distantPast) < ($1.verifiedAt ?? .distantPast) })
    }
}
