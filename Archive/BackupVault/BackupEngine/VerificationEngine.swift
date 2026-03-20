//
//  VerificationEngine.swift
//  BackupVault
//
//  Verifies backup integrity: basic (file size) and advanced (SHA256).
//

import Foundation

/// Result of verifying one file.
enum FileVerificationResult {
    case ok
    case sizeMismatch(expected: Int64, actual: Int64)
    case checksumMismatch
    case error(Error)
}

/// Verifies copied files: size comparison and optional SHA256.
final class VerificationEngine {
    
    private let fileManager = FileManager.default
    
    /// Verify a single file: size must match; if useSHA256, compute and optionally compare.
    func verify(
        fileAt url: URL,
        expectedSize: Int64,
        expectedSHA256: String? = nil,
        useSHA256: Bool
    ) -> FileVerificationResult {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return .error(VerificationError.cannotReadFile)
        }
        if size != expectedSize {
            return .sizeMismatch(expected: expectedSize, actual: size)
        }
        if useSHA256 {
            if let expected = expectedSHA256 {
                do {
                    let match = try FileHasher.verify(url: url, expectedSHA256Hex: expected)
                    return match ? .ok : .checksumMismatch
                } catch {
                    return .error(error)
                }
            } else {
                do {
                    _ = try FileHasher.sha256(url: url)
                    return .ok
                } catch {
                    return .error(error)
                }
            }
        }
        return .ok
    }
    
    /// Verify multiple files (e.g. after copy); returns number of failures.
    func verifyBatch(
        files: [(url: URL, expectedSize: Int64)],
        useSHA256: Bool,
        onProgress: ((Int, Int) -> Void)? = nil
    ) -> (passed: Int, failed: Int) {
        var passed = 0
        var failed = 0
        for (i, f) in files.enumerated() {
            let r = verify(fileAt: f.url, expectedSize: f.expectedSize, expectedSHA256: nil, useSHA256: useSHA256)
            if case .ok = r { passed += 1 } else { failed += 1 }
            onProgress?(i + 1, files.count)
        }
        return (passed, failed)
    }
}

enum VerificationError: LocalizedError {
    case cannotReadFile
    var errorDescription: String? { "Could not read file for verification." }
}
