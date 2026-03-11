function Sync-Directory
{
    <#
    .SYNOPSIS
        Synchronizes directories using native platform tools (rsync on macOS/Linux, robocopy on Windows).

    .DESCRIPTION
        Provides a cross-platform directory synchronization wrapper that uses the best native tools
        for each platform:
        - Windows: robocopy with mirror mode and progress
        - macOS/Linux: rsync with archive mode and progress

        This function is optimized for large directory operations and provides better performance
        than pure PowerShell file copying. For smaller operations or when native tools are not
        available, consider using Copy-Directory instead.

    .PARAMETER Source
        The source directory path to synchronize from. Supports relative paths and tilde (~) expansion.
        On macOS/Linux, trailing slashes affect rsync behavior (see examples).

    .PARAMETER Destination
        The destination directory path to synchronize to. Will be created if it doesn't exist.
        Supports relative paths and tilde (~) expansion.

    .PARAMETER Delete
        If specified, deletes files in destination that don't exist in source (mirror mode).
        On Windows, this uses robocopy's /MIR switch.
        On macOS/Linux, this uses rsync's --delete flag.

    .PARAMETER DryRun
        Shows what would be synchronized without actually performing the operation.
        Useful for testing synchronization before executing.

    .PARAMETER ExcludeFiles
        File patterns to exclude from synchronization.
        Examples: '*.log', '*.tmp', '*.bak'

    .PARAMETER ExcludeDirectories
        Directory names or patterns to exclude from synchronization.
        Examples: '.git', 'node_modules', 'bin', 'obj'

    .PARAMETER ExtraOptions
        Additional platform-specific options to pass to the underlying tool.
        For rsync: array of rsync flags (e.g., @('--compress', '--links'))
        For robocopy: array of robocopy switches (e.g., @('/MT:8', '/R:3'))

    .PARAMETER ThreadCount
        Number of threads to use for robocopy on Windows (`/MT:n`).
        Ignored on macOS/Linux. Valid range is 1-128.
        If `-ExtraOptions` already includes `/MT` or `/MT:n`, that value is used instead.

    .EXAMPLE
        PS > Sync-Directory -Source '.\MyProject' -Destination 'D:\Backup\MyProject'

        Synchronizes MyProject directory to D:\Backup\MyProject using platform-native tools.

    .EXAMPLE
        PS > Sync-Directory -Source '/home/user/data' -Destination '/mnt/backup/data' -Delete -ExcludeDirectories '.git' -ExcludeFiles '*.tmp'

        Mirrors the data directory to backup, deleting files in destination that don't exist in source,
        while excluding .git directories and .tmp files.

    .EXAMPLE
        PS > Sync-Directory -Source '~/Documents/' -Destination '~/Backup/Documents/' -DryRun

        Shows what would be synchronized without actually performing the operation.
        Note: On macOS/Linux, the trailing slash on Source means "contents of Documents".

    .EXAMPLE
        PS > Sync-Directory -Source 'C:\Projects' -Destination 'E:\Archive' -Delete -ExtraOptions @('/MT:16', '/R:2', '/W:5')

        Windows example using robocopy with 16 threads, 2 retries, and 5-second wait between retries.

    .EXAMPLE
        PS > Sync-Directory -Source '/var/log' -Destination '/backup/logs' -ExtraOptions @('--compress', '--verbose')

        Linux/macOS example using rsync with compression and verbose output.

    .EXAMPLE
        PS > Sync-Directory -Source './src' -Destination './dist' -ExcludeDirectories 'node_modules', 'bin', 'obj' -ExcludeFiles '*.log'

        Syncs a source code directory while excluding common build artifacts and dependencies.

    .EXAMPLE
        PS > Sync-Directory -Source 'C:\Users\Public\Photos' -Destination 'D:\PhotoBackup' -Delete -Verbose

        Creates a mirror backup of photos with verbose output showing what's being synchronized.
        Files deleted from source will be removed from destination.

    .EXAMPLE
        PS > $result = Sync-Directory -Source '~/data' -Destination '/mnt/nas/backup' -DryRun
        PS > if ($result.Success) { Sync-Directory -Source '~/data' -Destination '/mnt/nas/backup' }

        Test the sync operation first with DryRun, then execute only if successful.

    .EXAMPLE
        PS > Sync-Directory -Source '/media/videos' -Destination '/backup/videos' -ExcludeFiles '*.tmp', '*.part', '.DS_Store'

        Backup videos while excluding temporary files, partial downloads, and macOS metadata files.

    .EXAMPLE
        PS > Sync-Directory -Source 'C:\Development' -Destination '\\ServerName\Backups\Dev' -ExcludeDirectories '.git', '.vs', 'packages', 'bin', 'obj'

        Sync development projects to a network share, excluding version control and build outputs.

    .EXAMPLE
        PS > Sync-Directory -Source '/var/www/html' -Destination '/backup/www' -Delete -ExtraOptions @('--exclude=*.sock', '--exclude=cache/*')

        Sync web server files using custom rsync exclusions for socket files and cache directories.

    .EXAMPLE
        PS > Sync-Directory -Source './src/' -Destination '/mnt/wsl/projects/app/' -ExcludeDirectories '.git', '.vscode', 'node_modules'

        Mirrors the working tree into a mounted WSL path so Linux-specific tooling sees the latest code without committing.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns an object with Platform, Command, ExitCode, Success, and Message properties.

    .NOTES
        Cross-platform compatible with PowerShell 5.1+ and PowerShell Core 6.2+.

        Windows Requirements:
        - robocopy (built into Windows Vista and later)

        macOS/Linux Requirements:
        - rsync (typically pre-installed on most distributions)

        rsync trailing slash behavior:
        - '/path/to/source/' copies the CONTENTS of source into destination
        - '/path/to/source' copies the source DIRECTORY into destination

        robocopy automatically handles directory creation and always copies contents.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Sync-Directory.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Sync-Directory.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$Source,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [String]$Destination,

        [Parameter()]
        [Switch]$Delete,

        [Parameter()]
        [Switch]$DryRun,

        [Parameter()]
        [String[]]$ExcludeFiles = @(),

        [Parameter()]
        [String[]]$ExcludeDirectories = @(),

        [Parameter()]
        [String[]]$ExtraOptions = @(),

        [Parameter()]
        [ValidateRange(1, 128)]
        [Int32]$ThreadCount = ([Math]::Min(32, [Math]::Max(4, [Environment]::ProcessorCount)))
    )

    begin
    {
        Write-Verbose 'Starting Sync-Directory'

        # Detect platform once for path comparison and tool selection.
        $IsWindowsPlatform = $IsWindows -or $env:OS -eq 'Windows_NT'
        $pathComparison = if ($IsWindowsPlatform) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
        $separatorChars = @([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

        Write-Verbose "Platform: $(if ($IsWindowsPlatform) { 'Windows' } else { 'macOS/Linux' })"

        # Resolve paths to absolute paths (cross-platform compatible)
        $Source = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Source)
        $Destination = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
        $Source = [System.IO.Path]::GetFullPath($Source)
        $Destination = [System.IO.Path]::GetFullPath($Destination)

        $sourceComparable = $Source.TrimEnd($separatorChars)
        if ([String]::IsNullOrEmpty($sourceComparable))
        {
            $sourceComparable = [System.IO.Path]::DirectorySeparatorChar.ToString()
        }

        $destinationComparable = $Destination.TrimEnd($separatorChars)
        if ([String]::IsNullOrEmpty($destinationComparable))
        {
            $destinationComparable = [System.IO.Path]::DirectorySeparatorChar.ToString()
        }

        Write-Verbose "Resolved source path: $Source"
        Write-Verbose "Resolved destination path: $Destination"

        # Validate source exists
        if (-not (Test-Path -Path $Source -PathType Container))
        {
            throw "Source directory does not exist: $Source"
        }

        if (Test-Path -Path $Destination -PathType Leaf)
        {
            throw "Destination path exists as a file. Specify a directory path instead: $Destination"
        }

        # Prevent recursive self-sync scenarios.
        if ([String]::Equals($sourceComparable, $destinationComparable, $pathComparison))
        {
            throw "Source and destination cannot be the same directory: $Source"
        }

        $sourcePrefix = if ($sourceComparable.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString()))
        {
            $sourceComparable
        }
        else
        {
            $sourceComparable + [System.IO.Path]::DirectorySeparatorChar
        }

        $destinationPrefix = if ($destinationComparable.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString()))
        {
            $destinationComparable
        }
        else
        {
            $destinationComparable + [System.IO.Path]::DirectorySeparatorChar
        }

        if ($destinationComparable.StartsWith($sourcePrefix, $pathComparison))
        {
            throw "Destination cannot be inside source: $Destination"
        }

        if ($Delete -and $sourceComparable.StartsWith($destinationPrefix, $pathComparison))
        {
            throw "Source cannot be inside destination when -Delete is used: $Source"
        }
    }

    process
    {
        $Result = [PSCustomObject]@{
            Platform = if ($IsWindowsPlatform) { 'Windows' } else { 'macOS/Linux' }
            Command = $null
            ExitCode = $null
            Success = $false
            Message = $null
            StartTime = Get-Date
            EndTime = $null
            Duration = $null
        }

        try
        {
            if ($IsWindowsPlatform)
            {
                #region Windows - robocopy

                # Check if robocopy is available
                $robocopyPath = Get-Command -Name 'robocopy.exe' -ErrorAction SilentlyContinue
                if (-not $robocopyPath)
                {
                    throw 'robocopy.exe not found. This should be available on Windows Vista and later.'
                }

                # Build robocopy arguments
                $robocopyArgs = @()

                # Source and destination (robocopy doesn't use trailing slashes)
                $robocopyArgs += "`"$Source`""
                $robocopyArgs += "`"$Destination`""

                # Copy all files and subdirectories, including empty directories
                $robocopyArgs += '/E'

                # Mirror mode (includes /E plus deletes files in dest not in source)
                if ($Delete)
                {
                    $robocopyArgs += '/MIR'
                }

                # Show progress
                $robocopyArgs += '/NP' # No percentage in output (cleaner for PowerShell)
                $robocopyArgs += '/NDL' # No directory list (less verbose)
                $robocopyArgs += '/NFL' # No file list (less verbose, use /V for verbose)

                # Copy file data, attributes, and timestamps
                $robocopyArgs += '/COPY:DAT'

                # Retry settings (1 retry, 1 second wait)
                $robocopyArgs += '/R:1'
                $robocopyArgs += '/W:1'

                # Enable multi-threaded copy by default for better performance
                $hasThreadingOption = $ExtraOptions | Where-Object { $_ -match '^/MT(?::\d+)?$' }
                if (-not $hasThreadingOption)
                {
                    $robocopyArgs += "/MT:$ThreadCount"
                }

                # Handle exclusions
                foreach ($Pattern in $ExcludeDirectories)
                {
                    $robocopyArgs += '/XD'
                    $robocopyArgs += "`"$Pattern`""
                }

                foreach ($Pattern in $ExcludeFiles)
                {
                    $robocopyArgs += '/XF'
                    $robocopyArgs += "`"$Pattern`""
                }

                # Add extra options
                if ($ExtraOptions.Count -gt 0)
                {
                    $robocopyArgs += $ExtraOptions
                }

                # Dry run
                if ($DryRun)
                {
                    $robocopyArgs += '/L' # List only, don't copy
                }

                $commandString = "robocopy $($robocopyArgs -join ' ')"
                $Result.Command = $commandString
                Write-Verbose "Executing: $commandString"

                if ($PSCmdlet.ShouldProcess($Destination, "Synchronize from $Source using robocopy"))
                {
                    # Execute robocopy
                    $processArgs = @{
                        FilePath = 'robocopy.exe'
                        ArgumentList = $robocopyArgs
                        NoNewWindow = $true
                        Wait = $true
                        PassThru = $true
                    }

                    $process = Start-Process @processArgs
                    $Result.ExitCode = $process.ExitCode

                    # robocopy exit codes:
                    # 0 = No files copied (no changes needed)
                    # 1 = Files copied successfully
                    # 2 = Extra files or directories detected (only with /MIR or /PURGE)
                    # 4 = Some mismatched files or directories detected
                    # 8 = Some files or directories could not be copied (copy errors)
                    # 16 = Serious error (robocopy did not copy any files)

                    if ($process.ExitCode -lt 8)
                    {
                        $Result.Success = $true
                        $Result.Message = switch ($process.ExitCode)
                        {
                            0 { 'No files needed to be copied (already synchronized)' }
                            1 { 'Files copied successfully' }
                            2 { 'Extra files or directories detected and handled' }
                            3 { 'Files copied successfully with extra files handled' }
                            4 { 'Some mismatched files or directories detected' }
                            5 { 'Files copied with some mismatches' }
                            6 { 'Extra files and mismatches detected' }
                            7 { 'Files copied with extra files and mismatches' }
                            default { "Completed with exit code $($process.ExitCode)" }
                        }
                    }
                    else
                    {
                        $Result.Success = $false
                        $Result.Message = switch ($process.ExitCode)
                        {
                            8 { 'Some files or directories could not be copied (copy errors occurred)' }
                            16 { 'Serious error: robocopy did not copy any files' }
                            default { "Failed with exit code $($process.ExitCode)" }
                        }
                    }
                }
                else
                {
                    $Result.ExitCode = 0
                    $Result.Success = $true
                    $Result.Message = 'Synchronization skipped by WhatIf/Confirm'
                }

                #endregion
            }
            else
            {
                #region macOS/Linux - rsync

                # Check if rsync is available
                $rsyncPath = Get-Command -Name 'rsync' -ErrorAction SilentlyContinue
                if (-not $rsyncPath)
                {
                    throw 'rsync not found. Please install rsync (e.g., apt-get install rsync, yum install rsync, or brew install rsync)'
                }

                # Build rsync arguments
                $rsyncArgs = @()

                # Archive mode (recursive, preserve permissions, timestamps, etc.)
                $rsyncArgs += '-a'

                # Verbose output
                $rsyncArgs += '-v'

                # Show progress
                $rsyncArgs += '--progress'

                # Human-readable output
                $rsyncArgs += '-h'

                # Delete files in destination not in source
                if ($Delete)
                {
                    $rsyncArgs += '--delete'
                }

                # Dry run
                if ($DryRun)
                {
                    $rsyncArgs += '--dry-run'
                }

                # Handle exclusions
                foreach ($Pattern in $ExcludeDirectories)
                {
                    $rsyncArgs += "--exclude=$Pattern"
                }

                foreach ($Pattern in $ExcludeFiles)
                {
                    $rsyncArgs += "--exclude=$Pattern"
                }

                # Add extra options
                if ($ExtraOptions.Count -gt 0)
                {
                    $rsyncArgs += $ExtraOptions
                }

                # Source and destination
                # Add trailing slash to source to copy CONTENTS (matching robocopy behavior)
                # Without trailing slash, rsync would copy the directory itself into dest
                $sourcePath = $Source
                if (-not $sourcePath.EndsWith([System.IO.Path]::DirectorySeparatorChar))
                {
                    $sourcePath += [System.IO.Path]::DirectorySeparatorChar
                }

                # Quote paths that contain spaces for the command string display
                $quotedSource = if ($sourcePath -match '\s') { "'$sourcePath'" } else { $sourcePath }
                $quotedDest = if ($Destination -match '\s') { "'$Destination'" } else { $Destination }

                # Add to args array (Start-Process handles these correctly)
                $rsyncArgs += $sourcePath
                $rsyncArgs += $Destination

                $commandString = "rsync $($rsyncArgs[0..($rsyncArgs.Count - 3)] -join ' ') $quotedSource $quotedDest"
                $Result.Command = $commandString
                Write-Verbose "Executing: $commandString"

                if ($PSCmdlet.ShouldProcess($Destination, "Synchronize from $Source using rsync"))
                {
                    # Execute rsync using & operator to avoid Start-Process quoting issues on macOS/Linux
                    try
                    {
                        $Result.ExitCode = & {
                            # Capture exit code using $LASTEXITCODE
                            & 'rsync' @rsyncArgs 2>&1 | Out-Null
                            return $LASTEXITCODE
                        }
                    }
                    catch
                    {
                        $Result.ExitCode = 1
                        Write-Verbose "rsync execution failed: $($_.Exception.Message)"
                    }

                    # rsync exit codes:
                    # 0 = Success
                    # 1 = Syntax or usage error
                    # 2 = Protocol incompatibility
                    # 3 = Errors selecting input/output files, dirs
                    # 5 = Error starting client-server protocol
                    # 10 = Error in socket I/O
                    # 11 = Error in file I/O
                    # 23 = Partial transfer due to error
                    # 24 = Partial transfer due to vanished source files

                    if ($Result.ExitCode -eq 0)
                    {
                        $Result.Success = $true
                        $Result.Message = 'Synchronization completed successfully'
                    }
                    elseif ($Result.ExitCode -eq 24)
                    {
                        # Exit code 24 is common when files change during sync
                        $Result.Success = $true
                        $Result.Message = 'Synchronization completed with some files vanishing during transfer'
                        Write-Warning 'Some source files vanishing during transfer (exit code 24)'
                    }
                    else
                    {
                        $Result.Success = $false
                        $Result.Message = "rsync failed with exit code $($Result.ExitCode)"
                    }
                }
                else
                {
                    $Result.ExitCode = 0
                    $Result.Success = $true
                    $Result.Message = 'Synchronization skipped by WhatIf/Confirm'
                }

                #endregion
            }
        }
        catch
        {
            $Result.Success = $false
            $Result.Message = "Error: $($_.Exception.Message)"
            Write-Error $_
        }
        finally
        {
            $Result.EndTime = Get-Date
            $Result.Duration = $Result.EndTime - $Result.StartTime
        }

        Write-Verbose "Operation completed in $($Result.Duration.TotalSeconds) seconds"
        Write-Verbose "Exit code: $($Result.ExitCode)"
        Write-Verbose "Success: $($Result.Success)"

        return $Result
    }

    end
    {
        Write-Verbose 'Sync-Directory completed'
    }
}
