#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Invoke-Magika.

.DESCRIPTION
    Validates command selection (local Magika vs Docker fallback), Docker
    prerequisite checks, argument construction, path handling, pipeline behavior,
    and exit code behavior.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Invoke-Magika.ps1"

    # Deterministic shim used by Get-Command mocks so tests do not depend on Docker being installed.
    $script:DockerCommandName = 'pwshDockerTestShim'
    $script:DockerShimInvocations = @()
    $script:DockerShimRejectsPredictionMode = $false
    $script:MagikaCommandName = 'pwshMagikaTestShim'
    $script:MagikaShimInvocations = @()
    $script:MagikaShimRejectsPredictionMode = $false

    function pwshDockerTestShim
    {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [Object[]]$RemainingArgs
        )

        $argsArray = @($RemainingArgs)
        $script:DockerShimInvocations += , $argsArray

        if ($script:DockerShimRejectsPredictionMode -and $argsArray.Count -gt 0 -and $argsArray[0] -eq 'run' -and ($argsArray -contains '--prediction-mode'))
        {
            $global:LASTEXITCODE = 2
            return @("error: unexpected argument '--prediction-mode' found")
        }

        $global:LASTEXITCODE = 0
        return @('shim output')
    }

    function pwshMagikaTestShim
    {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [Object[]]$RemainingArgs
        )

        $argsArray = @($RemainingArgs)
        $script:MagikaShimInvocations += , $argsArray

        if ($script:MagikaShimRejectsPredictionMode -and ($argsArray -contains '--prediction-mode'))
        {
            $global:LASTEXITCODE = 2
            return @("error: unexpected argument '--prediction-mode' found")
        }

        $global:LASTEXITCODE = 0
        return @('shim output')
    }
}

AfterAll {
    Remove-Item -Path Function:\pwshDockerTestShim -ErrorAction SilentlyContinue
    Remove-Item -Path Function:\pwshMagikaTestShim -ErrorAction SilentlyContinue
}

Describe 'Invoke-Magika' {
    BeforeEach {
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "magika-tests-$(Get-Random)"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        # Reset shim state for each test
        $script:DockerShimInvocations = @()
        $script:MagikaShimInvocations = @()
        $script:DockerShimRejectsPredictionMode = $false
        $script:MagikaShimRejectsPredictionMode = $false

        # Default to Docker fallback mode for deterministic tests unless a test
        # explicitly mocks a local Magika command.
        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'magika' } -MockWith { $null }
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

    Context 'Command selection' {
        BeforeEach {
            $script:SampleFile = Join-Path -Path $script:TestDir -ChildPath 'sample.txt'
            'sample' | Set-Content -LiteralPath $script:SampleFile
            Push-Location $script:TestDir
        }

        AfterEach {
            Pop-Location
        }

        It 'Prefers local Magika when available' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'magika' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:MagikaCommandName
                    Source = '/usr/local/bin/magika'
                }
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            Invoke-Magika -Path $script:SampleFile | Out-Null

            $script:MagikaShimInvocations.Count | Should -Be 1
            $script:DockerShimInvocations.Count | Should -Be 0
        }

        It 'Skips Docker prerequisite checks when local Magika is available' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'magika' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:MagikaCommandName
                    Source = '/usr/local/bin/magika'
                }
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith { $null }

            { Invoke-Magika -Path $script:SampleFile } | Should -Not -Throw
            Assert-MockCalled -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -Times 0 -Exactly
        }

        It 'Falls back to Docker when local Magika is not available' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            Invoke-Magika -Path $script:SampleFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $script:MagikaShimInvocations.Count | Should -Be 0
        }

        It 'Binds positional argument to Path' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            Invoke-Magika 'sample.txt' | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain 'sample.txt'
        }

        It 'Uses Docker when Runtime is explicitly set to Docker' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'magika' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:MagikaCommandName
                    Source = '/usr/local/bin/magika'
                }
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            Invoke-Magika -Path $script:SampleFile -Runtime Docker | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $script:MagikaShimInvocations.Count | Should -Be 0
        }

        It 'Uses local Magika when Runtime is explicitly set to Local' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'magika' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:MagikaCommandName
                    Source = '/usr/local/bin/magika'
                }
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith { $null }

            Invoke-Magika -Path $script:SampleFile -Runtime Local | Out-Null

            $script:MagikaShimInvocations.Count | Should -Be 1
            $script:DockerShimInvocations.Count | Should -Be 0
        }

        It 'Passes --recursive to local Magika when Recurse is set' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'magika' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:MagikaCommandName
                    Source = '/usr/local/bin/magika'
                }
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            Invoke-Magika -Path $script:SampleFile -Recurse | Out-Null

            $script:MagikaShimInvocations.Count | Should -Be 1
            $script:MagikaShimInvocations[0] | Should -Contain '--recursive'
            $script:DockerShimInvocations.Count | Should -Be 0
        }

        It 'Passes translated --prediction-mode to local Magika when PredictionMode is set' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'magika' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:MagikaCommandName
                    Source = '/usr/local/bin/magika'
                }
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            Invoke-Magika -Path $script:SampleFile -PredictionMode High | Out-Null

            $script:MagikaShimInvocations.Count | Should -Be 1
            $script:MagikaShimInvocations[0] | Should -Contain '--prediction-mode'
            $script:MagikaShimInvocations[0] | Should -Contain 'HIGH_CONFIDENCE'
            $script:DockerShimInvocations.Count | Should -Be 0
        }

        It 'Passes translated default --prediction-mode to local Magika when PredictionMode is omitted' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'magika' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:MagikaCommandName
                    Source = '/usr/local/bin/magika'
                }
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            Invoke-Magika -Path $script:SampleFile | Out-Null

            $script:MagikaShimInvocations.Count | Should -Be 1
            $script:MagikaShimInvocations[0] | Should -Contain '--prediction-mode'
            $script:MagikaShimInvocations[0] | Should -Contain 'HIGH_CONFIDENCE'
            $script:DockerShimInvocations.Count | Should -Be 0
        }

        It 'Retries without --prediction-mode when local Magika runtime does not support it' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'magika' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:MagikaCommandName
                    Source = '/usr/local/bin/magika'
                }
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            $script:MagikaShimRejectsPredictionMode = $true

            $result = @(Invoke-Magika -Path $script:SampleFile)
            $result[-1] | Should -Be 0

            $script:MagikaShimInvocations.Count | Should -Be 2
            $script:MagikaShimInvocations[0] | Should -Contain '--prediction-mode'
            $script:MagikaShimInvocations[1] | Should -Not -Contain '--prediction-mode'
            $script:DockerShimInvocations.Count | Should -Be 0
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

        It 'Rejects invalid Runtime' {
            { Invoke-Magika -Path 'README.md' -Runtime 'Container' } | Should -Throw
        }

        It 'Rejects invalid PredictionMode' {
            { Invoke-Magika -Path 'README.md' -PredictionMode 'BEST_GUESS' } | Should -Throw
        }
    }

    Context 'Explicit runtime prerequisites' {
        It 'Throws when Runtime is Local and local Magika is not installed' {
            { Invoke-Magika -Path 'README.md' -Runtime Local } | Should -Throw 'Magika is not installed or not available in PATH. Install Magika or use -Runtime Docker.'
        }

        It 'Throws when Runtime is Docker and Docker is not installed even if local Magika is available' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'magika' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:MagikaCommandName
                    Source = '/usr/local/bin/magika'
                }
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith { $null }

            { Invoke-Magika -Path 'README.md' -Runtime Docker } | Should -Throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
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

        It 'Uses image entrypoint by default (no --entrypoint override)' {
            Invoke-Magika -Path $script:SampleFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Not -Contain '--entrypoint'
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

        It 'Appends --recursive when Recurse is set' {
            Invoke-Magika -Path $script:SampleFile -Recurse | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--recursive'
        }

        It 'Appends translated --prediction-mode when PredictionMode is set' {
            Invoke-Magika -Path $script:SampleFile -PredictionMode Medium | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--prediction-mode'
            $runCall | Should -Contain 'MEDIUM_CONFIDENCE'
        }

        It 'Appends translated default --prediction-mode when PredictionMode is omitted' {
            Invoke-Magika -Path $script:SampleFile | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--prediction-mode'
            $runCall | Should -Contain 'HIGH_CONFIDENCE'
        }

        It 'Retries without --prediction-mode when Docker runtime does not support it' {
            $script:DockerShimRejectsPredictionMode = $true

            $result = @(Invoke-Magika -Path $script:SampleFile)
            $result[-1] | Should -Be 0

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_ -contains 'run' })
            $runCalls.Count | Should -Be 2
            $runCalls[0] | Should -Contain '--prediction-mode'
            $runCalls[1] | Should -Not -Contain '--prediction-mode'
        }

        It 'Warns when explicit PredictionMode is unsupported by Docker runtime' {
            $script:DockerShimRejectsPredictionMode = $true

            $result = @(Invoke-Magika -Path $script:SampleFile -PredictionMode Medium 3>&1)
            $exitCode = $result | Where-Object { $_ -is [Int32] -or $_ -is [Int64] }
            $exitCode | Should -Be 0

            $warnings = @($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $warnings.Count | Should -BeGreaterThan 0
            $warnings[0].Message | Should -BeLike '*does not support*--prediction-mode*'
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

    Context 'Path scope validation (Docker fallback)' {
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

    Context 'Path scope validation (local Magika)' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'magika' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:MagikaCommandName
                    Source = '/usr/local/bin/magika'
                }
            }
        }

        It 'Allows paths outside the current working directory' {
            $outsideDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "magika-outside-local-$(Get-Random)"
            $outsideFile = Join-Path -Path $outsideDir -ChildPath 'outside.txt'

            New-Item -Path $outsideDir -ItemType Directory -Force | Out-Null
            'outside' | Set-Content -LiteralPath $outsideFile

            try
            {
                { Invoke-Magika -Path $outsideFile } | Should -Not -Throw

                $script:MagikaShimInvocations.Count | Should -Be 1
                $script:MagikaShimInvocations[0] | Should -Contain $outsideFile
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
