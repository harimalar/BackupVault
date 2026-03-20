//
//  NASManager.swift
//  BackupVault
//
//  Connects to NAS via SMB; credentials stored in Keychain.
//

import Foundation

/// Manages NAS (SMB) connections and mounting.
final class NASManager {
    
    static let shared = NASManager()
    
    private init() {}
    
    /// Mount SMB share and return the mounted volume URL (e.g. /Volumes/sharename).
    func mount(host: String, share: String, username: String, password: String) async throws -> URL {
        try await NASMountService.shared.mount(host: host, share: share, username: username, password: password)
    }
    
    /// Unmount a previously mounted share.
    func unmount(url: URL) {
        NASMountService.shared.unmount(url: url)
    }
}
