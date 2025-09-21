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
