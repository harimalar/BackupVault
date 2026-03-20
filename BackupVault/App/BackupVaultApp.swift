//
//  BackupVaultApp.swift
//  BackupVault
//
//  App entry point + MenuBarManager — kept in one file so Xcode always
//  includes both in the target without any manual file-membership step.
//

import SwiftUI
import AppKit
import UserNotifications

// MARK: - App Entry Point

@main
struct BackupVaultApp: App {
    @AppStorage("BackupVault.colorScheme") private var colorSchemeRaw = "system"
    @StateObject private var sharedViewModel = BackupViewModel()

    var preferredColorScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(sharedBackupViewModel: sharedViewModel)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    MenuBarController.shared.setup(with: sharedViewModel)
                }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Backup") {
                Button("Run Backup Now") {
                    sharedViewModel.lastCompletedSnapshotURL = nil
                    sharedViewModel.startBackup()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!sharedViewModel.canStartBackup)

                Button("Stop Backup") {
                    sharedViewModel.cancelBackup()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!sharedViewModel.isBackingUp)
            }
        }
    }
}

// MARK: - Menu Bar Controller

/// Manages the macOS status bar icon, live health score, and backup notifications.
/// Renamed MenuBarController to avoid any cached symbol conflicts.
final class MenuBarController: @unchecked Sendable {

    static let shared = MenuBarController()
    private init() {}

    private var statusItem: NSStatusItem?
    private weak var viewModel: BackupViewModel?
    private var timer: Timer?
    private var lastScore: Int = -1
    private var wasBackingUp = false

    // MARK: Setup

    @MainActor
    func setup(with vm: BackupViewModel) {
        self.viewModel = vm
        createStatusItem()
        requestNotificationPermission()
        startPolling()
    }

    @MainActor
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = templateImage("shield.lefthalf.filled")
        button.toolTip = "BackupVault"
        button.action = #selector(handleClick)
        button.target = self
    }

    // MARK: Icon

    @MainActor
    func updateHealthScore(_ score: Int) {
        lastScore = score
        refreshIcon()
    }

    @MainActor
    private func refreshIcon() {
        guard let button = statusItem?.button, let vm = viewModel else { return }

        if vm.isBackingUp {
            button.image = templateImage("arrow.triangle.2.circlepath")
            button.toolTip = "BackupVault — Backup running…"
        } else if vm.errorMessage != nil {
            button.image = coloredImage("exclamationmark.shield.fill", color: .systemRed)
            button.toolTip = "BackupVault — Check required"
        } else if lastScore >= 80 {
            button.image = coloredImage("shield.lefthalf.filled", color: .systemGreen)
            button.toolTip = "BackupVault — Protected (\(lastScore)/100)"
        } else if lastScore >= 50 {
            button.image = coloredImage("shield.lefthalf.filled", color: .systemOrange)
            button.toolTip = "BackupVault — Needs attention (\(lastScore)/100)"
        } else if lastScore >= 0 {
            button.image = coloredImage("shield.slash.fill", color: .systemRed)
            button.toolTip = "BackupVault — At risk (\(lastScore)/100)"
        } else {
            button.image = templateImage("shield.lefthalf.filled")
            button.toolTip = "BackupVault"
        }
    }

    private func templateImage(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }

    private func coloredImage(_ name: String, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let copy = base.copy() as! NSImage
        copy.isTemplate = false
        copy.lockFocus()
        color.set()
        NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
    }

    // MARK: Click → Menu

    @objc @MainActor
    private func handleClick() {
        guard let vm = viewModel else { return }

        let menu = NSMenu()

        // Status line
        let statusTitle: String
        if vm.isBackingUp {
            let copied = vm.progress?.filesCopied ?? 0
            let total  = vm.progress?.filesToCopy  ?? 0
            statusTitle = total > 0 ? "Backing up… \(copied)/\(total) files" : "Backup running…"
        } else {
            let runs = DestinationStore.shared.loadBackupRuns()
                .filter { $0.state == .completed }
                .max { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) }
            if let last = runs {
                let f = RelativeDateTimeFormatter()
                f.unitsStyle = .abbreviated
                statusTitle = "Last backup \(f.localizedString(for: last.completedAt ?? last.startedAt, relativeTo: Date()))"
            } else {
                statusTitle = "No backups yet"
            }
        }

        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        if vm.isBackingUp {
            let stop = NSMenuItem(title: "Stop Backup", action: #selector(stopBackup), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        } else {
            let run = NSMenuItem(title: "Run Backup Now", action: #selector(runBackup), keyEquivalent: "")
            run.target = self
            run.isEnabled = vm.canStartBackup
            menu.addItem(run)
        }

        if vm.lastCompletedSnapshotURL != nil {
            let finder = NSMenuItem(title: "Open Last Backup in Finder", action: #selector(openFinder), keyEquivalent: "")
            finder.target = self
            menu.addItem(finder)
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open BackupVault", action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        self.statusItem?.menu = menu
        self.statusItem?.button?.performClick(nil)
        self.statusItem?.menu = nil
    }

    @objc @MainActor private func runBackup() {
        viewModel?.lastCompletedSnapshotURL = nil
        viewModel?.startBackup()
        openWindow()
    }

    @objc @MainActor private func stopBackup() { viewModel?.cancelBackup() }

    @objc @MainActor private func openFinder() { viewModel?.openSelectedDestinationFolder() }

    @objc @MainActor private func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    // MARK: Polling

    @MainActor
    private func startPolling() {
        let controller = self
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in controller.poll() }
        }
    }

    @MainActor
    private func poll() {
        guard let vm = viewModel else { return }
        let isRunning = vm.isBackingUp
        let hasError  = vm.errorMessage != nil && !isRunning

        // Detect completion / failure
        if wasBackingUp && !isRunning {
            if hasError {
                notify(title: "Backup Failed",
                       body: vm.errorMessage ?? "An error occurred.",
                       success: false)
            } else {
                let count = vm.progress?.filesCopied ?? 0
                notify(title: "Backup Complete ✓",
                       body: count > 0 ? "\(count) files protected." : "Your files are protected.",
                       success: true)
            }
        }
        wasBackingUp = isRunning
        refreshIcon()
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String, success: Bool) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body  = body
        c.sound = success ? .default : UNNotificationSound(named: UNNotificationSoundName("Basso"))
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
