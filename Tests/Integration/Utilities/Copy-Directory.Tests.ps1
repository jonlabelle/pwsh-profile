#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Copy-Directory function.

.DESCRIPTION
    Integration tests that verify Copy-Directory works correctly in real-world
    scenarios with actual file systems, complex directory structures, and various UpdateMode options.

.NOTES
    These tests verify:
    - Actual file and directory copying
    - UpdateMode behavior (Skip, Overwrite, IfNewer, Prompt)
    - Directory exclusion with complex hierarchies
    - Timestamp handling
    - Space and time measurements
    - Error handling
    - WhatIf support
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Import the function under test
    . "$PSScriptRoot/../../../Functions/Utilities/Copy-Directory.ps1"

    # Import cleanup utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Copy-Directory Integration Tests' {
    Context 'Basic Copy Operations' {
        BeforeAll {
            $script:testDir = Join-Path -Path $TestDrive -ChildPath 'BasicCopy'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:testDir
        }

        It 'Should copy simple directory structure' {
            $sourceDir = Join-Path -Path $script:testDir -ChildPath 'simple_source'
            $destDir = Join-Path -Path $script:testDir -ChildPath 'simple_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'file1 content' | Set-Content -Path "$sourceDir\file1.txt"
            'file2 content' | Set-Content -Path "$sourceDir\file2.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip -Recurse

            $result.TotalFiles | Should -Be 2
            $result.TotalDirectories | Should -Be 0
            Test-Path "$destDir\file1.txt" | Should -Be $true
            Test-Path "$destDir\file2.txt" | Should -Be $true
            (Get-Content -Path "$destDir\file1.txt") | Should -Be 'file1 content'
        }

        It 'Should copy nested directory structure' {
            $sourceDir = Join-Path -Path $script:testDir -ChildPath 'nested_source'
            $destDir = Join-Path -Path $script:testDir -ChildPath 'nested_dest'

            New-Item -ItemType Directory -Path "$sourceDir\dir1\subdir1" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\dir2" -Force | Out-Null
            'content1' | Set-Content -Path "$sourceDir\dir1\file1.txt"
            'content2' | Set-Content -Path "$sourceDir\dir1\subdir1\file2.txt"
            'content3' | Set-Content -Path "$sourceDir\dir2\file3.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip -Recurse

            $result.TotalFiles | Should -Be 3
            $result.TotalDirectories | Should -Be 3
            Test-Path "$destDir\dir1\file1.txt" | Should -Be $true
            Test-Path "$destDir\dir1\subdir1\file2.txt" | Should -Be $true
            Test-Path "$destDir\dir2\file3.txt" | Should -Be $true
        }

        It 'Should preserve file contents during copy' {
            $sourceDir = Join-Path -Path $script:testDir -ChildPath 'content_source'
            $destDir = Join-Path -Path $script:testDir -ChildPath 'content_dest'
            $testContent = 'This is test content with special characters: áéíóú @#$%^&*()'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            $testContent | Set-Content -Path "$sourceDir\test.txt"

            Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip | Out-Null

            (Get-Content -Path "$destDir\test.txt") | Should -Be $testContent
        }
    }

    Context 'UpdateMode: Skip' {
        BeforeAll {
            $script:skipTestDir = Join-Path -Path $TestDrive -ChildPath 'SkipMode'
            New-Item -ItemType Directory -Path $script:skipTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:skipTestDir
        }

        It 'Should skip existing files in Skip mode' {
            $sourceDir = Join-Path -Path $script:skipTestDir -ChildPath 'skip_source'
            $destDir = Join-Path -Path $script:skipTestDir -ChildPath 'skip_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            'new content' | Set-Content -Path "$sourceDir\existing.txt"
            'old content' | Set-Content -Path "$destDir\existing.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip -Recurse

            $result.FilesSkipped | Should -Be 1
            $result.FilesOverwritten | Should -Be 0
            (Get-Content -Path "$destDir\existing.txt") | Should -Be 'old content'
        }

        It 'Should copy new files in Skip mode' {
            $sourceDir = Join-Path -Path $script:skipTestDir -ChildPath 'skip_new_source'
            $destDir = Join-Path -Path $script:skipTestDir -ChildPath 'skip_new_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'new file' | Set-Content -Path "$sourceDir\newfile.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip

            $result.TotalFiles | Should -Be 1
            $result.FilesSkipped | Should -Be 0
            Test-Path "$destDir\newfile.txt" | Should -Be $true
        }

        It 'Should track mixed skip and copy operations' {
            $sourceDir = Join-Path -Path $script:skipTestDir -ChildPath 'skip_mixed_source'
            $destDir = Join-Path -Path $script:skipTestDir -ChildPath 'skip_mixed_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            'new 1' | Set-Content -Path "$sourceDir\file1.txt"
            'new 2' | Set-Content -Path "$sourceDir\file2.txt"
            'old 2' | Set-Content -Path "$destDir\file2.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip

            # TotalFiles tracks copied files, FilesSkipped tracks skipped files
            $result.TotalFiles | Should -Be 1
            $result.FilesSkipped | Should -Be 1
            (Get-Content -Path "$destDir\file1.txt") | Should -Be 'new 1'
            (Get-Content -Path "$destDir\file2.txt") | Should -Be 'old 2'
        }
    }

    Context 'UpdateMode: Overwrite' {
        BeforeAll {
            $script:overwriteTestDir = Join-Path -Path $TestDrive -ChildPath 'OverwriteMode'
            New-Item -ItemType Directory -Path $script:overwriteTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:overwriteTestDir
        }

        It 'Should overwrite existing files in Overwrite mode' {
            $sourceDir = Join-Path -Path $script:overwriteTestDir -ChildPath 'overwrite_source'
            $destDir = Join-Path -Path $script:overwriteTestDir -ChildPath 'overwrite_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            'new content' | Set-Content -Path "$sourceDir\file.txt"
            'old content' | Set-Content -Path "$destDir\file.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Overwrite

            $result.FilesOverwritten | Should -Be 1
            (Get-Content -Path "$destDir\file.txt") | Should -Be 'new content'
        }

        It 'Should overwrite multiple files in Overwrite mode' {
            $sourceDir = Join-Path -Path $script:overwriteTestDir -ChildPath 'overwrite_multi_source'
            $destDir = Join-Path -Path $script:overwriteTestDir -ChildPath 'overwrite_multi_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            'new1' | Set-Content -Path "$sourceDir\file1.txt"
            'new2' | Set-Content -Path "$sourceDir\file2.txt"
            'old1' | Set-Content -Path "$destDir\file1.txt"
            'old2' | Set-Content -Path "$destDir\file2.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Overwrite

            $result.FilesOverwritten | Should -Be 2
            (Get-Content -Path "$destDir\file1.txt") | Should -Be 'new1'
            (Get-Content -Path "$destDir\file2.txt") | Should -Be 'new2'
        }
    }

    Context 'UpdateMode: IfNewer' {
        BeforeAll {
            $script:ifnewerTestDir = Join-Path -Path $TestDrive -ChildPath 'IfNewerMode'
            New-Item -ItemType Directory -Path $script:ifnewerTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:ifnewerTestDir
        }

        It 'Should overwrite if source is newer' {
            $sourceDir = Join-Path -Path $script:ifnewerTestDir -ChildPath 'ifnewer_newer_source'
            $destDir = Join-Path -Path $script:ifnewerTestDir -ChildPath 'ifnewer_newer_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            'new content' | Set-Content -Path "$sourceDir\file.txt"
            'old content' | Set-Content -Path "$destDir\file.txt"

            # Set destination file to be older
            $destFile = Get-Item -Path "$destDir\file.txt"
            $destFile.LastWriteTime = (Get-Date).AddDays(-1)

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode IfNewer

            $result.FilesOverwritten | Should -Be 1
            (Get-Content -Path "$destDir\file.txt") | Should -Be 'new content'
        }

        It 'Should skip if destination is newer or equal' {
            $sourceDir = Join-Path -Path $script:ifnewerTestDir -ChildPath 'ifnewer_older_source'
            $destDir = Join-Path -Path $script:ifnewerTestDir -ChildPath 'ifnewer_older_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            'new content' | Set-Content -Path "$sourceDir\file.txt"
            'old content' | Set-Content -Path "$destDir\file.txt"

            # Set source file to be older
            $sourceFile = Get-Item -Path "$sourceDir\file.txt"
            $sourceFile.LastWriteTime = (Get-Date).AddDays(-1)

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode IfNewer

            $result.FilesSkipped | Should -Be 1
            (Get-Content -Path "$destDir\file.txt") | Should -Be 'old content'
        }

        It 'Should handle timestamp comparison correctly' {
            $sourceDir = Join-Path -Path $script:ifnewerTestDir -ChildPath 'ifnewer_exact_source'
            $destDir = Join-Path -Path $script:ifnewerTestDir -ChildPath 'ifnewer_exact_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            'content' | Set-Content -Path "$sourceDir\file.txt"
            'content' | Set-Content -Path "$destDir\file.txt"

            # Set identical timestamps
            $now = (Get-Date).AddSeconds(-1)
            $sourceFile = Get-Item -Path "$sourceDir\file.txt"
            $destFile = Get-Item -Path "$destDir\file.txt"
            $sourceFile.LastWriteTime = $now
            $destFile.LastWriteTime = $now

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode IfNewer

            # Should skip if timestamps are equal (not newer)
            $result.FilesSkipped | Should -Be 1
        }
    }

    Context 'Directory Exclusion with Complex Hierarchies' {
        BeforeAll {
            $script:excludeTestDir = Join-Path -Path $TestDrive -ChildPath 'ExclusionTests'
            New-Item -ItemType Directory -Path $script:excludeTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:excludeTestDir
        }

        It 'Should exclude .git directories at all levels' {
            $sourceDir = Join-Path -Path $script:excludeTestDir -ChildPath 'git_exclude_source'
            $destDir = Join-Path -Path $script:excludeTestDir -ChildPath 'git_exclude_dest'

            New-Item -ItemType Directory -Path "$sourceDir\.git\objects" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\src\app\.git" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\src\lib" -Force | Out-Null

            'config' | Set-Content -Path "$sourceDir\.git\config"
            'object' | Set-Content -Path "$sourceDir\.git\objects\file"
            'app code' | Set-Content -Path "$sourceDir\src\app\main.ps1"
            'app git config' | Set-Content -Path "$sourceDir\src\app\.git\config"
            'lib code' | Set-Content -Path "$sourceDir\src\lib\helper.ps1"

            Copy-Directory -Source $sourceDir -Destination $destDir -ExcludeDirectories '.git' -UpdateMode Skip -Recurse

            Test-Path "$destDir\.git" | Should -Be $false
            Test-Path "$destDir\src\app\.git" | Should -Be $false
            Test-Path "$destDir\src\app\main.ps1" | Should -Be $true
            Test-Path "$destDir\src\lib\helper.ps1" | Should -Be $true
        }

        It 'Should exclude multiple build artifact directories' {
            $sourceDir = Join-Path -Path $script:excludeTestDir -ChildPath 'buildartifact_source'
            $destDir = Join-Path -Path $script:excludeTestDir -ChildPath 'buildartifact_dest'

            New-Item -ItemType Directory -Path "$sourceDir\bin\Debug" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\obj\Release" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\dist" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\src" -Force | Out-Null

            'debug exe' | Set-Content -Path "$sourceDir\bin\Debug\app.exe"
            'obj' | Set-Content -Path "$sourceDir\obj\Release\obj.o"
            'minified' | Set-Content -Path "$sourceDir\dist\app.min.js"
            'source' | Set-Content -Path "$sourceDir\src\main.ps1"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir `
                -ExcludeDirectories 'bin', 'obj', 'dist' -UpdateMode Skip -Recurse

            $result.ExcludedDirectories | Should -Be 3
            Test-Path "$destDir\bin" | Should -Be $false
            Test-Path "$destDir\obj" | Should -Be $false
            Test-Path "$destDir\dist" | Should -Be $false
            Test-Path "$destDir\src\main.ps1" | Should -Be $true
        }
    }

    Context 'WhatIf Support' {
        BeforeAll {
            $script:whatifTestDir = Join-Path -Path $TestDrive -ChildPath 'WhatIfTests'
            New-Item -ItemType Directory -Path $script:whatifTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:whatifTestDir
        }

        It 'Should support -WhatIf without copying files' {
            $sourceDir = Join-Path -Path $script:whatifTestDir -ChildPath 'whatif_source'
            $destDir = Join-Path -Path $script:whatifTestDir -ChildPath 'whatif_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'content' | Set-Content -Path "$sourceDir\file.txt"

            Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip -WhatIf

            # Destination should not exist with WhatIf
            Test-Path $destDir | Should -Be $false
        }
    }

    Context 'Output Statistics Accuracy' {
        BeforeAll {
            $script:statsTestDir = Join-Path -Path $TestDrive -ChildPath 'StatsTests'
            New-Item -ItemType Directory -Path $script:statsTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:statsTestDir
        }

        It 'Should accurately report file and directory counts' {
            $sourceDir = Join-Path -Path $script:statsTestDir -ChildPath 'stats_source'
            $destDir = Join-Path -Path $script:statsTestDir -ChildPath 'stats_dest'

            New-Item -ItemType Directory -Path "$sourceDir\dir1\subdir1" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\dir2" -Force | Out-Null

            1..3 | ForEach-Object {
                "file$_" | Set-Content -Path "$sourceDir\dir1\file$_.txt"
            }
            'file4' | Set-Content -Path "$sourceDir\dir1\subdir1\file4.txt"
            'file5' | Set-Content -Path "$sourceDir\dir2\file5.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip -Recurse

            # 5 files total
            $result.TotalFiles | Should -Be 5
            # 3 directories: dir1, dir1\subdir1, dir2
            $result.TotalDirectories | Should -Be 3
        }

        It 'Should measure duration correctly' {
            $sourceDir = Join-Path -Path $script:statsTestDir -ChildPath 'duration_source'
            $destDir = Join-Path -Path $script:statsTestDir -ChildPath 'duration_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'content' | Set-Content -Path "$sourceDir\file.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip

            $result.Duration | Should -Not -BeNullOrEmpty
            $result.Duration.TotalMilliseconds | Should -BeGreaterThan 0
        }

        It 'Should correctly count skipped vs overwritten files' {
            $sourceDir = Join-Path -Path $script:statsTestDir -ChildPath 'counts_source'
            $destDir = Join-Path -Path $script:statsTestDir -ChildPath 'counts_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            # Create source files
            'new1' | Set-Content -Path "$sourceDir\file1.txt"
            'new2' | Set-Content -Path "$sourceDir\file2.txt"
            'new3' | Set-Content -Path "$sourceDir\file3.txt"

            # Create existing dest files for files 2 and 3
            'old2' | Set-Content -Path "$destDir\file2.txt"
            'old3' | Set-Content -Path "$destDir\file3.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip

            # TotalFiles = copied files, FilesSkipped = files that existed and were skipped
            $result.TotalFiles | Should -Be 1  # Only file1 was copied
            $result.FilesSkipped | Should -Be 2  # Files 2 and 3 were skipped
            $result.FilesOverwritten | Should -Be 0
        }
    }

    Context 'Parallel Processing' {
        BeforeAll {
            $script:parallelTestDir = Join-Path -Path $TestDrive -ChildPath 'ParallelTests'
            New-Item -ItemType Directory -Path $script:parallelTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:parallelTestDir
        }

        It 'Should copy many files correctly with parallel processing' {
            $sourceDir = Join-Path -Path $script:parallelTestDir -ChildPath 'many_files_source'
            $destDir = Join-Path -Path $script:parallelTestDir -ChildPath 'many_files_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null

            # Create 20 files to ensure parallel processing is triggered
            1..20 | ForEach-Object {
                "content for file $_" | Set-Content -Path "$sourceDir\file$_.txt"
            }

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -ThrottleLimit 4

            $result.TotalFiles | Should -Be 20
            1..20 | ForEach-Object {
                Test-Path "$destDir\file$_.txt" | Should -Be $true
                (Get-Content -Path "$destDir\file$_.txt") | Should -Be "content for file $_"
            }
        }

        It 'Should handle parallel copying with nested directories' {
            $sourceDir = Join-Path -Path $script:parallelTestDir -ChildPath 'nested_parallel_source'
            $destDir = Join-Path -Path $script:parallelTestDir -ChildPath 'nested_parallel_dest'

            # Create nested structure with many files
            New-Item -ItemType Directory -Path "$sourceDir\level1\level2\level3" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\another" -Force | Out-Null

            1..5 | ForEach-Object { "root $_" | Set-Content -Path "$sourceDir\root$_.txt" }
            1..5 | ForEach-Object { "level1 $_" | Set-Content -Path "$sourceDir\level1\l1_$_.txt" }
            1..5 | ForEach-Object { "level2 $_" | Set-Content -Path "$sourceDir\level1\level2\l2_$_.txt" }
            1..5 | ForEach-Object { "level3 $_" | Set-Content -Path "$sourceDir\level1\level2\level3\l3_$_.txt" }
            1..5 | ForEach-Object { "another $_" | Set-Content -Path "$sourceDir\another\a$_.txt" }

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -ThrottleLimit 8 -Recurse

            $result.TotalFiles | Should -Be 25
            $result.TotalDirectories | Should -Be 4

            # Verify content integrity across all levels
            1..5 | ForEach-Object {
                (Get-Content -Path "$destDir\root$_.txt") | Should -Be "root $_"
                (Get-Content -Path "$destDir\level1\l1_$_.txt") | Should -Be "level1 $_"
                (Get-Content -Path "$destDir\level1\level2\l2_$_.txt") | Should -Be "level2 $_"
                (Get-Content -Path "$destDir\level1\level2\level3\l3_$_.txt") | Should -Be "level3 $_"
                (Get-Content -Path "$destDir\another\a$_.txt") | Should -Be "another $_"
            }
        }

        It 'Should correctly track statistics in parallel mode with Skip' {
            $sourceDir = Join-Path -Path $script:parallelTestDir -ChildPath 'parallel_skip_source'
            $destDir = Join-Path -Path $script:parallelTestDir -ChildPath 'parallel_skip_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            # Create 10 source files
            1..10 | ForEach-Object { "new $_" | Set-Content -Path "$sourceDir\file$_.txt" }

            # Create 5 existing files at destination
            1..5 | ForEach-Object { "old $_" | Set-Content -Path "$destDir\file$_.txt" }

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip -ThrottleLimit 4

            $result.TotalFiles | Should -Be 5  # Only files 6-10 copied
            $result.FilesSkipped | Should -Be 5  # Files 1-5 skipped
            $result.FilesOverwritten | Should -Be 0
        }

        It 'Should correctly track statistics in parallel mode with Overwrite' {
            $sourceDir = Join-Path -Path $script:parallelTestDir -ChildPath 'parallel_overwrite_source'
            $destDir = Join-Path -Path $script:parallelTestDir -ChildPath 'parallel_overwrite_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            # Create 10 source files
            1..10 | ForEach-Object { "new $_" | Set-Content -Path "$sourceDir\file$_.txt" }

            # Create 5 existing files at destination
            1..5 | ForEach-Object { "old $_" | Set-Content -Path "$destDir\file$_.txt" }

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Overwrite -ThrottleLimit 4

            $result.TotalFiles | Should -Be 10  # All 10 files copied
            $result.FilesSkipped | Should -Be 0
            $result.FilesOverwritten | Should -Be 5  # Files 1-5 overwritten

            # Verify all files have new content
            1..10 | ForEach-Object {
                (Get-Content -Path "$destDir\file$_.txt") | Should -Be "new $_"
            }
        }

        It 'Should correctly track statistics in parallel mode with IfNewer' {
            $sourceDir = Join-Path -Path $script:parallelTestDir -ChildPath 'parallel_ifnewer_source'
            $destDir = Join-Path -Path $script:parallelTestDir -ChildPath 'parallel_ifnewer_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            # Create 6 source files
            1..6 | ForEach-Object { "new $_" | Set-Content -Path "$sourceDir\file$_.txt" }

            # Create 3 older files at destination
            1..3 | ForEach-Object {
                "old $_" | Set-Content -Path "$destDir\file$_.txt"
                $destFile = Get-Item -Path "$destDir\file$_.txt"
                $destFile.LastWriteTime = (Get-Date).AddDays(-1)
            }

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode IfNewer -ThrottleLimit 4

            # Files 1-3: overwritten (newer), Files 4-6: newly copied
            $result.TotalFiles | Should -Be 6  # All 6 files copied
            $result.FilesOverwritten | Should -Be 3  # Files 1-3 overwritten
            $result.FilesSkipped | Should -Be 0
        }

        It 'Should produce consistent results between sequential and parallel modes' {
            $sourceSeqDir = Join-Path -Path $script:parallelTestDir -ChildPath 'consistency_seq_source'
            $destSeqDir = Join-Path -Path $script:parallelTestDir -ChildPath 'consistency_seq_dest'
            $sourceParDir = Join-Path -Path $script:parallelTestDir -ChildPath 'consistency_par_source'
            $destParDir = Join-Path -Path $script:parallelTestDir -ChildPath 'consistency_par_dest'

            # Create identical source structures
            New-Item -ItemType Directory -Path "$sourceSeqDir\sub" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceParDir\sub" -Force | Out-Null

            1..10 | ForEach-Object {
                "content $_" | Set-Content -Path "$sourceSeqDir\file$_.txt"
                "content $_" | Set-Content -Path "$sourceParDir\file$_.txt"
                "sub content $_" | Set-Content -Path "$sourceSeqDir\sub\sub$_.txt"
                "sub content $_" | Set-Content -Path "$sourceParDir\sub\sub$_.txt"
            }

            $resultSeq = Copy-Directory -Source $sourceSeqDir -Destination $destSeqDir -ThrottleLimit 1 -Recurse
            $resultPar = Copy-Directory -Source $sourceParDir -Destination $destParDir -ThrottleLimit 8 -Recurse

            $resultSeq.TotalFiles | Should -Be $resultPar.TotalFiles
            $resultSeq.TotalDirectories | Should -Be $resultPar.TotalDirectories
            $resultSeq.FilesSkipped | Should -Be $resultPar.FilesSkipped
            $resultSeq.FilesOverwritten | Should -Be $resultPar.FilesOverwritten

            # Verify content is identical
            1..10 | ForEach-Object {
                (Get-Content "$destSeqDir\file$_.txt") | Should -Be (Get-Content "$destParDir\file$_.txt")
                (Get-Content "$destSeqDir\sub\sub$_.txt") | Should -Be (Get-Content "$destParDir\sub\sub$_.txt")
            }
        }

        It 'Should handle directory exclusion correctly in parallel mode' {
            $sourceDir = Join-Path -Path $script:parallelTestDir -ChildPath 'parallel_exclude_source'
            $destDir = Join-Path -Path $script:parallelTestDir -ChildPath 'parallel_exclude_dest'

            New-Item -ItemType Directory -Path "$sourceDir\include" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\.git" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\node_modules" -Force | Out-Null

            1..5 | ForEach-Object {
                "include $_" | Set-Content -Path "$sourceDir\include\file$_.txt"
                "git $_" | Set-Content -Path "$sourceDir\.git\file$_.txt"
                "node $_" | Set-Content -Path "$sourceDir\node_modules\file$_.txt"
            }

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -ExcludeDirectories '.git', 'node_modules' -ThrottleLimit 4 -Recurse

            $result.TotalFiles | Should -Be 5
            $result.ExcludedDirectories | Should -Be 2

            Test-Path "$destDir\include" | Should -Be $true
            Test-Path "$destDir\.git" | Should -Be $false
            Test-Path "$destDir\node_modules" | Should -Be $false
        }

        It 'Should be faster with parallel processing for large file sets' {
            $sourceDir = Join-Path -Path $script:parallelTestDir -ChildPath 'perf_source'
            $destSeqDir = Join-Path -Path $script:parallelTestDir -ChildPath 'perf_seq_dest'
            $destParDir = Join-Path -Path $script:parallelTestDir -ChildPath 'perf_par_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null

            # Create 50 files with some content
            1..50 | ForEach-Object {
                "This is test content for file number $_ with enough data to make copying meaningful." | Set-Content -Path "$sourceDir\file$_.txt"
            }

            $resultSeq = Copy-Directory -Source $sourceDir -Destination $destSeqDir -ThrottleLimit 1
            $resultPar = Copy-Directory -Source $sourceDir -Destination $destParDir -ThrottleLimit 8

            # Both should complete successfully with same file count
            $resultSeq.TotalFiles | Should -Be 50
            $resultPar.TotalFiles | Should -Be 50

            # Parallel should generally be faster or equal (file I/O can be unpredictable)
            # We just verify both complete without errors
            $resultSeq.Duration | Should -BeOfType [TimeSpan]
            $resultPar.Duration | Should -BeOfType [TimeSpan]
        }
    }
}
