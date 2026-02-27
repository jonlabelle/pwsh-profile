BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Import the functions
    . "$PSScriptRoot/../../../Functions/Utilities/New-SymbolicLink.ps1"
    . "$PSScriptRoot/../../../Functions/Utilities/Remove-SymbolicLink.ps1"

    # Import test cleanup utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Remove-SymbolicLink Unit Tests' -Tag 'Unit', 'Utilities' {
    BeforeAll {
        # Create a test directory structure
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath 'RemoveSymbolicLinkTests'
        New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null

        # Create subdirectories for organized testing
        $script:targetDir = Join-Path -Path $script:testRoot -ChildPath 'targets'
        $script:linkDir = Join-Path -Path $script:testRoot -ChildPath 'links'
        New-Item -Path $script:targetDir -ItemType Directory -Force | Out-Null
        New-Item -Path $script:linkDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        # Cleanup
        if (Test-Path $script:testRoot)
        {
            Remove-TestDirectory -Path $script:testRoot
        }
    }

    Context 'Removing File Symbolic Links' {
        BeforeEach {
            # Create a target file
            $script:targetFile = Join-Path -Path $script:targetDir -ChildPath 'testfile.txt'
            'test content' | Out-File -FilePath $script:targetFile -Encoding UTF8

            # Create a symbolic link
            $script:linkPath = Join-Path -Path $script:linkDir -ChildPath 'link-to-file.txt'
            New-SymbolicLink -Path $script:linkPath -Target $script:targetFile
        }

        AfterEach {
            # Clean up
            if (Test-Path $script:linkPath)
            {
                Remove-Item -Path $script:linkPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $script:targetFile)
            {
                Remove-Item -Path $script:targetFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should remove a file symbolic link' {
            Remove-SymbolicLink -Path $script:linkPath

            Test-Path -Path $script:linkPath | Should -Be $false
        }

        It 'Should not remove the target file when removing symbolic link' {
            Remove-SymbolicLink -Path $script:linkPath

            Test-Path -Path $script:targetFile | Should -Be $true
            Get-Content -Path $script:targetFile | Should -Be 'test content'
        }

        It 'Should return information when PassThru is specified' {
            $result = Remove-SymbolicLink -Path $script:linkPath -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.Path | Should -Be $script:linkPath
            $result.Removed | Should -Be $true
            $result.ItemType | Should -Be 'File'
        }
    }

    Context 'Removing Directory Symbolic Links' {
        BeforeEach {
            # Create a target directory with content
            $script:targetSubDir = Join-Path -Path $script:targetDir -ChildPath 'subdir'
            New-Item -Path $script:targetSubDir -ItemType Directory -Force | Out-Null

            $fileInDir = Join-Path -Path $script:targetSubDir -ChildPath 'file-in-dir.txt'
            'content in subdir' | Out-File -FilePath $fileInDir -Encoding UTF8

            # Create a symbolic link to directory
            $script:dirLinkPath = Join-Path -Path $script:linkDir -ChildPath 'link-to-dir'
            New-SymbolicLink -Path $script:dirLinkPath -Target $script:targetSubDir
        }

        AfterEach {
            # Clean up directory symlink using robust helper function
            # This handles Windows PS 5.1 edge cases where directory symlinks can be problematic
            Remove-TestSymbolicLink -Path $script:dirLinkPath

            # Clean up target directory
            if (Test-Path $script:targetSubDir)
            {
                Remove-Item -Path $script:targetSubDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should remove a directory symbolic link' {
            Remove-SymbolicLink -Path $script:dirLinkPath

            Test-Path -Path $script:dirLinkPath | Should -Be $false
        }

        It 'Should not remove the target directory or its contents when removing symbolic link' {
            Remove-SymbolicLink -Path $script:dirLinkPath

            Test-Path -Path $script:targetSubDir | Should -Be $true

            $fileInDir = Join-Path -Path $script:targetSubDir -ChildPath 'file-in-dir.txt'
            Test-Path -Path $fileInDir | Should -Be $true
            Get-Content -Path $fileInDir | Should -Be 'content in subdir'
        }

        It 'Should return directory ItemType in PassThru output' {
            $result = Remove-SymbolicLink -Path $script:dirLinkPath -PassThru

            $result.ItemType | Should -Be 'Directory'
            $result.Removed | Should -Be $true
        }
    }

    Context 'Error Handling' {
        It 'Should fail when path does not exist' {
            $nonExistentPath = Join-Path -Path $script:linkDir -ChildPath 'does-not-exist'

            { Remove-SymbolicLink -Path $nonExistentPath -ErrorAction Stop } |
            Should -Throw '*not found*'
        }

        It 'Should return error info in PassThru when path does not exist' {
            $nonExistentPath = Join-Path -Path $script:linkDir -ChildPath 'does-not-exist'

            $result = Remove-SymbolicLink -Path $nonExistentPath -PassThru -ErrorAction SilentlyContinue

            $result | Should -Not -BeNullOrEmpty
            $result.Removed | Should -Be $false
            $result.Error | Should -Be 'Path not found'
        }

        It 'Should fail when path is not a symbolic link' {
            # Create a regular file (not a symbolic link)
            $regularFile = Join-Path -Path $script:linkDir -ChildPath 'regular-file.txt'
            'regular content' | Out-File -FilePath $regularFile -Encoding UTF8

            try
            {
                { Remove-SymbolicLink -Path $regularFile -ErrorAction Stop } |
                Should -Throw '*not a symbolic link*'
            }
            finally
            {
                Remove-Item -Path $regularFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should remove regular file when Force is specified (with warning)' {
            # Create a regular file (not a symbolic link)
            $regularFile = Join-Path -Path $script:linkDir -ChildPath 'regular-file-force.txt'
            'regular content' | Out-File -FilePath $regularFile -Encoding UTF8

            Remove-SymbolicLink -Path $regularFile -Force

            Test-Path -Path $regularFile | Should -Be $false
        }
    }

    Context 'Multiple Path Processing' {
        BeforeEach {
            # Create multiple target files
            $script:targetFile1 = Join-Path -Path $script:targetDir -ChildPath 'target1.txt'
            $script:targetFile2 = Join-Path -Path $script:targetDir -ChildPath 'target2.txt'
            $script:targetFile3 = Join-Path -Path $script:targetDir -ChildPath 'target3.txt'

            'content 1' | Out-File -FilePath $script:targetFile1 -Encoding UTF8
            'content 2' | Out-File -FilePath $script:targetFile2 -Encoding UTF8
            'content 3' | Out-File -FilePath $script:targetFile3 -Encoding UTF8

            # Create multiple symbolic links
            $script:linkPath1 = Join-Path -Path $script:linkDir -ChildPath 'link1.txt'
            $script:linkPath2 = Join-Path -Path $script:linkDir -ChildPath 'link2.txt'
            $script:linkPath3 = Join-Path -Path $script:linkDir -ChildPath 'link3.txt'

            New-SymbolicLink -Path $script:linkPath1 -Target $script:targetFile1
            New-SymbolicLink -Path $script:linkPath2 -Target $script:targetFile2
            New-SymbolicLink -Path $script:linkPath3 -Target $script:targetFile3
        }

        AfterEach {
            # Clean up all test files - remove symlinks WITHOUT -Recurse to avoid following links
            @($script:linkPath1, $script:linkPath2, $script:linkPath3) | ForEach-Object {
                if (Test-Path $_)
                {
                    Remove-Item -Path $_ -Force -ErrorAction SilentlyContinue
                }
            }
            Start-Sleep -Milliseconds 50  # Brief pause to ensure symlink removal is complete
            @($script:targetFile1, $script:targetFile2, $script:targetFile3) | ForEach-Object {
                if (Test-Path $_)
                {
                    Remove-Item -Path $_ -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It 'Should remove multiple symbolic links via array parameter' {
            Remove-SymbolicLink -Path $script:linkPath1, $script:linkPath2, $script:linkPath3

            Test-Path -Path $script:linkPath1 | Should -Be $false
            Test-Path -Path $script:linkPath2 | Should -Be $false
            Test-Path -Path $script:linkPath3 | Should -Be $false
        }

        It 'Should preserve all target files when removing multiple links' {
            Remove-SymbolicLink -Path $script:linkPath1, $script:linkPath2, $script:linkPath3

            Test-Path -Path $script:targetFile1 | Should -Be $true
            Test-Path -Path $script:targetFile2 | Should -Be $true
            Test-Path -Path $script:targetFile3 | Should -Be $true
        }

        It 'Should return results for all links when PassThru is specified' {
            $results = Remove-SymbolicLink -Path $script:linkPath1, $script:linkPath2, $script:linkPath3 -PassThru

            $results.Count | Should -Be 3
            $results | ForEach-Object { $_.Removed | Should -Be $true }
        }

        It 'Should process symbolic links via pipeline' {
            $script:linkPath1, $script:linkPath2, $script:linkPath3 | Remove-SymbolicLink

            Test-Path -Path $script:linkPath1 | Should -Be $false
            Test-Path -Path $script:linkPath2 | Should -Be $false
            Test-Path -Path $script:linkPath3 | Should -Be $false
        }
    }

    Context 'WhatIf Support' {
        BeforeEach {
            # Create a target file
            $script:targetFile = Join-Path -Path $script:targetDir -ChildPath 'whatif-target.txt'
            'whatif content' | Out-File -FilePath $script:targetFile -Encoding UTF8

            # Create a symbolic link
            $script:linkPath = Join-Path -Path $script:linkDir -ChildPath 'whatif-link.txt'
            New-SymbolicLink -Path $script:linkPath -Target $script:targetFile
        }

        AfterEach {
            if (Test-Path $script:linkPath)
            {
                Remove-Item -Path $script:linkPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $script:targetFile)
            {
                Remove-Item -Path $script:targetFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should not remove link when WhatIf is specified' {
            Remove-SymbolicLink -Path $script:linkPath -WhatIf

            Test-Path -Path $script:linkPath | Should -Be $true
        }

        It 'Should return WhatIf status in PassThru output' {
            $result = Remove-SymbolicLink -Path $script:linkPath -WhatIf -PassThru

            $result.Removed | Should -Be $false
            $result.Error | Should -Be 'WhatIf mode - not removed'
        }
    }

    Context 'Path Resolution' {
        BeforeEach {
            # Create target and link for relative path testing
            $script:targetFile = Join-Path -Path $script:targetDir -ChildPath 'relative-target.txt'
            'relative content' | Out-File -FilePath $script:targetFile -Encoding UTF8

            $script:linkPath = Join-Path -Path $script:linkDir -ChildPath 'relative-link.txt'
            New-SymbolicLink -Path $script:linkPath -Target $script:targetFile
        }

        AfterEach {
            if (Test-Path $script:linkPath)
            {
                Remove-Item -Path $script:linkPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $script:targetFile)
            {
                Remove-Item -Path $script:targetFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should handle relative paths correctly' {
            Push-Location $script:testRoot
            try
            {
                Remove-SymbolicLink -Path './links/relative-link.txt'

                Test-Path -Path $script:linkPath | Should -Be $false
            }
            finally
            {
                Pop-Location
            }
        }
    }

    Context 'Target Information in PassThru' {
        BeforeEach {
            # Create a target file
            $script:targetFile = Join-Path -Path $script:targetDir -ChildPath 'target-info.txt'
            'target info content' | Out-File -FilePath $script:targetFile -Encoding UTF8

            # Create a symbolic link
            $script:linkPath = Join-Path -Path $script:linkDir -ChildPath 'link-info.txt'
            New-SymbolicLink -Path $script:linkPath -Target $script:targetFile
        }

        AfterEach {
            if (Test-Path $script:linkPath)
            {
                Remove-Item -Path $script:linkPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $script:targetFile)
            {
                Remove-Item -Path $script:targetFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should include target path in PassThru output' -Skip:($PSVersionTable.PSVersion.Major -lt 6) {
            # This test is skipped on PowerShell 5.1 because LinkTarget property
            # may not be available or work consistently
            $result = Remove-SymbolicLink -Path $script:linkPath -PassThru

            $result.Target | Should -Not -BeNullOrEmpty
        }
    }
}
