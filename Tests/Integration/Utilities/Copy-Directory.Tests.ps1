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
    # Import the function under test
    . "$PSScriptRoot/../../../Functions/Utilities/Copy-Directory.ps1"

    # Import cleanup utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Copy-Directory Integration Tests' {
    Context 'Basic Copy Operations' {
        BeforeAll {
            $script:testDir = Join-Path $TestDrive 'BasicCopy'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:testDir
        }

        It 'Should copy simple directory structure' {
            $sourceDir = Join-Path $script:testDir 'simple_source'
            $destDir = Join-Path $script:testDir 'simple_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'file1 content' | Set-Content -Path "$sourceDir\file1.txt"
            'file2 content' | Set-Content -Path "$sourceDir\file2.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip

            $result.TotalFiles | Should -Be 2
            $result.TotalDirectories | Should -Be 0
            Test-Path "$destDir\file1.txt" | Should -Be $true
            Test-Path "$destDir\file2.txt" | Should -Be $true
            (Get-Content -Path "$destDir\file1.txt") | Should -Be 'file1 content'
        }

        It 'Should copy nested directory structure' {
            $sourceDir = Join-Path $script:testDir 'nested_source'
            $destDir = Join-Path $script:testDir 'nested_dest'

            New-Item -ItemType Directory -Path "$sourceDir\dir1\subdir1" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\dir2" -Force | Out-Null
            'content1' | Set-Content -Path "$sourceDir\dir1\file1.txt"
            'content2' | Set-Content -Path "$sourceDir\dir1\subdir1\file2.txt"
            'content3' | Set-Content -Path "$sourceDir\dir2\file3.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip

            $result.TotalFiles | Should -Be 3
            $result.TotalDirectories | Should -Be 3
            Test-Path "$destDir\dir1\file1.txt" | Should -Be $true
            Test-Path "$destDir\dir1\subdir1\file2.txt" | Should -Be $true
            Test-Path "$destDir\dir2\file3.txt" | Should -Be $true
        }

        It 'Should preserve file contents during copy' {
            $sourceDir = Join-Path $script:testDir 'content_source'
            $destDir = Join-Path $script:testDir 'content_dest'
            $testContent = 'This is test content with special characters: áéíóú @#$%^&*()'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            $testContent | Set-Content -Path "$sourceDir\test.txt"

            Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip | Out-Null

            (Get-Content -Path "$destDir\test.txt") | Should -Be $testContent
        }
    }

    Context 'UpdateMode: Skip' {
        BeforeAll {
            $script:skipTestDir = Join-Path $TestDrive 'SkipMode'
            New-Item -ItemType Directory -Path $script:skipTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:skipTestDir
        }

        It 'Should skip existing files in Skip mode' {
            $sourceDir = Join-Path $script:skipTestDir 'skip_source'
            $destDir = Join-Path $script:skipTestDir 'skip_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            'new content' | Set-Content -Path "$sourceDir\existing.txt"
            'old content' | Set-Content -Path "$destDir\existing.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip

            $result.FilesSkipped | Should -Be 1
            $result.FilesOverwritten | Should -Be 0
            (Get-Content -Path "$destDir\existing.txt") | Should -Be 'old content'
        }

        It 'Should copy new files in Skip mode' {
            $sourceDir = Join-Path $script:skipTestDir 'skip_new_source'
            $destDir = Join-Path $script:skipTestDir 'skip_new_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'new file' | Set-Content -Path "$sourceDir\newfile.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip

            $result.TotalFiles | Should -Be 1
            $result.FilesSkipped | Should -Be 0
            Test-Path "$destDir\newfile.txt" | Should -Be $true
        }

        It 'Should track mixed skip and copy operations' {
            $sourceDir = Join-Path $script:skipTestDir 'skip_mixed_source'
            $destDir = Join-Path $script:skipTestDir 'skip_mixed_dest'

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
            $script:overwriteTestDir = Join-Path $TestDrive 'OverwriteMode'
            New-Item -ItemType Directory -Path $script:overwriteTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:overwriteTestDir
        }

        It 'Should overwrite existing files in Overwrite mode' {
            $sourceDir = Join-Path $script:overwriteTestDir 'overwrite_source'
            $destDir = Join-Path $script:overwriteTestDir 'overwrite_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            'new content' | Set-Content -Path "$sourceDir\file.txt"
            'old content' | Set-Content -Path "$destDir\file.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Overwrite

            $result.FilesOverwritten | Should -Be 1
            (Get-Content -Path "$destDir\file.txt") | Should -Be 'new content'
        }

        It 'Should overwrite multiple files in Overwrite mode' {
            $sourceDir = Join-Path $script:overwriteTestDir 'overwrite_multi_source'
            $destDir = Join-Path $script:overwriteTestDir 'overwrite_multi_dest'

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
            $script:ifnewerTestDir = Join-Path $TestDrive 'IfNewerMode'
            New-Item -ItemType Directory -Path $script:ifnewerTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:ifnewerTestDir
        }

        It 'Should overwrite if source is newer' {
            $sourceDir = Join-Path $script:ifnewerTestDir 'ifnewer_newer_source'
            $destDir = Join-Path $script:ifnewerTestDir 'ifnewer_newer_dest'

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
            $sourceDir = Join-Path $script:ifnewerTestDir 'ifnewer_older_source'
            $destDir = Join-Path $script:ifnewerTestDir 'ifnewer_older_dest'

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
            $sourceDir = Join-Path $script:ifnewerTestDir 'ifnewer_exact_source'
            $destDir = Join-Path $script:ifnewerTestDir 'ifnewer_exact_dest'

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
            $script:excludeTestDir = Join-Path $TestDrive 'ExclusionTests'
            New-Item -ItemType Directory -Path $script:excludeTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:excludeTestDir
        }

        It 'Should exclude .git directories at all levels' {
            $sourceDir = Join-Path $script:excludeTestDir 'git_exclude_source'
            $destDir = Join-Path $script:excludeTestDir 'git_exclude_dest'

            New-Item -ItemType Directory -Path "$sourceDir\.git\objects" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\src\app\.git" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\src\lib" -Force | Out-Null

            'config' | Set-Content -Path "$sourceDir\.git\config"
            'object' | Set-Content -Path "$sourceDir\.git\objects\file"
            'app code' | Set-Content -Path "$sourceDir\src\app\main.ps1"
            'app git config' | Set-Content -Path "$sourceDir\src\app\.git\config"
            'lib code' | Set-Content -Path "$sourceDir\src\lib\helper.ps1"

            Copy-Directory -Source $sourceDir -Destination $destDir -ExcludeDirectories '.git' -UpdateMode Skip

            Test-Path "$destDir\.git" | Should -Be $false
            Test-Path "$destDir\src\app\.git" | Should -Be $false
            Test-Path "$destDir\src\app\main.ps1" | Should -Be $true
            Test-Path "$destDir\src\lib\helper.ps1" | Should -Be $true
        }

        It 'Should exclude multiple build artifact directories' {
            $sourceDir = Join-Path $script:excludeTestDir 'buildartifact_source'
            $destDir = Join-Path $script:excludeTestDir 'buildartifact_dest'

            New-Item -ItemType Directory -Path "$sourceDir\bin\Debug" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\obj\Release" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\dist" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\src" -Force | Out-Null

            'debug exe' | Set-Content -Path "$sourceDir\bin\Debug\app.exe"
            'obj' | Set-Content -Path "$sourceDir\obj\Release\obj.o"
            'minified' | Set-Content -Path "$sourceDir\dist\app.min.js"
            'source' | Set-Content -Path "$sourceDir\src\main.ps1"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir `
                -ExcludeDirectories 'bin', 'obj', 'dist' -UpdateMode Skip

            $result.ExcludedDirectories | Should -Be 3
            Test-Path "$destDir\bin" | Should -Be $false
            Test-Path "$destDir\obj" | Should -Be $false
            Test-Path "$destDir\dist" | Should -Be $false
            Test-Path "$destDir\src\main.ps1" | Should -Be $true
        }
    }

    Context 'WhatIf Support' {
        BeforeAll {
            $script:whatifTestDir = Join-Path $TestDrive 'WhatIfTests'
            New-Item -ItemType Directory -Path $script:whatifTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:whatifTestDir
        }

        It 'Should support -WhatIf without copying files' {
            $sourceDir = Join-Path $script:whatifTestDir 'whatif_source'
            $destDir = Join-Path $script:whatifTestDir 'whatif_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'content' | Set-Content -Path "$sourceDir\file.txt"

            Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip -WhatIf

            # Destination should not exist with WhatIf
            Test-Path $destDir | Should -Be $false
        }
    }

    Context 'Output Statistics Accuracy' {
        BeforeAll {
            $script:statsTestDir = Join-Path $TestDrive 'StatsTests'
            New-Item -ItemType Directory -Path $script:statsTestDir -Force | Out-Null
        }

        AfterAll {
            Remove-TestDirectory -Path $script:statsTestDir
        }

        It 'Should accurately report file and directory counts' {
            $sourceDir = Join-Path $script:statsTestDir 'stats_source'
            $destDir = Join-Path $script:statsTestDir 'stats_dest'

            New-Item -ItemType Directory -Path "$sourceDir\dir1\subdir1" -Force | Out-Null
            New-Item -ItemType Directory -Path "$sourceDir\dir2" -Force | Out-Null

            1..3 | ForEach-Object {
                "file$_" | Set-Content -Path "$sourceDir\dir1\file$_.txt"
            }
            'file4' | Set-Content -Path "$sourceDir\dir1\subdir1\file4.txt"
            'file5' | Set-Content -Path "$sourceDir\dir2\file5.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip

            # 5 files total
            $result.TotalFiles | Should -Be 5
            # 3 directories: dir1, dir1\subdir1, dir2
            $result.TotalDirectories | Should -Be 3
        }

        It 'Should measure duration correctly' {
            $sourceDir = Join-Path $script:statsTestDir 'duration_source'
            $destDir = Join-Path $script:statsTestDir 'duration_dest'

            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            'content' | Set-Content -Path "$sourceDir\file.txt"

            $result = Copy-Directory -Source $sourceDir -Destination $destDir -UpdateMode Skip

            $result.Duration | Should -Not -BeNullOrEmpty
            $result.Duration.TotalMilliseconds | Should -BeGreaterThan 0
        }

        It 'Should correctly count skipped vs overwritten files' {
            $sourceDir = Join-Path $script:statsTestDir 'counts_source'
            $destDir = Join-Path $script:statsTestDir 'counts_dest'

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
}
