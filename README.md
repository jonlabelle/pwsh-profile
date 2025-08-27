# PowerShell Profile

[![ci](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml)

> Cross-platform PowerShell profile with auto-loading utility functions for network testing, system administration, and developer workflows.

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
- **Custom prompt** - Clean, colored PowerShell prompt
- **Utility functions** - Collection of helpful PowerShell functions for daily tasks

## Screenshot

![PowerShell Profile in Windows Terminal](term-screen-shot.png)

## Available Commands

The profile includes various utility commands organized by category:

### 🌐 Network & DNS

- **`Get-CertificateExpiration`** — Gets SSL/TLS certificate expiration dates from remote hosts
- **`Get-CertificateDetails`** — Retrieves detailed SSL/TLS certificate information from remote hosts
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

- **`Get-OutdatedModules`** — Gets information about installed PowerShell modules that have newer versions available
- **`Remove-OldModules`** — Removes older versions of installed PowerShell modules
- **`Update-AllModules`** — Updates all installed PowerShell modules to their latest versions

### 🛠️ Profile Management

- **`Reload-Profile`** — Reloads the PowerShell profile without restarting the session
- **`Test-ProfileUpdate`** — Checks for available profile updates from the GitHub repository

### 🎬 Media Processing

- **`Invoke-FFmpeg`** — Converts video files using Samsung TV-friendly H.264/H.265 encoding
- **`Rename-VideoSeasonFile`** — Batch renames video files with season/episode formatting

### 🔧 Utilities

- **`Get-CommandAlias`** — Displays aliases for PowerShell cmdlets
- **`Get-IPSubnet`** — Calculates IP subnet information including network/broadcast addresses
- **`New-RandomString`** — Generates random strings, useful for passwords/tokens

## Update

To manually pull in the latest updates from [this GitHub repo](https://github.com/jonlabelle/pwsh-profile):

```powershell
Update-Profile
```

You can also check for available updates without applying them:

```powershell
Test-ProfileUpdate
```
