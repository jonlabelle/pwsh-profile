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

    .LINK
        https://ffmpeg.org/documentation.html
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path = '.',

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Extension = 'mkv',

        [Parameter(Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FFmpegPath,

        [switch]
        $Force,

        [switch]
        $KeepSourceFile,

        [switch]
        $PauseOnError,

        [switch]
        $NoRecursion,

        [Parameter()]
        [string[]]
        $Exclude = @('.git', 'node_modules'),

        [Parameter()]
        [ValidateSet('H.264', 'H.265')]
        [string]
        $VideoEncoder = 'H.264'
    )

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

    # Validate and resolve FFmpeg path
    if (-not $FFmpegPath)
    {
        # Try to find in PATH first
        $ffmpegCommand = Get-Command 'ffmpeg' -ErrorAction SilentlyContinue
        if ($ffmpegCommand)
        {
            $FFmpegPath = $ffmpegCommand.Path
            Write-VerboseMessage "Using FFmpeg from PATH: $FFmpegPath"
        }
        else
        {
            # Platform-specific default locations
            if ($IsWindows -or ($null -eq $IsWindows -and [Environment]::OSVersion.Platform -eq 'Win32NT'))
            {
                $FFmpegPath = 'C:\ffmpeg\bin\ffmpeg.exe'
            }
            elseif ($IsMacOS -or ($null -eq $IsMacOS -and [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)))
            {
                $FFmpegPath = '/usr/local/bin/ffmpeg'
            }
            else # Linux or other
            {
                $FFmpegPath = '/usr/bin/ffmpeg'
            }

            Write-VerboseMessage "Using default FFmpeg path for platform: $FFmpegPath"
        }
    }

    if (-not (Test-Path -Path $FFmpegPath -PathType Leaf))
    {
        Write-Error "FFmpeg executable not found at: '$FFmpegPath'"
        return $false
    }

    # Validate Input Directory
    if (-not (Test-Path -Path $Path -PathType Container))
    {
        Write-Error "Input directory not found: '$Path'"
        return $false
    }

    # Normalize file extension (ensure it has no leading dot)
    $Extension = $Extension.TrimStart('.')

    # Store current location and change to input directory
    try
    {
        Push-Location -Path $Path -ErrorAction Stop
        Write-VerboseMessage "Changed working directory to: $Path"
    }
    catch
    {
        Write-Error "Failed to change directory to '$Path'. Error: $($_.Exception.Message)"
        return $false
    }

    # Find files to process
    if ($NoRecursion)
    {
        Write-VerboseMessage "Searching for *.$Extension files in current directory only"

        # When not using recursion, exclusions are not applied since we only search the current directory
        $filesToProcess = Get-ChildItem -Path $Path -Filter "*.$Extension" -File
    }
    else
    {
        Write-VerboseMessage "Searching recursively for *.$Extension files (excluding $($Exclude -join ', '))"

        $filesToProcess = Get-ChildItem -Path $Path -Recurse -Filter "*.$Extension" -File | Where-Object {
            $fullPath = $_.FullName
            -not ($Exclude | Where-Object { $fullPath -like "*$_*" })
        }
    }

    $totalFiles = $filesToProcess.Count

    if ($totalFiles -eq 0)
    {
        Write-Warning "No '$Extension' files found in '$Path'"
        Pop-Location
        return $true
    }

    Write-Host "Found $totalFiles file(s) to process" -ForegroundColor Green

    # Start timer for script execution
    $scriptStartTime = Get-Date

    # Process files
    $currentFileNumber = 0
    $successCount = 0
    $skipCount = 0
    $errorCount = 0

    foreach ($file in $filesToProcess)
    {
        $currentFileNumber++
        $inputFilePath = $file.FullName # Use full paths instead of just filenames
        $outputFilePath = [System.IO.Path]::ChangeExtension($inputFilePath, 'mp4')
        $inputFile = $file.Name
        $outputFile = [System.IO.Path]::GetFileName($outputFilePath)

        # Progress information
        Write-Host "[$currentFileNumber/$totalFiles] Processing: '$inputFile'" -ForegroundColor Yellow

        # Check if output file already exists
        if ((Test-Path -Path $outputFilePath) -and (-not $Force))
        {
            Write-Warning "Output file '$outputFile' already exists. Use -Force to overwrite. Skipping..."
            $skipCount++
            continue
        }

        Write-VerboseMessage "Converting to: '$outputFile'"
        Write-VerboseMessage "Input path: '$inputFilePath'"
        Write-VerboseMessage "Output path: '$outputFilePath'"

        # Verify input file exists
        if (-not (Test-Path -Path $inputFilePath -PathType Leaf))
        {
            Write-Error "Input file not found: '$inputFilePath'"
            $errorCount++
            continue
        }

        # Construct ffmpeg arguments using Samsung-friendly encoding settings
        if ($VideoEncoder -eq 'H.264')
        {
            # Samsung-friendly H.264 encoding: 4K30, High profile, Level 5.1, up to 100 Mbps
            $ffmpegArgs = @(
                '-i', "`"$inputFilePath`"",                            # Input file (quoted)
                '-vcodec', 'libx264',                                  # H.264 video codec
                '-preset', 'medium',                                   # Encoding speed preset (balance of speed vs compression)
                '-crf', '18',                                          # Constant rate factor (near-visually-lossless quality)
                '-profile', 'high',                                    # H.264 High profile for Samsung compatibility
                '-level', '5.1',                                       # H.264 Level 5.1 (seamless up to 3840×2160)
                '-pix_fmt', 'yuv420p',                                 # Pixel format for wide compatibility
                '-framerate', '30',                                    # Max 30 fps for 4K on Samsung TV
                '-maxrate', '100M',                                    # Max bitrate 100 Mbps
                '-bufsize', '200M',                                    # Buffer size (2x maxrate)
                '-x264-params', 'keyint=60:min-keyint=60',             # Keyframe interval settings
                '-acodec', 'aac',                                      # AAC audio codec
                '-b:a', '192k',                                        # Audio bitrate 192 kbps
                '-ac', '2',                                            # 2 audio channels (stereo)
                '-ar', '48000',                                        # Audio sample rate 48 kHz
                '-movflags', '+faststart'                              # Web-optimized for progressive download
            )
        }
        else # H.265
        {
            # Samsung-friendly H.265 encoding: 4K60, Level 5.2, up to 100 Mbps (better compression)
            $ffmpegArgs = @(
                '-i', "`"$inputFilePath`"",                            # Input file (quoted)
                '-vcodec', 'libx265',                                  # H.265 video codec
                '-preset', 'medium',                                   # Encoding speed preset (balance of speed vs compression)
                '-crf', '22',                                          # Constant rate factor (good quality for H.265)
                '-x265-params', 'level-idc=5.2:keyint=60',             # H.265 Level 5.2 with keyframe interval
                '-pix_fmt', 'yuv420p10le',                             # 10-bit pixel format for better quality
                '-r', '60',                                            # Max 60 fps for 4K with H.265
                '-acodec', 'aac',                                      # AAC audio codec
                '-b:a', '192k',                                        # Audio bitrate 192 kbps
                '-ac', '2',                                            # 2 audio channels (stereo)
                '-ar', '48000',                                        # Audio sample rate 48 kHz
                '-movflags', '+faststart'                              # Web-optimized for progressive download
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
                    $process = Start-Process -FilePath $FFmpegPath -ArgumentList $ffmpegArgs -Wait -PassThru
                }
                else
                {
                    # PowerShell Desktop on Windows
                    $process = Start-Process -FilePath $FFmpegPath -ArgumentList $ffmpegArgs -NoNewWindow -Wait -PassThru
                }

                $LASTEXITCODE = $process.ExitCode
            }
            else
            {
                # macOS/Linux: Use direct execution which preserves TTY behavior better
                & $FFmpegPath @ffmpegArgs
            }

            if ($LASTEXITCODE -ne 0)
            {
                Write-Warning "FFmpeg failed for '$inputFile' with exit code $LASTEXITCODE."
                $errorCount++

                if ($PauseOnError)
                {
                    Read-Host 'Press Enter to continue...'
                }
            }
            else
            {
                Write-Host "Successfully converted '$inputFile' to '$outputFile'" -ForegroundColor Green
                $successCount++

                # Delete input file unless KeepSourceFile is specified
                if (-not $KeepSourceFile)
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
        catch
        {
            Write-Error "Error running FFmpeg for '$inputFile'. Error: $($_.Exception.Message)"
            $errorCount++

            if ($PauseOnError)
            {
                Read-Host 'Press Enter to continue...'
            }
        }

        Write-Host ''
    }

    # Return to original location
    Pop-Location

    # Calculate elapsed time
    $scriptEndTime = Get-Date
    $elapsedTime = Format-ElapsedTime -StartTime $scriptStartTime -EndTime $scriptEndTime

    # Summary
    Write-Host '----------------------------------------' -ForegroundColor Cyan
    Write-Host 'Summary:' -ForegroundColor Cyan
    Write-Host "  Total processed: $totalFiles" -ForegroundColor Cyan
    Write-Host "  Successful: $successCount" -ForegroundColor $(if ($successCount -gt 0) { 'Green' }else { 'Cyan' })
    Write-Host "  Skipped: $skipCount" -ForegroundColor $(if ($skipCount -gt 0) { 'Yellow' }else { 'Cyan' })
    Write-Host "  Failed: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { 'Red' }else { 'Cyan' })
    Write-Host "  Total time: $elapsedTime" -ForegroundColor Cyan
    Write-Host '----------------------------------------' -ForegroundColor Cyan

    # Return success if no errors occurred
    return ($errorCount -eq 0)
}
