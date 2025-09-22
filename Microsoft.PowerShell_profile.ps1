#
# Dot source all functions
$functions = @(Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Functions') -Filter '*.ps1' -File -Depth 1 -ErrorAction 'SilentlyContinue')
foreach ($function in $functions)
{
    Write-Verbose ('Loading function: {0}' -f $function.FullName)
    . $function.FullName
}

#
# Function to update the profile from the git repository
function Update-Profile
{
    <#
    .SYNOPSIS
        Updates PowerShell profile to the latest version.

    .LINK
        https://github.com/jonlabelle/pwsh-profile
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param()

    Write-Host 'Updating PowerShell profile...' -ForegroundColor Cyan

    # CD to this script's directory and update
    Push-Location -Path $PSScriptRoot

    try
    {
        $null = Start-Process -FilePath 'git' -ArgumentList 'pull', '--rebase', '--quiet' -WorkingDirectory $PSScriptRoot -Wait -NoNewWindow -PassThru
    }
    catch
    {
        Write-Error "An error occurred while updating the profile: $($_.Exception.Message)"
        return
    }
    finally
    {
        Pop-Location
    }

    Write-Host 'Profile updated successfully! Restart your PowerShell session to reload your profile.' -ForegroundColor Green
}

#
# Custom prompt function
function Prompt
{
    param()

    # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.2#add-a-customized-powershell-prompt

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
