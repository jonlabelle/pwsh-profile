function Update-EveryModule
{
    <#
    .SYNOPSIS
        Updates all installed PowerShell modules to their latest versions.

    .DESCRIPTION
        This function updates all installed PowerShell modules to their latest versions from the PowerShell Gallery.
        It includes error handling, supports excluding specific modules, and can optionally configure PSGallery trust.
        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

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

            if (-not $installedModules)
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
            }
            if ($Force)
            {
                $updateParams.Force = $true
            }

            # Update all modules with ShouldProcess check
            $moduleList = if ($installedModules.Count -eq 1) { $installedModules.Name } else { 'all installed modules' }

            if ($PSCmdlet.ShouldProcess($moduleList, 'Update PowerShell modules'))
            {
                if ($installedModules.Count -eq 1)
                {
                    Write-Host "Updating module: $($installedModules.Name)" -ForegroundColor Cyan
                }
                else
                {
                    Write-Host 'Updating all modules...' -ForegroundColor Cyan
                }

                Update-Module @updateParams
                Write-Host 'Module update process completed successfully' -ForegroundColor Green
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
