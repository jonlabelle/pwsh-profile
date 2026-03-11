function Test-Admin
{
    <#
    .SYNOPSIS
        Determines if the current PowerShell session is running with elevated privileges.

    .DESCRIPTION
        This function checks if the current PowerShell session is running with elevated
        privileges by examining the appropriate security context for the platform:

        - Windows: Checks if the session is running with administrator privileges by examining
          the user's Windows identity and role membership using Windows security principals.

        - macOS/Linux: Checks if the current PowerShell process is running as root
          by examining the effective user ID (EUID).

        This provides a cross-platform way to determine if the current session has the
        necessary permissions to perform administrative tasks.

        ALIASES: Test-Root, Test-Sudo

    .PARAMETER Quiet
        When specified, suppresses any warning messages and returns only the boolean result.
        Useful for silent checks in scripts.

    .EXAMPLE
        PS > Test-Admin

        Returns $true if the current PowerShell session is running with elevated privileges
        (administrator on Windows, root on macOS/Linux), otherwise returns $false.

    .EXAMPLE
        PS > Test-Root

        Alias for Test-Admin. Returns $true if running with elevated privileges.

    .EXAMPLE
        PS > Test-Sudo

        Alias for Test-Admin. Returns $true if running with elevated privileges.

    .EXAMPLE
        PS > if (Test-Admin) {
            Write-Host "Running with elevated privileges - proceeding with administrative tasks" -ForegroundColor Green
        } else {
            Write-Warning "Not running with elevated privileges - some operations may fail"
        }

        Conditionally displays a message and performs different actions based on privilege level.

    .EXAMPLE
        PS > if (-not (Test-Admin)) {
            Write-Error "This script requires elevated privileges. Please run as administrator (Windows) or with sudo (macOS/Linux)."
            return
        }

        Exits the script early if not running with elevated privileges.

    .EXAMPLE
        PS > $isAdmin = Test-Admin -Quiet
        PS > Write-Host "Elevated privileges: $isAdmin"

        Checks privilege status without any warning messages.

    .EXAMPLE
        PS > Get-Process | Where-Object { $_.ProcessName -eq 'svchost' } |
            ForEach-Object {
                if (Test-Admin) {
                    $_ | Stop-Process -WhatIf
                } else {
                    Write-Warning "Cannot stop system processes without elevated privileges"
                }
            }

        Demonstrates conditional process management based on privilege level.

    .EXAMPLE
        PS > function Invoke-AdminTask {
            param([scriptblock]$ScriptBlock)

            if (Test-Admin) {
                & $ScriptBlock
            } else {
                Write-Error "Elevated privileges required for this operation"
            }
        }
        PS > Invoke-AdminTask { Get-EventLog -LogName Security -Newest 10 }

        Shows how to create a wrapper function that checks privileges before executing.

    .OUTPUTS
        System.Boolean
        Returns $true if running with elevated privileges, otherwise $false.

    .NOTES
        Platform-specific behavior:

        Windows:
        - Checks if the session is running as an administrator using Windows security principals
        - Uses WindowsIdentity and WindowsPrincipal to determine role membership

        macOS/Linux:
        - Checks if the effective user ID (EUID) is 0 (root)
        - Uses the `id -u` system command to determine the current process EUID
        - Returns true only when the current process is actually elevated
        - A cached sudo timestamp or SUDO_* environment variables alone do not mean the
          current PowerShell process has elevated privileges

        The function is designed to be fast and reliable, using platform-appropriate methods:
        - Windows: .NET security classes
        - Unix-like: `id -u` to get the effective user ID

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Test-Admin.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Test-Admin.ps1

    .LINK
        https://jonlabelle.com/snippets/view/powershell/check-if-the-current-user-is-an-administrator

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.security.principal.windowsprincipal

    .LINK
        https://www.man7.org/linux/man-pages/man1/id.1.html
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        ## Suppress warning messages and return only the boolean result
        [Parameter()]
        [switch]$Quiet
    )

    function Write-TestAdminWarning
    {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Message
        )

        if (-not $Quiet)
        {
            Write-Warning "Test-Admin: $Message"
        }
    }

    $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6)
    {
        $true
    }
    else
    {
        [bool]$IsWindows
    }

    $isMacOSPlatform = if ($PSVersionTable.PSVersion.Major -lt 6)
    {
        $false
    }
    else
    {
        [bool]$IsMacOS
    }

    $isLinuxPlatform = if ($PSVersionTable.PSVersion.Major -lt 6)
    {
        $false
    }
    else
    {
        [bool]$IsLinux
    }

    Write-Verbose "Platform detection - Windows: $isWindowsPlatform, macOS: $isMacOSPlatform, Linux: $isLinuxPlatform"

    if ($isWindowsPlatform)
    {
        try
        {
            Write-Verbose 'Checking Windows administrator token membership'
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)

            return [bool]$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        catch
        {
            Write-TestAdminWarning -Message "Failed to determine administrator status: $($_.Exception.Message)"
            return $false
        }
    }

    if ($isMacOSPlatform -or $isLinuxPlatform)
    {
        try
        {
            $idCommand = Get-Command -Name 'id' -CommandType Application -ErrorAction Stop |
            Select-Object -First 1
            $effectiveUserIdOutput = & $idCommand.Source -u 2>$null
            $idExitCode = $LASTEXITCODE

            if ($idExitCode -ne 0)
            {
                throw "The '$($idCommand.Source) -u' check failed with exit code $idExitCode."
            }

            $effectiveUserIdText = [string]($effectiveUserIdOutput | Select-Object -First 1)
            if ([string]::IsNullOrWhiteSpace($effectiveUserIdText))
            {
                throw "The '$($idCommand.Source) -u' check returned no effective user ID."
            }

            $effectiveUserId = 0
            if (-not [int]::TryParse($effectiveUserIdText.Trim(), [ref]$effectiveUserId))
            {
                throw "Unexpected effective user ID value '$effectiveUserIdText' returned by '$($idCommand.Source) -u'."
            }

            if ($env:SUDO_USER -or $env:SUDO_UID)
            {
                Write-Verbose 'SUDO_* environment variables are present; using only the current process EUID to determine elevation.'
            }

            Write-Verbose "Effective user ID: $effectiveUserId"

            return ($effectiveUserId -eq 0)
        }
        catch
        {
            Write-TestAdminWarning -Message "Failed to determine privilege status: $($_.Exception.Message)"
            return $false
        }
    }

    Write-TestAdminWarning -Message 'Platform detection failed or this platform is unsupported.'
    return $false
}

if (-not (Get-Command -Name 'Test-Root' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'Test-Root' alias for Test-Admin"
        Set-Alias -Name 'Test-Root' -Value 'Test-Admin' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Test-Admin: Could not create 'Test-Root' alias: $($_.Exception.Message)"
    }
}

if (-not (Get-Command -Name 'Test-Sudo' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'Test-Sudo' alias for Test-Admin"
        Set-Alias -Name 'Test-Sudo' -Value 'Test-Admin' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Test-Admin: Could not create 'Test-Sudo' alias: $($_.Exception.Message)"
    }
}
