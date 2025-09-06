function Rename-VideoSeasonFile
{
    <#
    .SYNOPSIS
        Renames files into their proper season sequence format.

    .DESCRIPTION
        This function searches for video files with season/episode identifiers in their names
        (patterns like S01E01, s1e1, Season 1 Episode 1, etc.) and renames them to a clean,
        standardized format containing only the season/episode identifier. It's useful for
        organizing TV show collections by removing extra information like quality indicators,
        release groups, and other metadata from filenames.

        The function creates clean filenames in the format S##E##.ext (e.g., S01E01.mkv)
        regardless of the original filename complexity.

    .PARAMETER Path
        The directory path(s) to search for video files.
        Accepts an array of paths and supports pipeline input.
        Default is the current working directory.
        Must be valid directory paths.

    .PARAMETER Filters
        The file extensions to search for.
        Default filters are @('*.mkv', '*.mp4', '*.mov', '*.avi', '*.m4v', '*.wmv').

    .PARAMETER Exclude
        Specifies directory names to exclude from the search.
        Default exclusions are @('.git', 'node_modules', '.vscode').

    .PARAMETER PassThru
        Returns objects representing the renamed files.

    .EXAMPLE
        PS > Rename-VideoSeasonFile -Verbose -WhatIf

        Displays what would happen if the function ran with the default options, showing which files would be renamed.

    .EXAMPLE
        PS > Rename-VideoSeasonFile -Path 'D:\TV Shows\Breaking Bad' -Filters '*.mp4' -Verbose

        Renames all MP4 files in the specified directory that contain season identifiers to clean S##E##.mp4 format.
        For example: "Breaking.Bad.S01E01.1080p.BluRay.x264-DEMAND.mp4" becomes "S01E01.mp4"

    .EXAMPLE
        PS > Rename-VideoSeasonFile -Path 'D:\Downloads' -Exclude @('.git', 'node_modules', 'temp') -PassThru

        Renames video files in the Downloads folder, excluding specified directories, and returns information about renamed files.

    .EXAMPLE
        PS > Rename-VideoSeasonFile -Path @('D:\TV Shows\Breaking Bad', 'D:\TV Shows\Better Call Saul') -Filters '*.mp4' -Verbose

        Renames all MP4 files in multiple specified directories that contain season identifiers.

    .EXAMPLE
        PS > @('D:\TV Shows', 'D:\Movies') | Rename-VideoSeasonFile -PassThru

        Renames video files in multiple directories using pipeline input and returns information about renamed files.

    .EXAMPLE
        PS > Get-ChildItem -Directory 'D:\TV Shows' | Rename-VideoSeasonFile -Verbose

        Processes video files in all subdirectories of the TV Shows folder via pipeline input.

    .OUTPUTS
        System.IO.FileInfo
        When PassThru is specified, returns FileInfo objects for renamed files.

    .NOTES
        Version: 2.0.0
        Date: August 24, 2025
        Author: Jon LaBelle
        License: MIT

        Supported patterns:
        - S01E01, s01e01 (standard format)
        - S1E1, s1e1 (short format)
        - Season 1 Episode 1, season 1 episode 1
        - 1x01, 1X01 (alternative format)

    .LINK
        https://jonlabelle.com/snippets/view/powershell/rename-video-season-sequence-files-in-powershell
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Directory', 'Folder', 'Location')]
        [ValidateScript({
                if (-not (Test-Path -Path $_ -PathType Container))
                {
                    throw "Path '$_' does not exist or is not a directory."
                }
                $true
            })]
        [String[]]$Path = @($PWD.Path),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$Filters = @('*.mkv', '*.mp4', '*.mov', '*.avi', '*.m4v', '*.wmv'),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$Exclude = @('.git', 'node_modules', '.vscode'),

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        Write-Verbose "Starting video file rename process for $($Path.Count) path(s)"

        # Enhanced regex patterns to match various season/episode formats
        $patterns = @(
            [PSCustomObject]@{
                Name = 'Standard'
                Regex = '[Ss](\d{1,2})[Ee](\d{1,2})'
                Description = 'S01E01 or s01e01 format'
            },
            [PSCustomObject]@{
                Name = 'Alternative'
                Regex = '(\d{1,2})[xX](\d{1,2})'
                Description = '1x01 or 1X01 format'
            },
            [PSCustomObject]@{
                Name = 'Verbose'
                Regex = '[Ss]eason\s*(\d{1,2})\s*[Ee]pisode\s*(\d{1,2})'
                Description = 'Season 1 Episode 01 format'
            }
        )

        $renamedFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $processedCount = 0
        $renamedCount = 0
        $totalFilesAcrossAllPaths = 0
        $startTime = Get-Date
    }

    process
    {
        # First pass: collect all files to get total count for progress reporting
        $allFilesToProcess = @()

        foreach ($currentPath in $Path)
        {
            Write-Verbose "Scanning path: $currentPath"

            if ([String]::IsNullOrWhiteSpace($currentPath))
            {
                Write-Warning 'Path parameter is null or empty, skipping.'
                continue
            }

            # Validate Input Directory
            if (-not (Test-Path -Path $currentPath -PathType Container))
            {
                Write-Error "Input directory not found: '$currentPath'"
                continue
            }

            # Get all video files for current path
            $allVideoFiles = @()
            foreach ($filter in $Filters)
            {
                try
                {
                    $filesForFilter = Get-ChildItem -Path $currentPath -Filter $filter -Recurse -File -ErrorAction Stop

                    # Apply exclusion filter if needed
                    if ($Exclude.Count -gt 0)
                    {
                        $filesForFilter = $filesForFilter | Where-Object {
                            $filePath = $_.DirectoryName
                            $shouldExclude = $false
                            foreach ($excludeDir in $Exclude)
                            {
                                if ($filePath -like "*$([System.IO.Path]::DirectorySeparatorChar)$excludeDir" -or
                                    $filePath -like "*$([System.IO.Path]::DirectorySeparatorChar)$excludeDir$([System.IO.Path]::DirectorySeparatorChar)*")
                                {
                                    $shouldExclude = $true
                                    break
                                }
                            }
                            -not $shouldExclude
                        }
                    }

                    Write-Verbose "Found $($filesForFilter.Count) files with filter '$filter'"
                    $allVideoFiles += $filesForFilter
                }
                catch
                {
                    Write-Error "Error searching for files with filter '$filter' in path '$currentPath': $($_.Exception.Message)"
                    continue
                }
            }

            foreach ($file in $allVideoFiles)
            {
                $allFilesToProcess += [PSCustomObject]@{
                    File = $file
                    SourcePath = $currentPath
                }
            }
        }

        $totalFilesAcrossAllPaths = $allFilesToProcess.Count

        if ($totalFilesAcrossAllPaths -eq 0)
        {
            Write-Warning 'No video files with supported extensions found in any of the specified paths'
            return
        }

        Write-Verbose "Found $totalFilesAcrossAllPaths video files to process across all paths"

        # Second pass: process all files with unified progress reporting
        foreach ($fileInfo in $allFilesToProcess)
        {
            $processedCount++
            $file = $fileInfo.File
            $currentPath = $fileInfo.SourcePath

            Write-Verbose "Processing file $processedCount/$($totalFilesAcrossAllPaths): '$($file.Name)' from '$currentPath'"

            $matchFound = $false
            $newBaseName = $null

            # Try each pattern until we find a match
            foreach ($pattern in $patterns)
            {
                if ($file.BaseName -match $pattern.Regex)
                {
                    $matchFound = $true
                    $season = $Matches[1].PadLeft(2, '0')
                    $episode = $Matches[2].PadLeft(2, '0')

                    # Create standardized S##E## format as the entire new basename
                    $newBaseName = "S${season}E${episode}"

                    Write-Verbose "Matched pattern '$($pattern.Name)' ($($pattern.Description))"
                    Write-Verbose "Season: $season, Episode: $episode"
                    Write-Verbose "Clean filename will be: $newBaseName$($file.Extension.ToLower())"
                    break
                }
            }

            if (-not $matchFound)
            {
                Write-Verbose "No season/episode pattern found in: '$($file.Name)'"
                continue
            }

            # Check if rename is needed
            if ($newBaseName -ceq $file.BaseName)
            {
                Write-Verbose "File already has correct format: '$($file.Name)'"
                continue
            }

            $newFileName = "$newBaseName$($file.Extension.ToLower())"
            $newFullPath = [System.IO.Path]::Combine($file.DirectoryName, $newFileName)

            # Check if target file already exists
            if (Test-Path -Path $newFullPath -PathType Leaf)
            {
                Write-Warning "Target file already exists, skipping: '$newFileName'"
                continue
            }

            if ($PSCmdlet.ShouldProcess($file.FullName, "Rename to '$newFileName'"))
            {
                try
                {
                    Write-Verbose "Renaming: '$($file.Name)' -> '$newFileName'"
                    $renamedFile = Move-Item -LiteralPath $file.FullName -Destination $newFullPath -PassThru -ErrorAction Stop
                    $renamedFiles.Add($renamedFile)
                    $renamedCount++

                    Write-Host 'Renamed: ' -ForegroundColor Green -NoNewline
                    Write-Host "'$($file.Name)' " -ForegroundColor White -NoNewline
                    Write-Host '-> ' -ForegroundColor Yellow -NoNewline
                    Write-Host "'$newFileName'" -ForegroundColor Cyan
                }
                catch
                {
                    Write-Error "Failed to rename '$($file.Name)': $($_.Exception.Message)"
                }
            }
        }
    }

    end
    {
        # Calculate elapsed time
        $endTime = Get-Date
        $elapsedTime = $endTime - $startTime
        $elapsedFormatted = if ($elapsedTime.TotalMinutes -ge 1)
        {
            '{0:mm\:ss}' -f $elapsedTime
        }
        else
        {
            '{0:ss\.ff} seconds' -f $elapsedTime
        }

        Write-Verbose 'Rename operation completed'
        Write-Verbose "Files processed: $processedCount"
        Write-Verbose "Files renamed: $renamedCount"
        Write-Verbose "Total elapsed time: $elapsedFormatted"

        if ($processedCount -gt 0)
        {
            Write-Host "`nSummary: " -ForegroundColor Magenta -NoNewline
            Write-Host "Processed $processedCount files across $($Path.Count) path(s), renamed $renamedCount files" -ForegroundColor White

            if ($elapsedTime.TotalSeconds -ge 1)
            {
                Write-Host 'Elapsed time: ' -ForegroundColor Cyan -NoNewline
                Write-Host "$elapsedFormatted" -ForegroundColor White
            }
        }

        if ($PassThru -and $renamedFiles.Count -gt 0)
        {
            return $renamedFiles.ToArray()
        }
    }
}
