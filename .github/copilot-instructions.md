# PowerShell Profile Codebase Instructions

- Do NOT create summaries of work performed in Markdown files.
- Be sure to cleanup any temporary files created during tasks.
- Use the _tmp_ directory of the repository for temporary files during tests, not system-level temp directories (e.g. e.g the `/tmp` directory).
- Under no circumstances should you ever commit changes directly to the repository. Ever!

## Architecture Overview

This is a modern, **cross-platform PowerShell profile system** that provides utility functions for Windows, macOS, and Linux. Functions are auto-loaded via dot-sourcing from the `Functions/{Category}` directory.

**Core Structure:**

- `Microsoft.PowerShell_profile.ps1` - Main profile that dot-sources all functions
- `Functions/{Category}` - Individual functions (one per file)
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
- **Join-Path Usage:** Always use named parameters `-Path` and `-ChildPath` for PowerShell 5.1 compatibility. Never use `-AdditionalChildPath` (not available in PS 5.1):

  ```powershell
  # CORRECT - Works in PS 5.1 and Core
  $fullPath = Join-Path -Path $baseDir -ChildPath 'subdir'
  $nestedPath = Join-Path -Path (Join-Path -Path $baseDir -ChildPath 'subdir') -ChildPath 'file.txt'

  # WRONG - Positional parameters (avoid for clarity)
  $fullPath = Join-Path $baseDir 'subdir'

  # WRONG - Not available in PowerShell 5.1
  $fullPath = Join-Path -Path $baseDir -ChildPath 'subdir' -AdditionalChildPath 'file.txt'
  ```

- **Path Resolution:** For arbitrary strings/variables (and to normalize to an absolute path without requiring the path to exist), including the `~` symbol:

  ```powershell
  # Inside advanced functions (with [CmdletBinding()]) - PREFERRED for PS 5.1 compatibility:
  $OutputPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

  # In regular functions or scripts:
  $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

  # Note: Does NOT require the target to exist.
  # Note: Use $PSCmdlet version in advanced functions for better pipeline/PS 5.1 compatibility.
  ```

- **Network Testing:** Prefer .NET Socket classes over Windows-specific cmdlets
- **Admin Detection:** `Test-Admin` function only works on Windows

### File Encoding for Unicode Characters

**CRITICAL for PowerShell 5.1 compatibility:**

PowerShell 5.1 requires UTF-8 with BOM (Byte Order Mark) to properly parse files containing Unicode characters such as:

- Box-drawing characters (═, ║, ╔, ╗, ╚, ╝, ┌, ┐, └, ┘, ├, ┤, ┬, ┴, ┼, │, ─)
- Block elements (█, ▓, ▒, ░, ▄, ▀, ▁, ▂, ▃, ▅, ▆, ▇)
- Special symbols (✓, ✗, ✖, •, ○, ●)

**Requirements:**

1. **All `.ps1` files with Unicode characters MUST be saved as UTF-8 with BOM**
2. **Use `[char]` notation for Unicode characters in code when possible:**

   ```powershell
   # GOOD - Works in both PS 5.1 and Core
   $sparkChars = @(' ', [char]0x2581, [char]0x2582, [char]0x2583, [char]0x2584, [char]0x2585, [char]0x2586, [char]0x2587, [char]0x2588)

   # PROBLEMATIC in PS 5.1 without BOM
   $sparkChars = @(' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█')
   ```

3. **Never use curly quotes in code** - always use straight quotes:
   - ❌ WRONG: `'string'` or `"string"` (curly quotes)
   - ✅ CORRECT: `'string'` or `"string"` (straight quotes)

**How to add UTF-8 BOM to a file:**

```powershell
$path = "path\to\file.ps1"
$content = Get-Content -Path $path -Raw -Encoding UTF8
$utf8WithBom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($path, $content, $utf8WithBom)
```

Alternatively, use the [`Convert-LineEndings`](../Functions/Utilities/Convert-LineEndings.ps1) function which can convert encoding in a single command:

```powershell
Convert-LineEndings -Path "path\to\file.ps1" -Encoding UTF8BOM
```

**Testing for encoding issues:**

Always test functions in both PowerShell 5.1 and Core:

```powershell
# Test in PowerShell 5.1
powershell -NoProfile -File ".\Functions\Category\Function.ps1"

# Test in PowerShell Core
pwsh -NoProfile -File ".\Functions\Category\Function.ps1"
```

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

### Loading Dependencies on Other Profile Functions

When a function requires another function from this repository as a dependency, use a helper function to load it on demand. This allows functions to be loaded individually (outside the profile) while still ensuring dependencies are available.

**Pattern:**

```powershell
function Your-Function
{
    param(...)

    begin
    {
        # Helper function to load dependencies on demand
        function Import-DependencyIfNeeded
        {
            param(
                [Parameter(Mandatory)]
                [String]$FunctionName,

                [Parameter(Mandatory)]
                [String]$RelativePath
            )

            if (-not (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue))
            {
                Write-Verbose "$FunctionName is required - attempting to load it"

                # Resolve path from current script location
                $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath $RelativePath
                $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)

                if (Test-Path -Path $dependencyPath -PathType Leaf)
                {
                    try
                    {
                        . $dependencyPath
                        Write-Verbose "Loaded $FunctionName from: $dependencyPath"
                    }
                    catch
                    {
                        throw "Failed to load required dependency '$FunctionName' from '$dependencyPath': $($_.Exception.Message)"
                    }
                }
                else
                {
                    throw "Required function '$FunctionName' could not be found. Expected location: $dependencyPath"
                }
            }
            else
            {
                Write-Verbose "$FunctionName is already loaded"
            }
        }

        # Load dependency if needed
        Import-DependencyIfNeeded -FunctionName 'Some-RequiredFunction' -RelativePath '..\Category\Some-RequiredFunction.ps1'
    }

    process
    {
        # Use the dependency
        Some-RequiredFunction -Parameter 'value'
    }
}
```

**Example from `Import-DotEnv`:**

```powershell
# Load Invoke-ElevatedCommand if needed for Machine scope
if ($Scope -eq 'Machine' -and $script:IsWindowsPlatform)
{
    Import-DependencyIfNeeded -FunctionName 'Invoke-ElevatedCommand' -RelativePath '..\SystemAdministration\Invoke-ElevatedCommand.ps1'
}
```

**Key Benefits:**

- Functions can be dot-sourced individually without knowing dependency locations
- Dependencies are only loaded when needed (conditional loading)
- Clear error messages if dependencies are missing
- Works with relative paths using `$PSScriptRoot`
- Avoids duplicate loading with `Get-Command` check

## Testing and Quality

### Suppressing Progress Bars in Tests

All Pester test files must suppress progress indicators in the top-level `BeforeAll` block to prevent freezing in non-interactive environments (CI, background terminals):

```powershell
BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function under test
    . "$PSScriptRoot/../../../Functions/Category/Verb-Noun.ps1"
}
```

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

### Creating Aliases

Aliases for functions should go at the very end of the function, in the same file. The active environment must be checked to ensure existing command or alias names are not overwritten.

This example is from `Get-WhichCommand` that will create the alias `which` only if it does not already exist:

```powershell
# Create 'which' alias only if the native which command doesn't exist
if (-not (Get-Command -Name 'which' -CommandType Application -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'which' alias for Get-WhichCommand"
        Set-Alias -Name 'which' -Value 'Get-WhichCommand' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Get-WhichCommand: Could not create 'which' alias: $($_.Exception.Message)"
    }
}
```

> [!Important]
> We use `Get-Command` (instead of `Get-Alias`) to check for native `which` commands (e.g., on Linux or macOS). If such commands exist, the alias will not be created, preventing conflicts.

`Get-Command` searches for all command types in PowerShell:

- `Alias` - Existing aliases
- `Function` - PowerShell functions (including profile functions)
- `Cmdlet` - Built-in PowerShell cmdlets
- `Application` - Native executables in PATH (like which, base64, etc.)
- `ExternalScript` - PowerShell script files (.ps1)
- `Filter` - PowerShell filters
- `Configuration` - DSC configurations

### Suppressed PSScriptAnalyzer Rules

- `PSAvoidUsingWriteHost` - Allow `Write-Host` for user-facing output
- `PSUseShouldProcessForStateChangingFunctions` - Profile functions don't need `-WhatIf`

### File Organization

- One function per file in `Functions/{Category}`
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
