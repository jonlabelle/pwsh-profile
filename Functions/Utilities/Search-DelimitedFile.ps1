function Search-DelimitedFile
{
    <#
    .SYNOPSIS
        Searches rows in character-delimited files using one or more column criteria.

    .DESCRIPTION
        Searches CSV, TSV, and other character-delimited files and returns rows whose fields
        match the supplied criteria. Criteria are supplied as a dictionary whose keys are
        column names or zero-based column indexes. Every criterion must match the same row by
        default; use -Any to return a row when at least one criterion matches.

        Regular expressions are used by default. Use -Literal for substring matching without
        regular expression interpretation, and combine -Literal with -Exact to require an
        exact field value. Matching is case-insensitive unless -CaseSensitive is specified.

        Files with headers retain their original column names, which must be non-empty. Duplicate
        header names are made unique by appending numeric suffixes to each duplicate group, such as
        File1 and File2. For files without headers, use -NoHeader to generate Column0, Column1,
        and so on, or use -Header to assign custom names. Use -MatchColumnsOnly to return only the
        columns referenced by the criteria.

        When -Delimiter is omitted, tab is inferred for .tsv and .tab files and comma is used for
        all other files. If the default comma delimiter leaves a tab-containing first record as one
        column, the file is retried as tab-delimited. An explicit delimiter applies to every input
        file and disables delimiter inference.

    .PARAMETER Path
        One or more file paths, directory paths, or wildcard patterns. Paths can also be supplied
        through the pipeline or by property name. Directory searches are non-recursive unless
        -Recurse is specified. Only FileSystem provider paths are supported.
        The default path if not provided is the current working directory.

    .PARAMETER Criteria
        A dictionary that maps column names or zero-based integer column indexes to patterns.
        Column-name lookup is case-insensitive. A criterion value can be one value or an array of
        alternative values. When an array is supplied, any pattern in that array can satisfy that
        column's criterion.

        Use integer keys for index-based criteria, for example @{ 0 = 'Alice'; 2 = '^Open$' }.
        String keys are treated as column names, even when the string contains only digits. When
        file headers are duplicated, use the generated suffixed names, such as File1 and File2, or
        use integer keys.

    .PARAMETER Delimiter
        The character separating fields. When omitted, .tsv and .tab files use a tab and all
        other files use a comma. Supply this parameter for pipe-delimited, semicolon-delimited,
        or other character-delimited formats.

    .PARAMETER Filter
        One or more wildcard file-name patterns used when Path identifies a directory. The
        default patterns are *.csv, *.tsv, and *.tab. Explicit file paths are not restricted
        by Filter.

    .PARAMETER Recurse
        Searches all subdirectories when Path identifies a directory. Directory searches are
        non-recursive by default.

    .PARAMETER Exclude
        Directory-name wildcard patterns to exclude from recursive searches. The default
        exclusions are node_modules and the .git directory. This parameter has no effect unless
        -Recurse is specified.

    .PARAMETER NoHeader
        Indicates that the first record contains data rather than column names. Generated column
        names are zero-based: Column0, Column1, and so on. Cannot be combined with -Header.

    .PARAMETER Header
        Custom column names for a file whose first record contains data. The number of names must
        match the number of fields in the first record. Header names must be non-empty and unique
        case-insensitively. Cannot be combined with -NoHeader.

    .PARAMETER Literal
        Treats every criterion pattern as a literal substring instead of a regular expression.

    .PARAMETER Exact
        Requires an entire field to equal a literal criterion. Requires -Literal.

    .PARAMETER CaseSensitive
        Performs case-sensitive matching. Matching is case-insensitive by default.

    .PARAMETER Any
        Returns a row when any column criterion matches. By default, every criterion must match
        the same row.

    .PARAMETER MatchColumnsOnly
        Returns only the columns referenced by Criteria. Column order follows the input file,
        regardless of the order of keys in the criteria dictionary.

    .PARAMETER IncludeFileName
        Adds a FileName property containing the leaf name of the source file to every result.
        The command rejects this option when an input file already contains a FileName column.

    .PARAMETER IncludeFilePath
        Adds a FilePath property containing the absolute source file path to every result.
        The command rejects this option when an input file already contains a FilePath column.

    .PARAMETER Encoding
        Specifies the input file encoding. The default is UTF8. Accepted values are compatible
        with both Windows PowerShell 5.1 and PowerShell Core. OutputFile writes UTF-8 regardless
        of this setting.

    .PARAMETER OutputFile
        Writes all matching rows to one output file instead of returning them to the pipeline.
        Only the .csv and .json file extensions are supported, and the extension determines the
        serialization format. Existing files are overwritten. JSON output is always an array; CSV
        output is an empty file when no rows match. The output file cannot also be an explicit
        input file, and an existing output file discovered through a directory or wildcard search
        is skipped as input before it is overwritten.

    .EXAMPLE
        PS > Search-DelimitedFile -Path './users.csv' -Criteria @{ Status = '^Active$'; City = '^Boston$' }

        Returns complete rows where both Status and City match the regular expressions.

        Name    Status  Department  City
        ----    ------  ----------  ------
        Alice   Active  Engineering Boston

    .EXAMPLE
        PS > Search-DelimitedFile './users.csv' @{ Name = 'Smith'; Department = 'Sales' } -Literal

        Returns rows where Name contains Smith and Department contains Sales as literal text.

    .EXAMPLE
        PS > Search-DelimitedFile './users.csv' @{ Status = 'Active' } -Literal -Exact -CaseSensitive

        Returns rows whose Status field is exactly Active, including case.

        Name    Status  Department  City
        ----    ------  ----------  -------
        Alice   Active  Engineering Boston
        Bob     Active  Marketing   Seattle

    .EXAMPLE
        PS > Search-DelimitedFile './events.tsv' @{ Level = 'error|critical'; Message = 'timeout' }

        Infers a tab delimiter and returns rows where both regular expressions match.

    .EXAMPLE
        PS > Search-DelimitedFile './data.txt' @{ 0 = '^A'; 2 = 'done' } -Delimiter '|' -NoHeader

        Searches a headerless pipe-delimited file by zero-based column index.

    .EXAMPLE
        PS > Search-DelimitedFile './duplicate-headers.tsv' @{ File1 = 'Before'; File2 = 'After' } -Literal

        Searches a file with duplicate File headers using the generated File1 and File2 column names.

    .EXAMPLE
        PS > Search-DelimitedFile './data.txt' @{ Name = 'Alice'; State = 'NY' } -Delimiter ';' -Header Name,Age,State -Literal

        Applies custom names to a headerless semicolon-delimited file and searches two columns.

    .EXAMPLE
        PS > Search-DelimitedFile './orders.csv' @{ Status = @('Pending', 'Backorder') } -Literal -Exact

        Returns rows whose Status exactly equals either Pending or Backorder.

    .EXAMPLE
        PS > Search-DelimitedFile './audit.csv' @{ User = '^admin'; Action = 'delete' } -Any

        Returns rows where either the User or Action regular expression matches.

        User    Action  Timestamp
        ----    ------  -------------------
        admin   login   2024-01-15 09:12:44
        jsmith  delete  2024-01-15 10:05:22
        admin   delete  2024-01-15 11:33:01

    .EXAMPLE
        PS > Search-DelimitedFile './logs/*.csv' @{ Severity = 'warning|error'; Host = '^web-' } -MatchColumnsOnly

        Searches multiple files and returns only Severity and Host from matching rows.

    .EXAMPLE
        PS > Get-ChildItem './exports/*.csv' | Search-DelimitedFile -Criteria @{ Region = '^West$' } -IncludeFileName

        Accepts file objects through the pipeline and adds the source file name to each result.

    .EXAMPLE
        PS > Search-DelimitedFile './exports/*.csv' @{ Result = '^Failed$' } -IncludeFileName -IncludeFilePath

        Adds both the source file name and absolute file path to each matched row.

    .EXAMPLE
        PS > Search-DelimitedFile './inventory.csv', './inventory-archive.csv' @{ Sku = '^ABC-\d+$' }

        Searches more than one file using the same regular expression criterion.

    .EXAMPLE
        PS > Search-DelimitedFile './exports' @{ Status = '^Active$' } -Recurse -Filter '*.csv', '*.tsv' -IncludeFileName

        Recursively searches CSV and TSV files beneath exports and adds each matching file name.

    .EXAMPLE
        PS > Search-DelimitedFile './logs' @{ 0 = 'error'; 3 = 'timeout' } -Recurse -Filter '*.txt', '*.log' -Delimiter '|' -NoHeader -Literal

        Recursively searches pipe-delimited text and log files by zero-based column index.

    .EXAMPLE
        PS > Search-DelimitedFile './exports' @{ Status = '^Active$' } -Recurse -OutputFile './active-records.csv'

        Writes all matching rows from the directory tree to one CSV file.

    .EXAMPLE
        PS > Search-DelimitedFile './events.tsv' @{ Level = 'error|critical' } -IncludeFileName -OutputFile './events.json'

        Writes matching rows, including their source file name, to a JSON array.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
            A new object containing each matched row, optionally limited to searched columns and
            augmented with source file information. No objects are returned when OutputFile is
            specified.

    .NOTES
        The parser follows Import-Csv quoting rules, including escaped quotes and delimiters inside
        quoted fields. Delimiters are limited to a single character.

        TSV files use tabs as delimiters. Adjacent tabs are valid when they represent empty fields;
        collapse repeated tabs only when you know they are accidental padding, because doing so
        changes column positions.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Search-DelimitedFile.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Search-DelimitedFile.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path = (Get-Location),

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNull()]
        [System.Collections.IDictionary]$Criteria,

        [Parameter()]
        [Char]$Delimiter,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$Filter = @('*.csv', '*.tsv', '*.tab'),

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [String[]]$Exclude = @('.git', 'node_modules'),

        [Parameter()]
        [Switch]$NoHeader,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$Header,

        [Parameter()]
        [Switch]$Literal,

        [Parameter()]
        [Switch]$Exact,

        [Parameter()]
        [Switch]$CaseSensitive,

        [Parameter()]
        [Switch]$Any,

        [Parameter()]
        [Switch]$MatchColumnsOnly,

        [Parameter()]
        [Switch]$IncludeFileName,

        [Parameter()]
        [Switch]$IncludeFilePath,

        [Parameter()]
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Default', 'OEM', 'Unicode', 'UTF7', 'UTF8', 'UTF32')]
        [String]$Encoding = 'UTF8',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias('OutFile')]
        [String]$OutputFile
    )

    begin
    {
        function Get-TextEncoding
        {
            param(
                [Parameter(Mandatory)]
                [String]$Name
            )

            switch ($Name)
            {
                'ASCII' { return [System.Text.Encoding]::ASCII }
                'BigEndianUnicode' { return [System.Text.Encoding]::BigEndianUnicode }
                'Default' { return [System.Text.Encoding]::Default }
                'OEM' { return [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) }
                'Unicode' { return [System.Text.Encoding]::Unicode }
                'UTF7' { return [System.Text.Encoding]::UTF7 }
                'UTF8' { return New-Object System.Text.UTF8Encoding($false) }
                'UTF32' { return [System.Text.Encoding]::UTF32 }
            }
        }

        function Get-FirstRecordFields
        {
            param(
                [Parameter(Mandatory)]
                [String]$FilePath,

                [Parameter(Mandatory)]
                [Char]$FieldDelimiter,

                [Parameter(Mandatory)]
                [System.Text.Encoding]$TextEncoding
            )

            $parser = $null
            try
            {
                $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($FilePath, $TextEncoding, $true)
                $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
                $parser.SetDelimiters(@([String]$FieldDelimiter))
                $parser.HasFieldsEnclosedInQuotes = $true
                $parser.TrimWhiteSpace = $false

                if ($parser.EndOfData)
                {
                    return @()
                }

                return @($parser.ReadFields())
            }
            finally
            {
                if ($null -ne $parser)
                {
                    $parser.Dispose()
                }
            }
        }

        function Test-IsIntegerKey
        {
            param(
                [Parameter(Mandatory)]
                [Object]$Key
            )

            return $Key -is [Byte] -or
            $Key -is [SByte] -or
            $Key -is [Int16] -or
            $Key -is [UInt16] -or
            $Key -is [Int32] -or
            $Key -is [UInt32] -or
            $Key -is [Int64] -or
            $Key -is [UInt64]
        }

        function Resolve-DuplicateColumnNames
        {
            param(
                [Parameter(Mandatory)]
                [String[]]$ColumnNames
            )

            $nameCounts = New-Object 'System.Collections.Generic.Dictionary[String,Int32]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($columnName in $ColumnNames)
            {
                if ($nameCounts.ContainsKey($columnName))
                {
                    $nameCounts[$columnName]++
                }
                else
                {
                    $nameCounts[$columnName] = 1
                }
            }

            $reservedNames = New-Object 'System.Collections.Generic.HashSet[String]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($columnName in $ColumnNames)
            {
                if ($nameCounts[$columnName] -eq 1)
                {
                    [void]$reservedNames.Add($columnName)
                }
            }

            $usedNames = New-Object 'System.Collections.Generic.HashSet[String]' ([StringComparer]::OrdinalIgnoreCase)
            $duplicateIndexes = New-Object 'System.Collections.Generic.Dictionary[String,Int32]' ([StringComparer]::OrdinalIgnoreCase)
            $resolvedColumnNames = New-Object System.Collections.ArrayList

            foreach ($columnName in $ColumnNames)
            {
                if ($nameCounts[$columnName] -eq 1)
                {
                    $candidateName = $columnName
                    $suffix = 1
                    while ($usedNames.Contains($candidateName))
                    {
                        $candidateName = "$columnName$suffix"
                        $suffix++
                    }

                    [void]$usedNames.Add($candidateName)
                    [void]$resolvedColumnNames.Add($candidateName)
                    continue
                }

                if (-not $duplicateIndexes.ContainsKey($columnName))
                {
                    $duplicateIndexes[$columnName] = 0
                }

                do
                {
                    $duplicateIndexes[$columnName]++
                    $candidateName = "$columnName$($duplicateIndexes[$columnName])"
                }
                while ($reservedNames.Contains($candidateName) -or $usedNames.Contains($candidateName))

                [void]$usedNames.Add($candidateName)
                [void]$resolvedColumnNames.Add($candidateName)
            }

            return [String[]]$resolvedColumnNames.ToArray([String])
        }

        function Resolve-SearchCriteria
        {
            param(
                [Parameter(Mandatory)]
                [String[]]$ColumnNames
            )

            $resolved = New-Object System.Collections.ArrayList

            foreach ($entry in $Criteria.GetEnumerator())
            {
                $columnName = $null

                if (Test-IsIntegerKey -Key $entry.Key)
                {
                    $columnIndex = [Int64]$entry.Key
                    if ($columnIndex -lt 0 -or $columnIndex -ge $ColumnNames.Count)
                    {
                        throw "Column index $columnIndex is outside the valid range 0 through $($ColumnNames.Count - 1)."
                    }
                    $columnName = $ColumnNames[$columnIndex]
                }
                else
                {
                    $requestedName = [String]$entry.Key
                    foreach ($candidateName in $ColumnNames)
                    {
                        if ([String]::Equals($candidateName, $requestedName, [StringComparison]::OrdinalIgnoreCase))
                        {
                            $columnName = $candidateName
                            break
                        }
                    }

                    if ($null -eq $columnName)
                    {
                        throw "Column '$requestedName' was not found. Available columns: $($ColumnNames -join ', ')."
                    }
                }

                $patterns = @($entry.Value)
                if ($patterns.Count -eq 0 -or $null -eq $entry.Value)
                {
                    throw "Criterion for column '$columnName' must contain at least one pattern."
                }

                $stringPatterns = New-Object System.Collections.ArrayList
                foreach ($pattern in $patterns)
                {
                    if ($null -eq $pattern)
                    {
                        throw "Criterion for column '$columnName' cannot contain a null pattern."
                    }
                    [void]$stringPatterns.Add([String]$pattern)
                }

                [void]$resolved.Add([PSCustomObject]@{
                        ColumnName = $columnName
                        Patterns = [String[]]$stringPatterns.ToArray()
                    })
            }

            return @($resolved.ToArray())
        }

        function Test-FieldValue
        {
            param(
                [AllowNull()]
                [Object]$Value,

                [Parameter(Mandatory)]
                [String[]]$Patterns
            )

            $text = if ($null -eq $Value) { [String]::Empty } else { [String]$Value }
            $comparison = if ($CaseSensitive) { [StringComparison]::Ordinal } else { [StringComparison]::OrdinalIgnoreCase }
            $regexOptions = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
            if (-not $CaseSensitive)
            {
                $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            }

            foreach ($pattern in $Patterns)
            {
                if ($Literal)
                {
                    if ($Exact -and [String]::Equals($text, $pattern, $comparison))
                    {
                        return $true
                    }
                    if (-not $Exact -and $text.IndexOf($pattern, $comparison) -ge 0)
                    {
                        return $true
                    }
                }
                elseif ([System.Text.RegularExpressions.Regex]::IsMatch($text, $pattern, $regexOptions))
                {
                    return $true
                }
            }

            return $false
        }

        function Test-IsExcludedFile
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileInfo]$File,

                [Parameter(Mandatory)]
                [String]$RootPath
            )

            if (-not $Recurse -or -not $Exclude)
            {
                return $false
            }

            $trimmedRoot = $RootPath.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            )
            $relativeDirectory = $File.DirectoryName.Substring($trimmedRoot.Length)
            $directorySegments = @($relativeDirectory -split '[\\/]' | Where-Object { $_ })

            foreach ($directorySegment in $directorySegments)
            {
                foreach ($excludePattern in $Exclude)
                {
                    if ($directorySegment -like $excludePattern)
                    {
                        return $true
                    }
                }
            }

            return $false
        }

        if ($Criteria.Count -eq 0)
        {
            throw 'Criteria must contain at least one column and pattern.'
        }
        if ($NoHeader -and $PSBoundParameters.ContainsKey('Header'))
        {
            throw 'NoHeader and Header cannot be used together.'
        }
        if ($Exact -and -not $Literal)
        {
            throw 'Exact requires Literal.'
        }

        $writeOutputFile = $PSBoundParameters.ContainsKey('OutputFile')
        $resolvedOutputFile = $null
        $outputFormat = $null
        $outputRecords = New-Object 'System.Collections.Generic.List[Object]'

        if ($writeOutputFile)
        {
            if ([String]::IsNullOrWhiteSpace($OutputFile))
            {
                throw 'OutputFile cannot be empty or whitespace.'
            }

            try
            {
                $resolvedOutputFile = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile.Trim())
            }
            catch
            {
                throw "Invalid OutputFile path '$OutputFile': $($_.Exception.Message)"
            }

            $outputExtension = [System.IO.Path]::GetExtension($resolvedOutputFile).ToLowerInvariant()
            $outputFormat = switch ($outputExtension)
            {
                '.csv' { 'Csv' }
                '.json' { 'Json' }
                default { $null }
            }

            if ($null -eq $outputFormat)
            {
                throw "OutputFile must use a .csv or .json extension: $OutputFile"
            }
            if (Test-Path -LiteralPath $resolvedOutputFile -PathType Container)
            {
                throw "OutputFile points to a directory: $resolvedOutputFile"
            }

            $outputDirectory = Split-Path -Path $resolvedOutputFile -Parent
            if (-not [String]::IsNullOrWhiteSpace($outputDirectory) -and
                -not (Test-Path -LiteralPath $outputDirectory -PathType Container))
            {
                throw "OutputFile directory does not exist: $outputDirectory"
            }
        }

        $criteriaEntries = @($Criteria.GetEnumerator())
        if (-not $Literal)
        {
            foreach ($entry in $criteriaEntries)
            {
                foreach ($pattern in @($entry.Value))
                {
                    if ($null -eq $pattern)
                    {
                        throw "Criterion '$($entry.Key)' cannot contain a null pattern."
                    }

                    try
                    {
                        [void][System.Text.RegularExpressions.Regex]::IsMatch([String]::Empty, [String]$pattern)
                    }
                    catch [System.ArgumentException]
                    {
                        throw "Invalid regular expression for criterion '$($entry.Key)': $($_.Exception.Message)"
                    }
                }
            }
        }

        if ($PSBoundParameters.ContainsKey('Header'))
        {
            $headerNames = New-Object 'System.Collections.Generic.HashSet[String]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($headerName in $Header)
            {
                if ([String]::IsNullOrWhiteSpace($headerName))
                {
                    throw 'Header names cannot be empty or whitespace.'
                }
                if (-not $headerNames.Add($headerName))
                {
                    throw "Header contains the duplicate column name '$headerName'."
                }
            }
        }

        if (-not ('Microsoft.VisualBasic.FileIO.TextFieldParser' -as [Type]))
        {
            try
            {
                Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
            }
            catch
            {
                try
                {
                    Add-Type -AssemblyName Microsoft.VisualBasic.Core -ErrorAction Stop
                }
                catch
                {
                    throw 'Delimited-file header preflight requires the Microsoft.VisualBasic TextFieldParser type, which could not be loaded.'
                }
            }
        }

        $processedFiles = New-Object 'System.Collections.Generic.HashSet[String]' ([StringComparer]::OrdinalIgnoreCase)
        $textEncoding = Get-TextEncoding -Name $Encoding
    }

    process
    {
        foreach ($pathItem in $Path)
        {
            $pathUsesWildcard = [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($pathItem)
            try
            {
                $resolvedPaths = @($PSCmdlet.SessionState.Path.GetResolvedPSPathFromPSPath($pathItem))
            }
            catch
            {
                Write-Error -ErrorRecord $_
                continue
            }

            foreach ($resolvedPath in $resolvedPaths)
            {
                if ($resolvedPath.Provider.Name -ne 'FileSystem')
                {
                    Write-Error "Path '$($resolvedPath.Path)' is not a FileSystem provider path."
                    continue
                }

                $inputPath = $resolvedPath.ProviderPath
                $directoryRoot = $null
                $inputFiles = @()

                if (Test-Path -LiteralPath $inputPath -PathType Leaf)
                {
                    $inputFiles = @(Get-Item -LiteralPath $inputPath -ErrorAction Stop)
                }
                elseif (Test-Path -LiteralPath $inputPath -PathType Container)
                {
                    $directoryRoot = $inputPath
                    foreach ($filterPattern in $Filter)
                    {
                        $childItemParameters = @{
                            LiteralPath = $inputPath
                            Filter = $filterPattern
                            File = $true
                            ErrorAction = 'SilentlyContinue'
                        }
                        if ($Recurse)
                        {
                            $childItemParameters.Recurse = $true
                        }

                        $inputFiles += @(Get-ChildItem @childItemParameters)
                    }
                }
                else
                {
                    Write-Error "Path '$inputPath' is not a file or directory."
                    continue
                }

                foreach ($inputFile in $inputFiles)
                {
                    $filePath = $inputFile.FullName
                    if ($writeOutputFile -and [String]::Equals(
                            [System.IO.Path]::GetFullPath($filePath),
                            [System.IO.Path]::GetFullPath($resolvedOutputFile),
                            [StringComparison]::OrdinalIgnoreCase
                        ))
                    {
                        if ($directoryRoot -or $pathUsesWildcard)
                        {
                            Write-Verbose "Skipping existing output file during input discovery: $filePath"
                            continue
                        }

                        throw "OutputFile cannot also be an explicit input file: $filePath"
                    }
                    if ($directoryRoot -and (Test-IsExcludedFile -File $inputFile -RootPath $directoryRoot))
                    {
                        Write-Verbose "Skipping file in excluded directory: $filePath"
                        continue
                    }
                    if (-not $processedFiles.Add($filePath))
                    {
                        Write-Verbose "Skipping duplicate input file: $filePath"
                        continue
                    }

                    $delimiterWasExplicit = $PSBoundParameters.ContainsKey('Delimiter')
                    $fileDelimiter = if ($delimiterWasExplicit)
                    {
                        $Delimiter
                    }
                    elseif ([System.IO.Path]::GetExtension($filePath) -iin @('.tsv', '.tab'))
                    {
                        [Char]9
                    }
                    else
                    {
                        [Char]','
                    }

                    Write-Verbose "Searching '$filePath' with delimiter '$fileDelimiter'."

                    $importParameters = @{
                        LiteralPath = $filePath
                        Delimiter = $fileDelimiter
                        Encoding = $Encoding
                        ErrorAction = 'Stop'
                    }

                    try
                    {
                        $firstFields = @(Get-FirstRecordFields -FilePath $filePath -FieldDelimiter $fileDelimiter -TextEncoding $textEncoding)
                    }
                    catch
                    {
                        Write-Error "Unable to read the first record from '$filePath': $($_.Exception.Message)"
                        continue
                    }

                    if (-not $delimiterWasExplicit -and
                        $fileDelimiter -ne [Char]9 -and
                        $firstFields.Count -eq 1 -and
                        [String]$firstFields[0] -like "*`t*")
                    {
                        $fileDelimiter = [Char]9
                        $importParameters.Delimiter = $fileDelimiter
                        Write-Verbose "Detected tab-delimited header in '$filePath'; retrying with tab delimiter."

                        try
                        {
                            $firstFields = @(Get-FirstRecordFields -FilePath $filePath -FieldDelimiter $fileDelimiter -TextEncoding $textEncoding)
                        }
                        catch
                        {
                            Write-Error "Unable to read the first record from '$filePath' using the detected tab delimiter: $($_.Exception.Message)"
                            continue
                        }
                    }

                    if ($firstFields.Count -eq 0)
                    {
                        Write-Verbose "Skipping empty file: $filePath"
                        continue
                    }

                    $columnNames = $null
                    $skipFirstImportedRow = $false
                    if ($PSBoundParameters.ContainsKey('Header'))
                    {
                        if ($Header.Count -ne $firstFields.Count)
                        {
                            Write-Error "Header contains $($Header.Count) names, but the first record in '$filePath' contains $($firstFields.Count) fields."
                            continue
                        }
                        $importParameters.Header = $Header
                        $columnNames = [String[]]$Header
                    }
                    elseif ($NoHeader)
                    {
                        $generatedHeader = for ($columnIndex = 0; $columnIndex -lt $firstFields.Count; $columnIndex++)
                        {
                            "Column$columnIndex"
                        }
                        $importParameters.Header = [String[]]$generatedHeader
                        $columnNames = [String[]]$generatedHeader
                    }
                    else
                    {
                        $blankHeaderIndexes = for ($headerIndex = 0; $headerIndex -lt $firstFields.Count; $headerIndex++)
                        {
                            if ([String]::IsNullOrWhiteSpace($firstFields[$headerIndex]))
                            {
                                $headerIndex
                            }
                        }

                        if ($blankHeaderIndexes.Count -gt 0)
                        {
                            Write-Error (
                                "File '$filePath' contains empty column headers at zero-based indexes: $($blankHeaderIndexes -join ', '). " +
                                'Search-DelimitedFile requires non-empty headers when header parsing is enabled. ' +
                                'Re-run the search with -NoHeader and integer Criteria keys to search by zero-based column index.'
                            )
                            continue
                        }

                        $columnNames = Resolve-DuplicateColumnNames -ColumnNames $firstFields
                        for ($headerIndex = 0; $headerIndex -lt $firstFields.Count; $headerIndex++)
                        {
                            if (-not [String]::Equals($firstFields[$headerIndex], $columnNames[$headerIndex], [StringComparison]::Ordinal))
                            {
                                $importParameters.Header = $columnNames
                                $skipFirstImportedRow = $true
                                break
                            }
                        }
                    }

                    try
                    {
                        $resolvedCriteria = @(Resolve-SearchCriteria -ColumnNames $columnNames)
                        $criteriaColumnNames = @($resolvedCriteria | ForEach-Object { $_.ColumnName })
                        $selectedColumns = if ($MatchColumnsOnly)
                        {
                            @($columnNames | Where-Object { $criteriaColumnNames -icontains $_ })
                        }
                        else
                        {
                            $columnNames
                        }

                        if ($IncludeFileName -and $columnNames -icontains 'FileName')
                        {
                            throw "Input file '$filePath' already contains a FileName column. Omit IncludeFileName or rename the input column."
                        }
                        if ($IncludeFilePath -and $columnNames -icontains 'FilePath')
                        {
                            throw "Input file '$filePath' already contains a FilePath column. Omit IncludeFilePath or rename the input column."
                        }
                    }
                    catch
                    {
                        Write-Error -ErrorRecord $_
                        continue
                    }

                    try
                    {
                        $importedRowIndex = 0
                        Import-Csv @importParameters | ForEach-Object {
                            $row = $_
                            $shouldSkipRow = $skipFirstImportedRow -and $importedRowIndex -eq 0
                            $importedRowIndex++

                            if (-not $shouldSkipRow)
                            {
                                $criterionMatches = foreach ($criterion in $resolvedCriteria)
                                {
                                    Test-FieldValue -Value $row.($criterion.ColumnName) -Patterns $criterion.Patterns
                                }

                                $isMatch = if ($Any)
                                {
                                    $criterionMatches -contains $true
                                }
                                else
                                {
                                    $criterionMatches -notcontains $false
                                }

                                if ($isMatch)
                                {
                                    $outputRow = [Ordered]@{}
                                    if ($IncludeFileName)
                                    {
                                        $outputRow.FileName = [System.IO.Path]::GetFileName($filePath)
                                    }
                                    if ($IncludeFilePath)
                                    {
                                        $outputRow.FilePath = $filePath
                                    }
                                    foreach ($columnName in $selectedColumns)
                                    {
                                        $outputRow[$columnName] = $row.$columnName
                                    }

                                    $resultObject = [PSCustomObject]$outputRow
                                    if ($writeOutputFile)
                                    {
                                        $outputRecords.Add($resultObject)
                                    }
                                    else
                                    {
                                        $resultObject
                                    }
                                }
                            }
                        }
                    }
                    catch
                    {
                        Write-Error -ErrorRecord $_
                    }
                }
            }
        }
    }

    end
    {
        if (-not $writeOutputFile)
        {
            return
        }

        try
        {
            $utf8Encoding = New-Object System.Text.UTF8Encoding($false)

            switch ($outputFormat)
            {
                'Json'
                {
                    # Index the generic list explicitly. Windows PowerShell 5.1 can treat the
                    # Object[] returned by ToArray() as one pipeline object in this expression,
                    # causing ConvertTo-Json to serialize array metadata instead of each row.
                    $jsonItems = for ($outputIndex = 0; $outputIndex -lt $outputRecords.Count; $outputIndex++)
                    {
                        $outputRecords[$outputIndex] | ConvertTo-Json -Depth 10
                    }

                    if ($jsonItems.Count -eq 0)
                    {
                        $jsonText = '[]'
                    }
                    else
                    {
                        $jsonText = "[`n$($jsonItems -join ",`n")`n]"
                    }

                    [System.IO.File]::WriteAllText($resolvedOutputFile, $jsonText, $utf8Encoding)
                }
                'Csv'
                {
                    if ($outputRecords.Count -gt 0)
                    {
                        $outputRecords.ToArray() | Export-Csv -LiteralPath $resolvedOutputFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                    }
                    else
                    {
                        [System.IO.File]::WriteAllText($resolvedOutputFile, [String]::Empty, $utf8Encoding)
                    }
                }
            }
        }
        catch
        {
            throw "Unable to write search results to '$resolvedOutputFile': $($_.Exception.Message)"
        }

        Write-Verbose "Wrote $($outputRecords.Count) matching row(s) to '$resolvedOutputFile'."
    }
}
