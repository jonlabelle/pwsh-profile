#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs Pester tests for the PowerShell Profile project with cross-version compatibility.

.DESCRIPTION
    This script runs unit and integration tests using Pester, automatically detecting
    the installed Pester version and using the appropriate syntax for compatibility
    with Pester 4.x and 5.x.

    Requirements:
    - Pester 4.0 through 5.x (Pester 3.x and 6.x are not supported)
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

.PARAMETER ShowTimingSummary
    When specified, writes a Markdown timing summary from the generated NUnit XML
    test results after the test run completes.

.PARAMETER TimingSummaryTop
    Specifies how many slow test files and test cases to include in the timing
    summary. The default is 10.

.PARAMETER TimingSummaryTitle
    Specifies the Markdown heading text for the timing summary.

.PARAMETER TimingSummaryOutputPath
    Specifies where to append the Markdown timing summary. Use an empty string
    to write the summary to the console. The default is an empty string.

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

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType Unit -ShowTimingSummary
    Runs unit tests and writes a Markdown summary of the slowest test files and
    test cases to the console.

.EXAMPLE
    ./Invoke-Tests.ps1 -ShowTimingSummary -TimingSummaryOutputPath test-timing-summary.md
    Runs all tests and appends the timing summary to test-timing-summary.md.

.NOTES
    Requires Pester module to be installed. The script will automatically detect
    the Pester version and use the appropriate syntax:
    - Pester 5.x: Uses PesterConfiguration object
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
    [switch]$PassThru,

    [Parameter()]
    [switch]$ShowTimingSummary,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$TimingSummaryTop = 10,

    [Parameter()]
    [string]$TimingSummaryTitle = 'Pester timing summary',

    [Parameter()]
    [AllowEmptyString()]
    [string]$TimingSummaryOutputPath = ''
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
$TestTimingSummaryScriptPath = Join-Parts -BasePath $ScriptDirectory -PathSegments @('Tests', 'Write-TestTimingSummary.ps1')

# Import Pester if not already loaded
if (-not (Get-Module Pester -ListAvailable))
{
    Write-Error 'Pester module is not installed. Please install Pester 5.x first: Install-Module -Name Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99 -Force -SkipPublisherCheck'
    exit 1
}

# Pester 6 changed mock/assertion behavior used throughout the test suite, so stay
# on the supported 4.x/5.x range until the tests are migrated intentionally.
$availablePesterModules = Get-Module Pester -ListAvailable | Sort-Object Version -Descending
$compatiblePesterModules = $availablePesterModules | Where-Object { $_.Version.Major -ge 4 -and $_.Version.Major -lt 6 }
$selectedPesterModule = $compatiblePesterModules | Select-Object -First 1

if (-not $selectedPesterModule)
{
    Write-Error @"
No compatible Pester version is available.

This test suite currently supports Pester 4.x and 5.x. Pester 6.x introduced mock/assertion behavior changes that are not compatible with these tests.

Please install Pester 5.x:
    Install-Module -Name Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99 -Force -SkipPublisherCheck

Available Pester versions:
$($availablePesterModules | ForEach-Object { "  - $($_.Version.ToString()) at $($_.ModuleBase)" } | Out-String)
"@
    exit 1
}

# Import the latest compatible Pester version
Import-Module Pester -RequiredVersion $selectedPesterModule.Version -Force

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
$isPesterVersion5 = $installedPesterVersion -and $installedPesterVersion.Major -eq 5

# Check for unsupported Pester versions
if ($installedPesterVersion -and ($installedPesterVersion.Major -lt 4 -or $installedPesterVersion.Major -ge 6))
{
    Write-Error @"
Pester version $($installedPesterVersion.ToString()) is not supported.

This test suite supports Pester 4.x and 5.x due to the following features and compatibility requirements:

- BeforeAll/BeforeEach blocks (introduced in Pester 4.0)
- Improved parameter validation
- Better cross-platform support
- Pester 4.x/5.x mock/assertion semantics used by the current tests

The script attempted to use the latest compatible available version, but an unsupported version was imported.

Please install Pester 5.x:

    Install-Module -Name Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99 -Force -SkipPublisherCheck

Current Pester installation: $($selectedPesterModule.ModuleBase)
"@
    exit 1
}

# Validate and map OutputFormat based on Pester version capabilities
$ValidOutputFormats = if ($isPesterVersion5)
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
if ($isPesterVersion5 -and ([System.Management.Automation.PSTypeName]'PesterConfiguration').Type)
{
    # Pester 5.x syntax
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

if ($ShowTimingSummary)
{
    if (-not (Test-Path -LiteralPath $TestTimingSummaryScriptPath -PathType Leaf))
    {
        Write-Warning "Could not find test timing summary script at '$TestTimingSummaryScriptPath'."
    }
    else
    {
        Write-Host ''

        $timingSummaryParams = @{
            Path = $NUnitResultsPath
            Top = $TimingSummaryTop
            Title = $TimingSummaryTitle
            OutputPath = $TimingSummaryOutputPath
        }

        try
        {
            $timingSummaryOutput = & $TestTimingSummaryScriptPath @timingSummaryParams
            if ($PassThru)
            {
                $timingSummaryOutput | ForEach-Object {
                    Write-Host $_
                }
            }
            else
            {
                $timingSummaryOutput
            }
        }
        catch
        {
            Write-Warning "Could not write test timing summary: $($_.Exception.Message)"
        }
    }
}

# Return results if requested
if ($PassThru)
{
    return $pesterTestResults
}

# Exit with appropriate code
exit $pesterTestResults.FailedCount
