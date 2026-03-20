//
//  NASMountService.swift
//  BackupVault
//
//  Mounts SMB shares via NSWorkspace and returns the local mount point URL.
//

import Foundation
import AppKit
import NetFS

/// Mounts SMB share and provides the mounted volume URL. Uses Keychain for password.
final class NASMountService {
    
    static let shared = NASMountService()
    private init() {}

    static func normalizeShareName(_ rawShare: String) -> String {
        rawShare
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "/Volumes/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }
    
    /// Mount SMB share. Strategy:
    /// 1. Check if already mounted (e.g. user connected via Finder) — use it directly.
    /// 2. Try mount_smbfs programmatically.
    /// 3. Prompt user to connect via Finder as a last resort.
    func mount(host: String, share: String, username: String, password: String) async throws -> URL {
        var cleanHost = host
            .replacingOccurrences(of: "smb://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let cleanShare = Self.normalizeShareName(share)
        // Strip Bonjour service suffixes: DS220._smb._tcp.local → DS220.local
        cleanHost = cleanHost
            .replacingOccurrences(of: "._smb._tcp", with: "")
            .replacingOccurrences(of: "._afpovertcp._tcp", with: "")
            .replacingOccurrences(of: "._smb", with: "")

        // Step 1: Already mounted? Use it directly.
        if let existing = findExistingMount(host: cleanHost, share: cleanShare) {
            return existing
        }

        // Step 2: Try mount_smbfs (works outside sandbox or with entitlements).
        if let mounted = tryMountSmbfs(host: cleanHost, share: cleanShare,
                                        username: username, password: password) {
            return mounted
        }

        // Step 3: Try NetFS with saved credentials and no authentication UI.
        if let mounted = tryMountNetFS(host: cleanHost, share: cleanShare,
                                       username: username, password: password) {
            return mounted
        }

        Logger.shared.warning("[NAS] Falling back to system SMB open; macOS may prompt for credentials.")

        // Step 4: Use NSWorkspace to open the SMB URL, then wait for mount to appear.
        return try await mountViaWorkspaceAndWait(host: cleanHost, share: cleanShare,
                                                   username: username, password: password)
    }

    /// Check /Volumes for an already-mounted share matching share name.
    func findExistingMount(host: String, share: String) -> URL? {
        let fm = FileManager.default
        let shareLower = share.lowercased()

        // Log all available volumes for debugging
        let allVolumes = (try? fm.contentsOfDirectory(atPath: "/Volumes")) ?? []
        Logger.shared.info("[NAS] Looking for share '\(share)' among /Volumes: \(allVolumes)")

        // 1. Exact match in /Volumes
        for vol in allVolumes {
            let volLower = vol.lowercased()
            if volLower == shareLower || volLower.hasPrefix(shareLower + " ") {
                let url = URL(fileURLWithPath: "/Volumes/\(vol)")
                if (try? url.checkResourceIsReachable()) == true {
                    Logger.shared.info("[NAS] Found existing mount at \(url.path)")
                    return url
                }
            }
        }

        // 2. Check all mounted volume URLs (catches Finder-mounted SMB shares)
        if let mountedVols = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: []) {
            let volPaths = mountedVols.map { $0.path }
            Logger.shared.info("[NAS] Mounted volume URLs: \(volPaths)")
            for vol in mountedVols {
                guard !vol.path.hasPrefix("/System"), !vol.path.hasPrefix("/private") else { continue }
                let name = (try? vol.resourceValues(forKeys: [.volumeNameKey]))?.allValues[.volumeNameKey] as? String ?? ""
                Logger.shared.info("[NAS] Volume: \(vol.path) name='\(name)'")
                if !name.isEmpty && (name.lowercased() == shareLower || name.lowercased().hasPrefix(shareLower)) {
                    if (try? vol.checkResourceIsReachable()) == true {
                        Logger.shared.info("[NAS] Matched by volume name at \(vol.path)")
                        return vol
                    }
                }
            }
        }

        // 3. Partial path match — Finder sometimes mounts at /Volumes/<ServerName>/<ShareName>
        for vol in allVolumes {
            let volPath = "/Volumes/\(vol)"
            // Check subdirectories for nested mounts (e.g. /Volumes/DS220/data)
            if let subs = try? fm.contentsOfDirectory(atPath: volPath) {
                for sub in subs where sub.lowercased() == shareLower {
                    let url = URL(fileURLWithPath: "\(volPath)/\(sub)")
                    if (try? url.checkResourceIsReachable()) == true {
                        Logger.shared.info("[NAS] Found nested mount at \(url.path)")
                        return url
                    }
                }
            }
        }

        // 4. Our custom mount points
        let customPoint = URL(fileURLWithPath: "/Volumes/BackupVault_\(share)")
        if (try? customPoint.checkResourceIsReachable()) == true {
            return customPoint
        }

        Logger.shared.info("[NAS] Could not find mount for share '\(share)'")
        return nil
    }

    /// Attempt mount_smbfs synchronously. Returns nil if unavailable or failed.
    private func tryMountSmbfs(host: String, share: String,
                                username: String, password: String) -> URL? {
        let mountPoint = "/Volumes/BackupVault_\(share)"
        let fm = FileManager.default
        if !fm.fileExists(atPath: mountPoint) {
            try? fm.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
        }
        let userEnc = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
        let passEnc = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount_smbfs")
        process.arguments = ["//\(userEnc):\(passEnc)@\(host)/\(share)", mountPoint]
        process.standardError = Pipe()

        guard (try? process.run()) != nil else {
            try? fm.removeItem(atPath: mountPoint)
            return nil
        }
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return URL(fileURLWithPath: mountPoint)
        }
        try? fm.removeItem(atPath: mountPoint)
        return nil
    }

    private func tryMountNetFS(host: String, share: String,
                               username: String, password: String) -> URL? {
        guard let shareURL = URL(string: "smb://\(host)/\(share)") else {
            return nil
        }

        let openOptions = NSMutableDictionary()
        openOptions[kNAUIOptionKey as String] = kNAUIOptionNoUI
        openOptions[kNetFSNoUserPreferencesKey as String] = kCFBooleanTrue

        let mountOptions = NSMutableDictionary()
        mountOptions[kNetFSSoftMountKey as String] = kCFBooleanTrue
        mountOptions[kNetFSAllowSubMountsKey as String] = kCFBooleanTrue

        var mountPoints: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(
            shareURL as CFURL,
            nil,
            username as CFString,
            password as CFString,
            openOptions,
            mountOptions,
            &mountPoints
        )

        guard status == 0 else {
            Logger.shared.warning("[NAS] NetFS mount failed with status \(status)")
            return nil
        }

        if let rawMounts = mountPoints?.takeRetainedValue() as? [Any] {
            for rawMount in rawMounts {
                if let path = rawMount as? String {
                    let url = URL(fileURLWithPath: path)
                    if (try? url.checkResourceIsReachable()) == true {
                        Logger.shared.info("[NAS] NetFS mounted share at \(url.path)")
                        return url
                    }
                } else if let url = rawMount as? URL,
                          (try? url.checkResourceIsReachable()) == true {
                    Logger.shared.info("[NAS] NetFS mounted share at \(url.path)")
                    return url
                }
            }
        }

        return findExistingMount(host: host, share: share)
    }

    /// Open SMB URL via NSWorkspace, then poll /Volumes until the share appears (up to 8s).
    private func mountViaWorkspaceAndWait(host: String, share: String,
                                           username: String, password: String) async throws -> URL {
        let userEnc = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
        let passEnc = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
        guard let url = URL(string: "smb://\(userEnc):\(passEnc)@\(host)/\(share)") else {
            throw BackupError.nasMountFailed("Invalid SMB URL")
        }

        // Open the URL — macOS will mount it in the background
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.open(url, configuration: config) { _, _ in
                continuation.resume()
            }
        }

        // Poll up to 8 seconds for the mount to appear in /Volumes
        let shareLower = share.lowercased()
        for _ in 0..<16 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            if let found = findExistingMount(host: host, share: share) {
                return found
            }
            // Also check direct path
            let fm = FileManager.default
            if let vols = try? fm.contentsOfDirectory(atPath: "/Volumes") {
                for vol in vols where vol.lowercased().hasPrefix(shareLower) {
                    let candidate = URL(fileURLWithPath: "/Volumes/\(vol)")
                    if (try? candidate.checkResourceIsReachable()) == true {
                        return candidate
                    }
                }
            }
        }

        throw BackupError.nasMountFailed(
            "Could not mount \(share) on \(host). " +
            "Try connecting via Finder → Go → Connect to Server (smb://\(host)) first, then run the backup."
        )
    }

    
    
    func unmount(url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/diskutil")
        process.arguments = ["unmount", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    /// List available SMB shares by mounting the server root and scanning /Volumes,
    /// OR by trying common share names. Works within sandbox constraints.
    func listShares(host: String, username: String, password: String) async throws -> [String] {
        let cleanHost = host
            .replacingOccurrences(of: "smb://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try smbutil first (works outside sandbox / with com.apple.security.temporary-exception.files.absolute-path.read-only)
        if let shares = trySmbutilListShares(host: cleanHost, username: username, password: password) {
            return shares
        }

        // Fallback: mount the server root via NSWorkspace — macOS shows share picker
        // but we need to return something, so we ask the user to confirm by mounting
        // a test share. If nothing works, throw a helpful error.
        throw BackupError.nasMountFailed(
            "Could not retrieve share list from \(cleanHost). " +
            "Please enter the share name manually using the 'Enter manually' option."
        )
    }

    private func trySmbutilListShares(host: String, username: String, password: String) -> [String]? {
        let userEnc = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
        let passEnc = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
        process.arguments = ["view", "//\(userEnc):\(passEnc)@\(host)"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe

        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data   = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        let shares = output.components(separatedBy: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty,
                      !trimmed.hasPrefix("Share"),
                      !trimmed.hasPrefix("---"),
                      !trimmed.hasPrefix("Using"),
                      !trimmed.hasPrefix("Server")
                else { return nil }
                let name = trimmed.components(separatedBy: .whitespaces).first ?? ""
                guard !name.hasSuffix("$"), !name.isEmpty else { return nil }
                return name
            }
        return shares.isEmpty ? nil : shares
    }
}
