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

        TIMESTAMP HANDLING:
        JWT timestamps (iat, exp, nbf) are stored as Unix epoch seconds in UTC per RFC 7519.
        When displaying formatted output, these are automatically converted to your local timezone
        with proper daylight saving time adjustment.

        CROSS-PLATFORM COMPATIBILITY:
        This function works on PowerShell 5.1+ across Windows, macOS, and Linux
        by using .NET Base64 conversion and JSON parsing.

        SECURITY NOTE:
        This function ONLY decodes the token - it does NOT validate the signature.
        Do not use decoded tokens for authentication without proper signature verification.

        Aliases:
        The alias 'jwt-decode' is created for this function if it does not already exist.

    .PARAMETER Token
        The JWT token string to decode. Can be provided as a string or via pipeline.
        Must be in the standard three-part format: header.payload.signature

    .PARAMETER IncludeSignature
        If specified, includes the raw signature component in the output.
        The signature is returned as-is (Base64URL encoded) without validation.

    .PARAMETER AsObject
        If specified, returns the decoded token as a PSCustomObject instead of displaying
        formatted output. Use this when you need to process the token programmatically or
        assign it to a variable for further processing.

    .PARAMETER NoLocalTimeConversion
        If specified, displays timestamps in UTC instead of converting to local time.
        By default, JWT timestamps (iat, exp, nbf) are converted from UTC to your local
        timezone with DST adjustment. Use this to see the original UTC values.

    .EXAMPLE
        PS > $token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        PS > ConvertFrom-JwtToken -Token $token

        ═══════════════════════════════════════════════════════════════
        JWT TOKEN DECODED
        ═══════════════════════════════════════════════════════════════

        HEADER
        ──────────────────────────────────────────────────────────────
        alg                 : HS256  # Signing algorithm
        typ                 : JWT  # Token type

        PAYLOAD
        ──────────────────────────────────────────────────────────────
        sub                 : 1234567890  # Subject
        name                : John Doe  # Full name
        iat                 : 1516239022 (1/17/2018 8:30:22 PM)  # Issued at

        ═══════════════════════════════════════════════════════════════

        Decodes a JWT token and displays it in formatted output with claim descriptions.

    .EXAMPLE
        PS > Get-Clipboard | ConvertFrom-JwtToken

        Decodes a JWT token from the clipboard and displays it with claim descriptions (default).

    .EXAMPLE
        PS > $jwt = ConvertFrom-JwtToken -Token $token -AsObject
        PS > $jwt.Payload.iat

        1516239022

        Decodes a token as an object and accesses the expiration claim.

    .EXAMPLE
        PS > ConvertFrom-JwtToken -Token $token -IncludeSignature

        ═══════════════════════════════════════════════════════════════
        JWT TOKEN DECODED
        ═══════════════════════════════════════════════════════════════

        HEADER
        ──────────────────────────────────────────────────────────────
        alg                 : HS256  # Signing algorithm
        typ                 : JWT  # Token type

        PAYLOAD
        ──────────────────────────────────────────────────────────────
        sub                 : 1234567890  # Subject
        name                : John Doe  # Full name
        iat                 : 1516239022 (1/17/2018 8:30:22 PM)  # Issued at

        SIGNATURE
        ──────────────────────────────────────────────────────────────
        SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c

        ═══════════════════════════════════════════════════════════════

        Decodes the token and includes the signature in the formatted output.

    .EXAMPLE
        PS > ConvertFrom-JwtToken -Token $token -NoLocalTimeConversion

        ═══════════════════════════════════════════════════════════════
        JWT TOKEN DECODED
        ═══════════════════════════════════════════════════════════════

        HEADER
        ──────────────────────────────────────────────────────────────
        alg                 : HS256  # Signing algorithm
        typ                 : JWT  # Token type

        PAYLOAD
        ──────────────────────────────────────────────────────────────
        sub                 : 1234567890  # Subject
        name                : John Doe  # Full name
        iat                 : 1516239022 (1/18/2018 1:30:22 AM UTC)  # Issued at

        ═══════════════════════════════════════════════════════════════

        Decodes the token and displays timestamps in UTC instead of local time.

    .EXAMPLE
        PS > $decoded = ConvertFrom-JwtToken -Token $token -AsObject
        PS > $decoded.Header.alg
        PS > $decoded.Payload.sub
        PS > $decoded.Payload.name

        Decodes a token as an object for programmatic access to properties.

    .EXAMPLE
        PS > $bearer = (Invoke-RestMethod -Uri 'https://dev.example.com/token').access_token
        PS > $claims = ConvertFrom-JwtToken -Token $bearer -AsObject
        PS > $claims.Payload.scope

        Pulls a bearer token from an OAuth test endpoint and inspects the granted scopes without pasting the token into external tools.

    .EXAMPLE
        PS > $jwt = Get-Content ./id_token.txt -Raw
        PS > $exp = (ConvertFrom-JwtToken -Token $jwt -AsObject).Payload.exp
        PS > [DateTimeOffset]::FromUnixTimeSeconds($exp).UtcDateTime

        Extracts the expiration timestamp from a stored ID token to automate refresh logic in CI/CD scripts.

    .OUTPUTS
        PSCustomObject with properties:
        - Header: Decoded JWT header as a PowerShell object
        - Payload: Decoded JWT payload as a PowerShell object
        - Signature: Raw signature string (only if -IncludeSignature is specified)

    .NOTES
        This function does NOT validate the JWT signature. It only decodes the token contents.
        For production authentication, always validate signatures using proper JWT libraries.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Security/ConvertFrom-JwtToken.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$Token,

        [Parameter()]
        [Switch]$IncludeSignature,

        [Parameter()]
        [Switch]$AsObject,

        [Parameter()]
        [Switch]$NoLocalTimeConversion
    )

    begin
    {
        Write-Verbose 'Starting JWT token decoding'

        # Define standard JWT claim descriptions (kept short to avoid line wrapping)
        $script:ClaimDescriptions = @{
            # Standard header claims
            'alg' = 'Signing algorithm'
            'typ' = 'Token type'
            'kid' = 'Key ID'
            'cty' = 'Content type'

            # Standard payload claims (RFC 7519)
            'iss' = 'Issuer'
            'sub' = 'Subject'
            'aud' = 'Audience'
            'exp' = 'Expiration time'
            'nbf' = 'Not valid before'
            'iat' = 'Issued at'
            'jti' = 'JWT ID'

            # Common custom claims
            'name' = 'Full name'
            'given_name' = 'First name'
            'family_name' = 'Last name'
            'email' = 'Email address'
            'email_verified' = 'Email verified'
            'phone_number' = 'Phone number'
            'phone_number_verified' = 'Phone verified'
            'preferred_username' = 'Username'
            'nickname' = 'Nickname'
            'picture' = 'Picture URL'
            'website' = 'Website'
            'gender' = 'Gender'
            'birthdate' = 'Birthdate'
            'zoneinfo' = 'Timezone'
            'locale' = 'Locale'
            'updated_at' = 'Updated at'
            'roles' = 'Roles'
            'scope' = 'Scope'
            'azp' = 'Authorized party'
            'nonce' = 'Nonce'
            'auth_time' = 'Auth time'
            'acr' = 'Auth context'
            'amr' = 'Auth methods'
            'sid' = 'Session ID'
            'tenant' = 'Tenant'
            'tid' = 'Tenant ID'
            'oid' = 'Object ID'
            'upn' = 'User principal name'
            'unique_name' = 'Unique name'
            'appid' = 'App ID'
            'ver' = 'Version'
        }
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

            # Return as object if requested, otherwise display formatted output (default)
            if ($AsObject)
            {
                Write-Output $result
            }
            else
            {
                # Display pretty formatted output (default behavior)
                Write-Host ''
                Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
                Write-Host '  JWT TOKEN DECODED' -ForegroundColor Cyan
                Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
                Write-Host ''

                Write-Host 'HEADER' -ForegroundColor Green
                Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
                $header.PSObject.Properties | ForEach-Object {
                    Write-Host "  $($_.Name.PadRight(20)): " -NoNewline -ForegroundColor Yellow
                    Write-Host $_.Value -NoNewline -ForegroundColor White

                    if ($script:ClaimDescriptions.ContainsKey($_.Name))
                    {
                        Write-Host "  # $($script:ClaimDescriptions[$_.Name])" -ForegroundColor DarkGray
                    }
                    else
                    {
                        Write-Host ''
                    }
                }
                Write-Host ''

                Write-Host 'PAYLOAD' -ForegroundColor Green
                Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
                $payload.PSObject.Properties | ForEach-Object {
                    Write-Host "  $($_.Name.PadRight(20)): " -NoNewline -ForegroundColor Yellow

                    # Special handling for timestamps (iat, exp, nbf)
                    if ($_.Name -in @('iat', 'exp', 'nbf') -and $_.Value -is [long])
                    {
                        if ($NoLocalTimeConversion)
                        {
                            # Display in UTC without conversion
                            $utcTime = [DateTimeOffset]::FromUnixTimeSeconds($_.Value).UtcDateTime
                            $formattedTime = $utcTime.ToString('M/d/yyyy h:mm:ss tt') + ' UTC'
                        }
                        else
                        {
                            # Convert to local time with proper timezone handling (including DST)
                            $localTime = [DateTimeOffset]::FromUnixTimeSeconds($_.Value).ToLocalTime().DateTime
                            $formattedTime = $localTime.ToString('M/d/yyyy h:mm:ss tt')
                        }

                        Write-Host "$($_.Value) " -NoNewline -ForegroundColor White
                        Write-Host "($formattedTime)" -NoNewline -ForegroundColor DarkGray

                        if ($script:ClaimDescriptions.ContainsKey($_.Name))
                        {
                            Write-Host "  # $($script:ClaimDescriptions[$_.Name])" -ForegroundColor DarkGray
                        }
                        else
                        {
                            Write-Host ''
                        }
                    }
                    else
                    {
                        Write-Host $_.Value -NoNewline -ForegroundColor White

                        if ($script:ClaimDescriptions.ContainsKey($_.Name))
                        {
                            Write-Host "  # $($script:ClaimDescriptions[$_.Name])" -ForegroundColor DarkGray
                        }
                        else
                        {
                            Write-Host ''
                        }
                    }
                }

                if ($IncludeSignature)
                {
                    Write-Host ''
                    Write-Host 'SIGNATURE' -ForegroundColor Green
                    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
                    Write-Host "  $($parts[2])" -ForegroundColor White
                }

                Write-Host ''
                Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
                Write-Host ''
            }
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

# Create 'jwt-decode' alias only if it doesn't already exist
if (-not (Get-Command -Name 'jwt-decode' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'jwt-decode' alias for ConvertFrom-JwtToken"
        Set-Alias -Name 'jwt-decode' -Value 'ConvertFrom-JwtToken' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "ConvertFrom-JwtToken: Could not create 'jwt-decode' alias: $($_.Exception.Message)"
    }
}
