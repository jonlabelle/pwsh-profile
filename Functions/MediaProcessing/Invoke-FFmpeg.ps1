function Invoke-FFmpeg
{
    <#
    .SYNOPSIS
        Converts video files using Samsung-friendly encoding settings with H.264 or H.265 video encoding.

    .DESCRIPTION
        This function processes video files in a specified directory using Samsung-friendly encoding settings.
        For H.264: Supports 4K30 with High profile, Level 5.1, up to 100 Mbps bitrate for optimal Samsung TV compatibility.
        For H.265: Supports 4K60 with Level 5.2, up to 100 Mbps bitrate for better compression.
        Audio is intelligently converted based on source characteristics: E-AC-3 for multichannel content,
        enhanced AAC-LC for stereo, preserving original channel layout and sample rate when possible.
        Optimized for Samsung Neo QLED QN70F (2025) and web streaming via built-in browser.
        Source files are preserved by default unless -DeleteSourceFile is specified.

    .PARAMETER Path
        The directory containing the video files to be processed, or individual video file paths.
        Accepts an array of paths and supports pipeline input.

    .PARAMETER Extension
        The file extension of input video files. Defaults to 'mkv'.

    .PARAMETER FFmpegPath
        Path to the FFmpeg executable. If not specified, attempts to use 'ffmpeg' from PATH,
        then falls back to platform-specific default locations.

    .PARAMETER Force
        If specified, overwrites output files that already exist.

    .PARAMETER DeleteSourceFile
        If specified, input file(s) will be deleted after successful conversion.

    .PARAMETER PauseOnError
        If specified, the function will wait for user input when an error occurs instead of automatically continuing to the next file.

    .PARAMETER Recurse
        If specified, enables recursive searching through all subdirectories.
        By default, search is non-recursive (current directory only).

    .PARAMETER Exclude
        Specifies directories to exclude when searching recursively.
        Only applies when -Recurse is specified.
        Defaults to @('.git', 'node_modules').

    .PARAMETER VideoEncoder
        Specifies the video encoder to use. Valid values are 'H.264' and 'H.265'.
        H.264 provides faster encoding with 4K30 support, while H.265 offers better compression with 4K60 support.
        Defaults to 'H.264' for Samsung TV compatibility.
        This parameter cannot be used with -PassthroughVideo.

    .PARAMETER PassthroughVideo
        If specified, passes through video without re-encoding while still processing audio according to other settings.
        This is faster but doesn't apply Samsung-friendly video encoding settings.
        This parameter cannot be used with -VideoEncoder.

    .PARAMETER PassthroughAudio
        If specified, passes through audio without re-encoding while still processing video according to other settings.
        This is faster but doesn't apply Samsung-friendly audio encoding settings.

    .PARAMETER ClearMetadata
        If specified, removes all metadata from the output file. This includes title, artist, album,
        comment, creation time, and other metadata tags. Useful for creating clean output files
        without any identifying information or unnecessary metadata that can increase file size.
        Note: Essential stream metadata required for playback is preserved.

    .PARAMETER IncludeSubtitles
        Controls subtitle handling behavior. Valid values are:
        - 'Auto': Include text-based subtitles only (default for MP4 compatibility)
        - 'All': Include all subtitles (may cause errors with bitmap subtitles in MP4)
        - 'None': Exclude all subtitles from output
        Defaults to 'Auto'.

        The 'Auto' mode intelligently detects subtitle types and only includes text-based
        subtitles (SRT, ASS, WebVTT) and closed captions (CEA-608/708) that are compatible
        with MP4, while skipping
        bitmap subtitles (PGS, DVD) that can cause encoding errors. This resolves
        the common "Subtitle encoding currently only possible from text to text or
        bitmap to bitmap" error when processing files with PGS subtitles.

    .PARAMETER OutputPath
        Specifies the output file path or directory for the converted video.

        If a file path is provided (with extension), the output will be saved to that exact location.
        If a directory path is provided, the output file will be saved in that directory with the
        original filename but with .mp4 extension.
        If not specified, the output file will be created in the same directory as the input file
        with .mp4 extension (existing behavior).

        This parameter only applies when processing individual files. When processing directories,
        the original directory structure is preserved.

    .PARAMETER WhatIf
        If specified, shows what operations would be performed without actually executing them.
        Useful for previewing the conversion process before running it.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "C:\Videos" -Extension "mkv"

        Processes all .mkv files in C:\Videos using H.264 encoding (default) with Samsung-friendly settings.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "C:\Videos" -VideoEncoder "H.265" -Force

        Processes videos using H.265 encoding for better compression and overwrites existing output files.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "D:\Movies" -Extension "avi" -VideoEncoder "H.264"

        Processes all .avi files using H.264 encoding and preserves the input files.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "D:\Movies"

        Processes only the .mkv files directly in D:\Movies without searching subdirectories (default behavior).

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "D:\Movies" -Recurse

        Processes all .mkv files in D:\Movies and all subdirectories recursively.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "D:\Movies" -PassthroughVideo -DeleteSourceFile

        Processes all .mkv files using video passthrough (no video re-encoding) and deletes the source files after successful conversion.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "D:\Movies" -PassthroughAudio -VideoEncoder "H.265"

        Processes all .mkv files using H.265 video encoding while passing through the audio without re-encoding.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "C:\Videos" -WhatIf

        Shows what operations would be performed on all target files in C:\Videos without actually executing them.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "C:\Videos" -IncludeSubtitles "None"

        Processes all .mkv files in C:\Videos while excluding all subtitle streams from the output.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "C:\Videos" -IncludeSubtitles "All" -PassthroughVideo -PassthroughAudio

        Processes videos with passthrough for video/audio and attempts to include all subtitle types (may fail with bitmap subtitles in MP4).

    .EXAMPLE
        PS > Invoke-FFmpeg -Path @("C:\Videos", "D:\Movies") -Extension "mkv"

        Processes all .mkv files in multiple directories by passing an array to the Path parameter.

    .EXAMPLE
        PS > @("C:\Videos", "D:\Movies") | Invoke-FFmpeg -Extension "mkv"

        Processes all .mkv files in multiple directories using pipeline input.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path ".\Blazing Saddles.mkv" -PassthroughVideo -PassthroughAudio

        Processes a single video file with both video and audio passthrough (no re-encoding) and preserves the source file.

    .EXAMPLE
        PS > Get-ChildItem -Directory | Invoke-FFmpeg -VideoEncoder "H.265"

        Processes videos in all subdirectories using H.265 encoding via pipeline input.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "C:\Videos" -IncludeSubtitles "None"

        Processes all .mkv files in C:\Videos while excluding all subtitle streams from the output.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "C:\Videos" -IncludeSubtitles "All" -PassthroughVideo -PassthroughAudio

        Processes videos with passthrough for video/audio and attempts to include all subtitle types (may fail with bitmap subtitles in MP4).

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "movie.mkv" -ClearMetadata

        Converts a movie file using default H.264 encoding and removes all metadata from the output file.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "C:\Videos" -Recurse -ClearMetadata -VideoEncoder "H.265"

        Recursively processes all videos with H.265 encoding and strips all metadata tags for clean output files.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "C:\Movies" -VideoEncoder "H.264" -Verbose

        Processes movies with H.264 encoding and shows detailed audio codec selection reasoning:
        - Files with 5.1/7.1 surround sound: Automatically uses E-AC-3 at 640k for Samsung Neo QLED
        - Stereo files: Uses enhanced AAC-LC at 256k-320k (vs legacy 192k)
        - Preserves original sample rates ≥48kHz and channel layouts

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "D:\TV Shows" -Extension "mkv" -Recurse -VideoEncoder "H.265"

        Recursively processes TV show files with H.265 encoding and intelligent audio optimization:
        - Multichannel episodes: Converted to E-AC-3 for surround sound preservation
        - Stereo episodes: Enhanced to high-quality AAC-LC encoding
        - All optimized for Samsung Neo QLED QN70F (2025) and web streaming

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "movie-with-dts.mkv" -PassthroughVideo

        Processes a single movie file with video passthrough while intelligently handling audio:
        - If source has DTS 5.1: Converts to E-AC-3 640k for Samsung compatibility
        - If source has stereo: Upgrades to AAC-LC 256k+ for better quality
        - Maintains web streaming optimization with +faststart

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "movie.mkv" -OutputPath "converted\movie.mp4"

        Converts a single movie file and saves it to the specified output path.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "video.mkv" -OutputPath "C:\Converted"

        Converts a single video file and saves it to the specified directory with the original filename but .mp4 extension.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "source.mkv" -OutputPath "final-output.mp4" -VideoEncoder "H.265"

        Converts a video using H.265 encoding and saves it with a custom filename.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "movie.mkv" -OutputPath "~/Desktop/converted.mp4" -PassthroughVideo

        Converts a video with video passthrough and saves it to the user's Desktop with a custom filename.

    .EXAMPLE
        PS > Invoke-FFmpeg -Path "~/Downloads/sample.mkv" -OutputPath "~/Videos/converted-sample.mp4" -VideoEncoder "H.265"

        Converts a specific video file from the Downloads folder using H.265 encoding and saves it to the Videos folder with a new filename.

    .LINK
        https://ffmpeg.org/documentation.html

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/MediaProcessing/Invoke-FFmpeg.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/MediaProcessing/Invoke-FFmpeg.ps1
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
        $Path = (Get-Location),

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
        $DeleteSourceFile,

        [Parameter()]
        [switch]
        $PauseOnError,

        [Parameter()]
        [switch]
        $Recurse,

        [Parameter()]
        [string[]]
        $Exclude = @('.git', 'node_modules'),

        [Parameter(ParameterSetName = 'Encode')]
        [ValidateSet('H.264', 'H.265')]
        [string]
        $VideoEncoder = 'H.264',

        [Parameter(ParameterSetName = 'VideoPassthrough')]
        [switch]
        $PassthroughVideo,

        [Parameter()]
        [switch]
        $PassthroughAudio,

        [Parameter()]
        [switch]
        $ClearMetadata,

        [Parameter()]
        [ValidateSet('Auto', 'All', 'None')]
        [string]
        $IncludeSubtitles = 'Auto',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $OutputPath
    )

    begin
    {
        # Platform detection
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # PowerShell 5.1 - Windows only
            $script:IsWindowsPlatform = $true
            $script:IsMacOSPlatform = $false
            $script:IsLinuxPlatform = $false
        }
        else
        {
            # PowerShell Core - cross-platform
            $script:IsWindowsPlatform = $IsWindows
            $script:IsMacOSPlatform = $IsMacOS
            $script:IsLinuxPlatform = $IsLinux
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

        # Function to analyze audio streams and determine optimal encoding strategy for Samsung Neo QLED QN70F (2025)
        function Get-AudioEncodingStrategy
        {
            param(
                [String]$FilePath,
                [String]$FFmpegPath
            )

            try
            {
                # Helper function to load Get-VideoDetails dependency if needed
                function Import-DependencyIfNeeded
                {
                    param(
                        [Parameter(Mandatory)]
                        [String]$FunctionName,

                        [Parameter(Mandatory)]
                        [String]$RelativePath
                    )

                    if (-not (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue))
                    {
                        Write-Verbose "$FunctionName is required - attempting to load it"

                        # Resolve path from current script location
                        $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath $RelativePath
                        $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)

                        if (Test-Path -Path $dependencyPath -PathType Leaf)
                        {
                            try
                            {
                                . $dependencyPath
                                Write-Verbose "Loaded $FunctionName from: $dependencyPath"
                            }
                            catch
                            {
                                throw "Failed to load required dependency '$FunctionName' from '$dependencyPath': $($_.Exception.Message)"
                            }
                        }
                        else
                        {
                            throw "Required function '$FunctionName' could not be found. Expected location: $dependencyPath"
                        }
                    }
                    else
                    {
                        Write-Verbose "$FunctionName is already loaded"
                    }
                }

                # Load Get-MediaInfo if needed
                Import-DependencyIfNeeded -FunctionName 'Get-MediaInfo' -RelativePath 'Get-MediaInfo.ps1'

                # Try to find ffprobe path for Get-MediaInfo
                $ffprobeExecutable = $FFmpegPath -replace 'ffmpeg(\.exe)?$', 'ffprobe$1'

                if (-not (Test-Path $ffprobeExecutable))
                {
                    # Fallback: try ffprobe in PATH
                    $ffprobeCommand = Get-Command -Name 'ffprobe' -ErrorAction SilentlyContinue
                    if ($ffprobeCommand)
                    {
                        $ffprobeExecutable = $ffprobeCommand.Source
                    }
                    else
                    {
                        Write-Verbose 'FFprobe not found - using fallback audio settings'
                        return @{
                            Codec = 'aac'
                            Bitrate = '256k'
                            Channels = '2'
                            SampleRate = '48000'
                            Reasoning = 'Fallback: FFprobe unavailable'
                        }
                    }
                }

                # Use Get-MediaInfo to analyze the file
                $mediaInfo = Get-MediaInfo -Path $FilePath -FFprobePath $ffprobeExecutable -Extended -ErrorAction SilentlyContinue

                if (-not $mediaInfo -or -not $mediaInfo.Audio -or $mediaInfo.Audio.Count -eq 0)
                {
                    Write-Verbose 'No audio stream detected - using default settings'
                    return @{
                        Codec = 'aac'
                        Bitrate = '256k'
                        Channels = '2'
                        SampleRate = '48000'
                        Reasoning = 'No audio stream detected'
                    }
                }

                # Analyze primary audio stream (first audio track)
                $primaryAudio = $mediaInfo.Audio[0]
                $channels = [int]$primaryAudio.Channels
                $sampleRate = [int]$primaryAudio.SampleRate
                $sourceCodec = $primaryAudio.Codec.ToLower()

                Write-Verbose "Source audio: $sourceCodec, $channels channels, $sampleRate Hz"

                # Samsung Neo QLED QN70F (2025) intelligent codec selection
                if ($channels -gt 2)
                {
                    # Multichannel content: Use E-AC-3 for Samsung Neo QLED optimal support
                    $targetChannels = [Math]::Min($channels, 8)  # Cap at 7.1 (8 channels)
                    return @{
                        Codec = 'eac3'
                        Bitrate = '640k'  # E-AC-3 supports up to 640k efficiently
                        Channels = $targetChannels.ToString()
                        SampleRate = ([Math]::Max($sampleRate, 48000)).ToString()
                        Reasoning = "Multichannel ($channels ch) → E-AC-3 for Samsung Neo QLED surround support"
                    }
                }
                else
                {
                    # Stereo content: Use enhanced AAC-LC with higher bitrate than legacy 192k
                    $targetBitrate = if ($sampleRate -ge 96000) { '320k' } elseif ($sampleRate -ge 48000) { '256k' } else { '224k' }
                    return @{
                        Codec = 'aac'
                        Bitrate = $targetBitrate
                        Channels = '2'
                        SampleRate = ([Math]::Max($sampleRate, 48000)).ToString()
                        Reasoning = "Stereo → Enhanced AAC-LC ($targetBitrate) for Samsung Neo QLED quality"
                    }
                }
            }
            catch
            {
                Write-Verbose "Error analyzing audio stream: $($_.Exception.Message)"
                return @{
                    Codec = 'aac'
                    Bitrate = '256k'
                    Channels = '2'
                    SampleRate = '48000'
                    Reasoning = 'Error during analysis - using enhanced fallback'
                }
            }
        }

        # Function to analyze subtitle streams and determine handling strategy
        function Get-SubtitleHandlingStrategy
        {
            param(
                [String]$FilePath,
                [String]$FFmpegPath,
                [String]$IncludeSubtitles
            )

            if ($IncludeSubtitles -eq 'None')
            {
                return @{
                    IncludeSubtitles = $false
                    SubtitleArgs = @()
                    WarningMessage = $null
                }
            }

            try
            {
                # Use the existing Get-MediaInfo function to get subtitle information
                # Helper function to load Get-MediaInfo dependency if needed
                function Import-DependencyIfNeeded
                {
                    param(
                        [Parameter(Mandatory)]
                        [String]$FunctionName,

                        [Parameter(Mandatory)]
                        [String]$RelativePath
                    )

                    if (-not (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue))
                    {
                        Write-Verbose "$FunctionName is required - attempting to load it"

                        # Resolve path from current script location
                        $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath $RelativePath
                        $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)

                        if (Test-Path -Path $dependencyPath -PathType Leaf)
                        {
                            try
                            {
                                . $dependencyPath
                                Write-Verbose "Loaded $FunctionName from: $dependencyPath"
                            }
                            catch
                            {
                                throw "Failed to load required dependency '$FunctionName' from '$dependencyPath': $($_.Exception.Message)"
                            }
                        }
                        else
                        {
                            throw "Required function '$FunctionName' could not be found. Expected location: $dependencyPath"
                        }
                    }
                    else
                    {
                        Write-Verbose "$FunctionName is already loaded"
                    }
                }

                # Load Get-MediaInfo if needed
                Import-DependencyIfNeeded -FunctionName 'Get-MediaInfo' -RelativePath 'Get-MediaInfo.ps1'

                # Try to find ffprobe path for Get-MediaInfo
                $ffprobeExecutable = $FFmpegPath -replace 'ffmpeg(\.exe)?$', 'ffprobe$1'

                if (-not (Test-Path $ffprobeExecutable))
                {
                    # Fallback: try ffprobe in PATH
                    $ffprobeCommand = Get-Command -Name 'ffprobe' -ErrorAction SilentlyContinue
                    if ($ffprobeCommand)
                    {
                        $ffprobeExecutable = $ffprobeCommand.Source
                    }
                    else
                    {
                        Write-Verbose 'FFprobe not found - subtitle analysis skipped'
                        return @{
                            IncludeSubtitles = $false
                            SubtitleArgs = @()
                            WarningMessage = $null
                        }
                    }
                }

                # Use Get-MediaInfo to analyze the file
                $mediaInfo = Get-MediaInfo -Path $FilePath -FFprobePath $ffprobeExecutable -Extended -ErrorAction SilentlyContinue

                if (-not $mediaInfo -or -not $mediaInfo.Subtitles -or $mediaInfo.Subtitles.Count -eq 0)
                {
                    return @{
                        IncludeSubtitles = $false
                        SubtitleArgs = @()
                        WarningMessage = $null
                    }
                }

                # Categorize subtitle streams using the detailed subtitle information
                $textBasedCodecs = @('subrip', 'ass', 'ssa', 'webvtt', 'mov_text', 'srt', 'text')
                $closedCaptionCodecs = @('eia_608', 'eia_708', 'cea_608', 'cea_708', 'cc_dec', 'scc')
                $bitmapCodecs = @('hdmv_pgs_subtitle', 'dvd_subtitle', 'pgssub', 'dvdsub', 'pgs')

                $textSubtitles = @()
                $bitmapSubtitles = @()
                $closedCaptionSubtitles = @()

                foreach ($subtitle in $mediaInfo.Subtitles)
                {
                    $codecName = if ($subtitle.Codec) { $subtitle.Codec.ToLower() } else { '' }

                    if ($codecName -in $closedCaptionCodecs)
                    {
                        # Treat closed captions as text-based so they are preserved in the output
                        $textSubtitles += $subtitle
                        $closedCaptionSubtitles += $subtitle
                    }
                    elseif ($codecName -in $textBasedCodecs)
                    {
                        $textSubtitles += $subtitle
                    }
                    elseif ($codecName -in $bitmapCodecs)
                    {
                        $bitmapSubtitles += $subtitle
                    }
                    else
                    {
                        # Unknown codec, treat as bitmap for safety
                        $bitmapSubtitles += $subtitle
                    }
                }

                $warningMessage = $null
                $subtitleArgs = @()
                $includeSubtitles = $false

                if ($closedCaptionSubtitles.Count -gt 0)
                {
                    Write-Verbose "Detected $($closedCaptionSubtitles.Count) closed caption stream(s); including for output"
                }

                if ($IncludeSubtitles -eq 'All')
                {
                    if ($bitmapSubtitles.Count -gt 0)
                    {
                        $warningMessage = "Warning: File contains $($bitmapSubtitles.Count) bitmap subtitle stream(s) (e.g., PGS/DVD subtitles) which may not be compatible with MP4. Consider using -IncludeSubtitles 'Auto' or 'None'."
                    }

                    $subtitleArgs = @('-scodec', 'mov_text', '-map', '0:s?')
                    $includeSubtitles = $true
                }
                elseif ($IncludeSubtitles -eq 'Auto')
                {
                    if ($textSubtitles.Count -gt 0)
                    {
                        # Map only text-based subtitle streams
                        $subtitleArgs = @('-scodec', 'mov_text')
                        foreach ($subtitle in $textSubtitles)
                        {
                            $subtitleArgs += @('-map', "0:$($subtitle.Index)")
                        }
                        $includeSubtitles = $true
                    }

                    if ($bitmapSubtitles.Count -gt 0)
                    {
                        $skippedMessage = "Skipping $($bitmapSubtitles.Count) bitmap subtitle stream(s) for MP4 compatibility"
                        if ($textSubtitles.Count -gt 0)
                        {
                            $warningMessage = "$skippedMessage (including $($textSubtitles.Count) compatible text subtitle(s))"
                        }
                        else
                        {
                            $warningMessage = $skippedMessage
                        }
                    }
                }

                return @{
                    IncludeSubtitles = $includeSubtitles
                    SubtitleArgs = $subtitleArgs
                    WarningMessage = $warningMessage
                }
            }
            catch
            {
                Write-Verbose "Error analyzing subtitle streams: $($_.Exception.Message)"
                return @{
                    IncludeSubtitles = $false
                    SubtitleArgs = @()
                    WarningMessage = $null
                }
            }
        }

        # Function to validate and resolve FFmpeg path
        function Get-ValidFFmpegPath
        {
            param([string]$ProvidedPath)

            $resolvedPath = $ProvidedPath

            # Normalize FFmpeg path if provided (handles ~, relative paths)
            if ($resolvedPath)
            {
                $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($resolvedPath)
            }

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
                    if ($script:IsWindowsPlatform)
                    {
                        # Try common Windows locations
                        $commonPaths = @(
                            'C:\ffmpeg\bin\ffmpeg.exe',
                            'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
                            'C:\Program Files (x86)\ffmpeg\bin\ffmpeg.exe',
                            "$env:USERPROFILE\ffmpeg\bin\ffmpeg.exe",
                            "$env:LOCALAPPDATA\ffmpeg\bin\ffmpeg.exe",
                            'C:\tools\ffmpeg\bin\ffmpeg.exe',
                            'C:\ProgramData\chocolatey\lib\ffmpeg\tools\ffmpeg\bin\ffmpeg.exe',
                            "$env:USERPROFILE\scoop\apps\ffmpeg\current\bin\ffmpeg.exe",
                            "$env:USERPROFILE\Documents\ffmpeg\bin\ffmpeg.exe",
                            'D:\ffmpeg\bin\ffmpeg.exe'
                        )

                        $foundPath = $null
                        foreach ($path in $commonPaths)
                        {
                            if (Test-Path $path -PathType Leaf)
                            {
                                $foundPath = $path
                                break
                            }
                        }

                        if ($foundPath)
                        {
                            $resolvedPath = $foundPath
                            Write-VerboseMessage "Found FFmpeg at: $resolvedPath"
                        }
                        else
                        {
                            $resolvedPath = 'C:\ffmpeg\bin\ffmpeg.exe'
                            Write-VerboseMessage "Using default Windows path (may not exist): $resolvedPath"
                        }
                    }
                    elseif ($script:IsMacOSPlatform)
                    {
                        # Try common macOS locations
                        $commonPaths = @(
                            '/usr/local/bin/ffmpeg',
                            '/opt/homebrew/bin/ffmpeg',
                            '/usr/bin/ffmpeg',
                            '/opt/local/bin/ffmpeg',
                            "$env:HOME/.local/bin/ffmpeg",
                            '/Applications/ffmpeg/ffmpeg',
                            '/usr/local/opt/ffmpeg/bin/ffmpeg'
                        )

                        $foundPath = $null
                        foreach ($path in $commonPaths)
                        {
                            if (Test-Path $path -PathType Leaf)
                            {
                                $foundPath = $path
                                break
                            }
                        }

                        if ($foundPath)
                        {
                            $resolvedPath = $foundPath
                            Write-VerboseMessage "Found FFmpeg at: $resolvedPath"
                        }
                        else
                        {
                            $resolvedPath = '/usr/local/bin/ffmpeg'
                            Write-VerboseMessage "Using default macOS path (may not exist): $resolvedPath"
                        }
                    }
                    else
                    {
                        # Try common Linux locations
                        $commonPaths = @(
                            '/usr/bin/ffmpeg',
                            '/usr/local/bin/ffmpeg',
                            '/snap/bin/ffmpeg',
                            '/opt/ffmpeg/bin/ffmpeg',
                            "$env:HOME/.local/bin/ffmpeg",
                            "$env:HOME/bin/ffmpeg",
                            '/usr/local/share/ffmpeg/ffmpeg'
                        )

                        $foundPath = $null
                        foreach ($path in $commonPaths)
                        {
                            if (Test-Path $path -PathType Leaf)
                            {
                                $foundPath = $path
                                break
                            }
                        }

                        if ($foundPath)
                        {
                            $resolvedPath = $foundPath
                            Write-VerboseMessage "Found FFmpeg at: $resolvedPath"
                        }
                        else
                        {
                            $resolvedPath = '/usr/bin/ffmpeg'
                            Write-VerboseMessage "Using default Linux path (may not exist): $resolvedPath"
                        }
                    }
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
            # Write error and throw to completely stop function execution
            Write-Error $_.Exception.Message -ErrorAction Stop
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
            # Normalize path first (handles ~, relative paths)
            $normalizedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($currentPath)
            Write-Verbose "Scanning path: $normalizedPath"

            # Validate that the path exists
            if (-not (Test-Path -Path $normalizedPath))
            {
                Write-Error "Path not found: '$normalizedPath'"
                $script:totalFailed++
                continue
            }

            $pathItem = Get-Item -Path $normalizedPath -ErrorAction Stop

            if ($pathItem.PSIsContainer)
            {
                # Handle directory - search for video files with optional recursion
                Write-VerboseMessage "Processing directory: $normalizedPath"

                # Find files to process
                if ($Recurse)
                {
                    Write-VerboseMessage "Searching recursively for *.$Extension files (excluding $($Exclude -join ', '))"
                    $filesToProcess = Get-ChildItem -Path $normalizedPath -Recurse -Filter "*.$Extension" -File | Where-Object {
                        $fullPath = $_.FullName
                        -not ($Exclude | Where-Object { $fullPath -like "*$_*" })
                    }
                }
                else
                {
                    Write-VerboseMessage "Searching for *.$Extension files in current directory only"
                    $filesToProcess = Get-ChildItem -Path $normalizedPath -Filter "*.$Extension" -File
                }

                foreach ($file in $filesToProcess)
                {
                    $allFilesToProcess += [PSCustomObject]@{
                        File = $file
                        SourcePath = $normalizedPath
                    }
                }
            }
            else
            {
                # Handle individual file
                Write-VerboseMessage "Processing individual file: $normalizedPath"

                # For individual files, process regardless of extension (user explicitly specified the file)
                # Extension parameter only applies to directory scanning
                $allFilesToProcess += [PSCustomObject]@{
                    File = $pathItem
                    SourcePath = $pathItem.DirectoryName
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

        # Validate OutputPath parameter usage
        if ($OutputPath -and $script:totalFilesAcrossAllPaths -gt 1)
        {
            Write-Warning 'OutputPath parameter is only supported when processing a single file. When processing multiple files or directories, files will be saved with default naming in their respective locations.'
            $OutputPath = $null
        }

        # Second pass: process all files with unified progress reporting
        foreach ($fileInfo in $allFilesToProcess)
        {
            $script:globalFileCounter++
            $file = $fileInfo.File
            $currentPath = $fileInfo.SourcePath

            $inputFilePath = $file.FullName
            $inputFile = $file.Name

            # Determine output file path based on OutputPath parameter
            if ($OutputPath)
            {
                # Normalize the output path
                $normalizedOutputPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

                # Check if OutputPath is a directory or file
                if ([System.IO.Path]::HasExtension($normalizedOutputPath))
                {
                    # OutputPath is a file path
                    $outputFilePath = $normalizedOutputPath
                }
                else
                {
                    # OutputPath is a directory - use original filename with .mp4 extension
                    $outputFileName = [System.IO.Path]::GetFileNameWithoutExtension($inputFile) + '.mp4'
                    $outputFilePath = Join-Path -Path $normalizedOutputPath -ChildPath $outputFileName
                }
            }
            else
            {
                # Use existing behavior - change extension to .mp4 in same directory
                $outputFilePath = [System.IO.Path]::ChangeExtension($inputFilePath, 'mp4')
            }

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
            $operationDescription = if ($PassthroughVideo)
            {
                "Convert '$inputFile' to '$outputFile' using video passthrough mode"
            }
            else
            {
                "Convert '$inputFile' to '$outputFile' using $VideoEncoder encoding with Samsung-friendly settings"
            }
            if ($PassthroughAudio)
            {
                $operationDescription += ' with audio passthrough'
            }
            if ($DeleteSourceFile)
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

            # Analyze audio streams for intelligent codec selection (Samsung Neo QLED QN70F 2025 optimized)
            $audioStrategy = Get-AudioEncodingStrategy -FilePath $inputFilePath -FFmpegPath $script:ValidatedFFmpegPath
            Write-VerboseMessage "Audio strategy: $($audioStrategy.Reasoning)"

            # Analyze subtitle streams and determine handling strategy
            $subtitleStrategy = Get-SubtitleHandlingStrategy -FilePath $inputFilePath -FFmpegPath $script:ValidatedFFmpegPath -IncludeSubtitles $IncludeSubtitles

            if ($subtitleStrategy.WarningMessage)
            {
                Write-Warning $subtitleStrategy.WarningMessage
            }

            # Construct ffmpeg arguments using Samsung-friendly encoding settings
            if ($PassthroughVideo -and $PassthroughAudio)
            {
                # Both passthrough mode: copy video and audio without re-encoding
                $ffmpegArgs = @(
                    '-i', $inputFilePath,                            # Input file
                    '-vcodec', 'copy',                               # Copy video stream without re-encoding
                    '-acodec', 'copy',                               # Copy audio stream without re-encoding
                    '-map', '0:v',                                   # Map video stream
                    '-map', '0:a?'                                   # Map audio stream (optional)
                )

                # Add subtitle handling based on strategy
                if ($subtitleStrategy.IncludeSubtitles)
                {
                    $ffmpegArgs += $subtitleStrategy.SubtitleArgs
                }

                # Clear metadata if requested
                if ($ClearMetadata)
                {
                    $ffmpegArgs += @('-map_metadata', '-1')      # Strip all metadata
                }

                $ffmpegArgs += @('-movflags', '+faststart')         # Web-optimized for progressive download
            }
            elseif ($PassthroughVideo)
            {
                # Video passthrough with intelligent audio encoding
                $ffmpegArgs = @(
                    '-i', $inputFilePath,                            # Input file
                    '-vcodec', 'copy',                               # Copy video stream without re-encoding
                    '-acodec', $audioStrategy.Codec,                 # Intelligent audio codec selection
                    '-b:a', $audioStrategy.Bitrate,                  # Optimized bitrate for Samsung Neo QLED
                    '-ac', $audioStrategy.Channels,                  # Preserve/optimize channel count
                    '-ar', $audioStrategy.SampleRate,                # Preserve/optimize sample rate
                    '-map', '0:v',                                   # Map video stream
                    '-map', '0:a?'                                   # Map audio stream (optional)
                )

                # Add subtitle handling based on strategy
                if ($subtitleStrategy.IncludeSubtitles)
                {
                    $ffmpegArgs += $subtitleStrategy.SubtitleArgs
                }

                # Clear metadata if requested
                if ($ClearMetadata)
                {
                    $ffmpegArgs += @('-map_metadata', '-1')      # Strip all metadata
                }

                $ffmpegArgs += @('-movflags', '+faststart')         # Web-optimized for progressive download
            }
            elseif ($VideoEncoder -eq 'H.264')
            {
                # Samsung-friendly H.264 encoding: 4K30, High profile, Level 5.1, up to 100 Mbps
                $videoArgs = @(
                    '-vcodec', 'libx264',                            # H.264 video codec
                    '-preset', 'medium',                             # Encoding speed preset (balance of speed vs compression)
                    '-crf', '18',                                    # Constant rate factor (near-visually-lossless quality)
                    '-profile', 'high',                              # H.264 High profile for Samsung compatibility
                    '-level', '5.1',                                 # H.264 Level 5.1 (seamless up to 3840×2160)
                    '-pix_fmt', 'yuv420p',                           # Pixel format for wide compatibility
                    '-framerate', '30',                              # Max 30 fps for 4K on Samsung TV
                    '-maxrate', '100M',                              # Max bitrate 100 Mbps
                    '-bufsize', '200M',                              # Buffer size (2x maxrate)
                    '-x264-params', 'keyint=60:min-keyint=60'        # Keyframe interval settings
                )

                $audioArgs = if ($PassthroughAudio)
                {
                    @('-acodec', 'copy')                             # Copy audio stream without re-encoding
                }
                else
                {
                    @(
                        '-acodec', $audioStrategy.Codec,             # Intelligent audio codec (E-AC-3/AAC)
                        '-b:a', $audioStrategy.Bitrate,              # Optimized bitrate for Samsung Neo QLED
                        '-ac', $audioStrategy.Channels,              # Preserve/optimize channel count
                        '-ar', $audioStrategy.SampleRate             # Preserve/optimize sample rate
                    )
                }

                $ffmpegArgs = @(
                    '-i', $inputFilePath                            # Input file
                ) + $videoArgs + $audioArgs + @(
                    '-map', '0:v',                                   # Map video stream
                    '-map', '0:a?'                                   # Map audio stream (optional)
                )

                # Add subtitle handling based on strategy
                if ($subtitleStrategy.IncludeSubtitles)
                {
                    $ffmpegArgs += $subtitleStrategy.SubtitleArgs
                }

                # Clear metadata if requested
                if ($ClearMetadata)
                {
                    $ffmpegArgs += @('-map_metadata', '-1')      # Strip all metadata
                }

                $ffmpegArgs += @('-movflags', '+faststart')         # Web-optimized for progressive download
            }
            else # H.265
            {
                # Samsung-friendly H.265 encoding: 4K60, Level 5.2, up to 100 Mbps (better compression)
                $videoArgs = @(
                    '-vcodec', 'libx265',                            # H.265 video codec
                    '-preset', 'medium',                             # Encoding speed preset (balance of speed vs compression)
                    '-crf', '22',                                    # Constant rate factor (good quality for H.265)
                    '-x265-params', 'level-idc=5.2:keyint=60',       # H.265 Level 5.2 with keyframe interval
                    '-pix_fmt', 'yuv420p10le',                       # 10-bit pixel format for better quality
                    '-r', '60'                                       # Max 60 fps for 4K with H.265
                )

                $audioArgs = if ($PassthroughAudio)
                {
                    @('-acodec', 'copy')                             # Copy audio stream without re-encoding
                }
                else
                {
                    @(
                        '-acodec', $audioStrategy.Codec,             # Intelligent audio codec (E-AC-3/AAC)
                        '-b:a', $audioStrategy.Bitrate,              # Optimized bitrate for Samsung Neo QLED
                        '-ac', $audioStrategy.Channels,              # Preserve/optimize channel count
                        '-ar', $audioStrategy.SampleRate             # Preserve/optimize sample rate
                    )
                }

                $ffmpegArgs = @(
                    '-i', $inputFilePath                            # Input file
                ) + $videoArgs + $audioArgs + @(
                    '-map', '0:v',                                   # Map video stream
                    '-map', '0:a?'                                   # Map audio stream (optional)
                )

                # Add subtitle handling based on strategy
                if ($subtitleStrategy.IncludeSubtitles)
                {
                    $ffmpegArgs += $subtitleStrategy.SubtitleArgs
                }

                # Clear metadata if requested
                if ($ClearMetadata)
                {
                    $ffmpegArgs += @('-map_metadata', '-1')      # Strip all metadata
                }

                $ffmpegArgs += @('-movflags', '+faststart')         # Web-optimized for progressive download
            }

            # Add force overwrite if needed
            if ($Force)
            {
                $ffmpegArgs += '-y'
            }

            # Add output file
            $ffmpegArgs += $outputFilePath

            # Execute ffmpeg
            try
            {
                # Display the FFmpeg command being executed
                Write-VerboseMessage "Running FFmpeg: `"$script:ValidatedFFmpegPath`" $($ffmpegArgs -join ' ')"

                # Cross-platform FFmpeg execution with progress display optimization
                # Note: PowerShell Desktop 5.1 doesn't support FFmpeg's real-time progress updates
                # due to console host limitations with carriage return (\r) handling
                if ($script:IsWindowsPlatform -and $PSVersionTable.PSVersion.Major -lt 6)
                {
                    # PowerShell Desktop 5.1: Inform user about progress display limitation
                    Write-Host 'Note: Real-time progress updates are not supported in PowerShell Desktop 5.1.' -ForegroundColor Yellow
                    Write-Host 'Progress will be shown in stacked lines. Consider using PowerShell Core (pwsh) for better progress display.' -ForegroundColor Yellow
                    Write-Host ''

                    # Use direct execution - simpler and more reliable
                    & $script:ValidatedFFmpegPath @ffmpegArgs
                }
                else
                {
                    # PowerShell Core and Unix systems: Use direct execution with proper progress display
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

                    # Delete input file if DeleteSourceFile is specified
                    if ($DeleteSourceFile)
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
