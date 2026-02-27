#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Invoke-DockerAutoRun.

.DESCRIPTION
    Validates project detection, Dockerfile generation behavior, and docker build/run command
    orchestration with mocked Docker CLI calls.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Invoke-DockerAutoRun.ps1"

    # Deterministic shim used by Get-Command mocks so tests do not depend on Docker being installed.
    $script:DockerCommandName = 'pwshDockerTestShim'
    $script:DockerShimInvocations = @()
    $script:DockerShimOutputByCommand = @{}
    $script:DockerShimExitCodeByCommand = @{}

    function pwshDockerTestShim
    {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [Object[]]$RemainingArgs
        )

        $argsArray = @($RemainingArgs)
        $script:DockerShimInvocations += , $argsArray

        $commandName = ''
        if ($argsArray.Count -gt 0 -and -not [String]::IsNullOrWhiteSpace("$($argsArray[0])"))
        {
            $commandName = [String]$argsArray[0]
        }

        $exitCode = 0
        if ($script:DockerShimExitCodeByCommand.ContainsKey($commandName))
        {
            $exitCode = [Int]$script:DockerShimExitCodeByCommand[$commandName]
        }

        $global:LASTEXITCODE = $exitCode

        if ($script:DockerShimOutputByCommand.ContainsKey($commandName))
        {
            return @($script:DockerShimOutputByCommand[$commandName])
        }

        return @("shim output: $commandName")
    }
}

AfterAll {
    Remove-Item -Path Function:\pwshDockerTestShim -ErrorAction SilentlyContinue
}

Describe 'Invoke-DockerAutoRun' {
    BeforeEach {
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "docker-autorun-tests-$(Get-Random)"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        # Reset shim state for each test.
        $script:DockerShimInvocations = @()
        $script:DockerShimOutputByCommand = @{}
        $script:DockerShimExitCodeByCommand = @{}
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestDir)
        {
            Remove-Item -LiteralPath $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Prerequisite validation' {
        It 'Throws when Docker is missing for build/run operations' {
            '{"name":"app","scripts":{"start":"node index.js"}}' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'package.json')

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith { $null }

            { Invoke-DockerAutoRun -Path $script:TestDir } | Should -Throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
        }

        It 'Can generate a Dockerfile without Docker when -GenerateOnly is used' {
            '{"name":"app","scripts":{"start":"node index.js"}}' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'package.json')
            'console.log("ok")' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'index.js')

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith { $null }

            $result = Invoke-DockerAutoRun -Path $script:TestDir -GenerateOnly

            Test-Path -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'Dockerfile') | Should -BeTrue
            $result.BuildExecuted | Should -BeFalse
            $result.RunExecuted | Should -BeFalse
            $result.ProjectType | Should -Be 'Node'
        }
    }

    Context 'Dockerfile generation and detection' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }
        }

        It 'Generates a Node Dockerfile and runs build + run commands' {
            '{"name":"app","scripts":{"start":"node index.js"}}' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'package.json')
            'console.log("hello")' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'index.js')

            $script:DockerShimOutputByCommand['build'] = @('build success')
            $script:DockerShimOutputByCommand['run'] = @('container-id')

            $result = Invoke-DockerAutoRun -Path $script:TestDir -ImageName 'test-image' -ContainerName 'test-container'

            $dockerfilePath = Join-Path -Path $script:TestDir -ChildPath 'Dockerfile'
            $dockerfilePath | Should -Exist
            (Get-Content -LiteralPath $dockerfilePath -Raw) | Should -Match 'FROM node:lts-alpine'

            $result.ProjectType | Should -Be 'Node'
            $result.DockerfileGenerated | Should -BeTrue
            $result.Port | Should -Be 3000
            $result.BuildExecuted | Should -BeTrue
            $result.RunExecuted | Should -BeTrue

            $buildCalls = @($script:DockerShimInvocations | Where-Object { $_.Count -gt 0 -and $_[0] -eq 'build' })
            $runCalls = @($script:DockerShimInvocations | Where-Object { $_.Count -gt 0 -and $_[0] -eq 'run' })

            $buildCalls.Count | Should -Be 1
            $runCalls.Count | Should -Be 1
            $buildCalls[0] | Should -Contain '-t'
            $buildCalls[0] | Should -Contain 'test-image'
            $runCalls[0] | Should -Contain '--name'
            $runCalls[0] | Should -Contain 'test-container'
            $runCalls[0] | Should -Contain '3000:3000'
        }

        It 'Uses existing Dockerfile without overwriting by default' {
            @'
FROM alpine:3.20
EXPOSE 9090
CMD ["sh","-c","sleep 600"]
'@ | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'Dockerfile')

            $script:DockerShimOutputByCommand['build'] = @('build success')
            $script:DockerShimOutputByCommand['run'] = @('container-id')

            $result = Invoke-DockerAutoRun -Path $script:TestDir -ImageName 'existing-file-image'

            $result.ProjectType | Should -Be 'ExistingDockerfile'
            $result.DockerfileGenerated | Should -BeFalse
            $result.Port | Should -Be 9090

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_.Count -gt 0 -and $_[0] -eq 'run' })
            $runCalls.Count | Should -Be 1
            $runCalls[0] | Should -Contain '9090:9090'
        }

        It 'Overwrites existing Dockerfile when -ForceDockerfile is specified' {
            'FROM busybox' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'Dockerfile')
            '{"name":"app","scripts":{"start":"node index.js"}}' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'package.json')
            'console.log("hello")' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'index.js')

            $script:DockerShimOutputByCommand['build'] = @('build success')

            $result = Invoke-DockerAutoRun -Path $script:TestDir -ForceDockerfile -NoRun
            $dockerfileText = Get-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'Dockerfile') -Raw

            $result.DockerfileGenerated | Should -BeTrue
            $dockerfileText | Should -Match 'FROM node:lts-alpine'
        }
    }

    Context 'Run controls' {
        BeforeEach {
            '{"name":"app","scripts":{"start":"node index.js"}}' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'package.json')
            'console.log("hello")' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'index.js')

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }
            $script:DockerShimOutputByCommand['build'] = @('build success')
            $script:DockerShimOutputByCommand['run'] = @('container-id')
        }

        It 'Builds but does not run when -NoRun is specified' {
            $result = Invoke-DockerAutoRun -Path $script:TestDir -NoRun

            $result.BuildExecuted | Should -BeTrue
            $result.RunExecuted | Should -BeFalse

            $buildCalls = @($script:DockerShimInvocations | Where-Object { $_.Count -gt 0 -and $_[0] -eq 'build' })
            $runCalls = @($script:DockerShimInvocations | Where-Object { $_.Count -gt 0 -and $_[0] -eq 'run' })
            $buildCalls.Count | Should -Be 1
            $runCalls.Count | Should -Be 0
        }

        It 'Throws when project type cannot be auto-detected' {
            Remove-Item -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'package.json') -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'index.js') -Force -ErrorAction SilentlyContinue

            { Invoke-DockerAutoRun -Path $script:TestDir -GenerateOnly } | Should -Throw '*Unable to auto-detect project type*'
        }
    }

    Context '.dockerignore generation' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }
            $script:DockerShimOutputByCommand['build'] = @('build success')
        }

        It 'Generates .dockerignore alongside Dockerfile for Node projects' {
            '{"name":"app","scripts":{"start":"node index.js"}}' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'package.json')

            $result = Invoke-DockerAutoRun -Path $script:TestDir -GenerateOnly

            $ignorePath = Join-Path -Path $script:TestDir -ChildPath '.dockerignore'
            $ignorePath | Should -Exist
            $result.DockerIgnoreGenerated | Should -BeTrue

            $ignoreContent = Get-Content -LiteralPath $ignorePath -Raw
            $ignoreContent | Should -Match 'node_modules'
            $ignoreContent | Should -Match '\.git'
        }

        It 'Generates project-specific .dockerignore for Python projects' {
            'flask' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'requirements.txt')
            'from flask import Flask' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'app.py')

            Invoke-DockerAutoRun -Path $script:TestDir -GenerateOnly

            $ignorePath = Join-Path -Path $script:TestDir -ChildPath '.dockerignore'
            $ignorePath | Should -Exist

            $ignoreContent = Get-Content -LiteralPath $ignorePath -Raw
            $ignoreContent | Should -Match '__pycache__'
            $ignoreContent | Should -Match '\.venv'
        }

        It 'Does not overwrite existing .dockerignore' {
            '{"name":"app","scripts":{"start":"node index.js"}}' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'package.json')
            $ignorePath = Join-Path -Path $script:TestDir -ChildPath '.dockerignore'
            'custom-ignore' | Set-Content -LiteralPath $ignorePath

            $result = Invoke-DockerAutoRun -Path $script:TestDir -GenerateOnly

            $result.DockerIgnoreGenerated | Should -BeFalse
            (Get-Content -LiteralPath $ignorePath -Raw).Trim() | Should -Be 'custom-ignore'
        }

        It 'Skips .dockerignore generation when -NoDockerIgnore is specified' {
            '{"name":"app","scripts":{"start":"node index.js"}}' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'package.json')

            $result = Invoke-DockerAutoRun -Path $script:TestDir -GenerateOnly -NoDockerIgnore

            $ignorePath = Join-Path -Path $script:TestDir -ChildPath '.dockerignore'
            $ignorePath | Should -Not -Exist
            $result.DockerIgnoreGenerated | Should -BeFalse
        }
    }

    Context 'Interactive, EnvFile, and Network parameters' {
        BeforeEach {
            '{"name":"app","scripts":{"start":"node index.js"}}' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'package.json')
            'console.log("hello")' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'index.js')

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }
            $script:DockerShimOutputByCommand['build'] = @('build success')
            $script:DockerShimOutputByCommand['run'] = @('container-id')
            $script:DockerShimOutputByCommand['ps'] = @('')
        }

        It 'Adds -i and -t flags when -Interactive is specified' {
            $result = Invoke-DockerAutoRun -Path $script:TestDir -Interactive -ImageName 'test-app'

            $result.Interactive | Should -BeTrue
            $runCalls = @($script:DockerShimInvocations | Where-Object { $_.Count -gt 0 -and $_[0] -eq 'run' })
            $runCalls.Count | Should -Be 1
            $runCalls[0] | Should -Contain '-i'
            $runCalls[0] | Should -Contain '-t'
        }

        It 'Throws when -Interactive and -Detached are used together' {
            { Invoke-DockerAutoRun -Path $script:TestDir -Interactive -Detached } | Should -Throw '*cannot be used together*'
        }

        It 'Passes --env-file when -EnvFile is specified' {
            $envFilePath = Join-Path -Path $script:TestDir -ChildPath '.env.test'
            'MY_VAR=hello' | Set-Content -LiteralPath $envFilePath

            Invoke-DockerAutoRun -Path $script:TestDir -EnvFile $envFilePath -ImageName 'test-app'

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_.Count -gt 0 -and $_[0] -eq 'run' })
            $runCalls.Count | Should -Be 1
            $runCalls[0] | Should -Contain '--env-file'
            $runCalls[0] | Should -Contain $envFilePath
        }

        It 'Passes --network when -Network is specified' {
            Invoke-DockerAutoRun -Path $script:TestDir -Network 'my-bridge' -ImageName 'test-app'

            $runCalls = @($script:DockerShimInvocations | Where-Object { $_.Count -gt 0 -and $_[0] -eq 'run' })
            $runCalls.Count | Should -Be 1
            $runCalls[0] | Should -Contain '--network'
            $runCalls[0] | Should -Contain 'my-bridge'
        }
    }

    Context 'Existing container conflict handling' {
        BeforeEach {
            '{"name":"app","scripts":{"start":"node index.js"}}' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'package.json')
            'console.log("hello")' | Set-Content -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'index.js')

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }
            $script:DockerShimOutputByCommand['build'] = @('build success')
            $script:DockerShimOutputByCommand['run'] = @('container-id')
        }

        It 'Invokes docker ps to check for existing containers before run' {
            $script:DockerShimOutputByCommand['ps'] = @('')

            Invoke-DockerAutoRun -Path $script:TestDir -ImageName 'test-app' -ContainerName 'test-ctr' | Out-Null

            $psCalls = @($script:DockerShimInvocations | Where-Object { $_.Count -gt 0 -and $_[0] -eq 'ps' })
            $psCalls.Count | Should -Be 1
        }

        It 'Removes existing container when one is found with the same name' {
            $script:DockerShimOutputByCommand['ps'] = @('abc123')
            $script:DockerShimOutputByCommand['rm'] = @('abc123')

            Invoke-DockerAutoRun -Path $script:TestDir -ImageName 'test-app' -ContainerName 'test-ctr' | Out-Null

            $rmCalls = @($script:DockerShimInvocations | Where-Object { $_.Count -gt 0 -and $_[0] -eq 'rm' })
            $rmCalls.Count | Should -Be 1
            $rmCalls[0] | Should -Contain '-f'
            $rmCalls[0] | Should -Contain 'test-ctr'
        }
    }
}
