#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Writes a Markdown timing summary from Pester NUnit XML results.

.DESCRIPTION
    Reads testresults.xml and summarizes total duration, slowest test files, and
    slowest test cases. In GitHub Actions, output is appended to the step summary.
    Outside GitHub Actions, the summary is written to the pipeline.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = 'testresults.xml',

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$Top = 10,

    [Parameter()]
    [string]$Title = 'Pester timing summary',

    [Parameter()]
    [AllowEmptyString()]
    [string]$OutputPath = $env:GITHUB_STEP_SUMMARY
)

function Format-TestDuration
{
    param(
        [Parameter(Mandatory)]
        [double]$Seconds
    )

    return ('{0:N1}s' -f $Seconds)
}

function ConvertTo-MarkdownCell
{
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value)
    {
        return ''
    }

    return ([string]$Value) -replace '\|', '\|' -replace '\r?\n', ' '
}

function Get-RelativeTestName
{
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $normalizedName = $Name -replace '\\', '/'
    if ($normalizedName -match '(Tests/.*)$')
    {
        return $Matches[1]
    }

    return $normalizedName
}

function Write-MarkdownSummary
{
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter()]
        [AllowEmptyString()]
        [string]$DestinationPath
    )

    $content = ($Lines -join [Environment]::NewLine) + ([Environment]::NewLine * 2)

    if (-not [string]::IsNullOrWhiteSpace($DestinationPath))
    {
        [System.IO.File]::AppendAllText($DestinationPath, $content, [System.Text.Encoding]::UTF8)
        return
    }

    $Lines
}

$summaryLines = [System.Collections.Generic.List[string]]::new()
[void]$summaryLines.Add("### $(ConvertTo-MarkdownCell -Value $Title)")
[void]$summaryLines.Add('')

if (-not (Test-Path -LiteralPath $Path))
{
    [void]$summaryLines.Add("No test result file found at ``$Path``.")
    Write-MarkdownSummary -Lines $summaryLines.ToArray() -DestinationPath $OutputPath
    return
}

try
{
    $testResults = [System.Xml.XmlDocument]::new()
    $testResults.Load((Resolve-Path -LiteralPath $Path).ProviderPath)
}
catch
{
    [void]$summaryLines.Add("Could not parse ``$Path``: $($_.Exception.Message)")
    Write-MarkdownSummary -Lines $summaryLines.ToArray() -DestinationPath $OutputPath
    return
}

$reportFormat = $testResults.DocumentElement.LocalName
if ($reportFormat -eq 'test-run')
{
    $rootSuite = $testResults.'test-run'
    $fileSuites = @($testResults.SelectNodes('/test-run/test-suite[@type="Assembly"]'))
    $caseNodes = @($testResults.SelectNodes('//test-case') | Where-Object { $_.result -ne 'Skipped' })
    $durationAttribute = 'duration'
    $totalTests = [int]$rootSuite.total
    $failedTests = [int]$rootSuite.failed
    $skippedTests = [int]$rootSuite.skipped
}
elseif ($reportFormat -eq 'test-results')
{
    $rootSuite = $testResults.'test-results'.'test-suite'
    $fileSuites = @($rootSuite.results.'test-suite')
    $caseNodes = @($testResults.SelectNodes('//test-case') | Where-Object { $_.executed -eq 'True' })
    $durationAttribute = 'time'
    $totalTests = [int]$testResults.'test-results'.total
    $failedTests = [int]$testResults.'test-results'.failures
    $skippedTests = [int]$testResults.'test-results'.skipped
}

if (-not $rootSuite)
{
    [void]$summaryLines.Add("No supported NUnit root found in ``$Path``.")
    Write-MarkdownSummary -Lines $summaryLines.ToArray() -DestinationPath $OutputPath
    return
}

$totalSeconds = [double]$rootSuite.$durationAttribute

[void]$summaryLines.Add('| Metric | Value |')
[void]$summaryLines.Add('| --- | ---: |')
[void]$summaryLines.Add("| Total duration | $(Format-TestDuration -Seconds $totalSeconds) |")
[void]$summaryLines.Add("| Total tests | $totalTests |")
[void]$summaryLines.Add("| Failed tests | $failedTests |")
[void]$summaryLines.Add("| Skipped tests | $skippedTests |")
[void]$summaryLines.Add('')

$fileRows = @($fileSuites | ForEach-Object {
        [PSCustomObject]@{
            Name = Get-RelativeTestName -Name $(if ($reportFormat -eq 'test-run') { $_.fullname } else { $_.name })
            Result = $_.result
            Seconds = [double]$_.$durationAttribute
        }
    } | Sort-Object -Property Seconds -Descending | Select-Object -First $Top)

[void]$summaryLines.Add("#### Slowest test files (top $Top)")
[void]$summaryLines.Add('| Duration | Result | File |')
[void]$summaryLines.Add('| ---: | --- | --- |')
foreach ($fileRow in $fileRows)
{
    [void]$summaryLines.Add("| $(Format-TestDuration -Seconds $fileRow.Seconds) | $(ConvertTo-MarkdownCell -Value $fileRow.Result) | $(ConvertTo-MarkdownCell -Value $fileRow.Name) |")
}
[void]$summaryLines.Add('')

$caseRows = @($caseNodes | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.name
            Result = $_.result
            Seconds = [double]$_.$durationAttribute
        }
    } | Sort-Object -Property Seconds -Descending | Select-Object -First $Top)

[void]$summaryLines.Add("#### Slowest test cases (top $Top)")
[void]$summaryLines.Add('| Duration | Result | Test case |')
[void]$summaryLines.Add('| ---: | --- | --- |')
foreach ($caseRow in $caseRows)
{
    [void]$summaryLines.Add("| $(Format-TestDuration -Seconds $caseRow.Seconds) | $(ConvertTo-MarkdownCell -Value $caseRow.Result) | $(ConvertTo-MarkdownCell -Value $caseRow.Name) |")
}

Write-MarkdownSummary -Lines $summaryLines.ToArray() -DestinationPath $OutputPath
