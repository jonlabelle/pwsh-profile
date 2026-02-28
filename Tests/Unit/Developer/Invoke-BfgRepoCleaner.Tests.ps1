#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Invoke-BfgRepoCleaner.

.DESCRIPTION
    Validates Docker prerequisite checks, argument construction, volume mounting,
    and ShouldProcess gating for BFG Repo-Cleaner operations.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Invoke-BfgRepoCleaner.ps1"

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

Describe 'Invoke-BfgRepoCleaner' {
    BeforeEach {
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "bfg-tests-$(Get-Random)"
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

            { Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' } | Should -Throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
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

            { Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' } | Should -Throw '*daemon is not running*'

            Remove-Item -Path Function:\pwshDockerTestShimDaemonDown -ErrorAction SilentlyContinue
        }
    }

    Context 'Parameter validation' {
        It 'Rejects invalid StripBlobsBiggerThan format "<Value>"' -ForEach @(
            @{ Value = '100' }
            @{ Value = '100MB' }
            @{ Value = 'abc' }
            @{ Value = '10T' }
        ) {
            { Invoke-BfgRepoCleaner -StripBlobsBiggerThan $Value } | Should -Throw
        }

        It 'Accepts valid StripBlobsBiggerThan format "<Value>"' -ForEach @(
            @{ Value = '100M' }
            @{ Value = '1G' }
            @{ Value = '500K' }
            @{ Value = '1024B' }
        ) {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }

            # The param validation should pass (may still fail on daemon check, but not on param validation)
            { Invoke-BfgRepoCleaner -StripBlobsBiggerThan $Value -Confirm:$false } | Should -Not -Throw '*Cannot validate argument*'
        }

        It 'Rejects StripBiggestBlobs less than 1' {
            { Invoke-BfgRepoCleaner -StripBiggestBlobs 0 } | Should -Throw
        }

        It 'Rejects empty DeleteFiles' {
            { Invoke-BfgRepoCleaner -DeleteFiles '' } | Should -Throw
        }

        It 'Rejects empty DeleteFolders' {
            { Invoke-BfgRepoCleaner -DeleteFolders '' } | Should -Throw
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
        }

        It 'Passes --strip-blobs-bigger-than with the correct size' {
            Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' -Confirm:$false | Out-Null

            $script:DockerShimInvocations.Count | Should -BeGreaterThan 0
            # Find the 'run' invocation (skip the 'info' call)
            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--strip-blobs-bigger-than'
            $runCall | Should -Contain '100M'
        }

        It 'Passes --strip-biggest-blobs with the correct count' {
            Invoke-BfgRepoCleaner -StripBiggestBlobs 10 -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--strip-biggest-blobs'
            $runCall | Should -Contain '10'
        }

        It 'Passes --delete-files with the correct pattern' {
            Invoke-BfgRepoCleaner -DeleteFiles 'passwords.txt' -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--delete-files'
            $runCall | Should -Contain 'passwords.txt'
        }

        It 'Passes --delete-folders with the correct name' {
            Invoke-BfgRepoCleaner -DeleteFolders '.secrets' -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--delete-folders'
            $runCall | Should -Contain '.secrets'
        }

        It 'Passes --no-blob-protection when NoBlobProtection is specified' {
            Invoke-BfgRepoCleaner -StripBlobsBiggerThan '50M' -NoBlobProtection -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--no-blob-protection'
        }

        It 'Appends repository path as the last argument' {
            Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' -Repository 'my-repo.git' -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall[-1] | Should -Be 'my-repo.git'
        }

        It 'Appends additional arguments' {
            Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' -AdditionalArgs '--private' -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--private'
        }

        It 'Uses correct image reference with default tag' {
            Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain 'jonlabelle/bfg:latest'
        }

        It 'Uses correct image reference with custom tag' {
            Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' -ImageTag '1.15.0' -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain 'jonlabelle/bfg:1.15.0'
        }

        It 'Mounts the working directory as /work volume' {
            Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '-v'
            # Find the volume mount argument that contains :/work
            $volArg = $runCall | Where-Object { $_ -match ':/work$' }
            $volArg | Should -Not -BeNullOrEmpty
        }

        It 'Combines multiple BFG options in a single call' {
            Invoke-BfgRepoCleaner -DeleteFiles '*.env' -DeleteFolders 'node_modules' -Repository 'my-repo.git' -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--delete-files'
            $runCall | Should -Contain '*.env'
            $runCall | Should -Contain '--delete-folders'
            $runCall | Should -Contain 'node_modules'
            $runCall[-1] | Should -Be 'my-repo.git'
        }

        It 'Uses -i and --rm flags for docker run' {
            Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '-i'
            $runCall | Should -Contain '--rm'
        }
    }

    Context 'Replace text file handling' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }
        }

        It 'Throws when replace-text file does not exist' {
            { Invoke-BfgRepoCleaner -ReplaceText 'nonexistent-file.txt' -Confirm:$false } | Should -Throw 'Replace-text file not found*'
        }

        It 'Mounts replace-text file and passes --replace-text with container path' {
            $replaceFile = Join-Path -Path $script:TestDir -ChildPath 'replacements.txt'
            'PASSWORD1==>***REMOVED***' | Set-Content -LiteralPath $replaceFile

            Invoke-BfgRepoCleaner -ReplaceText $replaceFile -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--replace-text'
            $runCall | Should -Contain '/config/replacements.txt'

            # Verify the volume mount for the replace-text file
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
    }

    Context 'Exit code handling' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }
        }

        It 'Returns exit code 0 on success' {
            $result = @(Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' -Confirm:$false)

            # The last element is the exit code (preceding elements are Docker output)
            $result[-1] | Should -Be 0
        }

        It 'Returns non-zero exit code on failure and writes warning' {
            # Override the shim to return a non-zero exit code only for 'run', but pass 'info'
            function script:pwshDockerTestShimFail
            {
                param(
                    [Parameter(ValueFromRemainingArguments = $true)]
                    [Object[]]$RemainingArgs
                )

                $argsArray = @($RemainingArgs)
                $script:DockerShimInvocations += , $argsArray

                # Let the 'info' check pass, but fail the 'run' call
                if ($argsArray.Count -gt 0 -and $argsArray[0] -eq 'run')
                {
                    $global:LASTEXITCODE = 1
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

            $result = @(Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' -Confirm:$false 3>&1)

            # The result should contain a non-zero exit code and a warning
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
        }

        It 'Does not execute Docker when -WhatIf is specified' {
            Invoke-BfgRepoCleaner -StripBlobsBiggerThan '100M' -WhatIf | Out-Null

            # Only the 'info' call should have been made, not a 'run' call
            $runCalls = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' }
            $runCalls | Should -BeNullOrEmpty
        }
    }

    Context 'Help display' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:DockerCommandName
                    Source = '/usr/local/bin/docker'
                }
            }
        }

        It 'Passes --help via AdditionalArgs' {
            Invoke-BfgRepoCleaner -AdditionalArgs '--help' -Confirm:$false | Out-Null

            $runCall = $script:DockerShimInvocations | Where-Object { $_ -contains 'run' } | Select-Object -First 1
            $runCall | Should -Not -BeNullOrEmpty
            $runCall | Should -Contain '--help'
        }
    }
}
