#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Protect-PathWithPassword function.

.DESCRIPTION
    Tests the Protect-PathWithPassword function which encrypts files and directories with password protection.
    Validates parameter validation, file encryption, directory processing, and pipeline support.

.NOTES
    These tests are based on the examples in the Protect-PathWithPassword function documentation.
    Tests verify password-based encryption of files and directories with proper security handling.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function
    . "$PSScriptRoot/../../../Functions/Security/Protect-PathWithPassword.ps1"
}

Describe 'Protect-PathWithPassword Unit Tests' {
    BeforeEach {
        # Create test directory structure
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('ProtectPathTest_' + [System.Guid]::NewGuid().ToString('N')[0..7] -join '')
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        # Create test password
        $script:TestPassword = ConvertTo-SecureString 'TestPassword123!' -AsPlainText -Force

        # Create test files
        $script:TestFile1 = Join-Path -Path $script:TestDir -ChildPath 'test1.txt'
        $script:TestFile2 = Join-Path -Path $script:TestDir -ChildPath 'test2.txt'
        $script:SubDir = Join-Path -Path $script:TestDir -ChildPath 'subdir'
        $script:TestFile3 = Join-Path -Path $script:SubDir -ChildPath 'test3.txt'

        'Test content 1' | Out-File -FilePath $script:TestFile1 -Encoding UTF8
        'Test content 2' | Out-File -FilePath $script:TestFile2 -Encoding UTF8
        New-Item -Path $script:SubDir -ItemType Directory -Force | Out-Null
        'Test content 3' | Out-File -FilePath $script:TestFile3 -Encoding UTF8
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
            $command = Get-Command Protect-PathWithPassword
            $pathParam = $command.Parameters['Path']
            $pathParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should accept path from pipeline' {
            $result = Get-Item $script:TestFile1 | Protect-PathWithPassword -Password $script:TestPassword -Force
            $result.Success | Should -Be $true
        }

        It 'Should throw when path does not exist' {
            { Protect-PathWithPassword -Path 'C:\NonExistent\file.txt' -Password $script:TestPassword } | Should -Throw '*does not exist*'
        }
    }

    Context 'Single File Encryption' {
        It 'Should encrypt a single file successfully (Example: Protect-PathWithPassword -Path "file.txt" -Password $password -Force)' {
            # Test basic file encryption functionality as shown in documentation
            $result = Protect-PathWithPassword -Path $script:TestFile1 -Password $script:TestPassword -Force

            $result.Success | Should -Be $true
            $result.OriginalPath | Should -Be $script:TestFile1
            $result.EncryptedPath | Should -Be ($script:TestFile1 + '.enc')
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
        }

        It 'Should create encrypted file with .enc extension by default' {
            Protect-PathWithPassword -Path $script:TestFile1 -Password $script:TestPassword -Force | Out-Null
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
        }

        It 'Should respect custom output path' {
            $customOutput = Join-Path -Path $script:TestDir -ChildPath 'custom.encrypted'
            # Ensure the custom output file doesn't exist
            if (Test-Path $customOutput) { Remove-Item $customOutput -Force }

            $result = Protect-PathWithPassword -Path $script:TestFile1 -Password $script:TestPassword -OutputPath $customOutput -Force

            $result.EncryptedPath | Should -Be $customOutput
            Test-Path $customOutput | Should -Be $true
        }

        It 'Should support RemoveOriginal parameter' {
            $result = Protect-PathWithPassword -Path $script:TestFile1 -Password $script:TestPassword -RemoveOriginal -Force

            $result.Success | Should -Be $true
            Test-Path $script:TestFile1 | Should -Be $false
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
        }
    }

    Context 'Directory Encryption' {
        It 'Should encrypt files in directory without recursion' {
            Protect-PathWithPassword -Path $script:TestDir -Password $script:TestPassword -Force | Out-Null

            # Should encrypt files in root directory only
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
            Test-Path ($script:TestFile2 + '.enc') | Should -Be $true
            Test-Path ($script:TestFile3 + '.enc') | Should -Be $false
        }

        It 'Should encrypt files recursively when -Recurse is specified' {
            Protect-PathWithPassword -Path $script:TestDir -Password $script:TestPassword -Recurse -Force | Out-Null

            # Should encrypt all files including subdirectories
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
            Test-Path ($script:TestFile2 + '.enc') | Should -Be $true
            Test-Path ($script:TestFile3 + '.enc') | Should -Be $true
        }
    }

    Context 'Pipeline Support' {
        It 'Should accept input from pipeline' {
            $results = Get-ChildItem -Path $script:TestDir -File | Protect-PathWithPassword -Password $script:TestPassword -Force

            $results | Should -HaveCount 2
            $results | ForEach-Object { $_.Success | Should -Be $true }
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
            Test-Path ($script:TestFile2 + '.enc') | Should -Be $true
        }
    }

    Context 'File Overwrite Behavior' {
        It 'Should overwrite when -Force is specified' {
            # Create initial encrypted file
            Protect-PathWithPassword -Path $script:TestFile1 -Password $script:TestPassword -Force | Out-Null
            $initialTime = (Get-Item ($script:TestFile1 + '.enc')).LastWriteTime

            Start-Sleep -Milliseconds 100

            # Encrypt again with -Force
            $result = Protect-PathWithPassword -Path $script:TestFile1 -Password $script:TestPassword -Force

            $result.Success | Should -Be $true
            $newTime = (Get-Item ($script:TestFile1 + '.enc')).LastWriteTime
            $newTime | Should -BeGreaterThan $initialTime
        }
    }

    Context 'Security Features' {
        It 'Should generate different encrypted files for same input' {
            # Encrypt the same file twice
            $result1 = Protect-PathWithPassword -Path $script:TestFile1 -Password $script:TestPassword -OutputPath (Join-Path -Path $script:TestDir -ChildPath 'enc1.dat') -Force
            $result2 = Protect-PathWithPassword -Path $script:TestFile1 -Password $script:TestPassword -OutputPath (Join-Path -Path $script:TestDir -ChildPath 'enc2.dat') -Force

            $both = $result1, $result2
            $both | ForEach-Object { $_.Success | Should -Be $true }

            # Files should be different due to random salt and IV
            $bytes1 = [System.IO.File]::ReadAllBytes($result1.EncryptedPath)
            $bytes2 = [System.IO.File]::ReadAllBytes($result2.EncryptedPath)

            # Compare first 48 bytes (salt + IV) - they should be different
            $bytes1[0..47] | Should -Not -Be $bytes2[0..47]
        }

        It 'Should create files with appropriate size (larger than original due to encryption overhead)' {
            Protect-PathWithPassword -Path $script:TestFile1 -Password $script:TestPassword -Force | Out-Null

            $originalSize = (Get-Item $script:TestFile1).Length
            $encryptedSize = (Get-Item ($script:TestFile1 + '.enc')).Length

            # Encrypted file should be larger (salt + IV + padding)
            $encryptedSize | Should -BeGreaterThan $originalSize
            # Should have at least 48 bytes overhead (32 salt + 16 IV)
            $encryptedSize | Should -BeGreaterThan ($originalSize + 48)
        }
    }
}
