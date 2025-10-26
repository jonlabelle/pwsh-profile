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

    .PARAMETER IncludeModule
        Array of specific module names to include for updates. When specified, only these modules
        will be considered for updates. Cannot be used together with ExcludeModule.

    .PARAMETER TrustPSGallery
        Automatically sets PSGallery installation policy to Trusted if not already configured.

    .PARAMETER Force
        Forces the update even if a newer version is already installed.

    .PARAMETER UseElevation
        Automatically elevates privileges when updating modules that require administrator rights.
        Only works on Windows platforms. On other platforms, this parameter is ignored.

    .PARAMETER SkipPublisherCheck
        Skips the publisher check when updating modules. This allows updating modules that have
        different digital signatures than the previously installed version.

        Requires PowerShellGet 2.0 or later. If using an older version of PowerShellGet,
        this parameter will be ignored with a warning message.

        WARNING: This bypasses an important security feature. Only use this parameter when you trust
        the module source and have verified the update is legitimate. Consider using -WhatIf first
        to review what would be updated before applying this parameter.

    .PARAMETER Interactive
        Prompts the user for each module update, allowing them to choose whether to update each
        individual module. This provides fine-grained control over which modules are updated.

    .PARAMETER WhatIf
        Shows what modules would be updated without actually updating them.

    .EXAMPLE
        PS > Update-AllModules

        Updates all installed PowerShell modules to their latest versions.

    .EXAMPLE
        PS > Update-AllModules -IncludeModule @('Pester', 'DailyBackup')

        Updates only the specified modules (Pester and DailyBackup).

    .EXAMPLE
        PS > Update-AllModules -IncludeModule @('Pester') -Interactive -UseElevation

        Interactive mode for only the Pester module with automatic privilege elevation.

    .EXAMPLE
        PS > Update-AllModules -ExcludeModule @('Azure', 'AzureRM') -TrustPSGallery

        Updates all modules except Azure and AzureRM, and configures PSGallery as trusted.

    .EXAMPLE
        PS > Update-AllModules -UseElevation -Verbose

        Updates all modules with automatic privilege elevation for modules requiring admin rights.

    .EXAMPLE
        PS > Update-AllModules -Interactive

        Prompts for each module update, allowing the user to choose which modules to update.

    .EXAMPLE
        PS > Update-AllModules -Interactive -UseElevation

        Interactive mode with automatic privilege elevation when needed.

    .EXAMPLE
        PS > Update-AllModules -UseElevation -SkipPublisherCheck -Verbose

        Updates all modules with automatic privilege elevation and skips publisher verification.
        WARNING: Only use -SkipPublisherCheck when you trust the module sources.

    .EXAMPLE
        PS > Update-AllModules -ExcludeModule @('Azure', 'AzureRM') -UseElevation

        Updates all modules except Azure and AzureRM, using elevation when needed.

    .EXAMPLE
        PS > Update-AllModules -Force -Verbose

        Forcefully updates all modules with verbose output.

    .EXAMPLE
        PS > Update-AllModules -WhatIf
        PS > Get-OutdatedModules | ForEach-Object { Update-Module -Name $_.Name -SkipPublisherCheck }

        Safer alternative: First preview what would be updated, then update modules individually
        with selective use of -SkipPublisherCheck for better security control.

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
        - May require elevated permissions on some systems for system-installed modules
        - Use -ExcludeModule for problematic modules that fail to update
        - Use -IncludeModule to update only specific modules (cannot be used with ExcludeModule)
        - Use -UseElevation on Windows to automatically handle privilege elevation
        - Use -SkipPublisherCheck to bypass digital signature verification issues (requires PowerShellGet 2.0+)
        - Use -Interactive for fine-grained control over which modules to update
        - The Invoke-ElevatedCommand function must be available for elevation support

        SECURITY CONSIDERATIONS:
        - The -SkipPublisherCheck parameter bypasses PowerShell's built-in security that validates
          module publishers. This security feature helps prevent malicious module updates.
        - Only use -SkipPublisherCheck for trusted modules from the official PowerShell Gallery
        - Consider alternative approaches like updating modules individually to maintain better control
        - Always review module changes and changelogs before updating, especially with -SkipPublisherCheck
        - Use -WhatIf first to preview what would be updated before using -SkipPublisherCheck

        ALTERNATIVE APPROACHES:
        - Update modules individually: Update-Module -Name ModuleName -SkipPublisherCheck
        - Check module details first: Get-InstalledModule ModuleName | Format-List
        - Review publisher changes: Find-Module ModuleName | Format-List Name, Author, CompanyName
        - Use PowerShellGet v3+ which has improved publisher validation handling

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
        [String[]]$IncludeModule = @(),

        [Parameter()]
        [Switch]$TrustPSGallery,

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Switch]$UseElevation,

        [Parameter()]
        [Switch]$SkipPublisherCheck,

        [Parameter()]
        [Switch]$Interactive
    )

    begin
    {
        Write-Verbose 'Starting module update process'

        # Check for conflicting parameters
        if ($ExcludeModule.Count -gt 0 -and $IncludeModule.Count -gt 0)
        {
            Write-Error 'Cannot use both ExcludeModule and IncludeModule parameters together. Use one or the other.'
            return
        }

        # Platform detection for elevation support
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # PowerShell 5.1 - Windows only
            $script:IsWindowsPlatform = $true
        }
        else
        {
            # PowerShell Core - use built-in variables
            $script:IsWindowsPlatform = $IsWindows
        }

        # Check if UseElevation is supported on this platform
        if ($UseElevation -and -not $script:IsWindowsPlatform)
        {
            Write-Warning 'UseElevation parameter is only supported on Windows. Ignoring elevation request.'
            $UseElevation = $false
        }

        # Check PowerShellGet version for SkipPublisherCheck compatibility
        $powerShellGetModule = Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        $supportsSkipPublisherCheck = $powerShellGetModule -and $powerShellGetModule.Version -ge [Version]'2.0.0'

        # Show security warning for SkipPublisherCheck
        if ($SkipPublisherCheck)
        {
            if (-not $supportsSkipPublisherCheck)
            {
                Write-Host "ERROR: SkipPublisherCheck parameter requires PowerShellGet 2.0 or later. Current version: $($powerShellGetModule.Version)" -ForegroundColor Red
                Write-Host ''
                Write-Host 'To update PowerShellGet:' -ForegroundColor Yellow
                Write-Host '  Install-Module PowerShellGet -Force -AllowClobber' -ForegroundColor Cyan
                Write-Host '  Restart PowerShell, then try again' -ForegroundColor Cyan
                Write-Host ''
                Write-Host 'To update Pester manually (common issue):' -ForegroundColor Yellow
                Write-Host '  Uninstall-Module Pester -Force -AllVersions' -ForegroundColor Cyan
                Write-Host '  Install-Module Pester -Force -Scope CurrentUser' -ForegroundColor Cyan
                throw "SkipPublisherCheck requires PowerShellGet 2.0+. Current: $($powerShellGetModule.Version)"
            }
            else
            {
                Write-Warning 'SkipPublisherCheck bypasses module publisher verification - a security feature that helps prevent malicious updates. Only proceed if you trust the module sources.'
                if ($Host.UI.RawUI -and [Environment]::UserInteractive)
                {
                    $response = Read-Host 'Do you want to continue with publisher check disabled? (y/N)'
                    if ($response -notmatch '^[Yy]([Ee][Ss])?$')
                    {
                        Write-Host 'Operation cancelled by user.' -ForegroundColor Yellow
                        return
                    }
                }
            }
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
            $allInstalledModules = Get-InstalledModule

            # Apply include/exclude filtering
            if ($IncludeModule.Count -gt 0)
            {
                $installedModules = $allInstalledModules | Where-Object { $_.Name -in $IncludeModule }
                if ($installedModules.Count -lt $IncludeModule.Count)
                {
                    $notFound = $IncludeModule | Where-Object { $_ -notin $installedModules.Name }
                    foreach ($missing in $notFound)
                    {
                        Write-Warning "Module '$missing' specified in IncludeModule is not installed"
                    }
                }
            }
            elseif ($ExcludeModule.Count -gt 0)
            {
                $installedModules = $allInstalledModules | Where-Object { $_.Name -notin $ExcludeModule }
            }
            else
            {
                $installedModules = $allInstalledModules
            }

            if (-not $installedModules -or $installedModules.Count -eq 0)
            {
                Write-Host 'No modules found to update.' -ForegroundColor Yellow
                return
            }

            # If Interactive mode, check which modules have updates available first
            if ($Interactive)
            {
                Write-Host 'Checking for available updates...' -ForegroundColor Cyan
                $outdatedModules = @()

                foreach ($module in $installedModules)
                {
                    try
                    {
                        $latestModule = Find-Module -Name $module.Name -Repository PSGallery -ErrorAction Stop
                        if ($latestModule.Version -gt $module.Version)
                        {
                            $outdatedModules += [PSCustomObject]@{
                                Name = $module.Name
                                CurrentVersion = $module.Version
                                AvailableVersion = $latestModule.Version
                                Module = $module
                            }
                        }
                    }
                    catch
                    {
                        Write-Verbose "Could not check updates for $($module.Name): $($_.Exception.Message)"
                    }
                }

                if ($outdatedModules.Count -eq 0)
                {
                    Write-Host 'All modules are already up to date.' -ForegroundColor Green
                    return
                }

                Write-Host "Found $($outdatedModules.Count) module(s) with available updates:" -ForegroundColor Yellow
                foreach ($outdated in $outdatedModules)
                {
                    Write-Host "  - $($outdated.Name): $($outdated.CurrentVersion) → $($outdated.AvailableVersion)" -ForegroundColor Cyan
                }
                Write-Host ''

                # Filter installedModules to only include outdated ones for interactive prompting
                $modulesToProcess = $outdatedModules.Module
            }
            else
            {
                $modulesToProcess = $installedModules
            }

            Write-Host "Found $($modulesToProcess.Count) module(s) to check for updates" -ForegroundColor Green

            # Check if this is a WhatIf operation
            if ($WhatIfPreference)
            {
                Write-Host 'WhatIf: The following modules would be updated:' -ForegroundColor Yellow
                foreach ($module in $modulesToProcess)
                {
                    Write-Host "  - $($module.Name) (Current version: $($module.Version))" -ForegroundColor Cyan
                }
                return
            }

            # Update parameters
            $updateParams = @{
                Verbose = $VerbosePreference -eq 'Continue'
                ErrorAction = 'Stop'  # Changed to Stop so we can catch errors properly
            }
            if ($Force)
            {
                $updateParams.Force = $true
            }
            if ($SkipPublisherCheck -and $supportsSkipPublisherCheck)
            {
                $updateParams.SkipPublisherCheck = $true
            }

            # Update each module individually with ShouldProcess check
            $moduleList = if ($modulesToProcess.Count -eq 1) { $modulesToProcess.Name } else { 'selected modules' }

            if ($PSCmdlet.ShouldProcess($moduleList, 'Update PowerShell modules'))
            {
                $updatedCount = 0
                $failedCount = 0
                $processedCount = 0
                $skippedCount = 0

                foreach ($module in $modulesToProcess)
                {
                    $processedCount++

                    # Calculate progress percentage
                    $percentComplete = if ($modulesToProcess.Count -gt 0)
                    {
                        ($processedCount / $modulesToProcess.Count) * 100
                    }
                    else
                    {
                        0
                    }
                    Write-Progress -Activity 'Updating PowerShell modules' -Status "Processing $($module.Name)" -PercentComplete $percentComplete

                    # Interactive mode: prompt user for each module
                    if ($Interactive)
                    {
                        $availableVersion = if ($outdatedModules)
                        {
                            ($outdatedModules | Where-Object Name -EQ $module.Name).AvailableVersion
                        }
                        else
                        {
                            'Unknown'
                        }

                        Write-Host ''
                        Write-Host "Module: $($module.Name)" -ForegroundColor Cyan
                        Write-Host "  Current version: $($module.Version)" -ForegroundColor Gray
                        Write-Host "  Available version: $availableVersion" -ForegroundColor Gray

                        $response = Read-Host 'Do you want to update this module? (y/N/a=all/q=quit)'

                        switch -Regex ($response)
                        {
                            '^[Aa]([Ll][Ll])?$'
                            {
                                Write-Host 'Updating all remaining modules...' -ForegroundColor Green
                                $Interactive = $false  # Disable interactive mode for remaining modules
                                break
                            }
                            '^[Qq]([Uu][Ii][Tt])?$'
                            {
                                Write-Host 'Update process cancelled by user.' -ForegroundColor Yellow
                                return
                            }
                            '^[Yy]([Ee][Ss])?$'
                            {
                                # Continue with update
                                break
                            }
                            default
                            {
                                Write-Host "Skipping $($module.Name)" -ForegroundColor Yellow
                                $skippedCount++
                                continue
                            }
                        }
                    }

                    Write-Host "Updating module: $($module.Name) (current version: $($module.Version))" -ForegroundColor Cyan

                    try
                    {
                        $moduleUpdateParams = $updateParams.Clone()
                        $moduleUpdateParams.Name = $module.Name

                        Update-Module @moduleUpdateParams
                        $updatedCount++
                        Write-Verbose "Successfully updated $($module.Name)"
                    }
                    catch [Microsoft.PowerShell.Commands.WriteErrorException]
                    {
                        $errorMessage = $_.Exception.Message

                        # Check for specific error conditions
                        if ($errorMessage -like '*No match was found*')
                        {
                            Write-Warning "Module $($module.Name) not found in repository - skipping"
                            $skippedCount++
                        }
                        elseif ($errorMessage -like '*newer version*' -or $errorMessage -like '*already up to date*')
                        {
                            Write-Host "  Module $($module.Name) is already up to date" -ForegroundColor Green
                            $skippedCount++
                        }
                        elseif ($UseElevation -and $script:IsWindowsPlatform -and $errorMessage -like '*Administrator rights are required*')
                        {
                            try
                            {
                                Write-Host '  Retrying with elevated privileges...' -ForegroundColor Yellow

                                # Create the script block with embedded variables to avoid parameter passing issues
                                $elevatedScriptBlock = [ScriptBlock]::Create(@"
                                    `$elevatedUpdateParams = @{
                                        Name = '$($module.Name)'
                                        ErrorAction = 'Stop'
                                    }
                                    if ('$($Force.IsPresent)' -eq 'True') { `$elevatedUpdateParams.Force = `$true }
                                    if ('$($VerbosePreference -eq 'Continue')' -eq 'True') { `$elevatedUpdateParams.Verbose = `$true }

                                    # Only add SkipPublisherCheck if supported
                                    if ('$($SkipPublisherCheck.IsPresent)' -eq 'True') {
                                        `$psGetModule = Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
                                        if (`$psGetModule -and `$psGetModule.Version -ge [Version]'2.0.0') {
                                            `$elevatedUpdateParams.SkipPublisherCheck = `$true
                                        }
                                    }

                                    Update-Module @elevatedUpdateParams
"@) # End of here-string for elevated script block

                                # Use Invoke-ElevatedCommand to update the module
                                Invoke-ElevatedCommand -Scriptblock $elevatedScriptBlock

                                $updatedCount++
                                Write-Host "  Successfully updated $($module.Name) with elevation" -ForegroundColor Green
                                Write-Verbose "Successfully updated $($module.Name) with elevation"
                            }
                            catch
                            {
                                Write-Warning "Failed to update $($module.Name) even with elevation: $($_.Exception.Message)"
                                $failedCount++
                            }
                        }
                        else
                        {
                            Write-Warning "Failed to update $($module.Name): $errorMessage"
                            $failedCount++
                        }
                    }
                    catch [System.InvalidOperationException]
                    {
                        $errorMessage = $_.Exception.Message

                        if ($errorMessage -like '*No match was found*')
                        {
                            Write-Warning "Module $($module.Name) not found in repository - skipping"
                            $skippedCount++
                        }
                        elseif ($errorMessage -like '*newer version*')
                        {
                            Write-Host "  Module $($module.Name) is already up to date" -ForegroundColor Green
                            $skippedCount++
                        }
                        elseif ($UseElevation -and $script:IsWindowsPlatform -and $errorMessage -like '*Administrator rights are required*')
                        {
                            try
                            {
                                Write-Host '  Retrying with elevated privileges...' -ForegroundColor Yellow

                                # Create the script block with embedded variables to avoid parameter passing issues
                                $elevatedScriptBlock = [ScriptBlock]::Create(@"
                                    `$elevatedUpdateParams = @{
                                        Name = '$($module.Name)'
                                        ErrorAction = 'Stop'
                                    }
                                    if ('$($Force.IsPresent)' -eq 'True') { `$elevatedUpdateParams.Force = `$true }
                                    if ('$($VerbosePreference -eq 'Continue')' -eq 'True') { `$elevatedUpdateParams.Verbose = `$true }

                                    # Only add SkipPublisherCheck if supported
                                    if ('$($SkipPublisherCheck.IsPresent)' -eq 'True') {
                                        `$psGetModule = Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
                                        if (`$psGetModule -and `$psGetModule.Version -ge [Version]'2.0.0') {
                                            `$elevatedUpdateParams.SkipPublisherCheck = `$true
                                        }
                                    }

                                    Update-Module @elevatedUpdateParams
"@) # End of here-string for elevated script block

                                # Use Invoke-ElevatedCommand to update the module
                                Invoke-ElevatedCommand -Scriptblock $elevatedScriptBlock

                                $updatedCount++
                                Write-Host "  Successfully updated $($module.Name) with elevation" -ForegroundColor Green
                                Write-Verbose "Successfully updated $($module.Name) with elevation"
                            }
                            catch
                            {
                                Write-Warning "Failed to update $($module.Name) even with elevation: $($_.Exception.Message)"
                                $failedCount++
                            }
                        }
                        else
                        {
                            Write-Warning "Failed to update $($module.Name): $errorMessage"
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
                if ($skippedCount -gt 0)
                {
                    Write-Host "$skippedCount module(s) were already up to date or skipped" -ForegroundColor Cyan
                }
                if ($failedCount -gt 0)
                {
                    Write-Host "$failedCount module(s) failed to update" -ForegroundColor Yellow
                    if ($UseElevation -eq $false -and $script:IsWindowsPlatform)
                    {
                        Write-Host '  Tip: Use -UseElevation parameter to automatically handle privilege elevation' -ForegroundColor Gray
                    }
                    if ($SkipPublisherCheck -eq $false)
                    {
                        Write-Host '  Tip: Use -SkipPublisherCheck parameter to bypass publisher verification issues' -ForegroundColor Gray
                    }
                }
                if ($updatedCount -eq 0 -and $failedCount -eq 0 -and $skippedCount -eq 0)
                {
                    Write-Host 'No modules were processed' -ForegroundColor Yellow
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
