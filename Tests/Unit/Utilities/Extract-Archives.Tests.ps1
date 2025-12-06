#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Extract-Archives function.

.DESCRIPTION
    Tests the Extract-Archives function which scans a directory for common archive
    formats and extracts them into folders named after each archive. Covers
    parameter validation, extraction behavior, recursion, filtering, destination
    overrides, force handling, and support for tar/7z/rar archives when available.
#>

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../../Functions/Utilities/Extract-Archives.ps1"
}

Describe 'Extract-Archives' {
    Context 'Parameter Validation' {
        It 'Should accept optional Path parameter with pipeline support' {
            $command = Get-Command Extract-Archives
            $pathParam = $command.Parameters['Path']
            $pathParam.Attributes.Mandatory | Should -Not -Contain $true
            $pathParam.Attributes.ValueFromPipeline | Should -Contain $true
        }

        It 'Should expose Include, Exclude, and DestinationRoot parameters' {
            $command = Get-Command Extract-Archives
            $command.Parameters.ContainsKey('Include') | Should -Be $true
            $command.Parameters.ContainsKey('Exclude') | Should -Be $true
            $command.Parameters.ContainsKey('DestinationRoot') | Should -Be $true
        }

        It 'Should support ShouldProcess (WhatIf/Confirm)' {
            $command = Get-Command Extract-Archives
            $command.Parameters.ContainsKey('WhatIf') | Should -Be $true
            $command.Parameters.ContainsKey('Confirm') | Should -Be $true
        }

        It 'Should declare OutputType' {
            $command = Get-Command Extract-Archives
            $command.OutputType | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Extraction behavior' {
        It 'Extracts zip archive to folder named after archive' {
            $root = Join-Path $TestDrive 'zip-basic'
            $sourceDir = Join-Path $root 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'hello world' | Set-Content -Path (Join-Path $sourceDir 'file.txt')

            $zipPath = Join-Path $root 'archive.zip'
            Compress-Archive -Path (Join-Path $sourceDir '*') -DestinationPath $zipPath -Force

            $result = Extract-Archives -Path $root

            $destination = Join-Path $root 'archive'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path $destination 'file.txt')) | Should -Be 'hello world'
            ($result.Results | Where-Object { $_.Archive -eq $zipPath }).Status | Should -Be 'Extracted'
        }

        It 'Extracts archives recursively when -Recurse is specified' {
            $root = Join-Path $TestDrive 'recursive'
            $nested = Join-Path $root 'nested'
            $sourceDir = Join-Path $nested 'payload'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'nested content' | Set-Content -Path (Join-Path $sourceDir 'data.txt')

            $zipPath = Join-Path $nested 'nested.zip'
            Compress-Archive -Path (Join-Path $sourceDir '*') -DestinationPath $zipPath -Force

            $result = Extract-Archives -Path $root -Recurse

            $destination = Join-Path $nested 'nested'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path $destination 'data.txt')) | Should -Be 'nested content'
            $result.Extracted | Should -BeGreaterThan 0
        }
    }

    Context 'Force handling' {
        It 'Skips extraction when destination exists and Force is not provided' {
            $root = Join-Path $TestDrive 'force-skip'
            $sourceDir = Join-Path $root 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'original' | Set-Content -Path (Join-Path $sourceDir 'file.txt')

            $zipPath = Join-Path $root 'archive.zip'
            Compress-Archive -Path (Join-Path $sourceDir '*') -DestinationPath $zipPath -Force

            # First extraction
            Extract-Archives -Path $root | Out-Null

            # Modify extracted content
            $destination = Join-Path $root 'archive'
            'modified' | Set-Content -Path (Join-Path $destination 'file.txt')

            $result = Extract-Archives -Path $root

            (Get-Content -Path (Join-Path $destination 'file.txt')) | Should -Be 'modified'
            ($result.Results | Where-Object { $_.Archive -eq $zipPath }).Status | Should -Be 'SkippedExisting'
        }

        It 'Overwrites destination when Force is provided' {
            $root = Join-Path $TestDrive 'force-overwrite'
            $sourceDir = Join-Path $root 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'fresh' | Set-Content -Path (Join-Path $sourceDir 'file.txt')

            $zipPath = Join-Path $root 'archive.zip'
            Compress-Archive -Path (Join-Path $sourceDir '*') -DestinationPath $zipPath -Force

            # Initial extraction
            Extract-Archives -Path $root | Out-Null

            $destination = Join-Path $root 'archive'
            'stale' | Set-Content -Path (Join-Path $destination 'file.txt')

            $result = Extract-Archives -Path $root -Force

            (Get-Content -Path (Join-Path $destination 'file.txt')) | Should -Be 'fresh'
            ($result.Results | Where-Object { $_.Archive -eq $zipPath }).Status | Should -Be 'Extracted'
        }

        It 'Respects WhatIf when Force would overwrite destination' {
            $root = Join-Path $TestDrive 'force-whatif'
            $sourceDir = Join-Path $root 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'original' | Set-Content -Path (Join-Path $sourceDir 'file.txt')

            $zipPath = Join-Path $root 'archive.zip'
            Compress-Archive -Path (Join-Path $sourceDir '*') -DestinationPath $zipPath -Force

            # Initial extraction
            Extract-Archives -Path $root | Out-Null

            $destination = Join-Path $root 'archive'
            'stale' | Set-Content -Path (Join-Path $destination 'file.txt')

            $result = Extract-Archives -Path $root -Force -WhatIf

            (Get-Content -Path (Join-Path $destination 'file.txt')) | Should -Be 'stale'
            ($result.Results | Where-Object { $_.Archive -eq $zipPath }).Status | Should -Be 'SkippedWhatIf'
        }
    }

    Context 'Filtering and destination options' {
        It 'Applies Include patterns to limit extracted archives' {
            $root = Join-Path $TestDrive 'include-filter'
            $alphaSource = Join-Path $root 'alpha-src'
            $betaSource = Join-Path $root 'beta-src'
            New-Item -ItemType Directory -Path $alphaSource -Force | Out-Null
            New-Item -ItemType Directory -Path $betaSource -Force | Out-Null
            'alpha' | Set-Content -Path (Join-Path $alphaSource 'file.txt')
            'beta' | Set-Content -Path (Join-Path $betaSource 'file.txt')

            $alphaZip = Join-Path $root 'alpha.zip'
            $betaZip = Join-Path $root 'beta.zip'
            Compress-Archive -Path (Join-Path $alphaSource '*') -DestinationPath $alphaZip -Force
            Compress-Archive -Path (Join-Path $betaSource '*') -DestinationPath $betaZip -Force

            $result = Extract-Archives -Path $root -Include 'alpha*'

            Test-Path (Join-Path $root 'alpha') | Should -Be $true
            Test-Path (Join-Path $root 'beta') | Should -Be $false
            $result.TotalArchives | Should -Be 1
        }

        It 'Applies Exclude patterns to skip archives' {
            $root = Join-Path $TestDrive 'exclude-filter'
            $alphaSource = Join-Path $root 'alpha-src'
            $betaSource = Join-Path $root 'beta-src'
            New-Item -ItemType Directory -Path $alphaSource -Force | Out-Null
            New-Item -ItemType Directory -Path $betaSource -Force | Out-Null
            'alpha' | Set-Content -Path (Join-Path $alphaSource 'file.txt')
            'beta' | Set-Content -Path (Join-Path $betaSource 'file.txt')

            $alphaZip = Join-Path $root 'alpha.zip'
            $betaZip = Join-Path $root 'beta.zip'
            Compress-Archive -Path (Join-Path $alphaSource '*') -DestinationPath $alphaZip -Force
            Compress-Archive -Path (Join-Path $betaSource '*') -DestinationPath $betaZip -Force

            $result = Extract-Archives -Path $root -Exclude 'beta*'

            Test-Path (Join-Path $root 'alpha') | Should -Be $true
            Test-Path (Join-Path $root 'beta') | Should -Be $false
            $result.TotalArchives | Should -Be 1
        }

        It 'Extracts into a custom DestinationRoot while keeping per-archive folders' {
            $root = Join-Path $TestDrive 'destination-root'
            $sourceDir = Join-Path $root 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'payload' | Set-Content -Path (Join-Path $sourceDir 'file.txt')

            $zipPath = Join-Path $root 'archive.zip'
            Compress-Archive -Path (Join-Path $sourceDir '*') -DestinationPath $zipPath -Force

            $customRoot = Join-Path $root 'extracted'
            $result = Extract-Archives -Path $root -DestinationRoot $customRoot

            $destination = Join-Path $customRoot 'archive'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path $destination 'file.txt')) | Should -Be 'payload'
            $result.Results | Where-Object { $_.Destination -eq $destination } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Archive type support' {
        It 'Extracts tar archives when tar is available' -Skip:($null -eq (Get-Command -Name 'tar' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $tar = Get-Command -Name 'tar' -ErrorAction SilentlyContinue | Select-Object -First 1
            $root = Join-Path $TestDrive 'tar-support'
            $sourceDir = Join-Path $root 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'tar content' | Set-Content -Path (Join-Path $sourceDir 'file.txt')

            $tarPath = Join-Path $root 'archive.tar'
            Push-Location $sourceDir
            try
            {
                & $tar.Name '-cf' $tarPath 'file.txt' | Out-Null
            }
            finally
            {
                Pop-Location
            }

            $result = Extract-Archives -Path $root

            $destination = Join-Path $root 'archive'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path $destination 'file.txt')) | Should -Be 'tar content'
            ($result.Results | Where-Object { $_.Archive -eq $tarPath }).Status | Should -Be 'Extracted'
        }

        It 'Extracts 7z archives when 7z/7za is available' -Skip:($null -eq (Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $sevenZip = Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1
            $root = Join-Path $TestDrive 'sevenzip-support'
            $sourceDir = Join-Path $root 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            '7z content' | Set-Content -Path (Join-Path $sourceDir 'file.txt')

            $sevenZipPath = Join-Path $root 'archive.7z'
            Push-Location $sourceDir
            try
            {
                & $sevenZip.Name 'a' $sevenZipPath 'file.txt' | Out-Null
            }
            finally
            {
                Pop-Location
            }

            $result = Extract-Archives -Path $root

            $destination = Join-Path $root 'archive'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path $destination 'file.txt')) | Should -Be '7z content'
            ($result.Results | Where-Object { $_.Archive -eq $sevenZipPath }).Status | Should -Be 'Extracted'
        }

        It 'Extracts rar archives via 7z/7za when available' -Skip:($null -eq (Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $sevenZip = Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1
            $root = Join-Path $TestDrive 'rar-support'
            $sourceDir = Join-Path $root 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'rar content' | Set-Content -Path (Join-Path $sourceDir 'file.txt')

            $rarPath = Join-Path $root 'archive.rar'
            Push-Location $sourceDir
            try
            {
                & $sevenZip.Name 'a' '-t7z' $rarPath 'file.txt' | Out-Null
            }
            finally
            {
                Pop-Location
            }

            $result = Extract-Archives -Path $root

            $destination = Join-Path $root 'archive'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path $destination 'file.txt')) | Should -Be 'rar content'
            ($result.Results | Where-Object { $_.Archive -eq $rarPath }).Status | Should -Be 'Extracted'
        }
    }

    Context 'Missing dependency handling' {
        It 'Skips tar archives when tar dependency is missing' {
            Mock -CommandName Get-Command -MockWith { return $null } -ParameterFilter { $Name -contains 'tar' -or $Name -eq 'tar' }

            $root = Join-Path $TestDrive 'missing-tar'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            'dummy' | Set-Content -Path (Join-Path $root 'archive.tar')

            $result = Extract-Archives -Path $root

            $entry = $result.Results | Where-Object { $_.Archive -eq (Join-Path $root 'archive.tar') }
            $entry.Status | Should -Be 'SkippedMissingDependency'
            $entry.ErrorMessage | Should -Match 'tar'
            Test-Path (Join-Path $root 'archive') | Should -Be $false
        }

        It 'Skips 7z/rar archives when 7z dependency is missing' {
            Mock -CommandName Get-Command -MockWith { return $null } -ParameterFilter { ($Name -contains '7z') -or ($Name -contains '7za') -or $Name -eq '7z' -or $Name -eq '7za' }

            $root = Join-Path $TestDrive 'missing-7z'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            'dummy' | Set-Content -Path (Join-Path $root 'archive.7z')

            $result = Extract-Archives -Path $root

            $entry = $result.Results | Where-Object { $_.Archive -eq (Join-Path $root 'archive.7z') }
            $entry.Status | Should -Be 'SkippedMissingDependency'
            $entry.ErrorMessage | Should -Match '7z'
            Test-Path (Join-Path $root 'archive') | Should -Be $false
        }
    }
}
