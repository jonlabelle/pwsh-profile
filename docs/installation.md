# Installation Guide

[Docs home](README.md) | Previous: [Project README](../README.md) | Next: [Function Catalog](functions.md)

This page covers detailed install, restore, and fallback workflows for the PowerShell profile. For the shortest path, use the one-liners in the main [README](../README.md#install).

## Contents

- [Prerequisites](#prerequisites)
- [Quick Install](#quick-install)
- [Installer Behavior](#installer-behavior)
- [Run With Parameters](#run-with-parameters)
- [Parameters](#parameters)
- [Restore From Backup](#restore-from-backup)
- [Manual Install](#manual-install)

## Prerequisites

- PowerShell Desktop 5.1+ or PowerShell 6+ (`pwsh`)
- Internet access for install and update checks
- `git`, optional but recommended for `Update-Profile` and `Test-ProfileUpdate`

The installer works on PowerShell Desktop 5.1 and PowerShell Core 6+. If Git is available, it clones the repository. Otherwise, it downloads and extracts the repository zip from GitHub.

## Quick Install

Use the pipe form only for the default install. PowerShell does not pass named installer parameters after `pwsh -` or `powershell -`. If you need options such as `-FullCloneHistory`, `-SkipBackup`, `-RestorePath`, or `-WhatIf`, download [install.ps1](../install.ps1) first and run it with `-File`.

### PowerShell Core

```powershell
irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-profile/main/install.ps1' |
    pwsh -NoProfile -ExecutionPolicy Bypass -
```

### Windows PowerShell Desktop 5.1

```powershell
irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-profile/main/install.ps1' |
    powershell -NoProfile -ExecutionPolicy Bypass -
```

## Installer Behavior

During a normal install, the script:

- Resolves the target profile root, or uses `-ProfileRoot` if supplied.
- Preserves local paths from the existing profile directory.
- Creates a backup unless `-SkipBackup` is supplied.
- Removes the existing profile directory.
- Clones or downloads the profile repository.
- Restores preserved local paths.

By default, these paths are preserved:

- `Functions/Local`
- `Help`
- `Modules`
- `PSReadLine`
- `Scripts`
- `powershell.config.json`

## Run With Parameters

If you already cloned this repository or downloaded [install.ps1](../install.ps1), run it from the repository root:

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File ./install.ps1
```

To pass parameters while downloading the installer from GitHub, save it first and then run it with `-File`:

```powershell
$installScript = Join-Path ([System.IO.Path]::GetTempPath()) 'pwsh-profile-install.ps1'
irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-profile/main/install.ps1' -OutFile $installScript
pwsh -NoProfile -ExecutionPolicy Bypass -File $installScript -FullCloneHistory -SkipBackup
```

Use `powershell` instead of `pwsh` in the final line when installing for Windows PowerShell Desktop 5.1.

## Parameters

- `-ProfileRoot <path>` - Install into a custom profile directory.
- `-RepositoryUrl <url>` - Clone from a different Git repository URL.
- `-LocalSourcePath <path>` - Copy profile files from a local directory instead of cloning or downloading.
- `-BackupPath <path>` - Use a custom backup destination. During restore, this creates a backup of the current profile before restoring.
- `-SkipBackup` - Install without creating a backup of the current profile directory. This does not apply to restore.
- `-SkipPreserveDirectories` - Do not preserve local profile paths during install.
- `-PreserveDirectories @('Dir1','Dir2')` - Preserve only the relative profile paths you specify.
- `-RestorePath <path>` - Restore profile files from a backup directory.
- `-FullCloneHistory` - Clone the full Git history instead of the default shallow clone.
- `-WhatIf` - Preview install or restore actions without changing files.

For additional examples, inspect the comment-based help in [install.ps1](../install.ps1).

## Restore From Backup

You can restore a profile from a previous backup created by the install script. By default, restore does not create a new backup of the current profile unless you provide `-BackupPath`.

Restore from a backup without creating a new backup:

```powershell
$installScript = Join-Path ([System.IO.Path]::GetTempPath()) 'pwsh-profile-install.ps1'
irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-profile/main/install.ps1' -OutFile $installScript
pwsh -NoProfile -ExecutionPolicy Bypass -File $installScript -RestorePath 'C:\Users\you\Documents\WindowsPowerShell-backup-20251116-110000'
```

Restore and save the current profile first:

```powershell
$installScript = Join-Path ([System.IO.Path]::GetTempPath()) 'pwsh-profile-install.ps1'
irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-profile/main/install.ps1' -OutFile $installScript
pwsh -NoProfile -ExecutionPolicy Bypass -File $installScript -RestorePath 'C:\Users\you\Documents\WindowsPowerShell-backup-20251116-110000' -BackupPath 'C:\Users\you\Documents\WindowsPowerShell-backup-pre-restore'
```

## Manual Install

Use [install.ps1](../install.ps1) when possible. It handles backups, local path preservation, zip fallback, and restore workflows. If you still need a manual install, clone the repository into your profile directory:

```powershell
# Resolve profile directory
$profileDir = Split-Path -Path $PROFILE -Parent

# Backup existing profile directory
if (Test-Path -Path $profileDir) {
    $backupPath = "$profileDir-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Move-Item -Path $profileDir -Destination $backupPath
    Write-Host "Existing profile backed up to: $backupPath" -ForegroundColor Yellow
}

# Clone the repository into the profile directory
git clone 'https://github.com/jonlabelle/pwsh-profile.git' --depth 1 $profileDir
```

Restore from a manual backup:

```powershell
# Remove the new installation
Remove-Item -Path $profileDir -Recurse -Force

# Restore from backup
Move-Item -Path "$profileDir-backup-20250118-120000" -Destination $profileDir
```

For safer restoration, use [install.ps1](../install.ps1) with `-RestorePath`. Add `-BackupPath` if you want to keep a copy of the current profile before restoring.

---

[Docs home](README.md) | Previous: [Project README](../README.md) | Next: [Function Catalog](functions.md)
