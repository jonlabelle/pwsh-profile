function Remove-DotNetBuildArtifacts
{
    <#
    .SYNOPSIS
        Removes bin and obj folders from .NET project directories.

    .DESCRIPTION
        Recursively searches for .NET project files (.csproj, .vbproj, .fsproj, .sqlproj) and removes
        their associated bin and obj build artifact folders. Only removes folders when a project file
        is found in the parent directory, similar to 'dotnet clean' but more thorough.

        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Path
        The root path to search for .NET projects. Defaults to the current directory.
        Supports ~ for home directory expansion.

    .PARAMETER ExcludeDirectory
        Array of directory names to exclude from the search. Defaults to @('.git', 'node_modules').
        These directories and their subdirectories will not be searched for .NET projects.

    .PARAMETER NoSizeCalculation
        Skips calculating the size of folders before removal. By default, folder sizes are calculated
        to provide detailed space freed information. Use this switch for large directory structures
        to significantly speed up execution.

    .PARAMETER WhatIf
        Shows what would be removed without actually removing anything.

    .PARAMETER Confirm
        Prompts for confirmation before removing each folder.

    .EXAMPLE
        PS > Remove-DotNetBuildArtifacts

        Removes all bin and obj folders from .NET projects in the current directory and subdirectories,
        showing the total space freed.

    .EXAMPLE
        PS > Remove-DotNetBuildArtifacts -NoSizeCalculation

        Removes build artifacts without calculating space freed (faster for large directory structures).

    .EXAMPLE
        PS > Remove-DotNetBuildArtifacts -Path ~/Projects -WhatIf

        Shows what would be removed in the ~/Projects directory without actually removing anything.

    .EXAMPLE
        PS > Remove-DotNetBuildArtifacts -Path C:\MyProjects -Confirm

        Removes build artifacts with confirmation prompts for each folder.

    .EXAMPLE
        PS > Remove-DotNetBuildArtifacts -Verbose

        Removes build artifacts with detailed verbose output showing each operation.

    .EXAMPLE
        PS > Remove-DotNetBuildArtifacts -Path ~/Projects -ExcludeDirectory @('.git', 'node_modules', 'vendor')

        Removes build artifacts while excluding .git, node_modules, and vendor directories from the search.

    .OUTPUTS
        [PSCustomObject]
        Returns an object with summary information about the operation:
        - TotalProjectsFound: Number of .NET projects discovered
        - FoldersRemoved: Number of folders successfully removed
        - TotalSpaceFreed: Total disk space freed (unless -NoSizeCalculation is specified)
        - Errors: Number of errors encountered

    .LINK
        https://docs.microsoft.com/en-us/dotnet/core/tools/dotnet-clean

    .NOTES
        - Requires PowerShell 5.1 or later
        - Only removes bin/obj folders when a .NET project file exists in the parent directory
        - Respects -WhatIf and -Confirm parameters for safety
        - Processes .csproj, .vbproj, .fsproj, and .sqlproj project files

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Remove-DotNetBuildArtifacts.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$Path = (Get-Location).Path,

        [Parameter()]
        [String[]]$ExcludeDirectory = @('.git', 'node_modules'),

        [Parameter()]
        [Switch]$NoSizeCalculation
    )

    begin
    {
        Write-Verbose 'Starting .NET build artifacts cleanup'

        # Statistics tracking
        $stats = @{
            ProjectsFound = 0
            FoldersRemoved = 0
            TotalSpaceFreed = [int64]0
            Errors = 0
        }

        # Project file patterns
        $projectPatterns = @('*.csproj', '*.vbproj', '*.fsproj', '*.sqlproj')

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
            $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

            if (-not (Test-Path -Path $resolvedPath -PathType Container))
            {
                Write-Error "Path not found or is not a directory: $resolvedPath"
                return
            }

            Write-Verbose "Searching for .NET projects in: $resolvedPath"

            # Build Get-ChildItem parameters
            $getChildItemParams = @{
                Path = $resolvedPath
                Include = $projectPatterns
                File = $true
                Recurse = $true
                ErrorAction = 'SilentlyContinue'
            }

            # Disable progress bar for recursive file search (PowerShell 7.4+)
            if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 4)
            {
                $getChildItemParams['ProgressAction'] = 'SilentlyContinue'
            }

            # Add exclusions if specified
            if ($ExcludeDirectory -and $ExcludeDirectory.Count -gt 0)
            {
                $getChildItemParams['Exclude'] = $ExcludeDirectory
            }

            # Find all .NET project files
            $allProjectFiles = Get-ChildItem @getChildItemParams

            # Additional filtering for excluded directories (Get-ChildItem -Exclude only works on names, not paths)
            # So we need to filter out any files that are inside excluded directories
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
                Write-Host 'No .NET project files found in the specified path.' -ForegroundColor Yellow
                return
            }

            $stats.ProjectsFound = $projectFiles.Count
            Write-Host "Found $($stats.ProjectsFound) .NET project(s)" -ForegroundColor Cyan

            # Process each project
            foreach ($projectFile in $projectFiles)
            {
                $projectDir = $projectFile.DirectoryName
                Write-Verbose "Processing project: $($projectFile.Name) in $projectDir"

                # Look for bin and obj folders in the project directory
                $artifactFolders = @('bin', 'obj') | ForEach-Object {
                    $folderPath = Join-Path -Path $projectDir -ChildPath $_
                    if (Test-Path -Path $folderPath -PathType Container)
                    {
                        Get-Item -Path $folderPath
                    }
                }

                # Remove the artifact folders
                foreach ($folder in $artifactFolders)
                {
                    if ($folder)
                    {
                        try
                        {
                            # Calculate folder size before removal (unless disabled)
                            $folderSize = [int64]0
                            if ($PSCmdlet.ShouldProcess($folder.FullName, 'Remove build artifact folder'))
                            {
                                # Calculate size for reporting (unless -NoSizeCalculation is specified)
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
