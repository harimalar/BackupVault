//
//  AtomicFileWriter.swift
//  BackupVault
//
//  Writes data to a temp file then atomically replaces the target. Crash-safe: target is never partially written.
//

import Foundation

enum AtomicFileWriter {
    
    /// Suffix for temporary files (same directory as destination for atomic rename).
    private static let tempSuffix = ".backupvault_tmp"
    
    /// Write data atomically: write to dest + tempSuffix, then replace dest. Existing file is never corrupted.
    static func write(_ data: Data, to destURL: URL) throws {
        let dir = destURL.deletingLastPathComponent()
        let tempURL = dir.appendingPathComponent(destURL.lastPathComponent + tempSuffix)
        try data.write(to: tempURL)
        try (tempURL as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        if FileManager.default.fileExists(atPath: destURL.path) {
            var result: NSURL?
            try FileManager.default.replaceItem(at: destURL, withItemAt: tempURL, backupItemName: nil, options: .usingNewMetadataOnly, resultingItemURL: &result)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: destURL)
        }
    }
    
    /// Create a temp URL in the same directory as destination (for stream writes). Caller must move/replace when done.
    static func tempURL(forDestination destURL: URL) -> URL {
        destURL.deletingLastPathComponent().appendingPathComponent(destURL.lastPathComponent + tempSuffix)
    }
    
    /// Atomically replace destination with the file at tempURL. Removes tempURL on success.
    static func replace(dest: URL, withTemp tempURL: URL) throws {
        if FileManager.default.fileExists(atPath: dest.path) {
            var result: NSURL?
            try FileManager.default.replaceItem(at: dest, withItemAt: tempURL, backupItemName: nil, options: .usingNewMetadataOnly, resultingItemURL: &result)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: dest)
        }
    }
}
