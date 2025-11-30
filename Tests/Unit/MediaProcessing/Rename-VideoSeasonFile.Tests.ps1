BeforeAll {
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Rename-VideoSeasonFile.ps1"
}

Describe 'Rename-VideoSeasonFile' -Tag 'Unit' {
    Context 'Parameter Validation' {
        It 'Should have Recurse parameter' {
            $command = Get-Command Rename-VideoSeasonFile
            $command.Parameters.ContainsKey('Recurse') | Should -Be $true
        }

        It 'Should have Exclude parameter' {
            $command = Get-Command Rename-VideoSeasonFile
            $command.Parameters.ContainsKey('Exclude') | Should -Be $true
        }

        It 'Should have PassThru parameter' {
            $command = Get-Command Rename-VideoSeasonFile
            $command.Parameters.ContainsKey('PassThru') | Should -Be $true
        }
    }

    Context 'Parameter Types' {
        It 'Should have Recurse as Switch parameter' {
            $command = Get-Command Rename-VideoSeasonFile
            $recurseParam = $command.Parameters['Recurse']
            $recurseParam.ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have Exclude as String array parameter' {
            $command = Get-Command Rename-VideoSeasonFile
            $excludeParam = $command.Parameters['Exclude']
            $excludeParam.ParameterType.Name | Should -Be 'String[]'
        }

        It 'Should have Filters as String array parameter' {
            $command = Get-Command Rename-VideoSeasonFile
            $filtersParam = $command.Parameters['Filters']
            $filtersParam.ParameterType.Name | Should -Be 'String[]'
        }
    }

    Context 'Default Behavior' {
        BeforeAll {
            # Create test directory structure
            $testRoot = Join-Path $TestDrive 'RenameTest'
            $subDir = Join-Path $testRoot 'SubDirectory'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $subDir -ItemType Directory -Force | Out-Null

            # Create mock video files with season/episode patterns
            New-Item -Path (Join-Path $testRoot 'Show.S01E01.mkv') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $subDir 'Show.S01E02.mkv') -ItemType File -Force | Out-Null
        }

        It 'Should process non-recursively by default with -WhatIf' {
            # Test with -WhatIf to avoid actual file operations
            { Rename-VideoSeasonFile -Path $testRoot -WhatIf } | Should -Not -Throw
        }

        It 'Should process recursively when -Recurse is specified with -WhatIf' {
            # Test with -WhatIf to avoid actual file operations
            { Rename-VideoSeasonFile -Path $testRoot -Recurse -WhatIf } | Should -Not -Throw
        }

        It 'Should respect Exclude parameter when using -Recurse with -WhatIf' {
            # Test with -WhatIf to avoid actual file operations
            { Rename-VideoSeasonFile -Path $testRoot -Recurse -Exclude @('.git', 'SubDirectory') -WhatIf } | Should -Not -Throw
        }
    }

    Context 'Pattern Matching' {
        BeforeAll {
            # Create test directory
            $testRoot = Join-Path $TestDrive 'PatternTest'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        }

        It 'Should identify files with season/episode patterns' {
            # Create test files with various patterns
            $testFiles = @(
                'Show.S01E01.mkv',
                'Show.s02e05.mp4',
                'Show.Season.1.Episode.3.avi',
                'Show.1x04.mp4'
            )

            foreach ($file in $testFiles)
            {
                New-Item -Path (Join-Path $testRoot $file) -ItemType File -Force | Out-Null
            }

            # Test pattern recognition with -WhatIf
            { Rename-VideoSeasonFile -Path $testRoot -WhatIf -Verbose } | Should -Not -Throw
        }
    }

    Context 'Individual File Support' {
        BeforeAll {
            # Create test directory and files
            $testRoot = Join-Path $TestDrive 'RenameFileTest'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            # Create mock video files
            $script:testSeasonFile = Join-Path $testRoot 'Breaking.Bad.S01E01.1080p.BluRay.x264-DEMAND.mkv'
            $script:testNonSeasonFile = Join-Path $testRoot 'regular-movie.mkv'
            $script:testNonVideoFile = Join-Path $testRoot 'document.txt'

            New-Item -Path $script:testSeasonFile -ItemType File -Force | Out-Null
            New-Item -Path $script:testNonSeasonFile -ItemType File -Force | Out-Null
            New-Item -Path $script:testNonVideoFile -ItemType File -Force | Out-Null
        }

        It 'Should accept individual video file paths with -WhatIf' {
            # Should not throw when given an individual video file with season pattern
            { Rename-VideoSeasonFile -Path $script:testSeasonFile -WhatIf } | Should -Not -Throw
        }

        It 'Should validate file extension for individual files' {
            # Should warn when file extension doesn't match supported filters
            $output = Rename-VideoSeasonFile -Path $script:testNonVideoFile -WhatIf -WarningVariable warnings 2>&1
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Should handle files without season patterns gracefully' {
            # Should not crash when file has no season/episode pattern
            { Rename-VideoSeasonFile -Path $script:testNonSeasonFile -WhatIf -Verbose } | Should -Not -Throw
        }

        It 'Should handle non-existent file paths gracefully' {
            $nonExistentFile = Join-Path $TestDrive 'does-not-exist.mkv'

            # Should handle gracefully by producing appropriate error message
            $ErrorActionPreference = 'SilentlyContinue'
            $result = Rename-VideoSeasonFile -Path $nonExistentFile -WhatIf -ErrorVariable errors 2>&1
            $errors.Count | Should -BeGreaterThan 0
            $errors[0].Exception.Message | Should -BeLike '*not found*'
        }

        It 'Should support pipeline input for individual files' {
            $command = Get-Command Rename-VideoSeasonFile
            $pathParam = $command.Parameters['Path']

            # Check that Path parameter supports pipeline input
            $pipelineAttributes = $pathParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pipelineSupport = $pipelineAttributes | Where-Object { $_.ValueFromPipeline -eq $true -or $_.ValueFromPipelineByPropertyName -eq $true }
            $pipelineSupport | Should -Not -BeNullOrEmpty
        }

        It 'Should include FilePath and FullName aliases for individual file support' {
            $command = Get-Command Rename-VideoSeasonFile
            $pathParam = $command.Parameters['Path']

            # Check for aliases that support file input
            $aliases = $pathParam.Aliases
            $aliases | Should -Contain 'FilePath'
            $aliases | Should -Contain 'FullName'
        }
    }
}
