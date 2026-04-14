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
        Excludes potentially ambiguous characters (0, O, o, 1, I, i, l) from the generated string.
        This is useful when the string will be manually typed or displayed.

    .PARAMETER IncludeSymbols
        Includes common symbols (!@#$%^&*) in addition to alphanumeric characters.

    .PARAMETER ExcludeCharacters
        An array of specific characters to exclude from the generated string.
        Each string entry is treated as one or more individual characters, so values like 'AB'
        exclude both 'A' and 'B'. This parameter allows fine-grained control over which
        characters should not appear.

    .PARAMETER IncludeCharacters
        An array of additional characters to include in the character pool beyond the standard
        alphanumeric and symbol sets. Each string entry is treated as one or more individual
        characters before being added to the available character pool, and exclusions are
        applied afterward.

    .PARAMETER NoAdjacentDuplicates
        Prevents the same character from appearing twice in a row (case-insensitive for letters).
        Characters may still repeat elsewhere in the string unless UniqueCharacters is also specified.

    .PARAMETER UniqueCharacters
        Samples characters without replacement so each character can appear at most once.
        Length cannot exceed the number of distinct characters available in the final pool.

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
        KnY9LJMcjB3YD9mYFueFZjmn68e7zem8e3Ldq9UkSmt5Qed7R9YBauT

        Returns a random 64-character string without ambiguous characters (0, O, o, 1, I, i, l).

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

    .EXAMPLE
        PS > New-RandomString -Length 16 -IncludeCharacters @('-', '_', '.', '+', '=')
        3-K.L9+MN=_7RbPZ

        Returns a 16-character string that includes custom ASCII characters in addition to standard alphanumeric characters.

    .EXAMPLE
        PS > New-RandomString -Length 12 -IncludeCharacters @('-', '_', '.') -ExcludeAmbiguous
        K9m-L_w.S3hY

        Returns a 12-character string with custom separator characters, excluding ambiguous characters.

    .EXAMPLE
        PS > New-RandomString -Length 20 -IncludeCharacters @('+', '=', '%') -IncludeSymbols
        K9+L*w@S3h=Y2m8%!xQ

        Returns a 20-character string including custom characters and symbols for applications requiring special formatting.

    .EXAMPLE
        PS > New-RandomString -Length 10 -IncludeCharacters @('+', '=', '%', '~') -ExcludeCharacters @('0', '1', 'O', 'I')
        +P4M=~h8K

        Returns a 10-character string with custom characters, excluding potentially confusing characters.

    .EXAMPLE
        PS > New-RandomString -Length 24 -NoAdjacentDuplicates
        dM9qX2sN7bV4kR8wT3yH6cP1

        Returns a random 24-character string with no repeated adjacent characters.

    .EXAMPLE
        PS > New-RandomString -Length 10 -IncludeCharacters @('-', '_', '.') -NoAdjacentDuplicates
        t-3_.W9a-K

        Returns a random 10-character string that prevents adjacent duplicates while allowing
        custom separator characters.

    .EXAMPLE
        PS > New-RandomString -Length 12 -UniqueCharacters -ExcludeAmbiguous
        4wBz9rQ2TmYk

        Returns a random 12-character string where every character is unique.

    .EXAMPLE
        PS > $secret = New-RandomString -Length 48 -IncludeSymbols -Secure
        PS > dotnet user-secrets set 'Api:SharedSecret' $secret

        Generates a cryptographically strong API secret and stuffs it directly into the ASP.NET Core user secrets store so it never touches disk.

    .EXAMPLE
        PS > $suffix = New-RandomString -Length 6 -ExcludeAmbiguous
        PS > az storage account create --name "app$suffix" --resource-group Dev

        Uses a short random suffix to produce unique resource names when scripting deployments in Azure.

    .OUTPUTS
        System.String
        Returns a string of random characters based on the specified parameters.
        Character set includes alphanumeric characters, optionally symbols, and any custom characters
        specified via the IncludeCharacters parameter.

    .NOTES
        - Compatible with PowerShell Desktop 5.1+ and PowerShell Core 6+
        - Works on Windows, macOS, and Linux
        - The -Secure parameter provides cryptographically strong randomness
        - For general use cases, the default (non-secure) method is sufficient

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/New-RandomString.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/New-RandomString.ps1

    .LINK
        https://jonlabelle.com/snippets/view/powershell/generate-random-string-in-powershell
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Position = 0)]
        [ValidateRange(1, 10000)]
        [int] $Length = 32,

        [Parameter()]
        [Alias('NoAmbiguous')]
        [switch] $ExcludeAmbiguous,

        [Parameter()]
        [ValidateNotNull()]
        [string[]] $ExcludeCharacters = @(),

        [Parameter()]
        [ValidateNotNull()]
        [string[]] $IncludeCharacters = @(),

        [Parameter()]
        [switch] $IncludeSymbols,

        [Parameter()]
        [switch] $NoAdjacentDuplicates,

        [Parameter()]
        [Alias('WithoutReplacement')]
        [switch] $UniqueCharacters,

        [Parameter()]
        [switch] $Secure
    )

    # Build character set based on parameters
    if ($ExcludeAmbiguous)
    {
        # Exclude ambiguous characters: 0, 1, O, I, l, o, i
        $numbers = @('2', '3', '4', '5', '6', '7', '8', '9')
        $uppercaseLetters = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'M', 'N', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')
        $lowercaseLetters = @('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'j', 'k', 'm', 'n', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z')
    }
    else
    {
        # Include all standard alphanumeric characters
        $numbers = @('0', '1', '2', '3', '4', '5', '6', '7', '8', '9')
        $uppercaseLetters = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')
        $lowercaseLetters = @('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z')
    }

    $symbols = @('!', '@', '#', '$', '%', '^', '&', '*')

    $characterPool = New-Object 'System.Collections.Generic.List[string]'
    $seenCharacters = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

    $addCharacters = {
        param ([string[]] $Values)

        foreach ($value in $Values)
        {
            if ([string]::IsNullOrEmpty($value))
            {
                continue
            }

            foreach ($character in $value.ToCharArray())
            {
                $stringCharacter = [string] $character
                if ($seenCharacters.Add($stringCharacter))
                {
                    [void] $characterPool.Add($stringCharacter)
                }
            }
        }
    }

    & $addCharacters $numbers
    & $addCharacters $uppercaseLetters
    & $addCharacters $lowercaseLetters

    if ($IncludeSymbols)
    {
        & $addCharacters $symbols
    }

    $normalizedIncludeCharacters = New-Object 'System.Collections.Generic.List[string]'
    if ($IncludeCharacters.Count -gt 0)
    {
        foreach ($value in $IncludeCharacters)
        {
            if ([string]::IsNullOrEmpty($value))
            {
                continue
            }

            foreach ($character in $value.ToCharArray())
            {
                [void] $normalizedIncludeCharacters.Add([string] $character)
            }
        }

        if ($normalizedIncludeCharacters.Count -gt 0)
        {
            Write-Verbose "Including additional characters: $($normalizedIncludeCharacters.ToArray() -join ', ')"
            & $addCharacters $normalizedIncludeCharacters.ToArray()
        }
    }

    if ($ExcludeCharacters.Count -gt 0)
    {
        $normalizedExclusions = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

        foreach ($value in $ExcludeCharacters)
        {
            if ([string]::IsNullOrEmpty($value))
            {
                continue
            }

            foreach ($character in $value.ToCharArray())
            {
                [void] $normalizedExclusions.Add([string] $character)
            }
        }

        if ($normalizedExclusions.Count -gt 0)
        {
            Write-Verbose "Excluding characters: $(@($normalizedExclusions) -join ', ')"

            $filteredCharacterPool = New-Object 'System.Collections.Generic.List[string]'
            foreach ($character in $characterPool)
            {
                if (-not $normalizedExclusions.Contains($character))
                {
                    [void] $filteredCharacterPool.Add($character)
                }
            }

            $characterPool = $filteredCharacterPool
        }
    }

    if ($characterPool.Count -eq 0)
    {
        throw 'All available characters have been excluded. Please reduce the exclusion list.'
    }

    Write-Verbose "Character pool size: $($characterPool.Count)"

    # Convert to array for better performance
    $characters = $characterPool.ToArray()
    $adjacencyComparer = [System.StringComparer]::OrdinalIgnoreCase

    if ($UniqueCharacters -and $Length -gt $characters.Length)
    {
        throw "Length ($Length) exceeds the number of unique characters available in the pool ($($characters.Length)). Reduce -Length or widen the character pool."
    }

    if ($NoAdjacentDuplicates -and $Length -gt 1)
    {
        $adjacentDistinctCharacters = New-Object 'System.Collections.Generic.HashSet[string]' ($adjacencyComparer)
        foreach ($character in $characters)
        {
            [void] $adjacentDistinctCharacters.Add($character)
        }

        if ($adjacentDistinctCharacters.Count -lt 2)
        {
            throw 'At least two distinct characters are required when using -NoAdjacentDuplicates with a length greater than 1.'
        }
    }

    # Generate the random string
    $result = [System.Text.StringBuilder]::new($Length)

    $rng = $null
    $bytes = $null
    $useSecureRandom = $false

    try
    {
        if ($Secure)
        {
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
                $useSecureRandom = $true
            }
            catch
            {
                # If secure random generation fails, fall back to standard Get-Random
                Write-Warning "Secure random generation failed, falling back to Get-Random: $($_.Exception.Message)"
                $useSecureRandom = $false
            }
        }

        $getRandomIndex = {
            param ([int] $MaximumExclusive)

            if ($MaximumExclusive -le 0)
            {
                throw 'Random selection requires a positive maximum value.'
            }

            if ($useSecureRandom)
            {
                $exclusiveLimit = [uint32] $MaximumExclusive
                do
                {
                    $rng.GetBytes($bytes)
                    $randomValue = [BitConverter]::ToUInt32($bytes, 0)
                } while ($randomValue -ge ([uint32]::MaxValue - ([uint32]::MaxValue % $exclusiveLimit)))

                return [int] ($randomValue % $exclusiveLimit)
            }

            return Get-Random -Minimum 0 -Maximum $MaximumExclusive
        }

        if ($UniqueCharacters -and $NoAdjacentDuplicates)
        {
            $availableCharacters = New-Object 'System.Collections.Generic.List[string]'
            foreach ($character in $characters)
            {
                [void] $availableCharacters.Add($character)
            }

            $previousCharacter = $null

            for ($i = 0; $i -lt $Length; $i++)
            {
                $candidateIndices = New-Object 'System.Collections.Generic.List[int]'
                for ($candidateIndex = 0; $candidateIndex -lt $availableCharacters.Count; $candidateIndex++)
                {
                    if ($null -ne $previousCharacter -and $adjacencyComparer.Equals($availableCharacters[$candidateIndex], $previousCharacter))
                    {
                        continue
                    }

                    [void] $candidateIndices.Add($candidateIndex)
                }

                if ($candidateIndices.Count -eq 0)
                {
                    throw 'Unable to satisfy -UniqueCharacters and -NoAdjacentDuplicates with the available character pool. Reduce -Length or widen the character pool.'
                }

                $selectedCandidate = & $getRandomIndex $candidateIndices.Count
                $selectedIndex = $candidateIndices[$selectedCandidate]
                $selectedCharacter = $availableCharacters[$selectedIndex]

                [void] $result.Append($selectedCharacter)
                $availableCharacters.RemoveAt($selectedIndex)
                $previousCharacter = $selectedCharacter
            }
        }
        elseif ($UniqueCharacters)
        {
            $availableCharacters = [string[]] $characters.Clone()

            for ($i = 0; $i -lt $Length; $i++)
            {
                $swapOffset = & $getRandomIndex ($availableCharacters.Length - $i)
                $swapIndex = $i + $swapOffset

                if ($swapIndex -ne $i)
                {
                    $currentCharacter = $availableCharacters[$i]
                    $availableCharacters[$i] = $availableCharacters[$swapIndex]
                    $availableCharacters[$swapIndex] = $currentCharacter
                }

                [void] $result.Append($availableCharacters[$i])
            }
        }
        elseif ($NoAdjacentDuplicates)
        {
            $previousCharacter = $null

            for ($i = 0; $i -lt $Length; $i++)
            {
                if ($null -eq $previousCharacter)
                {
                    $index = & $getRandomIndex $characters.Length
                }
                else
                {
                    $candidateIndices = New-Object 'System.Collections.Generic.List[int]'
                    for ($candidateIndex = 0; $candidateIndex -lt $characters.Length; $candidateIndex++)
                    {
                        if ($adjacencyComparer.Equals($characters[$candidateIndex], $previousCharacter))
                        {
                            continue
                        }

                        [void] $candidateIndices.Add($candidateIndex)
                    }

                    $selectedCandidate = & $getRandomIndex $candidateIndices.Count
                    $index = $candidateIndices[$selectedCandidate]
                }

                $selectedCharacter = $characters[$index]
                [void] $result.Append($selectedCharacter)
                $previousCharacter = $selectedCharacter
            }
        }
        else
        {
            # Use standard sampling with replacement for default random-string behavior
            for ($i = 0; $i -lt $Length; $i++)
            {
                $randomIndex = & $getRandomIndex $characters.Length
                [void] $result.Append($characters[$randomIndex])
            }
        }
    }
    finally
    {
        if ($rng) { $rng.Dispose() }
    }

    return $result.ToString()
}

# Create 'New-Password' alias only if it doesn't already exist
if (-not (Get-Command -Name 'New-Password' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'New-Password' alias for New-RandomString"
        Set-Alias -Name 'New-Password' -Value 'New-RandomString' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "New-RandomString: Could not create 'New-Password' alias: $($_.Exception.Message)"
    }
}
