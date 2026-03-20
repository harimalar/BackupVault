//
//  VolumeObserver.swift
//  BackupVault
//
//  Detects when an external backup drive is connected and can trigger a notification.
//

import Foundation
import AppKit

/// Observes volume mount/unmount and matches against known backup destinations (external drives).
final class VolumeObserver: ObservableObject {
    
    static let shared = VolumeObserver()
    
    @Published var lastConnectedVolumeURL: URL?
    @Published var showDriveConnectedAlert = false
    
    private var mountedDestinations: Set<UUID> = []
    
    private init() {
        let workspace = NSWorkspace.shared
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(volumesDidChange),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(volumesDidChange),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
    }
    
    @objc private func volumesDidChange(_ notification: Notification) {
        guard notification.name == NSWorkspace.didMountNotification,
              let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else {
            return
        }
        
        let destinations = DestinationStore.shared.loadDestinations()
        let externalDestinations = destinations.filter { $0.type == .externalDrive }
        
        for dest in externalDestinations {
            if dest.path.path.hasPrefix(volumeURL.path) || volumeURL.path.hasPrefix(dest.path.path) {
                DispatchQueue.main.async {
                    self.lastConnectedVolumeURL = volumeURL
                    self.showDriveConnectedAlert = true
                    self.mountedDestinations.insert(dest.id)
                }
                break
            }
        }
    }
    
    func clearDriveAlert() {
        showDriveConnectedAlert = false
        lastConnectedVolumeURL = nil
    }
}
