BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    $invokePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Functions\NetworkAndDns\Invoke-NetworkDiagnostic.ps1'
    $invokePath = [System.IO.Path]::GetFullPath($invokePath)

    function Get-NetworkMetrics
    {
        param(
            [Parameter(Mandatory)][string]$HostName,
            [int]$Count,
            [int]$Timeout,
            [int]$Port,
            [switch]$IncludeDns,
            [int]$SampleDelayMilliseconds
        )
        if ($null -ne $script:MockMetricsQueue -and $script:MockMetricsQueue.Count -gt 0)
        {
            $next = $script:MockMetricsQueue[0]
            if ($script:MockMetricsQueue.Count -gt 1)
            {
                $script:MockMetricsQueue = @($script:MockMetricsQueue[1..($script:MockMetricsQueue.Count - 1)])
            }
            else
            {
                $script:MockMetricsQueue = @()
            }
            return $next
        }
        return $script:MockMetrics
    }

    function Show-NetworkLatencyGraph
    {
        param(
            [double[]]$Data,
            [string]$GraphType,
            [int]$Width,
            [int]$Height,
            [switch]$ShowStats,
            [switch]$NoColor
        )
        return 'SPARK'
    }

    . $invokePath
}

Describe 'Invoke-NetworkDiagnostic (Default continuous mode single iteration via -MaxIterations)' {
    It 'prints expected output and shows stop hint' {
        # Prepare canned metrics
        $script:MockLatencies = @(61, 62, 63, 64, 65)
        $script:MockMetrics = [PSCustomObject]@{
            HostName = 'example.com'
            Port = 443
            SamplesTotal = 5
            SamplesSuccess = 5
            PacketLoss = 0
            LatencyMin = 61.0
            LatencyMax = 65.0
            LatencyAvg = 63.0
            Jitter = 5.12
            DnsResolution = $null
            LatencyData = $script:MockLatencies
        }

        # Capture output
        $output = Invoke-NetworkDiagnostic -HostName 'example.com' -Count 5 -MaxIterations 1 *>&1 | Out-String

        # Verify expected content
        $output | Should -Match 'Network Diagnostic - Continuous Mode'
        $output | Should -Match '\[\d{2}:\d{2}:\d{2}\]\s+Refresh #1'
        $output | Should -Match 'example\.com:443'
        $output | Should -Match 'Stats'
        $output | Should -Match 'Quality\s+5/5\s+successful'
        $output | Should -Match 'Press Ctrl\+C to stop monitoring\.'
        $output | Should -Not -Match 'Samples per host'
        $output | Should -Not -Match 'Continuous Mode \(Press Ctrl\+C to stop\)'

        # Ensure NO timestamp or wait messages
        $output | Should -Not -Match 'Test completed at:'
        $output | Should -Not -Match 'Waiting'
    }

    It 'does not sleep for -Interval when final iteration is reached' {
        $script:MockMetrics = [PSCustomObject]@{
            HostName = 'example.com'
            Port = 443
            SamplesTotal = 5
            SamplesSuccess = 5
            PacketLoss = 0
            LatencyMin = 61.0
            LatencyMax = 65.0
            LatencyAvg = 63.0
            Jitter = 5.12
            DnsResolution = $null
            LatencyData = @(61, 62, 63, 64, 65)
        }

        Mock -CommandName Start-Sleep {}

        Invoke-NetworkDiagnostic -HostName 'example.com' -Count 5 -MaxIterations 1 -Interval 9 *> $null

        Should -Invoke -CommandName Start-Sleep -Times 0 -Exactly -ParameterFilter { $PSBoundParameters.ContainsKey('Seconds') -and $Seconds -eq 9 }
    }

    It 'shows per-host trend arrows from previous refresh in continuous mode' {
        $script:MockMetricsQueue = @(
            [PSCustomObject]@{
                HostName = 'example.com'
                Port = 443
                SamplesTotal = 5
                SamplesSuccess = 5
                PacketLoss = 0
                LatencyMin = 38.0
                LatencyMax = 42.0
                LatencyAvg = 40.0
                Jitter = 3.0
                DnsResolution = $null
                LatencyData = @(39, 40, 41, 40, 40)
            },
            [PSCustomObject]@{
                HostName = 'example.com'
                Port = 443
                SamplesTotal = 5
                SamplesSuccess = 4
                PacketLoss = 20
                LatencyMin = 70.0
                LatencyMax = 90.0
                LatencyAvg = 80.0
                Jitter = 8.0
                DnsResolution = $null
                LatencyData = @(70, 75, 80, 85, $null)
            }
        )

        Mock -CommandName Start-Sleep {}

        $output = Invoke-NetworkDiagnostic -HostName 'example.com' -Count 5 -MaxIterations 2 -Interval 1 *>&1 | Out-String

        $output | Should -Match 'Trend'
        $output | Should -Match 'avg'
        $output | Should -Match 'jitter'
        $output | Should -Match 'loss'
        $output | Should -Match '↑'
    }

    It 'continues when Clear-Host fails in continuous clear render mode' {
        $script:MockMetricsQueue = @(
            [PSCustomObject]@{
                HostName = 'example.com'
                Port = 443
                SamplesTotal = 5
                SamplesSuccess = 5
                PacketLoss = 0
                LatencyMin = 35.0
                LatencyMax = 45.0
                LatencyAvg = 40.0
                Jitter = 2.0
                DnsResolution = $null
                LatencyData = @(39, 40, 41, 40, 40)
            },
            [PSCustomObject]@{
                HostName = 'example.com'
                Port = 443
                SamplesTotal = 5
                SamplesSuccess = 4
                PacketLoss = 20
                LatencyMin = 70.0
                LatencyMax = 90.0
                LatencyAvg = 80.0
                Jitter = 8.0
                DnsResolution = $null
                LatencyData = @(70, 75, 80, 85, $null)
            }
        )

        Mock -CommandName Start-Sleep {}
        Mock -CommandName Clear-Host { throw [System.IO.IOException]::new('The handle is invalid.') }

        $output = Invoke-NetworkDiagnostic -HostName 'example.com' -Count 5 -MaxIterations 2 -Interval 1 -RenderMode Clear *>&1 | Out-String

        $output | Should -Match 'Trend'
        $output | Should -Match '↑'
    }
}
