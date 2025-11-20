BeforeAll {
    . "$PSScriptRoot/../../../Functions/Utilities/Find-Path.ps1"

    # Create a complex test directory structure for integration testing
    $script:TestRoot = Join-Path $TestDrive 'FindPathIntegration'
    $null = New-Item -Path $TestRoot -ItemType Directory -Force

    # Create various test files and directories
    $script:testStructure = @{
        'documents/readme.txt' = 'Small text file'
        'documents/guide.md' = 'Markdown guide'
        'documents/archived/old.txt' = 'Old document'
        'scripts/deploy.ps1' = 'PowerShell script'
        'scripts/build.ps1' = 'Build script'
        'scripts/test/unit.ps1' = 'Unit test'
        'data/config.json' = '{"key":"value"}'
        'data/settings.xml' = '<root></root>'
        'logs/app.log' = 'Log entry 1'
        'logs/error.log' = 'Error log'
        'temp/.gitkeep' = ''
        '.git/config' = 'git config'
        '.git/objects/abc123' = 'object'
        'node_modules/package/index.js' = 'module'
    }

    foreach ($file in $script:testStructure.Keys)
    {
        $fullPath = Join-Path $TestRoot $file
        $dir = Split-Path $fullPath -Parent
        if (-not (Test-Path $dir))
        {
            $null = New-Item -Path $dir -ItemType Directory -Force
        }
        Set-Content -Path $fullPath -Value $script:testStructure[$file] -Force
    }

    # Create some empty files and directories
    $null = New-Item -Path (Join-Path $TestRoot 'empty.txt') -ItemType File -Force
    $null = New-Item -Path (Join-Path $TestRoot 'empty_dir') -ItemType Directory -Force

    # Create a large file (>1MB)
    $largePath = Join-Path $TestRoot 'large.bin'
    $largeContent = 'x' * 1500000  # ~1.5MB
    Set-Content -Path $largePath -Value $largeContent -Force

    # Sleep briefly to ensure file times are distinct
    Start-Sleep -Milliseconds 500

    # Create a new file for time-based testing
    $script:newFile = Join-Path $TestRoot 'recent.txt'
    Set-Content -Path $script:newFile -Value 'recent file' -Force
}

AfterAll {
    # Cleanup is handled automatically by $TestDrive
}

Describe 'Find-Path Integration Tests' -Tag 'Integration' {
    Context 'Basic Find Operations' {
        It 'Should find all files recursively' {
            $result = Find-Path -Path $TestRoot -Type File -Simple
            $result.Count | Should -BeGreaterThan 10
        }

        It 'Should find all directories recursively' {
            $result = Find-Path -Path $TestRoot -Type Directory -Simple
            $result.Count | Should -BeGreaterThan 5
        }

        It 'Should find items in current directory only (NoRecurse)' {
            $result = Find-Path -Path $TestRoot -NoRecurse -Simple
            # Should find top-level items only
            $result | ForEach-Object {
                $_.Split([IO.Path]::DirectorySeparatorChar).Count | Should -Be ($TestRoot.Split([IO.Path]::DirectorySeparatorChar).Count + 1)
            }
        }
    }

    Context 'Name-Based Searching' {
        It 'Should find all PowerShell files' {
            $result = Find-Path -Path $TestRoot -Name '*.ps1' -Simple
            $result.Count | Should -Be 3
            $result | ForEach-Object {
                $_ | Should -BeLike '*.ps1'
            }
        }

        It 'Should find files with specific name' {
            $result = Find-Path -Path $TestRoot -Name 'readme.txt' -Simple
            $result.Count | Should -Be 1
            $result | Should -BeLike '*readme.txt'
        }

        It 'Should perform case-insensitive search by default' {
            $result = Find-Path -Path $TestRoot -Name 'README.TXT' -Simple
            $result.Count | Should -Be 1
        }

        It 'Should perform case-sensitive search when specified' {
            $result = Find-Path -Path $TestRoot -Name 'README.TXT' -CaseSensitive -Simple
            $result.Count | Should -Be 0
        }
    }

    Context 'Pattern-Based Searching' {
        It 'Should find files matching regex pattern' {
            $result = Find-Path -Path $TestRoot -Pattern '\.ps1$' -Simple
            $result.Count | Should -Be 3
        }

        It 'Should find files with complex regex' {
            # Find files starting with letter followed by exactly one word
            $result = Find-Path -Path $TestRoot -Pattern '^[a-z]+\.(txt|md)$' -Simple
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Size-Based Filtering' {
        It 'Should find files larger than 1MB' {
            $result = Find-Path -Path $TestRoot -MinSize '1MB' -Type File -Simple
            $result.Count | Should -Be 1
            $result | Should -BeLike '*large.bin'
        }

        It 'Should find small files under 1KB' {
            $result = Find-Path -Path $TestRoot -MaxSize '1KB' -Type File -Simple
            $result.Count | Should -BeGreaterThan 5
        }

        It 'Should find files within size range' {
            $result = Find-Path -Path $TestRoot -MinSize '10B' -MaxSize '100B' -Type File -Simple
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Time-Based Filtering' {
        It 'Should find recently modified files' {
            $result = Find-Path -Path $TestRoot -NewerThan (Get-Date).AddHours(-1) -Type File -Simple
            $result | Should -Contain $script:newFile
        }

        It 'Should find old files' {
            $result = Find-Path -Path $TestRoot -OlderThan (Get-Date).AddDays(-1) -Type File -Simple
            $result.Count | Should -Be 0  # All files were just created
        }

        It 'Should support time string format' {
            $result = Find-Path -Path $TestRoot -NewerThan '1h' -Type File -Simple
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Empty File and Directory Detection' {
        It 'Should find empty files' {
            $result = Find-Path -Path $TestRoot -Empty -Type File -Simple
            $result | Should -Contain (Join-Path $TestRoot 'empty.txt')
        }

        It 'Should find empty directories' {
            $result = Find-Path -Path $TestRoot -Empty -Type Directory -Simple
            $result | Should -Contain (Join-Path $TestRoot 'empty_dir')
        }

        It 'Should find all empty items' {
            $result = Find-Path -Path $TestRoot -Empty -Simple
            $result.Count | Should -BeGreaterThan 1
        }
    }

    Context 'Directory Exclusion' {
        It 'Should exclude .git directory by default' {
            $result = Find-Path -Path $TestRoot -Name 'config' -Simple
            $result | Should -BeNullOrEmpty
        }

        It 'Should exclude multiple directories' {
            $result = Find-Path -Path $TestRoot -ExcludeDirectory '.git', 'node_modules' -Type File -Simple
            $result | Should -Not -BeLike '*.git*'
            $result | Should -Not -BeLike '*node_modules*'
        }

        It 'Should find files in excluded directories when override is used' {
            $result = Find-Path -Path $TestRoot -ExcludeDirectory @() -Name 'config' -Simple
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'File Exclusion' {
        It 'Should exclude log files' {
            $result = Find-Path -Path $TestRoot -Exclude '*.log' -Type File -Simple
            $result | Should -Not -BeLike '*.log'
        }

        It 'Should exclude multiple patterns' {
            $result = Find-Path -Path $TestRoot -Exclude '*.log', '*.bin' -Type File -Simple
            $result | Should -Not -BeLike '*.log'
            $result | Should -Not -BeLike '*.bin'
        }
    }

    Context 'Depth Control' {
        It 'Should limit search depth with MaxDepth' {
            $result = Find-Path -Path $TestRoot -MaxDepth 1 -Type File -Simple
            # Should only find files in root and one level deep
            $result | ForEach-Object {
                $relativePath = $_.Substring($TestRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
                $depth = ($relativePath -split [regex]::Escape([IO.Path]::DirectorySeparatorChar)).Count - 1
                $depth | Should -BeLessOrEqual 1
            }
        }

        It 'Should skip shallow items with MinDepth' {
            $result = Find-Path -Path $TestRoot -MinDepth 2 -Type File -Simple
            $result | ForEach-Object {
                $relativePath = $_.Substring($TestRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
                $depth = ($relativePath -split [regex]::Escape([IO.Path]::DirectorySeparatorChar)).Count - 1
                $depth | Should -BeGreaterOrEqual 2
            }
        }

        It 'Should combine MinDepth and MaxDepth' {
            $result = Find-Path -Path $TestRoot -MinDepth 1 -MaxDepth 2 -Type File -Simple
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Output Formats' {
        It 'Should provide formatted output by default' {
            $result = Find-Path -Path $TestRoot -Name 'readme.txt'
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.Properties.Name | Should -Contain 'Type'
            $result[0].PSObject.Properties.Name | Should -Contain 'Size'
            $result[0].PSObject.Properties.Name | Should -Contain 'Modified'
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'Path'
        }

        It 'Should provide simple path output with -Simple' {
            $result = Find-Path -Path $TestRoot -Name 'readme.txt' -Simple
            $result | Should -BeOfType [String]
            $result | Should -BeLike '*readme.txt'
        }

        It 'Should allow piping simple output to other commands' {
            $result = Find-Path -Path $TestRoot -Name '*.ps1' -Simple | ForEach-Object { Test-Path $_ }
            $result | ForEach-Object { $_ | Should -Be $true }
        }
    }

    Context 'Complex Real-World Scenarios' {
        It 'Should find recent PowerShell scripts excluding test directories' {
            $result = Find-Path -Path $TestRoot -Name '*.ps1' -ExcludeDirectory 'test' -NewerThan '1d' -Simple
            $result | Should -Not -BeLike '*test*'
        }

        It 'Should find large old log files' {
            # Create a larger old log for this test
            $oldLog = Join-Path $TestRoot 'logs/old.log'
            Set-Content -Path $oldLog -Value ('x' * 2000)
            (Get-Item $oldLog).LastWriteTime = (Get-Date).AddDays(-10)

            $result = Find-Path -Path $TestRoot -Name '*.log' -MinSize '1KB' -OlderThan '5d' -Simple
            $result | Should -Contain $oldLog
        }

        It 'Should find configuration files in specific subdirectories' {
            $result = Find-Path -Path $TestRoot -Pattern '\.(json|xml)$' -MaxDepth 2 -Simple
            $result | Should -Not -BeNullOrEmpty
            $result | ForEach-Object {
                $_ | Should -Match '\.(json|xml)$'
            }
        }

        It 'Should list directory contents like ls -R' {
            $result = Find-Path -Path $TestRoot -Type File -Simple
            $result.Count | Should -BeGreaterThan 10
        }
    }

    Context 'Edge Cases and Error Handling' {
        It 'Should handle non-existent paths gracefully' {
            $warnings = @()
            $result = Find-Path -Path (Join-Path $TestRoot 'nonexistent') -Simple -WarningVariable +warnings 2>&1
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Should handle paths with spaces' {
            $spacePath = Join-Path $TestRoot 'path with spaces'
            $null = New-Item -Path $spacePath -ItemType Directory -Force
            $spaceFile = Join-Path $spacePath 'file.txt'
            Set-Content -Path $spaceFile -Value 'test'

            $result = Find-Path -Path $spacePath -Simple
            $result | Should -Contain $spaceFile
        }

        It 'Should handle special characters in filenames' {
            $specialFile = Join-Path $TestRoot 'special[chars].txt'
            Set-Content -LiteralPath $specialFile -Value 'test'

            $result = Find-Path -Path $TestRoot -Name 'special[chars].txt' -Simple
            $result | Should -Contain $specialFile
        }

        It 'Should handle deeply nested paths' {
            $deepPath = Join-Path $TestRoot 'a/b/c/d/e/f/g'
            $null = New-Item -Path $deepPath -ItemType Directory -Force
            $deepFile = Join-Path $deepPath 'deep.txt'
            Set-Content -Path $deepFile -Value 'deep'

            $result = Find-Path -Path $TestRoot -Name 'deep.txt' -Simple
            $result | Should -Contain $deepFile
        }
    }

    Context 'Performance and Scalability' {
        It 'Should handle searching many files efficiently' {
            $result = Find-Path -Path $TestRoot -Simple
            # Should complete without timeout
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should handle depth limits without stack overflow' {
            $result = Find-Path -Path $TestRoot -MaxDepth 10 -Simple
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Cross-Platform Path Handling' {
        It 'Should handle platform-specific path separators' {
            $result = Find-Path -Path $TestRoot -Name 'readme.txt' -Simple
            $result | Should -Match ([regex]::Escape([IO.Path]::DirectorySeparatorChar))
        }

        It 'Should resolve relative paths correctly' {
            Push-Location $TestRoot
            try
            {
                $result = Find-Path -Path '.' -Name 'readme.txt' -Simple
                $result | Should -Not -BeNullOrEmpty
            }
            finally
            {
                Pop-Location
            }
        }

        It 'Should handle tilde expansion for home directory' {
            # Only test if we can resolve home path
            $homePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('~')
            if (Test-Path $homePath)
            {
                { Find-Path -Path '~' -MaxDepth 0 -Simple } | Should -Not -Throw
            }
        }
    }
}
