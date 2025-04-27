function Remove-AllOldModules
{
    <#
    .SYNOPSIS
        Removes all older versions of installed PowerShell modules.

    .DESCRIPTION
        This function identifies and removes older versions of PowerShell modules that are installed,
        keeping only the latest version of each module. This helps maintain a clean PowerShell environment
        and reduces disk space usage.

    .EXAMPLE
        PS > Remove-AllOldModules
        Uninstalls all older versions of PowerShell modules, keeping only the latest version of each module.

    .NOTES
        Version: 0.1
        #requires -Version 2.0 -Modules PowerShellGet
        Author: Luke Murray (Luke.Geek.NZ)
        Updated by: Jon LaBelle
        Link: https://luke.geek.nz/powershell/remove-old-powershell-modules-versions-using-powershell/

        To show all installed modules, run:
        Get-Module -ListAvailable
    #>

    $Latest = Get-InstalledModule

    foreach ($module in $Latest)
    {
        Write-Verbose -Message "Uninstalling old versions of $($module.Name) [latest is $( $module.Version)]" -Verbose
        Get-InstalledModule -Name $module.Name -AllVersions | Where-Object {$_.Version -ne $module.Version} | Uninstall-Module -Verbose
    }
}
