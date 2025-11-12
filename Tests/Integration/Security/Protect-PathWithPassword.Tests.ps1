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
    # Load the functions
    . "$PSScriptRoot/../../../Functions/Security/Protect-PathWithPassword.ps1"
    . "$PSScriptRoot/../../../Functions/Security/Unprotect-PathWithPassword.ps1"

    # Import test utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Protect-PathWithPassword and Unprotect-PathWithPassword Integration Tests' {
    BeforeEach {
        # Create test directory structure
        $script:TestDir = Join-Path ([System.IO.Path]::GetTempPath()) ('PathProtectionIntegration_' + [System.Guid]::NewGuid().ToString('N')[0..7] -join '')
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
            $binaryFile = Join-Path $script:TestDir 'test.bin'
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
            $largeFile = Join-Path $script:TestDir 'large.txt'
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
                $testFile = Join-Path $script:TestDir "encoding_$($enc.Name).txt"
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
            $testFile = Join-Path $script:TestDir 'security_test.txt'
            'Identical content for security testing' | Out-File -FilePath $testFile -Encoding UTF8

            # Encrypt the same file twice
            $enc1 = Protect-PathWithPassword -Path $testFile -Password $script:TestPassword -OutputPath (Join-Path $script:TestDir 'enc1.dat')
            $enc2 = Protect-PathWithPassword -Path $testFile -Password $script:TestPassword -OutputPath (Join-Path $script:TestDir 'enc2.dat')

            # Read encrypted files as bytes
            $encBytes1 = [System.IO.File]::ReadAllBytes($enc1.EncryptedPath)
            $encBytes2 = [System.IO.File]::ReadAllBytes($enc2.EncryptedPath)

            # Files should be different (due to random salt and IV)
            $encBytes1 | Should -Not -Be $encBytes2

            # But both should decrypt to the same content
            Remove-Item $testFile -Force
            $dec1 = Unprotect-PathWithPassword -Path $enc1.EncryptedPath -Password $script:TestPassword -OutputPath (Join-Path $script:TestDir 'dec1.txt')
            $dec2 = Unprotect-PathWithPassword -Path $enc2.EncryptedPath -Password $script:TestPassword -OutputPath (Join-Path $script:TestDir 'dec2.txt')

            $content1 = Get-Content $dec1.DecryptedPath -Raw
            $content2 = Get-Content $dec2.DecryptedPath -Raw
            $content1 | Should -Be $content2
        }

        It 'Should fail gracefully with incorrect password' {
            $testFile = Join-Path $script:TestDir 'password_test.txt'
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
                $testFile = Join-Path $script:TestDir "batch_test_$i.txt"
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
                $restoredFile = Join-Path $script:TestDir "batch_test_$i.txt"
                Test-Path $restoredFile | Should -Be $true
                $content = Get-Content $restoredFile -Raw
                $content.Trim() | Should -Be "Batch content for file $i"
            }
        }

        It 'Should handle recursive directory operations' {
            # Create nested directory structure
            $subDir1 = Join-Path $script:TestDir 'subdir1'
            $subDir2 = Join-Path $subDir1 'subdir2'
            New-Item -Path $subDir1 -ItemType Directory -Force | Out-Null
            New-Item -Path $subDir2 -ItemType Directory -Force | Out-Null

            # Create files at different levels
            $files = @(
                @{ Path = (Join-Path $script:TestDir 'root.txt'); Content = 'Root level content' }
                @{ Path = (Join-Path $subDir1 'level1.txt'); Content = 'Level 1 content' }
                @{ Path = (Join-Path $subDir2 'level2.txt'); Content = 'Level 2 content' }
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
}
