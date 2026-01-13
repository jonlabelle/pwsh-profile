BeforeAll {
    # Import the function
    . "$PSScriptRoot/../../../Functions/Utilities/New-SymbolicLink.ps1"

    # Import test cleanup utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'New-SymbolicLink Unit Tests' -Tag 'Unit', 'Utilities' {
    BeforeAll {
        # Create a test directory structure
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath 'NewSymbolicLinkTests'
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

    Context 'Creating File Symbolic Links' {
        BeforeEach {
            # Create a target file for testing
            $script:targetFile = Join-Path -Path $script:targetDir -ChildPath 'testfile.txt'
            'test content' | Out-File -FilePath $script:targetFile -Encoding UTF8

            # Define link path
            $script:linkPath = Join-Path -Path $script:linkDir -ChildPath 'link-to-file.txt'
        }

        AfterEach {
            # Clean up links WITHOUT -Recurse to avoid following symlinks to targets
            if (Test-Path $script:linkPath)
            {
                Remove-Item -Path $script:linkPath -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 25
            }
            if (Test-Path $script:targetFile)
            {
                Remove-Item -Path $script:targetFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should create a symbolic link to a file' {
            New-SymbolicLink -Path $script:linkPath -Target $script:targetFile

            Test-Path -Path $script:linkPath | Should -Be $true

            $linkItem = Get-Item -Path $script:linkPath
            $linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint | Should -Be ([System.IO.FileAttributes]::ReparsePoint)
        }

        It 'Should create a symbolic link that points to correct content' {
            New-SymbolicLink -Path $script:linkPath -Target $script:targetFile

            $content = Get-Content -Path $script:linkPath
            $content | Should -Be 'test content'
        }

        It 'Should return FileInfo when PassThru is specified' {
            $result = New-SymbolicLink -Path $script:linkPath -Target $script:targetFile -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'link-to-file.txt'
            $result.Attributes -band [System.IO.FileAttributes]::ReparsePoint | Should -Be ([System.IO.FileAttributes]::ReparsePoint)
        }

        It 'Should fail when target does not exist and Force is not specified' {
            $nonExistentTarget = Join-Path -Path $script:targetDir -ChildPath 'does-not-exist.txt'

            { New-SymbolicLink -Path $script:linkPath -Target $nonExistentTarget -ErrorAction Stop } |
            Should -Throw '*does not exist*'
        }

        It 'Should create link to non-existent target when Force is specified' {
            $nonExistentTarget = Join-Path -Path $script:targetDir -ChildPath 'will-exist-later.txt'

            New-SymbolicLink -Path $script:linkPath -Target $nonExistentTarget -Force

            Test-Path -Path $script:linkPath | Should -Be $true
            $linkItem = Get-Item -Path $script:linkPath
            $linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint | Should -Be ([System.IO.FileAttributes]::ReparsePoint)
        }

        It 'Should fail when path already exists and Force is not specified' {
            # Create the link first
            New-SymbolicLink -Path $script:linkPath -Target $script:targetFile

            # Try to create another link at the same path
            { New-SymbolicLink -Path $script:linkPath -Target $script:targetFile -ErrorAction Stop } |
            Should -Throw '*already exists*'
        }

        It 'Should overwrite existing link when Force is specified' {
            # Create initial link
            New-SymbolicLink -Path $script:linkPath -Target $script:targetFile

            # Create a different target
            $targetFile2 = Join-Path -Path $script:targetDir -ChildPath 'testfile2.txt'
            'different content' | Out-File -FilePath $targetFile2 -Encoding UTF8

            # Overwrite with new link
            New-SymbolicLink -Path $script:linkPath -Target $targetFile2 -Force

            $content = Get-Content -Path $script:linkPath
            $content | Should -Be 'different content'

            # Cleanup second target
            Remove-Item -Path $targetFile2 -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Creating Directory Symbolic Links' {
        BeforeEach {
            # Create a target directory for testing
            $script:targetSubDir = Join-Path -Path $script:targetDir -ChildPath 'subdir'
            New-Item -Path $script:targetSubDir -ItemType Directory -Force | Out-Null

            # Create a file inside the target directory
            $fileInDir = Join-Path -Path $script:targetSubDir -ChildPath 'file-in-dir.txt'
            'content in subdir' | Out-File -FilePath $fileInDir -Encoding UTF8

            # Define link path
            $script:dirLinkPath = Join-Path -Path $script:linkDir -ChildPath 'link-to-dir'
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

        It 'Should create a symbolic link to a directory' {
            New-SymbolicLink -Path $script:dirLinkPath -Target $script:targetSubDir

            Test-Path -Path $script:dirLinkPath | Should -Be $true

            $linkItem = Get-Item -Path $script:dirLinkPath
            $linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint | Should -Be ([System.IO.FileAttributes]::ReparsePoint)
        }

        It 'Should allow access to files through directory symbolic link' {
            New-SymbolicLink -Path $script:dirLinkPath -Target $script:targetSubDir

            $fileViaLink = Join-Path -Path $script:dirLinkPath -ChildPath 'file-in-dir.txt'
            Test-Path -Path $fileViaLink | Should -Be $true

            $content = Get-Content -Path $fileViaLink
            $content | Should -Be 'content in subdir'
        }

        It 'Should auto-detect directory type' {
            $result = New-SymbolicLink -Path $script:dirLinkPath -Target $script:targetSubDir -PassThru

            $result.PSIsContainer | Should -Be $true
        }
    }

    Context 'Parent Directory Creation' {
        It 'Should create parent directories if they do not exist' {
            $targetFile = Join-Path -Path $script:targetDir -ChildPath 'target-for-nested.txt'
            'nested test' | Out-File -FilePath $targetFile -Encoding UTF8

            $nestedLinkPath = Join-Path -Path $script:linkDir -ChildPath 'nested/path/to/link.txt'

            New-SymbolicLink -Path $nestedLinkPath -Target $targetFile

            Test-Path -Path $nestedLinkPath | Should -Be $true

            # Cleanup
            $nestedParent = Join-Path -Path $script:linkDir -ChildPath 'nested'
            Remove-Item -Path $nestedParent -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $targetFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'ItemType Parameter' {
        BeforeEach {
            $script:linkPath = Join-Path -Path $script:linkDir -ChildPath 'typed-link'
        }

        AfterEach {
            if (Test-Path $script:linkPath)
            {
                Remove-Item -Path $script:linkPath -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should create file symbolic link when ItemType is File' {
            $targetFile = Join-Path -Path $script:targetDir -ChildPath 'typed-target.txt'
            'typed content' | Out-File -FilePath $targetFile -Encoding UTF8

            New-SymbolicLink -Path $script:linkPath -Target $targetFile -ItemType File

            $linkItem = Get-Item -Path $script:linkPath
            $linkItem.PSIsContainer | Should -Be $false

            Remove-Item -Path $targetFile -Force -ErrorAction SilentlyContinue
        }

        It 'Should create directory symbolic link when ItemType is Directory' {
            $targetSubDir = Join-Path -Path $script:targetDir -ChildPath 'typed-subdir'
            New-Item -Path $targetSubDir -ItemType Directory -Force | Out-Null

            New-SymbolicLink -Path $script:linkPath -Target $targetSubDir -ItemType Directory

            $linkItem = Get-Item -Path $script:linkPath
            $linkItem.PSIsContainer | Should -Be $true

            Remove-Item -Path $targetSubDir -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'WhatIf Support' {
        It 'Should not create link when WhatIf is specified' {
            $targetFile = Join-Path -Path $script:targetDir -ChildPath 'whatif-target.txt'
            'whatif content' | Out-File -FilePath $targetFile -Encoding UTF8

            $linkPath = Join-Path -Path $script:linkDir -ChildPath 'whatif-link.txt'

            New-SymbolicLink -Path $linkPath -Target $targetFile -WhatIf

            Test-Path -Path $linkPath | Should -Be $false

            Remove-Item -Path $targetFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Path Resolution' {
        It 'Should handle relative paths correctly' {
            $targetFile = Join-Path -Path $script:targetDir -ChildPath 'relative-target.txt'
            'relative content' | Out-File -FilePath $targetFile -Encoding UTF8

            $linkPath = Join-Path -Path $script:linkDir -ChildPath 'relative-link.txt'

            # Use relative paths from the test root
            Push-Location $script:testRoot
            try
            {
                New-SymbolicLink -Path './links/relative-link.txt' -Target './targets/relative-target.txt'

                Test-Path -Path $linkPath | Should -Be $true
            }
            finally
            {
                Pop-Location
            }

            # Cleanup
            Remove-Item -Path $linkPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $targetFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Error Handling' {
        It 'Should provide clear error when path is null or empty' {
            { New-SymbolicLink -Path '' -Target 'sometarget' -ErrorAction Stop } |
            Should -Throw
        }

        It 'Should provide clear error when target is null or empty' {
            { New-SymbolicLink -Path 'somepath' -Target '' -ErrorAction Stop } |
            Should -Throw
        }
    }
}
