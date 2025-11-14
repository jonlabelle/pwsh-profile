#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Get-StringHash function.

.DESCRIPTION
    Tests the Get-StringHash function which computes hash values for arbitrary string input
    using various cryptographic hash algorithms (SHA1, SHA256, SHA384, SHA512, MD5).

.NOTES
    These tests verify:
    - Hash computation for all supported algorithms
    - Pipeline input support
    - Different encoding support
    - Empty string and null handling
    - Object ToString() conversion
    - Output object structure
    - Error handling scenarios
#>

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../../Functions/Utilities/Get-StringHash.ps1"
}

Describe 'Get-StringHash' {
    Context 'Parameter Validation' {
        It 'Should have mandatory InputObject parameter' {
            $command = Get-Command Get-StringHash
            $inputParam = $command.Parameters['InputObject']
            $inputParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should accept pipeline input for InputObject' {
            $command = Get-Command Get-StringHash
            $inputParam = $command.Parameters['InputObject']
            $inputParam.Attributes.ValueFromPipeline | Should -Contain $true
        }

        It 'Should have optional Algorithm parameter with default SHA256' {
            $command = Get-Command Get-StringHash
            $algoParam = $command.Parameters['Algorithm']
            $algoParam.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should validate Algorithm parameter with correct values' {
            $command = Get-Command Get-StringHash
            $algoParam = $command.Parameters['Algorithm']
            $validateSet = $algoParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'SHA1'
            $validateSet.ValidValues | Should -Contain 'SHA256'
            $validateSet.ValidValues | Should -Contain 'SHA384'
            $validateSet.ValidValues | Should -Contain 'SHA512'
            $validateSet.ValidValues | Should -Contain 'MD5'
        }

        It 'Should have optional Encoding parameter with default UTF8' {
            $command = Get-Command Get-StringHash
            $encodingParam = $command.Parameters['Encoding']
            $encodingParam.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should validate Encoding parameter with correct values' {
            $command = Get-Command Get-StringHash
            $encodingParam = $command.Parameters['Encoding']
            $validateSet = $encodingParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'ASCII'
            $validateSet.ValidValues | Should -Contain 'UTF7'
            $validateSet.ValidValues | Should -Contain 'UTF8'
            $validateSet.ValidValues | Should -Contain 'UTF32'
            $validateSet.ValidValues | Should -Contain 'Unicode'
            $validateSet.ValidValues | Should -Contain 'BigEndianUnicode'
            $validateSet.ValidValues | Should -Contain 'Default'
        }
    }

    Context 'SHA256 Algorithm (Default)' {
        It 'Should compute correct SHA256 hash for simple string' {
            $result = Get-StringHash -InputObject 'Hello, World!'
            $result.Algorithm | Should -Be 'SHA256'
            $result.Hash | Should -Be 'DFFD6021BB2BD5B0AF676290809EC3A53191DD81C7F70A4B28688A362182986F'
            $result.InputObject | Should -Be 'Hello, World!'
        }

        It 'Should compute correct SHA256 hash for empty string' {
            $result = Get-StringHash -InputObject ''
            $result.Algorithm | Should -Be 'SHA256'
            $result.Hash | Should -Be 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'
            $result.InputObject | Should -Be ''
        }

        It 'Should use SHA256 as default algorithm when not specified' {
            $result = Get-StringHash -InputObject 'test'
            $result.Algorithm | Should -Be 'SHA256'
        }

        It 'Should compute correct SHA256 hash for numeric string' {
            $result = Get-StringHash -InputObject '12345'
            $result.Algorithm | Should -Be 'SHA256'
            $result.Hash | Should -Be '5994471ABB01112AFCC18159F6CC74B4F511B99806DA59B3CAF5A9C173CACFC5'
        }

        It 'Should compute correct SHA256 hash for special characters' {
            $result = Get-StringHash -InputObject '!@#$%^&*()'
            $result.Algorithm | Should -Be 'SHA256'
            $result.Hash | Should -Be '95CE789C5C9D18490972709838CA3A9719094BCA3AC16332CFEC0652B0236141'
        }
    }

    Context 'SHA1 Algorithm' {
        It 'Should compute correct SHA1 hash' {
            $result = Get-StringHash -InputObject 'Secret' -Algorithm SHA1
            $result.Algorithm | Should -Be 'SHA1'
            $result.Hash | Should -Be 'F4E7A8740DB0B7A0BFD8E63077261475F61FC2A6'
            $result.InputObject | Should -Be 'Secret'
        }

        It 'Should compute correct SHA1 hash for empty string' {
            $result = Get-StringHash -InputObject '' -Algorithm SHA1
            $result.Algorithm | Should -Be 'SHA1'
            $result.Hash | Should -Be 'DA39A3EE5E6B4B0D3255BFEF95601890AFD80709'
        }
    }

    Context 'SHA384 Algorithm' {
        It 'Should compute correct SHA384 hash' {
            $result = Get-StringHash -InputObject 'Test' -Algorithm SHA384
            $result.Algorithm | Should -Be 'SHA384'
            $result.Hash | Should -Be '7B8F4654076B80EB963911F19CFAD1AAF4285ED48E826F6CDE1B01A79AA73FADB5446E667FC4F90417782C91270540F3'
            $result.InputObject | Should -Be 'Test'
        }

        It 'Should compute correct SHA384 hash for empty string' {
            $result = Get-StringHash -InputObject '' -Algorithm SHA384
            $result.Algorithm | Should -Be 'SHA384'
            $result.Hash | Should -Be '38B060A751AC96384CD9327EB1B1E36A21FDB71114BE07434C0CC7BF63F6E1DA274EDEBFE76F65FBD51AD2F14898B95B'
        }
    }

    Context 'SHA512 Algorithm' {
        It 'Should compute correct SHA512 hash' {
            $result = Get-StringHash -InputObject 'Test123' -Algorithm SHA512
            $result.Algorithm | Should -Be 'SHA512'
            $result.Hash | Should -Be 'C12834F1031F6497214F27D4432F26517AD494156CB88D512BDB1DC4B57DB2D692A3DFA269A19B0A0A2A0FD7D6A2A885E33C839C93C206DA30A187392847ED27'
            $result.InputObject | Should -Be 'Test123'
        }

        It 'Should compute correct SHA512 hash for empty string' {
            $result = Get-StringHash -InputObject '' -Algorithm SHA512
            $result.Algorithm | Should -Be 'SHA512'
            $result.Hash | Should -Be 'CF83E1357EEFB8BDF1542850D66D8007D620E4050B5715DC83F4A921D36CE9CE47D0D13C5D85F2B0FF8318D2877EEC2F63B931BD47417A81A538327AF927DA3E'
        }
    }

    Context 'MD5 Algorithm' {
        It 'Should compute correct MD5 hash' {
            $result = Get-StringHash -InputObject 'PowerShell' -Algorithm MD5
            $result.Algorithm | Should -Be 'MD5'
            $result.Hash | Should -Be '3D265B4E1EEEF0DDF17881FA003B18CC'
            $result.InputObject | Should -Be 'PowerShell'
        }

        It 'Should compute correct MD5 hash for empty string' {
            $result = Get-StringHash -InputObject '' -Algorithm MD5
            $result.Algorithm | Should -Be 'MD5'
            $result.Hash | Should -Be 'D41D8CD98F00B204E9800998ECF8427E'
        }
    }

    Context 'Pipeline Input' {
        It 'Should accept string from pipeline' {
            $result = 'PowerShell' | Get-StringHash -Algorithm MD5
            $result.Hash | Should -Be '3D265B4E1EEEF0DDF17881FA003B18CC'
        }

        It 'Should process multiple strings from pipeline' {
            $results = 'test1', 'test2', 'test3' | Get-StringHash -Algorithm SHA256
            $results.Count | Should -Be 3
            $results[0].InputObject | Should -Be 'test1'
            $results[1].InputObject | Should -Be 'test2'
            $results[2].InputObject | Should -Be 'test3'
            $results[0].Hash | Should -Not -Be $results[1].Hash
            $results[1].Hash | Should -Not -Be $results[2].Hash
        }

        It 'Should process empty strings from pipeline' {
            $results = '', 'text', '' | Get-StringHash
            $results.Count | Should -Be 3
            $results[0].InputObject | Should -Be ''
            $results[1].InputObject | Should -Be 'text'
            $results[2].InputObject | Should -Be ''
            $results[0].Hash | Should -Be $results[2].Hash
        }
    }

    Context 'Encoding Support' {
        It 'Should produce different hashes for different encodings' {
            $utf8Result = Get-StringHash -InputObject 'Test' -Encoding UTF8
            $asciiResult = Get-StringHash -InputObject 'Test' -Encoding ASCII
            $unicodeResult = Get-StringHash -InputObject 'Test' -Encoding Unicode

            # For simple ASCII characters, UTF8 and ASCII should be the same
            $utf8Result.Hash | Should -Be $asciiResult.Hash
            # But Unicode (UTF-16LE) should be different
            $utf8Result.Hash | Should -Not -Be $unicodeResult.Hash
        }

        It 'Should handle UTF8 encoding (default)' {
            $result = Get-StringHash -InputObject 'Hello' -Encoding UTF8
            $result.Hash | Should -Be '185F8DB32271FE25F561A6FC938B2E264306EC304EDA518007D1764826381969'
        }

        It 'Should handle ASCII encoding' {
            $result = Get-StringHash -InputObject 'Hello' -Encoding ASCII
            $result.Hash | Should -Be '185F8DB32271FE25F561A6FC938B2E264306EC304EDA518007D1764826381969'
        }

        It 'Should handle Unicode encoding' {
            $result = Get-StringHash -InputObject 'Hello' -Encoding Unicode
            $result.Hash | Should -Be 'A07E4F7343246C82B26F32E56F85418D518D8B2F2DAE77F1D56FE7AF50DB97AF'
        }

        It 'Should handle UTF32 encoding' {
            $result = Get-StringHash -InputObject 'Hi' -Encoding UTF32
            $result.Hash | Should -Match '^[A-F0-9]{64}$'
        }

        It 'Should handle BigEndianUnicode encoding' {
            $result = Get-StringHash -InputObject 'Hi' -Encoding BigEndianUnicode
            $result.Hash | Should -Match '^[A-F0-9]{64}$'
        }
    }

    Context 'Object Input' {
        It 'Should convert integer to string and hash it' {
            $result = Get-StringHash -InputObject 42
            $result.InputObject | Should -Be '42'
            $result.Hash | Should -Match '^[A-F0-9]{64}$'
        }

        It 'Should convert DateTime to string and hash it' {
            $date = [DateTime]'2025-01-01'
            $result = Get-StringHash -InputObject $date
            $result.InputObject | Should -Be $date.ToString()
            $result.Hash | Should -Match '^[A-F0-9]{64}$'
        }

        It 'Should convert boolean to string and hash it' {
            $result = Get-StringHash -InputObject $true
            $result.InputObject | Should -Be 'True'
            $result.Hash | Should -Match '^[A-F0-9]{64}$'
        }

        It 'Should handle custom object with ToString()' {
            $obj = [PSCustomObject]@{ Name = 'Test'; Value = 123 }
            $result = Get-StringHash -InputObject $obj
            $result.InputObject | Should -Be $obj.ToString()
        }
    }

    Context 'Output Format' {
        It 'Should return object with Algorithm property' {
            $result = Get-StringHash -InputObject 'test'
            $result.PSObject.Properties.Name | Should -Contain 'Algorithm'
        }

        It 'Should return object with Hash property' {
            $result = Get-StringHash -InputObject 'test'
            $result.PSObject.Properties.Name | Should -Contain 'Hash'
        }

        It 'Should return object with InputObject property' {
            $result = Get-StringHash -InputObject 'test'
            $result.PSObject.Properties.Name | Should -Contain 'InputObject'
        }

        It 'Should return hash in uppercase hexadecimal format' {
            $result = Get-StringHash -InputObject 'test'
            $result.Hash | Should -Match '^[A-F0-9]+$'
        }

        It 'Should return SHA256 hash with 64 characters' {
            $result = Get-StringHash -InputObject 'test' -Algorithm SHA256
            $result.Hash.Length | Should -Be 64
        }

        It 'Should return SHA1 hash with 40 characters' {
            $result = Get-StringHash -InputObject 'test' -Algorithm SHA1
            $result.Hash.Length | Should -Be 40
        }

        It 'Should return SHA384 hash with 96 characters' {
            $result = Get-StringHash -InputObject 'test' -Algorithm SHA384
            $result.Hash.Length | Should -Be 96
        }

        It 'Should return SHA512 hash with 128 characters' {
            $result = Get-StringHash -InputObject 'test' -Algorithm SHA512
            $result.Hash.Length | Should -Be 128
        }

        It 'Should return MD5 hash with 32 characters' {
            $result = Get-StringHash -InputObject 'test' -Algorithm MD5
            $result.Hash.Length | Should -Be 32
        }
    }

    Context 'Consistency' {
        It 'Should produce same hash for same input string' {
            $result1 = Get-StringHash -InputObject 'consistent'
            $result2 = Get-StringHash -InputObject 'consistent'
            $result1.Hash | Should -Be $result2.Hash
        }

        It 'Should produce different hash for different input strings' {
            $result1 = Get-StringHash -InputObject 'string1'
            $result2 = Get-StringHash -InputObject 'string2'
            $result1.Hash | Should -Not -Be $result2.Hash
        }

        It 'Should produce same hash when called multiple times with same algorithm' {
            $hash1 = (Get-StringHash -InputObject 'test' -Algorithm SHA256).Hash
            $hash2 = (Get-StringHash -InputObject 'test' -Algorithm SHA256).Hash
            $hash3 = (Get-StringHash -InputObject 'test' -Algorithm SHA256).Hash
            $hash1 | Should -Be $hash2
            $hash2 | Should -Be $hash3
        }

        It 'Should produce different hash for different algorithms' {
            $sha256 = Get-StringHash -InputObject 'test' -Algorithm SHA256
            $sha512 = Get-StringHash -InputObject 'test' -Algorithm SHA512
            $md5 = Get-StringHash -InputObject 'test' -Algorithm MD5

            $sha256.Hash | Should -Not -Be $sha512.Hash
            $sha256.Hash | Should -Not -Be $md5.Hash
            $sha512.Hash | Should -Not -Be $md5.Hash
        }
    }

    Context 'Edge Cases' {
        It 'Should handle very long strings' {
            $longString = 'a' * 10000
            $result = Get-StringHash -InputObject $longString
            $result.Hash | Should -Match '^[A-F0-9]{64}$'
            $result.InputObject.Length | Should -Be 10000
        }

        It 'Should handle strings with newlines' {
            $multiline = "Line1`nLine2`nLine3"
            $result = Get-StringHash -InputObject $multiline
            $result.Hash | Should -Match '^[A-F0-9]{64}$'
            $result.InputObject | Should -Be $multiline
        }

        It 'Should handle strings with tabs' {
            $withTabs = "Tab`tSeparated`tValues"
            $result = Get-StringHash -InputObject $withTabs
            $result.Hash | Should -Match '^[A-F0-9]{64}$'
        }

        It 'Should handle Unicode characters' {
            $unicode = '你好世界🌍'
            $result = Get-StringHash -InputObject $unicode
            $result.Hash | Should -Match '^[A-F0-9]{64}$'
            $result.InputObject | Should -Be $unicode
        }

        It 'Should handle whitespace-only strings' {
            $whitespace = '   '
            $result = Get-StringHash -InputObject $whitespace
            $result.Hash | Should -Match '^[A-F0-9]{64}$'
            $result.InputObject | Should -Be $whitespace
        }

        It 'Should handle single character' {
            $result = Get-StringHash -InputObject 'x'
            $result.Hash | Should -Match '^[A-F0-9]{64}$'
        }
    }

    Context 'Empty String Handling' {
        It 'Should handle empty string correctly' {
            $result = Get-StringHash -InputObject ''
            $result.InputObject | Should -Be ''
            $result.Hash | Should -Be 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'
        }
    }

    Context 'Verbose Output' {
        It 'Should provide verbose output when requested' {
            $verboseOutput = Get-StringHash -InputObject 'test' -Verbose 4>&1
            $verboseOutput | Should -Not -BeNullOrEmpty
        }
    }
}
