#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    $script:InvokeTestsSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '../../Invoke-Tests.ps1'
    $script:TimingSummarySourcePath = Join-Path -Path $PSScriptRoot -ChildPath '../Write-TestTimingSummary.ps1'
    $script:PowerShellExecutable = (Get-Process -Id $PID).Path

    if (-not $script:PowerShellExecutable)
    {
        $script:PowerShellExecutable = (Get-Command -Name powershell).Source
    }

    function Get-FakeInvokeTestsProject
    {
        param(
            [Parameter(Mandatory)]
            [string]$RootPath,

            [Parameter()]
            [version[]]$PesterVersions = @([version]'6.99.0')
        )

        $testsPath = Join-Path -Path $RootPath -ChildPath 'Tests'
        $unitTestsPath = Join-Path -Path $testsPath -ChildPath 'Unit'
        $moduleRootPath = Join-Path -Path $RootPath -ChildPath 'Modules'
        $pesterModuleRootPath = Join-Path -Path $moduleRootPath -ChildPath 'Pester'

        New-Item -Path $unitTestsPath -ItemType Directory -Force | Out-Null
        New-Item -Path $pesterModuleRootPath -ItemType Directory -Force | Out-Null

        Copy-Item -LiteralPath $script:InvokeTestsSourcePath -Destination (Join-Path -Path $RootPath -ChildPath 'Invoke-Tests.ps1')
        Copy-Item -LiteralPath $script:TimingSummarySourcePath -Destination (Join-Path -Path $testsPath -ChildPath 'Write-TestTimingSummary.ps1')

        foreach ($pesterVersion in $PesterVersions)
        {
            $pesterModulePath = Join-Path -Path $pesterModuleRootPath -ChildPath $pesterVersion.ToString()
            New-Item -Path $pesterModulePath -ItemType Directory -Force | Out-Null

            $moduleManifest = @"
@{
    RootModule = 'Pester.psm1'
    ModuleVersion = '$($pesterVersion.ToString())'
    GUID = '8f60f7c8-ef86-4f89-b46d-d1cc5b3a1111'
    Author = 'Invoke-Tests unit test'
    Description = 'Minimal fake Pester module for Invoke-Tests.ps1 tests.'
    FunctionsToExport = @('Invoke-Pester', 'New-PesterConfiguration')
}
"@

            $moduleBody = @'
function New-PesterConfiguration
{
    return [PSCustomObject]@{
        Run = [PSCustomObject]@{
            Path = @()
            Exit = $false
            PassThru = $true
        }
        Output = [PSCustomObject]@{
            Verbosity = 'Detailed'
        }
        TestResult = [PSCustomObject]@{
            Enabled = $true
            OutputFormat = 'NUnitXml'
            OutputPath = ''
        }
    }
}

function Invoke-Pester
{
    [CmdletBinding()]
    param(
        [Parameter()]
        [Object]$Configuration
    )

    if ($Configuration.TestResult.OutputFormat -ne 'NUnit3')
    {
        throw 'Invoke-Tests.ps1 must select NUnit3 reporting.'
    }

    if ($env:PWSPROFILE_FAKE_PESTER_NO_RESULT -eq '1')
    {
        return $null
    }

    $outputPath = ''
    if ($Configuration -and $Configuration.TestResult -and $Configuration.TestResult.OutputPath)
    {
        $outputPath = $Configuration.TestResult.OutputPath
    }

    if ($outputPath)
    {
        $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<test-run total="2" passed="2" failed="0" skipped="0" duration="7.5">
  <test-suite type="Assembly" name="Slow.Tests.ps1" fullname="/tmp/fake/Tests/Unit/Slow.Tests.ps1" result="Passed" duration="6.4">
    <test-suite type="TestFixture" name="Slow tests" result="Passed" duration="6.4">
      <test-case name="Slow case" result="Passed" duration="5.8" />
    </test-suite>
  </test-suite>
  <test-suite type="Assembly" name="Fast.Tests.ps1" fullname="/tmp/fake/Tests/Unit/Fast.Tests.ps1" result="Passed" duration="1.1">
    <test-suite type="TestFixture" name="Fast tests" result="Passed" duration="1.1">
      <test-case name="Fast case" result="Passed" duration="0.9" />
    </test-suite>
  </test-suite>
</test-run>
"@

        [System.IO.File]::WriteAllText($outputPath, $xml, [System.Text.Encoding]::UTF8)
    }

    if ($env:PWSPROFILE_FAKE_PESTER_VERSION_OUTPUT)
    {
        [System.IO.File]::WriteAllText($env:PWSPROFILE_FAKE_PESTER_VERSION_OUTPUT, $MyInvocation.MyCommand.Module.Version.ToString(), [System.Text.Encoding]::UTF8)
    }

    [PSCustomObject]@{
        TotalCount = 2
        PassedCount = 2
        FailedCount = 0
        SkippedCount = 0
        Duration = [TimeSpan]::FromSeconds(7.5)
        Failed = @()
    }
}

Export-ModuleMember -Function Invoke-Pester, New-PesterConfiguration
'@

            Set-Content -LiteralPath (Join-Path -Path $pesterModulePath -ChildPath 'Pester.psd1') -Value $moduleManifest -Encoding UTF8
            Set-Content -LiteralPath (Join-Path -Path $pesterModulePath -ChildPath 'Pester.psm1') -Value $moduleBody -Encoding UTF8
        }

        return [PSCustomObject]@{
            RootPath = $RootPath
            InvokeTestsPath = Join-Path -Path $RootPath -ChildPath 'Invoke-Tests.ps1'
            ModuleRootPath = $moduleRootPath
        }
    }
}

Describe 'Invoke-Tests.ps1 timing summary' -Tag 'Unit' {
    BeforeEach {
        $script:OriginalPSModulePath = $env:PSModulePath
        $script:TestRootPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "invoke-tests-unit-$(Get-Random)"
        New-Item -Path $script:TestRootPath -ItemType Directory -Force | Out-Null
        $script:FakeProject = Get-FakeInvokeTestsProject -RootPath $script:TestRootPath
    }

    AfterEach {
        $env:PSModulePath = $script:OriginalPSModulePath

        if (Test-Path -LiteralPath $script:TestRootPath)
        {
            Remove-Item -LiteralPath $script:TestRootPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'appends the Markdown timing summary when ShowTimingSummary is specified' {
        $summaryPath = Join-Path -Path $script:TestRootPath -ChildPath 'timings.md'
        $env:PSModulePath = $script:FakeProject.ModuleRootPath

        $null = & $script:PowerShellExecutable -NoProfile -File $script:FakeProject.InvokeTestsPath -TestType Unit -OutputFormat Normal -ShowTimingSummary -TimingSummaryTop 1 -TimingSummaryTitle 'Local timings' -TimingSummaryOutputPath $summaryPath
        $LASTEXITCODE | Should-Be 0

        Test-Path -LiteralPath $summaryPath | Should-BeTruthy
        $summary = Get-Content -LiteralPath $summaryPath -Raw
        $summary | Should-MatchString '### Local timings'
        $summary | Should-MatchString '#### Slowest test files \(top 1\)'
        $summary | Should-MatchString 'Tests/Unit/Slow.Tests.ps1'
        $summary | Should-NotMatchString 'Tests/Unit/Fast.Tests.ps1'
        $summary | Should-MatchString 'Slow case'
        $summary | Should-NotMatchString 'Fast case'
    }

    It 'does not write a timing summary unless ShowTimingSummary is specified' {
        $summaryPath = Join-Path -Path $script:TestRootPath -ChildPath 'timings.md'
        $env:PSModulePath = $script:FakeProject.ModuleRootPath

        $null = & $script:PowerShellExecutable -NoProfile -File $script:FakeProject.InvokeTestsPath -TestType Unit -OutputFormat Normal -TimingSummaryOutputPath $summaryPath
        $LASTEXITCODE | Should-Be 0

        Test-Path -LiteralPath $summaryPath | Should-BeFalsy
    }

    It 'exits with failure when Pester returns no test results' {
        $env:PSModulePath = $script:FakeProject.ModuleRootPath
        $env:PWSPROFILE_FAKE_PESTER_NO_RESULT = '1'

        try
        {
            $stdoutPath = Join-Path -Path $script:TestRootPath -ChildPath 'child-stdout.txt'
            $stderrPath = Join-Path -Path $script:TestRootPath -ChildPath 'child-stderr.txt'
            $arguments = '-NoProfile -File "{0}" -TestType Unit -OutputFormat Normal' -f $script:FakeProject.InvokeTestsPath
            $process = Start-Process -FilePath $script:PowerShellExecutable -ArgumentList $arguments -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

            $process.ExitCode | Should-Be 1
            $stderrText = (Get-Content -LiteralPath $stderrPath -Raw) -replace '\s+', ' '
            $stderrText | Should-MatchString 'Pester did not return test results\.'
        }
        finally
        {
            Remove-Item Env:\PWSPROFILE_FAKE_PESTER_NO_RESULT -ErrorAction SilentlyContinue
        }
    }

    It 'uses the latest installed Pester 6 version and ignores Pester 7' {
        $versionOutputPath = Join-Path -Path $script:TestRootPath -ChildPath 'selected-pester-version.txt'
        $script:FakeProject = Get-FakeInvokeTestsProject -RootPath $script:TestRootPath -PesterVersions @(
            [version]'6.1.0'
            [version]'7.0.0'
            [version]'6.99.0'
        )
        $env:PSModulePath = $script:FakeProject.ModuleRootPath
        $env:PWSPROFILE_FAKE_PESTER_VERSION_OUTPUT = $versionOutputPath

        try
        {
            $null = & $script:PowerShellExecutable -NoProfile -File $script:FakeProject.InvokeTestsPath -TestType Unit -OutputFormat Normal
            $LASTEXITCODE | Should-Be 0

            (Get-Content -LiteralPath $versionOutputPath -Raw).Trim() | Should-Be '6.99.0'
        }
        finally
        {
            Remove-Item Env:\PWSPROFILE_FAKE_PESTER_VERSION_OUTPUT -ErrorAction SilentlyContinue
        }
    }
}
