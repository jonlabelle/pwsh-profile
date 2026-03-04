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
        Use -AsTable to render compatible objects/collections as Markdown tables.

    .PARAMETER InputObject
        The value to convert to Markdown.
        Supports pipeline input.

    .PARAMETER Depth
        Maximum recursion depth for nested objects and collections.
        When the limit is reached, `(max depth reached)` is emitted.

    .PARAMETER ParseJsonStrings
        Parses JSON strings that look like JSON objects/arrays and renders their
        structure as Markdown.

    .PARAMETER AsTable
        Renders compatible values as Markdown tables:
        - Hashtables/objects with scalar values become Property/Value tables
        - Collections of scalar records become multi-column tables
        Values that are not table-friendly fall back to list rendering.

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

    .EXAMPLE
        PS > @(
            [ordered]@{ Name = 'Jon'; Role = 'Admin' },
            [ordered]@{ Name = 'Ava'; Role = 'Author' }
        ) | ConvertTo-MarkdownObject -AsTable

        Renders a Markdown table with Name and Role columns.

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
        [Switch]$ParseJsonStrings,

        [Parameter()]
        [Switch]$AsTable
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

        function Add-MarkdownTextLine
        {
            param(
                [Parameter(Mandatory)]
                [AllowEmptyCollection()]
                [System.Collections.Generic.List[String]]$Lines,

                [Int32]$Level,

                [Parameter(Mandatory)]
                [String]$Text
            )

            $Lines.Add((('  ' * $Level) + $Text))
        }

        function Format-MarkdownTableCell
        {
            param(
                [AllowNull()]
                [Object]$Value
            )

            if ([Object]::ReferenceEquals($Value, $null))
            {
                return 'null'
            }

            if ($Value -is [Boolean])
            {
                if ($Value)
                {
                    return 'true'
                }
                return 'false'
            }

            if ($Value -is [String])
            {
                $text = $Value.Replace("`r`n", '\n').Replace("`n", '\n').Replace("`r", '\r')
                return $text.Replace('|', '\|')
            }

            if ($Value -is [System.IFormattable])
            {
                return $Value.ToString($null, $invariantCulture).Replace('|', '\|')
            }

            return ([String]$Value).Replace('|', '\|')
        }

        function Get-DictionaryEntries
        {
            param(
                [Parameter(Mandatory)]
                [System.Collections.IDictionary]$Dictionary
            )

            $keys = @($Dictionary.Keys)
            if (-not ($Dictionary -is [System.Collections.Specialized.OrderedDictionary]))
            {
                $keys = @($keys | Sort-Object { [String]$_ })
            }

            $entries = [System.Collections.Generic.List[Object]]::new()
            foreach ($key in $keys)
            {
                $entries.Add([PSCustomObject]@{
                        Name = [String]$key
                        Value = $Dictionary[$key]
                    })
            }

            return $entries
        }

        function Get-ObjectPropertyEntries
        {
            param(
                [Parameter(Mandatory)]
                [Object]$Object
            )

            $entries = [System.Collections.Generic.List[Object]]::new()
            $properties = @($Object.PSObject.Properties | Where-Object {
                    $_.IsGettable -and $_.MemberType -in @('NoteProperty', 'Property', 'AliasProperty')
                })

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

                $entries.Add([PSCustomObject]@{
                        Name = [String]$property.Name
                        Value = $propertyValue
                    })
            }

            return $entries
        }

        function Try-GetScalarMap
        {
            param(
                [AllowNull()]
                [Object]$Value,

                [Parameter(Mandatory)]
                [Ref]$Map
            )

            $Map.Value = $null

            if ([Object]::ReferenceEquals($Value, $null))
            {
                return $false
            }

            $candidate = Get-ParsedJsonValue -Value $Value
            if (Test-IsScalarValue -Value $candidate)
            {
                return $false
            }

            $entries = $null
            if ($candidate -is [System.Collections.IDictionary])
            {
                $entries = Get-DictionaryEntries -Dictionary $candidate
            }
            else
            {
                if ($candidate -is [System.Collections.IEnumerable] -and -not ($candidate -is [String]))
                {
                    return $false
                }

                $entries = Get-ObjectPropertyEntries -Object $candidate
            }

            if ($entries.Count -eq 0)
            {
                return $false
            }

            $rowMap = [ordered]@{}
            foreach ($entry in $entries)
            {
                if (-not (Test-IsScalarValue -Value $entry.Value))
                {
                    return $false
                }

                $rowMap[$entry.Name] = $entry.Value
            }

            if ($rowMap.Count -eq 0)
            {
                return $false
            }

            $Map.Value = $rowMap
            return $true
        }

        function Try-WriteTableForScalarMap
        {
            param(
                [AllowNull()]
                [Object]$Value,

                [Boolean]$HasLabel,

                [AllowNull()]
                [String]$Label,

                [Parameter(Mandatory)]
                [AllowEmptyCollection()]
                [System.Collections.Generic.List[String]]$Lines,

                [Parameter(Mandatory)]
                [Int32]$Level
            )

            if (-not $AsTable)
            {
                return $false
            }

            $rowMap = $null
            if (-not (Try-GetScalarMap -Value $Value -Map ([Ref]$rowMap)))
            {
                return $false
            }

            if ($HasLabel)
            {
                Add-MarkdownLine -Lines $Lines -Level $Level -Text (Format-MarkdownCodeSpan -Value $Label)
            }

            $tableLevel = if ($HasLabel) { $Level + 1 } else { $Level }

            Add-MarkdownTextLine -Lines $Lines -Level $tableLevel -Text '| Property | Value |'
            Add-MarkdownTextLine -Lines $Lines -Level $tableLevel -Text '| --- | --- |'
            foreach ($key in $rowMap.Keys)
            {
                $propertyCell = Format-MarkdownTableCell -Value ([String]$key)
                $valueCell = Format-MarkdownTableCell -Value $rowMap[$key]
                Add-MarkdownTextLine -Lines $Lines -Level $tableLevel -Text ('| {0} | {1} |' -f $propertyCell, $valueCell)
            }

            return $true
        }

        function Try-WriteTableForEnumerable
        {
            param(
                [AllowNull()]
                [Object]$Value,

                [Boolean]$HasLabel,

                [AllowNull()]
                [String]$Label,

                [Parameter(Mandatory)]
                [AllowEmptyCollection()]
                [System.Collections.Generic.List[String]]$Lines,

                [Parameter(Mandatory)]
                [Int32]$Level
            )

            if (-not $AsTable -or
                [Object]::ReferenceEquals($Value, $null) -or
                ($Value -is [String]) -or
                ($Value -is [System.Collections.IDictionary]) -or
                -not ($Value -is [System.Collections.IEnumerable]))
            {
                return $false
            }

            $items = @($Value)
            if ($items.Count -eq 0)
            {
                return $false
            }

            $allScalar = $true
            foreach ($item in $items)
            {
                if (-not (Test-IsScalarValue -Value (Get-ParsedJsonValue -Value $item)))
                {
                    $allScalar = $false
                    break
                }
            }

            if ($allScalar)
            {
                if ($HasLabel)
                {
                    Add-MarkdownLine -Lines $Lines -Level $Level -Text (Format-MarkdownCodeSpan -Value $Label)
                }

                $tableLevel = if ($HasLabel) { $Level + 1 } else { $Level }
                Add-MarkdownTextLine -Lines $Lines -Level $tableLevel -Text '| Value |'
                Add-MarkdownTextLine -Lines $Lines -Level $tableLevel -Text '| --- |'
                foreach ($item in $items)
                {
                    $valueCell = Format-MarkdownTableCell -Value (Get-ParsedJsonValue -Value $item)
                    Add-MarkdownTextLine -Lines $Lines -Level $tableLevel -Text ('| {0} |' -f $valueCell)
                }

                return $true
            }

            $rows = [System.Collections.Generic.List[Object]]::new()
            $columns = [System.Collections.Generic.List[String]]::new()
            $columnLookup = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($item in $items)
            {
                $rowMap = $null
                if (-not (Try-GetScalarMap -Value $item -Map ([Ref]$rowMap)))
                {
                    return $false
                }

                $rows.Add($rowMap)
                foreach ($key in $rowMap.Keys)
                {
                    $columnName = [String]$key
                    if ($columnLookup.Add($columnName))
                    {
                        $columns.Add($columnName)
                    }
                }
            }

            if ($columns.Count -eq 0)
            {
                return $false
            }

            if ($HasLabel)
            {
                Add-MarkdownLine -Lines $Lines -Level $Level -Text (Format-MarkdownCodeSpan -Value $Label)
            }

            $tableLevel = if ($HasLabel) { $Level + 1 } else { $Level }
            $headerCells = @($columns | ForEach-Object { Format-MarkdownTableCell -Value $_ })
            Add-MarkdownTextLine -Lines $Lines -Level $tableLevel -Text ('| ' + ($headerCells -join ' | ') + ' |')
            Add-MarkdownTextLine -Lines $Lines -Level $tableLevel -Text ('| ' + ((@($columns | ForEach-Object { '---' })) -join ' | ') + ' |')

            foreach ($row in $rows)
            {
                $rowCells = [System.Collections.Generic.List[String]]::new()
                foreach ($column in $columns)
                {
                    if (@($row.Keys) -contains $column)
                    {
                        $rowCells.Add((Format-MarkdownTableCell -Value $row[$column]))
                    }
                    else
                    {
                        $rowCells.Add('')
                    }
                }

                Add-MarkdownTextLine -Lines $Lines -Level $tableLevel -Text ('| ' + ($rowCells -join ' | ') + ' |')
            }

            return $true
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

            if (Try-WriteTableForEnumerable -Value $resolvedValue -HasLabel $hasLabel -Label $Label -Lines $Lines -Level $Level)
            {
                return
            }

            if (Try-WriteTableForScalarMap -Value $resolvedValue -HasLabel $hasLabel -Label $Label -Lines $Lines -Level $Level)
            {
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
                    $entries = Get-DictionaryEntries -Dictionary $resolvedValue

                    if ($entries.Count -eq 0)
                    {
                        Add-MarkdownLine -Lines $Lines -Level $childLevel -Text '*(empty object)*'
                        return
                    }

                    foreach ($entry in $entries)
                    {
                        Invoke-MarkdownNode -Value $entry.Value -Label $entry.Name -Lines $Lines -Level $childLevel -RemainingDepth ($RemainingDepth - 1) -VisitedReferences $VisitedReferences
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

                $properties = Get-ObjectPropertyEntries -Object $resolvedValue

                if ($properties.Count -gt 0)
                {
                    if ($hasLabel)
                    {
                        Add-MarkdownLine -Lines $Lines -Level $Level -Text (Format-MarkdownCodeSpan -Value $Label)
                    }

                    $childLevel = if ($hasLabel) { $Level + 1 } else { $Level }

                    foreach ($property in $properties)
                    {
                        Invoke-MarkdownNode -Value $property.Value -Label $property.Name -Lines $Lines -Level $childLevel -RemainingDepth ($RemainingDepth - 1) -VisitedReferences $VisitedReferences
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
