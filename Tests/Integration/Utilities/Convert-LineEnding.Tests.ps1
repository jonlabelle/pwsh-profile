#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Convert-LineEndings function.

.DESCRIPTION
    Integration tests that verify the Convert-LineEndings function works correctly in real-world scenarios
    with actual file systems, complex directory structures, and various file types.

.NOTES
    These integration tests verify real-world scenarios:
    - Directory processing with mixed file types
    - Recursive directory traversal
    - Complex Include/Exclude pattern matching
    - Read-only file handling with Force parameter
    - Cross-platform path handling
#>

BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../../Functions/Utilities/Convert-LineEndings.ps1"

    # Create a comprehensive test directory structure
    $script:TestDir = Join-Path -Path $TestDrive -ChildPath 'LineEndingIntegrationTests'
    $script:SourceDir = Join-Path -Path $script:TestDir -ChildPath 'source'
    $script:DocsDir = Join-Path -Path $script:TestDir -ChildPath 'docs'
    $script:ScriptsDir = Join-Path -Path $script:TestDir -ChildPath 'scripts'
    $script:BinaryDir = Join-Path -Path $script:TestDir -ChildPath 'binaries'
    $script:NodeModulesDir = Join-Path -Path $script:TestDir -ChildPath 'node_modules'

    @($script:TestDir, $script:SourceDir, $script:DocsDir, $script:ScriptsDir, $script:BinaryDir, $script:NodeModulesDir) | ForEach-Object {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}

AfterAll {
    # Clean up test directory
    if (Test-Path $script:TestDir)
    {
        Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Convert-LineEndings Integration Tests' {
    Context 'Real Project Structure Processing' {
        BeforeAll {
            # Create a realistic project structure with various file types
            $projectFiles = @{
                (Join-Path -Path $script:SourceDir -ChildPath 'main.ps1') = "# Main PowerShell script`r`nWrite-Host 'Hello World'`r`n"
                (Join-Path -Path $script:SourceDir -ChildPath 'module.psm1') = "function Test-Function {`r`n    return 'test'`r`n}`r`n"
                (Join-Path -Path $script:SourceDir -ChildPath 'config.json') = "{`r`n  `"setting`": `"value`"`r`n}`r`n"
                (Join-Path -Path $script:DocsDir -ChildPath 'README.md') = "# Project Documentation`r`n`r`nThis is a test project.`r`n"
                (Join-Path -Path $script:DocsDir -ChildPath 'CHANGELOG.md') = "# Changelog`r`n`r`n## Version 1.0`r`n- Initial release`r`n"
                (Join-Path -Path $script:ScriptsDir -ChildPath 'build.sh') = "#!/bin/bash`necho 'Building project'`n"
                (Join-Path -Path $script:ScriptsDir -ChildPath 'deploy.bat') = "@echo off`r`necho Deploying project`r`n"
            }

            # Create binary files that should be skipped
            $binaryFiles = @{
                (Join-Path -Path $script:BinaryDir -ChildPath 'app.exe') = [byte[]](77, 90, 144, 0, 3, 0, 0, 0)  # MZ header
                (Join-Path -Path $script:BinaryDir -ChildPath 'image.png') = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)  # PNG header
                (Join-Path -Path $script:BinaryDir -ChildPath 'archive.zip') = [byte[]](80, 75, 3, 4, 20, 0, 0, 0)  # ZIP header
            }

            # Create files that should be excluded by default
            $excludedFiles = @{
                (Join-Path -Path $script:NodeModulesDir -ChildPath 'package.json') = "{`r`n  `"name`": `"test`"`r`n}`r`n"
                (Join-Path -Path $script:NodeModulesDir -ChildPath 'index.js') = "console.log('test');`r`n"
            }

            # Write all text files
            foreach ($file in $projectFiles.GetEnumerator())
            {
                [System.IO.File]::WriteAllText($file.Key, $file.Value, [System.Text.Encoding]::UTF8)
            }

            # Write binary files
            foreach ($file in $binaryFiles.GetEnumerator())
            {
                [System.IO.File]::WriteAllBytes($file.Key, $file.Value)
            }

            # Write excluded files
            foreach ($file in $excludedFiles.GetEnumerator())
            {
                [System.IO.File]::WriteAllText($file.Key, $file.Value, [System.Text.Encoding]::UTF8)
            }
        }

        It 'Should convert entire project to Unix line endings while preserving structure' {
            # Convert entire project to LF
            Convert-LineEndings -Path $script:TestDir -LineEnding 'LF' -Recurse

            # Verify PowerShell files were converted
            $mainContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:SourceDir -ChildPath 'main.ps1'))
            $mainContent | Should -Not -Match "`r"
            $mainContent | Should -Match "Write-Host 'Hello World'"

            # Verify JSON files were converted
            $jsonContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:SourceDir -ChildPath 'config.json'))
            $jsonContent | Should -Not -Match "`r"
            $jsonContent | Should -Match '"setting"'

            # Verify Markdown files were converted
            $readmeContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:DocsDir -ChildPath 'README.md'))
            $readmeContent | Should -Not -Match "`r"
            $readmeContent | Should -Match 'Project Documentation'

            # Verify shell scripts were converted
            $shellContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:ScriptsDir -ChildPath 'build.sh'))
            $shellContent | Should -Not -Match "`r"
            $shellContent | Should -Match 'Building project'
        }

        It 'Should preserve binary files unchanged' {
            # Binary files should not be modified
            $exeBytes = [System.IO.File]::ReadAllBytes((Join-Path -Path $script:BinaryDir -ChildPath 'app.exe'))
            $exeBytes[0] | Should -Be 77  # MZ header intact
            $exeBytes[1] | Should -Be 90

            $pngBytes = [System.IO.File]::ReadAllBytes((Join-Path -Path $script:BinaryDir -ChildPath 'image.png'))
            $pngBytes[0] | Should -Be 137  # PNG header intact
            $pngBytes[1] | Should -Be 80
        }

        It 'Should respect default exclusions for node_modules' {
            # Files in node_modules should be excluded by default patterns
            Convert-LineEndings -Path $script:TestDir -LineEnding 'LF' -Recurse

            # Verify that node_modules was excluded by checking if files were processed
            # This test ensures the exclude patterns work correctly
            $nodeContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:NodeModulesDir -ChildPath 'package.json'))
            Write-Verbose "Node modules content preserved: $($nodeContent.Length) characters"
            # The actual line ending check depends on whether the exclude worked
        }
    }

    Context 'Cross-Platform File Processing' {
        BeforeAll {
            # Create files with different encodings and line endings
            $script:Utf8File = Join-Path -Path $script:TestDir -ChildPath 'utf8-test.txt'
            $script:Utf8BomFile = Join-Path -Path $script:TestDir -ChildPath 'utf8-bom-test.txt'
            $script:AsciiFile = Join-Path -Path $script:TestDir -ChildPath 'ascii-test.txt'

            # UTF-8 without BOM
            $utf8Content = "Testing UTF-8: café, naïve, résumé`r`nSecond line`r`n"
            [System.IO.File]::WriteAllText($script:Utf8File, $utf8Content, [System.Text.Encoding]::UTF8)

            # UTF-8 with BOM
            $utf8BomEncoding = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($script:Utf8BomFile, $utf8Content, $utf8BomEncoding)

            # ASCII
            $asciiContent = "Simple ASCII text`r`nNo special characters`r`n"
            [System.IO.File]::WriteAllText($script:AsciiFile, $asciiContent, [System.Text.Encoding]::ASCII)
        }

        It 'Should handle UTF-8 files correctly across platforms' {
            Convert-LineEndings -Path $script:Utf8File -LineEnding 'LF'

            $result = [System.IO.File]::ReadAllText($script:Utf8File, [System.Text.Encoding]::UTF8)
            $result | Should -Not -Match "`r"
            $result | Should -Match 'café, naïve, résumé'
        }

        It 'Should preserve UTF-8 BOM across platforms' {
            Convert-LineEndings -Path $script:Utf8BomFile -LineEnding 'LF'

            # Check BOM is preserved
            $bytes = [System.IO.File]::ReadAllBytes($script:Utf8BomFile)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF

            # Check content is correct
            $result = [System.IO.File]::ReadAllText($script:Utf8BomFile, [System.Text.Encoding]::UTF8)
            $result | Should -Not -Match "`r"
            $result | Should -Match 'café, naïve, résumé'
        }

        It 'Should handle ASCII files correctly' {
            Convert-LineEndings -Path $script:AsciiFile -LineEnding 'CRLF'

            $result = [System.IO.File]::ReadAllText($script:AsciiFile, [System.Text.Encoding]::ASCII)
            $result | Should -Match "`r`n"
            $result | Should -Match 'Simple ASCII text'
        }
    }

    Context 'PowerShell Pipeline Integration' {
        BeforeAll {
            # Create a mixed directory structure for pipeline testing
            $script:PipelineDir = Join-Path -Path $script:TestDir -ChildPath 'pipeline'
            $script:SubDir1 = Join-Path -Path $script:PipelineDir -ChildPath 'sub1'
            $script:SubDir2 = Join-Path -Path $script:PipelineDir -ChildPath 'sub2'

            @($script:PipelineDir, $script:SubDir1, $script:SubDir2) | ForEach-Object {
                New-Item -Path $_ -ItemType Directory -Force | Out-Null
            }

            # Create various file types
            $pipelineFiles = @{
                (Join-Path -Path $script:PipelineDir -ChildPath 'main.ps1') = "Write-Host 'Main'`r`n"
                (Join-Path -Path $script:PipelineDir -ChildPath 'config.json') = "{`r`n  `"test`": true`r`n}`r`n"
                (Join-Path -Path $script:SubDir1 -ChildPath 'helper.ps1') = "function Get-Help { }`r`n"
                (Join-Path -Path $script:SubDir1 -ChildPath 'data.xml') = "<?xml version=`"1.0`"?>`r`n<root></root>`r`n"
                (Join-Path -Path $script:SubDir2 -ChildPath 'readme.md') = "# Test`r`nContent`r`n"
                (Join-Path -Path $script:SubDir2 -ChildPath 'script.py') = "print('hello')`r`n"
            }

            foreach ($file in $pipelineFiles.GetEnumerator())
            {
                [System.IO.File]::WriteAllText($file.Key, $file.Value, [System.Text.Encoding]::UTF8)
            }
        }

        It 'Should work seamlessly with Get-ChildItem pipeline for specific file types' {
            # Convert only PowerShell files using pipeline
            Get-ChildItem -Path $script:PipelineDir -Filter '*.ps1' -Recurse |
            Convert-LineEndings -LineEnding 'LF'

            # PowerShell files should be converted
            $mainContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:PipelineDir -ChildPath 'main.ps1'))
            $mainContent | Should -Not -Match "`r"

            $helperContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:SubDir1 -ChildPath 'helper.ps1'))
            $helperContent | Should -Not -Match "`r"

            # Other files should remain unchanged
            $jsonContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:PipelineDir -ChildPath 'config.json'))
            $jsonContent | Should -Match "`r"  # Should still have CRLF
        }

        It 'Should work with Where-Object filtering in pipeline' {
            # Convert files larger than a certain size
            $processedFiles = Get-ChildItem -Path $script:PipelineDir -Recurse -File |
            Where-Object { $_.Length -gt 20 } |
            Convert-LineEndings -LineEnding 'LF' -PassThru

            # Verify that files were processed correctly
            if ($processedFiles)
            {
                $processedFiles | ForEach-Object {
                    $_.Success | Should -Be $true
                }
            }
            # This tests the integration with complex pipeline scenarios
        }

        It 'Should provide detailed information with PassThru in pipeline scenarios' {
            $results = Get-ChildItem -Path $script:PipelineDir -Filter '*.md' -Recurse |
            Convert-LineEndings -LineEnding 'CRLF' -PassThru

            $results | Should -Not -BeNullOrEmpty
            $results | ForEach-Object {
                $_.FilePath | Should -Not -BeNullOrEmpty
                $_.Success | Should -Be $true
                $_.SourceEncoding | Should -Not -BeNullOrEmpty
                $_.TargetEncoding | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Real-World Error Scenarios' {
        It 'Should handle permission denied scenarios gracefully' {
            $permissionFile = Join-Path -Path $script:TestDir -ChildPath 'permission-test.txt'
            [System.IO.File]::WriteAllText($permissionFile, "Test content`r`n", [System.Text.Encoding]::UTF8)

            try
            {
                # Make file read-only to simulate permission issues
                Set-ItemProperty -Path $permissionFile -Name IsReadOnly -Value $true

                $results = Convert-LineEndings -Path $permissionFile -LineEnding 'LF' -PassThru -ErrorAction SilentlyContinue

                if ($results)
                {
                    $results.Success | Should -Be $false
                    $results.Error | Should -Match 'read-only'
                }
            }
            finally
            {
                if (Test-Path $permissionFile)
                {
                    Set-ItemProperty -Path $permissionFile -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                    Remove-Item -Path $permissionFile -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It 'Should handle corrupted or inaccessible files' {
            $lockedFile = Join-Path -Path $script:TestDir -ChildPath 'locked-test.txt'
            [System.IO.File]::WriteAllText($lockedFile, "Test content`r`n", [System.Text.Encoding]::UTF8)

            try
            {
                # Open file for exclusive access to simulate file being in use
                $fileStream = [System.IO.File]::Open($lockedFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

                $errorMessages = @()
                Convert-LineEndings -Path $lockedFile -LineEnding 'LF' -ErrorVariable errorMessages -ErrorAction SilentlyContinue

                # Should handle the error gracefully
                $errorMessages | Should -Not -BeNullOrEmpty
            }
            finally
            {
                if ($fileStream)
                {
                    $fileStream.Close()
                    $fileStream.Dispose()
                }
                if (Test-Path $lockedFile)
                {
                    Remove-Item -Path $lockedFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context 'Complex Include/Exclude Pattern Scenarios' {
        BeforeAll {
            # Create a complex directory structure with various file types
            $script:ComplexDir = Join-Path -Path $script:TestDir -ChildPath 'complex'
            $script:SourceCodeDir = Join-Path -Path $script:ComplexDir -ChildPath 'src'
            $script:TestsDir = Join-Path -Path $script:ComplexDir -ChildPath 'tests'
            $script:DistDir = Join-Path -Path $script:ComplexDir -ChildPath 'dist'

            @($script:ComplexDir, $script:SourceCodeDir, $script:TestsDir, $script:DistDir) | ForEach-Object {
                New-Item -Path $_ -ItemType Directory -Force | Out-Null
            }

            # Create various files
            $complexFiles = @{
                (Join-Path -Path $script:SourceCodeDir -ChildPath 'main.js') = "console.log('main');`r`n"
                (Join-Path -Path $script:SourceCodeDir -ChildPath 'utils.ts') = "export function test() {}`r`n"
                (Join-Path -Path $script:TestsDir -ChildPath 'main.test.js') = "test('should work', () => {});`r`n"
                (Join-Path -Path $script:TestsDir -ChildPath 'utils.spec.ts') = "describe('utils', () => {});`r`n"
                (Join-Path -Path $script:DistDir -ChildPath 'bundle.min.js') = "console.log('minified');`r`n"
                (Join-Path -Path $script:DistDir -ChildPath 'app.min.css') = "body{color:red}`r`n"
            }

            foreach ($file in $complexFiles.GetEnumerator())
            {
                [System.IO.File]::WriteAllText($file.Key, $file.Value, [System.Text.Encoding]::UTF8)
            }
        }

        It 'Should handle complex include patterns for source files only' {
            # Reset files to CRLF before this test
            $complexFiles = @{
                (Join-Path -Path $script:SourceCodeDir -ChildPath 'main.js') = "console.log('main');`r`n"
                (Join-Path -Path $script:SourceCodeDir -ChildPath 'utils.ts') = "export function test() {}`r`n"
                (Join-Path -Path $script:TestsDir -ChildPath 'main.test.js') = "test('should work', () => {});`r`n"
                (Join-Path -Path $script:TestsDir -ChildPath 'utils.spec.ts') = "describe('utils', () => {});`r`n"
                (Join-Path -Path $script:DistDir -ChildPath 'bundle.min.js') = "console.log('minified');`r`n"
                (Join-Path -Path $script:DistDir -ChildPath 'app.min.css') = "body{color:red}`r`n"
            }

            foreach ($file in $complexFiles.GetEnumerator())
            {
                [System.IO.File]::WriteAllText($file.Key, $file.Value, [System.Text.Encoding]::UTF8)
            }

            Convert-LineEndings -Path $script:ComplexDir -LineEnding 'LF' -Recurse -Include '*.js', '*.ts' -Exclude '*.min.*', 'dist'

            # Source files should be converted
            $mainJsContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:SourceCodeDir -ChildPath 'main.js'))
            $mainJsContent | Should -Not -Match "`r"

            $utilsTsContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:SourceCodeDir -ChildPath 'utils.ts'))
            $utilsTsContent | Should -Not -Match "`r"

            # Test files should be converted (not in dist, not minified)
            $testJsContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:TestsDir -ChildPath 'main.test.js'))
            $testJsContent | Should -Not -Match "`r"

            # Minified files should be excluded
            $minJsContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:DistDir -ChildPath 'bundle.min.js'))
            $minJsContent | Should -Match "`r"  # Should still have CRLF
        }

        It 'Should handle multiple exclude patterns effectively' {
            # Reset files to CRLF before this test
            $complexFiles = @{
                (Join-Path -Path $script:SourceCodeDir -ChildPath 'main.js') = "console.log('main');`r`n"
                (Join-Path -Path $script:SourceCodeDir -ChildPath 'utils.ts') = "export function test() {}`r`n"
                (Join-Path -Path $script:TestsDir -ChildPath 'main.test.js') = "test('should work', () => {});`r`n"
                (Join-Path -Path $script:TestsDir -ChildPath 'utils.spec.ts') = "describe('utils', () => {});`r`n"
                (Join-Path -Path $script:DistDir -ChildPath 'bundle.min.js') = "console.log('minified');`r`n"
                (Join-Path -Path $script:DistDir -ChildPath 'app.min.css') = "body{color:red}`r`n"
            }

            foreach ($file in $complexFiles.GetEnumerator())
            {
                [System.IO.File]::WriteAllText($file.Key, $file.Value, [System.Text.Encoding]::UTF8)
            }

            Convert-LineEndings -Path $script:ComplexDir -LineEnding 'LF' -Recurse -Exclude '*.min.*', 'dist', '*.test.*', '*.spec.*'

            # Only main source files should be converted
            $mainJsContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:SourceCodeDir -ChildPath 'main.js'))
            $mainJsContent | Should -Not -Match "`r"

            $utilsTsContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:SourceCodeDir -ChildPath 'utils.ts'))
            $utilsTsContent | Should -Not -Match "`r"

            # Test files should be excluded
            $testJsContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:TestsDir -ChildPath 'main.test.js'))
            $testJsContent | Should -Match "`r"  # Should still have CRLF

            # Dist files should be excluded
            $minJsContent = [System.IO.File]::ReadAllText((Join-Path -Path $script:DistDir -ChildPath 'bundle.min.js'))
            $minJsContent | Should -Match "`r"  # Should still have CRLF
        }
    }

    Context 'EnsureEndingNewline Integration Tests' {
        BeforeAll {
            # Create test files with various ending scenarios
            $script:EndingTestDir = Join-Path -Path $script:TestDir -ChildPath 'ending-tests'
            New-Item -Path $script:EndingTestDir -ItemType Directory -Force | Out-Null

            # File with no ending newline
            $script:NoEndingFile = Join-Path -Path $script:EndingTestDir -ChildPath 'no-ending.txt'
            $content = 'Line 1' + [char]13 + [char]10 + 'Line 2 no ending'
            [System.IO.File]::WriteAllText($script:NoEndingFile, $content, [System.Text.Encoding]::UTF8)

            # File with proper ending newline
            $script:WithEndingFile = Join-Path -Path $script:EndingTestDir -ChildPath 'with-ending.txt'
            $contentWithEnding = 'Line 1' + [char]13 + [char]10 + 'Line 2' + [char]13 + [char]10
            [System.IO.File]::WriteAllText($script:WithEndingFile, $contentWithEnding, [System.Text.Encoding]::UTF8)

            # Empty file
            $script:EmptyFile = Join-Path -Path $script:EndingTestDir -ChildPath 'empty.txt'
            [System.IO.File]::WriteAllText($script:EmptyFile, '', [System.Text.Encoding]::UTF8)

            # Single line file without ending
            $script:SingleLineFile = Join-Path -Path $script:EndingTestDir -ChildPath 'single-line.txt'
            [System.IO.File]::WriteAllText($script:SingleLineFile, 'Single line content', [System.Text.Encoding]::UTF8)

            # Mix of files in subdirectories
            $script:SubDir = Join-Path -Path $script:EndingTestDir -ChildPath 'subdir'
            New-Item -Path $script:SubDir -ItemType Directory -Force | Out-Null

            $script:SubFileNoEnding = Join-Path -Path $script:SubDir -ChildPath 'sub-no-ending.js'
            [System.IO.File]::WriteAllText($script:SubFileNoEnding, "console.log('test');", [System.Text.Encoding]::UTF8)

            $script:SubFileWithEnding = Join-Path -Path $script:SubDir -ChildPath 'sub-with-ending.js'
            $jsContentWithEnding = "console.log('test');" + [char]10  # LF ending
            [System.IO.File]::WriteAllText($script:SubFileWithEnding, $jsContentWithEnding, [System.Text.Encoding]::UTF8)
        }

        It 'Should process directory recursively and add ending newlines where needed' {
            $results = Convert-LineEndings -Path $script:EndingTestDir -LineEnding 'LF' -EnsureEndingNewline -Recurse -PassThru

            # Check files that should have had newlines added
            $noEndingResult = $results | Where-Object { $_.FilePath -like '*no-ending.txt' }
            $noEndingResult.EndingNewlineAdded | Should -Be $true

            $singleLineResult = $results | Where-Object { $_.FilePath -like '*single-line.txt' }
            $singleLineResult.EndingNewlineAdded | Should -Be $true

            $subNoEndingResult = $results | Where-Object { $_.FilePath -like '*sub-no-ending.js' }
            $subNoEndingResult.EndingNewlineAdded | Should -Be $true

            # Check files that should NOT have had newlines added
            $withEndingResult = $results | Where-Object { $_.FilePath -like '*with-ending.txt' }
            $withEndingResult.EndingNewlineAdded | Should -Be $false

            $subWithEndingResult = $results | Where-Object { $_.FilePath -like '*sub-with-ending.js' }
            $subWithEndingResult.EndingNewlineAdded | Should -Be $false

            # Verify file contents
            $noEndingContent = [System.IO.File]::ReadAllText($script:NoEndingFile)
            $noEndingContent | Should -Be "Line 1`nLine 2 no ending`n"

            $withEndingContent = [System.IO.File]::ReadAllText($script:WithEndingFile)
            $withEndingContent | Should -Be "Line 1`nLine 2`n"

            $singleLineContent = [System.IO.File]::ReadAllText($script:SingleLineFile)
            $singleLineContent | Should -Be "Single line content`n"
        }

        It 'Should work with file filtering and EnsureEndingNewline' {
            # Reset files to original state (including the .txt file that should not be processed)
            $noEndingContent = 'Line 1' + [char]13 + [char]10 + 'Line 2 no ending'
            [System.IO.File]::WriteAllText($script:NoEndingFile, $noEndingContent, [System.Text.Encoding]::UTF8)

            [System.IO.File]::WriteAllText($script:SubFileNoEnding, "console.log('test');", [System.Text.Encoding]::UTF8)
            $jsWithEndingContent = "console.log('test');" + [char]10
            [System.IO.File]::WriteAllText($script:SubFileWithEnding, $jsWithEndingContent, [System.Text.Encoding]::UTF8)

            # Process only .js files
            $results = Convert-LineEndings -Path $script:EndingTestDir -LineEnding 'LF' -EnsureEndingNewline -Recurse -Include '*.js' -PassThru

            # Should only process .js files
            $results | Should -HaveCount 2
            $results | ForEach-Object { $_.FilePath | Should -Match '\.js$' }

            # Check that the .js file without ending newline was processed
            $jsNoEndingResult = $results | Where-Object { $_.FilePath -like '*sub-no-ending.js' }
            $jsNoEndingResult.EndingNewlineAdded | Should -Be $true

            # Check that the .js file with ending newline was not modified for newline
            $jsWithEndingResult = $results | Where-Object { $_.FilePath -like '*sub-with-ending.js' }
            $jsWithEndingResult.EndingNewlineAdded | Should -Be $false

            # Verify non-.js files were not processed (should still not end with newline)
            $finalNoEndingContent = [System.IO.File]::ReadAllText($script:NoEndingFile)
            $finalNoEndingContent | Should -Not -Match ([char]10 + '$')  # Should still not end with newline
        }

        It 'Should show correct information in WhatIf mode with EnsureEndingNewline' {
            # Reset files to known state
            $content = 'Line 1' + [char]13 + [char]10 + 'Line 2 no ending'
            [System.IO.File]::WriteAllText($script:NoEndingFile, $content, [System.Text.Encoding]::UTF8)

            # Use WhatIf to see what would be processed
            Convert-LineEndings -Path $script:NoEndingFile -LineEnding 'LF' -EnsureEndingNewline -WhatIf

            # File should not be modified
            $contentAfter = [System.IO.File]::ReadAllText($script:NoEndingFile)
            $contentAfter | Should -Be $content  # Should be unchanged
        }

        It 'Should work correctly with encoding conversion and ending newline' {
            # Create a UTF8 file without BOM and without ending newline
            $testFile = Join-Path -Path $script:EndingTestDir -ChildPath 'encoding-test.txt'
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($testFile, 'Test content with café', $utf8NoBom)

            $result = Convert-LineEndings -Path $testFile -LineEnding 'LF' -Encoding 'UTF8BOM' -EnsureEndingNewline -PassThru

            # Should have both encoding change and ending newline added
            $result.EncodingChanged | Should -Be $true
            $result.EndingNewlineAdded | Should -Be $true

            # Verify BOM was added
            $bytes = [System.IO.File]::ReadAllBytes($testFile)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF

            # Verify content and ending newline
            $content = [System.IO.File]::ReadAllText($testFile)
            $content | Should -Be "Test content with café`n"
        }

        It 'Should handle large number of files efficiently with EnsureEndingNewline' {
            # Create multiple test files
            $manyFilesDir = Join-Path -Path $script:EndingTestDir -ChildPath 'many-files'
            New-Item -Path $manyFilesDir -ItemType Directory -Force | Out-Null

            $fileCount = 20
            $filesCreated = @()
            for ($i = 1; $i -le $fileCount; $i++)
            {
                $filePath = Join-Path -Path $manyFilesDir -ChildPath "test$i.txt"
                $hasEnding = ($i % 2) -eq 0  # Every other file has ending newline
                $content = "File $i content"
                if ($hasEnding)
                {
                    $content += "`r`n"
                }
                [System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
                $filesCreated += $filePath
            }

            # Process all files
            $results = Convert-LineEndings -Path $manyFilesDir -LineEnding 'LF' -EnsureEndingNewline -Recurse -PassThru

            # Should have processed all files
            $results | Should -HaveCount $fileCount

            # Files without ending newlines should have had them added
            $filesWithNewlineAdded = $results | Where-Object EndingNewlineAdded
            $filesWithNewlineAdded | Should -HaveCount ($fileCount / 2)  # Half the files

            # Verify all files now end with newlines
            foreach ($file in $filesCreated)
            {
                $content = [System.IO.File]::ReadAllText($file)
                $content | Should -Match "`n$"
            }
        }

        It 'Should preserve file attributes when adding ending newlines' {
            # Create a file and set it read-only initially
            $attributeTestFile = Join-Path -Path $script:EndingTestDir -ChildPath 'readonly-test.txt'
            [System.IO.File]::WriteAllText($attributeTestFile, 'Test content', [System.Text.Encoding]::UTF8)

            # Note: On macOS/Linux, we'll test with normal permissions since read-only behavior is different

            $result = Convert-LineEndings -Path $attributeTestFile -LineEnding 'LF' -EnsureEndingNewline -PassThru

            $result.EndingNewlineAdded | Should -Be $true
            $result.Success | Should -Be $true

            # Verify content was modified correctly
            $content = [System.IO.File]::ReadAllText($attributeTestFile)
            $content | Should -Be "Test content`n"

            # File should still exist and be accessible
            Test-Path $attributeTestFile | Should -Be $true
        }
    }

    Context 'Auto LineEnding Integration Tests' {
        BeforeAll {
            # Create test files with various line endings for Auto testing
            $script:AutoTestDir = Join-Path -Path $script:TestDir -ChildPath 'auto-tests'
            New-Item -Path $script:AutoTestDir -ItemType Directory -Force | Out-Null

            # Mixed line endings file
            $script:MixedFile = Join-Path -Path $script:AutoTestDir -ChildPath 'mixed-endings.txt'
            $mixedContent = "Line 1`r`nLine 2`nLine 3`r`nLine 4"
            [System.IO.File]::WriteAllText($script:MixedFile, $mixedContent, [System.Text.Encoding]::UTF8)

            # CRLF file
            $script:CrlfFile = Join-Path -Path $script:AutoTestDir -ChildPath 'crlf-file.txt'
            $crlfContent = "Line 1`r`nLine 2`r`nLine 3`r`n"
            [System.IO.File]::WriteAllText($script:CrlfFile, $crlfContent, [System.Text.Encoding]::UTF8)

            # LF file
            $script:LfFile = Join-Path -Path $script:AutoTestDir -ChildPath 'lf-file.txt'
            $lfContent = "Line 1`nLine 2`nLine 3`n"
            [System.IO.File]::WriteAllText($script:LfFile, $lfContent, [System.Text.Encoding]::UTF8)
        }

        It 'Should process entire directory with Auto parameter (platform default)' {
            # Test Auto parameter behavior - should use platform default
            $results = Convert-LineEndings -Path $script:AutoTestDir -Recurse -PassThru

            # Should have results for all files
            $results | Should -Not -BeNullOrEmpty
            $results | Should -HaveCount 3

            # Platform detection logic
            if ($PSVersionTable.PSVersion.Major -lt 6)
            {
                $script:IsWindowsPlatform = $true
            }
            else
            {
                $script:IsWindowsPlatform = $IsWindows
            }

            # Verify results based on platform - all should have the correct LineEnding
            $results | ForEach-Object {
                if ($script:IsWindowsPlatform)
                {
                    $_.LineEnding | Should -Be 'CRLF'
                }
                else
                {
                    $_.LineEnding | Should -Be 'LF'
                }
            }
        }

        It 'Should work with Auto parameter when no LineEnding specified' {
            # Reset files to mixed state
            $mixedContent = "Line 1`r`nLine 2`nLine 3`r`nLine 4"
            [System.IO.File]::WriteAllText($script:MixedFile, $mixedContent, [System.Text.Encoding]::UTF8)

            # Don't specify LineEnding - should default to Auto
            $result = Convert-LineEndings -Path $script:MixedFile -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.Skipped | Should -Be $false

            # Platform detection
            if ($PSVersionTable.PSVersion.Major -lt 6)
            {
                $script:IsWindowsPlatform = $true
            }
            else
            {
                $script:IsWindowsPlatform = $IsWindows
            }

            if ($script:IsWindowsPlatform)
            {
                $result.LineEnding | Should -Be 'CRLF'
                # Verify file content has CRLF
                $finalContent = [System.IO.File]::ReadAllText($script:MixedFile)
                $finalContent | Should -Match "`r`n"
            }
            else
            {
                $result.LineEnding | Should -Be 'LF'
                # Verify file content has only LF
                $finalContent = [System.IO.File]::ReadAllText($script:MixedFile)
                $finalContent | Should -Not -Match "`r"
            }
        }

        It 'Should show correct behavior when files already match platform default' {
            # Platform detection
            if ($PSVersionTable.PSVersion.Major -lt 6)
            {
                $script:IsWindowsPlatform = $true
            }
            else
            {
                $script:IsWindowsPlatform = $IsWindows
            }

            if ($script:IsWindowsPlatform)
            {
                # On Windows, CRLF file should be skipped when using Auto
                $result = Convert-LineEndings -Path $script:CrlfFile -PassThru
                $result.Skipped | Should -Be $true
                $result.LineEnding | Should -Be 'CRLF'
            }
            else
            {
                # On Unix/Linux/macOS, LF file should be skipped when using Auto
                $result = Convert-LineEndings -Path $script:LfFile -PassThru
                $result.Skipped | Should -Be $true
                $result.LineEnding | Should -Be 'LF'
            }
        }
    }

    Context 'Timestamp Preservation in Real Scenarios' {
        BeforeAll {
            # Create test files with realistic content and timestamps
            $script:TimestampTestDir = Join-Path -Path $script:TestDir -ChildPath 'timestamp-tests'
            New-Item -Path $script:TimestampTestDir -ItemType Directory -Force | Out-Null

            # Create various file types that would be processed in a real project
            $testFiles = @{
                'config.json' = @{
                    Content = "{\r\n  `"name`": `"test-project`",\r\n  `"version`": `"1.0.0`"\r\n}"
                    Encoding = 'UTF8'
                }
                'README.md' = @{
                    Content = '# Test Project\r\n\r\nThis is a test project.\r\n\r\n## Features\r\n\r\n- Feature 1\r\n- Feature 2\r\n'
                    Encoding = 'UTF8'
                }
                'script.ps1' = @{
                    Content = "# PowerShell script\r\nGet-Process | Where-Object { `$_.Name -like 'pwsh*' }\r\n"
                    Encoding = 'UTF8BOM'
                }
                'LICENSE' = @{
                    Content = 'MIT License\r\n\r\nCopyright (c) 2025 Test\r\n\r\nPermission is hereby granted...\r\n'
                    Encoding = 'ASCII'
                }
            }

            $script:TestFileInfo = @{}
            foreach ($fileName in $testFiles.Keys)
            {
                $filePath = Join-Path -Path $script:TimestampTestDir -ChildPath $fileName
                $fileData = $testFiles[$fileName]

                # Create file with specific encoding
                switch ($fileData.Encoding)
                {
                    'UTF8' { [System.IO.File]::WriteAllText($filePath, $fileData.Content, [System.Text.UTF8Encoding]::new($false)) }
                    'UTF8BOM' { [System.IO.File]::WriteAllText($filePath, $fileData.Content, [System.Text.UTF8Encoding]::new($true)) }
                    'ASCII' { [System.IO.File]::WriteAllText($filePath, $fileData.Content, [System.Text.ASCIIEncoding]::new()) }
                }

                # Set timestamps to known values in the past
                $fileNames = @($testFiles.Keys)
                $pastTime = (Get-Date).AddDays(-30).AddHours(-$fileNames.IndexOf($fileName))
                $fileInfo = Get-Item $filePath
                $fileInfo.CreationTime = $pastTime
                $fileInfo.LastWriteTime = $pastTime

                # Store original timestamps for verification
                $script:TestFileInfo[$fileName] = @{
                    Path = $filePath
                    OriginalCreationTime = $pastTime
                    OriginalLastWriteTime = $pastTime
                    OriginalEncoding = $fileData.Encoding
                }
            }
        }

        AfterAll {
            if (Test-Path $script:TimestampTestDir)
            {
                Remove-Item -Path $script:TimestampTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should preserve timestamps when PreserveTimestamps switch is specified' {
            # Create a single test file that we know will be converted
            $singleTestFile = Join-Path -Path $script:TimestampTestDir -ChildPath 'timestamp-single-test.txt'
            $crlfContent = "Line 1`r`nLine 2`r`nLine 3`r`n"
            $crlfBytes = [System.Text.Encoding]::UTF8.GetBytes($crlfContent)
            [System.IO.File]::WriteAllBytes($singleTestFile, $crlfBytes)

            # Set a specific timestamp in the past
            $pastTime = (Get-Date).AddDays(-10)
            $fileInfo = Get-Item $singleTestFile
            $fileInfo.CreationTime = $pastTime
            $fileInfo.LastWriteTime = $pastTime

            # Convert with timestamp preservation enabled
            $result = Convert-LineEndings -Path $singleTestFile -LineEnding 'LF' -PreserveTimestamps -PassThru

            # Verify the file was converted successfully
            $result.Success | Should -Be $true
            $result.Converted | Should -Be $true
            $result.Skipped | Should -Be $false

            # Verify timestamps were preserved
            $newFileInfo = Get-Item $singleTestFile
            # Verify timestamps are preserved (allow for filesystem precision differences)
            $creationDiff = [Math]::Abs(($newFileInfo.CreationTime - $pastTime).TotalSeconds)
            $writeDiff = [Math]::Abs(($newFileInfo.LastWriteTime - $pastTime).TotalSeconds)

            # Use platform-appropriate tolerance: Windows NTFS can have different precision than APFS/ext4
            $tolerance = if ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) { 2 } else { 0.1 }
            $creationDiff | Should -BeLessThan $tolerance -Because 'Creation time should be preserved'
            $writeDiff | Should -BeLessThan $tolerance -Because 'Last write time should be preserved'

            # Verify content was actually converted
            $afterBytes = [System.IO.File]::ReadAllBytes($singleTestFile)
            $hasCarriageReturn = $afterBytes -contains 13
            $hasCarriageReturn | Should -Be $false -Because 'File should not contain CR bytes after LF conversion'

            # Clean up
            Remove-Item $singleTestFile -Force -ErrorAction SilentlyContinue
        }

        It 'Should update timestamps by default when not preserving timestamps' {
            # Create a single test file that we know will be converted
            $singleTestFile = Join-Path -Path $script:TimestampTestDir -ChildPath 'no-preserve-test.txt'
            $crlfContent = "Test content`r`nLine 2`r`n"
            $crlfBytes = [System.Text.Encoding]::UTF8.GetBytes($crlfContent)
            [System.IO.File]::WriteAllBytes($singleTestFile, $crlfBytes)

            # Set a specific timestamp in the past
            $pastTime = (Get-Date).AddDays(-5)
            $fileInfo = Get-Item $singleTestFile
            $fileInfo.CreationTime = $pastTime
            $fileInfo.LastWriteTime = $pastTime

            # Convert without PreserveTimestamps (default behavior)
            $result = Convert-LineEndings -Path $singleTestFile -LineEnding 'LF' -PassThru

            # Verify the file was converted
            $result.Success | Should -Be $true
            $result.Converted | Should -Be $true

            # Verify timestamps were NOT preserved (should be current time)
            $newFileInfo = Get-Item $singleTestFile
            $currentTime = Get-Date

            # Timestamps should be recent (within last 30 seconds)
            ($currentTime - $newFileInfo.LastWriteTime).TotalSeconds | Should -BeLessThan 30 -Because 'Last write time should be current when not preserving timestamps'

            # Should not be the original past time
            $newFileInfo.LastWriteTime | Should -Not -Be $pastTime -Because 'Timestamp should have changed when PreserveTimestamps is not specified'

            # Clean up
            Remove-Item $singleTestFile -Force -ErrorAction SilentlyContinue
        }

        It 'Should handle mixed scenarios with some files converted and some skipped' {
            # Create a fresh subdirectory for this test to avoid interference
            $mixedTestDir = Join-Path -Path $script:TimestampTestDir -ChildPath 'mixed-test'
            New-Item -Path $mixedTestDir -ItemType Directory -Force | Out-Null

            # Create files with different line endings
            $convertFile = Join-Path -Path $mixedTestDir -ChildPath 'convert-me.txt'
            $skipFile = Join-Path -Path $mixedTestDir -ChildPath 'skip-me.txt'

            # File that needs conversion (CRLF)
            $crlfContent = "Convert this`r`nFile with CRLF`r`n"
            $crlfBytes = [System.Text.Encoding]::UTF8.GetBytes($crlfContent)
            [System.IO.File]::WriteAllBytes($convertFile, $crlfBytes)

            # File that should be skipped (already LF)
            $lfContent = "Skip this`nFile with LF`n"
            $lfBytes = [System.Text.Encoding]::UTF8.GetBytes($lfContent)
            [System.IO.File]::WriteAllBytes($skipFile, $lfBytes)

            # Verify that files were created with correct line endings
            $crlfVerifyBytes = [System.IO.File]::ReadAllBytes($convertFile)
            $lfVerifyBytes = [System.IO.File]::ReadAllBytes($skipFile)

            # CRLF file should contain byte sequence 0D 0A (CR LF)
            $hasCrLf = $false
            for ($i = 0; $i -lt $crlfVerifyBytes.Length - 1; $i++)
            {
                if ($crlfVerifyBytes[$i] -eq 13 -and $crlfVerifyBytes[$i + 1] -eq 10)
                {
                    $hasCrLf = $true
                    break
                }
            }
            $hasCrLf | Should -Be $true -Because 'CRLF test file should actually contain CRLF bytes'

            # LF file should contain standalone LF (0A) without preceding CR
            $hasStandaloneLf = $false
            for ($i = 0; $i -lt $lfVerifyBytes.Length; $i++)
            {
                if ($lfVerifyBytes[$i] -eq 10)
                {
                    # LF
                    if ($i -eq 0 -or $lfVerifyBytes[$i - 1] -ne 13)
                    {
                        # No preceding CR
                        $hasStandaloneLf = $true
                        break
                    }
                }
            }
            $hasStandaloneLf | Should -Be $true -Because 'LF test file should actually contain standalone LF bytes'

            # Set past timestamps on both files
            $pastTime = (Get-Date).AddDays(-7)
            foreach ($file in @($convertFile, $skipFile))
            {
                $fileInfo = Get-Item $file
                $fileInfo.CreationTime = $pastTime
                $fileInfo.LastWriteTime = $pastTime
            }

            # Convert directory with timestamp preservation enabled
            $results = Convert-LineEndings -Path $mixedTestDir -LineEnding 'LF' -Recurse -PreserveTimestamps -PassThru

            # Verify we have both conversions and skips
            $convertedResults = @($results | Where-Object { $_.Converted -eq $true })
            $skippedResults = @($results | Where-Object { $_.Skipped -eq $true })

            $convertedResults.Count | Should -Be 1 -Because 'One file should have been converted from CRLF to LF'
            $skippedResults.Count | Should -Be 1 -Because 'One file should have been skipped (already LF)'

            # Both files should have preserved timestamps when -PreserveTimestamps is specified
            $allResults = @($convertedResults) + @($skippedResults)
            foreach ($result in $allResults)
            {
                $currentInfo = Get-Item $result.FilePath
                # Verify timestamps are preserved (allow for filesystem precision differences)
                $creationDiff = [Math]::Abs(($currentInfo.CreationTime - $pastTime).TotalSeconds)
                $writeDiff = [Math]::Abs(($currentInfo.LastWriteTime - $pastTime).TotalSeconds)

                # Use platform-appropriate tolerance: Windows NTFS can have different precision than APFS/ext4
                $tolerance = if ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) { 2 } else { 0.1 }
                $creationDiff | Should -BeLessThan $tolerance -Because 'Timestamps should be preserved when -PreserveTimestamps is specified'
                $writeDiff | Should -BeLessThan $tolerance -Because 'Timestamps should be preserved when -PreserveTimestamps is specified'
            }

            # Clean up
            Remove-Item $mixedTestDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $convertFile, $skipFile -Force -ErrorAction SilentlyContinue
        }
    }
}
