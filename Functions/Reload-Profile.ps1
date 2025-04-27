function Reload-Profile
{
    <#
    .SYNOPSIS
        Reload PowerShell profile.

    .DESCRIPTION
        This function reloads the PowerShell profile scripts from all profile locations,
        including the current user's profile, all users profile, and host-specific profiles.
        This is useful after making changes to profile scripts without needing to restart
        the PowerShell session.

    .PARAMETER Verbose
        When specified, displays each profile path as it's being loaded.

    .EXAMPLE
        PS> Reload-Profile
        Reloads all applicable PowerShell profile scripts silently.

    .EXAMPLE
        PS> Reload-Profile -Verbose
        Reloads all applicable PowerShell profile scripts and shows the path of each profile being loaded.

    .NOTES
        This function uses the SuppressMessageAttribute to suppress the PSUseApprovedVerbs warning
        since 'Reload' is not an approved verb, but is maintained for backward compatibility.

    .LINK
        https://stackoverflow.com/a/5501909
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
    [CmdletBinding()]
    param()

    @(
        $Profile.AllUsersAllHosts,
        $Profile.AllUsersCurrentHost,
        $Profile.CurrentUserAllHosts,
        $Profile.CurrentUserCurrentHost
    ) | ForEach-Object {
        if (Test-Path $_)
        {
            Write-Verbose "Loading profile '$_'"
            . $_
        }
    }
}
