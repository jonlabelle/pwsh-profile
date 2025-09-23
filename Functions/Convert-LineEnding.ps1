function Convert-LineEnding
{
    <#
    .SYNOPSIS
        Converts line endings between LF and CRLF while preserving file encoding.

    .DESCRIPTION
        This function converts line endings in text files between Unix (LF) and Windows (CRLF) formats
        while preserving the original file encoding. It uses streaming operations for optimal performance
        with large files and automatically detects and skips binary files to prevent corruption.

        The function supports both individual files and directory processing with optional recursion.
        It provides comprehensive WhatIf support to preview changes before execution.

    .PARAMETER Path
        The path to a file or directory to process.
        Accepts an array of paths and supports pipeline input.
        For directories, all text files will be processed unless filtered by Include/Exclude parameters.

    .PARAMETER LineEnding
        Specifies the target line ending format.
        Valid values are 'LF' (Unix format) and 'CRLF' (Windows format).

    .PARAMETER Recurse
        When processing directories, search recursively through all subdirectories.
        Only applies when Path points to a directory.

    .PARAMETER Include
        Specifies file patterns to include when processing directories.
        Supports wildcards (e.g., '*.txt', '*.ps1', '*.md').
        Default includes common text file extensions.

    .PARAMETER Exclude
        Specifies file patterns to exclude when processing directories.
        Supports wildcards and common binary file extensions are excluded by default.

    .PARAMETER Force
        Overwrites read-only files. Without this parameter, read-only files are skipped.

    .PARAMETER PassThru
        Returns information about the processed files.

    .EXAMPLE
        PS > Convert-LineEnding -Path 'script.ps1' -LineEnding 'LF'

        Converts the specified PowerShell script to use Unix line endings.

    .EXAMPLE
        PS > Convert-LineEnding -Path 'C:\Scripts' -LineEnding 'CRLF' -Recurse -Include '*.ps1', '*.txt'

        Recursively converts all PowerShell and text files in the Scripts directory to Windows line endings.

    .EXAMPLE
        PS > Get-ChildItem '*.md' | Convert-LineEnding -LineEnding 'LF' -WhatIf

        Shows what would happen when converting all Markdown files to Unix line endings.

    .EXAMPLE
        PS > Convert-LineEnding -Path 'project' -LineEnding 'LF' -Exclude '*.min.js', 'node_modules' -Recurse

        Converts files to Unix line endings while excluding minified JavaScript files and node_modules directories.

    .OUTPUTS
        None by default.
        [System.Object[]] when PassThru is specified, containing file path, original and new line ending counts.

    .NOTES
        Version: 1.0.0
        Date: September 22, 2025
        Author: Jon LaBelle
        License: MIT

        BINARY FILE DETECTION:
        The function automatically detects binary files using multiple methods:
        - File extension patterns (executables, images, archives, etc.)
        - Content analysis for null bytes and high ratio of non-printable characters
        - Files are skipped if determined to be binary to prevent corruption

        ENCODING PRESERVATION:
        File encoding is detected and preserved during conversion:
        - UTF-8 (with and without BOM)
        - UTF-16 (Little and Big Endian)
        - ASCII
        - Other encodings detected by .NET

        PERFORMANCE:
        Uses streaming operations to handle large files efficiently without loading
        entire file contents into memory.

    .LINK
        https://jonlabelle.com/snippets/view/powershell/convert-line-endings-in-powershell

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Convert-LineEnding.ps1
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('LF', 'CRLF')]
        [String]$LineEnding,

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [String[]]$Include = @(
            '*.txt', '*.md', '*.ps1', '*.psm1', '*.psd1', '*.ps1xml',
            '*.xml', '*.json', '*.yml', '*.yaml', '*.ini', '*.cfg', '*.config',
            '*.cs', '*.vb', '*.cpp', '*.c', '*.h', '*.hpp',
            '*.js', '*.ts', '*.html', '*.htm', '*.css', '*.scss', '*.sass',
            '*.py', '*.rb', '*.php', '*.java', '*.go', '*.rs', '*.swift',
            '*.sql', '*.sh', '*.bat', '*.cmd', '*.log'
        ),

        [Parameter()]
        [String[]]$Exclude = @(
            '*.exe', '*.dll', '*.so', '*.dylib', '*.a', '*.lib', '*.obj', '*.o',
            '*.zip', '*.7z', '*.rar', '*.tar', '*.gz', '*.bz2', '*.xz',
            '*.jpg', '*.jpeg', '*.png', '*.gif', '*.bmp', '*.tiff', '*.ico',
            '*.mp3', '*.mp4', '*.avi', '*.mkv', '*.mov', '*.wmv', '*.flv',
            '*.pdf', '*.doc', '*.docx', '*.xls', '*.xlsx', '*.ppt', '*.pptx',
            '*.min.js', '*.min.css', 'node_modules', '.git', '.vs', '.vscode'
        ),

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        Write-Verbose "Starting line ending conversion to $LineEnding"

        # Define line ending strings
        $lineEndings = @{
            'LF' = "`n"
            'CRLF' = "`r`n"
        }

        $targetLineEnding = $lineEndings[$LineEnding]
        $processedFiles = [System.Collections.ArrayList]::new()

        function Test-BinaryFile
        {
            param(
                [String]$FilePath
            )

            try
            {
                # First check file extension
                $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
                $binaryExtensions = @(
                    '.exe', '.dll', '.so', '.dylib', '.a', '.lib', '.obj', '.o',
                    '.zip', '.7z', '.rar', '.tar', '.gz', '.bz2', '.xz',
                    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.ico', '.svg',
                    '.mp3', '.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm',
                    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx'
                )

                if ($binaryExtensions -contains $extension)
                {
                    Write-Verbose "File '$FilePath' detected as binary by extension: $extension"
                    return $true
                }

                # Content-based detection for files without clear extensions
                $buffer = New-Object byte[] 8192
                $stream = [System.IO.File]::OpenRead($FilePath)
                try
                {
                    $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                    if ($bytesRead -eq 0)
                    {
                        return $false  # Empty file is not binary
                    }

                    # Check for text encoding patterns first to avoid false positives
                    $hasUtf16LeBom = $bytesRead -ge 2 -and $buffer[0] -eq 0xFF -and $buffer[1] -eq 0xFE
                    $hasUtf16BeBom = $bytesRead -ge 2 -and $buffer[0] -eq 0xFE -and $buffer[1] -eq 0xFF

                    # If we detect UTF-16 encoding (common with PowerShell Out-File), analyze accordingly
                    if ($hasUtf16LeBom -or $hasUtf16BeBom)
                    {
                        Write-Verbose "File '$FilePath' has UTF-16 BOM, analyzing as UTF-16 text"
                        # For UTF-16, check every other byte starting from position 2 (after BOM)
                        $printableCount = 0
                        $totalChars = 0
                        $startPos = if ($hasUtf16LeBom -or $hasUtf16BeBom) { 2 } else { 0 }

                        for ($i = $startPos; $i -lt $bytesRead - 1; $i += 2)
                        {
                            $char = if ($hasUtf16LeBom)
                            {
                                $buffer[$i] + ($buffer[$i + 1] * 256)
                            }
                            else
                            {
                                ($buffer[$i] * 256) + $buffer[$i + 1]
                            }

                            $totalChars++
                            # Check if character is printable (including common whitespace)
                            if (($char -ge 32 -and $char -le 126) -or $char -eq 9 -or $char -eq 10 -or $char -eq 13 -or ($char -ge 128 -and $char -le 255))
                            {
                                $printableCount++
                            }
                        }

                        if ($totalChars -gt 0)
                        {
                            $printableRatio = $printableCount / $totalChars
                            if ($printableRatio -lt 0.75)
                            {
                                Write-Verbose "File '$FilePath' detected as binary (low UTF-16 printable character ratio: $([math]::Round($printableRatio * 100, 1))%)"
                                return $true
                            }
                        }
                        return $false
                    }

                    # Check for potential UTF-16 without BOM (look for alternating null bytes pattern)
                    if ($bytesRead -ge 4)
                    {
                        $nullByteCount = 0
                        $alternatingNullPattern = $true

                        # Check first 100 bytes for alternating null pattern (UTF-16 LE)
                        $checkLength = [Math]::Min(100, $bytesRead)
                        for ($i = 1; $i -lt $checkLength; $i += 2)
                        {
                            if ($buffer[$i] -eq 0)
                            {
                                $nullByteCount++
                            }
                            else
                            {
                                $alternatingNullPattern = $false
                            }
                        }

                        # If more than 80% of even positions are null, likely UTF-16 LE
                        if ($alternatingNullPattern -and $nullByteCount -gt ($checkLength / 2) * 0.8)
                        {
                            Write-Verbose "File '$FilePath' appears to be UTF-16 LE without BOM (alternating null pattern)"
                            # Analyze as UTF-16 LE
                            $printableCount = 0
                            $totalChars = 0

                            for ($i = 0; $i -lt $bytesRead - 1; $i += 2)
                            {
                                $char = $buffer[$i] + ($buffer[$i + 1] * 256)
                                $totalChars++
                                if (($char -ge 32 -and $char -le 126) -or $char -eq 9 -or $char -eq 10 -or $char -eq 13 -or ($char -ge 128 -and $char -le 255))
                                {
                                    $printableCount++
                                }
                            }

                            if ($totalChars -gt 0)
                            {
                                $printableRatio = $printableCount / $totalChars
                                if ($printableRatio -lt 0.75)
                                {
                                    Write-Verbose "File '$FilePath' detected as binary (low UTF-16 printable character ratio: $([math]::Round($printableRatio * 100, 1))%)"
                                    return $true
                                }
                            }
                            return $false
                        }
                    }

                    # For other encodings, check for null bytes (but be more selective)
                    $nullByteCount = 0
                    for ($i = 0; $i -lt $bytesRead; $i++)
                    {
                        if ($buffer[$i] -eq 0)
                        {
                            $nullByteCount++
                        }
                    }

                    # If more than 10% of bytes are null (and not UTF-16), likely binary
                    if ($nullByteCount -gt ($bytesRead * 0.1))
                    {
                        Write-Verbose "File '$FilePath' detected as binary (contains $nullByteCount null bytes out of $bytesRead total)"
                        return $true
                    }

                    # Check ratio of printable characters for non-UTF-16 files
                    $printableCount = 0
                    for ($i = 0; $i -lt $bytesRead; $i++)
                    {
                        $byte = $buffer[$i]
                        # Printable ASCII (32-126), common whitespace (9,10,13), and extended ASCII
                        if (($byte -ge 32 -and $byte -le 126) -or $byte -eq 9 -or $byte -eq 10 -or $byte -eq 13 -or ($byte -ge 128 -and $byte -le 255))
                        {
                            $printableCount++
                        }
                    }

                    $printableRatio = $printableCount / $bytesRead
                    if ($printableRatio -lt 0.75)
                    {
                        Write-Verbose "File '$FilePath' detected as binary (low printable character ratio: $([math]::Round($printableRatio * 100, 1))%)"
                        return $true
                    }

                    return $false
                }
                finally
                {
                    $stream.Close()
                }
            }
            catch
            {
                Write-Verbose "Error analyzing file '$FilePath': $($_.Exception.Message)"
                return $true  # Assume binary if we can't analyze
            }
        }

        function Get-FileEncoding
        {
            param(
                [String]$FilePath
            )

            try
            {
                # Read only the first few bytes to detect BOM and sample for encoding detection
                $stream = [System.IO.File]::OpenRead($FilePath)
                try
                {
                    if ($stream.Length -eq 0)
                    {
                        return [System.Text.Encoding]::UTF8  # Default for empty files
                    }

                    # Read up to 4 bytes for BOM detection
                    $bomBuffer = New-Object byte[] 4
                    $bomBytesRead = $stream.Read($bomBuffer, 0, 4)

                    # Check for BOM patterns
                    if ($bomBytesRead -ge 3 -and $bomBuffer[0] -eq 0xEF -and $bomBuffer[1] -eq 0xBB -and $bomBuffer[2] -eq 0xBF)
                    {
                        return [System.Text.Encoding]::UTF8
                    }
                    elseif ($bomBytesRead -ge 2 -and $bomBuffer[0] -eq 0xFF -and $bomBuffer[1] -eq 0xFE)
                    {
                        return [System.Text.Encoding]::Unicode  # UTF-16 LE
                    }
                    elseif ($bomBytesRead -ge 2 -and $bomBuffer[0] -eq 0xFE -and $bomBuffer[1] -eq 0xFF)
                    {
                        return [System.Text.Encoding]::BigEndianUnicode  # UTF-16 BE
                    }
                    elseif ($bomBytesRead -ge 4 -and $bomBuffer[0] -eq 0x00 -and $bomBuffer[1] -eq 0x00 -and $bomBuffer[2] -eq 0xFE -and $bomBuffer[3] -eq 0xFF)
                    {
                        return [System.Text.Encoding]::UTF32
                    }

                    # No BOM detected, read a sample to determine encoding
                    # Reset stream position to beginning
                    $stream.Position = 0

                    # Read up to 8KB sample for encoding detection (much smaller than entire file)
                    $sampleSize = [Math]::Min($stream.Length, 8192)
                    $sampleBuffer = New-Object byte[] $sampleSize
                    $sampleBytesRead = $stream.Read($sampleBuffer, 0, $sampleSize)

                    if ($sampleBytesRead -eq 0)
                    {
                        return [System.Text.Encoding]::UTF8  # Default for empty files
                    }

                    # Check if it's valid UTF-8 using the sample
                    try
                    {
                        $utf8 = [System.Text.Encoding]::UTF8
                        $decoded = $utf8.GetString($sampleBuffer, 0, $sampleBytesRead)
                        $reencoded = $utf8.GetBytes($decoded)

                        # If reencoding produces the same bytes, it's likely UTF-8
                        if ($sampleBytesRead -eq $reencoded.Length)
                        {
                            $match = $true
                            for ($i = 0; $i -lt $sampleBytesRead; $i++)
                            {
                                if ($sampleBuffer[$i] -ne $reencoded[$i])
                                {
                                    $match = $false
                                    break
                                }
                            }
                            if ($match)
                            {
                                return $utf8
                            }
                        }
                    }
                    catch
                    {
                        # Not valid UTF-8, continue to next encoding check
                        Write-Debug "File '$FilePath' sample is not valid UTF-8: $($_.Exception.Message)"
                    }

                    # Check if sample bytes are all ASCII
                    $isAscii = $true
                    for ($i = 0; $i -lt $sampleBytesRead; $i++)
                    {
                        if ($sampleBuffer[$i] -gt 127)
                        {
                            $isAscii = $false
                            break
                        }
                    }

                    if ($isAscii)
                    {
                        return [System.Text.Encoding]::ASCII
                    }

                    # Default to UTF-8 without BOM for other cases
                    return [System.Text.Encoding]::UTF8
                }
                finally
                {
                    $stream.Close()
                }
            }
            catch
            {
                Write-Verbose "Error detecting encoding for '$FilePath': $($_.Exception.Message)"
                return [System.Text.Encoding]::UTF8
            }
        }

        function Convert-SingleFileLineEnding
        {
            param(
                [String]$FilePath,
                [String]$TargetLineEnding,
                [System.Text.Encoding]$Encoding
            )

            $tempFilePath = "$FilePath.tmp"
            $originalLfCount = 0
            $originalCrlfCount = 0
            $newLfCount = 0
            $newCrlfCount = 0

            try
            {
                # Create streams for reading and writing
                $reader = New-Object System.IO.StreamReader($FilePath, $Encoding)
                $writer = New-Object System.IO.StreamWriter($tempFilePath, $false, $Encoding)

                try
                {
                    $buffer = New-Object char[] 8192
                    $lineBuffer = New-Object System.Text.StringBuilder

                    while ($true)
                    {
                        $charsRead = $reader.Read($buffer, 0, $buffer.Length)
                        if ($charsRead -eq 0) { break }

                        for ($i = 0; $i -lt $charsRead; $i++)
                        {
                            $char = $buffer[$i]

                            if ($char -eq "`r")
                            {
                                # Check if next character is LF (CRLF sequence)
                                if ($i + 1 -lt $charsRead -and $buffer[$i + 1] -eq "`n")
                                {
                                    $originalCrlfCount++
                                    $i++  # Skip the LF character
                                }
                                else
                                {
                                    # Standalone CR (treat as line ending)
                                    $originalLfCount++
                                }

                                # Write line with target ending
                                $writer.Write($lineBuffer.ToString())
                                $writer.Write($TargetLineEnding)

                                if ($TargetLineEnding -eq "`n")
                                {
                                    $newLfCount++
                                }
                                else
                                {
                                    $newCrlfCount++
                                }

                                $lineBuffer.Clear() | Out-Null
                            }
                            elseif ($char -eq "`n")
                            {
                                # Standalone LF
                                $originalLfCount++

                                $writer.Write($lineBuffer.ToString())
                                $writer.Write($TargetLineEnding)

                                if ($TargetLineEnding -eq "`n")
                                {
                                    $newLfCount++
                                }
                                else
                                {
                                    $newCrlfCount++
                                }

                                $lineBuffer.Clear() | Out-Null
                            }
                            else
                            {
                                $lineBuffer.Append($char) | Out-Null
                            }
                        }
                    }

                    # Write any remaining content
                    if ($lineBuffer.Length -gt 0)
                    {
                        $writer.Write($lineBuffer.ToString())
                    }
                }
                finally
                {
                    $reader.Close()
                    $writer.Close()
                }

                # Replace original file with converted file
                if ($Force -or -not (Get-Item $FilePath).IsReadOnly)
                {
                    Move-Item -Path $tempFilePath -Destination $FilePath -Force
                }
                else
                {
                    Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue
                    throw 'File is read-only. Use -Force to overwrite read-only files.'
                }

                return [PSCustomObject]@{
                    FilePath = $FilePath
                    OriginalLF = $originalLfCount
                    OriginalCRLF = $originalCrlfCount
                    NewLF = $newLfCount
                    NewCRLF = $newCrlfCount
                    Encoding = $Encoding.EncodingName
                    Success = $true
                    Error = $null
                }
            }
            catch
            {
                # Clean up temp file on error
                if (Test-Path $tempFilePath)
                {
                    Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue
                }

                return [PSCustomObject]@{
                    FilePath = $FilePath
                    OriginalLF = 0
                    OriginalCRLF = 0
                    NewLF = 0
                    NewCRLF = 0
                    Encoding = $null
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        }
    }

    process
    {
        foreach ($currentPath in $Path)
        {
            # Normalize path
            $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($currentPath)

            if (-not (Test-Path $resolvedPath))
            {
                Write-Error "Path not found: $resolvedPath"
                continue
            }

            $item = Get-Item $resolvedPath

            if ($item.PSIsContainer)
            {
                # Process directory
                Write-Verbose "Processing directory: $resolvedPath"

                $getChildItemParams = @{
                    Path = $resolvedPath
                    File = $true
                    ErrorAction = 'SilentlyContinue'
                }

                if ($Recurse)
                {
                    $getChildItemParams.Recurse = $true
                }

                $files = Get-ChildItem @getChildItemParams

                # Apply include filters
                if ($Include.Count -gt 0)
                {
                    $filteredFiles = @()
                    foreach ($includePattern in $Include)
                    {
                        $filteredFiles += $files | Where-Object { $_.Name -like $includePattern }
                    }
                    $files = $filteredFiles | Sort-Object FullName -Unique
                }

                # Apply exclude filters
                if ($Exclude.Count -gt 0)
                {
                    $files = $files | Where-Object {
                        $file = $_
                        $shouldExclude = $false
                        foreach ($excludePattern in $Exclude)
                        {
                            # Check file name, relative path, and directory path for exclusion
                            $relativePath = $file.FullName.Substring($resolvedPath.Length).TrimStart('\', '/')
                            if ($file.Name -like $excludePattern -or
                                $relativePath -like "*$excludePattern*" -or
                                $file.DirectoryName -like "*$excludePattern*" -or
                                $file.Directory.Name -like $excludePattern)
                            {
                                $shouldExclude = $true
                                break
                            }
                        }
                        -not $shouldExclude
                    }
                }

                foreach ($file in $files)
                {
                    if (Test-BinaryFile -FilePath $file.FullName)
                    {
                        Write-Warning "Skipping binary file: $($file.FullName)"
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($file.FullName, "Convert line endings to $LineEnding"))
                    {
                        Write-Verbose "Processing file: $($file.FullName)"
                        $encoding = Get-FileEncoding -FilePath $file.FullName
                        $result = Convert-SingleFileLineEnding -FilePath $file.FullName -TargetLineEnding $targetLineEnding -Encoding $encoding

                        if ($PassThru)
                        {
                            $null = $processedFiles.Add($result)
                        }                        if ($result.Success)
                        {
                            Write-Verbose "Successfully converted '$($file.FullName)' (LF: $($result.OriginalLF)→$($result.NewLF), CRLF: $($result.OriginalCRLF)→$($result.NewCRLF))"
                        }
                        else
                        {
                            Write-Error "Failed to convert '$($file.FullName)': $($result.Error)"
                        }
                    }
                }
            }
            else
            {
                # Process single file
                if (Test-BinaryFile -FilePath $resolvedPath)
                {
                    Write-Warning "Skipping binary file: $resolvedPath"
                    continue
                }

                if ($PSCmdlet.ShouldProcess($resolvedPath, "Convert line endings to $LineEnding"))
                {
                    Write-Verbose "Processing file: $resolvedPath"
                    $encoding = Get-FileEncoding -FilePath $resolvedPath
                    $result = Convert-SingleFileLineEnding -FilePath $resolvedPath -TargetLineEnding $targetLineEnding -Encoding $encoding

                    if ($PassThru)
                    {
                        $null = $processedFiles.Add($result)
                    }

                    if ($result.Success)
                    {
                        Write-Verbose "Successfully converted '$resolvedPath' (LF: $($result.OriginalLF)→$($result.NewLF), CRLF: $($result.OriginalCRLF)→$($result.NewCRLF))"
                    }
                    else
                    {
                        Write-Error "Failed to convert '$resolvedPath': $($result.Error)"
                    }
                }
            }
        }
    }

    end
    {
        if ($PassThru)
        {
            # Return the processed files array
            return @($processedFiles)
        }

        Write-Verbose 'Line ending conversion completed'
    }
}
