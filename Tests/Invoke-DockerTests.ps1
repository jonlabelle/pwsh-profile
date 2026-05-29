#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs the Docker container test workflow.

.DESCRIPTION
    Runs PSScriptAnalyzer followed by Invoke-Tests.ps1 from inside the test
    container. Timing-summary parameters are passed through to Invoke-Tests.ps1
    so Docker runs use the same slow-test Markdown summary implementation as
    local runs.

.PARAMETER TestType
    Specifies which types of tests to run. Passed through to Invoke-Tests.ps1.

.PARAMETER OutputFormat
    Controls Pester output verbosity. Passed through to Invoke-Tests.ps1.

.PARAMETER ShowTimingSummary
    Writes the Markdown timing summary after tests complete. Passed through to
    Invoke-Tests.ps1.

.PARAMETER TimingSummaryTop
    Specifies how many slow test files and test cases to include. Passed
    through to Invoke-Tests.ps1.

.PARAMETER TimingSummaryTitle
    Specifies the Markdown heading text. Passed through to Invoke-Tests.ps1.

.PARAMETER TimingSummaryOutputPath
    Specifies where to append the Markdown timing summary. Use an empty string
    to write the summary to the console. Passed through to Invoke-Tests.ps1.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Unit', 'Integration', 'All')]
    [string]$TestType = 'All',

    [Parameter()]
    [string]$OutputFormat = 'Detailed',

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

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Set-Location -LiteralPath $repoRoot

Write-Host '=== Running PSScriptAnalyzer ==='
Import-Module PSScriptAnalyzer -ErrorAction Stop
Invoke-ScriptAnalyzer -Settings PSScriptAnalyzerSettings.psd1 -Path . -Recurse

Write-Host '=== Running Pester tests ==='
$invokeTestsPath = Join-Path -Path $repoRoot -ChildPath 'Invoke-Tests.ps1'
$invokeTestsParams = @{
    TestType = $TestType
    OutputFormat = $OutputFormat
    TimingSummaryTop = $TimingSummaryTop
    TimingSummaryTitle = $TimingSummaryTitle
    TimingSummaryOutputPath = $TimingSummaryOutputPath
}

if ($ShowTimingSummary)
{
    $invokeTestsParams.ShowTimingSummary = $true
}

& $invokeTestsPath @invokeTestsParams
$testExitCode = if ($null -ne $global:LASTEXITCODE)
{
    $global:LASTEXITCODE
}
else
{
    0
}

exit $testExitCode
