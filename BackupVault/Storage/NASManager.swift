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

// MARK: - Local Network NAS Discovery

struct DiscoveredNAS: Identifiable, Equatable {
    let id: String          // host
    let host: String        // e.g. "192.168.1.10" or "NAS.local"
    let displayName: String // friendly Bonjour name
    let shares: [String]    // SMB share names (populated after probing)

    static func == (lhs: DiscoveredNAS, rhs: DiscoveredNAS) -> Bool { lhs.id == rhs.id }
}

/// Scans the local network for SMB/AFP servers via Bonjour (_smb._tcp, _afpovertcp._tcp).
@MainActor
final class NASScanner: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {

    @Published var discovered: [DiscoveredNAS] = []
    @Published var isScanning = false

    private var browser: NetServiceBrowser?
    private var resolving: [NetService] = []
    private var pendingServices: [NetService] = []

    func startScan() {
        discovered = []
        isScanning = true
        resolving = []
        pendingServices = []

        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_smb._tcp.", inDomain: "local.")

        // Also look for AFP (Time Capsule, older Macs)
        let afpBrowser = NetServiceBrowser()
        afpBrowser.delegate = self
        afpBrowser.searchForServices(ofType: "_afpovertcp._tcp.", inDomain: "local.")

        // Auto-stop after 6 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.stopScan()
        }
    }

    func stopScan() {
        browser?.stop()
        browser = nil
        isScanning = false
    }

    // MARK: NetServiceBrowserDelegate

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser,
                                       didFind service: NetService,
                                       moreComing: Bool) {
        service.delegate = self
        Task { @MainActor in
            self.pendingServices.append(service)
            service.resolve(withTimeout: 4)
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser,
                                       didNotSearch errorDict: [String: NSNumber]) {
        Task { @MainActor in self.isScanning = false }
    }

    // MARK: NetServiceDelegate

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let name = sender.name
        let host = sender.hostName ?? sender.name

        // Clean up host: remove trailing dot and Bonjour service suffixes
        var cleanHost = host.hasSuffix(".") ? String(host.dropLast()) : host
        cleanHost = cleanHost
            .replacingOccurrences(of: "._smb._tcp", with: "")
            .replacingOccurrences(of: "._afpovertcp._tcp", with: "")
            .replacingOccurrences(of: "._smb", with: "")

        Task { @MainActor in
            let nas = DiscoveredNAS(
                id: cleanHost,
                host: cleanHost,
                displayName: name,
                shares: []
            )
            if !self.discovered.contains(where: { $0.id == nas.id }) {
                self.discovered.append(nas)
            }
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        // Silently ignore unresolvable services
    }
}
