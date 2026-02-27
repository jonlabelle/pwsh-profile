BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    $functionPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Functions\SystemAdministration\Show-SystemResourceMonitor.ps1'
    $functionPath = [System.IO.Path]::GetFullPath($functionPath)
    . $functionPath
}

Describe 'Show-SystemResourceMonitor' {
    It 'is available as a function' {
        $command = Get-Command -Name 'Show-SystemResourceMonitor' -ErrorAction SilentlyContinue
        $command | Should -Not -BeNullOrEmpty
        $command.CommandType | Should -Be 'Function'
    }

    It 'returns a non-empty dashboard string in one-shot mode' {
        $result = Show-SystemResourceMonitor -NoContinuous -NoColor -BarWidth 16 -HistoryLength 8

        $result | Should -BeOfType 'System.String'
        $result.Length | Should -BeGreaterThan 0
        $result | Should -Match 'System Resource Monitor'
        $result | Should -Match '(?m)^CPU'
        $result | Should -Match '(?m)^Memory'
        $result | Should -Match '(?m)^Disk'
        $result | Should -Match '(?m)^Network'
    }

    It 'includes CPU core busy readout in one-shot output' {
        $result = Show-SystemResourceMonitor -NoContinuous -NoColor -BarWidth 16 -HistoryLength 8

        $result | Should -Match '(?m)^CPU.+\S+/\S+ logical cores busy\r?$'
    }

    It 'includes overall summary in title and status metadata in one-shot output' {
        $result = Show-SystemResourceMonitor -NoContinuous -NoColor -BarWidth 16 -HistoryLength 8

        $result | Should -Match '(?m)^System Resource Monitor.+\[[ABCDF]\]'
        $result | Should -Match '(?m)^Status +\[Platform\].+\[Updated\].+\[Collect\]'
        $result | Should -Match '(?m)^History +\[Window\] +\d+ samples .+ \[Order\] +oldest (?:→|->) newest\r?$'
        $result | Should -Match '(?m)^ +\[Trend\] +(?:↗ up \| → steady \| ↘ down|\^ up \| = steady \| v down)\r?$'
        $result | Should -Not -Match '(?m)^Health +Overall:'

        $lines = @($result -split '\r?\n')
        $statusLine = @($lines | Where-Object { $_ -match '^Status +\[Platform\].+\[Updated\].+\[Collect\]' }) | Select-Object -First 1
        $historyLine = @($lines | Where-Object { $_ -match '^History +\[Window\] +\d+ samples .+ \[Order\] +oldest (?:→|->) newest$' }) | Select-Object -First 1
        $historyTrendLine = @($lines | Where-Object { $_ -match '^ +\[Trend\] +(?:↗ up \| → steady \| ↘ down|\^ up \| = steady \| v down)$' }) | Select-Object -First 1
        $dividerIndices = @(
            for ($index = 0; $index -lt $lines.Count; $index++)
            {
                if ($lines[$index] -match '^(?:\u2500|-){10,}$')
                {
                    $index
                }
            }
        )

        $statusLine | Should -Not -BeNullOrEmpty
        $historyLine | Should -Not -BeNullOrEmpty
        $historyTrendLine | Should -Not -BeNullOrEmpty
        $dividerIndices.Count | Should -BeGreaterOrEqual 2

        $statusIndex = [Array]::IndexOf($lines, $statusLine)
        $historyIndex = [Array]::IndexOf($lines, $historyLine)
        $historyTrendIndex = [Array]::IndexOf($lines, $historyTrendLine)

        $statusIndex | Should -Be ($dividerIndices[1] + 2)
        $lines[$dividerIndices[1] + 1] | Should -Be ''
        $historyIndex | Should -Be ($statusIndex + 1)
        $historyTrendIndex | Should -Be ($historyIndex + 1)
    }

    It 'returns structured output with -AsObject' {
        $result = Show-SystemResourceMonitor -AsObject -NoContinuous

        $result | Should -Not -BeNullOrEmpty
        $result.Timestamp | Should -BeOfType 'DateTime'
        $result.PSObject.Properties.Name | Should -Contain 'CpuUsagePercent'
        $result.PSObject.Properties.Name | Should -Contain 'MemoryUsagePercent'
        $result.PSObject.Properties.Name | Should -Contain 'DiskUsagePercent'
        $result.PSObject.Properties.Name | Should -Contain 'NetworkReceiveBytesPerSecond'
        $result.PSObject.Properties.Name | Should -Contain 'NetworkSendBytesPerSecond'
        $result.PSObject.Properties.Name | Should -Contain 'NetworkTotalBytesPerSecond'
        $result.PSObject.Properties.Name | Should -Contain 'NetworkActiveInterfaces'
        $result.PSObject.Properties.Name | Should -Contain 'Platform'
        $result.PSObject.Properties.Name | Should -Contain 'OverallLoadPercent'
        $result.PSObject.Properties.Name | Should -Contain 'HealthGrade'
        $result.PSObject.Properties.Name | Should -Contain 'Findings'
        $result.PSObject.Properties.Name | Should -Contain 'CollectMs'
    }

    It 'returns top processes in structured output by default' {
        $result = Show-SystemResourceMonitor -AsObject -NoContinuous -TopProcessCount 3
        $topProcesses = @($result.TopProcesses)

        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'TopProcesses'
        $topProcesses.Count | Should -BeLessOrEqual 3

        if ($topProcesses.Count -gt 0)
        {
            $topProcesses[0].PSObject.Properties.Name | Should -Contain 'Name'
            $topProcesses[0].PSObject.Properties.Name | Should -Contain 'Id'
            $topProcesses[0].PSObject.Properties.Name | Should -Contain 'CpuSeconds'
            $topProcesses[0].PSObject.Properties.Name | Should -Contain 'WorkingSetMiB'
        }
    }

    It 'filters top processes by wildcard process name' {
        $currentProcess = Get-Process -Id $PID -ErrorAction SilentlyContinue
        $currentProcess | Should -Not -BeNullOrEmpty
        $currentProcess.ProcessName | Should -Not -BeNullOrEmpty

        $namePattern = $currentProcess.ProcessName + '*'

        $result = Show-SystemResourceMonitor -AsObject -NoContinuous -TopProcessCount 10 -TopProcessName $namePattern
        $topProcesses = @($result.TopProcesses)

        $topProcesses.Count | Should -BeGreaterThan 0
        foreach ($processInfo in $topProcesses)
        {
            $processInfo.Name | Should -BeLike $namePattern
        }
    }

    It 'returns no process rows when wildcard filter has no matches' {
        $result = Show-SystemResourceMonitor -AsObject -NoContinuous -TopProcessCount 5 -TopProcessName '__definitely_not_a_real_process_name_*'
        $topProcesses = @($result.TopProcesses)

        $result | Should -Not -BeNullOrEmpty
        $topProcesses.Count | Should -Be 0
    }

    It 'supports process-scoped monitor metrics when process filters are specified' {
        $currentProcess = Get-Process -Id $PID -ErrorAction SilentlyContinue
        $currentProcess | Should -Not -BeNullOrEmpty
        $currentProcess.ProcessName | Should -Not -BeNullOrEmpty

        $namePattern = $currentProcess.ProcessName + '*'
        $result = Show-SystemResourceMonitor -AsObject -NoContinuous -MonitorProcessName $namePattern

        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'MonitorProcessName'
        $result.PSObject.Properties.Name | Should -Contain 'MonitorProcessMatchCount'
        @($result.MonitorProcessName) | Should -Contain $namePattern
        [Int32]$result.MonitorProcessMatchCount | Should -BeGreaterOrEqual 1
        $result.DiskUsagePercent | Should -BeNullOrEmpty
        $result.NetworkTotalBytesPerSecond | Should -BeNullOrEmpty
    }

    It 'treats plain monitor process names as contains matches' {
        $currentProcess = Get-Process -Id $PID -ErrorAction SilentlyContinue
        $currentProcess | Should -Not -BeNullOrEmpty
        $currentName = [String]$currentProcess.ProcessName
        $currentName | Should -Not -BeNullOrEmpty

        $plainFilter = if ($currentName.Length -gt 2)
        {
            $currentName.Substring(1)
        }
        else
        {
            $currentName
        }

        $result = Show-SystemResourceMonitor -AsObject -NoContinuous -MonitorProcessName $plainFilter

        $result | Should -Not -BeNullOrEmpty
        @($result.MonitorProcessName) | Should -Contain $plainFilter
        [Int32]$result.MonitorProcessMatchCount | Should -BeGreaterOrEqual 1
    }

    It 'reports zero scoped CPU and memory when process filter has no matches' {
        $result = Show-SystemResourceMonitor -AsObject -NoContinuous -MonitorProcessName '__definitely_not_a_real_process_name_*'

        $result | Should -Not -BeNullOrEmpty
        [Int32]$result.MonitorProcessMatchCount | Should -Be 0
        $result.CpuUsagePercent | Should -Be 0
        $result.MemoryUsedGiB | Should -Be 0
    }

    It 'shows process scope metadata in dashboard output' {
        $result = Show-SystemResourceMonitor -NoContinuous -NoColor -BarWidth 12 -HistoryLength 8 -MonitorProcessName '__definitely_not_a_real_process_name_*'
        $lines = @($result -split '\r?\n')
        $diskLine = @($lines | Where-Object { $_ -match '^Disk' }) | Select-Object -First 1
        $networkLine = @($lines | Where-Object { $_ -match '^Network' }) | Select-Object -First 1

        $result | Should -BeOfType 'System.String'
        $result | Should -Match '(?m)^Scope +Process filter: __definitely_not_a_real_process_name_\* \| matches: 0\r?$'
        $result | Should -Match '(?m)^CPU.+0\.0%'
        $result | Should -Match '(?m)^Disk.+n/a.+on n/a\r?$'
        $result | Should -Match '(?m)^Network.+n/a'
        $diskLine | Should -Not -Match '\?'
        $networkLine | Should -Not -Match '\?'
    }

    It 'supports ASCII-only rendering mode' {
        $result = Show-SystemResourceMonitor -NoContinuous -NoColor -Ascii -BarWidth 12 -HistoryLength 8

        $result | Should -BeOfType 'System.String'
        $result | Should -Match '(?m)^CPU'
        $result | Should -Match '(?m)^Status +\[Platform\]'
    }

    It 'includes top process visualization by default' {
        $result = Show-SystemResourceMonitor -NoContinuous -NoColor -BarWidth 12 -HistoryLength 8 -TopProcessCount 3

        $result | Should -BeOfType 'System.String'
        $result | Should -Match '(?m)^Top Processes \(limit: 3\)\r?$'
        $result | Should -Match '(?m)^  .+ PID +[0-9]+'
    }

    It 'shows top process wildcard filter in visualization heading' {
        $result = Show-SystemResourceMonitor -NoContinuous -NoColor -BarWidth 12 -HistoryLength 8 -TopProcessCount 3 -TopProcessName 'pwsh*'

        $result | Should -BeOfType 'System.String'
        $result | Should -Match '(?m)^Top Processes \(limit: 3\) \| filter: pwsh\*\r?$'
    }

    It 'uses process scope filter for top process heading when no top process filter is provided' {
        $currentProcess = Get-Process -Id $PID -ErrorAction SilentlyContinue
        $currentProcess | Should -Not -BeNullOrEmpty
        $namePattern = $currentProcess.ProcessName + '*'

        $result = Show-SystemResourceMonitor -NoContinuous -NoColor -BarWidth 12 -HistoryLength 8 -TopProcessCount 3 -MonitorProcessName $namePattern

        $result | Should -BeOfType 'System.String'
        $result | Should -Match (('(?m)^Top Processes \(limit: 3\) \| filter: {0}\r?$' -f [Regex]::Escape($namePattern)))
    }

    It 'formats disk label details for the current platform' {
        $result = Show-SystemResourceMonitor -NoContinuous -NoColor -BarWidth 12 -HistoryLength 8

        $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $true
        }
        else
        {
            $IsWindows
        }

        if ($isWindowsPlatform)
        {
            $result | Should -Match '(?m)^Disk.+on [A-Za-z]:\\\r?$'
        }
        else
        {
            $result | Should -Match '(?m)^Disk.+on / \(root fs\)\r?$'
        }
    }

    It 'supports bounded continuous mode for automation and tests' {
        $results = @(Show-SystemResourceMonitor -AsObject -IntervalSeconds 1 -MaxIterations 2)

        $results.Count | Should -Be 2
        $results[0].Timestamp | Should -BeOfType 'DateTime'
        $results[1].Timestamp | Should -BeOfType 'DateTime'
    }

    It 'renders continuous output without timestamp refresh noise' {
        $output = Show-SystemResourceMonitor -NoColor -IntervalSeconds 1 -MaxIterations 1 *>&1 | Out-String

        $output | Should -Match '(?m)^System Resource Monitor.+\[[ABCDF]\]'
        $output | Should -Not -Match 'Refresh #'
        $output | Should -Not -Match '(?m)^Health +Overall:'
        $output | Should -Match 'Press Ctrl\+C to stop monitor\.'
    }

    It 'omits top process sections when -NoTopProcesses is used' {
        $dashboard = Show-SystemResourceMonitor -NoContinuous -NoColor -NoTopProcesses -BarWidth 12 -HistoryLength 8
        $sample = Show-SystemResourceMonitor -AsObject -NoContinuous -NoTopProcesses

        $dashboard | Should -Not -Match '(?m)^Top Processes'
        $sample.PSObject.Properties.Name | Should -Not -Contain 'TopProcesses'
    }
}
