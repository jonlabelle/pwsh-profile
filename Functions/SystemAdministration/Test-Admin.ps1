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

        - macOS/Linux: Checks if the user is root (UID 0) or has an active sudo session by
          examining the effective user ID and environment variables (SUDO_USER, SUDO_UID).

        This provides a cross-platform way to determine if the current session has the
        necessary permissions to perform administrative tasks.

        ALIASES: Test-Root, Test-Sudo

    .PARAMETER Quiet
        When specified, suppresses any warning messages and returns only the boolean result.
        Useful for silent checks in scripts.

    .EXAMPLE
        PS > Test-Admin

        Returns $true if the current PowerShell session is running with elevated privileges
        (administrator on Windows, root or active sudo on macOS/Linux), otherwise returns $false.

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
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Test-Admin.ps1

        Platform-specific behavior:

        Windows:
        - Checks if the session is running as an administrator using Windows security principals
        - Uses WindowsIdentity and WindowsPrincipal to determine role membership

        macOS/Linux:
        - Checks if the effective user ID (EUID) is 0 (root)
        - Checks for active sudo session via SUDO_USER or SUDO_UID environment variables
        - Checks for valid sudo timestamp (password-less sudo available via 'sudo -n')
        - Returns true if running as root OR if sudo is active OR if sudo timestamp is valid

        The function is designed to be fast and reliable, using platform-appropriate methods:
        - Windows: .NET security classes
        - Unix-like: id command to get effective user ID and environment variable checks

    .LINK
        https://jonlabelle.com/snippets/view/powershell/check-if-the-current-user-is-an-administrator

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.security.principal.windowsprincipal

    .LINK
        https://www.man7.org/linux/man-pages/man1/id.1.html
    #>

    param(
        ## Suppress warning messages and return only the boolean result
        [Parameter()]
        [switch] $Quiet
    )

    # Platform detection
    if ($PSVersionTable.PSVersion.Major -lt 6)
    {
        # PowerShell 5.1 - Windows only
        $script:IsWindowsPlatform = $true
        $script:IsMacOSPlatform = $false
        $script:IsLinuxPlatform = $false
    }
    else
    {
        # PowerShell Core - cross-platform
        $script:IsWindowsPlatform = $IsWindows
        $script:IsMacOSPlatform = $IsMacOS
        $script:IsLinuxPlatform = $IsLinux
    }

    # Windows: Check administrator role
    if ($script:IsWindowsPlatform)
    {
        try
        {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)

            return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        catch
        {
            if (-not $Quiet)
            {
                Write-Warning "Failed to determine administrator status: $($_.Exception.Message)"
            }

            # Return false if we can't determine admin status
            return $false
        }
    }

    # macOS/Linux: Check for root or active sudo session
    if ($script:IsMacOSPlatform -or $script:IsLinuxPlatform)
    {
        try
        {
            # Check if effective user ID is 0 (root)
            $euid = id -u
            if ($LASTEXITCODE -eq 0 -and $euid -eq 0)
            {
                return $true
            }

            # Check for active sudo session via environment variables (when running under sudo)
            if ($env:SUDO_USER -or $env:SUDO_UID)
            {
                return $true
            }

            # Check for active sudo timestamp (password-less sudo available)
            # 'sudo -n true' returns 0 if sudo is available without password, non-zero otherwise
            $null = sudo -n true 2>&1
            if ($LASTEXITCODE -eq 0)
            {
                return $true
            }

            return $false
        }
        catch
        {
            if (-not $Quiet)
            {
                Write-Warning "Failed to determine privilege status: $($_.Exception.Message)"
            }

            # Return false if we can't determine privilege status
            return $false
        }
    }

    # Unknown platform
    if (-not $Quiet)
    {
        Write-Warning 'Test-Admin: Platform detection failed or unsupported platform'
    }

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
        Write-Warning "Failed to create 'Test-Root' alias: $($_.Exception.Message)"
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
        Write-Warning "Failed to create 'Test-Sudo' alias: $($_.Exception.Message)"
    }
}
