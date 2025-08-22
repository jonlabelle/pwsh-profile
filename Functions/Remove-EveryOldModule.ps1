function Remove-EveryOldModule
{
    <#
    .SYNOPSIS
        Removes all older versions of installed PowerShell modules.

    .DESCRIPTION
        This function identifies and removes older versions of PowerShell modules that are installed,
        keeping only the latest version of each module. This helps maintain a clean PowerShell environment
        and reduces disk space usage. Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

    .PARAMETER ExcludeModule
        Array of module names to exclude from cleanup. These modules will not have old versions removed.

    .PARAMETER WhatIf
        Shows what modules would be removed without actually removing them.

    .PARAMETER Force
        Forces removal without prompting for confirmation on protected modules.

    .PARAMETER IncludeSystemModules
        Includes system modules in the cleanup process. Use with caution.

    .EXAMPLE
        PS > Remove-AllOldModules

        Removes all older versions of PowerShell modules, keeping only the latest version of each.

    .EXAMPLE
        PS > Remove-AllOldModules -ExcludeModule @('PSReadLine', 'PowerShellGet') -WhatIf

        Shows what would be removed while excluding specific modules from cleanup.

    .EXAMPLE
        PS > Remove-AllOldModules -Force -Verbose

        Forces removal of old module versions with verbose output.

    .EXAMPLE
        PS > Remove-AllOldModules -IncludeSystemModules -WhatIf

        Shows what would be removed including system modules (use with caution).

    .EXAMPLE
        PS > Remove-AllOldModules -ExcludeModule @('Azure*', 'PowerShellGet') -IncludeSystemModules

        Removes old versions including system modules but excludes Azure modules and PowerShellGet.

    .EXAMPLE
        PS > Remove-AllOldModules -Confirm

        Removes old module versions with interactive confirmation for each removal operation.

    .EXAMPLE
        PS > Remove-AllOldModules -ExcludeModule @('PSReadLine') -Force -Verbose

        Forces removal with verbose output while excluding PSReadLine from cleanup.

    .OUTPUTS
        [System.Void]
        No output is returned, but progress information is displayed.

    .NOTES
        - Requires PowerShell 5.1 or later with PowerShellGet module
        - May require elevated permissions on some systems
        - System modules are excluded by default for safety
        - Always keeps the newest version of each module

        Original concept by Luke Murray (Luke.Geek.NZ)
        Enhanced for cross-platform compatibility and error handling

    .LINK
        https://luke.geek.nz/powershell/remove-old-powershell-modules-versions-using-powershell/
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Void])]
    param(
        [Parameter()]
        [String[]]$ExcludeModule = @(),

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Switch]$IncludeSystemModules
    )

    begin
    {
        Write-Verbose 'Starting old module cleanup process'

        # System modules that should typically be excluded for safety
        $systemModules = @(
            'Microsoft.PowerShell.*',
            'PowerShellGet',
            'PackageManagement',
            'PSReadLine'
        )

        # Build the final exclusion list
        $finalExcludeList = $ExcludeModule
        if (-not $IncludeSystemModules)
        {
            $finalExcludeList += $systemModules
            Write-Verbose "Excluding system modules: $($systemModules -join ', ')"
        }
    }

    process
    {
        try
        {
            # Get all installed modules
            Write-Host 'Retrieving installed modules...' -ForegroundColor Cyan
            $allModules = Get-InstalledModule -ErrorAction Stop

            if (-not $allModules)
            {
                Write-Host 'No modules found.' -ForegroundColor Yellow
                return
            }

            Write-Host "Found $($allModules.Count) installed module(s)" -ForegroundColor Green

            $processedCount = 0
            $removedCount = 0

            foreach ($latestModule in $allModules)
            {
                $processedCount++
                $moduleName = $latestModule.Name

                # Check if module should be excluded
                $shouldExclude = $false
                foreach ($excludePattern in $finalExcludeList)
                {
                    if ($moduleName -like $excludePattern)
                    {
                        $shouldExclude = $true
                        break
                    }
                }

                if ($shouldExclude)
                {
                    Write-Verbose "Skipping excluded module: $moduleName"
                    continue
                }

                Write-Progress -Activity 'Cleaning up old module versions' -Status "Processing $moduleName" -PercentComplete (($processedCount / $allModules.Count) * 100)

                try
                {
                    # Get all versions of this module
                    $allVersions = Get-InstalledModule -Name $moduleName -AllVersions -ErrorAction Stop
                    $oldVersions = $allVersions | Where-Object { $_.Version -ne $latestModule.Version }

                    if ($oldVersions)
                    {
                        $oldVersionList = ($oldVersions | ForEach-Object { $_.Version }) -join ', '
                        Write-Host "Processing $moduleName [latest: $($latestModule.Version)] - removing versions: $oldVersionList" -ForegroundColor Cyan

                        foreach ($oldVersion in $oldVersions)
                        {
                            if ($PSCmdlet.ShouldProcess("$moduleName version $($oldVersion.Version)", 'Uninstall'))
                            {
                                try
                                {
                                    $uninstallParams = @{
                                        Name = $moduleName
                                        RequiredVersion = $oldVersion.Version
                                        Verbose = $VerbosePreference -eq 'Continue'
                                        ErrorAction = 'Stop'
                                    }
                                    if ($Force)
                                    {
                                        $uninstallParams.Force = $true
                                    }

                                    Uninstall-Module @uninstallParams
                                    $removedCount++
                                    Write-Verbose "Successfully removed $moduleName version $($oldVersion.Version)"
                                }
                                catch [System.InvalidOperationException]
                                {
                                    Write-Warning "Could not remove $moduleName version $($oldVersion.Version): Module may be in use or protected"
                                }
                                catch [System.UnauthorizedAccessException]
                                {
                                    Write-Warning "Access denied removing $moduleName version $($oldVersion.Version): Try running with elevated permissions"
                                }
                                catch
                                {
                                    Write-Warning "Failed to remove $moduleName version $($oldVersion.Version): $($_.Exception.Message)"
                                }
                            }
                        }
                    }
                    else
                    {
                        Write-Verbose "No old versions found for $moduleName"
                    }
                }
                catch
                {
                    Write-Warning "Error processing module $moduleName`: $($_.Exception.Message)"
                    continue
                }
            }

            Write-Progress -Activity 'Cleaning up old module versions' -Completed

            if ($removedCount -gt 0)
            {
                Write-Host "Successfully removed $removedCount old module version(s)" -ForegroundColor Green
            }
            else
            {
                Write-Host 'No old module versions found to remove' -ForegroundColor Yellow
            }
        }
        catch [System.Management.Automation.CommandNotFoundException]
        {
            Write-Error 'PowerShellGet module not found. Please install it: Install-Module -Name PowerShellGet -Force'
        }
        catch
        {
            Write-Error "Unexpected error during module cleanup: $($_.Exception.Message)"
            Write-Verbose "Error details: $($_.Exception.GetType().FullName)"
            throw $_
        }
    }

    end
    {
        Write-Verbose 'Old module cleanup process completed'
    }
}
