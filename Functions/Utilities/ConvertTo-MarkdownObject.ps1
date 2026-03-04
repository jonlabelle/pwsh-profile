function ConvertTo-MarkdownObject
{
    <#
    .SYNOPSIS
        Converts arbitrary PowerShell objects into Markdown text.

    .DESCRIPTION
        Renders PowerShell values (hashtables, PSCustomObjects, arrays/enumerables,
        and scalar values) into nested Markdown bullet lists.

        This function is pure PowerShell and does not require Pandoc.

        Use -ParseJsonStrings when you want JSON strings to be parsed and rendered
        as structured Markdown instead of being treated as plain strings.

    .PARAMETER InputObject
        The value to convert to Markdown.
        Supports pipeline input.

    .PARAMETER Depth
        Maximum recursion depth for nested objects and collections.
        When the limit is reached, `(max depth reached)` is emitted.

    .PARAMETER ParseJsonStrings
        Parses JSON strings that look like JSON objects/arrays and renders their
        structure as Markdown.

    .EXAMPLE
        PS > @{ Name = 'Jon'; Age = 42 } | ConvertTo-MarkdownObject

        - `Age`: `42`
        - `Name`: `Jon`

    .EXAMPLE
        PS > 1,2,@{Key='Value'} | ConvertTo-MarkdownObject

        - `[0]`: `1`
        - `[1]`: `2`
        - `[2]`
          - `Key`: `Value`

    .EXAMPLE
        PS > '{"name":"Jon","roles":["admin","dev"]}' | ConvertTo-MarkdownObject -ParseJsonStrings

        - `name`: `Jon`
        - `roles`
          - `[0]`: `admin`
          - `[1]`: `dev`

    .EXAMPLE
        PS > Get-Process | Select-Object -First 1 | ConvertTo-MarkdownObject -Depth 2

        Converts the first process object into Markdown with nested depth limited to 2.

    .OUTPUTS
        System.String

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-MarkdownObject.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-MarkdownObject.ps1
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [AllowNull()]
        [Alias('Value', 'Object')]
        [Object]$InputObject,

        [Parameter()]
        [ValidateRange(1, 100)]
        [Int32]$Depth = 6,

        [Parameter()]
        [Switch]$ParseJsonStrings
    )

    begin
    {
        $invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

        function Format-MarkdownCodeSpan
        {
            param(
                [AllowNull()]
                [Object]$Value
            )

            if ([Object]::ReferenceEquals($Value, $null))
            {
                return '`null`'
            }

            $text = [String]$Value
            $maxBacktickRun = 0
            foreach ($match in [System.Text.RegularExpressions.Regex]::Matches($text, '`+'))
            {
                if ($match.Length -gt $maxBacktickRun)
                {
                    $maxBacktickRun = $match.Length
                }
            }

            $delimiter = '`' * ($maxBacktickRun + 1)
            if ($text.StartsWith(' ') -or $text.EndsWith(' '))
            {
                return "$delimiter $text $delimiter"
            }

            return "$delimiter$text$delimiter"
        }

        function Format-ScalarValue
        {
            param(
                [AllowNull()]
                [Object]$Value
            )

            if ([Object]::ReferenceEquals($Value, $null))
            {
                return '`null`'
            }

            if ($Value -is [Boolean])
            {
                if ($Value)
                {
                    return '`true`'
                }
                return '`false`'
            }

            if ($Value -is [String])
            {
                if ($Value.Length -eq 0)
                {
                    return '`""`'
                }

                $normalized = $Value.Replace("`r`n", '\n').Replace("`n", '\n').Replace("`r", '\r')
                return Format-MarkdownCodeSpan -Value $normalized
            }

            if ($Value -is [System.IFormattable])
            {
                return Format-MarkdownCodeSpan -Value $Value.ToString($null, $invariantCulture)
            }

            return Format-MarkdownCodeSpan -Value ([String]$Value)
        }

        function Test-IsScalarValue
        {
            param(
                [AllowNull()]
                [Object]$Value
            )

            if ([Object]::ReferenceEquals($Value, $null))
            {
                return $true
            }

            if ($Value -is [String] -or
                $Value -is [Char] -or
                $Value -is [Boolean] -or
                $Value -is [Decimal] -or
                $Value -is [DateTime] -or
                $Value -is [DateTimeOffset] -or
                $Value -is [TimeSpan] -or
                $Value -is [Guid] -or
                $Value -is [Uri] -or
                $Value -is [Version] -or
                $Value -is [Enum])
            {
                return $true
            }

            return $Value.GetType().IsPrimitive
        }

        function Get-ParsedJsonValue
        {
            param(
                [AllowNull()]
                [Object]$Value
            )

            if (-not $ParseJsonStrings -or -not ($Value -is [String]))
            {
                return $Value
            }

            $trimmed = $Value.Trim()
            if ([String]::IsNullOrWhiteSpace($trimmed))
            {
                return $Value
            }

            $looksLikeJson = ($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) -or
            ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))

            if (-not $looksLikeJson)
            {
                return $Value
            }

            try
            {
                return ($trimmed | ConvertFrom-Json -ErrorAction Stop)
            }
            catch
            {
                return $Value
            }
        }

        function Add-MarkdownLine
        {
            param(
                [Parameter(Mandatory)]
                [AllowEmptyCollection()]
                [System.Collections.Generic.List[String]]$Lines,

                [Int32]$Level,

                [Parameter(Mandatory)]
                [String]$Text
            )

            $Lines.Add((('  ' * $Level) + '- ' + $Text))
        }

        function Invoke-MarkdownNode
        {
            param(
                [AllowNull()]
                [Object]$Value,

                [AllowNull()]
                [String]$Label,

                [Parameter(Mandatory)]
                [AllowEmptyCollection()]
                [System.Collections.Generic.List[String]]$Lines,

                [Parameter(Mandatory)]
                [Int32]$Level,

                [Parameter(Mandatory)]
                [Int32]$RemainingDepth,

                [Parameter(Mandatory)]
                [AllowEmptyCollection()]
                [System.Collections.Generic.HashSet[Int32]]$VisitedReferences
            )

            if ($Value -is [Array] -and $Value.Length -eq 0)
            {
                Write-MarkdownNode -Value (, $Value) -Label $Label -Lines $Lines -Level $Level -RemainingDepth $RemainingDepth -VisitedReferences $VisitedReferences
                return
            }

            Write-MarkdownNode -Value $Value -Label $Label -Lines $Lines -Level $Level -RemainingDepth $RemainingDepth -VisitedReferences $VisitedReferences
        }

        function Write-MarkdownNode
        {
            param(
                [AllowNull()]
                [Object]$Value,

                [AllowNull()]
                [String]$Label,

                [Parameter(Mandatory)]
                [AllowEmptyCollection()]
                [System.Collections.Generic.List[String]]$Lines,

                [Parameter(Mandatory)]
                [Int32]$Level,

                [Parameter(Mandatory)]
                [Int32]$RemainingDepth,

                [Parameter(Mandatory)]
                [AllowEmptyCollection()]
                [System.Collections.Generic.HashSet[Int32]]$VisitedReferences
            )

            $resolvedValue = Get-ParsedJsonValue -Value $Value
            $hasLabel = -not [String]::IsNullOrEmpty($Label)
            $labelPrefix = if ($hasLabel)
            {
                "$(Format-MarkdownCodeSpan -Value $Label): "
            }
            else
            {
                ''
            }

            if (Test-IsScalarValue -Value $resolvedValue)
            {
                Add-MarkdownLine -Lines $Lines -Level $Level -Text ($labelPrefix + (Format-ScalarValue -Value $resolvedValue))
                return
            }

            if ($RemainingDepth -le 0)
            {
                Add-MarkdownLine -Lines $Lines -Level $Level -Text ($labelPrefix + '`(max depth reached)`')
                return
            }

            $isReferenceType = -not [Object]::ReferenceEquals($resolvedValue, $null) -and
            -not $resolvedValue.GetType().IsValueType -and
            -not ($resolvedValue -is [String])

            $referenceId = 0
            if ($isReferenceType)
            {
                $referenceId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($resolvedValue)
                if ($VisitedReferences.Contains($referenceId))
                {
                    Add-MarkdownLine -Lines $Lines -Level $Level -Text ($labelPrefix + '`(circular reference)`')
                    return
                }

                $null = $VisitedReferences.Add($referenceId)
            }

            try
            {
                if ($resolvedValue -is [System.Collections.IDictionary])
                {
                    if ($hasLabel)
                    {
                        Add-MarkdownLine -Lines $Lines -Level $Level -Text (Format-MarkdownCodeSpan -Value $Label)
                    }

                    $childLevel = if ($hasLabel) { $Level + 1 } else { $Level }
                    $keys = @($resolvedValue.Keys)

                    if ($keys.Count -eq 0)
                    {
                        Add-MarkdownLine -Lines $Lines -Level $childLevel -Text '*(empty object)*'
                        return
                    }

                    if (-not ($resolvedValue -is [System.Collections.Specialized.OrderedDictionary]))
                    {
                        $keys = @($keys | Sort-Object { [String]$_ })
                    }

                    foreach ($key in $keys)
                    {
                        Invoke-MarkdownNode -Value $resolvedValue[$key] -Label ([String]$key) -Lines $Lines -Level $childLevel -RemainingDepth ($RemainingDepth - 1) -VisitedReferences $VisitedReferences
                    }

                    return
                }

                if ($resolvedValue -is [System.Collections.IEnumerable] -and -not ($resolvedValue -is [String]))
                {
                    if ($hasLabel)
                    {
                        Add-MarkdownLine -Lines $Lines -Level $Level -Text (Format-MarkdownCodeSpan -Value $Label)
                    }

                    $childLevel = if ($hasLabel) { $Level + 1 } else { $Level }
                    $items = @($resolvedValue)

                    if ($items.Count -eq 0)
                    {
                        Add-MarkdownLine -Lines $Lines -Level $childLevel -Text '*(empty array)*'
                        return
                    }

                    for ($index = 0; $index -lt $items.Count; $index++)
                    {
                        Invoke-MarkdownNode -Value $items[$index] -Label ('[{0}]' -f $index) -Lines $Lines -Level $childLevel -RemainingDepth ($RemainingDepth - 1) -VisitedReferences $VisitedReferences
                    }

                    return
                }

                $properties = @($resolvedValue.PSObject.Properties | Where-Object {
                        $_.IsGettable -and $_.MemberType -in @('NoteProperty', 'Property', 'AliasProperty')
                    })

                if ($properties.Count -gt 0)
                {
                    if ($hasLabel)
                    {
                        Add-MarkdownLine -Lines $Lines -Level $Level -Text (Format-MarkdownCodeSpan -Value $Label)
                    }

                    $childLevel = if ($hasLabel) { $Level + 1 } else { $Level }

                    foreach ($property in $properties)
                    {
                        $propertyValue = $null
                        try
                        {
                            $propertyValue = $property.Value
                        }
                        catch
                        {
                            $propertyValue = "<error: $($_.Exception.Message)>"
                        }

                        Invoke-MarkdownNode -Value $propertyValue -Label $property.Name -Lines $Lines -Level $childLevel -RemainingDepth ($RemainingDepth - 1) -VisitedReferences $VisitedReferences
                    }

                    return
                }

                Add-MarkdownLine -Lines $Lines -Level $Level -Text ($labelPrefix + (Format-MarkdownCodeSpan -Value ([String]$resolvedValue)))
            }
            finally
            {
                if ($isReferenceType)
                {
                    $null = $VisitedReferences.Remove($referenceId)
                }
            }
        }
    }

    process
    {
        $lines = [System.Collections.Generic.List[String]]::new()
        $visitedReferences = [System.Collections.Generic.HashSet[Int32]]::new()
        Invoke-MarkdownNode -Value $InputObject -Label $null -Lines $lines -Level 0 -RemainingDepth $Depth -VisitedReferences $visitedReferences
        Write-Output ($lines -join [Environment]::NewLine)
    }
}
