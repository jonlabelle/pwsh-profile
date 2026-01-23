function Remove-NodeModules
{
    <#
    .SYNOPSIS
        Removes node_modules folders from Node.js project directories with optional recursion.

    .DESCRIPTION
        Searches for Node.js project files (package.json) and removes their associated node_modules
        folders. Only removes folders when a package.json file is found in the parent directory,
        ensuring only legitimate Node.js projects are cleaned. Recursion is controlled by the
        -Recurse switch.

        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Path
        The root path to search for Node.js projects. Defaults to the current directory.
        Supports ~ for home directory expansion.

    .PARAMETER ExcludeDirectory
        Array of directory names to exclude from the search. Defaults to @('.git').
        These directories and their subdirectories will not be searched for Node.js projects.

    .PARAMETER NoSizeCalculation
        Skips calculating the size of folders before removal. By default, folder sizes are calculated
        to provide detailed space freed information. Use this switch for large directory structures
        to significantly speed up execution.

    .PARAMETER Recurse
        When specified, searches for projects in subdirectories. Without this switch, only the
        specified path is inspected.

    .PARAMETER WhatIf
        Shows what would be removed without actually removing anything.

    .PARAMETER Confirm
        Prompts for confirmation before removing each folder.

    .EXAMPLE
        PS > Remove-NodeModules -Recurse

        Removes node_modules folders from Node.js projects in the current directory and subdirectories,
        showing the total space freed.

    .EXAMPLE
        PS > Remove-NodeModules -NoSizeCalculation

        Removes node_modules folders without calculating space freed (faster for large directory structures).

    .EXAMPLE
        PS > Remove-NodeModules -Path ~/Projects -Recurse -WhatIf

        Shows what would be removed in the ~/Projects directory and its subdirectories without actually removing anything.

    .EXAMPLE
        PS > Remove-NodeModules -Path C:\MyProjects -Recurse -Confirm

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
        - TotalSpaceFreed: Total disk space freed (unless -NoSizeCalculation is specified)
        - Errors: Number of errors encountered

    .NOTES
        - Requires PowerShell 5.1 or later
        - Only removes node_modules folders when a package.json file exists in the parent directory
        - Respects -WhatIf and -Confirm parameters for safety
        - Can free up significant disk space, especially in workspaces with many projects
        - Skips traversing node_modules directories during search to avoid unnecessary work

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Remove-NodeModules.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Remove-NodeModules.ps1

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
        [Switch]$NoSizeCalculation,

        [Parameter()]
        [Switch]$Recurse
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

        # Build exclusion lists for search (node_modules is always skipped)
        $searchExcludedDirectories = @()
        if ($ExcludeDirectory -and $ExcludeDirectory.Count -gt 0)
        {
            $searchExcludedDirectories += $ExcludeDirectory
        }
        $searchExcludedDirectories = @(
            $searchExcludedDirectories |
                Where-Object { $_ } |
                Select-Object -Unique
        )

        $recursionExcludedDirectories = @(
            ($searchExcludedDirectories + 'node_modules') |
                Where-Object { $_ } |
                Select-Object -Unique
        )

        if ($recursionExcludedDirectories -and $recursionExcludedDirectories.Count -gt 0)
        {
            Write-Verbose "Excluding directories from search: $($recursionExcludedDirectories -join ', ')"
        }

        function Test-IsExcludedPath
        {
            param(
                [String]$FilePath,
                [String[]]$ExcludedDirs
            )

            foreach ($excludeDir in $ExcludedDirs)
            {
                $escaped = [regex]::Escape([System.IO.Path]::DirectorySeparatorChar + $excludeDir + [System.IO.Path]::DirectorySeparatorChar)
                $escapedEnd = [regex]::Escape([System.IO.Path]::DirectorySeparatorChar + $excludeDir + '$')
                if ($FilePath -match $escaped -or $FilePath -match $escapedEnd)
                {
                    return $true
                }
            }
            return $false
        }

        function Get-NodeProjectDirectories
        {
            param(
                [String]$RootPath,
                [String]$ProjectFileName,
                [String[]]$ExcludedDirs,
                [Switch]$Recurse
            )

            $projectDirectories = New-Object System.Collections.Generic.List[string]
            $directoriesToScan = [System.Collections.Generic.Stack[string]]::new()

            if ($ExcludedDirs -and (Test-IsExcludedPath -FilePath $RootPath -ExcludedDirs $ExcludedDirs))
            {
                Write-Verbose "Skipping excluded path: $RootPath"
                return $projectDirectories
            }

            $directoriesToScan.Push($RootPath)

            while ($directoriesToScan.Count -gt 0)
            {
                $currentDir = $directoriesToScan.Pop()

                $projectFilePath = Join-Path -Path $currentDir -ChildPath $ProjectFileName
                if (Test-Path -Path $projectFilePath -PathType Leaf -ErrorAction SilentlyContinue)
                {
                    $projectDirectories.Add($currentDir)
                }

                if ($Recurse)
                {
                    try
                    {
                        $childDirectories = Get-ChildItem -Path $currentDir -Directory -ErrorAction SilentlyContinue
                    }
                    catch
                    {
                        Write-Verbose "Could not enumerate directories in: $currentDir"
                        Write-Verbose "Error details: $($_.Exception)"
                        continue
                    }

                    foreach ($childDir in $childDirectories)
                    {
                        if ($ExcludedDirs -and (Test-IsExcludedPath -FilePath $childDir.FullName -ExcludedDirs $ExcludedDirs))
                        {
                            continue
                        }

                        $directoriesToScan.Push($childDir.FullName)
                    }
                }
            }

            return $projectDirectories
        }
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

            Write-Verbose "Searching for Node.js projects in: $resolvedPath"

            $projectDirectories = Get-NodeProjectDirectories -RootPath $resolvedPath -ProjectFileName $projectPattern -ExcludedDirs $recursionExcludedDirectories -Recurse:$Recurse.IsPresent

            if (-not $projectDirectories -or $projectDirectories.Count -eq 0)
            {
                Write-Host 'No Node.js project files found in the specified path.' -ForegroundColor Yellow
                return
            }

            $stats.ProjectsFound = $projectDirectories.Count
            Write-Host "Found $($stats.ProjectsFound) Node.js project(s)" -ForegroundColor Cyan

            # Process each project
            foreach ($projectDir in $projectDirectories)
            {
                Write-Verbose "Processing project in $projectDir"

                # Look for node_modules folder in the project directory
                $nodeModulesPath = Join-Path -Path $projectDir -ChildPath 'node_modules'

                if (Test-Path -Path $nodeModulesPath -PathType Container)
                {
                    $folder = Get-Item -Path $nodeModulesPath

                    try
                    {
                        # Calculate folder size before removal (unless disabled)
                        $folderSize = [int64]0
                        if (-not $NoSizeCalculation)
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

                        if ($PSCmdlet.ShouldProcess($folder.FullName, 'Remove node_modules folder'))
                        {
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
                            $stats.TotalSpaceFreed += $folderSize
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
        Write-Host "  Projects found: $($stats.ProjectsFound)" -ForegroundColor White
        Write-Host "  Folders removed: $($stats.FoldersRemoved)" -ForegroundColor White

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
            TotalProjectsFound = $stats.ProjectsFound
            FoldersRemoved = $stats.FoldersRemoved
            TotalSpaceFreed = $spaceFreedFormatted
            Errors = $stats.Errors
        }
    }
}
