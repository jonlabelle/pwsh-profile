function Test-Admin
{
    <#
    .SYNOPSIS
        Determines if the current PowerShell session is running with elevated privileges.

    .DESCRIPTION
        This function checks if the current PowerShell session is running with administrator
        privileges by examining the user's Windows identity and role membership.

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
        On non-Windows systems, the function may not behave as expected.

    .LINK
        https://jonlabelle.com/snippets/view/powershell/check-if-the-current-user-is-an-administrator
    #>
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
