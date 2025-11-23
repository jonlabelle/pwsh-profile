function Search-FileContent
{
    <#
    .SYNOPSIS
        Searches file contents with advanced features beyond grep.

    .DESCRIPTION
        A powerful cross-platform file search utility that extends beyond standard grep functionality.
        Provides regex pattern matching, context lines, file filtering, colorized output, and
        performance optimizations for searching large codebases.

        Key features beyond grep:
        - Context lines (before/after matches)
        - Colorized and formatted output for readability
        - Multiple path inputs and glob patterns
        - File filtering by extension, size, and modification date
        - Exclude patterns for files and directories
        - Count-only mode for statistics
        - Simple output mode for pipelines and scripting
        - Line number display and match highlighting
        - Recursive directory search with depth control
        - Binary file detection and skipping
        - Performance optimizations for large file sets

        ALIASES:
        The 'grep' and 'search' aliases are created only if they don't already exist.

    .PARAMETER Pattern
        The search pattern. Supports regular expressions by default.
        Use -Literal for exact string matching.

    .PARAMETER Path
        One or more paths to search. Accepts file paths, directory paths, and wildcards.
        If a directory is specified, searches recursively unless -NoRecurse is used.
        Supports pipeline input.

    .PARAMETER Literal
        Treat the Pattern as a literal string instead of a regular expression.
        Special regex characters will be escaped automatically.

    .PARAMETER CaseInsensitive
        Perform case-insensitive pattern matching. By default, matching is case-sensitive.

    .PARAMETER Context
        Number of context lines to show before and after each match.
        Alias: -C

    .PARAMETER Before
        Number of context lines to show before each match.
        Alias: -B

    .PARAMETER After
        Number of context lines to show after each match.
        Alias: -A

    .PARAMETER Include
        File name patterns to include (e.g., '*.ps1', '*.txt').
        Supports multiple patterns as an array.

    .PARAMETER Exclude
        File name patterns to exclude (e.g., '*.log', 'temp*').
        Supports multiple patterns as an array.

    .PARAMETER ExcludeDirectory
        Directory names to exclude from recursive search (e.g., '.git', 'node_modules').
        Supports multiple patterns as an array.

    .PARAMETER MaxDepth
        Maximum directory depth for recursive search. Default is unlimited.

    .PARAMETER MaxFileSize
        Maximum file size to search (in MB). Files larger than this are skipped.
        Default is 100MB.

    .PARAMETER CountOnly
        Only display count of matches per file instead of the actual matches.
        Useful for quickly finding which files contain matches.

    .PARAMETER FilesOnly
        Only display file names that contain matches, not the matches themselves.
        Similar to grep -l.

    .PARAMETER Simple
        Use simple output format suitable for pipelines and scripting.
        Outputs PSCustomObjects instead of formatted text.

    .PARAMETER NoRecurse
        Do not search subdirectories. Only search files in the specified path.

    .PARAMETER NoLineNumber
        Do not display line numbers in the output.

    .EXAMPLE
        PS > Search-FileContent -Pattern 'function' -Path ./Functions

        /Users/jon/Functions/Utils.ps1
        42:function Get-Something {
        58:function Set-Value {

        /Users/jon/Functions/Helper.ps1
        15:function Test-Connection {

        Searches for 'function' in all files within the Functions directory recursively.
        Output is colorized with file paths, line numbers, and highlighted matches.

    .EXAMPLE
        PS > Search-FileContent -Pattern 'TODO' -Path . -Include '*.ps1' -Context 2

        /Users/jon/script.ps1
        18-    # Get user input
        19-    $name = Read-Host 'Name'
        20:    # TODO: Add validation
        21-    $result = Process-Name $name
        22-    return $result

        Searches for 'TODO' in PowerShell files with 2 lines of context before and after.
        Context lines are shown with '-' and matches with ':' after line numbers.

    .EXAMPLE
        PS > Search-FileContent -Pattern 'error' -Path ./logs -CaseInsensitive -CountOnly

        /var/logs/app.log: 23 matches
        /var/logs/system.log: 5 matches
        /var/logs/debug.log: 142 matches

        Case-insensitive search for 'error' showing only match counts per file.

    .EXAMPLE
        PS > Search-FileContent -Pattern '\b\d{3}-\d{4}\b' -Path . -Include '*.txt'

        Searches for phone number patterns (XXX-XXXX) in text files using regex.

    .EXAMPLE
        PS > Get-ChildItem *.cs | Search-FileContent -Pattern 'class\s+\w+' -Simple

        Path                    LineNumber Line                          Match
        ----                    ---------- ----                          -----
        /src/Models/User.cs             12 public class UserModel {      class UserModel
        /src/Models/Product.cs          8  public class ProductModel {   class ProductModel
        /src/Services/Auth.cs           25 internal class AuthService {  class AuthService

        Searches C# files from pipeline for class declarations, outputting PSCustomObjects.
        Perfect for further processing in pipelines or scripts.

    .EXAMPLE
        PS > Search-FileContent -Pattern 'import' -Path ./src -ExcludeDirectory 'node_modules','.git' -FilesOnly

        /src/app.js
        /src/utils/helpers.js
        /src/components/Header.jsx
        /src/services/api.js

        Finds files containing 'import', excluding common directories, showing only filenames.
        Similar to 'grep -l' for quickly identifying which files match.

    .EXAMPLE
        PS > Search-FileContent -Pattern 'password' -Path . -Before 1 -After 3 -Include '*.config'

        Searches config files with 1 line before and 3 lines after each match.

    .EXAMPLE
        PS > Search-FileContent -Pattern 'test' -Path ./src, ./lib, ./tests -Literal

        Searches multiple directories for literal string 'test' (not regex).

    .EXAMPLE
        PS > Search-FileContent -Pattern 'console\.log' -Path ./src -Include '*.ts' -FilesOnly | ForEach-Object { Write-Host "Remove logging in $($_.Path)" }

        Quickly enumerates files that still contain debug logging before promoting a build.

    .OUTPUTS
        PSCustomObject (when -Simple is used)
        Returns objects with properties: Path, LineNumber, Line, Match

        Formatted text (default)
        Colorized output showing file paths, line numbers, and matched content

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Search-FileContent.ps1

        - Binary files are automatically detected and skipped
        - Large files (>100MB by default) are skipped for performance
        - Use -Simple for programmatic processing of results
        - Exclude common directories like .git, node_modules for better performance
        - Context lines are marked with '--' separator in formatted output
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$Pattern,

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 1)]
        [Alias('FullName', 'FilePath', 'PSPath')]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path = (Get-Location),

        [Parameter()]
        [Switch]$Literal,

        [Parameter()]
        [Switch]$CaseInsensitive,

        [Parameter()]
        [Alias('C')]
        [ValidateRange(0, 100)]
        [Int]$Context,

        [Parameter()]
        [Alias('B')]
        [ValidateRange(0, 100)]
        [Int]$Before,

        [Parameter()]
        [Alias('A')]
        [ValidateRange(0, 100)]
        [Int]$After,

        [Parameter()]
        [String[]]$Include,

        [Parameter()]
        [String[]]$Exclude,

        [Parameter()]
        [String[]]$ExcludeDirectory = @('.git', '.svn', 'node_modules'),

        [Parameter()]
        [ValidateRange(1, 100)]
        [Int]$MaxDepth,

        [Parameter()]
        [ValidateRange(1, 10240)]
        [Int]$MaxFileSize = 100,

        [Parameter()]
        [Switch]$CountOnly,

        [Parameter()]
        [Switch]$FilesOnly,

        [Parameter()]
        [Switch]$Simple,

        [Parameter()]
        [Switch]$NoRecurse,

        [Parameter()]
        [Switch]$NoLineNumber
    )

    begin
    {
        Write-Verbose 'Initializing Search-FileContent'

        # Context handling - Context overrides Before/After if specified
        if ($PSBoundParameters.ContainsKey('Context'))
        {
            $Before = $Context
            $After = $Context
        }
        else
        {
            if (-not $PSBoundParameters.ContainsKey('Before')) { $Before = 0 }
            if (-not $PSBoundParameters.ContainsKey('After')) { $After = 0 }
        }

        # Prepare regex options
        $regexOptions = [System.Text.RegularExpressions.RegexOptions]::None
        if ($CaseInsensitive)
        {
            $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        }

        # Escape pattern for literal matching
        $searchPattern = if ($Literal)
        {
            [Regex]::Escape($Pattern)
        }
        else
        {
            $Pattern
        }

        # Compile regex for performance
        try
        {
            $regex = [Regex]::new($searchPattern, $regexOptions)
        }
        catch
        {
            throw "Invalid regex pattern '$Pattern': $($_.Exception.Message)"
        }

        # Maximum file size in bytes
        $maxFileSizeBytes = $MaxFileSize * 1MB

        # Color codes for formatted output (only if not Simple mode)
        if (-not $Simple -and -not $FilesOnly)
        {
            $colorReset = "`e[0m"
            $colorFile = "`e[90m"      # Dark gray for file paths
            $colorLineNum = "`e[90m"   # Dark gray for line numbers
            $colorMatch = "`e[96m"     # Bright cyan for matches
            $colorContext = "`e[90m"   # Gray for context
        }

        # Function to check if file is binary
        function Test-BinaryFile
        {
            param([String]$FilePath)

            try
            {
                # First check file extension for obvious binary files
                $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
                $binaryExtensions = @(
                    # Executables and Libraries
                    '.exe', '.dll', '.so', '.dylib', '.a', '.lib', '.obj', '.o',
                    # Archives
                    '.zip', '.7z', '.rar', '.tar', '.gz', '.bz2', '.xz', '.iso',
                    # Images
                    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.ico', '.webp',
                    # Audio/Video
                    '.mp3', '.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.wav',
                    # Documents
                    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
                    # Other
                    '.pyc', '.class', '.sqlite', '.db'
                )

                if ($binaryExtensions -contains $extension)
                {
                    Write-Verbose "Skipping binary file by extension: $FilePath"
                    return $true
                }

                # Content-based detection using streaming
                $buffer = New-Object byte[] 8192
                $stream = [System.IO.File]::OpenRead($FilePath)
                try
                {
                    $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                    if ($bytesRead -eq 0)
                    {
                        return $false  # Empty file is not binary
                    }

                    # Check for null bytes - if more than 10% are null, likely binary
                    $nullByteCount = 0
                    for ($i = 0; $i -lt $bytesRead; $i++)
                    {
                        if ($buffer[$i] -eq 0)
                        {
                            $nullByteCount++
                        }
                    }

                    if ($nullByteCount -gt ($bytesRead * 0.1))
                    {
                        Write-Verbose "Skipping binary file (null byte ratio): $FilePath"
                        return $true
                    }

                    # Check ratio of printable characters
                    $printableCount = 0
                    for ($i = 0; $i -lt $bytesRead; $i++)
                    {
                        $byte = $buffer[$i]
                        # Count ASCII printable and common whitespace
                        if (($byte -ge 32 -and $byte -le 126) -or $byte -eq 9 -or $byte -eq 10 -or $byte -eq 13)
                        {
                            $printableCount++
                        }
                    }

                    $printableRatio = $printableCount / $bytesRead
                    if ($printableRatio -lt 0.60)
                    {
                        Write-Verbose "Skipping binary file (low printable ratio): $FilePath"
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
                Write-Verbose "Error checking if file is binary: $FilePath"
                return $true  # Assume binary if we can't read it
            }
        }

        # Function to get files to search
        function Get-SearchFile
        {
            param(
                [String]$SearchPath,
                [String[]]$IncludePatterns,
                [String[]]$ExcludePatterns,
                [String[]]$ExcludeDirs,
                [Int]$Depth,
                [Bool]$Recurse
            )

            $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SearchPath)

            # Check if path exists
            if (-not (Test-Path -LiteralPath $resolvedPath))
            {
                Write-Warning "Path not found: $SearchPath"
                return
            }

            $item = Get-Item -LiteralPath $resolvedPath -Force

            if ($item.PSIsContainer)
            {
                # Directory - get files
                $getChildItemParams = @{
                    LiteralPath = $resolvedPath
                    File = $true
                    Force = $true
                    ErrorAction = 'SilentlyContinue'
                }

                if ($Recurse)
                {
                    $getChildItemParams['Recurse'] = $true
                    if ($Depth)
                    {
                        $getChildItemParams['Depth'] = $Depth
                    }
                }

                $files = Get-ChildItem @getChildItemParams

                # Apply include filter
                if ($IncludePatterns)
                {
                    $files = $files | Where-Object {
                        $fileName = $_.Name
                        $shouldInclude = $false
                        foreach ($pattern in $IncludePatterns)
                        {
                            if ($fileName -like $pattern)
                            {
                                $shouldInclude = $true
                                break
                            }
                        }
                        $shouldInclude
                    }
                }

                # Apply exclude filter
                if ($ExcludePatterns)
                {
                    $files = $files | Where-Object {
                        $fileName = $_.Name
                        $shouldExclude = $false
                        foreach ($pattern in $ExcludePatterns)
                        {
                            if ($fileName -like $pattern)
                            {
                                $shouldExclude = $true
                                break
                            }
                        }
                        -not $shouldExclude
                    }
                }

                # Apply directory exclusion
                if ($ExcludeDirs)
                {
                    $files = $files | Where-Object {
                        $filePath = $_.FullName
                        $shouldExclude = $false
                        foreach ($dirPattern in $ExcludeDirs)
                        {
                            if ($filePath -match [Regex]::Escape($dirPattern))
                            {
                                $shouldExclude = $true
                                break
                            }
                        }
                        -not $shouldExclude
                    }
                }

                $files
            }
            else
            {
                # Single file
                $item
            }
        }

        # Function to search a single file
        function Search-SingleFile
        {
            param(
                [System.IO.FileInfo]$File,
                [Regex]$Regex,
                [Int]$BeforeLines,
                [Int]$AfterLines,
                [Int64]$MaxSize
            )

            # Check file size
            if ($File.Length -gt $MaxSize)
            {
                Write-Verbose "Skipping large file ($(($File.Length / 1MB).ToString('F2'))MB): $($File.FullName)"
                return
            }

            # Check if binary
            if (Test-BinaryFile -FilePath $File.FullName)
            {
                Write-Verbose "Skipping binary file: $($File.FullName)"
                return
            }

            try
            {
                # Read all lines for context support
                $lines = [System.IO.File]::ReadAllLines($File.FullName)
                $matchCount = 0
                $results = @()
                $matchedLineNumbers = @()

                for ($i = 0; $i -lt $lines.Count; $i++)
                {
                    $line = $lines[$i]
                    $lineNumber = $i + 1

                    if ($Regex.IsMatch($line))
                    {
                        $matchCount++
                        $matchedLineNumbers += $lineNumber

                        # Store match with context
                        $contextStart = [Math]::Max(0, $i - $BeforeLines)
                        $contextEnd = [Math]::Min($lines.Count - 1, $i + $AfterLines)

                        $contextLines = @()
                        for ($c = $contextStart; $c -le $contextEnd; $c++)
                        {
                            $contextLines += [PSCustomObject]@{
                                LineNumber = $c + 1
                                Content = $lines[$c]
                                IsMatch = ($c -eq $i)
                            }
                        }

                        $results += [PSCustomObject]@{
                            Path = $File.FullName
                            LineNumber = $lineNumber
                            Line = $line
                            Match = $Regex.Match($line).Value
                            Context = $contextLines
                        }
                    }
                }

                # Return file info with results
                [PSCustomObject]@{
                    Path = $File.FullName
                    MatchCount = $matchCount
                    Matches = $results
                }
            }
            catch
            {
                Write-Verbose "Error reading file $($File.FullName): $($_.Exception.Message)"
                return
            }
        }

        # Collection for all files to process
        $allFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    }

    process
    {
        foreach ($pathItem in $Path)
        {
            $files = Get-SearchFile -SearchPath $pathItem `
                -IncludePatterns $Include `
                -ExcludePatterns $Exclude `
                -ExcludeDirs $ExcludeDirectory `
                -Depth $MaxDepth `
                -Recurse (-not $NoRecurse)

            foreach ($file in $files)
            {
                $allFiles.Add($file)
            }
        }
    }

    end
    {
        Write-Verbose "Searching $($allFiles.Count) files for pattern: $Pattern"

        $totalMatches = 0
        $filesWithMatches = 0

        foreach ($file in $allFiles)
        {
            $fileResult = Search-SingleFile -File $file `
                -Regex $regex `
                -BeforeLines $Before `
                -AfterLines $After `
                -MaxSize $maxFileSizeBytes

            if (-not $fileResult -or $fileResult.MatchCount -eq 0)
            {
                continue
            }

            $filesWithMatches++
            $totalMatches += $fileResult.MatchCount

            if ($CountOnly)
            {
                # Show count only
                if ($Simple)
                {
                    [PSCustomObject]@{
                        Path = $fileResult.Path
                        MatchCount = $fileResult.MatchCount
                    }
                }
                else
                {
                    Write-Host "$($colorFile)$($fileResult.Path)$($colorReset): $($fileResult.MatchCount) matches"
                }
            }
            elseif ($FilesOnly)
            {
                # Show filename only
                if ($Simple)
                {
                    [PSCustomObject]@{
                        Path = $fileResult.Path
                    }
                }
                else
                {
                    Write-Host "$($colorFile)$($fileResult.Path)$($colorReset)"
                }
            }
            else
            {
                # Show full results
                if ($Simple)
                {
                    # Output objects for pipeline
                    foreach ($match in $fileResult.Matches)
                    {
                        [PSCustomObject]@{
                            Path = $match.Path
                            LineNumber = $match.LineNumber
                            Line = $match.Line
                            Match = $match.Match
                        }
                    }
                }
                else
                {
                    # Formatted output
                    Write-Host ''
                    Write-Host "$($colorFile)$($fileResult.Path)$($colorReset)"

                    $lastEnd = -1
                    foreach ($match in $fileResult.Matches)
                    {
                        # Add separator if there's a gap in context
                        if ($lastEnd -ne -1 -and $match.Context[0].LineNumber -gt $lastEnd + 1)
                        {
                            Write-Host "$($colorContext)--$($colorReset)"
                        }

                        foreach ($contextLine in $match.Context)
                        {
                            if ($contextLine.IsMatch)
                            {
                                # Highlight the match
                                $highlightedLine = $regex.Replace($contextLine.Content, "$($colorMatch)`$&$($colorReset)")

                                if ($NoLineNumber)
                                {
                                    Write-Host $highlightedLine
                                }
                                else
                                {
                                    Write-Host "$($colorLineNum)$($contextLine.LineNumber):$($colorReset)$highlightedLine"
                                }
                            }
                            else
                            {
                                # Context line
                                if ($NoLineNumber)
                                {
                                    Write-Host "$($colorContext)$($contextLine.Content)$($colorReset)"
                                }
                                else
                                {
                                    Write-Host "$($colorContext)$($contextLine.LineNumber)-$($contextLine.Content)$($colorReset)"
                                }
                            }
                        }

                        $lastEnd = $match.Context[-1].LineNumber
                    }
                }
            }
        }

        if (-not $Simple -and -not $FilesOnly -and -not $CountOnly)
        {
            Write-Verbose "Search complete: $totalMatches matches in $filesWithMatches files"
        }
    }
}

# Create 'grep' alias only if it doesn't already exist
if (-not (Get-Command -Name 'grep' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'grep' alias for Search-FileContent"
        Set-Alias -Name 'grep' -Value 'Search-FileContent' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Search-FileContent: Could not create 'grep' alias: $($_.Exception.Message)"
    }
}

# Create 'search' alias only if it doesn't already exist
if (-not (Get-Command -Name 'search' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'search' alias for Search-FileContent"
        Set-Alias -Name 'search' -Value 'Search-FileContent' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Search-FileContent: Could not create 'search' alias: $($_.Exception.Message)"
    }
}
