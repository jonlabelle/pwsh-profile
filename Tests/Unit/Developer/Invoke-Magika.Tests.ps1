#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Invoke-Magika.

.DESCRIPTION
    Validates Docker prerequisite checks, argument construction, path handling,
    pipeline behavior, and exit code behavior for Magika Docker wrapper operations.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Invoke-Magika.ps1"

    # Deterministic shim used by Get-Command mocks so tests do not depend on Docker being installed.
    $script:DockerCommandName = 'pwshDockerTestShim'
    $script:DockerShimInvocations = @()

    function pwshDockerTestShim
    {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [Object[]]$RemainingArgs
        )

        $argsArray = @($RemainingArgs)
        $script:DockerShimInvocations += , $argsArray

        $global:LASTEXITCODE = 0
        return @('shim output')
    }
}

AfterAll {
    Remove-Item -Path Function:\pwshDockerTestShim -ErrorAction SilentlyContinue
}

Describe 'Invoke-Magika' {
    BeforeEach {
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "magika-tests-$(Get-Random)"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        # Reset shim state for each test
        $script:DockerShimInvocations = @()
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestDir)
        {
            Remove-Item -LiteralPath $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Prerequisite validation' {
        It 'Throws when Docker is not installed' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith { $null }

            { Invoke-Magika -Path 'README.md' } | Should -Throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
        }

        It 'Throws when Docker daemon is not running' {
            function script:pwshDockerTestShimDaemonDown
            {
                param(
                    [Parameter(ValueFromRemainingArguments = $true)]
                    [Object[]]$RemainingArgs
                )

                $argsArray = @($RemainingArgs)
                $script:DockerShimInvocations += , $argsArray

                $global:LASTEXITCODE = 1
                return @('daemon down')
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = 'pwshDockerTestShimDaemonDown'
                    Source = '/usr/local/bin/docker'
                }
            }

            { Invoke-Magika -Path 'README.md' } | Should -Throw '*daemon is not running*'

            Remove-Item -Path Function:\pwshDockerTestShimDaemonDown -ErrorAction SilentlyContinue
        }
    }

    Context 'Parameter validation' {
        It 'Rejects empty Path' {
            { Invoke-Magika -Path '' } | Should -Throw
        }

        It 'Rejects using Path and LiteralPath together' {
            { Invoke-Magika -Path 'README.md' -LiteralPath 'README.md' } | Should -Throw
        }

        It 'Rejects empty ImageTag' {
            { Invoke-Magika -Path 'README.md' -ImageTag '' } | Should -Throw
        }
    }

    Context 'Docker argument construction' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            $script:SampleFile = Join-Path -Path $script:TestDir -ChildPath 'sample.txt'
            'sample' | Set-Content -LiteralPath $script:SampleFile

            Push-Location $script:TestDir
        }

        AfterEach {
            Pop-Location
        }

        It 'Uses -i and --rm flags for docker run' {
            Invoke-Magika -Path $script:SampleFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '-i'
            $runCall | Should -Contain '--rm'
        }

        It 'Mounts the working directory as read-only /workspace volume' {
            Invoke-Magika -Path $script:SampleFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '-v'
            $volArg = $runCall | Where-Object { $_ -match ':/workspace:ro$' }
            $volArg | Should -Not -BeNullOrEmpty
        }

        It 'Sets the working directory to /workspace' {
            Invoke-Magika -Path $script:SampleFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '-w'
            $runCall | Should -Contain '/workspace'
        }

        It 'Uses correct image reference with default tag' {
            Invoke-Magika -Path $script:SampleFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain 'jonlabelle/magika:latest'
        }

        It 'Uses correct image reference with custom tag' {
            Invoke-Magika -Path $script:SampleFile -ImageTag '0.6.0' | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain 'jonlabelle/magika:0.6.0'
        }

        It 'Appends additional arguments' {
            Invoke-Magika -Path $script:SampleFile -AdditionalArgs '--json' | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--json'
        }

        It 'Includes normalized relative path in docker args' {
            Invoke-Magika -Path $script:SampleFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain 'sample.txt'
        }

        It 'Defaults to current directory when no path is provided' {
            Invoke-Magika | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '.'
        }

        It 'Expands wildcard Path patterns to matching files' {
            'a' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'a.txt')
            'b' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'b.txt')
            'c' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'c.log')

            Invoke-Magika -Path '*.txt' | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain 'a.txt'
            $runCall | Should -Contain 'b.txt'
        }

        It 'Treats wildcard characters literally with LiteralPath' {
            $specialName = 'report[1].txt'
            'data' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath $specialName)

            Invoke-Magika -LiteralPath $specialName | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain $specialName
        }
    }

    Context 'Path scope validation' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            Push-Location $script:TestDir
        }

        AfterEach {
            Pop-Location
        }

        It 'Throws when the path resolves outside the current working directory' {
            $outsideDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "magika-outside-$(Get-Random)"
            $outsideFile = Join-Path -Path $outsideDir -ChildPath 'outside.txt'

            New-Item -Path $outsideDir -ItemType Directory -Force | Out-Null
            'outside' | Set-Content -LiteralPath $outsideFile

            try
            {
                { Invoke-Magika -Path $outsideFile } | Should -Throw '*outside the current working directory*'
            }
            finally
            {
                if (Test-Path -LiteralPath $outsideDir)
                {
                    Remove-Item -LiteralPath $outsideDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context 'Exit code handling' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            $script:SampleFile = Join-Path -Path $script:TestDir -ChildPath 'sample.txt'
            'sample' | Set-Content -LiteralPath $script:SampleFile

            Push-Location $script:TestDir
        }

        AfterEach {
            Pop-Location
        }

        It 'Returns exit code 0 on success' {
            $result = @(Invoke-Magika -Path $script:SampleFile)

            $result[-1] | Should -Be 0
        }

        It 'Returns non-zero exit code on failure and writes warning' {
            function script:pwshDockerTestShimFail
            {
                param(
                    [Parameter(ValueFromRemainingArguments = $true)]
                    [Object[]]$RemainingArgs
                )

                $argsArray = @($RemainingArgs)
                $script:DockerShimInvocations += , $argsArray

                if ($argsArray.Count -gt 0 -and $argsArray[0] -eq 'run')
                {
                    $global:LASTEXITCODE = 2
                    return @('error output')
                }
                $global:LASTEXITCODE = 0
                return @('info output')
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = 'pwshDockerTestShimFail'
                    Source = '/usr/local/bin/docker'
                }
            }

            $result = @(Invoke-Magika -Path $script:SampleFile 3>&1)

            $exitCode = $result | Where-Object { $_ -is [Int32] -or $_ -is [Int64] }
            $exitCode | Should -Be 2

            $warnings = @($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $warnings.Count | Should -BeGreaterThan 0
            $warnings[0].Message | Should -BeLike '*Magika failed*'

            Remove-Item -Path Function:\pwshDockerTestShimFail -ErrorAction SilentlyContinue
        }
    }

    Context 'Pipeline input' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            Push-Location $script:TestDir
        }

        AfterEach {
            Pop-Location
        }

        It 'Accepts FileInfo objects from pipeline' {
            'one' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'one.txt')

            Get-ChildItem -Path $script:TestDir -Filter '*.txt' | Invoke-Magika | Out-Null

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_ -contains 'run' })
            $runCalls.Count | Should -Be 1
        }

        It 'Processes multiple files from pipeline' {
            'one' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'one.txt')
            'two' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'two.txt')

            Get-ChildItem -Path $script:TestDir -Filter '*.txt' | Invoke-Magika | Out-Null

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_ -contains 'run' })
            $runCalls.Count | Should -Be 2
        }
    }
}
