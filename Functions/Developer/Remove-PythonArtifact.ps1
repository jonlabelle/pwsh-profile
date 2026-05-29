function Remove-PythonArtifact
{
    <#
    .SYNOPSIS
        Removes Python build, test, environment, and cache artifacts from project directories.

    .DESCRIPTION
        Searches for and removes Python-related artifact directories and files, including
        bytecode caches (__pycache__, *.pyc, *.pyo, *.pyd), test caches (.pytest_cache),
        type-checker caches (.mypy_cache, .ruff_cache), virtual environments (.venv, venv),
        build output (dist, build, *.egg-info, .eggs), test runner environments (.tox, .nox),
        coverage artifacts (htmlcov, .coverage, coverage.xml), and tool-specific directories
        (.hatch, .pdm-build, .hypothesis, .ipynb_checkpoints, __pypackages__).

        Compatible with modern Python tooling including pip, setuptools, uv, hatch, PDM,
        poetry, tox, nox, pytest, mypy, and ruff.

        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

        NOTE: The 'dist' and 'build' directory names are also used by other ecosystems
        (JavaScript, Rust, etc.). Use -WhatIf first when running in mixed-language project trees.

    .PARAMETER Path
        The root path to search for Python artifacts. Defaults to the current directory.
        Supports ~ for home directory expansion.

    .PARAMETER ExcludeDirectory
        Array of directory names to exclude from the search. Defaults to @('.git', 'node_modules').
        These directories and their subdirectories will not be searched.

    .PARAMETER NoSizeCalculation
        Skips calculating the size of items before removal. By default, sizes are calculated
        to provide detailed space freed information. Use this switch for large directory trees
        to significantly speed up execution.

    .PARAMETER Recurse
        When specified, searches for artifacts in subdirectories. Without this switch, only
        the immediate children of the specified path are inspected.

    .PARAMETER WhatIf
        Shows what would be removed without actually removing anything.

    .PARAMETER Confirm
        Prompts for confirmation before removing each item.

    .EXAMPLE
        PS > Remove-PythonArtifact

        Removes Python artifact directories and files found directly in the current directory.

    .EXAMPLE
        PS > Remove-PythonArtifact -Recurse

        Recursively removes all Python artifacts throughout the current directory tree.

    .EXAMPLE
        PS > Remove-PythonArtifact -Recurse -WhatIf

        Shows what would be removed recursively without actually deleting anything.

    .EXAMPLE
        PS > Remove-PythonArtifact -Path ~/Projects -Recurse

        Recursively removes Python artifacts from all subdirectories under ~/Projects.

    .EXAMPLE
        PS > Remove-PythonArtifact -Path ~/Projects/myapp -WhatIf

        Shows what would be removed from a specific project directory without making any changes.

    .EXAMPLE
        PS > Remove-PythonArtifact -Recurse -NoSizeCalculation

        Removes artifacts without calculating space freed (faster for large directory trees).

    .EXAMPLE
        PS > Remove-PythonArtifact -Recurse -Confirm

        Removes artifacts with a confirmation prompt for each item.

    .EXAMPLE
        PS > Remove-PythonArtifact -Recurse -ExcludeDirectory @('.git', 'vendor', 'archive')

        Removes artifacts while excluding .git, vendor, and archive directories from the search.

    .EXAMPLE
        PS > Remove-PythonArtifact -Verbose

        Removes artifacts with detailed verbose output showing each operation.

    .EXAMPLE
        PS > Remove-PythonArtifact -Path ~/Projects -Recurse -NoSizeCalculation -WhatIf

        Quickly previews what would be removed throughout ~/Projects without size calculations.

    .OUTPUTS
        [PSCustomObject]
        Returns an object with summary information about the operation:
        - DirsRemoved: Number of artifact directories removed
        - FilesRemoved: Number of artifact files removed
        - TotalSpaceFreed: Total disk space freed (unless -NoSizeCalculation is specified)
        - Errors: Number of errors encountered

    .NOTES
        Artifact directories removed (when found):
          __pycache__, .pytest_cache, .mypy_cache, .ruff_cache, .tox, .nox, htmlcov,
          .eggs, *.egg-info, __pypackages__, .venv, venv, dist, build, .hatch,
          .pdm-build, .hypothesis, .ipynb_checkpoints

        Artifact files removed (when found):
          *.pyc, *.pyo, *.pyd, .coverage, .coverage.*, coverage.xml, .pdm-python

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Remove-PythonArtifact.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Remove-PythonArtifact.ps1
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
        [Switch]$NoSizeCalculation,

        [Parameter()]
        [Switch]$Recurse
    )

    begin
    {
        Write-Verbose 'Starting Python artifacts cleanup'

        $stats = @{
            DirsRemoved = 0
            FilesRemoved = 0
            TotalSpaceFreed = [int64]0
            Errors = 0
        }

        # Artifact directory names — exact match, case-insensitive.
        # Python tooling consistently uses lowercase names so OrdinalIgnoreCase is safe across platforms.
        $artifactDirNames = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        @(
            '__pycache__',        # Python bytecode cache
            '.pytest_cache',      # pytest cache
            '.mypy_cache',        # mypy type-checker cache
            '.ruff_cache',        # ruff linter cache
            '.tox',               # tox test environments
            '.nox',               # nox test environments
            'htmlcov',            # coverage HTML reports
            '.eggs',              # setuptools eggs staging directory
            '__pypackages__',     # PEP 582 package directory
            '.venv',              # virtual environment (PEP 405 / uv / hatch / poetry)
            'venv',               # virtual environment (alternate common name)
            'dist',               # distribution output (setuptools / build / flit)
            'build',              # build output (setuptools / build backend)
            '.hatch',             # hatch project environments
            '.pdm-build',         # PDM build artifacts
            '.hypothesis',        # Hypothesis testing framework database
            '.ipynb_checkpoints'  # Jupyter notebook checkpoints
        ) | ForEach-Object { [void]$artifactDirNames.Add($_) }

        # Artifact file patterns (glob match on file name)
        $artifactFilePatterns = @(
            '*.pyc',        # compiled Python bytecode
            '*.pyo',        # optimized bytecode (Python 2 / legacy)
            '*.pyd',        # Python extension module (Windows)
            '.coverage',    # coverage.py data file
            '.coverage.*',  # coverage.py parallel-mode data files
            'coverage.xml', # coverage XML report
            '.pdm-python'   # PDM Python interpreter reference file
        )

        function Test-IsArtifactDirectory
        {
            param(
                [String]$DirName,
                [System.Collections.Generic.HashSet[string]]$ArtifactNames
            )

            if ($ArtifactNames.Contains($DirName))
            {
                return $true
            }

            # Match *.egg-info pattern (setuptools egg-info directories)
            if ($DirName -like '*.egg-info')
            {
                return $true
            }

            return $false
        }

        function Test-IsArtifactFile
        {
            param(
                [String]$FileName,
                [String[]]$Patterns
            )

            foreach ($pattern in $Patterns)
            {
                if ($FileName -like $pattern)
                {
                    return $true
                }
            }
            return $false
        }

        function Test-IsExcludedPath
        {
            param(
                [String]$FilePath,
                [String[]]$ExcludedDirs
            )

            foreach ($excludeDir in $ExcludedDirs)
            {
                # Match any segment within the path (e.g. /vendor/ inside a deeper path)
                $escaped = [regex]::Escape([System.IO.Path]::DirectorySeparatorChar + $excludeDir + [System.IO.Path]::DirectorySeparatorChar)
                # Match when the path ends with the excluded directory name (no trailing separator)
                $escapedEnd = [regex]::Escape([System.IO.Path]::DirectorySeparatorChar + $excludeDir) + '$'
                if ($FilePath -match $escaped -or $FilePath -match $escapedEnd)
                {
                    return $true
                }
            }
            return $false
        }
    }

    process
    {
        try
        {
            $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

            if (-not (Test-Path -Path $resolvedPath -PathType Container))
            {
                Write-Error "Path not found or is not a directory: $resolvedPath"
                return
            }

            Write-Verbose "Searching for Python artifacts in: $resolvedPath"

            # Stack-based traversal: avoids recursion depth issues and allows skipping into
            # artifact directories so their contents are not double-counted.
            $dirsToScan = [System.Collections.Generic.Stack[string]]::new()
            $dirsToScan.Push($resolvedPath)

            while ($dirsToScan.Count -gt 0)
            {
                $currentDir = $dirsToScan.Pop()

                # --- Scan child directories ---
                $childDirs = $null
                try
                {
                    $childDirs = Get-ChildItem -Path $currentDir -Directory -Force -ErrorAction SilentlyContinue
                }
                catch
                {
                    Write-Verbose "Could not enumerate directories in: $currentDir - $($_.Exception.Message)"
                    continue
                }

                foreach ($childDir in $childDirs)
                {
                    if (Test-IsArtifactDirectory -DirName $childDir.Name -ArtifactNames $artifactDirNames)
                    {
                        # Artifact directory found — calculate size and remove
                        try
                        {
                            $itemSize = [int64]0
                            if (-not $NoSizeCalculation)
                            {
                                try
                                {
                                    $getSizeParams = @{
                                        Path = $childDir.FullName
                                        Recurse = $true
                                        File = $true
                                        ErrorAction = 'SilentlyContinue'
                                    }
                                    if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 4)
                                    {
                                        $getSizeParams['ProgressAction'] = 'SilentlyContinue'
                                    }
                                    $sizeResult = (Get-ChildItem @getSizeParams |
                                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                                    $itemSize = [int64](if ($null -eq $sizeResult) { 0 } else { $sizeResult })
                                }
                                catch
                                {
                                    Write-Verbose "Could not calculate size for: $($childDir.FullName)"
                                }
                            }

                            if ($PSCmdlet.ShouldProcess($childDir.FullName, 'Remove Python artifact directory'))
                            {
                                $removeParams = @{
                                    Path = $childDir.FullName
                                    Recurse = $true
                                    Force = $true
                                    ErrorAction = 'Stop'
                                }
                                if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 4)
                                {
                                    $removeParams['ProgressAction'] = 'SilentlyContinue'
                                }
                                Remove-Item @removeParams
                                Write-Host "Removed: $($childDir.FullName)" -ForegroundColor Green
                                $stats.DirsRemoved++
                                $stats.TotalSpaceFreed += $itemSize
                            }
                            else
                            {
                                Write-Host "WhatIf: Would remove $($childDir.FullName)" -ForegroundColor Yellow
                                $stats.TotalSpaceFreed += $itemSize
                            }
                        }
                        catch
                        {
                            $stats.Errors++
                            Write-Warning "Failed to remove $($childDir.FullName): $($_.Exception.Message)"
                            Write-Verbose "Error details: $($_.Exception)"
                        }
                        # Do NOT recurse into artifact directories
                    }
                    else
                    {
                        # Non-artifact directory — push onto stack if recursion is requested
                        if ($Recurse)
                        {
                            if ($ExcludeDirectory -and $ExcludeDirectory.Count -gt 0)
                            {
                                if (Test-IsExcludedPath -FilePath $childDir.FullName -ExcludedDirs $ExcludeDirectory)
                                {
                                    Write-Verbose "Skipping excluded directory: $($childDir.FullName)"
                                    continue
                                }
                            }
                            $dirsToScan.Push($childDir.FullName)
                        }
                    }
                }

                # --- Scan artifact files in the current directory ---
                $childFiles = $null
                try
                {
                    $childFiles = Get-ChildItem -Path $currentDir -File -Force -ErrorAction SilentlyContinue
                }
                catch
                {
                    Write-Verbose "Could not enumerate files in: $currentDir - $($_.Exception.Message)"
                    continue
                }

                foreach ($file in $childFiles)
                {
                    if (Test-IsArtifactFile -FileName $file.Name -Patterns $artifactFilePatterns)
                    {
                        try
                        {
                            $fileSize = [int64]0
                            if (-not $NoSizeCalculation)
                            {
                                $fileSize = $file.Length
                            }

                            if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove Python artifact file'))
                            {
                                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                                Write-Host "Removed: $($file.FullName)" -ForegroundColor Green
                                $stats.FilesRemoved++
                                $stats.TotalSpaceFreed += $fileSize
                            }
                            else
                            {
                                Write-Host "WhatIf: Would remove $($file.FullName)" -ForegroundColor Yellow
                                $stats.TotalSpaceFreed += $fileSize
                            }
                        }
                        catch
                        {
                            $stats.Errors++
                            Write-Warning "Failed to remove $($file.FullName): $($_.Exception.Message)"
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

        Write-Host "`nCleanup Summary:" -ForegroundColor Cyan
        Write-Host "  Directories removed: $($stats.DirsRemoved)" -ForegroundColor White
        Write-Host "  Files removed: $($stats.FilesRemoved)" -ForegroundColor White

        if (-not $NoSizeCalculation -and $stats.TotalSpaceFreed -gt 0)
        {
            Write-Host "  Space freed: $spaceFreedFormatted" -ForegroundColor Green
        }

        if ($stats.Errors -gt 0)
        {
            Write-Host "  Errors: $($stats.Errors)" -ForegroundColor Red
        }

        Write-Verbose 'Cleanup completed'

        return [PSCustomObject]@{
            DirsRemoved = $stats.DirsRemoved
            FilesRemoved = $stats.FilesRemoved
            TotalSpaceFreed = $spaceFreedFormatted
            Errors = $stats.Errors
        }
    }
}
