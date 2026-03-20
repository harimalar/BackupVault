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
    
    private func keychainKey(for id: UUID) -> String {
        "nas-password-\(id.uuidString)"
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
