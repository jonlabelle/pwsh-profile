BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../../Functions/Utilities/Sync-Directory.ps1"

    # Import test utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Sync-Directory Integration Tests' -Tag 'Integration' {
    BeforeAll {
        # Detect platform
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $script:IsWindowsPlatform = $true
        }
        else
        {
            $script:IsWindowsPlatform = $IsWindows
        }

        # Create base test directory
        $script:TestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "sync-integration-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    }

    AfterAll {
        # Cleanup test directory
        if (Test-Path $script:TestRoot)
        {
            Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Basic Synchronization' {
        It 'Should synchronize files from source to destination' {
            $Source = Join-Path -Path $script:TestRoot -ChildPath 'basic-source'
            $Dest = Join-Path -Path $script:TestRoot -ChildPath 'basic-dest'

            try
            {
                # Create source directory with files
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                'File 1 content' | Out-File (Join-Path -Path $Source -ChildPath 'file1.txt')
                'File 2 content' | Out-File (Join-Path -Path $Source -ChildPath 'file2.txt')

                # Sync
                $Result = Sync-Directory -Source $Source -Destination $Dest

                # Verify
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'file1.txt') | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'file2.txt') | Should -BeTrue
                Get-Content (Join-Path -Path $Dest -ChildPath 'file1.txt') | Should -Be 'File 1 content'
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }

        It 'Should synchronize nested directory structure' {
            $Source = Join-Path -Path $script:TestRoot -ChildPath 'nested-source'
            $Dest = Join-Path -Path $script:TestRoot -ChildPath 'nested-dest'

            try
            {
                # Create nested structure
                $SubDir1 = Join-Path -Path $Source -ChildPath 'subdir1'
                $SubDir2 = Join-Path -Path $SubDir1 -ChildPath 'subdir2'
                New-Item -ItemType Directory -Path $SubDir2 -Force | Out-Null

                'Root file' | Out-File (Join-Path -Path $Source -ChildPath 'root.txt')
                'Level 1 file' | Out-File (Join-Path -Path $SubDir1 -ChildPath 'level1.txt')
                'Level 2 file' | Out-File (Join-Path -Path $SubDir2 -ChildPath 'level2.txt')

                # Sync
                $Result = Sync-Directory -Source $Source -Destination $Dest

                # Verify
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'root.txt') | Should -BeTrue
                Test-Path (Join-Path -Path (Join-Path -Path $Dest -ChildPath 'subdir1') -ChildPath 'level1.txt') | Should -BeTrue
                Test-Path (Join-Path -Path (Join-Path -Path (Join-Path -Path $Dest -ChildPath 'subdir1') -ChildPath 'subdir2') -ChildPath 'level2.txt') | Should -BeTrue
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }

        It 'Should handle empty directories' {
            $Source = Join-Path -Path $script:TestRoot -ChildPath 'empty-source'
            $Dest = Join-Path -Path $script:TestRoot -ChildPath 'empty-dest'

            try
            {
                # Create source with empty subdirectory
                $EmptyDir = Join-Path -Path $Source -ChildPath 'empty-subdir'
                New-Item -ItemType Directory -Path $EmptyDir -Force | Out-Null
                'file.txt' | Out-File (Join-Path -Path $Source -ChildPath 'file.txt')

                # Sync
                $Result = Sync-Directory -Source $Source -Destination $Dest

                # Verify - both tools should preserve empty directories
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'empty-subdir') | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'file.txt') | Should -BeTrue
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }
    }

    Context 'Incremental Synchronization' {
        It 'Should only copy new or modified files on subsequent syncs' {
            $Source = Join-Path -Path $script:TestRoot -ChildPath 'incremental-source'
            $Dest = Join-Path -Path $script:TestRoot -ChildPath 'incremental-dest'

            try
            {
                # Initial sync
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                'Original content' | Out-File (Join-Path -Path $Source -ChildPath 'file1.txt')

                $Result1 = Sync-Directory -Source $Source -Destination $Dest
                $Result1.Success | Should -BeTrue

                # Modify source and add new file
                Start-Sleep -Seconds 1 # Ensure timestamp difference (rsync uses seconds)
                'Modified content' | Out-File (Join-Path -Path $Source -ChildPath 'file1.txt') -Force
                (Get-Item (Join-Path -Path $Source -ChildPath 'file1.txt')).LastWriteTime = (Get-Date).AddSeconds(2)
                'New file' | Out-File (Join-Path -Path $Source -ChildPath 'file2.txt')

                # Second sync
                $Result2 = Sync-Directory -Source $Source -Destination $Dest
                $Result2.Success | Should -BeTrue

                # Verify both files exist with correct content
                Get-Content (Join-Path -Path $Dest -ChildPath 'file1.txt') | Should -Be 'Modified content'
                Get-Content (Join-Path -Path $Dest -ChildPath 'file2.txt') | Should -Be 'New file'
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }
    }

    Context 'Mirror Mode (Delete)' {
        It 'Should delete files in destination not present in source when -Delete is used' {
            $Source = Join-Path -Path $script:TestRoot -ChildPath 'mirror-source'
            $Dest = Join-Path -Path $script:TestRoot -ChildPath 'mirror-dest'

            try
            {
                # Create initial sync
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                New-Item -ItemType Directory -Path $Dest -Force | Out-Null

                'Keep this' | Out-File (Join-Path -Path $Source -ChildPath 'keep.txt')
                'Keep this' | Out-File (Join-Path -Path $Dest -ChildPath 'keep.txt')
                'Delete this' | Out-File (Join-Path -Path $Dest -ChildPath 'delete.txt')

                # Sync with delete
                $Result = Sync-Directory -Source $Source -Destination $Dest -Delete

                # Verify
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'keep.txt') | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'delete.txt') | Should -BeFalse
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }

        It 'Should preserve extra files in destination when -Delete is NOT used' {
            $Source = Join-Path -Path $script:TestRoot -ChildPath 'preserve-source'
            $Dest = Join-Path -Path $script:TestRoot -ChildPath 'preserve-dest'

            try
            {
                # Create initial sync
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                New-Item -ItemType Directory -Path $Dest -Force | Out-Null

                'Source file' | Out-File (Join-Path -Path $Source -ChildPath 'source.txt')
                'Extra file' | Out-File (Join-Path -Path $Dest -ChildPath 'extra.txt')

                # Sync without delete
                $Result = Sync-Directory -Source $Source -Destination $Dest

                # Verify both files exist
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'source.txt') | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'extra.txt') | Should -BeTrue
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }
    }

    Context 'Exclusion Patterns' {
        It 'Should exclude files matching patterns' {
            $Source = Join-Path -Path $script:TestRoot -ChildPath 'exclude-source'
            $Dest = Join-Path -Path $script:TestRoot -ChildPath 'exclude-dest'

            try
            {
                # Create source with various files
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                'Include this' | Out-File (Join-Path -Path $Source -ChildPath 'include.txt')
                'Exclude this' | Out-File (Join-Path -Path $Source -ChildPath 'exclude.log')
                'Also exclude' | Out-File (Join-Path -Path $Source -ChildPath 'temp.tmp')

                # Sync with exclusions
                $Result = Sync-Directory -Source $Source -Destination $Dest -Exclude '*.log', '*.tmp'

                # Verify
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'include.txt') | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'exclude.log') | Should -BeFalse
                Test-Path (Join-Path -Path $Dest -ChildPath 'temp.tmp') | Should -BeFalse
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }

        It 'Should exclude directories matching patterns' {
            $Source = Join-Path -Path $script:TestRoot -ChildPath 'exclude-dir-source'
            $Dest = Join-Path -Path $script:TestRoot -ChildPath 'exclude-dir-dest'

            try
            {
                # Create source with directories
                $IncludeDir = Join-Path -Path $Source -ChildPath 'include-dir'
                $ExcludeDir = Join-Path -Path $Source -ChildPath 'node_modules'
                New-Item -ItemType Directory -Path $IncludeDir -Force | Out-Null
                New-Item -ItemType Directory -Path $ExcludeDir -Force | Out-Null

                'Include' | Out-File (Join-Path -Path $IncludeDir -ChildPath 'file.txt')
                'Exclude' | Out-File (Join-Path -Path $ExcludeDir -ChildPath 'package.json')

                # Sync with directory exclusion
                $Result = Sync-Directory -Source $Source -Destination $Dest -Exclude 'node_modules'

                # Verify
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'include-dir') | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'node_modules') | Should -BeFalse
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }
    }

    Context 'Special Characters in Paths' {
        It 'Should handle paths with spaces' {
            $Source = Join-Path -Path $script:TestRoot -ChildPath 'source with spaces'
            $Dest = Join-Path -Path $script:TestRoot -ChildPath 'dest with spaces'

            try
            {
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                'Content' | Out-File (Join-Path -Path $Source -ChildPath 'file with spaces.txt')

                $Result = Sync-Directory -Source $Source -Destination $Dest

                $Result.Success | Should -BeTrue
                Test-Path (Join-Path -Path $Dest -ChildPath 'file with spaces.txt') | Should -BeTrue
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }
    }

    Context 'Large File Operations' {
        It 'Should handle multiple files efficiently' {
            $Source = Join-Path -Path $script:TestRoot -ChildPath 'many-files-source'
            $Dest = Join-Path -Path $script:TestRoot -ChildPath 'many-files-dest'

            try
            {
                New-Item -ItemType Directory -Path $Source -Force | Out-Null

                # Create 50 files
                1..50 | ForEach-Object {
                    "Content $_" | Out-File (Join-Path -Path $Source -ChildPath "file$_.txt")
                }

                $Result = Sync-Directory -Source $Source -Destination $Dest

                $Result.Success | Should -BeTrue
                (Get-ChildItem -Path $Dest -File).Count | Should -Be 50
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }
    }

    Context 'Error Handling' {
        It 'Should return false for non-existent source' {
            $NonExistent = Join-Path -Path $script:TestRoot -ChildPath 'does-not-exist'
            $Dest = Join-Path -Path $script:TestRoot -ChildPath 'error-dest'

            { Sync-Directory -Source $NonExistent -Destination $Dest -ErrorAction Stop } |
            Should -Throw '*does not exist*'
        }
    }
}
