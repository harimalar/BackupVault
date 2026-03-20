//
//  BandwidthThrottle.swift
//  BackupVault
//
//  Limits transfer rate to a target bytes per second. Thread-safe.
//

import Foundation

/// Throttles throughput to a maximum bytes per second. Call consume(bytes:) before writing; sleeps if needed.
final class BandwidthThrottle: @unchecked Sendable {
    
    private let maxBytesPerSecond: Double?
    private let lock = NSLock()
    private var bytesTransferred: Int64 = 0
    private var windowStart = Date()
    
    /// nil = no throttle.
    init(maxBytesPerSecond: Double? = nil) {
        self.maxBytesPerSecond = maxBytesPerSecond
    }
    
    /// Call after transferring `bytes`. Blocks if we're ahead of the rate limit.
    func consume(bytes: Int) {
        guard let max = maxBytesPerSecond, max > 0 else { return }
        lock.lock()
        bytesTransferred += Int64(bytes)
        let elapsed = Date().timeIntervalSince(windowStart)
        let allowed = elapsed * max
        if Double(bytesTransferred) > allowed {
            let excess = Double(bytesTransferred) - allowed
            let sleepTime = excess / max
            lock.unlock()
            if sleepTime > 0.001 {
                Thread.sleep(forTimeInterval: sleepTime)
            }
            lock.lock()
        }
        if Date().timeIntervalSince(windowStart) >= 1.0 {
            windowStart = Date()
            bytesTransferred = 0
        }
        lock.unlock()
    }
}
