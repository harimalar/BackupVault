//
//  BackupDestination.swift
//  BackupVault
//
//  Represents where backups are stored: external drive or NAS (SMB).
//

import Foundation

/// Type of backup destination.
enum DestinationType: String, Codable, CaseIterable {
    case externalDrive = "External Drive"
    case nas = "Network (NAS)"
}

/// A backup destination: either a local volume or an SMB share.
struct BackupDestination: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var type: DestinationType
    var path: URL
    
    // NAS-specific (stored separately in Keychain; not in Codable payload)
    var nasHost: String?
    var nasShare: String?
    var nasUsername: String?
    // Password never stored in model; use KeychainService
    
    init(
        id: UUID = UUID(),
        name: String,
        type: DestinationType,
        path: URL,
        nasHost: String? = nil,
        nasShare: String? = nil,
        nasUsername: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
        self.nasHost = nasHost
        self.nasShare = nasShare
        self.nasUsername = nasUsername
    }
    
    /// Base URL for this destination (e.g. volume root or mounted SMB share).
    var baseURL: URL { path }
    
    /// Whether this destination is currently available (mounted / reachable).
    var isAvailable: Bool {
        if type == .externalDrive {
            return path.hasDirectoryPath && (try? path.checkResourceIsReachable()) == true
        }
        // NAS: we consider it available if we have valid config; actual mount check is in BackupEngine
        return (nasHost != nil && !(nasHost?.isEmpty ?? true))
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: BackupDestination, rhs: BackupDestination) -> Bool { lhs.id == rhs.id }
}
