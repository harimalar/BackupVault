# BackupVault Release Prep

## Project state prepared in code

- App Sandbox enabled
- User-selected read/write file access enabled
- App-scoped bookmarks enabled
- Network client access enabled for NAS/SMB usage
- App category set to `Productivity`
- App version shown in Settings now reads from the bundle instead of hardcoded text

## Manual release decisions still required

### 1. Final bundle identifier

Current bundle identifier:

`com.BackupVault.app`

Before App Store Connect submission, set this to the final owned identifier, for example:

`com.<your-company-or-name>.BackupVault`

Update it in:

- Xcode target settings
- App ID / Signing
- App Store Connect app record

### 2. Signing team

Make sure the target uses the correct Apple Developer team for:

- Debug
- Release
- Archive / Distribution

### 3. Versioning

Current project values:

- Marketing version: `1.0`
- Build number: `1`

Before each submission:

- increment `CURRENT_PROJECT_VERSION`
- update `MARKETING_VERSION` only for user-facing releases

### 4. Public URLs required by App Store Connect

You still need live public URLs for:

- Privacy Policy URL
- Support URL

Optional but recommended:

- Marketing URL / product page

The in-app sheets are useful for users, but App Store Connect still expects public web URLs.

## Release test checklist

Run all of these using the `Release` configuration:

1. Fresh launch
2. Onboarding flow
3. Add source folder
4. USB destination selection
5. USB custom backup folder selection
6. NAS destination sign-in
7. NAS folder chooser
8. Backup run to USB
9. Backup run to NAS
10. Restore everything
11. Restore selected files/folders
12. Quit and relaunch
13. Reboot and retest NAS reconnect
14. Resize narrow/wide windows
15. Light / dark appearance

## Release build commands

Build Release:

```bash
xcodebuild -project "/Users/harirajzgopal/Downloads/BackupVault 35/BackupVault/BackupVault.xcodeproj" \
  -scheme BackupVault \
  -configuration Release \
  -derivedDataPath /tmp/BackupVaultReleaseDerivedData \
  build
```

Archive once signing is finalized:

```bash
xcodebuild -project "/Users/harirajzgopal/Downloads/BackupVault 35/BackupVault/BackupVault.xcodeproj" \
  -scheme BackupVault \
  -configuration Release \
  -archivePath /tmp/BackupVault.xcarchive \
  archive
```
