function Remove-NodeModules
{
    <#
    .SYNOPSIS
        Removes node_modules folders from Node.js project directories.

    .DESCRIPTION
        Recursively searches for Node.js project files (package.json) and removes
        their associated node_modules folders. Only removes folders when a package.json file
        is found in the parent directory, ensuring only legitimate Node.js projects are cleaned.

        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Path
        The root path to search for Node.js projects. Defaults to the current directory.
        Supports ~ for home directory expansion.

    .PARAMETER ExcludeDirectory
        Array of directory names to exclude from the search. Defaults to @('.git').
        These directories and their subdirectories will not be searched for Node.js projects.

    .PARAMETER CalculateSize
        Calculates the size of folders before removal. This provides detailed space freed information
        but may significantly slow down execution for large directory structures. By default, size
        calculation is skipped for better performance.

    .PARAMETER WhatIf
        Shows what would be removed without actually removing anything.

    .PARAMETER Confirm
        Prompts for confirmation before removing each folder.

    .EXAMPLE
        PS > Remove-NodeModules

        Removes all node_modules folders from Node.js projects in the current directory and subdirectories.

    .EXAMPLE
        PS > Remove-NodeModules -CalculateSize

        Removes node_modules folders and calculates the total space freed (slower but provides detailed statistics).

    .EXAMPLE
        PS > Remove-NodeModules -Path ~/Projects -WhatIf

        Shows what would be removed in the ~/Projects directory without actually removing anything.

    .EXAMPLE
        PS > Remove-NodeModules -Path C:\MyProjects -Confirm

        Removes node_modules folders with confirmation prompts for each folder.

    .EXAMPLE
        PS > Remove-NodeModules -Verbose

        Removes node_modules folders with detailed verbose output showing each operation.

    .EXAMPLE
        PS > Remove-NodeModules -Path ~/Projects -ExcludeDirectory @('.git', 'vendor', 'archive')

        Removes node_modules folders while excluding .git, vendor, and archive directories from the search.

    .OUTPUTS
        [PSCustomObject]
        Returns an object with summary information about the operation:
        - TotalProjectsFound: Number of Node.js projects discovered
        - FoldersRemoved: Number of folders successfully removed
        - TotalSpaceFreed: Total disk space freed (only calculated if -CalculateSize is specified)
        - Errors: Number of errors encountered

    .NOTES
        - Requires PowerShell 5.1 or later
        - Only removes node_modules folders when a package.json file exists in the parent directory
        - Respects -WhatIf and -Confirm parameters for safety
        - Can free up significant disk space, especially in workspaces with many projects

    .LINK
        https://docs.npmjs.com/cli/v9/commands/npm-install
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$Path = (Get-Location).Path,

        [Parameter()]
        [String[]]$ExcludeDirectory = @('.git'),

        [Parameter()]
        [Switch]$CalculateSize
    )

    begin
    {
        Write-Verbose 'Starting node_modules cleanup'

        # Statistics tracking
        $stats = @{
            ProjectsFound = 0
            FoldersRemoved = 0
            TotalSpaceFreed = [int64]0
            Errors = 0
        }

        # Project file pattern
        $projectPattern = 'package.json'

        # Log excluded directories
        if ($ExcludeDirectory -and $ExcludeDirectory.Count -gt 0)
        {
            Write-Verbose "Excluding directories: $($ExcludeDirectory -join ', ')"
        }
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

            Write-Verbose "Searching for Node.js projects in: $resolvedPath"

            # Build Get-ChildItem parameters
            $getChildItemParams = @{
                Path = $resolvedPath
                Filter = $projectPattern
                File = $true
                Recurse = $true
                ErrorAction = 'SilentlyContinue'
            }

            # Disable progress bar for recursive file search (PowerShell 7.4+)
            if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 4)
            {
                $getChildItemParams['ProgressAction'] = 'SilentlyContinue'
            }

            # Find all package.json files
            $allProjectFiles = Get-ChildItem @getChildItemParams

            # Additional filtering for excluded directories
            # Get-ChildItem -Exclude only works on names, not paths, so we need manual filtering
            if ($ExcludeDirectory -and $ExcludeDirectory.Count -gt 0)
            {
                $projectFiles = $allProjectFiles | Where-Object {
                    $filePath = $_.FullName
                    $isExcluded = $false
                    foreach ($excludeDir in $ExcludeDirectory)
                    {
                        # Check if the file path contains the excluded directory
                        if ($filePath -match [regex]::Escape([System.IO.Path]::DirectorySeparatorChar + $excludeDir + [System.IO.Path]::DirectorySeparatorChar) -or
                            $filePath -match [regex]::Escape([System.IO.Path]::DirectorySeparatorChar + $excludeDir + '$'))
                        {
                            $isExcluded = $true
                            Write-Verbose "Excluding project in $excludeDir directory: $filePath"
                            break
                        }
                    }
                    -not $isExcluded
                }
            }
            else
            {
                $projectFiles = $allProjectFiles
            }

            if (-not $projectFiles -or $projectFiles.Count -eq 0)
            {
                Write-Host 'No Node.js project files found in the specified path.' -ForegroundColor Yellow
                return
            }

            $stats.ProjectsFound = $projectFiles.Count
            Write-Host "Found $($stats.ProjectsFound) Node.js project(s)" -ForegroundColor Cyan

            # Process each project
            foreach ($projectFile in $projectFiles)
            {
                $projectDir = $projectFile.DirectoryName
                Write-Verbose "Processing project: $($projectFile.Name) in $projectDir"

                # Look for node_modules folder in the project directory
                $nodeModulesPath = Join-Path -Path $projectDir -ChildPath 'node_modules'

                if (Test-Path -Path $nodeModulesPath -PathType Container)
                {
                    $folder = Get-Item -Path $nodeModulesPath

                    try
                    {
                        # Calculate folder size before removal (only if requested)
                        $folderSize = [int64]0
                        if ($PSCmdlet.ShouldProcess($folder.FullName, 'Remove node_modules folder'))
                        {
                            # Calculate size for reporting (only if -CalculateSize is specified)
                            if ($CalculateSize)
                            {
                                try
                                {
                                    $getSizeParams = @{
                                        Path = $folder.FullName
                                        Recurse = $true
                                        File = $true
                                        ErrorAction = 'SilentlyContinue'
                                    }
                                    # Disable progress bar when calculating folder size
                                    if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 4)
                                    {
                                        $getSizeParams['ProgressAction'] = 'SilentlyContinue'
                                    }
                                    $folderSize = (Get-ChildItem @getSizeParams |
                                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                                    if ($null -eq $folderSize) { $folderSize = 0 }
                                }
                                catch
                                {
                                    Write-Verbose "Could not calculate size for: $($folder.FullName)"
                                    $folderSize = 0
                                }
                            }

                            # Remove the folder
                            $removeParams = @{
                                Path = $folder.FullName
                                Recurse = $true
                                Force = $true
                                ErrorAction = 'Stop'
                            }
                            # Disable progress bar during recursive folder deletion
                            if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 4)
                            {
                                $removeParams['ProgressAction'] = 'SilentlyContinue'
                            }
                            Remove-Item @removeParams
                            Write-Host "Removed: $($folder.FullName)" -ForegroundColor Green

                            $stats.FoldersRemoved++
                            $stats.TotalSpaceFreed += $folderSize
                        }
                        else
                        {
                            Write-Host "WhatIf: Would remove $($folder.FullName)" -ForegroundColor Yellow
                        }
                    }
                    catch
                    {
                        $stats.Errors++
                        Write-Warning "Failed to remove $($folder.FullName): $($_.Exception.Message)"
                        Write-Verbose "Error details: $($_.Exception)"
                    }
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
        $spaceFreedFormatted = if ($CalculateSize)
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
            'Not calculated (use -CalculateSize for details)'
        }

        # Display summary
        Write-Host "`nCleanup Summary:" -ForegroundColor Cyan
        Write-Host "  Projects found: $($stats.ProjectsFound)" -ForegroundColor White
        Write-Host "  Folders removed: $($stats.FoldersRemoved)" -ForegroundColor White

        if ($CalculateSize -and $stats.TotalSpaceFreed -gt 0)
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
            TotalProjectsFound = $stats.ProjectsFound
            FoldersRemoved = $stats.FoldersRemoved
            TotalSpaceFreed = $spaceFreedFormatted
            Errors = $stats.Errors
        }
    }
}
