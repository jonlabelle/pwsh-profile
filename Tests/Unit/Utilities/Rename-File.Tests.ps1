BeforeAll {
    # Import the function
    . "$PSScriptRoot/../../../Functions/Utilities/Rename-File.ps1"

    # Import test cleanup utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Rename-File Unit Tests' -Tag 'Unit', 'Utilities' {
    BeforeAll {
        # Create a test directory structure
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath 'RenameFileTests'
        New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        # Cleanup
        if (Test-Path $script:testRoot)
        {
            Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Case Conversion' {
        BeforeEach {
            $script:testFile = Join-Path -Path $script:testRoot -ChildPath 'TestFile.txt'
            'test content' | Out-File -FilePath $script:testFile -Encoding UTF8
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should convert filename to uppercase' {
            Rename-File -LiteralPath $script:testFile -ToUpper
            $result = Get-ChildItem -Path $script:testRoot -File
            $result.Name | Should -Be 'TESTFILE.TXT'
        }

        It 'Should convert filename to lowercase' {
            Rename-File -LiteralPath $script:testFile -ToLower
            $result = Get-ChildItem -Path $script:testRoot -File
            $result.Name | Should -Be 'testfile.txt'
        }

        It 'Should convert filename to title case' {
            # Remove the initial test file from BeforeEach
            Remove-Item -Path $script:testFile -Force -ErrorAction SilentlyContinue
            $testFile2 = Join-Path -Path $script:testRoot -ChildPath 'test file name.txt'
            'content' | Out-File -FilePath $testFile2 -Encoding UTF8
            Rename-File -LiteralPath $testFile2 -ToTitleCase
            $result = Get-ChildItem -Path $script:testRoot -File
            $result.Name | Should -Be 'Test File Name.txt'
        }

        It 'Should convert filename to camel case' {
            # Remove the initial test file from BeforeEach
            Remove-Item -Path $script:testFile -Force -ErrorAction SilentlyContinue
            $testFile2 = Join-Path -Path $script:testRoot -ChildPath 'test file name.txt'
            'content' | Out-File -FilePath $testFile2 -Encoding UTF8
            Rename-File -LiteralPath $testFile2 -ToCamelCase
            $result = Get-ChildItem -Path $script:testRoot -File
            $result.Name | Should -Be 'testFileName.txt'
        }

        It 'Should convert filename to pascal case' {
            # Remove the initial test file from BeforeEach
            Remove-Item -Path $script:testFile -Force -ErrorAction SilentlyContinue
            $testFile2 = Join-Path -Path $script:testRoot -ChildPath 'test file name.txt'
            'content' | Out-File -FilePath $testFile2 -Encoding UTF8
            Rename-File -LiteralPath $testFile2 -ToPascalCase
            $result = Get-ChildItem -Path $script:testRoot -File
            $result.Name | Should -Be 'TestFileName.txt'
        }
    }

    Context 'Whitespace Replacement' {
        BeforeEach {
            $script:testFile = Join-Path -Path $script:testRoot -ChildPath 'test file.txt'
            'test content' | Out-File -FilePath $script:testFile -Encoding UTF8
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should replace spaces with underscores' {
            Rename-File -LiteralPath $script:testFile -ReplaceSpacesWith '_'
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test_file.txt') | Should -Be $true
        }

        It 'Should replace spaces with dashes' {
            Rename-File -LiteralPath $script:testFile -ReplaceSpacesWith '-'
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test-file.txt') | Should -Be $true
        }

        It 'Should replace underscores with spaces' {
            $testFile2 = Join-Path -Path $script:testRoot -ChildPath 'test_file.txt'
            'content' | Out-File -FilePath $testFile2 -Encoding UTF8
            Rename-File -LiteralPath $testFile2 -ReplaceUnderscoresWith ' '
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test file.txt') | Should -Be $true
        }

        It 'Should replace dashes with spaces' {
            $testFile2 = Join-Path -Path $script:testRoot -ChildPath 'test-file.txt'
            'content' | Out-File -FilePath $testFile2 -Encoding UTF8
            Rename-File -LiteralPath $testFile2 -ReplaceDashesWith ' '
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test file.txt') | Should -Be $true
        }
    }

    Context 'Trim Operations' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should trim leading and trailing spaces' {
            $testFile = Join-Path -Path $script:testRoot -ChildPath '  test file  .txt'
            'content' | Out-File -FilePath $testFile -Encoding UTF8
            Rename-File -LiteralPath $testFile -Trim
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test file.txt') | Should -Be $true
        }

        It 'Should trim leading spaces only' {
            $testFile = Join-Path -Path $script:testRoot -ChildPath '  test file.txt'
            'content' | Out-File -FilePath $testFile -Encoding UTF8
            Rename-File -LiteralPath $testFile -TrimStart
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test file.txt') | Should -Be $true
        }

        It 'Should trim trailing spaces only' {
            $testFile = Join-Path -Path $script:testRoot -ChildPath 'test file  .txt'
            'content' | Out-File -FilePath $testFile -Encoding UTF8
            Rename-File -LiteralPath $testFile -TrimEnd
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test file.txt') | Should -Be $true
        }
    }

    Context 'Prepend and Append' {
        BeforeEach {
            $script:testFile = Join-Path -Path $script:testRoot -ChildPath 'file.txt'
            'test content' | Out-File -FilePath $script:testFile -Encoding UTF8
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should prepend text to filename' {
            Rename-File -LiteralPath $script:testFile -Prepend 'prefix_'
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'prefix_file.txt') | Should -Be $true
        }

        It 'Should append text to filename' {
            Rename-File -LiteralPath $script:testFile -Append '_suffix'
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'file_suffix.txt') | Should -Be $true
        }

        It 'Should prepend and append text to filename' {
            Rename-File -LiteralPath $script:testFile -Prepend 'prefix_' -Append '_suffix'
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'prefix_file_suffix.txt') | Should -Be $true
        }
    }

    Context 'URL Decoding' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should URL decode filename with %20 (space)' {
            $testFile = Join-Path -Path $script:testRoot -ChildPath 'test%20file.txt'
            'content' | Out-File -FilePath $testFile -Encoding UTF8
            Rename-File -LiteralPath $testFile -UrlDecode
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test file.txt') | Should -Be $true
        }

        It 'Should URL decode filename with multiple encoded characters' {
            $testFile = Join-Path -Path $script:testRoot -ChildPath 'test%20file%2B%2D.txt'
            'content' | Out-File -FilePath $testFile -Encoding UTF8
            Rename-File -LiteralPath $testFile -UrlDecode
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test file+-.txt') | Should -Be $true
        }
    }

    Context 'Normalization' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should normalize filename with accented characters' {
            $testFile = Join-Path -Path $script:testRoot -ChildPath 'café.txt'
            'content' | Out-File -FilePath $testFile -Encoding UTF8
            Rename-File -LiteralPath $testFile -Normalize
            $result = Get-ChildItem -Path $script:testRoot -File
            $result.Name | Should -Be 'cafe.txt'
        }
    }

    Context 'Control and Shell Meta-Characters' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should remove shell meta-characters' {
            $testFile = Join-Path -Path $script:testRoot -ChildPath 'test(file).txt'
            'content' | Out-File -FilePath $testFile -Encoding UTF8
            Rename-File -LiteralPath $testFile -RemoveShellMetaCharacters
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'testfile.txt') | Should -Be $true
        }
    }

    Context 'Extension Handling' {
        BeforeEach {
            $script:testFile = Join-Path -Path $script:testRoot -ChildPath 'file.txt'
            'test content' | Out-File -FilePath $script:testFile -Encoding UTF8
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should remove file extension' {
            Rename-File -LiteralPath $script:testFile -RemoveExtension
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'file') | Should -Be $true
        }

        It 'Should change file extension' {
            Rename-File -LiteralPath $script:testFile -NewExtension '.dat'
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'file.dat') | Should -Be $true
        }
    }

    Context 'Text Replacement' {
        BeforeEach {
            $script:testFile = Join-Path -Path $script:testRoot -ChildPath 'old_file_test.txt'
            'test content' | Out-File -FilePath $script:testFile -Encoding UTF8
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should replace text using hashtable' {
            Rename-File -LiteralPath $script:testFile -Replace @{ 'old' = 'new'; 'test' = 'prod' }
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'new_file_prod.txt') | Should -Be $true
        }

        It 'Should replace text using regex pattern' {
            Rename-File -LiteralPath $script:testFile -RegexReplace @{ '_\w+_' = '_' }
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'old_test.txt') | Should -Be $true
        }
    }

    Context 'Expression-Based Transformation' {
        BeforeEach {
            $script:testFile = Join-Path -Path $script:testRoot -ChildPath 'long_filename_test.txt'
            'test content' | Out-File -FilePath $script:testFile -Encoding UTF8
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should apply script block transformation' {
            Rename-File -LiteralPath $script:testFile -Expression { $_.Substring(0, 4) }
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'long.txt') | Should -Be $true
        }

        It 'Should apply script block with string manipulation' {
            Rename-File -LiteralPath $script:testFile -Expression { "backup_$_" }
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'backup_long_filename_test.txt') | Should -Be $true
        }
    }

    Context 'Counter Functionality' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
            # Create multiple test files
            1..3 | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath "file$_.txt"
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should add counter with default format (D3)' {
            Get-ChildItem -Path $script:testRoot -Filter 'file*.txt' | Rename-File -Prepend 'img_' -Counter
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'img_file1001.txt') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'img_file2002.txt') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'img_file3003.txt') | Should -Be $true
        }

        It 'Should add counter with custom format (D2)' {
            Get-ChildItem -Path $script:testRoot -Filter 'file*.txt' | Rename-File -Prepend 'doc_' -Counter -CounterFormat 'D2'
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'doc_file101.txt') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'doc_file202.txt') | Should -Be $true
        }

        It 'Should add counter with custom start value' {
            Get-ChildItem -Path $script:testRoot -Filter 'file*.txt' | Rename-File -Prepend 'test_' -Counter -CounterStart 10
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test_file1010.txt') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test_file2011.txt') | Should -Be $true
        }
    }

    Context 'NewName with Counter Format' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
            # Create multiple test files
            1..3 | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath "IMG_$_.jpg"
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should use NewName with counter placeholder' {
            Get-ChildItem -Path $script:testRoot -Filter 'IMG_*.jpg' | Rename-File -NewName 'photo_{0:D4}.jpg' -Counter
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'photo_0001.jpg') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'photo_0002.jpg') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'photo_0003.jpg') | Should -Be $true
        }
    }

    Context 'Conflict Resolution' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
            $script:testFile1 = Join-Path -Path $script:testRoot -ChildPath 'file1.txt'
            $script:testFile2 = Join-Path -Path $script:testRoot -ChildPath 'file2.txt'
            'content1' | Out-File -FilePath $script:testFile1 -Encoding UTF8
            'content2' | Out-File -FilePath $script:testFile2 -Encoding UTF8
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should create unique filename when conflict exists' {
            # First, rename file2 to target name
            'target' | Out-File -FilePath (Join-Path -Path $script:testRoot -ChildPath 'target.txt') -Encoding UTF8

            # Now try to rename file1 to same name - should create unique name
            Rename-File -LiteralPath $script:testFile1 -NewName 'target.txt'
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'target_2.txt') | Should -Be $true
        }
    }

    Context 'Combined Transformations' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
            $script:testFile = Join-Path -Path $script:testRoot -ChildPath 'Test File Name.txt'
            'test content' | Out-File -FilePath $script:testFile -Encoding UTF8
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should apply multiple transformations in correct order' {
            Rename-File -LiteralPath $script:testFile -ReplaceSpacesWith '_' -ToLower -Prepend '2024_'
            Test-Path (Join-Path -Path $script:testRoot -ChildPath '2024_test_file_name.txt') | Should -Be $true
        }

        It 'Should combine normalization, case conversion, and whitespace replacement' {
            $testFile2 = Join-Path -Path $script:testRoot -ChildPath 'Café File.txt'
            'content' | Out-File -FilePath $testFile2 -Encoding UTF8
            Rename-File -LiteralPath $testFile2 -Normalize -ToLower -ReplaceSpacesWith '-'
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'cafe-file.txt') | Should -Be $true
        }
    }

    Context 'Cross-Platform Sanitization' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should sanitize filename for cross-platform compatibility' {
            $testFile = Join-Path -Path $script:testRoot -ChildPath 'file_test.txt'
            'content' | Out-File -FilePath $testFile -Encoding UTF8
            # After sanitization, colons should be replaced
            Rename-File -LiteralPath $testFile -SanitizeForCrossPlatform
            $result = Get-ChildItem -Path $script:testRoot -File
            $result.Name | Should -Match '^file_test\.txt$'
        }
    }

    Context 'PassThru Parameter' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
            $script:testFile = Join-Path -Path $script:testRoot -ChildPath 'test.txt'
            'content' | Out-File -FilePath $script:testFile -Encoding UTF8
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should return FileInfo object when PassThru is specified' {
            $result = Rename-File -LiteralPath $script:testFile -ToUpper -PassThru
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [System.IO.FileInfo]
            $result.Name | Should -Be 'TEST.TXT'
        }
    }

    Context 'Wildcard Support' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
            # Create multiple test files
            1..3 | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath "test$_.txt"
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should process multiple files with wildcard pattern' {
            Rename-File -Path (Join-Path -Path $script:testRoot -ChildPath 'test*.txt') -ToUpper
            $files = Get-ChildItem -Path $script:testRoot -File | Sort-Object Name
            $files | Should -HaveCount 3
            $files[0].Name | Should -Be 'TEST1.TXT'
            $files[1].Name | Should -Be 'TEST2.TXT'
            $files[2].Name | Should -Be 'TEST3.TXT'
        }
    }

    Context 'Error Handling' {
        It 'Should handle non-existent file gracefully' {
            { Rename-File -Path 'C:\NonExistent\File.txt' -ToUpper -ErrorAction Stop } | Should -Throw
        }

        It 'Should skip directories when not using Recurse' {
            $testDir = Join-Path -Path $script:testRoot -ChildPath 'TestDir'
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null
            { Rename-File -Path $testDir -ToUpper -WarningAction SilentlyContinue } | Should -Not -Throw
            Remove-Item -Path $testDir -Force
        }
    }

    Context 'WhatIf Support' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
            $script:testFile = Join-Path -Path $script:testRoot -ChildPath 'test.txt'
            'content' | Out-File -FilePath $script:testFile -Encoding UTF8
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force
        }

        It 'Should not rename file when WhatIf is specified' {
            Rename-File -LiteralPath $script:testFile -ToUpper -WhatIf
            Test-Path $script:testFile | Should -Be $true
            # On case-insensitive file systems, TEST.TXT and test.txt are the same file
            # Verify the actual file name hasn't changed by checking the FileInfo object
            $actualFile = Get-Item -LiteralPath $script:testFile
            $actualFile.Name | Should -Be 'test.txt'
        }
    }
}
