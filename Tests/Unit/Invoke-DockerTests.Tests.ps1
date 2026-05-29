#Requires -Modules Pester

BeforeAll {
    $script:InvokeDockerTestsSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '../Invoke-DockerTests.ps1'
    $script:PowerShellExecutable = (Get-Process -Id $PID).Path

    if (-not $script:PowerShellExecutable)
    {
        $script:PowerShellExecutable = (Get-Command -Name powershell).Source
    }

    function Get-FakeDockerTestProject
    {
        param(
            [Parameter(Mandatory)]
            [string]$RootPath
        )

        $testsPath = Join-Path -Path $RootPath -ChildPath 'Tests'

        New-Item -Path $testsPath -ItemType Directory -Force | Out-Null

        Copy-Item -LiteralPath $script:InvokeDockerTestsSourcePath -Destination (Join-Path -Path $testsPath -ChildPath 'Invoke-DockerTests.ps1')

        $invokeTestsBody = @'
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

$record = [ordered]@{
    TestType = $TestType
    OutputFormat = $OutputFormat
    ShowTimingSummary = $ShowTimingSummary.IsPresent
    TimingSummaryTop = $TimingSummaryTop
    TimingSummaryTitle = $TimingSummaryTitle
    TimingSummaryOutputPath = $TimingSummaryOutputPath
    WorkingDirectory = (Get-Location).Path
}

$record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'invoke-tests-args.json') -Encoding UTF8

$exitCode = 0
if (-not [string]::IsNullOrWhiteSpace($env:FAKE_INVOKE_TESTS_EXIT_CODE))
{
    $exitCode = [int]$env:FAKE_INVOKE_TESTS_EXIT_CODE
}

exit $exitCode
'@

        Set-Content -LiteralPath (Join-Path -Path $RootPath -ChildPath 'Invoke-Tests.ps1') -Value $invokeTestsBody -Encoding UTF8
        Set-Content -LiteralPath (Join-Path -Path $RootPath -ChildPath 'PSScriptAnalyzerSettings.psd1') -Value '@{}' -Encoding UTF8

        return [PSCustomObject]@{
            RootPath = $RootPath
            InvokeDockerTestsPath = Join-Path -Path $testsPath -ChildPath 'Invoke-DockerTests.ps1'
            InvokeTestsRecordPath = Join-Path -Path $RootPath -ChildPath 'invoke-tests-args.json'
        }
    }
}

Describe 'Invoke-DockerTests.ps1' -Tag 'Unit' {
    BeforeEach {
        $script:TestRootPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "invoke-docker-tests-unit-$(Get-Random)"
        New-Item -Path $script:TestRootPath -ItemType Directory -Force | Out-Null
        $script:FakeProject = Get-FakeDockerTestProject -RootPath $script:TestRootPath
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestRootPath)
        {
            Remove-Item -LiteralPath $script:TestRootPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Remove-Item -Path Env:FAKE_INVOKE_TESTS_EXIT_CODE -ErrorAction SilentlyContinue
    }

    It 'passes timing summary options through to Invoke-Tests.ps1' {
        $output = & $script:PowerShellExecutable -NoProfile -File $script:FakeProject.InvokeDockerTestsPath -TestType Unit -OutputFormat Normal -ShowTimingSummary -TimingSummaryTop 5 -TimingSummaryTitle 'Docker timings' -TimingSummaryOutputPath 'docker-timings.md' 2>&1
        $LASTEXITCODE | Should -Be 0
        ($output -join [Environment]::NewLine) | Should -Match '=== Running PSScriptAnalyzer ==='
        ($output -join [Environment]::NewLine) | Should -Match '=== Running Pester tests ==='

        $invokeTestsRecord = Get-Content -LiteralPath $script:FakeProject.InvokeTestsRecordPath -Raw | ConvertFrom-Json
        $invokeTestsRecord.TestType | Should -Be 'Unit'
        $invokeTestsRecord.OutputFormat | Should -Be 'Normal'
        $invokeTestsRecord.ShowTimingSummary | Should -BeTrue
        $invokeTestsRecord.TimingSummaryTop | Should -Be 5
        $invokeTestsRecord.TimingSummaryTitle | Should -Be 'Docker timings'
        $invokeTestsRecord.TimingSummaryOutputPath | Should -Be 'docker-timings.md'
        $invokeTestsRecord.WorkingDirectory | Should -Be $script:FakeProject.RootPath
    }

    It 'keeps the timing summary disabled by default' {
        $null = & $script:PowerShellExecutable -NoProfile -File $script:FakeProject.InvokeDockerTestsPath
        $LASTEXITCODE | Should -Be 0

        $invokeTestsRecord = Get-Content -LiteralPath $script:FakeProject.InvokeTestsRecordPath -Raw | ConvertFrom-Json
        $invokeTestsRecord.TestType | Should -Be 'All'
        $invokeTestsRecord.OutputFormat | Should -Be 'Detailed'
        $invokeTestsRecord.ShowTimingSummary | Should -BeFalse
        $invokeTestsRecord.TimingSummaryTop | Should -Be 10
        $invokeTestsRecord.TimingSummaryTitle | Should -Be 'Pester timing summary'
        $invokeTestsRecord.TimingSummaryOutputPath | Should -Be ''
    }

    It 'propagates the Invoke-Tests.ps1 exit code' {
        $env:FAKE_INVOKE_TESTS_EXIT_CODE = '7'

        $null = & $script:PowerShellExecutable -NoProfile -File $script:FakeProject.InvokeDockerTestsPath
        $LASTEXITCODE | Should -Be 7
    }
}
