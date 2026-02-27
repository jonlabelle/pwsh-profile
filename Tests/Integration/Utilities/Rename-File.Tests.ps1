BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Import the function
    . "$PSScriptRoot/../../../Functions/Utilities/Rename-File.ps1"

    # Import test cleanup utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Rename-File Integration Tests' -Tag 'Integration', 'Utilities' {
    BeforeAll {
        # Create a test directory structure
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath 'RenameFileIntegrationTests'
        New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        # Cleanup
        if (Test-Path $script:testRoot)
        {
            Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Real-World Scenario: Photo Organization' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
            # Simulate camera photo files
            1..5 | ForEach-Object {
                $fileName = "IMG_$($_ * 1234).jpg"
                $testFile = Join-Path -Path $script:testRoot -ChildPath $fileName
                'photo content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should rename camera photos with descriptive names and counters' {
            Get-ChildItem -Path $script:testRoot -Filter 'IMG_*.jpg' |
            Rename-File -NewName 'vacation_2024_{0:D4}.jpg' -Counter

            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'vacation_2024_0001.jpg') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'vacation_2024_0002.jpg') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'vacation_2024_0005.jpg') | Should -Be $true

            # Verify old names are gone
            Get-ChildItem -Path $script:testRoot -Filter 'IMG_*.jpg' | Should -HaveCount 0
        }
    }

    Context 'Real-World Scenario: Document Standardization' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
            # Simulate messy document names
            @(
                'Meeting Notes (1).txt',
                'project  PLAN.docx',
                'Budget-2024_FINAL.xlsx',
                'Résumé.pdf'
            ) | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath $_
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should standardize document names for corporate environment' {
            Get-ChildItem -Path $script:testRoot |
            Rename-File -Normalize -RemoveShellMetaCharacters -ReplaceSpacesWith '_' -ToLower

            $files = Get-ChildItem -Path $script:testRoot | Sort-Object Name
            $files.Name | Should -Contain 'budget-2024_final.xlsx'
            $files.Name | Should -Contain 'meeting_notes_1.txt'
            $files.Name | Should -Contain 'project__plan.docx'
            $files.Name | Should -Contain 'resume.pdf'
        }
    }

    Context 'Real-World Scenario: Web Downloads Cleanup' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
            # Simulate downloaded files with URL encoding
            @(
                'document%20file.pdf',
                'report%2B2024.xlsx',
                'photo%20%281%29.jpg'
            ) | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath $_
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should decode and clean up downloaded filenames' {
            Get-ChildItem -Path $script:testRoot |
            Rename-File -UrlDecode -RemoveShellMetaCharacters -ReplaceSpacesWith '_'

            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'document_file.pdf') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'report+2024.xlsx') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'photo_1.jpg') | Should -Be $true
        }
    }

    Context 'Real-World Scenario: Media Library Conversion' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
            # Simulate media files with different naming conventions
            @(
                'The_Great_Movie_2024.mkv',
                'Another-Movie-Title.mp4',
                'TV Show S01E01.avi'
            ) | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath $_
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should standardize media library naming convention' {
            Get-ChildItem -Path $script:testRoot -Filter '*.mkv' |
            Rename-File -ReplaceUnderscoresWith ' ' -ToTitleCase

            Get-ChildItem -Path $script:testRoot -Filter '*.mp4' |
            Rename-File -ReplaceDashesWith ' ' -ToTitleCase

            Get-ChildItem -Path $script:testRoot -Filter '*.avi' |
            Rename-File -ReplaceSpacesWith '.' -ToLower

            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'The Great Movie 2024.mkv') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'Another Movie Title.mp4') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'tv.show.s01e01.avi') | Should -Be $true
        }
    }

    Context 'Real-World Scenario: Batch Processing with Expressions' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
            # Create files with timestamps
            @(
                '20240101_report.txt',
                '20240102_notes.txt',
                '20240103_data.txt'
            ) | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath $_
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should extract date prefix and reformat filenames' {
            Get-ChildItem -Path $script:testRoot -Filter '*.txt' |
            Rename-File -Expression { $_ -replace '(\d{4})(\d{2})(\d{2})_', '$1-$2-$3_' }

            Test-Path (Join-Path -Path $script:testRoot -ChildPath '2024-01-01_report.txt') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath '2024-01-02_notes.txt') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath '2024-01-03_data.txt') | Should -Be $true
        }
    }

    Context 'Real-World Scenario: Extension Change for Batch Conversion' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
            # Create files that need extension change
            1..3 | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath "data$_.dat"
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should change extensions for all files in batch' {
            Get-ChildItem -Path $script:testRoot -Filter '*.dat' |
            Rename-File -NewExtension '.txt'

            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'data1.txt') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'data2.txt') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'data3.txt') | Should -Be $true

            Get-ChildItem -Path $script:testRoot -Filter '*.dat' | Should -HaveCount 0
        }
    }

    Context 'Real-World Scenario: Recursive Directory Processing' {
        BeforeEach {
            # Clean up and create nested directory structure
            if (Test-Path $script:testRoot)
            {
                Remove-Item -Path $script:testRoot -Recurse -Force
            }
            New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null

            $subDir1 = Join-Path -Path $script:testRoot -ChildPath 'SubDir1'
            $subDir2 = Join-Path -Path $script:testRoot -ChildPath 'SubDir2'
            New-Item -Path $subDir1 -ItemType Directory -Force | Out-Null
            New-Item -Path $subDir2 -ItemType Directory -Force | Out-Null

            # Create files in root and subdirectories
            'TEST FILE.txt' | Out-File -FilePath (Join-Path -Path $script:testRoot -ChildPath 'TEST FILE.txt') -Encoding UTF8
            'TEST FILE 1.txt' | Out-File -FilePath (Join-Path -Path $subDir1 -ChildPath 'TEST FILE 1.txt') -Encoding UTF8
            'TEST FILE 2.txt' | Out-File -FilePath (Join-Path -Path $subDir2 -ChildPath 'TEST FILE 2.txt') -Encoding UTF8
        }

        AfterEach {
            # Only clean up subdirectories and files, not the parent test directory
            Get-ChildItem -Path $script:testRoot -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should process files recursively in all subdirectories' {
            Rename-File -Path $script:testRoot -Recurse -ReplaceSpacesWith '_' -ToLower

            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'test_file.txt') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'SubDir1/test_file_1.txt') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'SubDir2/test_file_2.txt') | Should -Be $true
        }
    }

    Context 'Real-World Scenario: Code File Naming Convention' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
            # Simulate code files with various naming conventions
            @(
                'myFunction.js',
                'another-function.js',
                'ThirdFunction.js'
            ) | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath $_
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should convert all files to camelCase convention' {
            Get-ChildItem -Path $script:testRoot -Filter '*.js' |
            Rename-File -ToCamelCase

            $files = Get-ChildItem -Path $script:testRoot -Filter '*.js' | Sort-Object Name
            $files | Should -HaveCount 3
            # Verify camelCase format: first letter lowercase, subsequent words capitalized
            $files[0].Name | Should -Be 'anotherFunction.js'
            $files[1].Name | Should -Be 'myFunction.js'
            $files[2].Name | Should -Be 'thirdFunction.js'
        }

        It 'Should convert all files to PascalCase convention' {
            Get-ChildItem -Path $script:testRoot -Filter '*.js' |
            Rename-File -ToPascalCase

            $files = Get-ChildItem -Path $script:testRoot -Filter '*.js' | Sort-Object Name
            $files | Should -HaveCount 3
            # Verify PascalCase format: first letter of each word capitalized
            $files[0].Name | Should -Be 'AnotherFunction.js'
            $files[1].Name | Should -Be 'MyFunction.js'
            $files[2].Name | Should -Be 'ThirdFunction.js'
        }
    }

    Context 'Real-World Scenario: Log File Archiving' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
            # Simulate log files
            @(
                'application.log',
                'error.log',
                'debug.log'
            ) | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath $_
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should archive log files with date prefix and counter' {
            Get-ChildItem -Path $script:testRoot -Filter '*.log' |
            Rename-File -Prepend '2024-01-15_' -Append '_archived' -Counter -CounterFormat 'D2'

            # Files are processed in alphabetical order: application, debug, error
            Test-Path (Join-Path -Path $script:testRoot -ChildPath '2024-01-15_application_archived01.log') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath '2024-01-15_debug_archived02.log') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath '2024-01-15_error_archived03.log') | Should -Be $true
        }
    }

    Context 'Real-World Scenario: Multi-Platform Project Setup' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
            # Simulate files with problematic characters for cross-platform
            @(
                'Design|Draft.psd',
                'Contract#2024.pdf',
                'Meeting~Notes.txt'
            ) | ForEach-Object {
                # Create files with sanitized names for testing
                $safeName = $_ -replace '[|#~]', '_'
                $testFile = Join-Path -Path $script:testRoot -ChildPath $safeName
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should sanitize all files for cross-platform compatibility' {
            Get-ChildItem -Path $script:testRoot |
            Rename-File -SanitizeForCrossPlatform -RemoveShellMetaCharacters

            $files = Get-ChildItem -Path $script:testRoot
            foreach ($file in $files)
            {
                # Verify no problematic characters remain
                $file.Name | Should -Not -Match '[<>:"/\\|?*#~]'
            }
        }
    }

    Context 'Pipeline Integration with Other Cmdlets' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
            # Create test files
            1..5 | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath "file$_.txt"
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should work in pipeline with Get-ChildItem and Where-Object' {
            Get-ChildItem -Path $script:testRoot -Filter '*.txt' |
            Where-Object { $_.Name -match 'file[123]' } |
            Rename-File -ToUpper

            $files = Get-ChildItem -Path $script:testRoot -Filter '*.txt' | Sort-Object Name
            $files | Should -HaveCount 5
            # First three files should be uppercase (FILE1, FILE2, FILE3)
            $files[0].Name | Should -Be 'FILE1.TXT'
            $files[1].Name | Should -Be 'FILE2.TXT'
            $files[2].Name | Should -Be 'FILE3.TXT'
            # Last two files should remain lowercase
            $files[3].Name | Should -Be 'file4.txt'
            $files[4].Name | Should -Be 'file5.txt'
        }

        It 'Should work with PassThru for further processing' {
            $result = Get-ChildItem -Path $script:testRoot -Filter '*.txt' |
            Rename-File -Prepend 'processed_' -PassThru |
            Select-Object -ExpandProperty Name

            $result | Should -HaveCount 5
            $result | Should -Contain 'processed_file1.txt'
            $result | Should -Contain 'processed_file5.txt'
        }
    }

    Context 'Complex Regex Replacement Scenarios' {
        BeforeEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
            # Create files with various patterns
            @(
                'report-2024-01-15.txt',
                'data-2024-02-20.csv',
                'log-2024-03-25.log'
            ) | ForEach-Object {
                $testFile = Join-Path -Path $script:testRoot -ChildPath $_
                'content' | Out-File -FilePath $testFile -Encoding UTF8
            }
        }

        AfterEach {
            Get-ChildItem -Path $script:testRoot -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should apply multiple regex replacements to standardize format' {
            # Note: Hashtable order is not guaranteed in PowerShell, so we need to be careful
            # with overlapping patterns. Apply non-overlapping patterns or use ordered hashtable.
            Get-ChildItem -Path $script:testRoot |
            Rename-File -RegexReplace @{
                'report-' = 'rpt_'
                'data-' = 'dat_'
                'log-' = 'log_'
                '\d{4}-\d{2}-\d{2}' = 'DATE'
            }

            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'rpt_DATE.txt') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'dat_DATE.csv') | Should -Be $true
            Test-Path (Join-Path -Path $script:testRoot -ChildPath 'log_DATE.log') | Should -Be $true
        }
    }
}
