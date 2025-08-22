function Reload-Profile
{
    <#
    .SYNOPSIS
        Reload PowerShell profile.

    .DESCRIPTION
        This function reloads the current PowerShell profile and all its associated function files.
        It specifically reloads the profile from the same directory as the calling profile,
        ensuring that all functions from the Functions/ directory are properly reloaded.
        This is useful after making changes to profile scripts without needing to restart
        the PowerShell session.

    .PARAMETER Verbose
        When specified, displays each profile and function path as it's being loaded.

    .EXAMPLE
        PS> Reload-Profile
        Reloads the current PowerShell profile and all function files silently.

    .EXAMPLE
        PS> Reload-Profile -Verbose
        Reloads the current PowerShell profile and shows the path of each file being loaded.

    .NOTES
        This function uses the SuppressMessageAttribute to suppress the PSUseApprovedVerbs warning
        since 'Reload' is not an approved verb, but is maintained for backward compatibility.

        The function reloads the profile from the same directory structure as the original load,
        ensuring consistency with the auto-loading function mechanism.

    .LINK
        https://stackoverflow.com/a/5501909
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
    [CmdletBinding()]
    param()

    # Determine the profile directory - use the current profile's directory
    $profilePath = if ($PSCommandPath -and (Split-Path -Leaf $PSCommandPath) -eq 'Microsoft.PowerShell_profile.ps1')
    {
        # Called from main profile
        $PSCommandPath
    }
    elseif ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'Microsoft.PowerShell_profile.ps1')))
    {
        # Called from Functions directory
        Join-Path (Split-Path -Parent $PSScriptRoot) 'Microsoft.PowerShell_profile.ps1'
    }
    else
    {
        # Fallback to the current user's profile path
        $Profile.CurrentUserCurrentHost
    }

    if (Test-Path $profilePath)
    {
        Write-Verbose "Reloading profile: $profilePath"
        . $profilePath
    }
    else
    {
        Write-Warning "Profile not found at: $profilePath"
    }
}
