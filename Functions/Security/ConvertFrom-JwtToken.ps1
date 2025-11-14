function ConvertFrom-JwtToken
{
    <#
    .SYNOPSIS
        Decodes a JWT (JSON Web Token) and returns its header and payload.

    .DESCRIPTION
        This function decodes a JWT token and extracts its header and payload components.
        It performs Base64URL decoding and JSON parsing to reveal the token contents without
        validating the signature. This is useful for inspecting token claims, expiration times,
        and other metadata.

        Unlike online JWT decoding websites and tools, this function decodes tokens locally
        without transmitting them over the network, preventing potential token leakage to third-party
        services or clever browser extensions.

        JWT STRUCTURE:
        - Header: Contains token type and signing algorithm
        - Payload: Contains claims (user data, expiration, issuer, etc.)
        - Signature: Cryptographic signature (not validated by this function)

        CROSS-PLATFORM COMPATIBILITY:
        This function works on PowerShell 5.1+ across Windows, macOS, and Linux
        by using .NET Base64 conversion and JSON parsing.

        SECURITY NOTE:
        This function ONLY decodes the token - it does NOT validate the signature.
        Do not use decoded tokens for authentication without proper signature verification.

    .PARAMETER Token
        The JWT token string to decode. Can be provided as a string or via pipeline.
        Must be in the standard three-part format: header.payload.signature

    .PARAMETER IncludeSignature
        If specified, includes the raw signature component in the output.
        The signature is returned as-is (Base64URL encoded) without validation.

    .EXAMPLE
        PS > $token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        PS > ConvertFrom-JwtToken -Token $token

        Decodes a JWT token and displays the header and payload.

    .EXAMPLE
        PS > $jwt = ConvertFrom-JwtToken -Token $token
        PS > $jwt.Payload.exp

        Decodes a token and accesses the expiration claim.

    .EXAMPLE
        PS > Get-Clipboard | ConvertFrom-JwtToken

        Decodes a JWT token from the clipboard.

    .EXAMPLE
        PS > ConvertFrom-JwtToken -Token $token -IncludeSignature

        Decodes the token and includes the signature component.

    .EXAMPLE
        PS > $decoded = ConvertFrom-JwtToken -Token $token
        PS > $decoded.Header.alg
        PS > $decoded.Payload.sub
        PS > $decoded.Payload.name

        Decodes a token and accesses specific header and payload properties.

    .OUTPUTS
        PSCustomObject with properties:
        - Header: Decoded JWT header as a PowerShell object
        - Payload: Decoded JWT payload as a PowerShell object
        - Signature: Raw signature string (only if -IncludeSignature is specified)

    .NOTES
        This function does NOT validate the JWT signature. It only decodes the token contents.
        For production authentication, always validate signatures using proper JWT libraries.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$Token,

        [Parameter()]
        [Switch]$IncludeSignature
    )

    begin
    {
        Write-Verbose 'Starting JWT token decoding'
    }

    process
    {
        try
        {
            # Trim whitespace from token
            $Token = $Token.Trim()

            # Split the JWT into its three parts
            $parts = $Token.Split('.')

            if ($parts.Count -ne 3)
            {
                throw "Invalid JWT token format. Expected 3 parts (header.payload.signature), found $($parts.Count) parts."
            }

            Write-Verbose 'JWT token has valid structure (3 parts)'

            # Function to decode Base64URL to string
            function ConvertFrom-Base64Url
            {
                param([String]$Base64Url)

                # Convert Base64URL to standard Base64
                $base64 = $Base64Url.Replace('-', '+').Replace('_', '/')

                # Add padding if necessary
                switch ($base64.Length % 4)
                {
                    0 { break }
                    2 { $base64 += '==' }
                    3 { $base64 += '=' }
                    default { throw 'Invalid Base64URL string' }
                }

                # Decode Base64 to bytes, then to UTF8 string
                $bytes = [System.Convert]::FromBase64String($base64)
                return [System.Text.Encoding]::UTF8.GetString($bytes)
            }

            # Decode header
            Write-Verbose 'Decoding JWT header'
            $headerJson = ConvertFrom-Base64Url -Base64Url $parts[0]
            $header = $headerJson | ConvertFrom-Json

            # Decode payload
            Write-Verbose 'Decoding JWT payload'
            $payloadJson = ConvertFrom-Base64Url -Base64Url $parts[1]
            $payload = $payloadJson | ConvertFrom-Json

            # Build result object
            $result = [PSCustomObject]@{
                Header = $header
                Payload = $payload
            }

            # Add signature if requested
            if ($IncludeSignature)
            {
                Write-Verbose 'Including raw signature'
                $result | Add-Member -NotePropertyName 'Signature' -NotePropertyValue $parts[2]
            }

            Write-Verbose 'JWT token decoded successfully'
            return $result
        }
        catch
        {
            Write-Error "Failed to decode JWT token: $($_.Exception.Message)"
            throw $_
        }
    }

    end
    {
        Write-Verbose 'JWT token decoding completed'
    }
}
