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

        $defaultProfilePreservePaths = @('Functions/Local', 'Help', 'Modules', 'PSReadLine', 'Scripts', 'powershell.config.json')

        function Save-ProfilePreservedPaths
        {
            param(
                [Parameter(Mandatory)]
                [String]$SourceRoot,

                [Parameter(Mandatory)]
                [String[]]$PathsToPreserve
            )

            $tempRootName = 'pwsh-profile-preserve-{0}' -f ([Guid]::NewGuid().ToString())
            $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $tempRootName
            $preservedItems = @()

            foreach ($relativePath in $PathsToPreserve)
            {
                $sourcePath = Join-Path -Path $SourceRoot -ChildPath $relativePath
                if (Test-Path -Path $sourcePath)
                {
                    $destinationPath = Join-Path -Path $tempRoot -ChildPath $relativePath
                    $destinationParent = Split-Path -Parent $destinationPath
                    if ($destinationParent -and -not (Test-Path -Path $destinationParent))
                    {
                        New-Item -Path $destinationParent -ItemType Directory -Force | Out-Null
                    }

                    Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force
                    $preservedItems += [PSCustomObject]@{
                        Name = $relativePath
                        TempPath = $destinationPath
                        IsDirectory = Test-Path -Path $sourcePath -PathType Container
                    }
                }
            }

            if ($preservedItems.Count -eq 0)
            {
                if (Test-Path -Path $tempRoot)
                {
                    Remove-Item -Path $tempRoot -Recurse -Force
                }

                return $null
            }

            return [PSCustomObject]@{
                TempRoot = $tempRoot
                Items = $preservedItems
            }
        }

        function Restore-ProfilePreservedPaths
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$PreservationData,

                [Parameter(Mandatory)]
                [String]$DestinationRoot
            )

            foreach ($item in $PreservationData.Items)
            {
                $destinationPath = Join-Path -Path $DestinationRoot -ChildPath $item.Name
                Write-Verbose "Restoring preserved profile path '$($item.Name)'"
                if ($item.IsDirectory)
                {
                    if (-not (Test-Path -Path $destinationPath))
                    {
                        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
                    }

                    $preservedChildren = Get-ChildItem -Path $item.TempPath -Force
                    if ($preservedChildren)
                    {
                        Copy-Item -Path $preservedChildren.FullName -Destination $destinationPath -Recurse -Force
                    }
                }
                else
                {
                    $destinationParent = Split-Path -Parent $destinationPath
                    if ($destinationParent -and -not (Test-Path -Path $destinationParent))
                    {
                        New-Item -Path $destinationParent -ItemType Directory -Force | Out-Null
                    }

                    Copy-Item -Path $item.TempPath -Destination $destinationPath -Force
                }
            }

            if (Test-Path -Path $PreservationData.TempRoot)
            {
                Remove-Item -Path $PreservationData.TempRoot -Recurse -Force
            }
        }

        function Invoke-ProfileGit
        {
            param(
                [Parameter(Mandatory)]
                [String]$GitPath,

                [Parameter(Mandatory)]
                [String]$RepositoryRoot,

                [Parameter(Mandatory)]
                [String[]]$ArgumentList
            )

            $output = & $GitPath -C $RepositoryRoot @ArgumentList 2>&1
            return [PSCustomObject]@{
                ExitCode = $LASTEXITCODE
                Output = @($output)
            }
        }

        function Remove-ProfilePreservedWorkingTreePaths
        {
            param(
                [Parameter(Mandatory)]
                [String]$RepositoryRoot,

                [Parameter(Mandatory)]
                [String]$GitPath,

                [Parameter(Mandatory)]
                [PSCustomObject]$PreservationData
            )

            foreach ($item in $PreservationData.Items)
            {
                $relativePath = $item.Name
                $destinationPath = Join-Path -Path $RepositoryRoot -ChildPath $relativePath
                if (-not (Test-Path -Path $destinationPath))
                {
                    continue
                }

                $trackedResult = Invoke-ProfileGit -GitPath $GitPath -RepositoryRoot $RepositoryRoot -ArgumentList @('ls-files', '--', $relativePath)
                $trackedPaths = @($trackedResult.Output | Where-Object { $_ })

                if ($trackedPaths.Count -eq 0)
                {
                    Write-Verbose "Temporarily removing preserved untracked profile path '$relativePath'"
                    Remove-Item -Path $destinationPath -Recurse -Force
                    continue
                }

                $untrackedResult = Invoke-ProfileGit -GitPath $GitPath -RepositoryRoot $RepositoryRoot -ArgumentList @('ls-files', '--others', '--exclude-standard', '--', $relativePath)
                $ignoredResult = Invoke-ProfileGit -GitPath $GitPath -RepositoryRoot $RepositoryRoot -ArgumentList @('ls-files', '--others', '--ignored', '--exclude-standard', '--', $relativePath)
                $pathsToRemove = @($untrackedResult.Output + $ignoredResult.Output |
                        Where-Object { $_ } |
                        Sort-Object -Unique |
                        Sort-Object Length -Descending)

                foreach ($pathToRemove in $pathsToRemove)
                {
                    $fullPathToRemove = Join-Path -Path $RepositoryRoot -ChildPath $pathToRemove
                    if (Test-Path -Path $fullPathToRemove)
                    {
                        Write-Verbose "Temporarily removing preserved local profile item '$pathToRemove'"
                        Remove-Item -Path $fullPathToRemove -Recurse -Force
                    }
                }
            }
        }
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
        $gitPath = $gitCommand.Definition

        # Get the profile directory (parent of the Functions folder)
        $profilePath = $PROFILE
        if (-not $profilePath)
        {
            $profilePath = $PSCommandPath
        }

        $profileDirectory = Split-Path $profilePath -Parent

        $preservationData = Save-ProfilePreservedPaths -SourceRoot $profileDirectory -PathsToPreserve $defaultProfilePreservePaths
        if ($preservationData)
        {
            Write-Verbose "Preserved profile paths before update: $($preservationData.Items.Name -join ', ')"
            Remove-ProfilePreservedWorkingTreePaths -RepositoryRoot $profileDirectory -GitPath $gitPath -PreservationData $preservationData
        }

        # CD to profile directory and update
        Push-Location -Path $profileDirectory -ErrorAction 'Stop'

        try
        {
            $gitPull = Invoke-ProfileGit -GitPath $gitPath -RepositoryRoot $profileDirectory -ArgumentList @('pull', '--rebase', '--quiet')
            if ($gitPull.ExitCode -ne 0)
            {
                $gitOutput = ($gitPull.Output | Out-String).Trim()
                if (-not $gitOutput)
                {
                    $gitOutput = "git pull exited with code $($gitPull.ExitCode)."
                }

                Write-Error "Unable to update the profile: $gitOutput"
                return
            }
        }
        catch
        {
            Write-Error "An error occurred while updating the profile: $($_.Exception.Message)"
            return
        }
        finally
        {
            Pop-Location
            if ($preservationData)
            {
                Restore-ProfilePreservedPaths -PreservationData $preservationData -DestinationRoot $profileDirectory
            }
        }

        Write-Host 'Profile updated successfully! Restart your PowerShell session to reload your profile.' -ForegroundColor Green
    }

    end
    {
        Write-Verbose 'Update-Profile completed'
    }
}
