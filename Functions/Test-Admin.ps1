function Test-Admin
{
    <#
    .SYNOPSIS
        Determines if the current PowerShell session is running with elevated privileges.

    .DESCRIPTION
        This function checks if the current PowerShell session is running with administrator
        privileges by examining the user's Windows identity and role membership. It provides
        a reliable way to determine if the current session has the necessary permissions to
        perform administrative tasks.

        The function uses Windows security principals to check role membership, making it
        more reliable than checking environment variables or process names.

        NOTE: This function only works on Windows platforms as it relies on Windows-specific
        security principals and administrator roles. On macOS and Linux, use alternative
        methods to check for root/sudo privileges.

    .PARAMETER Quiet
        When specified, suppresses any warning messages and returns only the boolean result.
        Useful for silent checks in scripts.

    .EXAMPLE
        PS> Test-Admin

        Returns $true if the current PowerShell session is running as an administrator, otherwise returns $false.

    .EXAMPLE
        PS> if (Test-Admin) {
            Write-Host "Running as admin - proceeding with administrative tasks" -ForegroundColor Green
        } else {
            Write-Warning "Not running as admin - some operations may fail"
        }

        Conditionally displays a message and performs different actions based on admin privileges.

    .EXAMPLE
        PS> if (-not (Test-Admin)) {
            Write-Error "This script requires administrator privileges. Please run as administrator."
            return
        }

        Exits the script early if not running with admin privileges.

    .EXAMPLE
        PS> $isAdmin = Test-Admin -Quiet
        PS> Write-Host "Admin status: $isAdmin"

        Checks admin status without any warning messages.

    .EXAMPLE
        PS> Get-Process | Where-Object { $_.ProcessName -eq 'svchost' } |
            ForEach-Object {
                if (Test-Admin) {
                    $_ | Stop-Process -WhatIf
                } else {
                    Write-Warning "Cannot stop system processes without admin privileges"
                }
            }

        Demonstrates conditional process management based on admin privileges.

    .EXAMPLE
        PS> function Invoke-AdminTask {
            param([scriptblock]$ScriptBlock)

            if (Test-Admin) {
                & $ScriptBlock
            } else {
                Write-Error "Administrative privileges required for this operation"
            }
        }
        PS> Invoke-AdminTask { Get-EventLog -LogName Security -Newest 10 }

        Shows how to create a wrapper function that checks admin privileges before executing.

    .OUTPUTS
        System.Boolean
        Returns $true if running as administrator, otherwise $false.

    .NOTES
        This function only works on Windows systems where the concept of a Windows administrator exists.

        Alternative methods for non-Windows platforms:
        - Linux/macOS: Check if running as root with '$(id -u) -eq 0'
        - Linux/macOS: Check if running under sudo with '$env:SUDO_USER -ne $null'
        - Cross-platform: Use 'whoami' command and check the output

        The function is designed to be fast and reliable, using .NET security classes
        rather than external commands or registry checks.

    .LINK
        https://jonlabelle.com/snippets/view/powershell/check-if-the-current-user-is-an-administrator

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.security.principal.windowsprincipal
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

    # Check if running on Windows
    if (-not $script:IsWindowsPlatform)
    {
        $platformName = if ($script:IsMacOSPlatform) { 'macOS' } elseif ($script:IsLinuxPlatform) { 'Linux' } else { 'this platform' }

        if (-not $Quiet)
        {
            Write-Warning "Test-Admin is only supported on Windows. On $platformName, use alternative methods:"
            Write-Host '  - Check for root: ' -NoNewline -ForegroundColor Yellow
            Write-Host "`$(id -u) -eq 0" -ForegroundColor Cyan
            Write-Host '  - Check for sudo: ' -NoNewline -ForegroundColor Yellow
            Write-Host "`$env:SUDO_USER -ne `$null" -ForegroundColor Cyan
        }

        # Return false on non-Windows platforms instead of throwing
        return $false
    }

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
