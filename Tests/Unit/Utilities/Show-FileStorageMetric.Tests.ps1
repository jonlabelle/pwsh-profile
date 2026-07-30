#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    $script:FunctionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../Functions/Utilities/Show-FileStorageMetric.ps1'
    $script:FunctionPath = [System.IO.Path]::GetFullPath($script:FunctionPath)
    . $script:FunctionPath

    function New-StorageMetricTestFile
    {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
        param(
            [Parameter(Mandatory)]
            [String]$Path,

            [Parameter()]
            [ValidateRange(0, 1048576)]
            [Int32]$Length = 0,

            [Parameter()]
            [Nullable[DateTime]]$LastWriteTime
        )

        $parentPath = Split-Path -Path $Path -Parent
        if (-not (Test-Path -LiteralPath $parentPath -PathType Container))
        {
            New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
        }

        if ($Length -gt 0)
        {
            $content = New-Object Byte[] $Length
            [System.IO.File]::WriteAllBytes($Path, $content)
        }
        else
        {
            [System.IO.File]::WriteAllBytes($Path, [Byte[]]::new(0))
        }

        if ($null -ne $LastWriteTime)
        {
            [System.IO.File]::SetLastWriteTime($Path, $LastWriteTime)
        }

        return $Path
    }
}

Describe 'Show-FileStorageMetric' {
    BeforeEach {
        $script:TestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "show-file-storage-metric-$(Get-Random)"
        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestRoot)
        {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    Context 'Command contract and presentation' {
        It 'is available with the expected core defaults' {
            $command = Get-Command -Name 'Show-FileStorageMetric' -ErrorAction Stop

            $command.CommandType | Should -Be 'Function'
            $command.Parameters.Keys | Should -Contain 'Path'
            $command.Parameters.Keys | Should -Contain 'Filter'
            $command.Parameters.Keys | Should -Contain 'Days'
            $command.Parameters.Keys | Should -Contain 'DateField'
            $command.Parameters.Keys | Should -Contain 'Recurse'

            $filePath = Join-Path -Path $script:TestRoot -ChildPath 'today.txt'
            New-StorageMetricTestFile -Path $filePath -Length 10 | Out-Null
            $result = Show-FileStorageMetric -Path $script:TestRoot -AsObject

            $result.Days | Should -Be 0
            $result.DateField | Should -Be 'CreationTime'
            $result.Recurse | Should -BeFalse
            @($result.Filter) | Should -Contain '*'
            $result.DateWindowStart | Should -Be $result.ReferenceDate
            $result.DateWindowEnd | Should -Be $result.ReferenceDate
        }

        It 'returns a graphical dashboard string by default' {
            $filePath = Join-Path -Path $script:TestRoot -ChildPath 'sample.bin'
            New-StorageMetricTestFile -Path $filePath -Length 2048 | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot

            $result | Should -BeOfType ([String])
            $result | Should -Match 'FILE STORAGE / DASHBOARD'
            $result | Should -Match 'TOTAL STORAGE'
            $result | Should -Match 'DAILY STORAGE'
            $result | Should -Match 'FILE TYPE MIX'
            $result | Should -Match 'DIRECTORY HOTSPOTS'
            $result | Should -Match 'LARGEST FILES'
            $result | Should -Match 'READY'
            $result | Should -Match ([Regex]::Escape([String][Char]0x256D))
            $result | Should -Match ([Regex]::Escape([String][Char]0x2588))

            $ansiCodes = @(
                [Regex]::Matches($result, "$([Char]27)\[(?<Code>[0-9;]+)m") |
                ForEach-Object { $_.Groups['Code'].Value } |
                Sort-Object -Unique
            )
            $ansiCodes | Should -Contain '38;5;37'
            $ansiCodes | Should -Contain '0'
            $ansiCodes.Count | Should -Be 2
        }

        It 'limits dashboard date rows without truncating structured daily data' {
            $referenceDate = [DateTime]'2026-05-10'
            $filePath = Join-Path -Path $script:TestRoot -ChildPath 'sample.bin'
            New-StorageMetricTestFile -Path $filePath -Length 32 -LastWriteTime $referenceDate | Out-Null

            $dashboard = Show-FileStorageMetric -Path $script:TestRoot -DateField LastWriteTime -ReferenceDate $referenceDate -Days 5 -DisplayLimit 2
            $report = Show-FileStorageMetric -Path $script:TestRoot -DateField LastWriteTime -ReferenceDate $referenceDate -Days 5 -DisplayLimit 2 -AsObject

            $dashboard | Should -Match '4 earlier date group\(s\) omitted'
            @($report.DailyBreakdown).Count | Should -Be 6
        }

        It 'returns a stable structured report with nested breakdowns' {
            $filePath = Join-Path -Path $script:TestRoot -ChildPath 'sample.log'
            New-StorageMetricTestFile -Path $filePath -Length 100 | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot -AsObject

            $result.PSObject.TypeNames | Should -Contain 'FileStorageMetric.Report'
            $result.PSObject.Properties.Name | Should -Contain 'DailyBreakdown'
            $result.PSObject.Properties.Name | Should -Contain 'ExtensionBreakdown'
            $result.PSObject.Properties.Name | Should -Contain 'PathBreakdown'
            $result.PSObject.Properties.Name | Should -Contain 'DirectoryBreakdown'
            $result.PSObject.Properties.Name | Should -Contain 'LargestFiles'
            $result.DailyBreakdown[0].PSObject.TypeNames | Should -Contain 'FileStorageMetric.Day'
            $result.ExtensionBreakdown[0].PSObject.TypeNames | Should -Contain 'FileStorageMetric.Extension'
            $result.LargestFiles[0].PSObject.TypeNames | Should -Contain 'FileStorageMetric.File'
        }

        It 'provides parseable help examples' {
            $help = Get-Help -Name 'Show-FileStorageMetric' -Examples
            $exampleText = $help.Examples.Example | Out-String

            @($help.Examples.Example).Count | Should -BeGreaterThan 0
            $exampleText | Should -Match 'Show-FileStorageMetric'
            $exampleText | Should -Match 'CsvPath'
        }

        It 'is saved as UTF-8 with BOM for its Unicode dashboard characters' {
            $bytes = [System.IO.File]::ReadAllBytes($script:FunctionPath)

            $bytes.Length | Should -BeGreaterThan 3
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }
    }

    Context 'Path and file-name selection' {
        It 'combines multiple filters with OR logic and applies exclusions' {
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'one.log') -Length 10 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'two.txt') -Length 20 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'skip.log') -Length 30 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'other.json') -Length 40 | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot -Filter '*.log', '*.txt' -Exclude 'skip*' -AllDates -AsObject

            $result.ScannedFileCount | Should -Be 4
            $result.NameMatchedFileCount | Should -Be 2
            $result.FileCount | Should -Be 2
            $result.TotalBytes | Should -Be 30
            @($result.ExtensionBreakdown.Extension) | Should -Contain '.log'
            @($result.ExtensionBreakdown.Extension) | Should -Contain '.txt'
            @($result.ExtensionBreakdown.Extension) | Should -Not -Contain '.json'
        }

        It 'does not enter child directories unless Recurse is supplied' {
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'root.log') -Length 10 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'nested/child.log') -Length 20 | Out-Null

            $flat = Show-FileStorageMetric -Path $script:TestRoot -Filter '*.log' -AllDates -AsObject
            $recursive = Show-FileStorageMetric -Path $script:TestRoot -Filter '*.log' -AllDates -Recurse -AsObject

            $flat.FileCount | Should -Be 1
            $recursive.FileCount | Should -Be 2
            $recursive.TotalBytes | Should -Be 30
        }

        It 'accepts multiple paths and reports a row for every resolved root' {
            $firstRoot = Join-Path -Path $script:TestRoot -ChildPath 'first'
            $secondRoot = Join-Path -Path $script:TestRoot -ChildPath 'second'
            New-StorageMetricTestFile -Path (Join-Path -Path $firstRoot -ChildPath 'one.log') -Length 10 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $secondRoot -ChildPath 'two.txt') -Length 20 | Out-Null

            $result = Show-FileStorageMetric -Path $firstRoot, $secondRoot -Filter '*.log' -AllDates -AsObject

            $result.Paths.Count | Should -Be 2
            $result.PathBreakdown.Count | Should -Be 2
            $result.FileCount | Should -Be 1
            @($result.PathBreakdown | Where-Object FileCount -eq 0).Count | Should -Be 1
        }

        It 'accepts directory paths from the pipeline' {
            $firstRoot = Join-Path -Path $script:TestRoot -ChildPath 'first'
            $secondRoot = Join-Path -Path $script:TestRoot -ChildPath 'second'
            New-StorageMetricTestFile -Path (Join-Path -Path $firstRoot -ChildPath 'one.log') -Length 10 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $secondRoot -ChildPath 'two.log') -Length 20 | Out-Null

            $result = Get-ChildItem -LiteralPath $script:TestRoot -Directory |
                Show-FileStorageMetric -Filter '*.log' -AllDates -AsObject

            $result.Paths.Count | Should -Be 2
            $result.FileCount | Should -Be 2
            $result.TotalBytes | Should -Be 30
        }

        It 'supports wildcard input paths' {
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'one.log') -Length 10 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'two.log') -Length 20 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'three.txt') -Length 30 | Out-Null
            $wildcardPath = Join-Path -Path $script:TestRoot -ChildPath '*.log'

            $result = Show-FileStorageMetric -Path $wildcardPath -AllDates -AsObject

            $result.Paths.Count | Should -Be 2
            $result.FileCount | Should -Be 2
            $result.TotalBytes | Should -Be 30
        }

        It 'de-duplicates files discovered through overlapping roots' {
            $nestedRoot = Join-Path -Path $script:TestRoot -ChildPath 'nested'
            New-StorageMetricTestFile -Path (Join-Path -Path $nestedRoot -ChildPath 'one.log') -Length 25 | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot, $nestedRoot -Filter '*.log' -AllDates -Recurse -AsObject

            $result.FileCount | Should -Be 1
            $result.TotalBytes | Should -Be 25
            $result.DuplicateFileCount | Should -Be 1
        }

        It 'normalizes extension groups and includes files without extensions' {
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'ONE.LOG') -Length 10 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'two.log') -Length 20 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'LICENSE') -Length 30 | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot -AllDates -AsObject
            $logGroup = $result.ExtensionBreakdown | Where-Object Extension -eq '.log'
            $noExtensionGroup = $result.ExtensionBreakdown | Where-Object Extension -eq '(none)'

            $logGroup.FileCount | Should -Be 2
            $logGroup.TotalBytes | Should -Be 30
            $noExtensionGroup.FileCount | Should -Be 1
            $noExtensionGroup.TotalBytes | Should -Be 30
        }
    }

    Context 'Calendar filtering and grouping' {
        It 'treats Days as an inclusive lookback and emits zero-count calendar rows' {
            $referenceDate = [DateTime]'2026-05-10'
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'today.log') -Length 10 -LastWriteTime $referenceDate.AddHours(12) | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'yesterday.log') -Length 20 -LastWriteTime $referenceDate.AddDays(-1).AddHours(12) | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'older.log') -Length 30 -LastWriteTime $referenceDate.AddDays(-3).AddHours(12) | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot -DateField LastWriteTime -ReferenceDate $referenceDate -Days 2 -AsObject

            $result.FileCount | Should -Be 2
            $result.TotalBytes | Should -Be 30
            $result.CalendarDayCount | Should -Be 3
            $result.ActiveDayCount | Should -Be 2
            $result.DailyBreakdown.Count | Should -Be 3
            $result.DailyBreakdown[0].Date | Should -Be $referenceDate.AddDays(-2)
            $result.DailyBreakdown[0].FileCount | Should -Be 0
            $result.DailyBreakdown[2].Date | Should -Be $referenceDate
            $result.DailyBreakdown[2].FileCount | Should -Be 1
        }

        It 'uses only the reference date when Days is zero' {
            $referenceDate = [DateTime]'2026-05-10'
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'today.log') -Length 10 -LastWriteTime $referenceDate.AddHours(23) | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'yesterday.log') -Length 20 -LastWriteTime $referenceDate.AddDays(-1).AddHours(23) | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'tomorrow.log') -Length 30 -LastWriteTime $referenceDate.AddDays(1) | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot -DateField LastWriteTime -ReferenceDate $referenceDate -AsObject

            $result.FileCount | Should -Be 1
            $result.TotalBytes | Should -Be 10
            $result.DailyBreakdown.Count | Should -Be 1
            $result.DailyBreakdown[0].Date | Should -Be $referenceDate
        }

        It 'uses DateField for both filtering and daily grouping' {
            $referenceDate = [DateTime]'2025-02-15'
            $filePath = Join-Path -Path $script:TestRoot -ChildPath 'historical.log'
            New-StorageMetricTestFile -Path $filePath -Length 10 -LastWriteTime $referenceDate.AddHours(8) | Out-Null

            $lastWriteReport = Show-FileStorageMetric -Path $script:TestRoot -DateField LastWriteTime -ReferenceDate $referenceDate -AsObject
            $creationReport = Show-FileStorageMetric -Path $script:TestRoot -DateField CreationTime -ReferenceDate $referenceDate -AsObject

            $lastWriteReport.FileCount | Should -Be 1
            $lastWriteReport.DailyBreakdown[0].FileCount | Should -Be 1
            $creationReport.FileCount | Should -Be 0
            $creationReport.DailyBreakdown[0].FileCount | Should -Be 0
        }

        It 'includes all dates and only active date groups with AllDates' {
            $firstDate = [DateTime]'2024-01-02'
            $secondDate = [DateTime]'2024-03-15'
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'first.log') -Length 10 -LastWriteTime $firstDate | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'second.log') -Length 20 -LastWriteTime $secondDate | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot -DateField LastWriteTime -AllDates -AsObject

            $result.FileCount | Should -Be 2
            $result.DailyBreakdown.Count | Should -Be 2
            $result.ActiveDayCount | Should -Be 2
            $result.CalendarDayCount | Should -Be (($secondDate - $firstDate).Days + 1)
            $result.DailyBreakdown[0].Date | Should -Be $firstDate
            $result.DailyBreakdown[1].Date | Should -Be $secondDate
        }
    }

    Context 'Storage statistics' {
        It 'calculates total, average, median, percentile, deviation, and extrema' {
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'zero.bin') -Length 0 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'ten.bin') -Length 10 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'twenty.bin') -Length 20 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'thirty.bin') -Length 30 | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot -AllDates -AsObject

            $result.FileCount | Should -Be 4
            $result.TotalBytes | Should -Be 60
            $result.AverageBytes | Should -Be 15
            $result.MedianBytes | Should -Be 15
            $result.Percentile95Bytes | Should -Be 30
            $result.SizeStandardDeviationBytes | Should -Be 11.18
            $result.MinimumBytes | Should -Be 0
            $result.MaximumBytes | Should -Be 30
            $result.ZeroByteFileCount | Should -Be 1
        }

        It 'applies minimum and maximum size criteria before calculating statistics' {
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'small.bin') -Length 5 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'medium.bin') -Length 15 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'large.bin') -Length 25 | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot -AllDates -MinimumSizeBytes 10 -MaximumSizeBytes 20 -AsObject

            $result.ScannedFileCount | Should -Be 3
            $result.NameMatchedFileCount | Should -Be 3
            $result.FileCount | Should -Be 1
            $result.TotalBytes | Should -Be 15
            $result.AverageBytes | Should -Be 15
        }

        It 'sorts and limits largest files' {
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'small.bin') -Length 5 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'medium.bin') -Length 15 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'large.bin') -Length 25 | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot -AllDates -Top 2 -AsObject

            $result.LargestFiles.Count | Should -Be 2
            $result.LargestFiles[0].Name | Should -Be 'large.bin'
            $result.LargestFiles[0].LengthBytes | Should -Be 25
            $result.LargestFiles[1].Name | Should -Be 'medium.bin'
        }

        It 'returns useful zero and null values when no files match' {
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'sample.txt') -Length 10 | Out-Null

            $result = Show-FileStorageMetric -Path $script:TestRoot -Filter '*.missing' -AllDates -AsObject
            $dashboard = Show-FileStorageMetric -Path $script:TestRoot -Filter '*.missing' -AllDates

            $result.FileCount | Should -Be 0
            $result.TotalBytes | Should -Be 0
            $result.AverageBytes | Should -BeNullOrEmpty
            $result.MinimumBytes | Should -BeNullOrEmpty
            $result.ExtensionBreakdown.Count | Should -Be 0
            $result.DirectoryBreakdown.Count | Should -Be 0
            $result.PathBreakdown.Count | Should -Be 1
            $result.PathBreakdown[0].FileCount | Should -Be 0
            $dashboard | Should -Match '\(no matching files\)'
        }
    }

    Context 'CSV export' {
        It 'exports the daily breakdown as UTF-8 with BOM by default' {
            $referenceDate = [DateTime]'2026-05-10'
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'today.log') -Length 10 -LastWriteTime $referenceDate | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'yesterday.log') -Length 20 -LastWriteTime $referenceDate.AddDays(-1) | Out-Null
            $csvPath = Join-Path -Path $script:TestRoot -ChildPath 'daily.csv'

            $result = Show-FileStorageMetric -Path $script:TestRoot -Filter '*.log' -DateField LastWriteTime -ReferenceDate $referenceDate -Days 2 -CsvPath $csvPath -AsObject
            $csvRows = @(Import-Csv -LiteralPath $csvPath)
            $bytes = [System.IO.File]::ReadAllBytes($csvPath)

            $result.CsvExported | Should -BeTrue
            $result.CsvGroupBy | Should -Be 'Day'
            $result.CsvPath | Should -Be ([System.IO.Path]::GetFullPath($csvPath))
            $csvRows.Count | Should -Be 3
            $csvRows[0].PSObject.Properties.Name | Should -Contain 'Date'
            $csvRows[0].PSObject.Properties.Name | Should -Contain 'AverageBytes'
            $csvRows[0].PSObject.Properties.Name | Should -Contain 'PercentOfTotalBytes'
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }

        It 'can export one row per matching file' {
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'one.log') -Length 10 | Out-Null
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'two.log') -Length 20 | Out-Null
            $csvPath = Join-Path -Path $script:TestRoot -ChildPath 'files.csv'

            $result = Show-FileStorageMetric -Path $script:TestRoot -Filter '*.log' -AllDates -CsvPath $csvPath -CsvGroupBy File -AsObject
            $csvRows = @(Import-Csv -LiteralPath $csvPath)

            $result.FileCount | Should -Be 2
            $csvRows.Count | Should -Be 2
            @($csvRows.Name) | Should -Contain 'one.log'
            @($csvRows.Name) | Should -Contain 'two.log'
            $csvRows[0].PSObject.Properties.Name | Should -Contain 'LengthBytes'
            $csvRows[0].PSObject.Properties.Name | Should -Contain 'FileDate'
            $csvRows[0].PSObject.Properties.Name | Should -Contain 'SourcePath'
        }

        It 'writes a header-only CSV when an exported grouping has no records' {
            $csvPath = Join-Path -Path $script:TestRoot -ChildPath 'extensions.csv'

            $result = Show-FileStorageMetric -Path $script:TestRoot -Filter '*.missing' -AllDates -CsvPath $csvPath -CsvGroupBy Extension -AsObject
            $lines = @(Get-Content -LiteralPath $csvPath)
            $csvRows = @(Import-Csv -LiteralPath $csvPath)

            $result.CsvExported | Should -BeTrue
            $lines.Count | Should -Be 1
            $lines[0] | Should -Match '"Extension"'
            $lines[0] | Should -Match '"TotalBytes"'
            $csvRows.Count | Should -Be 0
        }

        It 'does not overwrite an existing CSV unless OverwriteCsv is supplied' {
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'sample.log') -Length 10 | Out-Null
            $csvPath = Join-Path -Path $script:TestRoot -ChildPath 'report.csv'
            [System.IO.File]::WriteAllText($csvPath, 'existing')

            { Show-FileStorageMetric -Path $script:TestRoot -Filter '*.log' -AllDates -CsvPath $csvPath -AsObject } |
                Should -Throw '*Use OverwriteCsv to replace it*'

            $result = Show-FileStorageMetric -Path $script:TestRoot -Filter '*.log' -AllDates -CsvPath $csvPath -OverwriteCsv -AsObject

            $result.CsvExported | Should -BeTrue
            $result.FileCount | Should -Be 1
            (Get-Content -LiteralPath $csvPath -Raw) | Should -Match '"Date"'
        }

        It 'honors WhatIf without suppressing the report' {
            New-StorageMetricTestFile -Path (Join-Path -Path $script:TestRoot -ChildPath 'sample.log') -Length 10 | Out-Null
            $csvPath = Join-Path -Path $script:TestRoot -ChildPath 'report.csv'

            $result = Show-FileStorageMetric -Path $script:TestRoot -Filter '*.log' -AllDates -CsvPath $csvPath -AsObject -WhatIf

            $result.FileCount | Should -Be 1
            $result.CsvExported | Should -BeFalse
            Test-Path -LiteralPath $csvPath | Should -BeFalse
        }
    }

    Context 'Preflight validation' {
        It 'rejects AllDates with explicitly supplied Days' {
            { Show-FileStorageMetric -Path $script:TestRoot -AllDates -Days 0 -AsObject } |
                Should -Throw '*AllDates cannot be combined with Days*'
        }

        It 'rejects AllDates with explicitly supplied ReferenceDate' {
            { Show-FileStorageMetric -Path $script:TestRoot -AllDates -ReferenceDate ([DateTime]'2026-01-01') -AsObject } |
                Should -Throw '*AllDates cannot be combined with ReferenceDate*'
        }

        It 'rejects an inverted size range' {
            { Show-FileStorageMetric -Path $script:TestRoot -AllDates -MinimumSizeBytes 20 -MaximumSizeBytes 10 -AsObject } |
                Should -Throw '*MinimumSizeBytes cannot be greater than MaximumSizeBytes*'
        }

        It 'rejects CsvGroupBy and OverwriteCsv without CsvPath' {
            { Show-FileStorageMetric -Path $script:TestRoot -AllDates -CsvGroupBy File -AsObject } |
                Should -Throw '*CsvGroupBy requires CsvPath*'
            { Show-FileStorageMetric -Path $script:TestRoot -AllDates -OverwriteCsv -AsObject } |
                Should -Throw '*OverwriteCsv requires CsvPath*'
        }

        It 'rejects invalid CSV targets before scanning' {
            $missingDirectoryCsv = Join-Path -Path $script:TestRoot -ChildPath 'missing/report.csv'
            $wrongExtension = Join-Path -Path $script:TestRoot -ChildPath 'report.json'

            { Show-FileStorageMetric -Path $script:TestRoot -AllDates -CsvPath $missingDirectoryCsv -AsObject } |
                Should -Throw '*parent directory does not exist*'
            { Show-FileStorageMetric -Path $script:TestRoot -AllDates -CsvPath $wrongExtension -AsObject } |
                Should -Throw '*must use a .csv extension*'
        }

        It 'rejects missing paths with an actionable message' {
            $missingPath = Join-Path -Path $script:TestRoot -ChildPath 'missing'

            { Show-FileStorageMetric -Path $missingPath -AllDates -AsObject } |
                Should -Throw '*Path not found or inaccessible*'
        }
    }
}
