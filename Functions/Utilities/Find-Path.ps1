function Find-Path
{
    <#
    .SYNOPSIS
        Cross-platform file and directory finder with advanced filtering (mimics POSIX find).

    .DESCRIPTION
        A powerful cross-platform file search utility that replicates and extends POSIX find functionality.
        By default, provides colorized, formatted output for easy reading. Use -Simple for POSIX-style
        plain output suitable for scripting and pipelines.

        Key features:
        - Recursive directory traversal with depth control
        - Name-based filtering with wildcards and regex
        - Type filtering (files, directories, or both)
        - Size-based filtering with comparison operators
        - Time-based filtering (modified, created, accessed)
        - Permission and attribute filtering (hidden, read-only, system)
        - Empty file/directory detection
        - Formatted output with colors and metadata
        - Simple mode for POSIX compatibility and scripting
        - Cross-platform support (Windows, macOS, Linux)

        ALIASES:
        The 'find' alias is created only if it doesn't already exist.

    .PARAMETER Path
        The starting path(s) for the search. Defaults to current directory.
        Accepts multiple paths and supports wildcards.
        Supports pipeline input.

    .PARAMETER Name
        Filter by name using wildcards (e.g., '*.ps1', 'test*').
        Case-insensitive by default unless -CaseSensitive is used.

    .PARAMETER Pattern
        Filter by name using regular expressions for advanced matching.
        Use with -CaseSensitive for case-sensitive regex matching.

    .PARAMETER Type
        Filter by item type: File, Directory, or All (default).

    .PARAMETER MinDepth
        Minimum directory depth to begin finding items.
        Depth 0 is the starting path, depth 1 is immediate children, etc.

    .PARAMETER MaxDepth
        Maximum directory depth to search.
        Use 0 to search only the starting path.

    .PARAMETER MinSize
        Minimum file size with unit suffix (e.g., '100KB', '5MB', '1GB').
        Supports: B (bytes), KB, MB, GB, TB.

    .PARAMETER MaxSize
        Maximum file size with unit suffix (e.g., '100KB', '5MB', '1GB').

    .PARAMETER NewerThan
        Find items modified after the specified DateTime or TimeSpan.
        Examples: (Get-Date).AddDays(-7), '7d', '2h', '30m'

    .PARAMETER OlderThan
        Find items modified before the specified DateTime or TimeSpan.

    .PARAMETER Empty
        Find empty files (0 bytes) or empty directories (no contents).

    .PARAMETER Hidden
        Include hidden files and directories in results.
        By default, hidden items are excluded.

    .PARAMETER ReadOnly
        Filter for read-only files.

    .PARAMETER System
        Include system files in results (Windows).
        By default, system files are excluded.

    .PARAMETER Exclude
        Exclude paths matching these patterns (e.g., '*.tmp', '.git').
        Supports multiple patterns as an array.

    .PARAMETER ExcludeDirectory
        Directory names to exclude from search (e.g., '.git', 'node_modules').
        Applies to directory basenames, not full paths.

    .PARAMETER CaseSensitive
        Make name and pattern matching case-sensitive.
        By default, matching is case-insensitive.

    .PARAMETER Simple
        Use simple POSIX-style output (just paths, one per line).
        Suitable for piping to other commands or scripting.

    .PARAMETER NoRecurse
        Do not search subdirectories. Only search the specified path(s).

    .EXAMPLE
        PS > Find-Path

        Recursively lists all files and directories in the current directory with formatted output.

    .EXAMPLE
        PS > Find-Path -Path ./src -Name '*.ps1'

        Finds all PowerShell files in the src directory.

    .EXAMPLE
        PS > Find-Path -Type Directory -Empty

        Finds all empty directories recursively from current location.

    .EXAMPLE
        PS > Find-Path -MinSize 10MB -MaxSize 100MB

        Finds files between 10MB and 100MB in size.

    .EXAMPLE
        PS > Find-Path -Name 'test*' -Type File -MaxDepth 2

        Finds files starting with 'test' up to 2 levels deep.

    .EXAMPLE
        PS > Find-Path -NewerThan (Get-Date).AddDays(-7) -Type File

        Finds files modified in the last 7 days.

    .EXAMPLE
        PS > Find-Path -Pattern '^test.*\.ps1$' -CaseSensitive

        Finds files matching a case-sensitive regex pattern.

    .EXAMPLE
        PS > Find-Path -Path . -ExcludeDirectory '.git','node_modules' -Name '*.js'

        Finds JavaScript files while excluding common directories.

    .EXAMPLE
        PS > Find-Path -ReadOnly -Type File

        Finds all read-only files.

    .EXAMPLE
        PS > Find-Path -Simple -Name '*.log' | Remove-Item

        POSIX-style: Finds and deletes all log files (simple output for piping).

    .EXAMPLE
        PS > Find-Path -Path /usr/local/bin -Type File -Simple

        POSIX-style output: Lists all files in /usr/local/bin as plain paths.

    .EXAMPLE
        PS > Find-Path -OlderThan '30d' -MinSize 1GB -Simple

        Finds large files older than 30 days with simple output.

    .OUTPUTS
        PSCustomObject (default formatted output)
        Properties: Name, Type, Size, Modified, Path

        String (when -Simple is used)
        Returns full path strings, one per line (POSIX find behavior)

    .NOTES
        - Time suffixes for NewerThan/OlderThan: d (days), h (hours), m (minutes)
        - Size suffixes: B, KB, MB, GB, TB
        - Use -Simple for scripting and piping to other commands
        - Hidden and system files are excluded by default for cleaner output
        - Supports both PowerShell 5.1 and PowerShell Core 6.2+
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType([PSCustomObject], [String])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [Alias('FullName', 'PSPath')]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path = '.',

        [Parameter()]
        [String]$Name,

        [Parameter()]
        [String]$Pattern,

        [Parameter()]
        [ValidateSet('File', 'Directory', 'All')]
        [String]$Type = 'All',

        [Parameter()]
        [ValidateRange(0, 100)]
        [Int]$MinDepth,

        [Parameter()]
        [ValidateRange(0, 100)]
        [Int]$MaxDepth,

        [Parameter()]
        [ValidatePattern('^\d+(\.\d+)?(B|KB|MB|GB|TB)$')]
        [String]$MinSize,

        [Parameter()]
        [ValidatePattern('^\d+(\.\d+)?(B|KB|MB|GB|TB)$')]
        [String]$MaxSize,

        [Parameter()]
        [Object]$NewerThan,

        [Parameter()]
        [Object]$OlderThan,

        [Parameter()]
        [Switch]$Empty,

        [Parameter()]
        [Switch]$Hidden,

        [Parameter()]
        [Switch]$ReadOnly,

        [Parameter()]
        [Switch]$System,

        [Parameter()]
        [String[]]$Exclude,

        [Parameter()]
        [String[]]$ExcludeDirectory = @('.git', '.svn'),

        [Parameter()]
        [Switch]$CaseSensitive,

        [Parameter()]
        [Switch]$Simple,

        [Parameter()]
        [Switch]$NoRecurse
    )

    begin
    {
        Write-Verbose 'Initializing Find-Path'

        # Helper function to parse size strings
        function ConvertTo-Bytes
        {
            param([String]$SizeString)

            if ($SizeString -match '^(\d+(?:\.\d+)?)(B|KB|MB|GB|TB)$')
            {
                $value = [Double]$Matches[1]
                $unit = $Matches[2]

                switch ($unit)
                {
                    'B' { $value }
                    'KB' { $value * 1KB }
                    'MB' { $value * 1MB }
                    'GB' { $value * 1GB }
                    'TB' { $value * 1TB }
                }
            }
            else
            {
                throw "Invalid size format: $SizeString"
            }
        }

        # Helper function to parse time strings
        function ConvertTo-DateTime
        {
            param([Object]$TimeValue)

            if ($TimeValue -is [DateTime])
            {
                return $TimeValue
            }
            elseif ($TimeValue -is [String])
            {
                # Parse relative time strings like '7d', '2h', '30m'
                if ($TimeValue -match '^(\d+)(d|h|m)$')
                {
                    $value = [Int]$Matches[1]
                    $unit = $Matches[2]

                    $now = Get-Date
                    switch ($unit)
                    {
                        'd' { return $now.AddDays(-$value) }
                        'h' { return $now.AddHours(-$value) }
                        'm' { return $now.AddMinutes(-$value) }
                    }
                }
                else
                {
                    # Try to parse as DateTime string
                    try
                    {
                        return [DateTime]::Parse($TimeValue)
                    }
                    catch
                    {
                        throw "Invalid time format: $TimeValue. Use DateTime, TimeSpan, or format like '7d', '2h', '30m'"
                    }
                }
            }
            elseif ($TimeValue -is [TimeSpan])
            {
                return (Get-Date).Add(-$TimeValue)
            }
            else
            {
                throw "Invalid time type: $($TimeValue.GetType().Name)"
            }
        }

        # Helper function to format file size
        function Format-FileSize
        {
            param([Int64]$Bytes)

            if ($Bytes -eq 0) { return '0 B' }
            elseif ($Bytes -lt 1KB) { return "$Bytes B" }
            elseif ($Bytes -lt 1MB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
            elseif ($Bytes -lt 1GB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
            elseif ($Bytes -lt 1TB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
            else { return '{0:N2} TB' -f ($Bytes / 1TB) }
        }

        # Parse size filters
        $minSizeBytes = if ($MinSize) { ConvertTo-Bytes -SizeString $MinSize } else { $null }
        $maxSizeBytes = if ($MaxSize) { ConvertTo-Bytes -SizeString $MaxSize } else { $null }

        # Parse time filters
        $newerThanDate = if ($NewerThan) { ConvertTo-DateTime -TimeValue $NewerThan } else { $null }
        $olderThanDate = if ($OlderThan) { ConvertTo-DateTime -TimeValue $OlderThan } else { $null }

        # Compile regex pattern if provided
        $regexOptions = if ($CaseSensitive)
        {
            [System.Text.RegularExpressions.RegexOptions]::None
        }
        else
        {
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        }

        $regex = if ($Pattern)
        {
            try
            {
                [Regex]::new($Pattern, $regexOptions)
            }
            catch
            {
                throw "Invalid regex pattern '$Pattern': $($_.Exception.Message)"
            }
        }
        else
        {
            $null
        }

        # Color codes for formatted output (only if not Simple mode)
        if (-not $Simple)
        {
            $colorReset = "`e[0m"
            $colorDirectory = "`e[94m"    # Bright blue for directories
            $colorFile = "`e[0m"           # Default for files
            $colorSize = "`e[90m"          # Gray for size
            $colorDate = "`e[90m"          # Gray for date
            $colorHidden = "`e[2m"         # Dim for hidden
            $colorReadOnly = "`e[93m"      # Yellow for read-only
        }

        # Collection for results
        $results = [System.Collections.Generic.List[Object]]::new()
    }

    process
    {
        foreach ($searchPath in $Path)
        {
            Write-Verbose "Processing path: $searchPath"

            # Resolve path
            $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($searchPath)

            if (-not (Test-Path -LiteralPath $resolvedPath))
            {
                Write-Warning "Path not found: $searchPath"
                continue
            }

            # Build Get-ChildItem parameters
            $getChildItemParams = @{
                LiteralPath = $resolvedPath
                Force = $true
                ErrorAction = 'SilentlyContinue'
            }

            if (-not $NoRecurse)
            {
                $getChildItemParams['Recurse'] = $true
                if ($PSBoundParameters.ContainsKey('MaxDepth'))
                {
                    $getChildItemParams['Depth'] = $MaxDepth
                }
            }

            # Note: We don't use -File or -Directory parameters here because on Windows,
            # Get-ChildItem with -File may not return hidden files even with -Force.
            # Instead, we filter by type manually below.

            # Get items
            $items = Get-ChildItem @getChildItemParams

            # Apply filters
            foreach ($item in $items)
            {
                Write-Verbose "Evaluating: $($item.FullName)"

                # Filter by type (file vs directory)
                # Note: We do this manually instead of using -File/-Directory parameters
                # because on Windows, Get-ChildItem with -File may not return hidden files
                # even when -Force is specified.
                if ($Type -eq 'File' -and $item.PSIsContainer)
                {
                    Write-Verbose "Skipping (directory, want file): $($item.Name)"
                    continue
                }
                elseif ($Type -eq 'Directory' -and -not $item.PSIsContainer)
                {
                    Write-Verbose "Skipping (file, want directory): $($item.Name)"
                    continue
                }

                # Calculate depth relative to search root
                $relativePath = $item.FullName.Substring($resolvedPath.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
                if ([string]::IsNullOrEmpty($relativePath))
                {
                    # Item is the root itself
                    $itemDepth = 0
                }
                else
                {
                    $itemDepth = ($relativePath -split [regex]::Escape([IO.Path]::DirectorySeparatorChar)).Count
                }

                # Apply depth filters
                if ($PSBoundParameters.ContainsKey('MinDepth') -and $itemDepth -lt $MinDepth)
                {
                    Write-Verbose "Skipping (depth $itemDepth < MinDepth $MinDepth): $($item.Name)"
                    continue
                }

                # Name filter (wildcard)
                if ($Name)
                {
                    # Determine if the name contains wildcard characters (* or ?)
                    # Note: We check for actual wildcards, not [ which can be part of literal filenames
                    $hasWildcards = ($Name.IndexOfAny([char[]]@('*', '?')) -ge 0)

                    if ($hasWildcards)
                    {
                        # Use -like for wildcard pattern matching
                        $matchResult = if ($CaseSensitive)
                        {
                            $item.Name -clike $Name
                        }
                        else
                        {
                            $item.Name -like $Name
                        }
                    }
                    else
                    {
                        # Use -eq for exact literal matching (handles [ ] correctly)
                        $matchResult = if ($CaseSensitive)
                        {
                            $item.Name -ceq $Name
                        }
                        else
                        {
                            $item.Name -eq $Name
                        }
                    }

                    if (-not $matchResult)
                    {
                        Write-Verbose "Skipping (name filter): $($item.Name)"
                        continue
                    }
                }

                # Pattern filter (regex)
                if ($regex -and -not $regex.IsMatch($item.Name))
                {
                    Write-Verbose "Skipping (pattern filter): $($item.Name)"
                    continue
                }

                # Exclude filter
                if ($Exclude)
                {
                    $shouldExclude = $false
                    foreach ($excludePattern in $Exclude)
                    {
                        if ($item.Name -like $excludePattern)
                        {
                            $shouldExclude = $true
                            break
                        }
                    }
                    if ($shouldExclude)
                    {
                        Write-Verbose "Skipping (exclude filter): $($item.Name)"
                        continue
                    }
                }

                # Directory exclusion - check if item is in excluded directory or is excluded directory itself
                if ($ExcludeDirectory)
                {
                    $shouldExcludeDir = $false
                    foreach ($excludeDirPattern in $ExcludeDirectory)
                    {
                        # Check if the item itself is an excluded directory
                        if ($item.PSIsContainer -and $item.Name -eq $excludeDirPattern)
                        {
                            $shouldExcludeDir = $true
                            break
                        }
                        # Check if item is inside an excluded directory
                        if ($item.FullName -match [Regex]::Escape([IO.Path]::DirectorySeparatorChar + $excludeDirPattern + [IO.Path]::DirectorySeparatorChar))
                        {
                            $shouldExcludeDir = $true
                            break
                        }
                        # Also check for excluded dir at end of path
                        if ($item.FullName -match [Regex]::Escape([IO.Path]::DirectorySeparatorChar + $excludeDirPattern) + '$')
                        {
                            $shouldExcludeDir = $true
                            break
                        }
                    }
                    if ($shouldExcludeDir)
                    {
                        Write-Verbose "Skipping (exclude directory): $($item.FullName)"
                        continue
                    }
                }

                # Hidden filter (exclude hidden by default unless -Hidden is specified)
                if (-not $Hidden -and $item.Attributes -match 'Hidden')
                {
                    Write-Verbose "Skipping (hidden): $($item.Name)"
                    continue
                }

                # System filter (exclude system by default unless -System is specified)
                if (-not $System -and $item.Attributes -match 'System')
                {
                    Write-Verbose "Skipping (system): $($item.Name)"
                    continue
                }

                # Read-only filter
                if ($ReadOnly -and -not ($item.Attributes -match 'ReadOnly'))
                {
                    Write-Verbose "Skipping (not read-only): $($item.Name)"
                    continue
                }

                # Size filters (files only)
                if (-not $item.PSIsContainer)
                {
                    if ($minSizeBytes -and $item.Length -lt $minSizeBytes)
                    {
                        Write-Verbose "Skipping (size $($item.Length) < $minSizeBytes): $($item.Name)"
                        continue
                    }

                    if ($maxSizeBytes -and $item.Length -gt $maxSizeBytes)
                    {
                        Write-Verbose "Skipping (size $($item.Length) > $maxSizeBytes): $($item.Name)"
                        continue
                    }
                }

                # Empty filter
                if ($Empty)
                {
                    if ($item.PSIsContainer)
                    {
                        # Check if directory is empty
                        $hasContents = Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($hasContents)
                        {
                            Write-Verbose "Skipping (not empty directory): $($item.Name)"
                            continue
                        }
                    }
                    else
                    {
                        # Check if file is empty
                        if ($item.Length -ne 0)
                        {
                            Write-Verbose "Skipping (not empty file): $($item.Name)"
                            continue
                        }
                    }
                }

                # Time filters
                if ($newerThanDate -and $item.LastWriteTime -lt $newerThanDate)
                {
                    Write-Verbose "Skipping (older than filter): $($item.Name)"
                    continue
                }

                if ($olderThanDate -and $item.LastWriteTime -gt $olderThanDate)
                {
                    Write-Verbose "Skipping (newer than filter): $($item.Name)"
                    continue
                }

                # Item passed all filters - add to results
                $results.Add($item)
            }
        }
    }

    end
    {
        Write-Verbose "Found $($results.Count) items"

        # Output results
        if ($Simple)
        {
            # POSIX-style output: just paths
            foreach ($item in $results)
            {
                $item.FullName
            }
        }
        else
        {
            # Formatted output with colors and metadata
            foreach ($item in $results)
            {
                $isHidden = $item.Attributes -match 'Hidden'
                $isReadOnly = $item.Attributes -match 'ReadOnly'

                # Build color prefix
                $colorPrefix = if ($item.PSIsContainer)
                {
                    $colorDirectory
                }
                elseif ($isReadOnly)
                {
                    $colorReadOnly
                }
                elseif ($isHidden)
                {
                    $colorHidden
                }
                else
                {
                    $colorFile
                }

                # Build formatted output
                $typeIndicator = if ($item.PSIsContainer) { 'd' } else { 'f' }
                $sizeFormatted = if ($item.PSIsContainer)
                {
                    '<DIR>'
                }
                else
                {
                    Format-FileSize -Bytes $item.Length
                }

                $dateFormatted = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')

                # Create output object
                [PSCustomObject]@{
                    Type = $typeIndicator
                    Size = $sizeFormatted
                    Modified = $dateFormatted
                    Name = $item.Name
                    Path = $item.FullName
                } | Add-Member -MemberType ScriptMethod -Name ToString -Value {
                    $colorPrefix = if ($this.Type -eq 'd')
                    {
                        "`e[94m"
                    }
                    else
                    {
                        "`e[0m"
                    }
                    $colorSize = "`e[90m"
                    $colorDate = "`e[90m"
                    $colorReset = "`e[0m"

                    '{0}{1}  {2}{3,-12}{4}  {5}{6}{4}  {0}{7}{4}' -f `
                        $colorPrefix,
                    $this.Type,
                    $colorSize,
                    $this.Size,
                    $colorReset,
                    $colorDate,
                    $this.Modified,
                    $this.Path
                } -Force -PassThru
            }
        }

        if (-not $Simple)
        {
            Write-Verbose "Find-Path complete: $($results.Count) items found"
        }
    }
}

# Create 'find' alias only if the native find command doesn't exist
if (-not (Get-Command -Name 'find' -CommandType Application -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'find' alias for Find-Path"
        Set-Alias -Name 'find' -Value 'Find-Path' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Find-Path: Could not create 'find' alias: $($_.Exception.Message)"
    }
}
