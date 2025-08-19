function New-RandomAlphaNumericString
{
    <#
    .SYNOPSIS
        Generates a random alphanumeric string of specified length.

    .DESCRIPTION
        This function generates a random string consisting of uppercase letters,
        lowercase letters, and numbers (0-9, A-Z, a-z). It's useful for creating
        random passwords, IDs, or other unique identifiers.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Length
        The length of the random string to generate.
        Default is 32 characters. Must be between 1 and 10000 characters.

    .PARAMETER ExcludeAmbiguous
        Excludes potentially ambiguous characters (0, O, 1, l, I) from the generated string.
        This is useful when the string will be manually typed or displayed.

    .PARAMETER IncludeSymbols
        Includes common symbols (!@#$%^&*) in addition to alphanumeric characters.

    .PARAMETER Secure
        Uses cryptographically secure random number generation instead of Get-Random.
        Recommended for passwords and security tokens.

    .EXAMPLE
        PS> New-RandomAlphaNumericString
        Returns a random 32-character alphanumeric string.

    .EXAMPLE
        PS> New-RandomAlphaNumericString -Length 16
        Returns a random 16-character alphanumeric string.

    .EXAMPLE
        PS> New-RandomAlphaNumericString -Length 64 -ExcludeAmbiguous
        Returns a random 64-character string without ambiguous characters.

    .EXAMPLE
        PS> New-RandomAlphaNumericString -Length 20 -IncludeSymbols -Secure
        Returns a 20-character string with symbols using secure random generation.

    .OUTPUTS
        System.String
        Returns a string of random characters based on the specified parameters.

    .NOTES
        - Compatible with PowerShell Desktop 5.1+ and PowerShell Core 6+
        - Works on Windows, macOS, and Linux
        - The -Secure parameter provides cryptographically strong randomness
        - For general use cases, the default (non-secure) method is sufficient

    .LINK
        https://jonlabelle.com/snippets/view/powershell/generate-random-alphanumeric-string-in-powershell
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

    # Convert to array for better performance
    $characters = [char[]]$characterPool

    # Generate the random string
    $result = [System.Text.StringBuilder]::new($Length)

    if ($Secure)
    {
        # Use cryptographically secure random number generation
        try
        {
            if ($PSVersionTable.PSVersion.Major -ge 6)
            {
                # PowerShell Core 6+ - use System.Security.Cryptography.RandomNumberGenerator
                $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            }
            else
            {
                # PowerShell Desktop 5.1 - use RNGCryptoServiceProvider
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
