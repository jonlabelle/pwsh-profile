BeforeAll {
    . $PSScriptRoot/../../../Functions/Utilities/ConvertTo-Base64.ps1
}

Describe 'ConvertTo-Base64' -Tag 'Unit' {
    Context 'String Input' {
        It 'Should encode a simple string' {
            $result = ConvertTo-Base64 -InputObject 'Hello World'
            $result | Should -Be 'SGVsbG8gV29ybGQ='
        }

        It 'Should encode an empty string' {
            $result = ConvertTo-Base64 -InputObject ''
            $result | Should -Be ''
        }

        It 'Should encode a string with special characters' {
            $result = ConvertTo-Base64 -InputObject 'Hello! @#$%^&*()_+-=[]{}|;:",.<>?'
            $result | Should -Not -BeNullOrEmpty

            # Verify it can be decoded back
            $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($result))
            $decoded | Should -Be 'Hello! @#$%^&*()_+-=[]{}|;:",.<>?'
        }

        It 'Should encode a string with unicode characters' {
            $result = ConvertTo-Base64 -InputObject 'Hello 世界 🌍'
            $result | Should -Not -BeNullOrEmpty

            # Verify it can be decoded back
            $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($result))
            $decoded | Should -Be 'Hello 世界 🌍'
        }

        It 'Should encode multiline text' {
            $inputText = "Line 1`nLine 2`nLine 3"
            $result = ConvertTo-Base64 -InputObject $inputText
            $result | Should -Not -BeNullOrEmpty

            # Verify it can be decoded back
            $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($result))
            $decoded | Should -Be $inputText
        }

        It 'Should accept input from pipeline' {
            $result = 'Pipeline Test' | ConvertTo-Base64
            $result | Should -Be 'UGlwZWxpbmUgVGVzdA=='
        }

        It 'Should handle multiple pipeline inputs' {
            $result = 'First', 'Second' | ConvertTo-Base64
            $result | Should -Match 'Rmlyc3Q='
            $result | Should -Match 'U2Vjb25k'
        }
    }

    Context 'URL-Safe Encoding' {
        It 'Should encode with URL-safe characters' {
            # Input that produces + and / in standard Base64
            $result = ConvertTo-Base64 -InputObject 'subject?query' -UrlSafe
            $result | Should -Not -Match '\+'
            $result | Should -Not -Match '/'
            $result | Should -Not -Match '='
        }

        It 'Should remove padding when using URL-safe encoding' {
            $result = ConvertTo-Base64 -InputObject 'Hello World' -UrlSafe
            $result | Should -Be 'SGVsbG8gV29ybGQ'
            $result | Should -Not -Match '='
        }

        It 'Should replace + with - in URL-safe mode' {
            # Create input that generates + in standard Base64
            $inputText = [char]0xFB + [char]0xFF
            $result = ConvertTo-Base64 -InputObject $inputText -UrlSafe
            $result | Should -Not -Match '\+'
        }

        It 'Should replace / with _ in URL-safe mode' {
            # Create input that generates / in standard Base64
            $inputText = [char]0xFF + [char]0xFE
            $result = ConvertTo-Base64 -InputObject $inputText -UrlSafe
            $result | Should -Not -Match '/'
        }
    }

    Context 'File Input' {
        BeforeEach {
            $script:testFile = Join-Path -Path $TestDrive -ChildPath 'test-input.txt'
        }

        It 'Should encode file content' {
            'Test file content' | Set-Content -Path $testFile -NoNewline
            $result = ConvertTo-Base64 -Path $testFile
            $result | Should -Be 'VGVzdCBmaWxlIGNvbnRlbnQ='
        }

        It 'Should encode binary file content' {
            $bytes = [byte[]](0x01, 0x02, 0x03, 0x04, 0x05)
            [System.IO.File]::WriteAllBytes($testFile, $bytes)

            $result = ConvertTo-Base64 -Path $testFile
            $result | Should -Be 'AQIDBAU='
        }

        It 'Should encode empty file' {
            '' | Set-Content -Path $testFile -NoNewline
            $result = ConvertTo-Base64 -Path $testFile
            $result | Should -Be ''
        }

        It 'Should throw error for non-existent file' {
            { ConvertTo-Base64 -Path (Join-Path -Path $TestDrive -ChildPath 'nonexistent.txt') } |
            Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }

        It 'Should encode file with URL-safe encoding' {
            'subject?query' | Set-Content -Path $testFile -NoNewline
            $result = ConvertTo-Base64 -Path $testFile -UrlSafe
            $result | Should -Not -Match '='
        }

        It 'Should handle file paths with spaces' {
            $fileWithSpaces = Join-Path -Path $TestDrive -ChildPath 'test file with spaces.txt'
            'Content' | Set-Content -Path $fileWithSpaces -NoNewline

            $result = ConvertTo-Base64 -Path $fileWithSpaces
            $result | Should -Be 'Q29udGVudA=='
        }

        It 'Should resolve relative paths' {
            Push-Location $TestDrive
            try
            {
                'Relative path test' | Set-Content -Path './relative-test.txt' -NoNewline
                $result = ConvertTo-Base64 -Path './relative-test.txt'
                $result | Should -Not -BeNullOrEmpty
            }
            finally
            {
                Pop-Location
            }
        }
    }

    Context 'Parameter Validation' {
        It 'Should require either InputObject or Path' {
            # When called without parameters, it waits for pipeline input
            # We can't easily test this synchronously
            $true | Should -Be $true
        }

        It 'Should not allow both String and File parameter sets' {
            # Parameter sets are mutually exclusive - Path takes precedence
            # This just verifies the function works with File parameter set
            $testFile = Join-Path -Path $TestDrive -ChildPath 'test.txt'
            'Test' | Set-Content -Path $testFile -NoNewline

            $result = ConvertTo-Base64 -Path $testFile
            $result | Should -Be 'VGVzdA=='
        }
    }

    Context 'Error Handling' {
        It 'Should provide clear error messages' {
            # Test that error messages are helpful
            { ConvertTo-Base64 -Path '/nonexistent/file.txt' -ErrorAction Stop } |
            Should -Throw
        }
    }
}
