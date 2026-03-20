//
//  NASMountService.swift
//  BackupVault
//
//  Mounts SMB shares via NSWorkspace and returns the local mount point URL.
//

import Foundation
import AppKit

/// Mounts SMB share and provides the mounted volume URL. Uses Keychain for password.
final class NASMountService {
    
    static let shared = NASMountService()
    private init() {}
    
    /// Mount SMB share. Returns URL of mounted volume (e.g. /Volumes/sharename) or throws.
    func mount(host: String, share: String, username: String, password: String) async throws -> URL {
        var cleanHost = host
            .replacingOccurrences(of: "smb://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if let slash = cleanHost.firstIndex(of: "/") {
            cleanHost = String(cleanHost[..<slash])
        }
        
        let userEnc = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
        let passEnc = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
        let urlString = "smb://\(userEnc):\(passEnc)@\(cleanHost)/\(share)"
        guard let url = URL(string: urlString) else {
            throw BackupError.nasMountFailed("Invalid SMB URL")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(url, configuration: config) { _, error in
                if let error = error {
                    continuation.resume(throwing: BackupError.nasMountFailed(error.localizedDescription))
                    return
                }
                let vol = URL(fileURLWithPath: "/Volumes/\(share)")
                if FileManager.default.fileExists(atPath: vol.path) {
                    continuation.resume(returning: vol)
                } else {
                    continuation.resume(throwing: BackupError.nasMountFailed("Mount path not found. Check share name."))
                }
            }
        }
    }
    
    func unmount(url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/diskutil")
        process.arguments = ["unmount", url.path]
        try? process.run()
        process.waitUntilExit()
    }
}
