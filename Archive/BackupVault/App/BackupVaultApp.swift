//
//  BackupVaultApp.swift
//  BackupVault
//
//  App entry point. Minimal backup for Mac: folders → destination → Start.
//

import SwiftUI

@main
struct BackupVaultApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 520, minHeight: 420)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
