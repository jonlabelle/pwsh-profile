function ConvertTo-UrlSlug
{
    <#
    .SYNOPSIS
        Converts arbitrary text to URL-friendly slugs, or renames files/directories using slugified names.

    .DESCRIPTION
        ConvertTo-UrlSlug creates URL-safe slug values from arbitrary string input.
        It can also rename existing files and directories using the same slug logic.

        String mode:
        - Accepts one or more strings via parameter or pipeline.
        - Returns one slug per input value.

        Rename mode:
        - Use -Path or -LiteralPath to target existing files/directories.
        - File extensions are preserved.
        - Dotfiles (for example: .editorconfig) keep their leading dot.
        - Name collisions are resolved by appending a numeric suffix.
        - Supports -WhatIf / -Confirm through SupportsShouldProcess.

        Compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

    .PARAMETER InputObject
        One or more values to convert into URL slugs.
        Supports pipeline input.

    .PARAMETER Path
        One or more file or directory paths to rename using slugified names.
        Supports wildcards.

    .PARAMETER LiteralPath
        One or more literal file or directory paths to rename using slugified names.
        Wildcard characters are treated literally.

    .PARAMETER Separator
        Separator used between slug tokens. Defaults to '-'.

    .PARAMETER KeepCase
        Preserves original case. By default output is lowercase.

    .PARAMETER KeepUnicode
        Preserves unicode letters/numbers in the slug.
        By default, diacritics are stripped and output is reduced to ASCII letters/numbers.

    .PARAMETER PassThru
        In rename mode, returns the renamed FileSystemInfo objects.

    .EXAMPLE
        PS > ConvertTo-UrlSlug -InputObject 'Hello, World!'
        hello-world

        Converts text to a lowercase URL slug.

    .EXAMPLE
        PS > 'My First Post', 'Another Entry' | ConvertTo-UrlSlug
        my-first-post
        another-entry

        Converts multiple strings from pipeline input.

    .EXAMPLE
        PS > ConvertTo-UrlSlug -InputObject 'Crème brûlée' -Separator '_'
        creme_brulee

        Converts text to a slug using a custom separator.

    .EXAMPLE
        PS > ConvertTo-UrlSlug -LiteralPath './My Draft File.txt'

        Renames My Draft File.txt to my-draft-file.txt.

    .EXAMPLE
        PS > Get-ChildItem -Path './content' | ConvertTo-UrlSlug -PassThru

        Renames each file/directory in ./content to slugified names and returns renamed items.

    .OUTPUTS
        System.String
            In string mode, one slug per input value.

        System.IO.FileSystemInfo
            In rename mode, when -PassThru is specified.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-UrlSlug.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-UrlSlug.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'InputObject')]
    [OutputType([String], [System.IO.FileSystemInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0, ParameterSetName = 'InputObject')]
        [AllowEmptyString()]
        [Alias('Text', 'Value')]
        [String[]]$InputObject,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position = 0, ParameterSetName = 'Path')]
        [SupportsWildcards()]
        [String[]]$Path,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'LiteralPath')]
        [Alias('PSPath', 'FullName')]
        [String[]]$LiteralPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$Separator = '-',

        [Parameter()]
        [Switch]$KeepCase,

        [Parameter()]
        [Switch]$KeepUnicode,

        [Parameter(ParameterSetName = 'Path')]
        [Parameter(ParameterSetName = 'LiteralPath')]
        [Switch]$PassThru
    )

    begin
    {
        $processedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $escapedSeparator = [Regex]::Escape($Separator)

        function ConvertTo-SlugValue
        {
            param(
                [Parameter()]
                [AllowNull()]
                [String]$Value
            )

            if ($null -eq $Value)
            {
                return ''
            }

            $working = $Value.Trim()
            if ([String]::IsNullOrWhiteSpace($working))
            {
                return ''
            }

            try
            {
                $working = [Uri]::UnescapeDataString($working)
            }
            catch
            {
                # Keep original text if URL decoding fails.
            }

            if (-not $KeepUnicode)
            {
                try
                {
                    $working = $working.Normalize([System.Text.NormalizationForm]::FormD)
                }
                catch
                {
                    # Keep original text if normalization is unavailable.
                }

                $builder = [System.Text.StringBuilder]::new()
                foreach ($char in $working.ToCharArray())
                {
                    $charCategory = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
                    if ($charCategory -ne [System.Globalization.UnicodeCategory]::NonSpacingMark)
                    {
                        [void]$builder.Append($char)
                    }
                }

                try
                {
                    $working = $builder.ToString().Normalize([System.Text.NormalizationForm]::FormC)
                }
                catch
                {
                    $working = $builder.ToString()
                }
            }

            $working = $working -replace "[`'’]", ''

            if (-not $KeepCase)
            {
                $working = $working.ToLowerInvariant()
            }

            if ($KeepUnicode)
            {
                $working = $working -replace '[^\p{L}\p{Nd}]+', $Separator
            }
            else
            {
                $working = $working -replace '[^a-zA-Z0-9]+', $Separator
            }

            $working = $working -replace "($escapedSeparator){2,}", $Separator
            $working = $working -replace "^$escapedSeparator+", ''
            $working = $working -replace "$escapedSeparator+$", ''

            return $working
        }

        function Get-RenameParts
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item
            )

            $baseName = ''
            $extension = ''
            $preserveLeadingDot = $false

            if ($Item.Name -match '^\.[^.]+$')
            {
                $preserveLeadingDot = $true
                $baseName = $Item.Name.Substring(1)
            }
            elseif ($Item.PSIsContainer)
            {
                $baseName = $Item.Name
            }
            else
            {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Item.Name)
                $extension = [System.IO.Path]::GetExtension($Item.Name)
                if ([String]::IsNullOrEmpty($extension))
                {
                    $extension = ''
                }
            }

            [PSCustomObject]@{
                BaseName = $baseName
                Extension = $extension
                PreserveLeadingDot = $preserveLeadingDot
            }
        }

        function Get-UniqueSlugName
        {
            param(
                [Parameter(Mandatory)]
                [String]$Directory,

                [Parameter(Mandatory)]
                [String]$BaseName,

                [Parameter()]
                [String]$Extension = ''
            )

            $counter = 2
            $candidateName = "$BaseName$Extension"

            while (Test-Path -LiteralPath (Join-Path -Path $Directory -ChildPath $candidateName))
            {
                $candidateName = '{0}{1}{2}{3}' -f $BaseName, $Separator, $counter, $Extension
                $counter++
            }

            return $candidateName
        }

        function Rename-SlugTarget
        {
            param(
                [Parameter(Mandatory)]
                [String[]]$TargetPath,

                [Parameter()]
                [Switch]$UseLiteralPath
            )

            foreach ($candidatePath in $TargetPath)
            {
                if ([String]::IsNullOrWhiteSpace($candidatePath))
                {
                    continue
                }

                $resolvedTargets = @()
                if ($UseLiteralPath)
                {
                    $resolvedTargets = @($candidatePath)
                }
                else
                {
                    try
                    {
                        $resolvedTargets = @(Resolve-Path -Path $candidatePath -ErrorAction Stop | Select-Object -ExpandProperty Path)
                    }
                    catch
                    {
                        Write-Error "Failed to resolve path '$candidatePath': $($_.Exception.Message)"
                        continue
                    }
                }

                foreach ($resolvedTarget in $resolvedTargets)
                {
                    try
                    {
                        $item = Get-Item -LiteralPath $resolvedTarget -ErrorAction Stop
                    }
                    catch
                    {
                        Write-Error "Failed to get item '$resolvedTarget': $($_.Exception.Message)"
                        continue
                    }

                    if (-not $processedPaths.Add($item.FullName))
                    {
                        Write-Verbose "Skipping '$($item.FullName)': already processed"
                        continue
                    }

                    $parts = Get-RenameParts -Item $item
                    $slugBase = ConvertTo-SlugValue -Value $parts.BaseName

                    if ([String]::IsNullOrWhiteSpace($slugBase))
                    {
                        Write-Warning "Skipping '$($item.FullName)': slug result is empty"
                        continue
                    }

                    $slugNameBase = if ($parts.PreserveLeadingDot)
                    {
                        ".$slugBase"
                    }
                    else
                    {
                        $slugBase
                    }

                    $newName = "$slugNameBase$($parts.Extension)"

                    if ($newName -ceq $item.Name)
                    {
                        Write-Verbose "Skipping '$($item.FullName)': already slugified"
                        continue
                    }

                    $parentPath = [System.IO.Path]::GetDirectoryName($item.FullName)
                    if ([String]::IsNullOrWhiteSpace($parentPath))
                    {
                        Write-Warning "Skipping '$($item.FullName)': unable to determine parent directory"
                        continue
                    }

                    $targetPathResolved = Join-Path -Path $parentPath -ChildPath $newName
                    if (Test-Path -LiteralPath $targetPathResolved)
                    {
                        $targetItem = Get-Item -LiteralPath $targetPathResolved -ErrorAction SilentlyContinue
                        $isSameItem = ($null -ne $targetItem) -and ($targetItem.FullName -eq $item.FullName)

                        if (-not $isSameItem)
                        {
                            $newName = Get-UniqueSlugName -Directory $parentPath -BaseName $slugNameBase -Extension $parts.Extension
                        }
                    }

                    if ($PSCmdlet.ShouldProcess($item.FullName, "Rename to '$newName'"))
                    {
                        try
                        {
                            $renamedItem = Rename-Item -LiteralPath $item.FullName -NewName $newName -PassThru -ErrorAction Stop
                            if ($PassThru)
                            {
                                $renamedItem
                            }
                        }
                        catch
                        {
                            Write-Error "Failed to rename '$($item.FullName)' to '$newName': $($_.Exception.Message)"
                        }
                    }
                }
            }
        }
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject')
        {
            foreach ($value in $InputObject)
            {
                ConvertTo-SlugValue -Value $value
            }
            return
        }

        if ($PSCmdlet.ParameterSetName -eq 'Path')
        {
            Rename-SlugTarget -TargetPath $Path
            return
        }

        Rename-SlugTarget -TargetPath $LiteralPath -UseLiteralPath
    }
}

# Create 'slug' alias only if it doesn't already exist
if (-not (Get-Command -Name 'slug' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'slug' alias for ConvertTo-UrlSlug"
        Set-Alias -Name 'slug' -Value 'ConvertTo-UrlSlug' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "ConvertTo-UrlSlug: Could not create 'slug' alias: $($_.Exception.Message)"
    }
}
