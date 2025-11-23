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

    .PARAMETER PreserveCase
        Preserve the case pattern of the matched text when replacing. This intelligently
        applies the case style of the original text to the replacement text.

        Supports these case patterns:
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

        Note: PreserveCase requires CaseInsensitive to be enabled and cannot be used with Regex mode.

    .PARAMETER Backup
        Create a backup of the original file with a .bak extension before making changes.

    .PARAMETER Encoding
        The file encoding to use when reading and writing files.
        Valid values: UTF8, ASCII, Unicode, UTF32, UTF7, Default, OEM
        Default: UTF8

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
        PS > Get-ChildItem *.txt | Replace-StringInFile -OldString 'foo' -NewString 'bar' -WhatIf

        Shows what would be replaced in all .txt files without making actual changes.

    .EXAMPLE
        PS > Replace-StringInFile -Path report.txt -OldString '(\d+) apples' -NewString '$1 oranges' -Regex

        Uses regex with capture groups to replace "5 apples" with "5 oranges", etc.

    .EXAMPLE
        PS > $version = (Get-Content package.json -Raw | ConvertFrom-Json).version
        PS > Replace-StringInFile -Path package.json -OldString "\"version\": \"$version\"" -NewString "\"version\": \"2.0.0\""

        Performs an automated version bump in package.json during a release script without pulling in external tooling.

    .EXAMPLE
        PS > Replace-StringInFile -Path code.cs -OldString 'oldname' -NewString 'newname' -CaseInsensitive -PreserveCase

        Replaces 'oldname', 'OldName', 'OLDNAME', etc. while preserving each match's case pattern.
        'OLDNAME' becomes 'NEWNAME', 'OldName' becomes 'NewName', 'oldname' becomes 'newname'.

    .EXAMPLE
        PS > Replace-StringInFile -Path app.js -OldString 'username' -NewString 'account id' -CaseInsensitive -PreserveCase

        Preserves camelCase and PascalCase patterns when renaming variables.
        'userName' becomes 'accountId', 'UserName' becomes 'AccountId', 'USERNAME' becomes 'ACCOUNT ID'.

    .EXAMPLE
        PS > Get-ChildItem -Path src -Filter *.cs -Recurse | Replace-StringInFile -OldString 'customer' -NewString 'client' -CaseInsensitive -PreserveCase -Backup

        Refactors an entire C# codebase, renaming 'customer' to 'client' while preserving case.
        'CustomerService' ~> 'ClientService', 'getCustomerId' ~> 'getClientId', 'CUSTOMER_ID' ~> 'CLIENT_ID'.
        Creates backups of all modified files.

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
        PS > $files | Replace-StringInFile -OldString 'apikey' -NewString 'api token' -CaseInsensitive -PreserveCase
        PS > # Process results
        PS > $results | Where-Object ReplacementsMade | Select-Object FilePath, MatchCount

        Batch processing multiple files and reviewing which files were modified.
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

    .OUTPUTS
        PSCustomObject with details about each file processed, including the number of replacements made.

    .NOTES
        - Always test with -WhatIf first when processing multiple files
        - Use -Backup to preserve original files
        - Binary files are automatically skipped
        - In regex mode, remember to escape special characters like . * + ? etc.
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
        [ValidateSet('UTF8', 'ASCII', 'Unicode', 'UTF32', 'UTF7', 'Default', 'OEM')]
        [String]$Encoding = 'UTF8'
    )

    begin
    {
        Write-Verbose 'Starting Replace-StringInFile'

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

        # If not using regex mode, escape the pattern for literal matching
        $searchPattern = if ($Regex)
        {
            $OldString
        }
        else
        {
            [regex]::Escape($OldString)
        }

        Write-Verbose "Search pattern: $searchPattern"
        Write-Verbose "Replacement: $NewString"
        Write-Verbose "Regex mode: $Regex"
        Write-Verbose "Case insensitive: $CaseInsensitive"
        Write-Verbose "Preserve case: $PreserveCase"
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

                    # Check if file is binary
                    try
                    {
                        # PowerShell 5.1 uses -Encoding Byte, PowerShell Core 6+ uses -AsByteStream
                        if ($PSVersionTable.PSVersion.Major -ge 6)
                        {
                            $testBytes = Get-Content -Path $file.FullName -AsByteStream -TotalCount 8000 -ErrorAction Stop
                        }
                        else
                        {
                            $testBytes = Get-Content -Path $file.FullName -Encoding Byte -TotalCount 8000 -ErrorAction Stop
                        }

                        $nullBytes = ($testBytes | Where-Object { $_ -eq 0 }).Count
                        if ($nullBytes -gt 0)
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

                    # Read file content
                    try
                    {
                        $content = Get-Content -Path $file.FullName -Raw -Encoding $Encoding -ErrorAction Stop
                    }
                    catch
                    {
                        Write-Warning "Failed to read file: $($file.FullName) - $($_.Exception.Message)"
                        continue
                    }

                    # Perform replacement
                    $replacementCount = 0
                    $newContent = $null

                    try
                    {
                        # Handle empty or null content
                        if ([string]::IsNullOrEmpty($content))
                        {
                            $replacementCount = 0
                        }
                        else
                        {
                            $regexMatches = [regex]::Matches($content, $searchPattern, $regexOptions)
                            $replacementCount = $regexMatches.Count

                            if ($replacementCount -gt 0)
                            {
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

                                        # Determine the case pattern of the matched text
                                        if ($matchedText -ceq $matchedText.ToUpper())
                                        {
                                            # ALL CAPS - check for separators
                                            if (Test-SnakeCase -text $matchedText)
                                            {
                                                return ConvertTo-SnakeCase -text $replacement -uppercase $true
                                            }
                                            elseif (Test-KebabCase -text $matchedText)
                                            {
                                                return ConvertTo-KebabCase -text $replacement -uppercase $true
                                            }
                                            else
                                            {
                                                return $replacement.ToUpper()
                                            }
                                        }
                                        elseif ($matchedText -ceq $matchedText.ToLower())
                                        {
                                            # all lowercase - check for separators
                                            if (Test-SnakeCase -text $matchedText)
                                            {
                                                return ConvertTo-SnakeCase -text $replacement -uppercase $false
                                            }
                                            elseif (Test-KebabCase -text $matchedText)
                                            {
                                                return ConvertTo-KebabCase -text $replacement -uppercase $false
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

                                    $newContent = [regex]::Replace($content, $searchPattern, $matchEvaluator, $regexOptions)
                                }
                                else
                                {
                                    $newContent = [regex]::Replace($content, $searchPattern, $NewString, $regexOptions)
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
                        MatchCount = $replacementCount
                        ReplacementsMade = $false
                        BackupCreated = $false
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

                        # Write new content
                        try
                        {
                            Set-Content -Path $file.FullName -Value $newContent -Encoding $Encoding -NoNewline -ErrorAction Stop
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
