#
# Generate a random Alphanumeric string
# https://jonlabelle.com/snippets/view/powershell/generate-random-alphanumeric-string-in-powershell
function Get-RandomAlphanumericString
{
    [CmdletBinding()]
    Param ([int] $length = 12)

    Begin {}

    Process
    {
        Write-Output ( -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count $length | ForEach-Object { [char]$_ }))
    }
}
