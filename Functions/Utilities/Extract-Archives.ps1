function Extract-Archives
{
    <#
    .SYNOPSIS
        Extracts archive files in a directory to folders named after each archive.

    .DESCRIPTION
        Searches a target directory (current directory by default) for supported archive
        types and extracts each one into a folder that matches the archive name without
        its extension. Supports optional recursive search. When -Force is specified,
        existing destination folders are removed before extraction.

        Supported archive types:
        - .zip (uses Expand-Archive)
        - .tar, .tar.gz, .tgz, .tar.bz2, .tbz, .tbz2, .tar.xz, .txz (uses tar)
        - .7z and .rar (uses 7z/7za if available)

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
                { $_ -like '*.zip' } { return 'Zip' }
                { $_ -like '*.tar.gz' -or $_ -like '*.tgz' } { return 'Tar' }
                { $_ -like '*.tar.bz2' -or $_ -like '*.tbz' -or $_ -like '*.tbz2' } { return 'Tar' }
                { $_ -like '*.tar.xz' -or $_ -like '*.txz' } { return 'Tar' }
                { $_ -like '*.tar' } { return 'Tar' }
                { $_ -like '*.7z' } { return 'SevenZip' }
                { $_ -like '*.rar' } { return 'SevenZip' }
                default { return $null }
            }
        }

        function Get-ArchiveBaseName
        {
            param([String]$FileName)

            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
            if ($FileName.ToLowerInvariant() -match '\.tar\.(gz|bz2|xz)$' -or
                $FileName.ToLowerInvariant() -like '*.tgz' -or
                $FileName.ToLowerInvariant() -like '*.tbz' -or
                $FileName.ToLowerInvariant() -like '*.tbz2' -or
                $FileName.ToLowerInvariant() -like '*.txz')
            {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
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
    }

    process
    {
        $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container))
        {
            throw "Path not found or is not a directory: $Path"
        }

        $getChildItemParams = @{
            Path = $resolvedPath
            File = $true
            ErrorAction = 'Stop'
            Force = $true
        }
        if ($Recurse)
        {
            $getChildItemParams['Recurse'] = $true
        }

        if ($DestinationRoot -and -not (Test-Path -LiteralPath $DestinationRoot))
        {
            if ($PSCmdlet.ShouldProcess($DestinationRoot, 'Create destination root'))
            {
                New-Item -ItemType Directory -Path $DestinationRoot -Force -ErrorAction Stop | Out-Null
            }
        }

        $archives = Get-ChildItem @getChildItemParams | Where-Object { Get-ArchiveType $_.Name }
        $archives = $archives | Where-Object { MatchesPattern -Name $_.Name -Patterns $Include }
        if ($Exclude)
        {
            $archives = $archives | Where-Object { -not (MatchesPattern -Name $_.Name -Patterns $Exclude) }
        }

        if (-not $archives)
        {
            Write-Verbose "No archives found under: $resolvedPath"
        }
        else
        {
            foreach ($archive in $archives)
            {
                $archiveType = Get-ArchiveType -FileName $archive.Name
                if (-not $archiveType)
                {
                    continue
                }

                $destinationRoot = if ($DestinationRoot) { $DestinationRoot } else { $archive.Directory.FullName }
                $destination = Join-Path -Path $destinationRoot -ChildPath (Get-ArchiveBaseName -FileName $archive.Name)
                $status = 'Pending'
                $errorMessage = $null

                try
                {
                    if ($archiveType -eq 'Tar' -and -not $tarCommand)
                    {
                        $status = 'SkippedMissingDependency'
                        $errorMessage = 'Missing required dependency: tar'
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

                    switch ($archiveType)
                    {
                        'Zip'
                        {
                            Expand-Archive -LiteralPath $archive.FullName -DestinationPath $destination -Force:$Force -ErrorAction Stop
                        }
                        'Tar'
                        {
                            & $tarCommand.Path @('-xf', $archive.FullName, '-C', $destination) 2>&1 | Out-Null
                            if ($LASTEXITCODE -ne 0)
                            {
                                throw "tar exited with code $LASTEXITCODE while processing $($archive.FullName)"
                            }
                        }
                        'SevenZip'
                        {
                            & $sevenZipCommand.Path @('x', $archive.FullName, "-o$destination", '-y') 2>&1 | Out-Null
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
                }
                catch
                {
                    $status = 'Failed'
                    $errorMessage = $_.Exception.Message
                }

                $results.Add([PSCustomObject]@{
                        Archive = $archive.FullName
                        Destination = $destination
                        Type = $archiveType
                        Status = $status
                        ErrorMessage = $errorMessage
                    }) | Out-Null
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
