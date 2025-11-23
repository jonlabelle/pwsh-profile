function Get-VideoDetails
{
    <#
    .SYNOPSIS
        Retrieves detailed information about video files.

    .DESCRIPTION
        Retrieves comprehensive metadata and properties of video files using ffprobe.
        Returns file information, video codec details, audio codec details, duration,
        resolution, bitrate, frame rate, and more.

        Requires ffprobe to be installed and available in PATH or specified via -FFprobePath.

    .PARAMETER Path
        The path to the video file(s) to analyze. Accepts wildcards and pipeline input.
        Supports both absolute and relative paths.

    .PARAMETER Extended
        If specified, includes additional metadata such as aspect ratio, color space,
        codec profile/level, HDR information, language tags, stream counts, and more.

    .PARAMETER NoEmptyProps
        Excludes properties with null or empty values from the output. This provides cleaner results by only
        showing properties that have actual values, which is particularly useful when some metadata fields
        are not populated in the video file.

    .PARAMETER FFprobePath
        Path to the ffprobe executable. If not specified, attempts to use 'ffprobe' from PATH,
        then falls back to platform-specific default locations.

    .EXAMPLE
        PS > Get-VideoDetails -Path "movie.mp4"

        Name            : movie.mp4
        FullPath        : /Users/jon/movies/movie.mp4
        SizeBytes       : 21574440
        SizeFormatted   : 20.57 MB
        Extension       : .mp4
        CreatedDate     : 11/23/2025 2:19:14 PM
        ModifiedDate    : 11/23/2025 2:19:22 PM
        Duration        : 00:00:26.5333330
        Bitrate         : 6,505 kbps
        Format          : QuickTime / MOV
        Resolution      : 3752x2160
        VideoCodec      : H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10
        VideoCodecShort : h264
        FrameRate       : 60.00 fps
        PixelFormat     : yuv420p
        VideoBitrate    : 6,503 kbps

        Retrieves comprehensive video information for movie.mp4.

    .EXAMPLE
        PS > Get-VideoDetails -Path "C:\Videos\*.mkv"

        Retrieves detailed information for all .mkv files in the specified directory.

    .EXAMPLE
        PS > Get-ChildItem -Path "C:\Videos" -Filter "*.mp4" | Get-VideoDetails

        Retrieves detailed information for all .mp4 files via pipeline input.

    .EXAMPLE
        PS > Get-VideoDetails -Path "movie.mp4" -FFprobePath "/opt/ffmpeg/bin/ffprobe"

        Uses a custom ffprobe path to retrieve video information.

    .EXAMPLE
        PS > Get-VideoDetails -Path "movie.mp4" -Extended

        Name                  : movie.mp4
        FullPath              : /Users/jon/movies/movie.mp4
        SizeBytes             : 21574440
        SizeFormatted         : 20.57 MB
        Extension             : .mp4
        CreatedDate           : 11/23/2025 2:19:14 PM
        ModifiedDate          : 11/23/2025 2:19:22 PM
        Duration              : 00:00:26.5333330
        Bitrate               : 6,505 kbps
        Format                : QuickTime / MOV
        Resolution            : 3752x2160
        VideoCodec            : H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10
        VideoCodecShort       : h264
        FrameRate             : 60.00 fps
        PixelFormat           : yuv420p
        VideoBitrate          : 6,503 kbps
        AspectRatio           : 469:270
        ColorSpace            : bt709
        ColorRange            : tv
        ColorPrimaries        : bt709
        ColorTransfer         : bt709
        Profile               : High
        Level                 : 52
        BitDepth              : 8
        IsAVC                 : true
        HasHDR                : False
        AvgFrameRate          : 60.00 fps
        VideoStreamIndex      : 0
        VideoLanguage         : und
        VideoTitle            :
        Rotation              :
        FormatName            : mov,mp4,m4a,3gp,3g2,mj2
        StreamCount           : 1
        VideoStreamCount      : 1
        AudioStreamCount      : 0
        SubtitleStreamCount   : 0
        AttachmentStreamCount : 0
        DataStreamCount       : 0
        ChapterCount          : 0
        Title                 :
        Artist                :
        Album                 :
        Year                  :
        Genre                 :
        Comment               :
        Description           :
        Encoder               : Lavf59.16.100
        CreationTime          :

        Retrieves comprehensive video information including extended metadata like aspect ratio,
        color space, codec profile/level, and HDR information.

    .OUTPUTS
        PSCustomObject
        Returns a custom object with comprehensive video properties.

        Standard properties:
        - Name, FullPath, SizeBytes, SizeFormatted, Extension, CreatedDate, ModifiedDate
        - Duration, Bitrate, Format, Resolution
        - VideoCodec, VideoCodecShort, FrameRate, PixelFormat, VideoBitrate
        - AudioCodec, AudioCodecShort, SampleRate, Channels, AudioBitrate

        Additional properties with -Extended:
        - Video: AspectRatio, ColorSpace, ColorRange, ColorPrimaries, ColorTransfer,
          Profile, Level, BitDepth, IsAVC, HasHDR, AvgFrameRate, VideoStreamIndex,
          VideoLanguage, VideoTitle, Rotation
        - Audio: AudioProfile, ChannelLayout, AudioStreamIndex, AudioLanguage, AudioTitle
        - Format: FormatName, StreamCount, VideoStreamCount, AudioStreamCount,
          SubtitleStreamCount, AttachmentStreamCount, DataStreamCount, ChapterCount
        - Metadata: Title, Artist, Album, Year, Genre, Comment, Description, Encoder, CreationTime
        - Subtitles: Array of subtitle objects (Index, Codec, CodecLong, Language, Title,
          Forced, Default, HearingImpaired)
        - Attachments: Array of attachment objects (Index, Type, Filename, MimeType)

    .LINK
        https://ffmpeg.org/ffprobe.html
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FilePath', 'VideoFile', 'FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Path,

        [Parameter()]
        [switch]
        $Extended,

        [Parameter()]
        [switch]
        $NoEmptyProps,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $FFprobePath
    )

    begin
    {
        Write-Verbose 'Starting Get-VideoDetails'

        # Detect platform for cross-platform compatibility
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

        # Function to validate and resolve ffprobe path
        function Get-ValidFFprobePath
        {
            param([string]$ProvidedPath)

            $resolvedPath = $ProvidedPath

            # Normalize ffprobe path if provided (handles ~, relative paths)
            if ($resolvedPath)
            {
                $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($resolvedPath)
            }

            if (-not $resolvedPath)
            {
                # Try to find in PATH first
                $ffprobeCommand = Get-Command 'ffprobe' -ErrorAction SilentlyContinue
                if ($ffprobeCommand)
                {
                    $resolvedPath = $ffprobeCommand.Path
                    Write-Verbose "Using ffprobe from PATH: $resolvedPath"
                }
                else
                {
                    # Platform-specific default locations
                    if ($script:IsWindowsPlatform)
                    {
                        $resolvedPath = 'C:\ffmpeg\bin\ffprobe.exe'
                    }
                    elseif ($script:IsMacOSPlatform)
                    {
                        $resolvedPath = '/usr/local/bin/ffprobe'
                    }
                    else
                    {
                        # Linux or other
                        $resolvedPath = '/usr/bin/ffprobe'
                    }

                    Write-Verbose "Using platform-specific default: $resolvedPath"
                }
            }

            # Validate that ffprobe exists and is executable
            if (-not (Test-Path -Path $resolvedPath -PathType Leaf))
            {
                throw "ffprobe not found at: $resolvedPath. Please install ffprobe or specify the path using -FFprobePath."
            }

            return $resolvedPath
        }

        # Function to get video information using ffprobe
        function Get-VideoInfo
        {
            param(
                [System.IO.FileInfo]$FileInfo,
                [string]$FFprobeExecutable,
                [bool]$IncludeExtended
            )

            try
            {
                # Use ffprobe to get JSON output with all stream and format information
                $ffprobeArgs = @(
                    '-v', 'quiet'
                    '-print_format', 'json'
                    '-show_format'
                    '-show_streams'
                    $FileInfo.FullName
                )

                Write-Verbose "Running: $FFprobeExecutable $($ffprobeArgs -join ' ')"

                $processInfo = New-Object System.Diagnostics.ProcessStartInfo
                $processInfo.FileName = $FFprobeExecutable
                $processInfo.Arguments = $ffprobeArgs -join ' '
                $processInfo.RedirectStandardOutput = $true
                $processInfo.RedirectStandardError = $true
                $processInfo.UseShellExecute = $false
                $processInfo.CreateNoWindow = $true

                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $processInfo
                [void]$process.Start()

                $stdout = $process.StandardOutput.ReadToEnd()
                $stderr = $process.StandardError.ReadToEnd()
                $process.WaitForExit()

                if ($process.ExitCode -ne 0)
                {
                    Write-Error "ffprobe failed for $($FileInfo.Name): $stderr"
                    return
                }

                # Parse JSON output
                $probeData = $stdout | ConvertFrom-Json

                # Extract stream information by type
                $videoStream = $probeData.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
                $audioStream = $probeData.streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1
                $subtitleStreams = $probeData.streams | Where-Object { $_.codec_type -eq 'subtitle' }
                $attachmentStreams = $probeData.streams | Where-Object { $_.codec_type -eq 'attachment' }
                $dataStreams = $probeData.streams | Where-Object { $_.codec_type -eq 'data' }

                # Build detailed result object
                $result = [PSCustomObject]@{
                    Name = $FileInfo.Name
                    FullPath = $FileInfo.FullName
                    SizeBytes = $FileInfo.Length
                    SizeFormatted = Format-FileSize -SizeInBytes $FileInfo.Length
                    Extension = $FileInfo.Extension
                    CreatedDate = $FileInfo.CreationTime
                    ModifiedDate = $FileInfo.LastWriteTime
                }

                # Add format information
                if ($probeData.format)
                {
                    $durationValue = if ($probeData.format.duration)
                    {
                        [TimeSpan]::FromSeconds([double]$probeData.format.duration)
                    }
                    else { $null }
                    $result | Add-Member -NotePropertyName 'Duration' -NotePropertyValue $durationValue

                    $bitrateValue = if ($probeData.format.bit_rate)
                    {
                        '{0:N0} kbps' -f ([int]$probeData.format.bit_rate / 1000)
                    }
                    else { $null }
                    $result | Add-Member -NotePropertyName 'Bitrate' -NotePropertyValue $bitrateValue

                    $result | Add-Member -NotePropertyName 'Format' -NotePropertyValue $probeData.format.format_long_name
                }

                # Add video stream information
                if ($videoStream)
                {
                    $resolutionValue = if ($videoStream.width -and $videoStream.height)
                    {
                        '{0}x{1}' -f $videoStream.width, $videoStream.height
                    }
                    else { $null }
                    $result | Add-Member -NotePropertyName 'Resolution' -NotePropertyValue $resolutionValue

                    $result | Add-Member -NotePropertyName 'VideoCodec' -NotePropertyValue $videoStream.codec_long_name
                    $result | Add-Member -NotePropertyName 'VideoCodecShort' -NotePropertyValue $videoStream.codec_name

                    $frameRateValue = if ($videoStream.r_frame_rate -and $videoStream.r_frame_rate -ne '0/0')
                    {
                        $parts = $videoStream.r_frame_rate -split '/'
                        if ($parts.Count -eq 2 -and [double]$parts[1] -ne 0)
                        {
                            '{0:N2} fps' -f ([double]$parts[0] / [double]$parts[1])
                        }
                        else { $null }
                    }
                    else { $null }
                    $result | Add-Member -NotePropertyName 'FrameRate' -NotePropertyValue $frameRateValue

                    $result | Add-Member -NotePropertyName 'PixelFormat' -NotePropertyValue $videoStream.pix_fmt

                    $videoBitrateValue = if ($videoStream.bit_rate)
                    {
                        '{0:N0} kbps' -f ([int]$videoStream.bit_rate / 1000)
                    }
                    else { $null }
                    $result | Add-Member -NotePropertyName 'VideoBitrate' -NotePropertyValue $videoBitrateValue

                    # Add extended video properties
                    if ($IncludeExtended)
                    {
                        # Aspect ratio
                        $aspectRatioValue = if ($videoStream.display_aspect_ratio -and $videoStream.display_aspect_ratio -ne '0:1')
                        {
                            $videoStream.display_aspect_ratio
                        }
                        elseif ($videoStream.width -and $videoStream.height)
                        {
                            $gcd = [Math]::Abs($videoStream.width)
                            $temp = [Math]::Abs($videoStream.height)
                            while ($temp -ne 0)
                            {
                                $remainder = $gcd % $temp
                                $gcd = $temp
                                $temp = $remainder
                            }
                            '{0}:{1}' -f ($videoStream.width / $gcd), ($videoStream.height / $gcd)
                        }
                        else { $null }
                        $result | Add-Member -NotePropertyName 'AspectRatio' -NotePropertyValue $aspectRatioValue

                        $result | Add-Member -NotePropertyName 'ColorSpace' -NotePropertyValue $videoStream.color_space
                        $result | Add-Member -NotePropertyName 'ColorRange' -NotePropertyValue $videoStream.color_range
                        $result | Add-Member -NotePropertyName 'ColorPrimaries' -NotePropertyValue $videoStream.color_primaries
                        $result | Add-Member -NotePropertyName 'ColorTransfer' -NotePropertyValue $videoStream.color_transfer
                        $result | Add-Member -NotePropertyName 'Profile' -NotePropertyValue $videoStream.profile
                        $result | Add-Member -NotePropertyName 'Level' -NotePropertyValue $videoStream.level
                        $result | Add-Member -NotePropertyName 'BitDepth' -NotePropertyValue $videoStream.bits_per_raw_sample
                        $result | Add-Member -NotePropertyName 'IsAVC' -NotePropertyValue $videoStream.is_avc

                        # HDR metadata
                        $hasHDR = $videoStream.color_transfer -match 'smpte2084|arib-std-b67' -or
                        $videoStream.color_space -eq 'bt2020nc'
                        $result | Add-Member -NotePropertyName 'HasHDR' -NotePropertyValue $hasHDR

                        # Average frame rate
                        if ($videoStream.avg_frame_rate -and $videoStream.avg_frame_rate -ne '0/0')
                        {
                            $parts = $videoStream.avg_frame_rate -split '/'
                            if ($parts.Count -eq 2 -and [double]$parts[1] -ne 0)
                            {
                                $avgFps = '{0:N2} fps' -f ([double]$parts[0] / [double]$parts[1])
                                $result | Add-Member -NotePropertyName 'AvgFrameRate' -NotePropertyValue $avgFps
                            }
                        }

                        $result | Add-Member -NotePropertyName 'VideoStreamIndex' -NotePropertyValue $videoStream.index
                        $result | Add-Member -NotePropertyName 'VideoLanguage' -NotePropertyValue $videoStream.tags.language
                        $result | Add-Member -NotePropertyName 'VideoTitle' -NotePropertyValue $videoStream.tags.title

                        # Rotation/Orientation
                        $rotation = $videoStream.tags.rotate
                        if (-not $rotation -and $videoStream.side_data_list)
                        {
                            $displayMatrix = $videoStream.side_data_list | Where-Object { $_.side_data_type -eq 'Display Matrix' }
                            if ($displayMatrix -and $displayMatrix.rotation)
                            {
                                $rotation = $displayMatrix.rotation
                            }
                        }
                        $result | Add-Member -NotePropertyName 'Rotation' -NotePropertyValue $rotation
                    }
                }

                # Add audio stream information
                if ($audioStream)
                {
                    $result | Add-Member -NotePropertyName 'AudioCodec' -NotePropertyValue $audioStream.codec_long_name
                    $result | Add-Member -NotePropertyName 'AudioCodecShort' -NotePropertyValue $audioStream.codec_name

                    $sampleRateValue = if ($audioStream.sample_rate)
                    {
                        '{0:N0} Hz' -f [int]$audioStream.sample_rate
                    }
                    else { $null }
                    $result | Add-Member -NotePropertyName 'SampleRate' -NotePropertyValue $sampleRateValue

                    $result | Add-Member -NotePropertyName 'Channels' -NotePropertyValue $audioStream.channels

                    $audioBitrateValue = if ($audioStream.bit_rate)
                    {
                        '{0:N0} kbps' -f ([int]$audioStream.bit_rate / 1000)
                    }
                    else { $null }
                    $result | Add-Member -NotePropertyName 'AudioBitrate' -NotePropertyValue $audioBitrateValue

                    # Add extended audio properties
                    if ($IncludeExtended)
                    {
                        $result | Add-Member -NotePropertyName 'AudioProfile' -NotePropertyValue $audioStream.profile
                        $result | Add-Member -NotePropertyName 'ChannelLayout' -NotePropertyValue $audioStream.channel_layout
                        $result | Add-Member -NotePropertyName 'AudioStreamIndex' -NotePropertyValue $audioStream.index
                        $result | Add-Member -NotePropertyName 'AudioLanguage' -NotePropertyValue $audioStream.tags.language
                        $result | Add-Member -NotePropertyName 'AudioTitle' -NotePropertyValue $audioStream.tags.title
                    }
                }

                # Add extended format/container information
                if ($IncludeExtended -and $probeData.format)
                {
                    $result | Add-Member -NotePropertyName 'FormatName' -NotePropertyValue $probeData.format.format_name
                    $result | Add-Member -NotePropertyName 'StreamCount' -NotePropertyValue $probeData.format.nb_streams

                    # Count streams by type
                    $videoCount = ($probeData.streams | Where-Object { $_.codec_type -eq 'video' }).Count
                    $audioCount = ($probeData.streams | Where-Object { $_.codec_type -eq 'audio' }).Count
                    $subtitleCount = ($probeData.streams | Where-Object { $_.codec_type -eq 'subtitle' }).Count
                    $attachmentCount = ($probeData.streams | Where-Object { $_.codec_type -eq 'attachment' }).Count
                    $dataCount = ($probeData.streams | Where-Object { $_.codec_type -eq 'data' }).Count

                    $result | Add-Member -NotePropertyName 'VideoStreamCount' -NotePropertyValue $videoCount
                    $result | Add-Member -NotePropertyName 'AudioStreamCount' -NotePropertyValue $audioCount
                    $result | Add-Member -NotePropertyName 'SubtitleStreamCount' -NotePropertyValue $subtitleCount
                    $result | Add-Member -NotePropertyName 'AttachmentStreamCount' -NotePropertyValue $attachmentCount
                    $result | Add-Member -NotePropertyName 'DataStreamCount' -NotePropertyValue $dataCount

                    # Chapters
                    $chapterCount = if ($probeData.chapters) { $probeData.chapters.Count } else { 0 }
                    $result | Add-Member -NotePropertyName 'ChapterCount' -NotePropertyValue $chapterCount

                    # Format tags
                    $result | Add-Member -NotePropertyName 'Title' -NotePropertyValue $probeData.format.tags.title
                    $result | Add-Member -NotePropertyName 'Artist' -NotePropertyValue $probeData.format.tags.artist
                    $result | Add-Member -NotePropertyName 'Album' -NotePropertyValue $probeData.format.tags.album
                    $result | Add-Member -NotePropertyName 'Year' -NotePropertyValue $probeData.format.tags.date
                    $result | Add-Member -NotePropertyName 'Genre' -NotePropertyValue $probeData.format.tags.genre
                    $result | Add-Member -NotePropertyName 'Comment' -NotePropertyValue $probeData.format.tags.comment
                    $result | Add-Member -NotePropertyName 'Description' -NotePropertyValue $probeData.format.tags.description
                    $result | Add-Member -NotePropertyName 'Encoder' -NotePropertyValue $probeData.format.tags.encoder
                    $result | Add-Member -NotePropertyName 'CreationTime' -NotePropertyValue $probeData.format.tags.creation_time

                    # Subtitle/Closed Caption details
                    if ($subtitleStreams -and $subtitleStreams.Count -gt 0)
                    {
                        $subtitleDetails = @()
                        foreach ($sub in $subtitleStreams)
                        {
                            $subtitleInfo = [PSCustomObject]@{
                                Index = $sub.index
                                Codec = $sub.codec_name
                                CodecLong = $sub.codec_long_name
                                Language = $sub.tags.language
                                Title = $sub.tags.title
                                Forced = if ($sub.disposition.forced -eq 1) { $true } else { $false }
                                Default = if ($sub.disposition.default -eq 1) { $true } else { $false }
                                HearingImpaired = if ($sub.disposition.hearing_impaired -eq 1) { $true } else { $false }
                            }
                            $subtitleDetails += $subtitleInfo
                        }
                        $result | Add-Member -NotePropertyName 'Subtitles' -NotePropertyValue $subtitleDetails
                    }

                    # Attachment details (fonts, cover art, etc.)
                    if ($attachmentStreams -and $attachmentStreams.Count -gt 0)
                    {
                        $attachmentDetails = @()
                        foreach ($attachment in $attachmentStreams)
                        {
                            $attachmentInfo = [PSCustomObject]@{
                                Index = $attachment.index
                                Type = $attachment.codec_name
                                Filename = $attachment.tags.filename
                                MimeType = $attachment.tags.mimetype
                            }
                            $attachmentDetails += $attachmentInfo
                        }
                        $result | Add-Member -NotePropertyName 'Attachments' -NotePropertyValue $attachmentDetails
                    }
                }

                # Remove null/empty properties if requested
                if ($NoEmptyProps)
                {
                    $propertiesToRemove = @()
                    foreach ($prop in $result.PSObject.Properties)
                    {
                        if ($null -eq $prop.Value -or
                            ($prop.Value -is [string] -and [string]::IsNullOrWhiteSpace($prop.Value)))
                        {
                            $propertiesToRemove += $prop.Name
                        }
                    }

                    foreach ($propName in $propertiesToRemove)
                    {
                        $result.PSObject.Properties.Remove($propName)
                    }
                }

                return $result
            }
            catch
            {
                Write-Error "Error processing $($FileInfo.Name) with ffprobe: $($_.Exception.Message)"
                return
            }
        }

        # Resolve ffprobe path
        try
        {
            $resolvedFFprobePath = Get-ValidFFprobePath -ProvidedPath $FFprobePath
            Write-Verbose "Using ffprobe at: $resolvedFFprobePath"
        }
        catch
        {
            throw "ffprobe not available: $($_.Exception.Message). Please install ffprobe or specify the path using -FFprobePath."
        }
    }

    process
    {
        foreach ($videoPath in $Path)
        {
            try
            {
                # Resolve path (handles ~, relative paths, wildcards)
                $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($videoPath)

                # Handle wildcards
                $files = Get-Item -Path $resolvedPath -ErrorAction Stop

                foreach ($file in $files)
                {
                    if ($file.PSIsContainer)
                    {
                        Write-Warning "Skipping directory: $($file.FullName)"
                        continue
                    }

                    Write-Verbose "Processing: $($file.FullName)"

                    Get-VideoInfo -FileInfo $file -FFprobeExecutable $resolvedFFprobePath -IncludeExtended $Extended
                }
            }
            catch
            {
                Write-Error "Error processing '$videoPath': $($_.Exception.Message)"
            }
        }
    }

    end
    {
        Write-Verbose 'Get-VideoDetails completed'
    }
}
