#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Search-FileContent function.

.DESCRIPTION
    Tests the Search-FileContent function which provides advanced file searching
    capabilities beyond grep, including regex patterns, context lines, file filtering,
    and multiple output modes.

.NOTES
    These tests verify:
    - Parameter validation and defaults
    - Basic pattern matching (literal and regex)
    - Case sensitivity and insensitivity
    - Context line handling (before, after, combined)
    - Output modes (default, simple, count-only, files-only)
    - File filtering (include, exclude)
    - Directory exclusion
    - Binary file detection and skipping
    - Line number display
    - Pipeline input support
    - Error handling
#>

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../../Functions/Utilities/Search-FileContent.ps1"
}

Describe 'Search-FileContent' {
    Context 'Parameter Validation' {
        It 'Should have mandatory Pattern parameter' {
            $command = Get-Command Search-FileContent
            $patternParam = $command.Parameters['Pattern']
            $patternParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have optional Path parameter with default value' {
            $command = Get-Command Search-FileContent
            $pathParam = $command.Parameters['Path']
            $pathParam.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should accept pipeline input for Path' {
            $command = Get-Command Search-FileContent
            $pathParam = $command.Parameters['Path']
            $pathParam.Attributes.ValueFromPipeline | Should -Contain $true
        }

        It 'Should validate Context parameter range' {
            $command = Get-Command Search-FileContent
            $contextParam = $command.Parameters['Context']
            $validateRange = $contextParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $validateRange.MinRange | Should -Be 0
            $validateRange.MaxRange | Should -Be 100
        }

        It 'Should validate Before parameter range' {
            $command = Get-Command Search-FileContent
            $beforeParam = $command.Parameters['Before']
            $validateRange = $beforeParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $validateRange.MinRange | Should -Be 0
            $validateRange.MaxRange | Should -Be 100
        }

        It 'Should validate After parameter range' {
            $command = Get-Command Search-FileContent
            $afterParam = $command.Parameters['After']
            $validateRange = $afterParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $validateRange.MinRange | Should -Be 0
            $validateRange.MaxRange | Should -Be 100
        }

        It 'Should validate MaxDepth parameter range' {
            $command = Get-Command Search-FileContent
            $maxDepthParam = $command.Parameters['MaxDepth']
            $validateRange = $maxDepthParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $validateRange.MinRange | Should -Be 1
            $validateRange.MaxRange | Should -Be 100
        }

        It 'Should validate MaxFileSize parameter range' {
            $command = Get-Command Search-FileContent
            $maxSizeParam = $command.Parameters['MaxFileSize']
            $validateRange = $maxSizeParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $validateRange.MinRange | Should -Be 1
            $validateRange.MaxRange | Should -Be 10240
        }

        It 'Should have Context alias C' {
            $command = Get-Command Search-FileContent
            $contextParam = $command.Parameters['Context']
            $aliases = $contextParam.Aliases
            $aliases | Should -Contain 'C'
        }

        It 'Should have Before alias B' {
            $command = Get-Command Search-FileContent
            $beforeParam = $command.Parameters['Before']
            $aliases = $beforeParam.Aliases
            $aliases | Should -Contain 'B'
        }

        It 'Should have After alias A' {
            $command = Get-Command Search-FileContent
            $afterParam = $command.Parameters['After']
            $aliases = $afterParam.Aliases
            $aliases | Should -Contain 'A'
        }
    }

    Context 'Basic Pattern Matching' {
        BeforeAll {
            # Create test directory and files
            $script:testDir = Join-Path -Path $TestDrive -ChildPath 'SearchTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            # Test file 1: Simple content
            $testFile1 = Join-Path -Path $script:testDir -ChildPath 'test1.txt'
            @'
This is line one
This is line two with PATTERN
This is line three
This is line four with pattern again
This is line five
'@ | Set-Content -Path $testFile1 -NoNewline

            # Test file 2: Different content
            $testFile2 = Join-Path -Path $script:testDir -ChildPath 'test2.txt'
            @'
First line
Second line contains MATCH
Third line
'@ | Set-Content -Path $testFile2 -NoNewline

            # Test file 3: No matches
            $testFile3 = Join-Path -Path $script:testDir -ChildPath 'test3.txt'
            @'
Nothing here
Just some text
No matches
'@ | Set-Content -Path $testFile3 -NoNewline
        }

        It 'Should find matches in files with Simple output' {
            $results = Search-FileContent -Pattern 'pattern' -Path $script:testDir -Simple -CaseInsensitive
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -Be 2
        }

        It 'Should return correct line numbers' {
            $results = Search-FileContent -Pattern 'pattern' -Path $script:testDir -Simple -CaseInsensitive
            $results[0].LineNumber | Should -Be 2
            $results[1].LineNumber | Should -Be 4
        }

        It 'Should return correct line content' {
            $results = Search-FileContent -Pattern 'pattern' -Path $script:testDir -Simple -CaseInsensitive
            $results[0].Line | Should -BeLike '*PATTERN*'
            $results[1].Line | Should -BeLike '*pattern again*'
        }

        It 'Should return correct match value' {
            $results = Search-FileContent -Pattern 'PATTERN' -Path $script:testDir -Simple
            $results[0].Match | Should -Be 'PATTERN'
        }

        It 'Should respect case sensitivity by default' {
            $results = @(Search-FileContent -Pattern 'PATTERN' -Path $script:testDir -Simple)
            $results.Count | Should -Be 1
        }

        It 'Should work with case insensitive flag' {
            $results = Search-FileContent -Pattern 'PATTERN' -Path $script:testDir -Simple -CaseInsensitive
            $results.Count | Should -Be 2
        }

        It 'Should find no matches when pattern does not exist' {
            $results = Search-FileContent -Pattern 'NOTFOUND' -Path $script:testDir -Simple
            $results | Should -BeNullOrEmpty
        }
    }

    Context 'Literal vs Regex Matching' {
        BeforeAll {
            $script:testDir = Join-Path -Path $TestDrive -ChildPath 'RegexTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            $testFile = Join-Path -Path $script:testDir -ChildPath 'regex.txt'
            @'
test.file.name
test*file*name
test[file]name
function Test-Function
function Get-Item
192.168.1.1
10.0.0.1
'@ | Set-Content -Path $testFile -NoNewline
        }

        It 'Should treat pattern as literal when -Literal is used' {
            $results = @(Search-FileContent -Pattern 'test.file' -Path $script:testDir -Simple -Literal)
            $results.Count | Should -Be 1
            $results[0].Line | Should -Be 'test.file.name'
        }

        It 'Should treat pattern as regex by default' {
            $results = Search-FileContent -Pattern 'test.file' -Path $script:testDir -Simple
            # Regex . matches any character, so should match test*file and test[file] too
            $results.Count | Should -BeGreaterThan 1
        }

        It 'Should support regex character classes' {
            $results = Search-FileContent -Pattern '\d+\.\d+\.\d+\.\d+' -Path $script:testDir -Simple
            $results.Count | Should -Be 2
        }

        It 'Should support regex word boundaries' {
            $results = Search-FileContent -Pattern '\bfunction\b' -Path $script:testDir -Simple
            $results.Count | Should -Be 2
        }

        It 'Should throw error for invalid regex pattern' {
            { Search-FileContent -Pattern '(unclosed' -Path $script:testDir -Simple } | Should -Throw
        }
    }

    Context 'Context Lines' {
        BeforeAll {
            $script:testDir = Join-Path -Path $TestDrive -ChildPath 'ContextTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            $testFile = Join-Path -Path $script:testDir -ChildPath 'context.txt'
            @'
Line 1
Line 2
Line 3 MATCH
Line 4
Line 5
Line 6
Line 7 MATCH
Line 8
Line 9
'@ | Set-Content -Path $testFile -NoNewline
        }

        It 'Should return matches without context by default' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple
            $results.Count | Should -Be 2
            # Each result should have no context or minimal context
        }

        It 'Should handle -Context parameter' {
            # Context parameter provides before and after context
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -Context 1
            # Should find 2 matches
            $results.Count | Should -Be 2
        }

        It 'Should handle -Before parameter' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -Before 2
            $results.Count | Should -Be 2
        }

        It 'Should handle -After parameter' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -After 2
            $results.Count | Should -Be 2
        }

        It 'Should handle both -Before and -After parameters' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -Before 1 -After 1
            $results.Count | Should -Be 2
        }
    }

    Context 'File Filtering' {
        BeforeAll {
            $script:testDir = Join-Path -Path $TestDrive -ChildPath 'FilterTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            # Create different file types
            'MATCH in txt' | Set-Content -Path (Join-Path -Path $script:testDir -ChildPath 'file1.txt')
            'MATCH in ps1' | Set-Content -Path (Join-Path -Path $script:testDir -ChildPath 'file2.ps1')
            'MATCH in log' | Set-Content -Path (Join-Path -Path $script:testDir -ChildPath 'file3.log')
            'MATCH in md' | Set-Content -Path (Join-Path -Path $script:testDir -ChildPath 'readme.md')
        }

        It 'Should search all files when no filter specified' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple
            $results.Count | Should -Be 4
        }

        It 'Should filter files with -Include parameter' {
            $results = @(Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -Include '*.txt')
            $results.Count | Should -Be 1
            $results[0].Path | Should -Match 'file1\.txt$'
        }

        It 'Should support multiple include patterns' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -Include '*.txt', '*.ps1'
            $results.Count | Should -Be 2
        }

        It 'Should filter files with -Exclude parameter' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -Exclude '*.log'
            $results.Count | Should -Be 3
        }

        It 'Should support multiple exclude patterns' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -Exclude '*.log', '*.md'
            $results.Count | Should -Be 2
        }

        It 'Should combine include and exclude filters' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -Include '*.txt', '*.ps1', '*.log' -Exclude '*.log'
            $results.Count | Should -Be 2
        }
    }

    Context 'Directory Exclusion' {
        BeforeAll {
            $script:testDir = Join-Path -Path $TestDrive -ChildPath 'DirExcludeTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            # Create subdirectories
            $gitDir = Join-Path -Path $script:testDir -ChildPath '.git'
            $nodeDir = Join-Path -Path $script:testDir -ChildPath 'node_modules'
            $srcDir = Join-Path -Path $script:testDir -ChildPath 'src'

            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            New-Item -ItemType Directory -Path $nodeDir -Force | Out-Null
            New-Item -ItemType Directory -Path $srcDir -Force | Out-Null

            # Create files in different directories
            'MATCH in git' | Set-Content -Path (Join-Path -Path $gitDir -ChildPath 'config')
            'MATCH in node' | Set-Content -Path (Join-Path -Path $nodeDir -ChildPath 'package.json')
            'MATCH in src' | Set-Content -Path (Join-Path -Path $srcDir -ChildPath 'main.ps1')
        }

        It 'Should exclude .git directories by default' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple
            $results.Path | Should -Not -BeLike '*.git*'
        }

        It 'Should exclude node_modules directories by default' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple
            $results.Path | Should -Not -BeLike '*node_modules*'
        }

        It 'Should allow custom directory exclusions' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -ExcludeDirectory 'src'
            $results.Path | Should -Not -BeLike '*src*'
        }

        It 'Should support multiple directory exclusions' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -ExcludeDirectory '.git', 'node_modules', 'src'
            $results | Should -BeNullOrEmpty
        }
    }

    Context 'Output Modes' {
        BeforeAll {
            $script:testDir = Join-Path -Path $TestDrive -ChildPath 'OutputTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            $testFile = Join-Path -Path $script:testDir -ChildPath 'output.txt'
            @'
Line with MATCH
Another line
Yet another MATCH here
Final line
'@ | Set-Content -Path $testFile -NoNewline
        }

        It 'Should output objects in Simple mode' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple
            $results | Should -BeOfType [PSCustomObject]
            $results[0].PSObject.Properties.Name | Should -Contain 'Path'
            $results[0].PSObject.Properties.Name | Should -Contain 'LineNumber'
            $results[0].PSObject.Properties.Name | Should -Contain 'Line'
            $results[0].PSObject.Properties.Name | Should -Contain 'Match'
        }

        It 'Should output count with -CountOnly and -Simple' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -CountOnly -Simple
            $results | Should -BeOfType [PSCustomObject]
            $results.PSObject.Properties.Name | Should -Contain 'Path'
            $results.PSObject.Properties.Name | Should -Contain 'MatchCount'
            $results.MatchCount | Should -Be 2
        }

        It 'Should output only file paths with -FilesOnly and -Simple' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -FilesOnly -Simple
            $results | Should -BeOfType [PSCustomObject]
            $results.PSObject.Properties.Name | Should -Contain 'Path'
            $results.PSObject.Properties.Name | Should -Not -Contain 'LineNumber'
        }
    }

    Context 'Recursion and Depth' {
        BeforeAll {
            $script:testDir = Join-Path -Path $TestDrive -ChildPath 'RecursionTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            # Create nested directory structure
            $level1 = Join-Path -Path $script:testDir -ChildPath 'level1'
            $level2 = Join-Path -Path $level1 -ChildPath 'level2'
            $level3 = Join-Path -Path $level2 -ChildPath 'level3'

            New-Item -ItemType Directory -Path $level1 -Force | Out-Null
            New-Item -ItemType Directory -Path $level2 -Force | Out-Null
            New-Item -ItemType Directory -Path $level3 -Force | Out-Null

            'MATCH at root' | Set-Content -Path (Join-Path -Path $script:testDir -ChildPath 'root.txt')
            'MATCH at level1' | Set-Content -Path (Join-Path -Path $level1 -ChildPath 'file1.txt')
            'MATCH at level2' | Set-Content -Path (Join-Path -Path $level2 -ChildPath 'file2.txt')
            'MATCH at level3' | Set-Content -Path (Join-Path -Path $level3 -ChildPath 'file3.txt')
        }

        It 'Should search recursively by default' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple
            $results.Count | Should -Be 4
        }

        It 'Should not search recursively with -NoRecurse' {
            $results = @(Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -NoRecurse)
            $results.Count | Should -Be 1
            $results[0].Path | Should -Match 'root\.txt$'
        }

        It 'Should respect MaxDepth parameter' {
            $results = Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple -MaxDepth 1
            $results.Count | Should -BeLessOrEqual 2
        }
    }

    Context 'Pipeline Support' {
        BeforeAll {
            $script:testDir = Join-Path -Path $TestDrive -ChildPath 'PipelineTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            'MATCH in file1' | Set-Content -Path (Join-Path -Path $script:testDir -ChildPath 'file1.txt')
            'MATCH in file2' | Set-Content -Path (Join-Path -Path $script:testDir -ChildPath 'file2.txt')
        }

        It 'Should accept file objects from pipeline' {
            $results = Get-ChildItem $script:testDir -File | Search-FileContent -Pattern 'MATCH' -Simple
            $results.Count | Should -Be 2
        }

        It 'Should accept path strings from pipeline' {
            $results = (Get-ChildItem $script:testDir -File).FullName | Search-FileContent -Pattern 'MATCH' -Simple
            $results.Count | Should -Be 2
        }
    }

    Context 'Binary File Handling' {
        BeforeAll {
            $script:testDir = Join-Path -Path $TestDrive -ChildPath 'BinaryTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            # Create a binary-like file with null bytes
            $binaryFile = Join-Path -Path $script:testDir -ChildPath 'binary.dat'
            $bytes = [byte[]]@(0, 1, 2, 3, 0, 0, 77, 65, 84, 67, 72) # Contains "MATCH" in ASCII
            [System.IO.File]::WriteAllBytes($binaryFile, $bytes)

            # Create a text file
            'MATCH in text' | Set-Content -Path (Join-Path -Path $script:testDir -ChildPath 'text.txt')
        }

        It 'Should skip binary files' {
            $results = @(Search-FileContent -Pattern 'MATCH' -Path $script:testDir -Simple)
            # Should only find the text file, not the binary file
            $results.Count | Should -Be 1
            $results[0].Path | Should -BeLike '*text.txt'
        }
    }

    Context 'Error Handling' {
        It 'Should warn about non-existent paths' {
            $nonExistentPath = Join-Path -Path $TestDrive -ChildPath 'DoesNotExist'
            $null = Search-FileContent -Pattern 'test' -Path $nonExistentPath -Simple -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Should throw error for invalid regex' {
            $testFile = Join-Path -Path $TestDrive -ChildPath 'test.txt'
            'test' | Set-Content -Path $testFile
            { Search-FileContent -Pattern '[invalid' -Path $testFile -Simple } | Should -Throw
        }
    }

    Context 'Case Variations' {
        BeforeAll {
            $script:testDir = Join-Path -Path $TestDrive -ChildPath 'CaseVariationTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            # Create test file with various case patterns of 'username' (without separators)
            $testFile1 = Join-Path -Path $script:testDir -ChildPath 'code.js'
            @'
const userName = getUser();
const UserName = parseData();
const USERNAME = process.env.USERNAME;
let username = 'test';
const Username = config.Username;
'@ | Set-Content -Path $testFile1

            # Create another test file with different patterns
            $testFile2 = Join-Path -Path $script:testDir -ChildPath 'code.py'
            @'
username = get_user()
userName = some_function()
            USERNAME = constant_value
'@ | Set-Content -Path $testFile2

            # Create test file with separated patterns (NOW WILL match with separator-aware matching)
            $testFile3 = Join-Path -Path $script:testDir -ChildPath 'config.py'
            @'
user_name = dbQuery()
USER_NAME = config.USER_NAME
user-name = cssClass
USER-NAME = cssConstant
'@ | Set-Content -Path $testFile3
        }

        It 'Should throw error when IncludeCaseVariations used without CaseInsensitive' {
            { Search-FileContent -Pattern 'username' -Path $script:testDir -IncludeCaseVariations } | Should -Throw '*IncludeCaseVariations requires CaseInsensitive*'
        }

        It 'Should throw error when IncludeCaseVariations used with CountOnly' {
            { Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -CountOnly } | Should -Throw '*IncludeCaseVariations cannot be used with CountOnly*'
        }

        It 'Should throw error when IncludeCaseVariations used with FilesOnly' {
            { Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -FilesOnly } | Should -Throw '*IncludeCaseVariations cannot be used with FilesOnly*'
        }

        It 'Should throw error when IncludeCaseVariations used with Context' {
            { Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -Context 2 } | Should -Throw '*IncludeCaseVariations cannot be used with Context*'
        }

        It 'Should throw error when IncludeCaseVariations used with Before' {
            { Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -Before 2 } | Should -Throw '*IncludeCaseVariations cannot be used with*Before*'
        }

        It 'Should throw error when IncludeCaseVariations used with After' {
            { Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -After 2 } | Should -Throw '*IncludeCaseVariations cannot be used with*After*'
        }

        It 'Should detect all case variations in Simple mode' {
            $results = Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -Simple
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterThan 0
            # Should find these variations (not separated patterns like user_name)
            $results.Variation | Should -Contain 'userName'
            $results.Variation | Should -Contain 'UserName'
            $results.Variation | Should -Contain 'USERNAME'
            $results.Variation | Should -Contain 'username'
            $results.Variation | Should -Contain 'Username'
        }

        It 'Should count occurrences correctly' {
            $results = Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -Simple
            $userNameResult = $results | Where-Object { $_.Variation -ceq 'userName' }
            $userNameResult.Count | Should -Be 2  # Once in code.js, once in code.py
        }

        It 'Should track files for each variation' {
            $results = Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -Simple
            $usernameResult = $results | Where-Object { $_.Variation -ceq 'username' }
            $usernameResult.Files | Should -Contain (Join-Path -Path $script:testDir -ChildPath 'code.js')
        }

        It 'Should identify camelCase pattern' {
            $results = Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -Simple
            $camelResult = $results | Where-Object { $_.Variation -ceq 'userName' }
            $camelResult.CasePattern | Should -Be 'camelCase'
        }

        It 'Should identify PascalCase pattern' {
            $results = Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -Simple
            $pascalResult = $results | Where-Object { $_.Variation -ceq 'UserName' }
            $pascalResult.CasePattern | Should -Be 'PascalCase'
        }

        It 'Should identify UPPERCASE pattern' {
            $results = Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -Simple
            $upperResult = $results | Where-Object { $_.Variation -ceq 'USERNAME' }
            $upperResult.CasePattern | Should -Be 'UPPERCASE'
        }

        It 'Should identify lowercase pattern' {
            $results = Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -Simple
            $lowerResult = $results | Where-Object { $_.Variation -ceq 'username' }
            $lowerResult.CasePattern | Should -Be 'lowercase'
        }

        It 'Should identify First Capital pattern' {
            $results = Search-FileContent -Pattern 'username' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -Simple
            $firstCapResult = $results | Where-Object { $_.Variation -ceq 'Username' }
            $firstCapResult.CasePattern | Should -Be 'First Capital'
        }

        It 'Should match separated patterns like user_name and user-name with separator-aware matching' {
            # With separator-aware matching, IncludeCaseVariations automatically finds variations
            # across different separators (underscores, hyphens, spaces) when pattern has word boundaries
            $results = Search-FileContent -Pattern 'userName' -Path $script:testDir -CaseInsensitive -IncludeCaseVariations -Simple
            # These SHOULD be in the results because the pattern is separator-aware
            $results.Variation | Should -Contain 'user_name'
            $results.Variation | Should -Contain 'USER_NAME'
            $results.Variation | Should -Contain 'user-name'
        }
    }
}
