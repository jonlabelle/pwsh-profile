#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Convert-LineEnding function.

.DESCRIPTION
    Tests the Convert-LineEnding function which converts line endings between LF and CRLF formats
    while preserving file encoding and automatically detecting binary files.

.NOTES
    These tests verify:
    - Line ending conversion between LF and CRLF
    - File encoding preservation
    - Binary file detection and skipping
    - WhatIf functionality
    - Directory processing with Include/Exclude filters
    - Error handling scenarios
#>

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../Functions/Convert-LineEnding.ps1"

    # Create a test directory
    $script:TestDir = Join-Path $TestDrive 'LineEndingTests'
    New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Clean up test directory
    if (Test-Path $script:TestDir)
    {
        Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Convert-LineEnding' {
    Context 'Parameter Validation' {
        It 'Should have mandatory Path parameter' {
            $command = Get-Command Convert-LineEnding
            $pathParam = $command.Parameters['Path']
            $pathParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have mandatory LineEnding parameter' {
            $command = Get-Command Convert-LineEnding
            $lineEndingParam = $command.Parameters['LineEnding']
            $lineEndingParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should validate LineEnding values' {
            $testFile = Join-Path $script:TestDir 'validation-test.txt'
            'test' | Out-File -FilePath $testFile -NoNewline
            { Convert-LineEnding -Path $testFile -LineEnding 'Invalid' -ErrorAction Stop } | Should -Throw
        }

        It 'Should accept valid LineEnding values' {
            # These should not throw (testing parameter validation only)
            $testFile = Join-Path $script:TestDir 'validation-test.txt'
            'test' | Out-File -FilePath $testFile -NoNewline

            { Convert-LineEnding -Path $testFile -LineEnding 'LF' -WhatIf } | Should -Not -Throw
            { Convert-LineEnding -Path $testFile -LineEnding 'CRLF' -WhatIf } | Should -Not -Throw
        }
    }

    Context 'Line Ending Conversion' {
        BeforeEach {
            $script:TestFile = Join-Path $script:TestDir 'lineending-test.txt'
        }

        AfterEach {
            if (Test-Path $script:TestFile)
            {
                Remove-Item -Path $script:TestFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should convert CRLF to LF' {
            # Create file with CRLF line endings
            $content = "Line 1`r`nLine 2`r`nLine 3"
            [System.IO.File]::WriteAllText($script:TestFile, $content, [System.Text.Encoding]::UTF8)

            Convert-LineEnding -Path $script:TestFile -LineEnding 'LF'

            $result = [System.IO.File]::ReadAllText($script:TestFile)
            $result | Should -Be "Line 1`nLine 2`nLine 3"
            $result | Should -Not -Match "`r"
        }

        It 'Should convert LF to CRLF' {
            # Create file with LF line endings
            $content = "Line 1`nLine 2`nLine 3"
            [System.IO.File]::WriteAllText($script:TestFile, $content, [System.Text.Encoding]::UTF8)

            Convert-LineEnding -Path $script:TestFile -LineEnding 'CRLF'

            $result = [System.IO.File]::ReadAllText($script:TestFile)
            $result | Should -Be "Line 1`r`nLine 2`r`nLine 3"
            ($result -split "`r`n").Count | Should -Be 3
        }

        It 'Should handle mixed line endings' {
            # Create file with mixed line endings
            $content = "Line 1`r`nLine 2`nLine 3`rLine 4"
            [System.IO.File]::WriteAllText($script:TestFile, $content, [System.Text.Encoding]::UTF8)

            Convert-LineEnding -Path $script:TestFile -LineEnding 'LF'

            $result = [System.IO.File]::ReadAllText($script:TestFile)
            $result | Should -Be "Line 1`nLine 2`nLine 3`nLine 4"
            $result | Should -Not -Match "`r"
        }

        It 'Should handle empty files' {
            # Create empty file using specific method to ensure it's truly empty
            [System.IO.File]::WriteAllBytes($script:TestFile, @())

            { Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' } | Should -Not -Throw

            # File should remain empty (or have only BOM if encoding requires it)
            $fileSize = (Get-Item $script:TestFile).Length
            $fileSize | Should -BeLessOrEqual 3  # Allow for potential BOM
        }

        It 'Should handle files without line endings' {
            # Create file without line endings
            'Single line without newline' | Out-File -FilePath $script:TestFile -NoNewline

            { Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' } | Should -Not -Throw

            $result = Get-Content -Path $script:TestFile -Raw
            $result | Should -Be 'Single line without newline'
        }
    }

    Context 'Encoding Preservation' {
        BeforeEach {
            $script:TestFile = Join-Path $script:TestDir 'encoding-test.txt'
        }

        AfterEach {
            if (Test-Path $script:TestFile)
            {
                Remove-Item -Path $script:TestFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should preserve UTF-8 encoding' {
            $content = "Test with UTF-8: café, naïve, résumé`r`n"
            [System.IO.File]::WriteAllText($script:TestFile, $content, [System.Text.Encoding]::UTF8)

            Convert-LineEnding -Path $script:TestFile -LineEnding 'LF'

            $result = [System.IO.File]::ReadAllText($script:TestFile, [System.Text.Encoding]::UTF8)
            $result | Should -Be "Test with UTF-8: café, naïve, résumé`n"
        }

        It 'Should preserve UTF-8 with BOM' {
            $content = "Test with UTF-8 BOM`r`n"
            $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($script:TestFile, $content, $utf8WithBom)

            Convert-LineEnding -Path $script:TestFile -LineEnding 'LF'

            # Verify BOM is still present
            $bytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }

        It 'Should preserve UTF-8 without BOM' {
            $content = "Test UTF-8 without BOM: café, naïve`r`n"
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($script:TestFile, $content, $utf8NoBom)

            # Verify original file has no BOM
            $originalBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $originalBytes[0] | Should -Not -Be 0xEF

            Convert-LineEnding -Path $script:TestFile -LineEnding 'CRLF'

            # Verify BOM is still NOT present after conversion
            $convertedBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $convertedBytes[0] | Should -Not -Be 0xEF

            # Verify content is correct
            $result = [System.IO.File]::ReadAllText($script:TestFile, $utf8NoBom)
            $result | Should -Be "Test UTF-8 without BOM: café, naïve`r`n"
        }

        It 'Should preserve ASCII encoding' {
            $content = "Simple ASCII text`r`n"
            [System.IO.File]::WriteAllText($script:TestFile, $content, [System.Text.Encoding]::ASCII)

            Convert-LineEnding -Path $script:TestFile -LineEnding 'LF'

            $result = [System.IO.File]::ReadAllText($script:TestFile, [System.Text.Encoding]::ASCII)
            $result | Should -Be "Simple ASCII text`n"
        }
    }

    Context 'Encoding Conversion Parameter' {
        BeforeEach {
            $script:TestFile = Join-Path $script:TestDir 'encoding-conversion-test.txt'
        }

        AfterEach {
            if (Test-Path $script:TestFile)
            {
                Remove-Item -Path $script:TestFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should accept valid encoding parameter values' {
            $command = Get-Command Convert-LineEnding
            $encodingParam = $command.Parameters['Encoding']
            $validEncodings = $encodingParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | Select-Object -ExpandProperty ValidValues

            $validEncodings | Should -Contain 'UTF8'
            $validEncodings | Should -Contain 'UTF8BOM'
            $validEncodings | Should -Contain 'UTF16LE'
            $validEncodings | Should -Contain 'UTF16BE'
            $validEncodings | Should -Contain 'UTF32'
            $validEncodings | Should -Contain 'ASCII'
        }

        It 'Should convert UTF8 to UTF8BOM' {
            $content = "Test content: café`r`n"  # CRLF content so conversion is needed
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($script:TestFile, $content, $utf8NoBom)

            # Verify original has no BOM and CRLF
            $originalBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $originalBytes[0] | Should -Not -Be 0xEF

            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -Encoding 'UTF8BOM' -PassThru

            # Verify conversion occurred
            $result.SourceEncoding | Should -Be 'Unicode (UTF-8)'
            $result.TargetEncoding | Should -Be 'Unicode (UTF-8)'
            $result.EncodingChanged | Should -Be $true

            # Verify BOM was added
            $convertedBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $convertedBytes[0] | Should -Be 0xEF
            $convertedBytes[1] | Should -Be 0xBB
            $convertedBytes[2] | Should -Be 0xBF
        }

        It 'Should convert UTF8BOM to UTF8' {
            $content = "Test content: café`r`n"  # CRLF content so conversion is needed
            $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($script:TestFile, $content, $utf8WithBom)

            # Verify original has BOM and CRLF
            $originalBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $originalBytes[0] | Should -Be 0xEF

            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -Encoding 'UTF8' -PassThru

            # Verify conversion occurred
            $result.SourceEncoding | Should -Be 'Unicode (UTF-8)'
            $result.TargetEncoding | Should -Be 'Unicode (UTF-8)'
            $result.EncodingChanged | Should -Be $true

            # Verify BOM was removed
            $convertedBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $convertedBytes[0] | Should -Not -Be 0xEF
        }

        It 'Should convert UTF8 to UTF16LE' {
            $content = "Test UTF16: café`r`n"  # CRLF content so conversion is needed
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($script:TestFile, $content, $utf8NoBom)

            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -Encoding 'UTF16LE' -PassThru

            # Verify conversion occurred
            $result.SourceEncoding | Should -Be 'Unicode (UTF-8)'
            $result.TargetEncoding | Should -Be 'Unicode'
            $result.EncodingChanged | Should -Be $true

            # Verify UTF16LE BOM
            $convertedBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $convertedBytes[0] | Should -Be 0xFF
            $convertedBytes[1] | Should -Be 0xFE

            # Verify content can be read correctly
            $readContent = [System.IO.File]::ReadAllText($script:TestFile, [System.Text.Encoding]::Unicode)
            $readContent | Should -Be "Test UTF16: café`n"
        }

        It 'Should convert UTF8 to ASCII (with special character replacement)' {
            $content = "Test ASCII: hello world`r`n"  # CRLF content so conversion is needed
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($script:TestFile, $content, $utf8NoBom)

            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -Encoding 'ASCII' -PassThru

            # Verify conversion occurred
            $result.SourceEncoding | Should -Be 'Unicode (UTF-8)'
            $result.TargetEncoding | Should -Be 'US-ASCII'
            $result.EncodingChanged | Should -Be $true

            # Verify content
            $readContent = [System.IO.File]::ReadAllText($script:TestFile, [System.Text.Encoding]::ASCII)
            $readContent | Should -Be "Test ASCII: hello world`n"
        }

        It 'Should not convert when target encoding matches source encoding' {
            $content = "Test content`r`n"  # CRLF content so line ending conversion is needed
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($script:TestFile, $content, $utf8NoBom)

            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -Encoding 'UTF8' -PassThru

            # Verify line ending conversion occurred but no encoding conversion
            $result.SourceEncoding | Should -Be 'Unicode (UTF-8)'
            $result.TargetEncoding | Should -Be 'Unicode (UTF-8)'
            $result.EncodingChanged | Should -Be $false
            $result.OriginalCRLF | Should -Be 1
            $result.NewLF | Should -Be 1
        }

        It 'Should convert only encoding when line endings are already correct (legacy behavior)' {
            $content = "Test content`n"  # LF content, already correct
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($script:TestFile, $content, $utf8NoBom)

            # Verify original has no BOM
            $originalBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $originalBytes[0] | Should -Not -Be 0xEF

            # This should convert encoding even though line endings are already correct
            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -Encoding 'UTF8BOM' -PassThru

            # Should NOT be skipped and should convert encoding
            $result.Skipped | Should -Be $false
            $result.EncodingChanged | Should -Be $true

            # Verify BOM was added
            $finalBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $finalBytes[0] | Should -Be 0xEF
        }

        It 'Should convert only encoding when line endings are already correct' {
            $content = "Test content`n"  # LF content, already correct
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($script:TestFile, $content, $utf8NoBom)

            # Verify original has no BOM
            $originalBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $originalBytes[0] | Should -Not -Be 0xEF

            # This should convert encoding but not line endings since they're already correct
            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -Encoding 'UTF8BOM' -PassThru

            # Should NOT be skipped and should convert encoding
            $result.Skipped | Should -Be $false
            $result.EncodingChanged | Should -Be $true
            $result.SourceEncoding | Should -Be 'Unicode (UTF-8)'
            $result.TargetEncoding | Should -Be 'Unicode (UTF-8)'

            # Verify BOM was added
            $finalBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $finalBytes[0] | Should -Be 0xEF
            $finalBytes[1] | Should -Be 0xBB
            $finalBytes[2] | Should -Be 0xBF

            # Verify content is still correct
            $finalContent = [System.IO.File]::ReadAllText($script:TestFile)
            $finalContent | Should -Be "Test content`n"
            $finalContent | Should -Not -Match "`r"
        }

        It 'Should convert only line endings when encoding is already correct' {
            $content = "Test content`r`n"  # CRLF content, needs conversion
            $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($script:TestFile, $content, $utf8WithBom)

            # Verify original has BOM and CRLF
            $originalBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $originalBytes[0] | Should -Be 0xEF
            $originalContent = [System.IO.File]::ReadAllText($script:TestFile)
            $originalContent | Should -Match "`r`n"

            # This should convert line endings but not encoding since it's already correct
            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -Encoding 'UTF8BOM' -PassThru

            # Should NOT be skipped and should convert line endings but not encoding
            $result.Skipped | Should -Be $false
            $result.EncodingChanged | Should -Be $false
            $result.OriginalCRLF | Should -Be 1
            $result.NewLF | Should -Be 1

            # Verify BOM is still present
            $finalBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $finalBytes[0] | Should -Be 0xEF
            $finalBytes[1] | Should -Be 0xBB
            $finalBytes[2] | Should -Be 0xBF

            # Verify line endings were converted
            $finalContent = [System.IO.File]::ReadAllText($script:TestFile)
            $finalContent | Should -Be "Test content`n"
            $finalContent | Should -Not -Match "`r"
        }

        It 'Should skip file entirely when both line endings and encoding are already correct' {
            $content = "Test content`n"  # LF content, already correct
            $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($script:TestFile, $content, $utf8WithBom)

            # Verify original has BOM and LF
            $originalBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $originalBytes[0] | Should -Be 0xEF

            # This should skip the file entirely since both line endings and encoding are correct
            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -Encoding 'UTF8BOM' -PassThru

            # Should return a skipped result
            $result.Skipped | Should -Be $true
            $result.EncodingChanged | Should -Be $false

            # Verify file is unchanged
            $finalBytes = [System.IO.File]::ReadAllBytes($script:TestFile)
            $finalBytes[0] | Should -Be 0xEF
            $finalBytes[1] | Should -Be 0xBB
            $finalBytes[2] | Should -Be 0xBF

            $finalContent = [System.IO.File]::ReadAllText($script:TestFile)
            $finalContent | Should -Be "Test content`n"
        }

        It 'Should work with cross-platform encoding names' -Skip:($PSVersionTable.PSVersion.Major -lt 6 -and $IsWindows -eq $false) {
            # This test ensures the Get-EncodingFromName function works across platforms
            $content = "Cross-platform test`r`n"
            [System.IO.File]::WriteAllText($script:TestFile, $content, [System.Text.Encoding]::UTF8)

            # Test each supported encoding can be resolved
            $encodings = @('UTF8', 'UTF8BOM', 'UTF16LE', 'UTF16BE', 'UTF32', 'ASCII')

            foreach ($encoding in $encodings)
            {
                { Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -Encoding $encoding -WhatIf } | Should -Not -Throw
            }
        }
    }

    Context 'Binary File Detection' {
        BeforeEach {
            # Use different extensions to test different detection methods
            $script:ContentBinaryFile = Join-Path $script:TestDir 'content-binary.dat'  # For content-based detection
            $script:ImageFile = Join-Path $script:TestDir 'image-test.jpg'            # For extension-based detection
            $script:ExecutableFile = Join-Path $script:TestDir 'executable-test.exe'  # For extension-based detection
        }

        AfterEach {
            @($script:ContentBinaryFile, $script:ImageFile, $script:ExecutableFile) | ForEach-Object {
                if (Test-Path $_)
                {
                    Remove-Item -Path $_ -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It 'Should detect binary files by extension' {
            # Create mock files with binary extensions
            'fake content' | Out-File -FilePath $script:ImageFile -NoNewline
            'fake content' | Out-File -FilePath $script:ExecutableFile -NoNewline

            # Should not process these files (function should skip them silently)
            { Convert-LineEnding -Path $script:ImageFile -LineEnding 'LF' } | Should -Not -Throw
            { Convert-LineEnding -Path $script:ExecutableFile -LineEnding 'LF' } | Should -Not -Throw

            # Files should remain unchanged
            $imageContent = Get-Content -Path $script:ImageFile -Raw
            $imageContent | Should -Be 'fake content'

            $exeContent = Get-Content -Path $script:ExecutableFile -Raw
            $exeContent | Should -Be 'fake content'
        }

        It 'Should detect binary files by content (null bytes)' {
            # Create file with null bytes using neutral extension
            $binaryData = [byte[]](65, 66, 67, 0, 68, 69, 70)  # ABC[null]DEF
            [System.IO.File]::WriteAllBytes($script:ContentBinaryFile, $binaryData)

            # Should not process this file and show verbose message about null bytes
            $verboseMessages = @()
            Convert-LineEnding -Path $script:ContentBinaryFile -LineEnding 'LF' -Verbose 4>&1 | Tee-Object -Variable verboseMessages | Out-Null
            ($verboseMessages | Where-Object { $_ -match 'detected as binary.*null bytes' }) | Should -Not -BeNullOrEmpty
        }

        It 'Should detect binary files by low printable character ratio' {
            # Create file with mostly non-printable characters using neutral extension
            $binaryData = [byte[]](1..50)  # Mostly non-printable control characters
            [System.IO.File]::WriteAllBytes($script:ContentBinaryFile, $binaryData)

            # Should not process this file
            $verboseMessages = @()
            Convert-LineEnding -Path $script:ContentBinaryFile -LineEnding 'LF' -Verbose 4>&1 | Tee-Object -Variable verboseMessages | Out-Null
            ($verboseMessages | Where-Object { $_ -match 'detected as binary.*printable character ratio' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Directory Processing' {
        BeforeEach {
            $script:SubDir = Join-Path $script:TestDir 'subdir'
            New-Item -Path $script:SubDir -ItemType Directory -Force | Out-Null

            # Create test files with explicit CRLF line endings using direct file writing
            [System.IO.File]::WriteAllText((Join-Path $script:TestDir 'test1.txt'), "Line 1`r`nLine 2", [System.Text.Encoding]::UTF8)
            [System.IO.File]::WriteAllText((Join-Path $script:TestDir 'test1.ps1'), "Line A`r`nLine B", [System.Text.Encoding]::UTF8)
            [System.IO.File]::WriteAllText((Join-Path $script:SubDir 'test2.txt'), "Line X`r`nLine Y", [System.Text.Encoding]::UTF8)

            # Create binary file that should be skipped
            [System.IO.File]::WriteAllBytes((Join-Path $script:TestDir 'binary.exe'), [byte[]](1, 2, 3, 0, 4, 5))
        }

        AfterEach {
            # Clean up test files created in this context
            $filesToClean = @(
                (Join-Path $script:TestDir 'test1.txt'),
                (Join-Path $script:TestDir 'test1.ps1'),
                (Join-Path $script:TestDir 'binary.exe')
            )

            foreach ($file in $filesToClean)
            {
                if (Test-Path $file)
                {
                    Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
                }
            }

            if (Test-Path $script:SubDir)
            {
                Remove-Item -Path $script:SubDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should process all text files in directory' {
            Convert-LineEnding -Path $script:TestDir -LineEnding 'LF'

            # Check that text files were converted
            $result1 = Get-Content -Path (Join-Path $script:TestDir 'test1.txt') -Raw
            $result1 | Should -Not -Match "`r"

            $result2 = Get-Content -Path (Join-Path $script:TestDir 'test1.ps1') -Raw
            $result2 | Should -Not -Match "`r"
        }

        It 'Should process recursively when Recurse is specified' {
            Convert-LineEnding -Path $script:TestDir -LineEnding 'LF' -Recurse

            # Check that file in subdirectory was also converted
            $result = Get-Content -Path (Join-Path $script:SubDir 'test2.txt') -Raw
            $result | Should -Not -Match "`r"
        }

        It 'Should not process recursively when Recurse is not specified' {
            Convert-LineEnding -Path $script:TestDir -LineEnding 'LF'

            # File in subdirectory should not be processed (still has CRLF)
            $result = Get-Content -Path (Join-Path $script:SubDir 'test2.txt') -Raw
            $result | Should -Match "`r"
        }

        It 'Should respect Include patterns' {
            Convert-LineEnding -Path $script:TestDir -LineEnding 'LF' -Include '*.ps1'

            # Only .ps1 file should be converted
            $ps1Result = Get-Content -Path (Join-Path $script:TestDir 'test1.ps1') -Raw
            $ps1Result | Should -Not -Match "`r"

            # .txt file should not be converted
            $txtResult = Get-Content -Path (Join-Path $script:TestDir 'test1.txt') -Raw
            $txtResult | Should -Match "`r"
        }

        It 'Should respect Exclude patterns' {
            Convert-LineEnding -Path $script:TestDir -LineEnding 'LF' -Exclude '*.txt'

            # .ps1 file should be converted
            $ps1Result = Get-Content -Path (Join-Path $script:TestDir 'test1.ps1') -Raw
            $ps1Result | Should -Not -Match "`r"

            # .txt file should not be converted (excluded)
            $txtResult = Get-Content -Path (Join-Path $script:TestDir 'test1.txt') -Raw
            $txtResult | Should -Match "`r"
        }
    }

    Context 'WhatIf Support' {
        BeforeEach {
            $script:TestFile = Join-Path $script:TestDir 'whatif-test.txt'
            [System.IO.File]::WriteAllText($script:TestFile, "Line 1`r`nLine 2", [System.Text.Encoding]::UTF8)
        }

        AfterEach {
            if (Test-Path $script:TestFile)
            {
                Remove-Item -Path $script:TestFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should not modify files when WhatIf is specified' {
            $originalContent = Get-Content -Path $script:TestFile -Raw

            Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -WhatIf

            $currentContent = Get-Content -Path $script:TestFile -Raw
            $currentContent | Should -Be $originalContent
            $currentContent | Should -Match "`r"  # Should still have CRLF
        }

        It 'Should show what would be processed when WhatIf is specified' {
            # WhatIf should not throw and should not modify the file
            { Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -WhatIf } | Should -Not -Throw

            # Verify file was not actually modified (this is the key test)
            $content = Get-Content -Path $script:TestFile -Raw
            $content | Should -Match "`r"  # Should still have CRLF
        }
    }

    Context 'PassThru Functionality' {
        BeforeEach {
            $script:TestFile = Join-Path $script:TestDir 'passthru-test.txt'
            [System.IO.File]::WriteAllText($script:TestFile, "Line 1`r`nLine 2`nLine 3", [System.Text.Encoding]::UTF8)
        }

        AfterEach {
            if (Test-Path $script:TestFile)
            {
                Remove-Item -Path $script:TestFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should return processing information when PassThru is specified' {
            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.FilePath | Should -Be $script:TestFile
            $result.Success | Should -Be $true
            $result.SourceEncoding | Should -Not -BeNullOrEmpty
            $result.TargetEncoding | Should -Not -BeNullOrEmpty
        }

        It 'Should return line ending counts' {
            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'CRLF' -PassThru

            # Should have counts of original and new line endings
            ($result.OriginalLF + $result.OriginalCRLF) | Should -BeGreaterThan 0
            ($result.NewLF + $result.NewCRLF) | Should -BeGreaterThan 0
        }

        It 'Should not return anything when PassThru is not specified' {
            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF'

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Error Handling' {
        It 'Should handle non-existent files gracefully' {
            $nonExistentFile = Join-Path $script:TestDir 'does-not-exist.txt'

            $errorMessages = @()
            Convert-LineEnding -Path $nonExistentFile -LineEnding 'LF' -ErrorVariable errorMessages -ErrorAction SilentlyContinue
            $errorMessages | Should -Not -BeNullOrEmpty
            $errorMessages[0] | Should -Match 'Path not found'
        }

        It 'Should handle read-only files when Force is not specified' {
            $script:ReadOnlyFile = Join-Path $script:TestDir 'readonly.txt'
            [System.IO.File]::WriteAllText($script:ReadOnlyFile, "Test content`r`n", [System.Text.Encoding]::UTF8)

            try
            {
                Set-ItemProperty -Path $script:ReadOnlyFile -Name IsReadOnly -Value $true

                $result = Convert-LineEnding -Path $script:ReadOnlyFile -LineEnding 'LF' -PassThru -ErrorAction SilentlyContinue
                $result.Success | Should -Be $false
                $result.Error | Should -Match 'read-only'
            }
            finally
            {
                # Clean up read-only file
                if (Test-Path $script:ReadOnlyFile)
                {
                    Set-ItemProperty -Path $script:ReadOnlyFile -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                    Remove-Item -Path $script:ReadOnlyFile -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It 'Should handle read-only files when Force is specified' {
            $script:ReadOnlyFile = Join-Path $script:TestDir 'readonly-force.txt'
            [System.IO.File]::WriteAllText($script:ReadOnlyFile, "Test content`r`n", [System.Text.Encoding]::UTF8)

            try
            {
                Set-ItemProperty -Path $script:ReadOnlyFile -Name IsReadOnly -Value $true

                $result = Convert-LineEnding -Path $script:ReadOnlyFile -LineEnding 'LF' -Force -PassThru
                $result.Success | Should -Be $true

                # Verify conversion worked
                $content = Get-Content -Path $script:ReadOnlyFile -Raw
                $content | Should -Not -Match "`r"
            }
            finally
            {
                # Clean up file
                if (Test-Path $script:ReadOnlyFile)
                {
                    Set-ItemProperty -Path $script:ReadOnlyFile -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                    Remove-Item -Path $script:ReadOnlyFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context 'Pipeline Support' {
        BeforeEach {
            # Create multiple test files with explicit CRLF line endings
            $script:PipelineFiles = @()
            for ($i = 1; $i -le 3; $i++)
            {
                $file = Join-Path $script:TestDir "pipeline-test$i.txt"
                [System.IO.File]::WriteAllText($file, "Content $i`r`nLine 2", [System.Text.Encoding]::UTF8)
                $script:PipelineFiles += $file
            }
        }

        AfterEach {
            $script:PipelineFiles | ForEach-Object {
                if (Test-Path $_)
                {
                    Remove-Item -Path $_ -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It 'Should accept pipeline input' {
            { $script:PipelineFiles | Convert-LineEnding -LineEnding 'LF' } | Should -Not -Throw

            # Verify all files were processed
            foreach ($file in $script:PipelineFiles)
            {
                $content = Get-Content -Path $file -Raw
                $content | Should -Not -Match "`r"
            }
        }

        It 'Should work with Get-ChildItem pipeline' {
            { Get-ChildItem -Path $script:TestDir -Filter '*.txt' | Convert-LineEnding -LineEnding 'LF' } | Should -Not -Throw

            # Verify files were processed
            foreach ($file in $script:PipelineFiles)
            {
                $content = Get-Content -Path $file -Raw
                $content | Should -Not -Match "`r"
            }
        }
    }

    Context 'EnsureEndingNewline Parameter' {
        BeforeEach {
            $script:TestFile = Join-Path $script:TestDir 'ending-newline-test.txt'
        }

        AfterEach {
            if (Test-Path $script:TestFile)
            {
                Remove-Item -Path $script:TestFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should have EnsureEndingNewline parameter' {
            $command = Get-Command Convert-LineEnding
            $command.Parameters.Keys | Should -Contain 'EnsureEndingNewline'
            $command.Parameters['EnsureEndingNewline'].ParameterType | Should -Be ([Switch])
        }

        It 'Should add ending newline to file without one' {
            # Create file without ending newline
            $content = 'Line 1' + [char]13 + [char]10 + 'Line 2 without newline'
            [System.IO.File]::WriteAllText($script:TestFile, $content, [System.Text.Encoding]::UTF8)

            Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -EnsureEndingNewline

            $result = [System.IO.File]::ReadAllText($script:TestFile)
            $expectedContent = 'Line 1' + [char]10 + 'Line 2 without newline' + [char]10
            $result | Should -Be $expectedContent
            $result | Should -Match ([char]10 + '$')
        }

        It 'Should not modify file that already ends with newline' {
            # Create file with ending newline
            $content = 'Line 1' + [char]13 + [char]10 + 'Line 2' + [char]13 + [char]10
            [System.IO.File]::WriteAllText($script:TestFile, $content, [System.Text.Encoding]::UTF8)

            # Wait a moment to ensure timestamp would change if file is modified
            Start-Sleep -Milliseconds 100

            Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -EnsureEndingNewline

            $result = [System.IO.File]::ReadAllText($script:TestFile)
            $result | Should -Be "Line 1`nLine 2`n"
            $result | Should -Match "`n$"
        }

        It 'Should add CRLF ending when LineEnding is CRLF' {
            # Create file without ending newline
            [System.IO.File]::WriteAllText($script:TestFile, 'Test content', [System.Text.Encoding]::UTF8)

            Convert-LineEnding -Path $script:TestFile -LineEnding 'CRLF' -EnsureEndingNewline

            $result = [System.IO.File]::ReadAllText($script:TestFile)
            $result | Should -Be "Test content`r`n"
            $result | Should -Match "`r`n$"
        }

        It 'Should add LF ending when LineEnding is LF' {
            # Create file without ending newline
            [System.IO.File]::WriteAllText($script:TestFile, 'Test content', [System.Text.Encoding]::UTF8)

            Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -EnsureEndingNewline

            $result = [System.IO.File]::ReadAllText($script:TestFile)
            $result | Should -Be "Test content`n"
            $result | Should -Match "`n$"
            $result | Should -Not -Match "`r"
        }

        It 'Should handle empty files correctly' {
            # Create empty file
            [System.IO.File]::WriteAllText($script:TestFile, '', [System.Text.Encoding]::UTF8)

            Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -EnsureEndingNewline

            # Empty files should get a newline added when EnsureEndingNewline is specified
            $result = [System.IO.File]::ReadAllText($script:TestFile)
            $result | Should -Be ([char]10)
        }

        It 'Should work with PassThru parameter' {
            # Create file without ending newline
            [System.IO.File]::WriteAllText($script:TestFile, 'Test content', [System.Text.Encoding]::UTF8)

            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -EnsureEndingNewline -PassThru

            $result.EndingNewlineAdded | Should -Be $true
            $result.Success | Should -Be $true
            $result.NewLF | Should -Be 1
        }

        It 'Should report EndingNewlineAdded as false when newline already exists' {
            # Create file with ending newline
            $content = 'Test content' + [char]10  # LF ending
            [System.IO.File]::WriteAllText($script:TestFile, $content, [System.Text.Encoding]::UTF8)

            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -EnsureEndingNewline -PassThru

            $result.EndingNewlineAdded | Should -Be $false
            $result.Success | Should -Be $true
        }

        It 'Should work with WhatIf parameter' {
            # Create file without ending newline
            [System.IO.File]::WriteAllText($script:TestFile, 'Test content', [System.Text.Encoding]::UTF8)

            # Should not throw and should not modify file
            { Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -EnsureEndingNewline -WhatIf } | Should -Not -Throw

            $result = [System.IO.File]::ReadAllText($script:TestFile)
            $result | Should -Be 'Test content'  # Should be unchanged
        }

        It 'Should work when only ending newline is needed (no line ending conversion)' {
            # Create file with LF endings but no final newline
            $content = 'Line 1' + [char]10 + 'Line 2 no ending'
            [System.IO.File]::WriteAllText($script:TestFile, $content, [System.Text.Encoding]::UTF8)

            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -EnsureEndingNewline -PassThru

            $result.EndingNewlineAdded | Should -Be $true
            $result.Success | Should -Be $true
            $result.NewLF | Should -Be 2  # 1 original + 1 added

            $content = [System.IO.File]::ReadAllText($script:TestFile)
            $content | Should -Be "Line 1`nLine 2 no ending`n"
        }

        It 'Should work when only ending newline is needed (no encoding conversion)' {
            # Create file with correct line endings and encoding but no final newline
            # Use UTF8 without BOM so that when we specify UTF8 target, no encoding change is needed
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($script:TestFile, 'Test content', $utf8NoBom)

            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -Encoding 'UTF8' -EnsureEndingNewline -PassThru

            $result.EndingNewlineAdded | Should -Be $true
            $result.EncodingChanged | Should -Be $false
            $result.Success | Should -Be $true

            $content = [System.IO.File]::ReadAllText($script:TestFile)
            $content | Should -Be "Test content`n"
        }

        It 'Should work with complex content including line endings within text' {
            # Create file with mixed content and no ending newline
            $content = 'Line 1' + [char]13 + [char]10 + 'Line 2' + [char]10 + 'Line 3 without ending'
            [System.IO.File]::WriteAllText($script:TestFile, $content, [System.Text.Encoding]::UTF8)

            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -EnsureEndingNewline -PassThru

            $result.EndingNewlineAdded | Should -Be $true
            $result.Success | Should -Be $true

            $finalContent = [System.IO.File]::ReadAllText($script:TestFile)
            $finalContent | Should -Be "Line 1`nLine 2`nLine 3 without ending`n"
        }

        It 'Should handle files with only whitespace content' {
            # Create file with only spaces/tabs but no newline
            $whitespaceContent = '   ' + [char]9 + '  '  # spaces + tab + spaces
            [System.IO.File]::WriteAllText($script:TestFile, $whitespaceContent, [System.Text.Encoding]::UTF8)

            $result = Convert-LineEnding -Path $script:TestFile -LineEnding 'LF' -EnsureEndingNewline -PassThru

            $result.EndingNewlineAdded | Should -Be $true
            $result.Success | Should -Be $true

            $finalContent = [System.IO.File]::ReadAllText($script:TestFile)
            $expectedContent = $whitespaceContent + [char]10
            $finalContent | Should -Be $expectedContent
        }
    }
}
