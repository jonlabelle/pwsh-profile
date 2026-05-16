# Contributing to pwsh-profile

Thanks for your interest in contributing! This guide will help you get started.

## Getting Started

1. **Fork and clone** the repository
2. **Read the docs:**
   - [Installation guide](docs/installation.md) to set up your environment
   - [Function catalog](docs/functions.md) to understand available utilities
3. **Review the [copilot-instructions.md](.github/copilot-instructions.md)** for coding standards and patterns

## Development Setup

### Prerequisites

- PowerShell Desktop 5.1+ (Windows) or PowerShell Core 6.2+ (all platforms)
- `git` (for version control and profile updates)
- `pester` (for testing) - installed via `dev-requirements.ps1`

### Initial Setup

```powershell
# Clone your fork
git clone https://github.com/<your-username>/pwsh-profile.git
cd pwsh-profile

# Install development dependencies
pwsh -NoProfile -File ./dev-requirements.ps1
```

## Development Workflow

### Creating a New Function

1. **Choose the right category** from `Functions/{Category}/`:
   - `ActiveDirectory/` - AD and group policy operations
   - `Developer/` - Git, GitHub, Docker, dotenv utilities
   - `MediaProcessing/` - Video/audio processing
   - `ModuleManagement/` - PowerShell module operations
   - `NetworkAndDns/` - Network testing, DNS, IP utilities
   - `ProfileManagement/` - Profile loading and updates
   - `Security/` - Certificates, JWT, encryption
   - `SystemAdministration/` - System operations and admin tasks
   - `Utilities/` - General-purpose helpers

2. **Create a function file** with the naming convention `Verb-Noun.ps1`

3. **Follow the standard structure:**

   ```powershell
   function Verb-Noun {
       <#
       .SYNOPSIS
           Brief, one-line description

       .DESCRIPTION
           Detailed description with cross-platform notes if applicable

       .PARAMETER Name
           Parameter description

       .EXAMPLE
           PS > Verb-Noun -Name 'example'

           Expected output

       .OUTPUTS
           Return type and description
       #>
       [CmdletBinding()]
       [OutputType([Type])]
       param(
           [Parameter(Mandatory, ValueFromPipeline)]
           [ValidateNotNullOrEmpty()]
           [String]
           $Name
       )

       begin
       {
           Write-Verbose 'Starting function'
       }
       process
       {
           # Implementation
       }
       end
       {
           Write-Verbose 'Function completed'
       }
   }
   ```

4. **Create tests** in the appropriate `Tests/{Unit,Integration}/` subdirectory

5. **Submit a pull request** with a clear description of the function's purpose

### Code Quality Standards

#### Cross-Platform Compatibility

**Critical:** All code must work on PowerShell Desktop 5.1 (Windows) and PowerShell Core 6.2+ (Windows/macOS/Linux).

**Platform Detection Pattern:**

```powershell
if ($PSVersionTable.PSVersion.Major -lt 6)
{
    $script:IsWindowsPlatform = $true
}
else
{
    $script:IsWindowsPlatform = $IsWindows
    $script:IsMacOSPlatform = $IsMacOS
    $script:IsLinuxPlatform = $IsLinux
}
```

**Forbidden APIs (Windows-only):**

- `Resolve-DnsName` → Use `[System.Net.Dns]::GetHostAddresses()`
- Windows-specific admin cmdlets → Use equivalent .NET classes

**Path Handling:**

```powershell
# CORRECT - Works in PS 5.1 and Core
$fullPath = Join-Path -Path $baseDir -ChildPath 'subdir'

# Path resolution with ~ support (inside advanced functions)
$OutputPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

# In regular functions
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
```

#### Unicode and File Encoding

**Files with Unicode characters (box-drawing, symbols) MUST be saved as UTF-8 with BOM:**

```powershell
# Use [char] notation instead of literal characters
$sparkChars = @(' ', [char]0x2581, [char]0x2582, [char]0x2583)

# Not problematic in PS 5.1 files with UTF-8 BOM
$boxChars = @('┌', '┐', '└', '┘', '─', '│')
```

To add BOM to a file:

```powershell
Convert-LineEnding -Path "Functions/Category/Function.ps1" -Encoding UTF8BOM
```

#### Code Style

- Use **TitleCase** for main variables: `$OutputPath`, `$DnsResult`
- Use **camelCase** for internal logic: `$tempFile`, `$isValid`
- Use **splatting** for readability with multiple parameters
- Avoid backticks for line continuation; use splatting or parentheses
- Always use `-Path` and `-ChildPath` with `Join-Path` (PS 5.1 compatibility)

#### Parameter Validation

- Use `[ValidateNotNullOrEmpty()]` for required strings
- Use `[ValidateSet(...)]` for enumerated values
- Use `[ValidateScript({...})]` for complex validation
- Include helpful error messages in validation failures
- Support `ValueFromPipeline` when appropriate

#### Error Handling

```powershell
try
{
    # Operation that may fail
}
catch [System.Net.Sockets.SocketException]
{
    Write-Verbose "Socket error: $($_.Exception.Message)"
    return $false
}
catch
{
    # Re-throw unexpected errors
    throw $_
}
```

#### Documentation

- Write comprehensive comment-based help with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, and `.OUTPUTS`
- Include platform-specific notes in `.DESCRIPTION` if applicable
- Provide realistic, runnable examples in `.EXAMPLE`
- Document return types in `.OUTPUTS`

### Testing Requirements

All new functions **must** include tests:

1. **Unit tests** in `Tests/Unit/{Category}/Verb-Noun.Tests.ps1`
2. **Integration tests** (if applicable) in `Tests/Integration/{Category}/Verb-Noun.Tests.ps1`

**Test Structure:**

```powershell
BeforeAll {
    # Suppress progress bars in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function under test
    . "$PSScriptRoot/../../../Functions/Category/Verb-Noun.ps1"
}

Describe 'Verb-Noun' {
    Context 'Parameter validation' {
        It 'throws when Name is null' {
            { Verb-Noun -Name $null } | Should -Throw
        }
    }

    Context 'Functionality' {
        It 'returns expected output' {
            Verb-Noun -Name 'test' | Should -Be 'expected'
        }
    }
}
```

**Run tests locally:**

```powershell
# All tests
pwsh -NoProfile -File ./Invoke-Tests.ps1 -TestType All

# Unit only
pwsh -NoProfile -File ./Invoke-Tests.ps1 -TestType Unit

# With detailed output
pwsh -NoProfile -File ./Invoke-Tests.ps1 -TestType All -OutputFormat Detailed
```

### Code Analysis

All code must pass **PSScriptAnalyzer** with no errors:

```powershell
# Run linting
pwsh -Command "Invoke-ScriptAnalyzer -Settings PSScriptAnalyzerSettings.psd1 -Path . -Recurse"
```

The following rules are suppressed (see [PSScriptAnalyzerSettings.psd1](PSScriptAnalyzerSettings.psd1)):

- `PSAvoidUsingWriteHost` - We use `Write-Host` for user-facing output

## Submitting Changes

### Before You Commit

1. **Test locally** across platforms if possible:

   ```powershell
   # macOS/Linux with PowerShell Core
   pwsh -NoProfile -File ./Invoke-Tests.ps1 -TestType All

   # Windows (if available) with both PowerShell versions
   pwsh -NoProfile -File ./Invoke-Tests.ps1 -TestType All
   powershell -NoProfile -File ./Invoke-Tests.ps1 -TestType All
   ```

2. **Run linting:**

   ```powershell
   Invoke-ScriptAnalyzer -Settings PSScriptAnalyzerSettings.psd1 -Path . -Recurse
   ```

3. **Update documentation** if you've added new functions:
   - Add entries to `docs/functions.md` if appropriate
   - Include platform-specific notes

### Pull Request Guidelines

1. **Use a semantic pull request title:**
   - **Example:** "feat: Add Get-IPAddress function for public IP retrieval"

2. **Describe your changes:**
   - What problem does this solve?
   - Is this a breaking change?
   - Are there platform-specific considerations?

3. **Link related issues:**
   - Use `Closes #123` to auto-close issues

4. **Keep it focused:**
   - One feature or fix per PR
   - Separate refactoring from feature changes

### CI Pipeline

Your PR will automatically run:

- **PSScriptAnalyzer** - Code quality checks
- **Pester tests** - Unit and integration tests on:
  - PowerShell Core on macOS, Ubuntu, Windows
  - PowerShell Desktop 5.1 on Windows (Windows only)

All checks must pass before merging.

## Reporting Issues

See [GitHub issues](../../issues) to:

- **Report bugs** - Describe the issue, expected behavior, and steps to reproduce
- **Request features** - Explain the use case and potential implementation
- **Ask questions** - Use issues for questions or discussions about the profile

## Questions or Need Help?

- Check [Troubleshooting guide](docs/troubleshooting.md) for common issues
- Browse [existing issues](../../issues) - your question may already be answered
- Review function examples with `Find-ProfileFunction <keyword>`

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (see [LICENSE](LICENSE)).

---

**Thank you for contributing to pwsh-profile!** 🎉
