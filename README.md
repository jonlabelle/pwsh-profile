# PowerShell Profile

[![ci](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml)

> Cross-platform PowerShell profile with auto-loading utility functions for network testing, system administration, and developer workflows.

## Table of Contents

- [Install](#install)
  - [Linux/macOS](#linuxmacos)
  - [Windows](#windows)
    - [PowerShell Desktop](#powershell-desktop)
    - [PowerShell Core](#powershell-core)
- [Features](#features)
- [Screenshot](#screenshot)
- [Available Commands](#available-commands)
  - [Network and DNS](#network-and-dns)
  - [System Administration](#system-administration)
  - [Developer](#developer)
  - [Security](#security)
  - [Active Directory](#active-directory)
  - [PowerShell Module Management](#powershell-module-management)
  - [Profile Management](#profile-management)
  - [Media Processing](#media-processing)
  - [Utilities](#utilities)
- [Update](#update)
- [Contributing](#contributing)
- [License](#license)

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

### Network and DNS

- **[`Get-CertificateExpiration`](Functions/Get-CertificateExpiration.ps1)** — Gets SSL/TLS certificate expiration dates from remote hosts
- **[`Get-CertificateDetails`](Functions/Get-CertificateDetails.ps1)** — Retrieves detailed SSL/TLS certificate information from remote hosts
- **[`Send-TcpRequest`](Functions/Send-TcpRequest.ps1)** — Sends TCP requests and retrieves responses for network testing
- **[`Test-DnsNameResolution`](Functions/Test-DnsNameResolution.ps1)** — Tests DNS name resolution using cross-platform .NET methods
- **[`Test-Port`](Functions/Test-Port.ps1)** — Tests TCP/UDP port connectivity with detailed connection information

### System Administration

- **[`Get-DotNetVersion`](Functions/Get-DotNetVersion.ps1)** — Retrieves installed .NET Framework and .NET Core versions
- **[`Invoke-ElevatedCommand`](Functions/Invoke-ElevatedCommand.ps1)** — Executes commands with elevated privileges (Run as Administrator)
- **[`Set-TlsSecurityProtocol`](Functions/Set-TlsSecurityProtocol.ps1)** — Configures TLS security protocol settings for secure network connections
- **[`Start-KeepAlive`](Functions/Start-KeepAlive.ps1)** — Prevents the system and display from sleeping
- **[`Test-Admin`](Functions/Test-Admin.ps1)** — Checks if the current PowerShell session is running as Administrator
- **[`Test-PendingReboot`](Functions/Test-PendingReboot.ps1)** — Checks if the system has pending reboot requirements
- **[`Get-SystemInfo`](Functions/Get-SystemInfo.ps1)** — Gets basic system information from local or remote computers

### Developer

- **[`Remove-DotNetBuildArtifacts`](Functions/Remove-DotNetBuildArtifacts.ps1)** — Cleans up .NET build artifacts from a project directory

### Security

- **[`Protect-PathWithPassword`](Functions/Protect-PathWithPassword.ps1)** — Encrypts files or folders with AES-256 encryption using a password
- **[`Unprotect-PathWithPassword`](Functions/Unprotect-PathWithPassword.ps1)** — Decrypts files that were encrypted with Protect-PathWithPassword

### Active Directory

- **[`Test-ADCredential`](Functions/Test-ADCredential.ps1)** — Validates Active Directory user credentials
- **[`Test-ADUserLocked`](Functions/Test-ADUserLocked.ps1)** — Test if an Active Directory user account is locked out

### PowerShell Module Management

- **[`Get-OutdatedModules`](Functions/Get-OutdatedModules.ps1)** — Check if any installed PowerShell modules have newer versions
- **[`Remove-OldModules`](Functions/Remove-OldModules.ps1)** — Removes older versions of installed PowerShell modules
- **[`Update-AllModules`](Functions/Update-AllModules.ps1)** — Updates all PowerShell modules to latest versions

### Profile Management

- **[`Show-ProfileCommands`](Functions/Show-ProfileCommands.ps1)** — Show all commands available in this PowerShell profile
- **[`Test-ProfileUpdate`](Functions/Test-ProfileUpdate.ps1)** — Checks for available profile updates from the GitHub repository

### Media Processing

- **[`Invoke-FFmpeg`](Functions/Invoke-FFmpeg.ps1)** — Converts video files using Samsung TV-friendly H.264/H.265 encoding
- **[`Rename-VideoSeasonFile`](Functions/Rename-VideoSeasonFile.ps1)** — Batch renames TV show episode files to a consistent format

### Utilities

- **[`Convert-LineEndings`](Functions/Convert-LineEndings.ps1)** — Converts line endings between Unix and Windows
- **[`Get-CommandAlias`](Functions/Get-CommandAlias.ps1)** — Displays aliases for PowerShell cmdlets
- **[`Get-IPSubnet`](Functions/Get-IPSubnet.ps1)** — Calculates IP subnet information including network/broadcast addresses
- **[`New-RandomString`](Functions/New-RandomString.ps1)** — Generates random strings, useful for passwords/tokens

## Update

To manually pull in the latest updates from [this repo](https://github.com/jonlabelle/pwsh-profile):

```powershell
Update-Profile
```

You can also check for available updates without applying them:

```powershell
Test-ProfileUpdate
```

## Contributing

Contributions are welcome! Please follow these basic guidelines:

- One function per file in Functions/ (Verb-Noun.ps1) — auto-loaded by the main profile.
- Open a [pull request](https://github.com/jonlabelle/pwsh-profile/pulls) with a brief description and include basic verification steps (lint + quick functional test).
- Keep changes cross-platform compatible per the project's conventions. See [./Functions](./Functions/) folder for examples.

## Author

[@jonlabelle](https://github.com/jonlabelle)

## License

[MIT License](LICENSE)
