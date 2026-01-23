# Dot source all functions
$functions = @(Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Functions') -Filter '*-*.ps1' -File -Recurse)
foreach ($function in $functions)
{
    Write-Verbose ('Loading profile function: {0}' -f $function.FullName)
    . $function.FullName
}

# Custom prompt function
function Prompt
{
    $psVersionTitle = "PowerShell $($PSEdition) $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
    $host.UI.RawUI.WindowTitle = "$psVersionTitle"
    Write-Host 'PS' -ForegroundColor 'Cyan' -NoNewline
    return ' > '
}

# Show the profile path in the console when in interactive mode
if ($Host.UI.RawUI -and [Environment]::UserInteractive)
{
    Write-Verbose 'User profile loaded: '
    Write-Verbose "$PSCommandPath"
    Write-Verbose ''
}
