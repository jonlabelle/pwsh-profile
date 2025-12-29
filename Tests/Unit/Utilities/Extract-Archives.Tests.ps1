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

        It 'Should expose Include, Exclude, DestinationRoot, and merging parameters' {
            $command = Get-Command Extract-Archives
            $command.Parameters.ContainsKey('Include') | Should -Be $true
            $command.Parameters.ContainsKey('Exclude') | Should -Be $true
            $command.Parameters.ContainsKey('DestinationRoot') | Should -Be $true
            $command.Parameters.ContainsKey('ExtractNested') | Should -Be $true
            $command.Parameters.ContainsKey('MergeMultipartAcrossDirectories') | Should -Be $true
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
            $root = Join-Path -Path $TestDrive -ChildPath 'zip-basic'
            $sourceDir = Join-Path -Path $root -ChildPath 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'hello world' | Set-Content -Path (Join-Path -Path $sourceDir -ChildPath 'file.txt')

            $zipPath = Join-Path -Path $root -ChildPath 'archive.zip'
            Compress-Archive -Path (Join-Path -Path $sourceDir -ChildPath '*') -DestinationPath $zipPath -Force

            $result = Extract-Archives -Path $root

            $destination = Join-Path -Path $root -ChildPath 'archive'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path -Path $destination -ChildPath 'file.txt')) | Should -Be 'hello world'
            ($result.Results | Where-Object { $_.Archive -eq $zipPath }).Status | Should -Be 'Extracted'
        }

        It 'Extracts archives recursively when -Recurse is specified' {
            $root = Join-Path -Path $TestDrive -ChildPath 'recursive'
            $nested = Join-Path -Path $root -ChildPath 'nested'
            $sourceDir = Join-Path -Path $nested -ChildPath 'payload'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'nested content' | Set-Content -Path (Join-Path -Path $sourceDir -ChildPath 'data.txt')

            $zipPath = Join-Path -Path $nested -ChildPath 'nested.zip'
            Compress-Archive -Path (Join-Path -Path $sourceDir -ChildPath '*') -DestinationPath $zipPath -Force

            $result = Extract-Archives -Path $root -Recurse

            $destination = Join-Path -Path $nested -ChildPath 'nested'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path -Path $destination -ChildPath 'data.txt')) | Should -Be 'nested content'
            $result.Extracted | Should -BeGreaterThan 0
        }
    }

    Context 'Force handling' {
        It 'Skips extraction when destination exists and Force is not provided' {
            $root = Join-Path -Path $TestDrive -ChildPath 'force-skip'
            $sourceDir = Join-Path -Path $root -ChildPath 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'original' | Set-Content -Path (Join-Path -Path $sourceDir -ChildPath 'file.txt')

            $zipPath = Join-Path -Path $root -ChildPath 'archive.zip'
            Compress-Archive -Path (Join-Path -Path $sourceDir -ChildPath '*') -DestinationPath $zipPath -Force

            # First extraction
            Extract-Archives -Path $root | Out-Null

            # Modify extracted content
            $destination = Join-Path -Path $root -ChildPath 'archive'
            'modified' | Set-Content -Path (Join-Path -Path $destination -ChildPath 'file.txt')

            $result = Extract-Archives -Path $root

            (Get-Content -Path (Join-Path -Path $destination -ChildPath 'file.txt')) | Should -Be 'modified'
            ($result.Results | Where-Object { $_.Archive -eq $zipPath }).Status | Should -Be 'SkippedExisting'
        }

        It 'Overwrites destination when Force is provided' {
            $root = Join-Path -Path $TestDrive -ChildPath 'force-overwrite'
            $sourceDir = Join-Path -Path $root -ChildPath 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'fresh' | Set-Content -Path (Join-Path -Path $sourceDir -ChildPath 'file.txt')

            $zipPath = Join-Path -Path $root -ChildPath 'archive.zip'
            Compress-Archive -Path (Join-Path -Path $sourceDir -ChildPath '*') -DestinationPath $zipPath -Force

            # Initial extraction
            Extract-Archives -Path $root | Out-Null

            $destination = Join-Path -Path $root -ChildPath 'archive'
            'stale' | Set-Content -Path (Join-Path -Path $destination -ChildPath 'file.txt')

            $result = Extract-Archives -Path $root -Force

            (Get-Content -Path (Join-Path -Path $destination -ChildPath 'file.txt')) | Should -Be 'fresh'
            ($result.Results | Where-Object { $_.Archive -eq $zipPath }).Status | Should -Be 'Extracted'
        }

        It 'Respects WhatIf when Force would overwrite destination' {
            $root = Join-Path -Path $TestDrive -ChildPath 'force-whatif'
            $sourceDir = Join-Path -Path $root -ChildPath 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'original' | Set-Content -Path (Join-Path -Path $sourceDir -ChildPath 'file.txt')

            $zipPath = Join-Path -Path $root -ChildPath 'archive.zip'
            Compress-Archive -Path (Join-Path -Path $sourceDir -ChildPath '*') -DestinationPath $zipPath -Force

            # Initial extraction
            Extract-Archives -Path $root | Out-Null

            $destination = Join-Path -Path $root -ChildPath 'archive'
            'stale' | Set-Content -Path (Join-Path -Path $destination -ChildPath 'file.txt')

            $result = Extract-Archives -Path $root -Force -WhatIf

            (Get-Content -Path (Join-Path -Path $destination -ChildPath 'file.txt')) | Should -Be 'stale'
            ($result.Results | Where-Object { $_.Archive -eq $zipPath }).Status | Should -Be 'SkippedWhatIf'
        }
    }

    Context 'Filtering and destination options' {
        It 'Applies Include patterns to limit extracted archives' {
            $root = Join-Path -Path $TestDrive -ChildPath 'include-filter'
            $alphaSource = Join-Path -Path $root -ChildPath 'alpha-src'
            $betaSource = Join-Path -Path $root -ChildPath 'beta-src'
            New-Item -ItemType Directory -Path $alphaSource -Force | Out-Null
            New-Item -ItemType Directory -Path $betaSource -Force | Out-Null
            'alpha' | Set-Content -Path (Join-Path -Path $alphaSource -ChildPath 'file.txt')
            'beta' | Set-Content -Path (Join-Path -Path $betaSource -ChildPath 'file.txt')

            $alphaZip = Join-Path -Path $root -ChildPath 'alpha.zip'
            $betaZip = Join-Path -Path $root -ChildPath 'beta.zip'
            Compress-Archive -Path (Join-Path -Path $alphaSource -ChildPath '*') -DestinationPath $alphaZip -Force
            Compress-Archive -Path (Join-Path -Path $betaSource -ChildPath '*') -DestinationPath $betaZip -Force

            $result = Extract-Archives -Path $root -Include 'alpha*'

            Test-Path (Join-Path -Path $root -ChildPath 'alpha') | Should -Be $true
            Test-Path (Join-Path -Path $root -ChildPath 'beta') | Should -Be $false
            $result.TotalArchives | Should -Be 1
        }

        It 'Applies Exclude patterns to skip archives' {
            $root = Join-Path -Path $TestDrive -ChildPath 'exclude-filter'
            $alphaSource = Join-Path -Path $root -ChildPath 'alpha-src'
            $betaSource = Join-Path -Path $root -ChildPath 'beta-src'
            New-Item -ItemType Directory -Path $alphaSource -Force | Out-Null
            New-Item -ItemType Directory -Path $betaSource -Force | Out-Null
            'alpha' | Set-Content -Path (Join-Path -Path $alphaSource -ChildPath 'file.txt')
            'beta' | Set-Content -Path (Join-Path -Path $betaSource -ChildPath 'file.txt')

            $alphaZip = Join-Path -Path $root -ChildPath 'alpha.zip'
            $betaZip = Join-Path -Path $root -ChildPath 'beta.zip'
            Compress-Archive -Path (Join-Path -Path $alphaSource -ChildPath '*') -DestinationPath $alphaZip -Force
            Compress-Archive -Path (Join-Path -Path $betaSource -ChildPath '*') -DestinationPath $betaZip -Force

            $result = Extract-Archives -Path $root -Exclude 'beta*'

            Test-Path (Join-Path -Path $root -ChildPath 'alpha') | Should -Be $true
            Test-Path (Join-Path -Path $root -ChildPath 'beta') | Should -Be $false
            $result.TotalArchives | Should -Be 1
        }

        It 'Extracts into a custom DestinationRoot while keeping per-archive folders' {
            $root = Join-Path -Path $TestDrive -ChildPath 'destination-root'
            $sourceDir = Join-Path -Path $root -ChildPath 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'payload' | Set-Content -Path (Join-Path -Path $sourceDir -ChildPath 'file.txt')

            $zipPath = Join-Path -Path $root -ChildPath 'archive.zip'
            Compress-Archive -Path (Join-Path -Path $sourceDir -ChildPath '*') -DestinationPath $zipPath -Force

            $customRoot = Join-Path -Path $root -ChildPath 'extracted'
            $result = Extract-Archives -Path $root -DestinationRoot $customRoot

            $destination = Join-Path -Path $customRoot -ChildPath 'archive'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path -Path $destination -ChildPath 'file.txt')) | Should -Be 'payload'
            $result.Results | Where-Object { $_.Destination -eq $destination } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Archive type support' {
        It 'Extracts tar archives when tar is available' -Skip:($null -eq (Get-Command -Name 'tar' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $tar = Get-Command -Name 'tar' -ErrorAction SilentlyContinue | Select-Object -First 1
            $root = Join-Path -Path $TestDrive -ChildPath 'tar-support'
            $sourceDir = Join-Path -Path $root -ChildPath 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'tar content' | Set-Content -Path (Join-Path -Path $sourceDir -ChildPath 'file.txt')

            $tarPath = Join-Path -Path $root -ChildPath 'archive.tar'
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

            $destination = Join-Path -Path $root -ChildPath 'archive'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path -Path $destination -ChildPath 'file.txt')) | Should -Be 'tar content'
            ($result.Results | Where-Object { $_.Archive -eq $tarPath }).Status | Should -Be 'Extracted'
        }

        It 'Extracts 7z archives when 7z/7za is available' -Skip:($null -eq (Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $sevenZip = Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1
            $root = Join-Path -Path $TestDrive -ChildPath 'sevenzip-support'
            $sourceDir = Join-Path -Path $root -ChildPath 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            '7z content' | Set-Content -Path (Join-Path -Path $sourceDir -ChildPath 'file.txt')

            $sevenZipPath = Join-Path -Path $root -ChildPath 'archive.7z'
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

            $destination = Join-Path -Path $root -ChildPath 'archive'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path -Path $destination -ChildPath 'file.txt')) | Should -Be '7z content'
            ($result.Results | Where-Object { $_.Archive -eq $sevenZipPath }).Status | Should -Be 'Extracted'
        }

        It 'Extracts rar archives via 7z/7za when available' -Skip:($null -eq (Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $sevenZip = Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1
            $root = Join-Path -Path $TestDrive -ChildPath 'rar-support'
            $sourceDir = Join-Path -Path $root -ChildPath 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'rar content' | Set-Content -Path (Join-Path -Path $sourceDir -ChildPath 'file.txt')

            $rarPath = Join-Path -Path $root -ChildPath 'archive.rar'
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

            $destination = Join-Path -Path $root -ChildPath 'archive'
            Test-Path $destination | Should -Be $true
            (Get-Content -Path (Join-Path -Path $destination -ChildPath 'file.txt')) | Should -Be 'rar content'
            ($result.Results | Where-Object { $_.Archive -eq $rarPath }).Status | Should -Be 'Extracted'
        }
    }

    Context 'Nested and multi-part extraction' {
        It 'Extracts a multi-part zip that contains a multi-part rar set when ExtractNested is used' -Skip:($null -eq (Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $sevenZip = Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1
            $root = Join-Path -Path $TestDrive -ChildPath 'nested-multipart'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $payloadSource = Join-Path -Path $root -ChildPath 'payload-src'
            New-Item -ItemType Directory -Path $payloadSource -Force | Out-Null
            $payloadFile = Join-Path -Path $payloadSource -ChildPath 'data.bin'
            $bytes = New-Object byte[] 400000
            (New-Object System.Random).NextBytes($bytes)
            [System.IO.File]::WriteAllBytes($payloadFile, $bytes)

            $rarBase = Join-Path -Path $root -ChildPath 'payload.rar'
            Push-Location $payloadSource
            try
            {
                & $sevenZip.Name 'a' '-t7z' '-mx=0' '-v100k' $rarBase 'data.bin' | Out-Null
            }
            finally
            {
                Pop-Location
            }

            $zipSource = Join-Path -Path $root -ChildPath 'zip-src'
            New-Item -ItemType Directory -Path $zipSource -Force | Out-Null
            Get-ChildItem -Path $root -Filter 'payload.rar.*' | Move-Item -Destination $zipSource

            $zipBase = Join-Path -Path $root -ChildPath 'wrapper.zip'
            Push-Location $zipSource
            try
            {
                & $sevenZip.Name 'a' '-tzip' '-mx=0' '-v120k' $zipBase 'payload.rar.*' | Out-Null
            }
            finally
            {
                Pop-Location
            }

            Remove-Item -LiteralPath $zipSource -Recurse -Force

            $result = Extract-Archives -Path $root -ExtractNested

            $wrapperDestination = Join-Path -Path $root -ChildPath 'wrapper'
            $payloadDestination = Join-Path -Path $wrapperDestination -ChildPath 'payload'
            $extractedFile = Join-Path -Path $payloadDestination -ChildPath 'data.bin'

            Test-Path $wrapperDestination | Should -Be $true
            Test-Path $payloadDestination | Should -Be $true
            Test-Path $extractedFile | Should -Be $true
            (Get-Item -LiteralPath $extractedFile).Length | Should -Be (Get-Item -LiteralPath $payloadFile).Length
            ($result.Results | Where-Object { $_.Archive -like '*wrapper.zip*' }).Status | Should -Be 'Extracted'
            ($result.Results | Where-Object { $_.Archive -like '*payload.rar.001' }).Status | Should -Be 'Extracted'
        }

        It 'Merges multipart parts across directories when requested' -Skip:($null -eq (Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $sevenZip = Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1
            $root = Join-Path -Path $TestDrive -ChildPath 'distributed-multipart'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $payloadSource = Join-Path -Path $root -ChildPath 'payload-src'
            New-Item -ItemType Directory -Path $payloadSource -Force | Out-Null
            $payloadFile = Join-Path -Path $payloadSource -ChildPath 'data.bin'
            $bytes = New-Object byte[] 500000
            (New-Object System.Random).NextBytes($bytes)
            [System.IO.File]::WriteAllBytes($payloadFile, $bytes)

            $rarBase = Join-Path -Path $root -ChildPath 'payload.rar'
            Push-Location $payloadSource
            try
            {
                & $sevenZip.Name 'a' '-t7z' '-mx=0' '-v80k' $rarBase 'data.bin' | Out-Null
            }
            finally
            {
                Pop-Location
            }

            $partFiles = Get-ChildItem -Path $root -Filter 'payload.rar.*' -File | Sort-Object Name
            $zipIndex = 1
            foreach ($part in $partFiles)
            {
                $zipPath = Join-Path -Path $root -ChildPath ('wrapper{0}.zip' -f $zipIndex)
                $tempDir = Join-Path -Path $root -ChildPath ('wrap-src-{0}' -f $zipIndex)
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                Copy-Item -LiteralPath $part.FullName -Destination $tempDir -Force
                Compress-Archive -LiteralPath (Join-Path -Path $tempDir -ChildPath $part.Name) -DestinationPath $zipPath -Force
                Remove-Item -LiteralPath $tempDir -Recurse -Force
                $zipIndex++
            }

            Get-ChildItem -Path $root -Filter 'payload.rar.*' -File | Remove-Item -Force

            $result = Extract-Archives -Path $root -ExtractNested -MergeMultipartAcrossDirectories

            $payloadDestination = Join-Path -Path $root -ChildPath 'payload'
            $extractedFile = Join-Path -Path $payloadDestination -ChildPath 'data.bin'

            Test-Path $payloadDestination | Should -Be $true
            Test-Path $extractedFile | Should -Be $true
            (Get-Item -LiteralPath $extractedFile).Length | Should -Be (Get-Item -LiteralPath $payloadFile).Length
            ($result.Results | Where-Object { $_.Archive -like '*wrapper1.zip' }).Status | Should -Be 'Extracted'
            ($result.Results | Where-Object { $_.Archive -like '*payload.rar.001' }).Status | Should -Be 'Extracted'
        }
    }

    Context 'Missing dependency handling' {
        It 'Skips tar archives when tar dependency is missing' {
            Mock -CommandName Get-Command -MockWith { return $null } -ParameterFilter { $Name -contains 'tar' -or $Name -eq 'tar' }

            $root = Join-Path -Path $TestDrive -ChildPath 'missing-tar'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            'dummy' | Set-Content -Path (Join-Path -Path $root -ChildPath 'archive.tar')

            $result = Extract-Archives -Path $root

            $entry = $result.Results | Where-Object { $_.Archive -eq (Join-Path -Path $root -ChildPath 'archive.tar') }
            $entry.Status | Should -Be 'SkippedMissingDependency'
            $entry.ErrorMessage | Should -Match 'tar'
            Test-Path (Join-Path -Path $root -ChildPath 'archive') | Should -Be $false
        }

        It 'Skips 7z/rar archives when 7z dependency is missing' {
            Mock -CommandName Get-Command -MockWith { return $null } -ParameterFilter { ($Name -contains '7z') -or ($Name -contains '7za') -or $Name -eq '7z' -or $Name -eq '7za' }

            $root = Join-Path -Path $TestDrive -ChildPath 'missing-7z'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            'dummy' | Set-Content -Path (Join-Path -Path $root -ChildPath 'archive.7z')

            $result = Extract-Archives -Path $root

            $entry = $result.Results | Where-Object { $_.Archive -eq (Join-Path -Path $root -ChildPath 'archive.7z') }
            $entry.Status | Should -Be 'SkippedMissingDependency'
            $entry.ErrorMessage | Should -Match '7z'
            Test-Path (Join-Path -Path $root -ChildPath 'archive') | Should -Be $false
        }
    }
}
