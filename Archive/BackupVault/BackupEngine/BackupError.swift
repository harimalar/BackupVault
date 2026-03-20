//
//  BackupError.swift
//  BackupVault
//
//  User-facing and internal backup errors.
//

import Foundation

enum BackupError: LocalizedError {
    case cannotEnumerateDirectory(URL)
    case destinationUnavailable(BackupDestination)
    case nasMountFailed(String)
    case copyFailed(URL, Error)
    case verificationFailed(URL)
    case permissionDenied(URL)
    case lowDiskSpace(URL)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .cannotEnumerateDirectory(let u): return "Cannot read folder: \(u.path)"
        case .destinationUnavailable(let d): return "Destination unavailable: \(d.name)"
        case .nasMountFailed(let m): return "Could not connect to NAS: \(m)"
        case .copyFailed(let u, let e): return "Copy failed for \(u.lastPathComponent): \(e.localizedDescription)"
        case .verificationFailed(let u): return "Verification failed: \(u.lastPathComponent)"
        case .permissionDenied(let u): return "Permission denied: \(u.path)"
        case .lowDiskSpace(let u): return "Not enough space on: \(u.path)"
        case .cancelled: return "Backup was cancelled."
        }
    }
}
