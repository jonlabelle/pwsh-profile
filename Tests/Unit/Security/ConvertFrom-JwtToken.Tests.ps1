#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for ConvertFrom-JwtToken function.

.DESCRIPTION
    Tests the ConvertFrom-JwtToken function which decodes JWT tokens.
    Validates parameter validation, JWT decoding, Base64URL decoding, and error handling.

.NOTES
    These tests are based on the examples in the ConvertFrom-JwtToken function documentation.
    Tests use standard JWT test vectors for validation.
#>

BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../../Functions/Security/ConvertFrom-JwtToken.ps1"

    # Standard test JWT token from jwt.io
    # Header: {"alg":"HS256","typ":"JWT"}
    # Payload: {"sub":"1234567890","name":"John Doe","iat":1516239022}
    $script:ValidToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c'

    # Token with additional claims
    # Header: {"alg":"RS256","typ":"JWT"}
    # Payload: {"sub":"user123","name":"Jane Smith","email":"jane@example.com","exp":1735689600,"iat":1704067200,"iss":"https://example.com","aud":"api://default"}
    $script:ComplexToken = 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMTIzIiwibmFtZSI6IkphbmUgU21pdGgiLCJlbWFpbCI6ImphbmVAZXhhbXBsZS5jb20iLCJleHAiOjE3MzU2ODk2MDAsImlhdCI6MTcwNDA2NzIwMCwiaXNzIjoiaHR0cHM6Ly9leGFtcGxlLmNvbSIsImF1ZCI6ImFwaTovL2RlZmF1bHQifQ.signature'
}

Describe 'ConvertFrom-JwtToken Unit Tests' {
    Context 'Parameter Validation' {
        It 'Should require Token parameter' {
            # Test that the Token parameter is mandatory by checking the parameter metadata
            $command = Get-Command ConvertFrom-JwtToken
            $tokenParam = $command.Parameters['Token']
            $tokenParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should accept token from pipeline' {
            $result = $script:ValidToken | ConvertFrom-JwtToken -AsObject
            $result | Should -Not -BeNullOrEmpty
            $result.Header | Should -Not -BeNullOrEmpty
            $result.Payload | Should -Not -BeNullOrEmpty
        }

        It 'Should throw when token is null or empty' {
            { ConvertFrom-JwtToken -Token '' } | Should -Throw
            { ConvertFrom-JwtToken -Token $null } | Should -Throw
        }

        It 'Should throw when token format is invalid (missing parts)' {
            { ConvertFrom-JwtToken -Token 'invalid.token' } | Should -Throw '*Invalid JWT token format*'
        }

        It 'Should throw when token has too many parts' {
            { ConvertFrom-JwtToken -Token 'part1.part2.part3.part4' } | Should -Throw '*Invalid JWT token format*'
        }

        It 'Should throw when token has only one part' {
            { ConvertFrom-JwtToken -Token 'singlepart' } | Should -Throw '*Invalid JWT token format*'
        }
    }

    Context 'JWT Decoding - Standard Token' {
        It 'Should decode a valid JWT token successfully (Example: ConvertFrom-JwtToken -Token $token -AsObject)' {
            # Test basic JWT decoding functionality as shown in documentation
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -AsObject

            $result | Should -Not -BeNullOrEmpty
            $result.Header | Should -Not -BeNullOrEmpty
            $result.Payload | Should -Not -BeNullOrEmpty
        }

        It 'Should decode header correctly' {
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -AsObject

            $result.Header.alg | Should -Be 'HS256'
            $result.Header.typ | Should -Be 'JWT'
        }

        It 'Should decode payload correctly' {
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -AsObject

            $result.Payload.sub | Should -Be '1234567890'
            $result.Payload.name | Should -Be 'John Doe'
            $result.Payload.iat | Should -Be 1516239022
        }

        It 'Should not include signature by default' {
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -AsObject

            $result.PSObject.Properties.Name | Should -Not -Contain 'Signature'
        }

        It 'Should handle tokens with whitespace (Example: Get-Clipboard | ConvertFrom-JwtToken -AsObject)' {
            # Simulate clipboard content with leading/trailing whitespace
            $tokenWithWhitespace = "  $script:ValidToken  "
            $result = ConvertFrom-JwtToken -Token $tokenWithWhitespace -AsObject

            $result.Payload.name | Should -Be 'John Doe'
        }
    }

    Context 'JWT Decoding - Complex Token' {
        It 'Should decode token with multiple claims (Example: $jwt.Payload.exp)' {
            $result = ConvertFrom-JwtToken -Token $script:ComplexToken -AsObject

            $result.Payload.sub | Should -Be 'user123'
            $result.Payload.name | Should -Be 'Jane Smith'
            $result.Payload.email | Should -Be 'jane@example.com'
            $result.Payload.exp | Should -Be 1735689600
            $result.Payload.iat | Should -Be 1704067200
            $result.Payload.iss | Should -Be 'https://example.com'
            $result.Payload.aud | Should -Be 'api://default'
        }

        It 'Should decode RS256 algorithm in header' {
            $result = ConvertFrom-JwtToken -Token $script:ComplexToken -AsObject

            $result.Header.alg | Should -Be 'RS256'
            $result.Header.typ | Should -Be 'JWT'
        }

        It 'Should allow accessing specific payload properties (Example: $decoded.Payload.sub)' {
            $decoded = ConvertFrom-JwtToken -Token $script:ComplexToken -AsObject

            $decoded.Payload.sub | Should -Be 'user123'
            $decoded.Payload.name | Should -Be 'Jane Smith'
        }

        It 'Should allow accessing header properties (Example: $decoded.Header.alg)' {
            $decoded = ConvertFrom-JwtToken -Token $script:ComplexToken -AsObject

            $decoded.Header.alg | Should -Be 'RS256'
        }
    }

    Context 'Signature Handling' {
        It 'Should include signature when -IncludeSignature is specified (Example: ConvertFrom-JwtToken -Token $token -IncludeSignature -AsObject)' {
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -IncludeSignature -AsObject

            $result.PSObject.Properties.Name | Should -Contain 'Signature'
            $result.Signature | Should -Be 'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c'
        }

        It 'Should return signature as string' {
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -IncludeSignature -AsObject

            $result.Signature | Should -BeOfType [String]
            $result.Signature | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Base64URL Decoding' {
        It 'Should handle Base64URL encoding with - and _ characters' {
            # Create a token with Base64URL special characters
            # Header: {"alg":"HS256"} -> eyJhbGciOiJIUzI1NiJ9
            # Payload: {"test":"value-with_special"} -> eyJ0ZXN0IjoidmFsdWUtd2l0aF9zcGVjaWFsIn0
            $specialToken = 'eyJhbGciOiJIUzI1NiJ9.eyJ0ZXN0IjoidmFsdWUtd2l0aF9zcGVjaWFsIn0.sig'

            $result = ConvertFrom-JwtToken -Token $specialToken -AsObject

            $result.Header.alg | Should -Be 'HS256'
            $result.Payload.test | Should -Be 'value-with_special'
        }

        It 'Should handle Base64URL padding correctly' {
            # JWT tokens don't have padding, but the function should add it correctly
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -AsObject

            # If padding was handled incorrectly, this would fail
            $result.Header | Should -Not -BeNullOrEmpty
            $result.Payload | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Output Format' {
        It 'Should return PSCustomObject' {
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -AsObject

            $result | Should -BeOfType [PSCustomObject]
        }

        It 'Should have Header and Payload properties' {
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -AsObject

            $result.PSObject.Properties.Name | Should -Contain 'Header'
            $result.PSObject.Properties.Name | Should -Contain 'Payload'
        }

        It 'Should have exactly 2 properties without -IncludeSignature' {
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -AsObject

            $result.PSObject.Properties.Name.Count | Should -Be 2
        }

        It 'Should have exactly 3 properties with -IncludeSignature' {
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -IncludeSignature -AsObject

            $result.PSObject.Properties.Name.Count | Should -Be 3
        }
    }

    Context 'Error Handling' {
        It 'Should throw on invalid Base64 in header' {
            $invalidToken = 'invalid!!!.eyJzdWIiOiIxMjM0NTY3ODkwIn0.sig'

            { ConvertFrom-JwtToken -Token $invalidToken } | Should -Throw
        }

        It 'Should throw on invalid Base64 in payload' {
            $invalidToken = 'eyJhbGciOiJIUzI1NiJ9.invalid!!!.sig'

            { ConvertFrom-JwtToken -Token $invalidToken } | Should -Throw
        }

        It 'Should throw on invalid JSON in header' {
            # Valid Base64 but invalid JSON
            $invalidToken = 'bm90anNvbg.eyJzdWIiOiIxMjM0NTY3ODkwIn0.sig'

            { ConvertFrom-JwtToken -Token $invalidToken } | Should -Throw
        }

        It 'Should throw on invalid JSON in payload' {
            # Valid Base64 but invalid JSON
            $invalidToken = 'eyJhbGciOiJIUzI1NiJ9.bm90anNvbg.sig'

            { ConvertFrom-JwtToken -Token $invalidToken } | Should -Throw
        }
    }

    Context 'Pipeline Support' {
        It 'Should process token from pipeline' {
            $result = $script:ValidToken | ConvertFrom-JwtToken -AsObject

            $result.Payload.name | Should -Be 'John Doe'
        }

        It 'Should process multiple tokens from pipeline' {
            $tokens = @($script:ValidToken, $script:ComplexToken)
            $results = $tokens | ConvertFrom-JwtToken -AsObject

            $results.Count | Should -Be 2
            $results[0].Payload.name | Should -Be 'John Doe'
            $results[1].Payload.name | Should -Be 'Jane Smith'
        }
    }

    Context 'Pretty Output Format' {
        It 'Should not return object by default (formatted output)' {
            $result = ConvertFrom-JwtToken -Token $script:ValidToken

            $result | Should -BeNullOrEmpty
        }

        It 'Should return object when -AsObject is used' {
            $result = ConvertFrom-JwtToken -Token $script:ValidToken -AsObject

            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [PSCustomObject]
        }

        It 'Should support -IncludeSignature with formatted output' {
            # This should not throw and should produce formatted output with signature
            { ConvertFrom-JwtToken -Token $script:ValidToken -IncludeSignature } | Should -Not -Throw
        }

        It 'Should support -AsObject with -IncludeSignature' {
            # This should not throw and should return object with signature
            { ConvertFrom-JwtToken -Token $script:ValidToken -AsObject -IncludeSignature } | Should -Not -Throw
        }
    }
}
