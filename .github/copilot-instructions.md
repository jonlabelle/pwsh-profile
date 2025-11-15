# PowerShell Profile Codebase Instructions

- Do NOT create summaries of work performed in Markdown files.
- Be sure to cleanup any temporary files created during tasks.
- Use the _tmp_ directory of the repository for temporary files during tests, not system temp directories (e.g. not the `/tmp` directory).

## Architecture Overview

This is a **cross-platform PowerShell profile system** that provides utility functions for Windows, macOS, and Linux. Functions are auto-loaded via dot-sourcing from the `Functions/` directory.

**Core Structure:**

- `Microsoft.PowerShell_profile.ps1` - Main profile that dot-sources all functions
- `Functions/` - Individual utility functions (one per file)
- `PSScriptAnalyzerSettings.psd1` - Linting configuration
- `.github/workflows/ci.yml` - Cross-platform CI testing

## Cross-Platform Compatibility Requirements

**CRITICAL:** All code must be compatible with:

- PowerShell Desktop 5.1 (Windows only)
- PowerShell Core 6.2+ (Windows, macOS, Linux)

### Platform Detection Pattern

```powershell
if ($PSVersionTable.PSVersion.Major -lt 6)
{
    # PowerShell 5.1 - Windows only
    $script:IsWindowsPlatform = $true
}
else
{
    # PowerShell Core - use built-in variables
    $script:IsWindowsPlatform = $IsWindows
    $script:IsMacOSPlatform = $IsMacOS
    $script:IsLinuxPlatform = $IsLinux
}
```

### Variable Naming Conventions

- Use TitleCase for main function variables: `$OutputPath`, `$DnsResult`, `$Path`; or `-OutputPath`, `-DnsName`, `-Path`
- Use camelCase variables for internal logic: `$tempFile`, `$dnsEntries`, `$isValid`

### Cross-Platform Considerations

- **DNS Resolution:** Use `[System.Net.Dns]::GetHostAddresses()` instead of Windows-only `Resolve-DnsName`
- **File Paths:** Use `[System.IO.Path]::` methods for cross-platform compatibility
- **Path Resolution:** For arbitrary strings/variables (and to normalize to an absolute path without requiring the path to exist), including the `~` symbol:

  ```powershell
  $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

  # If you're inside an advanced function, you can also use:
  $OutputPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

  # Note: Does NOT require the target to exist.
  ```

- **Network Testing:** Prefer .NET Socket classes over Windows-specific cmdlets
- **Admin Detection:** `Test-Admin` function only works on Windows

## Function Development Patterns

### Standard Function Structure

```powershell
function Verb-Noun {
    <#
    .SYNOPSIS
        Brief description

    .DESCRIPTION
        Detailed description with cross-platform notes

    .PARAMETER Name
        Parameter description

    .EXAMPLE
        PS > Verb-Noun -Name 'example'

        Usage example with expected output

    .OUTPUTS
        Return type description
    #>
    [CmdletBinding()]
    [OutputType([Type])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [String]$Name
    )

    begin
    {
        Write-Verbose 'Starting function'
    }
    process
    {
        # Main logic here
    }
    end
    {
        Write-Verbose 'Function completed'
    }
}
```

### Error Handling Patterns

- Use specific exception types: `catch [System.Net.Sockets.SocketException]`
- Return `$false` for expected failures (like DNS not found)
- Re-throw unexpected errors: `throw $_`
- Always include verbose logging: `Write-Verbose "Error: $($_.Exception.Message)"`

### Validation Patterns

- Use `ValidateScript` for complex validation (e.g., IP addresses)
- Include helpful error messages in validation failures
- Use `ValidateSet` for enumerated values
- Support pipeline input with `ValueFromPipeline`

## Testing and Quality

### Development Workflow

```bash
# Run linting (matches CI)
pwsh -Command "Invoke-ScriptAnalyzer -Settings PSScriptAnalyzerSettings.psd1 -Path . -Recurse"

# Test function interactively
pwsh -NoProfile -Command ". ./Functions/YourFunction.ps1; Test-YourFunction -Verbose"
```

### CI Pipeline

- Tests run on macOS, Ubuntu, Windows with PowerShell Core
- Additional Windows-only test with PowerShell Desktop 5.1
- PSScriptAnalyzer must pass with zero errors
- Warnings are acceptable but tracked

## Project-Specific Conventions

### Suppressed PSScriptAnalyzer Rules

- `PSAvoidUsingWriteHost` - Allow `Write-Host` for user-facing output
- `PSUseShouldProcessForStateChangingFunctions` - Profile functions don't need `-WhatIf`

### File Organization

- One function per file in `Functions/`
- File naming: `Verb-Noun.ps1` (matches function name)
- Auto-loaded by profile via dot-sourcing pattern

### Profile Management

- `Update-Profile` - Git pulls latest changes (requires restart to reload profile)
- Custom prompt function changes `PS >` color to cyan

## Key Functions Reference

- **Test-DnsNameResolution**: Cross-platform DNS testing using .NET methods
- **Invoke-FFmpeg**: Complex media processing with platform-specific executable detection
- **Test-Port**: Network connectivity testing with TCP/UDP support
- **Test-ADCredential**: Windows-only Active Directory authentication
- **Get-IP**: Advanced IP address and subnet calculations with custom methods

## Integration Points

- **Git Integration**: Profile updates via `git pull` in `Update-Profile`
- **External Tools**: FFmpeg path detection across platforms
- **System APIs**: Direct .NET class usage for cross-platform functionality
- **PowerShell Modules**: PSScriptAnalyzer for code quality enforcement
