BeforeAll {
    # Dot source the function
    . $PSScriptRoot/../../../Functions/Utilities/Replace-StringInFile.ps1
}

Describe 'Replace-StringInFile' -Tag 'Unit' {

    BeforeEach {
        # Create temporary test directory
        $script:testDir = Join-Path ([System.IO.Path]::GetTempPath()) "replace-string-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
    }

    AfterEach {
        # Clean up test directory
        if (Test-Path $script:testDir)
        {
            Remove-Item -Path $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Parameter Validation' {
        It 'Should have mandatory Path parameter' {
            (Get-Command Replace-StringInFile).Parameters['Path'].Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have mandatory OldString parameter' {
            (Get-Command Replace-StringInFile).Parameters['OldString'].Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have mandatory NewString parameter' {
            (Get-Command Replace-StringInFile).Parameters['NewString'].Attributes.Mandatory | Should -Contain $true
        }

        It 'Should accept valid encoding values' {
            $testFile = Join-Path $script:testDir 'test.txt'
            'test content' | Set-Content -Path $testFile -NoNewline
            { Replace-StringInFile -Path $testFile -OldString 'test' -NewString 'new' -Encoding UTF8 -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should accept pipeline input for Path' {
            $testFile = Join-Path $script:testDir 'test.txt'
            'test content' | Set-Content -Path $testFile -NoNewline
            { $testFile | Replace-StringInFile -OldString 'test' -NewString 'new' -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context 'Basic String Replacement' {
        It 'Should replace a simple string' {
            $testFile = Join-Path $script:testDir 'simple.txt'
            'Hello World' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'World' -NewString 'PowerShell'

            $result.MatchCount | Should -Be 1
            $result.ReplacementsMade | Should -Be $true
            (Get-Content -Path $testFile -Raw) | Should -Be 'Hello PowerShell'
        }

        It 'Should replace multiple occurrences' {
            $testFile = Join-Path $script:testDir 'multiple.txt'
            'foo bar foo baz foo' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'foo' -NewString 'test'

            $result.MatchCount | Should -Be 3
            $result.ReplacementsMade | Should -Be $true
            (Get-Content -Path $testFile -Raw) | Should -Be 'test bar test baz test'
        }

        It 'Should handle empty replacement string' {
            $testFile = Join-Path $script:testDir 'empty.txt'
            'Hello World!' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'World' -NewString ''

            $result.MatchCount | Should -Be 1
            (Get-Content -Path $testFile -Raw) | Should -Be 'Hello !'
        }

        It 'Should return zero matches when string not found' {
            $testFile = Join-Path $script:testDir 'notfound.txt'
            'Hello World' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'xyz' -NewString 'abc'

            $result.MatchCount | Should -Be 0
            $result.ReplacementsMade | Should -Be $false
        }

        It 'Should be case-sensitive by default' {
            $testFile = Join-Path $script:testDir 'case.txt'
            'Hello hello HELLO' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello' -NewString 'hi'

            $result.MatchCount | Should -Be 1
            (Get-Content -Path $testFile -Raw) | Should -Be 'Hello hi HELLO'
        }
    }

    Context 'Case-Insensitive Replacement' {
        It 'Should replace case-insensitively with -CaseInsensitive switch' {
            $testFile = Join-Path $script:testDir 'caseinsensitive.txt'
            'Hello hello HELLO' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello' -NewString 'hi' -CaseInsensitive

            $result.MatchCount | Should -Be 3
            (Get-Content -Path $testFile -Raw) | Should -Be 'hi hi hi'
        }
    }

    Context 'Regex Replacement' {
        It 'Should replace using regex pattern' {
            $testFile = Join-Path $script:testDir 'regex.txt'
            'Phone: 123-456-7890' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString '\d{3}-\d{3}-\d{4}' -NewString 'XXX-XXX-XXXX' -Regex

            $result.MatchCount | Should -Be 1
            (Get-Content -Path $testFile -Raw) | Should -Be 'Phone: XXX-XXX-XXXX'
        }

        It 'Should support regex capture groups' {
            $testFile = Join-Path $script:testDir 'capture.txt'
            'Date: 2024-11-14' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString '(\d{4})-(\d{2})-(\d{2})' -NewString '$3/$2/$1' -Regex

            $result.MatchCount | Should -Be 1
            (Get-Content -Path $testFile -Raw) | Should -Be 'Date: 14/11/2024'
        }

        It 'Should handle complex regex patterns' {
            $testFile = Join-Path $script:testDir 'email.txt'
            'Contact: user@example.com for help' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b' -NewString 'REDACTED' -Regex

            $result.MatchCount | Should -Be 1
            (Get-Content -Path $testFile -Raw) | Should -Be 'Contact: REDACTED for help'
        }
    }

    Context 'Special Characters' {
        It 'Should handle literal special characters in non-regex mode' {
            $testFile = Join-Path $script:testDir 'special.txt'
            'Price: $100.00' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString '$100.00' -NewString '$200.00'

            $result.MatchCount | Should -Be 1
            (Get-Content -Path $testFile -Raw) | Should -Be 'Price: $200.00'
        }

        It 'Should handle parentheses and brackets literally' {
            $testFile = Join-Path $script:testDir 'brackets.txt'
            'Array[0] = (value)' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString '[0]' -NewString '[1]'

            $result.MatchCount | Should -Be 1
            (Get-Content -Path $testFile -Raw) | Should -Be 'Array[1] = (value)'
        }
    }

    Context 'Backup Functionality' {
        It 'Should create backup file when -Backup is specified' {
            $testFile = Join-Path $script:testDir 'backup.txt'
            'original content' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'original' -NewString 'modified' -Backup

            $result.BackupCreated | Should -Be $true
            Test-Path "$testFile.bak" | Should -Be $true
            (Get-Content -Path "$testFile.bak" -Raw) | Should -Be 'original content'
            (Get-Content -Path $testFile -Raw) | Should -Be 'modified content'
        }

        It 'Should not create backup by default' {
            $testFile = Join-Path $script:testDir 'nobackup.txt'
            'content' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'content' -NewString 'new'

            $result.BackupCreated | Should -Be $false
            Test-Path "$testFile.bak" | Should -Be $false
        }
    }

    Context 'Multiple Files' {
        It 'Should process multiple files' {
            $file1 = Join-Path $script:testDir 'file1.txt'
            $file2 = Join-Path $script:testDir 'file2.txt'
            'foo bar' | Set-Content -Path $file1 -NoNewline
            'bar baz' | Set-Content -Path $file2 -NoNewline

            $results = Replace-StringInFile -Path $file1, $file2 -OldString 'bar' -NewString 'test'

            $results.Count | Should -Be 2
            ($results | Where-Object { $_.ReplacementsMade }).Count | Should -Be 2
            (Get-Content -Path $file1 -Raw) | Should -Be 'foo test'
            (Get-Content -Path $file2 -Raw) | Should -Be 'test baz'
        }

        It 'Should handle wildcards in path' {
            $file1 = Join-Path $script:testDir 'test1.txt'
            $file2 = Join-Path $script:testDir 'test2.txt'
            $file3 = Join-Path $script:testDir 'other.log'
            'foo' | Set-Content -Path $file1 -NoNewline
            'foo' | Set-Content -Path $file2 -NoNewline
            'foo' | Set-Content -Path $file3 -NoNewline

            $pattern = Join-Path $script:testDir '*.txt'
            $results = Replace-StringInFile -Path $pattern -OldString 'foo' -NewString 'bar'

            $results.Count | Should -Be 2
            (Get-Content -Path $file1 -Raw) | Should -Be 'bar'
            (Get-Content -Path $file2 -Raw) | Should -Be 'bar'
            (Get-Content -Path $file3 -Raw) | Should -Be 'foo'
        }
    }

    Context 'WhatIf and Confirm Support' {
        It 'Should support -WhatIf without making changes' {
            $testFile = Join-Path $script:testDir 'whatif.txt'
            'original' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'original' -NewString 'modified' -WhatIf

            (Get-Content -Path $testFile -Raw) | Should -Be 'original'
        }
    }

    Context 'Encoding Support' {
        It 'Should respect specified encoding' {
            $testFile = Join-Path $script:testDir 'encoding.txt'
            'test' | Set-Content -Path $testFile -Encoding UTF8 -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'test' -NewString 'new' -Encoding UTF8

            $result.ReplacementsMade | Should -Be $true
            (Get-Content -Path $testFile -Raw) | Should -Be 'new'
        }
    }

    Context 'Binary and Non-Text Files' {
        It 'Should skip binary files' {
            $binaryFile = Join-Path $script:testDir 'binary.dat'
            $bytes = [byte[]](0, 1, 2, 3, 0, 0, 255, 254)
            [System.IO.File]::WriteAllBytes($binaryFile, $bytes)

            $null = Replace-StringInFile -Path $binaryFile -OldString 'test' -NewString 'new' -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings | Should -Match 'binary'
        }
    }

    Context 'Edge Cases' {
        It 'Should handle multiline content' {
            $testFile = Join-Path $script:testDir 'multiline.txt'
            @'
Line 1
Line 2
Line 3
'@ | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'Line 2' -NewString 'Modified Line'

            $result.MatchCount | Should -Be 1
            (Get-Content -Path $testFile -Raw) | Should -Match 'Modified Line'
        }

        It 'Should handle empty files' {
            $testFile = Join-Path $script:testDir 'empty.txt'
            '' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'test' -NewString 'new'

            $result.MatchCount | Should -Be 0
            $result.ReplacementsMade | Should -Be $false
        }

        It 'Should handle very long lines' {
            $testFile = Join-Path $script:testDir 'longline.txt'
            $longString = 'a' * 10000 + 'REPLACE' + 'b' * 10000
            $longString | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'REPLACE' -NewString 'DONE'

            $result.MatchCount | Should -Be 1
            (Get-Content -Path $testFile -Raw) | Should -Match 'DONE'
        }
    }

    Context 'Error Handling' {
        It 'Should handle non-existent files gracefully' {
            $nonExistent = Join-Path $script:testDir 'doesnotexist.txt'

            { Replace-StringInFile -Path $nonExistent -OldString 'test' -NewString 'new' -ErrorAction Stop } | Should -Throw
        }

        It 'Should skip directories' {
            $subDir = Join-Path $script:testDir 'subdir'
            New-Item -ItemType Directory -Path $subDir -Force | Out-Null

            $result = Replace-StringInFile -Path $subDir -OldString 'test' -NewString 'new' -WarningAction SilentlyContinue

            $result | Should -BeNullOrEmpty
        }

        It 'Should handle invalid regex patterns' {
            $testFile = Join-Path $script:testDir 'invalidregex.txt'
            'test' | Set-Content -Path $testFile -NoNewline

            { Replace-StringInFile -Path $testFile -OldString '(' -NewString 'new' -Regex -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Output Object' {
        It 'Should return correct output object properties' {
            $testFile = Join-Path $script:testDir 'output.txt'
            'test content' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'test' -NewString 'new'

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'FilePath'
            $result.PSObject.Properties.Name | Should -Contain 'MatchCount'
            $result.PSObject.Properties.Name | Should -Contain 'ReplacementsMade'
            $result.PSObject.Properties.Name | Should -Contain 'BackupCreated'
            $result.PSObject.Properties.Name | Should -Contain 'Error'
        }

        # Skip on Linux when running as root because root can write to read-only files
        It 'Should set Error property when replacement fails' -Skip:($IsLinux -and (whoami) -eq 'root') {
            $testFile = Join-Path $script:testDir 'readonly.txt'
            'test' | Set-Content -Path $testFile -NoNewline

            # Make file read-only using platform-appropriate method
            if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6)
            {
                # Windows - use IsReadOnly property
                $fileItem = Get-Item $testFile
                $fileItem.IsReadOnly = $true
            }
            else
            {
                # Linux/macOS - use chmod to remove write permissions
                chmod 444 $testFile
            }

            $result = Replace-StringInFile -Path $testFile -OldString 'test' -NewString 'new' -ErrorAction SilentlyContinue

            # Restore write permissions for cleanup
            if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6)
            {
                $fileItem = Get-Item $testFile
                $fileItem.IsReadOnly = $false
            }
            else
            {
                chmod 644 $testFile
            }

            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Verbose Output' {
        It 'Should provide verbose messages' {
            $testFile = Join-Path $script:testDir 'verbose.txt'
            'test' | Set-Content -Path $testFile -NoNewline

            $verboseOutput = $null
            Replace-StringInFile -Path $testFile -OldString 'test' -NewString 'new' -Verbose 4>&1 | Tee-Object -Variable verboseOutput | Out-Null

            $verboseOutput | Should -Not -BeNullOrEmpty
        }
    }

    Context 'PreserveCase Parameter Validation' {
        It 'Should throw when PreserveCase is used with Regex' {
            $testFile = Join-Path $script:testDir 'test.txt'
            'foo bar' | Set-Content -Path $testFile -NoNewline

            {
                Replace-StringInFile -Path $testFile -OldString 'foo' -NewString 'bar' -Regex -PreserveCase -CaseInsensitive -ErrorAction Stop
            } | Should -Throw -ExpectedMessage 'PreserveCase cannot be used with Regex mode'
        }

        It 'Should throw when PreserveCase is used without CaseInsensitive' {
            $testFile = Join-Path $script:testDir 'test.txt'
            'foo bar' | Set-Content -Path $testFile -NoNewline

            {
                Replace-StringInFile -Path $testFile -OldString 'foo' -NewString 'bar' -PreserveCase -ErrorAction Stop
            } | Should -Throw -ExpectedMessage 'PreserveCase requires CaseInsensitive to be enabled'
        }

        It 'Should accept valid parameter combinations' {
            $testFile = Join-Path $script:testDir 'test.txt'
            'test content' | Set-Content -Path $testFile -NoNewline

            {
                Replace-StringInFile -Path $testFile -OldString 'test' -NewString 'demo' -CaseInsensitive -PreserveCase -WhatIf -ErrorAction Stop
            } | Should -Not -Throw
        }
    }

    Context 'PreserveCase Functionality' {
        It 'Should preserve ALL CAPS case' {
            $testFile = Join-Path $script:testDir 'caps.txt'
            'HELLO world' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello' -NewString 'goodbye' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'GOODBYE world'
            $result.ReplacementsMade | Should -Be $true
            $result.MatchCount | Should -Be 1
        }

        It 'Should preserve all lowercase case' {
            $testFile = Join-Path $script:testDir 'lower.txt'
            'hello WORLD' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello' -NewString 'GOODBYE' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'goodbye WORLD'
            $result.ReplacementsMade | Should -Be $true
        }

        It 'Should preserve First Capital case' {
            $testFile = Join-Path $script:testDir 'firstcap.txt'
            'Hello world' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello' -NewString 'goodbye' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'Goodbye world'
            $result.ReplacementsMade | Should -Be $true
        }

        It 'Should preserve Title Case for multi-word strings' {
            $testFile = Join-Path $script:testDir 'title.txt'
            'Hello World from everyone' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello world' -NewString 'goodbye universe' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'Goodbye Universe from everyone'
            $result.ReplacementsMade | Should -Be $true
        }

        It 'Should handle multiple matches with different cases' {
            $testFile = Join-Path $script:testDir 'multi.txt'
            @'
foo is here
FOO is there
Foo is everywhere
'@ | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'foo' -NewString 'bar' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Match 'bar is here'
            $content | Should -Match 'BAR is there'
            $content | Should -Match 'Bar is everywhere'
            $result.MatchCount | Should -Be 3
            $result.ReplacementsMade | Should -Be $true
        }

        It 'Should handle mixed case by using replacement as-is' {
            $testFile = Join-Path $script:testDir 'mixed.txt'
            'hElLo world' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello' -NewString 'goodbye' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            # Mixed case that doesn't match a clear pattern uses replacement as-is
            $content | Should -Be 'goodbye world'
        }

        It 'Should work with single character replacements' {
            $testFile = Join-Path $script:testDir 'single.txt'
            'A B C a b c' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'a' -NewString 'x' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'X B C x b c'
            $result.MatchCount | Should -Be 2
        }

        It 'Should preserve case with underscores and special characters' {
            $testFile = Join-Path $script:testDir 'special.txt'
            'OLD_NAME new_name' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'old_name' -NewString 'better_name' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'BETTER_NAME new_name'
            $result.MatchCount | Should -Be 1
        }

        It 'Should handle empty lines without errors' {
            $testFile = Join-Path $script:testDir 'empty.txt'
            @'
HELLO

hello
'@ | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello' -NewString 'goodbye' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Match 'GOODBYE'
            $content | Should -Match "`n`ngoodbye"
            $result.MatchCount | Should -Be 2
        }

        It 'Should not modify content when no matches found' {
            $testFile = Join-Path $script:testDir 'nomatch.txt'
            $originalContent = 'No matches here'
            $originalContent | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'foo' -NewString 'bar' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be $originalContent
            $result.MatchCount | Should -Be 0
            $result.ReplacementsMade | Should -Be $false
        }

        It 'Should preserve camelCase pattern' {
            $testFile = Join-Path $script:testDir 'camel.txt'
            'userName is required' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'username' -NewString 'account id' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'accountId is required'
            $result.ReplacementsMade | Should -Be $true
        }

        It 'Should preserve PascalCase pattern' {
            $testFile = Join-Path $script:testDir 'pascal.txt'
            'UserName is required' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'username' -NewString 'account id' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'AccountId is required'
            $result.ReplacementsMade | Should -Be $true
        }

        It 'Should preserve camelCase with multi-word replacement' {
            $testFile = Join-Path $script:testDir 'camel-multi.txt'
            'oldUserName' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'oldusername' -NewString 'new account id' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'newAccountId'
            $result.ReplacementsMade | Should -Be $true
        }

        It 'Should preserve PascalCase with multi-word replacement' {
            $testFile = Join-Path $script:testDir 'pascal-multi.txt'
            'OldUserName' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'oldusername' -NewString 'new account id' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'NewAccountId'
            $result.ReplacementsMade | Should -Be $true
        }

        It 'Should handle multiple camelCase/PascalCase variations' {
            $testFile = Join-Path $script:testDir 'case-variations.txt'
            @'
userName
UserName
USERNAME
'@ | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'username' -NewString 'account id' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Match 'accountId'
            $content | Should -Match 'AccountId'
            $content | Should -Match 'ACCOUNT ID'  # ALL CAPS preserves spaces
            $result.MatchCount | Should -Be 3
        }
    }

    Context 'PreserveCase with File Operations' {
        It 'Should create backup when -Backup is specified with PreserveCase' {
            $testFile = Join-Path $script:testDir 'backup.txt'
            'HELLO world' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello' -NewString 'goodbye' -CaseInsensitive -PreserveCase -Backup

            $result.BackupCreated | Should -Be $true
            Test-Path -Path "$testFile.bak" | Should -Be $true

            $backupContent = Get-Content -Path "$testFile.bak" -Raw
            $backupContent | Should -Be 'HELLO world'
        }

        It 'Should support WhatIf with PreserveCase' {
            $testFile = Join-Path $script:testDir 'whatif.txt'
            'HELLO world' | Set-Content -Path $testFile -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello' -NewString 'goodbye' -CaseInsensitive -PreserveCase -WhatIf

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'HELLO world'  # Should not be modified
            $result.ReplacementsMade | Should -Be $false
            $result.MatchCount | Should -Be 1  # Should still report matches found
        }

        It 'Should work with pipeline input' {
            $testFile = Join-Path $script:testDir 'pipeline.txt'
            'HELLO world' | Set-Content -Path $testFile -NoNewline

            $result = Get-Item -Path $testFile | Replace-StringInFile -OldString 'hello' -NewString 'goodbye' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Be 'GOODBYE world'
            $result.ReplacementsMade | Should -Be $true
        }
    }
}
