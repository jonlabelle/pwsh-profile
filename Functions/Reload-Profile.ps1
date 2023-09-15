<#
.SYNOPSIS
    Reload PowerShell profile.

.LINK
    https://stackoverflow.com/a/5501909
#>
function Reload-Profile
{
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
            Write-Verbose "Reloading '$_'"
            . $_
        }
    }
}
