# PowerShell Profile

[![ci](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml)
[![codeql](https://github.com/jonlabelle/pwsh-profile/actions/workflows/codeql.yml/badge.svg)](https://github.com/jonlabelle/pwsh-profile/actions/workflows/codeql.yml)

> A modern, cross-platform PowerShell profile with auto-loading utility functions for network testing, system administration, and developer workflows.

This profile turns the PowerShell profile directory into a small, portable toolkit. Public functions under [`Functions`](./Functions/) are loaded automatically, machine-local helpers can live safely under [`Functions/Local`](./Functions/Local/), and the included prompt stays clean across Windows, macOS, and Linux.

## Highlights

- Works with Windows PowerShell Desktop 5.1+ and PowerShell 6+ (`pwsh`).
- Auto-loads public functions from categorized folders under [`Functions`](./Functions/).
- Preserves local-only profile content during install and update workflows.
- Includes focused tools for networking, security, package management, GitHub, Docker, encoding, and more.

## Install

### Requirements

- PowerShell Desktop 5.1+ or PowerShell 6+ (`pwsh`)
- Internet access for the installer and update checks
- `git`, optional but recommended for `Update-Profile` and `Test-ProfileUpdate`

The installer backs up profile content it may replace, preserves local paths such as `Functions/Local`, `Help`, `Modules`, `PSReadLine`, `Scripts`, and `powershell.config.json` in place, then deploys the latest profile files. See the [installation guide](docs/installation.md) for custom preservation and restore options.

Git is optional. When Git is unavailable, the installer downloads the repository zip from GitHub.

### PowerShell Core (X-Platform)

```powershell
irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-profile/main/install.ps1' |
    pwsh -NoProfile -ExecutionPolicy Bypass -
```

### Windows PowerShell Desktop 5.1

```powershell
irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-profile/main/install.ps1' |
    powershell -NoProfile -ExecutionPolicy Bypass -
```

Need custom paths, restore options, `-WhatIf`, or full clone history? See the [installation guide](docs/installation.md).

## Quick Start

After installation, open a new PowerShell session and try:

```powershell
# Browse everything the profile loaded
Show-ProfileFunction

# Search for the right command by keyword
Find-ProfileFunction dns

# Test network connectivity
Test-Port bing.com -Port 443

# Get public IP and geolocation details
Get-IPAddress -Public

# Check DNS and TLS
Test-DnsNameResolution github.com
Get-CertificateExpiration github.com

# Run a one-shot network diagnostic
Invoke-NetworkDiagnostics 'bing.com', 'microsoft.com' -MaxIterations 1
```

## Common Workflows

```powershell
# Find a command, then read its built-in help
Find-ProfileFunction certificate
Get-Help Get-CertificateExpiration -Examples

# Check for and apply profile updates
Test-ProfileUpdate
Update-Profile

# Run the test suite from a cloned repository
./Invoke-Tests.ps1 -TestType Unit
```

## Screenshots

The profile includes focused console interfaces for live diagnostics, package management, system monitoring, and command discovery.

### Network diagnostics

[`Invoke-NetworkDiagnostics`](docs/functions.md#network-and-dns) checks multiple hosts and renders live latency, packet-loss, and DNS results.

```powershell
PS > 'www.google.com', 'www.cloudflare.com' |
    Invoke-NetworkDiagnostics -Port 80 -Interval 2 -IncludeDns
```

![Invoke-NetworkDiagnostics screenshot](resources/screenshots/Invoke-NetworkDiagnostics.png "Invoke-NetworkDiagnostics in action")

### Package management

[`Show-PlatformPackageManager`](docs/functions.md#system-administration) provides a single interactive interface for winget, Homebrew, apt, and apk.

```powershell
PS > Show-PlatformPackageManager
```

![Show-PlatformPackageManager screenshot](resources/screenshots/Show-PlatformPackageManager.png "Show-PlatformPackageManager in action")

### System resource monitor

[`Show-SystemResourceMonitor`](docs/functions.md#system-administration) presents live CPU, memory, disk, network activity, and top-process data.

```powershell
PS > Show-SystemResourceMonitor
```

![Show-SystemResourceMonitor screenshot](resources/screenshots/Show-SystemResourceMonitor.png "Show-SystemResourceMonitor in action")

### Function discovery

[`Show-ProfileFunction`](docs/functions.md#profile-management) lists the loaded profile commands by category, with descriptions and optional aliases.

```powershell
PS > Show-ProfileFunction -IncludeAliases
```

![Show-ProfileFunction screenshot](resources/screenshots/Show-ProfileFunction.png "Show-ProfileFunction in action")

## Documentation

Everything you need to know about installation, functions, troubleshooting, and remoting lives in the [docs](./docs/) folder:

- [Installation guide](docs/installation.md) - installer options, restore workflows, and manual fallback steps.
- [Function catalog](docs/functions.md) - every public function grouped by category.
- [Troubleshooting](docs/troubleshooting.md) - execution policy fixes and verbose profile loading.
- [Remote sessions](docs/remote-sessions.md) - loading profile functions inside PowerShell remoting sessions.
- [Local functions](Functions/Local/README.md) - local-only helper templates and conventions.
- [Tests](Tests/README.md) - test layout and contribution guidance.

## Function Areas

| Area                                                                | Includes                                                                      |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| [Network and DNS](docs/functions.md#network-and-dns)                | DNS, ports, TLS checks, ping, traceroute, WHOIS, GeoIP, latency graphs        |
| [System Administration](docs/functions.md#system-administration)    | permissions, elevation, system info, package managers, resource monitor       |
| [Developer](docs/functions.md#developer)                            | .NET, dotenv, Git, GitHub, Docker, SQLFluff, Magika                           |
| [Utilities](docs/functions.md#utilities)                            | Base64, Markdown, time zones, copy/sync, delimited search, symlinks, archives |
| [Security](docs/functions.md#security)                              | JWT decoding, certificate inspection, password-based file protection          |
| [Active Directory](docs/functions.md#active-directory)              | credentials, account lockout checks, group policy update                      |
| [Module Management](docs/functions.md#powershell-module-management) | module update checks and cleanup                                              |
| [Profile Management](docs/functions.md#profile-management)          | function discovery and profile update checks                                  |
| [Media Processing](docs/functions.md#media-processing)              | Encoding wrappers w/ ffmpeg, image metadata and privacy cleansing             |

## Compatibility

| Capability                              | Windows PowerShell 5.1 (Windows only)    | PowerShell Core (Windows/macOS/Linux)       |
| --------------------------------------- | ---------------------------------------- | ------------------------------------------- |
| Profile loading and core functions      | Supported                                | Supported                                   |
| Unit tests                              | Supported on Windows                     | Supported                                   |
| Integration tests                       | Available when explicitly selected in CI | Supported in CI                             |
| Native package-manager and system tools | Depends on installed Windows tools       | Depends on the platform and installed tools |

Platform-specific functions and integrations document their requirements in their help. The [function catalog](docs/functions.md) groups available commands by area.

## Local Functions

Place machine-specific helpers in [`Functions/Local`](./Functions/Local/). Files there load automatically with the rest of the profile, are ignored by Git, and are preserved by the installer and update workflow.

## Updating

Pull the latest profile changes with:

```powershell
Update-Profile
```

Check for updates without applying them:

```powershell
Test-ProfileUpdate
```

Both commands require Git. If Git is unavailable, rerun the install command to fetch the latest files.

## Standalone Use

Functions can be used without loading the whole profile by dot-sourcing the function file directly:

```powershell
PS > . 'Functions/NetworkAndDns/Test-Port.ps1'
PS > Test-Port bing.com -Port 443
```

Function dependencies are lazy-loaded by the function file when needed.

## Contributing

Contributions are welcome. Please keep changes aligned with the existing structure:

- One public function per `Functions/{Category}/Verb-Noun.ps1` file.
- Private helpers may live under category-specific `Private` folders.
- Include focused Pester coverage for new behavior.
- Keep functions cross-platform unless they are clearly platform-specific.
- Open a pull request with a short description and verification steps.

See the complete [contributing guide](CONTRIBUTING.md) for development setup, coding standards, and test guidance.

## Author

[@jonlabelle](https://github.com/jonlabelle)

## License

[MIT License](LICENSE)
