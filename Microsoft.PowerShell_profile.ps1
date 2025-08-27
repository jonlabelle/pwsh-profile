#
# Dot source all functions
$functions = @(Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Functions') -Filter '*.ps1' -File -Depth 1 -ErrorAction 'SilentlyContinue')
foreach ($function in $functions)
{
    Write-Verbose ('Loading function: {0}' -f $function.FullName)
    . $function.FullName
}

#
# Configures the prompt appearance
function ConfigurePrompt
{
    # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.2#add-a-customized-powershell-prompt

    # Determine PowerShell edition for window title
    $psVersionInfo = if ($PSVersionTable.PSVersion.Major -lt 6)
    {
        "PowerShell Desktop $($PSVersionTable.PSVersion)"
    }
    else
    {
        "PowerShell Core $($PSVersionTable.PSVersion)"
    }

    # $host.UI.RawUI.WindowTitle = "$psVersionInfo - $([System.Environment]::UserName)@$([System.Environment]::MachineName)"
    $host.UI.RawUI.WindowTitle = "$psVersionInfo"

    Write-Host 'PS' -ForegroundColor 'Cyan' -NoNewline
    return ' > '
}

#
# Custom prompt function
function Prompt
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()

    ConfigurePrompt
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
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

    # Clear any leftover update check variables
    Remove-Variable -Name ProfileUpdatesAvailable -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name ProfileUpdatePromptShown -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name ProfileUpdateCheckCompleted -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name ProfileUpdateCheckStarted -Scope Global -ErrorAction SilentlyContinue

    Write-Host 'Profile updated successfully! Run ''Reload-Profile'' to reload your profile.' -ForegroundColor Green
}

#
# Function to show profile update notification (non-blocking)
function Show-ProfileUpdateNotification
{
    <#
    .SYNOPSIS
        Shows a non-blocking notification about available profile updates.

    .DESCRIPTION
        This function displays information about available profile updates and prompts
        the user to decide whether to update. It can be called manually to check for
        and apply profile updates.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()

    try
    {
        # Show the update prompt
        Write-Host ''
        Write-Host 'Profile updates are available!' -ForegroundColor Yellow

        # Show available changes
        Push-Location -Path (Split-Path -Parent $PSCommandPath) -ErrorAction SilentlyContinue
        try
        {
            $gitLog = git log --oneline HEAD..origin/main 2>$null
            if ($gitLog)
            {
                Write-Host ''
                Write-Host 'Here are the available changes:' -ForegroundColor Cyan
                Write-Host ''
                foreach ($line in $gitLog)
                {
                    # Remove hash prefix and branch references, format as bullet point
                    $cleanLine = $line -replace '^\w+\s+', '' -replace '\s*\([^)]+\)\s*', ''
                    Write-Host "  - $cleanLine" -ForegroundColor Gray
                }
                Write-Host ''
            }
        }
        catch
        {
            Write-Debug "Could not retrieve git log: $($_.Exception.Message)"
        }
        finally
        {
            Pop-Location -ErrorAction SilentlyContinue
        }
    }
    catch
    {
        Write-Debug "Could not show profile update notification: $($_.Exception.Message)"
    }
}

# Show the profile path in the console when in interactive mode
if ($Host.UI.RawUI -and [Environment]::UserInteractive)
{
    Write-Verbose 'User profile loaded: '
    Write-Verbose "$PSCommandPath"
    Write-Verbose ''
}
