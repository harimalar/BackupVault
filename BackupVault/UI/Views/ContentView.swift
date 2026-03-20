//
//  ContentView.swift
//  BackupVault
//
//  Premium redesign: immersive sidebar with gradient accents and refined typography.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .dashboard
    @StateObject private var volumeObserver = VolumeObserver.shared
    @ObservedObject var sharedBackupViewModel: BackupViewModel
    @AppStorage("BackupVault.onboardingComplete") private var onboardingComplete = false
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224)
        } detail: {
            detailView(for: selection ?? .dashboard)
                .frame(minWidth: detailMinimumWidth(for: selection ?? .dashboard), maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                viewModel: sharedBackupViewModel,
                isPresented: $showOnboarding,
                onCompleted: {
                    onboardingComplete = true
                }
            )
                .interactiveDismissDisabled()
        }
        .onAppear {
            if !onboardingComplete {
                showOnboarding = true
            }
        }
        .alert("Backup drive connected", isPresented: $volumeObserver.showDriveConnectedAlert) {
            Button("Run Backup") {
                selection = .dashboard
                sharedBackupViewModel.startBackup()
                volumeObserver.clearDriveAlert()
            }
            Button("Later", role: .cancel) {
                volumeObserver.clearDriveAlert()
            }
        } message: {
            Text("A backup destination drive was detected. Start a backup now?")
        }
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem) -> some View {
        switch item {
        case .dashboard:
            DashboardView(
                backupViewModel: sharedBackupViewModel,
                onConfigureBackup: { selection = .backup }
            )
        case .backup:
            BackupView(viewModel: sharedBackupViewModel)
        case .restore:
            RestoreView()
        case .settings:
            SettingsView()
        }
    }

    private func detailMinimumWidth(for item: SidebarItem) -> CGFloat {
        switch item {
        case .dashboard:
            return 760
        case .backup:
            return 720
        case .restore:
            return 660
        case .settings:
            return 620
        }
    }
}

// MARK: - Premium Sidebar

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            // App identity header
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.28, green: 0.50, blue: 1.0),
                                    Color(red: 0.14, green: 0.30, blue: 0.82)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                        .shadow(color: Color(red: 0.28, green: 0.50, blue: 1.0).opacity(0.4), radius: 6, y: 3)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("BackupVault")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("File Protection")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
                .padding(.horizontal, 10)

            // Navigation items
            VStack(spacing: 3) {
                ForEach(SidebarItem.allCases) { item in
                    SidebarRowView(item: item, isSelected: selection == item) {
                        selection = item
                    }
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 8)

            Spacer()

            // Footer badge
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
                .padding(.horizontal, 10)

            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.78))
                Text("Local-only · No accounts · No cloud")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.38))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct SidebarRowView: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: item.iconColors.map {
                                    $0.opacity(isSelected ? 0.24 : (isHovered ? 0.16 : 0.11))
                                },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(item.accentColor.opacity(isSelected ? 0.30 : 0.12), lineWidth: 1)
                        )
                        .frame(width: 28, height: 28)
                        .shadow(
                            color: item.accentColor.opacity(isSelected ? 0.28 : (isHovered ? 0.14 : 0.0)),
                            radius: isSelected ? 7 : 4,
                            y: 2
                        )
                    Image(systemName: item.icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: item.iconColors.map { $0.opacity(isSelected ? 1.0 : 0.92) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                Text(item.title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected
                          ? item.accentColor.opacity(0.09)
                          : (isHovered ? Color.primary.opacity(0.045) : Color.clear))
            )
            .overlay(
                HStack {
                    Spacer()
                    if isSelected {
                        Capsule()
                            .fill(item.accentColor)
                            .frame(width: 3, height: 18)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Sidebar Item

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case backup    = "Backup Setup"
    case restore   = "Restore"
    case settings  = "Settings"

    var id: String { rawValue }
    var title: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "shield.lefthalf.filled"
        case .backup:    return "externaldrive.fill.badge.plus"
        case .restore:   return "arrow.uturn.backward.circle.fill"
        case .settings:  return "gearshape.fill"
        }
    }

    var accentColor: Color {
        iconColors[0]
    }

    var iconColors: [Color] {
        switch self {
        case .dashboard:
            return [
                Color(red: 0.36, green: 0.62, blue: 1.0),
                Color(red: 0.16, green: 0.37, blue: 0.92)
            ]
        case .backup:
            return [
                Color(red: 1.0, green: 0.63, blue: 0.20),
                Color(red: 0.94, green: 0.39, blue: 0.08)
            ]
        case .restore:
            return [
                Color(red: 0.32, green: 0.85, blue: 0.61),
                Color(red: 0.10, green: 0.62, blue: 0.42)
            ]
        case .settings:
            return [
                Color(red: 0.78, green: 0.52, blue: 1.0),
                Color(red: 0.52, green: 0.31, blue: 0.92)
            ]
        }
    }
}

// MARK: - Onboarding (inlined to ensure Xcode target membership)

struct OnboardingView: View {
    @ObservedObject var viewModel: BackupViewModel
    @Binding var isPresented: Bool
    let onCompleted: () -> Void
    @State private var step = 0
    @State private var showFolderPicker = false
    @State private var showDrivePicker = false
    @State private var showNASInOnboarding = false
    @State private var animateIn = false

    private let blue   = Color(red: 0.28, green: 0.50, blue: 1.0)
    private let green  = Color(red: 0.17, green: 0.73, blue: 0.51)
    private let orange = Color(red: 0.97, green: 0.50, blue: 0.15)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(i <= step ? blue : Color.primary.opacity(0.12))
                        .frame(width: i == step ? 24 : 8, height: 6)
                        .animation(.spring(response: 0.4), value: step)
                }
            }
            .padding(.top, 28).padding(.bottom, 24)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: foldersStep
                case 2: destinationStep
                default: EmptyView()
                }
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 16)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: animateIn)

            Spacer()

            HStack {
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1; bounce() } }
                        .controlSize(.large)
                } else {
                    Spacer().frame(width: 80)
                }
                Spacer()
                Button(action: advance) {
                    Text(nextLabel).frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(.horizontal, 32).padding(.bottom, 28)
        }
        .frame(width: 520, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls { _ = url.startAccessingSecurityScopedResource(); viewModel.addFolder(url) }
            }
        }
        .fileImporter(isPresented: $showDrivePicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let accessed = url.startAccessingSecurityScopedResource()
                viewModel.addDestination(BackupDestination(name: url.lastPathComponent, type: .externalDrive, path: url), password: nil)
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
        }
        .onAppear { bounce() }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(blue.opacity(0.10)).frame(width: 100, height: 100)
                Image(systemName: "lock.shield.fill").font(.system(size: 48, weight: .semibold)).foregroundStyle(blue)
            }
            VStack(spacing: 8) {
                Text("Welcome to BackupVault")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Your files, protected privately on your own drive.\nNo cloud, no accounts, no tracking — ever.")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineSpacing(3)
            }
            HStack(spacing: 28) {
                featurePill("hand.raised.fill",   "100% Private",  green)
                featurePill("externaldrive.fill",  "Your Drive",   orange)
                featurePill("bolt.fill",           "Fast & Simple", blue)
            }.padding(.top, 4)
        }.padding(.horizontal, 40)
    }

    private var foldersStep: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(orange.opacity(0.10)).frame(width: 100, height: 100)
                Image(systemName: "folder.fill.badge.plus").font(.system(size: 44, weight: .semibold)).foregroundStyle(orange)
            }
            VStack(spacing: 6) {
                Text("What do you want to protect?").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Add the folders BackupVault should back up.")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            }
            if viewModel.sourceFolders.isEmpty {
                Button { showFolderPicker = true } label: {
                    Label("Choose Folders…", systemImage: "plus.circle.fill").frame(minWidth: 200)
                }.buttonStyle(.borderedProminent).tint(orange).controlSize(.large)
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.sourceFolders.prefix(3), id: \.path) { url in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill").foregroundStyle(.yellow).font(.system(size: 13))
                            Text(url.lastPathComponent).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button(role: .destructive) { viewModel.removeFolder(url) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                    }
                    if viewModel.sourceFolders.count > 3 {
                        Text("+ \(viewModel.sourceFolders.count - 3) more").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Button("Add More Folders…") { showFolderPicker = true }.controlSize(.regular).padding(.top, 4)
                }.frame(maxWidth: 340)
            }
        }.padding(.horizontal, 40)
    }

    private var destinationStep: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(green.opacity(0.10)).frame(width: 80, height: 80)
                Image(systemName: "externaldrive.fill").font(.system(size: 36, weight: .semibold)).foregroundStyle(green)
            }
            VStack(spacing: 4) {
                Text("Where should we store it?").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Connect an external drive or NAS.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
            if viewModel.destinations.isEmpty {
                HStack(spacing: 10) {
                    Button { showDrivePicker = true } label: {
                        Label("External Drive", systemImage: "externaldrive.badge.plus")
                    }.buttonStyle(.borderedProminent).tint(green).controlSize(.large)
                    Button { showNASInOnboarding = true } label: {
                        Label("Network Drive", systemImage: "network")
                    }.controlSize(.large)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.destinations) { dest in
                        HStack(spacing: 10) {
                            Image(systemName: dest.type == .nas ? "network" : "externaldrive.fill")
                                .foregroundStyle(green).font(.system(size: 13))
                            Text(dest.name).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if viewModel.selectedDestination?.id == dest.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(green)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                    }
                    Button("Add Another") { showDrivePicker = true }
                        .controlSize(.small).padding(.top, 4)
                }.frame(maxWidth: 340)
            }
        }
        .padding(.horizontal, 32)
        .sheet(isPresented: $showNASInOnboarding) {
            NASDiscoverySheet(isPresented: $showNASInOnboarding) { destination, password in
                viewModel.addDestination(destination, password: password)
            }
        }
    }

    private func featurePill(_ symbol: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
            }
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    private var nextLabel: String {
        switch step {
        case 0: return "Get Started"
        case 1: return viewModel.sourceFolders.isEmpty ? "Skip" : "Next"
        case 2: return viewModel.destinations.isEmpty ? "Skip" : "Done!"
        default: return "Done"
        }
    }

    private func advance() {
        if step < 2 { withAnimation { step += 1; bounce() } }
        else {
            viewModel.saveConfiguration()
            onCompleted()
            isPresented = false
        }
    }

    private func bounce() {
        animateIn = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { animateIn = true }
    }
}
