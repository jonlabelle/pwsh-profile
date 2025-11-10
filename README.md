# PowerShell Profile

[![ci](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml)

> Cross-platform PowerShell profile with auto-loading utility functions for network testing, system administration, and developer workflows.

## Features

- **Cross-platform compatibility** - Works on Windows, macOS, and Linux
- **Auto-loading functions** - All functions in the [`Functions/`](./Functions/) are auto-loaded with your profile
- **Local functions support** - Add your own functions to [`Functions/Local/`](./Functions/Local/)
- **Custom prompt** - Clean, colored PowerShell prompt

## Screenshot

![PowerShell Profile in Windows Terminal](term-screen-shot.png)

## Table of Contents

- [Install](#install)
  - [Linux/macOS](#linuxmacos)
  - [Windows](#windows)
    - [PowerShell Desktop](#powershell-desktop)
    - [PowerShell Core](#powershell-core)
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
  - [Local Functions](#local-functions)
- [Update](#update)
- [Contributing](#contributing)
- [Author](#author)
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

## Available Commands

The profile includes various utility commands organized by category:

### Network and DNS

- **[`Get-CertificateExpiration`](Functions/NetworkAndDns/Get-CertificateExpiration.ps1)** — Gets SSL/TLS certificate expiration dates from remote hosts
- **[`Get-CertificateDetails`](Functions/NetworkAndDns/Get-CertificateDetails.ps1)** — Retrieves detailed SSL/TLS certificate information from remote hosts
- **[`Invoke-Ping`](Functions/NetworkAndDns/Invoke-Ping.ps1)** — Sends ICMP echo requests with detailed statistics (cross-platform ping alternative)
- **[`Send-TcpRequest`](Functions/NetworkAndDns/Send-TcpRequest.ps1)** — Sends TCP requests and retrieves responses for network testing
- **[`Test-Bandwidth`](Functions/NetworkAndDns/Test-Bandwidth.ps1)** — Tests network bandwidth with download speed and latency measurements
- **[`Test-DnsNameResolution`](Functions/NetworkAndDns/Test-DnsNameResolution.ps1)** — Tests DNS name resolution using cross-platform .NET methods
- **[`Test-HttpResponse`](Functions/NetworkAndDns/Test-HttpResponse.ps1)** — Tests HTTP/HTTPS endpoints and returns response details (status codes, timing, headers)
- **[`Test-Port`](Functions/NetworkAndDns/Test-Port.ps1)** — Tests TCP/UDP port connectivity with detailed connection information

### System Administration

- **[`Get-DotNetVersion`](Functions/SystemAdministration/Get-DotNetVersion.ps1)** — Retrieves installed .NET Framework and .NET Core versions
- **[`Invoke-ElevatedCommand`](Functions/SystemAdministration/Invoke-ElevatedCommand.ps1)** — Executes commands with elevated privileges (Run as Administrator)
- **[`Set-TlsSecurityProtocol`](Functions/SystemAdministration/Set-TlsSecurityProtocol.ps1)** — Configures TLS security protocol settings for secure network connections
- **[`Start-KeepAlive`](Functions/SystemAdministration/Start-KeepAlive.ps1)** — Prevents the system and display from sleeping
- **[`Test-Admin`](Functions/SystemAdministration/Test-Admin.ps1)** — Checks if the current PowerShell session is running as Administrator
- **[`Test-PendingReboot`](Functions/SystemAdministration/Test-PendingReboot.ps1)** — Checks if the system has pending reboot requirements
- **[`Get-SystemInfo`](Functions/SystemAdministration/Get-SystemInfo.ps1)** — Gets basic system information from local or remote computers

### Developer

- **[`Remove-DotNetBuildArtifacts`](Functions/Developer/Remove-DotNetBuildArtifacts.ps1)** — Cleans up .NET build artifacts from a project directory
- **[`Remove-NodeModules`](Functions/Developer/Remove-NodeModules.ps1)** — Removes node_modules folders from Node.js project directories

### Security

- **[`Protect-PathWithPassword`](Functions/Security/Protect-PathWithPassword.ps1)** — Encrypts files or folders with AES-256 encryption using a password
- **[`Unprotect-PathWithPassword`](Functions/Security/Unprotect-PathWithPassword.ps1)** — Decrypts files that were encrypted with Protect-PathWithPassword

### Active Directory

- **[`Invoke-GroupPolicyUpdate`](Functions/ActiveDirectory/Invoke-GroupPolicyUpdate.ps1)** — Forces an immediate Group Policy update on Windows systems
- **[`Test-ADCredential`](Functions/ActiveDirectory/Test-ADCredential.ps1)** — Validates Active Directory user credentials
- **[`Test-ADUserLocked`](Functions/ActiveDirectory/Test-ADUserLocked.ps1)** — Test if an Active Directory user account is locked out

### PowerShell Module Management

- **[`Get-OutdatedModules`](Functions/ModuleManagement/Get-OutdatedModules.ps1)** — Check if any installed PowerShell modules have newer versions
- **[`Remove-OldModules`](Functions/ModuleManagement/Remove-OldModules.ps1)** — Removes older versions of installed PowerShell modules
- **[`Update-AllModules`](Functions/ModuleManagement/Update-AllModules.ps1)** — Updates all PowerShell modules to latest versions

### Profile Management

- **[`Show-ProfileCommands`](Functions/ProfileManagement/Show-ProfileCommands.ps1)** — Show all commands available in this PowerShell profile
- **[`Test-ProfileUpdate`](Functions/ProfileManagement/Test-ProfileUpdate.ps1)** — Checks for available profile updates from the GitHub repository

### Media Processing

- **[`Invoke-FFmpeg`](Functions/MediaProcessing/Invoke-FFmpeg.ps1)** — Converts video files using Samsung TV-friendly H.264/H.265 encoding
- **[`Rename-VideoSeasonFile`](Functions/MediaProcessing/Rename-VideoSeasonFile.ps1)** — Batch renames TV show episode files to a consistent format

### Utilities

- **[`Convert-LineEndings`](Functions/Utilities/Convert-LineEndings.ps1)** — Converts line endings between Unix and Windows
- **[`Copy-DirectoryWithExclusions`](Functions/Utilities/Copy-DirectoryWithExclusions.ps1)** — Copies directories recursively and exclude specific directories
- **[`Get-CommandAlias`](Functions/Utilities/Get-CommandAlias.ps1)** — Displays aliases for PowerShell cmdlets
- **[`Get-IPSubnet`](Functions/Utilities/Get-IPSubnet.ps1)** — Calculates IP subnet information including network/broadcast addresses
- **[`New-RandomString`](Functions/Utilities/New-RandomString.ps1)** — Generates random strings, useful for passwords/tokens
- **[`Sync-Directory`](Functions/Utilities/Sync-Directory.ps1)** — Synchronizes directories using native platform tools (rsync/robocopy)

### Local Functions

The [`Functions/Local/`](./Functions/Local/) directory is available for your **machine-local functions** that you don't want to commit to the repository. This is perfect for:

- Work-specific utilities
- Personal helper functions
- Experimental functions you're testing
- Machine-specific automations

Any PowerShell file placed in `Functions/Local/` will be automatically loaded, just like the built-in functions. The entire directory is git-ignored, so your functions will never be accidentally committed.

**See [Functions/Local/README.md](Functions/Local/README.md) for detailed usage instructions, templates, and examples.**

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
