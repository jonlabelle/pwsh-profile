#
# Generate a random Alphanumeric string
# https://jonlabelle.com/snippets/view/powershell/generate-random-alphanumeric-string-in-powershell
function Get-RandomAlphaNumericString
{
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [int] $Length = 12
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
