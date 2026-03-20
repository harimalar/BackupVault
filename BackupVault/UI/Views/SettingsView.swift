//
//  SettingsView.swift
//  BackupVault
//
//  Settings + full About, Privacy Policy, Terms of Use, Support.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = SettingsViewModel()
    @AppStorage("BackupVault.colorScheme") private var colorSchemeRaw = "system"
    @State private var showPrivacy = false
    @State private var showTerms = false
    @State private var showAbout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader
                preferencesPanel
                nasHelpPanel
                aboutPanel
            }
            .padding(28)
        }
        .background(canvasBackground)
        .onAppear { viewModel.reloadBackupDetails() }
        .sheet(isPresented: $showPrivacy) { PrivacyPolicySheet(isPresented: $showPrivacy) }
        .sheet(isPresented: $showTerms)   { TermsSheet(isPresented: $showTerms) }
        .sheet(isPresented: $showAbout)   { AboutSheet(isPresented: $showAbout) }
    }

    // MARK: - Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Settings")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Customize how BackupVault protects your files.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Preferences Panel

    private var preferencesPanel: some View {
        VStack(spacing: 0) {
            settingRow(
                symbol: "calendar.badge.clock",
                palette: .blue,
                title: "Backup Schedule",
                description: "When to run automatic backups"
            ) {
                Picker("", selection: Binding(
                    get: { viewModel.schedule.type },
                    set: { viewModel.schedule = BackupSchedule(type: $0, dailyTime: viewModel.schedule.dailyTime) }
                )) {
                    ForEach(BackupScheduleType.allCases, id: \.self) { Text(scheduleLabel($0)).tag($0) }
                }
                .labelsHidden().frame(width: 200).controlSize(.regular)
            }

            if viewModel.schedule.type == .daily {
                divider
                settingRow(
                    symbol: "clock",
                    palette: .indigo,
                    title: "Daily Time",
                    description: "What time the backup runs each day"
                ) {
                    DatePicker("", selection: $viewModel.schedule.dailyTime, displayedComponents: .hourAndMinute)
                        .labelsHidden().controlSize(.regular)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            divider

            settingRow(
                symbol: "checkmark.shield",
                palette: .amber,
                title: "Integrity Check",
                description: "Verify every file after copying"
            ) {
                Toggle("", isOn: $viewModel.verifyWithChecksum).toggleStyle(.switch).labelsHidden()
            }

            divider

            settingRow(
                symbol: "circle.lefthalf.filled",
                palette: .violet,
                title: "Appearance",
                description: "Light, dark, or follow system"
            ) {
                Picker("", selection: $colorSchemeRaw) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .labelsHidden().frame(width: 130).controlSize(.regular)
            }
        }
        .background(panelBackground)
        .animation(.easeInOut(duration: 0.18), value: viewModel.schedule.type)
    }

    // MARK: - About Panel

    private var aboutPanel: some View {
        VStack(spacing: 0) {
            // App identity row
            HStack(spacing: 14) {
                iconBadge(symbol: "lock.shield.fill", palette: .blue, size: 48, iconSize: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("BackupVault")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Version \(AppReleaseMetadata.versionDisplay)  ·  Made by Malar Hari")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Privacy badge
                HStack(spacing: 5) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SettingsPalette.cyan.foreground)
                    Text("100% On-Device")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsPalette.cyan.foreground)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(SettingsPalette.cyan.background)
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            divider

            // No tracking promise
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    privacyPill(symbol: "eye.slash.fill",        text: "No data collection")
                    privacyPill(symbol: "antenna.radiowaves.left.and.right.slash", text: "No tracking or analytics")
                    privacyPill(symbol: "network.slash",         text: "No internet required")
                    privacyPill(symbol: "megaphone.fill",        text: "No ads, ever")
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    privacyPill(symbol: "lock.fill",             text: "Files stay on your device")
                    privacyPill(symbol: "person.slash.fill",     text: "No account needed")
                    privacyPill(symbol: "icloud.slash.fill",     text: "No cloud, no servers")
                    privacyPill(symbol: "checkmark.shield.fill", text: "Open, auditable logic")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            divider

            // Action rows
            aboutRow(symbol: "info.circle", title: "About BackupVault") { showAbout = true }
            divider
            aboutRow(symbol: "hand.raised", title: "Privacy Policy") { showPrivacy = true }
            divider
            aboutRow(symbol: "doc.text", title: "Terms of Use") { showTerms = true }
            divider
            aboutRow(symbol: "envelope", title: "Contact Support") {
                if let url = URL(string: "mailto:rajhari@gmail.com?subject=BackupVault%20Support") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .background(panelBackground)
    }

    private var nasHelpPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                iconBadge(symbol: "externaldrive.connected.to.line.below", palette: .amber, size: 34, iconSize: 14)
                Text("NAS Tip")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            Text("If you use a network drive, macOS may ask for the NAS password once after a restart. Choose “Remember this password in my keychain” so future backups can reconnect automatically.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(panelBackground)
    }

    private func privacyPill(symbol: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SettingsPalette.violet.foreground.opacity(0.8))
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func aboutRow(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared

    private func settingRow<C: View>(
        symbol: String,
        palette: SettingsPalette,
        title: String,
        description: String,
        @ViewBuilder control: () -> C
    ) -> some View {
        HStack(spacing: 14) {
            iconBadge(symbol: symbol, palette: palette, size: 36, iconSize: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(description).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.09)).frame(height: 1)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(cardFillColor)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.10), lineWidth: 1))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.04 : 0.07), radius: colorScheme == .dark ? 4 : 14, y: colorScheme == .dark ? 2 : 8)
    }

    private var canvasBackground: Color {
        if colorScheme == .dark {
            return Color(nsColor: .windowBackgroundColor)
        }
        return Color(red: 0.965, green: 0.968, blue: 0.975)
    }

    private var cardFillColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: .controlBackgroundColor)
        }
        return Color.white.opacity(0.92)
    }

    private func iconBadge(symbol: String, palette: SettingsPalette, size: CGFloat, iconSize: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.fillTop, palette.fillBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        }
        .frame(width: size, height: size)
        .overlay {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(palette.foreground)
        }
    }

    private func scheduleLabel(_ type: BackupScheduleType) -> String {
        switch type {
        case .manual: return "Manual only"
        case .daily:  return "Daily"
        case .whenDriveConnected: return "When drive connected"
        }
    }
}

private struct SettingsPalette {
    let fillTop: Color
    let fillBottom: Color
    let stroke: Color
    let foreground: Color
    let background: Color

    static let blue = SettingsPalette(
        fillTop: Color(red: 0.20, green: 0.36, blue: 0.84).opacity(0.30),
        fillBottom: Color(red: 0.10, green: 0.17, blue: 0.39).opacity(0.72),
        stroke: Color(red: 0.35, green: 0.55, blue: 1.00).opacity(0.30),
        foreground: Color(red: 0.48, green: 0.68, blue: 1.00),
        background: Color(red: 0.35, green: 0.55, blue: 1.00).opacity(0.10)
    )

    static let indigo = SettingsPalette(
        fillTop: Color(red: 0.35, green: 0.31, blue: 0.86).opacity(0.28),
        fillBottom: Color(red: 0.17, green: 0.12, blue: 0.42).opacity(0.75),
        stroke: Color(red: 0.56, green: 0.50, blue: 1.00).opacity(0.30),
        foreground: Color(red: 0.69, green: 0.66, blue: 1.00),
        background: Color(red: 0.56, green: 0.50, blue: 1.00).opacity(0.10)
    )

    static let amber = SettingsPalette(
        fillTop: Color(red: 0.93, green: 0.58, blue: 0.16).opacity(0.26),
        fillBottom: Color(red: 0.36, green: 0.20, blue: 0.07).opacity(0.78),
        stroke: Color(red: 1.00, green: 0.68, blue: 0.26).opacity(0.30),
        foreground: Color(red: 1.00, green: 0.72, blue: 0.30),
        background: Color(red: 1.00, green: 0.72, blue: 0.30).opacity(0.10)
    )

    static let violet = SettingsPalette(
        fillTop: Color(red: 0.56, green: 0.34, blue: 0.92).opacity(0.28),
        fillBottom: Color(red: 0.23, green: 0.12, blue: 0.42).opacity(0.76),
        stroke: Color(red: 0.74, green: 0.56, blue: 1.00).opacity(0.30),
        foreground: Color(red: 0.81, green: 0.68, blue: 1.00),
        background: Color(red: 0.81, green: 0.68, blue: 1.00).opacity(0.10)
    )

    static let cyan = SettingsPalette(
        fillTop: Color(red: 0.18, green: 0.74, blue: 0.84).opacity(0.24),
        fillBottom: Color(red: 0.07, green: 0.25, blue: 0.33).opacity(0.76),
        stroke: Color(red: 0.37, green: 0.85, blue: 0.95).opacity(0.28),
        foreground: Color(red: 0.49, green: 0.90, blue: 0.97),
        background: Color(red: 0.37, green: 0.85, blue: 0.95).opacity(0.10)
    )
}

// MARK: - About Sheet

struct AboutSheet: View {
    @Binding var isPresented: Bool
    var body: some View {
        legalSheet(title: "About BackupVault", isPresented: $isPresented) {
            Group {
                aboutSection("What is BackupVault?", """
BackupVault is a private, local backup application for macOS built by Malar Hari, an independent developer. It copies your selected folders to an external drive or network location on a schedule you control.

There are no subscriptions, no accounts, no cloud services, and no telemetry of any kind.
""")
                aboutSection("Developer", """
BackupVault is developed and maintained by Malar Hari, an independent software developer.

For support, questions, or feedback, contact:
rajhari@gmail.com
""")
                aboutSection("Open Source & Transparency", """
BackupVault's backup logic is straightforward: it copies files from your source folders to a destination directory using standard macOS file APIs. No proprietary formats, no encrypted vaults that lock you in. Your files are always accessible directly from Finder.
""")
                aboutSection("Version", "BackupVault \(AppReleaseMetadata.versionDisplay)\nRequires \(AppReleaseMetadata.minimumOSDisplay).\n© 2026 Malar Hari. All rights reserved.")
            }
        }
    }
}

// MARK: - Privacy Policy Sheet

struct PrivacyPolicySheet: View {
    @Binding var isPresented: Bool
    var body: some View {
        legalSheet(title: "Privacy Policy", isPresented: $isPresented) {
            Group {
                aboutSection("Effective Date", "1 January 2026")
                aboutSection("Our Commitment", """
BackupVault is designed from the ground up to protect your privacy. This Privacy Policy explains what data BackupVault handles and, more importantly, what it does not do.
""")
                aboutSection("Data We Do NOT Collect", """
BackupVault does not collect, store, transmit, or share any of the following:

• Personal information (name, email, account details)
• File names, file contents, or metadata of your backed-up files
• Usage statistics, crash reports, or analytics
• Device identifiers, IP addresses, or location data
• Any data from your computer for any purpose

We have no servers that receive data from your device. We have no database of users. We do not know you use BackupVault.
""")
                aboutSection("Data Stored On Your Device", """
BackupVault stores only the following data locally on your Mac, in macOS standard storage (UserDefaults and Keychain):

• Your selected source folder paths (as security-scoped bookmarks)
• Your selected backup destination path (as a security-scoped bookmark)
• Your backup schedule preference
• Your app appearance preference (light/dark/system)
• A history of backup run metadata (timestamps, file counts) for display in the app

This data never leaves your device. It is used solely to operate the app.
""")
                aboutSection("No Advertising", """
BackupVault contains no advertising of any kind. We do not work with advertising networks. We do not use your data to serve ads. We do not sell your data. Ever.
""")
                aboutSection("No Third-Party SDKs or Trackers", """
BackupVault contains no third-party SDKs, analytics libraries, crash reporting tools, or tracking pixels. The app makes no outbound network requests except when you explicitly configure a NAS destination, in which case it connects only to the server address you provide.
""")
                aboutSection("Network Access", """
BackupVault requests network access solely to support SMB network-attached storage (NAS) connections. This connection goes only to the server you configure. No other network requests are made by the app.
""")
                aboutSection("Children's Privacy", """
BackupVault does not knowingly collect data from children or any other users. As stated above, BackupVault collects no data at all.
""")
                aboutSection("Changes to This Policy", """
If this policy is updated, the new version will be included in a future app update. We will not change our core commitment: BackupVault will never collect your data.
""")
                aboutSection("Contact", "For privacy questions, contact:\nrajhari@gmail.com")
            }
        }
    }
}

// MARK: - Terms of Use Sheet

struct TermsSheet: View {
    @Binding var isPresented: Bool
    var body: some View {
        legalSheet(title: "Terms of Use", isPresented: $isPresented) {
            Group {
                aboutSection("Effective Date", "1 January 2026")
                aboutSection("Acceptance", """
By downloading or using BackupVault, you agree to these Terms of Use. If you do not agree, do not use the app.
""")
                aboutSection("License", """
BackupVault is licensed to you, not sold. Malar Hari grants you a personal, non-transferable, non-exclusive licence to use BackupVault on any Mac you own or control, subject to these Terms.

You may not:
• Reverse-engineer, decompile, or disassemble the app
• Remove or alter any copyright or proprietary notices
• Distribute or resell the app or any derivative work
""")
                aboutSection("Your Data & Responsibility", """
BackupVault copies files from your selected source folders to a destination you choose. You are solely responsible for:

• Choosing appropriate source folders and destinations
• Ensuring sufficient storage space on your destination
• Verifying the accuracy and completeness of your backups
• Maintaining physical security of your backup drives

BackupVault is a tool to assist with backup; it does not guarantee that all files will be recoverable in all circumstances.
""")
                aboutSection("No Warranty", """
BackupVault is provided "as is" without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement.

We do not warrant that the app will be error-free, uninterrupted, or free from data loss. You assume all risk associated with the use of BackupVault and any loss of data.
""")
                aboutSection("Limitation of Liability", """
To the maximum extent permitted by law, Malar Hari shall not be liable for any indirect, incidental, special, consequential, or punitive damages, including loss of data, arising out of or in connection with your use of BackupVault, even if advised of the possibility of such damages.

Our total liability to you for any claims arising from your use of BackupVault shall not exceed the amount you paid for the app (which may be zero if the app is free).
""")
                aboutSection("Governing Law", """
These Terms are governed by the laws of the jurisdiction in which Malar Hari is resident, without regard to conflict of law principles. Any disputes shall be resolved in the courts of that jurisdiction.
""")
                aboutSection("Changes to Terms", """
We may update these Terms from time to time. Continued use of BackupVault after changes are published constitutes acceptance of the new Terms.
""")
                aboutSection("Contact", "For legal enquiries, contact:\nrajhari@gmail.com")
            }
        }
    }
}

// MARK: - Shared Legal Sheet Builder

private func legalSheet<Content: View>(title: String, isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
        // Header
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Spacer()
            Button {
                isPresented.wrappedValue = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)

        Divider()

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(24)
        }
    }
    .frame(width: 560, height: 620)
    .background(Color(nsColor: .windowBackgroundColor))
}

private func aboutSection(_ heading: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(heading)
            .font(.system(size: 13, weight: .bold))
        Text(body)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 20)
}

private enum AppReleaseMetadata {
    static var versionDisplay: String {
        let bundle = Bundle.main
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String

        switch (marketing, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty && version != build:
            return "\(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return version
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "1.0"
        }
    }

    static let minimumOSDisplay = "macOS 13.0 or later"
}
