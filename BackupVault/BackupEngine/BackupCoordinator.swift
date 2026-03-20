//
//  BackupCoordinator.swift
//  BackupVault
//
//  Orchestrates: resolve destination (mount NAS if needed), scan, incremental filter, copy, verify, save manifest.
//

import Foundation

/// Live progress for UI.
struct BackupProgress: Sendable {
    var phase: BackupPhase
    var filesScanned: Int
    var filesToCopy: Int
    var filesCopied: Int
    var filesHardLinked: Int
    var filesSkipped: Int
    var bytesCopied: Int64
    var logicalBytesProtected: Int64
    var currentFile: String?
    var bytesPerSecond: Double
    var estimatedTimeRemaining: TimeInterval?
    var errorMessage: String?
}

enum BackupPhase: Sendable {
    case resolvingDestination
    case scanning
    case copying
    case verifying
    case completed
    case failed
}

/// One scanned file with its source root index (for multi-folder backup).
struct ScannedFileWithRoot: Sendable {
    let rootIndex: Int
    let file: ScannedFile
}

private struct SourceRootDescriptor {
    let rootURL: URL
    let snapshotFolderName: String
}

final class BackupCoordinator: @unchecked Sendable {
    
    private let scanner = FileScanner()
    private let copyEngine = FileCopyEngine()
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH-mm"
        return f
    }()
    
    private static let stateFileName = ".backupvault_state.json"
    
    /// Run full backup: resolve destination, scan sources, incremental filter, copy, verify.
    func runBackup(
        sourceRoots: [URL],
        destination: BackupDestination,
        verifyWithChecksum: Bool,
        runStartedAt: Date? = nil,
        lastCopiedPath: String?,
        exclusions: BackupExclusions? = nil,
        progress: @escaping (BackupProgress) -> Void
    ) async throws {
        progress(BackupProgress(phase: .resolvingDestination, filesScanned: 0, filesToCopy: 0, filesCopied: 0, filesHardLinked: 0, filesSkipped: 0, bytesCopied: 0, logicalBytesProtected: 0, currentFile: nil, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: nil))
        
        let destinationBase = try await resolveDestination(destination)
        Logger.shared.info("Backup started to \(destination.name)")
        
        let computerName = Host.current().localizedName ?? "Mac"
        let now = runStartedAt ?? Date()
        let snapshotFolderName = "\(dateFormatter.string(from: now))_\(timeFormatter.string(from: now))"
        let snapshotContainer = try snapshotContainerURL(from: destinationBase, computerName: computerName)
        let backupBase = snapshotContainer.appendingPathComponent(snapshotFolderName)
        
        try FileManager.default.createDirectory(at: backupBase, withIntermediateDirectories: true)
        
        let sourceDescriptors = makeSourceRootDescriptors(for: sourceRoots)
        var allScanned: [SnapshotFileCandidate] = []
        var allDirectories = Set(sourceDescriptors.map(\.snapshotFolderName))
        var scannedLogicalBytes: Int64 = 0
        try scanner.scan(
            sourceRoots: sourceRoots,
            skipHidden: true,
            exclusions: exclusions,
            onDirectory: { rootIndex, directory in
                let descriptor = sourceDescriptors[rootIndex]
                allDirectories.insert(descriptor.snapshotFolderName + "/" + directory.relativePath)
            },
            onFile: { rootIndex, scanned in
                let descriptor = sourceDescriptors[rootIndex]
                scannedLogicalBytes += scanned.size
                allScanned.append(
                    SnapshotFileCandidate(
                        sourceRootName: descriptor.snapshotFolderName,
                        sourceRootPath: descriptor.rootURL.path,
                        relativePath: scanned.relativePath,
                        snapshotRelativePath: descriptor.snapshotFolderName + "/" + scanned.relativePath,
                        url: scanned.url,
                        size: scanned.size,
                        modifiedDate: scanned.modifiedDate
                    )
                )
                if allScanned.count % 100 == 0 {
                    progress(BackupProgress(phase: .scanning, filesScanned: allScanned.count, filesToCopy: 0, filesCopied: 0, filesHardLinked: 0, filesSkipped: 0, bytesCopied: 0, logicalBytesProtected: scannedLogicalBytes, currentFile: descriptor.snapshotFolderName + "/" + scanned.relativePath, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: nil))
                }
            },
            onError: { _, _ in }
        )

        try createSnapshotDirectories(allDirectories, in: backupBase)
        
        let logicalBytesProtected = scannedLogicalBytes
        progress(BackupProgress(phase: .scanning, filesScanned: allScanned.count, filesToCopy: 0, filesCopied: 0, filesHardLinked: 0, filesSkipped: 0, bytesCopied: 0, logicalBytesProtected: logicalBytesProtected, currentFile: nil, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: nil))
        
        let parentBase = backupBase.deletingLastPathComponent()
        var previousRecords: [FileRecord] = []
        var previousSnapshotBase: URL?
        if let lastRun = DestinationStore.shared.lastCompletedRun(forDestinationID: destination.id) {
            let prevFolderName = lastRun.snapshotFolderName(dateFormatter: dateFormatter, timeFormatter: timeFormatter)
            previousSnapshotBase = parentBase.appendingPathComponent(prevFolderName)
            let previousManifestPath = previousSnapshotBase!.appendingPathComponent("manifest.json")
            if let data = try? Data(contentsOf: previousManifestPath),
               let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) {
                previousRecords = manifest.files
            }
        }
        
        _ = lastCopiedPath
        let previousMap = IncrementalLogic.previousRecordMap(previousRecords)
        let filesToCopy: [FileCopyEngine.FileToCopy] = allScanned.map { item in
            let previousRecord = previousMap[item.snapshotRelativePath]
            let previousFileURL: URL? = {
                guard let base = previousSnapshotBase,
                      !IncrementalLogic.fileHasChanged(item, previousRecord: previousRecord) else {
                    return nil
                }
                let previousFile = base.appendingPathComponent(item.snapshotRelativePath)
                return fileManager.fileExists(atPath: previousFile.path) ? previousFile : nil
            }()
            return FileCopyEngine.FileToCopy(
                sourceURL: item.url,
                displayPath: item.snapshotRelativePath,
                destinationRelativePath: item.snapshotRelativePath,
                fileSize: item.size,
                previousFileURL: previousFileURL
            )
        }
        let totalTransferBytes = filesToCopy
            .filter { $0.previousFileURL == nil }
            .reduce(into: Int64(0)) { $0 += $1.fileSize }
        let filesSkippedCount = 0
        
        progress(BackupProgress(phase: .copying, filesScanned: allScanned.count, filesToCopy: filesToCopy.count, filesCopied: 0, filesHardLinked: 0, filesSkipped: filesSkippedCount, bytesCopied: 0, logicalBytesProtected: logicalBytesProtected, currentFile: nil, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: nil))
        
        var lastCopyBytes: Int64 = 0
        var lastHardLinked: Int = 0
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var config = FileCopyEngine.CopyConfig()
                    config.verifyWithChecksum = verifyWithChecksum
                    config.lockSourceFile = true
                    config.maxConcurrent = 6
                    try self.copyEngine.copy(files: filesToCopy, destinationBase: backupBase, config: config) { copyProg in
                        lastCopyBytes = copyProg.bytesCopied
                        lastHardLinked = copyProg.filesHardLinked
                        if let path = copyProg.currentFile {
                            self.saveResumeState(BackupResumeState(lastCopiedPath: path, filesCopiedCount: copyProg.filesCopied + copyProg.filesHardLinked, bytesCopied: copyProg.bytesCopied), to: backupBase)
                        }
                        let remainingBytes = totalTransferBytes - copyProg.bytesCopied
                        let eta: TimeInterval? = copyProg.bytesPerSecond > 0 && remainingBytes > 0
                            ? Double(remainingBytes) / copyProg.bytesPerSecond
                            : nil
                        progress(BackupProgress(
                            phase: .copying,
                            filesScanned: copyProg.filesScanned,
                            filesToCopy: copyProg.filesToCopy,
                            filesCopied: copyProg.filesCopied,
                            filesHardLinked: copyProg.filesHardLinked,
                            filesSkipped: filesSkippedCount,
                            bytesCopied: copyProg.bytesCopied,
                            logicalBytesProtected: logicalBytesProtected,
                            currentFile: copyProg.currentFile,
                            bytesPerSecond: copyProg.bytesPerSecond,
                            estimatedTimeRemaining: eta,
                            errorMessage: nil
                        ))
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        let currentManifestPath = backupBase.appendingPathComponent("manifest.json")
        let manifest = BackupManifest(
            backupDatePath: snapshotFolderName,
            computerName: computerName,
            recordedAt: Date(),
            files: IncrementalLogic.toRecords(allScanned)
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try AtomicFileWriter.write(manifestData, to: currentManifestPath)
        
        saveResumeState(nil, to: backupBase)
        let duration = Date().timeIntervalSince(now)
        Logger.shared.logFilesCopied(count: filesToCopy.count, bytes: lastCopyBytes, duration: duration)
        if verifyWithChecksum { Logger.shared.logVerificationResult(success: true, fileCount: filesToCopy.count) }
        
        progress(BackupProgress(phase: .completed, filesScanned: allScanned.count, filesToCopy: filesToCopy.count, filesCopied: filesToCopy.count - lastHardLinked, filesHardLinked: lastHardLinked, filesSkipped: filesSkippedCount, bytesCopied: lastCopyBytes, logicalBytesProtected: logicalBytesProtected, currentFile: nil, bytesPerSecond: 0, estimatedTimeRemaining: nil, errorMessage: nil))
    }
    
    private struct BackupResumeState: Codable {
        var lastCopiedPath: String?
        var filesCopiedCount: Int
        var bytesCopied: Int64
    }
    
    private func loadResumeState(from snapshotBase: URL) -> BackupResumeState? {
        let url = snapshotBase.appendingPathComponent(Self.stateFileName)
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(BackupResumeState.self, from: data) else { return nil }
        return state
    }
    
    /// Crash-safe: write to .tmp then rename so state is never half-written.
    private func saveResumeState(_ state: BackupResumeState?, to snapshotBase: URL) {
        let url = snapshotBase.appendingPathComponent(Self.stateFileName)
        if let state = state, let data = try? JSONEncoder().encode(state) {
            try? AtomicFileWriter.write(data, to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
            let tmpURL = snapshotBase.appendingPathComponent(Self.stateFileName + ".tmp")
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    private func createSnapshotDirectories(_ relativePaths: Set<String>, in snapshotBase: URL) throws {
        for path in relativePaths.sorted(by: directoryPathSort) {
            try fileManager.createDirectory(
                at: snapshotBase.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func directoryPathSort(_ lhs: String, _ rhs: String) -> Bool {
        let lhsDepth = lhs.split(separator: "/").count
        let rhsDepth = rhs.split(separator: "/").count
        if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
    
    private func resolveDestination(_ destination: BackupDestination) async throws -> URL {
        switch destination.type {
        case .externalDrive:
            // Start security-scoped access using stored bookmark (required in sandbox)
            let resolvedURL = DestinationStore.shared.startAccessing(destination: destination)
            guard DestinationStore.shared.isReachableDirectory(resolvedURL),
                  DestinationStore.shared.canWrite(in: resolvedURL) else {
                DestinationStore.shared.stopAccessing(url: resolvedURL)
                throw BackupError.destinationUnavailable(destination)
            }
            return resolvedURL
        case .nas:
            let needsExplicitAuthorization = !destination.path.isFileURL || !DestinationStore.shared.hasBookmark(for: destination.id)
            let authorizedURL = DestinationStore.shared.startAccessing(destination: destination)
            if authorizedURL.isFileURL,
               DestinationStore.shared.isReachableDirectory(authorizedURL),
               DestinationStore.shared.canWrite(in: authorizedURL) {
                Logger.shared.info("[NAS] Using authorized destination: \(authorizedURL.path)")
                return authorizedURL
            }
            DestinationStore.shared.stopAccessing(url: authorizedURL)
            guard let host = destination.nasHost,
                  let share = destination.nasShare,
                  let username = destination.nasUsername else {
                throw BackupError.nasMountFailed("Missing NAS configuration. Re-add the destination.")
            }
            // Clean share name — strip /Volumes/ if user typed full path
            let cleanShare = NASMountService.normalizeShareName(share)
            // First try to find an already-mounted share (Finder connection)
            Logger.shared.info("[NAS] Resolving destination: host=\(host) share=\(cleanShare)")
            let mountedRoot: URL
            if let existing = NASMountService.shared.findExistingMount(host: host, share: cleanShare) {
                Logger.shared.info("[NAS] Using existing mount: \(existing.path)")
                guard (try? existing.checkResourceIsReachable()) == true else {
                    throw BackupError.nasMountFailed(
                        "\(cleanShare) on \(host) is mounted but not reachable. Try disconnecting and reconnecting via Finder.")
                }
                mountedRoot = existing
            } else {
                Logger.shared.info("[NAS] No existing mount found for '\(cleanShare)', attempting programmatic mount")
                // Not mounted yet — try to mount
                let password = try KeychainService.shared.getPassword(forDestinationID: destination.id) ?? ""
                guard !password.isEmpty else {
                    throw BackupError.nasMountFailed(
                        "No password saved for \(destination.name). Remove and re-add the destination.")
                }
                let mounted = try await NASMountService.shared.mount(
                    host: host, share: cleanShare, username: username, password: password)
                // Sanity check: ensure we got a real mounted volume, not a local path
                guard mounted.path.hasPrefix("/Volumes/") else {
                    Logger.shared.error("[NAS] Mount returned non-/Volumes path: \(mounted.path)")
                    throw BackupError.nasMountFailed(
                        "Could not reach \(destination.name). Please connect via Finder first: Go → Connect to Server → smb://\(host)")
                }
                mountedRoot = mounted
            }
            if needsExplicitAuthorization {
                throw BackupError.nasMountFailed(
                    "BackupVault needs one-time access to a folder on \(destination.name). Re-open the NAS destination and choose a folder inside the mounted share."
                )
            }
            let rebuiltURL = rebuiltNASDestinationURL(for: destination, mountedRoot: mountedRoot)
            try ensureDirectoryExists(at: rebuiltURL)
            guard DestinationStore.shared.canWrite(in: rebuiltURL) else {
                throw BackupError.nasMountFailed(
                    "BackupVault needs folder permission for \(destination.name). Re-select the NAS destination folder once and try again."
                )
            }
            if rebuiltURL != destination.path {
                var updatedDestination = destination
                updatedDestination.path = rebuiltURL
                DestinationStore.shared.updateDestination(updatedDestination)
            }
            Logger.shared.info("[NAS] Using mounted volume at \(rebuiltURL.path)")
            return rebuiltURL
        }
    }
    
    func cancel() {
        scanner.cancel()
        copyEngine.cancel()
    }

    private func makeSourceRootDescriptors(for sourceRoots: [URL]) -> [SourceRootDescriptor] {
        var seenNames: [String: Int] = [:]
        return sourceRoots.map { root in
            let rawName = root.lastPathComponent.isEmpty ? "Root" : root.lastPathComponent
            let count = seenNames[rawName, default: 0]
            seenNames[rawName] = count + 1
            let snapshotName = count == 0 ? rawName : "\(rawName)-\(count + 1)"
            return SourceRootDescriptor(rootURL: root, snapshotFolderName: snapshotName)
        }
    }

    private func rebuiltNASDestinationURL(for destination: BackupDestination, mountedRoot: URL) -> URL {
        guard destination.path.isFileURL else { return mountedRoot }
        let components = destination.path.standardizedFileURL.pathComponents
        guard let volumesIndex = components.firstIndex(of: "Volumes"),
              components.count > volumesIndex + 2 else {
            return mountedRoot
        }
        let relativeComponents = Array(components[(volumesIndex + 2)...])
        guard !relativeComponents.isEmpty else { return mountedRoot }
        return relativeComponents.reduce(mountedRoot) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
    }

    private func ensureDirectoryExists(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func snapshotContainerURL(from destinationBase: URL, computerName: String) throws -> URL {
        let baseName = destinationBase.lastPathComponent
        let parentName = destinationBase.deletingLastPathComponent().lastPathComponent
        let backupRoot: URL

        if baseName.caseInsensitiveCompare(computerName) == .orderedSame,
           parentName.caseInsensitiveCompare("BackupVault") == .orderedSame {
            backupRoot = destinationBase.deletingLastPathComponent()
        } else if baseName.caseInsensitiveCompare("BackupVault") == .orderedSame {
            backupRoot = destinationBase
        } else {
            backupRoot = destinationBase.appendingPathComponent("BackupVault", isDirectory: true)
        }
        try ensureDirectoryExists(at: backupRoot)

        let candidates = [
            computerName,
            "\(computerName)-BackupVault",
            "This Mac",
            "This Mac BackupVault"
        ]
        for candidateName in candidates {
            let candidate = backupRoot.appendingPathComponent(candidateName, isDirectory: true)
            if prepareWritableContainer(at: candidate) {
                if candidateName != computerName {
                    Logger.shared.warning("[NAS] Falling back to writable machine folder: \(candidate.path)")
                }
                return candidate
            }
        }

        throw BackupError.permissionDenied(backupRoot)
    }

    private func prepareWritableContainer(at url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.path) {
            return DestinationStore.shared.canWrite(in: url)
        }
        do {
            try ensureDirectoryExists(at: url)
            return DestinationStore.shared.canWrite(in: url)
        } catch {
            return false
        }
    }
}
