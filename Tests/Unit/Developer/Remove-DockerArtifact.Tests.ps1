#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Remove-DockerArtifact.

.DESCRIPTION
    Validates Docker cleanup wrapper logic: prerequisite checks, command selection, reclaimable estimation,
    and safety switches including -WhatIf/-Confirm behavior.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function under test
    . "$PSScriptRoot/../../../Functions/Developer/Remove-DockerArtifact.ps1"

    # Check if Docker is available for testing
    $script:dockerAvailable = $null -ne (Get-Command -Name 'docker' -ErrorAction SilentlyContinue)
}

Describe 'Remove-DockerArtifact' {
    Context 'Prerequisite validation' {
        It 'Throws when Docker is not available' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith { $null }

            { Remove-DockerArtifact } | Should-Throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
        }
    }

    Context 'Prune command selection' {
        BeforeEach {
            if (-not $script:dockerAvailable)
            {
                Set-ItResult -Skipped -Because 'Docker is not installed'
                return
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = 'docker'
                    Source = '/usr/local/bin/docker'
                }
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'ps' -and $args[1] -eq '-a' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith { @() }
        }

        It 'Prunes images, networks, and build cache without touching containers by default' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 500MB' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 100MB' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 50MB' }

            $result = Remove-DockerArtifact

            $result.ContainersPruned | Should-BeFalsy
            $result.VolumesPruned | Should-BeFalsy
            $result.BuildHistoryPruned | Should-BeFalsy
            $result.ImageMode | Should-Be 'AllUnused'
            $result.TotalSpaceFreed | Should-Be '650.00 MB'

            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'history' -and $args[2] -eq 'rm' } -Times 0 -Exactly
        }

        It 'Uses docker system prune when stopped containers are included' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' -and $args -contains '--all' -and $args -contains '--volumes' } -MockWith { 'Total reclaimed space: 2GB' }

            $result = Remove-DockerArtifact -IncludeStoppedContainers -IncludeVolumes

            $result.ContainersPruned | Should-BeTruthy
            $result.VolumesPruned | Should-BeTruthy
            $result.BuildHistoryPruned | Should-BeFalsy
            $result.TotalSpaceFreed | Should-Be '2.00 GB'

            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -Times 1
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'history' -and $args[2] -eq 'rm' } -Times 0 -Exactly
        }

        It 'Uses all cleanup categories when -All is specified' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' -and $args -contains '--all' -and $args -contains '--volumes' } -MockWith { 'Total reclaimed space: 2GB' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'history' -and $args[2] -eq 'rm' -and $args -contains '--all' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'prune' -and $args -contains '--all' } -MockWith { 'Total: 0B' }

            $result = Remove-DockerArtifact -All

            $result.ContainersPruned | Should-BeTruthy
            $result.VolumesPruned | Should-BeTruthy
            $result.BuildHistoryPruned | Should-BeTruthy
            $result.TotalSpaceFreed | Should-Be '2.00 GB'

            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -Times 1
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'history' -and $args[2] -eq 'rm' } -Times 1
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'prune' } -Times 1
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'prune' } -Times 0 -Exactly
        }

        It 'Throws when -All and -DanglingImagesOnly are used together' -Skip:(-not $script:dockerAvailable) {
            { Remove-DockerArtifact -All -DanglingImagesOnly } | Should-Throw 'The -All and -DanglingImagesOnly parameters cannot be used together.'
        }

        It 'Prunes Docker Desktop build history when requested' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 0B' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 0B' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 0B' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'history' -and $args[2] -eq 'rm' -and $args -contains '--all' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'prune' -and $args -contains '--all' } -MockWith { 'Total: 200MB' }

            $result = Remove-DockerArtifact -IncludeBuildHistory

            $result.BuildHistoryPruned | Should-BeTruthy
            $result.TotalSpaceFreed | Should-Be '200.00 MB'
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'history' -and $args[2] -eq 'rm' -and $args -contains '--all' } -Times 1
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'prune' -and $args -contains '--all' } -Times 1
        }

        It 'Respects -DanglingImagesOnly for targeted prunes' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' -and -not ($args -contains '--all') } -MockWith { 'Total reclaimed space: 0B' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 0B' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' -and -not ($args -contains '--all') } -MockWith { 'Total reclaimed space: 0B' }

            $result = Remove-DockerArtifact -DanglingImagesOnly

            $result.ImageMode | Should-Be 'DanglingOnly'
            Should-Invoke -CommandName docker -ParameterFilter { $args -contains '--all' } -Times 0 -Exactly
        }

        It 'Honors -WhatIf and does not invoke Docker commands' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'ps' -and $args[1] -eq '-a' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not prune images under -WhatIf' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not prune networks under -WhatIf' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not prune builder cache under -WhatIf' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'history' -and $args[2] -eq 'rm' } -MockWith { throw 'Should not remove build history under -WhatIf' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not prune build history under -WhatIf' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not system prune under -WhatIf' }

            $result = Remove-DockerArtifact -IncludeStoppedContainers -IncludeBuildHistory -WhatIf

            $result.TotalSpaceFreed | Should-Be '0 bytes'
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'history' -and $args[2] -eq 'rm' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'buildx' -and $args[1] -eq 'prune' } -Times 0 -Exactly
            Should-Invoke -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -Times 0 -Exactly
        }
    }

    Context 'Reclaimable estimation' {
        BeforeEach {
            if (-not $script:dockerAvailable)
            {
                Set-ItResult -Skipped -Because 'Docker is not installed'
                return
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = 'docker'
                    Source = '/usr/local/bin/docker'
                }
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'ps' -and $args[1] -eq '-a' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith { @() }
        }

        It 'Aggregates reclaimed space from prune commands' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 1.2GB' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 0B' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 0B' }

            $result = Remove-DockerArtifact

            $result.TotalSpaceFreed | Should-Be '1.20 GB'
            $result.EstimatedReclaimable | Should-Be 'Not calculated (use -WhatIf to preview)'
        }

        It 'Estimates reclaimable space from unused images when no preview is available' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @'
{"Repository":"jonlabelle/network-tools","Tag":"latest","ID":"sha256:abcd1234efgh","Size":"400MB"}
'@
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'ps' -and $args[1] -eq '-a' } -MockWith { @() }

            $result = Remove-DockerArtifact -WhatIf

            $result.EstimatedReclaimable | Should-Be '400.00 MB'
            $result.TotalSpaceFreed | Should-Be '0 bytes'
        }
    }

    Context 'Summary theme' {
        It 'Uses warning color only for WhatIf status and keeps the result object ANSI-free' {
            function docker
            {
                @()
            }

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = 'docker'
                    Source = 'test-docker'
                }
            }
            Mock -CommandName docker -MockWith { @() }
            $global:LASTEXITCODE = 0

            $script:ThemeHostOutput = [System.Collections.Generic.List[String]]::new()
            Mock -CommandName Write-Host -MockWith {
                if ($null -ne $Object)
                {
                    $script:ThemeHostOutput.Add([String]$Object)
                }
            }

            $result = Remove-DockerArtifact -WhatIf
            $escapeCharacter = [String][Char]27
            $ansiPattern = "$escapeCharacter\[[0-9;]*m"
            $rawOutput = $script:ThemeHostOutput -join ''
            $codes = @([Regex]::Matches($rawOutput, $ansiPattern).Value | Sort-Object -Unique)

            $codes.Count | Should-Be 4
            $codes | Should-ContainCollection "$escapeCharacter[38;5;37m"
            $codes | Should-ContainCollection "$escapeCharacter[38;5;244m"
            $codes | Should-ContainCollection "$escapeCharacter[33m"
            $codes | Should-ContainCollection "$escapeCharacter[0m"
            $codes | Should-NotContainCollection "$escapeCharacter[91m"
            ($result | ConvertTo-Json -Depth 5) | Should-NotMatchString ([Regex]::Escape($escapeCharacter))
        }
    }
}
