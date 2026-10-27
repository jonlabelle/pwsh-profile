function Resize-Image
{
    <#
    .SYNOPSIS
        Resizes image files using ImageMagick.

    .DESCRIPTION
        Resizes individual images, wildcard matches, or images in directories.
        Supports PowerShell 5.1 and PowerShell Core on Windows, macOS, and Linux.
        Requires ImageMagick (magick, or convert on non-Windows platforms).

        By default, writes a sibling copy named photo-resized.jpg. Use -OutputPath
        for another destination or -InPlace to explicitly replace originals.
        Existing copies are protected unless -Force is specified. Output paths
        cannot replace any selected source image without -InPlace.

        Width and height describe a bounding box in the default Fit mode, which
        preserves aspect ratio. Exact mode stretches to both dimensions; Fill
        mode preserves aspect ratio and crops centrally to both dimensions.
        Alternatively, use -Percentage to scale both dimensions proportionally.
        Images may be enlarged. EXIF orientation is applied before resizing.

        Multi-frame images are coalesced before resizing. The output format must
        support writing all frames to one file; numbered output files are rejected.
        Available image formats depend on the installed ImageMagick delegates.
        Images are re-encoded; this is not a metadata-removal command.

    .PARAMETER Path
        Image file or directory paths. Accepts wildcard patterns, pipeline strings,
        and FileInfo objects. Defaults to the current directory.

    .PARAMETER Width
        Target width in pixels. With Fit, may be specified without Height.

    .PARAMETER Height
        Target height in pixels. With Fit, may be specified without Width.

    .PARAMETER Mode
        Fit preserves aspect ratio within the specified dimensions (default).
        Exact stretches the image. Fill crops centrally to fill the dimensions.
        Exact and Fill require both Width and Height.

    .PARAMETER Percentage
        Positive, finite scaling percentage, such as 50 to halve both dimensions.
        Cannot be combined with Width, Height, or Mode.

    .PARAMETER OutputPath
        Destination file or directory. An existing directory, a path without an
        extension, or any destination for multiple images is treated as a directory.
        Directory outputs use the original file names and do not preserve subfolders.
        Conflicting destinations are reported as errors, even with -Force.
        Cannot be combined with -InPlace.

    .PARAMETER InPlace
        Explicitly replaces the source images after successful resizing.
        Cannot be combined with -OutputPath.

    .PARAMETER Force
        Allows overwriting existing output copies. Does not permit overwriting a
        selected source image; use -InPlace for that.

    .PARAMETER Filter
        File name patterns for supported images. Defaults to common image formats.

    .PARAMETER Recurse
        Searches subdirectories. Directory searches are non-recursive by default.
        Directory symbolic links are not followed.

    .PARAMETER Exclude
        Directory names to skip during recursive searches.
        Defaults to .git, node_modules, and .vscode.

    .PARAMETER ImageMagickPath
        ImageMagick executable path. Otherwise searches PATH and common install
        locations. Windows convert.exe is never selected automatically.

    .PARAMETER PassThru
        Returns an object per selected image with SourcePath, Path, Name, Resized,
        InPlace, Mode, Geometry, ExitCode, and Message. Resized is false for failed
        operations and operations skipped by -WhatIf or confirmation.

    .EXAMPLE
        PS > Resize-Image -Path './photo.jpg' -Width 1200

        Writes photo-resized.jpg, preserving aspect ratio.

    .EXAMPLE
        PS > Resize-Image './photo.jpg' -Width 800 -Height 600

        Fits the image inside an 800-by-600 bounding box.

    .EXAMPLE
        PS > Resize-Image './photo.jpg' -Width 400 -Height 400 -Mode Fill

        Writes a square copy, preserving aspect ratio and cropping centrally.

    .EXAMPLE
        PS > Resize-Image './photo.png' -Width 640 -Height 480 -Mode Exact

        Stretches the copy to exactly 640 by 480 pixels.

    .EXAMPLE
        PS > Get-ChildItem './Photos' -Filter '*.jpg' | Resize-Image -Percentage 50

        Creates half-sized copies of the JPEG files supplied through the pipeline.

    .EXAMPLE
        PS > Resize-Image './Photos' -Width 1920 -Recurse -OutputPath './Small' -PassThru

        Writes resized copies to Small and returns result objects. Duplicate file
        names across source subfolders are reported instead of being overwritten.

    .EXAMPLE
        PS > Resize-Image './Photos' -Width 1920 -OutputPath './Small' -PassThru |
                 Where-Object { $_.Resized } |
                 ForEach-Object {
                     Remove-ImageMetadata -Path $_.Path -Paranoid -Verify
                 }

        Creates resized copies in ./Small (folder), then re-encodes and removes embedded
        metadata from only successfully resized copies and verifies the cleanup.
        Original images remain unchanged.

    .EXAMPLE
        PS > Resize-Image './photo.jpg' -Percentage 50 -InPlace -WhatIf

        Previews resizing the original without invoking ImageMagick or writing files.

    .EXAMPLE
        PS > Resize-Image './photo.jpg' -Width 800 -OutputPath './small.jpg' -Force

        Overwrites small.jpg only after ImageMagick successfully creates the copy.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Result objects when -PassThru is specified; otherwise no success output.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/MediaProcessing/Resize-Image.ps1

    .LINK
        https://imagemagick.org/Usage/resize/
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Dimensions')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Directory', 'Folder', 'Location', 'FilePath', 'FullName')]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Path = @($PWD.Path),

        [Parameter(ParameterSetName = 'Dimensions')]
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int32]
        $Width,

        [Parameter(ParameterSetName = 'Dimensions')]
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int32]
        $Height,

        [Parameter(ParameterSetName = 'Dimensions')]
        [ValidateSet('Fit', 'Exact', 'Fill')]
        [String]
        $Mode = 'Fit',

        [Parameter(Mandatory, ParameterSetName = 'Percentage')]
        [ValidateScript({
                if ($_ -le 0 -or [Double]::IsInfinity($_) -or [Double]::IsNaN($_))
                {
                    throw 'Percentage must be a positive, finite number.'
                }
                $true
            })]
        [Double]
        $Percentage,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]
        $OutputPath,

        [Parameter()]
        [Switch]
        $InPlace,

        [Parameter()]
        [Switch]
        $Force,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Filter = @('*.jpg', '*.jpeg', '*.png', '*.tif', '*.tiff', '*.webp', '*.heic', '*.heif', '*.avif', '*.gif', '*.bmp'),

        [Parameter()]
        [Switch]
        $Recurse,

        [Parameter()]
        [AllowEmptyCollection()]
        [String[]]
        $Exclude = @('.git', 'node_modules', '.vscode'),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]
        $ImageMagickPath,

        [Parameter()]
        [Switch]
        $PassThru
    )

    begin
    {
        $resizeMode = $Mode
        if ($InPlace -and $OutputPath)
        {
            throw 'InPlace and OutputPath cannot be combined.'
        }

        if ($PSCmdlet.ParameterSetName -eq 'Dimensions')
        {
            if (-not $Width -and -not $Height)
            {
                throw 'Specify Width and/or Height, or use Percentage.'
            }
            if ($Mode -ne 'Fit' -and (-not $Width -or -not $Height))
            {
                throw "$Mode mode requires both Width and Height."
            }
            $geometry = '{0}x{1}' -f $(if ($Width) { $Width }), $(if ($Height) { $Height })
            if ($Mode -eq 'Exact') { $geometry += '!' }
            if ($Mode -eq 'Fill') { $geometry += '^' }
        }
        else
        {
            $resizeMode = 'Percentage'
            $geometry = $Percentage.ToString('R', [Globalization.CultureInfo]::InvariantCulture) + '%'
        }

        $isWindowsPlatform = $PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows
        $isMacOSPlatform = $PSVersionTable.PSVersion.Major -ge 6 -and $IsMacOS
        $pathComparer = [StringComparer]::Ordinal
        if ($isWindowsPlatform -or $isMacOSPlatform) { $pathComparer = [StringComparer]::OrdinalIgnoreCase }
        $imageFilesByPath = [System.Collections.Generic.Dictionary[String, System.IO.FileInfo]]::new($pathComparer)

        function Resolve-ResizeImageExecutable
        {
            if ($ImageMagickPath)
            {
                $executablePath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ImageMagickPath)
                if (Test-Path -LiteralPath $executablePath -PathType Leaf)
                {
                    return $executablePath
                }
            }
            else
            {
                $commandNames = @('magick')
                if (-not $isWindowsPlatform) { $commandNames += 'convert' }
                foreach ($commandName in $commandNames)
                {
                    $command = Get-Command -Name $commandName -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                    if ($command) { return $command.Path }
                }

                $commonPaths = @()
                if ($isWindowsPlatform)
                {
                    foreach ($programFilesRoot in @($env:ProgramFiles, ${env:ProgramFiles(x86)}))
                    {
                        if ($programFilesRoot -and (Test-Path -LiteralPath $programFilesRoot -PathType Container))
                        {
                            foreach ($directory in (Get-ChildItem -LiteralPath $programFilesRoot -Directory -Filter 'ImageMagick-*' -ErrorAction Stop | Sort-Object Name -Descending))
                            {
                                $commonPaths += Join-Path -Path $directory.FullName -ChildPath 'magick.exe'
                            }
                        }
                    }
                    $commonPaths += @(
                        "$env:ProgramData\chocolatey\bin\magick.exe",
                        "$env:USERPROFILE\scoop\apps\imagemagick\current\magick.exe"
                    )
                }
                else
                {
                    $commonPaths = @(
                        '/opt/homebrew/bin/magick', '/usr/local/bin/magick', '/opt/local/bin/magick',
                        '/usr/bin/magick', '/snap/bin/magick', "$env:HOME/.local/bin/magick",
                        "$env:HOME/bin/magick", '/opt/homebrew/bin/convert', '/usr/local/bin/convert',
                        '/usr/bin/convert'
                    )
                }
                foreach ($candidatePath in $commonPaths)
                {
                    if (Test-Path -LiteralPath $candidatePath -PathType Leaf) { return $candidatePath }
                }
            }

            $message = 'ImageMagick executable not found. Install ImageMagick or specify -ImageMagickPath.'
            $packageName = $null
            if ($isWindowsPlatform) { $packageName = 'ImageMagick.ImageMagick' }
            elseif ($isMacOSPlatform) { $packageName = 'imagemagick' }
            elseif (Get-Command -Name 'apt-get', 'apk', 'brew' -CommandType Application -ErrorAction SilentlyContinue)
            {
                $packageName = 'imagemagick'
            }
            if ($packageName)
            {
                $message += " Hint: run: Install-PlatformPackage -Name $packageName (function path: ./Functions/SystemAdministration/Install-PlatformPackage.ps1)."
            }
            throw $message
        }

        function Test-ResizeImageFilter
        {
            param([System.IO.FileInfo]$FileInfo)

            foreach ($pattern in $Filter)
            {
                if ($FileInfo.Name -like $pattern) { return $true }
            }
            return $false
        }

        function Get-ResizeImageChildFile
        {
            param([String]$DirectoryPath)

            Get-ChildItem -LiteralPath $DirectoryPath -File -ErrorAction Stop |
            Where-Object { Test-ResizeImageFilter -FileInfo $_ }
            if ($Recurse)
            {
                foreach ($directory in (Get-ChildItem -LiteralPath $DirectoryPath -Directory -ErrorAction Stop))
                {
                    if ($Exclude -contains $directory.Name) { continue }
                    if ($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
                    {
                        Write-Verbose "Skipping directory link: $($directory.FullName)"
                        continue
                    }
                    Get-ResizeImageChildFile -DirectoryPath $directory.FullName
                }
            }
        }
    }

    process
    {
        foreach ($inputPath in $Path)
        {
            try
            {
                $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($inputPath)
                if (Test-Path -LiteralPath $resolvedPath)
                {
                    $items = @(Get-Item -LiteralPath $resolvedPath -ErrorAction Stop)
                }
                else
                {
                    $items = @(Get-Item -Path $inputPath -ErrorAction Stop)
                }
                foreach ($item in $items)
                {
                    if ($item -is [System.IO.DirectoryInfo])
                    {
                        $files = @(Get-ResizeImageChildFile -DirectoryPath $item.FullName)
                    }
                    elseif ($item -is [System.IO.FileInfo])
                    {
                        $files = @()
                        if (Test-ResizeImageFilter -FileInfo $item) { $files = @($item) }
                        else { Write-Warning "Skipping unsupported image file extension: '$($item.FullName)'" }
                    }
                    else
                    {
                        throw "Path must refer to a filesystem file or directory: '$inputPath'"
                    }
                    foreach ($file in $files)
                    {
                        $imageFilesByPath[$file.FullName] = $file
                    }
                }
            }
            catch
            {
                Write-Verbose "Unable to select images from '$inputPath': $($_.Exception.Message)"
                Write-Error -ErrorRecord $_
            }
        }
    }

    end
    {
        $imageFiles = @($imageFilesByPath.Values | Sort-Object -Property FullName)
        if ($imageFiles.Count -eq 0)
        {
            Write-Warning 'No image files matched the specified paths and filters.'
            return
        }

        $resolvedOutputPath = $null
        $outputIsDirectory = $false
        if ($OutputPath)
        {
            $resolvedOutputPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
            $outputIsDirectory = $imageFiles.Count -gt 1 -or
            (Test-Path -LiteralPath $resolvedOutputPath -PathType Container) -or
            -not [System.IO.Path]::GetExtension($resolvedOutputPath)
        }

        $operations = @(
            foreach ($imageFile in $imageFiles)
            {
                $targetPath = $imageFile.FullName
                if ($resolvedOutputPath)
                {
                    $targetPath = $resolvedOutputPath
                    if ($outputIsDirectory)
                    {
                        $targetPath = Join-Path -Path $resolvedOutputPath -ChildPath $imageFile.Name
                    }
                }
                elseif (-not $InPlace)
                {
                    $targetPath = Join-Path -Path $imageFile.DirectoryName -ChildPath ($imageFile.BaseName + '-resized' + $imageFile.Extension)
                }
                [PSCustomObject]@{ SourcePath = $imageFile.FullName; TargetPath = $targetPath }
            }
        )
        $targetCounts = [System.Collections.Generic.Dictionary[String, Int32]]::new($pathComparer)
        foreach ($operation in $operations)
        {
            if (-not $targetCounts.ContainsKey($operation.TargetPath)) { $targetCounts[$operation.TargetPath] = 0 }
            $targetCounts[$operation.TargetPath]++
        }

        $imageMagickExecutable = $null
        if (-not $WhatIfPreference)
        {
            $imageMagickExecutable = Resolve-ResizeImageExecutable
            Write-Verbose "Using ImageMagick: $imageMagickExecutable"
        }

        foreach ($operation in $operations)
        {
            $sourcePath = $operation.SourcePath
            $targetPath = $operation.TargetPath
            $temporaryDirectory = $null
            $resized = $false
            $exitCode = $null
            $message = ''
            try
            {
                if ($targetCounts[$targetPath] -gt 1)
                {
                    throw "Multiple source images would write to the same output path: '$targetPath'. Choose distinct destinations."
                }
                if (-not $InPlace -and $imageFilesByPath.ContainsKey($targetPath))
                {
                    throw "Output path is a selected source image: '$targetPath'. Use -InPlace to replace originals."
                }
                if (Test-Path -LiteralPath $targetPath -PathType Container)
                {
                    throw "Output path is a directory: '$targetPath'"
                }
                if (-not $InPlace -and -not $Force -and (Test-Path -LiteralPath $targetPath))
                {
                    throw "Output file already exists: '$targetPath'. Use -Force to overwrite it."
                }

                if ($PSCmdlet.ShouldProcess($targetPath, "Resize '$sourcePath' using $resizeMode ($geometry)"))
                {
                    $targetDirectory = [System.IO.Path]::GetDirectoryName($targetPath)
                    [System.IO.Directory]::CreateDirectory($targetDirectory) | Out-Null
                    # Stage on the destination filesystem so replacement is atomic.
                    $temporaryDirectory = Join-Path -Path $targetDirectory -ChildPath ('.resize-image-' + [Guid]::NewGuid().ToString('N'))
                    [System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
                    $temporaryPath = Join-Path -Path $temporaryDirectory -ChildPath ('image' + [System.IO.Path]::GetExtension($targetPath))
                    $imageMagickArgs = @($sourcePath, '-coalesce', '-auto-orient', '-resize', $geometry)
                    if ($Mode -eq 'Fill')
                    {
                        $imageMagickArgs += @('-gravity', 'center', '-extent', ('{0}x{1}' -f $Width, $Height))
                    }
                    $imageMagickArgs += @('+repage', $temporaryPath)
                    Write-Verbose "ImageMagick command: $imageMagickExecutable $($imageMagickArgs -join ' ')"

                    $savedErrorActionPreference = $ErrorActionPreference
                    try
                    {
                        # Capture native stderr on Desktop too, then handle the exit code explicitly.
                        $ErrorActionPreference = 'Continue'
                        $PSNativeCommandUseErrorActionPreference = $false
                        $global:LASTEXITCODE = 0
                        $commandOutput = @(& $imageMagickExecutable @imageMagickArgs 2>&1)
                        $exitCode = $LASTEXITCODE
                    }
                    finally
                    {
                        $ErrorActionPreference = $savedErrorActionPreference
                    }
                    $message = ($commandOutput | ForEach-Object { "$_" }) -join [Environment]::NewLine
                    if ($exitCode -ne 0)
                    {
                        throw "ImageMagick failed for '$sourcePath' with exit code $exitCode. $message"
                    }
                    $outputFiles = @(Get-ChildItem -LiteralPath $temporaryDirectory -File -ErrorAction Stop)
                    if ($outputFiles.Count -ne 1 -or -not (Test-Path -LiteralPath $temporaryPath -PathType Leaf))
                    {
                        throw "ImageMagick did not produce a single output image for '$sourcePath'. Use an output format that supports all input frames."
                    }
                    if ((Get-Item -LiteralPath $temporaryPath -ErrorAction Stop).Length -eq 0)
                    {
                        throw "ImageMagick produced an empty output image for '$sourcePath'."
                    }
                    if ($message) { Write-Warning "ImageMagick: $message" }

                    if (Test-Path -LiteralPath $targetPath)
                    {
                        if (-not $InPlace -and -not $Force)
                        {
                            throw "Output file already exists: '$targetPath'. Use -Force to overwrite it."
                        }
                        [System.IO.File]::Replace($temporaryPath, $targetPath, [NullString]::Value)
                    }
                    else
                    {
                        [System.IO.File]::Move($temporaryPath, $targetPath)
                    }
                    $resized = $true
                    Write-Verbose "Resized image: $targetPath"
                }
                else
                {
                    $message = 'Skipped by ShouldProcess.'
                }
            }
            catch
            {
                $message = $_.Exception.Message
                Write-Verbose "Unable to resize '$sourcePath': $message"
                Write-Error -ErrorRecord $_
            }
            finally
            {
                if ($temporaryDirectory -and (Test-Path -LiteralPath $temporaryDirectory))
                {
                    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -Confirm:$false -ErrorAction Stop
                }
            }
            if ($PassThru)
            {
                [PSCustomObject]@{
                    SourcePath = $sourcePath
                    Path = $targetPath
                    Name = [System.IO.Path]::GetFileName($targetPath)
                    Resized = $resized
                    InPlace = [Boolean]$InPlace
                    Mode = $resizeMode
                    Geometry = $geometry
                    ExitCode = $exitCode
                    Message = $message
                }
            }
        }
    }
}
