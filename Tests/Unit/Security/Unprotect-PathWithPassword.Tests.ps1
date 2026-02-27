#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Unprotect-PathWithPassword function.

.DESCRIPTION
    Tests the Unprotect-PathWithPassword function which decrypts files and directories that were
    encrypted with Protect-PathWithPassword. Validates password verification, file decryption,
    and proper handling of encrypted content.

.NOTES
    These tests are based on the examples in the Unprotect-PathWithPassword function documentation.
    Tests verify password-based decryption and round-trip compatibility with encryption function.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function
    . "$PSScriptRoot/../../../Functions/Security/Unprotect-PathWithPassword.ps1"
    . "$PSScriptRoot/../../../Functions/Security/Protect-PathWithPassword.ps1"
}

Describe 'Unprotect-PathWithPassword Unit Tests' {
    BeforeEach {
        # Create test directory structure
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('UnprotectPathTest_' + [System.Guid]::NewGuid().ToString('N')[0..7] -join '')
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        # Create test password
        $script:TestPassword = ConvertTo-SecureString 'TestPassword123!' -AsPlainText -Force
        $script:WrongPassword = ConvertTo-SecureString 'WrongPassword456!' -AsPlainText -Force

        # Create test files and encrypt them
        $script:TestFile1 = Join-Path -Path $script:TestDir -ChildPath 'test1.txt'
        $script:TestFile2 = Join-Path -Path $script:TestDir -ChildPath 'test2.txt'
        $script:SubDir = Join-Path -Path $script:TestDir -ChildPath 'subdir'
        $script:TestFile3 = Join-Path -Path $script:SubDir -ChildPath 'test3.txt'

        'Test content 1' | Out-File -FilePath $script:TestFile1 -Encoding UTF8
        'Test content 2' | Out-File -FilePath $script:TestFile2 -Encoding UTF8
        New-Item -Path $script:SubDir -ItemType Directory -Force | Out-Null
        'Test content 3' | Out-File -FilePath $script:TestFile3 -Encoding UTF8

        # Encrypt the test files
        Protect-PathWithPassword -Path $script:TestFile1 -Password $script:TestPassword | Out-Null
        Protect-PathWithPassword -Path $script:TestFile2 -Password $script:TestPassword | Out-Null
        Protect-PathWithPassword -Path $script:TestFile3 -Password $script:TestPassword | Out-Null

        # Store encrypted file paths
        $script:EncFile1 = $script:TestFile1 + '.enc'
        $script:EncFile2 = $script:TestFile2 + '.enc'
        $script:EncFile3 = $script:TestFile3 + '.enc'

        # Remove original files to simulate real-world scenario
        Remove-Item $script:TestFile1, $script:TestFile2, $script:TestFile3 -Force
    }

    AfterEach {
        # Clean up test directory - ensure cleanup even if tests fail
        try
        {
            if ($script:TestDir -and (Test-Path $script:TestDir))
            {
                Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        catch
        {
            # Force cleanup with additional attempts if first fails
            try
            {
                Start-Sleep -Milliseconds 100
                if (Test-Path $script:TestDir)
                {
                    Get-ChildItem -Path $script:TestDir -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                    Remove-Item -Path $script:TestDir -Force -ErrorAction SilentlyContinue
                }
            }
            catch
            {
                Write-Warning "Failed to cleanup test directory: $script:TestDir - $_"
            }
        }
    }

    Context 'Parameter Validation' {
        It 'Should require Path parameter' {
            # Test that the Path parameter is mandatory by checking the parameter metadata
            $command = Get-Command Unprotect-PathWithPassword
            $pathParam = $command.Parameters['Path']
            $pathParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should accept path from pipeline' {
            # Ensure the encrypted test file exists before piping it
            Test-Path $script:EncFile1 | Should -Be $true
            $result = Get-Item $script:EncFile1 | Unprotect-PathWithPassword -Password $script:TestPassword -Force
            $result.Success | Should -Be $true
        }

        It 'Should throw when path does not exist' {
            { Unprotect-PathWithPassword -Path 'C:\NonExistent\file.enc' -Password $script:TestPassword } | Should -Throw '*does not exist*'
        }
    }

    Context 'Single File Decryption' {
        It 'Should decrypt a single file successfully' {
            $result = Unprotect-PathWithPassword -Path $script:EncFile1 -Password $script:TestPassword -Force

            $result.Success | Should -Be $true
            $result.EncryptedPath | Should -Be $script:EncFile1
            $result.DecryptedPath | Should -Be $script:TestFile1
            Test-Path $script:TestFile1 | Should -Be $true
        }

        It 'Should restore original file content correctly' {
            Unprotect-PathWithPassword -Path $script:EncFile1 -Password $script:TestPassword -Force | Out-Null

            $content = Get-Content -Path $script:TestFile1 -Raw
            $content.Trim() | Should -Be 'Test content 1'
        }

        It 'Should remove .enc extension by default' {
            $result = Unprotect-PathWithPassword -Path $script:EncFile1 -Password $script:TestPassword -Force
            $result.DecryptedPath | Should -Be $script:TestFile1
        }

        It 'Should respect custom output path' {
            $customOutput = Join-Path -Path $script:TestDir -ChildPath 'custom.decrypted'
            $result = Unprotect-PathWithPassword -Path $script:EncFile1 -Password $script:TestPassword -OutputPath $customOutput -Force

            $result.DecryptedPath | Should -Be $customOutput
            Test-Path $customOutput | Should -Be $true
        }

        It 'Should fail with wrong password' {
            # Clean up any existing decrypted file to ensure we test password validation, not file overwrite
            if (Test-Path $script:TestFile1)
            {
                Remove-Item $script:TestFile1 -Force
            }

            $result = Unprotect-PathWithPassword -Path $script:EncFile1 -Password $script:WrongPassword -ErrorAction SilentlyContinue

            $result.Success | Should -Be $false
            $result.Error | Should -Match 'Decryption failed|Invalid password'
        }
    }

    Context 'Directory Decryption' {
        It 'Should decrypt .enc files in directory without recursion' {
            Unprotect-PathWithPassword -Path $script:TestDir -Password $script:TestPassword -Force | Out-Null

            # Should decrypt files in root directory only
            Test-Path $script:TestFile1 | Should -Be $true
            Test-Path $script:TestFile2 | Should -Be $true
            Test-Path $script:TestFile3 | Should -Be $false
        }

        It 'Should decrypt .enc files recursively when -Recurse is specified' {
            Unprotect-PathWithPassword -Path $script:TestDir -Password $script:TestPassword -Recurse -Force | Out-Null

            # Should decrypt all .enc files including subdirectories
            Test-Path $script:TestFile1 | Should -Be $true
            Test-Path $script:TestFile2 | Should -Be $true
            Test-Path $script:TestFile3 | Should -Be $true
        }

        It 'Should only process .enc files in directories' {
            # Create a non-.enc file
            $nonEncFile = Join-Path -Path $script:TestDir -ChildPath 'regular.txt'
            'Regular content' | Out-File -FilePath $nonEncFile -Encoding UTF8

            Unprotect-PathWithPassword -Path $script:TestDir -Password $script:TestPassword -Force | Out-Null

            # .enc files should be processed
            Test-Path $script:TestFile1 | Should -Be $true
            Test-Path $script:TestFile2 | Should -Be $true
            # Regular file should remain unchanged
            Test-Path $nonEncFile | Should -Be $true
        }
    }

    Context 'File Management Options' {
        It 'Should remove encrypted file by default' {
            Unprotect-PathWithPassword -Path $script:EncFile1 -Password $script:TestPassword -Force | Out-Null

            Test-Path $script:TestFile1 | Should -Be $true
            Test-Path $script:EncFile1 | Should -Be $false
        }

        It 'Should keep encrypted file when -KeepEncrypted is specified' {
            $result = Unprotect-PathWithPassword -Path $script:EncFile1 -Password $script:TestPassword -KeepEncrypted

            $result.Success | Should -Be $true
            Test-Path $script:TestFile1 | Should -Be $true
            Test-Path $script:EncFile1 | Should -Be $true
        }

        It 'Should overwrite when -Force is specified' {
            # Create the target file first
            'Existing content' | Out-File -FilePath $script:TestFile1 -Encoding UTF8

            $result = Unprotect-PathWithPassword -Path $script:EncFile1 -Password $script:TestPassword -Force

            $result.Success | Should -Be $true
            $content = Get-Content -Path $script:TestFile1 -Raw
            $content.Trim() | Should -Be 'Test content 1'
        }
    }

    Context 'Round-trip Compatibility' {
        It 'Should successfully decrypt files encrypted by Protect-PathWithPassword' {
            # Test with various file sizes and content types
            $testCases = @(
                @{ Content = 'Simple text'; Name = 'simple.txt' }
                @{ Content = ''; Name = 'empty.txt' }
                @{ Content = "Line 1`nLine 2`nLine 3"; Name = 'multiline.txt' }
                @{ Content = [String]::new('X', 1000); Name = 'large.txt' }
            )

            foreach ($case in $testCases)
            {
                $testFile = Join-Path -Path $script:TestDir -ChildPath $case.Name
                $case.Content | Out-File -FilePath $testFile -Encoding UTF8 -NoNewline

                # Encrypt then decrypt
                Protect-PathWithPassword -Path $testFile -Password $script:TestPassword | Out-Null
                Remove-Item $testFile -Force
                $encFile = $testFile + '.enc'

                $result = Unprotect-PathWithPassword -Path $encFile -Password $script:TestPassword

                $result.Success | Should -Be $true
                $decryptedContent = Get-Content -Path $testFile -Raw
                if ($case.Content -eq '')
                {
                    $decryptedContent | Should -BeNullOrEmpty
                }
                else
                {
                    $decryptedContent.TrimEnd("`r", "`n") | Should -Be $case.Content
                }
            }
        }
    }
}
