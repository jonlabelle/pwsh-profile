<p align="center">
  <a href="installation.md">← Installation Guide</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="README.md">Docs</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="troubleshooting.md">Troubleshooting →</a>
</p>

---

# Function Catalog

> Public functions live under `Functions/{Category}` and are loaded automatically by the main profile.

## Contents

- [Network and DNS](#network-and-dns)
- [System Administration](#system-administration)
- [Developer](#developer)
- [Security](#security)
- [Active Directory](#active-directory)
- [PowerShell Module Management](#powershell-module-management)
- [Profile Management](#profile-management)
- [Media Processing](#media-processing)
- [Utilities](#utilities)

## Network and DNS

- [`ConvertTo-CidrNotation`](../Functions/NetworkAndDns/ConvertTo-CidrNotation.ps1) - Converts between subnet mask, CIDR prefix length, and wildcard mask formats.
- [`Get-DnsRecord`](../Functions/NetworkAndDns/Get-DnsRecord.ps1) - Retrieves DNS records for a specified domain name.
- [`Get-IPAddress`](../Functions/NetworkAndDns/Get-IPAddress.ps1) - Retrieves local network interface IP addresses or public external IP address.
- [`Get-IPSubnet`](../Functions/NetworkAndDns/Get-IPSubnet.ps1) - Calculates IP subnet information including network address, broadcast address, and subnet mask.
- [`Get-NetworkMetrics`](../Functions/NetworkAndDns/Get-NetworkMetrics.ps1) - Collects network performance metrics for a target host.
- [`Get-NetworkProcess`](../Functions/NetworkAndDns/Get-NetworkProcess.ps1) - Shows local network ports and the processes using them.
- [`Get-NetworkRoute`](../Functions/NetworkAndDns/Get-NetworkRoute.ps1) - Displays the local routing table as structured PowerShell objects.
- [`Get-PublicDnsServers`](../Functions/NetworkAndDns/Get-PublicDnsServers.ps1) - Returns a curated list of well-known public DNS servers.
- [`Get-ReverseDns`](../Functions/NetworkAndDns/Get-ReverseDns.ps1) - Performs reverse DNS (PTR) lookups for IP addresses.
- [`Get-Whois`](../Functions/NetworkAndDns/Get-Whois.ps1) - Performs WHOIS lookups for domain names and IP addresses.
- [`Invoke-NetworkDiagnostic`](../Functions/NetworkAndDns/Invoke-NetworkDiagnostic.ps1) - Performs comprehensive network diagnostics with visual output.
- [`Invoke-Ping`](../Functions/NetworkAndDns/Invoke-Ping.ps1) - Sends ICMP echo requests to test network connectivity.
- [`Resolve-GeoIP`](../Functions/NetworkAndDns/Resolve-GeoIP.ps1) - Resolves IP addresses to geographic location information.
- [`Send-TcpRequest`](../Functions/NetworkAndDns/Send-TcpRequest.ps1) - Sends a TCP request to a remote computer and returns the response.
- [`Show-NetworkLatencyGraph`](../Functions/NetworkAndDns/Show-NetworkLatencyGraph.ps1) - Displays ASCII graph visualizations of network latency data.
- [`Test-Bandwidth`](../Functions/NetworkAndDns/Test-Bandwidth.ps1) - Tests network bandwidth with download speed and latency measurements.
- [`Test-DnsNameResolution`](../Functions/NetworkAndDns/Test-DnsNameResolution.ps1) - Tests if a DNS name can be resolved.
- [`Test-DnsPropagation`](../Functions/NetworkAndDns/Test-DnsPropagation.ps1) - Checks DNS propagation across multiple public DNS servers.
- [`Test-HttpResponse`](../Functions/NetworkAndDns/Test-HttpResponse.ps1) - Tests HTTP/HTTPS endpoints and returns response details.
- [`Test-Port`](../Functions/NetworkAndDns/Test-Port.ps1) - Tests TCP or UDP port connectivity to target hosts.
- [`Test-TlsProtocol`](../Functions/NetworkAndDns/Test-TlsProtocol.ps1) - Tests which TLS protocols are supported by a remote server.
- [`Trace-Route`](../Functions/NetworkAndDns/Trace-Route.ps1) - Performs a cross-platform traceroute to a destination host.

## System Administration

The platform package commands share normalized package records across winget, Homebrew,
apt, and apk. Use `Get-PlatformPackage`, `Find-PlatformPackage -NonInteractive`, and
`Get-PlatformPackageDependency` when scripts need objects. Use `Find-PlatformPackage`,
`Show-InstalledPlatformPackage`, `Install-PlatformPackage`, `Remove-PlatformPackage`,
and `Upgrade-PlatformPackage` for interactive package workflows; destructive commands
also support `-WhatIf`.

| Command                                | Best use                                        |
| -------------------------------------- | ----------------------------------------------- |
| `Show-PlatformPackageManager`          | Menu-driven package workflows.                  |
| `Get-PlatformPackage`                  | Script-friendly installed package inventory.    |
| `Find-PlatformPackage -NonInteractive` | Script-friendly remote registry search.         |
| `Find-PlatformPackage`                 | Interactive remote search and optional install. |
| `Show-InstalledPlatformPackage`        | Interactive installed package browser.          |
| `Install-PlatformPackage`              | Direct, pipeline, or search-driven installs.    |
| `Upgrade-PlatformPackage`              | Interactive, filtered, or all-package upgrades. |
| `Remove-PlatformPackage`               | Interactive, filtered, or all-package removals. |
| `Get-PlatformPackageDependency`        | Direct and reverse dependency inspection.       |

- [`Find-PlatformPackage`](../Functions/SystemAdministration/Find-PlatformPackage.ps1) - Searches native platform package registries.
- [`Get-PathPermission`](../Functions/SystemAdministration/Get-PathPermission.ps1) - Shows file and directory permission details for one or more paths.
- [`Get-PlatformPackage`](../Functions/SystemAdministration/Get-PlatformPackage.ps1) - Gets installed packages from the native platform package manager.
- [`Get-PlatformPackageDependency`](../Functions/SystemAdministration/Get-PlatformPackageDependency.ps1) - Gets package dependency relationships from the native platform package manager.
- [`Get-SystemInfo`](../Functions/SystemAdministration/Get-SystemInfo.ps1) - Gets system information from local or remote computers.
- [`Get-TlsSecurityProtocol`](../Functions/SystemAdministration/Get-TlsSecurityProtocol.ps1) - Gets the current TLS security protocol configuration for the PowerShell session.
- [`Install-PlatformPackage`](../Functions/SystemAdministration/Install-PlatformPackage.ps1) - Installs packages with the native platform package manager.
- [`Invoke-ElevatedCommand`](../Functions/SystemAdministration/Invoke-ElevatedCommand.ps1) - Runs a script block with elevated privileges and passes pipeline input.
- [`Remove-PlatformPackage`](../Functions/SystemAdministration/Remove-PlatformPackage.ps1) - Removes installed packages with the native platform package manager.
- [`Set-PathPermission`](../Functions/SystemAdministration/Set-PathPermission.ps1) - Sets filesystem permissions for files and directories.
- [`Set-TlsSecurityProtocol`](../Functions/SystemAdministration/Set-TlsSecurityProtocol.ps1) - Configures TLS security protocol settings for secure network connections.
- [`Show-InstalledPlatformPackage`](../Functions/SystemAdministration/Show-InstalledPlatformPackage.ps1) - Displays installed packages from the native platform package manager.
- [`Show-PlatformPackageManager`](../Functions/SystemAdministration/Show-PlatformPackageManager.ps1) - Opens a unified console UI for native platform package management.
- [`Show-SystemResourceMonitor`](../Functions/SystemAdministration/Show-SystemResourceMonitor.ps1) - Displays a visual monitor for CPU, memory, disk, and network activity.
- [`Start-KeepAlive`](../Functions/SystemAdministration/Start-KeepAlive.ps1) - Prevents the system and display from sleeping.
- [`Test-Admin`](../Functions/SystemAdministration/Test-Admin.ps1) - Determines if the current PowerShell session is running with elevated privileges.
- [`Test-PendingReboot`](../Functions/SystemAdministration/Test-PendingReboot.ps1) - Tests whether the local computer is pending a reboot.
- [`Upgrade-PlatformPackage`](../Functions/SystemAdministration/Upgrade-PlatformPackage.ps1) - Upgrades outdated packages with the native platform package manager.

## Developer

- [`Get-DotNetVersion`](../Functions/Developer/Get-DotNetVersion.ps1) - Gets installed .NET Framework and .NET versions from local or remote computers.
- [`Get-GitHubRepositoryTopic`](../Functions/Developer/Get-GitHubRepositoryTopic.ps1) - Gets GitHub repository topics from an explicit repository or the current Git repository.
- [`Get-GitHubVariable`](../Functions/Developer/Get-GitHubVariable.ps1) - Retrieves a GitHub configuration variable from repository, environment, or organization scope.
- [`Import-DotEnv`](../Functions/Developer/Import-DotEnv.ps1) - Loads environment variables from dotenv (`.env`) files.
- [`Invoke-BfgRepoCleaner`](../Functions/Developer/Invoke-BfgRepoCleaner.ps1) - Runs BFG Repo-Cleaner against a Git repository.
- [`Invoke-DockerAutoRun`](../Functions/Developer/Invoke-DockerAutoRun.ps1) - Auto-detects a project, generates a Dockerfile, then builds and runs a container.
- [`Invoke-GitPull`](../Functions/Developer/Invoke-GitPull.ps1) - Performs a Git pull with rebase on one or more Git repositories.
- [`Invoke-Magika`](../Functions/Developer/Invoke-Magika.ps1) - Runs Magika file-type detection against files and folders.
- [`Invoke-SqlFluff`](../Functions/Developer/Invoke-SqlFluff.ps1) - Runs SQLFluff lint, fix, or format against SQL files.
- [`Remove-DockerArtifacts`](../Functions/Developer/Remove-DockerArtifacts.ps1) - Cleans up unused Docker artifacts with safety controls.
- [`Remove-DotNetBuildArtifacts`](../Functions/Developer/Remove-DotNetBuildArtifacts.ps1) - Removes `bin` and `obj` folders from .NET project directories.
- [`Remove-GitHubRepositoryTopic`](../Functions/Developer/Remove-GitHubRepositoryTopic.ps1) - Ensures one or more GitHub repository topics are absent.
- [`Remove-GitHubSecret`](../Functions/Developer/Remove-GitHubSecret.ps1) - Removes a GitHub secret from repository, environment, organization, or user scope.
- [`Remove-GitHubVariable`](../Functions/Developer/Remove-GitHubVariable.ps1) - Removes a GitHub configuration variable from repository, environment, or organization scope.
- [`Remove-GitIgnoredFiles`](../Functions/Developer/Remove-GitIgnoredFiles.ps1) - Removes ignored and optionally untracked files from a Git repository.
- [`Remove-NodeModules`](../Functions/Developer/Remove-NodeModules.ps1) - Removes `node_modules` folders from Node.js project directories.
- [`Set-GitHubRepositoryTopic`](../Functions/Developer/Set-GitHubRepositoryTopic.ps1) - Ensures one or more GitHub repository topics are present.
- [`Set-GitHubSecret`](../Functions/Developer/Set-GitHubSecret.ps1) - Creates or updates a GitHub secret at repository, environment, organization, or user scope.
- [`Set-GitHubVariable`](../Functions/Developer/Set-GitHubVariable.ps1) - Creates or updates a GitHub configuration variable at repository, environment, or organization scope.
- [`Update-DockerImages`](../Functions/Developer/Update-DockerImages.ps1) - Pulls the latest versions of local Docker images from their remote registries.

## Security

- [`ConvertFrom-JwtToken`](../Functions/Security/ConvertFrom-JwtToken.ps1) - Decodes a JWT and returns its header and payload.
- [`Get-CertificateExpiration`](../Functions/Security/Get-CertificateExpiration.ps1) - Gets the expiration date of an SSL/TLS certificate from a remote host or certificate file.
- [`Get-CertificateInfo`](../Functions/Security/Get-CertificateInfo.ps1) - Gets detailed SSL/TLS certificate information from remote hosts or certificate files.
- [`Protect-PathWithPassword`](../Functions/Security/Protect-PathWithPassword.ps1) - Encrypts files or folders with AES-256 encryption using a password.
- [`Unprotect-PathWithPassword`](../Functions/Security/Unprotect-PathWithPassword.ps1) - Decrypts files encrypted with `Protect-PathWithPassword`.

## Active Directory

- [`Invoke-GroupPolicyUpdate`](../Functions/ActiveDirectory/Invoke-GroupPolicyUpdate.ps1) - Forces an immediate Group Policy update on Windows systems.
- [`Test-ADCredential`](../Functions/ActiveDirectory/Test-ADCredential.ps1) - Tests an Active Directory username and password.
- [`Test-ADUserLocked`](../Functions/ActiveDirectory/Test-ADUserLocked.ps1) - Tests whether an Active Directory user account is locked out.

## PowerShell Module Management

- [`Get-OutdatedModules`](../Functions/ModuleManagement/Get-OutdatedModules.ps1) - Gets installed PowerShell modules that have newer versions available.
- [`Remove-OldModules`](../Functions/ModuleManagement/Remove-OldModules.ps1) - Removes older versions of installed PowerShell modules.
- [`Update-AllModules`](../Functions/ModuleManagement/Update-AllModules.ps1) - Updates installed PowerShell modules to their latest versions.

## Profile Management

- [`Find-ProfileFunction`](../Functions/ProfileManagement/Find-ProfileFunction.ps1) - Searches profile functions to help find the right command quickly.
- [`Show-ProfileFunctions`](../Functions/ProfileManagement/Show-ProfileFunctions.ps1) - Shows the available profile functions grouped by category.
- [`Test-ProfileUpdate`](../Functions/ProfileManagement/Test-ProfileUpdate.ps1) - Checks for available profile updates from the remote repository.
- [`Update-Profile`](../Functions/ProfileManagement/Update-Profile.ps1) - Updates the PowerShell profile to the latest version.

## Media Processing

- [`Get-MediaInfo`](../Functions/MediaProcessing/Get-MediaInfo.ps1) - Retrieves detailed information about media files.
- [`Invoke-FFmpeg`](../Functions/MediaProcessing/Invoke-FFmpeg.ps1) - Converts video files using Samsung-friendly H.264 or H.265 settings.
- [`Remove-ImageMetadata`](../Functions/MediaProcessing/Remove-ImageMetadata.ps1) - Removes metadata and privacy-sensitive information from images.
- [`Rename-VideoSeasonFile`](../Functions/MediaProcessing/Rename-VideoSeasonFile.ps1) - Renames files into a consistent season sequence format.

## Utilities

- [`Convert-LineEndings`](../Functions/Utilities/Convert-LineEndings.ps1) - Converts line endings between LF and CRLF with optional encoding conversion.
- [`ConvertFrom-Base64`](../Functions/Utilities/ConvertFrom-Base64.ps1) - Decodes a Base64-encoded string to text or file content.
- [`ConvertTo-Base64`](../Functions/Utilities/ConvertTo-Base64.ps1) - Converts a string or file content to Base64 encoding.
- [`ConvertTo-Markdown`](../Functions/Utilities/ConvertTo-Markdown.ps1) - Converts a URL or local file path to Markdown using Pandoc.
- [`ConvertTo-MarkdownObject`](../Functions/Utilities/ConvertTo-MarkdownObject.ps1) - Converts arbitrary PowerShell objects into Markdown text.
- [`ConvertTo-USDateTime`](../Functions/Utilities/ConvertTo-USDateTime.ps1) - Converts a local, UTC, or offset-aware date/time into major US time zones.
- [`ConvertTo-UrlSlug`](../Functions/Utilities/ConvertTo-UrlSlug.ps1) - Converts text to URL-friendly slugs or renames paths using slugified names.
- [`Copy-Directory`](../Functions/Utilities/Copy-Directory.ps1) - Copies directories with recursion, exclusions, and parallel processing options.
- [`Extract-Archives`](../Functions/Utilities/Extract-Archives.ps1) - Extracts archive files and can optionally process nested archives.
- [`Format-Bytes`](../Functions/Utilities/Format-Bytes.ps1) - Formats byte or bit quantities into human-friendly unit conversions.
- [`Get-CommandAlias`](../Functions/Utilities/Get-CommandAlias.ps1) - Lists aliases for a specified PowerShell command.
- [`Get-EncodingFromName`](../Functions/Utilities/Get-EncodingFromName.ps1) - Resolves a profile encoding name to a .NET encoding instance.
- [`Get-FileEncoding`](../Functions/Utilities/Get-FileEncoding.ps1) - Detects text file encoding using BOM and content sampling.
- [`Get-StringHash`](../Functions/Utilities/Get-StringHash.ps1) - Computes the hash value for arbitrary string input.
- [`Get-WhichCommand`](../Functions/Utilities/Get-WhichCommand.ps1) - Locates a command and displays its location or type.
- [`New-RandomString`](../Functions/Utilities/New-RandomString.ps1) - Generates random strings for passwords, tokens, and other uses.
- [`New-SymbolicLink`](../Functions/Utilities/New-SymbolicLink.ps1) - Creates a symbolic link to a file or directory.
- [`Remove-OldFiles`](../Functions/Utilities/Remove-OldFiles.ps1) - Removes files older than a specified time period.
- [`Remove-SymbolicLink`](../Functions/Utilities/Remove-SymbolicLink.ps1) - Removes a symbolic link without deleting the target.
- [`Rename-File`](../Functions/Utilities/Rename-File.ps1) - Renames files with transformations such as case conversion, normalization, replacement, and batch numbering.
- [`Replace-StringInFile`](../Functions/Utilities/Replace-StringInFile.ps1) - Finds and replaces text in files.
- [`Search-FileContent`](../Functions/Utilities/Search-FileContent.ps1) - Searches file contents with context, filtering, and colorized output.
- [`Set-FileEncoding`](../Functions/Utilities/Set-FileEncoding.ps1) - Converts one or more text files to a specified encoding.
- [`Sync-Directory`](../Functions/Utilities/Sync-Directory.ps1) - Synchronizes directories using `rsync` on macOS/Linux or `robocopy` on Windows.

---

<p align="center">
  <a href="installation.md">← Installation Guide</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="README.md">Docs</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="troubleshooting.md">Troubleshooting →</a>
</p>
