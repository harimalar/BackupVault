//
//  BackupViewModel.swift
//  BackupVault
//
//  MVVM: state and actions for the Backup flow.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

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
    
    private let coordinator = BackupCoordinator()
    private var backupTask: Task<Void, Error>?
    private var currentRunId: UUID?

    var canStartBackup: Bool {
        !sourceFolders.isEmpty && selectedDestination != nil && !isBackingUp
    }
    
    init() {
        loadState()
    }
    
    func loadState() {
        sourceFolders = DestinationStore.shared.loadSelectedSourceFolders()
        destinations = DestinationStore.shared.loadDestinations()
        exclusions = DestinationStore.shared.loadExclusions()
        verifyWithChecksum = UserDefaults.standard.bool(forKey: Keys.verifyWithChecksum)

        let savedDestinationID = UserDefaults.standard.string(forKey: Keys.selectedDestinationID)
            .flatMap(UUID.init(uuidString:))
        if let savedDestinationID,
           let savedDestination = destinations.first(where: { $0.id == savedDestinationID }) {
            selectedDestination = savedDestination
        } else if selectedDestination == nil, let first = destinations.first {
            selectedDestination = first
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
        Task {
            var count = 0
            var total: Int64 = 0
            let scanner = FileScanner()
            do {
                try scanner.scan(sourceRoots: sourceFolders, skipHidden: true, exclusions: exclusions) { _, scanned in
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
            try? KeychainService.shared.setPassword(pass, forDestinationID: dest.id)
        }
        DestinationStore.shared.addDestination(dest)
        destinations = DestinationStore.shared.loadDestinations()
        selectedDestination = dest
        updateDestinationFreeSpace()
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
        
        backupTask = Task {
            do {
                try await coordinator.runBackup(
                    sourceRoots: sourceFolders,
                    destination: dest,
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
}
