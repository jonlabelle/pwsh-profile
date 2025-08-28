function Get-OutdatedModules
{
    <#
    .SYNOPSIS
        Gets information about installed PowerShell modules that have newer versions available.

    .DESCRIPTION
        This function checks all installed PowerShell modules against the PowerShell Gallery to identify
        modules that have newer versions available. It returns detailed information about outdated modules
        including current and available versions. Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

    .PARAMETER ExcludeModule
        Array of module names to exclude from the outdated check. These modules will be skipped.

    .PARAMETER IncludeSystemModules
        Includes system modules in the outdated check. System modules are excluded by default for safety.

    .PARAMETER Repository
        Specifies the repository to check for newer versions. Defaults to 'PSGallery'.

    .EXAMPLE
        PS > Get-OutdatedModules

        Returns all outdated modules with current and available version information.

    .EXAMPLE
        PS > Get-OutdatedModules -ExcludeModule @('PSReadLine', 'PowerShellGet')

        Gets outdated modules while excluding specific modules from the check.

    .EXAMPLE
        PS > Get-OutdatedModules | Format-Table Name, CurrentVersion, AvailableVersion

        Displays outdated modules in a formatted table showing version information.

    .EXAMPLE
        PS > Get-OutdatedModules | Where-Object Name -like 'Azure*'

        Gets only outdated Azure modules using pipeline filtering.

    .EXAMPLE
        PS > $outdated = Get-OutdatedModules; $outdated | Update-AllModules -ExcludeModule @('ProblematicModule')

        Store outdated modules and use the results to selectively update modules.

    .OUTPUTS
        [PSCustomObject[]]
        Returns custom objects with properties: Name, CurrentVersion, AvailableVersion, Repository, Description

    .NOTES
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

        # Configure TLS for secure connections
        try
        {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Write-Verbose 'Configured TLS 1.2 for secure connections'
        }
        catch
        {
            Write-Warning "Could not configure TLS settings: $($_.Exception.Message)"
        }

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

        $outdatedModules = @()
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

                    if ($latestModule.Version -gt $installedModule.Version)
                    {
                        $outdatedModule = [PSCustomObject]@{
                            Name = $moduleName
                            CurrentVersion = $installedModule.Version
                            AvailableVersion = $latestModule.Version
                            Repository = $latestModule.Repository
                            Description = $latestModule.Description
                            PublishedDate = $latestModule.PublishedDate
                            Author = $latestModule.Author
                        }

                        $outdatedModules += $outdatedModule
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
            if ($outdatedModules.Count -gt 0)
            {
                Write-Host "Found $($outdatedModules.Count) outdated module(s) out of $checkedCount checked" -ForegroundColor Yellow
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
        Write-Verbose 'Outdated module check process completed'
        return $outdatedModules
    }
}
