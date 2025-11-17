<#
    .SYNOPSIS
        Installs or restores the pwsh-profile configuration with automatic backups and optional directory preservation.

    .DESCRIPTION
        `install.ps1` detects the active PowerShell profile directory (Windows PowerShell 5.1 or PowerShell Core on macOS, Linux, and Windows),
        backs up the existing contents, preserves the `Help`, `Modules`, `PSReadLine`, and `Scripts` folders by default, and then deploys the
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
        Skips saving and restoring the `Help`, `Modules`, `PSReadLine`, and `Scripts` directories during installation.

    .PARAMETER PreserveDirectories
        Overrides the list of directories to preserve/restore (defaults to `Help`, `Modules`, `PSReadLine`, `Scripts`).

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
    [string[]]$PreserveDirectories = @('Help', 'Modules', 'PSReadLine', 'Scripts'),

    [Parameter()]
    [string]$RestorePath,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Determine the appropriate PowerShell executable name
$psExecutable = if ($PSVersionTable.PSVersion.Major -lt 6) { 'powershell' } else { 'pwsh' }

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

function Ensure-DirectoryExists
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

function Invoke-RepositoryDownload
{
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    $parentDirectory = Split-Path -Parent $Destination
    Ensure-DirectoryExists -Path $parentDirectory

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
            throw "Git clone failed with exit code $LASTEXITCODE"
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
        Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing

        Write-Verbose 'Extracting to temporary location'
        $tempExtract = Join-Path ([System.IO.Path]::GetTempPath()) "pwsh-profile-extract-$([guid]::NewGuid().ToString('N'))"
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

        # GitHub zip archives contain a single top-level directory named {repo}-{branch}
        $extractedDir = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1

        if (-not $extractedDir)
        {
            throw 'Failed to find extracted content in zip archive'
        }

        Write-Verbose "Moving extracted content to $Destination"
        Ensure-DirectoryExists -Path $Destination

        Get-ChildItem -Path $extractedDir.FullName -Force | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $Destination -Recurse -Force
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
    Ensure-DirectoryExists -Path $DestinationPath

    Get-ChildItem -Path $SourcePath -Force | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $DestinationPath -Recurse -Force
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

    Ensure-DirectoryExists -Path $Destination

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
        $resolvedProfileRoot = if ($ProfileRoot) { Resolve-ProviderPath -PathToResolve $ProfileRoot } else { Get-DefaultProfileRoot }
        Write-Verbose "Using profile root: $resolvedProfileRoot"

        # Safety check: Warn if current directory is inside the profile directory that will be removed
        if (-not $RestorePath -and (Test-Path -Path $resolvedProfileRoot))
        {
            $currentLocation = $PWD.Path
            $resolvedCurrent = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($currentLocation)
            $isInsideProfile = $resolvedCurrent -eq $resolvedProfileRoot -or $resolvedCurrent.StartsWith($resolvedProfileRoot + [System.IO.Path]::DirectorySeparatorChar)

            if ($isInsideProfile)
            {
                Write-Host ''
                Write-Host 'WARNING: Your current directory is inside the profile directory that will be removed.' -ForegroundColor Yellow
                Write-Host "Current location: $resolvedCurrent" -ForegroundColor Yellow
                Write-Host "Profile root: $resolvedProfileRoot" -ForegroundColor Yellow
                Write-Host ''
                Write-Host 'Please change to a different directory before continuing.' -ForegroundColor Yellow
                Write-Host "Example: Set-Location -Path (Split-Path -Parent '$resolvedProfileRoot')" -ForegroundColor Cyan
                Write-Host ''
                throw 'Installation aborted: Current directory is inside the profile directory.'
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
            Remove-Item -Path $resolvedProfileRoot -Recurse -Force
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
    }
    catch
    {
        Write-Error $_
        throw
    }
}
