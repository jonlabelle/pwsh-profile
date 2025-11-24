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
        The 'search' alias is created only if it doesn't already exist in the current environment.

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

    .PARAMETER IncludeCaseVariations
        When enabled with -CaseInsensitive, groups and displays the different case variations
        found for the search pattern. This is useful for identifying naming inconsistencies
        across a codebase (e.g., 'userName', 'UserName', 'USERNAME', 'user_name').

        The output includes:
        - Total unique case variations found
        - Count of each variation
        - Files where each variation appears

        Case patterns detected:
        - ALL CAPS (USERNAME)
        - Title Case (User Name)
        - lowercase (username)
        - First capital (Username)
        - camelCase (userName)
        - PascalCase (UserName)
        - snake_case (user_name)
        - SCREAMING_SNAKE_CASE (USER_NAME)
        - kebab-case (user-name)
        - SCREAMING-KEBAB-CASE (USER-NAME)

        Note: Requires -CaseInsensitive to be enabled. Cannot be used with -CountOnly or -FilesOnly.

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
        PS > Search-FileContent -Pattern 'username' -Path ./src -CaseInsensitive -IncludeCaseVariations

        Case Variations Found: 4 unique patterns

        USERNAME (SCREAMING_SNAKE_CASE) - 12 occurrences
          /src/auth.js (5)
          /src/user.js (7)

        userName (camelCase) - 8 occurrences
          /src/auth.js (3)
          /src/profile.js (5)

        UserName (PascalCase) - 3 occurrences
          /src/models.ts (3)

        user_name (snake_case) - 2 occurrences
          /src/database.py (2)

        Searches for 'username' case-insensitively and shows all case variations found.
        Helps identify naming inconsistencies across different files and coding styles.

    .EXAMPLE
        PS > Search-FileContent -Pattern 'apikey' -Path . -CaseInsensitive -IncludeCaseVariations -Simple

        Variation     CasePattern              Count Files
        ---------     -----------              ----- -----
        API_KEY       SCREAMING_SNAKE_CASE        15 {config.py, settings.py}
        apiKey        camelCase                    8 {app.js, utils.js}
        ApiKey        PascalCase                   2 {Models.cs}

        Simple output mode showing case variations as structured objects for pipeline processing.

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
        [Switch]$NoLineNumber,

        [Parameter()]
        [Switch]$IncludeCaseVariations
    )

    begin
    {
        Write-Verbose 'Initializing Search-FileContent'

        # Validate parameter combinations
        if ($IncludeCaseVariations)
        {
            if (-not $CaseInsensitive)
            {
                throw 'IncludeCaseVariations requires CaseInsensitive to be enabled'
            }
            if ($CountOnly)
            {
                throw 'IncludeCaseVariations cannot be used with CountOnly'
            }
            if ($FilesOnly)
            {
                throw 'IncludeCaseVariations cannot be used with FilesOnly'
            }
        }

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

        # Helper function to detect case pattern of a string
        function Get-CasePattern
        {
            param([String]$Text)

            if ([string]::IsNullOrEmpty($Text))
            {
                return 'Unknown'
            }

            # Helper to check if text contains underscores and is consistent case
            $hasUnderscores = $Text -match '_'
            $hasHyphens = $Text -match '-'
            $hasSpaces = $Text -match '\s'

            # All uppercase
            if ($Text -ceq $Text.ToUpper())
            {
                if ($hasUnderscores)
                {
                    return 'SCREAMING_SNAKE_CASE'
                }
                elseif ($hasHyphens)
                {
                    return 'SCREAMING-KEBAB-CASE'
                }
                elseif ($hasSpaces)
                {
                    return 'ALL CAPS'
                }
                else
                {
                    return 'UPPERCASE'
                }
            }

            # All lowercase
            if ($Text -ceq $Text.ToLower())
            {
                if ($hasUnderscores)
                {
                    return 'snake_case'
                }
                elseif ($hasHyphens)
                {
                    return 'kebab-case'
                }
                elseif ($hasSpaces)
                {
                    return 'lowercase'
                }
                else
                {
                    return 'lowercase'
                }
            }

            # Check for separators (if mixed case with separators)
            if ($hasUnderscores)
            {
                $letters = $Text -replace '_', ''
                if ($letters -and (($letters -ceq $letters.ToLower()) -or ($letters -ceq $letters.ToUpper())))
                {
                    return 'snake_case (mixed)'
                }
            }

            if ($hasHyphens)
            {
                $letters = $Text -replace '-', ''
                if ($letters -and (($letters -ceq $letters.ToLower()) -or ($letters -ceq $letters.ToUpper())))
                {
                    return 'kebab-case (mixed)'
                }
            }

            # Check for camelCase or PascalCase (no spaces/separators, mixed case)
            if (-not $hasSpaces -and -not $hasUnderscores -and -not $hasHyphens)
            {
                # Look for lowercase followed by uppercase
                $hasCamelTransition = $false
                for ($i = 0; $i -lt $Text.Length - 1; $i++)
                {
                    if ([char]::IsLower($Text[$i]) -and [char]::IsUpper($Text[$i + 1]))
                    {
                        $hasCamelTransition = $true
                        break
                    }
                }

                if ($hasCamelTransition)
                {
                    if ([char]::IsUpper($Text[0]))
                    {
                        return 'PascalCase'
                    }
                    else
                    {
                        return 'camelCase'
                    }
                }
            }

            # Check for Title Case (spaces with each word capitalized)
            if ($hasSpaces)
            {
                $words = $Text -split '\s+'
                $allWordsCapitalized = $true
                foreach ($word in $words)
                {
                    if ($word.Length -gt 0 -and [char]::IsLower($word[0]))
                    {
                        $allWordsCapitalized = $false
                        break
                    }
                }

                if ($allWordsCapitalized -and $words.Count -gt 1)
                {
                    return 'Title Case'
                }
            }

            # First letter capitalized only
            if ($Text.Length -gt 0 -and [char]::IsUpper($Text[0]))
            {
                $restLower = $true
                for ($i = 1; $i -lt $Text.Length; $i++)
                {
                    if ([char]::IsUpper($Text[$i]))
                    {
                        $restLower = $false
                        break
                    }
                }

                if ($restLower)
                {
                    return 'First Capital'
                }
            }

            return 'Mixed Case'
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

                        $matchValue = $Regex.Match($line).Value
                        $results += [PSCustomObject]@{
                            Path = $File.FullName
                            LineNumber = $lineNumber
                            Line = $line
                            Match = $matchValue
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
        # Use case-sensitive dictionary for case variations
        $caseVariations = New-Object 'System.Collections.Generic.Dictionary[String,Object]' ([StringComparer]::Ordinal)

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

            # Collect case variations if requested
            if ($IncludeCaseVariations)
            {
                foreach ($match in $fileResult.Matches)
                {
                    $matchText = $match.Match
                    if (-not $caseVariations.ContainsKey($matchText))
                    {
                        $caseVariations[$matchText] = @{
                            CasePattern = Get-CasePattern -Text $matchText
                            Count = 0
                            Files = @{}
                        }
                    }
                    $caseVariations[$matchText].Count++

                    # Track file occurrences
                    if (-not $caseVariations[$matchText].Files.ContainsKey($fileResult.Path))
                    {
                        $caseVariations[$matchText].Files[$fileResult.Path] = 0
                    }
                    $caseVariations[$matchText].Files[$fileResult.Path]++
                }
            }

            # Skip normal output if showing case variations
            if (-not $IncludeCaseVariations)
            {
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
        }

        # Display case variations summary if requested
        if ($IncludeCaseVariations -and $caseVariations.Count -gt 0)
        {
            if ($Simple)
            {
                # Simple output - return objects
                foreach ($variation in ($caseVariations.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending))
                {
                    [PSCustomObject]@{
                        Variation = $variation.Key
                        CasePattern = $variation.Value.CasePattern
                        Count = $variation.Value.Count
                        Files = @($variation.Value.Files.Keys)
                    }
                }
            }
            else
            {
                # Formatted output
                Write-Host ''
                Write-Host "$($colorMatch)Case Variations Found: $($caseVariations.Count) unique patterns$($colorReset)"
                Write-Host ''

                # Sort by count descending
                $sortedVariations = $caseVariations.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending

                foreach ($variation in $sortedVariations)
                {
                    $varText = $variation.Key
                    $varData = $variation.Value
                    $casePattern = $varData.CasePattern
                    $count = $varData.Count

                    Write-Host "$($colorMatch)$varText$($colorReset) ($casePattern) - $count occurrence$(if ($count -ne 1) { 's' })"

                    # Show files where this variation appears
                    $fileEntries = $varData.Files.GetEnumerator() | Sort-Object { $_.Value } -Descending
                    foreach ($fileEntry in $fileEntries)
                    {
                        Write-Host "  $($colorFile)$($fileEntry.Key)$($colorReset) ($($fileEntry.Value))"
                    }
                    Write-Host ''
                }
            }
        }

        if (-not $Simple -and -not $FilesOnly -and -not $CountOnly -and -not $IncludeCaseVariations)
        {
            Write-Verbose "Search complete: $totalMatches matches in $filesWithMatches files"
        }
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
