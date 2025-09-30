#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs Pester tests for the PowerShell Profile project with cross-version compatibility.

.DESCRIPTION
    This script runs unit and integration tests using Pester, automatically detecting
    the installed Pester version and using the appropriate syntax for compatibility
    with both Pester 4.x and Pester 5+.

    Requirements:
    - Pester 4.0 or higher (Pester 3.x is not supported)
    - Test files must be compatible with the installed Pester version

    Features:
    - Cross-platform compatibility (Windows, macOS, Linux)
    - Automatic Pester version detection and syntax adaptation
    - Support for unit and integration test separation
    - Configurable output verbosity
    - NUnit XML test results generation
    - CI/CD pipeline friendly with proper exit codes

.PARAMETER TestType
    Specifies which types of tests to run.
    - 'Unit': Run only unit tests from ./Tests/Unit/
    - 'Integration': Run only integration tests from ./Tests/Integration/
    - 'All': Run both unit and integration tests (default)

.PARAMETER OutputFormat
    Controls the verbosity of test output.
    - 'Normal': Standard test output with basic information
    - 'Detailed': Comprehensive output including test names and timing (default)
    - 'Diagnostic': Maximum verbosity for debugging

    Note: The actual available output formats depend on the Pester version installed.

.PARAMETER PassThru
    When specified, returns the Pester test results object for further processing
    instead of just displaying the summary.

.EXAMPLE
    ./Invoke-Tests.ps1
    Runs all tests with detailed output.

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType Unit
    Runs only unit tests with detailed output.

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType Integration -OutputFormat Normal
    Runs integration tests with normal verbosity.

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType All -OutputFormat Diagnostic -PassThru
    Runs all tests with maximum verbosity and returns results object.

.NOTES
    Requires Pester module to be installed. The script will automatically detect
    the Pester version and use the appropriate syntax:
    - Pester 5+: Uses PesterConfiguration object
    - Pester 4.x: Uses parameter-based syntax
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Unit', 'Integration', 'All')]
    [string]$TestType = 'All',

    [Parameter()]
    [string]$OutputFormat = 'Detailed',

    [Parameter()]
    [switch]$PassThru
)

# Ensure we're in the script directory
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot)
{
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
Set-Location $ScriptRoot

# Import Pester if not already loaded
# This ensures Pester is available before attempting to use it
if (-not (Get-Module Pester -ListAvailable))
{
    Write-Error 'Pester module is not installed. Please install Pester 5.x first: Install-Module Pester -Force'
    exit 1
}

# Ensure we're using Pester 4+ by importing the latest available version
$PesterModules = Get-Module Pester -ListAvailable | Sort-Object Version -Descending
$LatestPester = $PesterModules[0]

if ($LatestPester.Version.Major -lt 4)
{
    Write-Error @"
The latest available Pester version ($($LatestPester.Version.ToString())) is too old.

This test suite requires Pester 4.0 or higher. Please update Pester:
    Install-Module -Name Pester -Force -SkipPublisherCheck

Available Pester versions:
$($PesterModules | ForEach-Object { "  - $($_.Version.ToString()) at $($_.ModuleBase)" } | Out-String)
"@
    exit 1
}

# Import the latest compatible Pester version
Import-Module Pester -RequiredVersion $LatestPester.Version -Force

# Determine which tests to run based on TestType parameter
# Maps the user-friendly test type names to actual directory paths
$TestPaths = switch ($TestType)
{
    'Unit' { @('./Tests/Unit') }
    'Integration' { @('./Tests/Integration') }
    'All' { @('./Tests/Unit', './Tests/Integration') }
}

# Filter paths to only existing directories
# This prevents errors if one of the test directories doesn't exist
$TestPaths = $TestPaths | Where-Object { Test-Path $_ }

if (-not $TestPaths)
{
    Write-Warning "No test directories found for test type: $TestType"
    exit 1
}

Write-Host "Running $TestType tests from: $($TestPaths -join ', ')" -ForegroundColor Green

# Check Pester version and configure accordingly
# This enables cross-version compatibility between Pester 4.x and 5+
$PesterVersion = (Get-Module Pester).Version
$IsPester5OrHigher = $PesterVersion -and $PesterVersion.Major -ge 5

# Check for Pester 3.x which is not supported
if ($PesterVersion -and $PesterVersion.Major -lt 4)
{
    Write-Error @"
Pester version $($PesterVersion.ToString()) is not supported.

This test suite requires Pester 4.0 or higher due to the following features:

- BeforeAll/BeforeEach blocks (introduced in Pester 4.0)
- Improved parameter validation
- Better cross-platform support

The script attempted to use the latest available version but it's still too old.

Please update Pester:

    Install-Module -Name Pester -Force -SkipPublisherCheck

Current Pester installation: $($LatestPester.ModuleBase)
"@
    exit 1
}

# Validate and map OutputFormat based on Pester version capabilities
$ValidOutputFormats = if ($IsPester5OrHigher)
{
    @('Normal', 'Detailed', 'Diagnostic')
}
else
{
    @('Normal', 'Detailed')  # Pester 4.x may not support 'Diagnostic'
}

if ($OutputFormat -notin $ValidOutputFormats)
{
    Write-Error "Invalid OutputFormat '$OutputFormat'. Valid values for Pester $($PesterVersion.ToString()) are: $($ValidOutputFormats -join ', ')"
    exit 1
}

# Determine which Pester syntax to use based on version and available types
if ($IsPester5OrHigher -and ([System.Management.Automation.PSTypeName]'PesterConfiguration').Type)
{
    # Pester 5+ syntax - uses configuration object for advanced features
    Write-Verbose "Using Pester $($PesterVersion.ToString()) with configuration object syntax"
    $PesterConfiguration = [PesterConfiguration]::Default
    $PesterConfiguration.Run.Path = $TestPaths
    $PesterConfiguration.Run.Exit = $false
    $PesterConfiguration.Run.PassThru = $true
    $PesterConfiguration.Output.Verbosity = $OutputFormat

    # Configure test results output in NUnit XML format
    # This is used by CI/CD systems for test reporting and visualization
    $PesterConfiguration.TestResult.Enabled = $true
    $PesterConfiguration.TestResult.OutputFormat = 'NUnitXml'
    $PesterConfiguration.TestResult.OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'testresults.xml')

    # Run tests
    $oldProgressPreference = $global:ProgressPreference
    try
    {
        # Disable progress bars for cleaner output
        $global:ProgressPreference = 'SilentlyContinue'

        $TestResults = Invoke-Pester -Configuration $PesterConfiguration
    }
    catch
    {
        Write-Error "Error running tests: $($_.Exception.Message)"
        exit 1
    }
    finally
    {
        $global:ProgressPreference = $oldProgressPreference
    }
}
else
{
    # Pester 4.x syntax - uses traditional parameter-based approach
    Write-Verbose "Using Pester $($PesterVersion.ToString()) with parameter-based syntax"
    $PesterParams = @{
        Path = $TestPaths
        PassThru = $true
    }

    # Handle OutputFormat for Pester 4.x
    # Some older versions may not support OutputFormat parameter or have limited options
    if ($PesterVersion -and $PesterVersion.Major -ge 4)
    {
        try
        {
            # Test if OutputFormat parameter accepts our value by attempting to get command metadata
            $pesterCommand = Get-Command Invoke-Pester -Module Pester
            $outputFormatParam = $pesterCommand.Parameters['OutputFormat']
            if ($outputFormatParam -and $outputFormatParam.Attributes.ValidateSet)
            {
                $validSet = $outputFormatParam.Attributes.ValidateSet.ValidValues
                if ($OutputFormat -in $validSet)
                {
                    $PesterParams.OutputFormat = $OutputFormat
                }
                else
                {
                    Write-Warning "OutputFormat '$OutputFormat' not supported in Pester $($PesterVersion.ToString()). Valid values: $($validSet -join ', '). Using default."
                }
            }
            elseif ($outputFormatParam)
            {
                # Parameter exists but no ValidateSet, try to use it
                $PesterParams.OutputFormat = $OutputFormat
            }
        }
        catch
        {
            Write-Warning "Could not determine OutputFormat support in Pester $($PesterVersion.ToString()). Using default output format."
        }
    }

    # Add test results output for Pester 4.x
    # Pester 4.x uses different parameter names for test results
    if ($PesterVersion -and $PesterVersion.Major -ge 4)
    {
        $PesterParams.OutputFile = (Join-Path -Path $PSScriptRoot -ChildPath 'testresults.xml')
        $PesterParams.OutputFormat = 'NUnitXml'
    }

    # Run tests
    $oldProgressPreference = $global:ProgressPreference
    try
    {
        # Disable progress bars for cleaner output
        $global:ProgressPreference = 'SilentlyContinue'

        $TestResults = Invoke-Pester @PesterParams
    }
    catch
    {
        Write-Error "Error running tests: $($_.Exception.Message)"
        exit 1
    }
    finally
    {
        $global:ProgressPreference = $oldProgressPreference
    }
}

# Output results summary
# Display test results in a user-friendly format
Write-Host ''
Write-Host 'Test Results Summary:' -ForegroundColor Yellow
Write-Host "  Total Tests: $($TestResults.TotalCount)" -ForegroundColor White
Write-Host "  Passed: $($TestResults.PassedCount)" -ForegroundColor Green
Write-Host "  Failed: $($TestResults.FailedCount)" -ForegroundColor Red
Write-Host "  Skipped: $($TestResults.SkippedCount)" -ForegroundColor Yellow
Write-Host "  Duration: $($TestResults.Duration)" -ForegroundColor White

# Show failed tests if any
if ($TestResults.FailedCount -gt 0)
{
    Write-Host ''
    Write-Host 'Failed Tests:' -ForegroundColor Red
    $TestResults.Failed | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor Red
    }
}

# Return results if requested
# This allows the script to be used programmatically in CI/CD pipelines or other automation
# When -PassThru is specified, the function returns the PesterResults object instead of just displaying output
if ($PassThru)
{
    return $TestResults
}

# Exit with appropriate code
# 0 for success, non-zero for failures (useful for CI/CD)
exit $TestResults.FailedCount
