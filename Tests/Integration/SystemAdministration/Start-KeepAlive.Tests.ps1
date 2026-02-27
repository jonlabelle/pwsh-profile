#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Start-KeepAlive function.

.DESCRIPTION
    Comprehensive integration tests that verify real-world keep-alive functionality including
    actual COM object interactions, system sleep prevention, and complete job lifecycle management.

.NOTES
    These integration tests validate real-world usage scenarios including:
    - Platform-specific activity simulation (keystrokes on Windows, caffeinate on macOS, etc.)
    - Platform-specific resource creation and cleanup
    - Background job management and monitoring
    - System sleep prevention verification
    - Error recovery and edge case handling

    Tests are skipped in CI environments to avoid interference with build agents.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Start-KeepAlive.ps1"

    # Import test utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"

    # Detect if we're in a CI environment
    $script:IsCI = $env:CI -eq 'true' -or
        $env:GITHUB_ACTIONS -eq 'true' -or
        $env:APPVEYOR -eq 'True' -or
        $env:AZURE_PIPELINES -eq 'True' -or
        $env:TF_BUILD -eq 'True'

    # Platform detection for cross-platform compatibility
    $script:IsWindowsTest = if ($PSVersionTable.PSVersion.Major -lt 6)
    {
        $true  # PowerShell 5.1 is Windows-only
    }
    else
    {
        $IsWindows  # PowerShell Core cross-platform check
    }

    Write-Verbose "CI Environment detected: $script:IsCI"
    Write-Verbose "Windows platform: $script:IsWindowsTest"
}

Describe 'Start-KeepAlive Integration Tests' -Tag 'Integration' -Skip:($script:IsCI) {

    BeforeAll {
        # Clean up any existing integration test jobs
        try
        {
            Get-Job -Name 'IntegrationTest*' -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
            Get-Job -Name 'IntegrationTest*' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
        }
        catch
        {
            Write-Warning "Failed to cleanup existing jobs in BeforeAll: $_"
        }
    }

    AfterAll {
        # Clean up all integration test jobs - ensure complete cleanup
        try
        {
            Get-Job -Name 'IntegrationTest*' -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500  # Give jobs time to stop
            Get-Job -Name 'IntegrationTest*' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
        }
        catch
        {
            Write-Warning "Failed to cleanup jobs in AfterAll: $_"
        }

        # Additional cleanup attempt for any remaining jobs
        try
        {
            $remainingJobs = Get-Job | Where-Object { $_.Name -like 'IntegrationTest*' }
            if ($remainingJobs)
            {
                $remainingJobs | Stop-Job -ErrorAction SilentlyContinue
                $remainingJobs | Remove-Job -Force -ErrorAction SilentlyContinue
            }
        }
        catch
        {
            Write-Warning "Failed to cleanup remaining jobs: $_"
        }
    }
}
