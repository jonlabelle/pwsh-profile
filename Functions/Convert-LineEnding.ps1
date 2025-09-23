function Convert-LineEnding
{
    <#
    .SYNOPSIS
        Converts line endings between LF and CRLF while preserving file encoding.

    .DESCRIPTION
        This function converts line endings in text files between Unix (LF) and Windows (CRLF) formats
        while preserving the original file encoding. It uses streaming operations for optimal performance
        with large files and automatically detects and skips binary files to prevent corruption.

        The function includes intelligent optimization that pre-scans files to detect their current line
        ending format. Files that already have the correct line endings are skipped entirely, preserving
        their modification timestamps and avoiding unnecessary I/O operations.

        The function supports both individual files and directory processing with optional recursion.
        It provides intelligent WhatIf support that analyzes files to show only those that would
        actually be modified, rather than showing all files in scope.

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

    .PARAMETER Encoding
        Specifies the target file encoding. When set to 'Auto' (default), the original file encoding
        is preserved. When set to a specific encoding, files will be converted to that encoding only
        if line endings need to be converted.

        Valid values:
        - Auto: Preserve original file encoding (default)
        - UTF8: UTF-8 without BOM
        - UTF8BOM: UTF-8 with BOM
        - UTF16LE: UTF-16 Little Endian with BOM
        - UTF16BE: UTF-16 Big Endian with BOM
        - UTF32: UTF-32 with BOM
        - ASCII: 7-bit ASCII encoding

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

        Shows which Markdown files would be converted to Unix line endings vs. which would be skipped.
        Files needing conversion show "Convert line endings to LF" while files with correct endings
        show "Skip file - already has correct line endings (LF)".

    .EXAMPLE
        PS > Convert-LineEnding -Path 'project' -LineEnding 'LF' -Exclude '*.min.js', 'node_modules' -Recurse

        Converts files to Unix line endings while excluding minified JavaScript files and node_modules directories.

    .EXAMPLE
        PS > Convert-LineEnding -Path 'data.csv' -LineEnding 'CRLF' -Encoding 'UTF8BOM'

        Converts a CSV file to Windows line endings and UTF-8 with BOM encoding.

    .EXAMPLE
        PS > Get-ChildItem '*.txt' | Convert-LineEnding -LineEnding 'LF' -Encoding 'UTF8' -PassThru

        Converts all text files to Unix line endings and UTF-8 without BOM, returning processing information.

    .OUTPUTS
        None by default.
        [System.Object[]] when PassThru is specified, containing file path, original and new line ending counts,
        source encoding, target encoding, and whether encoding was changed.

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
        File encoding is detected and preserved during conversion by default.
        When the -Encoding parameter is specified, files are converted to the target encoding.
        Supported encodings:
        - UTF-8 (with and without BOM)
        - UTF-16 (Little and Big Endian)
        - UTF-32
        - ASCII

        PERFORMANCE:
        Uses streaming operations to handle large files efficiently without loading
        entire file contents into memory. Includes intelligent pre-scanning that
        samples the first 64KB of each file to detect current line ending format.
        Files that already have the correct line endings are skipped entirely,
        preserving modification timestamps and avoiding unnecessary processing.

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
            # General Text Files
            '*.txt', '*.md', '*.log',

            # PowerShell Files
            '*.ps1', '*.psm1', '*.psd1', '*.ps1xml',

            # Configuration Files
            '*.ini', '*.cfg', '*.config', '*.conf', '*.rc', '*.properties',
            '*.toml', '*.env', '*.editorconfig', '*.htaccess',

            # Data Formats
            '*.xml', '*.json', '*.yml', '*.yaml', '*.csv', '*.tsv',
            '*.po', '*.pot', '*.bib', '*.rst', '*.adoc',

            # Programming Languages
            '*.cs', '*.vb', '*.cpp', '*.c', '*.h', '*.hpp',
            '*.java', '*.go', '*.rs', '*.swift', '*.php', '*.py', '*.rb',
            '*.pl', '*.tcl', '*.lua', '*.r', '*.tex', '*.sql',

            # Web Development
            '*.js', '*.ts', '*.html', '*.htm', '*.css', '*.scss', '*.sass',
            '*.svg', '*.xaml',

            # Scripts and Shell Files
            '*.sh', '*.bat', '*.cmd', '*.profile', '*.zshrc', '*.bashrc', '*.vimrc',

            # Version Control
            '*.gitignore', '*.gitattributes',

            # Build and Make Files
            '*.makefile', '*.cmake'
        ),

        [Parameter()]
        [String[]]$Exclude = @(
            # Executables and Libraries
            '*.exe', '*.dll', '*.so', '*.dylib', '.a', '.lib', '*.obj', '*.o',

            # Archives
            '*.zip', '*.7z', '*.rar', '*.tar', '*.gz', '*.bz2', '.xz',

            # Images
            '*.jpg', '*.jpeg', '*.png', '*.gif', '*.bmp', '*.tiff', '*.ico',

            # Audio/Video
            '*.mp3', '*.mp4', '*.avi', '*.mkv', '*.mov', '*.wmv', '*.flv',

            # Documents
            '*.pdf', '*.doc', '*.docx', '*.xls', '*.xlsx', '*.ppt', '*.pptx',

            # Dev Minified Files and Directories
            '*.min.js', '*.min.css', 'node_modules', '.git', '.vs', '.vscode',

            # Additional Archives and Binaries
            '*.tgz', '*.tbz2', '*.txz', '*.cab', '*.msi', '*.dmg', '*.pkg',
            '*.deb', '*.rpm',

            # Compiled Code
            '*.class', '*.jar', '*.pyc', '*.pyo', '*.pyd',

            # Additional Media Formats
            '*.flac', '*.wav', '*.aac', '*.ogg', '*.m4a', '*.m4v', '*.3gp', '*.webm',

            # Additional Document Formats
            '*.odt', '*.ods', '*.odp', '*.sqlite', '*.db', '*.mdb',

            # Font Files
            '*.ttf', '*.otf', '*.woff', '*.woff2',

            # Version Control and Build Directories
            '.svn', '.hg', '.bzr', '__pycache__', 'dist', 'build', 'target',
            'bin', 'obj',

            # System/Cache Files
            '.DS_Store', 'Thumbs.db', '.cache'
        ),

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [ValidateSet('Auto', 'UTF8', 'UTF8BOM', 'UTF16LE', 'UTF16BE', 'UTF32', 'ASCII')]
        [String]$Encoding = 'Auto',

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

        function Get-EncodingFromName
        {
            param(
                [String]$EncodingName
            )

            if ([String]::IsNullOrEmpty($EncodingName))
            {
                return $null
            }

            try
            {
                switch ($EncodingName.ToUpper())
                {
                    'AUTO' { return $null }  # Return null to indicate keep original encoding
                    'UTF8' { return New-Object System.Text.UTF8Encoding($false) }
                    'UTF8BOM' { return New-Object System.Text.UTF8Encoding($true) }
                    'UTF16LE' { return [System.Text.Encoding]::Unicode }
                    'UTF16BE' { return [System.Text.Encoding]::BigEndianUnicode }
                    'UTF32' { return [System.Text.Encoding]::UTF32 }
                    'ASCII' { return [System.Text.Encoding]::ASCII }
                    default
                    {
                        throw "Unsupported encoding: $EncodingName"
                    }
                }
            }
            catch
            {
                Write-Error "Failed to create encoding '$EncodingName': $($_.Exception.Message)"
                return $null
            }
        }

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
                    # Executables and Libraries
                    '.exe', '.dll', '.so', '.dylib', '.a', '.lib', '.obj', '.o',

                    # Archives
                    '.zip', '.7z', '.rar', '.tar', '.gz', '.bz2', '.xz',
                    '.cab', '.iso', '.vhd', '.vhdx',

                    # Images
                    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.ico',
                    '.svg', '.webp', '.heic', '.psd',

                    # Audio/Video
                    '.mp3', '.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv',
                    '.webm', '.flac', '.wav', '.m4a', '.m4v', '.3gp',

                    # Documents
                    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.rtf',

                    # Installers and Packages
                    '.msi', '.dmg', '.pkg', '.deb', '.rpm', '.appimage', '.bin', '.jar',

                    # Fonts
                    '.ttf', '.otf', '.woff', '.woff2',

                    # Databases and Compiled Files
                    '.sqlite', '.db', '.pyc', '.class', '.swf'
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

        function Test-LineEndingConversionNeeded
        {
            param(
                [String]$FilePath,
                [String]$TargetLineEnding
            )

            try
            {
                $stream = [System.IO.File]::OpenRead($FilePath)
                try
                {
                    if ($stream.Length -eq 0)
                    {
                        return $false  # Empty files don't need conversion
                    }

                    # Sample first 64KB for performance (most files are smaller)
                    $sampleSize = [Math]::Min($stream.Length, 65536)
                    $buffer = New-Object byte[] $sampleSize
                    $bytesRead = $stream.Read($buffer, 0, $sampleSize)

                    $hasLF = $false
                    $hasCRLF = $false

                    for ($i = 0; $i -lt $bytesRead; $i++)
                    {
                        if ($buffer[$i] -eq 13) # CR
                        {
                            if ($i + 1 -lt $bytesRead -and $buffer[$i + 1] -eq 10) # LF
                            {
                                $hasCRLF = $true
                                $i++ # Skip next LF
                            }
                            else
                            {
                                $hasLF = $true # Standalone CR treated as line ending
                            }
                        }
                        elseif ($buffer[$i] -eq 10) # Standalone LF
                        {
                            $hasLF = $true
                        }

                        # Early exit if we found mixed endings or the "wrong" type
                        if ($TargetLineEnding -eq "`n" -and $hasCRLF)
                        {
                            return $true # Need conversion: found CRLF when targeting LF
                        }
                        elseif ($TargetLineEnding -eq "`r`n" -and $hasLF)
                        {
                            return $true # Need conversion: found LF when targeting CRLF
                        }
                    }

                    # If we reached here without early exit, check final state
                    if ($TargetLineEnding -eq "`n") # LF target
                    {
                        return $hasCRLF # Need conversion if any CRLF found
                    }
                    else # CRLF target
                    {
                        return $hasLF # Need conversion if any standalone LF/CR found
                    }
                }
                finally
                {
                    $stream.Close()
                }
            }
            catch
            {
                Write-Verbose "Error checking line endings for '$FilePath': $($_.Exception.Message)"
                # If we can't determine, assume conversion is needed for safety
                return $true
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
                        return New-Object System.Text.UTF8Encoding($false)  # UTF-8 without BOM for empty files
                    }

                    # Read up to 4 bytes for BOM detection
                    $bomBuffer = New-Object byte[] 4
                    $bomBytesRead = $stream.Read($bomBuffer, 0, 4)

                    # Check for BOM patterns
                    if ($bomBytesRead -ge 3 -and $bomBuffer[0] -eq 0xEF -and $bomBuffer[1] -eq 0xBB -and $bomBuffer[2] -eq 0xBF)
                    {
                        return New-Object System.Text.UTF8Encoding($true)  # UTF-8 with BOM
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
                        return New-Object System.Text.UTF8Encoding($false)  # UTF-8 without BOM for empty files
                    }

                    # Check if it's valid UTF-8 using the sample
                    try
                    {
                        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                        $decoded = $utf8NoBom.GetString($sampleBuffer, 0, $sampleBytesRead)
                        $reencoded = $utf8NoBom.GetBytes($decoded)

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
                                return $utf8NoBom  # UTF-8 without BOM
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
                    return New-Object System.Text.UTF8Encoding($false)
                }
                finally
                {
                    $stream.Close()
                }
            }
            catch
            {
                Write-Verbose "Error detecting encoding for '$FilePath': $($_.Exception.Message)"
                return New-Object System.Text.UTF8Encoding($false)  # UTF-8 without BOM as fallback
            }
        }

        function Convert-SingleFileLineEnding
        {
            param(
                [String]$FilePath,
                [String]$TargetLineEnding,
                [System.Text.Encoding]$SourceEncoding,
                [System.Text.Encoding]$TargetEncoding = $null
            )

            $tempFilePath = "$FilePath.tmp"
            $originalLfCount = 0
            $originalCrlfCount = 0
            $newLfCount = 0
            $newCrlfCount = 0

            # Use source encoding if no target encoding specified
            $outputEncoding = if ($TargetEncoding) { $TargetEncoding } else { $SourceEncoding }

            try
            {
                # Create streams for reading and writing
                $reader = New-Object System.IO.StreamReader($FilePath, $SourceEncoding)
                $writer = New-Object System.IO.StreamWriter($tempFilePath, $false, $outputEncoding)

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
                    SourceEncoding = $SourceEncoding.EncodingName
                    TargetEncoding = $outputEncoding.EncodingName
                    EncodingChanged = $SourceEncoding.ToString() -ne $outputEncoding.ToString() -or $SourceEncoding.GetPreamble().Length -ne $outputEncoding.GetPreamble().Length
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
                    SourceEncoding = if ($SourceEncoding) { $SourceEncoding.EncodingName } else { $null }
                    TargetEncoding = if ($outputEncoding) { $outputEncoding.EncodingName } else { $null }
                    EncodingChanged = $false
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

                    # Pre-check if conversion is needed (even for WhatIf to provide accurate preview)
                    $needsConversion = Test-LineEndingConversionNeeded -FilePath $file.FullName -TargetLineEnding $targetLineEnding

                    if ($needsConversion)
                    {
                        if ($PSCmdlet.ShouldProcess($file.FullName, "Convert line endings to $LineEnding"))
                        {
                            Write-Verbose "Processing file: $($file.FullName)"
                            $sourceEncoding = Get-FileEncoding -FilePath $file.FullName
                            $targetEncoding = if ($Encoding -ne 'Auto') { Get-EncodingFromName -EncodingName $Encoding } else { $null }
                            $result = Convert-SingleFileLineEnding -FilePath $file.FullName -TargetLineEnding $targetLineEnding -SourceEncoding $sourceEncoding -TargetEncoding $targetEncoding

                            if ($PassThru)
                            {
                                $null = $processedFiles.Add($result)
                            }

                            if ($result.Success)
                            {
                                $encodingInfo = if ($result.EncodingChanged) { " Encoding: $($result.SourceEncoding)→$($result.TargetEncoding)" } else { '' }
                                Write-Verbose "Successfully converted '$($file.FullName)' (LF: $($result.OriginalLF)→$($result.NewLF), CRLF: $($result.OriginalCRLF)→$($result.NewCRLF))$encodingInfo"
                            }
                            else
                            {
                                Write-Error "Failed to convert '$($file.FullName)': $($result.Error)"
                            }
                        }
                    }
                    else
                    {
                        if ($PSCmdlet.ShouldProcess($file.FullName, "Skip file - already has correct line endings ($LineEnding)"))
                        {
                            Write-Verbose "Skipping '$($file.FullName)' - already has correct line endings"

                            if ($PassThru)
                            {
                                # Return info showing no changes were needed
                                $sourceEncoding = Get-FileEncoding -FilePath $file.FullName
                                $result = [PSCustomObject]@{
                                    FilePath = $file.FullName
                                    OriginalLF = if ($LineEnding -eq 'LF') { 1 } else { 0 }
                                    OriginalCRLF = if ($LineEnding -eq 'CRLF') { 1 } else { 0 }
                                    NewLF = if ($LineEnding -eq 'LF') { 1 } else { 0 }
                                    NewCRLF = if ($LineEnding -eq 'CRLF') { 1 } else { 0 }
                                    SourceEncoding = $sourceEncoding.EncodingName
                                    TargetEncoding = $sourceEncoding.EncodingName
                                    EncodingChanged = $false
                                    Success = $true
                                    Error = $null
                                    Skipped = $true
                                }
                                $null = $processedFiles.Add($result)
                            }
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

                # Pre-check if conversion is needed (even for WhatIf to provide accurate preview)
                $needsConversion = Test-LineEndingConversionNeeded -FilePath $resolvedPath -TargetLineEnding $targetLineEnding

                if ($needsConversion)
                {
                    if ($PSCmdlet.ShouldProcess($resolvedPath, "Convert line endings to $LineEnding"))
                    {
                        Write-Verbose "Processing file: $resolvedPath"
                        $sourceEncoding = Get-FileEncoding -FilePath $resolvedPath
                        $targetEncoding = if ($Encoding -ne 'Auto') { Get-EncodingFromName -EncodingName $Encoding } else { $null }
                        $result = Convert-SingleFileLineEnding -FilePath $resolvedPath -TargetLineEnding $targetLineEnding -SourceEncoding $sourceEncoding -TargetEncoding $targetEncoding

                        if ($PassThru)
                        {
                            $null = $processedFiles.Add($result)
                        }

                        if ($result.Success)
                        {
                            $encodingInfo = if ($result.EncodingChanged) { " Encoding: $($result.SourceEncoding)→$($result.TargetEncoding)" } else { '' }
                            Write-Verbose "Successfully converted '$resolvedPath' (LF: $($result.OriginalLF)→$($result.NewLF), CRLF: $($result.OriginalCRLF)→$($result.NewCRLF))$encodingInfo"
                        }
                        else
                        {
                            Write-Error "Failed to convert '$resolvedPath': $($result.Error)"
                        }
                    }
                }
                else
                {
                    if ($PSCmdlet.ShouldProcess($resolvedPath, "Skip file - already has correct line endings ($LineEnding)"))
                    {
                        Write-Verbose "Skipping '$resolvedPath' - already has correct line endings"

                        if ($PassThru)
                        {
                            # Return info showing no changes were needed
                            $sourceEncoding = Get-FileEncoding -FilePath $resolvedPath
                            $result = [PSCustomObject]@{
                                FilePath = $resolvedPath
                                OriginalLF = if ($LineEnding -eq 'LF') { 1 } else { 0 }
                                OriginalCRLF = if ($LineEnding -eq 'CRLF') { 1 } else { 0 }
                                NewLF = if ($LineEnding -eq 'LF') { 1 } else { 0 }
                                NewCRLF = if ($LineEnding -eq 'CRLF') { 1 } else { 0 }
                                SourceEncoding = $sourceEncoding.EncodingName
                                TargetEncoding = $sourceEncoding.EncodingName
                                EncodingChanged = $false
                                Success = $true
                                Error = $null
                                Skipped = $true
                            }
                            $null = $processedFiles.Add($result)
                        }
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
