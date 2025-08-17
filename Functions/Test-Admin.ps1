function Test-Admin
{
    <#
    .SYNOPSIS
        Determines if the current PowerShell session is running with elevated privileges.

    .DESCRIPTION
        This function checks if the current PowerShell session is running with administrator
        privileges by examining the user's Windows identity and role membership.

        NOTE: This function only works on Windows platforms as it relies on Windows-specific
        security principals and administrator roles. On macOS and Linux, use alternative
        methods to check for root/sudo privileges.

    .EXAMPLE
        PS > Test-Admin
        Returns $true if the current PowerShell session is running as an administrator, otherwise returns $false.

    .EXAMPLE
        PS > if (Test-Admin) { Write-Host "Running as admin" } else { Write-Host "Not running as admin" }
        Conditionally displays a message based on whether the session is running with admin privileges.

    .OUTPUTS
        System.Boolean
        Returns $true if running as administrator, otherwise $false.

    .NOTES
        This function only works on Windows systems where the concept of a Windows administrator exists.
        On macOS and Linux, use alternative methods such as checking if the current user ID is 0 (root)
        or if running under sudo privileges.

    .LINK
        https://jonlabelle.com/snippets/view/powershell/check-if-the-current-user-is-an-administrator
    #>

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
        throw "Test-Admin is only supported on Windows. On $platformName, check for root privileges using methods like '`$(id -u) -eq 0' or checking `$env:USER -eq 'root'."
    }

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
