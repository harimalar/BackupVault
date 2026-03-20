//
//  FileHasher.swift
//  BackupVault
//
//  SHA256 hashing for file integrity verification.
//

import Foundation
import CryptoKit

/// Computes SHA256 hash of a file (streaming, low memory for large files).
enum FileHasher {
    
    static func sha256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 64 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    
    /// Compare file at URL with expected SHA256 hex string.
    static func verify(url: URL, expectedSHA256Hex: String) throws -> Bool {
        let actual = try sha256(url: url)
        return actual.lowercased() == expectedSHA256Hex.lowercased()
    }
}
