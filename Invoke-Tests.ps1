#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs all Pester tests for the PowerShell Profile project.

.DESCRIPTION
    This script runs all unit and integration tests using Pester 5.x.
    It can be used locally or in CI/CD pipelines.

.PARAMETER TestType
    Specifies which types of tests to run. Valid values: 'Unit', 'Integration', 'All'
    Default is 'All'.

.PARAMETER OutputFormat
    Specifies the output format. Valid values: 'Normal', 'Detailed', 'Diagnostic'
    Default is 'Detailed'.

.PARAMETER PassThru
    Returns the Pester result object for further processing.

.EXAMPLE
    ./Invoke-Tests.ps1
    Runs all tests with detailed output.

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType Unit
    Runs only unit tests.

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType Integration -OutputFormat Normal
    Runs only integration tests with normal output.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Unit', 'Integration', 'All')]
    [string]$TestType = 'All',

    [Parameter()]
    [ValidateSet('Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',

    [Parameter()]
    [switch]$PassThru
)

# Ensure we're in the script directory
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
Set-Location $ScriptRoot

# Import Pester if not already loaded
if (-not (Get-Module -Name Pester -ListAvailable)) {
    Write-Error "Pester module is not installed. Please install Pester 5.x first: Install-Module Pester -Force"
    exit 1
}

Import-Module Pester -Force

# Determine which tests to run
$TestPaths = switch ($TestType) {
    'Unit' { @('./Tests/Unit') }
    'Integration' { @('./Tests/Integration') }
    'All' { @('./Tests/Unit', './Tests/Integration') }
}

# Filter paths to only existing directories
$TestPaths = $TestPaths | Where-Object { Test-Path $_ }

if (-not $TestPaths) {
    Write-Warning "No test directories found for test type: $TestType"
    exit 1
}

Write-Host "Running $TestType tests from: $($TestPaths -join ', ')" -ForegroundColor Green

# Configure Pester
$PesterConfiguration = [PesterConfiguration]::Default
$PesterConfiguration.Run.Path = $TestPaths
$PesterConfiguration.Run.Exit = $false
$PesterConfiguration.Run.PassThru = $true
$PesterConfiguration.Output.Verbosity = $OutputFormat

# Configure test results
$PesterConfiguration.TestResult.Enabled = $true
$PesterConfiguration.TestResult.OutputFormat = 'NUnitXml'
$PesterConfiguration.TestResult.OutputPath = './testresults.xml'

# Run tests
try {
    $TestResults = Invoke-Pester -Configuration $PesterConfiguration

    # Output results summary
    Write-Host ""
    Write-Host "Test Results Summary:" -ForegroundColor Yellow
    Write-Host "  Total Tests: $($TestResults.TotalCount)" -ForegroundColor White
    Write-Host "  Passed: $($TestResults.PassedCount)" -ForegroundColor Green
    Write-Host "  Failed: $($TestResults.FailedCount)" -ForegroundColor Red
    Write-Host "  Skipped: $($TestResults.SkippedCount)" -ForegroundColor Yellow
    Write-Host "  Duration: $($TestResults.Duration)" -ForegroundColor White

    if ($TestResults.FailedCount -gt 0) {
        Write-Host ""
        Write-Host "Failed Tests:" -ForegroundColor Red
        $TestResults.Failed | ForEach-Object {
            Write-Host "  - $($_.Name)" -ForegroundColor Red
        }
    }

    # Return results if requested
    if ($PassThru) {
        return $TestResults
    }

    # Exit with appropriate code
    exit $TestResults.FailedCount
}
catch {
    Write-Error "Error running tests: $($_.Exception.Message)"
    exit 1
}