BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    $invokePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Functions\NetworkAndDns\Invoke-NetworkDiagnostic.ps1'
    $invokePath = [System.IO.Path]::GetFullPath($invokePath)

    function Get-NetworkMetric
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
        if ($null -ne $script:GraphTypes)
        {
            $script:GraphTypes.Add($GraphType)
        }
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
        $output | Should-MatchString 'Network Diagnostic - Continuous Mode'
        $output | Should-MatchString '\[\d{2}:\d{2}:\d{2}\]\s+Refresh #1'
        $output | Should-MatchString 'example\.com:443'
        $output | Should-MatchString 'Stats'
        $output | Should-MatchString 'Quality\s+5/5\s+successful'
        $output | Should-MatchString 'Press (Q or )?Ctrl\+C to stop monitoring\.'
        $output | Should-NotMatchString 'Samples per host'
        $output | Should-NotMatchString 'Continuous Mode \(Press Ctrl\+C to stop\)'

        # Ensure NO timestamp or wait messages
        $output | Should-NotMatchString 'Test completed at:'
        $output | Should-NotMatchString 'Waiting'
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

        Should-Invoke -CommandName Start-Sleep -Times 0 -Exactly -ParameterFilter { $PSBoundParameters.ContainsKey('Seconds') -and $Seconds -eq 9 }
    }

    It 'uses the accent, muted, and reset codes for a healthy diagnostic card' {
        $script:MockMetrics = [PSCustomObject]@{
            HostName = 'example.com'
            Port = 443
            SamplesTotal = 5
            SamplesSuccess = 5
            PacketLoss = 0
            LatencyMin = 20.0
            LatencyMax = 24.0
            LatencyAvg = 22.0
            Jitter = 1.5
            DnsResolution = $null
            LatencyData = @(20, 21, 22, 23, 24)
        }
        $script:ThemeWrites = [System.Collections.Generic.List[String]]::new()
        Mock -CommandName Write-Host {
            param([Object]$Object)
            if ($null -ne $Object)
            {
                $script:ThemeWrites.Add([String]$Object)
            }
        }

        Invoke-NetworkDiagnostic -HostName 'example.com' -Count 5 -Continuous:$false *> $null

        $escapeCharacter = [String][Char]27
        $ansiPattern = "$escapeCharacter\[[0-9;]*m"
        $rawOutput = $script:ThemeWrites -join ''
        $codes = [Regex]::Matches($rawOutput, $ansiPattern).Value | Sort-Object -Unique
        $plainText = [Regex]::Replace($rawOutput, $ansiPattern, '')

        $codes.Count | Should-Be 3
        $codes | Should-ContainCollection "$escapeCharacter[38;5;37m"
        $codes | Should-ContainCollection "$escapeCharacter[38;5;244m"
        $codes | Should-ContainCollection "$escapeCharacter[0m"
        $plainText | Should-MatchString 'example\.com:443'
        $plainText | Should-MatchString 'Healthy'
    }

    It 'renders the compact SummaryOnly view without full metric rows' {
        $script:MockMetrics = [PSCustomObject]@{
            HostName = 'example.com'
            Port = 443
            SamplesTotal = 5
            SamplesSuccess = 5
            PacketLoss = 0
            LatencyMin = 20.0
            LatencyMax = 24.0
            LatencyAvg = 22.0
            Jitter = 1.5
            DnsResolution = 8.0
            LatencyData = @(20, 21, 22, 23, 24)
        }

        $output = Invoke-NetworkDiagnostic -HostName 'example.com' -Count 5 -Continuous:$false -SummaryOnly *>&1 | Out-String

        $output | Should-MatchString 'Summary\s+avg\s+22ms'
        $output | Should-MatchString 'dns\s+8ms'
        $output | Should-NotMatchString 'Stats\s+'
        $output | Should-NotMatchString 'Quality\s+'
        $output | Should-NotMatchString 'Findings\s+'
    }

    It 'routes ShowGraph output through the TimeSeries renderer' {
        $script:MockMetrics = [PSCustomObject]@{
            HostName = 'example.com'
            Port = 443
            SamplesTotal = 5
            SamplesSuccess = 5
            PacketLoss = 0
            LatencyMin = 20.0
            LatencyMax = 24.0
            LatencyAvg = 22.0
            Jitter = 1.5
            DnsResolution = $null
            LatencyData = @(20, 21, 22, 23, 24)
        }
        $script:GraphTypes = [System.Collections.Generic.List[String]]::new()

        $output = Invoke-NetworkDiagnostic -HostName 'example.com' -Count 5 -Continuous:$false -ShowGraph *>&1 | Out-String

        $script:GraphTypes | Should-ContainCollection 'TimeSeries'
        $script:GraphTypes | Should-NotContainCollection 'Sparkline'
        $output | Should-MatchString 'SPARK'
        $output | Should-NotMatchString 'Stats\s+'
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
        $upArrowPattern = [Regex]::Escape(([string][char]0x2191))

        Should-MatchString -Actual $output -Expected 'Trend'
        Should-MatchString -Actual $output -Expected 'avg'
        Should-MatchString -Actual $output -Expected 'jitter'
        Should-MatchString -Actual $output -Expected 'loss'
        Should-MatchString -Actual $output -Expected $upArrowPattern
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
        $upArrowPattern = [Regex]::Escape(([string][char]0x2191))

        Should-MatchString -Actual $output -Expected 'Trend'
        Should-MatchString -Actual $output -Expected $upArrowPattern
    }
}
