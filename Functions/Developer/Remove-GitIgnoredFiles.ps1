function Remove-GitIgnoredFiles
{
    <#
    .SYNOPSIS
        Removes ignored and optionally untracked files from a Git repository.

    .DESCRIPTION
        Cleans up Git repository by removing files that are ignored by .gitignore and optionally
        untracked files. This is similar to 'git clean' but provides PowerShell-friendly output,
        size calculations, and safety features.

        IMPORTANT: This function does NOT remove unstaged changes to tracked files. It only
        removes files that Git is not currently tracking.

        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

        Requires Git to be installed and available in PATH.

    .PARAMETER Path
        The root path of the Git repository to clean. Defaults to the current directory.
        Supports ~ for home directory expansion.

        Without -Recurse: Must be within a Git repository (cleans that repository).
        With -Recurse: Can be any directory (searches for Git repositories within).

    .PARAMETER Recurse
        Searches for Git repositories recursively within the specified Path and cleans each one.
        Useful for workspace directories containing multiple Git repositories.

        WARNING: This will clean ALL Git repositories found within the specified path.
        Use -WhatIf first to see what repositories would be cleaned.

        Example use case: Clean ignored files from all projects in ~/Projects

    .PARAMETER IncludeUntracked
        Also removes untracked files (files not in .gitignore but not tracked by Git).
        By default, only ignored files are removed for safety.

    .PARAMETER NoSizeCalculation
        Skips calculating the size of files before removal. By default, file sizes are calculated
        to provide detailed space freed information. Use this switch for repositories with many
        files to significantly speed up execution.

    .PARAMETER WhatIf
        Shows what would be removed without actually removing anything.

    .PARAMETER Confirm
        Prompts for confirmation before removing files.

    .EXAMPLE
        PS > Remove-GitIgnoredFiles

        Removes all ignored files from the Git repository in the current directory,
        showing the total space freed.

    .EXAMPLE
        PS > Remove-GitIgnoredFiles -Recurse -WhatIf

        Shows what would be removed from all Git repositories found in the current directory
        and its subdirectories without actually removing anything.

    .EXAMPLE
        PS > Remove-GitIgnoredFiles -Path ~/Projects -Recurse

        Finds all Git repositories within ~/Projects and cleans ignored files from each one.
        Useful for cleaning up an entire workspace with multiple projects.

    .EXAMPLE
        PS > Remove-GitIgnoredFiles -IncludeUntracked

        Removes both ignored and untracked files from the repository.

    .EXAMPLE
        PS > Remove-GitIgnoredFiles -NoSizeCalculation

        Removes ignored files without calculating space freed (faster for large repositories).

    .EXAMPLE
        PS > Remove-GitIgnoredFiles -Path ~/Projects/MyRepo -WhatIf

        Shows what would be removed in the specified repository without actually removing anything.

    .EXAMPLE
        PS > Remove-GitIgnoredFiles -IncludeUntracked -Confirm

        Removes ignored and untracked files with confirmation prompts.

    .EXAMPLE
        PS > Remove-GitIgnoredFiles -Verbose

        Removes ignored files with detailed verbose output showing each operation.

    .OUTPUTS
        [PSCustomObject]
        Returns an object with summary information about the operation:
        - RepositoriesProcessed: Number of Git repositories processed (when using -Recurse)
        - FilesRemoved: Number of files successfully removed
        - DirectoriesRemoved: Number of directories successfully removed
        - TotalSpaceFreed: Total disk space freed (unless -NoSizeCalculation is specified)
        - Errors: Number of errors encountered

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Remove-GitIgnoredFiles.ps1

        - Requires PowerShell 5.1 or later
        - Requires Git to be installed and available in PATH
        - Only removes files not tracked by Git (ignored and optionally untracked)
        - Does NOT remove unstaged changes to tracked files
        - Respects -WhatIf and -Confirm parameters for safety
        - Uses 'git clean' internally with appropriate flags
        - With -Recurse: Finds .git directories to locate repositories, then cleans each one
        - With -Recurse: Use -WhatIf first to preview which repositories will be cleaned

    .LINK
        https://git-scm.com/docs/git-clean
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$Path = (Get-Location).Path,

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [Switch]$IncludeUntracked,

        [Parameter()]
        [Switch]$NoSizeCalculation
    )

    begin
    {
        Write-Verbose 'Starting Git repository cleanup'

        # Statistics tracking
        $stats = @{
            RepositoriesProcessed = 0
            FilesRemoved = 0
            DirectoriesRemoved = 0
            TotalSpaceFreed = [int64]0
            Errors = 0
        }

        # Check if Git is installed
        $gitCommand = Get-Command -Name 'git' -ErrorAction SilentlyContinue
        if (-not $gitCommand)
        {
            throw 'Git is not installed or not available in PATH. Please install Git and try again.'
        }

        Write-Verbose "Git found at: $($gitCommand.Source)"
    }

    process
    {
        try
        {
            # Resolve and validate the path
            $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

            if (-not (Test-Path -Path $resolvedPath -PathType Container))
            {
                Write-Error "Path not found or is not a directory: $resolvedPath"
                return
            }

            Write-Verbose "Searching for Git repositories in: $resolvedPath"

            # Find Git repositories
            $repositories = @()

            if ($Recurse)
            {
                # Find all .git directories recursively
                Write-Verbose 'Searching recursively for Git repositories...'

                $getChildItemParams = @{
                    Path = $resolvedPath
                    Filter = '.git'
                    Directory = $true
                    Recurse = $true
                    Force = $true
                    ErrorAction = 'SilentlyContinue'
                }

                # Disable progress bar for recursive directory search (PowerShell 7.4+)
                if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 4)
                {
                    $getChildItemParams['ProgressAction'] = 'SilentlyContinue'
                }

                $gitDirs = Get-ChildItem @getChildItemParams

                foreach ($gitDir in $gitDirs)
                {
                    # The repository root is the parent of the .git directory
                    $repoPath = $gitDir.Parent.FullName
                    $repositories += $repoPath
                    Write-Verbose "Found repository: $repoPath"
                }

                if ($repositories.Count -eq 0)
                {
                    Write-Host 'No Git repositories found in the specified path.' -ForegroundColor Yellow
                    return
                }

                Write-Host "Found $($repositories.Count) Git repositor$(if ($repositories.Count -eq 1) { 'y' } else { 'ies' })" -ForegroundColor Cyan
            }
            else
            {
                # Single repository mode - verify it's a Git repository
                $gitCheckResult = & git -C $resolvedPath rev-parse --git-dir 2>&1
                if ($LASTEXITCODE -ne 0)
                {
                    Write-Error "Path is not within a Git repository: $resolvedPath`nUse -Recurse to search for repositories within this path."
                    return
                }

                Write-Verbose "Git repository found: $gitCheckResult"
                $repositories += $resolvedPath
            }

            # Process each repository
            foreach ($repoPath in $repositories)
            {
                try
                {
                    if ($Recurse)
                    {
                        Write-Host "`nProcessing: $repoPath" -ForegroundColor Cyan
                    }

                    # Determine what files would be removed
                    # -n = dry run, -d = include directories, -X = ignored files only, -x = ignored + untracked
                    $cleanFlag = if ($IncludeUntracked) { '-x' } else { '-X' }
                    $dryRunOutput = & git -C $repoPath clean -n -d $cleanFlag 2>&1

                    if ($LASTEXITCODE -ne 0)
                    {
                        Write-Warning "Git clean failed for $repoPath : $dryRunOutput"
                        $stats.Errors++
                        continue
                    }

                    # Parse the output to get list of files/directories
                    $itemsToRemove = @()
                    foreach ($line in $dryRunOutput)
                    {
                        if ($line -match '^Would remove (.+)$')
                        {
                            $itemPath = $matches[1]
                            $fullPath = Join-Path -Path $repoPath -ChildPath $itemPath
                            if (Test-Path -Path $fullPath)
                            {
                                $itemsToRemove += Get-Item -Path $fullPath -Force
                            }
                        }
                    }

                    if ($itemsToRemove.Count -eq 0)
                    {
                        if ($Recurse)
                        {
                            Write-Host '  No ignored files to remove' -ForegroundColor DarkGray
                        }
                        else
                        {
                            Write-Host 'No ignored files found to remove.' -ForegroundColor Yellow
                        }
                        continue
                    }

                    $fileTypeMessage = if ($IncludeUntracked) { 'ignored and untracked' } else { 'ignored' }
                    if ($Recurse)
                    {
                        Write-Host "  Found $($itemsToRemove.Count) $fileTypeMessage item(s)" -ForegroundColor White
                    }
                    else
                    {
                        Write-Host "Found $($itemsToRemove.Count) $fileTypeMessage item(s) to remove" -ForegroundColor Cyan
                    }

                    # Calculate sizes before removal (unless disabled)
                    if (-not $NoSizeCalculation)
                    {
                        Write-Verbose 'Calculating total size of items to remove...'
                        foreach ($item in $itemsToRemove)
                        {
                            try
                            {
                                if ($item.PSIsContainer)
                                {
                                    $getSizeParams = @{
                                        Path = $item.FullName
                                        Recurse = $true
                                        File = $true
                                        Force = $true
                                        ErrorAction = 'SilentlyContinue'
                                    }
                                    # Disable progress bar when calculating folder size
                                    if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 4)
                                    {
                                        $getSizeParams['ProgressAction'] = 'SilentlyContinue'
                                    }
                                    $itemSize = (Get-ChildItem @getSizeParams |
                                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                                    if ($null -eq $itemSize) { $itemSize = 0 }
                                    $stats.TotalSpaceFreed += $itemSize
                                }
                                else
                                {
                                    $stats.TotalSpaceFreed += $item.Length
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not calculate size for: $($item.FullName)"
                            }
                        }
                    }

                    # Perform the actual cleanup
                    $repoDisplayPath = if ($Recurse) { $repoPath } else { $repoPath }
                    if ($PSCmdlet.ShouldProcess($repoDisplayPath, "Remove $fileTypeMessage files using 'git clean -f -d $cleanFlag'"))
                    {
                        Write-Verbose "Executing: git clean -f -d $cleanFlag in $repoPath"
                        $cleanOutput = & git -C $repoPath clean -f -d $cleanFlag 2>&1

                        if ($LASTEXITCODE -ne 0)
                        {
                            Write-Warning "Git clean failed for $repoPath : $cleanOutput"
                            $stats.Errors++
                            continue
                        }

                        # Parse output to count removed items
                        foreach ($line in $cleanOutput)
                        {
                            if ($line -match '^Removing (.+)$')
                            {
                                $removedItem = $matches[1]
                                if ($Recurse)
                                {
                                    Write-Host "  Removed: $removedItem" -ForegroundColor Green
                                }
                                else
                                {
                                    Write-Host "Removed: $removedItem" -ForegroundColor Green
                                }

                                # Determine if it was a file or directory
                                if ($removedItem -match '/$')
                                {
                                    $stats.DirectoriesRemoved++
                                }
                                else
                                {
                                    $stats.FilesRemoved++
                                }
                            }
                        }

                        $stats.RepositoriesProcessed++
                    }
                    else
                    {
                        if ($Recurse)
                        {
                            Write-Host "  WhatIf: Would remove $($itemsToRemove.Count) $fileTypeMessage item(s)" -ForegroundColor Yellow
                        }
                        else
                        {
                            Write-Host "WhatIf: Would remove $($itemsToRemove.Count) $fileTypeMessage item(s) from $repoPath" -ForegroundColor Yellow
                        }

                        # Show what would be removed
                        foreach ($item in $itemsToRemove)
                        {
                            $relativePath = $item.FullName.Substring($repoPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                            if ($Recurse)
                            {
                                Write-Host "    Would remove: $relativePath" -ForegroundColor Yellow
                            }
                            else
                            {
                                Write-Host "  Would remove: $relativePath" -ForegroundColor Yellow
                            }
                        }
                    }
                }
                catch
                {
                    $stats.Errors++
                    Write-Warning "Error processing repository $repoPath : $($_.Exception.Message)"
                    Write-Verbose "Error details: $($_.Exception)"
                }
            }
        }
        catch
        {
            $stats.Errors++
            Write-Error "Error processing path: $($_.Exception.Message)"
            Write-Verbose "Error details: $($_.Exception)"
        }
    }

    end
    {
        # Helper function to format bytes into human-readable size
        function Format-ByteSize
        {
            param([int64]$Bytes)

            switch ($Bytes)
            {
                { $_ -ge 1TB } { '{0:N2} TB' -f ($_ / 1TB); break }
                { $_ -ge 1GB } { '{0:N2} GB' -f ($_ / 1GB); break }
                { $_ -ge 1MB } { '{0:N2} MB' -f ($_ / 1MB); break }
                { $_ -ge 1KB } { '{0:N2} KB' -f ($_ / 1KB); break }
                default { '{0} bytes' -f $_ }
            }
        }

        # Format space freed for output and return object
        $spaceFreedFormatted = if (-not $NoSizeCalculation)
        {
            if ($stats.TotalSpaceFreed -gt 0)
            {
                Format-ByteSize -Bytes $stats.TotalSpaceFreed
            }
            else
            {
                '0 bytes'
            }
        }
        else
        {
            'Not calculated (use without -NoSizeCalculation for details)'
        }

        # Display summary
        Write-Host "`nCleanup Summary:" -ForegroundColor Cyan

        if ($Recurse)
        {
            Write-Host "  Repositories processed: $($stats.RepositoriesProcessed)" -ForegroundColor White
        }

        Write-Host "  Files removed: $($stats.FilesRemoved)" -ForegroundColor White
        Write-Host "  Directories removed: $($stats.DirectoriesRemoved)" -ForegroundColor White

        if (-not $NoSizeCalculation -and $stats.TotalSpaceFreed -gt 0)
        {
            Write-Host "  Space freed: $spaceFreedFormatted" -ForegroundColor Green
        }

        if ($stats.Errors -gt 0)
        {
            Write-Host "  Errors: $($stats.Errors)" -ForegroundColor Red
        }

        Write-Verbose 'Cleanup completed'

        # Return statistics object
        return [PSCustomObject]@{
            RepositoriesProcessed = $stats.RepositoriesProcessed
            FilesRemoved = $stats.FilesRemoved
            DirectoriesRemoved = $stats.DirectoriesRemoved
            TotalSpaceFreed = $spaceFreedFormatted
            Errors = $stats.Errors
        }
    }
}
