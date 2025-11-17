#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for New-RandomString function.

.DESCRIPTION
    Tests the New-RandomString function which generates random strings for passwords, tokens, and other uses.
    Validates parameter validation, character set handling, cryptographic security options, and exclusion features.

.NOTES
    These tests are based on the examples in the New-RandomString function documentation.
    Tests verify string generation, character exclusion, and cryptographically secure random generation.
#>

BeforeAll {
    # Load the function under test
    . "$PSScriptRoot/../../../Functions/Utilities/New-RandomString.ps1"
}

Describe 'New-RandomString' {
    Context 'Basic functionality' {
        It 'Returns a random 32-character string by default (Example: New-RandomString)' {
            # Test the default behavior - 32 character alphanumeric string
            $result = New-RandomString
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 32
            $result | Should -MatchExactly '^[0-9A-Za-z]+$'
        }

        It 'Returns a random 16-character string when Length is specified (Example: New-RandomString -Length 16)' {
            # Test custom length specification
            $result = New-RandomString -Length 16
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 16
            $result | Should -MatchExactly '^[0-9A-Za-z]+$'
        }

        It 'Returns a random 64-character string without ambiguous characters when ExcludeAmbiguous is specified (Example: New-RandomString -Length 64 -ExcludeAmbiguous)' {
            # Test exclusion of potentially confusing characters: 0, 1, O, I, l, o, i
            $result = New-RandomString -Length 64 -ExcludeAmbiguous
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 64
            # Should exclude all ambiguous characters: 0, 1, O, I, l, o, i
            $result | Should -Not -Match '[01OIlio]'
            $result | Should -MatchExactly '^[2-9A-HJ-KM-NP-Za-hj-km-np-z]+$'
        }

        It 'Returns a 20-character string including symbols when IncludeSymbols and Secure are specified (Example: New-RandomString -Length 20 -IncludeSymbols -Secure)' {
            # Test symbol inclusion and cryptographically secure generation
            $result = New-RandomString -Length 20 -IncludeSymbols -Secure
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 20
            # Should allow alphanumeric and symbols
            $result | Should -MatchExactly '^[0-9A-Za-z!@#$%^&*]+$'
        }

        It 'Returns different values on multiple calls' {
            # Verify randomness - multiple calls should produce different results
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
                # Should exclude all ambiguous characters: 0, 1, O, I, l, o, i
                $result | Should -Not -Match '[01OIlio]'
            }
        }

        It 'Should still include non-ambiguous numbers and letters when ExcludeAmbiguous is specified' {
            $result = New-RandomString -Length 1000 -ExcludeAmbiguous
            $result | Should -Match '[2-9]'  # Non-ambiguous numbers
            $result | Should -Match '[A-HJ-KM-NP-Z]'  # Uppercase letters excluding I, L, O
            $result | Should -Match '[a-hj-km-np-z]'  # Lowercase letters excluding i, l, o
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

            # Should exclude ambiguous characters: 0, 1, O, I, l, o, i
            $result | Should -Not -Match '[01OIlio]'

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
            # Use explicit arrays for better compatibility across PowerShell versions
            $numbers = @('0', '1', '2', '3', '4', '5', '6', '7', '8', '9')
            $upperCase = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')
            $lowerCase = @('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z')

            $allChars = $numbers + $upperCase + $lowerCase

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

    Context 'IncludeCharacters parameter' {
        It 'Should include custom characters when IncludeCharacters is specified' {
            $customChars = @('-', '_', '.')
            $result = New-RandomString -Length 200 -IncludeCharacters $customChars
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 200

            # At least one custom character should appear in a large sample
            $foundCustomChar = $false
            foreach ($char in $customChars)
            {
                if ($result -match [regex]::Escape($char))
                {
                    $foundCustomChar = $true
                    break
                }
            }
            $foundCustomChar | Should -Be $true
        }

        It 'Should work with special ASCII characters' {
            $specialChars = @('-', '_', '.', '|')
            $result = New-RandomString -Length 100 -IncludeCharacters $specialChars
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 100

            # Test multiple times to increase probability of finding special characters
            $foundSpecialChar = $false
            for ($i = 0; $i -lt 10; $i++)
            {
                $testResult = New-RandomString -Length 100 -IncludeCharacters $specialChars
                foreach ($char in $specialChars)
                {
                    if ($testResult -match [regex]::Escape($char))
                    {
                        $foundSpecialChar = $true
                        break
                    }
                }
                if ($foundSpecialChar) { break }
            }
            $foundSpecialChar | Should -Be $true
        }

        It 'Should work in combination with IncludeSymbols' {
            $customChars = @('-', '_', '.')
            $result = New-RandomString -Length 200 -IncludeCharacters $customChars -IncludeSymbols
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 200

            # Should allow standard symbols and custom characters
            $result | Should -MatchExactly '^[0-9A-Za-z!@#$%^&*._-]+$'
        }

        It 'Should work in combination with ExcludeAmbiguous' {
            $customChars = @('+', '=', '%')
            $result = New-RandomString -Length 100 -IncludeCharacters $customChars -ExcludeAmbiguous
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 100

            # Should exclude ambiguous characters: 0, 1, O, I, l, o, i
            $result | Should -Not -Match '[01OIlio]'

            # Test multiple times to find custom characters
            $foundCustomChar = $false
            for ($i = 0; $i -lt 10; $i++)
            {
                $testResult = New-RandomString -Length 100 -IncludeCharacters $customChars -ExcludeAmbiguous
                foreach ($char in $customChars)
                {
                    if ($testResult -match [regex]::Escape($char))
                    {
                        $foundCustomChar = $true
                        break
                    }
                }
                if ($foundCustomChar) { break }
            }
            $foundCustomChar | Should -Be $true
        }

        It 'Should respect ExcludeCharacters even when characters are in IncludeCharacters' {
            $customChars = @('X', 'Y', 'Z', '-', '_')
            $excludeChars = @('X', 'Z')  # Exclude some of the custom characters
            $result = New-RandomString -Length 100 -IncludeCharacters $customChars -ExcludeCharacters $excludeChars
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 100

            # Excluded characters should not appear, even if they were in IncludeCharacters
            foreach ($char in $excludeChars)
            {
                $result | Should -Not -Match [regex]::Escape($char)
            }

            # But non-excluded custom characters should still be possible
            $foundAllowedCustomChar = $false
            for ($i = 0; $i -lt 10; $i++)
            {
                $testResult = New-RandomString -Length 100 -IncludeCharacters $customChars -ExcludeCharacters $excludeChars
                if ($testResult -match '[Y_-]')
                {
                    $foundAllowedCustomChar = $true
                    break
                }
            }
            $foundAllowedCustomChar | Should -Be $true
        }

        It 'Should work with Secure parameter' {
            $customChars = @('+', '=', '%', '~')
            $result = New-RandomString -Length 50 -IncludeCharacters $customChars -Secure
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 50

            # Test multiple times to find custom characters with secure generation
            $foundCustomChar = $false
            for ($i = 0; $i -lt 10; $i++)
            {
                $testResult = New-RandomString -Length 50 -IncludeCharacters $customChars -Secure
                foreach ($char in $customChars)
                {
                    if ($testResult -match [regex]::Escape($char))
                    {
                        $foundCustomChar = $true
                        break
                    }
                }
                if ($foundCustomChar) { break }
            }
            $foundCustomChar | Should -Be $true
        }

        It 'Should handle empty IncludeCharacters array' {
            $result = New-RandomString -Length 20 -IncludeCharacters @()
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 20
            $result | Should -MatchExactly '^[0-9A-Za-z]+$'
        }

        It 'Should handle single custom character' {
            $customChar = @('-')
            $result = New-RandomString -Length 100 -IncludeCharacters $customChar
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 100

            # Test multiple times to find the custom character
            $foundCustomChar = $false
            for ($i = 0; $i -lt 10; $i++)
            {
                $testResult = New-RandomString -Length 100 -IncludeCharacters $customChar
                if ($testResult -match '-')
                {
                    $foundCustomChar = $true
                    break
                }
            }
            $foundCustomChar | Should -Be $true
        }

        It 'Should handle duplicate characters in IncludeCharacters array' {
            $customChars = @('X', 'X', 'Y', 'Y', 'Z')  # Duplicates should not cause issues
            $result = New-RandomString -Length 100 -IncludeCharacters $customChars
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 100

            # Test multiple times to find custom characters
            $foundCustomChar = $false
            for ($i = 0; $i -lt 10; $i++)
            {
                $testResult = New-RandomString -Length 100 -IncludeCharacters $customChars
                if ($testResult -match '[XYZ]')
                {
                    $foundCustomChar = $true
                    break
                }
            }
            $foundCustomChar | Should -Be $true
        }

        It 'Should work with separator characters' {
            $separators = @('-', '_', '.', '|')
            $result = New-RandomString -Length 50 -IncludeCharacters $separators
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 50

            # Should allow alphanumeric and separator characters
            $result | Should -MatchExactly '^[0-9A-Za-z._|-]+$'
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

                # Check that no ambiguous characters are present: 0, 1, O, I, l, o, i
                if ($result -match '[01OIlio]')
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
