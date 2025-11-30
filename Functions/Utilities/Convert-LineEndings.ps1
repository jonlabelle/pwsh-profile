function Convert-LineEndings
{
    <#
    .SYNOPSIS
        Converts line endings between LF (Unix) and CRLF (Windows) with optional file encoding conversion.

    .DESCRIPTION
        This function converts line endings in text files between Unix (LF) and Windows (CRLF) formats
        with optional file encoding conversion. By default, the original file encoding is preserved, but
        you can specify a target encoding to convert files during line ending processing. It uses streaming
        operations for optimal performance with large files and automatically detects and skips binary files
        to prevent corruption.

        The function includes intelligent optimization that independently checks both line ending format
        and file encoding. Only the conversions that are actually needed are performed:
        - If line endings are already correct but encoding needs conversion, only encoding is changed
        - If encoding is already correct but line endings need conversion, only line endings are changed
        - If both are already correct, the file is skipped entirely, preserving modification timestamps
        - If both need conversion, both are converted in a single operation

        The function supports both individual files and directory processing with optional recursion.
        It provides intelligent WhatIf support that analyzes files to show exactly what conversions
        would be performed, rather than showing all files in scope.

    .PARAMETER Path
        The path to a file or directory to process.
        Accepts an array of paths and supports pipeline input.
        For directories, all text files will be processed unless filtered by Include/Exclude parameters.
        If not provided, defaults to the current working directory.

    .PARAMETER LineEnding
        Specifies the target line ending format. Files are converted only if their current line
        endings differ from the target format. Line ending conversion is performed independently
        of encoding conversion - files that already have the correct line endings will not be
        modified even if encoding conversion is needed.

        Valid values:
        - Auto (or System): Use platform default line endings (CRLF on Windows, LF on Unix/Linux/macOS) [Default]
        - CRLF (or Windows): Carriage Return + Line Feed (Windows: \r\n)
        - LF (or Unix): Line Feed only (Unix/Linux/macOS: \n)

        Note that the single CR (/r) line ending (used by old Mac systems) is not supported.
        There's simply no practical reason to convert files to/from this obsolete format anymore.

    .PARAMETER Recurse
        When processing directories, search recursively through all subdirectories.
        Only applies when Path points to a directory.

    .PARAMETER Include
        Specifies file patterns to include when processing directories.
        Supports wildcards (e.g., '*.txt', '*.ps1', '*.md') and specific filenames.
        Default includes common text file extensions and extension-less text files
        like LICENSE, README, Dockerfile, Makefile, etc.

    .PARAMETER Exclude
        Specifies file patterns to exclude when processing directories.
        Supports wildcards and common binary file extensions are excluded by default.

    .PARAMETER Force
        Overwrites read-only files. Without this parameter, read-only files are skipped.

    .PARAMETER Encoding
        Specifies the target file encoding. When set to 'Auto' (default), the original file encoding
        is preserved. When set to a specific encoding, files will be converted to that encoding only
        if their current encoding differs from the target. Encoding conversion is performed independently
        of line ending conversion - files that already have the correct encoding will not be modified
        even if line ending conversion is needed.

        Valid values:
        - Auto: Preserve original file encoding (default)
        - UTF8: UTF-8 without BOM
        - UTF8BOM: UTF-8 with BOM
        - UTF16LE: UTF-16 Little Endian with BOM
        - UTF16BE: UTF-16 Big Endian with BOM
        - UTF32: UTF-32 Little Endian with BOM
        - UTF32BE: UTF-32 Big Endian with BOM
        - ASCII: 7-bit ASCII encoding
        - ANSI: System default ANSI encoding (code page dependent)

    .PARAMETER EnsureEndingNewline
        Ensures that each processed file ends with a newline character. If a file already ends
        with a newline (LF or CRLF), it will not be modified. If a file does not end with a
        newline, one will be added using the specified LineEnding format. This parameter is
        useful for ensuring consistent file formatting across projects, as many tools and
        editors expect text files to end with a newline character.

    .PARAMETER PreserveTimestamps
        When specified, preserves the original file timestamps (creation time and last write time)
        when files are modified. By default, modified files will have updated timestamps
        reflecting the time of conversion.

    .PARAMETER PassThru
        Returns information about the processed files.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'script.ps1' -LineEnding 'LF'

        Converts the specified PowerShell script to use Unix line endings only if it doesn't
        already have LF line endings. The file encoding is preserved (Auto encoding).

    .EXAMPLE
        PS > Convert-LineEndings -Path 'script.ps1'

        Converts the specified PowerShell script to use platform default line endings
        (CRLF on Windows, LF on Unix/Linux/macOS). The file encoding is preserved.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'C:\Scripts' -LineEnding 'CRLF' -Recurse -Include '*.ps1', '*.txt'

        Recursively converts all PowerShell and text files in the Scripts directory to Windows line endings.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'project' -LineEnding 'LF' -Recurse

        Converts all files in the project directory to Unix line endings, including common text files
        like LICENSE, README, Dockerfile, and Makefile, along with all supported text file extensions.

    .EXAMPLE
        PS > Get-ChildItem '*.md' | Convert-LineEndings -LineEnding 'LF' -WhatIf

        Shows which Markdown files would be converted to Unix line endings vs. which would be skipped.
        Files needing line ending conversion show "Convert line endings from [Current] to LF" while files
        with correct endings show "Skip file - already has correct line endings (LF)".

    .EXAMPLE
        PS > Convert-LineEndings -Path 'project' -LineEnding 'LF' -Exclude '*.min.js', 'node_modules' -Recurse

        Converts files to Unix line endings while excluding minified JavaScript files and node_modules directories.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'data.csv' -LineEnding 'CRLF' -Encoding 'UTF8BOM'

        Converts a CSV file to Windows line endings and UTF-8 with BOM encoding. Both conversions
        are performed independently - if the file already has CRLF endings but wrong encoding,
        only the encoding will be converted.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'legacy-file.txt' -LineEnding 'CRLF' -Encoding 'ANSI'

        Converts a legacy text file to Windows line endings and system default ANSI encoding.
        This is useful for older Windows applications that expect ANSI-encoded files with
        the system's default code page.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'unicode-data.xml' -LineEnding 'LF' -Encoding 'UTF32'

        Converts an XML file to Unix line endings and UTF-32 Little Endian encoding with BOM.
        UTF-32 provides fixed-width encoding for all Unicode characters, useful for applications
        that need predictable character indexing.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'big-endian-file.txt' -LineEnding 'CRLF' -Encoding 'UTF32BE'

        Converts a file to Windows line endings and UTF-32 Big Endian encoding. This might be
        needed for interoperability with systems that prefer big-endian byte ordering.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'script.txt' -LineEnding 'LF' -Encoding 'UTF8' -PassThru

        Converts to LF line endings and UTF-8 without BOM. The PassThru output will show which
        conversions were actually performed (line endings, encoding, both, or neither).

    .EXAMPLE
        PS > Get-ChildItem '*.txt' | Convert-LineEndings -LineEnding 'LF' -Encoding 'UTF8' -PassThru

        Processes all text files for both line ending and encoding conversion. Returns detailed
        information about which files were converted and what changes were made.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'mixed-content' -LineEnding 'LF' -Recurse -PassThru |
             Where-Object {$_.Converted -or $_.EncodingChanged} |
             Format-Table FilePath,Converted,EncodingChanged,SourceEncoding,TargetEncoding

        Processes a directory recursively and shows only files that actually required conversion,
        displaying what type of conversion was performed on each file.

    .EXAMPLE
        PS > Convert-LineEndings -Path @('file1.txt','file2.json','file3.xml') -LineEnding 'CRLF' -Encoding 'UTF8' -PassThru

        Processes multiple specific files and shows which ones needed line ending conversion,
        encoding conversion, both, or neither. Demonstrates independent conversion logic
        across different file types.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'config.json' -LineEnding 'LF' -Encoding 'UTF8' -WhatIf

        Preview what would happen when converting a JSON file. Shows output like:
        "Convert line endings from CRLF to LF" (if line endings need conversion)
        "Convert encoding from UTF8BOM to UTF8" (if encoding needs conversion)
        "Skip file - already has correct line endings (LF) and encoding (UTF8)" (if no conversion needed)

    .EXAMPLE
        PS > Convert-LineEndings -Path 'document.txt' -Encoding 'UTF8BOM' -PassThru

        Converts only the encoding to UTF-8 with BOM while using platform default line endings.
        When LineEnding is not specified, it defaults to 'Auto' which uses the current platform's
        default line ending format. PassThru output will show EncodingChanged: True and line
        ending information based on platform defaults.

    .EXAMPLE
        PS > Get-ChildItem 'src\*.cs' | Convert-LineEndings -LineEnding 'CRLF' -Force -PassThru | Where-Object Converted

        Converts C# source files to Windows line endings and returns only files that actually
        had their line endings converted (filters out files that already had CRLF).

    .EXAMPLE
        PS > Convert-LineEndings -Path 'legacy-file.txt' -LineEnding 'LF' -Encoding 'UTF8' -PassThru

        Converts both line endings and encoding. The file timestamps will be updated to
        the current time since -PreserveTimestamps is not specified.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'project' -LineEnding 'LF' -Recurse -PreserveTimestamps -PassThru

        Converts all files in the project directory to Unix line endings while preserving their
        original timestamps. Without -PreserveTimestamps, modified files would get new timestamps
        reflecting the time of conversion. Files that don't need conversion are never touched,
        so their timestamps are naturally preserved regardless of the -PreserveTimestamps setting.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'legacy-file.txt' -LineEnding 'LF' -Encoding 'UTF8' -PassThru | Format-Table

        Converts both line endings and encoding with tabular output showing before/after state:
        FilePath         OriginalLF OriginalCRLF NewLF NewCRLF SourceEncoding TargetEncoding EncodingChanged Converted Skipped
        --------         ---------- ------------ ----- ------- -------------- -------------- --------------- --------- -------
        legacy-file.txt  0          15           15    0       ASCII          UTF8           True            True      False

    .EXAMPLE
        PS > $results = Get-ChildItem '*.md' | Convert-LineEndings -LineEnding 'LF' -Encoding 'UTF8' -PassThru
        PS > $results | Group-Object Skipped,Converted,EncodingChanged | Select-Object Name,Count

        Processes Markdown files and groups results by conversion type to see summary statistics:
        - "False,True,True": Files that had both line endings and encoding converted
        - "False,True,False": Files that had only line endings converted
        - "False,False,True": Files that had only encoding converted
        - "True,False,False": Files that were skipped (no conversion needed)

    .EXAMPLE
        PS > Convert-LineEndings -Path 'project' -Recurse -PassThru

        Converts all files in the current working directory to platform default line endings using 'Auto' mode.
        On Windows systems, files will be converted to CRLF; on Unix/Linux/macOS systems, files will
        be converted to LF. Returns detailed information about processed files.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'script.js' -LineEnding 'LF' -EnsureEndingNewline

        Converts the JavaScript file to Unix line endings and ensures it ends with a newline.
        If the file already ends with a newline, it won't be modified for that purpose.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'config.json' -LineEnding 'CRLF' -EnsureEndingNewline -PassThru

        Converts a JSON file to Windows line endings and ensures it ends with CRLF.
        Returns detailed information showing whether an ending newline was added.

    .EXAMPLE
        PS > Get-ChildItem '*.cs' | Convert-LineEndings -LineEnding 'CRLF' -EnsureEndingNewline -PassThru |
             Where-Object EndingNewlineAdded

        Processes C# files and returns only those that had an ending newline added.
        Useful for identifying files that didn't previously end with a newline.

    .EXAMPLE
        PS > Convert-LineEndings -Path 'src' -LineEnding 'LF' -EnsureEndingNewline -Recurse -Include '*.py' -WhatIf

        Shows what would happen when processing Python files recursively - which files would
        have line endings converted and which would have ending newlines added.

    .EXAMPLE
        PS > Measure-Command { Convert-LineEndings -Path 'large-project' -LineEnding 'LF' -Recurse }

        Measures the performance of processing a large project directory. The optimized
        implementation reduces I/O operations by combining file analysis (binary detection,
        encoding detection, line ending analysis) into a single file read per file,
        providing significant performance improvements over the previous implementation.

    .OUTPUTS
        None by default.
        [System.Object[]] when PassThru is specified, containing:
        - File: Full path to the processed file
        - LineEnding: Target line ending format
        - Encoding: Target or detected encoding
        - OriginalLineEnding: Source line ending format
        - OriginalEncoding: Source file encoding
        - Converted: Whether line ending conversion was performed
        - EncodingChanged: Whether encoding conversion was performed
        - EndingNewlineAdded: Whether an ending newline was added to the file
        - Skipped: Whether the file was skipped (all conversions already correct)

    .NOTES
        BINARY FILE DETECTION:

        The function automatically detects binary files using multiple methods:

        - File extension patterns (executables, images, archives, etc.)
        - Content analysis for null bytes and high ratio of non-printable characters
        - Files are skipped if determined to be binary to prevent corruption

        ENCODING PRESERVATION:

        File encoding is detected and preserved during conversion by default.
        When the -Encoding parameter is specified, files are converted to the target encoding.

        Supported encodings:
        - Auto: Preserve original file encoding (default)
        - UTF8: UTF-8 without BOM
        - UTF8BOM: UTF-8 with BOM
        - UTF16LE: UTF-16 Little Endian with BOM
        - UTF16BE: UTF-16 Big Endian with BOM
        - UTF32: UTF-32 Little Endian with BOM
        - UTF32BE: UTF-32 Big Endian with BOM
        - ASCII: 7-bit ASCII encoding
        - ANSI: System default ANSI encoding (code page dependent)

        INTELLIGENT CONVERSION:

        The function analyzes each file to determine what conversions are actually needed:

        - Line ending conversion only if current format differs from target
        - Encoding conversion only if current encoding differs from target
        - Both conversions if both differ from targets
        - Skip file entirely if both line endings and encoding are already correct

        This optimization minimizes file modifications and preserves timestamps when possible.

        PERFORMANCE:

        Optimized for high performance with large directory trees through several techniques:

        - Combined file analysis reduces I/O operations from 4-5 file reads to 1-2 per file
        - Optimized include/exclude filtering eliminates redundant array operations
        - Uses existing FileInfo objects from Get-ChildItem to avoid redundant Get-Item calls
        - Streaming operations handle large files efficiently without loading entire contents
        - Intelligent pre-scanning samples the first 64KB for encoding and line ending detection
        - Files are processed only if conversions are actually needed
        - Binary files are detected early using both extension patterns and content analysis

        The function evaluates line ending and encoding conversions independently - only
        the conversions that are actually needed are performed. Files that already have
        the correct line endings, encoding, and ending newline are skipped entirely,
        preserving modification timestamps and avoiding unnecessary processing.

        TIMESTAMP PRESERVATION:

        By default, file timestamps are updated to reflect the time of conversion. Use the
        -PreserveTimestamps switch to maintain original file timestamps (creation time and last write time)
        when files are modified. This can be useful to maintain original file history and
        make the conversion process transparent to file system monitoring tools. Files that are
        skipped (no conversion needed) are never touched, so their timestamps are naturally preserved
        regardless of the -PreserveTimestamps setting.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Convert-LineEndings.ps1

    .LINK
        https://jonlabelle.com/snippets/view/powershell/convert-line-endings-in-powershell

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Convert-LineEndings.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Object[]])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path = (Get-Location).Path,

        [Parameter()]
        [ValidateSet('Auto', 'LF', 'CRLF', 'Unix', 'Windows', 'System')]
        [String]$LineEnding = 'Auto',

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
            '.zprofile', '.bash_profile', '.bash_logout', '.npmrc', '.nvmrc',
            '.inputrc', '.curlrc', '.screenrc',

            # Version Control
            '*.gitignore', '*.gitattributes',

            # Build and Make Files
            '*.makefile', '*.cmake',

            # Common Extension-less Text Files
            'LICENSE', 'LICENCE', 'README', 'CHANGELOG',
            'AUTHORS', 'CONTRIBUTORS', 'CONTRIBUTING', 'INSTALL',
            'NEWS', 'HISTORY', 'COPYING', 'COPYRIGHT',
            'NOTICE', 'THANKS', 'TODO', 'BUGS',
            'Dockerfile', 'Makefile', 'Rakefile', 'Gemfile', 'Podfile',
            'Vagrantfile', 'Procfile', 'Brewfile'
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
        [ValidateSet('Auto', 'UTF8', 'UTF8BOM', 'UTF16LE', 'UTF16BE', 'UTF32', 'UTF32BE', 'ASCII', 'ANSI')]
        [String]$Encoding = 'Auto',

        [Parameter()]
        [Alias('InsertFinalNewline', 'EnsureFinalNewline', 'FinalNewline')]
        [Switch]$EnsureEndingNewline,

        [Parameter()]
        [Alias('KeepTimestamps')]
        [Switch]$PreserveTimestamps,

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        # Map aliases to standard values
        switch ($LineEnding)
        {
            'Windows' { $LineEnding = 'CRLF' }
            'Unix' { $LineEnding = 'LF' }
            'System' { $LineEnding = 'Auto' }
        }

        # Resolve Auto line ending to platform default
        if ($LineEnding -eq 'Auto')
        {
            # Use cross-platform detection pattern from project instructions
            if ($PSVersionTable.PSVersion.Major -lt 6)
            {
                # PowerShell 5.1 - Windows only
                $script:IsWindowsPlatform = $true
            }
            else
            {
                # PowerShell Core - use built-in variables
                $script:IsWindowsPlatform = $IsWindows
            }

            if ($script:IsWindowsPlatform)
            {
                $LineEnding = 'CRLF'
                Write-Verbose 'Auto mode: Using Windows default line ending (CRLF)'
            }
            else
            {
                $LineEnding = 'LF'
                Write-Verbose 'Auto mode: Using Unix/Linux/macOS default line ending (LF)'
            }
        }

        Write-Verbose "Starting line ending conversion to $LineEnding"

        # Define line ending strings
        $lineEndings = @{
            'LF' = "`n"
            'CRLF' = "`r`n"
        }

        $targetLineEnding = $lineEndings[$LineEnding]
        $processedFiles = [System.Collections.ArrayList]::new()

        function Get-FileAnalysis
        {
            <#
            .SYNOPSIS
                Performs combined file analysis to reduce multiple file I/O operations.

            .DESCRIPTION
                This function combines binary detection, line ending analysis, encoding detection,
                and ending newline checking into a single file read operation for optimal performance.
            #>
            param(
                [String]$FilePath,
                [String]$TargetLineEnding,
                [String]$TargetEncodingName,
                [Boolean]$CheckEndingNewline
            )

            try
            {
                $fileInfo = Get-Item -Path $FilePath -ErrorAction Stop
                if ($fileInfo.Length -eq 0)
                {
                    return @{
                        IsBinary = $false
                        SourceEncoding = [System.Text.Encoding]::UTF8
                        NeedsLineEndingConversion = $false
                        NeedsEncodingConversion = $false
                        NeedsEndingNewline = $CheckEndingNewline
                        Error = $null
                    }
                }

                # First check file extension for obvious binary files
                $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
                $binaryExtensions = @(
                    '.exe', '.dll', '.so', '.dylib', '.a', '.lib', '.obj', '.o',
                    '.zip', '.7z', '.rar', '.tar', '.gz', '.bz2', '.xz', '.tgz', '.tbz2', '.txz',
                    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.ico', '.webp',
                    '.mp3', '.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.flac', '.wav',
                    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
                    '.class', '.jar', '.pyc', '.pyo', '.pyd',
                    '.ttf', '.otf', '.woff', '.woff2',
                    '.sqlite', '.db', '.mdb'
                )

                if ($binaryExtensions -contains $extension)
                {
                    return @{
                        IsBinary = $true
                        SourceEncoding = $null
                        NeedsLineEndingConversion = $false
                        NeedsEncodingConversion = $false
                        NeedsEndingNewline = $false
                        Error = $null
                    }
                }

                # Single file read operation for all analysis
                $stream = [System.IO.File]::OpenRead($FilePath)
                try
                {
                    # Read up to 64KB for analysis (same as original functions)
                    $analysisSize = [Math]::Min($stream.Length, 65536)
                    $analysisBuffer = New-Object byte[] $analysisSize
                    $bytesRead = $stream.Read($analysisBuffer, 0, $analysisSize)

                    # First, do encoding detection using BOM detection logic
                    $sourceEncoding = $null
                    $isUtf32 = $false
                    $isUtf16 = $false

                    if ($bytesRead -ge 4 -and $analysisBuffer[0] -eq 0xFF -and $analysisBuffer[1] -eq 0xFE -and $analysisBuffer[2] -eq 0x00 -and $analysisBuffer[3] -eq 0x00)
                    {
                        $sourceEncoding = [System.Text.Encoding]::UTF32
                        $isUtf32 = $true
                        Write-Verbose "File '$FilePath' detected as UTF-32 LE with BOM"
                    }
                    elseif ($bytesRead -ge 4 -and $analysisBuffer[0] -eq 0x00 -and $analysisBuffer[1] -eq 0x00 -and $analysisBuffer[2] -eq 0xFE -and $analysisBuffer[3] -eq 0xFF)
                    {
                        $sourceEncoding = New-Object System.Text.UTF32Encoding($true, $true)
                        $isUtf32 = $true
                        Write-Verbose "File '$FilePath' detected as UTF-32 BE with BOM"
                    }
                    elseif ($bytesRead -ge 3 -and $analysisBuffer[0] -eq 0xEF -and $analysisBuffer[1] -eq 0xBB -and $analysisBuffer[2] -eq 0xBF)
                    {
                        $sourceEncoding = New-Object System.Text.UTF8Encoding($true)
                        Write-Verbose "File '$FilePath' detected as UTF-8 with BOM"
                    }
                    elseif ($bytesRead -ge 2 -and $analysisBuffer[0] -eq 0xFF -and $analysisBuffer[1] -eq 0xFE)
                    {
                        $sourceEncoding = [System.Text.Encoding]::Unicode
                        $isUtf16 = $true
                        Write-Verbose "File '$FilePath' detected as UTF-16 LE with BOM"
                    }
                    elseif ($bytesRead -ge 2 -and $analysisBuffer[0] -eq 0xFE -and $analysisBuffer[1] -eq 0xFF)
                    {
                        $sourceEncoding = [System.Text.Encoding]::BigEndianUnicode
                        $isUtf16 = $true
                        Write-Verbose "File '$FilePath' detected as UTF-16 BE with BOM"
                    }
                    else
                    {
                        # No BOM - try UTF-8 validation on sample
                        try
                        {
                            $utf8Decoder = [System.Text.Encoding]::UTF8.GetDecoder()
                            $utf8Decoder.Fallback = [System.Text.DecoderFallback]::ExceptionFallback
                            $charBuffer = New-Object char[] ([System.Text.Encoding]::UTF8.GetMaxCharCount($bytesRead))
                            $null = $utf8Decoder.GetChars($analysisBuffer, 0, $bytesRead, $charBuffer, 0)
                            $sourceEncoding = New-Object System.Text.UTF8Encoding($false)
                        }
                        catch
                        {
                            # Check if all bytes are ASCII
                            $isAscii = $true
                            for ($i = 0; $i -lt $bytesRead; $i++)
                            {
                                if ($analysisBuffer[$i] -gt 127)
                                {
                                    $isAscii = $false
                                    break
                                }
                            }
                            $sourceEncoding = if ($isAscii) { [System.Text.Encoding]::ASCII } else { New-Object System.Text.UTF8Encoding($false) }
                        }
                    }

                    # Now do binary detection (but skip for known text encodings)
                    $isBinary = $false
                    if (-not $isUtf32 -and -not $isUtf16)
                    {
                        # For non-UTF32/UTF16 files, do content-based binary detection
                        $nullByteCount = 0
                        $nonPrintableCount = 0

                        for ($i = 0; $i -lt $bytesRead; $i++)
                        {
                            $byte = $analysisBuffer[$i]

                            # Count null bytes for binary detection
                            if ($byte -eq 0)
                            {
                                $nullByteCount++
                            }

                            # Count non-printable characters (excluding common whitespace)
                            if ($byte -lt 32 -and $byte -ne 9 -and $byte -ne 10 -and $byte -ne 13)
                            {
                                $nonPrintableCount++
                            }
                        }

                        if ($bytesRead -gt 0)
                        {
                            $nullByteRatio = $nullByteCount / $bytesRead
                            $nonPrintableRatio = $nonPrintableCount / $bytesRead

                            if ($nullByteCount -gt 0)
                            {
                                Write-Verbose "File '$FilePath' detected as binary due to null bytes (ratio: $nullByteRatio)"
                                $isBinary = $nullByteRatio -gt 0.01
                            }
                            elseif ($nonPrintableRatio -gt 0.3)
                            {
                                Write-Verbose "File '$FilePath' detected as binary due to low printable character ratio ($nonPrintableRatio)"
                                $isBinary = $true
                            }
                        }
                    }

                    if ($isBinary)
                    {
                        return @{
                            IsBinary = $true
                            SourceEncoding = $null
                            NeedsLineEndingConversion = $false
                            NeedsEncodingConversion = $false
                            NeedsEndingNewline = $false
                            Error = $null
                        }
                    }

                    # Line ending detection (encoding-aware)
                    $lfCount = 0
                    $crlfCount = 0
                    $crCount = 0

                    if ($isUtf32)
                    {
                        # For UTF-32, look for line endings in 4-byte patterns
                        # Start after BOM (4 bytes for UTF-32)
                        $startPos = if ($sourceEncoding.GetPreamble().Length -gt 0) { 4 } else { 0 }
                        for ($i = $startPos; $i -lt ($bytesRead - 3); $i += 4)
                        {
                            $preamble = $sourceEncoding.GetPreamble()
                            $isBigEndian = $preamble.Length -eq 4 -and $preamble[0] -eq 0x00 -and $preamble[1] -eq 0x00 -and $preamble[2] -eq 0xFE -and $preamble[3] -eq 0xFF

                            if ($isBigEndian)
                            {
                                # UTF-32 BE: look for 00 00 00 0A (LF) or 00 00 00 0D (CR)
                                if ($analysisBuffer[$i] -eq 0x00 -and $analysisBuffer[$i + 1] -eq 0x00 -and $analysisBuffer[$i + 2] -eq 0x00)
                                {
                                    if ($analysisBuffer[$i + 3] -eq 0x0A) # LF
                                    {
                                        # Check if preceded by CR (0x00 0x00 0x00 0x0D pattern)
                                        if ($i -ge ($startPos + 4) -and $analysisBuffer[$i - 4] -eq 0x00 -and $analysisBuffer[$i - 3] -eq 0x00 -and $analysisBuffer[$i - 2] -eq 0x00 -and $analysisBuffer[$i - 1] -eq 0x0D)
                                        {
                                            $crlfCount++
                                        }
                                        else
                                        {
                                            $lfCount++
                                        }
                                    }
                                    elseif ($analysisBuffer[$i + 3] -eq 0x0D) # CR
                                    {
                                        # Check if not followed by LF
                                        if ($i + 7 -lt $bytesRead -and -not ($analysisBuffer[$i + 4] -eq 0x00 -and $analysisBuffer[$i + 5] -eq 0x00 -and $analysisBuffer[$i + 6] -eq 0x00 -and $analysisBuffer[$i + 7] -eq 0x0A))
                                        {
                                            $crCount++
                                        }
                                    }
                                }
                            }
                            else
                            {
                                # UTF-32 LE: look for 0A 00 00 00 (LF) or 0D 00 00 00 (CR)
                                if ($analysisBuffer[$i + 1] -eq 0x00 -and $analysisBuffer[$i + 2] -eq 0x00 -and $analysisBuffer[$i + 3] -eq 0x00)
                                {
                                    if ($analysisBuffer[$i] -eq 0x0A) # LF
                                    {
                                        # Check if preceded by CR
                                        if ($i -ge ($startPos + 4) -and $analysisBuffer[$i - 4] -eq 0x0D)
                                        {
                                            $crlfCount++
                                        }
                                        else
                                        {
                                            $lfCount++
                                        }
                                    }
                                    elseif ($analysisBuffer[$i] -eq 0x0D) # CR
                                    {
                                        # Check if not followed by LF
                                        if ($i + 4 -lt $bytesRead -and -not ($analysisBuffer[$i + 4] -eq 0x0A))
                                        {
                                            $crCount++
                                        }
                                    }
                                }
                            }
                        }
                    }
                    elseif ($isUtf16)
                    {
                        # For UTF-16, look for line endings in 2-byte patterns
                        # Start after BOM (2 bytes for UTF-16)
                        $startPos = if ($sourceEncoding.GetPreamble().Length -gt 0) { 2 } else { 0 }
                        for ($i = $startPos; $i -lt ($bytesRead - 1); $i += 2)
                        {
                            if ($sourceEncoding.ToString().Contains('BigEndian'))
                            {
                                # UTF-16 BE: look for 00 0A (LF) or 00 0D (CR)
                                if ($analysisBuffer[$i] -eq 0x00)
                                {
                                    if ($analysisBuffer[$i + 1] -eq 0x0A) # LF
                                    {
                                        # Check if preceded by CR (0x00 0x0D pattern)
                                        if ($i -ge 2 -and $analysisBuffer[$i - 2] -eq 0x00 -and $analysisBuffer[$i - 1] -eq 0x0D)
                                        {
                                            $crlfCount++
                                        }
                                        else
                                        {
                                            $lfCount++
                                        }
                                    }
                                    elseif ($analysisBuffer[$i + 1] -eq 0x0D) # CR
                                    {
                                        # Check if not followed by LF
                                        if ($i + 3 -lt $bytesRead -and -not ($analysisBuffer[$i + 2] -eq 0x00 -and $analysisBuffer[$i + 3] -eq 0x0A))
                                        {
                                            $crCount++
                                        }
                                    }
                                }
                            }
                            else
                            {
                                # UTF-16 LE: look for 0A 00 (LF) or 0D 00 (CR)
                                if ($analysisBuffer[$i + 1] -eq 0x00)
                                {
                                    if ($analysisBuffer[$i] -eq 0x0A) # LF
                                    {
                                        # Check if preceded by CR
                                        if ($i -ge 2 -and $analysisBuffer[$i - 2] -eq 0x0D)
                                        {
                                            $crlfCount++
                                        }
                                        else
                                        {
                                            $lfCount++
                                        }
                                    }
                                    elseif ($analysisBuffer[$i] -eq 0x0D) # CR
                                    {
                                        # Check if not followed by LF
                                        if ($i + 2 -lt $bytesRead -and -not ($analysisBuffer[$i + 2] -eq 0x0A))
                                        {
                                            $crCount++
                                        }
                                    }
                                }
                            }
                        }
                    }
                    else
                    {
                        # For UTF-8/ASCII, use standard byte-level detection
                        # Start after BOM for UTF-8 (3 bytes), otherwise from beginning
                        $startPos = if ($sourceEncoding.GetPreamble().Length -gt 0) { 3 } else { 0 }
                        for ($i = $startPos; $i -lt $bytesRead; $i++)
                        {
                            $byte = $analysisBuffer[$i]

                            if ($byte -eq 10) # LF
                            {
                                if ($i -gt $startPos -and $analysisBuffer[$i - 1] -eq 13) # Previous was CR
                                {
                                    $crlfCount++
                                }
                                else
                                {
                                    $lfCount++
                                }
                            }
                            elseif ($byte -eq 13) # CR
                            {
                                if ($i -lt $bytesRead - 1 -and $analysisBuffer[$i + 1] -ne 10) # Next is not LF
                                {
                                    $crCount++
                                }
                            }
                        }
                    }

                    # Determine if line ending conversion is needed
                    $needsLineEndingConversion = $false
                    if ($TargetLineEnding -eq "`n") # Target is LF
                    {
                        $needsLineEndingConversion = $crlfCount -gt 0 -or $crCount -gt 0
                    }
                    elseif ($TargetLineEnding -eq "`r`n") # Target is CRLF
                    {
                        $needsLineEndingConversion = $lfCount -gt 0 -or $crCount -gt 0
                    }

                    # Check encoding conversion need
                    $targetEncoding = if ($TargetEncodingName -ne 'Auto') { Get-EncodingFromName -EncodingName $TargetEncodingName } else { $null }
                    $needsEncodingConversion = -not (Test-EncodingMatch -SourceEncoding $sourceEncoding -TargetEncoding $targetEncoding)

                    # Check ending newline if needed
                    $needsEndingNewline = $false
                    if ($CheckEndingNewline -and $stream.Length -gt 0)
                    {
                        # Check last few bytes for ending newline (encoding-aware)
                        $bytesToCheck = if ($isUtf32) { 4 } elseif ($isUtf16) { 2 } else { 1 }
                        $stream.Position = [Math]::Max(0, $stream.Length - ($bytesToCheck * 2))
                        $endBuffer = New-Object byte[] ($bytesToCheck * 2)
                        $endBytesRead = $stream.Read($endBuffer, 0, ($bytesToCheck * 2))

                        if ($endBytesRead -gt 0)
                        {
                            if ($isUtf32)
                            {
                                # Check last 4 bytes for UTF-32 line ending
                                $lastBytes = $endBuffer[($endBytesRead - 4)..($endBytesRead - 1)]
                                if ($sourceEncoding.ToString().Contains('BigEndian'))
                                {
                                    $needsEndingNewline = -not ($lastBytes[0] -eq 0x00 -and $lastBytes[1] -eq 0x00 -and $lastBytes[2] -eq 0x00 -and ($lastBytes[3] -eq 0x0A -or $lastBytes[3] -eq 0x0D))
                                }
                                else
                                {
                                    $needsEndingNewline = -not (($lastBytes[0] -eq 0x0A -or $lastBytes[0] -eq 0x0D) -and $lastBytes[1] -eq 0x00 -and $lastBytes[2] -eq 0x00 -and $lastBytes[3] -eq 0x00)
                                }
                            }
                            elseif ($isUtf16)
                            {
                                # Check last 2 bytes for UTF-16 line ending
                                $lastBytes = $endBuffer[($endBytesRead - 2)..($endBytesRead - 1)]
                                if ($sourceEncoding.ToString().Contains('BigEndian'))
                                {
                                    $needsEndingNewline = -not ($lastBytes[0] -eq 0x00 -and ($lastBytes[1] -eq 0x0A -or $lastBytes[1] -eq 0x0D))
                                }
                                else
                                {
                                    $needsEndingNewline = -not (($lastBytes[0] -eq 0x0A -or $lastBytes[0] -eq 0x0D) -and $lastBytes[1] -eq 0x00)
                                }
                            }
                            else
                            {
                                # Check last byte for UTF-8/ASCII line ending
                                $lastByte = $endBuffer[$endBytesRead - 1]
                                $needsEndingNewline = $lastByte -ne 10 -and $lastByte -ne 13 # Not LF or CR
                            }
                        }
                    }

                    return @{
                        IsBinary = $false
                        SourceEncoding = $sourceEncoding
                        NeedsLineEndingConversion = $needsLineEndingConversion
                        NeedsEncodingConversion = $needsEncodingConversion
                        NeedsEndingNewline = $needsEndingNewline
                        Error = $null
                    }
                }
                finally
                {
                    $stream.Close()
                }
            }
            catch
            {
                return @{
                    IsBinary = $true  # Assume binary if we can't analyze
                    SourceEncoding = $null
                    NeedsLineEndingConversion = $false
                    NeedsEncodingConversion = $false
                    NeedsEndingNewline = $false
                    Error = $_.Exception.Message
                }
            }
        }

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
                    'UTF32BE' { return [System.Text.Encoding]::GetEncoding('utf-32BE') }
                    'ASCII' { return [System.Text.Encoding]::ASCII }
                    'ANSI' { return [System.Text.Encoding]::Default }
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

        function Test-EncodingMatch
        {
            param(
                [System.Text.Encoding]$SourceEncoding,
                [System.Text.Encoding]$TargetEncoding
            )

            # If target encoding is null, it means keep original (Auto mode)
            if ($null -eq $TargetEncoding)
            {
                return $true
            }

            # If both are null, they match
            if ($null -eq $SourceEncoding -and $null -eq $TargetEncoding)
            {
                return $true
            }

            # If one is null and the other isn't, they don't match
            if ($null -eq $SourceEncoding -or $null -eq $TargetEncoding)
            {
                return $false
            }

            # Compare the encoding types and BOM presence
            $sourceType = $SourceEncoding.ToString()
            $targetType = $TargetEncoding.ToString()
            $sourceBomLength = $SourceEncoding.GetPreamble().Length
            $targetBomLength = $TargetEncoding.GetPreamble().Length

            return ($sourceType -eq $targetType) -and ($sourceBomLength -eq $targetBomLength)
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
                    '.svgz', '.webp', '.heic', '.psd',

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

                    # Perform checks for text encoding patterns first to avoid false positives

                    # UTF-32 LE BOM: FF FE 00 00 (check before UTF-16 LE to avoid conflict)
                    $hasUtf32LeBom = $bytesRead -ge 4 -and $buffer[0] -eq 0xFF -and $buffer[1] -eq 0xFE -and $buffer[2] -eq 0x00 -and $buffer[3] -eq 0x00

                    # UTF-32 BE BOM: 00 00 FE FF
                    $hasUtf32BeBom = $bytesRead -ge 4 -and $buffer[0] -eq 0x00 -and $buffer[1] -eq 0x00 -and $buffer[2] -eq 0xFE -and $buffer[3] -eq 0xFF

                    # UTF-16 LE BOM: FF FE (check after UTF-32 LE to avoid conflict)
                    $hasUtf16LeBom = $bytesRead -ge 2 -and $buffer[0] -eq 0xFF -and $buffer[1] -eq 0xFE -and -not $hasUtf32LeBom

                    # UTF-16 BE BOM: FE FF
                    $hasUtf16BeBom = $bytesRead -ge 2 -and $buffer[0] -eq 0xFE -and $buffer[1] -eq 0xFF

                    # If we detect UTF-32 encoding, analyze accordingly
                    if ($hasUtf32LeBom -or $hasUtf32BeBom)
                    {
                        Write-Verbose "File '$FilePath' has UTF-32 BOM, analyzing as UTF-32 text"
                        # For UTF-32, check every 4 bytes starting from position 4 (after BOM)
                        $printableCount = 0
                        $totalChars = 0
                        $startPos = 4

                        for ($i = $startPos; $i -lt $bytesRead - 3; $i += 4)
                        {
                            $char = if ($hasUtf32LeBom)
                            {
                                $buffer[$i] + ($buffer[$i + 1] * 256) + ($buffer[$i + 2] * 65536) + ($buffer[$i + 3] * 16777216)
                            }
                            else
                            {
                                ($buffer[$i] * 16777216) + ($buffer[$i + 1] * 65536) + ($buffer[$i + 2] * 256) + $buffer[$i + 3]
                            }

                            $totalChars++
                            # Check if character is printable (including common whitespace and extended Unicode)
                            if (($char -ge 32 -and $char -le 126) -or $char -eq 9 -or $char -eq 10 -or $char -eq 13 -or ($char -ge 128 -and $char -le 0x10FFFF))
                            {
                                $printableCount++
                            }
                        }

                        if ($totalChars -gt 0)
                        {
                            $printableRatio = $printableCount / $totalChars
                            if ($printableRatio -lt 0.75)
                            {
                                Write-Verbose "File '$FilePath' detected as binary (low UTF-32 printable character ratio: $([math]::Round($printableRatio * 100, 1))%)"
                                return $true
                            }
                        }
                        return $false
                    }
                    # If we detect UTF-16 encoding (common with PowerShell Out-File), analyze accordingly
                    elseif ($hasUtf16LeBom -or $hasUtf16BeBom)
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

                    # For other encodings, first try to validate as UTF-8
                    try
                    {
                        $utf8NoBom = New-Object System.Text.UTF8Encoding($false, $true) # Strict UTF-8 validation
                        $decoded = $utf8NoBom.GetString($buffer, 0, $bytesRead)

                        # If we successfully decoded as UTF-8, check the decoded string for printable characters
                        $printableCount = 0
                        foreach ($char in $decoded.ToCharArray())
                        {
                            $charCode = [int]$char
                            # Printable Unicode characters: basic ASCII printable (32-126), common whitespace (9,10,13),
                            # and other Unicode characters (128+, but exclude control characters 127-159)
                            if (($charCode -ge 32 -and $charCode -le 126) -or
                                $charCode -eq 9 -or $charCode -eq 10 -or $charCode -eq 13 -or
                                ($charCode -ge 160)) # Unicode characters above control range
                            {
                                $printableCount++
                            }
                        }

                        $printableRatio = if ($decoded.Length -gt 0) { $printableCount / $decoded.Length } else { 1.0 }
                        if ($printableRatio -ge 0.75)
                        {
                            Write-Verbose "File '$FilePath' validated as UTF-8 text (printable character ratio: $([math]::Round($printableRatio * 100, 1))%)"
                            return $false
                        }
                        else
                        {
                            Write-Verbose "File '$FilePath' is valid UTF-8 but has low printable character ratio: $([math]::Round($printableRatio * 100, 1))%"
                        }
                    }
                    catch
                    {
                        # Not valid UTF-8, fall back to byte-level analysis
                        Write-Verbose "File '$FilePath' is not valid UTF-8, performing byte-level analysis: $($_.Exception.Message)"
                    }

                    # Fall back to byte-level analysis for non-UTF-8 files
                    # Check for null bytes (but be more selective)
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

                    # Check ratio of printable characters for non-UTF-8 files (ASCII/ANSI)
                    $printableCount = 0
                    for ($i = 0; $i -lt $bytesRead; $i++)
                    {
                        $byte = $buffer[$i]
                        # Only count ASCII printable and common whitespace for byte-level analysis
                        # Don't assume extended ASCII (128-255) is printable without proper encoding context
                        if (($byte -ge 32 -and $byte -le 126) -or $byte -eq 9 -or $byte -eq 10 -or $byte -eq 13)
                        {
                            $printableCount++
                        }
                    }

                    $printableRatio = $printableCount / $bytesRead
                    if ($printableRatio -lt 0.60) # Lower threshold for ASCII-only analysis
                    {
                        Write-Verbose "File '$FilePath' detected as binary (low ASCII printable character ratio: $([math]::Round($printableRatio * 100, 1))%)"
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

        function Test-FileEndsWithNewline
        {
            param(
                [String]$FilePath
            )

            try
            {
                $fileInfo = Get-Item -Path $FilePath
                if ($fileInfo.Length -eq 0)
                {
                    # Empty files don't end with newline
                    return $false
                }

                # Use streaming to read just the end of the file to check for line endings
                $stream = [System.IO.FileStream]::new($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
                try
                {
                    # Read the last few bytes to check for line endings
                    $bytesToCheck = [Math]::Min(4, $fileInfo.Length)
                    $stream.Seek(-$bytesToCheck, [System.IO.SeekOrigin]::End) | Out-Null

                    $buffer = New-Object byte[] $bytesToCheck
                    $bytesRead = $stream.Read($buffer, 0, $bytesToCheck)

                    # Check if file ends with common line ending patterns
                    # LF (0x0A), CRLF (0x0D 0x0A), or CR (0x0D)
                    if ($bytesRead -gt 0)
                    {
                        $lastByte = $buffer[$bytesRead - 1]
                        if ($lastByte -eq 0x0A)  # LF
                        {
                            return $true
                        }
                        elseif ($lastByte -eq 0x0D)  # CR
                        {
                            return $true
                        }
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
                Write-Verbose "Error checking file ending for '$FilePath': $($_.Exception.Message)"
                # If we can't determine, assume it doesn't end with newline for safety
                return $false
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

                    # Check for BOM patterns - Order matters! Check longer BOMs first
                    # UTF-32 LE BOM: FF FE 00 00 (4 bytes)
                    if ($bomBytesRead -ge 4 -and $bomBuffer[0] -eq 0xFF -and $bomBuffer[1] -eq 0xFE -and $bomBuffer[2] -eq 0x00 -and $bomBuffer[3] -eq 0x00)
                    {
                        return [System.Text.Encoding]::UTF32  # UTF-32 LE
                    }
                    # UTF-32 BE BOM: 00 00 FE FF (4 bytes)
                    elseif ($bomBytesRead -ge 4 -and $bomBuffer[0] -eq 0x00 -and $bomBuffer[1] -eq 0x00 -and $bomBuffer[2] -eq 0xFE -and $bomBuffer[3] -eq 0xFF)
                    {
                        return [System.Text.Encoding]::GetEncoding('utf-32BE')  # UTF-32 BE
                    }
                    # UTF-8 BOM: EF BB BF (3 bytes)
                    elseif ($bomBytesRead -ge 3 -and $bomBuffer[0] -eq 0xEF -and $bomBuffer[1] -eq 0xBB -and $bomBuffer[2] -eq 0xBF)
                    {
                        return New-Object System.Text.UTF8Encoding($true)  # UTF-8 with BOM
                    }
                    # UTF-16 LE BOM: FF FE (2 bytes) - Check after UTF-32 LE to avoid conflict
                    elseif ($bomBytesRead -ge 2 -and $bomBuffer[0] -eq 0xFF -and $bomBuffer[1] -eq 0xFE)
                    {
                        return [System.Text.Encoding]::Unicode  # UTF-16 LE
                    }
                    # UTF-16 BE BOM: FE FF (2 bytes)
                    elseif ($bomBytesRead -ge 2 -and $bomBuffer[0] -eq 0xFE -and $bomBuffer[1] -eq 0xFF)
                    {
                        return [System.Text.Encoding]::BigEndianUnicode  # UTF-16 BE
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
                [System.Text.Encoding]$TargetEncoding = $null,
                [Boolean]$ConvertLineEndings = $true,
                [Boolean]$EnsureEndingNewline = $false,
                [Boolean]$PreserveTimestamps = $false,
                [Hashtable]$OriginalTimestamps = $null
            )

            $tempFilePath = "$FilePath.tmp"
            $originalLfCount = 0
            $originalCrlfCount = 0
            $newLfCount = 0
            $newCrlfCount = 0
            $endingNewlineAdded = $false

            # Check if file originally ends with newline (before any conversion)
            $originallyEndsWithNewline = Test-FileEndsWithNewline -FilePath $FilePath

            # Use pre-captured timestamps if provided, otherwise capture them now
            if ($OriginalTimestamps)
            {
                $originalTimestamps = $OriginalTimestamps
                Write-Verbose "Using pre-captured timestamps for '$FilePath'"
            }
            elseif ($PreserveTimestamps)
            {
                try
                {
                    $fileInfo = Get-Item -Path $FilePath
                    $originalTimestamps = @{
                        CreationTime = $fileInfo.CreationTime
                        LastWriteTime = $fileInfo.LastWriteTime
                    }
                    Write-Verbose "Captured original timestamps for '$FilePath'"
                }
                catch
                {
                    Write-Verbose "Failed to capture timestamps for '$FilePath': $($_.Exception.Message)"
                    $originalTimestamps = $null
                }
            }
            else
            {
                $originalTimestamps = $null
            }

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

                                    # Write line with appropriate ending
                                    $writer.Write($lineBuffer.ToString())
                                    if ($ConvertLineEndings)
                                    {
                                        $writer.Write($TargetLineEnding)
                                        if ($TargetLineEnding -eq "`n")
                                        {
                                            $newLfCount++
                                        }
                                        else
                                        {
                                            $newCrlfCount++
                                        }
                                    }
                                    else
                                    {
                                        # Preserve original CRLF
                                        $writer.Write("`r`n")
                                        $newCrlfCount++
                                    }
                                }
                                else
                                {
                                    # Standalone CR (treat as line ending)
                                    $originalLfCount++

                                    # Write line with appropriate ending
                                    $writer.Write($lineBuffer.ToString())
                                    if ($ConvertLineEndings)
                                    {
                                        $writer.Write($TargetLineEnding)
                                        if ($TargetLineEnding -eq "`n")
                                        {
                                            $newLfCount++
                                        }
                                        else
                                        {
                                            $newCrlfCount++
                                        }
                                    }
                                    else
                                    {
                                        # Preserve original CR
                                        $writer.Write("`r")
                                        $newLfCount++
                                    }
                                }

                                $lineBuffer.Clear() | Out-Null
                            }
                            elseif ($char -eq "`n")
                            {
                                # Standalone LF
                                $originalLfCount++

                                $writer.Write($lineBuffer.ToString())
                                if ($ConvertLineEndings)
                                {
                                    $writer.Write($TargetLineEnding)
                                    if ($TargetLineEnding -eq "`n")
                                    {
                                        $newLfCount++
                                    }
                                    else
                                    {
                                        $newCrlfCount++
                                    }
                                }
                                else
                                {
                                    # Preserve original LF
                                    $writer.Write("`n")
                                    $newLfCount++
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

                    # Add ending newline if requested and file doesn't already end with one
                    if ($EnsureEndingNewline)
                    {
                        # Determine if we need to add an ending newline
                        $needsEndingNewline = $false

                        # If file originally didn't end with newline, we need to add one
                        if (-not $originallyEndsWithNewline)
                        {
                            $needsEndingNewline = $true
                        }
                        # If file originally ended with newline but we have content in buffer,
                        # it means the file didn't end with a line ending after our conversion
                        elseif ($lineBuffer.Length -gt 0)
                        {
                            $needsEndingNewline = $true
                        }

                        if ($needsEndingNewline)
                        {
                            $writer.Write($TargetLineEnding)
                            $endingNewlineAdded = $true

                            # Update counts
                            if ($TargetLineEnding -eq "`n")
                            {
                                $newLfCount++
                            }
                            else
                            {
                                $newCrlfCount++
                            }
                        }
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

                    # Restore original timestamps if preservation was requested and we captured them
                    if ($PreserveTimestamps -and $originalTimestamps)
                    {
                        try
                        {
                            $fileInfo = Get-Item -Path $FilePath
                            $fileInfo.CreationTime = $originalTimestamps.CreationTime
                            $fileInfo.LastWriteTime = $originalTimestamps.LastWriteTime
                            Write-Verbose "Restored original timestamps for '$FilePath'"
                        }
                        catch
                        {
                            Write-Verbose "Failed to restore timestamps for '$FilePath': $($_.Exception.Message)"
                        }
                    }
                }
                else
                {
                    Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue
                    throw 'File is read-only. Use -Force to overwrite read-only files.'
                }

                return [PSCustomObject]@{
                    FilePath = $FilePath
                    LineEnding = if ($TargetLineEnding -eq "`n") { 'LF' } elseif ($TargetLineEnding -eq "`r`n") { 'CRLF' } else { 'Unknown' }
                    OriginalLF = $originalLfCount
                    OriginalCRLF = $originalCrlfCount
                    NewLF = $newLfCount
                    NewCRLF = $newCrlfCount
                    SourceEncoding = $SourceEncoding.EncodingName
                    TargetEncoding = $outputEncoding.EncodingName
                    EncodingChanged = $SourceEncoding.ToString() -ne $outputEncoding.ToString() -or $SourceEncoding.GetPreamble().Length -ne $outputEncoding.GetPreamble().Length
                    EndingNewlineAdded = $endingNewlineAdded
                    Success = $true
                    Error = $null
                    Skipped = $false
                    Converted = $ConvertLineEndings
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
                    LineEnding = if ($TargetLineEnding -eq "`n") { 'LF' } elseif ($TargetLineEnding -eq "`r`n") { 'CRLF' } else { 'Unknown' }
                    OriginalLF = 0
                    OriginalCRLF = 0
                    NewLF = 0
                    NewCRLF = 0
                    SourceEncoding = if ($SourceEncoding) { $SourceEncoding.EncodingName } else { $null }
                    TargetEncoding = if ($outputEncoding) { $outputEncoding.EncodingName } else { $null }
                    EncodingChanged = $false
                    EndingNewlineAdded = $false
                    Success = $false
                    Error = $_.Exception.Message
                    Skipped = $false
                    Converted = $false
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

                # Apply include filters (optimized)
                if ($Include.Count -gt 0)
                {
                    $files = $files | Where-Object {
                        $fileName = $_.Name
                        foreach ($pattern in $Include)
                        {
                            if ($fileName -like $pattern)
                            {
                                return $true
                            }
                        }
                        return $false
                    }
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
                    # Capture original timestamps BEFORE any file analysis to prevent access time changes
                    $originalTimestamps = $null
                    if ($PreserveTimestamps)
                    {
                        try
                        {
                            # Use existing FileInfo object from Get-ChildItem instead of redundant Get-Item call
                            $originalTimestamps = @{
                                CreationTime = $file.CreationTime
                                LastWriteTime = $file.LastWriteTime
                            }
                            Write-Verbose "Captured original timestamps for '$($file.FullName)' before analysis"
                        }
                        catch
                        {
                            Write-Verbose "Failed to capture timestamps for '$($file.FullName)': $($_.Exception.Message)"
                            $originalTimestamps = $null
                        }
                    }

                    # Perform combined file analysis for optimal performance (single file read)
                    $analysis = Get-FileAnalysis -FilePath $file.FullName -TargetLineEnding $targetLineEnding -TargetEncodingName $Encoding -CheckEndingNewline $EnsureEndingNewline.IsPresent

                    if ($analysis.Error)
                    {
                        Write-Warning "Error analyzing file '$($file.FullName)': $($analysis.Error)"
                        continue
                    }

                    if ($analysis.IsBinary)
                    {
                        Write-Warning "Skipping binary file: $($file.FullName)"
                        continue
                    }

                    # Extract analysis results
                    $needsLineEndingConversion = $analysis.NeedsLineEndingConversion
                    $needsEncodingConversion = $analysis.NeedsEncodingConversion
                    $needsEndingNewline = $analysis.NeedsEndingNewline
                    $sourceEncoding = $analysis.SourceEncoding
                    $targetEncoding = if ($needsEncodingConversion) { Get-EncodingFromName -EncodingName $Encoding } else { $null }

                    if ($needsLineEndingConversion -or $needsEncodingConversion -or $needsEndingNewline)
                    {
                        # Determine what needs to be converted
                        $conversionType = @()
                        if ($needsLineEndingConversion) { $conversionType += "line endings to $LineEnding" }
                        if ($needsEncodingConversion) { $conversionType += "encoding to $Encoding" }
                        if ($needsEndingNewline) { $conversionType += 'add ending newline' }
                        $conversionDescription = $conversionType -join ' and '

                        if ($PSCmdlet.ShouldProcess($file.FullName, "Convert $conversionDescription"))
                        {
                            Write-Verbose "Processing file: $($file.FullName)"

                            # Only use target encoding if encoding conversion is needed
                            $actualTargetEncoding = if ($needsEncodingConversion) { $targetEncoding } else { $null }
                            $result = Convert-SingleFileLineEnding -FilePath $file.FullName -TargetLineEnding $targetLineEnding -SourceEncoding $sourceEncoding -TargetEncoding $actualTargetEncoding -ConvertLineEndings $needsLineEndingConversion -EnsureEndingNewline $EnsureEndingNewline.IsPresent -PreserveTimestamps $PreserveTimestamps.IsPresent -OriginalTimestamps $originalTimestamps

                            if ($PassThru)
                            {
                                $null = $processedFiles.Add($result)
                            }

                            if ($result.Success)
                            {
                                $encodingInfo = if ($result.EncodingChanged) { " Encoding: $($result.SourceEncoding)~>$($result.TargetEncoding)" } else { '' }
                                Write-Verbose "Successfully converted '$($file.FullName)' (LF: $($result.OriginalLF)~>$($result.NewLF), CRLF: $($result.OriginalCRLF)~>$($result.NewCRLF))$encodingInfo"
                            }
                            else
                            {
                                Write-Error "Failed to convert '$($file.FullName)': $($result.Error)"
                            }
                        }
                    }
                    else
                    {
                        # Determine the target encoding name for display purposes
                        $targetEncodingName = if ($Encoding -eq 'Auto') { 'Auto' } else { $Encoding }

                        if ($PSCmdlet.ShouldProcess($file.FullName, "Skip file - already has correct line endings ($LineEnding), encoding ($targetEncodingName), and ending newline"))
                        {
                            Write-Verbose "Skipping '$($file.FullName)' - already has correct line endings, encoding, and ending newline"

                            if ($PassThru)
                            {
                                # Return info showing no changes were needed
                                $result = [PSCustomObject]@{
                                    FilePath = $file.FullName
                                    LineEnding = $LineEnding
                                    OriginalLF = if ($LineEnding -eq 'LF') { 1 } else { 0 }
                                    OriginalCRLF = if ($LineEnding -eq 'CRLF') { 1 } else { 0 }
                                    NewLF = if ($LineEnding -eq 'LF') { 1 } else { 0 }
                                    NewCRLF = if ($LineEnding -eq 'CRLF') { 1 } else { 0 }
                                    SourceEncoding = $sourceEncoding.EncodingName
                                    TargetEncoding = $sourceEncoding.EncodingName
                                    EncodingChanged = $false
                                    EndingNewlineAdded = $false
                                    Success = $true
                                    Error = $null
                                    Skipped = $true
                                    Converted = $false
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
                # Capture original timestamps BEFORE any file analysis to prevent access time changes
                $originalTimestamps = $null
                if ($PreserveTimestamps)
                {
                    try
                    {
                        # Use the existing item object instead of redundant Get-Item call
                        $originalTimestamps = @{
                            CreationTime = $item.CreationTime
                            LastWriteTime = $item.LastWriteTime
                        }
                        Write-Verbose "Captured original timestamps for '$resolvedPath' before analysis"
                    }
                    catch
                    {
                        Write-Verbose "Failed to capture timestamps for '$resolvedPath': $($_.Exception.Message)"
                        $originalTimestamps = $null
                    }
                }

                # Perform combined file analysis for optimal performance (single file read)
                $analysis = Get-FileAnalysis -FilePath $resolvedPath -TargetLineEnding $targetLineEnding -TargetEncodingName $Encoding -CheckEndingNewline $EnsureEndingNewline.IsPresent

                if ($analysis.Error)
                {
                    Write-Warning "Error analyzing file '$resolvedPath': $($analysis.Error)"
                    continue
                }

                if ($analysis.IsBinary)
                {
                    Write-Warning "Skipping binary file: $resolvedPath"
                    continue
                }

                # Extract analysis results
                $needsLineEndingConversion = $analysis.NeedsLineEndingConversion
                $needsEncodingConversion = $analysis.NeedsEncodingConversion
                $needsEndingNewline = $analysis.NeedsEndingNewline
                $sourceEncoding = $analysis.SourceEncoding
                $targetEncoding = if ($needsEncodingConversion) { Get-EncodingFromName -EncodingName $Encoding } else { $null }

                if ($needsLineEndingConversion -or $needsEncodingConversion -or $needsEndingNewline)
                {
                    # Determine what needs to be converted
                    $conversionType = @()
                    if ($needsLineEndingConversion) { $conversionType += "line endings to $LineEnding" }
                    if ($needsEncodingConversion) { $conversionType += "encoding to $Encoding" }
                    if ($needsEndingNewline) { $conversionType += 'add ending newline' }
                    $conversionDescription = $conversionType -join ' and '

                    if ($PSCmdlet.ShouldProcess($resolvedPath, "Convert $conversionDescription"))
                    {
                        Write-Verbose "Processing file: $resolvedPath"

                        # Only use target encoding if encoding conversion is needed
                        $actualTargetEncoding = if ($needsEncodingConversion) { $targetEncoding } else { $null }
                        $result = Convert-SingleFileLineEnding -FilePath $resolvedPath -TargetLineEnding $targetLineEnding -SourceEncoding $sourceEncoding -TargetEncoding $actualTargetEncoding -ConvertLineEndings $needsLineEndingConversion -EnsureEndingNewline $EnsureEndingNewline.IsPresent -PreserveTimestamps $PreserveTimestamps.IsPresent -OriginalTimestamps $originalTimestamps

                        if ($PassThru)
                        {
                            $null = $processedFiles.Add($result)
                        }

                        if ($result.Success)
                        {
                            $encodingInfo = if ($result.EncodingChanged) { " Encoding: $($result.SourceEncoding)~>$($result.TargetEncoding)" } else { '' }
                            Write-Verbose "Successfully converted '$resolvedPath' (LF: $($result.OriginalLF)~>$($result.NewLF), CRLF: $($result.OriginalCRLF)~>$($result.NewCRLF))$encodingInfo"
                        }
                        else
                        {
                            Write-Error "Failed to convert '$resolvedPath': $($result.Error)"
                        }
                    }
                }
                else
                {
                    # Determine the target encoding name for display purposes
                    $targetEncodingName = if ($Encoding -eq 'Auto') { 'Auto' } else { $Encoding }

                    if ($PSCmdlet.ShouldProcess($resolvedPath, "Skip file - already has correct line endings ($LineEnding), encoding ($targetEncodingName), and ending newline"))
                    {
                        Write-Verbose "Skipping '$resolvedPath' - already has correct line endings, encoding, and ending newline"

                        if ($PassThru)
                        {
                            # Return info showing no changes were needed
                            $result = [PSCustomObject]@{
                                FilePath = $resolvedPath
                                LineEnding = $LineEnding
                                OriginalLF = if ($LineEnding -eq 'LF') { 1 } else { 0 }
                                OriginalCRLF = if ($LineEnding -eq 'CRLF') { 1 } else { 0 }
                                NewLF = if ($LineEnding -eq 'LF') { 1 } else { 0 }
                                NewCRLF = if ($LineEnding -eq 'CRLF') { 1 } else { 0 }
                                SourceEncoding = $sourceEncoding.EncodingName
                                TargetEncoding = $sourceEncoding.EncodingName
                                EncodingChanged = $false
                                EndingNewlineAdded = $false
                                Success = $true
                                Error = $null
                                Skipped = $true
                                Converted = $false
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
