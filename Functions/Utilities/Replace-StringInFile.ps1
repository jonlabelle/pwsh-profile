function Replace-StringInFile
{
    <#
    .SYNOPSIS
        Finds and replaces text in files.

    .DESCRIPTION
        Cross-platform function that searches for a string pattern in one or more files
        and replaces it with a new string. Supports literal text replacement and regular
        expressions. Can process multiple files and optionally create backups.

        By default, performs case-sensitive literal string replacement. Use -Regex for
        pattern matching and -CaseInsensitive for case-insensitive matching.

        Dependencies:
        - Get-EncodingFromName: Resolves profile encoding names to .NET encoding instances.
        - Get-FileEncoding: Detects source file encoding for preservation/conversion decisions.

        Both dependencies are automatically loaded when needed.

        ALIASES:
        The 'sarep' alias is created only if it doesn't already exist in the current environment.

    .PARAMETER Path
        The path to the file(s) to process. Accepts wildcards and pipeline input.
        Can be a single file, multiple files, or a wildcard pattern.

    .PARAMETER OldString
        The text to search for. By default, this is treated as a literal string.
        Use -Regex to treat this as a regular expression pattern.

    .PARAMETER NewString
        The replacement text. In regex mode, can include capture group references ($1, $2, etc.).

    .PARAMETER Regex
        Treat OldString as a regular expression pattern instead of literal text.

    .PARAMETER CaseInsensitive
        Perform case-insensitive matching. By default, matching is case-sensitive.

        When used with -PreserveCase, the pattern is automatically converted to match variations
        with different separators. For example, 'userName' will match and replace 'USERNAME',
        'user_name', 'user-name', 'UserName', etc., while preserving each match's case pattern.

        When used without -PreserveCase, only alphabetic case is ignored. Separators (underscores,
        hyphens, spaces) must match exactly unless you use a regex pattern with -Regex.

    .PARAMETER PreserveCase
        Preserve the case pattern of the matched text when replacing. This intelligently applies
        the case style of the original text to the replacement text, and automatically matches
        variations across different naming conventions.

        The pattern is automatically converted to be separator-aware. For example, searching for
        'userName' with -PreserveCase will find and replace: 'userName' → 'newName', 'UserName' →
        'NewName', 'USERNAME' → 'NEWNAME', 'user_name' → 'new_name', 'USER_NAME' → 'NEW_NAME',
        'user-name' → 'new-name', 'user name' → 'new name', etc.

        Supported case patterns:
        - ALL CAPS: Converts replacement to uppercase
        - Title Case: Capitalizes first letter of each word
        - lowercase: Converts replacement to lowercase
        - First capital: Capitalizes only the first letter
        - camelCase: First word lowercase, subsequent words capitalized
        - PascalCase: All words capitalized with no separators
        - snake_case: Words separated by underscores, all lowercase
        - SCREAMING_SNAKE_CASE: Words separated by underscores, all uppercase
        - kebab-case: Words separated by hyphens, all lowercase
        - SCREAMING-KEBAB-CASE: Words separated by hyphens, all uppercase

        How it works: The pattern is split into words based on camelCase/PascalCase boundaries or
        existing separators, then reconstructed as a regex that matches any combination of separators
        (spaces, underscores, hyphens) between words. Each match's case pattern is detected and
        applied to the replacement text.

        Note: PreserveCase requires CaseInsensitive to be enabled and cannot be used with Regex mode.

    .PARAMETER Backup
        Create a backup of the original file with a .bak extension before making changes.

    .PARAMETER Encoding
        The file encoding to use when reading and writing files.
        When set to 'Auto' (default), the original file encoding is automatically detected and preserved.

        Valid values:
        - Auto: Automatically detect and preserve original file encoding (default)
        - UTF8: UTF-8 without BOM
        - UTF8BOM: UTF-8 with BOM
        - UTF16LE: UTF-16 Little Endian with BOM
        - UTF16BE: UTF-16 Big Endian with BOM
        - UTF32: UTF-32 Little Endian with BOM
        - UTF32BE: UTF-32 Big Endian with BOM
        - ASCII: 7-bit ASCII encoding
        - ANSI: System default ANSI encoding (code page dependent)

        Default: Auto

    .PARAMETER WhatIf
        Shows what would happen if the command runs without actually making changes.

    .PARAMETER Confirm
        Prompts for confirmation before making changes to each file.

    .EXAMPLE
        PS > Replace-StringInFile -Path config.txt -OldString 'localhost' -NewString '192.168.1.100'

        Replaces all occurrences of 'localhost' with '192.168.1.100' in config.txt.

    .EXAMPLE
        PS > Replace-StringInFile -Path *.cs -OldString 'OldClassName' -NewString 'NewClassName' -Backup

        Replaces 'OldClassName' with 'NewClassName' in all .cs files and creates .bak backups.

    .EXAMPLE
        PS > Replace-StringInFile -Path log.txt -OldString '\d{4}-\d{2}-\d{2}' -NewString 'REDACTED' -Regex

        Uses regex to replace all date patterns (YYYY-MM-DD) with 'REDACTED' in log.txt.

    .EXAMPLE
        PS > Replace-StringInFile -Path app.config -OldString 'DEBUG' -NewString 'RELEASE' -CaseInsensitive

        Replaces 'debug', 'Debug', 'DEBUG', etc. with 'RELEASE' (case-insensitive).

    .EXAMPLE
        PS > $results = Replace-StringInFile -Path config.txt -OldString 'username' -NewString 'accountid' -CaseInsensitive -PreserveCase -WhatIf
        PS > $results.Matches | Format-Table

        Line Column OldValue NewValue  LineContent
        ---- ------ -------- --------  -----------
           1      7 USERNAME ACCOUNTID const USERNAME = 'admin';
           2      5 userName accountid let userName = getUser();
           3      7 username accountid Check username in logs.

        Shows detailed information about what would be replaced without making changes.
        Each match includes Line, Column, OldValue, NewValue, and LineContent.

    .EXAMPLE
        PS > Replace-StringInFile -Path *.txt -OldString 'foo' -NewString 'bar' -WhatIf

        What if: Performing the operation "Replace 3 occurrence(s) of 'foo' with 'bar'" on target "C:\files\test.txt".

        FilePath         : C:\files\test.txt
        MatchCount       : 3
        Matches          : {@{Line=1; Column=10; OldValue=foo; NewValue=bar; LineContent=Example foo text},
                           @{Line=2; Column=5; OldValue=foo; NewValue=bar; LineContent=More foo here},
                           @{Line=4; Column=1; OldValue=foo; NewValue=bar; LineContent=foo at start}}
        ReplacementsMade : False
        BackupCreated    : False
        Encoding         : Unicode (UTF-8)
        Error            :

        Shows what would be replaced in all .txt files without making actual changes.

    .EXAMPLE
        PS > Replace-StringInFile -Path report.txt -OldString '(\d+) apples' -NewString '$1 oranges' -Regex

        Uses regex with capture groups to replace "5 apples" with "5 oranges", etc.

    .EXAMPLE
        PS > $version = (Get-Content package.json -Raw | ConvertFrom-Json).version
        PS > Replace-StringInFile -Path package.json -OldString "\"version\": \"$version\"" -NewString "\"version\": \"2.0.0\""

        Performs an automated version bump in package.json during a release script without pulling in external tooling.

    .EXAMPLE
        PS > Replace-StringInFile -Path code.cs -OldString 'userName' -NewString 'accountId' -CaseInsensitive -PreserveCase

        Replaces all variations of 'userName' while preserving each match's case pattern:
        'userName' → 'accountId'
        'UserName' → 'AccountId'
        'USERNAME' → 'ACCOUNTID'
        'user_name' → 'account_id'
        'USER_NAME' → 'ACCOUNT_ID'
        'user-name' → 'account-id'

        The pattern is automatically converted to match across different naming conventions.

    .EXAMPLE
        PS > Replace-StringInFile -Path app.js -OldString 'username' -NewString 'account id' -CaseInsensitive -PreserveCase

        Preserves camelCase and PascalCase patterns when renaming variables.
        'userName' becomes 'accountId', 'UserName' becomes 'AccountId', 'USERNAME' becomes 'ACCOUNT ID'.

    .EXAMPLE
        PS > Get-ChildItem -Path src -Filter *.cs -Recurse | Replace-StringInFile -OldString 'userName' -NewString 'accountId' -CaseInsensitive -PreserveCase -Backup

        Refactors an entire C# codebase, finding and replacing all variations of 'userName' with 'accountId':
        'userName' → 'accountId'
        'UserName' → 'AccountId'
        'USERNAME' → 'ACCOUNTID'
        'user_name' → 'account_id'
        'USER_NAME' → 'ACCOUNT_ID'

        Automatically handles mixed naming conventions across the codebase while preserving each file's
        case style. Creates backups of all modified files.

    .EXAMPLE
        PS > Replace-StringInFile -Path config.yaml -OldString 'database host' -NewString 'db server' -CaseInsensitive -PreserveCase

        Demonstrates Title Case preservation in configuration files.
        'Database Host' becomes 'Db Server', 'database host' becomes 'db server'.

    .EXAMPLE
        PS > Replace-StringInFile -Path script.py -OldString 'old variable name' -NewString 'new var name' -CaseInsensitive -PreserveCase

        Python variable renaming with snake_case preservation.
        'old_variable_name' stays as 'new_var_name', 'OldVariableName' becomes 'NewVarName'.

    .EXAMPLE
        PS > Replace-StringInFile -Path *.md -OldString 'product name' -NewString 'service name' -CaseInsensitive -PreserveCase -WhatIf

        Preview changes across all markdown files before applying.
        Shows how 'Product Name', 'PRODUCT NAME', 'productName' would be transformed.

    .EXAMPLE
        PS > $files = @('app.js', 'utils.js', 'config.js')
        PS > $results = $files | Replace-StringInFile -OldString 'apikey' -NewString 'api token' -CaseInsensitive -PreserveCase -WhatIf
        PS > $results | Select-Object FilePath, MatchCount, @{N='Matches';E={$_.Matches.Count}}

        FilePath      MatchCount Matches
        --------      ---------- -------
        app.js                 3       3
        utils.js               1       1
        config.js              2       2

        Batch processing multiple files and reviewing match counts.
        'apiKey' ~> 'apiToken', 'APIKey' ~> 'APIToken', 'APIKEY' ~> 'API TOKEN'.

    .EXAMPLE
        PS > Replace-StringInFile -Path database.py -OldString 'user name' -NewString 'account id' -CaseInsensitive -PreserveCase

        Python code refactoring with snake_case preservation.
        'user_name' ~> 'account_id', 'USER_NAME' ~> 'ACCOUNT_ID', 'userName' ~> 'accountId'.

    .EXAMPLE
        PS > Replace-StringInFile -Path styles.css -OldString 'primary color' -NewString 'brand color' -CaseInsensitive -PreserveCase

        CSS variable renaming with kebab-case preservation.
        '--primary-color' ~> '--brand-color', 'PRIMARY-COLOR' ~> 'BRAND-COLOR'.

    .EXAMPLE
        PS > Replace-StringInFile -Path .env -OldString 'database url' -NewString 'db connection' -CaseInsensitive -PreserveCase

        Environment variable renaming with SCREAMING_SNAKE_CASE preservation.
        'DATABASE_URL' ~> 'DB_CONNECTION', 'database_url' ~> 'db_connection'.

    .EXAMPLE
        PS > Replace-StringInFile -Path app.js -OldString 'userName' -NewString 'accountId' -WhatIf | ConvertTo-Json -Depth 3

        {
          "FilePath": "/path/to/app.js",
          "MatchCount": 2,
          "Matches": [
            {
              "Line": 5,
              "Column": 10,
              "OldValue": "userName",
              "NewValue": "accountId",
              "LineContent": "const userName = getUser();"
            },
            {
              "Line": 12,
              "Column": 15,
              "OldValue": "userName",
              "NewValue": "accountId",
              "LineContent": "  return userName.trim();"
            }
          ],
          "ReplacementsMade": false,
          "BackupCreated": false,
          "Encoding": "Unicode (UTF-8)",
          "Error": null
        }

        Export detailed match information as JSON for programmatic processing or CI/CD pipelines.

    .EXAMPLE
        PS > Replace-StringInFile -Path logs/*.log -OldString '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b' -NewString '[REDACTED_EMAIL]' -Regex -Backup

        Anonymizes email addresses in log files using regex pattern matching.

        - john.doe@example.com -> [REDACTED_EMAIL]
        - support@company.org ->  [REDACTED_EMAIL]

        Creates backups of original files before modification.

    .EXAMPLE
        PS > Replace-StringInFile -Path customer_data.csv -OldString '\b\d{3}-\d{3}-\d{4}\b' -NewString 'XXX-XXX-XXXX' -Regex

        Redacts US phone numbers (format: 555-123-4567) in CSV files.
        All phone numbers are replaced with XXX-XXX-XXXX for privacy compliance.

    .EXAMPLE
        PS > Replace-StringInFile -Path application.log -OldString '\b\d{3}-\d{2}-\d{4}\b' -NewString '***-**-****' -Regex -Backup

        Anonymizes US Social Security Numbers (SSN) in application logs.
        Pattern matches XXX-XX-XXXX format and replaces with asterisks.
        Original files are preserved with .bak extension.

    .EXAMPLE
        PS > Replace-StringInFile -Path *.txt -OldString '\b(?:\d{4}[-\s]?){3}\d{4}\b' -NewString '[REDACTED_CC]' -Regex

        Removes credit card numbers from text files.
        Matches formats: 1234567890123456, 1234-5678-9012-3456, 1234 5678 9012 3456
        Useful for sanitizing data before sharing with third parties.

    .EXAMPLE
        PS > Replace-StringInFile -Path debug.log -OldString '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b' -NewString '[IP_ADDRESS]' -Regex

        Anonymizes IPv4 addresses in debug logs.
        192.168.1.100 -> [IP_ADDRESS]
        10.0.0.1 -> [IP_ADDRESS]
        Helps comply with GDPR/privacy requirements when sharing logs.

    .EXAMPLE
        PS > $patterns = @(
        PS >     @{ Pattern = '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'; Replacement = '[EMAIL]' },
        PS >     @{ Pattern = '\b\d{3}-\d{3}-\d{4}\b'; Replacement = '[PHONE]' },
        PS >     @{ Pattern = '\b\d{3}-\d{2}-\d{4}\b'; Replacement = '[SSN]' }
        PS > )
        PS > foreach ($p in $patterns) {
        PS >     Replace-StringInFile -Path sensitive_data.txt -OldString $p.Pattern -NewString $p.Replacement -Regex
        PS > }

        Multi-pass anonymization removing multiple PII types from a single file.
        First pass: emails, second pass: phone numbers, third pass: SSNs.
        Comprehensive data sanitization for compliance purposes.

    .EXAMPLE
        PS > Replace-StringInFile -Path user_dump.json -OldString '"password"\s*:\s*"[^"]*"' -NewString '"password": "[REDACTED]"' -Regex

        Redacts password values from JSON exports while preserving structure.
        "password": "mySecretPass123" -> "password": "[REDACTED]"
        Safe for sharing database dumps or API responses in bug reports.

    .EXAMPLE
        PS > Get-ChildItem ./exports -Filter *.csv | Replace-StringInFile -OldString '\b[A-Z]{2}\d{6,8}\b' -NewString '[ID_REDACTED]' -Regex -WhatIf

        Preview anonymization of government ID numbers across multiple CSV export files.
        Matches patterns like AB123456, CA98765432 (passport/license numbers).
        Use -WhatIf to verify patterns before making changes.

    .OUTPUTS
        PSCustomObject with details about each file processed, including:
        - FilePath: Full path to the file
        - FileName: Name of the file
        - MatchCount: Number of matches found
        - Matches: Array of match details (Line, Column, OldValue, NewValue, LineContent)
        - ReplacementsMade: Whether replacements were actually performed
        - BackupCreated: Whether a backup was created
        - Encoding: The encoding used (detected or specified)
        - Error: Any error that occurred during processing

    .NOTES
        - Always test with -WhatIf first when processing multiple files
        - Use -Backup to preserve original files
        - Binary files are automatically skipped
        - In regex mode, remember to escape special characters like . * + ? etc.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Replace-StringInFile.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Replace-StringInFile.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [Alias('FullName', 'FilePath')]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNull()]
        [String]$OldString,

        [Parameter(Mandatory, Position = 2)]
        [AllowEmptyString()]
        [String]$NewString,

        [Parameter()]
        [Switch]$Regex,

        [Parameter()]
        [Switch]$CaseInsensitive,

        [Parameter()]
        [Switch]$PreserveCase,

        [Parameter()]
        [Switch]$Backup,

        [Parameter()]
        [ValidateSet('Auto', 'UTF8', 'UTF8BOM', 'UTF16LE', 'UTF16BE', 'UTF32', 'UTF32BE', 'ASCII', 'ANSI')]
        [String]$Encoding = 'Auto'
    )

    begin
    {
        Write-Verbose 'Starting Replace-StringInFile'

        # Helper function to load dependencies on demand
        function Import-DependencyIfNeeded
        {
            param(
                [Parameter(Mandatory)]
                [String]$FunctionName,

                [Parameter(Mandatory)]
                [String]$RelativePath
            )

            if (-not (Get-Command -Name $FunctionName -ErrorAction Ignore))
            {
                Write-Verbose "$FunctionName is required - attempting to load it"

                # Resolve path from current script location
                $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath $RelativePath
                $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)

                if (Test-Path -Path $dependencyPath -PathType Leaf)
                {
                    return $dependencyPath
                }
                else
                {
                    throw "Required function '$FunctionName' could not be found. Expected location: $dependencyPath"
                }
            }
            else
            {
                Write-Verbose "$FunctionName is already loaded"
                return $null
            }
        }

        $dependencyPath = Import-DependencyIfNeeded -FunctionName 'Get-EncodingFromName' -RelativePath 'Get-EncodingFromName.ps1'
        if ($dependencyPath)
        {
            try
            {
                . $dependencyPath
                Write-Verbose "Loaded Get-EncodingFromName from: $dependencyPath"
            }
            catch
            {
                throw "Failed to load required dependency 'Get-EncodingFromName' from '$dependencyPath': $($_.Exception.Message)"
            }
        }

        $dependencyPath = Import-DependencyIfNeeded -FunctionName 'Get-FileEncoding' -RelativePath 'Get-FileEncoding.ps1'
        if ($dependencyPath)
        {
            try
            {
                . $dependencyPath
                Write-Verbose "Loaded Get-FileEncoding from: $dependencyPath"
            }
            catch
            {
                throw "Failed to load required dependency 'Get-FileEncoding' from '$dependencyPath': $($_.Exception.Message)"
            }
        }

        # Helper function to convert a pattern to separator-aware regex
        function Convert-ToSeparatorAwarePattern
        {
            param([String]$Pattern)

            # Split pattern into words based on camelCase, PascalCase, or existing separators
            $words = @()
            $currentWord = ''

            for ($i = 0; $i -lt $Pattern.Length; $i++)
            {
                $char = $Pattern[$i]

                # Check if this is a separator
                if ($char -match '[\s_-]')
                {
                    if ($currentWord.Length -gt 0)
                    {
                        $words += $currentWord
                        $currentWord = ''
                    }
                    continue
                }

                # Check for camelCase/PascalCase boundary (lowercase followed by uppercase)
                if ($i -gt 0 -and
                    [char]::IsLower($Pattern[$i - 1]) -and
                    [char]::IsUpper($char))
                {
                    $words += $currentWord
                    $currentWord = $char
                }
                # Check for acronym boundary (multiple uppercase followed by lowercase)
                elseif ($i -gt 1 -and
                    [char]::IsUpper($Pattern[$i - 2]) -and
                    [char]::IsUpper($Pattern[$i - 1]) -and
                    [char]::IsLower($char))
                {
                    # Move last char of previous word to current word
                    $lastChar = $currentWord[$currentWord.Length - 1]
                    $currentWord = $currentWord.Substring(0, $currentWord.Length - 1)
                    if ($currentWord.Length -gt 0)
                    {
                        $words += $currentWord
                    }
                    $currentWord = $lastChar + $char
                }
                else
                {
                    $currentWord += $char
                }
            }

            # Add the last word
            if ($currentWord.Length -gt 0)
            {
                $words += $currentWord
            }

            # If no words were detected, treat entire pattern as single word
            if ($words.Count -eq 0)
            {
                $words = @($Pattern)
            }

            # Build regex pattern with optional separators between words
            $escapedWords = $words | ForEach-Object { [Regex]::Escape($_) }
            $regexPattern = $escapedWords -join '[\s_-]*'

            Write-Verbose "Converted pattern '$Pattern' to separator-aware regex: '$regexPattern'"
            Write-Verbose "Detected words: $($words -join ', ')"

            return $regexPattern
        }

        # Helper function to detect case pattern
        function Get-CasePattern
        {
            param([String]$Text)

            if ([string]::IsNullOrEmpty($Text))
            {
                return 'Unknown'
            }

            $hasUnderscores = $Text -match '_'
            $hasHyphens = $Text -match '-'
            $hasSpaces = $Text -match '\s'

            # All uppercase
            if ($Text -ceq $Text.ToUpper())
            {
                if ($hasUnderscores) { return 'SCREAMING_SNAKE_CASE' }
                elseif ($hasHyphens) { return 'SCREAMING-KEBAB-CASE' }
                elseif ($hasSpaces) { return 'ALL CAPS' }
                else { return 'UPPERCASE' }
            }

            # All lowercase
            if ($Text -ceq $Text.ToLower())
            {
                if ($hasUnderscores) { return 'snake_case' }
                elseif ($hasHyphens) { return 'kebab-case' }
                elseif ($hasSpaces) { return 'lowercase' }
                else { return 'lowercase' }
            }

            # Check for camelCase or PascalCase
            if (-not $hasSpaces -and -not $hasUnderscores -and -not $hasHyphens)
            {
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
                    if ([char]::IsUpper($Text[0])) { return 'PascalCase' }
                    else { return 'camelCase' }
                }
            }

            # Check for Title Case
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
                if ($allWordsCapitalized -and $words.Count -gt 1) { return 'Title Case' }
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
                if ($restLower) { return 'First Capital' }
            }

            return 'Mixed Case'
        }

        # Validate parameter combinations
        if ($PreserveCase -and $Regex)
        {
            throw 'PreserveCase cannot be used with Regex mode'
        }
        if ($PreserveCase -and -not $CaseInsensitive)
        {
            throw 'PreserveCase requires CaseInsensitive to be enabled'
        }

        # Build regex options
        $regexOptions = [System.Text.RegularExpressions.RegexOptions]::None
        if ($CaseInsensitive)
        {
            $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        }

        # If not using regex mode, escape the pattern for literal matching or convert to separator-aware
        $searchPattern = if ($PreserveCase)
        {
            # For preserve case, automatically convert to separator-aware pattern
            Convert-ToSeparatorAwarePattern -Pattern $OldString
        }
        elseif ($Regex)
        {
            $OldString
        }
        else
        {
            [regex]::Escape($OldString)
        }

        try
        {
            # Compile once and reuse across all files.
            $searchRegex = [regex]::new($searchPattern, $regexOptions)
        }
        catch
        {
            throw "Invalid search pattern '$OldString': $($_.Exception.Message)"
        }

        Write-Verbose "Search pattern: $searchPattern"
        Write-Verbose "Replacement: $NewString"
        Write-Verbose "Regex mode: $Regex"
        Write-Verbose "Case insensitive: $CaseInsensitive"
        Write-Verbose "Preserve case: $PreserveCase"
        Write-Verbose "Encoding: $Encoding"
    }

    process
    {
        foreach ($filePath in $Path)
        {
            try
            {
                # Resolve wildcards and relative paths
                $resolvedPaths = Resolve-Path -Path $filePath -ErrorAction Stop

                foreach ($resolvedPath in $resolvedPaths)
                {
                    $file = Get-Item -Path $resolvedPath.Path -ErrorAction Stop

                    # Skip directories
                    if ($file.PSIsContainer)
                    {
                        Write-Verbose "Skipping directory: $($file.FullName)"
                        continue
                    }

                    Write-Verbose "Processing file: $($file.FullName)"

                    # Always auto-detect the source encoding for reading
                    $sourceEncoding = Get-FileEncoding -FilePath $file.FullName
                    Write-Verbose "Detected source encoding: $($sourceEncoding.EncodingName) (BOM: $($sourceEncoding.GetPreamble().Length -gt 0))"

                    # Determine target encoding for writing
                    $targetEncoding = if ($Encoding -eq 'Auto')
                    {
                        # Use the same encoding as source
                        $sourceEncoding
                    }
                    else
                    {
                        # Use the explicitly specified encoding
                        $explicitEncoding = Get-EncodingFromName -EncodingName $Encoding
                        Write-Verbose "Target encoding specified: $Encoding"
                        $explicitEncoding
                    }

                    # Check if file is binary (encoding-aware)
                    try
                    {
                        # Skip binary detection for known text encodings with null bytes (UTF-16, UTF-32)
                        $encodingType = $sourceEncoding.GetType().Name
                        $isBinary = $false

                        if ($encodingType -notmatch 'Unicode|UTF32')
                        {
                            # For UTF-8, ASCII, and other encodings, check for excessive null bytes
                            # PowerShell 5.1 uses -Encoding Byte, PowerShell Core 6+ uses -AsByteStream
                            if ($PSVersionTable.PSVersion.Major -ge 6)
                            {
                                $testBytes = Get-Content -Path $file.FullName -AsByteStream -TotalCount 8000 -ErrorAction Stop
                            }
                            else
                            {
                                $testBytes = Get-Content -Path $file.FullName -Encoding Byte -TotalCount 8000 -ErrorAction Stop
                            }

                            $nullBytes = 0
                            foreach ($testByte in $testBytes)
                            {
                                if ($testByte -eq 0)
                                {
                                    $nullBytes++
                                }
                            }
                            # Allow a small number of null bytes, but flag as binary if > 1% are null
                            if ($testBytes.Count -gt 0 -and $nullBytes -gt ($testBytes.Count * 0.01))
                            {
                                $isBinary = $true
                            }
                        }
                        else
                        {
                            Write-Verbose "Skipping binary check for $encodingType encoding (null bytes are normal)"
                        }

                        if ($isBinary)
                        {
                            Write-Warning "Skipping binary file: $($file.FullName)"
                            continue
                        }
                    }
                    catch
                    {
                        Write-Warning "Unable to read file: $($file.FullName) - $($_.Exception.Message)"
                        continue
                    }

                    # Read file content using detected or specified encoding
                    try
                    {
                        # Always read file using the source encoding
                        $fileBytes = [System.IO.File]::ReadAllBytes($file.FullName)
                        $content = $sourceEncoding.GetString($fileBytes)
                    }
                    catch
                    {
                        Write-Warning "Failed to read file: $($file.FullName) - $($_.Exception.Message)"
                        continue
                    }

                    # Perform replacement
                    $replacementCount = 0
                    $newContent = $null
                    $matchDetails = [System.Collections.Generic.List[object]]::new()

                    try
                    {
                        # Handle empty or null content
                        if ([string]::IsNullOrEmpty($content))
                        {
                            $replacementCount = 0
                        }
                        else
                        {
                            $regexMatches = $searchRegex.Matches($content)
                            $replacementCount = $regexMatches.Count

                            if ($replacementCount -gt 0)
                            {
                                # Precompute line starts once and reuse for all matches.
                                $lineStartIndices = [System.Collections.Generic.List[int]]::new()
                                $lineStartIndices.Add(0)
                                foreach ($newlineMatch in [regex]::Matches($content, "`r`n|`n|`r"))
                                {
                                    $lineStartIndices.Add([int]($newlineMatch.Index + $newlineMatch.Length))
                                }

                                $lineStartArray = $lineStartIndices.ToArray()
                                $lines = [regex]::Split($content, "`r`n|`n|`r")

                                # Calculate line and column numbers for each match
                                foreach ($match in $regexMatches)
                                {
                                    # Locate the line by binary-searching the nearest line start
                                    # index that is <= match index.
                                    $lineStartLookup = [System.Array]::BinarySearch($lineStartArray, [int]$match.Index)
                                    $lineIndex = if ($lineStartLookup -ge 0)
                                    {
                                        $lineStartLookup
                                    }
                                    else
                                    {
                                        (-bnot $lineStartLookup) - 1
                                    }

                                    if ($lineIndex -lt 0)
                                    {
                                        $lineIndex = 0
                                    }

                                    $lineNumber = $lineIndex + 1
                                    $columnNumber = ($match.Index - $lineStartArray[$lineIndex]) + 1
                                    $lineContent = if ($lineIndex -lt $lines.Count) { $lines[$lineIndex] } else { '' }

                                    # Calculate replacement value (respecting PreserveCase if enabled)
                                    $replacementValue = $NewString
                                    if ($PreserveCase)
                                    {
                                        $matchedText = $match.Value

                                        # Helper function to detect camelCase/PascalCase patterns
                                        function Test-CamelCase
                                        {
                                            param([string]$text)

                                            # Must have at least one lowercase followed by uppercase
                                            # and no spaces, underscores, or hyphens
                                            if ($text -match '[\s_-]')
                                            {
                                                return $false
                                            }

                                            # Check for transitions between lowercase and uppercase
                                            for ($i = 0; $i -lt $text.Length - 1; $i++)
                                            {
                                                $current = $text[$i]
                                                $next = $text[$i + 1]

                                                if ([char]::IsLower($current) -and [char]::IsUpper($next))
                                                {
                                                    return $true
                                                }
                                            }

                                            return $false
                                        }

                                        # Helper function to detect snake_case pattern
                                        function Test-SnakeCase
                                        {
                                            param([string]$text)

                                            # Must contain underscores and be all lowercase or all uppercase
                                            if ($text -notmatch '_')
                                            {
                                                return $false
                                            }

                                            # Check if all letters are same case (excluding underscores)
                                            $letters = $text -replace '_', ''
                                            return ($letters -ceq $letters.ToLower()) -or ($letters -ceq $letters.ToUpper())
                                        }

                                        # Helper function to detect kebab-case pattern
                                        function Test-KebabCase
                                        {
                                            param([string]$text)

                                            # Must contain hyphens and be all lowercase or all uppercase
                                            if ($text -notmatch '-')
                                            {
                                                return $false
                                            }

                                            # Check if all letters are same case (excluding hyphens)
                                            $letters = $text -replace '-', ''
                                            return ($letters -ceq $letters.ToLower()) -or ($letters -ceq $letters.ToUpper())
                                        }

                                        function ConvertTo-CamelCase
                                        {
                                            param([string]$text, [bool]$pascalCase)

                                            # Split on spaces, underscores, hyphens, or case transitions
                                            $words = @()
                                            $currentWord = ''

                                            for ($i = 0; $i -lt $text.Length; $i++)
                                            {
                                                $char = $text[$i]

                                                if ($char -match '[\s_-]')
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                        $currentWord = ''
                                                    }
                                                }
                                                elseif ($i -gt 0 -and [char]::IsUpper($char) -and [char]::IsLower($text[$i - 1]))
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                    }
                                                    $currentWord = [string]$char
                                                }
                                                else
                                                {
                                                    $currentWord += $char
                                                }
                                            }

                                            if ($currentWord)
                                            {
                                                $words += $currentWord
                                            }

                                            # If we got a single word (no separators found), return it as-is in the requested case
                                            if ($words.Count -eq 1)
                                            {
                                                $word = $words[0].ToLower()
                                                if ($pascalCase)
                                                {
                                                    return $word.Substring(0, 1).ToUpper() + $(if ($word.Length -gt 1) { $word.Substring(1) } else { '' })
                                                }
                                                else
                                                {
                                                    return $word
                                                }
                                            }

                                            # Build camelCase or PascalCase
                                            $result = ''
                                            for ($i = 0; $i -lt $words.Count; $i++)
                                            {
                                                $word = $words[$i].ToLower()
                                                if ($word.Length -eq 0) { continue }

                                                if ($i -eq 0)
                                                {
                                                    if ($pascalCase)
                                                    {
                                                        $result += $word.Substring(0, 1).ToUpper() + $(if ($word.Length -gt 1) { $word.Substring(1) } else { '' })
                                                    }
                                                    else
                                                    {
                                                        $result += $word
                                                    }
                                                }
                                                else
                                                {
                                                    $result += $word.Substring(0, 1).ToUpper() + $(if ($word.Length -gt 1) { $word.Substring(1) } else { '' })
                                                }
                                            }

                                            return $result
                                        }

                                        function ConvertTo-SnakeCase
                                        {
                                            param([string]$text, [bool]$uppercase)

                                            # Split on spaces, hyphens, underscores, or case transitions
                                            $words = @()
                                            $currentWord = ''

                                            for ($i = 0; $i -lt $text.Length; $i++)
                                            {
                                                $char = $text[$i]

                                                if ($char -match '[\s_-]')
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                        $currentWord = ''
                                                    }
                                                }
                                                elseif ($i -gt 0 -and [char]::IsUpper($char) -and [char]::IsLower($text[$i - 1]))
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                    }
                                                    $currentWord = [string]$char
                                                }
                                                else
                                                {
                                                    $currentWord += $char
                                                }
                                            }

                                            if ($currentWord)
                                            {
                                                $words += $currentWord
                                            }

                                            # Join with underscores
                                            $result = ($words | ForEach-Object { $_.ToLower() }) -join '_'

                                            if ($uppercase)
                                            {
                                                return $result.ToUpper()
                                            }

                                            return $result
                                        }

                                        function ConvertTo-KebabCase
                                        {
                                            param([string]$text, [bool]$uppercase)

                                            # Split on spaces, hyphens, underscores, or case transitions
                                            $words = @()
                                            $currentWord = ''

                                            for ($i = 0; $i -lt $text.Length; $i++)
                                            {
                                                $char = $text[$i]

                                                if ($char -match '[\s_-]')
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                        $currentWord = ''
                                                    }
                                                }
                                                elseif ($i -gt 0 -and [char]::IsUpper($char) -and [char]::IsLower($text[$i - 1]))
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                    }
                                                    $currentWord = [string]$char
                                                }
                                                else
                                                {
                                                    $currentWord += $char
                                                }
                                            }

                                            if ($currentWord)
                                            {
                                                $words += $currentWord
                                            }

                                            # Join with hyphens
                                            $result = ($words | ForEach-Object { $_.ToLower() }) -join '-'

                                            if ($uppercase)
                                            {
                                                return $result.ToUpper()
                                            }

                                            return $result
                                        }

                                        # Helper to detect separator type in matched text
                                        function Get-Separator
                                        {
                                            param([string]$text)

                                            if ($text -match '_') { return '_' }
                                            if ($text -match '-') { return '-' }
                                            if ($text -match '\s') { return ' ' }
                                            return $null
                                        }

                                        # Determine the case pattern of the matched text
                                        $separator = Get-Separator -text $matchedText

                                        if ($matchedText -ceq $matchedText.ToUpper())
                                        {
                                            # ALL CAPS - check for separators
                                            if ($separator -eq '_')
                                            {
                                                $replacementValue = ConvertTo-SnakeCase -text $NewString -uppercase $true
                                            }
                                            elseif ($separator -eq '-')
                                            {
                                                $replacementValue = ConvertTo-KebabCase -text $NewString -uppercase $true
                                            }
                                            elseif ($separator -eq ' ')
                                            {
                                                # Space-separated uppercase - split camelCase/PascalCase first
                                                $words = @()
                                                $currentWord = ''
                                                for ($i = 0; $i -lt $NewString.Length; $i++)
                                                {
                                                    $char = $NewString[$i]
                                                    if ($char -match '[\s_-]')
                                                    {
                                                        if ($currentWord) { $words += $currentWord; $currentWord = '' }
                                                    }
                                                    elseif ($i -gt 0 -and [char]::IsUpper($char) -and [char]::IsLower($NewString[$i - 1]))
                                                    {
                                                        if ($currentWord) { $words += $currentWord }
                                                        $currentWord = [string]$char
                                                    }
                                                    else { $currentWord += $char }
                                                }
                                                if ($currentWord) { $words += $currentWord }
                                                $replacementValue = ($words | ForEach-Object { $_.ToUpper() }) -join ' '
                                            }
                                            else
                                            {
                                                $replacementValue = $NewString.ToUpper()
                                            }
                                        }
                                        elseif ($matchedText -ceq $matchedText.ToLower())
                                        {
                                            # all lowercase - check for separators
                                            if ($separator -eq '_')
                                            {
                                                $replacementValue = ConvertTo-SnakeCase -text $NewString -uppercase $false
                                            }
                                            elseif ($separator -eq '-')
                                            {
                                                $replacementValue = ConvertTo-KebabCase -text $NewString -uppercase $false
                                            }
                                            elseif ($separator -eq ' ')
                                            {
                                                # Space-separated lowercase - split camelCase/PascalCase first
                                                $words = @()
                                                $currentWord = ''
                                                for ($i = 0; $i -lt $NewString.Length; $i++)
                                                {
                                                    $char = $NewString[$i]
                                                    if ($char -match '[\s_-]')
                                                    {
                                                        if ($currentWord) { $words += $currentWord; $currentWord = '' }
                                                    }
                                                    elseif ($i -gt 0 -and [char]::IsUpper($char) -and [char]::IsLower($NewString[$i - 1]))
                                                    {
                                                        if ($currentWord) { $words += $currentWord }
                                                        $currentWord = [string]$char
                                                    }
                                                    else { $currentWord += $char }
                                                }
                                                if ($currentWord) { $words += $currentWord }
                                                $replacementValue = ($words | ForEach-Object { $_.ToLower() }) -join ' '
                                            }
                                            else
                                            {
                                                $replacementValue = $NewString.ToLower()
                                            }
                                        }
                                        elseif (Test-SnakeCase -text $matchedText)
                                        {
                                            # snake_case (mixed case with underscores - rare but possible)
                                            $replacementValue = ConvertTo-SnakeCase -text $NewString -uppercase $false
                                        }
                                        elseif (Test-KebabCase -text $matchedText)
                                        {
                                            # kebab-case (mixed case with hyphens - rare but possible)
                                            $replacementValue = ConvertTo-KebabCase -text $NewString -uppercase $false
                                        }
                                        elseif (Test-CamelCase -text $matchedText)
                                        {
                                            # camelCase or PascalCase
                                            $isPascalCase = [char]::IsUpper($matchedText[0])
                                            $replacementValue = ConvertTo-CamelCase -text $NewString -pascalCase $isPascalCase
                                        }
                                        elseif ($matchedText[0] -ceq [char]::ToUpper($matchedText[0]))
                                        {
                                            # Check if it's Title Case (each word capitalized)
                                            $words = $matchedText -split '\s+'
                                            $isTitleCase = $true
                                            foreach ($word in $words)
                                            {
                                                if ($word.Length -gt 0 -and $word[0] -cne [char]::ToUpper($word[0]))
                                                {
                                                    $isTitleCase = $false
                                                    break
                                                }
                                            }

                                            if ($isTitleCase -and $words.Count -gt 1)
                                            {
                                                # Title Case - capitalize first letter of each word
                                                $replacementWords = $NewString -split '\s+'
                                                $titleCased = @()
                                                foreach ($word in $replacementWords)
                                                {
                                                    if ($word.Length -gt 0)
                                                    {
                                                        $titleCased += $word.Substring(0, 1).ToUpper() + $word.Substring(1).ToLower()
                                                    }
                                                }
                                                $replacementValue = $titleCased -join ' '
                                            }
                                            else
                                            {
                                                # First letter capitalized only
                                                $replacementValue = $NewString.Substring(0, 1).ToUpper() + $NewString.Substring(1).ToLower()
                                            }
                                        }
                                        else
                                        {
                                            # Mixed case or other - use replacement as-is
                                            $replacementValue = $NewString
                                        }
                                    }

                                    # Store match details
                                    $matchDetails.Add([PSCustomObject]@{
                                        Line = $lineNumber
                                        Column = $columnNumber
                                        OldValue = $match.Value
                                        NewValue = $replacementValue
                                        LineContent = $lineContent
                                    })
                                }

                                if ($PreserveCase)
                                {
                                    # Use MatchEvaluator to preserve case for each match
                                    $matchEvaluator = {
                                        param($match)
                                        $matchedText = $match.Value
                                        $replacement = $NewString

                                        # Helper function to detect camelCase/PascalCase patterns
                                        function Test-CamelCase
                                        {
                                            param([string]$text)

                                            # Must have at least one lowercase followed by uppercase
                                            # and no spaces, underscores, or hyphens
                                            if ($text -match '[\s_-]')
                                            {
                                                return $false
                                            }

                                            # Check for transitions between lowercase and uppercase
                                            for ($i = 0; $i -lt $text.Length - 1; $i++)
                                            {
                                                $current = $text[$i]
                                                $next = $text[$i + 1]

                                                if ([char]::IsLower($current) -and [char]::IsUpper($next))
                                                {
                                                    return $true
                                                }
                                            }

                                            return $false
                                        }

                                        # Helper function to detect snake_case pattern
                                        function Test-SnakeCase
                                        {
                                            param([string]$text)

                                            # Must contain underscores and be all lowercase or all uppercase
                                            if ($text -notmatch '_')
                                            {
                                                return $false
                                            }

                                            # Check if all letters are same case (excluding underscores)
                                            $letters = $text -replace '_', ''
                                            return ($letters -ceq $letters.ToLower()) -or ($letters -ceq $letters.ToUpper())
                                        }

                                        # Helper function to detect kebab-case pattern
                                        function Test-KebabCase
                                        {
                                            param([string]$text)

                                            # Must contain hyphens and be all lowercase or all uppercase
                                            if ($text -notmatch '-')
                                            {
                                                return $false
                                            }

                                            # Check if all letters are same case (excluding hyphens)
                                            $letters = $text -replace '-', ''
                                            return ($letters -ceq $letters.ToLower()) -or ($letters -ceq $letters.ToUpper())
                                        }

                                        function ConvertTo-CamelCase
                                        {
                                            param([string]$text, [bool]$pascalCase)

                                            # Split on spaces, underscores, hyphens, or case transitions
                                            $words = @()
                                            $currentWord = ''

                                            for ($i = 0; $i -lt $text.Length; $i++)
                                            {
                                                $char = $text[$i]

                                                if ($char -match '[\s_-]')
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                        $currentWord = ''
                                                    }
                                                }
                                                elseif ($i -gt 0 -and [char]::IsUpper($char) -and [char]::IsLower($text[$i - 1]))
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                    }
                                                    $currentWord = [string]$char
                                                }
                                                else
                                                {
                                                    $currentWord += $char
                                                }
                                            }

                                            if ($currentWord)
                                            {
                                                $words += $currentWord
                                            }

                                            # If we got a single word (no separators found), return it as-is in the requested case
                                            if ($words.Count -eq 1)
                                            {
                                                $word = $words[0].ToLower()
                                                if ($pascalCase)
                                                {
                                                    return $word.Substring(0, 1).ToUpper() + $(if ($word.Length -gt 1) { $word.Substring(1) } else { '' })
                                                }
                                                else
                                                {
                                                    return $word
                                                }
                                            }

                                            # Build camelCase or PascalCase
                                            $result = ''
                                            for ($i = 0; $i -lt $words.Count; $i++)
                                            {
                                                $word = $words[$i].ToLower()
                                                if ($word.Length -eq 0) { continue }

                                                if ($i -eq 0)
                                                {
                                                    if ($pascalCase)
                                                    {
                                                        $result += $word.Substring(0, 1).ToUpper() + $(if ($word.Length -gt 1) { $word.Substring(1) } else { '' })
                                                    }
                                                    else
                                                    {
                                                        $result += $word
                                                    }
                                                }
                                                else
                                                {
                                                    $result += $word.Substring(0, 1).ToUpper() + $(if ($word.Length -gt 1) { $word.Substring(1) } else { '' })
                                                }
                                            }

                                            return $result
                                        }

                                        function ConvertTo-SnakeCase
                                        {
                                            param([string]$text, [bool]$uppercase)

                                            # Split on spaces, hyphens, underscores, or case transitions
                                            $words = @()
                                            $currentWord = ''

                                            for ($i = 0; $i -lt $text.Length; $i++)
                                            {
                                                $char = $text[$i]

                                                if ($char -match '[\s_-]')
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                        $currentWord = ''
                                                    }
                                                }
                                                elseif ($i -gt 0 -and [char]::IsUpper($char) -and [char]::IsLower($text[$i - 1]))
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                    }
                                                    $currentWord = [string]$char
                                                }
                                                else
                                                {
                                                    $currentWord += $char
                                                }
                                            }

                                            if ($currentWord)
                                            {
                                                $words += $currentWord
                                            }

                                            # Join with underscores
                                            $result = ($words | ForEach-Object { $_.ToLower() }) -join '_'

                                            if ($uppercase)
                                            {
                                                return $result.ToUpper()
                                            }

                                            return $result
                                        }

                                        function ConvertTo-KebabCase
                                        {
                                            param([string]$text, [bool]$uppercase)

                                            # Split on spaces, hyphens, underscores, or case transitions
                                            $words = @()
                                            $currentWord = ''

                                            for ($i = 0; $i -lt $text.Length; $i++)
                                            {
                                                $char = $text[$i]

                                                if ($char -match '[\s_-]')
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                        $currentWord = ''
                                                    }
                                                }
                                                elseif ($i -gt 0 -and [char]::IsUpper($char) -and [char]::IsLower($text[$i - 1]))
                                                {
                                                    if ($currentWord)
                                                    {
                                                        $words += $currentWord
                                                    }
                                                    $currentWord = [string]$char
                                                }
                                                else
                                                {
                                                    $currentWord += $char
                                                }
                                            }

                                            if ($currentWord)
                                            {
                                                $words += $currentWord
                                            }

                                            # Join with hyphens
                                            $result = ($words | ForEach-Object { $_.ToLower() }) -join '-'

                                            if ($uppercase)
                                            {
                                                return $result.ToUpper()
                                            }

                                            return $result
                                        }

                                        # Helper to detect separator type in matched text
                                        function Get-Separator
                                        {
                                            param([string]$text)

                                            if ($text -match '_') { return '_' }
                                            if ($text -match '-') { return '-' }
                                            if ($text -match '\s') { return ' ' }
                                            return $null
                                        }

                                        # Determine the case pattern of the matched text
                                        $separator = Get-Separator -text $matchedText

                                        if ($matchedText -ceq $matchedText.ToUpper())
                                        {
                                            # ALL CAPS - check for separators
                                            if ($separator -eq '_')
                                            {
                                                return ConvertTo-SnakeCase -text $replacement -uppercase $true
                                            }
                                            elseif ($separator -eq '-')
                                            {
                                                return ConvertTo-KebabCase -text $replacement -uppercase $true
                                            }
                                            elseif ($separator -eq ' ')
                                            {
                                                # Space-separated uppercase - split camelCase/PascalCase first
                                                $words = @()
                                                $currentWord = ''
                                                for ($i = 0; $i -lt $replacement.Length; $i++)
                                                {
                                                    $char = $replacement[$i]
                                                    if ($char -match '[\s_-]')
                                                    {
                                                        if ($currentWord) { $words += $currentWord; $currentWord = '' }
                                                    }
                                                    elseif ($i -gt 0 -and [char]::IsUpper($char) -and [char]::IsLower($replacement[$i - 1]))
                                                    {
                                                        if ($currentWord) { $words += $currentWord }
                                                        $currentWord = [string]$char
                                                    }
                                                    else { $currentWord += $char }
                                                }
                                                if ($currentWord) { $words += $currentWord }
                                                return ($words | ForEach-Object { $_.ToUpper() }) -join ' '
                                            }
                                            else
                                            {
                                                return $replacement.ToUpper()
                                            }
                                        }
                                        elseif ($matchedText -ceq $matchedText.ToLower())
                                        {
                                            # all lowercase - check for separators
                                            if ($separator -eq '_')
                                            {
                                                return ConvertTo-SnakeCase -text $replacement -uppercase $false
                                            }
                                            elseif ($separator -eq '-')
                                            {
                                                return ConvertTo-KebabCase -text $replacement -uppercase $false
                                            }
                                            elseif ($separator -eq ' ')
                                            {
                                                # Space-separated lowercase - split camelCase/PascalCase first
                                                $words = @()
                                                $currentWord = ''
                                                for ($i = 0; $i -lt $replacement.Length; $i++)
                                                {
                                                    $char = $replacement[$i]
                                                    if ($char -match '[\s_-]')
                                                    {
                                                        if ($currentWord) { $words += $currentWord; $currentWord = '' }
                                                    }
                                                    elseif ($i -gt 0 -and [char]::IsUpper($char) -and [char]::IsLower($replacement[$i - 1]))
                                                    {
                                                        if ($currentWord) { $words += $currentWord }
                                                        $currentWord = [string]$char
                                                    }
                                                    else { $currentWord += $char }
                                                }
                                                if ($currentWord) { $words += $currentWord }
                                                return ($words | ForEach-Object { $_.ToLower() }) -join ' '
                                            }
                                            else
                                            {
                                                return $replacement.ToLower()
                                            }
                                        }
                                        elseif (Test-SnakeCase -text $matchedText)
                                        {
                                            # snake_case (mixed case with underscores - rare but possible)
                                            return ConvertTo-SnakeCase -text $replacement -uppercase $false
                                        }
                                        elseif (Test-KebabCase -text $matchedText)
                                        {
                                            # kebab-case (mixed case with hyphens - rare but possible)
                                            return ConvertTo-KebabCase -text $replacement -uppercase $false
                                        }
                                        elseif (Test-CamelCase -text $matchedText)
                                        {
                                            # camelCase or PascalCase
                                            $isPascalCase = [char]::IsUpper($matchedText[0])
                                            return ConvertTo-CamelCase -text $replacement -pascalCase $isPascalCase
                                        }
                                        elseif ($matchedText[0] -ceq [char]::ToUpper($matchedText[0]))
                                        {
                                            # Check if it's Title Case (each word capitalized)
                                            $words = $matchedText -split '\s+'
                                            $isTitleCase = $true
                                            foreach ($word in $words)
                                            {
                                                if ($word.Length -gt 0 -and $word[0] -cne [char]::ToUpper($word[0]))
                                                {
                                                    $isTitleCase = $false
                                                    break
                                                }
                                            }

                                            if ($isTitleCase -and $words.Count -gt 1)
                                            {
                                                # Title Case - capitalize first letter of each word
                                                $replacementWords = $replacement -split '\s+'
                                                $titleCased = @()
                                                foreach ($word in $replacementWords)
                                                {
                                                    if ($word.Length -gt 0)
                                                    {
                                                        $titleCased += $word.Substring(0, 1).ToUpper() + $word.Substring(1).ToLower()
                                                    }
                                                }
                                                return $titleCased -join ' '
                                            }
                                            else
                                            {
                                                # First letter capitalized only
                                                return $replacement.Substring(0, 1).ToUpper() + $replacement.Substring(1).ToLower()
                                            }
                                        }
                                        else
                                        {
                                            # Mixed case or other - use replacement as-is
                                            return $replacement
                                        }
                                    }

                                    $newContent = $searchRegex.Replace($content, $matchEvaluator)
                                }
                                else
                                {
                                    $newContent = $searchRegex.Replace($content, $NewString)
                                }
                            }
                        }
                    }
                    catch
                    {
                        Write-Error "Regex error in file $($file.FullName): $($_.Exception.Message)"
                        continue
                    }

                    # Create result object
                    $result = [PSCustomObject]@{
                        FilePath = $file.FullName
                        FileName = $file.Name
                        MatchCount = $replacementCount
                        Matches = @($matchDetails)
                        ReplacementsMade = $false
                        BackupCreated = $false
                        Encoding = if ($Encoding -eq 'Auto') { $sourceEncoding.EncodingName } else { $Encoding }
                        Error = $null
                    }

                    # If no matches found, skip this file
                    if ($replacementCount -eq 0)
                    {
                        Write-Verbose "No matches found in: $($file.FullName)"
                        $result
                        continue
                    }

                    # Process changes if matches found
                    if ($PSCmdlet.ShouldProcess($file.FullName, "Replace $replacementCount occurrence(s) of '$OldString' with '$NewString'"))
                    {
                        # Create backup if requested
                        if ($Backup)
                        {
                            $backupPath = "$($file.FullName).bak"
                            try
                            {
                                Copy-Item -Path $file.FullName -Destination $backupPath -Force -ErrorAction Stop
                                $result.BackupCreated = $true
                                Write-Verbose "Created backup: $backupPath"
                            }
                            catch
                            {
                                Write-Error "Failed to create backup for $($file.FullName): $($_.Exception.Message)"
                                $result.Error = "Backup failed: $($_.Exception.Message)"
                                $result
                                continue
                            }
                        }

                        # Write new content using the same encoding
                        try
                        {
                            # Convert string content to bytes using the target encoding
                            $preamble = $targetEncoding.GetPreamble()
                            $contentBytes = $targetEncoding.GetBytes($newContent)

                            # Combine preamble (BOM) and content bytes
                            if ($preamble.Length -gt 0)
                            {
                                $newBytes = New-Object byte[] ($preamble.Length + $contentBytes.Length)
                                [Array]::Copy($preamble, 0, $newBytes, 0, $preamble.Length)
                                [Array]::Copy($contentBytes, 0, $newBytes, $preamble.Length, $contentBytes.Length)
                            }
                            else
                            {
                                $newBytes = $contentBytes
                            }

                            [System.IO.File]::WriteAllBytes($file.FullName, $newBytes)
                            $result.ReplacementsMade = $true
                            Write-Verbose "Replaced $replacementCount occurrence(s) in: $($file.FullName)"
                        }
                        catch
                        {
                            Write-Error "Failed to write file $($file.FullName): $($_.Exception.Message)"
                            $result.Error = "Write failed: $($_.Exception.Message)"
                        }
                    }

                    $result
                }
            }
            catch
            {
                Write-Error "Failed to process path '$filePath': $($_.Exception.Message)"
            }
        }
    }

    end
    {
        Write-Verbose 'Replace-StringInFile completed'
    }
}

# Create 'sarep' alias only if it doesn't already exist
if (-not (Get-Command -Name 'sarep' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'sarep' alias for Replace-StringInFile"
        Set-Alias -Name 'sarep' -Value 'Replace-StringInFile' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Replace-StringInFile: Could not create 'sarep' alias: $($_.Exception.Message)"
    }
}
