//
//  KeychainService.swift
//  BackupVault
//
//  Securely stores NAS credentials in macOS Keychain (never plaintext).
//

import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()
    
    private let serviceName = "com.BackupVault.app"
    
    private init() {}
    
    /// Save password for a given destination ID (NAS).
    func setPassword(_ password: String, forDestinationID destinationID: UUID) throws {
        let data = password.data(using: .utf8)!
        let key = keychainKey(for: destinationID)
        
        // Delete existing so we can add (SecItemAdd fails if item exists)
        try? deletePassword(forDestinationID: destinationID)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.failedToSave(status)
        }
    }

    /// Save app-local and system SMB credentials for a NAS destination.
    func setNASPassword(_ password: String, for destination: BackupDestination) throws {
        try setPassword(password, forDestinationID: destination.id)

        guard let username = destination.nasUsername, !username.isEmpty else { return }

        let share = destination.nasShare
        for server in smbServerAliases(for: destination.nasHost) {
            try saveSystemSMBPassword(password, server: server, share: share, username: username)
        }
    }
    
    /// Retrieve password for a destination.
    func getPassword(forDestinationID destinationID: UUID) throws -> String? {
        let key = keychainKey(for: destinationID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.failedToRead(status)
        }
        return String(data: data, encoding: .utf8)
    }
    
    /// Remove stored password for a destination.
    func deletePassword(forDestinationID destinationID: UUID) throws {
        let key = keychainKey(for: destinationID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.failedToDelete(status)
        }
    }

    func deleteNASPassword(for destination: BackupDestination) throws {
        try deletePassword(forDestinationID: destination.id)

        guard let username = destination.nasUsername, !username.isEmpty else { return }

        let share = destination.nasShare
        for server in smbServerAliases(for: destination.nasHost) {
            try deleteSystemSMBPassword(server: server, share: share, username: username)
        }
    }

    private func keychainKey(for id: UUID) -> String {
        "nas-password-\(id.uuidString)"
    }

    private func smbServerAliases(for rawHost: String?) -> [String] {
        guard let rawHost, !rawHost.isEmpty else { return [] }

        let trimmed = rawHost
            .replacingOccurrences(of: "smb://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        let normalized = trimmed
            .replacingOccurrences(of: "._smb._tcp", with: "")
            .replacingOccurrences(of: "._afpovertcp._tcp", with: "")
            .replacingOccurrences(of: "._smb", with: "")

        var aliases = [trimmed, normalized]
        if normalized.hasSuffix(".local") {
            aliases.append(String(normalized.dropLast(".local".count)))
        } else if !normalized.contains(".") {
            aliases.append("\(normalized).local")
        }

        var seen = Set<String>()
        return aliases
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private func saveSystemSMBPassword(_ password: String, server: String, share: String?, username: String) throws {
        let data = password.data(using: .utf8)!
        let path = normalizedSMBPath(for: share)

        try? deleteSystemSMBPassword(server: server, share: share, username: username)

        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrAccount as String: username,
            kSecAttrProtocol as String: kSecAttrProtocolSMB,
            kSecAttrPath as String: path,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.failedToSave(status)
        }

        let serverOnlyQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrAccount as String: username,
            kSecAttrProtocol as String: kSecAttrProtocolSMB,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let serverOnlyStatus = SecItemAdd(serverOnlyQuery as CFDictionary, nil)
        guard serverOnlyStatus == errSecSuccess || serverOnlyStatus == errSecDuplicateItem else {
            throw KeychainError.failedToSave(serverOnlyStatus)
        }
    }

    private func deleteSystemSMBPassword(server: String, share: String?, username: String) throws {
        let path = normalizedSMBPath(for: share)

        let queries: [[String: Any]] = [
            [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: server,
                kSecAttrAccount as String: username,
                kSecAttrProtocol as String: kSecAttrProtocolSMB,
                kSecAttrPath as String: path
            ],
            [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: server,
                kSecAttrAccount as String: username,
                kSecAttrProtocol as String: kSecAttrProtocolSMB
            ]
        ]

        for query in queries {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw KeychainError.failedToDelete(status)
            }
        }
    }

    private func normalizedSMBPath(for share: String?) -> String {
        let cleanShare = (share ?? "")
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "/Volumes/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return cleanShare.isEmpty ? "/" : "/\(cleanShare)"
    }
}

enum KeychainError: LocalizedError {
    case failedToSave(OSStatus)
    case failedToRead(OSStatus)
    case failedToDelete(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .failedToSave(let s): return "Could not save credential: \(s)"
        case .failedToRead(let s): return "Could not read credential: \(s)"
        case .failedToDelete(let s): return "Could not delete credential: \(s)"
        }
    }
}
