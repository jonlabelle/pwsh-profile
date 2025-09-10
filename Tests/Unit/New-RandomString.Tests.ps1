BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../Functions/New-RandomString.ps1"
}

Describe 'New-RandomString' {
    Context 'Basic functionality' {
        It 'Returns a random 32-character string by default' {
            $result = New-RandomString
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 32
            $result | Should -MatchExactly '^[0-9A-Za-z]+$'
        }

        It 'Returns a random 16-character string when Length is specified' {
            $result = New-RandomString -Length 16
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 16
            $result | Should -MatchExactly '^[0-9A-Za-z]+$'
        }

        It 'Returns a random 64-character string without ambiguous characters when ExcludeAmbiguous is specified' {
            $result = New-RandomString -Length 64 -ExcludeAmbiguous
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 64
            # Based on implementation: only excludes '0' and '1' from numbers, but includes all letters
            $result | Should -Not -Match '[01]'
            $result | Should -MatchExactly '^[2-9A-Za-z]+$'
        }

        It 'Returns a 20-character string including symbols when IncludeSymbols and Secure are specified' {
            $result = New-RandomString -Length 20 -IncludeSymbols -Secure
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 20
            # Should allow alphanumeric and symbols
            $result | Should -MatchExactly '^[0-9A-Za-z!@#$%^&*]+$'
        }

        It 'Returns different values on multiple calls' {
            $result1 = New-RandomString -Length 10
            $result2 = New-RandomString -Length 10
            $result1 | Should -Not -Be $result2
        }
    }

    Context 'Parameter validation' {
        It 'Should accept Length values within valid range' {
            { New-RandomString -Length 1 } | Should -Not -Throw
            { New-RandomString -Length 10000 } | Should -Not -Throw
        }

        It 'Should reject Length values outside valid range' {
            { New-RandomString -Length 0 } | Should -Throw
            { New-RandomString -Length 10001 } | Should -Throw
            { New-RandomString -Length -1 } | Should -Throw
        }
    }

    Context 'Character set validation' {
        It 'Should include numbers when not excluding ambiguous' {
            $result = New-RandomString -Length 1000  # Large sample to increase probability
            $result | Should -Match '[0-9]'
        }

        It 'Should include uppercase letters' {
            $result = New-RandomString -Length 1000
            $result | Should -Match '[A-Z]'
        }

        It 'Should include lowercase letters' {
            $result = New-RandomString -Length 1000
            $result | Should -Match '[a-z]'
        }

        It 'Should include symbols when IncludeSymbols is specified' {
            $result = New-RandomString -Length 1000 -IncludeSymbols
            $result | Should -Match '[!@#$%^&*]'
        }

        It 'Should not include symbols when IncludeSymbols is not specified' {
            $result = New-RandomString -Length 100
            $result | Should -Not -Match '[!@#$%^&*]'
        }
    }

    Context 'ExcludeAmbiguous parameter' {
        It 'Should exclude ambiguous characters when ExcludeAmbiguous is specified' {
            # Test multiple times to increase confidence
            1..10 | ForEach-Object {
                $result = New-RandomString -Length 100 -ExcludeAmbiguous
                # Based on actual implementation: only '0' and '1' are excluded
                $result | Should -Not -Match '[01]'
            }
        }

        It 'Should still include non-ambiguous numbers and letters when ExcludeAmbiguous is specified' {
            $result = New-RandomString -Length 1000 -ExcludeAmbiguous
            $result | Should -Match '[2-9]'  # Non-ambiguous numbers (actual implementation)
            $result | Should -Match '[A-Z]'  # All uppercase letters (actual implementation)
            $result | Should -Match '[a-z]'  # All lowercase letters (actual implementation)
        }
    }

    Context 'ExcludeCharacters parameter' {
        It 'Should exclude specific characters when ExcludeCharacters is specified' {
            $excludedChars = @('0', '1', 'A', 'a')
            $result = New-RandomString -Length 100 -ExcludeCharacters $excludedChars
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 100

            # None of the excluded characters should appear
            foreach ($char in $excludedChars)
            {
                $result | Should -Not -Match [regex]::Escape($char)
            }
        }

        It 'Should work with symbols exclusion when IncludeSymbols is specified' {
            $excludedSymbols = @('!', '@', '#')
            $result = New-RandomString -Length 200 -IncludeSymbols -ExcludeCharacters $excludedSymbols
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 200

            # Excluded symbols should not appear
            foreach ($symbol in $excludedSymbols)
            {
                $result | Should -Not -Match [regex]::Escape($symbol)
            }

            # But other symbols should still be possible
            # Test multiple times to increase probability of finding allowed symbols
            $foundAllowedSymbol = $false
            for ($i = 0; $i -lt 10; $i++)
            {
                $testResult = New-RandomString -Length 200 -IncludeSymbols -ExcludeCharacters $excludedSymbols
                if ($testResult -match '[$%^&*]')
                {
                    $foundAllowedSymbol = $true
                    break
                }
            }
            $foundAllowedSymbol | Should -Be $true
        }

        It 'Should work in combination with ExcludeAmbiguous' {
            $additionalExclusions = @('X', 'Y', 'Z')
            $result = New-RandomString -Length 100 -ExcludeAmbiguous -ExcludeCharacters $additionalExclusions
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 100

            # Should exclude ambiguous characters (0, 1 based on implementation)
            $result | Should -Not -Match '[01]'

            # Should also exclude additional characters
            foreach ($char in $additionalExclusions)
            {
                $result | Should -Not -Match [regex]::Escape($char)
            }
        }

        It 'Should work with Secure parameter' {
            $excludedChars = @('0', 'O', '1', 'I')
            $result = New-RandomString -Length 50 -ExcludeCharacters $excludedChars -Secure
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 50

            # None of the excluded characters should appear
            foreach ($char in $excludedChars)
            {
                $result | Should -Not -Match [regex]::Escape($char)
            }
        }

        It 'Should throw an error when all characters are excluded' {
            # Create a list that excludes all possible characters
            $allChars = @()
            $allChars += 0..9 | ForEach-Object { $_.ToString() }
            $allChars += 'A'..'Z'
            $allChars += 'a'..'z'

            { New-RandomString -Length 10 -ExcludeCharacters $allChars } | Should -Throw -ExpectedMessage '*All available characters have been excluded*'
        }

        It 'Should handle empty ExcludeCharacters array' {
            $result = New-RandomString -Length 20 -ExcludeCharacters @()
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 20
            $result | Should -MatchExactly '^[0-9A-Za-z]+$'
        }

        It 'Should exclude single character correctly' {
            $result = New-RandomString -Length 100 -ExcludeCharacters @('X')
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 100
            $result | Should -Not -Match 'X'
        }

        It 'Should handle case-sensitive exclusions' {
            # Test excluding uppercase 'A'
            $result = New-RandomString -Length 100 -ExcludeCharacters @('A')
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 100
            $result | Should -Not -Match 'A'

            # Test excluding lowercase 'a'
            $result2 = New-RandomString -Length 100 -ExcludeCharacters @('a')
            $result2 | Should -Not -BeNullOrEmpty
            $result2.Length | Should -Be 100
            $result2 | Should -Not -Match 'a'
        }
    }

    Context 'Secure parameter' {
        It 'Should generate cryptographically secure random when Secure is specified' {
            # We can't directly test cryptographic security, but we can test that it works
            $result = New-RandomString -Length 32 -Secure
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 32
        }

        It 'Should work with all parameter combinations when Secure is specified' {
            # Test multiple times to ensure we get symbols due to randomness
            $foundSymbol = $false
            $foundNoAmbiguous = $true

            for ($i = 0; $i -lt 10; $i++)
            {
                $result = New-RandomString -Length 100 -ExcludeAmbiguous -IncludeSymbols -Secure
                $result | Should -Not -BeNullOrEmpty
                $result.Length | Should -Be 100

                # Check that no ambiguous characters are present
                if ($result -match '[01]')
                {
                    $foundNoAmbiguous = $false
                }

                # Check if we found symbols in any attempt
                if ($result -match '[!@#$%^&*]')
                {
                    $foundSymbol = $true
                }
            }

            $foundNoAmbiguous | Should -Be $true
            $foundSymbol | Should -Be $true
        }
    }

    Context 'Output type' {
        It 'Should return a string' {
            $result = New-RandomString
            $result | Should -BeOfType [String]
        }
    }
}
