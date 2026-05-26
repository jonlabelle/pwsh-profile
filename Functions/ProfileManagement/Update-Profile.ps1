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

        # Resolve the repo root from this script's known location (Functions/ProfileManagement/)
        $profileDirectory = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath '..')))

        # Verify the directory is a git repository
        $gitDir = Join-Path -Path $profileDirectory -ChildPath '.git'
        if (-not (Test-Path -Path $gitDir))
        {
            Write-Error "Profile directory '$profileDirectory' is not a git repository. Cannot update."
            return
        }

        try
        {
            $commitBefore = & git -C $profileDirectory rev-parse HEAD 2>$null

            $gitOutput = & git -C $profileDirectory pull --rebase 2>&1
            if ($LASTEXITCODE -ne 0)
            {
                $gitOutput | ForEach-Object { Write-Host $_ }
                Write-Error "git pull failed with exit code $LASTEXITCODE."
                return
            }

            $commitAfter = & git -C $profileDirectory rev-parse HEAD 2>$null
        }
        catch
        {
            Write-Error "An error occurred while updating the profile: $($_.Exception.Message)"
            return
        }

        if ($commitBefore -eq $commitAfter)
        {
            Write-Host 'Profile is already up to date.' -ForegroundColor Green
        }
        else
        {
            $gitLog = & git -C $profileDirectory log --oneline "${commitBefore}..${commitAfter}" 2>$null
            if ($gitLog)
            {
                Write-Host ''
                Write-Host 'Updates:' -ForegroundColor Cyan
                Write-Host ''
                foreach ($line in $gitLog)
                {
                    $cleanLine = $line -replace '^\w+\s+', '' -replace '\s*\([^)]+\)\s*', ''
                    Write-Host "  - $cleanLine" -ForegroundColor Gray
                }
                Write-Host ''
            }

            Write-Host 'Profile updated successfully! Restart your PowerShell session to reload your profile.' -ForegroundColor Green
        }
    }

    end
    {
        Write-Verbose 'Update-Profile completed'
    }
}
