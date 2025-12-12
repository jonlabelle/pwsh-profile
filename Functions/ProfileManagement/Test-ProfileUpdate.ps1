function Test-ProfileUpdate
{
    <#
    .SYNOPSIS
        Checks for available PowerShell profile updates from the remote repository.

    .DESCRIPTION
        This function checks if there are updates available for the PowerShell profile
        from the remote Git repository. It compares the local HEAD commit with the
        remote HEAD commit to determine if updates are available.

        The check is designed to be non-blocking and network-aware:

        - Only checks if Internet connectivity is available
        - Works cross-platform (Windows, macOS, Linux)

        If updates are detected, displays a notification message suggesting to run Update-Profile.

    .PARAMETER Async
        When specified, runs the update check in a background job to avoid blocking.

    .PARAMETER ShowChanges
        When specified along with available updates, displays the list of changes available in the remote repository.
        Note: This parameter has no effect when used with -Async as the output would not be visible from background jobs.

    .PARAMETER Force
        Reserved for future use. Currently has no effect.

    .EXAMPLE
        PS > Test-ProfileUpdate

        Performs a synchronous check for profile updates.

    .EXAMPLE
        PS > Test-ProfileUpdate -Async

        Starts a background job to check for profile updates without blocking.

    .EXAMPLE
        PS > Test-ProfileUpdate -ShowChanges

        Checks for updates and displays available changes if updates are found.

    .EXAMPLE
        PS > Test-ProfileUpdate -Force

        Checks for updates (Force parameter currently has no effect).

    .OUTPUTS
        System.Boolean
        Returns $true if updates are available, $false if not, or $null if check couldn't be performed.
        When using -Async, returns the background job object instead.

    .NOTES
        This function requires Git to be available in the system PATH.
        Internet connectivity is required to check for remote updates.

        Compatible with PowerShell Desktop 5.1+ and PowerShell Core 6.2+.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ProfileManagement/Test-ProfileUpdate.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ProfileManagement/Test-ProfileUpdate.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile
    #>

    [CmdletBinding()]
    [OutputType([System.Boolean], [System.Management.Automation.Job])]
    param
    (
        [Parameter()]
        [switch]
        $Async,

        [Parameter()]
        [switch]
        $ShowChanges,

        [Parameter()]
        [switch]
        $Force
    )

    begin
    {
        Write-Verbose 'Starting profile update check'

        # Get the profile root directory
        # When dot-sourced, $PSScriptRoot points to the function's directory
        # We need to navigate up to the repository root
        if ($PSScriptRoot)
        {
            $profileRoot = $PSScriptRoot

            # Navigate up the directory tree until we find the .git directory or reach root
            while ($profileRoot -and -not (Test-Path (Join-Path -Path $profileRoot -ChildPath '.git')))
            {
                $parent = Split-Path -Parent $profileRoot
                if ($parent -eq $profileRoot)
                {
                    # We've reached the root without finding .git
                    break
                }
                $profileRoot = $parent
            }
        }
        elseif ($PSCommandPath)
        {
            $profileRoot = Split-Path -Parent $PSCommandPath

            # Navigate up the directory tree until we find the .git directory
            while ($profileRoot -and -not (Test-Path (Join-Path -Path $profileRoot -ChildPath '.git')))
            {
                $parent = Split-Path -Parent $profileRoot
                if ($parent -eq $profileRoot)
                {
                    break
                }
                $profileRoot = $parent
            }
        }
        else
        {
            # Fallback to current directory
            $profileRoot = Get-Location
        }

        Write-Verbose "Profile root directory: $profileRoot"
    }

    process
    {
        # Define the update check script block
        $updateCheckScript = {
            param($ProfileRoot, $ShowChanges)

            # Save the current location before changing directories
            $originalLocation = Get-Location

            # Change to profile directory
            try
            {
                Set-Location -Path $ProfileRoot -ErrorAction Stop
            }
            catch
            {
                Write-Warning "Could not change to profile directory: $($_.Exception.Message)"
                return $null
            }

            # Helper function to restore location before returning
            function RestoreLocationAndReturn
            {
                param($ReturnValue)
                try
                {
                    Set-Location -Path $originalLocation -ErrorAction SilentlyContinue
                }
                catch
                {
                    Write-Debug "Could not restore original location: $($_.Exception.Message)"
                }
                return $ReturnValue
            }

            # Check if this is a Git repository
            if (-not (Test-Path -Path '.git'))
            {
                Write-Verbose 'Profile directory is not a Git repository'
                return RestoreLocationAndReturn $null
            }

            # Test Internet connectivity by trying to reach the remote repository
            try
            {
                Write-Verbose 'Testing connectivity to remote repository'

                # Get remote URL
                $remoteUrl = git config --get remote.origin.url 2>$null
                if (-not $remoteUrl)
                {
                    Write-Verbose 'No remote origin configured'
                    return RestoreLocationAndReturn $null
                }

                # Extract hostname from remote URL for connectivity test
                $hostname = if ($remoteUrl -match 'github\.com')
                {
                    'github.com'
                }
                elseif ($remoteUrl -match 'https?://([^/]+)')
                {
                    $matches[1]
                }
                else
                {
                    # Default to github.com if we can't parse
                    'github.com'
                }

                # Test connectivity using .NET methods for cross-platform compatibility
                $connected = $false
                try
                {
                    $addresses = [System.Net.Dns]::GetHostAddresses($hostname)
                    if ($addresses -and $addresses.Count -gt 0)
                    {
                        Write-Verbose "DNS resolution successful for $hostname"
                        $connected = $true
                    }
                }
                catch
                {
                    Write-Verbose "DNS resolution failed for ${hostname}: $($_.Exception.Message)"
                }

                if (-not $connected)
                {
                    Write-Verbose 'No Internet connectivity detected'
                    return RestoreLocationAndReturn $null
                }
            }
            catch
            {
                Write-Verbose "Connectivity test failed: $($_.Exception.Message)"
                return RestoreLocationAndReturn $null
            }

            # Fetch latest information from remote
            try
            {
                Write-Verbose 'Fetching remote information'
                $fetchOutput = git fetch origin 2>&1
                if ($LASTEXITCODE -ne 0)
                {
                    Write-Verbose "Git fetch failed with exit code $LASTEXITCODE. Output: $fetchOutput"
                    return RestoreLocationAndReturn $null
                }
                else
                {
                    Write-Verbose 'Git fetch completed successfully'
                }
            }
            catch
            {
                Write-Verbose "Failed to fetch remote information: $($_.Exception.Message)"
                return RestoreLocationAndReturn $null
            }

            # Compare local and remote HEAD
            try
            {
                $localHead = git rev-parse HEAD 2>$null
                $remoteHead = git rev-parse origin/main 2>$null

                if (-not $localHead -or -not $remoteHead)
                {
                    Write-Verbose 'Could not determine local or remote HEAD commit'
                    return RestoreLocationAndReturn $null
                }

                Write-Verbose "Local HEAD: $localHead"
                Write-Verbose "Remote HEAD: $remoteHead"

                # Check if local is behind remote
                if ($localHead -ne $remoteHead)
                {
                    # Verify that remote has commits that local doesn't have
                    $behindCommits = git rev-list --count "${localHead}..${remoteHead}" 2>$null
                    if ($behindCommits -and $behindCommits -gt 0)
                    {
                        Write-Verbose "Local repository is $behindCommits commits behind remote"

                        # Show changes if requested
                        if ($ShowChanges)
                        {
                            try
                            {
                                # Show the update prompt
                                Write-Host ''
                                Write-Host 'Profile updates are available!' -ForegroundColor Yellow

                                # Use the main branch for this repository
                                $remoteBranch = 'origin/main'

                                # Show available changes
                                $gitLog = git log --oneline "${localHead}..${remoteBranch}" 2>$null
                                if ($gitLog)
                                {
                                    Write-Host ''
                                    Write-Host 'Here are the available changes:' -ForegroundColor Cyan
                                    Write-Host ''
                                    foreach ($line in $gitLog)
                                    {
                                        # Remove hash prefix and branch references, format as bullet point
                                        $cleanLine = $line -replace '^\w+\s+', '' -replace '\s*\([^)]+\)\s*', ''
                                        Write-Host "  - $cleanLine" -ForegroundColor Gray
                                    }
                                    Write-Host ''
                                    Write-Host 'Run ''Update-Profile'' to apply these changes.' -ForegroundColor Green
                                    Write-Host ''
                                }
                            }
                            catch
                            {
                                Write-Debug "Could not show profile update notification: $($_.Exception.Message)"
                            }
                        }

                        return RestoreLocationAndReturn $true
                    }
                }

                Write-Verbose 'Local repository is up to date'
                return RestoreLocationAndReturn $false
            }
            catch
            {
                Write-Verbose "Failed to compare local and remote commits: $($_.Exception.Message)"
                return RestoreLocationAndReturn $null
            }
        }

        if ($Async)
        {
            Write-Verbose 'Starting background update check job'
            $job = Start-Job -ScriptBlock $updateCheckScript -ArgumentList $profileRoot, $ShowChanges.IsPresent -Name 'ProfileUpdateCheck'
            return $job
        }
        else
        {
            Write-Verbose 'Running synchronous update check'
            return & $updateCheckScript $profileRoot $ShowChanges.IsPresent
        }
    }

    end
    {
        Write-Verbose 'Profile update check completed'
    }
}
