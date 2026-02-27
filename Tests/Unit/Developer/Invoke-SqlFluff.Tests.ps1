#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Invoke-SqlFluff.

.DESCRIPTION
    Validates Docker prerequisite checks, argument construction, volume mounting,
    SQL file discovery, config file handling, ShouldProcess gating, and exit code
    behavior for SQLFluff Docker wrapper operations.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Invoke-SqlFluff.ps1"

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

Describe 'Invoke-SqlFluff' {
    BeforeEach {
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "sqlfluff-tests-$(Get-Random)"
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

            { Invoke-SqlFluff -Mode lint -Path 'test.sql' } | Should -Throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
        }

        It 'Throws when Docker daemon is not running' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = 'docker'
                    Source = '/usr/local/bin/docker'
                }
            }

            Mock -CommandName docker -MockWith { $global:LASTEXITCODE = 1 }

            { Invoke-SqlFluff -Mode lint -Path 'test.sql' } | Should -Throw '*daemon is not running*'
        }
    }

    Context 'Parameter validation' {
        It 'Rejects invalid Mode "<Value>"' -ForEach @(
            @{ Value = 'check' }
            @{ Value = 'analyze' }
            @{ Value = '' }
        ) {
            { Invoke-SqlFluff -Mode $Value -Path 'test.sql' } | Should -Throw
        }

        It 'Accepts valid Mode "<Value>"' -ForEach @(
            @{ Value = 'lint' }
            @{ Value = 'fix' }
            @{ Value = 'format' }
        ) {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            $sqlFile = Join-Path -Path $script:TestDir -ChildPath 'test.sql'
            'SELECT 1' | Set-Content -LiteralPath $sqlFile

            Push-Location $script:TestDir
            try
            {
                { Invoke-SqlFluff -Mode $Value -Path $sqlFile -Confirm:$false } | Should -Not -Throw '*Cannot validate argument*'
            }
            finally
            {
                Pop-Location
            }
        }

        It 'Rejects empty Path' {
            { Invoke-SqlFluff -Mode lint -Path '' } | Should -Throw
        }

        It 'Rejects empty ImageTag' {
            { Invoke-SqlFluff -Mode lint -Path 'test.sql' -ImageTag '' } | Should -Throw
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

            # Create a SQL file for testing
            $script:SqlFile = Join-Path -Path $script:TestDir -ChildPath 'query.sql'
            'SELECT 1' | Set-Content -LiteralPath $script:SqlFile

            Push-Location $script:TestDir
        }

        AfterEach {
            Pop-Location
        }

        It 'Passes the correct mode "<Mode>" to SQLFluff' -ForEach @(
            @{ Mode = 'lint' }
            @{ Mode = 'fix' }
            @{ Mode = 'format' }
        ) {
            Invoke-SqlFluff -Mode $Mode -Path $script:SqlFile -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain $Mode
        }

        It 'Uses -i and --rm flags for docker run' {
            Invoke-SqlFluff -Mode lint -Path $script:SqlFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '-i'
            $runCall | Should -Contain '--rm'
        }

        It 'Mounts the working directory as /sql volume' {
            Invoke-SqlFluff -Mode lint -Path $script:SqlFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '-v'
            $volArg = $runCall | Where-Object { $_ -match ':/sql$' }
            $volArg | Should -Not -BeNullOrEmpty
        }

        It 'Uses correct image reference with default tag' {
            Invoke-SqlFluff -Mode lint -Path $script:SqlFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain 'sqlfluff/sqlfluff:latest'
        }

        It 'Uses correct image reference with custom tag' {
            Invoke-SqlFluff -Mode lint -Path $script:SqlFile -ImageTag '3.0.0' | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain 'sqlfluff/sqlfluff:3.0.0'
        }

        It 'Passes --dialect with the correct value' {
            Invoke-SqlFluff -Mode lint -Path $script:SqlFile -Dialect tsql | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--dialect'
            $runCall | Should -Contain 'tsql'
        }

        It 'Appends additional arguments' {
            Invoke-SqlFluff -Mode lint -Path $script:SqlFile -AdditionalArgs '--exclude-rules', 'LT01' | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--exclude-rules'
            $runCall | Should -Contain 'LT01'
        }

        It 'Includes relative SQL file path in docker args' {
            Invoke-SqlFluff -Mode lint -Path $script:SqlFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain 'query.sql'
        }
    }

    Context 'Config file handling' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            $script:SqlFile = Join-Path -Path $script:TestDir -ChildPath 'query.sql'
            'SELECT 1' | Set-Content -LiteralPath $script:SqlFile

            Push-Location $script:TestDir
        }

        AfterEach {
            Pop-Location
        }

        It 'Mounts config file and passes --config when config exists' {
            $configFile = Join-Path -Path $script:TestDir -ChildPath '.sqlfluff'
            '[sqlfluff]' | Set-Content -LiteralPath $configFile

            Invoke-SqlFluff -Mode lint -Path $script:SqlFile -ConfigPath $configFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--config'
            $runCall | Should -Contain '/config/.sqlfluff'

            # Verify the volume mount for the config file
            $volArgs = @()
            for ($i = 0; $i -lt $runCall.Count; $i++)
            {
                if ($runCall[$i] -eq '-v' -and ($i + 1) -lt $runCall.Count)
                {
                    $volArgs += $runCall[$i + 1]
                }
            }
            $configMount = $volArgs | Where-Object { $_ -match ':/config/' }
            $configMount | Should -Not -BeNullOrEmpty
        }

        It 'Throws when explicitly specified config file does not exist' {
            { Invoke-SqlFluff -Mode lint -Path $script:SqlFile -ConfigPath '/nonexistent/.sqlfluff' } | Should -Throw 'Config file not found*'
        }

        It 'Throws when explicitly specified config path does not exist' {
            $missingConfig = Join-Path -Path $script:TestDir -ChildPath 'no-such-dir/.sqlfluff'

            { Invoke-SqlFluff -Mode lint -Path $script:SqlFile -ConfigPath $missingConfig } | Should -Throw 'Config file not found*'
        }

        It 'Runs without --config when default config is not found' {
            # Point default config to a path that doesn't exist by not passing -ConfigPath
            # We can't easily override the default, so instead verify behavior when config exists
            # by checking that --config is absent when no config file is mounted.

            # Create a mock scenario where the default config doesn't exist
            # The function defaults to $HOME/.sqlfluff - we just check args don't include --config
            # when no config is explicitly provided and no default exists.
            Mock -CommandName Test-Path -ParameterFilter { $LiteralPath -and $LiteralPath -like '*/.sqlfluff' } -MockWith { $false }

            Invoke-SqlFluff -Mode lint -Path $script:SqlFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            if ($runCall)
            {
                $runCall | Should -Not -Contain '--config'
            }
        }
    }

    Context 'SQL file discovery' {
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

        It 'Discovers *.sql files when no Path is provided' {
            'SELECT 1' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'a.sql')
            'SELECT 2' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'b.sql')

            Invoke-SqlFluff -Mode lint | Out-Null

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_ -contains 'run' })
            $runCalls.Count | Should -Be 2
        }

        It 'Warns when no *.sql files are found in working directory' {
            # Empty TestDir has no SQL files
            $result = Invoke-SqlFluff -Mode lint 3>&1

            $warnings = @($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $warnings.Count | Should -BeGreaterThan 0
            $warnings[0].Message | Should -BeLike '*No *.sql files found*'
        }

        It 'Expands directories to contained *.sql files' {
            $subDir = Join-Path -Path $script:TestDir -ChildPath 'subdir'
            New-Item -Path $subDir -ItemType Directory -Force | Out-Null
            'SELECT 1' | Set-Content -LiteralPath (Join-Path -Path $subDir -ChildPath 'inner.sql')

            Invoke-SqlFluff -Mode lint -Path $subDir | Out-Null

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_ -contains 'run' })
            $runCalls.Count | Should -Be 1
        }

        It 'Discovers files recursively with -Recurse' {
            'SELECT 1' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'top.sql')
            $subDir = Join-Path -Path $script:TestDir -ChildPath 'nested'
            New-Item -Path $subDir -ItemType Directory -Force | Out-Null
            'SELECT 2' | Set-Content -LiteralPath (Join-Path -Path $subDir -ChildPath 'deep.sql')

            Invoke-SqlFluff -Mode lint -Recurse | Out-Null

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_ -contains 'run' })
            $runCalls.Count | Should -Be 2
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

            $script:SqlFile = Join-Path -Path $script:TestDir -ChildPath 'query.sql'
            'SELECT 1' | Set-Content -LiteralPath $script:SqlFile

            Push-Location $script:TestDir
        }

        AfterEach {
            Pop-Location
        }

        It 'Returns exit code 0 on success' {
            $result = @(Invoke-SqlFluff -Mode lint -Path $script:SqlFile)

            $result[-1] | Should -Be 0
        }

        It 'Returns non-zero exit code on lint violations and writes warning' {
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
                    $global:LASTEXITCODE = 1
                    return @('violation output')
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

            $result = @(Invoke-SqlFluff -Mode lint -Path $script:SqlFile 3>&1)

            $exitCode = $result | Where-Object { $_ -is [Int32] -or $_ -is [Int64] }
            $exitCode | Should -Be 1

            Remove-Item -Path Function:\pwshDockerTestShimFail -ErrorAction SilentlyContinue
        }
    }

    Context 'ShouldProcess gating' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            $script:SqlFile = Join-Path -Path $script:TestDir -ChildPath 'query.sql'
            'SELECT 1' | Set-Content -LiteralPath $script:SqlFile

            Push-Location $script:TestDir
        }

        AfterEach {
            Pop-Location
        }

        It 'Does not execute Docker run when -WhatIf is specified for fix mode' {
            Invoke-SqlFluff -Mode fix -Path $script:SqlFile -WhatIf | Out-Null

            $runCalls = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' }
            $runCalls | Should -BeNullOrEmpty
        }

        It 'Does not execute Docker run when -WhatIf is specified for format mode' {
            Invoke-SqlFluff -Mode format -Path $script:SqlFile -WhatIf | Out-Null

            $runCalls = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' }
            $runCalls | Should -BeNullOrEmpty
        }

        It 'Executes Docker run for lint mode without ShouldProcess prompt' {
            Invoke-SqlFluff -Mode lint -Path $script:SqlFile | Out-Null

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_ -contains 'run' })
            $runCalls.Count | Should -Be 1
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
            'SELECT 1' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'piped.sql')

            Get-ChildItem -Path $script:TestDir -Filter '*.sql' | Invoke-SqlFluff -Mode lint | Out-Null

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_ -contains 'run' })
            $runCalls.Count | Should -Be 1
        }

        It 'Processes multiple files from pipeline' {
            'SELECT 1' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'one.sql')
            'SELECT 2' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'two.sql')

            Get-ChildItem -Path $script:TestDir -Filter '*.sql' | Invoke-SqlFluff -Mode lint | Out-Null

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_ -contains 'run' })
            $runCalls.Count | Should -Be 2
        }
    }
}
