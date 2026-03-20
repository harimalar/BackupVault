//
//  RestoreService.swift
//  BackupVault
//
//  Browse backup locations, search files, restore to original or custom folder.
//

import Foundation
import UniformTypeIdentifiers

/// A backup location the user can browse (BackupVault/ComputerName/Date).
struct BackupLocation: Identifiable, Hashable {
    let id: String
    let computerName: String
    let date: Date
    let path: URL
    let displayName: String
    
    /// Date only for grouping (e.g. "2026-03-15"); from folder name when possible.
    var snapshotDateString: String {
        let name = path.lastPathComponent
        if name.count >= 10, name[name.index(name.startIndex, offsetBy: 4)] == "-", name[name.index(name.startIndex, offsetBy: 7)] == "-" {
            return String(name.prefix(10))
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    
    /// Short time for display (e.g. "19:30"); from folder name when format is YYYY-MM-DD_HH-mm.
    var snapshotTimeString: String {
        let name = path.lastPathComponent
        if name.count >= 16, name.contains("_"), let range = name.range(of: "_") {
            return String(name[name.index(after: range.lowerBound)...]).replacingOccurrences(of: "-", with: ":")
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: BackupLocation, rhs: BackupLocation) -> Bool { lhs.id == rhs.id }
}

/// A file or folder inside a backup, for browsing/restore.
struct BackupItem: Identifiable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let snapshotRelativePath: String
}

final class RestoreService {
    
    private let fileManager = FileManager.default
    private let backupRootName = "BackupVault"
    private let snapshotDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return formatter
    }()
    
    /// List backup roots (e.g. external volume or mounted NAS) and find BackupVault/ComputerName/Date folders.
    func listBackupLocations(destinationRoots: [URL]) -> [BackupLocation] {
        var locations: [BackupLocation] = []
        
        for root in destinationRoots {
            let backupRootURL = root.appendingPathComponent(backupRootName)
            guard let computerNames = try? fileManager.contentsOfDirectory(at: backupRootURL, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { continue }
            
            for computerDir in computerNames where (try? computerDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                guard let dates = try? fileManager.contentsOfDirectory(at: computerDir, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: []) else { continue }
                
                for dateDir in dates where (try? dateDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    guard fileManager.fileExists(atPath: dateDir.appendingPathComponent("manifest.json").path) else { continue }
                    let name = dateDir.lastPathComponent
                    let mod = snapshotDateFormatter.date(from: name)
                        ?? (try? dateDir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                        ?? Date()
                    let loc = BackupLocation(
                        id: dateDir.path,
                        computerName: computerDir.lastPathComponent,
                        date: mod,
                        path: dateDir,
                        displayName: "\(computerDir.lastPathComponent) – \(name)"
                    )
                    locations.append(loc)
                }
            }
        }
        
        return locations.sorted { $0.date > $1.date }
    }
    
    func loadManifest(for snapshotRoot: URL) -> BackupManifest? {
        let manifestURL = snapshotRoot.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(BackupManifest.self, from: data)
    }
    
    /// List contents of a directory inside a backup (for browsing).
    func listContents(of url: URL, snapshotRoot: URL) -> [BackupItem] {
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return contents.compactMap { u in
            guard shouldShowInBrowser(u, snapshotRoot: snapshotRoot) else { return nil }
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return BackupItem(
                id: u.path,
                url: u,
                name: u.lastPathComponent,
                isDirectory: isDir,
                size: size.map { Int64($0) },
                snapshotRelativePath: relativePath(of: u, from: snapshotRoot)
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    
    /// Search for files by name under a backup location.
    func search(query: String, in backupRoot: URL) -> [BackupItem] {
        guard !query.isEmpty else { return [] }
        var results: [BackupItem] = []
        if let enumerator = fileManager.enumerator(at: backupRoot, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
            while let url = enumerator.nextObject() as? URL {
                guard shouldShowInBrowser(url, snapshotRoot: backupRoot) else { continue }
                if url.lastPathComponent.localizedCaseInsensitiveContains(query) {
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                    results.append(BackupItem(id: url.path, url: url, name: url.lastPathComponent, isDirectory: isDir, size: size.map { Int64($0) }, snapshotRelativePath: relativePath(of: url, from: backupRoot)))
                }
            }
        }
        return results
    }
    
    /// Restore a file or folder to a custom destination.
    func restore(item: BackupItem, to destinationURL: URL) throws {
        let dest = destinationURL.appendingPathComponent(item.name)
        try copyReplacingItem(at: item.url, to: dest)
    }
    
    /// Restore multiple items.
    func restore(items: [BackupItem], to destinationURL: URL) throws {
        for item in items {
            try restore(item: item, to: destinationURL)
        }
    }
    
    func restore(item: BackupItem, using manifest: BackupManifest) throws {
        guard let destinationParent = originalRestoreParent(for: item.snapshotRelativePath, manifest: manifest) else {
            throw RestoreError.cannotResolveOriginalLocation(item.name)
        }
        let destination = destinationParent.appendingPathComponent(item.name)
        try copyReplacingItem(at: item.url, to: destination)
    }
    
    func restore(items: [BackupItem], using manifest: BackupManifest) throws {
        for item in items {
            try restore(item: item, using: manifest)
        }
    }
    
    /// Restore entire snapshot (all contents of snapshot root) to destination. Creates a folder with snapshot name.
    func restoreEntireSnapshot(snapshotRoot: URL, to destinationURL: URL) throws {
        let snapshotName = snapshotRoot.lastPathComponent
        let destRoot = destinationURL.appendingPathComponent(snapshotName)
        try copyReplacingItem(at: snapshotRoot, to: destRoot, filterInternalFiles: true, snapshotRoot: snapshotRoot)
    }
    
    func restoreEntireSnapshot(snapshotRoot: URL, using manifest: BackupManifest) throws {
        let rootMappings = Dictionary(grouping: manifest.files, by: \.sourceRootName)
        for (sourceRootName, records) in rootMappings {
            guard let rootPath = records.first?.sourceRootPath, !rootPath.isEmpty else {
                throw RestoreError.snapshotMissingOriginalPath(sourceRootName)
            }
            let sourceRootURL = URL(fileURLWithPath: rootPath)
            let sourceFolderInSnapshot = snapshotRoot.appendingPathComponent(sourceRootName)
            guard fileManager.fileExists(atPath: sourceFolderInSnapshot.path) else { continue }
            let destination = sourceRootURL.deletingLastPathComponent().appendingPathComponent(sourceRootName)
            try copyReplacingItem(at: sourceFolderInSnapshot, to: destination)
        }
    }
    
    private func copyReplacingItem(at source: URL, to destination: URL, filterInternalFiles: Bool = false, snapshotRoot: URL? = nil) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !filterInternalFiles {
            try fileManager.copyItem(at: source, to: destination)
            return
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let snapshotRoot else { return }
        let contents = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for item in contents where shouldShowInBrowser(item, snapshotRoot: snapshotRoot) {
            try copyReplacingItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
        }
    }
    
    private func originalRestoreParent(for snapshotRelativePath: String, manifest: BackupManifest) -> URL? {
        let components = snapshotRelativePath.split(separator: "/").map(String.init)
        guard let sourceRootName = components.first else { return nil }
        guard let record = manifest.files.first(where: {
            if !$0.sourceRootName.isEmpty {
                return $0.sourceRootName == sourceRootName
            }
            return $0.snapshotRelativePath.hasPrefix(sourceRootName + "/")
        }), !record.sourceRootPath.isEmpty else {
            return nil
        }
        let originalRootURL = URL(fileURLWithPath: record.sourceRootPath)
        let itemComponents = Array(components.dropFirst())
        if itemComponents.isEmpty {
            return originalRootURL.deletingLastPathComponent()
        }
        return itemComponents.dropLast().reduce(into: originalRootURL) { partial, component in
            partial.appendPathComponent(component)
        }
    }
    
    private func shouldShowInBrowser(_ url: URL, snapshotRoot: URL) -> Bool {
        if url == snapshotRoot.appendingPathComponent("manifest.json") { return false }
        if url.lastPathComponent == ".backupvault_state.json" || url.lastPathComponent == ".backupvault_state.json.tmp" {
            return false
        }
        return true
    }
    
    private func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(url.path.dropFirst(rootPath.count))
    }
}

enum RestoreError: LocalizedError {
    case cannotResolveOriginalLocation(String)
    case snapshotMissingOriginalPath(String)
    
    var errorDescription: String? {
        switch self {
        case .cannotResolveOriginalLocation(let item):
            return "Could not determine the original restore location for \(item)."
        case .snapshotMissingOriginalPath(let folder):
            return "Snapshot metadata is missing the original path for \(folder)."
        }
    }
}
