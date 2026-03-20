//
//  BackupExclusions.swift
//  BackupVault
//
//  User-defined exclusion rules: folder names and file patterns (e.g. node_modules, *.tmp).
//

import Foundation

/// Exclusion rules for backup (exclude folders by name, files by pattern).
struct BackupExclusions: Codable, Equatable {
    /// Folder names to exclude (e.g. "node_modules", ".cache"). Case-insensitive.
    var excludedFolderNames: [String]
    /// File patterns: "*.tmp", "*.log", or extension ".ds_store". Case-insensitive.
    var excludedFilePatterns: [String]
    
    init(excludedFolderNames: [String] = [], excludedFilePatterns: [String] = []) {
        self.excludedFolderNames = excludedFolderNames
        self.excludedFilePatterns = excludedFilePatterns
    }
    
    /// Default common exclusions.
    static var `default`: BackupExclusions {
        BackupExclusions(
            excludedFolderNames: ["node_modules", ".cache", ".git", "build", "DerivedData"],
            excludedFilePatterns: ["*.tmp", "*.temp", "*.log", ".DS_Store"]
        )
    }
    
    /// Check if a directory (last path component) should be excluded.
    func shouldExcludeFolder(name: String) -> Bool {
        let lower = name.lowercased()
        return excludedFolderNames.contains { $0.lowercased() == lower }
    }
    
    /// Check if a file (name or relative path) should be excluded.
    func shouldExcludeFile(name: String) -> Bool {
        let fileName = (name as NSString).lastPathComponent.lowercased()
        for pattern in excludedFilePatterns {
            let p = pattern.lowercased().trimmingCharacters(in: .whitespaces)
            if p.hasPrefix("*.") {
                let ext = String(p.dropFirst(2))
                if fileName.hasSuffix("." + ext) || fileName == ext { return true }
            } else if p.hasPrefix(".") || p.contains(".") {
                if fileName == p || fileName.hasSuffix(p) { return true }
            } else {
                if fileName == p { return true }
            }
        }
        return false
    }
}
