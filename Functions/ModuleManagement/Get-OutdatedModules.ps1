function Get-OutdatedModules
{
    <#
    .SYNOPSIS
        Gets information about installed PowerShell modules that have newer versions available.

    .DESCRIPTION
        This function checks all installed PowerShell modules against the PowerShell Gallery to identify
        modules that have newer versions available. It returns detailed information about all checked modules
        including current and available versions, with an indicator showing whether they're up-to-date.
        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

    .PARAMETER ExcludeModule
        Array of module names to exclude from the outdated check. These modules will be skipped.

    .PARAMETER IncludeSystemModules
        Includes system modules in the outdated check. System modules are excluded by default for safety.

    .PARAMETER Repository
        Specifies the repository to check for newer versions. Defaults to 'PSGallery'.

    .EXAMPLE
        PS > Get-OutdatedModules

        Returns all checked modules with current version, available version, and up-to-date status.

    .EXAMPLE
        PS > Get-OutdatedModules -ExcludeModule @('PSReadLine', 'PowerShellGet')

        Gets module status while excluding specific modules from the check.

    .EXAMPLE
        PS > Get-OutdatedModules | Format-Table Name, CurrentVersion, AvailableVersion, IsUpToDate

        Displays all modules in a formatted table showing version information and update status.

    .EXAMPLE
        PS > Get-OutdatedModules | Where-Object -Not IsUpToDate

        Gets only modules that have updates available using pipeline filtering.

    .EXAMPLE
        PS > Get-OutdatedModules | Where-Object IsUpToDate

        Gets only modules that are already up-to-date.

    .EXAMPLE
        PS > Get-OutdatedModules | Where-Object Name -like 'Azure*'

        Gets status for all Azure modules using pipeline filtering.

    .EXAMPLE
        PS > $results = Get-OutdatedModules; $results | Where-Object -Not IsUpToDate | Update-AllModules

        Check all modules and selectively update only those that are outdated.

    .OUTPUTS
        [PSCustomObject[]]
        Returns custom objects with properties: Name, CurrentVersion, AvailableVersion, IsUpToDate, Repository, Description, PublishedDate, Author

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ModuleManagement/Get-OutdatedModules.ps1

        - Requires PowerShell 5.1 or later with PowerShellGet module
        - Internet connection required to check for available versions
        - System modules are excluded by default for safety
        - Results can be piped to other cmdlets for filtering and processing

    .LINK
        https://jonlabelle.com/snippets/view/markdown/powershellget-commands
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [String[]]$ExcludeModule = @(),

        [Parameter()]
        [Switch]$IncludeSystemModules,

        [Parameter()]
        [String]$Repository = 'PSGallery'
    )

    begin
    {
        Write-Verbose 'Starting outdated module check process'

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

        $moduleResults = @()
    }

    process
    {
        try
        {
            # Get all installed modules
            Write-Host 'Retrieving installed modules...' -ForegroundColor Cyan
            $installedModules = Get-InstalledModule -ErrorAction Stop

            if (-not $installedModules -or $installedModules.Count -eq 0)
            {
                Write-Host 'No modules found.' -ForegroundColor Yellow
                return
            }

            Write-Host "Found $($installedModules.Count) installed module(s) to check" -ForegroundColor Green

            $processedCount = 0
            $checkedCount = 0

            foreach ($installedModule in $installedModules)
            {
                $processedCount++
                $moduleName = $installedModule.Name

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

                # Calculate progress percentage safely
                $percentComplete = if ($installedModules.Count -gt 0)
                {
                    ($processedCount / $installedModules.Count) * 100
                }
                else
                {
                    0
                }
                Write-Progress -Activity 'Checking for outdated modules' -Status "Checking $moduleName" -PercentComplete $percentComplete

                try
                {
                    $checkedCount++
                    Write-Verbose "Checking $moduleName (current: $($installedModule.Version))"

                    # Find the latest version in the repository
                    $latestModule = Find-Module -Name $moduleName -Repository $Repository -ErrorAction Stop

                    $isUpToDate = $latestModule.Version -le $installedModule.Version

                    $moduleInfo = [PSCustomObject]@{
                        Name = $moduleName
                        CurrentVersion = $installedModule.Version
                        AvailableVersion = $latestModule.Version
                        IsUpToDate = $isUpToDate
                        Repository = $latestModule.Repository
                        Description = $latestModule.Description
                        PublishedDate = $latestModule.PublishedDate
                        Author = $latestModule.Author
                    }

                    $moduleResults += $moduleInfo

                    if (-not $isUpToDate)
                    {
                        Write-Verbose "Found outdated module: $moduleName ($($installedModule.Version) -> $($latestModule.Version))"
                    }
                    else
                    {
                        Write-Verbose "$moduleName is up to date"
                    }
                }
                catch [System.InvalidOperationException]
                {
                    Write-Warning "Module $moduleName not found in repository $Repository or access denied"
                    continue
                }
                catch
                {
                    # Handle all other exceptions including network errors
                    if ($_.Exception -is [System.Net.WebException])
                    {
                        Write-Warning "Network error checking $moduleName`: $($_.Exception.Message)"
                    }
                    else
                    {
                        Write-Warning "Error checking module $moduleName`: $($_.Exception.Message)"
                    }
                    continue
                }
            }

            Write-Progress -Activity 'Checking for outdated modules' -Completed

            # Display summary
            $outdatedCount = ($moduleResults | Where-Object { -not $_.IsUpToDate }).Count
            $upToDateCount = ($moduleResults | Where-Object { $_.IsUpToDate }).Count

            if ($outdatedCount -gt 0)
            {
                Write-Host "Found $outdatedCount outdated module(s) and $upToDateCount up-to-date module(s) out of $checkedCount checked" -ForegroundColor Yellow
            }
            else
            {
                Write-Host "All $checkedCount checked modules are up to date" -ForegroundColor Green
            }
        }
        catch [System.Management.Automation.CommandNotFoundException]
        {
            Write-Error 'PowerShellGet module not found. Please install it: Install-Module -Name PowerShellGet -Force'
            return
        }
        catch
        {
            Write-Error "Unexpected error during module check: $($_.Exception.Message)"
            Write-Verbose "Error details: $($_.Exception.GetType().FullName)"
            throw $_
        }
    }

    end
    {
        Write-Verbose 'Module check process completed'
        return $moduleResults
    }
}
