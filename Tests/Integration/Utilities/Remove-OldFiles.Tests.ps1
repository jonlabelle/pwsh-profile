#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Remove-OldFiles function.

.DESCRIPTION
    Integration tests that verify Remove-OldFiles works correctly in real-world scenarios
    with actual file systems, file age manipulation, and directory cleanup.

.NOTES
    These tests verify:
    - Actual file deletion based on age
    - Directory structure navigation
    - Include/Exclude pattern filtering
    - Empty directory cleanup
    - Recursive operations
    - Force parameter with read-only files
    - Space calculation accuracy
    - Pipeline input processing
    - Error handling with invalid paths
#>

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../../Functions/Utilities/Remove-OldFiles.ps1"

    # Import cleanup utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Remove-OldFiles Integration Tests' {
    Context 'Basic File Deletion by Age' {
        BeforeAll {
            $script:testDir = Join-Path $TestDrive 'AgeTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            # Create old files (30 days old)
            1..3 | ForEach-Object {
                $file = Join-Path $script:testDir "old_file_$_.txt"
                "Old content $_" | Set-Content -Path $file
                (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-30)
            }

            # Create recent files (3 days old)
            1..2 | ForEach-Object {
                $file = Join-Path $script:testDir "recent_file_$_.txt"
                "Recent content $_" | Set-Content -Path $file
                (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-3)
            }

            # Create current files
            'current.txt' | ForEach-Object {
                $file = Join-Path $script:testDir $_
                'Current content' | Set-Content -Path $file
            }
        }

        AfterAll {
            Remove-TestDirectory -Path $script:testDir
        }

        It 'Should remove only files older than threshold' {
            $result = Remove-OldFiles -Path $script:testDir -OlderThan 7 -Confirm:$false

            $result.FilesRemoved | Should -Be 3

            # Verify old files are gone
            Test-Path (Join-Path $script:testDir 'old_file_1.txt') | Should -Be $false
            Test-Path (Join-Path $script:testDir 'old_file_2.txt') | Should -Be $false
            Test-Path (Join-Path $script:testDir 'old_file_3.txt') | Should -Be $false

            # Verify recent and current files remain
            Test-Path (Join-Path $script:testDir 'recent_file_1.txt') | Should -Be $true
            Test-Path (Join-Path $script:testDir 'current.txt') | Should -Be $true
        }

        It 'Should calculate space freed correctly' {
            # Create new test directory
            $spaceTestDir = Join-Path $TestDrive 'SpaceTest'
            New-Item -ItemType Directory -Path $spaceTestDir -Force | Out-Null

            # Create file with known size (1MB to ensure measurable space)
            $file = Join-Path $spaceTestDir 'large_old_file.txt'
            $content = 'x' * (1024 * 1024)  # 1MB
            $content | Set-Content -Path $file -NoNewline
            (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-10)

            $result = Remove-OldFiles -Path $spaceTestDir -OlderThan 5 -Confirm:$false

            $result.TotalSpaceFreed | Should -BeGreaterThan 1000000
            $result.TotalSpaceFreedMB | Should -BeGreaterThan 0.9

            Remove-TestDirectory -Path $spaceTestDir
        }
    }

    Context 'Time Unit Variations' {
        BeforeAll {
            $script:timeTestDir = Join-Path $TestDrive 'TimeUnitTests'
            New-Item -ItemType Directory -Path $script:timeTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:timeTestDir
        }

        It 'Should work with Hours unit' {
            $file = Join-Path $script:timeTestDir 'old_hours.txt'
            'test' | Set-Content -Path $file
            (Get-Item $file).LastWriteTime = (Get-Date).AddHours(-48)

            $result = Remove-OldFiles -Path $script:timeTestDir -OlderThan 24 -Unit Hours -Confirm:$false

            $result.FilesRemoved | Should -Be 1
            Test-Path $file | Should -Be $false
        }

        It 'Should work with Days unit' {
            $file = Join-Path $script:timeTestDir 'old_days.txt'
            'test' | Set-Content -Path $file
            (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-15)

            $result = Remove-OldFiles -Path $script:timeTestDir -OlderThan 10 -Unit Days -Confirm:$false

            $result.FilesRemoved | Should -Be 1
            Test-Path $file | Should -Be $false
        }

        It 'Should work with Months unit' {
            $file = Join-Path $script:timeTestDir 'old_months.txt'
            'test' | Set-Content -Path $file
            (Get-Item $file).LastWriteTime = (Get-Date).AddMonths(-6)

            $result = Remove-OldFiles -Path $script:timeTestDir -OlderThan 3 -Unit Months -Confirm:$false

            $result.FilesRemoved | Should -Be 1
            Test-Path $file | Should -Be $false
        }

        It 'Should work with Years unit' {
            $file = Join-Path $script:timeTestDir 'old_years.txt'
            'test' | Set-Content -Path $file
            (Get-Item $file).LastWriteTime = (Get-Date).AddYears(-2)

            $result = Remove-OldFiles -Path $script:timeTestDir -OlderThan 1 -Unit Years -Confirm:$false

            $result.FilesRemoved | Should -Be 1
            Test-Path $file | Should -Be $false
        }
    }

    Context 'Include and Exclude Patterns' {
        BeforeAll {
            $script:filterDir = Join-Path $TestDrive 'FilterTests'
            New-Item -ItemType Directory -Path $script:filterDir -Force | Out-Null

            # Create various old file types
            @('file1.log', 'file2.txt', 'file3.log', 'file4.tmp', 'keep.log') | ForEach-Object {
                $file = Join-Path $script:filterDir $_
                'content' | Set-Content -Path $file
                (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-30)
            }
        }

        AfterAll {
            Remove-TestDirectory -Path $script:filterDir
        }

        It 'Should only remove files matching Include pattern' {
            $result = Remove-OldFiles -Path $script:filterDir -OlderThan 7 -Include '*.log' -Confirm:$false

            $result.FilesRemoved | Should -Be 3

            # .log files should be removed
            Test-Path (Join-Path $script:filterDir 'file1.log') | Should -Be $false
            Test-Path (Join-Path $script:filterDir 'file3.log') | Should -Be $false

            # Other files should remain
            Test-Path (Join-Path $script:filterDir 'file2.txt') | Should -Be $true
            Test-Path (Join-Path $script:filterDir 'file4.tmp') | Should -Be $true
        }

        It 'Should exclude files matching Exclude pattern' {
            # Recreate files for this test
            $excludeTestDir = Join-Path $TestDrive 'ExcludeTest'
            New-Item -ItemType Directory -Path $excludeTestDir -Force | Out-Null

            @('old1.txt', 'old2.txt', 'keep1.txt') | ForEach-Object {
                $file = Join-Path $excludeTestDir $_
                'content' | Set-Content -Path $file
                (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-30)
            }

            $result = Remove-OldFiles -Path $excludeTestDir -OlderThan 7 -Exclude 'keep*' -Confirm:$false

            $result.FilesRemoved | Should -Be 2
            Test-Path (Join-Path $excludeTestDir 'keep1.txt') | Should -Be $true

            Remove-TestDirectory -Path $excludeTestDir
        }

        It 'Should support multiple Include patterns' {
            $multiIncludeDir = Join-Path $TestDrive 'MultiInclude'
            New-Item -ItemType Directory -Path $multiIncludeDir -Force | Out-Null

            @('file1.log', 'file2.tmp', 'file3.txt', 'file4.log', 'file5.tmp') | ForEach-Object {
                $file = Join-Path $multiIncludeDir $_
                'content' | Set-Content -Path $file
                (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-30)
            }

            $result = Remove-OldFiles -Path $multiIncludeDir -OlderThan 7 -Include @('*.log', '*.tmp') -Confirm:$false

            $result.FilesRemoved | Should -Be 4
            Test-Path (Join-Path $multiIncludeDir 'file3.txt') | Should -Be $true

            Remove-TestDirectory -Path $multiIncludeDir
        }
    }

    Context 'Directory Exclusion' {
        BeforeAll {
            $script:dirExcludeTest = Join-Path $TestDrive 'DirExcludeTest'
            New-Item -ItemType Directory -Path $script:dirExcludeTest -Force | Out-Null

            # Create directory structure
            $keepDir = Join-Path $script:dirExcludeTest 'KeepMe'
            $processDir = Join-Path $script:dirExcludeTest 'ProcessMe'
            New-Item -ItemType Directory -Path $keepDir -Force | Out-Null
            New-Item -ItemType Directory -Path $processDir -Force | Out-Null

            # Create old files in both directories
            $file1 = Join-Path $keepDir 'file_keep.txt'
            $file2 = Join-Path $processDir 'file_process.txt'
            'keep' | Set-Content -Path $file1
            'process' | Set-Content -Path $file2
            (Get-Item $file1).LastWriteTime = (Get-Date).AddDays(-30)
            (Get-Item $file2).LastWriteTime = (Get-Date).AddDays(-30)
        }

        AfterAll {
            Remove-TestDirectory -Path $script:dirExcludeTest
        }

        It 'Should exclude specified directories from processing' {
            $result = Remove-OldFiles -Path $script:dirExcludeTest -OlderThan 7 -ExcludeDirectory 'KeepMe' -Confirm:$false

            $result.FilesRemoved | Should -Be 1

            # File in excluded directory should remain
            Test-Path (Join-Path $script:dirExcludeTest 'KeepMe/file_keep.txt') | Should -Be $true

            # File in processed directory should be removed
            Test-Path (Join-Path $script:dirExcludeTest 'ProcessMe/file_process.txt') | Should -Be $false
        }
    }

    Context 'Empty Directory Removal' {
        BeforeAll {
            $script:emptyDirTest = Join-Path $TestDrive 'EmptyDirTest'
            New-Item -ItemType Directory -Path $script:emptyDirTest -Force | Out-Null

            # Create nested directory structure with old files
            $subDir1 = Join-Path $script:emptyDirTest 'SubDir1'
            $subDir2 = Join-Path $subDir1 'SubDir2'
            New-Item -ItemType Directory -Path $subDir1 -Force | Out-Null
            New-Item -ItemType Directory -Path $subDir2 -Force | Out-Null

            # Add old file in deepest directory
            $file = Join-Path $subDir2 'old_file.txt'
            'content' | Set-Content -Path $file
            (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-30)

            # Create another directory with both old and new files
            $mixedDir = Join-Path $script:emptyDirTest 'MixedDir'
            New-Item -ItemType Directory -Path $mixedDir -Force | Out-Null

            $oldFile = Join-Path $mixedDir 'old.txt'
            $newFile = Join-Path $mixedDir 'new.txt'
            'old' | Set-Content -Path $oldFile
            'new' | Set-Content -Path $newFile
            (Get-Item $oldFile).LastWriteTime = (Get-Date).AddDays(-30)
        }

        AfterAll {
            Remove-TestDirectory -Path $script:emptyDirTest
        }

        It 'Should remove empty directories when specified' {
            $result = Remove-OldFiles -Path $script:emptyDirTest -OlderThan 7 -RemoveEmptyDirectories -Confirm:$false -ErrorAction SilentlyContinue

            $result.FilesRemoved | Should -Be 2
            $result.DirectoriesRemoved | Should -BeGreaterOrEqual 2

            # Empty directories should be removed
            Test-Path (Join-Path $script:emptyDirTest 'SubDir1/SubDir2') | Should -Be $false
            Test-Path (Join-Path $script:emptyDirTest 'SubDir1') | Should -Be $false

            # Directory with remaining files should exist
            Test-Path (Join-Path $script:emptyDirTest 'MixedDir') | Should -Be $true
            Test-Path (Join-Path $script:emptyDirTest 'MixedDir/new.txt') | Should -Be $true
        }

        It 'Should not remove directories when flag not set' {
            # Create new test structure
            $noRemoveDir = Join-Path $TestDrive 'NoRemoveDir'
            $subDir = Join-Path $noRemoveDir 'SubDir'
            New-Item -ItemType Directory -Path $subDir -Force | Out-Null

            $file = Join-Path $subDir 'old.txt'
            'content' | Set-Content -Path $file
            (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-30)

            $result = Remove-OldFiles -Path $noRemoveDir -OlderThan 7 -Confirm:$false

            $result.FilesRemoved | Should -Be 1
            $result.DirectoriesRemoved | Should -Be 0

            # Directory should still exist (empty)
            Test-Path $subDir | Should -Be $true

            Remove-TestDirectory -Path $noRemoveDir
        }
    }

    Context 'Force Parameter with Read-Only Files' {
        BeforeAll {
            $script:forceTestDir = Join-Path $TestDrive 'ForceTest'
            New-Item -ItemType Directory -Path $script:forceTestDir -Force | Out-Null

            # Create read-only file
            $readOnlyFile = Join-Path $script:forceTestDir 'readonly.txt'
            'readonly content' | Set-Content -Path $readOnlyFile
            (Get-Item $readOnlyFile).LastWriteTime = (Get-Date).AddDays(-30)
            Set-ItemProperty -Path $readOnlyFile -Name IsReadOnly -Value $true

            # Create normal file
            $normalFile = Join-Path $script:forceTestDir 'normal.txt'
            'normal content' | Set-Content -Path $normalFile
            (Get-Item $normalFile).LastWriteTime = (Get-Date).AddDays(-30)
        }

        AfterAll {
            # Ensure read-only flag is removed before cleanup
            Get-ChildItem -Path $script:forceTestDir -File -Force | ForEach-Object {
                if ($_.IsReadOnly)
                {
                    $_.IsReadOnly = $false
                }
            }
            Remove-TestDirectory -Path $script:forceTestDir
        }

        It 'Should skip read-only files without Force' {
            $result = Remove-OldFiles -Path $script:forceTestDir -OlderThan 7 -Confirm:$false

            # Only normal file should be removed
            $result.FilesRemoved | Should -Be 1
            Test-Path (Join-Path $script:forceTestDir 'readonly.txt') | Should -Be $true
            Test-Path (Join-Path $script:forceTestDir 'normal.txt') | Should -Be $false
        }

        It 'Should remove read-only files with Force' {
            # Recreate the read-only file
            $readOnlyFile = Join-Path $script:forceTestDir 'readonly.txt'
            if (Test-Path $readOnlyFile)
            {
                (Get-Item $readOnlyFile).IsReadOnly = $false
                Remove-Item $readOnlyFile -Force
            }
            'readonly content' | Set-Content -Path $readOnlyFile
            (Get-Item $readOnlyFile).LastWriteTime = (Get-Date).AddDays(-30)
            Set-ItemProperty -Path $readOnlyFile -Name IsReadOnly -Value $true

            $result = Remove-OldFiles -Path $script:forceTestDir -OlderThan 7 -Force -Confirm:$false

            $result.FilesRemoved | Should -BeGreaterOrEqual 1
            Test-Path $readOnlyFile | Should -Be $false
        }
    }

    Context 'Pipeline Input' {
        BeforeAll {
            $script:pipelineDir1 = Join-Path $TestDrive 'Pipeline1'
            $script:pipelineDir2 = Join-Path $TestDrive 'Pipeline2'

            New-Item -ItemType Directory -Path $script:pipelineDir1 -Force | Out-Null
            New-Item -ItemType Directory -Path $script:pipelineDir2 -Force | Out-Null

            # Create old files in both directories
            1..2 | ForEach-Object {
                $file1 = Join-Path $script:pipelineDir1 "file$_.txt"
                $file2 = Join-Path $script:pipelineDir2 "file$_.txt"
                'content' | Set-Content -Path $file1
                'content' | Set-Content -Path $file2
                (Get-Item $file1).LastWriteTime = (Get-Date).AddDays(-30)
                (Get-Item $file2).LastWriteTime = (Get-Date).AddDays(-30)
            }
        }

        AfterAll {
            Remove-TestDirectory -Path $script:pipelineDir1
            Remove-TestDirectory -Path $script:pipelineDir2
        }

        It 'Should accept pipeline input' {
            $result = @($script:pipelineDir1, $script:pipelineDir2) |
                Remove-OldFiles -OlderThan 7 -Confirm:$false

            # Should process both directories and return a single summary
            $result | Should -Not -BeNullOrEmpty
            $result.FilesRemoved | Should -Be 4
            $result.Errors | Should -Be 0
        }
    }

    Context 'Error Handling' {
        It 'Should handle non-existent paths gracefully' {
            $nonExistent = Join-Path $TestDrive 'DoesNotExist'

            $result = Remove-OldFiles -Path $nonExistent -OlderThan 1 -ErrorAction SilentlyContinue

            $result.Errors | Should -BeGreaterThan 0
        }

        It 'Should continue processing after individual file errors' {
            $errorTestDir = Join-Path $TestDrive 'ErrorTest'
            New-Item -ItemType Directory -Path $errorTestDir -Force | Out-Null

            # Create files
            $file1 = Join-Path $errorTestDir 'file1.txt'
            $file2 = Join-Path $errorTestDir 'file2.txt'
            'content1' | Set-Content -Path $file1
            'content2' | Set-Content -Path $file2
            (Get-Item $file1).LastWriteTime = (Get-Date).AddDays(-30)
            (Get-Item $file2).LastWriteTime = (Get-Date).AddDays(-30)

            # Make first file locked (read-only without Force)
            Set-ItemProperty -Path $file1 -Name IsReadOnly -Value $true

            $result = Remove-OldFiles -Path $errorTestDir -OlderThan 7 -Confirm:$false

            # Should remove file2 even if file1 fails
            $result.FilesRemoved | Should -BeGreaterOrEqual 1
            Test-Path $file2 | Should -Be $false

            # Cleanup
            (Get-Item $file1).IsReadOnly = $false
            Remove-TestDirectory -Path $errorTestDir
        }
    }
}
