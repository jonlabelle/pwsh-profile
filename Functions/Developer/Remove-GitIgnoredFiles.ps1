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
        Supports ~ for home directory expansion. Must be within a Git repository.

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
        - FilesRemoved: Number of files successfully removed
        - DirectoriesRemoved: Number of directories successfully removed
        - TotalSpaceFreed: Total disk space freed (unless -NoSizeCalculation is specified)
        - Errors: Number of errors encountered

    .NOTES
        - Requires PowerShell 5.1 or later
        - Requires Git to be installed and available in PATH
        - Only removes files not tracked by Git (ignored and optionally untracked)
        - Does NOT remove unstaged changes to tracked files
        - Respects -WhatIf and -Confirm parameters for safety
        - Uses 'git clean' internally with appropriate flags

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
        [Switch]$IncludeUntracked,

        [Parameter()]
        [Switch]$NoSizeCalculation
    )

    begin
    {
        Write-Verbose 'Starting Git repository cleanup'

        # Statistics tracking
        $stats = @{
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
            $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

            if (-not (Test-Path -Path $resolvedPath -PathType Container))
            {
                Write-Error "Path not found or is not a directory: $resolvedPath"
                return
            }

            Write-Verbose "Checking Git repository in: $resolvedPath"

            # Check if the path is within a Git repository
            $gitCheckResult = & git -C $resolvedPath rev-parse --git-dir 2>&1
            if ($LASTEXITCODE -ne 0)
            {
                Write-Error "Path is not within a Git repository: $resolvedPath"
                return
            }

            $gitDir = $gitCheckResult
            Write-Verbose "Git repository found: $gitDir"

            # Determine what files would be removed
            # -n = dry run, -d = include directories, -X = ignored files only, -x = ignored + untracked
            $cleanFlag = if ($IncludeUntracked) { '-x' } else { '-X' }
            $dryRunOutput = & git -C $resolvedPath clean -n -d $cleanFlag 2>&1

            if ($LASTEXITCODE -ne 0)
            {
                Write-Error "Git clean failed: $dryRunOutput"
                $stats.Errors++
                return
            }

            # Parse the output to get list of files/directories
            $itemsToRemove = @()
            foreach ($line in $dryRunOutput)
            {
                if ($line -match '^Would remove (.+)$')
                {
                    $itemPath = $matches[1]
                    $fullPath = Join-Path -Path $resolvedPath -ChildPath $itemPath
                    if (Test-Path -Path $fullPath)
                    {
                        $itemsToRemove += Get-Item -Path $fullPath -Force
                    }
                }
            }

            if ($itemsToRemove.Count -eq 0)
            {
                Write-Host 'No ignored files found to remove.' -ForegroundColor Yellow
                return
            }

            $fileTypeMessage = if ($IncludeUntracked) { 'ignored and untracked' } else { 'ignored' }
            Write-Host "Found $($itemsToRemove.Count) $fileTypeMessage item(s) to remove" -ForegroundColor Cyan

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
            if ($PSCmdlet.ShouldProcess($resolvedPath, "Remove $fileTypeMessage files using 'git clean -f -d $cleanFlag'"))
            {
                Write-Verbose "Executing: git clean -f -d $cleanFlag"
                $cleanOutput = & git -C $resolvedPath clean -f -d $cleanFlag 2>&1

                if ($LASTEXITCODE -ne 0)
                {
                    Write-Error "Git clean failed: $cleanOutput"
                    $stats.Errors++
                    return
                }

                # Parse output to count removed items
                foreach ($line in $cleanOutput)
                {
                    if ($line -match '^Removing (.+)$')
                    {
                        $removedItem = $matches[1]
                        Write-Host "Removed: $removedItem" -ForegroundColor Green

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
            }
            else
            {
                Write-Host "WhatIf: Would remove $($itemsToRemove.Count) $fileTypeMessage item(s) from $resolvedPath" -ForegroundColor Yellow

                # Show what would be removed
                foreach ($item in $itemsToRemove)
                {
                    $relativePath = $item.FullName.Substring($resolvedPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                    Write-Host "  Would remove: $relativePath" -ForegroundColor Yellow
                }
            }
        }
        catch
        {
            $stats.Errors++
            Write-Error "Error processing repository: $($_.Exception.Message)"
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
            FilesRemoved = $stats.FilesRemoved
            DirectoriesRemoved = $stats.DirectoriesRemoved
            TotalSpaceFreed = $spaceFreedFormatted
            Errors = $stats.Errors
        }
    }
}
