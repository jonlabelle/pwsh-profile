# Test Cleanup Utilities
# Provides robust cleanup functions for PowerShell tests

function Remove-TestDirectory
{
    <#
    .SYNOPSIS
        Robustly removes a test directory with multiple cleanup attempts

    .PARAMETER Path
        The path to the directory to remove

    .PARAMETER MaxAttempts
        Maximum number of cleanup attempts (default: 3)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$MaxAttempts = 3
    )

    if (-not $Path -or -not (Test-Path $Path))
    {
        return
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++)
    {
        try
        {
            # Force unlock any files that might be in use
            if ($attempt -gt 1)
            {
                Start-Sleep -Milliseconds (100 * $attempt)
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
            }

            # Remove with force and recurse
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Verbose "Successfully removed test directory: $Path"
            return
        }
        catch
        {
            Write-Verbose "Attempt $attempt failed to remove $Path : $_"

            if ($attempt -eq $MaxAttempts)
            {
                Write-Warning "Failed to cleanup test directory after $MaxAttempts attempts: $Path - $_"

                # Try individual file cleanup as last resort
                try
                {
                    Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        try { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
                        catch { Write-Verbose "Could not remove file: $($_.FullName)" }
                    }
                    Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
                }
                catch
                {
                    # Final fallback - just warn
                    Write-Warning "Unable to clean up test directory: $Path"
                }
            }
        }
    }
}

function Stop-TestJob
{
    <#
    .SYNOPSIS
        Robustly stops and removes test jobs by name pattern

    .PARAMETER NamePattern
        The name pattern for jobs to clean up

    .PARAMETER TimeoutSeconds
        How long to wait for jobs to stop (default: 10)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NamePattern,

        [int]$TimeoutSeconds = 10
    )

    try
    {
        # Get all matching jobs
        $jobs = Get-Job -Name $NamePattern -ErrorAction SilentlyContinue

        if ($jobs)
        {
            Write-Verbose "Cleaning up $($jobs.Count) jobs matching pattern: $NamePattern"

            # Stop jobs first
            $jobs | Stop-Job -ErrorAction SilentlyContinue

            # Wait for jobs to stop with timeout
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            do
            {
                Start-Sleep -Milliseconds 100
                $runningJobs = $jobs | Where-Object { $_.State -eq 'Running' }
            } while ($runningJobs -and $stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds)

            # Force remove all jobs
            $jobs | Remove-Job -Force -ErrorAction SilentlyContinue

            # Verify cleanup
            $remainingJobs = Get-Job -Name $NamePattern -ErrorAction SilentlyContinue
            if ($remainingJobs)
            {
                Write-Warning "Some jobs could not be cleaned up: $($remainingJobs.Name -join ', ')"
            }
        }
    }
    catch
    {
        Write-Warning "Error during job cleanup for pattern '$NamePattern': $_"
    }
}

function Remove-TestSymbolicLink
{
    <#
    .SYNOPSIS
        Robustly removes a symbolic link with special handling for Windows PowerShell 5.1

    .DESCRIPTION
        On Windows PowerShell 5.1, directory symbolic links can be problematic to remove.
        This function uses multiple strategies to ensure cleanup succeeds:
        1. First tries standard Remove-Item
        2. Falls back to [System.IO.Directory]::Delete for directory symlinks
        3. Uses cmd.exe rmdir as a final fallback on Windows

    .PARAMETER Path
        The path to the symbolic link to remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not $Path -or -not (Test-Path -Path $Path -ErrorAction SilentlyContinue))
    {
        return
    }

    # Detect platform
    $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { $IsWindows }
    $isPowerShell51 = $PSVersionTable.PSVersion.Major -lt 6

    try
    {
        # Check if it's actually a symlink
        $item = Get-Item -Path $Path -Force -ErrorAction SilentlyContinue
        if (-not $item)
        {
            # Item might have been removed already or is inaccessible
            return
        }

        $isSymlink = $item.Attributes -band [System.IO.FileAttributes]::ReparsePoint
        $isDirectory = $item.PSIsContainer

        if ($isSymlink -and $isDirectory -and $isWindowsPlatform -and $isPowerShell51)
        {
            # Special handling for directory symlinks on Windows PS 5.1
            # Try multiple methods in order of preference

            # Method 1: Try [System.IO.Directory]::Delete (does not follow symlinks)
            try
            {
                [System.IO.Directory]::Delete($Path)
                Write-Verbose "Removed directory symlink via .NET: $Path"
                return
            }
            catch
            {
                Write-Verbose "Failed to remove directory symlink via .NET: $($_.Exception.Message)"
            }

            # Method 2: Try cmd.exe rmdir (specifically for directory junctions/symlinks)
            try
            {
                $null = cmd.exe /c rmdir "$Path" 2>&1
                if (-not (Test-Path -Path $Path -ErrorAction SilentlyContinue))
                {
                    Write-Verbose "Removed directory symlink via cmd.exe rmdir: $Path"
                    return
                }
            }
            catch
            {
                Write-Verbose "Failed to remove directory symlink via cmd.exe: $($_.Exception.Message)"
            }

            # Method 3: Standard Remove-Item as final fallback
            Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
        }
        else
        {
            # Standard removal for file symlinks or non-Windows platforms
            # Do NOT use -Recurse on symlinks
            Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
        }
    }
    catch
    {
        Write-Verbose "Error removing symbolic link '$Path': $($_.Exception.Message)"
        # Final fallback - try simple removal
        Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
    }

    # Wait a moment and verify removal
    Start-Sleep -Milliseconds 50
    if (Test-Path -Path $Path -ErrorAction SilentlyContinue)
    {
        Write-Warning "Failed to remove symbolic link: $Path"
    }
}

function Invoke-RobustTestCleanup
{
    <#
    .SYNOPSIS
        Performs comprehensive cleanup for tests with both directories and jobs

    .PARAMETER TestDirectories
        Array of test directories to clean up

    .PARAMETER JobNamePatterns
        Array of job name patterns to clean up
    #>
    [CmdletBinding()]
    param(
        [string[]]$TestDirectories = @(),
        [string[]]$JobNamePatterns = @()
    )

    # Clean up jobs first (they might be accessing files)
    foreach ($pattern in $JobNamePatterns)
    {
        Stop-TestJob -NamePattern $pattern
    }

    # Clean up directories
    foreach ($dir in $TestDirectories)
    {
        Remove-TestDirectory -Path $dir
    }
}
