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
$ScriptDirectory = $PSScriptRoot
if (-not $ScriptDirectory)
{
    $ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
}
Set-Location $ScriptDirectory

# ---- Path helpers (PowerShell 5.1-safe) ----
function Join-Parts
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param(
        [Parameter(Mandatory)] [string]$BasePath,
        [Parameter(Mandatory)] [string[]]$PathSegments
    )
    $path = $BasePath
    foreach ($segment in $PathSegments)
    {
        $path = Join-Path -Path $path -ChildPath $segment
    }
    return $path
}

$UnitTestsPath = Join-Parts -BasePath $ScriptDirectory -PathSegments @('Tests', 'Unit')
$IntegrationTestsPath = Join-Parts -BasePath $ScriptDirectory -PathSegments @('Tests', 'Integration')
$NUnitResultsPath = Join-Path -Path $ScriptDirectory -ChildPath 'testresults.xml'

# Import Pester if not already loaded
if (-not (Get-Module Pester -ListAvailable))
{
    Write-Error 'Pester module is not installed. Please install Pester 5.x first: Install-Module Pester -Force'
    exit 1
}

# Ensure we're using Pester 4+ by importing the latest available version
$availablePesterModules = Get-Module Pester -ListAvailable | Sort-Object Version -Descending
$latestPesterModule = $availablePesterModules[0]

if ($latestPesterModule.Version.Major -lt 4)
{
    Write-Error @"
The latest available Pester version ($($latestPesterModule.Version.ToString())) is too old.

This test suite requires Pester 4.0 or higher. Please update Pester:
    Install-Module -Name Pester -Force -SkipPublisherCheck

Available Pester versions:
$($availablePesterModules | ForEach-Object { "  - $($_.Version.ToString()) at $($_.ModuleBase)" } | Out-String)
"@
    exit 1
}

# Import the latest compatible Pester version
Import-Module Pester -RequiredVersion $latestPesterModule.Version -Force

# Determine which tests to run based on TestType parameter
$testPathsToRun = switch ($TestType)
{
    'Unit' { @($UnitTestsPath) }
    'Integration' { @($IntegrationTestsPath) }
    'All' { @($UnitTestsPath, $IntegrationTestsPath) }
}

# Filter paths to only existing directories
$testPathsToRun = $testPathsToRun | Where-Object { Test-Path $_ }

if (-not $testPathsToRun)
{
    Write-Warning "No test directories found for test type: $TestType"
    exit 1
}

Write-Host "Running $TestType tests from: $($testPathsToRun -join ', ')" -ForegroundColor Green

# Check Pester version and configure accordingly
$installedPesterVersion = (Get-Module Pester).Version
$isPesterVersion5OrHigher = $installedPesterVersion -and $installedPesterVersion.Major -ge 5

# Check for Pester 3.x which is not supported
if ($installedPesterVersion -and $installedPesterVersion.Major -lt 4)
{
    Write-Error @"
Pester version $($installedPesterVersion.ToString()) is not supported.

This test suite requires Pester 4.0 or higher due to the following features:

- BeforeAll/BeforeEach blocks (introduced in Pester 4.0)
- Improved parameter validation
- Better cross-platform support

The script attempted to use the latest available version but it's still too old.

Please update Pester:

    Install-Module -Name Pester -Force -SkipPublisherCheck

Current Pester installation: $($latestPesterModule.ModuleBase)
"@
    exit 1
}

# Validate and map OutputFormat based on Pester version capabilities
$ValidOutputFormats = if ($isPesterVersion5OrHigher)
{
    @('Normal', 'Detailed', 'Diagnostic')
}
else
{
    @('Normal', 'Detailed')
}

if ($OutputFormat -notin $ValidOutputFormats)
{
    Write-Error "Invalid OutputFormat '$OutputFormat'. Valid values for Pester $($installedPesterVersion.ToString()) are: $($ValidOutputFormats -join ', ')"
    exit 1
}

# Determine which Pester syntax to use based on version and available types
if ($isPesterVersion5OrHigher -and ([System.Management.Automation.PSTypeName]'PesterConfiguration').Type)
{
    # Pester 5+ syntax
    Write-Verbose "Using Pester $($installedPesterVersion.ToString()) with configuration object syntax"
    $PesterConfiguration = [PesterConfiguration]::Default
    $PesterConfiguration.Run.Path = $testPathsToRun
    $PesterConfiguration.Run.Exit = $false
    $PesterConfiguration.Run.PassThru = $true
    $PesterConfiguration.Output.Verbosity = $OutputFormat

    # NUnit XML results
    $PesterConfiguration.TestResult.Enabled = $true
    $PesterConfiguration.TestResult.OutputFormat = 'NUnitXml'
    $PesterConfiguration.TestResult.OutputPath = $NUnitResultsPath

    # Run tests
    $previousProgressPreference = $global:ProgressPreference
    try
    {
        $global:ProgressPreference = 'SilentlyContinue'
        $pesterTestResults = Invoke-Pester -Configuration $PesterConfiguration
    }
    catch
    {
        Write-Error "Error running tests: $($_.Exception.Message)"
        exit 1
    }
    finally
    {
        $global:ProgressPreference = $previousProgressPreference
    }
}
else
{
    # Pester 4.x syntax
    Write-Verbose "Using Pester $($installedPesterVersion.ToString()) with parameter-based syntax"
    $invokePesterParams = @{
        Path = $testPathsToRun
        PassThru = $true
    }

    # Handle OutputFormat for Pester 4.x when available
    if ($installedPesterVersion -and $installedPesterVersion.Major -ge 4)
    {
        try
        {
            $invokePesterCommand = Get-Command Invoke-Pester -Module Pester
            $outputFormatParameter = $invokePesterCommand.Parameters['OutputFormat']
            if ($outputFormatParameter -and $outputFormatParameter.Attributes.ValidateSet)
            {
                $validOutputFormatSet = $outputFormatParameter.Attributes.ValidateSet.ValidValues
                if ($OutputFormat -in $validOutputFormatSet)
                {
                    $invokePesterParams.OutputFormat = $OutputFormat
                }
                else
                {
                    Write-Warning "OutputFormat '$OutputFormat' not supported in Pester $($installedPesterVersion.ToString()). Valid values: $($validOutputFormatSet -join ', '). Using default."
                }
            }
            elseif ($outputFormatParameter)
            {
                $invokePesterParams.OutputFormat = $OutputFormat
            }
        }
        catch
        {
            Write-Warning "Could not determine OutputFormat support in Pester $($installedPesterVersion.ToString()). Using default output format."
        }
    }

    # NUnit XML results (Pester 4.x)
    if ($installedPesterVersion -and $installedPesterVersion.Major -ge 4)
    {
        $invokePesterParams.OutputFile = $NUnitResultsPath
        $invokePesterParams.OutputFormat = 'NUnitXml'
    }

    # Run tests
    $previousProgressPreference = $global:ProgressPreference
    try
    {
        $global:ProgressPreference = 'SilentlyContinue'
        $pesterTestResults = Invoke-Pester @invokePesterParams
    }
    catch
    {
        Write-Error "Error running tests: $($_.Exception.Message)"
        exit 1
    }
    finally
    {
        $global:ProgressPreference = $previousProgressPreference
    }
}

# Output results summary
Write-Host ''
Write-Host 'Test Results Summary:' -ForegroundColor Yellow
Write-Host "  Total Tests: $($pesterTestResults.TotalCount)" -ForegroundColor White
Write-Host "  Passed: $($pesterTestResults.PassedCount)" -ForegroundColor Green
Write-Host "  Failed: $($pesterTestResults.FailedCount)" -ForegroundColor Red
Write-Host "  Skipped: $($pesterTestResults.SkippedCount)" -ForegroundColor Yellow
Write-Host "  Duration: $($pesterTestResults.Duration)" -ForegroundColor White

# Show failed tests if any
if ($pesterTestResults.FailedCount -gt 0)
{
    Write-Host ''
    Write-Host 'Failed Tests:' -ForegroundColor Red
    $pesterTestResults.Failed | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor Red
    }
}

# Return results if requested
if ($PassThru)
{
    return $pesterTestResults
}

# Exit with appropriate code
exit $pesterTestResults.FailedCount
