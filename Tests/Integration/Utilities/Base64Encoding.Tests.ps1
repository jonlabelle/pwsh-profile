BeforeAll {
    . $PSScriptRoot/../../../Functions/Utilities/ConvertTo-Base64.ps1
    . $PSScriptRoot/../../../Functions/Utilities/ConvertFrom-Base64.ps1
}

Describe 'Base64 Encoding Integration Tests' -Tag 'Integration' {
    BeforeEach {
        $script:testDir = Join-Path -Path $TestDrive -ChildPath "base64-integration-$(New-Guid)"
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $testDir)
        {
            Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Pipeline Integration' {
        It 'Should encode and decode through pipeline' {
            $original = 'Pipeline integration test'
            $result = $original | ConvertTo-Base64 | ConvertFrom-Base64
            $result | Should -Be $original
        }

        It 'Should handle multiple items through pipeline' {
            $items = @('First', 'Second', 'Third')
            $encoded = $items | ConvertTo-Base64
            $decoded = ($encoded -split "`n") | ConvertFrom-Base64

            $decoded -join ',' | Should -Match 'First'
            $decoded -join ',' | Should -Match 'Second'
            $decoded -join ',' | Should -Match 'Third'
        }

        It 'Should work with Get-Content pipeline' {
            $testFile = Join-Path -Path $testDir -ChildPath 'input.txt'
            'Line 1', 'Line 2', 'Line 3' | Set-Content -Path $testFile

            $encoded = Get-Content $testFile | ConvertTo-Base64
            $encoded | Should -Not -BeNullOrEmpty
        }
    }

    Context 'File Round-Trip' {
        It 'Should encode and decode text file' {
            $sourceFile = Join-Path -Path $testDir -ChildPath 'source.txt'
            $outputFile = Join-Path -Path $testDir -ChildPath 'output.txt'
            $content = 'Test content with special chars: !@#$%^&*()'

            $content | Set-Content -Path $sourceFile -NoNewline

            $encoded = ConvertTo-Base64 -Path $sourceFile
            ConvertFrom-Base64 -InputObject $encoded -OutputPath $outputFile

            $result = Get-Content -Path $outputFile -Raw
            $result.TrimEnd() | Should -Be $content
        }

        It 'Should encode and decode binary file' {
            $sourceFile = Join-Path -Path $testDir -ChildPath 'binary.dat'
            $outputFile = Join-Path -Path $testDir -ChildPath 'binary-output.dat'
            $bytes = [byte[]](0..255)

            [System.IO.File]::WriteAllBytes($sourceFile, $bytes)

            $encoded = ConvertTo-Base64 -Path $sourceFile
            ConvertFrom-Base64 -InputObject $encoded -OutputPath $outputFile

            $result = [System.IO.File]::ReadAllBytes($outputFile)
            $result | Should -Be $bytes
        }

        It 'Should handle large text file' {
            $sourceFile = Join-Path -Path $testDir -ChildPath 'large.txt'
            $outputFile = Join-Path -Path $testDir -ChildPath 'large-output.txt'

            # Create a large file (1000 lines)
            $lines = 1..1000 | ForEach-Object { "Line ${_}: Some test content here" }
            $lines | Set-Content -Path $sourceFile

            $encoded = ConvertTo-Base64 -Path $sourceFile
            ConvertFrom-Base64 -InputObject $encoded -OutputPath $outputFile

            $originalContent = Get-Content -Path $sourceFile -Raw
            $decodedContent = Get-Content -Path $outputFile -Raw
            $decodedContent | Should -Be $originalContent
        }

        It 'Should handle empty file' {
            $sourceFile = Join-Path -Path $testDir -ChildPath 'empty.txt'

            '' | Set-Content -Path $sourceFile -NoNewline

            $encoded = ConvertTo-Base64 -Path $sourceFile
            $encoded | Should -Be ''
        }
    }

    Context 'URL-Safe Round-Trip' {
        It 'Should round-trip with URL-safe encoding for text' {
            $original = 'Hello World!?&=subject+query/test'
            $encoded = ConvertTo-Base64 -InputObject $original -UrlSafe
            $decoded = ConvertFrom-Base64 -InputObject $encoded -UrlSafe
            $decoded | Should -Be $original
        }

        It 'Should round-trip with URL-safe encoding for files' {
            $sourceFile = Join-Path -Path $testDir -ChildPath 'url-safe.txt'
            $outputFile = Join-Path -Path $testDir -ChildPath 'url-safe-output.txt'
            $content = 'URL-safe encoding test!?&='

            $content | Set-Content -Path $sourceFile -NoNewline

            $encoded = ConvertTo-Base64 -Path $sourceFile -UrlSafe
            $encoded | Should -Not -Match '\+'
            $encoded | Should -Not -Match '/'
            $encoded | Should -Not -Match '='

            ConvertFrom-Base64 -InputObject $encoded -OutputPath $outputFile -UrlSafe

            $result = Get-Content -Path $outputFile -Raw
            $result.TrimEnd() | Should -Be $content
        }

        It 'Should handle various padding scenarios with URL-safe encoding' {
            $testStrings = @(
                'A'
                'AB'
                'ABC'
                'ABCD'
                'ABCDE'
            )

            foreach ($str in $testStrings)
            {
                $encoded = ConvertTo-Base64 -InputObject $str -UrlSafe
                $decoded = ConvertFrom-Base64 -InputObject $encoded -UrlSafe
                $decoded | Should -Be $str
            }
        }
    }

    Context 'Cross-Platform Compatibility' {
        It 'Should handle different line endings' {
            $testCases = @(
                @{ Content = "Line1`nLine2"; Description = 'Unix (LF)' }
                @{ Content = "Line1`r`nLine2"; Description = 'Windows (CRLF)' }
                @{ Content = "Line1`rLine2"; Description = 'Old Mac (CR)' }
            )

            foreach ($case in $testCases)
            {
                $encoded = ConvertTo-Base64 -InputObject $case.Content
                $decoded = ConvertFrom-Base64 -InputObject $encoded
                $decoded | Should -Be $case.Content -Because $case.Description
            }
        }

        It 'Should handle Unicode correctly' {
            # Use Unicode escape sequences for PowerShell 5.1 compatibility
            $unicodeStrings = @(
                "Hello $([char]0x4e16)$([char]0x754c)"  # Hello 世界
                "Привет мир"
                "$([char]0x645)$([char]0x631)$([char]0x62d)$([char]0x628)$([char]0x627) $([char]0x628)$([char]0x627)$([char]0x644)$([char]0x639)$([char]0x627)$([char]0x644)$([char]0x645)"  # مرحبا بالعالم
                "$([char]::ConvertFromUtf32(0x1F600))$([char]::ConvertFromUtf32(0x1F30D))$([char]::ConvertFromUtf32(0x1F389))"  # 😀🌍🎉
            )

            foreach ($str in $unicodeStrings)
            {
                $encoded = ConvertTo-Base64 -InputObject $str
                $decoded = ConvertFrom-Base64 -InputObject $encoded
                $decoded | Should -Be $str
            }
        }
    }

    Context 'Real-World Scenarios' {
        It 'Should encode credentials (common use case)' {
            $username = 'testuser'
            $password = 'P@ssw0rd!123'
            $credentials = "${username}:${password}"

            $encoded = ConvertTo-Base64 -InputObject $credentials
            $decoded = ConvertFrom-Base64 -InputObject $encoded

            $decoded | Should -Be $credentials
        }

        It 'Should handle JWT-like tokens (URL-safe)' {
            $header = @'
{"alg":"HS256","typ":"JWT"}
'@
            $payload = @'
{"sub":"1234567890","name":"John Doe","iat":1516239022}
'@

            $encodedHeader = ConvertTo-Base64 -InputObject $header -UrlSafe
            $encodedPayload = ConvertTo-Base64 -InputObject $payload -UrlSafe

            $decodedHeader = ConvertFrom-Base64 -InputObject $encodedHeader -UrlSafe
            $decodedPayload = ConvertFrom-Base64 -InputObject $encodedPayload -UrlSafe

            $decodedHeader | Should -Be $header
            $decodedPayload | Should -Be $payload
        }

        It 'Should encode small image file' {
            $sourceFile = Join-Path -Path $testDir -ChildPath 'image.bin'
            $outputFile = Join-Path -Path $testDir -ChildPath 'image-output.bin'

            # Simulate a small binary image (random bytes)
            $imageBytes = [byte[]](0..255 | Get-Random -Count 100)
            [System.IO.File]::WriteAllBytes($sourceFile, $imageBytes)

            $encoded = ConvertTo-Base64 -Path $sourceFile
            ConvertFrom-Base64 -InputObject $encoded -OutputPath $outputFile

            $result = [System.IO.File]::ReadAllBytes($outputFile)
            $result | Should -Be $imageBytes
        }

        It 'Should handle configuration data' {
            $config = @{
                server = 'example.com'
                port = 443
                ssl = $true
            } | ConvertTo-Json -Compress

            $encoded = ConvertTo-Base64 -InputObject $config
            $decoded = ConvertFrom-Base64 -InputObject $encoded

            $decoded | Should -Be $config
        }
    }

    Context 'Performance and Edge Cases' {
        It 'Should handle very long single-line input' {
            $longString = 'A' * 10000
            $encoded = ConvertTo-Base64 -InputObject $longString
            $decoded = ConvertFrom-Base64 -InputObject $encoded
            $decoded | Should -Be $longString
        }

        It 'Should handle special whitespace characters' {
            $testInput = "Tab:`t Space: NewLine:`n CarriageReturn:`r"
            $encoded = ConvertTo-Base64 -InputObject $testInput
            $decoded = ConvertFrom-Base64 -InputObject $encoded
            $decoded | Should -Be $testInput
        }

        It 'Should handle null bytes in binary data' {
            $bytes = [byte[]](0x00, 0xFF, 0x00, 0xFF, 0x00)
            $sourceFile = Join-Path -Path $testDir -ChildPath 'null-bytes.bin'
            $outputFile = Join-Path -Path $testDir -ChildPath 'null-bytes-output.bin'

            [System.IO.File]::WriteAllBytes($sourceFile, $bytes)

            $encoded = ConvertTo-Base64 -Path $sourceFile
            ConvertFrom-Base64 -InputObject $encoded -OutputPath $outputFile

            $result = [System.IO.File]::ReadAllBytes($outputFile)
            $result | Should -Be $bytes
        }
    }
}
