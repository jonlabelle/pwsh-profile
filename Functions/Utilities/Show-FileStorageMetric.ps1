function Show-FileStorageMetric
{
    <#
    .SYNOPSIS
        Calculates file storage metrics and displays a graphical summary.

    .DESCRIPTION
        Scans one or more file-system paths, applies file-name, date, and size criteria,
        and calculates storage statistics. The default output is a compact text dashboard
        with daily activity bars, file-type totals, top directories, and largest files.
        Unicode framing and a single teal ANSI accent give the dashboard a restrained
        monochrome appearance.

        Use -AsObject for automation. The returned report contains raw byte values and
        nested DailyBreakdown, ExtensionBreakdown, PathBreakdown, DirectoryBreakdown,
        and LargestFiles collections.

        Days is inclusive of the reference date. For example, -Days 0 includes only the
        reference calendar date, while -Days 2 includes the reference date and the two
        preceding calendar dates. The default reference date is today. Use -AllDates to
        disable date filtering.

        Filter accepts one or more wildcard file-name patterns. Multiple filters are
        combined with OR logic. Exclude patterns are applied after Filter.

    .PARAMETER Path
        One or more files or directories to inspect. Wildcards and pipeline input are
        supported. Directories are not traversed recursively unless -Recurse is used.
        Defaults to the current location.

    .PARAMETER Filter
        One or more wildcard file-name patterns, such as '*.log' or @('*.jpg', '*.png').
        Defaults to '*'.

    .PARAMETER Exclude
        One or more wildcard file-name patterns to exclude after Filter is applied.

    .PARAMETER Days
        Number of calendar days to look back from ReferenceDate. Zero includes only the
        reference date and is the default. The resulting range contains Days + 1 dates.

    .PARAMETER AllDates
        Disables date filtering and includes matching files regardless of their date.
        Cannot be combined with an explicitly supplied Days or ReferenceDate value.

    .PARAMETER ReferenceDate
        Calendar date used as the end of the date window. Defaults to today. Time-of-day
        is ignored. This is useful for repeatable historical reports.

    .PARAMETER DateField
        File date property used for filtering and daily grouping. Valid values are
        CreationTime, LastWriteTime, and LastAccessTime. Defaults to CreationTime.

    .PARAMETER Recurse
        Searches all subdirectories beneath directory paths.

    .PARAMETER IncludeHidden
        Includes hidden and system files by passing Force to file enumeration.

    .PARAMETER MinimumSizeBytes
        Minimum file size in bytes. Defaults to zero.

    .PARAMETER MaximumSizeBytes
        Optional maximum file size in bytes.

    .PARAMETER Top
        Number of largest files to include in the dashboard and LargestFiles collection.
        Use zero to omit the largest-files section. Defaults to 5.

    .PARAMETER BarWidth
        Width, in characters, of graphical percentage bars. Defaults to 18.

    .PARAMETER DisplayLimit
        Maximum rows shown in each dashboard breakdown. Complete breakdown collections
        remain available with -AsObject. Defaults to 14.

    .PARAMETER AsObject
        Returns a structured report object instead of the graphical dashboard.

    .PARAMETER CsvPath
        Optional path for a CSV export. The parent directory must already exist and the
        file name must use a .csv extension. CSV files are written as UTF-8 with BOM.

    .PARAMETER CsvGroupBy
        Selects the flat record set exported through CsvPath:
        Summary, Day, Extension, Path, Directory, or File. Defaults to Day.

    .PARAMETER OverwriteCsv
        Allows CsvPath to overwrite an existing file. Requires CsvPath.

    .EXAMPLE
        PS > Show-FileStorageMetric

        Displays metrics for files created today in the current directory.

    .EXAMPLE
        PS > Show-FileStorageMetric -Path ./logs -Filter '*.log', '*.json' -Days 7 -DateField LastWriteTime -Recurse

        Displays an eight-date report (today plus the preceding seven dates) for log and
        JSON files, grouped by LastWriteTime.

    .EXAMPLE
        PS > $report = Show-FileStorageMetric -Path ./media -Filter '*.jpg', '*.png' -AllDates -Recurse -AsObject
        PS > $report.ExtensionBreakdown | Sort-Object TotalBytes -Descending

        Returns structured metrics for all matching image files.

    .EXAMPLE
        PS > Show-FileStorageMetric -Path ./exports -Days 30 -DateField LastWriteTime -CsvPath ./daily-storage.csv

        Displays the dashboard and exports the daily breakdown to a UTF-8 CSV file.

    .EXAMPLE
        PS > Show-FileStorageMetric -Path ./artifacts -AllDates -Recurse -CsvPath ./files.csv -CsvGroupBy File -AsObject

        Returns a structured report and exports one CSV row per matching file.

    .EXAMPLE
        PS > Get-ChildItem -Directory ./projects | Show-FileStorageMetric -Filter '*.zip' -AllDates -Recurse -AsObject

        Aggregates matching ZIP files from directory paths received through the pipeline.

    .OUTPUTS
        System.String
        System.Management.Automation.PSCustomObject

    .NOTES
        Calendar boundaries use the local DateTime values exposed by FileInfo.
        Overlapping input paths are de-duplicated by full file path.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Show-FileStorageMetric.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Show-FileStorageMetric.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.String], [System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'PSPath')]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path = (Get-Location).Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$Filter = @('*'),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$Exclude,

        [Parameter()]
        [ValidateRange(0, 365000)]
        [Int32]$Days = 0,

        [Parameter()]
        [Switch]$AllDates,

        [Parameter()]
        [DateTime]$ReferenceDate = (Get-Date).Date,

        [Parameter()]
        [ValidateSet('CreationTime', 'LastWriteTime', 'LastAccessTime')]
        [String]$DateField = 'CreationTime',

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [Switch]$IncludeHidden,

        [Parameter()]
        [ValidateRange(0, [Int64]::MaxValue)]
        [Int64]$MinimumSizeBytes = 0,

        [Parameter()]
        [ValidateRange(0, [Int64]::MaxValue)]
        [Nullable[Int64]]$MaximumSizeBytes,

        [Parameter()]
        [ValidateRange(0, 100)]
        [Int32]$Top = 5,

        [Parameter()]
        [ValidateRange(5, 80)]
        [Int32]$BarWidth = 18,

        [Parameter()]
        [ValidateRange(1, 100)]
        [Int32]$DisplayLimit = 14,

        [Parameter()]
        [Switch]$AsObject,

        [Parameter()]
        [String]$CsvPath,

        [Parameter()]
        [ValidateSet('Summary', 'Day', 'Extension', 'Path', 'Directory', 'File')]
        [String]$CsvGroupBy = 'Day',

        [Parameter()]
        [Switch]$OverwriteCsv
    )

    begin
    {
        $inputPaths = New-Object 'System.Collections.Generic.List[String]'
        $daysWasSpecified = $PSBoundParameters.ContainsKey('Days')
        $referenceDateWasSpecified = $PSBoundParameters.ContainsKey('ReferenceDate')
        $csvGroupByWasSpecified = $PSBoundParameters.ContainsKey('CsvGroupBy')

        function Test-WildcardPatternMatch
        {
            param(
                [Parameter(Mandatory)]
                [String]$Value,

                [Parameter()]
                [AllowNull()]
                [String[]]$Pattern
            )

            foreach ($currentPattern in @($Pattern))
            {
                if ($Value -like $currentPattern)
                {
                    return $true
                }
            }

            return $false
        }

        function Format-StorageSize
        {
            param(
                [Parameter()]
                [AllowNull()]
                [Object]$Bytes
            )

            if ($null -eq $Bytes)
            {
                return 'n/a'
            }

            $numericBytes = [Decimal]$Bytes
            $absoluteBytes = [Math]::Abs($numericBytes)
            $units = @(
                [PSCustomObject]@{ Threshold = [Decimal]1PB; Divisor = [Decimal]1PB; Label = 'PiB' },
                [PSCustomObject]@{ Threshold = [Decimal]1TB; Divisor = [Decimal]1TB; Label = 'TiB' },
                [PSCustomObject]@{ Threshold = [Decimal]1GB; Divisor = [Decimal]1GB; Label = 'GiB' },
                [PSCustomObject]@{ Threshold = [Decimal]1MB; Divisor = [Decimal]1MB; Label = 'MiB' },
                [PSCustomObject]@{ Threshold = [Decimal]1KB; Divisor = [Decimal]1KB; Label = 'KiB' }
            )

            foreach ($unit in $units)
            {
                if ($absoluteBytes -ge $unit.Threshold)
                {
                    return '{0:N2} {1}' -f ($numericBytes / $unit.Divisor), $unit.Label
                }
            }

            return '{0:N0} B' -f $numericBytes
        }

        function Get-SizeStatistics
        {
            param(
                [Parameter(Mandatory)]
                [AllowNull()]
                [AllowEmptyCollection()]
                [Object[]]$Record
            )

            $records = @($Record | Where-Object { $null -ne $_ })
            if ($records.Count -eq 0)
            {
                return [PSCustomObject]@{
                    FileCount                  = 0
                    TotalBytes                 = [Decimal]0
                    AverageBytes               = $null
                    MedianBytes                = $null
                    Percentile95Bytes          = $null
                    SizeStandardDeviationBytes = $null
                    MinimumBytes               = $null
                    MaximumBytes               = $null
                    ZeroByteFileCount           = 0
                }
            }

            $sizes = @(
                $records |
                ForEach-Object { [Int64]$_.LengthBytes } |
                Sort-Object
            )

            [Decimal]$totalBytes = 0
            [Int32]$zeroByteFileCount = 0
            foreach ($size in $sizes)
            {
                $totalBytes += [Decimal]$size
                if ($size -eq 0)
                {
                    $zeroByteFileCount++
                }
            }

            $averageBytes = [Double]($totalBytes / $sizes.Count)
            $middleIndex = [Math]::Floor($sizes.Count / 2)
            $medianBytes = if (($sizes.Count % 2) -eq 1)
            {
                [Double]$sizes[$middleIndex]
            }
            else
            {
                ([Double]$sizes[$middleIndex - 1] + [Double]$sizes[$middleIndex]) / 2
            }

            $percentile95Index = [Math]::Max(0, [Math]::Ceiling($sizes.Count * 0.95) - 1)
            $sumSquaredDifferences = [Double]0
            foreach ($size in $sizes)
            {
                $difference = [Double]$size - $averageBytes
                $sumSquaredDifferences += $difference * $difference
            }

            return [PSCustomObject]@{
                FileCount                  = $sizes.Count
                TotalBytes                 = $totalBytes
                AverageBytes               = [Math]::Round($averageBytes, 2)
                MedianBytes                = [Math]::Round($medianBytes, 2)
                Percentile95Bytes          = [Double]$sizes[$percentile95Index]
                SizeStandardDeviationBytes = [Math]::Round([Math]::Sqrt($sumSquaredDifferences / $sizes.Count), 2)
                MinimumBytes               = [Int64]$sizes[0]
                MaximumBytes               = [Int64]$sizes[$sizes.Count - 1]
                ZeroByteFileCount           = $zeroByteFileCount
            }
        }

        function Get-Percentage
        {
            param(
                [Parameter(Mandatory)]
                [Decimal]$Value,

                [Parameter(Mandatory)]
                [Decimal]$Total
            )

            if ($Total -eq 0)
            {
                return [Double]0
            }

            return [Math]::Round([Double](($Value / $Total) * 100), 2)
        }

        function Add-StorageBucketRecord
        {
            param(
                [Parameter(Mandatory)]
                [Hashtable]$Bucket,

                [Parameter(Mandatory)]
                [String]$Key,

                [Parameter(Mandatory)]
                [Object]$Record
            )

            if (-not $Bucket.ContainsKey($Key))
            {
                $Bucket[$Key] = New-Object 'System.Collections.Generic.List[Object]'
            }

            [void]$Bucket[$Key].Add($Record)
        }

        function Get-StorageBreakdownRow
        {
            param(
                [Parameter(Mandatory)]
                [String]$TypeName,

                [Parameter(Mandatory)]
                [String]$GroupProperty,

                [Parameter(Mandatory)]
                [Object]$GroupValue,

                [Parameter(Mandatory)]
                [AllowNull()]
                [AllowEmptyCollection()]
                [Object[]]$Record,

                [Parameter(Mandatory)]
                [Int32]$TotalFileCount,

                [Parameter(Mandatory)]
                [Decimal]$ReportTotalBytes
            )

            $statistics = Get-SizeStatistics -Record $Record
            $properties = [Ordered]@{
                PSTypeName          = $TypeName
            }
            $properties[$GroupProperty] = $GroupValue
            $properties['FileCount'] = $statistics.FileCount
            $properties['TotalBytes'] = $statistics.TotalBytes
            $properties['AverageBytes'] = $statistics.AverageBytes
            $properties['MedianBytes'] = $statistics.MedianBytes
            $properties['MinimumBytes'] = $statistics.MinimumBytes
            $properties['MaximumBytes'] = $statistics.MaximumBytes
            $properties['ZeroByteFileCount'] = $statistics.ZeroByteFileCount
            $properties['PercentOfFiles'] = Get-Percentage -Value ([Decimal]$statistics.FileCount) -Total ([Decimal]$TotalFileCount)
            $properties['PercentOfTotalBytes'] = Get-Percentage -Value $statistics.TotalBytes -Total $ReportTotalBytes

            return [PSCustomObject]$properties
        }

        function Get-GraphBar
        {
            param(
                [Parameter(Mandatory)]
                [Double]$Percentage,

                [Parameter()]
                [ValidateRange(1, 80)]
                [Int32]$Width = $BarWidth
            )

            $boundedPercentage = [Math]::Max(0, [Math]::Min(100, $Percentage))
            $filledCount = [Int32][Math]::Round(($boundedPercentage / 100) * $Width)
            if ($boundedPercentage -gt 0 -and $filledCount -eq 0)
            {
                $filledCount = 1
            }

            $filledCount = [Math]::Min($Width, $filledCount)
            $emptyCount = $Width - $filledCount
            $filledCharacter = [String][Char]0x2588
            $emptyCharacter = [String][Char]0x2591

            return ($filledCharacter * $filledCount) + ($emptyCharacter * $emptyCount)
        }

        function Limit-StorageText
        {
            param(
                [Parameter(Mandatory)]
                [AllowEmptyString()]
                [String]$Text,

                [Parameter(Mandatory)]
                [ValidateRange(4, 500)]
                [Int32]$Width
            )

            if ($Text.Length -le $Width)
            {
                return $Text
            }

            return $Text.Substring(0, $Width - 3) + '...'
        }

        function Get-CsvExportData
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Report,

                [Parameter(Mandatory)]
                [AllowNull()]
                [AllowEmptyCollection()]
                [Object[]]$FileRecord,

                [Parameter(Mandatory)]
                [String]$Grouping
            )

            switch ($Grouping)
            {
                'Summary'
                {
                    $columns = @(
                        'GeneratedAt', 'Paths', 'Filter', 'Exclude', 'DateField',
                        'DateWindowStart', 'DateWindowEnd', 'AllDates', 'Recurse',
                        'ScannedFileCount', 'NameMatchedFileCount', 'FileCount',
                        'TotalBytes', 'AverageBytes', 'MedianBytes', 'Percentile95Bytes',
                        'SizeStandardDeviationBytes', 'MinimumBytes', 'MaximumBytes',
                        'ZeroByteFileCount', 'ActiveDayCount', 'CalendarDayCount',
                        'DuplicateFileCount', 'EnumerationErrorCount'
                    )
                    $records = @(
                        [PSCustomObject][Ordered]@{
                            GeneratedAt                = $Report.GeneratedAt.ToString('o')
                            Paths                      = [String]::Join('; ', [String[]]$Report.Paths)
                            Filter                     = [String]::Join('; ', [String[]]$Report.Filter)
                            Exclude                    = [String]::Join('; ', [String[]]@($Report.Exclude))
                            DateField                  = $Report.DateField
                            DateWindowStart            = if ($Report.DateWindowStart) { $Report.DateWindowStart.ToString('yyyy-MM-dd') } else { $null }
                            DateWindowEnd              = if ($Report.DateWindowEnd) { $Report.DateWindowEnd.ToString('yyyy-MM-dd') } else { $null }
                            AllDates                   = $Report.AllDates
                            Recurse                    = $Report.Recurse
                            ScannedFileCount           = $Report.ScannedFileCount
                            NameMatchedFileCount       = $Report.NameMatchedFileCount
                            FileCount                  = $Report.FileCount
                            TotalBytes                 = $Report.TotalBytes
                            AverageBytes               = $Report.AverageBytes
                            MedianBytes                = $Report.MedianBytes
                            Percentile95Bytes          = $Report.Percentile95Bytes
                            SizeStandardDeviationBytes = $Report.SizeStandardDeviationBytes
                            MinimumBytes               = $Report.MinimumBytes
                            MaximumBytes               = $Report.MaximumBytes
                            ZeroByteFileCount           = $Report.ZeroByteFileCount
                            ActiveDayCount              = $Report.ActiveDayCount
                            CalendarDayCount            = $Report.CalendarDayCount
                            DuplicateFileCount          = $Report.DuplicateFileCount
                            EnumerationErrorCount       = $Report.EnumerationErrorCount
                        }
                    )
                }
                'Day'
                {
                    $columns = @(
                        'Date', 'FileCount', 'TotalBytes', 'AverageBytes', 'MedianBytes',
                        'MinimumBytes', 'MaximumBytes', 'ZeroByteFileCount',
                        'PercentOfFiles', 'PercentOfTotalBytes'
                    )
                    $records = @(
                        $Report.DailyBreakdown |
                        ForEach-Object {
                            [PSCustomObject][Ordered]@{
                                Date                    = $_.Date.ToString('yyyy-MM-dd')
                                FileCount               = $_.FileCount
                                TotalBytes              = $_.TotalBytes
                                AverageBytes            = $_.AverageBytes
                                MedianBytes             = $_.MedianBytes
                                MinimumBytes            = $_.MinimumBytes
                                MaximumBytes            = $_.MaximumBytes
                                ZeroByteFileCount       = $_.ZeroByteFileCount
                                PercentOfFiles          = $_.PercentOfFiles
                                PercentOfTotalBytes     = $_.PercentOfTotalBytes
                            }
                        }
                    )
                }
                'Extension'
                {
                    $columns = @(
                        'Extension', 'FileCount', 'TotalBytes', 'AverageBytes', 'MedianBytes',
                        'MinimumBytes', 'MaximumBytes', 'ZeroByteFileCount',
                        'PercentOfFiles', 'PercentOfTotalBytes'
                    )
                    $records = @($Report.ExtensionBreakdown)
                }
                'Path'
                {
                    $columns = @(
                        'Path', 'FileCount', 'TotalBytes', 'AverageBytes', 'MedianBytes',
                        'MinimumBytes', 'MaximumBytes', 'ZeroByteFileCount',
                        'PercentOfFiles', 'PercentOfTotalBytes'
                    )
                    $records = @($Report.PathBreakdown)
                }
                'Directory'
                {
                    $columns = @(
                        'Directory', 'FileCount', 'TotalBytes', 'AverageBytes', 'MedianBytes',
                        'MinimumBytes', 'MaximumBytes', 'ZeroByteFileCount',
                        'PercentOfFiles', 'PercentOfTotalBytes'
                    )
                    $records = @($Report.DirectoryBreakdown)
                }
                'File'
                {
                    $columns = @(
                        'Path', 'Name', 'Directory', 'Extension', 'LengthBytes', 'FileDate',
                        'CreationTime', 'LastWriteTime', 'LastAccessTime', 'SourcePath'
                    )
                    $records = @(
                        $FileRecord |
                        ForEach-Object {
                            [PSCustomObject][Ordered]@{
                                Path           = $_.Path
                                Name           = $_.Name
                                Directory      = $_.Directory
                                Extension      = $_.Extension
                                LengthBytes    = $_.LengthBytes
                                FileDate       = $_.FileDate.ToString('o')
                                CreationTime   = $_.CreationTime.ToString('o')
                                LastWriteTime  = $_.LastWriteTime.ToString('o')
                                LastAccessTime = $_.LastAccessTime.ToString('o')
                                SourcePath     = $_.SourcePath
                            }
                        }
                    )
                }
            }

            return [PSCustomObject]@{
                Columns = [String[]]$columns
                Records = [Object[]]$records
            }
        }

        function Write-StorageCsv
        {
            param(
                [Parameter(Mandatory)]
                [String]$OutputPath,

                [Parameter(Mandatory)]
                [String[]]$Column,

                [Parameter(Mandatory)]
                [AllowNull()]
                [AllowEmptyCollection()]
                [Object[]]$Record
            )

            $records = @($Record | Where-Object { $null -ne $_ })
            if ($records.Count -gt 0)
            {
                $csvLines = @(
                    $records |
                    Select-Object -Property $Column |
                    ConvertTo-Csv -NoTypeInformation
                )
            }
            else
            {
                $emptyValues = [Ordered]@{}
                foreach ($columnName in $Column)
                {
                    $emptyValues[$columnName] = $null
                }

                $templateLines = @(
                    [PSCustomObject]$emptyValues |
                    ConvertTo-Csv -NoTypeInformation
                )
                $csvLines = @($templateLines[0])
            }

            $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllLines($OutputPath, [String[]]$csvLines, $utf8WithBom)
        }

        function Format-StorageDashboard
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Report
            )

            $dashboardWidth = 104
            $horizontal = [String][Char]0x2500
            $vertical = [String][Char]0x2502
            $topLeft = [String][Char]0x256D
            $topRight = [String][Char]0x256E
            $bottomLeft = [String][Char]0x2570
            $bottomRight = [String][Char]0x256F
            $arrow = [String][Char]0x2192
            $bullet = [String][Char]0x2022
            $statusDot = [String][Char]0x25CF
            $escapeCharacter = [String][Char]27
            $accentStart = $escapeCharacter + '[38;5;37m'
            $accentReset = $escapeCharacter + '[0m'

            function Format-DashboardAccent
            {
                param(
                    [Parameter(Mandatory)]
                    [AllowEmptyString()]
                    [String]$Text
                )

                return $accentStart + $Text + $accentReset
            }

            function Get-DashboardLeftRight
            {
                param(
                    [Parameter(Mandatory)]
                    [String]$Left,

                    [Parameter(Mandatory)]
                    [String]$Right,

                    [Parameter(Mandatory)]
                    [Int32]$Width
                )

                $rightText = Limit-StorageText -Text $Right -Width ([Math]::Min(32, $Width - 8))
                $leftWidth = [Math]::Max(4, $Width - $rightText.Length - 1)
                $leftText = Limit-StorageText -Text $Left -Width $leftWidth
                return $leftText.PadRight($Width - $rightText.Length) + $rightText
            }

            function Get-DashboardFrameLine
            {
                param(
                    [Parameter(Mandatory)]
                    [AllowEmptyString()]
                    [String]$Text
                )

                $contentWidth = $dashboardWidth - 4
                $content = Limit-StorageText -Text $Text -Width $contentWidth
                return (Format-DashboardAccent -Text $vertical) +
                    ' ' + $content.PadRight($contentWidth) + ' ' +
                    (Format-DashboardAccent -Text $vertical)
            }

            function Get-DashboardKpiCard
            {
                param(
                    [Parameter(Mandatory)]
                    [String]$Label,

                    [Parameter(Mandatory)]
                    [String]$Value,

                    [Parameter(Mandatory)]
                    [String]$Hint,

                    [Parameter(Mandatory)]
                    [Int32]$Width
                )

                $innerWidth = $Width - 2
                $labelText = (' ' + (Limit-StorageText -Text $Label.ToUpperInvariant() -Width ($innerWidth - 1))).PadRight($innerWidth)
                $valueText = (' ' + (Limit-StorageText -Text $Value -Width ($innerWidth - 1))).PadRight($innerWidth)
                $hintText = (' ' + (Limit-StorageText -Text $Hint -Width ($innerWidth - 1))).PadRight($innerWidth)
                $accentVertical = Format-DashboardAccent -Text $vertical

                return @(
                    (Format-DashboardAccent -Text ($topLeft + ($horizontal * $innerWidth) + $topRight)),
                    ($accentVertical + (Format-DashboardAccent -Text $labelText) + $accentVertical),
                    ($accentVertical + $valueText + $accentVertical),
                    ($accentVertical + $hintText + $accentVertical),
                    (Format-DashboardAccent -Text ($bottomLeft + ($horizontal * $innerWidth) + $bottomRight))
                )
            }

            function Get-DashboardPanel
            {
                param(
                    [Parameter(Mandatory)]
                    [String]$Title,

                    [Parameter(Mandatory)]
                    [AllowNull()]
                    [AllowEmptyCollection()]
                    [String[]]$Row,

                    [Parameter(Mandatory)]
                    [Int32]$Width,

                    [Parameter(Mandatory)]
                    [Int32]$RowCount
                )

                $titleToken = ' ' + $Title.ToUpperInvariant() + ' '
                $topRuleWidth = [Math]::Max(0, $Width - $titleToken.Length - 2)
                $contentWidth = $Width - 4
                $rows = @($Row)
                $panelLines = New-Object 'System.Collections.Generic.List[String]'
                $accentVertical = Format-DashboardAccent -Text $vertical

                [void]$panelLines.Add((Format-DashboardAccent -Text ($topLeft + $titleToken + ($horizontal * $topRuleWidth) + $topRight)))
                for ($index = 0; $index -lt $RowCount; $index++)
                {
                    $rowText = if ($index -lt $rows.Count) { $rows[$index] } else { '' }
                    $rowText = Limit-StorageText -Text $rowText -Width $contentWidth
                    [void]$panelLines.Add($accentVertical + ' ' + $rowText.PadRight($contentWidth) + ' ' + $accentVertical)
                }
                [void]$panelLines.Add((Format-DashboardAccent -Text ($bottomLeft + ($horizontal * ($Width - 2)) + $bottomRight)))

                return @($panelLines.ToArray())
            }

            $lines = New-Object 'System.Collections.Generic.List[String]'
            $dateRangeText = if ($Report.AllDates)
            {
                'all dates'
            }
            else
            {
                '{0:yyyy-MM-dd} {1} {2:yyyy-MM-dd}' -f $Report.DateWindowStart, $arrow, $Report.DateWindowEnd
            }
            $maximumSizeText = if ($null -eq $Report.MaximumSizeBytes)
            {
                'unlimited'
            }
            else
            {
                Format-StorageSize -Bytes $Report.MaximumSizeBytes
            }
            $scanMode = if ($Report.Recurse) { 'recursive' } else { 'current level' }
            $headerTitle = Get-DashboardLeftRight -Left 'FILE STORAGE / DASHBOARD' -Right $Report.GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss') -Width ($dashboardWidth - 4)
            $scopeText = '{0}  {1}  {2}  {1}  {3}' -f $dateRangeText, $bullet, $Report.DateField, $scanMode
            $filterText = 'filters: {0}' -f ([String]::Join(', ', [String[]]$Report.Filter))
            if (@($Report.Exclude).Count -gt 0)
            {
                $filterText += '  {0}  exclude: {1}' -f $bullet, ([String]::Join(', ', [String[]]$Report.Exclude))
            }
            $sizeText = 'size: {0} {1} {2}  {3}  roots: {4:N0}' -f
                (Format-StorageSize -Bytes $Report.MinimumSizeBytes),
                $arrow,
                $maximumSizeText,
                $bullet,
                $Report.Paths.Count

            [void]$lines.Add((Format-DashboardAccent -Text ($topLeft + ($horizontal * ($dashboardWidth - 2)) + $topRight)))
            [void]$lines.Add((Get-DashboardFrameLine -Text $headerTitle))
            [void]$lines.Add((Get-DashboardFrameLine -Text $scopeText))
            [void]$lines.Add((Get-DashboardFrameLine -Text $filterText))
            [void]$lines.Add((Get-DashboardFrameLine -Text $sizeText))

            $visibleRootCount = [Math]::Min(2, $Report.Paths.Count)
            for ($rootIndex = 0; $rootIndex -lt $visibleRootCount; $rootIndex++)
            {
                [void]$lines.Add((Get-DashboardFrameLine -Text ('root {0:N0}: {1}' -f ($rootIndex + 1), $Report.Paths[$rootIndex])))
            }
            if ($Report.Paths.Count -gt $visibleRootCount)
            {
                [void]$lines.Add((Get-DashboardFrameLine -Text ('+ {0:N0} more root(s)' -f ($Report.Paths.Count - $visibleRootCount))))
            }
            [void]$lines.Add((Format-DashboardAccent -Text ($bottomLeft + ($horizontal * ($dashboardWidth - 2)) + $bottomRight)))

            $cardWidth = 24
            $cardGap = '  '
            $fileCard = @(Get-DashboardKpiCard -Label 'Files' -Value ('{0:N0}' -f $Report.FileCount) -Hint ('of {0:N0} scanned' -f $Report.ScannedFileCount) -Width $cardWidth)
            $totalCard = @(Get-DashboardKpiCard -Label 'Total storage' -Value (Format-StorageSize -Bytes $Report.TotalBytes) -Hint ('{0:N0} active date(s)' -f $Report.ActiveDayCount) -Width $cardWidth)
            $averageCard = @(Get-DashboardKpiCard -Label 'Average file' -Value (Format-StorageSize -Bytes $Report.AverageBytes) -Hint ('median {0}' -f (Format-StorageSize -Bytes $Report.MedianBytes)) -Width $cardWidth)
            $percentileCard = @(Get-DashboardKpiCard -Label 'P95 file size' -Value (Format-StorageSize -Bytes $Report.Percentile95Bytes) -Hint ('max {0}' -f (Format-StorageSize -Bytes $Report.MaximumBytes)) -Width $cardWidth)

            [void]$lines.Add('')
            for ($cardLineIndex = 0; $cardLineIndex -lt $fileCard.Count; $cardLineIndex++)
            {
                $cardLine = $fileCard[$cardLineIndex] + $cardGap +
                    $totalCard[$cardLineIndex] + $cardGap +
                    $averageCard[$cardLineIndex] + $cardGap +
                    $percentileCard[$cardLineIndex]
                [void]$lines.Add(' ' + $cardLine + ' ')
            }

            $dailyRows = @($Report.DailyBreakdown)
            $dailyRowsToShow = if ($dailyRows.Count -gt $DisplayLimit)
            {
                @($dailyRows | Select-Object -Last $DisplayLimit)
            }
            else
            {
                $dailyRows
            }
            $dailySummary = if ($dailyRows.Count -gt 0)
            {
                'latest {0:N0} of {1:N0} date group(s)' -f $dailyRowsToShow.Count, $dailyRows.Count
            }
            else
            {
                'no date groups'
            }
            $dailyHeading = Get-DashboardLeftRight -Left ($statusDot + ' DAILY STORAGE') -Right $dailySummary -Width $dashboardWidth
            $dailyBarWidth = [Math]::Max(5, [Math]::Min($BarWidth, $dashboardWidth - 53))

            [void]$lines.Add('')
            [void]$lines.Add((Format-DashboardAccent -Text $dailyHeading))
            [void]$lines.Add('DATE'.PadRight(12) + 'FILES'.PadRight(15) + 'SHARE'.PadRight($dailyBarWidth + 4) + 'STORAGE'.PadLeft(12) + '   %')
            if ($dailyRowsToShow.Count -eq 0)
            {
                [void]$lines.Add('(no date groups)')
            }
            else
            {
                foreach ($row in $dailyRowsToShow)
                {
                    $dailyBar = Format-DashboardAccent -Text (Get-GraphBar -Percentage $row.PercentOfTotalBytes -Width $dailyBarWidth)
                    $dailyLine = '{0:yyyy-MM-dd}  {1,10:N0}     {2}  {3,12}  {4,6:N1}%' -f
                        $row.Date,
                        $row.FileCount,
                        $dailyBar,
                        (Format-StorageSize -Bytes $row.TotalBytes),
                        $row.PercentOfTotalBytes
                    [void]$lines.Add($dailyLine)
                }
            }
            if ($dailyRows.Count -gt $dailyRowsToShow.Count)
            {
                [void]$lines.Add(('{0} {1:N0} earlier date group(s) omitted; use -AsObject for all rows.' -f
                        $bullet, ($dailyRows.Count - $dailyRowsToShow.Count)))
            }

            $panelWidth = 51
            $panelGap = '  '
            $panelDisplayLimit = [Math]::Min(6, $DisplayLimit)
            $extensionRows = @($Report.ExtensionBreakdown | Select-Object -First $panelDisplayLimit)
            $directoryRows = @($Report.DirectoryBreakdown | Select-Object -First $panelDisplayLimit)
            $typePanelRows = New-Object 'System.Collections.Generic.List[String]'
            $directoryPanelRows = New-Object 'System.Collections.Generic.List[String]'
            $panelBarWidth = 8

            if ($extensionRows.Count -eq 0)
            {
                [void]$typePanelRows.Add('(no matching files)')
            }
            else
            {
                foreach ($row in $extensionRows)
                {
                    $typeText = '{0,-10} {1} {2,6:N1}% {3,10}' -f
                        (Limit-StorageText -Text ([String]$row.Extension) -Width 10),
                        (Get-GraphBar -Percentage $row.PercentOfTotalBytes -Width $panelBarWidth),
                        $row.PercentOfTotalBytes,
                        (Format-StorageSize -Bytes $row.TotalBytes)
                    [void]$typePanelRows.Add($typeText)
                }
            }

            if ($directoryRows.Count -eq 0)
            {
                [void]$directoryPanelRows.Add('(no matching files)')
            }
            else
            {
                $directoryLabelWidth = 29
                for ($directoryIndex = 0; $directoryIndex -lt $directoryRows.Count; $directoryIndex++)
                {
                    $row = $directoryRows[$directoryIndex]
                    $directoryFormat = '{0:D2}  {1,-' + $directoryLabelWidth + '} {2,10}'
                    $directoryText = $directoryFormat -f
                        ($directoryIndex + 1),
                        (Limit-StorageText -Text ([String]$row.Directory) -Width $directoryLabelWidth),
                        (Format-StorageSize -Bytes $row.TotalBytes)
                    [void]$directoryPanelRows.Add($directoryText)
                }
            }

            $panelRowCount = [Math]::Max($typePanelRows.Count, $directoryPanelRows.Count)
            $typePanel = @(Get-DashboardPanel -Title 'File type mix' -Row $typePanelRows.ToArray() -Width $panelWidth -RowCount $panelRowCount)
            $directoryPanel = @(Get-DashboardPanel -Title 'Directory hotspots' -Row $directoryPanelRows.ToArray() -Width $panelWidth -RowCount $panelRowCount)

            [void]$lines.Add('')
            for ($panelLineIndex = 0; $panelLineIndex -lt $typePanel.Count; $panelLineIndex++)
            {
                [void]$lines.Add($typePanel[$panelLineIndex] + $panelGap + $directoryPanel[$panelLineIndex])
            }
            if ($Report.ExtensionBreakdown.Count -gt $extensionRows.Count -or
                $Report.DirectoryBreakdown.Count -gt $directoryRows.Count)
            {
                [void]$lines.Add($bullet + ' Additional type or directory rows are available with -AsObject.')
            }

            if ($Report.Paths.Count -gt 1)
            {
                $pathRows = @($Report.PathBreakdown | Select-Object -First $DisplayLimit)
                $pathHeading = Get-DashboardLeftRight -Left ($statusDot + ' INPUT ROOTS') -Right ('{0:N0} resolved roots' -f $Report.Paths.Count) -Width $dashboardWidth
                $rootBarWidth = [Math]::Min($BarWidth, 24)
                $pathLabelWidth = $dashboardWidth - $rootBarWidth - 32

                [void]$lines.Add('')
                [void]$lines.Add((Format-DashboardAccent -Text $pathHeading))
                foreach ($row in $pathRows)
                {
                    $pathFormat = '{0,-' + $pathLabelWidth + '} {1} {2,10} {3,6:N1}%'
                    $pathBar = Format-DashboardAccent -Text (Get-GraphBar -Percentage $row.PercentOfTotalBytes -Width $rootBarWidth)
                    $pathLine = $pathFormat -f
                        (Limit-StorageText -Text ([String]$row.Path) -Width $pathLabelWidth),
                        $pathBar,
                        (Format-StorageSize -Bytes $row.TotalBytes),
                        $row.PercentOfTotalBytes
                    [void]$lines.Add($pathLine)
                }
            }

            if ($Top -gt 0)
            {
                $largestHeading = Get-DashboardLeftRight -Left ($statusDot + ' LARGEST FILES') -Right ('top {0:N0}' -f $Top) -Width $dashboardWidth
                [void]$lines.Add('')
                [void]$lines.Add((Format-DashboardAccent -Text $largestHeading))
                if ($Report.LargestFiles.Count -eq 0)
                {
                    [void]$lines.Add('(no matching files)')
                }
                else
                {
                    $largestPathWidth = $dashboardWidth - 31
                    for ($largestIndex = 0; $largestIndex -lt $Report.LargestFiles.Count; $largestIndex++)
                    {
                        $file = $Report.LargestFiles[$largestIndex]
                        $largestLine = '{0:D2}  {1,12}  {2:yyyy-MM-dd}  {3}' -f
                            ($largestIndex + 1),
                            (Format-StorageSize -Bytes $file.LengthBytes),
                            $file.FileDate,
                            (Limit-StorageText -Text $file.Path -Width $largestPathWidth)
                        [void]$lines.Add($largestLine)
                    }
                }
            }

            if ($Report.EnumerationErrorCount -gt 0)
            {
                [void]$lines.Add('')
                [void]$lines.Add((Format-DashboardAccent -Text ($statusDot + ' ENUMERATION ERRORS')))
                foreach ($errorMessage in @($Report.EnumerationErrors | Select-Object -First 3))
                {
                    [void]$lines.Add(('  {0} {1}' -f $bullet, (Limit-StorageText -Text $errorMessage -Width ($dashboardWidth - 4))))
                }
                if ($Report.EnumerationErrorCount -gt 3)
                {
                    [void]$lines.Add(('  {0} {1:N0} additional error(s); use -AsObject for details.' -f
                            $bullet, ($Report.EnumerationErrorCount - 3)))
                }
            }

            $statusLabel = if ($Report.EnumerationErrorCount -gt 0)
            {
                'PARTIAL'
            }
            elseif ($Report.FileCount -eq 0)
            {
                'EMPTY'
            }
            else
            {
                'READY'
            }
            $statusText = '{0} {1}  {2:N0} selected / {3:N0} scanned  {4}  {5:N0} zero-byte  {4}  {6:N0} duplicate(s)  {4}  {7:N0} error(s)' -f
                $statusDot,
                $statusLabel,
                $Report.FileCount,
                $Report.ScannedFileCount,
                $bullet,
                $Report.ZeroByteFileCount,
                $Report.DuplicateFileCount,
                $Report.EnumerationErrorCount

            [void]$lines.Add('')
            [void]$lines.Add((Format-DashboardAccent -Text ($topLeft + ($horizontal * ($dashboardWidth - 2)) + $topRight)))
            [void]$lines.Add((Get-DashboardFrameLine -Text $statusText))
            if ($Report.CsvPath)
            {
                $csvStatus = if ($Report.CsvExported) { 'written' } else { 'not written' }
                [void]$lines.Add((Get-DashboardFrameLine -Text ('CSV  {0}  {1}  {2}' -f $csvStatus, $Report.CsvGroupBy, $Report.CsvPath)))
            }
            [void]$lines.Add((Format-DashboardAccent -Text ($bottomLeft + ($horizontal * ($dashboardWidth - 2)) + $bottomRight)))

            return $lines -join [Environment]::NewLine
        }
    }

    process
    {
        foreach ($inputPath in @($Path))
        {
            if ([String]::IsNullOrWhiteSpace($inputPath))
            {
                throw 'Path values cannot be empty or whitespace.'
            }

            [void]$inputPaths.Add($inputPath.Trim())
        }
    }

    end
    {
        if ($AllDates -and $daysWasSpecified)
        {
            throw 'AllDates cannot be combined with Days. Remove Days to include every file date.'
        }

        if ($AllDates -and $referenceDateWasSpecified)
        {
            throw 'AllDates cannot be combined with ReferenceDate. Remove ReferenceDate to include every file date.'
        }

        if ($null -ne $MaximumSizeBytes -and $MinimumSizeBytes -gt $MaximumSizeBytes)
        {
            throw 'MinimumSizeBytes cannot be greater than MaximumSizeBytes.'
        }

        if ($OverwriteCsv -and [String]::IsNullOrWhiteSpace($CsvPath))
        {
            throw 'OverwriteCsv requires CsvPath.'
        }

        if ($csvGroupByWasSpecified -and [String]::IsNullOrWhiteSpace($CsvPath))
        {
            throw 'CsvGroupBy requires CsvPath.'
        }

        $normalizedFilters = @(
            foreach ($fileFilter in @($Filter))
            {
                if ([String]::IsNullOrWhiteSpace($fileFilter))
                {
                    throw 'Filter values cannot be empty or whitespace.'
                }

                $fileFilter.Trim()
            }
        )
        $normalizedExclusions = @(
            foreach ($fileExclusion in @($Exclude | Where-Object { $null -ne $_ }))
            {
                if ([String]::IsNullOrWhiteSpace($fileExclusion))
                {
                    throw 'Exclude values cannot be empty or whitespace.'
                }

                $fileExclusion.Trim()
            }
        )

        $referenceCalendarDate = $ReferenceDate.Date
        $dateWindowStart = if ($AllDates) { $null } else { $referenceCalendarDate.AddDays(-$Days) }
        $dateWindowEndExclusive = if ($AllDates) { $null } else { $referenceCalendarDate.AddDays(1) }

        $resolvedCsvPath = $null
        if (-not [String]::IsNullOrWhiteSpace($CsvPath))
        {
            if ([System.IO.Path]::GetExtension($CsvPath) -ine '.csv')
            {
                throw "CsvPath must use a .csv extension: $CsvPath"
            }

            try
            {
                $resolvedCsvPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath.Trim())
            }
            catch
            {
                throw "Invalid CsvPath '$CsvPath': $($_.Exception.Message)"
            }

            if (Test-Path -LiteralPath $resolvedCsvPath -PathType Container)
            {
                throw "CsvPath must identify a file, not a directory: $resolvedCsvPath"
            }

            $csvDirectory = [System.IO.Path]::GetDirectoryName($resolvedCsvPath)
            if ([String]::IsNullOrWhiteSpace($csvDirectory) -or -not (Test-Path -LiteralPath $csvDirectory -PathType Container))
            {
                throw "CsvPath parent directory does not exist: $csvDirectory"
            }

            if ((Test-Path -LiteralPath $resolvedCsvPath -PathType Leaf) -and -not $OverwriteCsv)
            {
                throw "CsvPath already exists: $resolvedCsvPath. Use OverwriteCsv to replace it."
            }
        }

        if ($inputPaths.Count -eq 0)
        {
            [void]$inputPaths.Add((Get-Location).Path)
        }

        $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { $IsWindows }
        $pathComparer = if ($isWindowsPlatform) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
        $resolvedRootKeys = [System.Collections.Generic.HashSet[String]]::new($pathComparer)
        $resolvedRoots = New-Object 'System.Collections.Generic.List[Object]'

        foreach ($requestedPath in $inputPaths)
        {
            try
            {
                $resolvedPathInfo = @(Resolve-Path -Path $requestedPath -ErrorAction Stop)
            }
            catch
            {
                throw "Path not found or inaccessible: $requestedPath. $($_.Exception.Message)"
            }

            if ($resolvedPathInfo.Count -eq 0)
            {
                throw "Path did not resolve to a file or directory: $requestedPath"
            }

            foreach ($pathInfo in $resolvedPathInfo)
            {
                if ($pathInfo.Provider.Name -ne 'FileSystem')
                {
                    throw "Path must use the FileSystem provider: $($pathInfo.Path)"
                }

                try
                {
                    $item = Get-Item -LiteralPath $pathInfo.ProviderPath -Force:$IncludeHidden -ErrorAction Stop
                }
                catch
                {
                    throw "Unable to inspect path '$($pathInfo.Path)': $($_.Exception.Message)"
                }

                $rootKey = [System.IO.Path]::GetFullPath($item.FullName)
                if ($resolvedRootKeys.Add($rootKey))
                {
                    [void]$resolvedRoots.Add([PSCustomObject]@{
                            Path = $rootKey
                            Item = $item
                        })
                }
            }
        }

        $seenFilePaths = [System.Collections.Generic.HashSet[String]]::new($pathComparer)
        $matchingFiles = New-Object 'System.Collections.Generic.List[Object]'
        $enumerationErrors = New-Object 'System.Collections.Generic.List[String]'
        [Int32]$scannedFileCount = 0
        [Int32]$nameMatchedFileCount = 0
        [Int32]$duplicateFileCount = 0

        foreach ($root in $resolvedRoots)
        {
            if ($root.Item -is [System.IO.FileInfo])
            {
                $candidateFiles = @($root.Item)
                $childErrors = @()
            }
            else
            {
                $childErrors = @()
                $getChildItemParameters = @{
                    LiteralPath  = $root.Path
                    File         = $true
                    ErrorAction  = 'SilentlyContinue'
                    ErrorVariable = 'childErrors'
                }
                if ($Recurse)
                {
                    $getChildItemParameters['Recurse'] = $true
                }
                if ($IncludeHidden)
                {
                    $getChildItemParameters['Force'] = $true
                }

                $candidateFiles = @(Get-ChildItem @getChildItemParameters)
            }

            foreach ($childError in @($childErrors))
            {
                [void]$enumerationErrors.Add(('{0}: {1}' -f $root.Path, $childError.Exception.Message))
            }

            foreach ($file in $candidateFiles)
            {
                if ($file -isnot [System.IO.FileInfo])
                {
                    continue
                }

                $fullFilePath = [System.IO.Path]::GetFullPath($file.FullName)
                if ($resolvedCsvPath -and $pathComparer.Equals($fullFilePath, $resolvedCsvPath))
                {
                    continue
                }

                if (-not $seenFilePaths.Add($fullFilePath))
                {
                    $duplicateFileCount++
                    continue
                }

                $scannedFileCount++
                if (-not (Test-WildcardPatternMatch -Value $file.Name -Pattern $normalizedFilters))
                {
                    continue
                }
                if ($normalizedExclusions.Count -gt 0 -and
                    (Test-WildcardPatternMatch -Value $file.Name -Pattern $normalizedExclusions))
                {
                    continue
                }

                $nameMatchedFileCount++

                try
                {
                    $fileDate = [DateTime]$file.$DateField
                    $lengthBytes = [Int64]$file.Length
                }
                catch
                {
                    [void]$enumerationErrors.Add(('{0}: {1}' -f $fullFilePath, $_.Exception.Message))
                    continue
                }

                if (-not $AllDates -and
                    ($fileDate -lt $dateWindowStart -or $fileDate -ge $dateWindowEndExclusive))
                {
                    continue
                }
                if ($lengthBytes -lt $MinimumSizeBytes)
                {
                    continue
                }
                if ($null -ne $MaximumSizeBytes -and $lengthBytes -gt $MaximumSizeBytes)
                {
                    continue
                }

                $extension = if ([String]::IsNullOrWhiteSpace($file.Extension))
                {
                    '(none)'
                }
                else
                {
                    $file.Extension.ToLowerInvariant()
                }
                $directoryName = if ([String]::IsNullOrWhiteSpace($file.DirectoryName))
                {
                    '(root)'
                }
                else
                {
                    $file.DirectoryName
                }

                [void]$matchingFiles.Add([PSCustomObject]@{
                        PSTypeName     = 'FileStorageMetric.File'
                        Path           = $fullFilePath
                        Name           = $file.Name
                        Directory      = $directoryName
                        Extension      = $extension
                        LengthBytes    = $lengthBytes
                        FileDate       = $fileDate
                        CreationTime   = [DateTime]$file.CreationTime
                        LastWriteTime  = [DateTime]$file.LastWriteTime
                        LastAccessTime = [DateTime]$file.LastAccessTime
                        SourcePath     = $root.Path
                    })
            }
        }

        $fileRecords = @($matchingFiles.ToArray())
        $reportStatistics = Get-SizeStatistics -Record $fileRecords
        $dailyBuckets = @{}
        $extensionBuckets = @{}
        $pathBuckets = @{}
        $directoryBuckets = @{}

        foreach ($record in $fileRecords)
        {
            Add-StorageBucketRecord -Bucket $dailyBuckets -Key $record.FileDate.ToString('yyyy-MM-dd') -Record $record
            Add-StorageBucketRecord -Bucket $extensionBuckets -Key $record.Extension -Record $record
            Add-StorageBucketRecord -Bucket $pathBuckets -Key $record.SourcePath -Record $record
            Add-StorageBucketRecord -Bucket $directoryBuckets -Key $record.Directory -Record $record
        }

        $dailyRows = New-Object 'System.Collections.Generic.List[Object]'
        if ($AllDates)
        {
            $dailyKeys = @($dailyBuckets.Keys | Sort-Object)
            foreach ($dailyKey in $dailyKeys)
            {
                $bucketRecords = @($dailyBuckets[$dailyKey].ToArray())
                $groupDate = $bucketRecords[0].FileDate.Date
                $dailyRowParameters = @{
                    TypeName        = 'FileStorageMetric.Day'
                    GroupProperty   = 'Date'
                    GroupValue      = $groupDate
                    Record          = $bucketRecords
                    TotalFileCount  = $reportStatistics.FileCount
                    ReportTotalBytes = $reportStatistics.TotalBytes
                }
                [void]$dailyRows.Add((Get-StorageBreakdownRow @dailyRowParameters))
            }
        }
        else
        {
            for ($groupDate = $dateWindowStart; $groupDate -le $referenceCalendarDate; $groupDate = $groupDate.AddDays(1))
            {
                $dailyKey = $groupDate.ToString('yyyy-MM-dd')
                $bucketRecords = if ($dailyBuckets.ContainsKey($dailyKey))
                {
                    @($dailyBuckets[$dailyKey].ToArray())
                }
                else
                {
                    @()
                }

                $dailyRowParameters = @{
                    TypeName        = 'FileStorageMetric.Day'
                    GroupProperty   = 'Date'
                    GroupValue      = $groupDate
                    Record          = $bucketRecords
                    TotalFileCount  = $reportStatistics.FileCount
                    ReportTotalBytes = $reportStatistics.TotalBytes
                }
                [void]$dailyRows.Add((Get-StorageBreakdownRow @dailyRowParameters))
            }
        }

        $extensionRows = @(
            foreach ($extensionKey in $extensionBuckets.Keys)
            {
                $extensionRowParameters = @{
                    TypeName        = 'FileStorageMetric.Extension'
                    GroupProperty   = 'Extension'
                    GroupValue      = $extensionKey
                    Record          = @($extensionBuckets[$extensionKey].ToArray())
                    TotalFileCount  = $reportStatistics.FileCount
                    ReportTotalBytes = $reportStatistics.TotalBytes
                }
                Get-StorageBreakdownRow @extensionRowParameters
            }
        ) | Sort-Object -Property @{ Expression = 'TotalBytes'; Descending = $true }, @{ Expression = 'FileCount'; Descending = $true }, Extension

        $pathRows = @(
            foreach ($resolvedRoot in $resolvedRoots)
            {
                $pathKey = $resolvedRoot.Path
                $pathBucketRecords = if ($pathBuckets.ContainsKey($pathKey))
                {
                    @($pathBuckets[$pathKey].ToArray())
                }
                else
                {
                    @()
                }

                $pathRowParameters = @{
                    TypeName        = 'FileStorageMetric.Path'
                    GroupProperty   = 'Path'
                    GroupValue      = $pathKey
                    Record          = $pathBucketRecords
                    TotalFileCount  = $reportStatistics.FileCount
                    ReportTotalBytes = $reportStatistics.TotalBytes
                }
                Get-StorageBreakdownRow @pathRowParameters
            }
        ) | Sort-Object -Property @{ Expression = 'TotalBytes'; Descending = $true }, Path

        $directoryRows = @(
            foreach ($directoryKey in $directoryBuckets.Keys)
            {
                $directoryRowParameters = @{
                    TypeName        = 'FileStorageMetric.Directory'
                    GroupProperty   = 'Directory'
                    GroupValue      = $directoryKey
                    Record          = @($directoryBuckets[$directoryKey].ToArray())
                    TotalFileCount  = $reportStatistics.FileCount
                    ReportTotalBytes = $reportStatistics.TotalBytes
                }
                Get-StorageBreakdownRow @directoryRowParameters
            }
        ) | Sort-Object -Property @{ Expression = 'TotalBytes'; Descending = $true }, Directory

        $largestFiles = if ($Top -gt 0)
        {
            @(
                $fileRecords |
                Sort-Object -Property @{ Expression = 'LengthBytes'; Descending = $true }, Path |
                Select-Object -First $Top
            )
        }
        else
        {
            @()
        }

        $oldestFileDate = $null
        $newestFileDate = $null
        if ($fileRecords.Count -gt 0)
        {
            $orderedFileDates = @($fileRecords | Sort-Object -Property FileDate)
            $oldestFileDate = $orderedFileDates[0].FileDate
            $newestFileDate = $orderedFileDates[$orderedFileDates.Count - 1].FileDate
        }

        $activeDayCount = $dailyBuckets.Count
        $calendarDayCount = if (-not $AllDates)
        {
            $Days + 1
        }
        elseif ($fileRecords.Count -gt 0)
        {
            ($newestFileDate.Date - $oldestFileDate.Date).Days + 1
        }
        else
        {
            0
        }
        $averageFilesPerCalendarDay = if ($calendarDayCount -gt 0)
        {
            [Math]::Round($reportStatistics.FileCount / $calendarDayCount, 2)
        }
        else
        {
            $null
        }
        $averageFilesPerActiveDay = if ($activeDayCount -gt 0)
        {
            [Math]::Round($reportStatistics.FileCount / $activeDayCount, 2)
        }
        else
        {
            $null
        }
        $averageBytesPerCalendarDay = if ($calendarDayCount -gt 0)
        {
            [Math]::Round([Double]($reportStatistics.TotalBytes / $calendarDayCount), 2)
        }
        else
        {
            $null
        }

        $report = [PSCustomObject]@{
            PSTypeName                  = 'FileStorageMetric.Report'
            GeneratedAt                 = Get-Date
            Paths                       = [String[]]@($resolvedRoots | ForEach-Object { $_.Path })
            Filter                      = [String[]]$normalizedFilters
            Exclude                     = [String[]]$normalizedExclusions
            Days                        = if ($AllDates) { $null } else { $Days }
            AllDates                    = [Boolean]$AllDates
            ReferenceDate               = if ($AllDates) { $null } else { $referenceCalendarDate }
            DateWindowStart             = $dateWindowStart
            DateWindowEnd               = if ($AllDates) { $null } else { $referenceCalendarDate }
            DateField                   = $DateField
            Recurse                     = [Boolean]$Recurse
            IncludeHidden               = [Boolean]$IncludeHidden
            MinimumSizeBytes            = $MinimumSizeBytes
            MaximumSizeBytes            = $MaximumSizeBytes
            ScannedFileCount            = $scannedFileCount
            NameMatchedFileCount        = $nameMatchedFileCount
            FileCount                   = $reportStatistics.FileCount
            TotalBytes                  = $reportStatistics.TotalBytes
            AverageBytes                = $reportStatistics.AverageBytes
            MedianBytes                 = $reportStatistics.MedianBytes
            Percentile95Bytes           = $reportStatistics.Percentile95Bytes
            SizeStandardDeviationBytes  = $reportStatistics.SizeStandardDeviationBytes
            MinimumBytes                = $reportStatistics.MinimumBytes
            MaximumBytes                = $reportStatistics.MaximumBytes
            ZeroByteFileCount           = $reportStatistics.ZeroByteFileCount
            OldestFileDate              = $oldestFileDate
            NewestFileDate              = $newestFileDate
            ActiveDayCount              = $activeDayCount
            CalendarDayCount            = $calendarDayCount
            AverageFilesPerCalendarDay  = $averageFilesPerCalendarDay
            AverageFilesPerActiveDay    = $averageFilesPerActiveDay
            AverageBytesPerCalendarDay  = $averageBytesPerCalendarDay
            DuplicateFileCount          = $duplicateFileCount
            EnumerationErrorCount       = $enumerationErrors.Count
            EnumerationErrors           = [String[]]$enumerationErrors.ToArray()
            DailyBreakdown              = [Object[]]$dailyRows.ToArray()
            ExtensionBreakdown          = [Object[]]$extensionRows
            PathBreakdown               = [Object[]]$pathRows
            DirectoryBreakdown          = [Object[]]$directoryRows
            LargestFiles                = [Object[]]$largestFiles
            CsvPath                     = $resolvedCsvPath
            CsvGroupBy                  = if ($resolvedCsvPath) { $CsvGroupBy } else { $null }
            CsvExported                 = $false
        }

        if ($resolvedCsvPath -and $PSCmdlet.ShouldProcess($resolvedCsvPath, "Export $CsvGroupBy file storage metrics to CSV"))
        {
            $csvData = Get-CsvExportData -Report $report -FileRecord $fileRecords -Grouping $CsvGroupBy
            Write-StorageCsv -OutputPath $resolvedCsvPath -Column $csvData.Columns -Record $csvData.Records
            $report.CsvExported = $true
        }

        Write-Verbose ('Included {0:N0} of {1:N0} scanned file(s), totaling {2:N0} bytes.' -f
            $report.FileCount, $report.ScannedFileCount, $report.TotalBytes)

        if ($AsObject)
        {
            return $report
        }

        return Format-StorageDashboard -Report $report
    }
}
