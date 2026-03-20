//
//  DiskSpaceMonitor.swift
//  BackupVault
//
//  Monitors volume capacity (total/free) and volume info for backup destinations.
//

import Foundation
import Darwin

/// Provides disk space info for a path (volume total and available).
struct DiskSpaceMonitor {
    
    struct VolumeSpace {
        let totalBytes: Int64
        let availableBytes: Int64
        let usedBytes: Int64
        var freePercent: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(availableBytes) / Double(totalBytes) * 100
        }
        var usedPercent: Double { max(0, 100 - freePercent) }
    }
    
    /// Rich volume info for dashboard: name, free space, format (APFS), connection type.
    struct VolumeInfo {
        let name: String
        let totalBytes: Int64
        let availableBytes: Int64
        let volumeFormat: String
        let connectionType: String
        
        var freeFormatted: String {
            ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
        }
    }
    
    /// Get volume space for the volume containing the given URL.
    static func space(for url: URL) -> VolumeSpace? {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        } catch {
            return nil
        }
        guard let total = values.volumeTotalCapacity, let avail = values.volumeAvailableCapacity else {
            return nil
        }
        return VolumeSpace(
            totalBytes: Int64(total),
            availableBytes: Int64(avail),
            usedBytes: Int64(total) - Int64(avail)
        )
    }
    
    /// Get volume info (name, free space, format, connection) for the volume containing the URL.
    static func volumeInfo(for url: URL, connectionLabel: String? = nil) -> VolumeInfo? {
        guard let space = space(for: url) else { return nil }
        let name: String
        if url.path.hasPrefix("/Volumes/") {
            let components = url.path.split(separator: "/")
            name = components.count >= 2 ? String(components[1]) : url.lastPathComponent
        } else {
            name = url.lastPathComponent
        }
        var format = "—"
        url.path.withCString { cPath in
            var statBuf = statfs()
            if statfs(cPath, &statBuf) == 0 {
                let fstype = statBuf.f_fstypename
                withUnsafePointer(to: fstype) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: fstype)) {
                        format = String(cString: $0)
                    }
                }
                if format.isEmpty { format = "—" }
            }
        }
        let connection = connectionLabel ?? (url.path.hasPrefix("/Volumes") ? "External" : "Local")
        return VolumeInfo(
            name: name,
            totalBytes: space.totalBytes,
            availableBytes: space.availableBytes,
            volumeFormat: format.uppercased(),
            connectionType: connection
        )
    }
    
    /// Returns true if free space is above the given percentage (e.g. 10).
    static func hasMinimumFreePercent(_ percent: Double, on url: URL) -> Bool {
        guard let space = space(for: url) else { return false }
        return space.freePercent >= percent
    }
}
