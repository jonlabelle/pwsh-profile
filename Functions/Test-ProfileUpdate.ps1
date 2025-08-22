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
        - Uses background job processing to avoid blocking profile load
        - Respects opt-out file (.disable-profile-update-check)
        - Works cross-platform (Windows, macOS, Linux)

        If updates are detected, displays a notification message suggesting to run Update-Profile.

    .PARAMETER Async
        When specified, runs the update check in a background job to avoid blocking.
        This is the recommended approach when called during profile loading.

    .PARAMETER Force
        When specified, ignores the .disable-profile-update-check file and performs the check anyway.

    .EXAMPLE
        PS > Test-ProfileUpdates
        Performs a synchronous check for profile updates.

    .EXAMPLE
        PS > Test-ProfileUpdates -Async
        Starts a background job to check for profile updates without blocking.

    .EXAMPLE
        PS > Test-ProfileUpdates -Force
        Checks for updates even if .disable-profile-update-check file exists.

    .OUTPUTS
        System.Boolean
        Returns $true if updates are available, $false if not, or $null if check couldn't be performed.
        When using -Async, returns the background job object instead.

    .NOTES
        This function requires Git to be available in the system PATH.
        Internet connectivity is required to check for remote updates.

        To opt-out of automatic update checks, create a .disable-profile-update-check file
        in the profile directory.

        Compatible with PowerShell Desktop 5.1+ and PowerShell Core 6.2+.

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
        $Force
    )

    begin
    {
        Write-Verbose 'Starting profile update check'

        # Get the profile root directory - we need to go up one level from Functions
        if ($PSScriptRoot -and (Split-Path -Leaf $PSScriptRoot) -eq 'Functions')
        {
            $profileRoot = Split-Path -Parent $PSScriptRoot
        }
        elseif ($PSScriptRoot)
        {
            $profileRoot = $PSScriptRoot
        }
        elseif ($PSCommandPath)
        {
            $profileRoot = Split-Path -Parent $PSCommandPath
            if ((Split-Path -Leaf $profileRoot) -eq 'Functions')
            {
                $profileRoot = Split-Path -Parent $profileRoot
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
        # Check for opt-out file unless Force is specified
        if (-not $Force)
        {
            $disableFile = Join-Path -Path $profileRoot -ChildPath '.disable-profile-update-check'
            if (Test-Path -Path $disableFile)
            {
                Write-Verbose "Update check disabled by .disable-profile-update-check file"
                return $false
            }
        }

        # Define the update check script block
        $updateCheckScript = {
            param($ProfileRoot)

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

            # Check if this is a Git repository
            if (-not (Test-Path -Path '.git'))
            {
                Write-Verbose "Profile directory is not a Git repository"
                return $null
            }

            # Test Internet connectivity by trying to reach the remote repository
            try
            {
                Write-Verbose "Testing connectivity to remote repository"

                # Get remote URL
                $remoteUrl = git config --get remote.origin.url 2>$null
                if (-not $remoteUrl)
                {
                    Write-Verbose "No remote origin configured"
                    return $null
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
                    Write-Verbose "No Internet connectivity detected"
                    return $null
                }
            }
            catch
            {
                Write-Verbose "Connectivity test failed: $($_.Exception.Message)"
                return $null
            }

            # Fetch latest information from remote
            try
            {
                Write-Verbose "Fetching remote information"
                $fetchOutput = git fetch origin 2>&1
                if ($LASTEXITCODE -ne 0)
                {
                    Write-Verbose "Git fetch failed with exit code $LASTEXITCODE. Output: $fetchOutput"
                    return $null
                }
                else
                {
                    Write-Verbose "Git fetch completed successfully"
                }
            }
            catch
            {
                Write-Verbose "Failed to fetch remote information: $($_.Exception.Message)"
                return $null
            }

            # Compare local and remote HEAD
            try
            {
                $localHead = git rev-parse HEAD 2>$null
                $remoteHead = git rev-parse origin/HEAD 2>$null

                # If origin/HEAD is not set, try origin/main or origin/master
                if (-not $remoteHead -or $LASTEXITCODE -ne 0)
                {
                    $defaultBranch = git symbolic-ref refs/remotes/origin/HEAD 2>$null
                    if ($defaultBranch)
                    {
                        $defaultBranch = $defaultBranch -replace '^refs/remotes/origin/', ''
                        $remoteHead = git rev-parse "origin/$defaultBranch" 2>$null
                    }
                    else
                    {
                        # Try common default branches
                        foreach ($branch in @('main', 'master'))
                        {
                            $remoteHead = git rev-parse "origin/$branch" 2>$null
                            if ($remoteHead -and $LASTEXITCODE -eq 0)
                            {
                                break
                            }
                        }
                    }
                }

                if (-not $localHead -or -not $remoteHead)
                {
                    Write-Verbose "Could not determine local or remote HEAD commit"
                    return $null
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
                        return $true
                    }
                }

                Write-Verbose "Local repository is up to date"
                return $false
            }
            catch
            {
                Write-Verbose "Failed to compare local and remote commits: $($_.Exception.Message)"
                return $null
            }
        }

        if ($Async)
        {
            Write-Verbose "Starting background update check job"
            $job = Start-Job -ScriptBlock $updateCheckScript -ArgumentList $profileRoot -Name 'ProfileUpdateCheck'
            return $job
        }
        else
        {
            Write-Verbose "Running synchronous update check"
            return & $updateCheckScript $profileRoot
        }
    }

    end
    {
        Write-Verbose 'Profile update check completed'
    }
}
