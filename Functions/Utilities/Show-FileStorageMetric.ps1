function Show-FileStorageMetric
{
    <#
    .SYNOPSIS
        Calculates file storage metrics and displays a graphical summary.

    .DESCRIPTION
        Scans one or more file-system paths, applies file-name, date, and size criteria,
        and calculates storage statistics. The default output is a compact text dashboard
        with daily activity bars, file-type totals, top directories, and largest files.
        Unicode framing, a teal ANSI accent, and charcoal-grey secondary text give the
        dashboard a restrained monochrome appearance.

        Use -AsObject for automation. The returned report contains raw byte values and
        nested DailyBreakdown, ExtensionBreakdown, PathBreakdown, DirectoryBreakdown,
        and LargestFiles collections.

        The dashboard includes a capacity forecast by default. It extrapolates the average
        retained bytes per calendar day in a separate 30-day growth window, recommends
        capacity at 30, 90, and 365 days with 20 percent headroom, and reports the current
        capacity of file-system volumes containing the resolved paths when available.
        Use ProjectionDays, GrowthWindowDays, and CapacityHeadroomPercent to tune it, or
        NoCapacityProjection to omit it.

        The forecast is an acquisition-rate estimate from a point-in-time scan, not a
        measurement of net growth. Deletions, deduplication, compression, and future size
        changes cannot be inferred. The current selected-data baseline applies file-name
        and size criteria across all dates, while the main report retains its requested
        date window.

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

    .PARAMETER ProjectionDays
        One or more future horizons, in days, for the storage-capacity forecast.
        Duplicate horizons are removed and results are ordered from shortest to longest.
        Defaults to 30, 90, and 365.

    .PARAMETER GrowthWindowDays
        Number of calendar days used to estimate average retained-byte growth. The window
        ends on ReferenceDate and includes zero-activity dates. It is independent of Days
        so the default one-day metrics report still receives a useful forecast. Defaults
        to 30.

    .PARAMETER CapacityHeadroomPercent
        Percentage of projected capacity to leave unused. Required capacity is calculated
        so projected usage does not exceed the remaining percentage. Defaults to 20.
        Valid values are 0 through 99.

    .PARAMETER NoCapacityProjection
        Omits growth and volume-capacity calculations from the report and dashboard.
        Cannot be combined with explicitly supplied projection settings or Projection
        and Volume CSV groupings.

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
        Summary, Day, Extension, Path, Directory, File, Projection, or Volume.
        Projection and Volume are available when capacity projection is enabled.
        Defaults to Day.

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

    .EXAMPLE
        PS > $report = Show-FileStorageMetric -Path ./archive -Days 30 -DateField CreationTime -Recurse -ProjectionDays 30, 90, 365 -CapacityHeadroomPercent 20 -AsObject
        PS > $report.GrowthProjection.Projections
        PS > $report.VolumeBreakdown

        Projects retained storage additions at three horizons, recommends selected-data
        capacity with 20 percent headroom, and returns current volume-capacity details.

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
        [ValidateNotNullOrEmpty()]
        [ValidateRange(1, 365000)]
        [Int32[]]$ProjectionDays = @(30, 90, 365),

        [Parameter()]
        [ValidateRange(1, 365000)]
        [Int32]$GrowthWindowDays = 30,

        [Parameter()]
        [ValidateRange(0, 99)]
        [Double]$CapacityHeadroomPercent = 20,

        [Parameter()]
        [Switch]$NoCapacityProjection,

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
        [ValidateSet('Summary', 'Day', 'Extension', 'Path', 'Directory', 'File', 'Projection', 'Volume')]
        [String]$CsvGroupBy = 'Day',

        [Parameter()]
        [Switch]$OverwriteCsv
    )

    begin
    {
        $inputPaths = New-Object 'System.Collections.Generic.List[String]'
        $daysWasSpecified = $PSBoundParameters.ContainsKey('Days')
        $referenceDateWasSpecified = $PSBoundParameters.ContainsKey('ReferenceDate')
        $projectionDaysWasSpecified = $PSBoundParameters.ContainsKey('ProjectionDays')
        $growthWindowDaysWasSpecified = $PSBoundParameters.ContainsKey('GrowthWindowDays')
        $capacityHeadroomWasSpecified = $PSBoundParameters.ContainsKey('CapacityHeadroomPercent')
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

        function Get-FileStorageVolumeInventory
        {
            $volumeInventory = New-Object 'System.Collections.Generic.List[Object]'

            try
            {
                $drives = @([System.IO.DriveInfo]::GetDrives())
            }
            catch
            {
                Write-Verbose "Could not enumerate file-system volumes: $($_.Exception.Message)"
                return [Object[]]@()
            }

            foreach ($drive in $drives)
            {
                try
                {
                    $isReady = [Boolean]$drive.IsReady
                    $mountPoint = [String]$drive.Name
                    try
                    {
                        if ($drive.RootDirectory -and
                            -not [String]::IsNullOrWhiteSpace($drive.RootDirectory.FullName))
                        {
                            $mountPoint = [String]$drive.RootDirectory.FullName
                        }
                    }
                    catch
                    {
                        Write-Verbose "Could not resolve the mount point for volume '$($drive.Name)': $($_.Exception.Message)"
                    }

                    try
                    {
                        $mountPoint = [System.IO.Path]::GetFullPath($mountPoint)
                    }
                    catch
                    {
                        Write-Verbose "Could not normalize volume mount point '$mountPoint'; using the provider-supplied value."
                    }

                    $volumeProperties = [Ordered]@{
                        PSTypeName         = 'FileStorageMetric.VolumeSource'
                        Name               = [String]$drive.Name
                        MountPoint         = $mountPoint
                        DriveType          = [String]$drive.DriveType
                        DriveFormat        = $null
                        IsReady            = $isReady
                        CapacityBytes      = $null
                        UsedBytes          = $null
                        TotalFreeBytes     = $null
                        AvailableFreeBytes = $null
                        UsedPercent        = $null
                    }

                    if ($isReady)
                    {
                        [Int64]$capacityBytes = $drive.TotalSize
                        [Int64]$totalFreeBytes = $drive.TotalFreeSpace
                        [Int64]$availableFreeBytes = $drive.AvailableFreeSpace
                        [Int64]$usedBytes = $capacityBytes - $totalFreeBytes

                        $volumeProperties.DriveFormat = [String]$drive.DriveFormat
                        $volumeProperties.CapacityBytes = $capacityBytes
                        $volumeProperties.UsedBytes = $usedBytes
                        $volumeProperties.TotalFreeBytes = $totalFreeBytes
                        $volumeProperties.AvailableFreeBytes = $availableFreeBytes
                        if ($capacityBytes -gt 0)
                        {
                            $volumeProperties.UsedPercent = [Math]::Round(
                                ([Double]$usedBytes / [Double]$capacityBytes) * 100,
                                2)
                        }
                    }

                    [void]$volumeInventory.Add([PSCustomObject]$volumeProperties)
                }
                catch
                {
                    Write-Verbose "Could not inspect file-system volume '$($drive.Name)': $($_.Exception.Message)"
                }
            }

            return [Object[]]$volumeInventory.ToArray()
        }

        function Resolve-FileStorageVolume
        {
            param(
                [Parameter(Mandatory)]
                [String]$FileSystemPath,

                [Parameter(Mandatory)]
                [AllowEmptyCollection()]
                [Object[]]$Volume,

                [Parameter(Mandatory)]
                [StringComparison]$PathComparison
            )

            try
            {
                $normalizedPath = [System.IO.Path]::GetFullPath($FileSystemPath)
            }
            catch
            {
                $normalizedPath = $FileSystemPath
            }

            $bestMatch = $null
            $bestMatchLength = -1
            $directorySeparator = [String][System.IO.Path]::DirectorySeparatorChar
            $alternateSeparator = [String][System.IO.Path]::AltDirectorySeparatorChar

            foreach ($currentVolume in @($Volume))
            {
                $mountPoint = [String]$currentVolume.MountPoint
                if ([String]::IsNullOrWhiteSpace($mountPoint))
                {
                    continue
                }

                try
                {
                    $mountPoint = [System.IO.Path]::GetFullPath($mountPoint)
                }
                catch
                {
                    Write-Verbose "Could not normalize volume mount point '$mountPoint' while resolving '$normalizedPath'."
                }

                $mountPointWithSeparator = $mountPoint
                if (-not $mountPoint.EndsWith($directorySeparator) -and
                    -not $mountPoint.EndsWith($alternateSeparator))
                {
                    $mountPointWithSeparator += $directorySeparator
                }

                $isMatch = $normalizedPath.Equals($mountPoint, $PathComparison) -or
                    $normalizedPath.StartsWith($mountPointWithSeparator, $PathComparison)
                if ($isMatch -and $mountPoint.Length -gt $bestMatchLength)
                {
                    $bestMatch = $currentVolume
                    $bestMatchLength = $mountPoint.Length
                }
            }

            return $bestMatch
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
                'Projection'
                {
                    $columns = @(
                        'Method', 'DateField', 'ObservationStartDate', 'ObservationEndDate',
                        'ObservationDayCount', 'ObservedBytes', 'ObservedGrowthBytesPerDay',
                        'ObservedGrowthBytesPerWeek', 'ObservedGrowthBytesPer30DayMonth',
                        'ObservedGrowthBytesPerYear', 'CapacityHeadroomPercent', 'HorizonDays',
                        'ProjectionDate', 'ProjectedAdditionalBytes', 'ProjectedSelectedBytes',
                        'RequiredSelectedCapacityBytes'
                    )
                    $records = @(
                        foreach ($projection in @($Report.GrowthProjection.Projections))
                        {
                            [PSCustomObject][Ordered]@{
                                Method                           = $Report.GrowthProjection.Method
                                DateField                        = $Report.GrowthProjection.DateField
                                ObservationStartDate             = if ($Report.GrowthProjection.ObservationStartDate) { $Report.GrowthProjection.ObservationStartDate.ToString('yyyy-MM-dd') } else { $null }
                                ObservationEndDate               = if ($Report.GrowthProjection.ObservationEndDate) { $Report.GrowthProjection.ObservationEndDate.ToString('yyyy-MM-dd') } else { $null }
                                ObservationDayCount              = $Report.GrowthProjection.ObservationDayCount
                                ObservedBytes                    = $Report.GrowthProjection.ObservedBytes
                                ObservedGrowthBytesPerDay        = $Report.GrowthProjection.ObservedGrowthBytesPerDay
                                ObservedGrowthBytesPerWeek       = $Report.GrowthProjection.ObservedGrowthBytesPerWeek
                                ObservedGrowthBytesPer30DayMonth = $Report.GrowthProjection.ObservedGrowthBytesPer30DayMonth
                                ObservedGrowthBytesPerYear       = $Report.GrowthProjection.ObservedGrowthBytesPerYear
                                CapacityHeadroomPercent          = $Report.GrowthProjection.CapacityHeadroomPercent
                                HorizonDays                      = $projection.HorizonDays
                                ProjectionDate                   = $projection.ProjectionDate.ToString('yyyy-MM-dd')
                                ProjectedAdditionalBytes         = $projection.ProjectedAdditionalBytes
                                ProjectedSelectedBytes           = $projection.ProjectedSelectedBytes
                                RequiredSelectedCapacityBytes    = $projection.RequiredSelectedCapacityBytes
                            }
                        }
                    )
                }
                'Volume'
                {
                    $columns = @(
                        'MountPoint', 'DriveType', 'DriveFormat', 'IsReady', 'CapacityBytes',
                        'UsedBytes', 'TotalFreeBytes', 'AvailableFreeBytes', 'UsedPercent',
                        'CurrentSelectedFileCount', 'CurrentSelectedBytes', 'ObservedFileCount',
                        'ObservedBytes', 'ObservedGrowthBytesPerDay',
                        'EstimatedDaysUntilAvailableSpaceExhausted',
                        'EstimatedAvailableSpaceExhaustionDate', 'HorizonDays', 'ProjectionDate',
                        'ProjectedAdditionalBytes', 'ProjectedUsedBytes', 'ProjectedUsedPercent',
                        'ProjectedAvailableFreeBytes', 'RequiredCapacityBytes',
                        'AdditionalCapacityRequiredBytes', 'MeetsCapacityTarget'
                    )
                    $records = @(
                        foreach ($volumeRow in @($Report.VolumeBreakdown))
                        {
                            foreach ($volumeProjection in @($volumeRow.Projections))
                            {
                                [PSCustomObject][Ordered]@{
                                    MountPoint                                = $volumeRow.MountPoint
                                    DriveType                                 = $volumeRow.DriveType
                                    DriveFormat                               = $volumeRow.DriveFormat
                                    IsReady                                   = $volumeRow.IsReady
                                    CapacityBytes                             = $volumeRow.CapacityBytes
                                    UsedBytes                                 = $volumeRow.UsedBytes
                                    TotalFreeBytes                            = $volumeRow.TotalFreeBytes
                                    AvailableFreeBytes                        = $volumeRow.AvailableFreeBytes
                                    UsedPercent                               = $volumeRow.UsedPercent
                                    CurrentSelectedFileCount                  = $volumeRow.CurrentSelectedFileCount
                                    CurrentSelectedBytes                      = $volumeRow.CurrentSelectedBytes
                                    ObservedFileCount                         = $volumeRow.ObservedFileCount
                                    ObservedBytes                             = $volumeRow.ObservedBytes
                                    ObservedGrowthBytesPerDay                 = $volumeRow.ObservedGrowthBytesPerDay
                                    EstimatedDaysUntilAvailableSpaceExhausted = $volumeRow.EstimatedDaysUntilAvailableSpaceExhausted
                                    EstimatedAvailableSpaceExhaustionDate     = if ($volumeRow.EstimatedAvailableSpaceExhaustionDate) { $volumeRow.EstimatedAvailableSpaceExhaustionDate.ToString('yyyy-MM-dd') } else { $null }
                                    HorizonDays                               = $volumeProjection.HorizonDays
                                    ProjectionDate                            = $volumeProjection.ProjectionDate.ToString('yyyy-MM-dd')
                                    ProjectedAdditionalBytes                  = $volumeProjection.ProjectedAdditionalBytes
                                    ProjectedUsedBytes                        = $volumeProjection.ProjectedUsedBytes
                                    ProjectedUsedPercent                      = $volumeProjection.ProjectedUsedPercent
                                    ProjectedAvailableFreeBytes               = $volumeProjection.ProjectedAvailableFreeBytes
                                    RequiredCapacityBytes                     = $volumeProjection.RequiredCapacityBytes
                                    AdditionalCapacityRequiredBytes           = $volumeProjection.AdditionalCapacityRequiredBytes
                                    MeetsCapacityTarget                       = $volumeProjection.MeetsCapacityTarget
                                }
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
            $mutedStart = $escapeCharacter + '[38;5;244m'
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

            function Format-DashboardMuted
            {
                param(
                    [Parameter(Mandatory)]
                    [AllowEmptyString()]
                    [String]$Text
                )

                return $mutedStart + $Text + $accentReset
            }

            function Get-DashboardBar
            {
                param(
                    [Parameter(Mandatory)]
                    [Double]$Percentage,

                    [Parameter(Mandatory)]
                    [Int32]$Width
                )

                $plainBar = Get-GraphBar -Percentage $Percentage -Width $Width
                $emptyCharacter = [String][Char]0x2591
                $emptyStartIndex = $plainBar.IndexOf($emptyCharacter)
                if ($emptyStartIndex -lt 0)
                {
                    return Format-DashboardAccent -Text $plainBar
                }

                $filledText = $plainBar.Substring(0, $emptyStartIndex)
                $emptyText = $plainBar.Substring($emptyStartIndex)
                $styledBar = ''
                if ($filledText.Length -gt 0)
                {
                    $styledBar += Format-DashboardAccent -Text $filledText
                }
                if ($emptyText.Length -gt 0)
                {
                    $styledBar += Format-DashboardMuted -Text $emptyText
                }

                return $styledBar
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
                    [String]$Text,

                    [Parameter()]
                    [Switch]$Muted
                )

                $contentWidth = $dashboardWidth - 4
                $content = Limit-StorageText -Text $Text -Width $contentWidth
                $paddedContent = ' ' + $content.PadRight($contentWidth) + ' '
                if ($Muted)
                {
                    $paddedContent = Format-DashboardMuted -Text $paddedContent
                }

                return (Format-DashboardAccent -Text $vertical) +
                    $paddedContent +
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
                    ($accentVertical + (Format-DashboardMuted -Text $hintText) + $accentVertical),
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
            [void]$lines.Add((Get-DashboardFrameLine -Text $scopeText -Muted))
            [void]$lines.Add((Get-DashboardFrameLine -Text $filterText -Muted))
            [void]$lines.Add((Get-DashboardFrameLine -Text $sizeText -Muted))

            $visibleRootCount = [Math]::Min(2, $Report.Paths.Count)
            for ($rootIndex = 0; $rootIndex -lt $visibleRootCount; $rootIndex++)
            {
                [void]$lines.Add((Get-DashboardFrameLine -Text ('root {0:N0}: {1}' -f ($rootIndex + 1), $Report.Paths[$rootIndex]) -Muted))
            }
            if ($Report.Paths.Count -gt $visibleRootCount)
            {
                [void]$lines.Add((Get-DashboardFrameLine -Text ('+ {0:N0} more root(s)' -f ($Report.Paths.Count - $visibleRootCount)) -Muted))
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

            if ($null -ne $Report.PSObject.Properties['GrowthProjection'])
            {
                $growth = $Report.GrowthProjection
                $forecastHeading = Get-DashboardLeftRight `
                    -Left ($statusDot + ' CAPACITY FORECAST') `
                    -Right ('{0:N0}-day retained-byte average' -f $growth.ObservationDayCount) `
                    -Width $dashboardWidth
                $rateText = 'RATE  {0}/day  {1}  {2}/week  {1}  observed {3} in {4:N0} file(s)' -f
                    (Format-StorageSize -Bytes $growth.ObservedGrowthBytesPerDay),
                    $bullet,
                    (Format-StorageSize -Bytes $growth.ObservedGrowthBytesPerWeek),
                    (Format-StorageSize -Bytes $growth.ObservedBytes),
                    $growth.ObservedFileCount
                $baselineText = 'CURRENT SELECTED  {0} in {1:N0} file(s), all dates  {2}  HEADROOM  {3:G}%' -f
                    (Format-StorageSize -Bytes $growth.CurrentSelectedBytes),
                    $growth.CurrentSelectedFileCount,
                    $bullet,
                    $growth.CapacityHeadroomPercent

                [void]$lines.Add('')
                [void]$lines.Add((Format-DashboardAccent -Text $forecastHeading))
                [void]$lines.Add($rateText)
                [void]$lines.Add((Format-DashboardMuted -Text $baselineText))
                [void]$lines.Add((Format-DashboardMuted -Text (
                            'DAYS'.PadLeft(6) + '  ' +
                            'THROUGH'.PadRight(12) +
                            'ADDED'.PadLeft(14) +
                            'PROJECTED'.PadLeft(16) +
                            'CAPACITY NEEDED'.PadLeft(20))))

                $forecastRows = @($growth.Projections | Select-Object -First $DisplayLimit)
                foreach ($projection in $forecastRows)
                {
                    $forecastLine = '{0,6:N0}  {1:yyyy-MM-dd}  {2,14}  {3,16}  {4,20}' -f
                        $projection.HorizonDays,
                        $projection.ProjectionDate,
                        (Format-StorageSize -Bytes $projection.ProjectedAdditionalBytes),
                        (Format-StorageSize -Bytes $projection.ProjectedSelectedBytes),
                        (Format-StorageSize -Bytes $projection.RequiredSelectedCapacityBytes)
                    [void]$lines.Add($forecastLine)
                }
                if ($growth.Projections.Count -gt $forecastRows.Count)
                {
                    [void]$lines.Add((Format-DashboardMuted -Text ('{0} {1:N0} additional horizon(s) available with -AsObject.' -f
                                $bullet, ($growth.Projections.Count - $forecastRows.Count))))
                }

                [void]$lines.Add((Format-DashboardMuted -Text (
                            $bullet + ' Estimate uses retained ' + $growth.DateField +
                            ' bytes; deletions and compression are not observable.')))

                $volumeRows = @($Report.VolumeBreakdown)
                $volumeHeading = Get-DashboardLeftRight `
                    -Left ($statusDot + ' VOLUME CAPACITY') `
                    -Right ('{0:N0} volume(s) / {1}' -f $volumeRows.Count, $growth.VolumeCapacityStatus) `
                    -Width $dashboardWidth
                [void]$lines.Add('')
                [void]$lines.Add((Format-DashboardAccent -Text $volumeHeading))
                if ($volumeRows.Count -eq 0)
                {
                    [void]$lines.Add((Format-DashboardMuted -Text '(volume capacity unavailable)'))
                }
                else
                {
                    $longestHorizonDays = @($growth.Projections | Select-Object -Last 1)[0].HorizonDays
                    [void]$lines.Add((Format-DashboardMuted -Text (
                                'MOUNT'.PadRight(24) +
                                'USED'.PadLeft(13) + ' / ' +
                                'CAPACITY'.PadLeft(12) +
                                'AVAILABLE'.PadLeft(13) +
                                (('{0:N0}D NEED' -f $longestHorizonDays).PadLeft(17)) +
                                'GAP'.PadLeft(13))))
                    $visibleVolumeRows = @($volumeRows | Select-Object -First ([Math]::Min($DisplayLimit, 6)))
                    foreach ($volume in $visibleVolumeRows)
                    {
                        $longestVolumeProjection = @($volume.Projections | Select-Object -Last 1)[0]
                        $volumeLine = '{0,-24} {1,12} / {2,12} {3,12} {4,16} {5,12}' -f
                            (Limit-StorageText -Text ([String]$volume.MountPoint) -Width 24),
                            (Format-StorageSize -Bytes $volume.UsedBytes),
                            (Format-StorageSize -Bytes $volume.CapacityBytes),
                            (Format-StorageSize -Bytes $volume.AvailableFreeBytes),
                            (Format-StorageSize -Bytes $longestVolumeProjection.RequiredCapacityBytes),
                            (Format-StorageSize -Bytes $longestVolumeProjection.AdditionalCapacityRequiredBytes)
                        [void]$lines.Add($volumeLine)
                    }
                    if ($volumeRows.Count -gt $visibleVolumeRows.Count)
                    {
                        [void]$lines.Add((Format-DashboardMuted -Text ('{0} {1:N0} additional volume(s) available with -AsObject.' -f
                                    $bullet, ($volumeRows.Count - $visibleVolumeRows.Count))))
                    }
                }
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
            [void]$lines.Add((Format-DashboardMuted -Text ('DATE'.PadRight(12) + 'FILES'.PadRight(15) + 'SHARE'.PadRight($dailyBarWidth + 4) + 'STORAGE'.PadLeft(12) + '   %')))
            if ($dailyRowsToShow.Count -eq 0)
            {
                [void]$lines.Add((Format-DashboardMuted -Text '(no date groups)'))
            }
            else
            {
                foreach ($row in $dailyRowsToShow)
                {
                    $dailyBar = Get-DashboardBar -Percentage $row.PercentOfTotalBytes -Width $dailyBarWidth
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
                $omittedDateText = '{0} {1:N0} earlier date group(s) omitted; use -AsObject for all rows.' -f
                    $bullet, ($dailyRows.Count - $dailyRowsToShow.Count)
                [void]$lines.Add((Format-DashboardMuted -Text $omittedDateText))
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
                [void]$lines.Add((Format-DashboardMuted -Text ($bullet + ' Additional type or directory rows are available with -AsObject.')))
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
                    $pathBar = Get-DashboardBar -Percentage $row.PercentOfTotalBytes -Width $rootBarWidth
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
                [void]$lines.Add((Get-DashboardFrameLine -Text ('CSV  {0}  {1}  {2}' -f $csvStatus, $Report.CsvGroupBy, $Report.CsvPath) -Muted))
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

        if ($NoCapacityProjection -and
            ($projectionDaysWasSpecified -or $growthWindowDaysWasSpecified -or $capacityHeadroomWasSpecified))
        {
            throw 'NoCapacityProjection cannot be combined with ProjectionDays, GrowthWindowDays, or CapacityHeadroomPercent.'
        }

        if ($NoCapacityProjection -and $CsvGroupBy -in @('Projection', 'Volume'))
        {
            throw "CsvGroupBy $CsvGroupBy cannot be used with NoCapacityProjection."
        }

        $capacityProjectionEnabled = -not [Boolean]$NoCapacityProjection
        $normalizedProjectionDays = if ($capacityProjectionEnabled)
        {
            [Int32[]]@($ProjectionDays | Sort-Object -Unique)
        }
        else
        {
            [Int32[]]@()
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
        if ($capacityProjectionEnabled)
        {
            try
            {
                $growthWindowStart = $referenceCalendarDate.AddDays(-($GrowthWindowDays - 1))
                $growthWindowEndExclusive = $referenceCalendarDate.AddDays(1)
                foreach ($projectionDayCount in $normalizedProjectionDays)
                {
                    [void]$referenceCalendarDate.AddDays($projectionDayCount)
                }
            }
            catch
            {
                throw "Projection settings exceed the supported date range for ReferenceDate $($referenceCalendarDate.ToString('yyyy-MM-dd')). Reduce GrowthWindowDays or ProjectionDays."
            }
        }
        else
        {
            $growthWindowStart = $null
            $growthWindowEndExclusive = $null
        }

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

        $pathComparison = if ($isWindowsPlatform)
        {
            [StringComparison]::OrdinalIgnoreCase
        }
        else
        {
            [StringComparison]::Ordinal
        }
        $volumeInventory = [Object[]]@()
        $volumeByMountPoint = [System.Collections.Generic.Dictionary[String, Object]]::new($pathComparer)
        $selectedVolumeKeys = [System.Collections.Generic.HashSet[String]]::new($pathComparer)
        $directoryVolumeCache = [System.Collections.Generic.Dictionary[String, Object]]::new($pathComparer)
        $volumeCapacityMetrics = [System.Collections.Generic.Dictionary[String, Object]]::new($pathComparer)
        [Int32]$unresolvedVolumePathCount = 0

        if ($capacityProjectionEnabled)
        {
            $volumeInventory = @(Get-FileStorageVolumeInventory)
            foreach ($volumeInfo in $volumeInventory)
            {
                if (-not $volumeByMountPoint.ContainsKey($volumeInfo.MountPoint))
                {
                    $volumeByMountPoint.Add($volumeInfo.MountPoint, $volumeInfo)
                }
            }

            foreach ($resolvedRoot in $resolvedRoots)
            {
                $rootVolume = Resolve-FileStorageVolume -FileSystemPath $resolvedRoot.Path `
                    -Volume $volumeInventory -PathComparison $pathComparison
                if ($null -ne $rootVolume)
                {
                    [void]$selectedVolumeKeys.Add($rootVolume.MountPoint)
                }
                else
                {
                    $unresolvedVolumePathCount++
                }
            }
        }

        $seenFilePaths = [System.Collections.Generic.HashSet[String]]::new($pathComparer)
        $matchingFiles = New-Object 'System.Collections.Generic.List[Object]'
        $enumerationErrors = New-Object 'System.Collections.Generic.List[String]'
        [Int32]$scannedFileCount = 0
        [Int32]$nameMatchedFileCount = 0
        [Int32]$duplicateFileCount = 0
        [Int32]$capacityScopeFileCount = 0
        [Decimal]$capacityScopeBytes = 0
        [Int32]$growthObservedFileCount = 0
        [Decimal]$growthObservedBytes = 0

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

                if ($lengthBytes -lt $MinimumSizeBytes)
                {
                    continue
                }
                if ($null -ne $MaximumSizeBytes -and $lengthBytes -gt $MaximumSizeBytes)
                {
                    continue
                }

                $directoryName = if ([String]::IsNullOrWhiteSpace($file.DirectoryName))
                {
                    '(root)'
                }
                else
                {
                    $file.DirectoryName
                }
                $volumeCacheKey = if ($directoryName -eq '(root)')
                {
                    $fullFilePath
                }
                else
                {
                    $directoryName
                }
                $fileVolume = $null
                if ($capacityProjectionEnabled)
                {
                    $capacityScopeFileCount++
                    $capacityScopeBytes += [Decimal]$lengthBytes
                    $isInGrowthWindow = $fileDate -ge $growthWindowStart -and
                        $fileDate -lt $growthWindowEndExclusive
                    if ($isInGrowthWindow)
                    {
                        $growthObservedFileCount++
                        $growthObservedBytes += [Decimal]$lengthBytes
                    }

                    if ($directoryVolumeCache.ContainsKey($volumeCacheKey))
                    {
                        $fileVolume = $directoryVolumeCache[$volumeCacheKey]
                    }
                    else
                    {
                        $fileVolume = Resolve-FileStorageVolume -FileSystemPath $fullFilePath `
                            -Volume $volumeInventory -PathComparison $pathComparison
                        $directoryVolumeCache.Add($volumeCacheKey, $fileVolume)
                    }

                    if ($null -ne $fileVolume)
                    {
                        [void]$selectedVolumeKeys.Add($fileVolume.MountPoint)
                        if (-not $volumeCapacityMetrics.ContainsKey($fileVolume.MountPoint))
                        {
                            $volumeCapacityMetrics.Add(
                                $fileVolume.MountPoint,
                                [PSCustomObject]@{
                                    CurrentSelectedFileCount = 0
                                    CurrentSelectedBytes     = [Decimal]0
                                    ObservedFileCount        = 0
                                    ObservedBytes            = [Decimal]0
                                })
                        }

                        $currentVolumeMetrics = $volumeCapacityMetrics[$fileVolume.MountPoint]
                        $currentVolumeMetrics.CurrentSelectedFileCount++
                        $currentVolumeMetrics.CurrentSelectedBytes += [Decimal]$lengthBytes
                        if ($isInGrowthWindow)
                        {
                            $currentVolumeMetrics.ObservedFileCount++
                            $currentVolumeMetrics.ObservedBytes += [Decimal]$lengthBytes
                        }
                    }
                    else
                    {
                        $unresolvedVolumePathCount++
                    }
                }

                if (-not $AllDates -and
                    ($fileDate -lt $dateWindowStart -or $fileDate -ge $dateWindowEndExclusive))
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

                $fileProperties = [Ordered]@{
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
                }
                [void]$matchingFiles.Add([PSCustomObject]$fileProperties)
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

        $generatedAt = Get-Date
        $growthProjection = $null
        $volumeRows = [Object[]]@()
        if ($capacityProjectionEnabled)
        {
            [Decimal]$observedGrowthBytesPerDay = [Math]::Round(
                ($growthObservedBytes / [Decimal]$GrowthWindowDays),
                2)
            [Decimal]$usableCapacityRatio = [Decimal]1 -
                ([Decimal]$CapacityHeadroomPercent / [Decimal]100)
            $projectionRows = New-Object 'System.Collections.Generic.List[Object]'

            foreach ($projectionDayCount in $normalizedProjectionDays)
            {
                [Decimal]$projectedAdditionalBytes = [Math]::Ceiling(
                    $observedGrowthBytesPerDay * [Decimal]$projectionDayCount)
                [Decimal]$projectedSelectedBytes = $capacityScopeBytes + $projectedAdditionalBytes
                [Decimal]$requiredSelectedCapacityBytes = [Math]::Ceiling(
                    $projectedSelectedBytes / $usableCapacityRatio)

                [void]$projectionRows.Add([PSCustomObject][Ordered]@{
                        PSTypeName                    = 'FileStorageMetric.CapacityProjection'
                        HorizonDays                  = $projectionDayCount
                        ProjectionDate               = $referenceCalendarDate.AddDays($projectionDayCount)
                        ProjectedAdditionalBytes     = $projectedAdditionalBytes
                        ProjectedSelectedBytes       = $projectedSelectedBytes
                        RequiredSelectedCapacityBytes = $requiredSelectedCapacityBytes
                    })
            }

            $volumeRowList = New-Object 'System.Collections.Generic.List[Object]'
            [Int32]$volumeWithCapacityCount = 0
            foreach ($volumeKey in @($selectedVolumeKeys | Sort-Object))
            {
                if (-not $volumeByMountPoint.ContainsKey($volumeKey))
                {
                    continue
                }

                $sourceVolume = $volumeByMountPoint[$volumeKey]
                $currentVolumeMetrics = if ($volumeCapacityMetrics.ContainsKey($volumeKey))
                {
                    $volumeCapacityMetrics[$volumeKey]
                }
                else
                {
                    [PSCustomObject]@{
                        CurrentSelectedFileCount = 0
                        CurrentSelectedBytes     = [Decimal]0
                        ObservedFileCount        = 0
                        ObservedBytes            = [Decimal]0
                    }
                }
                [Decimal]$volumeGrowthBytesPerDay = [Math]::Round(
                    ([Decimal]$currentVolumeMetrics.ObservedBytes / [Decimal]$GrowthWindowDays),
                    2)
                $estimatedDaysUntilAvailableSpaceExhausted = $null
                $estimatedAvailableSpaceExhaustionDate = $null
                $availableSpaceExhaustionStatus = 'CapacityUnavailable'

                if ($null -ne $sourceVolume.AvailableFreeBytes)
                {
                    $volumeWithCapacityCount++
                    if ($volumeGrowthBytesPerDay -gt 0)
                    {
                        $estimatedDaysUntilAvailableSpaceExhausted = [Math]::Round(
                            ([Decimal]$sourceVolume.AvailableFreeBytes / $volumeGrowthBytesPerDay),
                            2)
                        $availableSpaceExhaustionStatus = 'Projected'
                        try
                        {
                            $estimatedAvailableSpaceExhaustionDate = $referenceCalendarDate.AddDays(
                                [Math]::Ceiling([Double]$estimatedDaysUntilAvailableSpaceExhausted))
                        }
                        catch
                        {
                            $estimatedAvailableSpaceExhaustionDate = $null
                            $availableSpaceExhaustionStatus = 'BeyondDateRange'
                        }
                    }
                    else
                    {
                        $availableSpaceExhaustionStatus = 'NoObservedGrowth'
                    }
                }

                $volumeProjectionRows = New-Object 'System.Collections.Generic.List[Object]'
                foreach ($projectionDayCount in $normalizedProjectionDays)
                {
                    [Decimal]$volumeProjectedAdditionalBytes = [Math]::Ceiling(
                        $volumeGrowthBytesPerDay * [Decimal]$projectionDayCount)
                    $projectedUsedBytes = $null
                    $projectedUsedPercent = $null
                    $projectedAvailableFreeBytes = $null
                    $requiredCapacityBytes = $null
                    $additionalCapacityRequiredBytes = $null
                    $meetsCapacityTarget = $null

                    if ($null -ne $sourceVolume.CapacityBytes -and
                        $null -ne $sourceVolume.UsedBytes -and
                        $null -ne $sourceVolume.AvailableFreeBytes)
                    {
                        $projectedUsedBytes = [Decimal]$sourceVolume.UsedBytes +
                            $volumeProjectedAdditionalBytes
                        $projectedAvailableFreeBytes = [Decimal]$sourceVolume.AvailableFreeBytes -
                            $volumeProjectedAdditionalBytes
                        $requiredCapacityBytes = [Math]::Ceiling(
                            $projectedUsedBytes / $usableCapacityRatio)
                        [Decimal]$capacityGapBytes = $requiredCapacityBytes -
                            [Decimal]$sourceVolume.CapacityBytes
                        $additionalCapacityRequiredBytes = if ($capacityGapBytes -gt 0)
                        {
                            $capacityGapBytes
                        }
                        else
                        {
                            [Decimal]0
                        }

                        if ([Decimal]$sourceVolume.CapacityBytes -gt 0)
                        {
                            $projectedUsedPercent = [Math]::Round(
                                [Double](($projectedUsedBytes / [Decimal]$sourceVolume.CapacityBytes) * 100),
                                2)
                        }
                        $meetsCapacityTarget = $additionalCapacityRequiredBytes -eq 0 -and
                            $projectedAvailableFreeBytes -ge 0
                    }

                    [void]$volumeProjectionRows.Add([PSCustomObject][Ordered]@{
                            PSTypeName                      = 'FileStorageMetric.VolumeCapacityProjection'
                            HorizonDays                    = $projectionDayCount
                            ProjectionDate                 = $referenceCalendarDate.AddDays($projectionDayCount)
                            ProjectedAdditionalBytes       = $volumeProjectedAdditionalBytes
                            ProjectedUsedBytes             = $projectedUsedBytes
                            ProjectedUsedPercent           = $projectedUsedPercent
                            ProjectedAvailableFreeBytes    = $projectedAvailableFreeBytes
                            RequiredCapacityBytes          = $requiredCapacityBytes
                            AdditionalCapacityRequiredBytes = $additionalCapacityRequiredBytes
                            MeetsCapacityTarget            = $meetsCapacityTarget
                        })
                }

                [void]$volumeRowList.Add([PSCustomObject][Ordered]@{
                        PSTypeName                                  = 'FileStorageMetric.Volume'
                        MountPoint                                  = $sourceVolume.MountPoint
                        DriveType                                   = $sourceVolume.DriveType
                        DriveFormat                                 = $sourceVolume.DriveFormat
                        IsReady                                     = $sourceVolume.IsReady
                        CapacityBytes                               = $sourceVolume.CapacityBytes
                        UsedBytes                                   = $sourceVolume.UsedBytes
                        TotalFreeBytes                              = $sourceVolume.TotalFreeBytes
                        AvailableFreeBytes                          = $sourceVolume.AvailableFreeBytes
                        UsedPercent                                = $sourceVolume.UsedPercent
                        CurrentSelectedFileCount                    = $currentVolumeMetrics.CurrentSelectedFileCount
                        CurrentSelectedBytes                        = $currentVolumeMetrics.CurrentSelectedBytes
                        ObservedFileCount                           = $currentVolumeMetrics.ObservedFileCount
                        ObservedBytes                               = $currentVolumeMetrics.ObservedBytes
                        ObservedGrowthBytesPerDay                   = $volumeGrowthBytesPerDay
                        EstimatedDaysUntilAvailableSpaceExhausted   = $estimatedDaysUntilAvailableSpaceExhausted
                        EstimatedAvailableSpaceExhaustionDate       = $estimatedAvailableSpaceExhaustionDate
                        AvailableSpaceExhaustionStatus              = $availableSpaceExhaustionStatus
                        Projections                                 = [Object[]]$volumeProjectionRows.ToArray()
                    })
            }
            $volumeRows = [Object[]]$volumeRowList.ToArray()
            $volumeCapacityStatus = if ($volumeRows.Count -eq 0 -or $volumeWithCapacityCount -eq 0)
            {
                'Unavailable'
            }
            elseif ($volumeWithCapacityCount -lt $volumeRows.Count -or $unresolvedVolumePathCount -gt 0)
            {
                'Partial'
            }
            else
            {
                'Available'
            }

            $growthProjection = [PSCustomObject][Ordered]@{
                PSTypeName                           = 'FileStorageMetric.GrowthProjection'
                Status                               = if ($growthObservedFileCount -gt 0) { 'Ready' } else { 'NoActivity' }
                Method                               = 'AverageRetainedBytesPerCalendarDay'
                DateField                            = $DateField
                ObservationStartDate                 = $growthWindowStart
                ObservationEndDate                   = $referenceCalendarDate
                ObservationDayCount                  = $GrowthWindowDays
                ObservedFileCount                    = $growthObservedFileCount
                ObservedBytes                        = $growthObservedBytes
                CurrentSelectedFileCount             = $capacityScopeFileCount
                CurrentSelectedBytes                 = $capacityScopeBytes
                ObservedGrowthBytesPerDay            = $observedGrowthBytesPerDay
                ObservedGrowthBytesPerWeek           = [Math]::Round($observedGrowthBytesPerDay * [Decimal]7, 2)
                ObservedGrowthBytesPer30DayMonth      = [Math]::Round($observedGrowthBytesPerDay * [Decimal]30, 2)
                ObservedGrowthBytesPerYear            = [Math]::Round($observedGrowthBytesPerDay * [Decimal]365, 2)
                CapacityHeadroomPercent               = $CapacityHeadroomPercent
                VolumeCapacityStatus                  = $volumeCapacityStatus
                UnresolvedVolumePathCount             = $unresolvedVolumePathCount
                Caveat                               = "Estimates extrapolate retained bytes grouped by $DateField and cannot account for deletions, deduplication, compression, or future file-size changes."
                Projections                           = [Object[]]$projectionRows.ToArray()
            }
        }

        $reportProperties = [Ordered]@{
            PSTypeName                  = 'FileStorageMetric.Report'
            GeneratedAt                 = $generatedAt
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
        if ($capacityProjectionEnabled)
        {
            $reportProperties.GrowthProjection = $growthProjection
            $reportProperties.VolumeBreakdown = $volumeRows
        }
        $report = [PSCustomObject]$reportProperties

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
