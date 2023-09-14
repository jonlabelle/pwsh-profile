# $SCRIPT:shell = 'powershell'
# if ($PSVersionTable.PSVersion.Major -lt 6) { $SCRIPT:shell = 'WindowsPowerShell' }

$SCRIPT:IsWindowsPlatform = $false
if ([IO.Path]::DirectorySeparatorChar -eq '\')
{
    $SCRIPT:IsWindowsPlatform = $true
}

#
# Dot source all functions
$functions = @(Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot 'Functions') -Filter '*.ps1' -File -Depth 1 -ErrorAction 'SilentlyContinue')
foreach ($function in $functions)
{
    Write-Verbose ("Loading script '{0}'" -f $function.FullName)
    . $function.FullName
}

#
# Description: Helper function to show variable defined in the environment, that
# you declared, opposed to all global variables via `Get-Variable`.
#
# Usage:
#
#   To show variable declared by you:
#   PS> cmpv
#
#   To show all variables:
#   PS> $AutomaticVariables
#
# Link:
# https://4sysops.com/archives/display-and-search-all-variables-of-a-powershell-script-with-get-variable/#excluding-automatic-variables-in-get-variable
$AutomaticVariables = Get-Variable
function cmpv
{
    Compare-Object (Get-Variable) $AutomaticVariables -Property Name -PassThru | Where-Object -Property Name -NE 'AutomaticVariables'
}

function Prompt
{
    # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.2#add-a-customized-powershell-prompt
    # "PS > "
    Write-Host 'PS' -ForegroundColor 'Cyan' -NoNewline
    return ' > '
}

# (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

Write-Host -ForegroundColor DarkBlue -NoNewline 'User profile loaded: '
Write-Host -ForegroundColor Gray "$PSCommandPath"
