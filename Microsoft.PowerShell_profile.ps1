#
# Dot source all functions
$functions = @(Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot 'Functions') -Filter '*.ps1' -File -Depth 1 -ErrorAction 'SilentlyContinue')
foreach ($function in $functions)
{
    Write-Verbose ("Loading function(s) '{0}'" -f $function.FullName)
    . $function.FullName
}

<#
.SYNOPSIS
    Updates PowerShell profile to the latest version.

.LINK
    https://github.com/jonlabelle/pwsh-profile
#>
function Update-Profile
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param([switch] $Verbose)

    Write-Host -ForegroundColor Cyan 'Updating PowerShell profile...'

    # CD to this script's directory and update
    Push-Location -Path $PSScriptRoot
    git pull
    Pop-Location

    . Reload-Profile -Verbose:$Verbose
}

function Prompt
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()

    # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.2#add-a-customized-powershell-prompt
    # "PS > "
    Write-Host 'PS' -ForegroundColor 'Cyan' -NoNewline
    return ' > '
}

# (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

Write-Host -ForegroundColor DarkBlue -NoNewline 'User profile loaded: '
Write-Host -ForegroundColor Gray "$PSCommandPath"
