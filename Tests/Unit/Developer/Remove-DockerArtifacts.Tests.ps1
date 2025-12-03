#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Remove-DockerArtifacts.

.DESCRIPTION
    Validates Docker cleanup wrapper logic: prerequisite checks, command selection, preview reporting,
    and safety switches including -WhatIf/-Confirm behavior.
#>

BeforeAll {
    # Load the function under test
    . "$PSScriptRoot/../../../Functions/Developer/Remove-DockerArtifacts.ps1"
}

Describe 'Remove-DockerArtifacts' {
    Context 'Prerequisite validation' {
        It 'Throws when Docker is not available' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith { $null }

            { Remove-DockerArtifacts -SkipPreview } | Should -Throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
        }
    }

    Context 'Prune command selection' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = 'docker'
                    Source = '/usr/local/bin/docker'
                }
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'ps' -and $args[1] -eq '-a' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith { @() }
        }

        It 'Prunes images, networks, and build cache without touching containers by default' {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 500MB' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 100MB' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 50MB' }

            $result = Remove-DockerArtifacts -SkipPreview

            $result.ContainersPruned | Should -BeFalse
            $result.VolumesPruned | Should -BeFalse
            $result.ImageMode | Should -Be 'AllUnused'
            $result.TotalSpaceFreed | Should -Be '650.00 MB'

            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'prune' } -Times 0
        }

        It 'Uses docker system prune when stopped containers are included' {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' -and $args -contains '--all' -and $args -contains '--volumes' } -MockWith { 'Total reclaimed space: 2GB' }

            $result = Remove-DockerArtifacts -IncludeStoppedContainers -IncludeVolumes -SkipPreview

            $result.ContainersPruned | Should -BeTrue
            $result.VolumesPruned | Should -BeTrue
            $result.TotalSpaceFreed | Should -Be '2.00 GB'

            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -Times 1
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -Times 0
        }

        It 'Respects -DanglingImagesOnly for targeted prunes' {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' -and -not ($args -contains '--all') } -MockWith { 'Total reclaimed space: 0B' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 0B' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' -and -not ($args -contains '--all') } -MockWith { 'Total reclaimed space: 0B' }

            $result = Remove-DockerArtifacts -DanglingImagesOnly -SkipPreview

            $result.ImageMode | Should -Be 'DanglingOnly'
            Assert-MockCalled -CommandName docker -ParameterFilter { $args -contains '--all' } -Times 0
        }

        It 'Honors -WhatIf and does not invoke Docker commands' {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'ps' -and $args[1] -eq '-a' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not prune images under -WhatIf' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not prune networks under -WhatIf' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not prune builder cache under -WhatIf' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -MockWith { throw 'Should not system prune under -WhatIf' }

            $result = Remove-DockerArtifacts -IncludeStoppedContainers -SkipPreview -WhatIf

            $result.TotalSpaceFreed | Should -Be '0 bytes'
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'prune' } -Times 0
        }
    }

    Context 'Preview reporting' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = 'docker'
                    Source = '/usr/local/bin/docker'
                }
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'ps' -and $args[1] -eq '-a' } -MockWith { @() }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith { @() }
        }

        It 'Reports reclaimable space and remaining usage with previews' {
            $beforeDf = @'
{"Type":"Images","TotalCount":5,"Active":2,"Size":"5GB","Reclaimable":"1.5GB (30%)"}
{"Type":"Containers","TotalCount":3,"Active":1,"Size":"1GB","Reclaimable":"400MB (40%)"}
{"Type":"Local Volumes","TotalCount":2,"Active":1,"Size":"500MB","Reclaimable":"100MB (20%)"}
{"Type":"Build Cache","TotalCount":3,"Active":0,"Size":"2GB","Reclaimable":"1GB (50%)"}
'@

            $afterDf = @'
{"Type":"Images","TotalCount":4,"Active":2,"Size":"3GB","Reclaimable":"500MB (16%)"}
{"Type":"Containers","TotalCount":2,"Active":1,"Size":"1GB","Reclaimable":"200MB (20%)"}
{"Type":"Local Volumes","TotalCount":2,"Active":1,"Size":"500MB","Reclaimable":"0B"}
{"Type":"Build Cache","TotalCount":1,"Active":0,"Size":"1GB","Reclaimable":"200MB (20%)"}
'@

            $script:dfCallCount = 0
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'df' } -MockWith {
                $script:dfCallCount++
                if ($script:dfCallCount -eq 1) { return $beforeDf } else { return $afterDf }
            }

            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 1.2GB' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 0B' }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'builder' -and $args[1] -eq 'prune' } -MockWith { 'Total reclaimed space: 0B' }

            $result = Remove-DockerArtifacts

            $result.PreviewReclaimable | Should -Be '2.99 GB'
            $result.ReclaimableRemaining | Should -Be '900.00 MB'
            $result.TotalSpaceFreed | Should -Be '3.00 GB'

            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'system' -and $args[1] -eq 'df' } -Times 2
        }

        It 'Estimates reclaimable space from unused images when preview is skipped' {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @'
{"Repository":"jonlabelle/network-tools","Tag":"latest","ID":"sha256:abcd1234efgh","Size":"400MB"}
'@
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'ps' -and $args[1] -eq '-a' } -MockWith { @() }

            $result = Remove-DockerArtifacts -SkipPreview -WhatIf

            $result.EstimatedReclaimable | Should -Be '400.00 MB'
            $result.TotalSpaceFreed | Should -Be '0 bytes'
        }
    }
}
