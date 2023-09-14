function Remove-AllOldModules
{
    <#
        .SYNOPSIS
            Basic function to remove old PowerShell modules which are installed.

            Description: This little snippet with remove any old PowerShell modules (that are not the latest version), which are installed.

        .NOTES
            Version: 0.1
            #requires -Version 2.0 -Modules PowerShellGet
            Author: Luke Murray (Luke.Geek.NZ)
            Link: https://luke.geek.nz/powershell/remove-old-powershell-modules-versions-using-powershell/
    #>

    #
    # Added to my pwsh profile:
    # /Users/jon/.config/powershell/profile.ps1
    #
    # Snippet:
    # https://jonlabelle.com/snippets/view/powershell/remove-old-powershell-modules
    #
    # To show all installed modules, run:
    # Get-Module -ListAvailable
    #

    $Latest = Get-InstalledModule

    foreach ($module in $Latest)
    {
        Write-Verbose -Message "Uninstalling old versions of $($module.Name) [latest is $( $module.Version)]" -Verbose
        Get-InstalledModule -Name $module.Name -AllVersions | Where-Object {$_.Version -ne $module.Version} | Uninstall-Module -Verbose
    }
}
