<#
    .SYNOPSIS
        Installs or restores the pwsh-profile configuration with automatic backups and optional directory preservation.

    .DESCRIPTION
        `install.ps1` detects the active PowerShell profile directory (Windows PowerShell 5.1 or PowerShell Core on macOS, Linux, and Windows),
        backs up the existing contents, preserves the `Functions/Local`, `Help`, `Modules`, `PSReadLine`, and `Scripts` folders by default, and then deploys the
        latest profile files from this repository (via `git clone`) or from a local path. You can also point the script at a previous backup to restore it.

        When installing from a remote repository, the script will use `git clone` if Git is available. If Git is not installed, it will
        automatically fall back to downloading and extracting the repository as a zip file from GitHub.

        Backups are created in the parent directory of your profile with the format: `{ProfileDirectory}-backup-{yyyyMMdd-HHmmss}`
        Example: `C:\Users\YourName\Documents\WindowsPowerShell-backup-20250116-143022`

        To restore from a backup, use: `pwsh -NoProfile -File ./install.ps1 -RestorePath 'path\to\backup'`

    .PARAMETER ProfileRoot
        Overrides the detected profile root directory (defaults to `Split-Path -Parent $PROFILE`).

    .PARAMETER RepositoryUrl
        Specifies the Git repository to clone when installing. Defaults to the main pwsh-profile repository.

    .PARAMETER LocalSourcePath
        Copies profile files from an existing local directory instead of cloning from Git.

    .PARAMETER BackupPath
        Optional explicit destination for the backup folder. When omitted a timestamped directory is created beside the profile.

    .PARAMETER SkipBackup
        Prevents the script from backing up the current profile directory before installing or restoring.

    .PARAMETER SkipPreserveDirectories
        Skips saving and restoring the `Functions/Local`, `Help`, `Modules`, `PSReadLine`, and `Scripts` directories during installation.

    .PARAMETER PreserveDirectories
        Overrides the list of directories to preserve/restore (defaults to `Functions/Local`, `Help`, `Modules`, `PSReadLine`, `Scripts`).

    .PARAMETER RestorePath
        When supplied, skips installation and restores the profile from the provided backup directory.

    .PARAMETER Force
        Reserved for future use. Currently behaves like the default run.

    .EXAMPLE
        PS > irm https://raw.githubusercontent.com/jonlabelle/pwsh-profile/main/install.ps1 | pwsh -NoProfile -ExecutionPolicy Bypass - -Verbose

        Downloads and runs the installer with PowerShell Core, producing verbose output.

    .EXAMPLE
        PS > irm 'https://raw.githubusercontent.com/jonlabelle/pwsh-profile/main/install.ps1' | powershell -NoProfile -ExecutionPolicy Bypass -

        Downloads and runs the installer for PowerShell Desktop.

    .EXAMPLE
        PS > pwsh -NoProfile -ExecutionPolicy Bypass -File ./install.ps1 -Verbose

        Installs from the GitHub repository. Uses git clone if Git is available, otherwise downloads and extracts as a zip file.

    .EXAMPLE
        PS > pwsh -NoProfile -ExecutionPolicy Bypass -File ./install.ps1 -LocalSourcePath (Get-Location)

        Installs the profile from an already-cloned local repository.

    .EXAMPLE
        PS > pwsh -NoProfile -ExecutionPolicy Bypass -File ./install.ps1 -RestorePath 'C:\Backups\WindowsPowerShell-backup-20250101-120000'

        Restores a previously backed-up profile directory.

    .EXAMPLE
        PS > pwsh -NoProfile -ExecutionPolicy Bypass -File ./install.ps1 -SkipBackup -SkipPreserveDirectories -PreserveDirectories @('Modules')

        Installs without creating a backup while only preserving the `Modules` directory.

    .EXAMPLE
        # List available backups
        PS > Get-ChildItem -Path (Split-Path -Parent $PROFILE) -Filter '*-backup-*' | Sort-Object Name -Descending

        # Restore from the most recent backup
        PS > pwsh -NoProfile -File ./install.ps1 -RestorePath 'C:\Users\YourName\Documents\WindowsPowerShell-backup-20250116-143022'

    .EXAMPLE
        PS > pwsh -NoProfile -ExecutionPolicy Bypass -File ./install.ps1 -LocalSourcePath (Get-Location) -WhatIf -Verbose

        Performs a dry run that shows which directories would be removed, backed up, preserved, or copied without actually changing anything.

    .NOTES
        The script will use `git` when available for cloning, otherwise it downloads the repository as a zip file.
        Run with `-Verbose` to see detailed progress, especially when preserving directories or restoring backups.

        Execution Policy (Windows only):
        On Windows, you may need to set the execution policy to load profile scripts. macOS and Linux do not enforce
        execution policies. If you encounter an execution policy error on Windows after installation, run this command
        in a regular PowerShell window (no administrator privileges required):

        PS > Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

        The CurrentUser scope affects only your user account and does not require administrator privileges.

        Parameter Conflicts:
        The following parameter combinations are not allowed and will produce clear error messages:
        - RestorePath cannot be used with LocalSourcePath or RepositoryUrl (restore vs. install)
        - LocalSourcePath cannot be used with RepositoryUrl (choose one installation source)
        - SkipPreserveDirectories cannot be used with PreserveDirectories (contradictory options)
        - RestorePath cannot be used with PreserveDirectories or SkipPreserveDirectories (restore doesn't preserve selectively)

    .LINK
        https://github.com/jonlabelle/pwsh-profile
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProfileRoot,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryUrl = 'https://github.com/jonlabelle/pwsh-profile.git',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LocalSourcePath,

    [Parameter()]
    [string]$BackupPath,

    [Parameter()]
    [switch]$SkipBackup,

    [Parameter()]
    [switch]$SkipPreserveDirectories,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$PreserveDirectories = @('Functions/Local', 'Help', 'Modules', 'PSReadLine', 'Scripts'),

    [Parameter()]
    [string]$RestorePath,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest

# Save current preferences and set error/progress preferences for the script
$savedErrorActionPreference = $ErrorActionPreference
$savedProgressPreference = $ProgressPreference

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Determine the appropriate PowerShell executable name
$psExecutable = if ($PSVersionTable.PSVersion.Major -lt 6) { 'powershell' } else { 'pwsh' }

# Used to restore the working directory after installation
$originalLocation = $null

function Test-ParameterConflicts
{
    <#
    .SYNOPSIS
        Validates that mutually exclusive parameters are not used together.

    .DESCRIPTION
        Checks for conflicting parameter combinations and throws clear error messages
        when incompatible parameters are used together.
    #>
    param()

    if ($RestorePath -and $LocalSourcePath)
    {
        Write-Error 'Cannot use both RestorePath and LocalSourcePath parameters together. Use RestorePath to restore from a backup, or LocalSourcePath to install from a local directory.'
        return $false
    }

    if ($RestorePath -and $RepositoryUrl -and $PSBoundParameters.ContainsKey('RepositoryUrl'))
    {
        Write-Error 'Cannot use both RestorePath and RepositoryUrl parameters together. Use RestorePath to restore from a backup, or RepositoryUrl to install from a Git repository.'
        return $false
    }

    if ($LocalSourcePath -and $RepositoryUrl -and $PSBoundParameters.ContainsKey('RepositoryUrl'))
    {
        Write-Error 'Cannot use both LocalSourcePath and RepositoryUrl parameters together. Use LocalSourcePath to install from a local directory, or RepositoryUrl to clone from a Git repository.'
        return $false
    }

    if ($SkipPreserveDirectories -and $PreserveDirectories -and $PSBoundParameters.ContainsKey('PreserveDirectories'))
    {
        Write-Error 'Cannot use both SkipPreserveDirectories and PreserveDirectories parameters together. Use SkipPreserveDirectories to skip preservation entirely, or PreserveDirectories to specify custom directories to preserve.'
        return $false
    }

    if ($RestorePath -and $PreserveDirectories -and $PSBoundParameters.ContainsKey('PreserveDirectories'))
    {
        Write-Error 'Cannot use both RestorePath and PreserveDirectories parameters together. RestorePath restores the entire backup directory without selective preservation.'
        return $false
    }

    if ($RestorePath -and $SkipPreserveDirectories)
    {
        Write-Error 'Cannot use both RestorePath and SkipPreserveDirectories parameters together. RestorePath restores the entire backup directory without selective preservation.'
        return $false
    }

    return $true
}

function Resolve-ProviderPath
{
    param(
        [Parameter(Mandatory)]
        [string]$PathToResolve
    )

    if (-not $PathToResolve)
    {
        throw 'Path cannot be empty.'
    }

    if ($PSCmdlet)
    {
        return $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PathToResolve)
    }

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PathToResolve)
}

function Get-DefaultProfileRoot
{
    param()

    if (-not $PROFILE)
    {
        throw 'Unable to determine $PROFILE for the current session.'
    }

    return Split-Path -Parent $PROFILE
}

function New-ProfileBackup
{
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter()]
        [string]$DestinationPath
    )

    if (-not (Test-Path -Path $SourcePath))
    {
        return $null
    }

    if (-not $DestinationPath)
    {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $DestinationPath = '{0}-backup-{1}' -f $SourcePath, $timestamp
    }

    $resolvedDestination = Resolve-ProviderPath -PathToResolve $DestinationPath
    Write-Verbose "Creating backup at $resolvedDestination"
    Copy-Item -Path $SourcePath -Destination $resolvedDestination -Recurse -Force
    return $resolvedDestination
}

function Save-PreservedDirectories
{
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string[]]$DirectoriesToPreserve
    )

    $tempRootName = 'pwsh-profile-preserve-{0}' -f ([guid]::NewGuid().ToString())
    $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $tempRootName
    $preservedItems = @()

    foreach ($directory in $DirectoriesToPreserve)
    {
        $sourceDirectory = Join-Path -Path $SourceRoot -ChildPath $directory
        if (Test-Path -Path $sourceDirectory -PathType Container)
        {
            $destinationDirectory = Join-Path -Path $tempRoot -ChildPath $directory
            Copy-Item -Path $sourceDirectory -Destination $destinationDirectory -Recurse -Force
            $preservedItems += [PSCustomObject]@{
                Name = $directory
                TempPath = $destinationDirectory
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

function Restore-PreservedDirectories
{
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$PreservationData,

        [Parameter(Mandatory)]
        [string]$DestinationRoot
    )

    foreach ($item in $PreservationData.Items)
    {
        $destinationDirectory = Join-Path -Path $DestinationRoot -ChildPath $item.Name
        Write-Verbose "Restoring preserved directory '$($item.Name)'"
        if (-not (Test-Path -Path $destinationDirectory))
        {
            New-Item -Path $destinationDirectory -ItemType Directory -Force | Out-Null
        }

        Copy-Item -Path (Join-Path -Path $item.TempPath -ChildPath '*') -Destination $destinationDirectory -Recurse -Force
    }

    if (Test-Path -Path $PreservationData.TempRoot)
    {
        Remove-Item -Path $PreservationData.TempRoot -Recurse -Force
    }
}

function Assert-DirectoryExists
{
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path))
    {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Test-ExecutionPolicyRequiresAction
{
    param()

    $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { $IsWindows }
    if (-not $isWindowsPlatform)
    {
        return $false
    }

    try
    {
        $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction Stop
    }
    catch
    {
        Write-Verbose "Unable to determine CurrentUser execution policy: $($_.Exception.Message)"
        return $true
    }

    if ([string]::IsNullOrEmpty($currentPolicy) -or $currentPolicy -eq 'Undefined')
    {
        return $true
    }

    $permissivePolicies = @('RemoteSigned', 'Unrestricted', 'Bypass')
    return -not ($permissivePolicies -contains $currentPolicy)
}

function Show-ExecutionPolicyGuidance
{
    param()

    if (-not (Test-ExecutionPolicyRequiresAction))
    {
        return
    }

    Write-Host 'If you encounter an execution policy error when PowerShell starts, run:' -ForegroundColor Yellow
    Write-Host '  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser' -ForegroundColor Gray
    Write-Host ''
}

function Invoke-RepositoryDownload
{
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    $parentDirectory = Split-Path -Parent $Destination
    if ($parentDirectory)
    {
        Assert-DirectoryExists -Path $parentDirectory
    }

    $gitCommand = Get-Command -Name git -ErrorAction SilentlyContinue
    if ($gitCommand)
    {
        Write-Verbose "Git found, cloning $Repository into $Destination"
        $gitExecutable = $gitCommand.Definition
        # Temporarily suppress error action to prevent Git's stderr from terminating in PS Desktop 5.1
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $gitOutput = & $gitExecutable clone --depth 1 $Repository $Destination 2>&1
        $ErrorActionPreference = $previousErrorAction

        if ($LASTEXITCODE -ne 0)
        {
            $errorMsg = "Git clone failed with exit code $LASTEXITCODE"
            if ($gitOutput)
            {
                $errorMsg += ". Git output: $($gitOutput -join '; ')"
            }
            throw $errorMsg
        }
        $gitOutput | ForEach-Object { Write-Verbose $_ }
    }
    else
    {
        Write-Verbose 'Git not found, downloading repository as zip archive'
        Invoke-ZipDownload -Repository $Repository -Destination $Destination
    }
}

function Invoke-ZipDownload
{
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    # Convert GitHub repository URL to zip download URL
    # https://github.com/user/repo.git -> https://github.com/user/repo/archive/refs/heads/main.zip
    $zipUrl = $Repository -replace '\.git$', '' -replace '$', '/archive/refs/heads/main.zip'

    $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "pwsh-profile-$([guid]::NewGuid().ToString('N')).zip"

    try
    {
        Write-Verbose "Downloading from $zipUrl"
        try
        {
            Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
        }
        catch
        {
            throw "Failed to download repository from $zipUrl : $($_.Exception.Message)"
        }

        Write-Verbose 'Extracting to temporary location'
        $tempExtract = Join-Path ([System.IO.Path]::GetTempPath()) "pwsh-profile-extract-$([guid]::NewGuid().ToString('N'))"
        try
        {
            Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
        }
        catch
        {
            throw "Failed to extract zip archive: $($_.Exception.Message)"
        }

        # GitHub zip archives contain a single top-level directory named {repo}-{branch}
        $extractedDir = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1

        if (-not $extractedDir)
        {
            throw 'Failed to find extracted content in zip archive'
        }

        Write-Verbose "Moving extracted content to $Destination"

        # Ensure parent directory exists first
        $parentDir = Split-Path -Parent $Destination
        Write-Verbose "Parent directory: $parentDir"

        if ($parentDir)
        {
            if (-not (Test-Path -Path $parentDir))
            {
                Write-Verbose 'Parent directory does not exist, creating it...'
                try
                {
                    $createdParent = New-Item -Path $parentDir -ItemType Directory -Force -ErrorAction Stop
                    Write-Verbose "Successfully created parent directory: $($createdParent.FullName)"
                }
                catch
                {
                    throw "Failed to create parent directory $parentDir : $($_.Exception.Message)"
                }

                # Verify parent was created
                if (-not (Test-Path -Path $parentDir -PathType Container))
                {
                    throw "Parent directory $parentDir does not exist after creation attempt"
                }
            }
            else
            {
                Write-Verbose "Parent directory already exists: $parentDir"
            }
        }

        # Ensure destination directory exists and is accessible
        Write-Verbose "Checking if destination exists: $Destination"
        if (-not (Test-Path -Path $Destination))
        {
            Write-Verbose 'Destination does not exist, creating it...'
            try
            {
                $createdDest = New-Item -Path $Destination -ItemType Directory -Force -ErrorAction Stop
                Write-Verbose "Successfully created destination directory: $($createdDest.FullName)"
            }
            catch
            {
                throw "Failed to create destination directory $Destination : $($_.Exception.Message)"
            }

            # Wait a moment for filesystem to catch up (Windows sometimes has delays)
            Start-Sleep -Milliseconds 100

            # Verify the directory was created successfully
            if (-not (Test-Path -Path $Destination -PathType Container))
            {
                throw "Destination directory $Destination does not exist after creation attempt. Parent exists: $(Test-Path -Path $parentDir)"
            }

            Write-Verbose 'Verified destination directory exists'
        }
        else
        {
            Write-Verbose "Destination directory already exists: $Destination"
        }

        try
        {
            # Copy all items from extracted directory into destination
            Write-Verbose "Source directory: $($extractedDir.FullName)"
            Write-Verbose "Destination directory: $Destination"
            Write-Verbose "Destination exists: $(Test-Path -Path $Destination)"

            # Copy each item individually to avoid path resolution issues on Windows
            Get-ChildItem -Path $extractedDir.FullName -Force | ForEach-Object {
                $itemName = $_.Name
                $sourcePath = $_.FullName
                $destPath = Join-Path -Path $Destination -ChildPath $itemName

                Write-Verbose "Copying: $itemName"

                if ($_.PSIsContainer)
                {
                    # For directories, ensure destination exists then copy contents
                    if (-not (Test-Path -Path $destPath))
                    {
                        New-Item -Path $destPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    }
                    Copy-Item -Path (Join-Path -Path $sourcePath -ChildPath '*') -Destination $destPath -Recurse -Force -ErrorAction Stop
                }
                else
                {
                    # For files, copy directly
                    Copy-Item -Path $sourcePath -Destination $destPath -Force -ErrorAction Stop
                }
            }
        }
        catch
        {
            # Provide detailed error information
            $errorDetails = "Failed to copy extracted files to $Destination"
            $errorDetails += "`n  Error: $($_.Exception.Message)"
            $errorDetails += "`n  Destination exists: $(Test-Path -Path $Destination)"
            if (Test-Path -Path $Destination)
            {
                $errorDetails += "`n  Destination is directory: $(Test-Path -Path $Destination -PathType Container)"
            }
            throw $errorDetails
        }

        # Cleanup
        Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
    finally
    {
        if (Test-Path -Path $tempZip)
        {
            Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
        }
    }
}

function Copy-LocalSource
{
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -Path $SourcePath -PathType Container))
    {
        throw "Local source path not found: $SourcePath"
    }

    Write-Verbose "Copying local source from $SourcePath to $DestinationPath"

    # Ensure parent directory exists first
    $parentDir = Split-Path -Parent $DestinationPath
    if ($parentDir -and -not (Test-Path -Path $parentDir))
    {
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        Write-Verbose "Created parent directory: $parentDir"
    }

    # Ensure destination directory exists and is accessible
    if (-not (Test-Path -Path $DestinationPath))
    {
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        Write-Verbose "Created destination directory: $DestinationPath"
    }

    # Verify the directory was created successfully
    if (-not (Test-Path -Path $DestinationPath -PathType Container))
    {
        throw "Destination directory $DestinationPath does not exist after creation attempt"
    }

    # Copy each item individually to avoid path resolution issues on Windows
    Get-ChildItem -Path $SourcePath -Force | ForEach-Object {
        $itemName = $_.Name
        $sourcePath = $_.FullName
        $destPath = Join-Path -Path $DestinationPath -ChildPath $itemName

        Write-Verbose "Copying: $itemName"

        if ($_.PSIsContainer)
        {
            # For directories, ensure destination exists then copy contents
            if (-not (Test-Path -Path $destPath))
            {
                New-Item -Path $destPath -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path (Join-Path -Path $sourcePath -ChildPath '*') -Destination $destPath -Recurse -Force
        }
        else
        {
            # For files, copy directly
            Copy-Item -Path $sourcePath -Destination $destPath -Force
        }
    }
}

function Restore-FromBackup
{
    param(
        [Parameter(Mandatory)]
        [string]$BackupSource,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path -Path $BackupSource -PathType Container))
    {
        throw "Backup path not found: $BackupSource"
    }

    if (Test-Path -Path $Destination)
    {
        Write-Verbose "Removing existing profile directory $Destination"
        Remove-Item -Path $Destination -Recurse -Force
    }

    Assert-DirectoryExists -Path $Destination

    Write-Verbose "Restoring profile from $BackupSource"
    Get-ChildItem -Path $BackupSource -Force | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $Destination -Recurse -Force
    }
}

# Only execute installation if the script is being run directly (not dot-sourced).
# This allows the script to be dot-sourced for testing individual functions without
# triggering the installation process.
if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.\s+')
{
    try
    {
        # Validate parameter combinations
        if (-not (Test-ParameterConflicts))
        {
            return
        }

        $resolvedProfileRoot = if ($ProfileRoot) { Resolve-ProviderPath -PathToResolve $ProfileRoot } else { Get-DefaultProfileRoot }
        Write-Verbose "Using profile root: $resolvedProfileRoot"

        # Safety check: If current directory is inside the profile directory that will be removed, switch to home directory
        if (-not $RestorePath -and (Test-Path -Path $resolvedProfileRoot))
        {
            $currentLocation = $PWD.Path
            $resolvedCurrent = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($currentLocation)
            $isInsideProfile = $resolvedCurrent -eq $resolvedProfileRoot -or $resolvedCurrent.StartsWith($resolvedProfileRoot + [System.IO.Path]::DirectorySeparatorChar)

            if ($isInsideProfile)
            {
                $originalLocation = $currentLocation
                $homeDirectory = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
                Write-Verbose "Current directory is inside profile directory. Temporarily switching to: $homeDirectory"
                Set-Location -Path $homeDirectory
            }
        }

        if ($RestorePath)
        {
            $resolvedRestorePath = Resolve-ProviderPath -PathToResolve $RestorePath
            if (-not $SkipBackup -and (Test-Path -Path $resolvedProfileRoot))
            {
                $createdBackup = New-ProfileBackup -SourcePath $resolvedProfileRoot -DestinationPath $BackupPath
                if ($createdBackup)
                {
                    Write-Host "Profile backup created at $createdBackup"
                }
            }

            Restore-FromBackup -BackupSource $resolvedRestorePath -Destination $resolvedProfileRoot
            Write-Host ''
            Write-Host 'Profile successfully restored from:' -ForegroundColor Green
            Write-Host "  $resolvedRestorePath" -ForegroundColor Cyan
            Write-Host ''
            Write-Host 'Please restart your PowerShell session to load the restored profile.' -ForegroundColor Yellow
            Write-Host ''

            # Only show execution policy guidance when action is required
            Show-ExecutionPolicyGuidance

            return
        }

        $preservationData = $null
        if (-not $SkipPreserveDirectories -and (Test-Path -Path $resolvedProfileRoot))
        {
            $preservationData = Save-PreservedDirectories -SourceRoot $resolvedProfileRoot -DirectoriesToPreserve $PreserveDirectories
            if ($preservationData)
            {
                Write-Host "Preserved directories: $($preservationData.Items.Name -join ', ')"
            }
        }

        $backupLocation = $null
        if (-not $SkipBackup -and (Test-Path -Path $resolvedProfileRoot))
        {
            $backupLocation = New-ProfileBackup -SourcePath $resolvedProfileRoot -DestinationPath $BackupPath
            if ($backupLocation)
            {
                Write-Host "Profile backup created at $backupLocation"
            }
        }

        if (Test-Path -Path $resolvedProfileRoot)
        {
            Write-Verbose "Removing existing profile directory $resolvedProfileRoot"
            try
            {
                Remove-Item -Path $resolvedProfileRoot -Recurse -Force -ErrorAction Stop
            }
            catch
            {
                # Check if the error is due to files being in use
                if ($_.Exception.Message -match 'being used by another process|cannot access|is in use')
                {
                    Write-Host ''
                    Write-Host 'ERROR: Cannot remove profile directory because files are currently in use.' -ForegroundColor Red
                    Write-Host ''
                    Write-Host 'This may be caused by:' -ForegroundColor Yellow
                    Write-Host '  - Files open in an editor (VS Code, Vim, etc.)' -ForegroundColor Gray
                    Write-Host '  - PowerShell sessions loading functions from the profile' -ForegroundColor Gray
                    Write-Host '  - Antivirus or backup software scanning the directory' -ForegroundColor Gray
                    Write-Host ''
                    Write-Host 'Please close any open files in the profile directory and try again.' -ForegroundColor Yellow
                    Write-Host ''
                    throw
                }
                # Re-throw other errors
                throw
            }
        }

        if ($LocalSourcePath)
        {
            $resolvedLocalSource = Resolve-ProviderPath -PathToResolve $LocalSourcePath
            Copy-LocalSource -SourcePath $resolvedLocalSource -DestinationPath $resolvedProfileRoot
        }
        else
        {
            Invoke-RepositoryDownload -Repository $RepositoryUrl -Destination $resolvedProfileRoot
        }

        if ($preservationData)
        {
            Restore-PreservedDirectories -PreservationData $preservationData -DestinationRoot $resolvedProfileRoot
        }

        Write-Host ''
        Write-Host 'PowerShell profile installed successfully at:' -ForegroundColor Green
        Write-Host "  $resolvedProfileRoot" -ForegroundColor Cyan
        Write-Host ''

        if ($backupLocation)
        {
            Write-Host 'Your previous profile was backed up to:' -ForegroundColor Yellow
            Write-Host "  $backupLocation" -ForegroundColor Cyan
            Write-Host ''
            Write-Host 'To restore from this backup:' -ForegroundColor Yellow
            Write-Host "  $psExecutable -NoProfile -File ./install.ps1 -RestorePath '$backupLocation'" -ForegroundColor Gray
            Write-Host ''
            Write-Host 'Or manually copy contents from the backup directory to:' -ForegroundColor Yellow
            Write-Host "  $resolvedProfileRoot" -ForegroundColor Gray
            Write-Host ''
        }
        else
        {
            Write-Host 'No backup was created (profile directory did not exist or -SkipBackup was used).' -ForegroundColor Gray
            Write-Host ''
        }

        Write-Host 'Please restart your PowerShell session to load the updated profile.' -ForegroundColor Yellow
        Write-Host ''

        # Only show execution policy guidance when action is required (macOS/Linux don't enforce execution policies)
        Show-ExecutionPolicyGuidance
    }
    catch
    {
        Write-Host ''
        Write-Host 'ERROR: Profile installation failed' -ForegroundColor Red
        Write-Host ''
        Write-Host 'Error details:' -ForegroundColor Yellow
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Gray
        Write-Host ''
        if ($_.Exception.InnerException)
        {
            Write-Host 'Inner exception:' -ForegroundColor Yellow
            Write-Host "  $($_.Exception.InnerException.Message)" -ForegroundColor Gray
            Write-Host ''
        }
        Write-Host 'If the issue persists, please report it at:' -ForegroundColor Yellow
        Write-Host '  https://github.com/jonlabelle/pwsh-profile/issues' -ForegroundColor Cyan
        Write-Host ''
        throw
    }
    finally
    {
        $ErrorActionPreference = $savedErrorActionPreference
        $ProgressPreference = $savedProgressPreference

        # Restore original location if it was changed
        if ($originalLocation -and (Test-Path -Path $originalLocation))
        {
            Write-Verbose "Restoring original location: $originalLocation"
            Set-Location -Path $originalLocation
        }
    }
}
