# PowerShell Profile

[![ci](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml)

> Cross-platform PowerShell profile with auto-loading utility functions for network testing, system administration, and developer workflows

## Install

~~Overlay~~ Overwrite your [PowerShell profile path](https://gist.github.com/jonlabelle/f2a4fdd989dbfe59e444e0beaf07bcc9) with the contents of this repository.

Choose your appropriate platform:

- [Linux/macOS](#linuxmacos)
- [Windows](#windows)
  - [PowerShell Desktop](#powershell-desktop)
  - [PowerShell Core](#powershell-core)

### Linux/macOS

```powershell
git clone 'https://github.com/jonlabelle/pwsh-profile.git' $HOME/.config/powershell
```

### Windows

#### PowerShell Desktop

```powershell
git clone 'https://github.com/jonlabelle/pwsh-profile.git' $HOME\Documents\WindowsPowerShell
```

#### PowerShell Core

```powershell
git clone 'https://github.com/jonlabelle/pwsh-profile.git' $HOME\Documents\PowerShell
```

## Features

- **Cross-platform compatibility** - Works on Windows, macOS, and Linux
- **Auto-loading functions** - All functions in the `Functions/` directory are automatically loaded
- **Automatic update notifications** - Background checks for profile updates without slowing startup
- **Custom prompt** - Clean, colored PowerShell prompt
- **Utility functions** - Collection of helpful PowerShell functions for daily tasks

## Screenshot

![PowerShell Profile in Windows Terminal](term-screen-shot.png)

## Available Commands

The profile includes various utility commands organized by category:

### 🌐 Network & DNS

- **`Get-CertificateExpiration`** — Gets SSL/TLS certificate expiration dates from remote hosts
- **`Send-TcpRequest`** — Sends TCP requests and retrieves responses for network testing
- **`Test-DnsNameResolution`** — Tests DNS name resolution using cross-platform .NET methods
- **`Test-Port`** — Tests TCP/UDP port connectivity with detailed connection information

### 🔧 System Administration

- **`Get-DotNetVersion`** — Retrieves installed .NET Framework and .NET Core versions
- **`Invoke-ElevatedCommand`** — Executes commands with elevated privileges (Run as Administrator)
- **`Start-KeepAlive`** — Prevents system sleep/timeout by simulating keypress activity
- **`Test-Admin`** — Checks if the current PowerShell session is running as Administrator
- **`Test-PendingReboot`** — Checks if the system has pending reboot requirements

### 🔐 Active Directory & Security

- **`Test-ADCredential`** — Validates Active Directory user credentials

### 📦 PowerShell Module Management

- **`Remove-AllOldModules`** — Removes older versions of installed PowerShell modules
- **`Update-AllModules`** — Updates all installed PowerShell modules to their latest versions

### 🛠️ Profile Management

- **`Reload-Profile`** — Reloads the PowerShell profile without restarting the session
- **`Test-ProfileUpdate`** — Checks for available profile updates from the GitHub repository

### 🎬 Media Processing

- **`Invoke-FFmpeg`** — Converts video files using Samsung TV-friendly H.264/H.265 encoding
- **`Rename-VideoSeasonFile`** — Batch renames video files with season/episode formatting

### 🔧 Utilities

- **`Get-CmdletAlias`** — Displays aliases for PowerShell cmdlets
- **`Get-IPSubnet`** — Calculates IP subnet information including network/broadcast addresses
- **`New-RandomAlphaNumericString`** — Generates random alphanumeric strings for passwords/tokens

## Update

To manually pull in the latest updates from [this GitHub repo](https://github.com/jonlabelle/pwsh-profile):

```powershell
Update-Profile
```

## Automatic Update Checks

The profile [automatically checks for updates](./Functions/Test-ProfileUpdate.ps1) when it loads in interactive mode and will prompt you to update if updates are available. The check runs in the background without slowing down your profile startup.

When updates are detected, you'll be asked:

```text
Profile updates are available!
Would you like to update your profile now? (Y/N)
```

Choose "Y" or "Yes" to update immediately, or "N" to skip and update later manually with `Update-Profile`.

**Note:** Update checks only run in interactive PowerShell sessions to avoid interrupting automated scripts or CI/CD pipelines.

To disable automatic profile update checks entirely, create an empty `.disable-profile-update-check` file in your profile directory:

```powershell
# For Windows PowerShell Desktop
New-Item -Path "$HOME\Documents\WindowsPowerShell\.disable-profile-update-check" -ItemType File

# For PowerShell Core
New-Item -Path "$HOME\Documents\PowerShell\.disable-profile-update-check" -ItemType File
```
