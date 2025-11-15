#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Search-FileContent function.

.DESCRIPTION
    Integration tests that verify Search-FileContent works correctly in real-world scenarios
    with actual file systems, complex directory structures, and various file types.

.NOTES
    These tests verify:
    - Real directory tree searches
    - Performance with multiple files
    - Combined filter scenarios
    - Complex regex patterns in real files
    - Output formatting and display
    - Integration with PowerShell pipeline
    - Large file handling
    - Mixed file type handling
#>

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../../Functions/Utilities/Search-FileContent.ps1"

    # Import cleanup utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Search-FileContent Integration Tests' {
    Context 'Real-World Directory Search' {
        BeforeAll {
            # Create a realistic project structure
            $script:projectDir = Join-Path $TestDrive 'TestProject'
            New-Item -ItemType Directory -Path $script:projectDir -Force | Out-Null

            # Create source directory
            $srcDir = Join-Path $script:projectDir 'src'
            New-Item -ItemType Directory -Path $srcDir -Force | Out-Null

            # Create PowerShell files
            @'
function Get-UserData {
    param([string]$UserId)
    # TODO: Implement error handling
    Write-Verbose "Getting data for user $UserId"
    return $userData
}
'@ | Set-Content -Path (Join-Path $srcDir 'UserModule.ps1')

            @'
function Set-UserData {
    param([string]$UserId, [object]$Data)
    # TODO: Add validation
    Write-Host "Setting data for user $UserId"
    $script:userData = $Data
}
'@ | Set-Content -Path (Join-Path $srcDir 'DataModule.ps1')

            # Create tests directory
            $testsDir = Join-Path $script:projectDir 'tests'
            New-Item -ItemType Directory -Path $testsDir -Force | Out-Null

            @'
Describe 'UserModule Tests' {
    It 'Should get user data' {
        # TODO: Write actual test
        $result = Get-UserData -UserId '123'
        $result | Should -Not -BeNullOrEmpty
    }
}
'@ | Set-Content -Path (Join-Path $testsDir 'UserModule.Tests.ps1')

            # Create config files
            @'
{
    "version": "1.0.0",
    "author": "Test Author",
    "description": "Test project configuration"
}
'@ | Set-Content -Path (Join-Path $script:projectDir 'config.json')

            @'
# Test Project

TODO: Add project description

## Installation

TODO: Add installation instructions

## Usage

Write-Host "Example usage"
'@ | Set-Content -Path (Join-Path $script:projectDir 'README.md')

            # Create .git directory (should be excluded)
            $gitDir = Join-Path $script:projectDir '.git'
            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            'TODO: This should be ignored' | Set-Content -Path (Join-Path $gitDir 'config')
        }

        AfterAll {
            Remove-TestDirectory -Path $script:projectDir
        }

        It 'Should find all TODO comments across project' {
            $results = Search-FileContent -Pattern 'TODO:' -Path $script:projectDir -Simple
            # Should find TODOs in src files, test files, and README, but not in .git
            $results.Count | Should -BeGreaterOrEqual 4
            $results.Path | Should -Not -BeLike '*.git*'
        }

        It 'Should find function declarations in PowerShell files' {
            $results = Search-FileContent -Pattern 'function\s+\w+-\w+' -Path $script:projectDir -Include '*.ps1' -Simple
            # Should find Get-UserData and Set-UserData
            $results.Count | Should -BeGreaterOrEqual 2
        }

        It 'Should exclude test files when requested' {
            $results = Search-FileContent -Pattern 'TODO' -Path $script:projectDir -Exclude '*.Tests.ps1' -Simple
            $results.Path | Should -Not -BeLike '*Tests.ps1'
        }

        It 'Should search only PowerShell files' {
            $results = Search-FileContent -Pattern 'Write-' -Path $script:projectDir -Include '*.ps1' -Simple
            $results.Count | Should -BeGreaterOrEqual 2
            $results.Path | ForEach-Object { $_ | Should -BeLike '*.ps1' }
        }

        It 'Should find matches with context lines' {
            $results = Search-FileContent -Pattern 'function Get-UserData' -Path $script:projectDir -Simple -Before 0 -After 2
            $results | Should -Not -BeNullOrEmpty
            # Verify it's finding the function
            $results[0].Line | Should -BeLike '*Get-UserData*'
        }
    }

    Context 'Complex Regex Patterns' {
        BeforeAll {
            $script:codeDir = Join-Path $TestDrive 'CodeSamples'
            New-Item -ItemType Directory -Path $script:codeDir -Force | Out-Null

            # Create file with various patterns
            @'
192.168.1.1
10.0.0.1
256.1.1.1
test@example.com
user@domain.co.uk
invalid@email
function Test-Connection { }
function Get-Item { }
$variable = "value"
$another_var = 123
camelCaseVariable = true
'@ | Set-Content -Path (Join-Path $script:codeDir 'patterns.txt')
        }

        AfterAll {
            Remove-TestDirectory -Path $script:codeDir
        }

        It 'Should find valid IP addresses' {
            $pattern = '\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'
            $results = Search-FileContent -Pattern $pattern -Path $script:codeDir -Simple
            # Should find 192.168.1.1 and 10.0.0.1, but not 256.1.1.1
            $results.Count | Should -Be 2
        }

        It 'Should find email addresses' {
            $pattern = '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'
            $results = Search-FileContent -Pattern $pattern -Path $script:codeDir -Simple
            # Should find test@example.com and user@domain.co.uk
            $results.Count | Should -BeGreaterOrEqual 2
        }

        It 'Should find PowerShell function declarations' {
            $pattern = 'function\s+[A-Z][a-z]+-[A-Z][a-z]+'
            $results = Search-FileContent -Pattern $pattern -Path $script:codeDir -Simple
            # Should find Test-Connection and Get-Item
            $results.Count | Should -Be 2
        }

        It 'Should find PowerShell variables' {
            $pattern = '\$[a-zA-Z_][a-zA-Z0-9_]*'
            $results = Search-FileContent -Pattern $pattern -Path $script:codeDir -Simple
            # Should find $variable and $another_var
            $results.Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Pipeline Integration' {
        BeforeAll {
            $script:pipelineDir = Join-Path $TestDrive 'PipelineTest'
            New-Item -ItemType Directory -Path $script:pipelineDir -Force | Out-Null

            # Create multiple files
            1..5 | ForEach-Object {
                "This is file $_ with MATCH" | Set-Content -Path (Join-Path $script:pipelineDir "file$_.txt")
            }

            # Create some files without matches
            1..3 | ForEach-Object {
                'This is file without pattern' | Set-Content -Path (Join-Path $script:pipelineDir "other$_.txt")
            }
        }

        AfterAll {
            Remove-TestDirectory -Path $script:pipelineDir
        }

        It 'Should work with Get-ChildItem pipeline' {
            $results = Get-ChildItem $script:pipelineDir -Filter 'file*.txt' | Search-FileContent -Pattern 'MATCH' -Simple
            $results.Count | Should -Be 5
        }

        It 'Should work with Where-Object in pipeline' {
            $results = Get-ChildItem $script:pipelineDir -File |
            Where-Object { $_.Name -like 'file*' } |
            Search-FileContent -Pattern 'MATCH' -Simple
            $results.Count | Should -Be 5
        }

        It 'Should chain with other cmdlets' {
            $fileNames = Get-ChildItem $script:pipelineDir -Filter 'file*.txt' |
            Search-FileContent -Pattern 'MATCH' -FilesOnly -Simple |
            ForEach-Object { Split-Path $_.Path -Leaf }

            $fileNames.Count | Should -Be 5
            $fileNames | Should -Contain 'file1.txt'
        }
    }

    Context 'Performance with Multiple Files' {
        BeforeAll {
            $script:perfDir = Join-Path $TestDrive 'PerformanceTest'
            New-Item -ItemType Directory -Path $script:perfDir -Force | Out-Null

            # Create many files (50 files)
            1..50 | ForEach-Object {
                $content = @"
Line 1 of file $_
Line 2 with MATCH in file $_
Line 3 of file $_
Line 4 of file $_
Line 5 with another MATCH
"@
                Set-Content -Path (Join-Path $script:perfDir "file$_.txt") -Value $content
            }
        }

        AfterAll {
            Remove-TestDirectory -Path $script:perfDir
        }

        It 'Should search many files efficiently' {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:perfDir -Simple
            $stopwatch.Stop()

            # Should find 2 matches per file * 50 files = 100 matches
            $results.Count | Should -Be 100

            # Should complete in reasonable time (less than 5 seconds for 50 files)
            $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 5
        }

        It 'Should count matches efficiently' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:perfDir -CountOnly -Simple
            $results.Count | Should -Be 50
            $results | ForEach-Object { $_.MatchCount | Should -Be 2 }
        }
    }

    Context 'Mixed File Types' {
        BeforeAll {
            $script:mixedDir = Join-Path $TestDrive 'MixedTypes'
            New-Item -ItemType Directory -Path $script:mixedDir -Force | Out-Null

            # PowerShell script
            'function Test-PATTERN { }' | Set-Content -Path (Join-Path $script:mixedDir 'script.ps1')

            # JSON file
            '{"key": "PATTERN value"}' | Set-Content -Path (Join-Path $script:mixedDir 'config.json')

            # Markdown file
            '# Title with PATTERN' | Set-Content -Path (Join-Path $script:mixedDir 'README.md')

            # Log file
            '2024-01-01 12:00:00 ERROR PATTERN detected' | Set-Content -Path (Join-Path $script:mixedDir 'app.log')

            # XML file
            '<root><item>PATTERN</item></root>' | Set-Content -Path (Join-Path $script:mixedDir 'data.xml')
        }

        AfterAll {
            Remove-TestDirectory -Path $script:mixedDir
        }

        It 'Should search across different file types' {
            $results = Search-FileContent -Pattern 'PATTERN' -Path $script:mixedDir -Simple
            $results.Count | Should -Be 5
        }

        It 'Should filter by specific file types' {
            $results = Search-FileContent -Pattern 'PATTERN' -Path $script:mixedDir -Include '*.ps1', '*.md' -Simple
            $results.Count | Should -Be 2
        }

        It 'Should exclude specific file types' {
            $results = Search-FileContent -Pattern 'PATTERN' -Path $script:mixedDir -Exclude '*.log', '*.xml' -Simple
            $results.Count | Should -Be 3
        }
    }

    Context 'Large File Handling' {
        BeforeAll {
            $script:largeFileDir = Join-Path $TestDrive 'LargeFiles'
            New-Item -ItemType Directory -Path $script:largeFileDir -Force | Out-Null

            # Create a moderately large file (1000 lines)
            $largeContent = 1..1000 | ForEach-Object {
                if ($_ % 100 -eq 0)
                {
                    "Line $_ with MATCH"
                }
                else
                {
                    "Line $_ without pattern"
                }
            }
            $largeContent -join "`n" | Set-Content -Path (Join-Path $script:largeFileDir 'large.txt')
        }

        AfterAll {
            Remove-TestDirectory -Path $script:largeFileDir
        }

        It 'Should handle large files correctly' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:largeFileDir -Simple
            # Should find 10 matches (at lines 100, 200, 300, ..., 1000)
            $results.Count | Should -Be 10
        }

        It 'Should provide correct line numbers in large files' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:largeFileDir -Simple
            $results[0].LineNumber | Should -Be 100
            $results[9].LineNumber | Should -Be 1000
        }
    }

    Context 'Special Characters and Encodings' {
        BeforeAll {
            $script:specialDir = Join-Path $TestDrive 'SpecialChars'
            New-Item -ItemType Directory -Path $script:specialDir -Force | Out-Null

            # File with special characters
            @'
Line with special chars: !@#$%^&*()
Line with brackets: [PATTERN]
Line with braces: {PATTERN}
Line with parentheses: (PATTERN)
Line with quotes: "PATTERN" and 'PATTERN'
Line with backslash: \PATTERN\
'@ | Set-Content -Path (Join-Path $script:specialDir 'special.txt')
        }

        AfterAll {
            Remove-TestDirectory -Path $script:specialDir
        }

        It 'Should find patterns with special characters around them' {
            $results = Search-FileContent -Pattern 'PATTERN' -Path $script:specialDir -Simple
            $results.Count | Should -BeGreaterOrEqual 5
        }

        It 'Should handle bracket patterns with literal matching' {
            $results = @(Search-FileContent -Pattern '[PATTERN]' -Path $script:specialDir -Simple -Literal)
            $results.Count | Should -Be 1
            $results[0].Line | Should -BeLike '*[PATTERN]*'
        }

        It 'Should handle regex special characters properly' {
            $results = @(Search-FileContent -Pattern '\[PATTERN\]' -Path $script:specialDir -Simple)
            $results.Count | Should -Be 1
        }
    }

    Context 'Nested Directory Structures' {
        BeforeAll {
            $script:nestedDir = Join-Path $TestDrive 'NestedStructure'
            New-Item -ItemType Directory -Path $script:nestedDir -Force | Out-Null

            # Create deep nested structure
            $current = $script:nestedDir
            1..5 | ForEach-Object {
                $current = Join-Path $current "level$_"
                New-Item -ItemType Directory -Path $current -Force | Out-Null
                "MATCH at level $_" | Set-Content -Path (Join-Path $current "file$_.txt")
            }
        }

        AfterAll {
            Remove-TestDirectory -Path $script:nestedDir
        }

        It 'Should search deep nested directories' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:nestedDir -Simple
            $results.Count | Should -Be 5
        }

        It 'Should respect MaxDepth limitation' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:nestedDir -Simple -MaxDepth 2
            # Should only find matches in level1 and level2
            $results.Count | Should -BeLessOrEqual 2
        }

        It 'Should not recurse with -NoRecurse' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:nestedDir -Simple -NoRecurse
            # Should find no files since there are no files at root level
            $results | Should -BeNullOrEmpty
        }
    }

    Context 'Output Mode Comparisons' {
        BeforeAll {
            $script:outputDir = Join-Path $TestDrive 'OutputModes'
            New-Item -ItemType Directory -Path $script:outputDir -Force | Out-Null

            @'
First line with MATCH
Second line
Third line with MATCH
Fourth line
Fifth line with MATCH
'@ | Set-Content -Path (Join-Path $script:outputDir 'test.txt')
        }

        AfterAll {
            Remove-TestDirectory -Path $script:outputDir
        }

        It 'Should provide detailed results in Simple mode' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:outputDir -Simple
            $results.Count | Should -Be 3
            $results[0].PSObject.Properties.Name | Should -Contain 'Path'
            $results[0].PSObject.Properties.Name | Should -Contain 'LineNumber'
            $results[0].PSObject.Properties.Name | Should -Contain 'Line'
            $results[0].PSObject.Properties.Name | Should -Contain 'Match'
        }

        It 'Should provide count in CountOnly mode' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:outputDir -CountOnly -Simple
            $results.MatchCount | Should -Be 3
        }

        It 'Should provide only paths in FilesOnly mode' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:outputDir -FilesOnly -Simple
            $results.PSObject.Properties.Name | Should -Contain 'Path'
            $results.PSObject.Properties.Name | Should -Not -Contain 'LineNumber'
        }
    }
}
