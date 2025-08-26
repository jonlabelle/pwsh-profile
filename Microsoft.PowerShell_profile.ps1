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
    # This handles notifications for PowerShell Desktop 5.1 where timer-based notifications may not be reliable
    if (-not $global:ProfileUpdatePromptShown)
    {
        if ($global:ProfileUpdateCheckCompleted -and $global:ProfileUpdatesAvailable)
        {
            # Updates were found by the timer - show full notification now
            # For PowerShell Desktop 5.1, this is the primary notification method
            # For PowerShell Core, this provides the full experience if user presses Enter after the brief notification
            if ($PSVersionTable.PSVersion.Major -lt 6 -or $PSVersionTable.PSVersion.Major -ge 6)
            {
                # Mark as shown immediately to prevent duplicate prompts
                $global:ProfileUpdatePromptShown = $true
                # Show the full notification with git log and Y/N prompt
                Show-ProfileUpdateNotification
                return ' > '  # Return early to avoid duplicate prompt output
            }
        }
        elseif (-not $global:ProfileUpdateCheckStarted -and $PSVersionTable.PSVersion.Major -lt 6)
        {
            # First time in prompt for PowerShell Desktop 5.1 - do a direct check
            $global:ProfileUpdateCheckStarted = $true

            try
            {
                # Import and run the update check function directly
                $testProfileUpdatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Functions\Test-ProfileUpdate.ps1'
                if (Test-Path -Path $testProfileUpdatePath)
                {
                    . $testProfileUpdatePath
                    # Use async version to avoid blocking the prompt
                    $updateJob = Test-ProfileUpdate -Async -ErrorAction SilentlyContinue

                    if ($updateJob)
                    {
                        # Store the job for later checking - don't block here
                        $global:ProfileUpdateJob = $updateJob
                        # We'll check this job result in the timer action instead
                    }
                    else
                    {
                        # Job creation failed, mark as checked to avoid future attempts
                        $global:ProfileUpdatePromptShown = $true
                    }
                }
                else
                {
                    # Function not found, mark as checked to avoid future attempts
                    $global:ProfileUpdatePromptShown = $true
                }
            }
            catch
            {
                # Error during check, mark as checked to avoid future attempts
                $global:ProfileUpdatePromptShown = $true
                Write-Debug "Profile update check failed: $($_.Exception.Message)"
            }
        }
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
        the user to decide whether to update. It's designed to be called asynchronously
        to avoid blocking the PowerShell session startup.
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
            Remove-Variable -Name ProfileUpdateCheckStarted -Scope Global -ErrorAction SilentlyContinue
        }

        # Force prompt to reappear
        prompt
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

#
# Check for profile updates in background (truly non-blocking) - only in interactive mode
if ($Host.UI.RawUI -and [Environment]::UserInteractive)
{
    # Store the profile root path in a way that's accessible to the timer event
    $script:ProfileRootForUpdateCheck = $PSScriptRoot

    # Use a completely deferred approach - schedule the update check to run after profile load
    # This ensures zero blocking during profile initialization
    $updateCheckAction = {
        try
        {
            # Get the profile root path from script scope
            $profileRoot = $script:ProfileRootForUpdateCheck
            if (-not $profileRoot)
            {
                $profileRoot = Split-Path -Parent $PSCommandPath
            }

            # Import the function we need
            $testProfileUpdatePath = Join-Path -Path $profileRoot -ChildPath 'Functions\Test-ProfileUpdate.ps1'
            if (Test-Path -Path $testProfileUpdatePath)
            {
                . $testProfileUpdatePath

                # Check if there's already a job from the prompt (PowerShell Desktop 5.1)
                $updateJob = $null
                $updateAvailable = $null

                if ($global:ProfileUpdateJob)
                {
                    $updateJob = $global:ProfileUpdateJob
                    # Clear the global variable
                    Remove-Variable -Name ProfileUpdateJob -Scope Global -ErrorAction SilentlyContinue
                }
                else
                {
                    # Run the actual update check asynchronously
                    $updateJob = Test-ProfileUpdate -Async -ErrorAction SilentlyContinue
                }

                if ($updateJob)
                {
                    # Wait for job completion with timeout (non-blocking for the timer context)
                    $jobResult = Wait-Job -Job $updateJob -Timeout 30
                    if ($jobResult)
                    {
                        $updateAvailable = Receive-Job -Job $updateJob -ErrorAction SilentlyContinue
                        Remove-Job -Job $updateJob -ErrorAction SilentlyContinue
                    }
                    else
                    {
                        # Timeout - clean up job
                        Remove-Job -Job $updateJob -Force -ErrorAction SilentlyContinue
                    }
                }

                if ($updateAvailable -eq $true)
                {
                    # Set global variables to signal updates are available
                    $global:ProfileUpdatesAvailable = $true
                    $global:ProfileUpdateCheckCompleted = $true

                    # For PowerShell Core, show immediate brief notification since prompt won't trigger automatically
                    # For PowerShell Desktop 5.1, rely on the prompt to show the full notification
                    if ($PSVersionTable.PSVersion.Major -ge 6)
                    {
                        try
                        {
                            # Schedule a simple notification to display after a short delay
                            $notificationTimer = New-Object System.Timers.Timer
                            $notificationTimer.Interval = 1000  # 1 second delay
                            $notificationTimer.AutoReset = $false
                            $notificationTimer.Enabled = $true

                            $notificationAction = {
                                try
                                {
                                    Write-Host ''
                                    Write-Host 'Profile updates are available!' -ForegroundColor Yellow
                                    Write-Host 'Press Enter and then run Update-Profile to see the changes and update.' -ForegroundColor Gray
                                    Write-Host ''
                                }
                                catch
                                {
                                    Write-Debug "Could not show notification: $($_.Exception.Message)"
                                }
                            }

                            Register-ObjectEvent -InputObject $notificationTimer -EventName Elapsed -Action $notificationAction
                        }
                        catch
                        {
                            Write-Debug "Could not set up notification timer: $($_.Exception.Message)"
                        }
                    }
                }
            }
            else
            {
                Write-Debug "Could not find Test-ProfileUpdate function at: $testProfileUpdatePath"
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
        $updateTimer.Interval = 3000  # 3 second delay - enough time for profile to fully load
        $updateTimer.AutoReset = $false
        $updateTimer.Enabled = $true

        # Register the event handler
        $eventRegistration = Register-ObjectEvent -InputObject $updateTimer -EventName Elapsed -Action $updateCheckAction

        # Store references so they don't get garbage collected
        $global:ProfileUpdateTimer = $updateTimer
        $global:ProfileUpdateEventSubscription = $eventRegistration

        # For debugging - let's add a simple test to see if the timer fires at all
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            Write-Debug 'Profile update check scheduled for PowerShell Desktop 5.1'
        }
    }
    catch
    {
        # If timer setup fails, silently ignore to avoid disrupting profile load
        Write-Debug "Could not set up profile update timer: $($_.Exception.Message)"
    }
}
