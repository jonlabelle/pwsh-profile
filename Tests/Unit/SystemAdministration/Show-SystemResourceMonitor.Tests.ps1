BeforeAll {
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
        $result = Show-SystemResourceMonitor -NoColor -BarWidth 16 -HistoryLength 8

        $result | Should -BeOfType 'System.String'
        $result.Length | Should -BeGreaterThan 0
        $result | Should -Match 'System Resource Monitor'
        $result | Should -Match '(?m)^CPU'
        $result | Should -Match '(?m)^Memory'
        $result | Should -Match '(?m)^Disk'
        $result | Should -Match '(?m)^Network'
    }

    It 'includes overall summary in title and status metadata in one-shot output' {
        $result = Show-SystemResourceMonitor -NoColor -BarWidth 16 -HistoryLength 8

        $result | Should -Match '(?m)^System Resource Monitor.+\[[ABCDF]\]'
        $result | Should -Match '(?m)^Status +Platform:.+Updated:.+Collect:'
        $result | Should -Not -Match '(?m)^Health +Overall:'
    }

    It 'returns structured output with -AsObject' {
        $result = Show-SystemResourceMonitor -AsObject

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

    It 'returns top processes in structured output when requested' {
        $result = Show-SystemResourceMonitor -AsObject -IncludeTopProcesses -TopProcessCount 3
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

        $result = Show-SystemResourceMonitor -AsObject -IncludeTopProcesses -TopProcessCount 10 -TopProcessName $namePattern
        $topProcesses = @($result.TopProcesses)

        $topProcesses.Count | Should -BeGreaterThan 0
        foreach ($processInfo in $topProcesses)
        {
            $processInfo.Name | Should -BeLike $namePattern
        }
    }

    It 'returns no process rows when wildcard filter has no matches' {
        $result = Show-SystemResourceMonitor -AsObject -IncludeTopProcesses -TopProcessCount 5 -TopProcessName '__definitely_not_a_real_process_name_*'
        $topProcesses = @($result.TopProcesses)

        $result | Should -Not -BeNullOrEmpty
        $topProcesses.Count | Should -Be 0
    }

    It 'supports ASCII-only rendering mode' {
        $result = Show-SystemResourceMonitor -NoColor -Ascii -BarWidth 12 -HistoryLength 8

        $result | Should -BeOfType 'System.String'
        $result | Should -Match '(?m)^CPU'
        $result | Should -Match '(?m)^Status +Platform:'
    }

    It 'includes top process visualization when requested' {
        $result = Show-SystemResourceMonitor -NoColor -BarWidth 12 -HistoryLength 8 -IncludeTopProcesses -TopProcessCount 3

        $result | Should -BeOfType 'System.String'
        $result | Should -Match '(?m)^Top Processes \(limit: 3\)\r?$'
        $result | Should -Match '(?m)^  .+ PID +[0-9]+'
    }

    It 'shows top process wildcard filter in visualization heading' {
        $result = Show-SystemResourceMonitor -NoColor -BarWidth 12 -HistoryLength 8 -IncludeTopProcesses -TopProcessCount 3 -TopProcessName 'pwsh*'

        $result | Should -BeOfType 'System.String'
        $result | Should -Match '(?m)^Top Processes \(limit: 3\) \| filter: pwsh\*\r?$'
    }

    It 'formats disk label details for the current platform' {
        $result = Show-SystemResourceMonitor -NoColor -BarWidth 12 -HistoryLength 8

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
        $results = @(Show-SystemResourceMonitor -AsObject -Continuous -IntervalSeconds 1 -MaxIterations 2)

        $results.Count | Should -Be 2
        $results[0].Timestamp | Should -BeOfType 'DateTime'
        $results[1].Timestamp | Should -BeOfType 'DateTime'
    }

    It 'renders continuous output without timestamp refresh noise' {
        $output = Show-SystemResourceMonitor -Continuous -NoColor -IntervalSeconds 1 -MaxIterations 1 *>&1 | Out-String

        $output | Should -Match '(?m)^System Resource Monitor.+\[[ABCDF]\]'
        $output | Should -Not -Match 'Refresh #'
        $output | Should -Not -Match '(?m)^Health +Overall:'
        $output | Should -Match 'Press Ctrl\+C to stop monitor\.'
    }
}
