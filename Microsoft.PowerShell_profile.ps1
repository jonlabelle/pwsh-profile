#
# Dot source all functions
$functions = @(Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot 'Functions') -Filter '*.ps1' -File -Depth 1 -ErrorAction 'SilentlyContinue')
foreach ($function in $functions)
{
    Write-Verbose ('Loading function: {0}' -f $function.FullName)
    . $function.FullName
}

#
# Custom prompt function
function Prompt
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()

    # Check for profile updates that need to be displayed
    # This handles notifications for PowerShell Desktop 5.1 where timer-based notifications may not be visible
    if ($global:ProfileUpdateCheckCompleted -and $global:ProfileUpdatesAvailable -and -not $global:ProfileUpdatePromptShown)
    {
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # For PowerShell Desktop 5.1, show the full notification in the prompt
            Show-ProfileUpdateNotification
        }
        # PowerShell Core notifications are handled by the timer event, so no need to duplicate here
    }

    # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.2#add-a-customized-powershell-prompt
    # "PS > "
    Write-Host 'PS' -ForegroundColor 'Cyan' -NoNewline
    return ' > '
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

    # Clear the update available flags
    Remove-Variable -Name ProfileUpdatesAvailable -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name ProfileUpdatePromptShown -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name ProfileUpdateCheckCompleted -Scope Global -ErrorAction SilentlyContinue

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
        the user to decide whether to update. It's designed to be called asynchronously
        to avoid blocking the PowerShell session startup.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()

    if ($global:ProfileUpdatePromptShown)
    {
        return
    }

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

        $response = Read-Host 'Would you like to update your profile now? (Y/N)'
        if ($response -match '^[Yy]([Ee][Ss])?$')
        {
            Update-Profile
        }
        else
        {
            Write-Host "Skipped profile update. You can run 'Update-Profile' later to get the latest changes." -ForegroundColor Gray
            Remove-Variable -Name ProfileUpdatesAvailable -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name ProfileUpdateCheckCompleted -Scope Global -ErrorAction SilentlyContinue
        }

        # Force prompt to reappear
        prompt

        $global:ProfileUpdatePromptShown = $true
    }
    catch
    {
        Write-Debug "Could not show profile update notification: $($_.Exception.Message)"
    }
}

# (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

# Show the profile path in the console when in interactive mode
if ($Host.UI.RawUI -and [Environment]::UserInteractive)
{
    Write-Verbose 'User profile loaded: '
    Write-Verbose "$PSCommandPath"
    Write-Verbose ''
}

#
# Check for profile updates in background (truly non-blocking) - only in interactive mode
if ($Host.UI.RawUI -and [Environment]::UserInteractive)
{
    # Use a completely deferred approach - schedule the update check to run after profile load
    # This ensures zero blocking during profile initialization
    $updateCheckAction = {
        try
        {
            # Import the function we need
            $testProfileUpdatePath = Join-Path -Path $using:PSScriptRoot -ChildPath 'Functions\Test-ProfileUpdate.ps1'
            if (Test-Path -Path $testProfileUpdatePath)
            {
                . $testProfileUpdatePath

                # Run the actual update check
                $updateAvailable = Test-ProfileUpdate -ErrorAction SilentlyContinue

                if ($updateAvailable -eq $true)
                {
                    # Set global variables to signal updates are available
                    $global:ProfileUpdatesAvailable = $true
                    $global:ProfileUpdateCheckCompleted = $true

                    # For PowerShell Desktop 5.1, rely entirely on the prompt to show notifications
                    # For PowerShell Core, show an immediate brief notification
                    if ($PSVersionTable.PSVersion.Major -ge 6)
                    {
                        try
                        {
                            Write-Host 'Profile updates are available! Run Update-Profile to get the latest changes.' -ForegroundColor Yellow
                            $global:ProfileUpdatePromptShown = $true
                        }
                        catch
                        {
                            # If immediate notification fails, the prompt will handle it
                            Write-Debug "Could not show immediate notification: $($_.Exception.Message)"
                        }
                    }
                }
            }
        }
        catch
        {
            # Silently ignore errors to avoid disrupting user experience
            Write-Debug "Profile update check failed: $($_.Exception.Message)"
        }
    }

    # Schedule the update check to run after a short delay using a timer
    # This completely decouples it from profile loading
    try
    {
        $updateTimer = New-Object System.Timers.Timer
        $updateTimer.Interval = 2000  # 2 second delay - enough time for profile to fully load
        $updateTimer.AutoReset = $false
        $updateTimer.Enabled = $true

        # Register the event handler
        $eventRegistration = Register-ObjectEvent -InputObject $updateTimer -EventName Elapsed -Action $updateCheckAction

        # Store references so they don't get garbage collected
        $global:ProfileUpdateTimer = $updateTimer
        $global:ProfileUpdateEventSubscription = $eventRegistration
    }
    catch
    {
        # If timer setup fails, silently ignore to avoid disrupting profile load
        Write-Debug "Could not set up profile update timer: $($_.Exception.Message)"
    }
}
