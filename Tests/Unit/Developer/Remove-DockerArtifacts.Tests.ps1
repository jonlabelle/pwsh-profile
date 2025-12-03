#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Remove-DockerArtifacts.

.DESCRIPTION
    Validates Docker cleanup wrapper logic: prerequisite checks, command selection, reclaimable estimation,
    and safety switches including -WhatIf/-Confirm behavior.
#>

BeforeAll {
    # Load the function under test
    . "$PSScriptRoot/../../../Functions/Developer/Remove-DockerArtifacts.ps1"

    # Check if Docker is available for testing
    $script:dockerAvailable = $null -ne (Get-Command -Name 'docker' -ErrorAction SilentlyContinue)
}

Describe 'Remove-DockerArtifacts' {
    Context 'Prerequisite validation' {
        It 'Throws when Docker is not available' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith { $null }

            { Remove-DockerArtifacts } | Should -Throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
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

            $result = Remove-DockerArtifacts

            $result.ContainersPruned | Should -BeFalse
            $result.VolumesPruned | Should -BeFalse
            $result.ImageMode | Should -Be 'AllUnused'
            $result.TotalSpaceFreed | Should -Be '650.00 MB'

            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'prune' } -Times 0
        }

        It 'Uses docker system prune when stopped containers are included' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' -and $args -contains '--all' -and $args -contains '--volumes' } -MockWith { 'Total reclaimed space: 2GB' }

            $result = Remove-DockerArtifacts -IncludeStoppedContainers -IncludeVolumes

            $result.ContainersPruned | Should -BeTrue
            $result.VolumesPruned | Should -BeTrue
            $result.TotalSpaceFreed | Should -Be '2.00 GB'

            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -Times 1
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -Times 0
        }

        It 'Respects -DanglingImagesOnly for targeted prunes' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' -and -not ($args -contains '--all') } -MockWith { 'Total reclaimed space: 0B' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 0B' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' -and -not ($args -contains '--all') } -MockWith { 'Total reclaimed space: 0B' }

            $result = Remove-DockerArtifacts -DanglingImagesOnly

            $result.ImageMode | Should -Be 'DanglingOnly'
            Assert-MockCalled -CommandName docker -ParameterFilter { $args -contains '--all' } -Times 0
        }

        It 'Honors -WhatIf and does not invoke Docker commands' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'ps' -and $args[1] -eq '-a' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not prune images under -WhatIf' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not prune networks under -WhatIf' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not prune builder cache under -WhatIf' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not system prune under -WhatIf' }

            $result = Remove-DockerArtifacts -IncludeStoppedContainers -WhatIf

            $result.TotalSpaceFreed | Should -Be '0 bytes'
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -Times 0
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

            $result = Remove-DockerArtifacts

            $result.TotalSpaceFreed | Should -Be '1.20 GB'
            $result.EstimatedReclaimable | Should -Be 'Not calculated (use -WhatIf to preview)'
        }

        It 'Estimates reclaimable space from unused images when no preview is available' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @'
{"Repository":"jonlabelle/network-tools","Tag":"latest","ID":"sha256:abcd1234efgh","Size":"400MB"}
'@
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'ps' -and $args[1] -eq '-a' } -MockWith { @() }

            $result = Remove-DockerArtifacts -WhatIf

            $result.EstimatedReclaimable | Should -Be '400.00 MB'
            $result.TotalSpaceFreed | Should -Be '0 bytes'
        }
    }
}
