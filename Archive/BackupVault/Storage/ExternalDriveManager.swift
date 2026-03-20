//
//  ExternalDriveManager.swift
//  BackupVault
//
//  Detects and lists external volumes using macOS volume APIs.
//

import Foundation
import AppKit

/// Manages external drive detection and volume listing.
final class ExternalDriveManager {
    
    static let shared = ExternalDriveManager()
    private let fileManager = FileManager.default
    
    private init() {}
    
    /// All mounted volume URLs (e.g. /Volumes/MyDrive). Excludes the root volume.
    var mountedVolumes: [URL] {
        guard let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey], options: [.skipHiddenVolumes]) else {
            return []
        }
        return urls.filter { url in
            guard url.path != "/" else { return false }
            let removable = (try? url.resourceValues(forKeys: [.volumeIsRemovableKey]).volumeIsRemovable) ?? false
            let ejectable = (try? url.resourceValues(forKeys: [.volumeIsEjectableKey]).volumeIsEjectable) ?? false
            return removable || ejectable
        }
    }
    
    /// Check if a URL is on an external (removable/ejectable) volume.
    func isOnExternalVolume(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIsRemovableKey, .volumeIsEjectableKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return false }
        return (values.volumeIsRemovable ?? false) || (values.volumeIsEjectable ?? false)
    }
    
    /// Volume space for a URL (uses DiskSpaceMonitor).
    func space(for url: URL) -> DiskSpaceMonitor.VolumeSpace? {
        DiskSpaceMonitor.space(for: url)
    }
}
