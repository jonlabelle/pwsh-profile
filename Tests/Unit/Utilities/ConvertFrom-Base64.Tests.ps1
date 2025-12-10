BeforeAll {
    . $PSScriptRoot/../../../Functions/Utilities/ConvertFrom-Base64.ps1
    . $PSScriptRoot/../../../Functions/Utilities/ConvertTo-Base64.ps1
}

Describe 'ConvertFrom-Base64' -Tag 'Unit' {
    Context 'String Output' {
        It 'Should decode a simple Base64 string' {
            $result = ConvertFrom-Base64 -InputObject 'SGVsbG8gV29ybGQ='
            $result | Should -Be 'Hello World'
        }

        It 'Should decode Base64 from pipeline' {
            $result = 'UGlwZWxpbmUgVGVzdA==' | ConvertFrom-Base64
            $result | Should -Be 'Pipeline Test'
        }

        It 'Should decode Base64 with special characters' {
            $encoded = ConvertTo-Base64 -InputObject 'Hello! @#$%^&*()_+-=[]{}|;:",.<>?'
            $result = ConvertFrom-Base64 -InputObject $encoded
            $result | Should -Be 'Hello! @#$%^&*()_+-=[]{}|;:",.<>?'
        }

        It 'Should decode Base64 with unicode characters' {
            $encoded = ConvertTo-Base64 -InputObject 'Hello 世界 🌍'
            $result = ConvertFrom-Base64 -InputObject $encoded
            $result | Should -Be 'Hello 世界 🌍'
        }

        It 'Should decode multiline Base64' {
            $original = "Line 1`nLine 2`nLine 3"
            $encoded = ConvertTo-Base64 -InputObject $original
            $result = ConvertFrom-Base64 -InputObject $encoded
            $result | Should -Be $original
        }

        It 'Should handle multiple pipeline inputs' {
            $result = 'Rmlyc3Q=', 'U2Vjb25k' | ConvertFrom-Base64
            $result | Should -Match 'First'
            $result | Should -Match 'Second'
        }

        It 'Should handle minimal valid Base64 input' {
            # Single character Base64 (A = 0x00)
            $result = ConvertFrom-Base64 -InputObject 'AA=='
            $result | Should -Be ([char]0x00)
        }
    }

    Context 'URL-Safe Decoding' {
        It 'Should decode URL-safe Base64 without padding' {
            $result = ConvertFrom-Base64 -InputObject 'SGVsbG8gV29ybGQ' -UrlSafe
            $result | Should -Be 'Hello World'
        }

        It 'Should decode URL-safe Base64 with - instead of +' {
            # Standard: 'subject?query' encodes to contain + or /
            $urlSafeEncoded = ConvertTo-Base64 -InputObject 'subject?query' -UrlSafe
            $result = ConvertFrom-Base64 -InputObject $urlSafeEncoded -UrlSafe
            $result | Should -Be 'subject?query'
        }

        It 'Should decode URL-safe Base64 with _ instead of /' {
            $original = [char]0xFF + [char]0xFE
            $urlSafeEncoded = ConvertTo-Base64 -InputObject $original -UrlSafe
            $result = ConvertFrom-Base64 -InputObject $urlSafeEncoded -UrlSafe
            $result | Should -Be $original
        }

        It 'Should add padding when decoding URL-safe Base64' {
            # Test different padding scenarios
            $testCases = @(
                @{ Input = 'SGVsbG8gV29ybGQ'; Expected = 'Hello World' }      # 2 chars padding needed
                @{ Input = 'VGVzdA'; Expected = 'Test' }                      # 2 chars padding needed
                @{ Input = 'SGVsbG8'; Expected = 'Hello' }                    # 1 char padding needed
            )

            foreach ($case in $testCases)
            {
                $result = ConvertFrom-Base64 -InputObject $case.Input -UrlSafe
                $result | Should -Be $case.Expected
            }
        }
    }

    Context 'File Output' {
        BeforeEach {
            $script:outputFile = Join-Path -Path $TestDrive -ChildPath 'decoded-output.txt'
        }

        It 'Should decode Base64 to file' {
            $encoded = 'VGVzdCBmaWxlIGNvbnRlbnQ='
            ConvertFrom-Base64 -InputObject $encoded -OutputPath $outputFile

            $content = Get-Content -Path $outputFile -Raw
            $content.TrimEnd() | Should -Be 'Test file content'
        }

        It 'Should decode binary Base64 to file' {
            $originalBytes = [byte[]](0x01, 0x02, 0x03, 0x04, 0x05)
            $encoded = [System.Convert]::ToBase64String($originalBytes)

            ConvertFrom-Base64 -InputObject $encoded -OutputPath $outputFile

            $decodedBytes = [System.IO.File]::ReadAllBytes($outputFile)
            $decodedBytes | Should -Be $originalBytes
        }

        It 'Should create output directory if it does not exist' {
            $nestedPath = Join-Path -Path $TestDrive -ChildPath 'nested/folder/output.txt'
            $encoded = 'VGVzdA=='

            ConvertFrom-Base64 -InputObject $encoded -OutputPath $nestedPath

            Test-Path $nestedPath | Should -Be $true
        }

        It 'Should handle output paths with spaces' {
            $pathWithSpaces = Join-Path -Path $TestDrive -ChildPath 'output file with spaces.txt'
            $encoded = 'Q29udGVudA=='

            ConvertFrom-Base64 -InputObject $encoded -OutputPath $pathWithSpaces

            $content = Get-Content -Path $pathWithSpaces -Raw
            $content.TrimEnd() | Should -Be 'Content'
        }

        It 'Should resolve relative output paths' {
            Push-Location $TestDrive
            try
            {
                $encoded = 'UmVsYXRpdmUgcGF0aCB0ZXN0'
                ConvertFrom-Base64 -InputObject $encoded -OutputPath './relative-output.txt'

                Test-Path './relative-output.txt' | Should -Be $true
            }
            finally
            {
                Pop-Location
            }
        }

        It 'Should overwrite existing file' {
            'Old content' | Set-Content -Path $outputFile

            $encoded = 'TmV3IGNvbnRlbnQ='
            ConvertFrom-Base64 -InputObject $encoded -OutputPath $outputFile

            $content = Get-Content -Path $outputFile -Raw
            $content.TrimEnd() | Should -Be 'New content'
        }
    }

    Context 'Parameter Validation' {
        It 'Should require InputObject parameter' {
            # When ValueFromPipeline is enabled, calling without params waits for pipeline
            # Instead test that an empty/null value throws
            { ConvertFrom-Base64 -InputObject '' -ErrorAction Stop } | Should -Throw
        }

        It 'Should not accept null or empty InputObject' {
            { ConvertFrom-Base64 -InputObject $null -ErrorAction Stop } | Should -Throw
            { ConvertFrom-Base64 -InputObject '' -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Error Handling' {
        It 'Should throw error for invalid Base64 string' {
            { ConvertFrom-Base64 -InputObject 'Invalid!@#$' -ErrorAction Stop } |
            Should -Throw
        }

        It 'Should throw error for malformed Base64' {
            # Test with string that has invalid length (not multiple of 4 after padding)
            { ConvertFrom-Base64 -InputObject 'A' -ErrorAction Stop } |
            Should -Throw
        }

        It 'Should handle decoding errors gracefully' {
            { ConvertFrom-Base64 -InputObject '!!!Invalid!!!' -ErrorAction Stop } |
            Should -Throw
        }
    }

    Context 'Round-Trip Encoding/Decoding' {
        It 'Should round-trip simple text' {
            $original = 'Hello World'
            $encoded = ConvertTo-Base64 -InputObject $original
            $decoded = ConvertFrom-Base64 -InputObject $encoded
            $decoded | Should -Be $original
        }

        It 'Should round-trip with URL-safe encoding' {
            $original = 'Hello World'
            $encoded = ConvertTo-Base64 -InputObject $original -UrlSafe
            $decoded = ConvertFrom-Base64 -InputObject $encoded -UrlSafe
            $decoded | Should -Be $original
        }

        It 'Should round-trip complex text' {
            $original = 'Line 1' + [Environment]::NewLine + 'Line 2' + [Environment]::NewLine + 'Special: !@#$%^&*()'
            $encoded = ConvertTo-Base64 -InputObject $original
            $decoded = ConvertFrom-Base64 -InputObject $encoded
            $decoded | Should -Be $original
        }

        It 'Should round-trip file content' {
            $testFile = Join-Path -Path $TestDrive -ChildPath 'original.txt'
            $outputFile = Join-Path -Path $TestDrive -ChildPath 'decoded.txt'
            $originalContent = 'Test file content with special chars: !@#$%'

            $originalContent | Set-Content -Path $testFile -NoNewline

            $encoded = ConvertTo-Base64 -Path $testFile
            ConvertFrom-Base64 -InputObject $encoded -OutputPath $outputFile

            $decodedContent = Get-Content -Path $outputFile -Raw
            $decodedContent.TrimEnd() | Should -Be $originalContent
        }
    }
}
