function New-RandomString
{
    <#
    .SYNOPSIS
        Generates a random string of specified length.

    .DESCRIPTION
        This function generates a random string consisting of uppercase letters,
        lowercase letters, and numbers (0-9, A-Z, a-z). When the IncludeSymbols
        parameter is specified, it can also include common symbols (!@#$%^&*).
        It's useful for creating random passwords, IDs, tokens, or other unique identifiers.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Length
        The length of the random string to generate.
        Default is 32 characters. Must be between 1 and 10000 characters.

    .PARAMETER ExcludeAmbiguous
        Excludes potentially ambiguous characters (0, O, 1, l, I) from the generated string.
        This is useful when the string will be manually typed or displayed.

    .PARAMETER IncludeSymbols
        Includes common symbols (!@#$%^&*) in addition to alphanumeric characters.

    .PARAMETER ExcludeCharacters
        An array of specific characters to exclude from the generated string.
        This parameter allows fine-grained control over which characters should not appear.

    .PARAMETER Secure
        Uses cryptographically secure random number generation instead of Get-Random.
        Recommended for passwords and security tokens.

    .EXAMPLE
        PS > New-RandomString
        fwRXOU9o0s7sx4cZYzVMiWJGJoKsOG3b

        Returns a random 32-character string using alphanumeric characters.

    .EXAMPLE
        PS > New-RandomString -Length 16
        p6w1J4ml47zhyFCh

        Returns a random 16-character string using alphanumeric characters.

    .EXAMPLE
        PS > New-RandomString -Length 64 -ExcludeAmbiguous
        KnY9LJMcjB3YD9mYFueFo4vGfZjmnoir68i7zemo8e3Ldq9UkSmt5Qed7R9YBauT

        Returns a random 64-character string without ambiguous characters (0, O, 1, l, I).

    .EXAMPLE
        PS > New-RandomString -Length 20 -IncludeSymbols -Secure
        eWOHlQvO^5P%0QU%vJ4o

        Returns a 20-character string including symbols using secure random generation.

    .EXAMPLE
        PS > New-RandomString -Length 12 -ExcludeCharacters @('0', '1', 'O', 'I')
        2lMWW4Sn26Jb

        Returns a 12-character string excluding the specified characters.

    .EXAMPLE
        PS > New-RandomString -Length 8 -IncludeSymbols -ExcludeCharacters @('!', '@', '#')
        XS6Z7%1h

        Returns an 8-character string including symbols but excluding '!', '@', and '#'.

    .OUTPUTS
        System.String
        Returns a string of random characters based on the specified parameters.
        Character set includes alphanumeric characters and optionally symbols.

    .NOTES
        - Compatible with PowerShell Desktop 5.1+ and PowerShell Core 6+
        - Works on Windows, macOS, and Linux
        - The -Secure parameter provides cryptographically strong randomness
        - For general use cases, the default (non-secure) method is sufficient

    .LINK
        https://jonlabelle.com/snippets/view/powershell/generate-random-string-in-powershell
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Position = 0)]
        [ValidateRange(1, 10000)]
        [int] $Length = 32,

        [Parameter()]
        [switch] $ExcludeAmbiguous,

        [Parameter()]
        [ValidateNotNull()]
        [string[]] $ExcludeCharacters = @(),

        [Parameter()]
        [switch] $IncludeSymbols,

        [Parameter()]
        [switch] $Secure
    )

    # Build character set based on parameters
    if ($ExcludeAmbiguous)
    {
        # Exclude ambiguous characters: 0, 1, O, I, l
        $numbers = @('2', '3', '4', '5', '6', '7', '8', '9')
        $uppercaseLetters = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')
        $lowercaseLetters = @('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z')
    }
    else
    {
        # Include all standard alphanumeric characters
        $numbers = @('0', '1', '2', '3', '4', '5', '6', '7', '8', '9')
        $uppercaseLetters = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')
        $lowercaseLetters = @('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z')
    }

    $symbols = @('!', '@', '#', '$', '%', '^', '&', '*')

    # Build the character pool
    $characterPool = @()
    $characterPool += $numbers
    $characterPool += $uppercaseLetters
    $characterPool += $lowercaseLetters

    if ($IncludeSymbols)
    {
        $characterPool += $symbols
    }

    # Apply custom character exclusions if specified
    if ($ExcludeCharacters.Count -gt 0)
    {
        Write-Verbose "Excluding characters: $($ExcludeCharacters -join ', ')"
        $characterPool = $characterPool | Where-Object { $_ -notin $ExcludeCharacters }

        # Validate that we still have characters left
        if ($characterPool.Count -eq 0)
        {
            throw 'All available characters have been excluded. Please reduce the exclusion list.'
        }

        Write-Verbose "Character pool size after exclusions: $($characterPool.Count)"
    }

    # Convert to array for better performance
    $characters = [char[]]$characterPool

    # Generate the random string
    $result = [System.Text.StringBuilder]::new($Length)

    if ($Secure)
    {
        # Use cryptographically secure random number generation
        try
        {
            # Use System.Security.Cryptography.RandomNumberGenerator for all modern PowerShell versions
            if ($PSVersionTable.PSVersion.Major -ge 6)
            {
                # PowerShell Core 6+ - use System.Security.Cryptography.RandomNumberGenerator
                $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            }
            else
            {
                # PowerShell Desktop 5.1 - use RNGCryptoServiceProvider for compatibility
                $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
            }

            $bytes = New-Object byte[] 4
            for ($i = 0; $i -lt $Length; $i++)
            {
                do
                {
                    $rng.GetBytes($bytes)
                    $randomValue = [BitConverter]::ToUInt32($bytes, 0)
                } while ($randomValue -ge ([uint32]::MaxValue - ([uint32]::MaxValue % $characters.Length)))

                $index = $randomValue % $characters.Length
                [void]$result.Append($characters[$index])
            }
        }
        catch
        {
            # If secure random generation fails, fall back to standard Get-Random
            Write-Verbose "Secure random generation failed, falling back to Get-Random: $($_.Exception.Message)"
            $result.Clear()

            for ($i = 0; $i -lt $Length; $i++)
            {
                $randomIndex = Get-Random -Minimum 0 -Maximum $characters.Length
                [void]$result.Append($characters[$randomIndex])
            }
        }
        finally
        {
            if ($rng) { $rng.Dispose() }
        }
    }
    else
    {
        # Use standard Get-Random for better performance in non-secure scenarios
        for ($i = 0; $i -lt $Length; $i++)
        {
            $randomIndex = Get-Random -Minimum 0 -Maximum $characters.Length
            [void]$result.Append($characters[$randomIndex])
        }
    }

    return $result.ToString()
}
