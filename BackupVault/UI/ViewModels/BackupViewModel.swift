//
//  BackupViewModel.swift
//  BackupVault
//
//  MVVM: state and actions for the Backup flow.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AppKit  // for NSWorkspace (open in Finder)

@MainActor
final class BackupViewModel: ObservableObject {
    private enum Keys {
        static let selectedDestinationID = "BackupVault.selectedDestinationID"
        static let verifyWithChecksum = "BackupVault.verifyWithChecksum"
    }
    
    @Published var sourceFolders: [URL] = []
    @Published var selectedDestination: BackupDestination? {
        didSet {
            guard selectedDestination?.id != oldValue?.id else { return }
            persistSelectedDestination()
            updateDestinationFreeSpace()
        }
    }
    @Published var destinations: [BackupDestination] = []
    @Published var isBackingUp = false
    @Published var progress: BackupProgress?
    @Published var errorMessage: String?
    @Published var showFolderPicker = false
    @Published var showDestinationPicker = false
    @Published var verifyWithChecksum = false {
        didSet {
            UserDefaults.standard.set(verifyWithChecksum, forKey: Keys.verifyWithChecksum)
        }
    }
    @Published var exclusions: BackupExclusions = .default
    @Published var estimatedFileCount: Int?
    @Published var estimatedSizeBytes: Int64?
    @Published var destinationFreeSpaceBytes: Int64?
    @Published var isEstimating = false
    @Published var lastCompletedSnapshotURL: URL?  // for "Open in Finder" after backup
    
    private let coordinator = BackupCoordinator()
    private let fileManager = FileManager.default
    private var backupTask: Task<Void, Error>?
    private var currentRunId: UUID?
    private var workspaceObservers: [Any] = []

    var canStartBackup: Bool {
        !sourceFolders.isEmpty && selectedDestination != nil && !isBackingUp
    }
    
    init() {
        observeVolumeChanges()
        loadState()
    }
    
    func loadState() {
        sourceFolders = DestinationStore.shared.loadSelectedSourceFolders()
        // loadDestinations() deduplicates by path and persists the cleaned list
        destinations = DestinationStore.shared.loadDestinations()
        exclusions = DestinationStore.shared.loadExclusions()
        verifyWithChecksum = UserDefaults.standard.bool(forKey: Keys.verifyWithChecksum)

        // Try to restore the previously selected destination by UUID.
        // After dedup the saved UUID may no longer exist — fall back to first.
        let savedID = UserDefaults.standard.string(forKey: Keys.selectedDestinationID)
            .flatMap(UUID.init(uuidString:))
        if let savedID, let match = destinations.first(where: { $0.id == savedID }) {
            selectedDestination = match
        } else if let first = destinations.first {
            // Either no saved ID, or the saved ID was a duplicate that got removed.
            // Pick the first unique destination and persist it so next launch is reliable.
            selectedDestination = first
            UserDefaults.standard.set(first.id.uuidString, forKey: Keys.selectedDestinationID)
        }
        updateDestinationFreeSpace()
        refreshEstimates()
    }

    func saveConfiguration() {
        DestinationStore.shared.saveSelectedSourceFolders(sourceFolders)
        DestinationStore.shared.saveExclusions(exclusions)
        UserDefaults.standard.set(verifyWithChecksum, forKey: Keys.verifyWithChecksum)
        persistSelectedDestination()
        updateDestinationFreeSpace()
    }

    func startBackupWithVerification() {
        verifyWithChecksum = true
        startBackup()
    }
    
    func saveExclusions() {
        DestinationStore.shared.saveExclusions(exclusions)
    }
    
    func addExcludedFolder(_ name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !exclusions.excludedFolderNames.contains(where: { $0.lowercased() == t.lowercased() }) else { return }
        exclusions.excludedFolderNames.append(t)
        saveExclusions()
    }
    
    func removeExcludedFolder(at index: Int) {
        guard index >= 0, index < exclusions.excludedFolderNames.count else { return }
        exclusions.excludedFolderNames.remove(at: index)
        saveExclusions()
    }
    
    func removeExcludedFolder(named name: String) {
        exclusions.excludedFolderNames.removeAll { $0.lowercased() == name.lowercased() }
        saveExclusions()
    }
    
    func addExcludedPattern(_ pattern: String) {
        let t = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !exclusions.excludedFilePatterns.contains(where: { $0.lowercased() == t.lowercased() }) {
            exclusions.excludedFilePatterns.append(t)
            saveExclusions()
        }
    }
    
    func removeExcludedPattern(at index: Int) {
        guard index >= 0, index < exclusions.excludedFilePatterns.count else { return }
        exclusions.excludedFilePatterns.remove(at: index)
        saveExclusions()
    }
    
    func removeExcludedPattern(_ pattern: String) {
        exclusions.excludedFilePatterns.removeAll { $0.lowercased() == pattern.lowercased() }
        saveExclusions()
    }
    
    func updateDestinationFreeSpace() {
        guard let dest = selectedDestination else { destinationFreeSpaceBytes = nil; return }
        if dest.type == .externalDrive, let space = DiskSpaceMonitor.space(for: dest.path) {
            destinationFreeSpaceBytes = space.availableBytes
        } else {
            destinationFreeSpaceBytes = nil
        }
    }
    
    func refreshEstimates() {
        guard !sourceFolders.isEmpty else {
            estimatedFileCount = nil
            estimatedSizeBytes = nil
            isEstimating = false
            return
        }
        isEstimating = true
        estimatedFileCount = nil
        estimatedSizeBytes = nil
        let activeSourceFolders = sourceFolders
        Task {
            let accessedSourceFolders = startAccessingSourceFolders(activeSourceFolders)
            defer { stopAccessingSourceFolders(accessedSourceFolders) }
            var count = 0
            var total: Int64 = 0
            let scanner = FileScanner()
            do {
                try scanner.scan(sourceRoots: activeSourceFolders, skipHidden: true, exclusions: exclusions) { _, scanned in
                    count += 1
                    total += scanned.size
                }
            } catch {}
            await MainActor.run {
                estimatedFileCount = count
                estimatedSizeBytes = total
                isEstimating = false
            }
        }
    }
    
    func addFolder(_ url: URL) {
        guard !sourceFolders.contains(where: { $0.path == url.path }) else { return }
        sourceFolders.append(url)
        DestinationStore.shared.saveSelectedSourceFolders(sourceFolders)
        refreshEstimates()
    }
    
    func removeFolder(_ url: URL) {
        sourceFolders.removeAll { $0.path == url.path }
        DestinationStore.shared.saveSelectedSourceFolders(sourceFolders)
        refreshEstimates()
    }
    
    func addDestination(_ dest: BackupDestination, password: String?) {
        if let pass = password, !pass.isEmpty, dest.type == .nas {
            try? KeychainService.shared.setNASPassword(pass, for: dest)
        }
        guard dest.type == .nas else {
            guard validateNoPathOverlap(with: dest.path) else { return }
            DestinationStore.shared.addDestination(dest)
            destinations = DestinationStore.shared.loadDestinations()
            selectedDestination = dest
            updateDestinationFreeSpace()
            return
        }

        if dest.path.isFileURL {
            let accessed = dest.path.startAccessingSecurityScopedResource()
            DestinationStore.shared.addDestination(dest)
            if accessed {
                dest.path.stopAccessingSecurityScopedResource()
            }
                guard DestinationStore.shared.hasBookmark(for: dest.id) else {
                    DestinationStore.shared.removeDestination(id: dest.id)
                    try? KeychainService.shared.deleteNASPassword(for: dest)
                    errorMessage = "BackupVault couldn’t save access to the selected NAS folder. Choose the folder again."
                    return
                }
            destinations = DestinationStore.shared.loadDestinations()
            selectedDestination = dest
            updateDestinationFreeSpace()
            return
        }

        Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                let authorizedDestination = try await ensureDestinationAccess(for: dest)
                DestinationStore.shared.addDestination(authorizedDestination)
                guard DestinationStore.shared.hasBookmark(for: authorizedDestination.id) else {
                    DestinationStore.shared.removeDestination(id: authorizedDestination.id)
                    throw BackupError.nasMountFailed("BackupVault couldn’t save access to the selected NAS folder. Choose a folder inside the mounted share and try again.")
                }
                destinations = DestinationStore.shared.loadDestinations()
                selectedDestination = authorizedDestination
                updateDestinationFreeSpace()
            } catch {
                try? KeychainService.shared.deleteNASPassword(for: dest)
                if !(error is CancellationError) {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func removeDestination(id: UUID) {
        if selectedDestination?.id == id { selectedDestination = nil }
        DestinationStore.shared.removeDestination(id: id)
        destinations = DestinationStore.shared.loadDestinations()
        updateDestinationFreeSpace()
    }
    
    func startBackup() {
        guard !sourceFolders.isEmpty, let dest = selectedDestination else {
            errorMessage = "Select at least one folder and a destination."
            return
        }
        
        errorMessage = nil
        isBackingUp = true
        progress = BackupProgress(phase: .resolvingDestination, filesScanned: 0, filesToCopy: 0, filesCopied: 0, filesHardLinked: 0, filesSkipped: 0, bytesCopied: 0, logicalBytesProtected: 0, currentFile: nil, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: nil)
        
        let runStartedAt = Date()
        let run = BackupRun(destinationID: dest.id, startedAt: runStartedAt, snapshotFolderName: snapshotFolderName(for: runStartedAt), state: .inProgress)
        currentRunId = run.id
        DestinationStore.shared.appendRun(run)
        let activeSourceFolders = sourceFolders
        
        backupTask = Task {
            let accessedSourceFolders = startAccessingSourceFolders(activeSourceFolders)
            defer { stopAccessingSourceFolders(accessedSourceFolders) }
            do {
                let authorizedDestination = try await ensureDestinationAccess(for: dest)
                try validateNoPathOverlapOrThrow(with: authorizedDestination.path)
                try await coordinator.runBackup(
                    sourceRoots: activeSourceFolders,
                    destination: authorizedDestination,
                    verifyWithChecksum: verifyWithChecksum,
                    runStartedAt: runStartedAt,
                    lastCopiedPath: nil,
                    exclusions: exclusions
                ) { [weak self] prog in
                    Task { @MainActor in
                        self?.progress = prog
                        if let err = prog.errorMessage { self?.errorMessage = err }
                        if prog.phase == .completed, let runId = self?.currentRunId {
                            if var run = DestinationStore.shared.loadBackupRuns().first(where: { $0.id == runId }) {
                                run.completedAt = Date()
                                run.snapshotFolderName = self?.snapshotFolderName(for: run.startedAt)
                                run.totalFilesScanned = prog.filesScanned
                                run.totalFilesCopied = prog.filesCopied
                                run.totalFilesHardLinked = prog.filesHardLinked
                                run.totalFilesSkipped = prog.filesSkipped
                                run.totalBytesCopied = prog.bytesCopied
                                run.totalLogicalBytes = prog.logicalBytesProtected
                                run.state = .completed
                                if self?.verifyWithChecksum == true { run.verifiedAt = Date() }
                                // Store snapshot URL so user can open it in Finder
                                if let dest = self?.selectedDestination,
                                   let folderName = run.snapshotFolderName {
                                    let computerName = Host.current().localizedName ?? "Mac"
                                    self?.lastCompletedSnapshotURL = dest.path
                                        .appendingPathComponent("BackupVault")
                                        .appendingPathComponent(computerName)
                                        .appendingPathComponent(folderName)
                                }
                                DestinationStore.shared.updateRun(run)
                            }
                            self?.currentRunId = nil
                        }
                    }
                }
            } catch {
                Logger.shared.logError(error, context: "Backup failed")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.progress = BackupProgress(phase: .failed, filesScanned: 0, filesToCopy: 0, filesCopied: 0, filesHardLinked: 0, filesSkipped: 0, bytesCopied: 0, logicalBytesProtected: 0, currentFile: nil, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: error.localizedDescription)
                    if let runId = self.currentRunId, var run = DestinationStore.shared.loadBackupRuns().first(where: { $0.id == runId }) {
                        run.snapshotFolderName = self.snapshotFolderName(for: run.startedAt)
                        run.state = .interrupted
                        DestinationStore.shared.updateRun(run)
                        self.currentRunId = nil
                    }
                }
            }
            await MainActor.run {
                self.isBackingUp = false
            }
        }
    }
    
    func cancelBackup() {
        coordinator.cancel()
        backupTask?.cancel()
        isBackingUp = false
    }
    
    func openSelectedDestinationFolder() {
        guard let destination = selectedDestination else { return }

        Task {
            do {
                let resolvedDestination: BackupDestination
                if destination.type == .nas {
                    resolvedDestination = try await ensureDestinationAccess(for: destination)
                } else {
                    resolvedDestination = destination
                }

                guard resolvedDestination.path.isFileURL else {
                    errorMessage = "BackupVault couldn’t open the selected backup folder."
                    return
                }

                NSWorkspace.shared.open(resolvedDestination.path)
            } catch {
                if !(error is CancellationError) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func ejectDestination(_ destination: BackupDestination) {
        guard destination.type == .externalDrive else { return }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: destination.path)
            handleDestinationEnvironmentChange()
        } catch {
            errorMessage = "BackupVault couldn’t eject \(destination.name): \(error.localizedDescription)"
        }
    }

    func chooseFolderWithinExternalDrive(_ destination: BackupDestination) {
        guard destination.type == .externalDrive else { return }

        let driveRoot = externalDriveRoot(for: destination.path)
        let panel = NSOpenPanel()
        panel.message = "Choose where BackupVault should store backups on \(destination.name)."
        panel.prompt = "Use This Folder"
        panel.directoryURL = fileManager.fileExists(atPath: destination.path.path) ? destination.path : driveRoot
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true

        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else { return }
        guard selectedURL.standardizedFileURL.path.hasPrefix(driveRoot.standardizedFileURL.path) else {
            errorMessage = "Choose a folder inside \(destination.name)."
            return
        }
        guard validateNoPathOverlap(with: selectedURL) else { return }

        let accessed = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }

        var updatedDestination = destination
        updatedDestination.path = selectedURL
        DestinationStore.shared.updateDestination(updatedDestination)
        destinations = DestinationStore.shared.loadDestinations()
        if selectedDestination?.id == updatedDestination.id {
            selectedDestination = updatedDestination
        }
        updateDestinationFreeSpace()
    }

    func clearError() {
        errorMessage = nil
    }

    private func snapshotFolderName(for date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH-mm"
        return "\(dateFormatter.string(from: date))_\(timeFormatter.string(from: date))"
    }

    private func persistSelectedDestination() {
        UserDefaults.standard.set(selectedDestination?.id.uuidString, forKey: Keys.selectedDestinationID)
    }

    private func externalDriveRoot(for url: URL) -> URL {
        let standardized = url.standardizedFileURL
        let components = standardized.pathComponents
        guard let volumesIndex = components.firstIndex(of: "Volumes"),
              components.count > volumesIndex + 1 else {
            return standardized
        }
        let rootComponents = Array(components.prefix(volumesIndex + 2))
        let rootPath = NSString.path(withComponents: rootComponents)
        return URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    private func ensureDestinationAccess(for destination: BackupDestination) async throws -> BackupDestination {
        guard destination.type == .nas else {
            return destination
        }

        let needsExplicitAuthorization = !destination.path.isFileURL || !DestinationStore.shared.hasBookmark(for: destination.id)
        let initiallyAuthorizedURL = DestinationStore.shared.startAccessing(destination: destination)
        defer { DestinationStore.shared.stopAccessing(url: initiallyAuthorizedURL) }

        if !needsExplicitAuthorization,
           DestinationStore.shared.canWrite(in: initiallyAuthorizedURL) {
            let persisted = persistResolvedDestination(destination, resolvedURL: initiallyAuthorizedURL)
            try ensurePersistentBookmark(for: persisted)
            return persisted
        }

        guard let host = destination.nasHost,
              let share = destination.nasShare,
              let username = destination.nasUsername else {
            throw BackupError.nasMountFailed("Missing NAS configuration. Remove and re-add the destination.")
        }
        let password = try KeychainService.shared.getPassword(forDestinationID: destination.id) ?? ""
        guard !password.isEmpty else {
            throw BackupError.nasMountFailed("No password saved for \(destination.name). Remove and re-add the destination.")
        }

        let mountedURL = try await NASMountService.shared.mount(
            host: host,
            share: share,
            username: username,
            password: password
        )
        let preferredURL = preferredNASDestinationURL(for: destination, mountedURL: mountedURL)
        if !needsExplicitAuthorization,
           ensureDirectoryExists(at: preferredURL),
           DestinationStore.shared.canWrite(in: preferredURL) {
            let persisted = persistResolvedDestination(destination, resolvedURL: preferredURL)
            try ensurePersistentBookmark(for: persisted)
            return persisted
        }

        let chosenURL = try await requestDestinationFolderAccess(
            for: destination,
            mountedURL: mountedURL,
            suggestedURL: preferredURL
        )
        let persisted = persistResolvedDestination(destination, resolvedURL: chosenURL)
        try ensurePersistentBookmark(for: persisted)
        return persisted
    }

    private func requestDestinationFolderAccess(
        for destination: BackupDestination,
        mountedURL: URL,
        suggestedURL: URL
    ) async throws -> URL {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder on \(destination.name) where BackupVault should store backups."
        panel.prompt = "Use This Folder"
        panel.directoryURL = fileManager.fileExists(atPath: suggestedURL.path) ? suggestedURL : mountedURL
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true

        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else {
            throw BackupError.cancelled
        }
        guard selectedURL.path.hasPrefix(mountedURL.path) else {
            throw BackupError.nasMountFailed("Choose a folder inside the mounted share for \(destination.name).")
        }
        try validateNoPathOverlapOrThrow(with: selectedURL)
        return selectedURL
    }

    private func persistResolvedDestination(_ destination: BackupDestination, resolvedURL: URL) -> BackupDestination {
        var updatedDestination = destination
        updatedDestination.path = resolvedURL
        let accessed = resolvedURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                resolvedURL.stopAccessingSecurityScopedResource()
            }
        }
        DestinationStore.shared.updateDestination(updatedDestination)
        destinations = DestinationStore.shared.loadDestinations()
        if selectedDestination?.id == updatedDestination.id {
            selectedDestination = updatedDestination
        }
        return updatedDestination
    }

    private func ensurePersistentBookmark(for destination: BackupDestination) throws {
        guard destination.path.isFileURL,
              DestinationStore.shared.hasBookmark(for: destination.id) else {
            throw BackupError.nasMountFailed("BackupVault couldn’t save access to the selected NAS folder. Choose the folder again.")
        }
    }

    private func preferredNASDestinationURL(for destination: BackupDestination, mountedURL: URL) -> URL {
        guard destination.path.isFileURL else { return mountedURL }
        let relativeComponents = relativeNASPathComponents(from: destination.path)
        guard !relativeComponents.isEmpty else { return mountedURL }
        return relativeComponents.reduce(mountedURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
    }

    private func relativeNASPathComponents(from url: URL) -> [String] {
        let components = url.standardizedFileURL.pathComponents
        guard let volumesIndex = components.firstIndex(of: "Volumes"),
              components.count > volumesIndex + 2 else {
            return []
        }
        return Array(components[(volumesIndex + 2)...])
    }

    @discardableResult
    private func ensureDirectoryExists(at url: URL) -> Bool {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    private func validateNoPathOverlap(with destinationURL: URL) -> Bool {
        do {
            try validateNoPathOverlapOrThrow(with: destinationURL)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func validateNoPathOverlapOrThrow(with destinationURL: URL) throws {
        let destinationPath = destinationURL.standardizedFileURL.path
        for sourceURL in sourceFolders {
            let sourcePath = sourceURL.standardizedFileURL.path
            if pathsOverlap(sourcePath, destinationPath) {
                throw BackupError.nasMountFailed(
                    "Choose a backup location outside the folders you’re protecting. Backups can’t be stored inside a source folder."
                )
            }
        }
    }

    private func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || isAncestor(lhs, of: rhs) || isAncestor(rhs, of: lhs)
    }

    private func isAncestor(_ candidateParent: String, of candidateChild: String) -> Bool {
        let parentPath = candidateParent.hasSuffix("/") ? candidateParent : candidateParent + "/"
        return candidateChild.hasPrefix(parentPath)
    }

    private func startAccessingSourceFolders(_ urls: [URL]) -> [URL] {
        urls.filter { $0.startAccessingSecurityScopedResource() }
    }

    private func stopAccessingSourceFolders(_ urls: [URL]) {
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    private func observeVolumeChanges() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleDestinationEnvironmentChange()
                }
            }
        )
        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleDestinationEnvironmentChange()
                }
            }
        )
    }

    private func handleDestinationEnvironmentChange() {
        updateDestinationFreeSpace()
        objectWillChange.send()
    }
}
