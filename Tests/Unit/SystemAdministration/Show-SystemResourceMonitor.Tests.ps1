BeforeAll {
    $functionPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Functions\SystemAdministration\Show-SystemResourceMonitor.ps1'
    $functionPath = [System.IO.Path]::GetFullPath($functionPath)
    . $functionPath

    $script:IsWindowsTest = if ($PSVersionTable.PSVersion.Major -lt 6)
    {
        $true
    }
    else
    {
        $IsWindows
    }
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
    }

    It 'returns structured output with -AsObject' {
        $result = Show-SystemResourceMonitor -AsObject

        $result | Should -Not -BeNullOrEmpty
        $result.Timestamp | Should -BeOfType 'DateTime'
        $result.PSObject.Properties.Name | Should -Contain 'CpuUsagePercent'
        $result.PSObject.Properties.Name | Should -Contain 'MemoryUsagePercent'
        $result.PSObject.Properties.Name | Should -Contain 'DiskUsagePercent'
        $result.PSObject.Properties.Name | Should -Contain 'Platform'
    }

    It 'supports ASCII-only rendering mode' {
        $result = Show-SystemResourceMonitor -NoColor -Ascii -BarWidth 12 -HistoryLength 8

        $result | Should -BeOfType 'System.String'
        $result | Should -Match '(?m)^CPU'
        $result | Should -Match '(?m)^\\* \\| Platform:'
    }

    It 'labels Unix root disk as root fs in dashboard details' -Skip:$script:IsWindowsTest {
        $result = Show-SystemResourceMonitor -NoColor -BarWidth 12 -HistoryLength 8

        $result | Should -Match '(?m)^Disk.+on / \(root fs\)$'
    }

    It 'supports bounded continuous mode for automation and tests' {
        $results = @(Show-SystemResourceMonitor -AsObject -Continuous -IntervalSeconds 1 -MaxIterations 2)

        $results.Count | Should -Be 2
        $results[0].Timestamp | Should -BeOfType 'DateTime'
        $results[1].Timestamp | Should -BeOfType 'DateTime'
    }
}
