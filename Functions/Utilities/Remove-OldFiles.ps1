function Remove-OldFiles
{
    <#
    .SYNOPSIS
        Removes files older than a specified time period.

    .DESCRIPTION
        Recursively searches for files older than a specified age and removes them. Supports
        filtering by file patterns, excluding specific files/directories, and optionally removing
        empty directories after cleanup.

        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Path
        The root path to search for old files. Defaults to the current directory.
        Supports ~ for home directory expansion and accepts pipeline input.

    .PARAMETER OlderThan
        The age threshold for files to be removed. Files with LastWriteTime older than this
        value will be deleted.

    .PARAMETER Unit
        The time unit for the OlderThan parameter. Valid values: Days, Hours, Months, Years.
        Default is Days.

    .PARAMETER Include
        File name patterns to include (e.g., '*.log', '*.tmp').
        Supports multiple patterns as an array. If not specified, all files are considered.

    .PARAMETER Exclude
        File name patterns to exclude (e.g., '*.keep', 'important*').
        Supports multiple patterns as an array.

    .PARAMETER ExcludeDirectory
        Directory names to exclude from the search (e.g., '.git', 'node_modules').
        These directories and their subdirectories will not be searched.
        Supports multiple patterns as an array.

    .PARAMETER RemoveEmptyDirectories
        After removing old files, also remove any directories that are now empty.
        This is done recursively from the deepest level up.

    .PARAMETER Force
        Forces removal of read-only and hidden files. Without this switch, read-only and
        hidden files are skipped.

    .PARAMETER WhatIf
        Shows what files would be removed without actually removing anything.

    .PARAMETER Confirm
        Prompts for confirmation before removing files.

    .EXAMPLE
        PS > Remove-OldFiles -OlderThan 30

        Removes all files in the current directory (and subdirectories) older than 30 days.

    .EXAMPLE
        PS > Remove-OldFiles -Path C:\Logs -OlderThan 7 -Include '*.log','*.txt'

        Removes .log and .txt files from C:\Logs that are older than 7 days.

    .EXAMPLE
        PS > Remove-OldFiles -OlderThan 12 -Unit Hours -RemoveEmptyDirectories

        Removes files older than 12 hours and cleans up any empty directories.

    .EXAMPLE
        PS > Remove-OldFiles -OlderThan 3 -Unit Months -Exclude '*.keep' -WhatIf

        Shows what files older than 3 months would be removed, excluding files matching '*.keep'.

    .EXAMPLE
        PS > Remove-OldFiles -Path ~/Downloads -OlderThan 90 -ExcludeDirectory @('Important', 'Archive')

        Removes files older than 90 days from ~/Downloads, excluding the Important and Archive directories.

    .EXAMPLE
        PS > Remove-OldFiles -OlderThan 1 -Unit Years -Force -Confirm

        Removes files older than 1 year, including read-only and hidden files, with confirmation prompts.

    .EXAMPLE
        PS > Get-ChildItem -Directory | Remove-OldFiles -OlderThan 14 -Include '*.tmp','*.cache'

        Processes multiple directories via pipeline, removing .tmp and .cache files older than 14 days.

    .OUTPUTS
        [PSCustomObject]
        Returns an object with summary information about the operation:
        - FilesRemoved: Number of files successfully removed
        - DirectoriesRemoved: Number of empty directories removed (if -RemoveEmptyDirectories specified)
        - TotalSpaceFreed: Total disk space freed in bytes
        - Errors: Number of errors encountered
        - OldestDate: The cutoff date used for file age comparison

    .NOTES
        - Requires PowerShell 5.1 or later
        - Uses LastWriteTime to determine file age
        - Respects -WhatIf and -Confirm parameters for safety
        - Read-only and hidden files are skipped unless -Force is specified
        - Empty directory removal is performed after file removal and processes from deepest to shallowest

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Remove-OldFiles.ps1

    .LINK
        https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/remove-item
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$Path = (Get-Location).Path,

        [Parameter(Mandatory)]
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int32]$OlderThan,

        [Parameter()]
        [ValidateSet('Days', 'Hours', 'Months', 'Years')]
        [String]$Unit = 'Days',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$Include,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$Exclude,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$ExcludeDirectory,

        [Parameter()]
        [Switch]$RemoveEmptyDirectories,

        [Parameter()]
        [Switch]$Force
    )

    begin
    {
        # Helper function to format file sizes
        function Format-FileSize
        {
            param([Int64]$Size)

            if ($Size -gt 1TB)
            {
                return '{0:N2} TB' -f ($Size / 1TB)
            }
            elseif ($Size -gt 1GB)
            {
                return '{0:N2} GB' -f ($Size / 1GB)
            }
            elseif ($Size -gt 1MB)
            {
                return '{0:N2} MB' -f ($Size / 1MB)
            }
            elseif ($Size -gt 1KB)
            {
                return '{0:N2} KB' -f ($Size / 1KB)
            }
            else
            {
                return '{0} bytes' -f $Size
            }
        }

        Write-Verbose 'Starting Remove-OldFiles'

        # Initialize counters
        $filesRemoved = 0
        $directoriesRemoved = 0
        $totalSpaceFreed = 0
        $errorCount = 0

        # Calculate cutoff date
        $cutoffDate = switch ($Unit)
        {
            'Hours' { (Get-Date).AddHours(-$OlderThan) }
            'Days' { (Get-Date).AddDays(-$OlderThan) }
            'Months' { (Get-Date).AddMonths(-$OlderThan) }
            'Years' { (Get-Date).AddYears(-$OlderThan) }
        }

        Write-Verbose "Cutoff date: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))"
        Write-Verbose 'Files with LastWriteTime before this date will be removed'

        # Collection to track processed directories for empty directory cleanup
        $processedDirectories = [System.Collections.Generic.HashSet[String]]::new()
    }

    process
    {
        # Skip null or empty paths
        if ([String]::IsNullOrWhiteSpace($Path))
        {
            Write-Verbose 'Skipping null or empty path'
            continue
        }

        # Resolve path (handles ~, relative paths, etc.)
        try
        {
            $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

            # Ensure we got a valid path back
            if ([String]::IsNullOrWhiteSpace($resolvedPath))
            {
                Write-Error "Failed to resolve path '$Path': resulted in empty path"
                $errorCount++
                continue
            }
        }
        catch
        {
            Write-Error "Failed to resolve path '$Path': $($_.Exception.Message)"
            $errorCount++
            continue
        }

        # Verify path exists
        if (-not (Test-Path -LiteralPath $resolvedPath))
        {
            Write-Error "Path not found: $resolvedPath"
            $errorCount++
            continue
        }

        Write-Verbose "Processing path: $resolvedPath"

        # Build Get-ChildItem parameters
        $getChildItemParams = @{
            LiteralPath = $resolvedPath
            File = $true
            Recurse = $true
            Force = $Force
            ErrorAction = 'SilentlyContinue'
        }

        # Get all files (wrap in array to ensure it's always an array)
        $files = @(Get-ChildItem @getChildItemParams)

        # Filter by Include patterns if specified (manual filtering for PS 5.1 compatibility)
        if ($Include)
        {
            $files = $files | Where-Object {
                $fileName = $_.Name
                $matched = $false
                foreach ($pattern in $Include)
                {
                    if ($fileName -like $pattern)
                    {
                        $matched = $true
                        break
                    }
                }
                $matched
            }
        }

        # Filter by Exclude patterns if specified (manual filtering for PS 5.1 compatibility)
        if ($Exclude)
        {
            $files = $files | Where-Object {
                $fileName = $_.Name
                $excluded = $false
                foreach ($pattern in $Exclude)
                {
                    if ($fileName -like $pattern)
                    {
                        $excluded = $true
                        break
                    }
                }
                -not $excluded
            }
        }

        # Filter by excluded directories if specified
        if ($ExcludeDirectory)
        {
            $files = $files | Where-Object {
                $filePath = $_.FullName
                $shouldExclude = $false

                foreach ($excludePattern in $ExcludeDirectory)
                {
                    # Check if any parent directory matches the exclude pattern
                    $pathParts = $filePath -split [regex]::Escape([System.IO.Path]::DirectorySeparatorChar)
                    if ($pathParts -contains $excludePattern)
                    {
                        $shouldExclude = $true
                        break
                    }
                }

                -not $shouldExclude
            }
        }

        # Filter by age and process
        foreach ($file in $files)
        {
            if ($file.LastWriteTime -lt $cutoffDate)
            {
                $fileSize = $file.Length
                $fileName = $file.FullName

                # Track parent directory for potential cleanup (before removal)
                if ($RemoveEmptyDirectories)
                {
                    $parentDir = [System.IO.Path]::GetDirectoryName($fileName)
                    if ($parentDir)
                    {
                        [void]$processedDirectories.Add($parentDir)
                    }
                }

                if ($PSCmdlet.ShouldProcess($fileName, 'Remove file'))
                {
                    try
                    {
                        if ($Force)
                        {
                            Remove-Item -LiteralPath $fileName -Force -ErrorAction Stop
                        }
                        else
                        {
                            Remove-Item -LiteralPath $fileName -ErrorAction Stop
                        }
                        $filesRemoved++
                        $totalSpaceFreed += $fileSize
                        Write-Verbose "Removed: $fileName ($(Format-FileSize $fileSize))"
                    }
                    catch [System.UnauthorizedAccessException]
                    {
                        if ($Force)
                        {
                            Write-Error "Failed to remove file '$fileName': $($_.Exception.Message)"
                            $errorCount++
                        }
                        else
                        {
                            Write-Verbose "Skipping read-only or protected file: $fileName (use -Force to remove)"
                        }
                    }
                    catch [System.IO.IOException]
                    {
                        # On Unix systems, permission errors may manifest as IOException
                        if ($_.Exception.Message -match 'access rights|permission|read only')
                        {
                            if ($Force)
                            {
                                Write-Error "Failed to remove file '$fileName': $($_.Exception.Message)"
                                $errorCount++
                            }
                            else
                            {
                                Write-Verbose "Skipping read-only or protected file: $fileName (use -Force to remove)"
                            }
                        }
                        else
                        {
                            Write-Error "Failed to remove file '$fileName': $($_.Exception.Message)"
                            $errorCount++
                        }
                    }
                    catch
                    {
                        Write-Error "Failed to remove file '$fileName': $($_.Exception.Message)"
                        $errorCount++
                    }
                }
            }
        }
    }

    end
    {
        # Remove empty directories if requested
        if ($RemoveEmptyDirectories -and $processedDirectories.Count -gt 0)
        {
            Write-Verbose 'Checking for empty directories to remove...'

            # Keep checking until no more directories can be removed
            # This handles cascading empty directory removal (e.g., removing SubDir2 might make SubDir1 empty)
            $removedInPass = $true
            while ($removedInPass)
            {
                $removedInPass = $false

                # Sort directories by depth (deepest first) to handle nested empty directories
                $sortedDirs = $processedDirectories | Sort-Object { ($_ -split [regex]::Escape([System.IO.Path]::DirectorySeparatorChar)).Count } -Descending

                foreach ($dir in $sortedDirs)
                {
                    if (Test-Path -LiteralPath $dir)
                    {
                        try
                        {
                            # Check if directory is empty
                            $items = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)
                            if ($items.Count -eq 0)
                            {
                                if ($PSCmdlet.ShouldProcess($dir, 'Remove empty directory'))
                                {
                                    Remove-Item -LiteralPath $dir -Force -ErrorAction Stop
                                    $directoriesRemoved++
                                    $removedInPass = $true
                                    Write-Verbose "Removed empty directory: $dir"

                                    # Track parent for potential cleanup
                                    $parentDir = [System.IO.Path]::GetDirectoryName($dir)
                                    if ($parentDir -and -not $processedDirectories.Contains($parentDir))
                                    {
                                        [void]$processedDirectories.Add($parentDir)
                                    }
                                }
                            }
                        }
                        catch
                        {
                            Write-Verbose "Could not remove directory '$dir': $($_.Exception.Message)"
                        }
                    }
                }
            }
        }

        # Output summary
        $summary = [PSCustomObject]@{
            FilesRemoved = $filesRemoved
            DirectoriesRemoved = $directoriesRemoved
            TotalSpaceFreed = $totalSpaceFreed
            TotalSpaceFreedMB = [Math]::Round($totalSpaceFreed / 1MB, 2)
            Errors = $errorCount
            OldestDate = $cutoffDate
        }

        Write-Verbose "Operation completed: $filesRemoved files removed, $directoriesRemoved directories removed"
        Write-Verbose "Total space freed: $(Format-FileSize $totalSpaceFreed)"

        return $summary
    }
}
