#
# Generate a random Alphanumeric string
# https://jonlabelle.com/snippets/view/powershell/generate-random-alphanumeric-string-in-powershell
function Get-RandomAlphaNumericString
{
    [CmdletBinding()]
    [OutputType([String])]
    param ([int] $Length = 12)

    Write-Output (-join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count $Length | ForEach-Object { [char]$_ }))
}
