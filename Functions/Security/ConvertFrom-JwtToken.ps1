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
        The alias 'decode-jwt' is created for this function if it does not already exist.

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

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Security/ConvertFrom-JwtToken.ps1
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
        $claimDescriptions = @{
            # Standard header claims
            'alg' = 'Signing algorithm'
            'typ' = 'Token type'
            'kid' = 'Key ID'
            'cty' = 'Content type'
            'x5t' = 'X.509 thumbprint'
            'x5c' = 'X.509 cert chain'
            'jwk' = 'JSON Web Key'
            'jku' = 'JWK set URL'
            'crit' = 'Critical headers'

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
            'groups' = 'Group IDs'
            'scope' = 'Scope'
            'scp' = 'Scopes'
            'azp' = 'Authorized party'
            'nonce' = 'Nonce'
            'auth_time' = 'Auth time'
            'acr' = 'Auth context'
            'amr' = 'Auth methods'
            'sid' = 'Session ID'
            'onprem_sid' = 'On-premises SID'
            'tenant' = 'Tenant'
            'tid' = 'Tenant ID'
            'oid' = 'Object ID'
            'deviceid' = 'Device ID'
            'upn' = 'User principal name'
            'unique_name' = 'Unique name'
            'appid' = 'App ID'
            'appidacr' = 'App auth context'
            'aio' = 'Azure AD internal'
            'ipaddr' = 'IP address'
            'rh' = 'Refresh token handle'
            'uti' = 'Unique token ID'
            'xms_ftd' = 'Family token device ID'
            'idp' = 'Identity provider'
            'puid' = 'Personal user ID'
            'altsecid' = 'Alternate security ID'
            'azpacr' = 'App auth context (legacy)'
            'at_hash' = 'Access token hash'
            'c_hash' = 'Auth code hash'
            's_hash' = 'State hash'
            'wids' = 'Directory role IDs'
            'hasgroups' = 'Has groups (overage)'
            '_claim_names' = 'Claim name map'
            '_claim_sources' = 'Claim sources'
            'xms_cc' = 'Client capabilities'
            'xms_mirid' = 'Managed identity resource ID'
            'ver' = 'Version'
        }

        $timestampClaims = @('iat', 'exp', 'nbf', 'auth_time', 'updated_at')

        function ConvertTo-NormalizedJwtToken
        {
            param([Parameter(Mandatory)][String]$InputToken)

            $normalizedToken = $InputToken.Trim()
            $normalizedToken = $normalizedToken -replace '^(?i:Bearer)\s+', ''
            $normalizedToken = [System.Text.RegularExpressions.Regex]::Replace($normalizedToken, '\s+', '')

            if ([String]::IsNullOrWhiteSpace($normalizedToken))
            {
                throw 'JWT token is empty after trimming whitespace.'
            }

            return $normalizedToken
        }

        function ConvertFrom-Base64UrlSegment
        {
            param(
                [Parameter(Mandatory)]
                [AllowEmptyString()]
                [String]$Base64Url,

                [Parameter(Mandatory)]
                [String]$SegmentName
            )

            if ([String]::IsNullOrEmpty($Base64Url))
            {
                throw "JWT $SegmentName segment is empty."
            }

            $normalizedSegment = $Base64Url.TrimEnd('=')

            if ($normalizedSegment -notmatch '^[A-Za-z0-9_-]+$')
            {
                throw "Invalid Base64URL encoding in the $SegmentName segment."
            }

            $base64 = $normalizedSegment.Replace('-', '+').Replace('_', '/')

            switch ($base64.Length % 4)
            {
                0 { break }
                2 { $base64 += '==' }
                3 { $base64 += '=' }
                default { throw "Invalid Base64URL length in the $SegmentName segment." }
            }

            try
            {
                $bytes = [System.Convert]::FromBase64String($base64)
                return [System.Text.Encoding]::UTF8.GetString($bytes)
            }
            catch
            {
                throw "Invalid Base64URL encoding in the $SegmentName segment. $($_.Exception.Message)"
            }
        }

        function ConvertFrom-JsonSegment
        {
            param(
                [Parameter(Mandatory)]
                [String]$Json,

                [Parameter(Mandatory)]
                [String]$SegmentName
            )

            if ([String]::IsNullOrWhiteSpace($Json))
            {
                throw "The $SegmentName segment decoded to an empty string."
            }

            try
            {
                return $Json | ConvertFrom-Json -ErrorAction Stop
            }
            catch
            {
                throw "Invalid JSON in the $SegmentName segment. $($_.Exception.Message)"
            }
        }

        function Get-JwtRelativeTimeText
        {
            param([Parameter(Mandatory)][DateTimeOffset]$TargetTime)

            $delta = $TargetTime - [DateTimeOffset]::UtcNow
            $absoluteDelta = $delta.Duration()

            if ($absoluteDelta.TotalDays -ge 1)
            {
                $quantity = [Math]::Floor($absoluteDelta.TotalDays)
                $unit = 'day'
            }
            elseif ($absoluteDelta.TotalHours -ge 1)
            {
                $quantity = [Math]::Floor($absoluteDelta.TotalHours)
                $unit = 'hour'
            }
            elseif ($absoluteDelta.TotalMinutes -ge 1)
            {
                $quantity = [Math]::Floor($absoluteDelta.TotalMinutes)
                $unit = 'minute'
            }
            else
            {
                $quantity = [Math]::Max([Math]::Floor($absoluteDelta.TotalSeconds), 0)
                $unit = 'second'
            }

            if ($quantity -ne 1)
            {
                $unit += 's'
            }

            if ($delta.TotalSeconds -lt 0)
            {
                return "expired $quantity $unit ago"
            }

            return "expires in $quantity $unit"
        }

        function Format-JwtTimestampValue
        {
            param(
                [Parameter(Mandatory)]
                [String]$ClaimName,

                [Parameter(Mandatory)]
                $Value,

                [Parameter(Mandatory)]
                [Boolean]$UseUtc
            )

            $unixSeconds = 0L

            if ($Value -is [String])
            {
                if (-not [Int64]::TryParse($Value, [ref]$unixSeconds))
                {
                    return $null
                }
            }
            elseif ($Value -is [SByte] -or
                $Value -is [Byte] -or
                $Value -is [Int16] -or
                $Value -is [UInt16] -or
                $Value -is [Int32] -or
                $Value -is [UInt32] -or
                $Value -is [Int64] -or
                $Value -is [UInt64] -or
                $Value -is [Single] -or
                $Value -is [Double] -or
                $Value -is [Decimal])
            {
                try
                {
                    $unixSeconds = [Int64]$Value
                }
                catch
                {
                    return $null
                }
            }
            else
            {
                return $null
            }

            try
            {
                $timestamp = [DateTimeOffset]::FromUnixTimeSeconds($unixSeconds)
            }
            catch
            {
                return $null
            }

            if ($UseUtc)
            {
                $formattedTime = $timestamp.UtcDateTime.ToString('M/d/yyyy h:mm:ss tt') + ' UTC'
            }
            else
            {
                $formattedTime = $timestamp.ToLocalTime().DateTime.ToString('M/d/yyyy h:mm:ss tt')
            }

            if ($ClaimName -eq 'exp')
            {
                $relativeTime = Get-JwtRelativeTimeText -TargetTime $timestamp
                return "$unixSeconds ($formattedTime, $relativeTime)"
            }

            return "$unixSeconds ($formattedTime)"
        }

        function Format-JwtValue
        {
            param(
                [Parameter(Mandatory)]
                [String]$ClaimName,

                [Parameter()]
                $Value,

                [Parameter(Mandatory)]
                [Boolean]$UseUtc
            )

            if ($timestampClaims -contains $ClaimName)
            {
                $timestampDisplay = Format-JwtTimestampValue -ClaimName $ClaimName -Value $Value -UseUtc:$UseUtc

                if ($null -ne $timestampDisplay)
                {
                    return $timestampDisplay
                }
            }

            if ($null -eq $Value)
            {
                return '<null>'
            }

            if ($Value -is [Boolean])
            {
                return $Value.ToString().ToLowerInvariant()
            }

            if ($Value -is [String])
            {
                return $Value
            }

            if ($Value -is [DateTime] -or $Value -is [DateTimeOffset])
            {
                return $Value.ToString('o')
            }

            $isComplexObject =
            $Value -is [PSCustomObject] -or
            $Value -is [System.Collections.IDictionary] -or
            ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [String]) -or
            ($Value -is [PSObject] -and
            $Value -isnot [ValueType] -and
            $Value.PSObject.Properties.Count -gt 0)

            if ($isComplexObject)
            {
                try
                {
                    return $Value | ConvertTo-Json -Compress -Depth 10
                }
                catch
                {
                    return [String]$Value
                }
            }

            return [String]$Value
        }

        function Write-JwtSection
        {
            param(
                [Parameter(Mandatory)]
                [String]$Title,

                [Parameter(Mandatory)]
                [Object]$Data,

                [Parameter(Mandatory)]
                [Boolean]$UseUtc
            )

            Write-Host $Title -ForegroundColor Green
            Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray

            $properties = @($Data.PSObject.Properties)

            if ($properties.Count -eq 0)
            {
                Write-Host '  <empty>' -ForegroundColor DarkGray
                Write-Host ''
                return
            }

            $maxPropertyWidth = ($properties.Name | Measure-Object -Maximum Length).Maximum
            $labelWidth = [Math]::Min([Math]::Max($maxPropertyWidth, 20), 28)

            foreach ($property in $properties)
            {
                $formattedValue = Format-JwtValue -ClaimName $property.Name -Value $property.Value -UseUtc:$UseUtc

                Write-Host ("  {0,-$labelWidth}: " -f $property.Name) -NoNewline -ForegroundColor Yellow
                Write-Host $formattedValue -NoNewline -ForegroundColor White

                if ($claimDescriptions.ContainsKey($property.Name))
                {
                    Write-Host "  # $($claimDescriptions[$property.Name])" -ForegroundColor DarkGray
                }
                else
                {
                    Write-Host ''
                }
            }

            Write-Host ''
        }
    }

    process
    {
        try
        {
            Write-Verbose 'Normalizing JWT token input'
            $Token = ConvertTo-NormalizedJwtToken -InputToken $Token

            # Split the JWT into its three parts
            $parts = $Token.Split('.')

            if ($parts.Count -ne 3)
            {
                throw "Invalid JWT token format. Expected 3 parts (header.payload.signature), found $($parts.Count) parts."
            }

            if ([String]::IsNullOrEmpty($parts[0]) -or [String]::IsNullOrEmpty($parts[1]))
            {
                throw 'Invalid JWT token format. Header and payload segments must not be empty.'
            }

            Write-Verbose 'JWT token has valid structure (3 parts)'

            # Decode header
            Write-Verbose 'Decoding JWT header'
            $headerJson = ConvertFrom-Base64UrlSegment -Base64Url $parts[0] -SegmentName 'header'
            $header = ConvertFrom-JsonSegment -Json $headerJson -SegmentName 'header'

            # Decode payload
            Write-Verbose 'Decoding JWT payload'
            $payloadJson = ConvertFrom-Base64UrlSegment -Base64Url $parts[1] -SegmentName 'payload'
            $payload = ConvertFrom-JsonSegment -Json $payloadJson -SegmentName 'payload'

            # Build result object
            $result = [PSCustomObject][ordered]@{
                Header = $header
                Payload = $payload
            }
            $result.PSObject.TypeNames.Insert(0, 'PwshProfile.JwtToken')

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

                Write-JwtSection -Title 'HEADER' -Data $header -UseUtc:$NoLocalTimeConversion
                Write-JwtSection -Title 'PAYLOAD' -Data $payload -UseUtc:$NoLocalTimeConversion

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
            $message = $_.Exception.Message

            if ($message -notlike 'Failed to decode JWT token*')
            {
                $message = "Failed to decode JWT token. $message"
            }

            throw [System.InvalidOperationException]::new($message, $_.Exception)
        }
    }

    end
    {
        Write-Verbose 'JWT token decoding completed'
    }
}

# Create 'decode-jwt' alias only if it doesn't already exist
if (-not (Get-Command -Name 'decode-jwt' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'decode-jwt' alias for ConvertFrom-JwtToken"
        Set-Alias -Name 'decode-jwt' -Value 'ConvertFrom-JwtToken' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "ConvertFrom-JwtToken: Could not create 'decode-jwt' alias: $($_.Exception.Message)"
    }
}
