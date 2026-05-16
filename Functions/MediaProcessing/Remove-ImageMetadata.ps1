function Remove-ImageMetadata
{
    <#
    .SYNOPSIS
        Removes embedded metadata from image files.

    .DESCRIPTION
        Removes writable metadata from image files using ExifTool. This includes
        EXIF, GPS location data, XMP, IPTC, comments, descriptions, PNG textual
        chunks, maker notes, thumbnails, and other embedded tag groups supported
        by ExifTool.

        The function processes image files in place by default and passes
        -overwrite_original to ExifTool so no metadata-bearing *_original backup
        files are left behind. Use -KeepBackup if you intentionally want ExifTool
        to preserve original backup files.

        Use -OutputPath to write sanitized copies instead of modifying the source
        files. Use -Paranoid to re-encode images through ImageMagick, stripping
        metadata from a newly rendered image file before replacing or writing the
        final target.

        Dependencies:
        - `exiftool` must be available in PATH or specified via -ExifToolPath.

           Note that the image pixel data is not recompressed by ExifTool when
           metadata is removed unless -Paranoid is specified.

        - `magick` -Paranoid mode also requires ImageMagick to be installed and
           available in PATH or specified via -ImageMagickPath.

    .PARAMETER Path
        One or more image file or directory paths to process. Accepts pipeline
        input and wildcard patterns. Defaults to the current working directory.

    .PARAMETER Filters
        File name filters to use when searching directories. Defaults to common
        image extensions including JPEG, PNG, TIFF, WebP, HEIC, AVIF, GIF, and BMP.

    .PARAMETER Exclude
        Directory names to exclude when -Recurse is specified. Defaults to
        @('.git', 'node_modules', '.vscode').

    .PARAMETER Recurse
        Searches directories recursively. By default, only files directly inside
        each directory are processed.

    .PARAMETER ExifToolPath
        Path to the ExifTool executable. If omitted, the function searches PATH
        and common platform-specific install locations.

    .PARAMETER ImageMagickPath
        Path to the ImageMagick executable (magick) used by -Paranoid.
        If omitted, the function searches PATH and common platform-specific install locations.

    .PARAMETER OutputPath
        Writes sanitized image files to this file or directory path instead of
        modifying the source images in place. When processing multiple images,
        OutputPath is treated as a directory.

    .PARAMETER Force
        Overwrites existing files when -OutputPath targets already exist.

    .PARAMETER KeepBackup
        Allows ExifTool to create *_original backup files. By default, backups are
        suppressed with -overwrite_original so original metadata is not retained.

    .PARAMETER PreserveFileTimestamp
        Preserves the filesystem modified timestamp by passing -P to ExifTool.

    .PARAMETER ResetFileTimestamp
        Resets creation, last write, and last access timestamps on sanitized
        output files to the value of -ResetTimestamp.

    .PARAMETER ResetTimestamp
        The UTC timestamp to apply when -ResetFileTimestamp is specified. Defaults
        to 2000-01-01T00:00:00Z.

    .PARAMETER Paranoid
        Re-encodes each image through ImageMagick using -strip, then runs ExifTool
        metadata removal on the newly rendered output. This helps remove hidden
        payloads, embedded previews, and format-specific metadata that simple tag
        deletion may not fully normalize.

    .PARAMETER Verify
        Runs ExifTool after cleanup and reports remaining watched metadata tags
        such as EXIF, GPS, XMP, IPTC, ICC profile, Photoshop, comments, titles,
        authors, software, device details, and thumbnail/preview tags.

    .PARAMETER PassThru
        Returns a result object for each image file considered for processing.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg'

        Removes embedded metadata from photo.jpg in place.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\Images'

        Removes metadata from supported image files directly inside the Images folder.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\Images' -Recurse

        Recursively removes metadata from supported image files under the Images folder.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\Images' -Recurse -Exclude @('.git', 'raw')

        Recursively removes image metadata while skipping .git and raw directories.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\Images' -Filters '*.jpg', '*.png'

        Removes metadata only from JPEG and PNG files in the Images folder.

    .EXAMPLE
        PS > Get-ChildItem -Path '.\Uploads' -Filter '*.jpg' | Remove-ImageMetadata

        Removes metadata from JPEG files provided through the pipeline.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -PassThru

        Removes metadata and returns a result object describing the operation.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -WhatIf

        Shows what metadata removal would do without changing the file.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -KeepBackup

        Removes metadata and lets ExifTool create a photo.jpg_original backup file.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -PreserveFileTimestamp

        Removes metadata while preserving the file modified timestamp.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -ResetFileTimestamp

        Removes metadata and resets filesystem timestamps to 2000-01-01T00:00:00Z.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -OutputPath '.\clean\photo.jpg'

        Writes a sanitized copy to the clean folder without modifying photo.jpg.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\Images' -OutputPath '.\CleanImages' -Recurse

        Recursively writes sanitized copies to the CleanImages folder.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -Paranoid

        Re-encodes photo.jpg through ImageMagick, strips metadata, and replaces the source file.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -OutputPath '.\clean\photo.jpg' -Paranoid -Verify

        Writes a re-encoded sanitized copy and reports any watched metadata tags that remain.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -Verify -PassThru

        Removes metadata, verifies watched metadata groups, and returns a result object.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -ExifToolPath '/opt/homebrew/bin/exiftool'

        Uses a specific ExifTool executable to remove metadata.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\*.jpeg' -PassThru

        Removes metadata from all JPEG files matching the wildcard pattern and returns result objects.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\Photos' -OutputPath '.\CleanPhotos' -Recurse -Paranoid -Verify -ResetFileTimestamp

        Runs a strong privacy cleanup by re-encoding images, writing clean copies, verifying watched metadata, and resetting timestamps.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\Screenshots' -OutputPath '.\CleanScreenshots' -Filters '*.png' -Verify

        Removes textual PNG metadata from screenshots and verifies watched metadata tags in the clean copies.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\DCIM' -Filters '*.heic', '*.heif' -OutputPath '.\CleanDCIM' -Recurse -Paranoid

        Re-encodes HEIC/HEIF images into sanitized copies under CleanDCIM using paranoid mode.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -OutputPath '.\clean\photo.jpg' -Force

        Overwrites an existing sanitized copy at the specified output path.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -OutputPath '.\clean\photo.jpg' -ResetFileTimestamp -ResetTimestamp ([DateTime]'2024-01-01T00:00:00Z')

        Writes a sanitized copy and resets its filesystem timestamps to a specific UTC value.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\Shared' -OutputPath '.\Shared-Clean' -Recurse -Exclude @('.git', 'node_modules', 'private', 'raw')

        Recursively sanitizes shareable images while skipping source-control, dependency, private, and raw folders.

    .EXAMPLE
        PS > Get-ChildItem '.\Uploads' -Include *.jpg, *.png, *.webp -Recurse | Remove-ImageMetadata -OutputPath '.\Uploads-Clean' -Verify

        Sanitizes recursively discovered upload images through the pipeline and verifies the clean output files.

    .EXAMPLE
        PS > Get-ChildItem '.\Photos' -File | Where-Object LastWriteTime -gt (Get-Date).AddDays(-7) | Remove-ImageMetadata -OutputPath '.\Recent-Clean'

        Removes metadata only from images modified in the last seven days.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\BeforeUpload' -OutputPath '.\ReadyToUpload' -Recurse -WhatIf

        Previews the files that would be sanitized before uploading or publishing images.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\BeforeUpload' -OutputPath '.\ReadyToUpload' -Recurse -PassThru | Format-Table Path, MetadataRemoved, ExitCode

        Sanitizes images and displays a concise processing summary table.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -Verify

        Removes metadata in place and reports verification status for watched privacy-related tags.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -Paranoid -ImageMagickPath '/opt/homebrew/bin/magick'

        Uses a specific ImageMagick executable for paranoid re-encoding.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -ExifToolPath 'C:\Tools\ExifTool\exiftool.exe' -Verify

        Uses a specific Windows ExifTool path and verifies the result.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\Album' -Filters '*.jpg', '*.jpeg', '*.png', '*.webp' -Recurse -PassThru

        Removes metadata from common web image formats in an album and returns one result object per image.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\PublicGallery' -OutputPath '.\PublicGalleryClean' -Recurse -Paranoid -Force

        Rebuilds an existing clean public gallery by overwriting previous sanitized copies.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -OutputPath '.\clean\photo.jpg' -KeepBackup

        Writes a sanitized copy and allows ExifTool to keep an *_original backup of that clean-copy target.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\Scans' -OutputPath '.\Scans-Clean' -Filters '*.tif', '*.tiff' -PreserveFileTimestamp

        Removes metadata from scanned TIFF files while preserving their modified timestamps.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\Export' -OutputPath '.\Export-Clean' -Filters '*.avif', '*.webp' -Recurse -Verify -PassThru

        Sanitizes modern web image exports and returns verification details for each clean file.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\one.jpg', '.\two.png', '.\three.webp' -OutputPath '.\CleanBatch' -PassThru

        Sanitizes a small explicit batch of files into one clean output directory.

    .EXAMPLE
        PS > Remove-ImageMetadata -Path '.\photo.jpg' -OutputPath '.\clean\photo.jpg' -Paranoid -Verify -ResetFileTimestamp -PassThru

        Creates a clean copy using the strictest workflow and returns processing, timestamp, and verification details.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        When PassThru is specified, returns one object per file with Path,
        MetadataRemoved, ExitCode, Message, and related processing details.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/MediaProcessing/Remove-ImageMetadata.ps1

    .LINK
        https://exiftool.org/

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/MediaProcessing/Remove-ImageMetadata.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Metadata is a mass noun in this command name.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Several parameters are consumed by nested helper functions; the analyzer reports false positives for this pattern.')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'InPlace')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Directory', 'Folder', 'Location', 'FilePath', 'FullName')]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Path = @($PWD.Path),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Filters = @('*.jpg', '*.jpeg', '*.png', '*.tif', '*.tiff', '*.webp', '*.heic', '*.heif', '*.avif', '*.gif', '*.bmp'),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Exclude = @('.git', 'node_modules', '.vscode'),

        [Parameter()]
        [Switch]
        $Recurse,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]
        $ExifToolPath,

        [Parameter(ParameterSetName = 'InPlaceParanoid')]
        [Parameter(ParameterSetName = 'InPlaceParanoidPreserveTimestamp')]
        [Parameter(ParameterSetName = 'InPlaceParanoidResetTimestamp')]
        [Parameter(ParameterSetName = 'OutputParanoid')]
        [Parameter(ParameterSetName = 'OutputParanoidPreserveTimestamp')]
        [Parameter(ParameterSetName = 'OutputParanoidResetTimestamp')]
        [ValidateNotNullOrEmpty()]
        [String]
        $ImageMagickPath,

        [Parameter(Mandatory, ParameterSetName = 'Output')]
        [Parameter(Mandatory, ParameterSetName = 'OutputPreserveTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'OutputResetTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'OutputParanoid')]
        [Parameter(Mandatory, ParameterSetName = 'OutputParanoidPreserveTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'OutputParanoidResetTimestamp')]
        [ValidateNotNullOrEmpty()]
        [String]
        $OutputPath,

        [Parameter(ParameterSetName = 'Output')]
        [Parameter(ParameterSetName = 'OutputPreserveTimestamp')]
        [Parameter(ParameterSetName = 'OutputResetTimestamp')]
        [Parameter(ParameterSetName = 'OutputParanoid')]
        [Parameter(ParameterSetName = 'OutputParanoidPreserveTimestamp')]
        [Parameter(ParameterSetName = 'OutputParanoidResetTimestamp')]
        [Switch]
        $Force,

        [Parameter()]
        [Switch]
        $KeepBackup,

        [Parameter(Mandatory, ParameterSetName = 'InPlacePreserveTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'InPlaceParanoidPreserveTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'OutputPreserveTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'OutputParanoidPreserveTimestamp')]
        [Switch]
        $PreserveFileTimestamp,

        [Parameter(Mandatory, ParameterSetName = 'InPlaceResetTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'InPlaceParanoidResetTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'OutputResetTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'OutputParanoidResetTimestamp')]
        [Switch]
        $ResetFileTimestamp,

        [Parameter(ParameterSetName = 'InPlaceResetTimestamp')]
        [Parameter(ParameterSetName = 'InPlaceParanoidResetTimestamp')]
        [Parameter(ParameterSetName = 'OutputResetTimestamp')]
        [Parameter(ParameterSetName = 'OutputParanoidResetTimestamp')]
        [DateTime]
        $ResetTimestamp = ([DateTime]::SpecifyKind([DateTime]'2000-01-01T00:00:00', [DateTimeKind]::Utc)),

        [Parameter(Mandatory, ParameterSetName = 'InPlaceParanoid')]
        [Parameter(Mandatory, ParameterSetName = 'InPlaceParanoidPreserveTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'InPlaceParanoidResetTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'OutputParanoid')]
        [Parameter(Mandatory, ParameterSetName = 'OutputParanoidPreserveTimestamp')]
        [Parameter(Mandatory, ParameterSetName = 'OutputParanoidResetTimestamp')]
        [Switch]
        $Paranoid,

        [Parameter()]
        [Switch]
        $Verify,

        [Parameter()]
        [Switch]
        $PassThru
    )

    begin
    {
        Write-Verbose 'Starting image metadata removal'

        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $script:IsWindowsPlatform = $true
            $script:IsMacOSPlatform = $false
            $script:IsLinuxPlatform = $false
        }
        else
        {
            $script:IsWindowsPlatform = $IsWindows
            $script:IsMacOSPlatform = $IsMacOS
            $script:IsLinuxPlatform = $IsLinux
        }

        if ($PreserveFileTimestamp -and $ResetFileTimestamp)
        {
            throw 'PreserveFileTimestamp and ResetFileTimestamp cannot be used together.'
        }

        function Get-ImageMetadataLinuxPackageManagerHint
        {
            $aptCommand = Get-Command -Name 'apt' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
            if ($aptCommand)
            {
                return 'apt'
            }

            $apkCommand = Get-Command -Name 'apk' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
            if ($apkCommand)
            {
                return 'apk'
            }

            $brewCommand = Get-Command -Name 'brew' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
            if ($brewCommand)
            {
                return 'brew'
            }

            if (-not (Test-Path -Path '/etc/os-release' -PathType Leaf))
            {
                return ''
            }

            try
            {
                $linuxIds = @()
                foreach ($line in (Get-Content -Path '/etc/os-release' -ErrorAction Stop))
                {
                    if ($line -match '^(?<Name>ID|ID_LIKE)=(?<Value>.+)$')
                    {
                        $linuxIds += $Matches.Value.Trim().Trim('"')
                    }
                }

                $linuxFamily = ($linuxIds -join ' ').ToLowerInvariant()
                if ($linuxFamily -match '\balpine\b')
                {
                    return 'apk'
                }

                if ($linuxFamily -match '\b(debian|ubuntu)\b')
                {
                    return 'apt'
                }
            }
            catch
            {
                Write-Verbose "Unable to detect Linux package manager for install hint: $($_.Exception.Message)"
            }

            return ''
        }

        function Get-ImageMetadataInstallPackageHint
        {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('ExifTool', 'ImageMagick')]
                [String]$RequirementName
            )

            $installerCommand = 'Install-PlatformPackage'

            if ($script:IsWindowsPlatform)
            {
                switch ($RequirementName)
                {
                    'ExifTool' { return "$installerCommand -Id OliverBetz.ExifTool" }
                    'ImageMagick' { return "$installerCommand -Id ImageMagick.ImageMagick" }
                }
            }

            if ($script:IsMacOSPlatform)
            {
                switch ($RequirementName)
                {
                    'ExifTool' { return "$installerCommand -Name exiftool" }
                    'ImageMagick' { return "$installerCommand -Name imagemagick" }
                }
            }

            if ($script:IsLinuxPlatform)
            {
                $linuxPackageManager = Get-ImageMetadataLinuxPackageManagerHint
                switch ($linuxPackageManager)
                {
                    'apt'
                    {
                        switch ($RequirementName)
                        {
                            'ExifTool' { return "$installerCommand -Name libimage-exiftool-perl" }
                            'ImageMagick' { return "$installerCommand -Name imagemagick" }
                        }
                    }
                    'apk'
                    {
                        switch ($RequirementName)
                        {
                            'ExifTool' { return "$installerCommand -Name exiftool" }
                            'ImageMagick' { return "$installerCommand -Name imagemagick" }
                        }
                    }
                    'brew'
                    {
                        switch ($RequirementName)
                        {
                            'ExifTool' { return "$installerCommand -Name exiftool" }
                            'ImageMagick' { return "$installerCommand -Name imagemagick" }
                        }
                    }
                }
            }

            return ''
        }

        function Get-ImageMetadataMissingRequirementMessage
        {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('ExifTool', 'ImageMagick')]
                [String]$RequirementName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$PathParameterName
            )

            $message = "$RequirementName executable not found. Install $RequirementName or specify the path using -$PathParameterName."
            $installPackageHint = Get-ImageMetadataInstallPackageHint -RequirementName $RequirementName

            if (-not [String]::IsNullOrWhiteSpace($installPackageHint))
            {
                $message = "$message Hint: run: $installPackageHint (function path: ./Functions/SystemAdministration/Install-PlatformPackage.ps1)."
            }

            return $message
        }

        function Get-ValidExifToolPath
        {
            param([String]$ProvidedPath)

            $resolvedPath = $ProvidedPath

            if ($resolvedPath)
            {
                $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($resolvedPath)
            }

            if (-not $resolvedPath)
            {
                $exifToolCommand = Get-Command -Name 'exiftool' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
                Select-Object -First 1

                if ($exifToolCommand)
                {
                    if ($exifToolCommand.Path)
                    {
                        $resolvedPath = $exifToolCommand.Path
                    }
                    else
                    {
                        $resolvedPath = $exifToolCommand.Source
                    }

                    Write-Verbose "Using ExifTool from PATH: $resolvedPath"
                }
                else
                {
                    if ($script:IsWindowsPlatform)
                    {
                        $commonPaths = @(
                            'C:\Windows\exiftool.exe',
                            'C:\Program Files\ExifTool\exiftool.exe',
                            'C:\Program Files (x86)\ExifTool\exiftool.exe',
                            "$env:USERPROFILE\scoop\apps\exiftool\current\exiftool.exe",
                            "$env:ProgramData\chocolatey\bin\exiftool.exe"
                        )
                    }
                    elseif ($script:IsMacOSPlatform)
                    {
                        $commonPaths = @(
                            '/opt/homebrew/bin/exiftool',
                            '/usr/local/bin/exiftool',
                            '/opt/local/bin/exiftool',
                            "$env:HOME/.local/bin/exiftool",
                            "$env:HOME/bin/exiftool"
                        )
                    }
                    else
                    {
                        $commonPaths = @(
                            '/usr/bin/exiftool',
                            '/usr/local/bin/exiftool',
                            '/snap/bin/exiftool',
                            "$env:HOME/.local/bin/exiftool",
                            "$env:HOME/bin/exiftool"
                        )
                    }

                    foreach ($pathCandidate in $commonPaths)
                    {
                        if (Test-Path -LiteralPath $pathCandidate -PathType Leaf)
                        {
                            $resolvedPath = $pathCandidate
                            Write-Verbose "Found ExifTool at: $resolvedPath"
                            break
                        }
                    }
                }
            }

            if (-not $resolvedPath -or -not (Test-Path -LiteralPath $resolvedPath -PathType Leaf))
            {
                throw (Get-ImageMetadataMissingRequirementMessage -RequirementName 'ExifTool' -PathParameterName 'ExifToolPath')
            }

            return $resolvedPath
        }

        function Get-ValidImageMagickPath
        {
            param([String]$ProvidedPath)

            $resolvedPath = $ProvidedPath

            if ($resolvedPath)
            {
                $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($resolvedPath)
            }

            if (-not $resolvedPath)
            {
                $imageMagickCommand = Get-Command -Name 'magick' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
                Select-Object -First 1

                if (-not $imageMagickCommand -and -not $script:IsWindowsPlatform)
                {
                    $imageMagickCommand = Get-Command -Name 'convert' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                }

                if ($imageMagickCommand)
                {
                    if ($imageMagickCommand.Path)
                    {
                        $resolvedPath = $imageMagickCommand.Path
                    }
                    else
                    {
                        $resolvedPath = $imageMagickCommand.Source
                    }

                    Write-Verbose "Using ImageMagick from PATH: $resolvedPath"
                }
                else
                {
                    if ($script:IsWindowsPlatform)
                    {
                        $commonPaths = @(
                            'C:\Program Files\ImageMagick-7.1.1-Q16-HDRI\magick.exe',
                            'C:\Program Files\ImageMagick-7.1.0-Q16-HDRI\magick.exe',
                            "$env:ProgramData\chocolatey\bin\magick.exe",
                            "$env:USERPROFILE\scoop\apps\imagemagick\current\magick.exe"
                        )
                    }
                    elseif ($script:IsMacOSPlatform)
                    {
                        $commonPaths = @(
                            '/opt/homebrew/bin/magick',
                            '/usr/local/bin/magick',
                            '/opt/local/bin/magick',
                            "$env:HOME/.local/bin/magick",
                            "$env:HOME/bin/magick",
                            '/opt/homebrew/bin/convert',
                            '/usr/local/bin/convert'
                        )
                    }
                    else
                    {
                        $commonPaths = @(
                            '/usr/bin/magick',
                            '/usr/local/bin/magick',
                            '/snap/bin/magick',
                            "$env:HOME/.local/bin/magick",
                            "$env:HOME/bin/magick",
                            '/usr/bin/convert',
                            '/usr/local/bin/convert'
                        )
                    }

                    foreach ($pathCandidate in $commonPaths)
                    {
                        if (Test-Path -LiteralPath $pathCandidate -PathType Leaf)
                        {
                            $resolvedPath = $pathCandidate
                            Write-Verbose "Found ImageMagick at: $resolvedPath"
                            break
                        }
                    }
                }
            }

            if (-not $resolvedPath -or -not (Test-Path -LiteralPath $resolvedPath -PathType Leaf))
            {
                throw (Get-ImageMetadataMissingRequirementMessage -RequirementName 'ImageMagick' -PathParameterName 'ImageMagickPath')
            }

            return $resolvedPath
        }

        function Test-ImageFileName
        {
            param([System.IO.FileInfo]$FileInfo)

            foreach ($filter in $Filters)
            {
                if ($FileInfo.Name -like $filter)
                {
                    return $true
                }
            }

            return $false
        }

        function Test-ExcludedDirectory
        {
            param([System.IO.FileInfo]$FileInfo)

            if (-not $Recurse -or -not $FileInfo.DirectoryName -or $Exclude.Count -eq 0)
            {
                return $false
            }

            $directoryParts = $FileInfo.DirectoryName -split '[\\/]'
            foreach ($excludeDirectory in $Exclude)
            {
                if ($directoryParts -contains $excludeDirectory)
                {
                    return $true
                }
            }

            return $false
        }

        function Resolve-ImageMetadataPath
        {
            param([String]$InputPath)

            if ([String]::IsNullOrWhiteSpace($InputPath))
            {
                Write-Warning 'Path parameter is null or empty, skipping.'
                return @()
            }

            try
            {
                if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($InputPath))
                {
                    $resolvedItems = @(Resolve-Path -Path $InputPath -ErrorAction Stop)
                }
                else
                {
                    $resolvedProviderPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InputPath)
                    $resolvedItems = @([PSCustomObject]@{ Path = $resolvedProviderPath })
                }
            }
            catch
            {
                Write-Error $_.Exception.Message
                return @()
            }

            $imageFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

            foreach ($resolvedItem in $resolvedItems)
            {
                $resolvedPath = $resolvedItem.Path

                if (-not (Test-Path -LiteralPath $resolvedPath))
                {
                    Write-Error "Path not found: '$resolvedPath'"
                    continue
                }

                $pathItem = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop

                if ($pathItem.PSIsContainer)
                {
                    foreach ($filter in $Filters)
                    {
                        $childItemParams = @{
                            LiteralPath = $pathItem.FullName
                            Filter = $filter
                            File = $true
                            ErrorAction = 'Stop'
                        }

                        if ($Recurse)
                        {
                            $childItemParams.Recurse = $true
                        }

                        try
                        {
                            $filesForFilter = @(Get-ChildItem @childItemParams)
                        }
                        catch
                        {
                            Write-Error $_.Exception.Message
                            continue
                        }

                        foreach ($fileForFilter in $filesForFilter)
                        {
                            if (-not (Test-ExcludedDirectory -FileInfo $fileForFilter))
                            {
                                $imageFiles.Add($fileForFilter)
                            }
                        }
                    }
                }
                elseif ($pathItem -is [System.IO.FileInfo])
                {
                    if (Test-ImageFileName -FileInfo $pathItem)
                    {
                        $imageFiles.Add($pathItem)
                    }
                    else
                    {
                        Write-Warning "Skipping unsupported image file extension: '$($pathItem.FullName)'"
                    }
                }
            }

            return @($imageFiles)
        }

        function Get-ImageOutputPath
        {
            param(
                [System.IO.FileInfo]$FileInfo,
                [Int32]$TotalFileCount
            )

            if (-not $OutputPath)
            {
                return $FileInfo.FullName
            }

            $resolvedOutputPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
            $treatAsDirectory = $true

            if ($TotalFileCount -eq 1 -and [System.IO.Path]::GetExtension($resolvedOutputPath))
            {
                if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Container))
                {
                    $treatAsDirectory = $false
                }
            }

            if ($treatAsDirectory)
            {
                return (Join-Path -Path $resolvedOutputPath -ChildPath $FileInfo.Name)
            }

            return $resolvedOutputPath
        }

        function Get-TemporaryImagePath
        {
            param([String]$DestinationPath)

            $destinationDirectory = Split-Path -Path $DestinationPath -Parent
            $extension = [System.IO.Path]::GetExtension($DestinationPath)

            if ([String]::IsNullOrWhiteSpace($extension))
            {
                $extension = '.img'
            }

            do
            {
                $fileName = '.remove-image-metadata-{0}{1}' -f ([Guid]::NewGuid().ToString('N')), $extension
                $temporaryPath = Join-Path -Path $destinationDirectory -ChildPath $fileName
            }
            while (Test-Path -LiteralPath $temporaryPath)

            return $temporaryPath
        }

        function Move-ImageMetadataOutput
        {
            param(
                [String]$SourcePath,
                [String]$DestinationPath,
                [Boolean]$AllowOverwrite,
                [Boolean]$UseForce
            )

            if ((Test-Path -LiteralPath $DestinationPath) -and -not $AllowOverwrite)
            {
                throw "Output file already exists: '$DestinationPath'. Use -Force to overwrite it."
            }

            if ($UseForce)
            {
                Move-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
                return
            }

            if (Test-Path -LiteralPath $DestinationPath)
            {
                [System.IO.File]::Copy($SourcePath, $DestinationPath, $true)
                [System.IO.File]::Delete($SourcePath)
                return
            }

            [System.IO.File]::Move($SourcePath, $DestinationPath)
        }

        function Invoke-ExifToolMetadataRemoval
        {
            param([String]$FilePath)

            $exifToolArgs = @()

            if (-not $KeepBackup)
            {
                $exifToolArgs += '-overwrite_original'
            }

            if ($PreserveFileTimestamp)
            {
                $exifToolArgs += '-P'
            }

            $exifToolArgs += '-all='
            $exifToolArgs += $FilePath

            Write-Verbose "ExifTool command: $exifToolExecutable $($exifToolArgs -join ' ')"

            $global:LASTEXITCODE = 0
            $commandOutput = @(& $exifToolExecutable @exifToolArgs 2>&1)
            $exitCode = $LASTEXITCODE
            $message = ($commandOutput | ForEach-Object { "$_" }) -join [Environment]::NewLine

            return [PSCustomObject]@{
                ExitCode = $exitCode
                Message = $message
            }
        }

        function Invoke-ImageMagickStrip
        {
            param(
                [String]$SourcePath,
                [String]$DestinationPath
            )

            $imageMagickArgs = @(
                $SourcePath
                '-auto-orient'
                '-strip'
                $DestinationPath
            )

            Write-Verbose "ImageMagick command: $imageMagickExecutable $($imageMagickArgs -join ' ')"

            $global:LASTEXITCODE = 0
            $commandOutput = @(& $imageMagickExecutable @imageMagickArgs 2>&1)
            $exitCode = $LASTEXITCODE
            $message = ($commandOutput | ForEach-Object { "$_" }) -join [Environment]::NewLine

            return [PSCustomObject]@{
                ExitCode = $exitCode
                Message = $message
            }
        }

        function Invoke-ImageFileTimestampReset
        {
            param([String]$FilePath)

            try
            {
                $fileInfo = Get-Item -LiteralPath $FilePath -ErrorAction Stop
                $normalizedTimestamp = $ResetTimestamp.ToUniversalTime()
                $fileInfo.CreationTimeUtc = $normalizedTimestamp
                $fileInfo.LastWriteTimeUtc = $normalizedTimestamp
                $fileInfo.LastAccessTimeUtc = $normalizedTimestamp
                return $true
            }
            catch
            {
                Write-Warning "Could not reset filesystem timestamps for '$FilePath': $($_.Exception.Message)"
                return $false
            }
        }

        function Get-RemainingImageMetadataTag
        {
            param([String]$FilePath)

            $verifyArgs = @(
                '-a'
                '-G1'
                '-s'
                '-EXIF:all'
                '-GPS:all'
                '-XMP:all'
                '-IPTC:all'
                '-MakerNotes:all'
                '-ICC_Profile:all'
                '-Photoshop:all'
                '-Comment'
                '-UserComment'
                '-ImageDescription'
                '-Description'
                '-Title'
                '-Subject'
                '-Keywords'
                '-Artist'
                '-Author'
                '-Creator'
                '-Copyright'
                '-Software'
                '-Make'
                '-Model'
                '-SerialNumber'
                '-OwnerName'
                '-DocumentName'
                '-XPTitle'
                '-XPComment'
                '-XPAuthor'
                '-XPKeywords'
                '-XPSubject'
                '-ThumbnailImage'
                '-PreviewImage'
                $FilePath
            )

            Write-Verbose "ExifTool verify command: $exifToolExecutable $($verifyArgs -join ' ')"

            $global:LASTEXITCODE = 0
            $commandOutput = @(& $exifToolExecutable @verifyArgs 2>&1)
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0)
            {
                $message = ($commandOutput | ForEach-Object { "$_" }) -join [Environment]::NewLine
                return [PSCustomObject]@{
                    Success = $false
                    Tags = @("Verification failed: $message")
                }
            }

            $remainingTags = [System.Collections.Generic.List[String]]::new()
            foreach ($line in $commandOutput)
            {
                $text = "$line"
                if ($text -match '^\[(?<Group>[^\]]+)\]\s+(?<Tag>[^:]+)\s*:')
                {
                    $remainingTags.Add(('[{0}] {1}' -f $Matches.Group.Trim(), $Matches.Tag.Trim()))
                }
                elseif ($text -match '^(?<Tag>[^:]+)\s*:')
                {
                    $remainingTags.Add($Matches.Tag.Trim())
                }
            }

            return [PSCustomObject]@{
                Success = $true
                Tags = @($remainingTags | Sort-Object -Unique)
            }
        }

        $exifToolExecutable = $null
        if (-not $WhatIfPreference)
        {
            $exifToolExecutable = Get-ValidExifToolPath -ProvidedPath $ExifToolPath
        }
        else
        {
            Write-Verbose 'WhatIf is active; ExifTool path validation is deferred.'
        }

        $imageMagickExecutable = $null
        if ($Paranoid -and -not $WhatIfPreference)
        {
            $imageMagickExecutable = Get-ValidImageMagickPath -ProvidedPath $ImageMagickPath
        }
        elseif ($Paranoid)
        {
            Write-Verbose 'WhatIf is active; ImageMagick path validation is deferred.'
        }

        $processedCount = 0
        $successfulCount = 0
        $skippedCount = 0
        $failedCount = 0
    }

    process
    {
        $imageFilesByPath = @{}

        foreach ($currentPath in $Path)
        {
            foreach ($imageFile in (Resolve-ImageMetadataPath -InputPath $currentPath))
            {
                if (-not $imageFilesByPath.ContainsKey($imageFile.FullName))
                {
                    $imageFilesByPath[$imageFile.FullName] = $imageFile
                }
            }
        }

        $imageFilesToProcess = @(
            $imageFilesByPath.GetEnumerator() |
            Sort-Object -Property Name |
            ForEach-Object { $_.Value }
        )

        $outputPathCounts = @{}
        foreach ($imageFile in $imageFilesToProcess)
        {
            $candidateOutputPath = Get-ImageOutputPath -FileInfo $imageFile -TotalFileCount $imageFilesToProcess.Count
            if (-not $outputPathCounts.ContainsKey($candidateOutputPath))
            {
                $outputPathCounts[$candidateOutputPath] = 0
            }
            $outputPathCounts[$candidateOutputPath]++
        }

        foreach ($imageFile in $imageFilesToProcess)
        {
            $processedCount++
            $sourcePath = $imageFile.FullName
            $targetPath = Get-ImageOutputPath -FileInfo $imageFile -TotalFileCount $imageFilesToProcess.Count
            $usesOutputPath = [Boolean]$OutputPath
            $outputCopied = $false
            $timestampReset = $false
            $verified = $null
            $remainingMetadataTags = @()
            $exitCode = $null
            $messageParts = [System.Collections.Generic.List[String]]::new()
            $targetDescription = 'Remove all writable embedded metadata, including GPS and text tags'

            if ($outputPathCounts[$targetPath] -gt 1)
            {
                $failedCount++
                $errorMessage = "Multiple source images would write to the same output path: '$targetPath'. Use distinct output file paths or process one directory at a time."
                Write-Error $errorMessage

                if ($PassThru -or $Verify)
                {
                    [PSCustomObject]@{
                        SourcePath = $sourcePath
                        Path = $targetPath
                        Name = [System.IO.Path]::GetFileName($targetPath)
                        MetadataRemoved = $false
                        OutputCopied = $false
                        Paranoid = [Boolean]$Paranoid
                        BackupKept = [Boolean]$KeepBackup
                        TimestampPreserved = [Boolean]$PreserveFileTimestamp
                        TimestampReset = $false
                        Verified = $false
                        RemainingMetadataTags = @($errorMessage)
                        ExitCode = $null
                        Message = $errorMessage
                    }
                }

                continue
            }

            if ($usesOutputPath -and (Test-Path -LiteralPath $targetPath) -and -not $Force)
            {
                $skippedCount++
                $errorMessage = "Output file already exists: '$targetPath'. Use -Force to overwrite it."
                Write-Error $errorMessage

                if ($PassThru -or $Verify)
                {
                    [PSCustomObject]@{
                        SourcePath = $sourcePath
                        Path = $targetPath
                        Name = [System.IO.Path]::GetFileName($targetPath)
                        MetadataRemoved = $false
                        OutputCopied = $false
                        Paranoid = [Boolean]$Paranoid
                        BackupKept = [Boolean]$KeepBackup
                        TimestampPreserved = [Boolean]$PreserveFileTimestamp
                        TimestampReset = $false
                        Verified = $false
                        RemainingMetadataTags = @($errorMessage)
                        ExitCode = $null
                        Message = $errorMessage
                    }
                }

                continue
            }

            if ($PSCmdlet.ShouldProcess($targetPath, $targetDescription))
            {
                $temporaryPath = $null

                try
                {
                    $targetDirectory = Split-Path -Path $targetPath -Parent
                    if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container))
                    {
                        New-Item -Path $targetDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    }

                    $workingPath = $targetPath

                    if ($Paranoid)
                    {
                        $temporaryPath = Get-TemporaryImagePath -DestinationPath $targetPath
                        $imageMagickResult = Invoke-ImageMagickStrip -SourcePath $sourcePath -DestinationPath $temporaryPath
                        $messageParts.Add("ImageMagick: $($imageMagickResult.Message)")

                        if ($imageMagickResult.ExitCode -ne 0)
                        {
                            $exitCode = $imageMagickResult.ExitCode
                            throw "ImageMagick failed for '$sourcePath' with exit code $exitCode. $($imageMagickResult.Message)"
                        }

                        $workingPath = $temporaryPath
                    }
                    elseif ($usesOutputPath)
                    {
                        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force:$Force -ErrorAction Stop
                        $outputCopied = $true
                    }

                    $exifToolResult = Invoke-ExifToolMetadataRemoval -FilePath $workingPath
                    $messageParts.Add("ExifTool: $($exifToolResult.Message)")
                    $exitCode = $exifToolResult.ExitCode

                    if ($exitCode -ne 0)
                    {
                        throw "ExifTool failed for '$workingPath' with exit code $exitCode. $($exifToolResult.Message)"
                    }

                    if ($Paranoid)
                    {
                        Move-ImageMetadataOutput -SourcePath $temporaryPath -DestinationPath $targetPath -AllowOverwrite:((-not $usesOutputPath) -or $Force) -UseForce:($usesOutputPath -and $Force)
                        $temporaryPath = $null
                        $outputCopied = $usesOutputPath
                    }

                    if ($ResetFileTimestamp)
                    {
                        $timestampReset = Invoke-ImageFileTimestampReset -FilePath $targetPath
                    }

                    if ($Verify)
                    {
                        $verifyResult = Get-RemainingImageMetadataTag -FilePath $targetPath
                        $verified = ($verifyResult.Success -and $verifyResult.Tags.Count -eq 0)
                        $remainingMetadataTags = @($verifyResult.Tags)

                        if ($verified)
                        {
                            Write-Verbose "Verification found no watched metadata tags in: $targetPath"
                        }
                        else
                        {
                            Write-Warning "Verification found remaining watched metadata tags in '$targetPath': $($remainingMetadataTags -join ', ')"
                        }
                    }

                    $successfulCount++
                    Write-Verbose "Removed metadata from: $targetPath"
                }
                catch
                {
                    $failedCount++
                    $messageParts.Add($_.Exception.Message)
                    Write-Error $_.Exception.Message
                }
                finally
                {
                    if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath))
                    {
                        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
                    }
                }

                if ($PassThru -or $Verify)
                {
                    [PSCustomObject]@{
                        SourcePath = $sourcePath
                        Path = $targetPath
                        Name = [System.IO.Path]::GetFileName($targetPath)
                        MetadataRemoved = ($exitCode -eq 0)
                        OutputCopied = $outputCopied
                        Paranoid = [Boolean]$Paranoid
                        BackupKept = [Boolean]$KeepBackup
                        TimestampPreserved = [Boolean]$PreserveFileTimestamp
                        TimestampReset = $timestampReset
                        Verified = $verified
                        RemainingMetadataTags = @($remainingMetadataTags)
                        ExitCode = $exitCode
                        Message = (($messageParts | Where-Object { -not [String]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine)
                    }
                }
            }
            else
            {
                $skippedCount++

                if ($PassThru -or $Verify)
                {
                    [PSCustomObject]@{
                        SourcePath = $sourcePath
                        Path = $targetPath
                        Name = [System.IO.Path]::GetFileName($targetPath)
                        MetadataRemoved = $false
                        OutputCopied = $false
                        Paranoid = [Boolean]$Paranoid
                        BackupKept = [Boolean]$KeepBackup
                        TimestampPreserved = [Boolean]$PreserveFileTimestamp
                        TimestampReset = $false
                        Verified = $null
                        RemainingMetadataTags = @()
                        ExitCode = $null
                        Message = 'Skipped by ShouldProcess.'
                    }
                }
            }
        }
    }

    end
    {
        Write-Verbose "Image metadata removal complete. Processed: $processedCount; Successful: $successfulCount; Skipped: $skippedCount; Failed: $failedCount"
    }
}
