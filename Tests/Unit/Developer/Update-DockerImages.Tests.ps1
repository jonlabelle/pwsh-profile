#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Update-DockerImages.

.DESCRIPTION
    Validates Docker image update logic: prerequisite checks, image filtering, deduplication,
    pull behavior, and result reporting.
#>

BeforeAll {
    # Load the function under test
    . "$PSScriptRoot/../../../Functions/Developer/Update-DockerImages.ps1"

    # Check if Docker is available for testing
    $script:dockerAvailable = $null -ne (Get-Command -Name 'docker' -ErrorAction SilentlyContinue)
}

Describe 'Update-DockerImages' {
    Context 'Prerequisite validation' {
        It 'Throws when Docker is not available' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith { $null }

            { Update-DockerImages } | Should -Throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
        }
    }

    Context 'Image listing and filtering' {
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
        }

        It 'Skips images with <none> repository' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @(
                    '{"Repository":"<none>","Tag":"<none>","ID":"sha256:abc123","Size":"100MB"}'
                    '{"Repository":"nginx","Tag":"latest","ID":"sha256:def456","Size":"200MB"}'
                )
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith { 'Status: Image is up to date for nginx:latest' }

            $result = Update-DockerImages

            $result.Eligible | Should -Be 1
            $result.Results.Count | Should -Be 1
            $result.Results[0].Image | Should -Be 'nginx:latest'
        }

        It 'Skips images with <none> tag' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @(
                    '{"Repository":"myapp","Tag":"<none>","ID":"sha256:abc123","Size":"100MB"}'
                    '{"Repository":"alpine","Tag":"3.18","ID":"sha256:def456","Size":"50MB"}'
                )
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith { 'Status: Image is up to date for alpine:3.18' }

            $result = Update-DockerImages

            $result.Eligible | Should -Be 1
            $result.Results[0].Image | Should -Be 'alpine:3.18'
        }

        It 'Deduplicates images with the same Repository:Tag' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @(
                    '{"Repository":"nginx","Tag":"latest","ID":"sha256:abc123","Size":"200MB"}'
                    '{"Repository":"nginx","Tag":"latest","ID":"sha256:abc123","Size":"200MB"}'
                    '{"Repository":"alpine","Tag":"latest","ID":"sha256:def456","Size":"50MB"}'
                )
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith { 'Status: Image is up to date' }

            $result = Update-DockerImages

            $result.Eligible | Should -Be 2
        }

        It 'Applies -Filter to select matching images only' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @(
                    '{"Repository":"nginx","Tag":"latest","ID":"sha256:abc123","Size":"200MB"}'
                    '{"Repository":"mcr.microsoft.com/dotnet/sdk","Tag":"8.0","ID":"sha256:def456","Size":"800MB"}'
                    '{"Repository":"mcr.microsoft.com/dotnet/runtime","Tag":"8.0","ID":"sha256:ghi789","Size":"200MB"}'
                )
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith { 'Status: Image is up to date' }

            $result = Update-DockerImages -Filter 'mcr.microsoft.com/*'

            $result.Eligible | Should -Be 2
            $result.Results | ForEach-Object { $_.Image | Should -BeLike 'mcr.microsoft.com/*' }
        }

        It 'Applies -ExcludeFilter to skip matching images' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @(
                    '{"Repository":"nginx","Tag":"latest","ID":"sha256:abc123","Size":"200MB"}'
                    '{"Repository":"myapp-dev","Tag":"latest","ID":"sha256:def456","Size":"100MB"}'
                    '{"Repository":"alpine","Tag":"latest","ID":"sha256:ghi789","Size":"50MB"}'
                )
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith { 'Status: Image is up to date' }

            $result = Update-DockerImages -ExcludeFilter '*dev*'

            $result.Eligible | Should -Be 2
            $result.Results | ForEach-Object { $_.Image | Should -Not -BeLike '*dev*' }
        }
    }

    Context 'Pull behavior and result reporting' {
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
        }

        It 'Reports success for a successful pull' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @('{"Repository":"nginx","Tag":"latest","ID":"sha256:abc123","Size":"200MB"}')
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith {
                'latest: Pulling from library/nginx'
                'Digest: sha256:abc123'
                'Status: Downloaded newer image for nginx:latest'
            }

            $result = Update-DockerImages

            $result.Updated | Should -Be 1
            $result.Failed | Should -Be 0
            $result.Results[0].Status | Should -Be 'Success'
            $result.Results[0].Message | Should -Be 'Updated'
        }

        It 'Detects already up-to-date images' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @('{"Repository":"nginx","Tag":"latest","ID":"sha256:abc123","Size":"200MB"}')
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith {
                'latest: Pulling from library/nginx'
                'Digest: sha256:abc123'
                'Status: Image is up to date for nginx:latest'
            }

            $result = Update-DockerImages

            $result.Updated | Should -Be 1
            $result.Results[0].Status | Should -Be 'Success'
            $result.Results[0].Message | Should -Be 'Already up to date'
        }

        It 'Reports failure when pull fails' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @('{"Repository":"nonexistent/image","Tag":"latest","ID":"sha256:abc123","Size":"100MB"}')
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith {
                $global:LASTEXITCODE = 1
                'Error response from daemon: pull access denied'
            }

            $result = Update-DockerImages

            $result.Failed | Should -Be 1
            $result.Results[0].Status | Should -Be 'Failed'
        }

        It 'Returns correct summary counts' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                @(
                    '{"Repository":"nginx","Tag":"latest","ID":"sha256:abc123","Size":"200MB"}'
                    '{"Repository":"alpine","Tag":"3.18","ID":"sha256:def456","Size":"50MB"}'
                    '{"Repository":"<none>","Tag":"<none>","ID":"sha256:ghi789","Size":"100MB"}'
                )
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith { 'Status: Image is up to date' }

            $result = Update-DockerImages

            $result.TotalImages | Should -Be 3
            $result.Eligible | Should -Be 2
            $result.Updated | Should -Be 2
            $result.Skipped | Should -Be 1
            $result.Failed | Should -Be 0
        }

        It 'Returns empty results when no images exist' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith { @() }

            $result = Update-DockerImages

            $result.TotalImages | Should -Be 0
            $result.Eligible | Should -Be 0
            $result.Updated | Should -Be 0
            $result.Failed | Should -Be 0
            $result.Results.Count | Should -Be 0
        }
    }

    Context 'Dangling prune behavior' {
        BeforeEach {
            if (-not $script:dockerAvailable)
            {
                Set-ItResult -Skipped -Because 'Docker is not installed'
                return
            }

            $global:LASTEXITCODE = 0

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'docker' } -MockWith {
                [PSCustomObject]@{
                    Name = 'docker'
                    Source = '/usr/local/bin/docker'
                }
            }
        }

        It 'Prunes dangling images when -PruneDanglingImages is specified' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                $global:LASTEXITCODE = 0
                @('{"Repository":"nginx","Tag":"latest","ID":"sha256:abc123","Size":"200MB"}')
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith {
                $global:LASTEXITCODE = 0
                'Status: Image is up to date for nginx:latest'
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' -and $args -contains '--force' } -MockWith {
                $global:LASTEXITCODE = 0
                'Total reclaimed space: 150MB'
            }

            $result = Update-DockerImages -PruneDanglingImages

            $result.DanglingPruneRequested | Should -BeTrue
            $result.DanglingPruneSucceeded | Should -BeTrue
            $result.DanglingPruneError | Should -BeNullOrEmpty

            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' -and $args -contains '--force' } -Times 1
        }

        It 'Does not prune dangling images by default' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                $global:LASTEXITCODE = 0
                @('{"Repository":"nginx","Tag":"latest","ID":"sha256:abc123","Size":"200MB"}')
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith {
                $global:LASTEXITCODE = 0
                'Status: Image is up to date for nginx:latest'
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -MockWith {
                throw 'Dangling prune should not run unless -PruneDanglingImages is specified'
            }

            $result = Update-DockerImages

            $result.DanglingPruneRequested | Should -BeFalse
            $result.DanglingPruneSucceeded | Should -BeFalse
            $result.DanglingPruneError | Should -Be $null

            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -Times 0
        }

        It 'Honors -WhatIf and skips dangling prune' -Skip:(-not $script:dockerAvailable) {
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'ls' } -MockWith {
                $global:LASTEXITCODE = 0
                @('{"Repository":"nginx","Tag":"latest","ID":"sha256:abc123","Size":"200MB"}')
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -MockWith {
                throw 'Pull should not run under -WhatIf'
            }
            Mock -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -MockWith {
                throw 'Dangling prune should not run under -WhatIf'
            }

            $result = Update-DockerImages -PruneDanglingImages -WhatIf

            $result.DanglingPruneRequested | Should -BeTrue
            $result.DanglingPruneSucceeded | Should -BeFalse
            $result.DanglingPruneError | Should -Be $null

            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'pull' } -Times 0
            Assert-MockCalled -CommandName docker -ParameterFilter { $args[0] -eq 'image' -and $args[1] -eq 'prune' } -Times 0
        }
    }
}
