function Invoke-FFmpeg
{
    <#
    .SYNOPSIS
        Converts video files using Samsung-friendly encoding settings with H.264 or H.265 video encoding.

    .DESCRIPTION
        This function processes video files in a specified directory using Samsung-friendly encoding settings.
        For H.264: Supports 4K30 with High profile, Level 5.1, up to 100 Mbps bitrate for optimal Samsung TV compatibility.
        For H.265: Supports 4K60 with Level 5.2, up to 100 Mbps bitrate for better compression.
        Audio is converted to AAC-LC format at 48 kHz with 192 kbps bitrate.
        By default, input files are deleted after successful conversion.

    .PARAMETER Path
        The directory containing the video files to be processed.
        Accepts an array of paths and supports pipeline input.

    .PARAMETER Extension
        The file extension of input video files. Defaults to 'mkv'.

    .PARAMETER FFmpegPath
        Path to the FFmpeg executable. If not specified, attempts to use 'ffmpeg' from PATH,
        then falls back to platform-specific default locations.

    .PARAMETER Force
        If specified, overwrites output files that already exist.

    .PARAMETER KeepSourceFile
        If specified, input file(s) will not be deleted after successful conversion.

    .PARAMETER PauseOnError
        If specified, the function will wait for user input when an error occurs instead of automatically continuing to the next file.

    .PARAMETER NoRecursion
        If specified, disables recursive searching and only processes files in the specified Path.
        By default, search is recursive through all subdirectories.

    .PARAMETER Exclude
        Specifies directories to exclude when searching recursively.
        Only applies when -NoRecursion is not specified.
        Defaults to @('.git', 'node_modules').

    .PARAMETER VideoEncoder
        Specifies the video encoder to use. Valid values are 'H.264' and 'H.265'.
        H.264 provides faster encoding with 4K30 support, while H.265 offers better compression with 4K60 support.
        Defaults to 'H.264' for Samsung TV compatibility.
        This parameter cannot be used with -Passthrough.

    .PARAMETER Passthrough
        If specified, passes through video and audio without re-encoding, and encodes subtitles to mov_text format.
        This is much faster but doesn't apply Samsung-friendly (or specific) encoding settings.
        This parameter cannot be used with -VideoEncoder.

    .PARAMETER WhatIf
        If specified, shows what operations would be performed without actually executing them.
        Useful for previewing the conversion process before running it.

    .EXAMPLE
        PS> Invoke-FFmpeg -Path "C:\Videos" -Extension "mkv"
        Processes all .mkv files in C:\Videos using H.264 encoding (default) with Samsung-friendly settings.

    .EXAMPLE
        PS> Invoke-FFmpeg -Path "C:\Videos" -VideoEncoder "H.265" -Force
        Processes videos using H.265 encoding for better compression and overwrites existing output files.

    .EXAMPLE
        PS> Invoke-FFmpeg -Path "D:\Movies" -Extension "avi" -VideoEncoder "H.264" -KeepSourceFile
        Processes all .avi files using H.264 encoding without deleting the input files.

    .EXAMPLE
        PS> Invoke-FFmpeg -Path "D:\Movies" -NoRecursion
        Processes only the .mkv files directly in D:\Movies without searching subdirectories.

    .EXAMPLE
        PS> Invoke-FFmpeg -Path "D:\Movies" -Passthrough -KeepSourceFile
        Processes all .mkv files using passthrough mode (no re-encoding) and keeps the source files.

    .EXAMPLE
        PS> Invoke-FFmpeg -Path "C:\Videos" -WhatIf
        Shows what operations would be performed on all target files in C:\Videos without actually executing them.

    .EXAMPLE
        PS> Invoke-FFmpeg -Path @("C:\Videos", "D:\Movies") -Extension "mkv"
        Processes all .mkv files in multiple directories by passing an array to the Path parameter.

    .EXAMPLE
        PS> @("C:\Videos", "D:\Movies") | Invoke-FFmpeg -Extension "mkv"
        Processes all .mkv files in multiple directories using pipeline input.

    .EXAMPLE
        PS> Get-ChildItem -Directory | Invoke-FFmpeg -VideoEncoder "H.265"
        Processes videos in all subdirectories using H.265 encoding via pipeline input.

    .LINK
        https://ffmpeg.org/documentation.html
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
    [CmdletBinding(DefaultParameterSetName = 'Encode', SupportsShouldProcess)]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Directory', 'Folder', 'Location')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Path = '.',

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Extension = 'mkv',

        [Parameter(Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FFmpegPath,

        [Parameter()]
        [switch]
        $Force,

        [Parameter()]
        [switch]
        $KeepSourceFile,

        [Parameter()]
        [switch]
        $PauseOnError,

        [Parameter()]
        [switch]
        $NoRecursion,

        [Parameter()]
        [string[]]
        $Exclude = @('.git', 'node_modules'),

        [Parameter(ParameterSetName = 'Encode')]
        [ValidateSet('H.264', 'H.265')]
        [string]
        $VideoEncoder = 'H.264',

        [Parameter(ParameterSetName = 'Passthrough')]
        [switch]
        $Passthrough
    )

    begin
    {
        # Platform detection for PowerShell 5.1
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $global:IsWindows = $true
            $global:IsMacOS = $false
            # $global:IsLinux = $false
        }

        function Write-VerboseMessage
        {
            param([string]$Message)

            if ($VerbosePreference -eq 'Continue')
            {
                Write-Host $Message -ForegroundColor Cyan
            }
        }

        # The time will be display as:
        # - 10 seconds
        # - 1 minute 30 seconds
        # - 1 day, 3 hours, 20 minutes and 10 seconds
        function Format-ElapsedTime
        {
            param(
                [DateTime]$StartTime,
                [DateTime]$EndTime
            )

            $elapsedTime = $EndTime - $StartTime
            $timeFormatted = ''

            if ($elapsedTime.Days -gt 0)
            {
                $timeFormatted += "$($elapsedTime.Days) day$(if ($elapsedTime.Days -ne 1) { 's' }), "
            }
            if ($elapsedTime.Hours -gt 0)
            {
                $timeFormatted += "$($elapsedTime.Hours) hour$(if ($elapsedTime.Hours -ne 1) { 's' }), "
            }
            if ($elapsedTime.Minutes -gt 0)
            {
                $timeFormatted += "$($elapsedTime.Minutes) minute$(if ($elapsedTime.Minutes -ne 1) { 's' }) and "
            }

            $seconds = [math]::Round($elapsedTime.TotalSeconds - ($elapsedTime.Days * 86400) - ($elapsedTime.Hours * 3600) - ($elapsedTime.Minutes * 60))
            $timeFormatted += "$seconds second$(if ($seconds -ne 1) { 's' })"

            return $timeFormatted
        }

        # Function to format file size in human-readable format
        function Format-FileSize
        {
            param([long]$SizeInBytes)

            if ($SizeInBytes -eq 0) { return '0 B' }

            $units = @('B', 'KB', 'MB', 'GB', 'TB')
            $index = 0
            $size = [double]$SizeInBytes

            while ($size -ge 1024 -and $index -lt ($units.Length - 1))
            {
                $size /= 1024
                $index++
            }

            return '{0:N2} {1}' -f $size, $units[$index]
        }

        # Function to estimate remaining time based on current progress
        function Get-EstimatedTimeRemaining
        {
            param(
                [DateTime]$StartTime,
                [int]$CompletedItems,
                [int]$TotalItems
            )

            if ($CompletedItems -eq 0) { return 'Calculating...' }

            $elapsedTime = (Get-Date) - $StartTime
            $averageTimePerItem = $elapsedTime.TotalSeconds / $CompletedItems
            $remainingItems = $TotalItems - $CompletedItems
            $estimatedRemainingSeconds = $averageTimePerItem * $remainingItems

            $remainingTime = [TimeSpan]::FromSeconds($estimatedRemainingSeconds)

            if ($remainingTime.TotalHours -ge 1)
            {
                return '{0:D2}h {1:D2}m {2:D2}s' -f $remainingTime.Hours, $remainingTime.Minutes, $remainingTime.Seconds
            }
            elseif ($remainingTime.TotalMinutes -ge 1)
            {
                return '{0:D2}m {1:D2}s' -f $remainingTime.Minutes, $remainingTime.Seconds
            }
            else
            {
                return '{0:D2}s' -f $remainingTime.Seconds
            }
        }

        # Function to validate and resolve FFmpeg path
        function Get-ValidFFmpegPath
        {
            param([string]$ProvidedPath)

            $resolvedPath = $ProvidedPath

            if (-not $resolvedPath)
            {
                # Try to find in PATH first
                $ffmpegCommand = Get-Command 'ffmpeg' -ErrorAction SilentlyContinue
                if ($ffmpegCommand)
                {
                    $resolvedPath = $ffmpegCommand.Path
                    Write-VerboseMessage "Using FFmpeg from PATH: $resolvedPath"
                }
                else
                {
                    # Platform-specific default locations
                    if ($IsWindows -or ($null -eq $IsWindows -and [Environment]::OSVersion.Platform -eq 'Win32NT'))
                    {
                        $resolvedPath = 'C:\ffmpeg\bin\ffmpeg.exe'
                    }
                    elseif ($IsMacOS -or ($null -eq $IsMacOS -and [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)))
                    {
                        $resolvedPath = '/usr/local/bin/ffmpeg'
                    }
                    else
                    {
                        # Linux or other
                        $resolvedPath = '/usr/bin/ffmpeg'
                    }
                    Write-VerboseMessage "Using default FFmpeg path for platform: $resolvedPath"
                }
            }

            if (-not (Test-Path -Path $resolvedPath -PathType Leaf))
            {
                throw "FFmpeg executable not found at: '$resolvedPath'"
            }

            return $resolvedPath
        }

        # Validate FFmpeg path once in begin block
        try
        {
            $script:ValidatedFFmpegPath = Get-ValidFFmpegPath -ProvidedPath $FFmpegPath
        }
        catch
        {
            Write-Error $_.Exception.Message
            # Set flag to indicate initialization failed
            $script:initializationFailed = $true
            return $false
        }

        # Initialize counters for summary
        $script:totalProcessed = 0
        $script:totalSuccessful = 0
        $script:totalSkipped = 0
        $script:totalFailed = 0
        $script:scriptStartTime = Get-Date
        $script:globalFileCounter = 0
        $script:totalFilesAcrossAllPaths = 0

        # Normalize file extension (ensure it has no leading dot)
        $Extension = $Extension.TrimStart('.')
    }

    process
    {
        # First pass: collect all files to get total count for progress reporting
        $allFilesToProcess = @()

        foreach ($currentPath in $Path)
        {
            Write-Verbose "Scanning path: $currentPath"

            # Validate Input Directory
            if (-not (Test-Path -Path $currentPath -PathType Container))
            {
                Write-Error "Input directory not found: '$currentPath'"
                $script:totalFailed++
                continue
            }

            # Find files to process
            if ($NoRecursion)
            {
                Write-VerboseMessage "Searching for *.$Extension files in current directory only"
                $filesToProcess = Get-ChildItem -Path $currentPath -Filter "*.$Extension" -File
            }
            else
            {
                Write-VerboseMessage "Searching recursively for *.$Extension files (excluding $($Exclude -join ', '))"
                $filesToProcess = Get-ChildItem -Path $currentPath -Recurse -Filter "*.$Extension" -File | Where-Object {
                    $fullPath = $_.FullName
                    -not ($Exclude | Where-Object { $fullPath -like "*$_*" })
                }
            }

            foreach ($file in $filesToProcess)
            {
                $allFilesToProcess += [PSCustomObject]@{
                    File = $file
                    SourcePath = $currentPath
                }
            }
        }

        $script:totalFilesAcrossAllPaths = $allFilesToProcess.Count
        $script:totalProcessed = $script:totalFilesAcrossAllPaths

        if ($script:totalFilesAcrossAllPaths -eq 0)
        {
            Write-Warning "No '$Extension' files found in any of the specified paths"
            return $true
        }

        Write-Host "Found $script:totalFilesAcrossAllPaths file(s) to process across all paths" -ForegroundColor Green

        # Second pass: process all files with unified progress reporting
        foreach ($fileInfo in $allFilesToProcess)
        {
            $script:globalFileCounter++
            $file = $fileInfo.File
            $currentPath = $fileInfo.SourcePath

            $inputFilePath = $file.FullName
            $outputFilePath = [System.IO.Path]::ChangeExtension($inputFilePath, 'mp4')
            $inputFile = $file.Name
            $outputFile = [System.IO.Path]::GetFileName($outputFilePath)

            # Get file size for progress display
            $inputFileInfo = Get-Item -Path $inputFilePath -ErrorAction SilentlyContinue
            $fileSizeFormatted = if ($inputFileInfo) { Format-FileSize -SizeInBytes $inputFileInfo.Length } else { 'Unknown' }

            # Calculate progress percentage
            $progressPercent = [math]::Round(($script:globalFileCounter / $script:totalFilesAcrossAllPaths) * 100, 1)

            # Estimate remaining time
            $estimatedTimeRemaining = if ($script:globalFileCounter -gt 1)
            {
                Get-EstimatedTimeRemaining -StartTime $script:scriptStartTime -CompletedItems ($script:globalFileCounter - 1) -TotalItems $script:totalFilesAcrossAllPaths
            }
            else
            {
                'Calculating...'
            }

            # Progress information to console with ETA
            Write-Host "[$script:globalFileCounter/$script:totalFilesAcrossAllPaths] Processing: '$inputFile' ($fileSizeFormatted) | ETA: $estimatedTimeRemaining" -ForegroundColor Yellow

            # Check if output file already exists
            if ((Test-Path -Path $outputFilePath) -and (-not $Force))
            {
                Write-Warning "Output file '$outputFile' already exists. Use -Force to overwrite. Skipping..."
                $script:totalSkipped++
                continue
            }

            # ShouldProcess check for conversion operation
            $operationDescription = if ($Passthrough)
            {
                "Convert '$inputFile' to '$outputFile' using passthrough mode (copy video/audio, encode subtitles)"
            }
            else
            {
                "Convert '$inputFile' to '$outputFile' using $VideoEncoder encoding with Samsung-friendly settings"
            }
            if (-not $KeepSourceFile)
            {
                $operationDescription += ' and delete source file'
            }
            if (-not $PSCmdlet.ShouldProcess($inputFile, $operationDescription))
            {
                $script:totalSkipped++
                continue
            }

            Write-VerboseMessage "Converting to: '$outputFile'"
            Write-VerboseMessage "Input path: '$inputFilePath'"
            Write-VerboseMessage "Output path: '$outputFilePath'"

            # Verify input file exists and has content
            if (-not (Test-Path -Path $inputFilePath -PathType Leaf))
            {
                Write-Error "Input file not found: '$inputFilePath'"
                $script:totalFailed++
                continue
            }

            # Check if input file has content (not 0 bytes)
            if ($inputFileInfo.Length -eq 0)
            {
                Write-Warning "Skipping '$inputFile' - file is empty (0 bytes)"
                $script:totalSkipped++
                continue
            }

            # Ensure output directory exists
            $outputDirectory = [System.IO.Path]::GetDirectoryName($outputFilePath)
            if (-not (Test-Path -Path $outputDirectory -PathType Container))
            {
                try
                {
                    New-Item -Path $outputDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    Write-VerboseMessage "Created output directory: '$outputDirectory'"
                }
                catch
                {
                    Write-Error "Failed to create output directory '$outputDirectory'. Error: $($_.Exception.Message)"
                    $script:totalFailed++
                    continue
                }
            }

            # Construct ffmpeg arguments using Samsung-friendly encoding settings
            if ($Passthrough)
            {
                # Passthrough mode: copy video and audio without re-encoding, only encode subtitles
                $ffmpegArgs = @(
                    '-i', "`"$inputFilePath`"",                      # Input file (quoted)
                    '-vcodec', 'copy',                               # Copy video stream without re-encoding
                    '-acodec', 'copy',                               # Copy audio stream without re-encoding
                    '-scodec', 'mov_text',                           # Convert subtitles to mov_text format (MP4 compatible)
                    '-map', '0:v',                                   # Map video stream
                    '-map', '0:a',                                   # Map audio stream
                    '-map', '0:s?',                                  # Map subtitle streams if they exist (optional)
                    '-movflags', '+faststart'                        # Web-optimized for progressive download
                )
            }
            elseif ($VideoEncoder -eq 'H.264')
            {
                # Samsung-friendly H.264 encoding: 4K30, High profile, Level 5.1, up to 100 Mbps
                $ffmpegArgs = @(
                    '-i', "`"$inputFilePath`"",                      # Input file (quoted)
                    '-vcodec', 'libx264',                            # H.264 video codec
                    '-preset', 'medium',                             # Encoding speed preset (balance of speed vs compression)
                    '-crf', '18',                                    # Constant rate factor (near-visually-lossless quality)
                    '-profile', 'high',                              # H.264 High profile for Samsung compatibility
                    '-level', '5.1',                                 # H.264 Level 5.1 (seamless up to 3840×2160)
                    '-pix_fmt', 'yuv420p',                           # Pixel format for wide compatibility
                    '-framerate', '30',                              # Max 30 fps for 4K on Samsung TV
                    '-maxrate', '100M',                              # Max bitrate 100 Mbps
                    '-bufsize', '200M',                              # Buffer size (2x maxrate)
                    '-x264-params', 'keyint=60:min-keyint=60',       # Keyframe interval settings
                    '-acodec', 'aac',                                # AAC audio codec
                    '-b:a', '192k',                                  # Audio bitrate 192 kbps
                    '-ac', '2',                                      # 2 audio channels (stereo)
                    '-ar', '48000',                                  # Audio sample rate 48 kHz
                    '-scodec', 'mov_text',                           # Convert subtitles to mov_text format (MP4 compatible)
                    '-map', '0:v',                                   # Map video stream
                    '-map', '0:a',                                   # Map audio stream
                    '-map', '0:s?',                                  # Map subtitle streams if they exist (optional)
                    '-movflags', '+faststart'                        # Web-optimized for progressive download
                )
            }
            else # H.265
            {
                # Samsung-friendly H.265 encoding: 4K60, Level 5.2, up to 100 Mbps (better compression)
                $ffmpegArgs = @(
                    '-i', "`"$inputFilePath`"",                      # Input file (quoted)
                    '-vcodec', 'libx265',                            # H.265 video codec
                    '-preset', 'medium',                             # Encoding speed preset (balance of speed vs compression)
                    '-crf', '22',                                    # Constant rate factor (good quality for H.265)
                    '-x265-params', 'level-idc=5.2:keyint=60',       # H.265 Level 5.2 with keyframe interval
                    '-pix_fmt', 'yuv420p10le',                       # 10-bit pixel format for better quality
                    '-r', '60',                                      # Max 60 fps for 4K with H.265
                    '-acodec', 'aac',                                # AAC audio codec
                    '-b:a', '192k',                                  # Audio bitrate 192 kbps
                    '-ac', '2',                                      # 2 audio channels (stereo)
                    '-ar', '48000',                                  # Audio sample rate 48 kHz
                    '-scodec', 'mov_text',                           # Convert subtitles to mov_text format (MP4 compatible)
                    '-map', '0:v',                                   # Map video stream
                    '-map', '0:a',                                   # Map audio stream
                    '-map', '0:s?',                                  # Map subtitle streams if they exist (optional)
                    '-movflags', '+faststart'                        # Web-optimized for progressive download
                )
            }

            # Add force overwrite if needed
            if ($Force)
            {
                $ffmpegArgs += '-y'
            }

            # Add output file
            $ffmpegArgs += "`"$outputFilePath`""

            # Execute ffmpeg
            try
            {
                Write-VerboseMessage "Running FFmpeg with arguments: $($ffmpegArgs -join ' ')"

                # Cross-platform FFmpeg execution to preserve TTY behavior for proper progress display
                # Windows uses Start-Process for better process control, Unix systems use direct execution
                if ($IsWindows -or ($null -eq $IsWindows -and [Environment]::OSVersion.Platform -eq 'Win32NT'))
                {
                    # Windows: Use Start-Process with available parameters
                    if ($PSVersionTable.PSVersion.Major -ge 6)
                    {
                        # PowerShell Core on Windows
                        $process = Start-Process -FilePath $script:ValidatedFFmpegPath -ArgumentList $ffmpegArgs -Wait -PassThru
                    }
                    else
                    {
                        # PowerShell Desktop on Windows
                        $process = Start-Process -FilePath $script:ValidatedFFmpegPath -ArgumentList $ffmpegArgs -NoNewWindow -Wait -PassThru
                    }

                    $LASTEXITCODE = $process.ExitCode
                }
                else
                {
                    # macOS/Linux: Use direct execution which preserves TTY behavior better
                    & $script:ValidatedFFmpegPath @ffmpegArgs
                }

                if ($LASTEXITCODE -ne 0)
                {
                    Write-Warning "FFmpeg failed for '$inputFile' with exit code $LASTEXITCODE."
                    $script:totalFailed++

                    if ($PauseOnError)
                    {
                        Read-Host 'Press Enter to continue...'
                    }
                }
                else
                {
                    Write-Host "Successfully converted '$inputFile' to '$outputFile'" -ForegroundColor Green
                    $script:totalSuccessful++

                    # Delete input file unless KeepSourceFile is specified
                    if (-not $KeepSourceFile)
                    {
                        if ($PSCmdlet.ShouldProcess($inputFile, 'Delete source file'))
                        {
                            try
                            {
                                Remove-Item -Path $inputFilePath -Confirm:$false -ErrorAction Stop
                                Write-Host "Deleted input file '$inputFile'" -ForegroundColor Green
                            }
                            catch
                            {
                                Write-Warning "Failed to delete '$inputFile'. Error: $($_.Exception.Message)"
                            }
                        }
                    }
                }
            }
            catch
            {
                Write-Error "Error running FFmpeg for '$inputFile'. Error: $($_.Exception.Message)"
                $script:totalFailed++

                if ($PauseOnError)
                {
                    Read-Host 'Press Enter to continue...'
                }
            }

            Write-Host ''
        }
    }

    end
    {
        # Skip end block processing if initialization failed
        if ($script:initializationFailed)
        {
            return $false
        }

        # Calculate elapsed time
        $scriptEndTime = Get-Date
        $elapsedTime = Format-ElapsedTime -StartTime $script:scriptStartTime -EndTime $scriptEndTime

        # Summary
        Write-Host '----------------------------------------' -ForegroundColor Cyan
        Write-Host 'Summary:' -ForegroundColor Cyan
        Write-Host "  Total processed: $script:totalProcessed" -ForegroundColor Cyan
        Write-Host "  Successful: $script:totalSuccessful" -ForegroundColor $(if ($script:totalSuccessful -gt 0) { 'Green' }else { 'Cyan' })
        Write-Host "  Skipped: $script:totalSkipped" -ForegroundColor $(if ($script:totalSkipped -gt 0) { 'Yellow' }else { 'Cyan' })
        Write-Host "  Failed: $script:totalFailed" -ForegroundColor $(if ($script:totalFailed -gt 0) { 'Red' }else { 'Cyan' })
        Write-Host "  Total time: $elapsedTime" -ForegroundColor Cyan
        Write-Host '----------------------------------------' -ForegroundColor Cyan

        # Return success if no errors occurred
        return ($script:totalFailed -eq 0)
    }
}
