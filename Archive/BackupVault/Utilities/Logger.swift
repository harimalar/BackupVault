//
//  Logger.swift
//  BackupVault
//
//  Writes backup logs to backup.log (files copied, errors, verification results).
//

import Foundation
import os.log

/// Logs backup activity to backup.log in Application Support.
final class Logger {
    static let shared = Logger()
    
    private let logFileName = "backup.log"
    private let queue = DispatchQueue(label: "com.backupvault.logger", qos: .utility)
    private var logURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BackupVault", isDirectory: true)
            .appendingPathComponent(logFileName)
    }
    
    private init() {
        ensureLogDirectory()
    }
    
    private func ensureLogDirectory() {
        guard let url = logURL?.deletingLastPathComponent() else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    
    private func write(_ message: String, level: String = "INFO") {
        queue.async { [weak self] in
            guard let url = self?.logURL else { return }
            let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    guard let handle = try? FileHandle(forWritingTo: url) else { return }
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? data.write(to: url)
                }
            }
        }
    }
    
    func info(_ message: String) { write(message, level: "INFO") }
    func error(_ message: String) { write(message, level: "ERROR") }
    func warning(_ message: String) { write(message, level: "WARN") }
    
    func logFilesCopied(count: Int, bytes: Int64, duration: TimeInterval) {
        info("Backup completed: \(count) files, \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)), \(Int(duration))s")
    }
    
    func logVerificationResult(success: Bool, fileCount: Int, message: String? = nil) {
        if success {
            info("Verification passed: \(fileCount) files checked")
        } else {
            error("Verification failed: \(message ?? "unknown") (\(fileCount) files)")
        }
    }
    
    func logError(_ error: Error, context: String = "") {
        self.error("\(context.isEmpty ? "" : context + " ")\(error.localizedDescription)")
    }
}
