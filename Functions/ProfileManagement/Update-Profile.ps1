function Update-Profile
{
    <#
    .SYNOPSIS
        Updates PowerShell profile to the latest version.

    .DESCRIPTION
        Updates the PowerShell profile by performing a git pull from the remote repository.
        If Git is not available, provides instructions for manual update using the install script.
        Requires a restart of the PowerShell session after updating to reload the profile.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .EXAMPLE
        PS > Update-Profile

        Updating PowerShell profile...
        Profile updated successfully! Restart your PowerShell session to reload your profile.

        Updates the profile from the git repository.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ProfileManagement/Update-Profile.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ProfileManagement/Update-Profile.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param()

    begin
    {
        Write-Verbose 'Starting Update-Profile'
    }

    process
    {
        Write-Host 'Updating PowerShell profile...' -ForegroundColor Cyan

        # Check if Git is available
        $gitCommand = Get-Command -Name git -ErrorAction SilentlyContinue
        if (-not $gitCommand)
        {
            $psExecutable = if ($PSVersionTable.PSVersion.Major -lt 6) { 'powershell' } else { 'pwsh' }

            Write-Host ''
            Write-Host 'Git is not installed or not found in PATH.' -ForegroundColor Yellow
            Write-Host 'To update your profile without Git, use the install.ps1 script:' -ForegroundColor Yellow
            Write-Host ''
            Write-Host "  irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-profile/main/install.ps1' |" -ForegroundColor Cyan
            Write-Host "      $psExecutable -NoProfile -ExecutionPolicy Bypass -" -ForegroundColor Cyan
            Write-Host ''
            Write-Host 'This will download and install the latest profile version.' -ForegroundColor Gray
            return
        }

        # Get the profile directory (parent of the Functions folder)
        $profilePath = $PROFILE
        if (-not $profilePath)
        {
            $profilePath = $PSCommandPath
        }

        $profileDirectory = Split-Path $profilePath -Parent

        # CD to profile directory and update
        Push-Location -Path $profileDirectory -ErrorAction 'Stop'

        try
        {
            $null = Start-Process -FilePath 'git' -ArgumentList 'pull', '--rebase', '--quiet' -WorkingDirectory $profileDirectory -Wait -NoNewWindow -PassThru
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

    end
    {
        Write-Verbose 'Update-Profile completed'
    }
}
