#
# Dot source all functions
$functions = @(Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot 'Functions') -Filter '*.ps1' -File -Depth 1 -ErrorAction 'SilentlyContinue')
foreach ($function in $functions)
{
    Write-Verbose ("Loading function(s) '{0}'" -f $function.FullName)
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param([switch] $Verbose)

    Write-Host -ForegroundColor Cyan 'Updating PowerShell profile...'

    # CD to this script's directory and update
    Push-Location -Path $PSScriptRoot
    git pull
    Pop-Location

    . Reload-Profile -Verbose:$Verbose

    # Clear the update available flag
    if ($global:ProfileUpdatesAvailable)
    {
        Remove-Variable -Name ProfileUpdatesAvailable -Scope Global -ErrorAction SilentlyContinue
    }
}

#
# Function to check and prompt for profile updates interactively
function Invoke-ProfileUpdatePrompt
{
    <#
    .SYNOPSIS
        Prompts the user to update the profile if updates are available.

    .DESCRIPTION
        This function checks if the global ProfileUpdatesAvailable flag is set
        and prompts the user with a Y/N choice to update the profile immediately.
        This must be called from the main thread, not from an event handler.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    param()

    if ($global:ProfileUpdatesAvailable)
    {
        Write-Host 'Profile updates are available!' -ForegroundColor Yellow
        $response = Read-Host 'Would you like to update your profile now? (Y/N)'
        if ($response -match '^[Yy]([Ee][Ss])?$')
        {
            Update-Profile
        }
        else
        {
            Write-Host "Skipped profile update. You can run 'Update-Profile' later to get the latest changes." -ForegroundColor Gray
            Remove-Variable -Name ProfileUpdatesAvailable -Scope Global -ErrorAction SilentlyContinue
        }
    }
    else
    {
        Write-Host 'No profile updates are currently available.' -ForegroundColor Green
    }
}

#
# Custom prompt function
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

#
# Check for profile updates in background (non-blocking) - only in interactive mode
if ($Host.UI.RawUI -and [Environment]::UserInteractive)
{
    try
    {
        $updateJob = Test-ProfileUpdate -Async -ErrorAction SilentlyContinue
        if ($updateJob)
        {
            # Register an event to handle the job completion
            Register-ObjectEvent -InputObject $updateJob -EventName StateChanged -Action {
                $job = $Event.Sender
                if ($job.State -eq 'Completed')
                {
                    $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

                    if ($result -eq $true)
                    {
                        # Set a global variable to signal that updates are available
                        # We can't use Read-Host in an event handler reliably
                        $global:ProfileUpdatesAvailable = $true

                        Write-Host 'Profile updates are available!' -ForegroundColor Yellow
                        Write-Host "Type 'Update-Profile' to update now, or ignore this message to update later." -ForegroundColor Gray
                    }
                }
                elseif ($job.State -eq 'Failed')
                {
                    # Clean up failed job silently
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                }
            } | Out-Null
        }
    }
    catch
    {
        # Silently ignore any errors during update check to avoid disrupting profile load
        Write-Debug "Profile update check failed: $($_.Exception.Message)"
    }
}
