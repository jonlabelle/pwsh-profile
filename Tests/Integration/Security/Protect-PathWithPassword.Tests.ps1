#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Protect-PathWithPassword and Unprotect-PathWithPassword functions.

.DESCRIPTION
    Comprehensive integration tests that verify the complete encryption/decryption workflow
    with real files, large data sets, different file types, and various security scenarios.

.NOTES
    These integration tests validate real-world usage scenarios including:
    - Binary file handling
    - Large file processing
    - Different text encodings
    - Security robustness
    - Batch processing workflows
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the functions
    . "$PSScriptRoot/../../../Functions/Security/Protect-PathWithPassword.ps1"
    . "$PSScriptRoot/../../../Functions/Security/Unprotect-PathWithPassword.ps1"

    # Import test utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Protect-PathWithPassword and Unprotect-PathWithPassword Integration Tests' {
    BeforeEach {
        # Create test directory structure
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PathProtectionIntegration_' + [System.Guid]::NewGuid().ToString('N')[0..7] -join '')
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        # Create test password - suppress lint warning as this is needed for testing
        $script:TestPassword = ConvertTo-SecureString 'Integration_Test_Password_2025!' -AsPlainText -Force # PSScriptAnalyzer ignore
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

    Context 'Real-world File Scenarios' {
        It 'Should handle binary files correctly (validates encryption of non-text data like images, executables, etc.)' {
            # Create a binary test file (simulate an image or other binary content)
            # This test ensures the encryption/decryption process preserves binary data integrity
            $binaryFile = Join-Path -Path $script:TestDir -ChildPath 'test.bin'
            $binaryData = [byte[]](0..255)
            [System.IO.File]::WriteAllBytes($binaryFile, $binaryData)

            # Encrypt and decrypt
            $encResult = Protect-PathWithPassword -Path $binaryFile -Password $script:TestPassword
            Remove-Item $binaryFile -Force
            $decResult = Unprotect-PathWithPassword -Path $encResult.EncryptedPath -Password $script:TestPassword

            # Verify binary data integrity
            $restoredData = [System.IO.File]::ReadAllBytes($decResult.DecryptedPath)
            $restoredData | Should -Be $binaryData
        }

        It 'Should handle large files efficiently' {
            # Create a large text file (1MB)
            $largeFile = Join-Path -Path $script:TestDir -ChildPath 'large.txt'
            $largeContent = [String]::new('A', 1024) * 1024  # 1MB of 'A's
            [System.IO.File]::WriteAllText($largeFile, $largeContent)

            # Measure encryption time
            $encStartTime = Get-Date
            $encResult = Protect-PathWithPassword -Path $largeFile -Password $script:TestPassword
            $encEndTime = Get-Date
            $encTime = ($encEndTime - $encStartTime).TotalSeconds

            # Verify encryption succeeded
            $encResult.Success | Should -Be $true
            Test-Path $encResult.EncryptedPath | Should -Be $true

            # Measure decryption time
            Remove-Item $largeFile -Force
            $decStartTime = Get-Date
            $decResult = Unprotect-PathWithPassword -Path $encResult.EncryptedPath -Password $script:TestPassword
            $decEndTime = Get-Date
            $decTime = ($decEndTime - $decStartTime).TotalSeconds

            # Verify decryption succeeded
            $decResult.Success | Should -Be $true
            $restoredContent = [System.IO.File]::ReadAllText($decResult.DecryptedPath)
            $restoredContent | Should -Be $largeContent

            # Performance check (should complete within reasonable time)
            $encTime | Should -BeLessThan 30
            $decTime | Should -BeLessThan 30
        }

        It 'Should handle different text encodings' {
            $encodings = @(
                @{ Name = 'UTF8'; Encoding = [System.Text.UTF8Encoding]::new($false) }  # UTF8 without BOM
                @{ Name = 'ASCII'; Encoding = [System.Text.Encoding]::ASCII }
                @{ Name = 'Unicode'; Encoding = [System.Text.Encoding]::Unicode }
            )

            foreach ($enc in $encodings)
            {
                $testFile = Join-Path -Path $script:TestDir -ChildPath "encoding_$($enc.Name).txt"
                $testContent = "Test content for $($enc.Name) encoding"

                # Write file with specific encoding using WriteAllBytes to avoid BOM issues
                $contentBytes = $enc.Encoding.GetBytes($testContent)
                [System.IO.File]::WriteAllBytes($testFile, $contentBytes)

                # Encrypt and decrypt
                $encResult = Protect-PathWithPassword -Path $testFile -Password $script:TestPassword
                Remove-Item $testFile -Force
                $decResult = Unprotect-PathWithPassword -Path $encResult.EncryptedPath -Password $script:TestPassword

                # Verify content (comparing with the same bytes we wrote)
                $restoredBytes = [System.IO.File]::ReadAllBytes($decResult.DecryptedPath)
                $restoredBytes | Should -Be $contentBytes
            }
        }
    }

    Context 'Security and Robustness' {
        It 'Should produce different encrypted output for same input with same password' {
            $testFile = Join-Path -Path $script:TestDir -ChildPath 'security_test.txt'
            'Identical content for security testing' | Out-File -FilePath $testFile -Encoding UTF8

            # Encrypt the same file twice
            $enc1 = Protect-PathWithPassword -Path $testFile -Password $script:TestPassword -OutputPath (Join-Path -Path $script:TestDir -ChildPath 'enc1.dat')
            $enc2 = Protect-PathWithPassword -Path $testFile -Password $script:TestPassword -OutputPath (Join-Path -Path $script:TestDir -ChildPath 'enc2.dat')

            # Read encrypted files as bytes
            $encBytes1 = [System.IO.File]::ReadAllBytes($enc1.EncryptedPath)
            $encBytes2 = [System.IO.File]::ReadAllBytes($enc2.EncryptedPath)

            # Files should be different (due to random salt and IV)
            $encBytes1 | Should -Not -Be $encBytes2

            # But both should decrypt to the same content
            Remove-Item $testFile -Force
            $dec1 = Unprotect-PathWithPassword -Path $enc1.EncryptedPath -Password $script:TestPassword -OutputPath (Join-Path -Path $script:TestDir -ChildPath 'dec1.txt')
            $dec2 = Unprotect-PathWithPassword -Path $enc2.EncryptedPath -Password $script:TestPassword -OutputPath (Join-Path -Path $script:TestDir -ChildPath 'dec2.txt')

            $content1 = Get-Content $dec1.DecryptedPath -Raw
            $content2 = Get-Content $dec2.DecryptedPath -Raw
            $content1 | Should -Be $content2
        }

        It 'Should fail gracefully with incorrect password' {
            $testFile = Join-Path -Path $script:TestDir -ChildPath 'password_test.txt'
            'Secret content that should not be accessible' | Out-File -FilePath $testFile -Encoding UTF8

            $correctPassword = $script:TestPassword
            $wrongPassword = ConvertTo-SecureString 'Wrong_Password_123!' -AsPlainText -Force

            # Encrypt with correct password
            $encResult = Protect-PathWithPassword -Path $testFile -Password $correctPassword
            Remove-Item $testFile -Force

            # Try to decrypt with wrong password
            $decResult = Unprotect-PathWithPassword -Path $encResult.EncryptedPath -Password $wrongPassword -ErrorAction SilentlyContinue

            # Should fail
            $decResult.Success | Should -Be $false
            $decResult.Error | Should -Match 'Decryption failed|Invalid password'

            # Original file should not be restored
            Test-Path $testFile | Should -Be $false
        }
    }

    Context 'Workflow Integration' {
        It 'Should work with pipeline operations for batch processing' {
            # Create multiple test files
            $testFiles = @()
            for ($i = 1; $i -le 5; $i++)
            {
                $testFile = Join-Path -Path $script:TestDir -ChildPath "batch_test_$i.txt"
                "Batch content for file $i" | Out-File -FilePath $testFile -Encoding UTF8
                $testFiles += $testFile
            }

            # Encrypt all files via pipeline
            $encResults = Get-ChildItem -Path $script:TestDir -File | Protect-PathWithPassword -Password $script:TestPassword

            # All encryptions should succeed
            $encResults | Should -HaveCount 5
            $encResults | ForEach-Object { $_.Success | Should -Be $true }

            # Remove original files
            $testFiles | ForEach-Object { Remove-Item $_ -Force }

            # Decrypt all files via pipeline
            $decResults = Get-ChildItem -Path $script:TestDir -File -Filter '*.enc' | Unprotect-PathWithPassword -Password $script:TestPassword

            # All decryptions should succeed
            $decResults | Should -HaveCount 5
            $decResults | ForEach-Object { $_.Success | Should -Be $true }

            # Verify all files are restored with correct content
            for ($i = 1; $i -le 5; $i++)
            {
                $restoredFile = Join-Path -Path $script:TestDir -ChildPath "batch_test_$i.txt"
                Test-Path $restoredFile | Should -Be $true
                $content = Get-Content $restoredFile -Raw
                $content.Trim() | Should -Be "Batch content for file $i"
            }
        }

        It 'Should handle recursive directory operations' {
            # Create nested directory structure
            $subDir1 = Join-Path -Path $script:TestDir -ChildPath 'subdir1'
            $subDir2 = Join-Path -Path $subDir1 -ChildPath 'subdir2'
            New-Item -Path $subDir1 -ItemType Directory -Force | Out-Null
            New-Item -Path $subDir2 -ItemType Directory -Force | Out-Null

            # Create files at different levels
            $files = @(
                @{ Path = (Join-Path -Path $script:TestDir -ChildPath 'root.txt'); Content = 'Root level content' }
                @{ Path = (Join-Path -Path $subDir1 -ChildPath 'level1.txt'); Content = 'Level 1 content' }
                @{ Path = (Join-Path -Path $subDir2 -ChildPath 'level2.txt'); Content = 'Level 2 content' }
            )

            foreach ($file in $files)
            {
                $file.Content | Out-File -FilePath $file.Path -Encoding UTF8
            }

            # Encrypt recursively
            Protect-PathWithPassword -Path $script:TestDir -Password $script:TestPassword -Recurse | Out-Null

            # Remove original files
            $files | ForEach-Object { Remove-Item $_.Path -Force }

            # Decrypt recursively
            Unprotect-PathWithPassword -Path $script:TestDir -Password $script:TestPassword -Recurse | Out-Null

            # Verify all files are restored
            foreach ($file in $files)
            {
                Test-Path $file.Path | Should -Be $true
                $content = Get-Content $file.Path -Raw
                $content.Trim() | Should -Be $file.Content
            }
        }
    }

    Context 'Cross-Platform Compatibility' {
        It 'Should create consistent file format across all platforms' {
            $testFile = Join-Path -Path $script:TestDir -ChildPath 'cross_platform.txt'
            'Cross-platform test content' | Out-File -FilePath $testFile -Encoding UTF8 -NoNewline

            # Encrypt the file
            $encResult = Protect-PathWithPassword -Path $testFile -Password $script:TestPassword

            # Read the encrypted file structure
            $encryptedBytes = [System.IO.File]::ReadAllBytes($encResult.EncryptedPath)

            # Verify expected structure: 32-byte salt + 16-byte IV + encrypted data
            $encryptedBytes.Length | Should -BeGreaterThan 48  # Minimum size

            # Extract components
            $salt = $encryptedBytes[0..31]
            $iv = $encryptedBytes[32..47]

            # Verify salt and IV are not all zeros (proper randomness)
            $salt | Should -Not -Be (@(0) * 32)
            $iv | Should -Not -Be (@(0) * 16)

            # Verify we can decrypt it
            Remove-Item $testFile -Force
            $decResult = Unprotect-PathWithPassword -Path $encResult.EncryptedPath -Password $script:TestPassword

            $decResult.Success | Should -Be $true
            $content = Get-Content $decResult.DecryptedPath -Raw
            $content | Should -Be 'Cross-platform test content'
        }

        It 'Should handle files encrypted on different PowerShell versions' {
            # This test simulates the file format that should work across PS 5.1 and PS 7+
            $testFile = Join-Path -Path $script:TestDir -ChildPath 'version_test.txt'
            'PowerShell version compatibility test' | Out-File -FilePath $testFile -Encoding UTF8 -NoNewline

            # Encrypt and get the file structure
            $encResult = Protect-PathWithPassword -Path $testFile -Password $script:TestPassword

            # Verify the file can be read and parsed correctly
            $encryptedBytes = [System.IO.File]::ReadAllBytes($encResult.EncryptedPath)

            # Manually verify structure (same as what Unprotect expects)
            $encryptedBytes.Length | Should -BeGreaterOrEqual 64

            # Decrypt should work
            Remove-Item $testFile -Force
            $decResult = Unprotect-PathWithPassword -Path $encResult.EncryptedPath -Password $script:TestPassword

            $decResult.Success | Should -Be $true
        }
    }

    Context 'OpenSSL Interoperability' {
        BeforeAll {
            # Skip on Windows PowerShell Desktop 5.1 due to external command output handling issues
            if ($PSVersionTable.PSVersion.Major -eq 5)
            {
                $script:BashScriptAvailable = $false
                $script:SkipReason = 'Skipped on PowerShell Desktop 5.1 (external command compatibility issues)'
            }
            else
            {
                # Check if the bash script and OpenSSL with KDF support are available
                $BashScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'scripts/pwsh-encrypt-compat.sh'
                $script:BashScriptAvailable = (Test-Path $BashScriptPath) -and
                ($null -ne (Get-Command bash -ErrorAction SilentlyContinue)) -and
                ($null -ne (Get-Command openssl -ErrorAction SilentlyContinue))

                if ($script:BashScriptAvailable)
                {
                    # Test if OpenSSL has KDF support (OpenSSL 3.0+)
                    try
                    {
                        $kdfTest = bash -c 'openssl kdf -help 2>&1'
                        $hasKdf = ($LASTEXITCODE -eq 0) -and ($kdfTest -match 'kdf|KDF')
                        if (-not $hasKdf)
                        {
                            $script:BashScriptAvailable = $false
                            $script:SkipReason = 'OpenSSL 3.0+ with KDF support required'
                        }
                    }
                    catch
                    {
                        $script:BashScriptAvailable = $false
                        $script:SkipReason = 'Failed to test OpenSSL KDF support'
                    }
                }
                else
                {
                    $script:SkipReason = 'Bash script or OpenSSL not available'
                }
            }
        }

        It 'Should decrypt files encrypted by the OpenSSL bash script' {
            if (-not $script:BashScriptAvailable)
            {
                Set-ItResult -Skipped -Because $script:SkipReason
                return
            }

            $testFile = Join-Path -Path $script:TestDir -ChildPath 'bash_encrypted.txt'
            $originalContent = 'Encrypted by bash, decrypted by PowerShell'
            $originalContent | Out-File -FilePath $testFile -Encoding UTF8 -NoNewline

            $encryptedFile = $testFile + '.enc'
            $testPassword = 'BashTest_Password_2025!'
            $BashScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'scripts/pwsh-encrypt-compat.sh'

            # Encrypt with bash script
            $bashOutput = & bash $BashScriptPath encrypt -i $testFile -o $encryptedFile -p $testPassword 2>&1 | Out-String
            Write-Verbose "Bash encrypt output: $bashOutput"

            # Verify bash created the file
            Test-Path $encryptedFile | Should -Be $true

            # Remove original
            Remove-Item $testFile -Force

            # Decrypt with PowerShell
            $pwPassword = ConvertTo-SecureString $testPassword -AsPlainText -Force
            $decResult = Unprotect-PathWithPassword -Path $encryptedFile -Password $pwPassword

            # Verify decryption
            $decResult.Success | Should -Be $true
            $content = Get-Content $decResult.DecryptedPath -Raw
            $content | Should -Be $originalContent
        }

        It 'Should encrypt files that the OpenSSL bash script can decrypt' {
            if (-not $script:BashScriptAvailable)
            {
                Set-ItResult -Skipped -Because $script:SkipReason
                return
            }

            # Create test file with PowerShell
            $TestFile = Join-Path -Path $script:TestDir -ChildPath 'test_roundtrip.txt'
            Set-Content -Path $TestFile -Value 'Testing PowerShell -> bash decryption'

            $BashScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'scripts/pwsh-encrypt-compat.sh'
            $testFile = Join-Path -Path $script:TestDir -ChildPath 'pwsh_encrypted.txt'
            $originalContent = 'Encrypted by PowerShell, decrypted by bash'
            $originalContent | Out-File -FilePath $testFile -Encoding UTF8 -NoNewline

            $testPassword = 'PwshTest_Password_2025!'
            $BashScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'scripts/pwsh-encrypt-compat.sh'

            # Encrypt with PowerShell
            $pwPassword = ConvertTo-SecureString $testPassword -AsPlainText -Force
            $encResult = Protect-PathWithPassword -Path $testFile -Password $pwPassword

            # Verify encryption
            $encResult.Success | Should -Be $true
            Test-Path $encResult.EncryptedPath | Should -Be $true

            # Remove original
            Remove-Item $testFile -Force

            # Decrypt with bash script
            $decryptedFile = $testFile
            $bashOutput = & bash $BashScriptPath decrypt -i $encResult.EncryptedPath -o $decryptedFile -p $testPassword 2>&1 | Out-String
            Write-Verbose "Bash decrypt output: $bashOutput"

            # Verify bash decrypted successfully
            Test-Path $decryptedFile | Should -Be $true
            $content = Get-Content $decryptedFile -Raw
            $content | Should -Be $originalContent

            # Cleanup
            Remove-Item $decryptedFile -Force -ErrorAction SilentlyContinue
        }

        It 'Should handle binary files with OpenSSL bash script' {
            if (-not $script:BashScriptAvailable)
            {
                Set-ItResult -Skipped -Because $script:SkipReason
                return
            }

            $testFile = Join-Path -Path $script:TestDir -ChildPath 'binary_test.bin'
            $binaryData = [byte[]](0..255)
            [System.IO.File]::WriteAllBytes($testFile, $binaryData)

            $encryptedFile = $testFile + '.enc'
            $testPassword = 'Binary_Password_2025!'
            $BashScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'scripts/pwsh-encrypt-compat.sh'

            # Encrypt with bash
            $bashOutput = & bash $BashScriptPath encrypt -i $testFile -o $encryptedFile -p $testPassword 2>&1 | Out-String
            Write-Verbose "Bash encrypt output: $bashOutput"

            Remove-Item $testFile -Force

            # Decrypt with PowerShell
            $pwPassword = ConvertTo-SecureString $testPassword -AsPlainText -Force
            $decResult = Unprotect-PathWithPassword -Path $encryptedFile -Password $pwPassword

            # Verify binary integrity
            $restoredData = [System.IO.File]::ReadAllBytes($decResult.DecryptedPath)
            $restoredData | Should -Be $binaryData
        }

        It 'Should provide information about OpenSSL script availability' {
            if ($script:BashScriptAvailable)
            {
                Write-Host 'OpenSSL bash script available and functional' -ForegroundColor Green
                $opensslVersion = bash -c 'openssl version' 2>&1
                Write-Host "OpenSSL version: $opensslVersion" -ForegroundColor Cyan
                $true | Should -Be $true
            }
            else
            {
                $reason = if ($script:SkipReason) { $script:SkipReason } else { 'Unknown reason' }
                Write-Host "OpenSSL interoperability tests skipped: $reason" -ForegroundColor Yellow
                Write-Host 'For full compatibility testing, install OpenSSL 3.0+ with KDF support' -ForegroundColor Yellow
                $true | Should -Be $true
            }
        }
    }
}
