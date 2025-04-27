#
# Generate a random Alphanumeric string
# https://jonlabelle.com/snippets/view/powershell/generate-random-alphanumeric-string-in-powershell
function Get-RandomAlphaNumericString
{
    <#
    .SYNOPSIS
        Generates a random alphanumeric string of specified length.

    .DESCRIPTION
        This function generates a random string consisting of uppercase letters,
        lowercase letters, and numbers (0-9, A-Z, a-z). It's useful for creating
        random passwords, IDs, or other unique identifiers.

    .PARAMETER Length
        The length of the random string to generate.
        Default is 32 characters. Must be between 1 and 1024 characters.

    .EXAMPLE
        PS> Get-RandomAlphaNumericString
        Returns a random 32-character alphanumeric string.

    .EXAMPLE
        PS> Get-RandomAlphaNumericString -Length 16
        Returns a random 16-character alphanumeric string.

    .EXAMPLE
        PS> Get-RandomAlphaNumericString -Length 64
        Returns a random 64-character alphanumeric string.

    .OUTPUTS
        System.String
        Returns a string of random alphanumeric characters.

    .NOTES
        The function uses the Get-Random cmdlet for randomization. While suitable for
        most general purposes, it should not be used for cryptographic security needs.

    .LINK
        https://jonlabelle.com/snippets/view/powershell/generate-random-alphanumeric-string-in-powershell
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [int] $Length = 32
    )

    if ($Length -le 0)
    {
        throw "Length parameter must be greater than zero"
    }

    if ($Length -gt 1024)
    {
        throw "Length parameter cannot exceed 1024"
    }

    # Write-Output (-join ( (0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count $Length | ForEach-Object { [char]$_ }))

    # Adapted from: Using ForEach with a nested call to Get-Random on the input ranges is another way to avoid repeats:
    # https://gist.github.com/gregjhogan/2350eb60d02aa759c9d269c3fc6265b1?permalink_comment_id=4053128#gistcomment-4053128
    -join (1..$Length | ForEach-Object {[char]((0x30..0x39) + (0x41..0x5A) + (0x61..0x7A) | Get-Random)})
}
