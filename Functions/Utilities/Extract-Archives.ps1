function Extract-Archives
{
    <#
    .SYNOPSIS
        Extracts archive files in a directory to folders named after each archive, with optional nested extraction.

    .DESCRIPTION
        Searches a target directory (current directory by default) for supported archive
        types and extracts each one into a folder that matches the archive name without
        its extension. Supports optional recursive search and optional extraction of
        newly discovered archives created by earlier extractions (use -ExtractNested
        to enable). When -Force is specified, existing destination folders are removed
        before extraction.

        Supported archive types:
        - .zip (uses Expand-Archive)
        - .tar, .tar.gz, .tgz, .tar.bz2, .tbz, .tbz2, .tar.xz, .txz (uses tar)
        - .7z and .rar (uses 7z/7za if available)

        Multi-part archives are detected and only the primary part is processed. Common
        patterns such as .part1.rar, .r00 sets, .z01 sets, and .zip/.rar.001 style
        volumes are supported when 7z/7za is available.

    .PARAMETER Path
        The directory to search for archives. Defaults to the current directory.
        Accepts pipeline input.

    .PARAMETER Recurse
        Recursively search subdirectories for archives.

    .PARAMETER Include
        Archive name patterns to include (wildcards supported). If omitted, all supported
        archives are processed.

    .PARAMETER Exclude
        Archive name patterns to exclude (wildcards supported).

    .PARAMETER DestinationRoot
        Optional root directory to place extracted folders. Each archive is still
        extracted into its own subfolder (matching the archive name) beneath this root.

    .PARAMETER ExtractNested
        After extracting an archive, scan the newly created destination for additional
        archives and extract them as well. This is useful for chained or multi-layer
        archive sets (for example, zip parts that contain rar parts).

    .PARAMETER DeleteArchive
        Remove the archive file (or multipart set) after a successful extraction. Files
        are only removed when extraction completes without errors.

    .PARAMETER MergeMultipartAcrossDirectories
        When extracting multipart archives, treat parts with the same base name as a
        single set even if they reside in different directories, staging the parts
        together before extraction. Useful for scenarios where each volume is wrapped
        in its own archive and expanded into separate folders.

    .PARAMETER Force
        Overwrite existing destination folders by removing them before extraction.

    .EXAMPLE
        PS > Extract-Archives

        Extracts all supported archives in the current directory into folders named
        after each archive.

    .EXAMPLE
        PS > Extract-Archives -Path ~/Downloads -Recurse -Force

        Recursively extracts archives under ~/Downloads, overwriting any existing
        destination folders.

    .EXAMPLE
        PS > 'C:\Archives', './artifacts' | Extract-Archives -Recurse

        Processes multiple directories from the pipeline and extracts archives found
        in each location.

    .EXAMPLE
        PS > Extract-Archives -Path ./artifacts -Include '*.zip','*.tar.gz'

        Extracts only .zip and .tar.gz archives under ./artifacts, leaving other
        archive types untouched.

    .EXAMPLE
        PS > Extract-Archives -Path ./logs -Exclude '*old*','*backup*'

        Extracts supported archives under ./logs while skipping any whose names
        contain "old" or "backup".

    .EXAMPLE
        PS > Extract-Archives -Path ./archives -DestinationRoot ~/Extracted

        Places extracted folders beneath ~/Extracted instead of alongside the
        original archives.

    .EXAMPLE
        PS > Extract-Archives -Recurse -WhatIf

        Shows which archives would be extracted recursively without making any
        changes.

    .EXAMPLE
        PS > Extract-Archives -Path ./downloads -ExtractNested -Recurse

        Extracts archives under ./downloads, then continues extracting archives that
        appear inside newly created destinations (useful for zip-to-rar chains).

    .EXAMPLE
        PS > Extract-Archives -Path ./media -Recurse -ExtractNested -MergeMultipartAcrossDirectories

        Recurses through ./media, stages multipart volumes that were unpacked into
        separate folders (for example, zip parts that each contain rar volumes),
        merges them, and extracts the combined payload.

    .EXAMPLE
        PS > Get-ChildItem ~/Downloads -Directory | Extract-Archives -DestinationRoot ~/Unpacked

        Sends directories from Get-ChildItem through the pipeline for processing and
        extracts any archives found into ~/Unpacked.

    .OUTPUTS
        PSCustomObject
        Returns a summary object with TotalArchives, Extracted, Skipped, Failed, and
        Results (detailed per-archive status) properties.

    .NOTES
        - Requires the tar command for tar-based archives.
        - Requires 7z or 7za for .7z and .rar archives.
        - Respects -WhatIf and -Confirm via SupportsShouldProcess.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Extract-Archives.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Extract-Archives.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [String]$Path = (Get-Location).Path,

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [String[]]$Include,

        [Parameter()]
        [String[]]$Exclude,

        [Parameter()]
        [String]$DestinationRoot,

        [Parameter()]
        [Switch]$ExtractNested,

        [Parameter()]
        [Switch]$DeleteArchive,

        [Parameter()]
        [Switch]$MergeMultipartAcrossDirectories,

        [Parameter()]
        [Switch]$Force
    )

    begin
    {
        $results = New-Object -TypeName System.Collections.Generic.List[PSCustomObject]
        $tarCommand = Get-Command -Name 'tar' -ErrorAction SilentlyContinue
        $sevenZipCommand = Get-Command -Name '7z', '7za' -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($DestinationRoot)
        {
            $DestinationRoot = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationRoot)
        }

        function Get-ArchiveType
        {
            param([String]$FileName)

            $lowerName = $FileName.ToLowerInvariant()
            switch ($lowerName)
            {
                { $_ -match '\.zip(\.\d{3,})?$' } { return 'Zip' }
                { $_ -match '\.z\d{2,3}$' } { return 'Zip' }
                { $_ -match '\.part\d+\.zip$' } { return 'Zip' }
                { $_ -like '*.tar.gz' -or $_ -like '*.tgz' } { return 'Tar' }
                { $_ -like '*.tar.bz2' -or $_ -like '*.tbz' -or $_ -like '*.tbz2' } { return 'Tar' }
                { $_ -like '*.tar.xz' -or $_ -like '*.txz' } { return 'Tar' }
                { $_ -like '*.tar' } { return 'Tar' }
                { $_ -match '\.7z(\.\d{3,})?$' } { return 'SevenZip' }
                { $_ -match '\.rar(\.\d{3,})?$' } { return 'SevenZip' }
                { $_ -match '\.part\d+\.rar$' } { return 'SevenZip' }
                { $_ -match '\.r\d{2,3}$' } { return 'SevenZip' }
                default { return $null }
            }
        }

        function Get-ArchiveBaseName
        {
            param([String]$FileName)

            $lowerName = $FileName.ToLowerInvariant()
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
            if ($lowerName -match '\.tar\.(gz|bz2|xz)$' -or
                $lowerName -like '*.tgz' -or
                $lowerName -like '*.tbz' -or
                $lowerName -like '*.tbz2' -or
                $lowerName -like '*.txz')
            {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
            }

            if ($lowerName -match '\.part\d+\.(rar|7z|zip)$')
            {
                $baseName = $baseName -replace '\.part\d+$', ''
            }
            elseif ($lowerName -match '\.(rar|zip|7z)\.\d{3,}$')
            {
                $baseName = $baseName -replace '\.(rar|zip|7z)$', ''
            }

            return $baseName
        }

        function MatchesPattern
        {
            param(
                [String]$Name,
                [String[]]$Patterns
            )

            if (-not $Patterns -or $Patterns.Count -eq 0)
            {
                return $true
            }

            foreach ($pattern in $Patterns)
            {
                if ($Name -like $pattern)
                {
                    return $true
                }
            }

            return $false
        }

        function Get-MultipartMetadata
        {
            param([System.IO.FileInfo]$Archive)

            $name = $Archive.Name
            $lowerName = $name.ToLowerInvariant()
            $baseName = Get-ArchiveBaseName -FileName $name
            $groupIdentifier = $null
            $isMultipart = $false
            $isPrimary = $true

            if ($lowerName -match '^(?<root>.+)\.part(?<index>\d+)\.(?<ext>rar|7z|zip)$')
            {
                $isMultipart = $true
                $baseName = $Matches['root']
                $groupIdentifier = "$($Matches['root']).$($Matches['ext'])"
                $isPrimary = ([int]$Matches['index'] -eq 1)
            }
            elseif ($lowerName -match '^(?<root>.+)\.(?<ext>rar|zip|7z)\.(?<index>\d{3,})$')
            {
                $isMultipart = $true
                $baseName = $Matches['root']
                $groupIdentifier = "$($Matches['root']).$($Matches['ext'])"
                $isPrimary = ($Matches['index'] -eq '001')
            }
            elseif ($lowerName -match '^(?<root>.+)\.z(?<index>\d{2,3})$')
            {
                $isMultipart = $true
                $groupIdentifier = "$($Matches['root']).zip"
                $isPrimary = $false
            }
            elseif ($lowerName -match '^(?<root>.+)\.r(?<index>\d{2,3})$')
            {
                $isMultipart = $true
                $groupIdentifier = "$($Matches['root']).rar"
                $isPrimary = $false
            }
            elseif ($lowerName -match '\.zip$')
            {
                $groupIdentifier = "$($Archive.BaseName).zip"
                $z01 = Join-Path -Path $Archive.Directory.FullName -ChildPath "$($Archive.BaseName).z01"
                if (Test-Path -LiteralPath $z01)
                {
                    $isMultipart = $true
                }
            }
            elseif ($lowerName -match '\.rar$')
            {
                $groupIdentifier = "$($Archive.BaseName).rar"
                $r00 = Join-Path -Path $Archive.Directory.FullName -ChildPath "$($Archive.BaseName).r00"
                if (Test-Path -LiteralPath $r00)
                {
                    $isMultipart = $true
                }
            }
            elseif ($lowerName -match '\.7z$')
            {
                $groupIdentifier = "$($Archive.BaseName).7z"
            }
            else
            {
                $groupIdentifier = $Archive.FullName
            }

            if ($groupIdentifier)
            {
                $groupKey = if ($MergeMultipartAcrossDirectories) { $groupIdentifier.ToLowerInvariant() } else { '{0}|{1}' -f $Archive.Directory.FullName.ToLowerInvariant(), $groupIdentifier.ToLowerInvariant() }
            }
            else
            {
                $groupKey = $Archive.FullName.ToLowerInvariant()
            }

            return [PSCustomObject]@{
                BaseName = $baseName
                GroupKey = $groupKey
                IsMultipart = $isMultipart
                IsPrimary = $isPrimary
            }
        }

        function Get-MultipartPartFiles
        {
            param(
                [System.IO.FileInfo]$Archive,
                [String]$SearchRoot
            )

            $lowerName = $Archive.Name.ToLowerInvariant()
            $patterns = @($Archive.Name)

            if ($lowerName -match '^(?<root>.+)\.part(?<index>\d+)\.(?<ext>rar|7z|zip)$')
            {
                $patterns = @("$($Matches['root']).part*.$($Matches['ext'])")
            }
            elseif ($lowerName -match '^(?<root>.+)\.(?<ext>rar|zip|7z)\.(?<index>\d{3,})$')
            {
                $patterns = @("$($Matches['root']).$($Matches['ext']).*")
            }
            elseif ($lowerName -match '^(?<root>.+)\.z(?<index>\d{2,3})$')
            {
                $patterns = @("$($Matches['root']).z??")
            }
            elseif ($lowerName -match '^(?<root>.+)\.r(?<index>\d{2,3})$')
            {
                $patterns = @("$($Matches['root']).r??")
            }
            elseif ($lowerName -match '\.rar$')
            {
                $patterns = @("$($Archive.BaseName).rar", "$($Archive.BaseName).r??")
            }

            $found = New-Object -TypeName System.Collections.Generic.List[System.IO.FileInfo]
            foreach ($pattern in $patterns)
            {
                $items = Get-ChildItem -Path $SearchRoot -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue
                if ($items)
                {
                    foreach ($item in $items)
                    {
                        $found.Add($item)
                    }
                }
            }

            return $found | Sort-Object -Property FullName -Unique
        }

        function Write-MissingDependency
        {
            param(
                [String]$ArchivePath,
                [String]$Dependency
            )

            Write-Host "Skipping $ArchivePath (missing dependency: $Dependency)" -ForegroundColor Yellow
        }

        $processedArchives = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $processedGroups = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    }

    process
    {
        $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container))
        {
            throw "Path not found or is not a directory: $Path"
        }

        if ($DestinationRoot -and -not (Test-Path -LiteralPath $DestinationRoot))
        {
            if ($PSCmdlet.ShouldProcess($DestinationRoot, 'Create destination root'))
            {
                New-Item -ItemType Directory -Path $DestinationRoot -Force -ErrorAction Stop | Out-Null
            }
        }

        $directoriesToProcess = New-Object 'System.Collections.Generic.Queue[string]'
        $directoriesToProcess.Enqueue($resolvedPath)

        while ($directoriesToProcess.Count -gt 0)
        {
            $currentPath = $directoriesToProcess.Dequeue()

            $getChildItemParams = @{
                Path = $currentPath
                File = $true
                ErrorAction = 'Stop'
                Force = $true
            }
            if ($Recurse)
            {
                $getChildItemParams['Recurse'] = $true
            }

            $archives = Get-ChildItem @getChildItemParams | Where-Object { Get-ArchiveType $_.Name }
            $archives = $archives | Where-Object { MatchesPattern -Name $_.Name -Patterns $Include }
            if ($Exclude)
            {
                $archives = $archives | Where-Object { -not (MatchesPattern -Name $_.Name -Patterns $Exclude) }
            }

            if (-not $archives)
            {
                Write-Verbose "No archives found under: $currentPath"
                continue
            }

            foreach ($archive in $archives)
            {
                if (-not $processedArchives.Add($archive.FullName))
                {
                    continue
                }

                $archiveType = Get-ArchiveType -FileName $archive.Name
                if (-not $archiveType)
                {
                    continue
                }

                $multipartInfo = Get-MultipartMetadata -Archive $archive
                if (-not $multipartInfo.IsPrimary)
                {
                    Write-Verbose "Skipping secondary part of multipart archive: $($archive.FullName)"
                    continue
                }

                if ($multipartInfo.GroupKey -and -not $processedGroups.Add($multipartInfo.GroupKey))
                {
                    Write-Verbose "Skipping already processed archive set: $($archive.FullName)"
                    continue
                }

                $effectiveDestinationRoot = if ($DestinationRoot)
                {
                    $DestinationRoot
                }
                elseif ($MergeMultipartAcrossDirectories -and $multipartInfo.IsMultipart)
                {
                    $resolvedPath
                }
                else
                {
                    $archive.Directory.FullName
                }
                $destination = Join-Path -Path $effectiveDestinationRoot -ChildPath $multipartInfo.BaseName
                $status = 'Pending'
                $errorMessage = $null
                $stagingPath = $null
                $workingArchivePath = $archive.FullName
                $multipartParts = @($archive)

                try
                {
                    if ($archiveType -eq 'Tar' -and -not $tarCommand)
                    {
                        $status = 'SkippedMissingDependency'
                        $errorMessage = 'Missing required dependency: tar'
                        Write-MissingDependency -ArchivePath $archive.FullName -Dependency 'tar'
                        $results.Add([PSCustomObject]@{
                                Archive = $archive.FullName
                                Destination = $destination
                                Type = $archiveType
                                Status = $status
                                ErrorMessage = $errorMessage
                            }) | Out-Null
                        continue
                    }

                    if ($archiveType -eq 'SevenZip' -and -not $sevenZipCommand)
                    {
                        $status = 'SkippedMissingDependency'
                        $errorMessage = 'Missing required dependency: 7z/7za'
                        Write-MissingDependency -ArchivePath $archive.FullName -Dependency '7z/7za'
                        $results.Add([PSCustomObject]@{
                                Archive = $archive.FullName
                                Destination = $destination
                                Type = $archiveType
                                Status = $status
                                ErrorMessage = $errorMessage
                            }) | Out-Null
                        continue
                    }

                    if ($archiveType -eq 'Zip' -and $multipartInfo.IsMultipart -and -not $sevenZipCommand)
                    {
                        $status = 'SkippedMissingDependency'
                        $errorMessage = 'Multi-part zip extraction requires 7z/7za'
                        Write-MissingDependency -ArchivePath $archive.FullName -Dependency '7z/7za (required for multi-part zip)'
                        $results.Add([PSCustomObject]@{
                                Archive = $archive.FullName
                                Destination = $destination
                                Type = $archiveType
                                Status = $status
                                ErrorMessage = $errorMessage
                            }) | Out-Null
                        continue
                    }

                    $shouldExtract = $PSCmdlet.ShouldProcess($archive.FullName, "Extract to $destination")
                    $shouldRemove = $true

                    if (Test-Path -LiteralPath $destination)
                    {
                        if ($Force)
                        {
                            $shouldRemove = $PSCmdlet.ShouldProcess($destination, 'Remove existing destination')
                        }
                        else
                        {
                            $status = 'SkippedExisting'
                            $results.Add([PSCustomObject]@{
                                    Archive = $archive.FullName
                                    Destination = $destination
                                    Type = $archiveType
                                    Status = $status
                                    ErrorMessage = $null
                                }) | Out-Null
                            continue
                        }
                    }

                    if (-not ($shouldExtract -and $shouldRemove))
                    {
                        $status = 'SkippedWhatIf'
                        $results.Add([PSCustomObject]@{
                                Archive = $archive.FullName
                                Destination = $destination
                                Type = $archiveType
                                Status = $status
                                ErrorMessage = $null
                            }) | Out-Null
                        continue
                    }

                    if ((Test-Path -LiteralPath $destination) -and $Force)
                    {
                        Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction Stop
                    }

                    if (-not (Test-Path -LiteralPath $destination))
                    {
                        New-Item -ItemType Directory -Path $destination -Force -ErrorAction Stop | Out-Null
                    }

                    if ($multipartInfo.IsMultipart)
                    {
                        $multipartParts = @(Get-MultipartPartFiles -Archive $archive -SearchRoot $resolvedPath)
                        if (-not $multipartParts -or $multipartParts.Count -eq 0)
                        {
                            $multipartParts = @($archive)
                        }

                        $uniquePartDirectories = $multipartParts | Select-Object -ExpandProperty DirectoryName -Unique
                        if ($uniquePartDirectories.Count -gt 1)
                        {
                            $stagingRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'Extract-Archives'
                            if (-not (Test-Path -LiteralPath $stagingRoot))
                            {
                                New-Item -ItemType Directory -Path $stagingRoot -Force -ErrorAction Stop | Out-Null
                            }

                            $stagingPath = Join-Path -Path $stagingRoot -ChildPath ([guid]::NewGuid().ToString())
                            New-Item -ItemType Directory -Path $stagingPath -Force -ErrorAction Stop | Out-Null

                            foreach ($part in $multipartParts)
                            {
                                Copy-Item -LiteralPath $part.FullName -Destination $stagingPath -Force -ErrorAction Stop
                            }

                            $workingArchivePath = Join-Path -Path $stagingPath -ChildPath $archive.Name
                        }
                        else
                        {
                            $workingArchivePath = $archive.FullName
                        }
                    }

                    switch ($archiveType)
                    {
                        'Zip'
                        {
                            if ($multipartInfo.IsMultipart -and $sevenZipCommand)
                            {
                                & $sevenZipCommand.Path @('x', $workingArchivePath, "-o$destination", '-y') 2>&1 | Out-Null
                                if ($LASTEXITCODE -ne 0)
                                {
                                    throw "7zip exited with code $LASTEXITCODE while processing $($archive.FullName)"
                                }
                            }
                            else
                            {
                                Expand-Archive -LiteralPath $workingArchivePath -DestinationPath $destination -Force:$Force -ErrorAction Stop | Out-Null
                            }
                        }
                        'Tar'
                        {
                            & $tarCommand.Path @('-xf', $workingArchivePath, '-C', $destination) 2>&1 | Out-Null
                            if ($LASTEXITCODE -ne 0)
                            {
                                throw "tar exited with code $LASTEXITCODE while processing $($archive.FullName)"
                            }
                        }
                        'SevenZip'
                        {
                            & $sevenZipCommand.Path @('x', $workingArchivePath, "-o$destination", '-y') 2>&1 | Out-Null
                            if ($LASTEXITCODE -ne 0)
                            {
                                throw "7zip exited with code $LASTEXITCODE while processing $($archive.FullName)"
                            }
                        }
                        default
                        {
                            throw "Unsupported archive type for: $($archive.FullName)"
                        }
                    }

                    $status = 'Extracted'

                    if ($DeleteArchive)
                    {
                        foreach ($archivePart in ($multipartParts | Sort-Object -Property FullName -Unique))
                        {
                            if (-not (Test-Path -LiteralPath $archivePart.FullName))
                            {
                                continue
                            }

                            if ($PSCmdlet.ShouldProcess($archivePart.FullName, 'Delete archive after extraction'))
                            {
                                Remove-Item -LiteralPath $archivePart.FullName -Force -ErrorAction Stop
                            }
                        }
                    }
                }
                catch
                {
                    $status = 'Failed'
                    $errorMessage = $_.Exception.Message
                }
                finally
                {
                    if ($stagingPath -and (Test-Path -LiteralPath $stagingPath))
                    {
                        Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }

                $results.Add([PSCustomObject]@{
                        Archive = $archive.FullName
                        Destination = $destination
                        Type = $archiveType
                        Status = $status
                        ErrorMessage = $errorMessage
                    }) | Out-Null

                if ($status -eq 'Extracted' -and $ExtractNested)
                {
                    $directoriesToProcess.Enqueue($destination)
                }
            }
        }
    }

    end
    {
        $summary = [PSCustomObject]@{
            TotalArchives = @($results).Count
            Extracted = @($results | Where-Object { $_.Status -eq 'Extracted' }).Count
            Skipped = @($results | Where-Object { $_.Status -like 'Skipped*' }).Count
            Failed = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
            Results = $results
        }

        return $summary
    }
}

# Create alias 'extract' if it doesn't conflict
if (-not (Get-Command -Name 'extract' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'extract' alias for Extract-Archives"
        Set-Alias -Name 'extract' -Value 'Extract-Archives' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Extract-Archives: Could not create 'extract' alias: $($_.Exception.Message)"
    }
}
