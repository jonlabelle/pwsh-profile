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
        [Switch]$Backup,

        [Parameter()]
        [ValidateSet('UTF8', 'ASCII', 'Unicode', 'UTF32', 'UTF7', 'Default', 'OEM')]
        [String]$Encoding = 'UTF8'
    )

    begin
    {
        Write-Verbose 'Starting Replace-StringInFile'

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
                                $newContent = [regex]::Replace($content, $searchPattern, $NewString, $regexOptions)
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
