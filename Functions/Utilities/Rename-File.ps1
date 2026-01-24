function Rename-File
{
    <#
    .SYNOPSIS
        Renames files with advanced transformation options including case conversion, normalization,
        pattern replacement, and batch numbering.

    .DESCRIPTION
        This function provides a comprehensive file renaming solution with multiple transformation
        options that can be combined. It supports:

        - Case conversion (uppercase, lowercase, title case, camel case, pascal case)
        - Normalization (remove accents, control characters, shell meta-characters)
        - Text operations (append, prepend, trim, substitute, replace)
        - Whitespace handling (replace with underscores, dashes, or custom characters)
        - URL decoding
        - Extension management (keep, remove, replace)
        - Expression-based transformations using PowerShell script blocks
        - Counter-based batch renaming with custom formatting
        - Conflict resolution with automatic suffixing

        All transformations are applied in a specific order to ensure predictable results.
        Use -DryRun to safely preview what files will be renamed before executing actual changes.

    .PARAMETER Path
        The path to the file(s) to rename. Accepts wildcards and pipeline input.
        Can be a single file path, multiple paths, or a directory. If omitted, the
        current working directory is used. Use -Recurse to include subdirectories.

    .PARAMETER NewName
        The new name for the file. If not specified, transformations are applied to the current name.
        Can be used with counter formatting (e.g., 'file_{0:D3}.txt' for file_001.txt).

    .PARAMETER LiteralPath
        The literal path to the file(s) to rename. Unlike Path, this does not interpret wildcards.

    .PARAMETER Normalize
        Normalizes the filename by removing accents, converting to basic ASCII characters,
        and removing common problematic characters. Also trims leading and trailing whitespace.
        Useful for cross-platform compatibility.

    .PARAMETER ToUpper
        Converts the filename to UPPERCASE.

    .PARAMETER ToLower
        Converts the filename to lowercase.

    .PARAMETER ToTitleCase
        Converts the filename to Title Case (first letter of each word capitalized).

    .PARAMETER ToCamelCase
        Converts the filename to camelCase (first letter lowercase, subsequent words capitalized).

    .PARAMETER ToPascalCase
        Converts the filename to PascalCase (first letter of each word capitalized, no spaces).

    .PARAMETER Trim
        Trims leading and trailing whitespace from the filename.

    .PARAMETER TrimStart
        Trims leading whitespace from the filename.

    .PARAMETER TrimEnd
        Trims trailing whitespace from the filename.

    .PARAMETER Append
        Text to append to the filename (before the extension).

    .PARAMETER Prepend
        Text to prepend to the filename.

    .PARAMETER UrlDecode
        URL-decodes the filename, converting %20 to spaces, %2B to +, etc.

    .PARAMETER ReplaceSpacesWith
        Replaces all spaces in the filename with the specified character(s).
        Common values: '_' (underscore), '-' (dash), '.' (dot).

    .PARAMETER ReplaceUnderscoresWith
        Replaces all underscores in the filename with the specified character(s).
        Useful for converting back to spaces or other delimiters.

    .PARAMETER ReplaceDashesWith
        Replaces all dashes/hyphens in the filename with the specified character(s).

    .PARAMETER RemoveControlCharacters
        Removes all control characters (ASCII 0-31 and 127) from the filename.

    .PARAMETER RemoveShellMetaCharacters
        Removes shell meta-characters that may cause issues in command-line environments.
        Removes: & | ; < > ( ) $ ` \ " ' * ? [ ] # ~ = %

    .PARAMETER SanitizeForCrossPlatform
        Sanitizes the filename for cross-platform compatibility by removing/replacing
        characters that are problematic on Windows, macOS, or Linux.

    .PARAMETER RemoveExtension
        Removes the file extension from the filename.

    .PARAMETER NewExtension
        Changes the file extension to the specified value (include the dot, e.g., '.txt').

    .PARAMETER Replace
        A hashtable of old/new string pairs to replace in the filename.
        Example: @{ 'old' = 'new'; 'foo' = 'bar' }

    .PARAMETER RegexReplace
        A hashtable of regex pattern/replacement pairs to apply to the filename.
        Example: @{ '\d+' = 'NUM'; '\s+' = '_' }

    .PARAMETER Expression
        A script block that receives the filename (without extension) as $_ and returns
        the modified filename. Example: { $_.Substring(0, 10) }

    .PARAMETER Counter
        Adds a counter to the filename. Use with -CounterFormat to customize formatting.
        The counter is applied when processing multiple files.

    .PARAMETER CounterFormat
        Format string for the counter. Default is 'D3' (3-digit with leading zeros).
        Examples: 'D2' (01, 02), 'D4' (0001), 'X' (hexadecimal), 'N0' (no decimals).

    .PARAMETER CounterStart
        Starting number for the counter. Default is 1.

    .PARAMETER CounterPosition
        Position where the counter should be inserted.
        Valid values: 'End' (default), 'Start', 'BeforeExtension'.

    .PARAMETER Recurse
        Recursively processes files in subdirectories when Path is a directory.

    .PARAMETER Force
        Forces the rename even if the target file already exists (overwriting the target).
        By default, conflicts are resolved by adding a numeric suffix.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs without actually performing the rename.

    .PARAMETER DryRun
        Shows what would be renamed without actually performing the rename operations.
        Uses internal preview logic to display exact output, that otherwise couldn't be accomplished with built-in -WhatIf support.
        Note that you -WhatIf is an alias for -DryRun in this function.

    .PARAMETER PassThru
        Returns FileInfo objects for the renamed files.

    .EXAMPLE
        PS > Rename-File -Path 'My Document.txt' -ReplaceSpacesWith '_'

        Renames 'My Document.txt' to 'My_Document.txt'.

    .EXAMPLE
        PS > Rename-File -Path 'FILE.TXT' -ToLower

        Renames 'FILE.TXT' to 'file.txt'.

    .EXAMPLE
        PS > Get-ChildItem '*.jpg' | Rename-File -Prepend '2024-' -Counter -CounterFormat 'D3'

        Renames all .jpg files to: 2024-001.jpg, 2024-002.jpg, 2024-003.jpg, etc.

    .EXAMPLE
        PS > Rename-File -Path 'document%20file.txt' -UrlDecode -ToLower

        URL-decodes and converts to lowercase: 'document file.txt'.

    .EXAMPLE
        PS > Rename-File -Path 'file.dat' -NewExtension '.txt'

        Changes the extension from .dat to .txt: 'file.txt'.

    .EXAMPLE
        PS > Get-ChildItem '*.txt' | Rename-File -RemoveShellMetaCharacters -Normalize

        Sanitizes all .txt files by removing shell meta-characters and normalizing.

    .EXAMPLE
        PS > Rename-File -Path 'test_file.txt' -ReplaceUnderscoresWith ' ' -ToTitleCase

        Converts 'test_file.txt' to 'Test File.txt'.

    .EXAMPLE
        PS > Rename-File -Path '*.log' -Expression { "backup_$_" } -Append '_2024'

        Prepends 'backup_' and appends '_2024' to all .log files.

    .EXAMPLE
        PS > Rename-File -Path 'file.txt' -Replace @{ 'old' = 'new'; 'test' = 'prod' }

        Replaces 'old' with 'new' and 'test' with 'prod' in the filename.

    .EXAMPLE
        PS > Get-ChildItem 'C:\Photos' -Recurse | Rename-File -SanitizeForCrossPlatform -Counter

        Recursively sanitizes all filenames for cross-platform compatibility and adds counters.

    .EXAMPLE
        PS > Rename-File -Path 'IMG_*.jpg' -NewName 'photo_{0:D4}.jpg' -Counter

        Renames IMG_*.jpg files to photo_0001.jpg, photo_0002.jpg, etc.

    .EXAMPLE
        PS > Rename-File -Path 'data.txt' -ToPascalCase -RemoveExtension

        Converts 'data.txt' to 'Data' (removes extension).

    .EXAMPLE
        PS > Rename-File -Path '*.tmp' -RegexReplace @{ '\d{4}-\d{2}-\d{2}' = 'DATE' }

        Replaces date patterns (YYYY-MM-DD) with 'DATE' in all .tmp files.

    .EXAMPLE
        PS > Rename-File -Path 'C:\MyFiles' -Recurse -DryRun -RemoveShellMetaCharacters

        Shows a preview of what would be renamed when removing shell meta-characters from all files
        in C:\MyFiles and subdirectories, without actually performing any renames.

    .OUTPUTS
        None by default.
        [System.IO.FileInfo] when PassThru is specified.

    .NOTES
        Transformation Order:
        1. URL decode (if specified)
        2. Expression (if specified)
        3. Replace operations (Replace, RegexReplace)
        4. Normalization
        5. Remove control/shell characters
        6. Case conversion
        7. Whitespace replacements
        8. Trim operations (explicit or implied by -Normalize)
        9. Prepend/Append
        10. Counter (if specified)
        11. Extension handling

        Conflict Resolution:
        If a file with the new name already exists and -Force is not specified,
        a numeric suffix is automatically added (e.g., filename_2.txt).

        Cross-Platform Compatibility:
        The function works on Windows, macOS, and Linux. Use -SanitizeForCrossPlatform
        to ensure filenames are compatible across all platforms.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Rename-File.ps1

    .LINK
        https://jonlabelle.com/snippets/view/powershell/rename-files-with-advanced-options

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Rename-File.ps1
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Path', Position = 0)]
        [SupportsWildcards()]
        [String[]]$Path,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'LiteralPath')]
        [Alias('PSPath')]
        [String[]]$LiteralPath,

        [Parameter()]
        [String]$NewName,

        [Parameter()]
        [Switch]$Normalize,

        [Parameter()]
        [Switch]$ToUpper,

        [Parameter()]
        [Switch]$ToLower,

        [Parameter()]
        [Switch]$ToTitleCase,

        [Parameter()]
        [Switch]$ToCamelCase,

        [Parameter()]
        [Switch]$ToPascalCase,

        [Parameter()]
        [Switch]$Trim,

        [Parameter()]
        [Switch]$TrimStart,

        [Parameter()]
        [Switch]$TrimEnd,

        [Parameter()]
        [String]$Append,

        [Parameter()]
        [String]$Prepend,

        [Parameter()]
        [Switch]$UrlDecode,

        [Parameter()]
        [String]$ReplaceSpacesWith,

        [Parameter()]
        [String]$ReplaceUnderscoresWith,

        [Parameter()]
        [String]$ReplaceDashesWith,

        [Parameter()]
        [Switch]$RemoveControlCharacters,

        [Parameter()]
        [Switch]$RemoveShellMetaCharacters,

        [Parameter()]
        [Switch]$SanitizeForCrossPlatform,

        [Parameter()]
        [Switch]$RemoveExtension,

        [Parameter()]
        [ValidatePattern('^\..+')]
        [String]$NewExtension,

        [Parameter()]
        [Hashtable]$Replace,

        [Parameter()]
        [Hashtable]$RegexReplace,

        [Parameter()]
        [ScriptBlock]$Expression,

        [Parameter()]
        [Switch]$Counter,

        [Parameter()]
        [String]$CounterFormat = 'D3',

        [Parameter()]
        [Int]$CounterStart = 1,

        [Parameter()]
        [ValidateSet('End', 'Start', 'BeforeExtension')]
        [String]$CounterPosition = 'BeforeExtension',

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Alias('WhatIf')]
        [Switch]$DryRun,

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        $currentCounter = $CounterStart
        $fileCount = 0
        $processedPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

        # Collect all files from pipeline before processing to prevent PassThru output from re-entering
        $allFilesToProcess = [System.Collections.ArrayList]::new()

        function Get-NormalizedString
        {
            param([String]$Text)

            if ([String]::IsNullOrEmpty($Text))
            {
                return $Text
            }

            # Fix common UTF-8 mojibake sequences FIRST before any other normalization
            # When UTF-8 bytes are interpreted as ISO-8859-1, we get mojibake sequences
            # We construct these strings from escape sequences for maximum compatibility
            $normalized = $Text
            $mojibakeReplacements = @{}

            # Lowercase vowels with diacritics
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xA1)] = 'a'  # á bytes C3 A1
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xA0)] = 'a'  # à bytes C3 A0
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xA4)] = 'a'  # ä bytes C3 A4
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xA2)] = 'a'  # â bytes C3 A2
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xA3)] = 'a'  # ã bytes C3 A3
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xA5)] = 'a'  # å bytes C3 A5

            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xA9)] = 'e'  # é bytes C3 A9
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xA8)] = 'e'  # è bytes C3 A8
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xAB)] = 'e'  # ë bytes C3 AB
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xAA)] = 'e'  # ê bytes C3 AA

            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xAD)] = 'i'  # í bytes C3 AD
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xAC)] = 'i'  # ì bytes C3 AC
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xAF)] = 'i'  # ï bytes C3 AF
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xAE)] = 'i'  # î bytes C3 AE

            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xB3)] = 'o'  # ó bytes C3 B3
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xB2)] = 'o'  # ò bytes C3 B2
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xB6)] = 'o'  # ö bytes C3 B6
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xB4)] = 'o'  # ô bytes C3 B4
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xB5)] = 'o'  # õ bytes C3 B5
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xB8)] = 'o'  # ø bytes C3 B8

            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xBA)] = 'u'  # ú bytes C3 BA
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xB9)] = 'u'  # ù bytes C3 B9
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xBC)] = 'u'  # ü bytes C3 BC
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xBB)] = 'u'  # û bytes C3 BB

            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xB1)] = 'n'  # ñ bytes C3 B1
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xA7)] = 'c'  # ç bytes C3 A7
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xBD)] = 'y'  # ý bytes C3 BD
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0xBF)] = 'y'  # ÿ bytes C3 BF

            # Uppercase vowels with diacritics
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x80)] = 'A'  # À bytes C3 80
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x84)] = 'A'  # Ä bytes C3 84
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x82)] = 'A'  # Â bytes C3 82
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x83)] = 'A'  # Ã bytes C3 83
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x85)] = 'A'  # Å bytes C3 85

            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x89)] = 'E'  # É bytes C3 89
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x88)] = 'E'  # È bytes C3 88
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x8B)] = 'E'  # Ë bytes C3 8B
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x8A)] = 'E'  # Ê bytes C3 8A

            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x8D)] = 'I'  # Í bytes C3 8D
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x8C)] = 'I'  # Ì bytes C3 8C
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x8F)] = 'I'  # Ï bytes C3 8F
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x8E)] = 'I'  # Î bytes C3 8E

            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x93)] = 'O'  # Ó bytes C3 93
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x92)] = 'O'  # Ò bytes C3 92
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x96)] = 'O'  # Ö bytes C3 96
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x94)] = 'O'  # Ô bytes C3 94
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x95)] = 'O'  # Õ bytes C3 95
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x98)] = 'O'  # Ø bytes C3 98

            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x9A)] = 'U'  # Ú bytes C3 9A
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x99)] = 'U'  # Ù bytes C3 99
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x9C)] = 'U'  # Ü bytes C3 9C
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x9B)] = 'U'  # Û bytes C3 9B

            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x91)] = 'N'  # Ñ bytes C3 91
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x87)] = 'C'  # Ç bytes C3 87
            $mojibakeReplacements[[string]([char]0xC3) + [string]([char]0x9D)] = 'Y'  # Ý bytes C3 9D

            foreach ($key in $mojibakeReplacements.Keys)
            {
                $normalized = $normalized -replace [regex]::Escape($key), $mojibakeReplacements[$key]
            }

            try
            {
                # Try NFD normalization to decompose accents
                $normalized = $normalized.Normalize([System.Text.NormalizationForm]::FormD)
            }
            catch
            {
                # Fallback for PowerShell 5.1 or if Normalize method fails
                # Use a character-by-character replacement table for common accented characters
                $replacements = @{}

                # Lowercase a variants
                $replacements['á'] = 'a'
                $replacements['à'] = 'a'
                $replacements['ä'] = 'a'
                $replacements['â'] = 'a'
                $replacements['ã'] = 'a'
                $replacements['å'] = 'a'
                $replacements['ą'] = 'a'

                # Lowercase e variants
                $replacements['é'] = 'e'
                $replacements['è'] = 'e'
                $replacements['ë'] = 'e'
                $replacements['ê'] = 'e'
                $replacements['ę'] = 'e'

                # Lowercase i variants
                $replacements['í'] = 'i'
                $replacements['ì'] = 'i'
                $replacements['ï'] = 'i'
                $replacements['î'] = 'i'
                $replacements['į'] = 'i'

                # Lowercase o variants
                $replacements['ó'] = 'o'
                $replacements['ò'] = 'o'
                $replacements['ö'] = 'o'
                $replacements['ô'] = 'o'
                $replacements['õ'] = 'o'
                $replacements['ø'] = 'o'
                $replacements['ǿ'] = 'o'

                # Lowercase u variants
                $replacements['ú'] = 'u'
                $replacements['ù'] = 'u'
                $replacements['ü'] = 'u'
                $replacements['û'] = 'u'
                $replacements['ų'] = 'u'

                # Lowercase y variants
                $replacements['ý'] = 'y'
                $replacements['ỳ'] = 'y'
                $replacements['ÿ'] = 'y'
                $replacements['ŷ'] = 'y'

                # Lowercase c variants
                $replacements['ć'] = 'c'
                $replacements['č'] = 'c'
                $replacements['ċ'] = 'c'
                $replacements['ç'] = 'c'

                # Lowercase d variants
                $replacements['ď'] = 'd'
                $replacements['đ'] = 'd'

                # Lowercase g variants
                $replacements['ğ'] = 'g'
                $replacements['ģ'] = 'g'

                # Other lowercase variants
                $replacements['ħ'] = 'h'
                $replacements['ĵ'] = 'j'
                $replacements['ķ'] = 'k'
                $replacements['ļ'] = 'l'
                $replacements['ł'] = 'l'
                $replacements['ń'] = 'n'
                $replacements['ň'] = 'n'
                $replacements['ņ'] = 'n'
                $replacements['ñ'] = 'n'
                $replacements['ŕ'] = 'r'
                $replacements['ř'] = 'r'
                $replacements['ŗ'] = 'r'
                $replacements['ś'] = 's'
                $replacements['š'] = 's'
                $replacements['ş'] = 's'
                $replacements['ť'] = 't'
                $replacements['ţ'] = 't'
                $replacements['ź'] = 'z'
                $replacements['ž'] = 'z'
                $replacements['ż'] = 'z'

                # Uppercase variants
                $replacements['Á'] = 'A'
                $replacements['À'] = 'A'
                $replacements['Ä'] = 'A'
                $replacements['Â'] = 'A'
                $replacements['Ã'] = 'A'
                $replacements['Å'] = 'A'
                $replacements['É'] = 'E'
                $replacements['È'] = 'E'
                $replacements['Ë'] = 'E'
                $replacements['Ê'] = 'E'
                $replacements['Í'] = 'I'
                $replacements['Ì'] = 'I'
                $replacements['Ï'] = 'I'
                $replacements['Î'] = 'I'
                $replacements['Ó'] = 'O'
                $replacements['Ò'] = 'O'
                $replacements['Ö'] = 'O'
                $replacements['Ô'] = 'O'
                $replacements['Õ'] = 'O'
                $replacements['Ø'] = 'O'
                $replacements['Ú'] = 'U'
                $replacements['Ù'] = 'U'
                $replacements['Ü'] = 'U'
                $replacements['Û'] = 'U'
                $replacements['Ý'] = 'Y'
                $replacements['Ÿ'] = 'Y'
                $replacements['Ç'] = 'C'
                $replacements['Ñ'] = 'N'

                foreach ($key in $replacements.Keys)
                {
                    $normalized = $normalized -replace [regex]::Escape($key), $replacements[$key]
                }
            }

            # Remove diacritical marks (combining characters)
            $sb = New-Object System.Text.StringBuilder
            foreach ($char in $normalized.ToCharArray())
            {
                $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
                if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark)
                {
                    $null = $sb.Append($char)
                }
            }

            # Normalize back to FormC (composed form)
            try
            {
                return $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
            }
            catch
            {
                return $sb.ToString()
            }
        }

        function ConvertTo-TitleCase
        {
            param([String]$Text)

            if ([String]::IsNullOrEmpty($Text))
            {
                return $Text
            }

            $textInfo = (Get-Culture).TextInfo
            return $textInfo.ToTitleCase($Text.ToLower())
        }

        function ConvertTo-CamelCase
        {
            param([String]$Text)

            if ([String]::IsNullOrEmpty($Text))
            {
                return $Text
            }

            # Split on non-alphanumeric characters and spaces
            $words = $Text -split '[^a-zA-Z0-9]+'
            $result = New-Object System.Text.StringBuilder

            for ($i = 0; $i -lt $words.Count; $i++)
            {
                $word = $words[$i]
                if ([String]::IsNullOrWhiteSpace($word))
                {
                    continue
                }

                if ($i -eq 0)
                {
                    # First word: lowercase first letter
                    $null = $result.Append($word.Substring(0, 1).ToLower())
                    if ($word.Length -gt 1)
                    {
                        $null = $result.Append($word.Substring(1).ToLower())
                    }
                }
                else
                {
                    # Subsequent words: uppercase first letter
                    $null = $result.Append($word.Substring(0, 1).ToUpper())
                    if ($word.Length -gt 1)
                    {
                        $null = $result.Append($word.Substring(1).ToLower())
                    }
                }
            }

            return $result.ToString()
        }

        function ConvertTo-PascalCase
        {
            param([String]$Text)

            if ([String]::IsNullOrEmpty($Text))
            {
                return $Text
            }

            # Split on non-alphanumeric characters and spaces
            $words = $Text -split '[^a-zA-Z0-9]+'
            $result = New-Object System.Text.StringBuilder

            foreach ($word in $words)
            {
                if ([String]::IsNullOrWhiteSpace($word))
                {
                    continue
                }

                # Uppercase first letter, lowercase the rest
                $null = $result.Append($word.Substring(0, 1).ToUpper())
                if ($word.Length -gt 1)
                {
                    $null = $result.Append($word.Substring(1).ToLower())
                }
            }

            return $result.ToString()
        }

        function Remove-ControlCharacters
        {
            param([String]$Text)

            if ([String]::IsNullOrEmpty($Text))
            {
                return $Text
            }

            # Remove ASCII control characters (0-31 and 127)
            return [regex]::Replace($Text, '[\x00-\x1F\x7F]', '')
        }

        function Remove-ShellMetaCharacters
        {
            param([String]$Text)

            if ([String]::IsNullOrEmpty($Text))
            {
                return $Text
            }

            # Remove common shell meta-characters
            # Characters: & | ; < > ( ) $ ` \ " ' * ? [ ] # ~ = %
            $result = $Text
            # Use individual replacements for maximum compatibility across PowerShell versions
            $result = $result -replace '\&', ''
            $result = $result -replace '\|', ''
            $result = $result -replace '\;', ''
            $result = $result -replace '[<>]', ''
            $result = $result -replace '[\(\)]', ''
            $result = $result -replace '\$', ''
            $result = $result -replace '`', ''
            $result = $result -replace '\\', ''
            $result = $result -replace '"', ''
            $result = $result -replace "'", ''
            $result = $result -replace '\*', ''
            $result = $result -replace '\?', ''
            $result = $result -replace '[\[\]]', ''
            $result = $result -replace '#', ''
            $result = $result -replace '~', ''
            $result = $result -replace '=', ''
            $result = $result -replace '%', ''
            return $result
        }

        function Get-SanitizedFilename
        {
            param([String]$Filename)

            if ([String]::IsNullOrEmpty($Filename))
            {
                return $Filename
            }

            # Remove or replace characters that are problematic on Windows, macOS, or Linux
            # Windows: < > : " / \ | ? *
            # macOS/Linux: / (and null character)
            # Also remove leading/trailing dots and spaces (problematic on Windows)

            $sanitized = $Filename
            $sanitized = $sanitized -replace '[<>:"/\\|?*]', '_'
            $sanitized = $sanitized -replace '[\x00]', ''
            $sanitized = $sanitized.Trim('. ')

            return $sanitized
        }

        function Get-UrlDecodedString
        {
            param([String]$Text)

            if ([String]::IsNullOrEmpty($Text))
            {
                return $Text
            }

            try
            {
                # Use .NET's UrlDecode
                return [System.Web.HttpUtility]::UrlDecode($Text)
            }
            catch
            {
                # If System.Web is not available, do basic replacements
                $result = $Text
                $result = $result -replace '%20', ' '
                $result = $result -replace '%21', '!'
                $result = $result -replace '%22', '"'
                $result = $result -replace '%23', '#'
                $result = $result -replace '%24', '$'
                $result = $result -replace '%25', '%'
                $result = $result -replace '%26', '&'
                $result = $result -replace '%27', "'"
                $result = $result -replace '%28', '('
                $result = $result -replace '%29', ')'
                $result = $result -replace '%2A', '*'
                $result = $result -replace '%2B', '+'
                $result = $result -replace '%2C', ','
                $result = $result -replace '%2D', '-'
                $result = $result -replace '%2E', '.'
                $result = $result -replace '%2F', '/'
                return $result
            }
        }

        function Get-UniqueFilename
        {
            param(
                [String]$Directory,
                [String]$BaseName,
                [String]$FileExtension
            )

            # Use local variable with different name to avoid scope contamination
            $ext = $FileExtension
            $targetPath = Join-Path -Path $Directory -ChildPath ($BaseName + $ext)
            $suffix = 2

            while (Test-Path -LiteralPath $targetPath)
            {
                $newBaseName = "${BaseName}_${suffix}"
                $targetPath = Join-Path -Path $Directory -ChildPath ($newBaseName + $ext)
                $suffix++
            }

            return Split-Path -Leaf $targetPath
        }

        function Get-TransformedFilename
        {
            param(
                [String]$OriginalName,
                [String]$FileExt,
                [Int]$CounterValue
            )

            # Use different parameter name (FileExt instead of Extension) to avoid any scope collision
            $result = $OriginalName
            $ext = $FileExt

            # 1. URL decode (if specified)
            if ($UrlDecode)
            {
                $result = Get-UrlDecodedString -Text $result
                Write-Verbose "After URL decode: '$result'"
            }

            # 2. Expression (if specified)
            if ($Expression)
            {
                try
                {
                    # Use ForEach-Object to properly set $_ variable for the script block
                    $newResult = $result | ForEach-Object -Process $Expression
                    if (-not [String]::IsNullOrEmpty($newResult))
                    {
                        $result = $newResult
                        Write-Verbose "After expression: '$result'"
                    }
                    else
                    {
                        Write-Warning "Expression returned null or empty value for: $result"
                    }
                }
                catch
                {
                    Write-Warning "Expression evaluation failed: $($_.Exception.Message)"
                }
            }

            # 3. Replace operations
            if ($Replace)
            {
                foreach ($key in $Replace.Keys)
                {
                    $result = $result -replace [regex]::Escape($key), $Replace[$key]
                }
                Write-Verbose "After replace: '$result'"
            }

            if ($RegexReplace)
            {
                foreach ($pattern in $RegexReplace.Keys)
                {
                    $result = $result -replace $pattern, $RegexReplace[$pattern]
                }
                Write-Verbose "After regex replace: '$result'"
            }

            # 4. Normalization
            if ($Normalize)
            {
                $result = Get-NormalizedString -Text $result
                Write-Verbose "After normalization: '$result'"
            }

            # 5. Remove control/shell characters
            if ($RemoveControlCharacters)
            {
                $result = Remove-ControlCharacters -Text $result
                Write-Verbose "After removing control characters: '$result'"
            }

            if ($RemoveShellMetaCharacters)
            {
                $result = Remove-ShellMetaCharacters -Text $result
                Write-Verbose "After removing shell meta-characters: '$result'"
            }

            if ($SanitizeForCrossPlatform)
            {
                $result = Get-SanitizedFilename -Filename $result
                Write-Verbose "After cross-platform sanitization: '$result'"
            }

            # 6. Case conversion (only one should be applied)
            if ($ToUpper)
            {
                $result = $result.ToUpper()
                Write-Verbose "After ToUpper: '$result'"
            }
            elseif ($ToLower)
            {
                $result = $result.ToLower()
                Write-Verbose "After ToLower: '$result'"
            }
            elseif ($ToTitleCase)
            {
                $result = ConvertTo-TitleCase -Text $result
                Write-Verbose "After ToTitleCase: '$result'"
            }
            elseif ($ToCamelCase)
            {
                $result = ConvertTo-CamelCase -Text $result
                Write-Verbose "After ToCamelCase: '$result'"
            }
            elseif ($ToPascalCase)
            {
                $result = ConvertTo-PascalCase -Text $result
                Write-Verbose "After ToPascalCase: '$result'"
            }

            # 7. Whitespace replacements
            if ($ReplaceSpacesWith)
            {
                $result = $result -replace ' ', $ReplaceSpacesWith
                Write-Verbose "After replacing spaces: '$result'"
            }

            if ($ReplaceUnderscoresWith)
            {
                $result = $result -replace '_', $ReplaceUnderscoresWith
                Write-Verbose "After replacing underscores: '$result'"
            }

            if ($ReplaceDashesWith)
            {
                $result = $result -replace '-', $ReplaceDashesWith
                Write-Verbose "After replacing dashes: '$result'"
            }

            # 8. Trim operations
            if ($Trim -or $Normalize)
            {
                $result = $result.Trim()
                Write-Verbose "After trim: '$result'"
            }
            elseif ($TrimStart)
            {
                $result = $result.TrimStart()
                Write-Verbose "After trim start: '$result'"
            }
            elseif ($TrimEnd)
            {
                $result = $result.TrimEnd()
                Write-Verbose "After trim end: '$result'"
            }

            # 9. Prepend/Append
            if ($Prepend)
            {
                $result = $Prepend + $result
                Write-Verbose "After prepend: '$result'"
            }

            if ($Append)
            {
                $result = $result + $Append
                Write-Verbose "After append: '$result'"
            }

            # 10. Counter
            if ($Counter)
            {
                $counterText = $CounterValue.ToString($CounterFormat)

                switch ($CounterPosition)
                {
                    'Start'
                    {
                        $result = $counterText + $result
                    }
                    'End'
                    {
                        $result = $result + $counterText
                    }
                    'BeforeExtension'
                    {
                        # Counter is added at the end of the name (will be before extension when combined)
                        $result = $result + $counterText
                    }
                }
                Write-Verbose "After counter: '$result'"
            }

            # 11. Extension handling
            if ($RemoveExtension)
            {
                return $result
            }
            elseif ($NewExtension)
            {
                return ($result + $NewExtension)
            }
            else
            {
                return ($result + $ext)
            }
        }
    }

    process
    {
        # Collect all files from pipeline input before processing
        # This prevents PassThru output from flowing back into the pipeline and being processed again
        $files = @()

        if ($PSCmdlet.ParameterSetName -eq 'Path')
        {
            if (-not $PSBoundParameters.ContainsKey('Path') -and -not $PSBoundParameters.ContainsKey('LiteralPath'))
            {
                $Path = @((Get-Location).Path)
            }

            foreach ($p in $Path)
            {
                try
                {
                    $resolvedPaths = @(Resolve-Path -Path $p -ErrorAction Stop)
                    foreach ($resolvedPath in $resolvedPaths)
                    {
                        $item = Get-Item -LiteralPath $resolvedPath.Path -ErrorAction Stop
                        if ($item.PSIsContainer)
                        {
                            # If it's a directory and Recurse is specified, get all files
                            if ($Recurse)
                            {
                                $files += Get-ChildItem -LiteralPath $item.FullName -File -Recurse -ErrorAction Stop
                            }
                            else
                            {
                                $files += Get-ChildItem -LiteralPath $item.FullName -File -ErrorAction Stop
                            }
                        }
                        else
                        {
                            $files += $item
                        }
                    }
                }
                catch
                {
                    Write-Error "Failed to resolve path '$p': $($_.Exception.Message)"
                    continue
                }
            }
        }
        else
        {
            # LiteralPath
            foreach ($lp in $LiteralPath)
            {
                try
                {
                    $item = Get-Item -LiteralPath $lp -ErrorAction Stop
                    if ($item.PSIsContainer)
                    {
                        if ($Recurse)
                        {
                            $files += Get-ChildItem -LiteralPath $item.FullName -File -Recurse -ErrorAction Stop
                        }
                        else
                        {
                            $files += Get-ChildItem -LiteralPath $item.FullName -File -ErrorAction Stop
                        }
                    }
                    else
                    {
                        $files += $item
                    }
                }
                catch
                {
                    Write-Error "Failed to get item '$lp': $($_.Exception.Message)"
                    continue
                }
            }
        }

        # Add collected files to the processing list
        foreach ($file in $files)
        {
            $null = $allFilesToProcess.Add($file)
        }
    }

    end
    {
        # Process all collected files AFTER all pipeline input has been received
        # This prevents PassThru output from re-entering the pipeline
        foreach ($file in $allFilesToProcess)
        {
            $fileCount++

            try
            {
                # Prevent accidental double-processing by tracking the original file identity
                # Use the file's directory + original name as the key, since FullName changes after rename
                $originalIdentity = Join-Path -Path $file.DirectoryName -ChildPath $file.Name
                if (-not $processedPaths.Add($originalIdentity))
                {
                    Write-Verbose "Skipping '$originalIdentity': already processed"
                    continue
                }

                $directory = $file.DirectoryName
                $currentName = $file.Name

                # Handle dotfiles specially: .editorconfig, .gitignore, etc.
                # These files start with a dot and have no real extension separator
                # CRITICAL: Always reset these variables at the start of each loop iteration
                # to prevent contamination from previous files
                $fileBaseName = ''
                $fileExtension = ''

                if ($currentName -match '^\.[^.]*$')
                {
                    # Dotfile with no extension - treat the entire name as the basename
                    $fileBaseName = $currentName
                    $fileExtension = ''
                }
                else
                {
                    $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($currentName)
                    $fileExtension = [System.IO.Path]::GetExtension($currentName)

                    # DEFENSIVE: Ensure $fileExtension is never null, always a string
                    # Convert null/empty to truly empty string, not $null
                    if ([string]::IsNullOrEmpty($fileExtension))
                    {
                        $fileExtension = [string]::Empty
                    }
                    # Also ensure it's truly a string type, never an object
                    $fileExtension = [string]$fileExtension
                }

                # Determine new filename
                if ($NewName)
                {
                    # If NewName contains a format placeholder, use it with the counter
                    if ($NewName -match '\{0[^}]*\}' -and $Counter)
                    {
                        $newFileName = $NewName -f $currentCounter
                    }
                    else
                    {
                        $newFileName = $NewName
                    }
                }
                else
                {
                    # Apply transformations to existing name
                    # Pass extension as FileExt to avoid parameter name collision
                    $newFileName = Get-TransformedFilename -OriginalName $fileBaseName -FileExt $fileExtension -CounterValue $currentCounter
                }

                # Ensure the new filename is not empty
                if ([String]::IsNullOrWhiteSpace($newFileName))
                {
                    Write-Warning "Skipping '$currentName': Transformation resulted in empty filename"
                    continue
                }

                # Check if filename actually changed (use case-sensitive comparison)
                if ($newFileName -ceq $currentName)
                {
                    Write-Verbose "Skipping '$currentName': No changes to apply"
                    continue
                }

                # Handle conflicts
                $targetPath = Join-Path -Path $directory -ChildPath $newFileName

                # Check if target exists AND is a different file (not just case-different on case-insensitive systems)
                if ((Test-Path -LiteralPath $targetPath) -and -not $Force)
                {
                    # Compare actual paths to see if it's truly a different file
                    $targetItem = Get-Item -LiteralPath $targetPath -ErrorAction SilentlyContinue
                    $isSameFile = ($null -ne $targetItem) -and ($targetItem.FullName -eq $file.FullName)

                    if (-not $isSameFile)
                    {
                        # File exists and is different, generate unique name
                        # Use unique variable names to prevent contamination across iterations
                        $uniqueBaseName = [System.IO.Path]::GetFileNameWithoutExtension($newFileName)
                        $uniqueExtension = [System.IO.Path]::GetExtension($newFileName)
                        $newFileName = Get-UniqueFilename -Directory $directory -BaseName $uniqueBaseName -FileExtension $uniqueExtension
                        $targetPath = Join-Path -Path $directory -ChildPath $newFileName
                        Write-Verbose "Conflict detected, using unique name: $newFileName"
                    }
                }

                # Perform the rename
                if ($DryRun)
                {
                    # DryRun mode: show what would be renamed without actually doing it
                    Write-Host "Would rename: $($file.FullName)" -ForegroundColor Cyan
                    Write-Host "          to: $(Join-Path -Path $directory -ChildPath $newFileName)" -ForegroundColor Green

                    # Increment counter for next file (even in dry-run)
                    if ($Counter)
                    {
                        $currentCounter++
                    }
                }
                else
                {
                    # Normal mode: actually perform the rename
                    try
                    {
                        $renamedFile = Rename-Item -LiteralPath $file.FullName -NewName $newFileName -Force:$Force -PassThru -ErrorAction Stop
                        Write-Verbose "Successfully renamed to: $newFileName"

                        if ($PassThru)
                        {
                            $renamedFile
                        }

                        # Increment counter for next file
                        if ($Counter)
                        {
                            $currentCounter++
                        }
                    }
                    catch
                    {
                        Write-Error "Failed to rename '$currentName' to '$newFileName': $($_.Exception.Message)"
                    }
                }
            }
            catch
            {
                Write-Error "Error processing file '$($file.FullName)': $($_.Exception.Message)"
                continue
            }
        }

        # Summary message
        if ($fileCount -eq 0)
        {
            Write-Warning 'No files were found to process'
        }
        else
        {
            Write-Verbose "Processed $fileCount file(s)"
        }
    }
}
