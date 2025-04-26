function Invoke-FFMpeg
{
    <#
    .SYNOPSIS
        Converts video files by copying video streams and re-encoding audio/subtitle streams.

    .DESCRIPTION
        This function processes video files in a specified directory, copying the video stream (no re-encoding)
        while converting audio to AAC format and subtitles to MOV_TEXT format. The output is saved as MP4 files.
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

    .PARAMETER KeepSourceFiles
        If specified, input files will not be deleted after successful conversion.

    .PARAMETER PauseOnError
        If specified, the function will wait for user input when an error occurs instead of automatically continuing to the next file.

    .PARAMETER Recursive
        If specified, searches for video files in the specified Path and all subdirectories.

    .PARAMETER Exclude
        Specifies directories to exclude when using Recursive search.
        Defaults to @('.git', 'node_modules').

    .EXAMPLE
        PS> Invoke-FFMpeg -Path "C:\Videos" -Extension "mkv"
        Processes all .mkv files in C:\Videos, converting them to MP4 with copied video streams and re-encoded audio and subtitle streams.

    .EXAMPLE
        PS> Invoke-FFMpeg -Path "C:\Videos" -FFmpegPath "D:\tools\ffmpeg.exe" -Force
        Processes videos using a specific FFmpeg executable and overwrites existing output files.

    .EXAMPLE
        PS> Invoke-FFMpeg -Path "D:\Movies" -Extension "avi" -KeepSourceFiles -PauseOnError
        Processes all .avi files in D:\Movies without deleting the input files and pauses for user input when errors occur.

    .EXAMPLE
        PS> Invoke-FFMpeg -Path "D:\Movies" -Recursive
        Recursively processes all .mkv files in D:\Movies and all subdirectories.

    .LINK
        https://ffmpeg.org/documentation.html
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'Variables are used in conditional statements later in the script')]
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Extension = 'mkv',

        [Parameter(Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$FFmpegPath,

        [switch]$Force,
        [switch]$KeepSourceFiles,
        [switch]$PauseOnError,
        [switch]$Recursive,

        [Parameter()]
        [string[]]$Exclude = @('.git', 'node_modules')
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
    if ($Recursive)
    {
        $filesToProcess = Get-ChildItem -Path $Path -Recurse -Filter "*.$Extension" -File -Exclude $Exclude | Where-Object {
            $excludeMatch = $false
            foreach ($excludePath in $Exclude)
            {
                if ($_.FullName -like "*$excludePath*")
                {
                    $excludeMatch = $true
                    break
                }
            }
            -not $excludeMatch
        }
        Write-VerboseMessage "Searching recursively for *.$Extension files (excluding $($Exclude -join ', '))"
    }
    else
    {
        $filesToProcess = Get-ChildItem -Path $Path -Filter "*.$Extension" -File
        Write-VerboseMessage "Searching for *.$Extension files in current directory only"
    }
    $totalFiles = $filesToProcess.Count

    if ($totalFiles -eq 0)
    {
        Write-Warning "No '$Extension' files found in '$Path'"
        Pop-Location
        return $true
    }

    Write-Host "Found $totalFiles file(s) to process" -ForegroundColor Green

    # Process files
    $currentFileNumber = 0
    $successCount = 0
    $skipCount = 0
    $errorCount = 0

    foreach ($file in $filesToProcess)
    {
        $currentFileNumber++
        $inputFile = $file.Name
        $outputFile = [System.IO.Path]::ChangeExtension($file.Name, 'mp4')

        # Progress information
        Write-Host "[$currentFileNumber/$totalFiles] Processing: '$inputFile'" -ForegroundColor Yellow

        # Check if output file already exists
        if ((Test-Path -Path $outputFile) -and (-not $Force))
        {
            Write-Warning "Output file '$outputFile' already exists. Use -Force to overwrite. Skipping..."
            $skipCount++
            continue
        }

        Write-VerboseMessage "Converting to: '$outputFile'"

        # Construct ffmpeg arguments using splatting
        $ffmpegArgs = @(
            '-i', $inputFile,
            '-map', '0',
            '-vcodec', 'copy',
            '-acodec', 'aac', '-ac', '2', '-b:a', '320k',
            '-scodec', 'mov_text', '-metadata:s:s:0', 'language=eng', '-metadata:s:s:1', 'language=ipk',
            '-movflags', '+faststart',
            '-map_metadata', '-1'
        )

        # Add force overwrite if needed
        if ($Force)
        {
            $ffmpegArgs += '-y'
        }

        # Add output file
        $ffmpegArgs += $outputFile

        # Execute ffmpeg
        try
        {
            Write-VerboseMessage "Running FFmpeg with arguments: $($ffmpegArgs -join ' ')"

            # Always show FFmpeg output
            & $FFmpegPath @ffmpegArgs

            # Check exit code explicitly as ffmpeg might not throw terminating errors
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

                # Delete input file unless KeepSourceFiles is specified
                if (-not $KeepSourceFiles)
                {
                    try
                    {
                        Remove-Item -Path $inputFile -Confirm:$false -ErrorAction Stop
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

    # Summary
    Write-Host '----------------------------------------' -ForegroundColor Cyan
    Write-Host 'Summary:' -ForegroundColor Cyan
    Write-Host "  Total processed: $totalFiles" -ForegroundColor Cyan
    Write-Host "  Successful: $successCount" -ForegroundColor $(if ($successCount -gt 0) { 'Green' }else { 'Cyan' })
    Write-Host "  Skipped: $skipCount" -ForegroundColor $(if ($skipCount -gt 0) { 'Yellow' }else { 'Cyan' })
    Write-Host "  Failed: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { 'Red' }else { 'Cyan' })
    Write-Host '----------------------------------------' -ForegroundColor Cyan

    # Return success if no errors occurred
    return ($errorCount -eq 0)
}
