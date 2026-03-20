# BackupVault

**Simplest Mac backup ever.** A minimal local backup tool for macOS: select folders → select destination (external drive or NAS) → Start Backup.

- **No accounts.** No cloud. No complex settings.
- **Destinations:** External drives or SMB (NAS) shares.
- **Incremental backups:** Only copies changed files (path, size, modified date).
- **Restore:** Browse backups, search files, restore to a folder.
- **Schedule:** Manual, daily, or when drive connected.

## Requirements

- macOS 13.0+
- Xcode 15+ (for building)

## Project structure

```
BackupVault/
├── App/
│   └── BackupVaultApp.swift
├── UI/
│   ├── ViewModels/               # MVVM: Dashboard, Backup, Restore, Settings
│   └── Views/                    # DashboardView, BackupView, RestoreView, SettingsView, HealthView
├── BackupEngine/                 # BackupCoordinator, FileScanner, FileCopyEngine, IncrementalLogic,
│                                 # NASMountService, HealthEngine, VerificationEngine
├── StorageLayer/                 # BackupDestination, BackupMetadata, BackupHealth, KeychainService, DestinationStore
├── Storage/                      # ExternalDriveManager, NASManager
├── Health/                       # BackupHealthAnalyzer, BackupHealthScore
├── Scheduler/                    # BackupSchedule, ScheduleManager, VolumeObserver, BackupScheduler
├── RestoreSystem/                # RestoreService (browse, search, restore)
├── Models/                       # BackupJob, BackupSnapshot, BackupHealthStatus
├── Utilities/                    # Logger (backup.log), FileHasher (SHA256), DiskSpaceMonitor
├── Assets.xcassets/
└── BackupVault.entitlements
```

## Build & run

1. Open `BackupVault.xcodeproj` in Xcode.
2. Select the **BackupVault** scheme and **My Mac** as destination.
3. Press **Run** (⌘R).

## Public site

This repo includes a simple GitHub Pages site in `docs/`.

Recommended public URLs after enabling GitHub Pages:

- Landing page: `https://harimalar.github.io/BackupVault/`
- Privacy Policy: `https://harimalar.github.io/BackupVault/privacy-policy.html`
- Terms of Use: `https://harimalar.github.io/BackupVault/terms.html`
- Support: `https://harimalar.github.io/BackupVault/support.html`

## Usage

1. **Backup**
   - Add folders to back up (e.g. Documents, Desktop).
   - Add destination: **Add External Drive…** (choose volume/folder) or **Add NAS (SMB)…** (host, share, username, password; stored in Keychain).
   - Optionally enable **Verify with SHA256** in the backup screen or in Settings.
   - Click **Start Backup**. Progress shows files scanned/copied, speed, and ETA.

2. **Restore**
   - Select a backup (computer + date) in the sidebar.
   - Browse or search, select items, choose restore destination (or “Restore to original location” for home folder), then **Restore Selected**.

3. **Settings**
   - **Schedule:** Manual only, Daily (set time), or When drive connected.
   - **Verification:** Toggle SHA256 verification (slower, more reliable).

## Backup layout on destination

```
BackupVault/
  <ComputerName>/
    <YYYY-MM-DD_HH-mm>/   # Snapshot folder (e.g. 2026-03-15_10-30)
      <FolderName>/       # e.g. Documents, Desktop
        ...files...
      manifest.json       # For incremental backup
      .backupvault_state.json   # Resume state (last copied file)
```

Logs are written to `~/Library/Application Support/BackupVault/backup.log` (files copied, errors, verification).

## Security

- NAS passwords are stored in **macOS Keychain** (not plaintext).
- App is sandboxed; folder and drive access is via user-selected files only.

## License

Use and modify as needed for your project.
