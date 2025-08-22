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

    Write-Host 'Updating PowerShell profile...' -ForegroundColor Cyan

    # CD to this script's directory and update
    Push-Location -Path $PSScriptRoot
    git pull --rebase
    Write-Host '' # Add a blank line for better readability
    Pop-Location

    . Reload-Profile -Verbose:$Verbose

    # Clear the update available flags
    Remove-Variable -Name ProfileUpdatesAvailable -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name ProfileUpdatePromptShown -Scope Global -ErrorAction SilentlyContinue
}

#
# Custom prompt function
function Prompt
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()

    # Check if profile updates are available and prompt user
    if ($global:ProfileUpdatesAvailable -and -not $global:ProfileUpdatePromptShown)
    {
        Write-Host ''  # Add a blank line for better readability
        Write-Host 'Profile updates are available!' -ForegroundColor Yellow

        # Show available changes
        try
        {
            Push-Location -Path $PSScriptRoot
            $gitLog = git log --oneline HEAD..origin/main 2>$null
            if ($gitLog)
            {
                Write-Host 'Here are the available changes:' -ForegroundColor Cyan
                foreach ($line in $gitLog)
                {
                    # Remove branch references and format as bullet point
                    $cleanLine = $line -replace '\s*\([^)]+\)\s*', ''
                    Write-Host "  • $cleanLine" -ForegroundColor Gray
                }
                Write-Host ''
            }
            Pop-Location
        }
        catch
        {
            # If we can't get the log, just continue with the prompt
            Write-Debug "Could not retrieve git log: $($_.Exception.Message)"
        }

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

        $global:ProfileUpdatePromptShown = $true
    }

    # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.2#add-a-customized-powershell-prompt
    # "PS > "
    Write-Host 'PS' -ForegroundColor 'Cyan' -NoNewline
    return ' > '
}

# (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

# Show the profile path in the console when in interactive mode
if ($Host.UI.RawUI -and [Environment]::UserInteractive)
{
    Write-Host 'User profile loaded: ' -ForegroundColor DarkBlue -NoNewline
    Write-Host "$PSCommandPath" -ForegroundColor Gray
    Write-Host '' # Add a blank line for better readability
}

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
                        # The prompt function will handle the user interaction
                        $global:ProfileUpdatesAvailable = $true

                        # Immediately show the notification instead of waiting for prompt
                        if ($Host.UI.RawUI -and [Environment]::UserInteractive)
                        {
                            try
                            {
                                # Show the notification immediately
                                Write-Host '' # Add a blank line
                                Write-Host 'Profile updates are available!' -ForegroundColor Yellow
                                Write-Host '' # Add a blank line

                                # Show available changes
                                Push-Location -Path (Split-Path -Parent $PSCommandPath) -ErrorAction SilentlyContinue
                                try
                                {
                                    $gitLog = git log --oneline HEAD..origin/main 2>$null
                                    if ($gitLog)
                                    {
                                        Write-Host 'Here are the available changes:' -ForegroundColor Cyan
                                        foreach ($line in $gitLog)
                                        {
                                            # Remove branch references and format as bullet point
                                            $cleanLine = $line -replace '\s*\([^)]+\)\s*', ''
                                            Write-Host "  • $cleanLine" -ForegroundColor Gray
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

                                Write-Host "Run 'Update-Profile' to install updates, or press any key to continue..." -ForegroundColor Cyan

                                # Set flag to prevent prompt from showing again
                                $global:ProfileUpdatePromptShown = $true
                            }
                            catch
                            {
                                # If immediate display fails, fall back to prompt-based approach
                                Write-Debug "Could not display immediate notification: $($_.Exception.Message)"
                            }
                        }
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
