BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../Functions/Utilities/Sync-Directory.ps1"

    # Import test utilities
    . "$PSScriptRoot/../TestCleanupUtilities.ps1"
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
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "sync-integration-$(Get-Random)"
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
            $Source = Join-Path $script:TestRoot 'basic-source'
            $Dest = Join-Path $script:TestRoot 'basic-dest'

            try
            {
                # Create source directory with files
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                'File 1 content' | Out-File (Join-Path $Source 'file1.txt')
                'File 2 content' | Out-File (Join-Path $Source 'file2.txt')

                # Sync
                $Result = Sync-Directory -Source $Source -Destination $Dest

                # Verify
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path $Dest 'file1.txt') | Should -BeTrue
                Test-Path (Join-Path $Dest 'file2.txt') | Should -BeTrue
                Get-Content (Join-Path $Dest 'file1.txt') | Should -Be 'File 1 content'
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }

        It 'Should synchronize nested directory structure' {
            $Source = Join-Path $script:TestRoot 'nested-source'
            $Dest = Join-Path $script:TestRoot 'nested-dest'

            try
            {
                # Create nested structure
                $SubDir1 = Join-Path $Source 'subdir1'
                $SubDir2 = Join-Path $SubDir1 'subdir2'
                New-Item -ItemType Directory -Path $SubDir2 -Force | Out-Null

                'Root file' | Out-File (Join-Path $Source 'root.txt')
                'Level 1 file' | Out-File (Join-Path $SubDir1 'level1.txt')
                'Level 2 file' | Out-File (Join-Path $SubDir2 'level2.txt')

                # Sync
                $Result = Sync-Directory -Source $Source -Destination $Dest

                # Verify
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path $Dest 'root.txt') | Should -BeTrue
                Test-Path (Join-Path $Dest 'subdir1' 'level1.txt') | Should -BeTrue
                Test-Path (Join-Path $Dest 'subdir1' 'subdir2' 'level2.txt') | Should -BeTrue
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }

        It 'Should handle empty directories' {
            $Source = Join-Path $script:TestRoot 'empty-source'
            $Dest = Join-Path $script:TestRoot 'empty-dest'

            try
            {
                # Create source with empty subdirectory
                $EmptyDir = Join-Path $Source 'empty-subdir'
                New-Item -ItemType Directory -Path $EmptyDir -Force | Out-Null
                'file.txt' | Out-File (Join-Path $Source 'file.txt')

                # Sync
                $Result = Sync-Directory -Source $Source -Destination $Dest

                # Verify - both tools should preserve empty directories
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path $Dest 'empty-subdir') | Should -BeTrue
                Test-Path (Join-Path $Dest 'file.txt') | Should -BeTrue
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
            $Source = Join-Path $script:TestRoot 'incremental-source'
            $Dest = Join-Path $script:TestRoot 'incremental-dest'

            try
            {
                # Initial sync
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                'Original content' | Out-File (Join-Path $Source 'file1.txt')

                $Result1 = Sync-Directory -Source $Source -Destination $Dest
                $Result1.Success | Should -BeTrue

                # Modify source and add new file
                Start-Sleep -Seconds 1 # Ensure timestamp difference (rsync uses seconds)
                'Modified content' | Out-File (Join-Path $Source 'file1.txt') -Force
                (Get-Item (Join-Path $Source 'file1.txt')).LastWriteTime = (Get-Date).AddSeconds(2)
                'New file' | Out-File (Join-Path $Source 'file2.txt')

                # Second sync
                $Result2 = Sync-Directory -Source $Source -Destination $Dest
                $Result2.Success | Should -BeTrue

                # Verify both files exist with correct content
                Get-Content (Join-Path $Dest 'file1.txt') | Should -Be 'Modified content'
                Get-Content (Join-Path $Dest 'file2.txt') | Should -Be 'New file'
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
            $Source = Join-Path $script:TestRoot 'mirror-source'
            $Dest = Join-Path $script:TestRoot 'mirror-dest'

            try
            {
                # Create initial sync
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                New-Item -ItemType Directory -Path $Dest -Force | Out-Null

                'Keep this' | Out-File (Join-Path $Source 'keep.txt')
                'Keep this' | Out-File (Join-Path $Dest 'keep.txt')
                'Delete this' | Out-File (Join-Path $Dest 'delete.txt')

                # Sync with delete
                $Result = Sync-Directory -Source $Source -Destination $Dest -Delete

                # Verify
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path $Dest 'keep.txt') | Should -BeTrue
                Test-Path (Join-Path $Dest 'delete.txt') | Should -BeFalse
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }

        It 'Should preserve extra files in destination when -Delete is NOT used' {
            $Source = Join-Path $script:TestRoot 'preserve-source'
            $Dest = Join-Path $script:TestRoot 'preserve-dest'

            try
            {
                # Create initial sync
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                New-Item -ItemType Directory -Path $Dest -Force | Out-Null

                'Source file' | Out-File (Join-Path $Source 'source.txt')
                'Extra file' | Out-File (Join-Path $Dest 'extra.txt')

                # Sync without delete
                $Result = Sync-Directory -Source $Source -Destination $Dest

                # Verify both files exist
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path $Dest 'source.txt') | Should -BeTrue
                Test-Path (Join-Path $Dest 'extra.txt') | Should -BeTrue
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
            $Source = Join-Path $script:TestRoot 'exclude-source'
            $Dest = Join-Path $script:TestRoot 'exclude-dest'

            try
            {
                # Create source with various files
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                'Include this' | Out-File (Join-Path $Source 'include.txt')
                'Exclude this' | Out-File (Join-Path $Source 'exclude.log')
                'Also exclude' | Out-File (Join-Path $Source 'temp.tmp')

                # Sync with exclusions
                $Result = Sync-Directory -Source $Source -Destination $Dest -Exclude '*.log', '*.tmp'

                # Verify
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path $Dest 'include.txt') | Should -BeTrue
                Test-Path (Join-Path $Dest 'exclude.log') | Should -BeFalse
                Test-Path (Join-Path $Dest 'temp.tmp') | Should -BeFalse
            }
            finally
            {
                if (Test-Path $Source) { Remove-Item -Path $Source -Recurse -Force }
                if (Test-Path $Dest) { Remove-Item -Path $Dest -Recurse -Force }
            }
        }

        It 'Should exclude directories matching patterns' {
            $Source = Join-Path $script:TestRoot 'exclude-dir-source'
            $Dest = Join-Path $script:TestRoot 'exclude-dir-dest'

            try
            {
                # Create source with directories
                $IncludeDir = Join-Path $Source 'include-dir'
                $ExcludeDir = Join-Path $Source 'node_modules'
                New-Item -ItemType Directory -Path $IncludeDir -Force | Out-Null
                New-Item -ItemType Directory -Path $ExcludeDir -Force | Out-Null

                'Include' | Out-File (Join-Path $IncludeDir 'file.txt')
                'Exclude' | Out-File (Join-Path $ExcludeDir 'package.json')

                # Sync with directory exclusion
                $Result = Sync-Directory -Source $Source -Destination $Dest -Exclude 'node_modules'

                # Verify
                $Result.Success | Should -BeTrue
                Test-Path (Join-Path $Dest 'include-dir') | Should -BeTrue
                Test-Path (Join-Path $Dest 'node_modules') | Should -BeFalse
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
            $Source = Join-Path $script:TestRoot 'source with spaces'
            $Dest = Join-Path $script:TestRoot 'dest with spaces'

            try
            {
                New-Item -ItemType Directory -Path $Source -Force | Out-Null
                'Content' | Out-File (Join-Path $Source 'file with spaces.txt')

                $Result = Sync-Directory -Source $Source -Destination $Dest

                $Result.Success | Should -BeTrue
                Test-Path (Join-Path $Dest 'file with spaces.txt') | Should -BeTrue
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
            $Source = Join-Path $script:TestRoot 'many-files-source'
            $Dest = Join-Path $script:TestRoot 'many-files-dest'

            try
            {
                New-Item -ItemType Directory -Path $Source -Force | Out-Null

                # Create 50 files
                1..50 | ForEach-Object {
                    "Content $_" | Out-File (Join-Path $Source "file$_.txt")
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
            $NonExistent = Join-Path $script:TestRoot 'does-not-exist'
            $Dest = Join-Path $script:TestRoot 'error-dest'

            { Sync-Directory -Source $NonExistent -Destination $Dest -ErrorAction Stop } |
            Should -Throw '*does not exist*'
        }
    }
}
