BeforeAll {
    . "$PSScriptRoot/../../../Functions/Utilities/Find-Path.ps1"
}

Describe 'Find-Path Unit Tests' -Tag 'Unit' {
    Context 'Parameter Validation' {
        It 'Should accept Path parameter' {
            { Find-Path -Path '.' -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should accept multiple paths' {
            { Find-Path -Path '.', '.' -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should validate Type parameter accepts only valid values' {
            { Find-Path -Type 'Invalid' } | Should -Throw
        }

        It 'Should accept valid Type values' {
            { Find-Path -Type 'File' -Path '.' } | Should -Not -Throw
            { Find-Path -Type 'Directory' -Path '.' } | Should -Not -Throw
            { Find-Path -Type 'All' -Path '.' } | Should -Not -Throw
        }

        It 'Should validate MinDepth range' {
            { Find-Path -MinDepth -1 } | Should -Throw
            { Find-Path -MinDepth 101 } | Should -Throw
            { Find-Path -MinDepth 0 } | Should -Not -Throw
            { Find-Path -MinDepth 50 } | Should -Not -Throw
        }

        It 'Should validate MaxDepth range' {
            { Find-Path -MaxDepth -1 } | Should -Throw
            { Find-Path -MaxDepth 101 } | Should -Throw
            { Find-Path -MaxDepth 0 } | Should -Not -Throw
            { Find-Path -MaxDepth 50 } | Should -Not -Throw
        }

        It 'Should validate size format' {
            { Find-Path -MinSize 'invalid' } | Should -Throw
            { Find-Path -MinSize '100KB' } | Should -Not -Throw
            { Find-Path -MinSize '5.5MB' } | Should -Not -Throw
            { Find-Path -MaxSize '1GB' } | Should -Not -Throw
        }
    }

    Context 'Helper Function Tests' {
        BeforeAll {
            # Access internal helper functions via script scope
            $findPathScript = Get-Content "$PSScriptRoot/../../../Functions/Utilities/Find-Path.ps1" -Raw
        }

        It 'Should convert size strings to bytes correctly' {
            # Test size conversion logic
            $result = Find-Path -Path $TestDrive -MinSize '1KB' -Simple
            # If this doesn't throw, size parsing works
            { Find-Path -Path $TestDrive -MinSize '1KB' -Simple } | Should -Not -Throw
        }

        It 'Should handle time-based filters' {
            # Test time parsing logic
            { Find-Path -Path $TestDrive -NewerThan '7d' -Simple } | Should -Not -Throw
            { Find-Path -Path $TestDrive -OlderThan (Get-Date) -Simple } | Should -Not -Throw
        }
    }

    Context 'Output Mode Tests' {
        BeforeAll {
            # Create a temporary test file
            $testFile = Join-Path $TestDrive 'test.txt'
            Set-Content -Path $testFile -Value 'test content'
        }

        It 'Should return objects by default (formatted output)' {
            $result = Find-Path -Path $TestDrive -Name 'test.txt'
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.Properties.Name | Should -Contain 'Path'
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'Type'
        }

        It 'Should return string paths when using -Simple' {
            $result = Find-Path -Path $TestDrive -Name 'test.txt' -Simple
            $result | Should -BeOfType [String]
            $result | Should -BeLike '*test.txt'
        }

        It 'Should handle empty results gracefully' {
            $result = Find-Path -Path $TestDrive -Name 'nonexistent.xyz' -Simple
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Name and Pattern Filtering' {
        BeforeAll {
            # Create test files with various names
            $null = New-Item -Path "$TestDrive/file1.ps1" -ItemType File -Force
            $null = New-Item -Path "$TestDrive/file2.txt" -ItemType File -Force
            $null = New-Item -Path "$TestDrive/Test.PS1" -ItemType File -Force
        }

        It 'Should filter by name with wildcards (case-insensitive by default)' {
            $result = Find-Path -Path $TestDrive -Name '*.ps1' -Simple -NoRecurse
            $result.Count | Should -Be 2
        }

        It 'Should filter by name with case sensitivity when specified' {
            $result = Find-Path -Path $TestDrive -Name '*.PS1' -CaseSensitive -Simple -NoRecurse
            $result.Count | Should -Be 1
            $result | Should -BeLike '*Test.PS1'
        }

        It 'Should filter by regex pattern' {
            $result = Find-Path -Path $TestDrive -Pattern '^file\d\.ps1$' -Simple -NoRecurse
            $result.Count | Should -Be 1
            $result | Should -BeLike '*file1.ps1'
        }

        It 'Should throw on invalid regex pattern' {
            { Find-Path -Path $TestDrive -Pattern '[invalid' } | Should -Throw
        }
    }

    Context 'Type Filtering' {
        BeforeAll {
            $null = New-Item -Path "$TestDrive/testfile.txt" -ItemType File -Force
            $null = New-Item -Path "$TestDrive/testdir" -ItemType Directory -Force
        }

        It 'Should filter files only' {
            $result = Find-Path -Path $TestDrive -Type File -Simple -NoRecurse
            $result | Should -Not -BeNullOrEmpty
            $result | ForEach-Object {
                Test-Path -LiteralPath $_ -PathType Leaf | Should -Be $true
            }
        }

        It 'Should filter directories only' {
            $result = Find-Path -Path $TestDrive -Type Directory -Simple -NoRecurse
            $result | Should -Not -BeNullOrEmpty
            $result | ForEach-Object {
                Test-Path -LiteralPath $_ -PathType Container | Should -Be $true
            }
        }

        It 'Should return both files and directories with Type All' {
            $result = Find-Path -Path $TestDrive -Type All -Simple -NoRecurse
            $result.Count | Should -BeGreaterThan 1
        }
    }

    Context 'Recursion Control' {
        BeforeAll {
            # Create nested directory structure
            $null = New-Item -Path "$TestDrive/level1" -ItemType Directory -Force
            $null = New-Item -Path "$TestDrive/level1/level2" -ItemType Directory -Force
            $null = New-Item -Path "$TestDrive/level1/level2/file.txt" -ItemType File -Force
        }

        It 'Should not recurse when -NoRecurse is specified' {
            $result = Find-Path -Path $TestDrive -Type File -Simple -NoRecurse
            $result | Should -Not -Contain (Join-Path $TestDrive 'level1/level2/file.txt')
        }

        It 'Should recurse by default' {
            $result = Find-Path -Path $TestDrive -Name 'file.txt' -Simple
            $result | Should -BeLike '*level2*file.txt'
        }

        It 'Should respect MaxDepth' {
            $result = Find-Path -Path $TestDrive -Type File -MaxDepth 1 -Simple
            $result | Should -Not -Contain (Join-Path $TestDrive 'level1/level2/file.txt')
        }

        It 'Should respect MinDepth' {
            $result = Find-Path -Path $TestDrive -Type File -MinDepth 2 -Simple
            $result | Should -BeLike '*level2*file.txt'
        }
    }

    Context 'Exclude Filters' {
        BeforeAll {
            $null = New-Item -Path "$TestDrive/include.txt" -ItemType File -Force
            $null = New-Item -Path "$TestDrive/exclude.log" -ItemType File -Force
            $null = New-Item -Path "$TestDrive/.git" -ItemType Directory -Force
            $null = New-Item -Path "$TestDrive/.git/config" -ItemType File -Force
        }

        It 'Should exclude files matching exclude pattern' {
            $result = Find-Path -Path $TestDrive -Type File -Exclude '*.log' -Simple -NoRecurse
            $result | Should -Not -Contain (Join-Path $TestDrive 'exclude.log')
            $result | Should -Contain (Join-Path $TestDrive 'include.txt')
        }

        It 'Should exclude directories by default (.git)' {
            $result = Find-Path -Path $TestDrive -Name 'config' -Simple
            $result | Should -BeNullOrEmpty
        }

        It 'Should respect custom ExcludeDirectory parameter' {
            $result = Find-Path -Path $TestDrive -ExcludeDirectory @() -Name 'config' -Simple
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Special Attributes' {
        BeforeAll {
            $testFile = Join-Path $TestDrive 'normal.txt'
            Set-Content -Path $testFile -Value 'content'

            if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6)
            {
                # Test read-only on Windows
                $readOnlyFile = Join-Path $TestDrive 'readonly.txt'
                Set-Content -Path $readOnlyFile -Value 'readonly'
                Set-ItemProperty -Path $readOnlyFile -Name IsReadOnly -Value $true

                # Test hidden on Windows
                $hiddenFile = Join-Path $TestDrive 'hidden.txt'
                Set-Content -Path $hiddenFile -Value 'hidden'
                (Get-Item -Path $hiddenFile -Force).Attributes = 'Hidden'
            }
        }

        It 'Should filter read-only files when specified' -Skip:(-not ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6)) {
            $result = Find-Path -Path $TestDrive -ReadOnly -Simple -NoRecurse
            $result | Should -BeLike '*readonly.txt'
            $result | Should -Not -BeLike '*normal.txt'
        }

        It 'Should exclude hidden files by default' -Skip:(-not ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6)) {
            $result = Find-Path -Path $TestDrive -Type File -Simple -NoRecurse
            $result | Should -Not -BeLike '*hidden.txt'
        }

        It 'Should include hidden files when -Hidden is specified' -Skip:(-not ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6)) {
            $result = Find-Path -Path $TestDrive -Type File -Hidden -Simple -NoRecurse
            $result | Should -BeLike '*hidden.txt'
        }
    }

    Context 'Pipeline Input' {
        BeforeAll {
            $testFile = Join-Path $TestDrive 'pipeline.txt'
            Set-Content -Path $testFile -Value 'test'
        }

        It 'Should accept path from pipeline' {
            $result = $TestDrive | Find-Path -Type File -Simple -NoRecurse
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should accept multiple paths from pipeline' {
            $result = @($TestDrive, $TestDrive) | Find-Path -Name 'pipeline.txt' -Simple
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should accept FileInfo objects from pipeline' {
            $result = Get-Item $TestDrive | Find-Path -Type File -Simple -NoRecurse
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Error Handling' {
        It 'Should warn on non-existent path' {
            $result = Find-Path -Path '/nonexistent/path/xyz' -WarningVariable warnings -Simple 2>&1
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Should handle paths with special characters' {
            $specialPath = Join-Path $TestDrive 'test [brackets].txt'
            Set-Content -Path $specialPath -Value 'test'
            $result = Find-Path -Path $TestDrive -Name 'test [brackets].txt' -Simple
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Verbose Output' {
        It 'Should provide verbose output when requested' {
            $verboseOutput = Find-Path -Path $TestDrive -Verbose 4>&1
            $verboseOutput | Should -Not -BeNullOrEmpty
        }
    }
}
