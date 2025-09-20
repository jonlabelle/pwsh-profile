BeforeAll {
    # Import the functions to test
    . "$PSScriptRoot/../../Functions/Protect-Path.ps1"
    . "$PSScriptRoot/../../Functions/Unprotect-Path.ps1"
}

Describe 'Protect-Path Unit Tests' {
    BeforeEach {
        # Create test directory structure
        $script:TestDir = Join-Path ([System.IO.Path]::GetTempPath()) ('ProtectPathTest_' + [System.Guid]::NewGuid().ToString('N')[0..7] -join '')
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        # Create test password
        $script:TestPassword = ConvertTo-SecureString 'TestPassword123!' -AsPlainText -Force

        # Create test files
        $script:TestFile1 = Join-Path $script:TestDir 'test1.txt'
        $script:TestFile2 = Join-Path $script:TestDir 'test2.txt'
        $script:SubDir = Join-Path $script:TestDir 'subdir'
        $script:TestFile3 = Join-Path $script:SubDir 'test3.txt'

        'Test content 1' | Out-File -FilePath $script:TestFile1 -Encoding UTF8
        'Test content 2' | Out-File -FilePath $script:TestFile2 -Encoding UTF8
        New-Item -Path $script:SubDir -ItemType Directory -Force | Out-Null
        'Test content 3' | Out-File -FilePath $script:TestFile3 -Encoding UTF8
    }

    AfterEach {
        # Clean up test directory
        if (Test-Path $script:TestDir)
        {
            Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Parameter Validation' {
        It 'Should require Path parameter' {
            { Protect-Path -Password $script:TestPassword -ErrorAction Stop } | Should -Throw
        }

        It 'Should accept path from pipeline' {
            $result = Get-Item $script:TestFile1 | Protect-Path -Password $script:TestPassword
            $result.Success | Should -Be $true
        }

        It 'Should throw when path does not exist' {
            { Protect-Path -Path 'C:\NonExistent\file.txt' -Password $script:TestPassword } | Should -Throw '*does not exist*'
        }
    }

    Context 'Single File Encryption' {
        It 'Should encrypt a single file successfully' {
            $result = Protect-Path -Path $script:TestFile1 -Password $script:TestPassword

            $result.Success | Should -Be $true
            $result.OriginalPath | Should -Be $script:TestFile1
            $result.EncryptedPath | Should -Be ($script:TestFile1 + '.enc')
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
        }

        It 'Should create encrypted file with .enc extension by default' {
            Protect-Path -Path $script:TestFile1 -Password $script:TestPassword | Out-Null
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
        }

        It 'Should respect custom output path' {
            $customOutput = Join-Path $script:TestDir 'custom.encrypted'
            $result = Protect-Path -Path $script:TestFile1 -Password $script:TestPassword -OutputPath $customOutput

            $result.EncryptedPath | Should -Be $customOutput
            Test-Path $customOutput | Should -Be $true
        }

        It 'Should support RemoveOriginal parameter' {
            $result = Protect-Path -Path $script:TestFile1 -Password $script:TestPassword -RemoveOriginal

            $result.Success | Should -Be $true
            Test-Path $script:TestFile1 | Should -Be $false
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
        }
    }

    Context 'Directory Encryption' {
        It 'Should encrypt files in directory without recursion' {
            Protect-Path -Path $script:TestDir -Password $script:TestPassword | Out-Null

            # Should encrypt files in root directory only
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
            Test-Path ($script:TestFile2 + '.enc') | Should -Be $true
            Test-Path ($script:TestFile3 + '.enc') | Should -Be $false
        }

        It 'Should encrypt files recursively when -Recurse is specified' {
            Protect-Path -Path $script:TestDir -Password $script:TestPassword -Recurse | Out-Null

            # Should encrypt all files including subdirectories
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
            Test-Path ($script:TestFile2 + '.enc') | Should -Be $true
            Test-Path ($script:TestFile3 + '.enc') | Should -Be $true
        }
    }

    Context 'Pipeline Support' {
        It 'Should accept input from pipeline' {
            $results = Get-ChildItem -Path $script:TestDir -File | Protect-Path -Password $script:TestPassword

            $results | Should -HaveCount 2
            $results | ForEach-Object { $_.Success | Should -Be $true }
            Test-Path ($script:TestFile1 + '.enc') | Should -Be $true
            Test-Path ($script:TestFile2 + '.enc') | Should -Be $true
        }
    }

    Context 'File Overwrite Behavior' {
        It 'Should overwrite when -Force is specified' {
            # Create initial encrypted file
            Protect-Path -Path $script:TestFile1 -Password $script:TestPassword | Out-Null
            $initialTime = (Get-Item ($script:TestFile1 + '.enc')).LastWriteTime

            Start-Sleep -Milliseconds 100

            # Encrypt again with -Force
            $result = Protect-Path -Path $script:TestFile1 -Password $script:TestPassword -Force

            $result.Success | Should -Be $true
            $newTime = (Get-Item ($script:TestFile1 + '.enc')).LastWriteTime
            $newTime | Should -BeGreaterThan $initialTime
        }
    }

    Context 'Security Features' {
        It 'Should generate different encrypted files for same input' {
            # Encrypt the same file twice
            $result1 = Protect-Path -Path $script:TestFile1 -Password $script:TestPassword -OutputPath (Join-Path $script:TestDir 'enc1.dat')
            $result2 = Protect-Path -Path $script:TestFile1 -Password $script:TestPassword -OutputPath (Join-Path $script:TestDir 'enc2.dat')

            $both = $result1, $result2
            $both | ForEach-Object { $_.Success | Should -Be $true }

            # Files should be different due to random salt and IV
            $bytes1 = [System.IO.File]::ReadAllBytes($result1.EncryptedPath)
            $bytes2 = [System.IO.File]::ReadAllBytes($result2.EncryptedPath)

            # Compare first 48 bytes (salt + IV) - they should be different
            $bytes1[0..47] | Should -Not -Be $bytes2[0..47]
        }

        It 'Should create files with appropriate size (larger than original due to encryption overhead)' {
            Protect-Path -Path $script:TestFile1 -Password $script:TestPassword | Out-Null

            $originalSize = (Get-Item $script:TestFile1).Length
            $encryptedSize = (Get-Item ($script:TestFile1 + '.enc')).Length

            # Encrypted file should be larger (salt + IV + padding)
            $encryptedSize | Should -BeGreaterThan $originalSize
            # Should have at least 48 bytes overhead (32 salt + 16 IV)
            $encryptedSize | Should -BeGreaterThan ($originalSize + 48)
        }
    }
}
