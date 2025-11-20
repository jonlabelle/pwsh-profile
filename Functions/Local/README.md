# Local Functions

This directory is for **machine-local functions** that you don't want to commit to the repository. It's perfect for:

- Work-specific utilities
- Personal helper functions
- Experimental functions you're testing
- Machine-specific automations
- Functions containing sensitive information

## How It Works

Any PowerShell function file (matching the pattern `*-*.ps1`, e.g. `Get-Something.ps1`) placed in this directory will be **automatically loaded** by your profile, just like the built-in functions.

**The entire `Functions/Local/` directory is git-ignored**, so your functions will never be accidentally committed to the repository.

## Usage

1. Create a new `.ps1` file in this directory following PowerShell naming conventions (e.g., `Get-MyData.ps1`, `Invoke-CustomTool.ps1`)
2. Write your function using the same patterns as [other functions](../) in this profile
3. Restart PowerShell or reload your profile
4. Your function is now available!

## Function Template

Here's a template following this profile's conventions:

```powershell
function Verb-Noun {
    <#
    .SYNOPSIS
        Brief description of what the function does

    .DESCRIPTION
        Detailed description with any cross-platform notes

    .PARAMETER Name
        Description of the parameter

    .EXAMPLE
        PS > Verb-Noun -Name 'example'

        Usage example with expected output

    .OUTPUTS
        Type of output (if any)

    .NOTES
        Any additional notes
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [String]$Name
    )

    begin {
        Write-Verbose 'Starting function'
    }

    process {
        # Your logic here
        Write-Output "Processing: $Name"
    }

    end {
        Write-Verbose 'Function completed'
    }
}
```

## Best Practices

### Cross-Platform Compatibility

If you want your functions to work across Windows, macOS, and Linux:

```powershell
# Platform detection for PowerShell 5.1 and Core
if ($PSVersionTable.PSVersion.Major -lt 6) {
    # PowerShell 5.1 - Windows only
    $script:IsWindowsPlatform = $true
} else {
    # PowerShell Core - use built-in variables
    $script:IsWindowsPlatform = $IsWindows
    $script:IsMacOSPlatform = $IsMacOS
    $script:IsLinuxPlatform = $IsLinux
}
```

### File Paths

Use .NET methods for cross-platform path handling:

```powershell
# Get absolute path (including ~) without requiring path to exist
# In advanced functions with [CmdletBinding()]:
$OutputPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

# In regular scripts or test files (without [CmdletBinding()]):
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

# Join paths
$FilePath = [System.IO.Path]::Combine($Directory, $FileName)
```

### Error Handling

```powershell
try {
    # Your code
}
catch [System.Net.Sockets.SocketException] {
    # Handle specific exceptions
    Write-Verbose "Connection failed: $($_.Exception.Message)"
    return $false
}
catch {
    # Re-throw unexpected errors
    throw $_
}
```

## Examples

### Simple Utility Function

```powershell
# File: Get-WorkProjects.ps1
function Get-WorkProjects {
    <#
    .SYNOPSIS
        Lists all work projects from my projects directory
    #>
    [CmdletBinding()]
    param()

    $ProjectsPath = "$HOME/work/projects"
    Get-ChildItem -Path $ProjectsPath -Directory |
        Select-Object Name, LastWriteTime
}
```

### Function with Pipeline Support

```powershell
# File: ConvertTo-MyFormat.ps1
function ConvertTo-MyFormat {
    <#
    .SYNOPSIS
        Converts input to custom format
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [String]$InputText
    )

    process {
        # Process each pipeline input
        $InputText.ToUpper() -replace '\s+', '_'
    }
}
```

### Cross-Platform Function

```powershell
# File: Get-SystemEditor.ps1
function Get-SystemEditor {
    <#
    .SYNOPSIS
        Gets the default text editor for the current platform
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $IsWindowsPlatform = $true
    } else {
        $IsWindowsPlatform = $IsWindows
    }

    if ($IsWindowsPlatform) {
        'notepad.exe'
    } else {
        $env:EDITOR ?? 'nano'
    }
}
```

## Testing Your Functions

Test your functions before using them in production:

```powershell
# Load function without restarting PowerShell
. ./Functions/Local/Your-Function.ps1

# Test with verbose output
Your-Function -Verbose

# Test with WhatIf (if applicable)
Your-Function -WhatIf
```

## Need Help?

- Check existing functions in other `Functions/` subdirectories for examples
- See the main [README.md](../../README.md) for project conventions
- Review [PSScriptAnalyzerSettings.psd1](../../PSScriptAnalyzerSettings.psd1) for code quality rules
