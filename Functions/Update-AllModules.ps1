function Update-AllModules
{
    <#
    .SYNOPSIS
        Updates all installed PowerShell modules to their latest versions.

    .DESCRIPTION
        This function updates all installed PowerShell modules to their latest versions from the PowerShell Gallery.
        Each module is updated individually with proper error handling and progress reporting. It supports excluding
        specific modules and can optionally configure PSGallery trust. Cross-platform compatible with PowerShell 5.1+
        on Windows, macOS, and Linux.

    .PARAMETER ExcludeModule
        Array of module names to exclude from updates.

    .PARAMETER TrustPSGallery
        Automatically sets PSGallery installation policy to Trusted if not already configured.

    .PARAMETER Force
        Forces the update even if a newer version is already installed.

    .PARAMETER WhatIf
        Shows what modules would be updated without actually updating them.

    .EXAMPLE
        PS > Update-AllModules

        Updates all installed PowerShell modules to their latest versions.

    .EXAMPLE
        PS > Update-AllModules -ExcludeModule @('Azure', 'AzureRM') -TrustPSGallery

        Updates all modules except Azure and AzureRM, and configures PSGallery as trusted.

    .EXAMPLE
        PS > Update-AllModules -Force -Verbose

        Forcefully updates all modules with verbose output.

    .EXAMPLE
        PS > Update-AllModules -WhatIf

        Shows what modules would be updated without actually performing the updates.

    .EXAMPLE
        PS > Update-AllModules -ExcludeModule @('Azure', 'AzureRM') -WhatIf

        Preview what would be updated while excluding specific modules from the update process.

    .EXAMPLE
        PS > Update-AllModules -Confirm

        Updates all modules with interactive confirmation for each operation.

    .OUTPUTS
        [System.Void]
        No output is returned, but progress information is displayed.

    .NOTES
        - Requires PowerShell 5.1 or later
        - Internet connection required to check for updates
        - May require elevated permissions on some systems
        - Use -ExcludeModule for problematic modules that fail to update

    .LINK
        https://jonlabelle.com/snippets/view/markdown/powershellget-commands
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Void])]
    param(
        [Parameter()]
        [String[]]$ExcludeModule = @(),

        [Parameter()]
        [Switch]$TrustPSGallery,

        [Parameter()]
        [Switch]$Force
    )

    begin
    {
        Write-Verbose 'Starting module update process'

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

        # Configure PSGallery trust if requested
        if ($TrustPSGallery)
        {
            try
            {
                $repo = Get-PSRepository -Name PSGallery -ErrorAction Stop
                if ($repo.InstallationPolicy -ne 'Trusted')
                {
                    if ($PSCmdlet.ShouldProcess('PSGallery repository', 'Set installation policy to Trusted'))
                    {
                        Write-Host 'Configuring PSGallery as trusted repository...' -ForegroundColor Cyan
                        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                        Write-Verbose 'PSGallery configured as trusted'
                    }
                }
                else
                {
                    Write-Verbose 'PSGallery already configured as trusted'
                }
            }
            catch
            {
                Write-Error "Failed to configure PSGallery: $($_.Exception.Message)"
                return
            }
        }
    }

    process
    {
        try
        {
            # Get all installed modules
            Write-Host 'Retrieving installed modules...' -ForegroundColor Cyan
            $installedModules = Get-InstalledModule | Where-Object { $_.Name -notin $ExcludeModule }

            if (-not $installedModules -or $installedModules.Count -eq 0)
            {
                Write-Host 'No modules found to update.' -ForegroundColor Yellow
                return
            }

            Write-Host "Found $($installedModules.Count) module(s) to check for updates" -ForegroundColor Green

            # Check if this is a WhatIf operation
            if ($WhatIfPreference)
            {
                Write-Host 'WhatIf: The following modules would be updated:' -ForegroundColor Yellow
                foreach ($module in $installedModules)
                {
                    Write-Host "  - $($module.Name) (Current version: $($module.Version))" -ForegroundColor Cyan
                }
                return
            }

            # Update parameters
            $updateParams = @{
                Verbose = $VerbosePreference -eq 'Continue'
                ErrorAction = 'Continue'
            }
            if ($Force)
            {
                $updateParams.Force = $true
            }

            # Update each module individually with ShouldProcess check
            $moduleList = if ($installedModules.Count -eq 1) { $installedModules.Name } else { 'all installed modules' }

            if ($PSCmdlet.ShouldProcess($moduleList, 'Update PowerShell modules'))
            {
                $updatedCount = 0
                $failedCount = 0
                $processedCount = 0

                foreach ($module in $installedModules)
                {
                    $processedCount++

                    # Calculate progress percentage
                    $percentComplete = if ($installedModules.Count -gt 0)
                    {
                        ($processedCount / $installedModules.Count) * 100
                    }
                    else
                    {
                        0
                    }
                    Write-Progress -Activity 'Updating PowerShell modules' -Status "Updating $($module.Name)" -PercentComplete $percentComplete

                    try
                    {
                        Write-Host "Updating module: $($module.Name) (current version: $($module.Version))" -ForegroundColor Cyan

                        $moduleUpdateParams = $updateParams.Clone()
                        $moduleUpdateParams.Name = $module.Name

                        Update-Module @moduleUpdateParams
                        $updatedCount++
                        Write-Verbose "Successfully updated $($module.Name)"
                    }
                    catch [System.InvalidOperationException]
                    {
                        if ($_.Exception.Message -like "*No match was found*")
                        {
                            Write-Warning "Module $($module.Name) not found in repository - skipping"
                        }
                        elseif ($_.Exception.Message -like "*newer version*")
                        {
                            Write-Host "Module $($module.Name) is already up to date" -ForegroundColor Green
                        }
                        else
                        {
                            Write-Warning "Failed to update $($module.Name): $($_.Exception.Message)"
                            $failedCount++
                        }
                    }
                    catch
                    {
                        Write-Warning "Failed to update $($module.Name): $($_.Exception.Message)"
                        $failedCount++
                    }
                }

                Write-Progress -Activity 'Updating PowerShell modules' -Completed

                # Display summary
                if ($updatedCount -gt 0)
                {
                    Write-Host "Successfully updated $updatedCount module(s)" -ForegroundColor Green
                }
                if ($failedCount -gt 0)
                {
                    Write-Host "$failedCount module(s) failed to update" -ForegroundColor Yellow
                }
                if ($updatedCount -eq 0 -and $failedCount -eq 0)
                {
                    Write-Host 'All modules are already up to date' -ForegroundColor Green
                }

                Write-Host 'Module update process completed' -ForegroundColor Green
            }
        }
        catch [System.InvalidOperationException]
        {
            Write-Error "PowerShellGet operation failed: $($_.Exception.Message)"
            Write-Host 'Try running: Install-Module -Name PowerShellGet -Force -AllowClobber' -ForegroundColor Yellow
        }
        catch [System.UnauthorizedAccessException]
        {
            Write-Error "Access denied: $($_.Exception.Message)"
            Write-Host 'Try running PowerShell as administrator or with elevated permissions' -ForegroundColor Yellow
        }
        catch
        {
            Write-Error "Unexpected error during module update: $($_.Exception.Message)"
            Write-Verbose "Error details: $($_.Exception.GetType().FullName)"
            throw $_
        }
    }

    end
    {
        Write-Verbose 'Module update process completed'
    }
}
