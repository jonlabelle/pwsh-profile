function Get-NetworkMetrics
{
    <#
    .SYNOPSIS
        Collects comprehensive network performance metrics for a target host

    .DESCRIPTION
        Performs multiple network tests against a target host and returns detailed metrics
        including latency, packet loss, jitter, and DNS resolution time. Uses cross-platform
        .NET methods for compatibility across Windows, macOS, and Linux.

        Metrics collected:
        - Latency (min/max/avg)
        - Packet loss percentage
        - Jitter (latency variance)
        - DNS resolution time
        - Success/failure counts

        UNDERSTANDING METRICS:

        This function provides the raw data needed for network diagnostics. Understanding
        these metrics helps identify specific network issues:

        1. LATENCY METRICS (LatencyMin/Max/Avg)
           Round-trip time for packets to reach destination and return:
           - Good: < 50ms (suitable for most applications)
           - Acceptable: 50-100ms (noticeable for interactive apps)
           - Poor: 100-200ms (degraded user experience)
           - Critical: > 200ms (unusable for real-time applications)

           Min vs Max difference analysis:
           - Small difference (< 20ms): Stable, predictable connection
           - Medium difference (20-50ms): Some variance, generally acceptable
           - Large difference (> 50ms): High variability, investigate cause

        2. PACKET LOSS ANALYSIS
           Percentage of packets that fail to reach destination:
           - 0%: Perfect connectivity (expected for most services)
           - 1-2%: Minor issues, acceptable for web browsing
           - 2-5%: Noticeable degradation for VoIP/video
           - 5-10%: Significant issues, poor user experience
           - > 10%: Critical problems requiring immediate attention

           Common causes to investigate:
           - Network congestion (QoS configuration needed)
           - Firewall dropping packets (rule misconfiguration)
           - Physical layer issues (bad cable, WiFi interference)
           - Route flapping or unstable BGP routing

        3. JITTER ANALYSIS
           Standard deviation of latency measuring connection consistency:
           - Excellent: < 10ms (suitable for VoIP, gaming, real-time apps)
           - Good: 10-30ms (acceptable for most applications)
           - Poor: 30-50ms (degraded quality for real-time apps)
           - Critical: > 50ms (unusable for VoIP/gaming)

           High jitter indicates:
           - Network congestion with variable queuing delays
           - Route changes occurring during measurement period
           - Shared bandwidth with bursty traffic patterns
           - WiFi interference or poor signal quality

        4. DNS RESOLUTION TIME
           Time taken to resolve hostname to IP address:
           - Fast: < 50ms (well-configured DNS infrastructure)
           - Acceptable: 50-100ms (typical for remote DNS servers)
           - Slow: 100-200ms (DNS server overloaded or geographically distant)
           - Critical: > 200ms (DNS performance issue requiring attention)

           High DNS time suggests:
           - DNS server overloaded or performing slowly
           - Network path to DNS server is congested
           - DNS server should be changed to closer/faster alternative
           - DNS cache not being utilized effectively

        See EXAMPLES for practical troubleshooting workflows and metric analysis scenarios.

        RELATED FUNCTIONS:
        This function is designed to be used by:
        - Invoke-NetworkDiagnostic: Calls Get-NetworkMetrics to collect data for each host
        - Show-NetworkLatencyGraph: Uses Get-NetworkMetrics in continuous mode to gather latency samples

        Can also be used standalone for custom network metric collection and analysis.    .PARAMETER HostName
        Target hostname or IP address to test

    .PARAMETER Count
        Number of test iterations to perform (default: 10)

    .PARAMETER Timeout
        Timeout in milliseconds for each test (default: 2000)

    .PARAMETER Port
        TCP port to test (default: 443)

    .PARAMETER IncludeDns
        Include DNS resolution time in metrics

    .PARAMETER SampleDelayMilliseconds
        Delay between samples in milliseconds (default: 100). Set to 0 for back-to-back samples.

    .EXAMPLE
        PS > Get-NetworkMetrics -HostName 'google.com' -Count 20

        Collects 20 samples of network metrics for google.com

    .EXAMPLE
        PS > Get-NetworkMetrics -HostName '1.1.1.1' -Port 53 -IncludeDns

        Tests DNS server with DNS resolution metrics

    .EXAMPLE
        PS > Get-NetworkMetrics -HostName 'github.com' -Count 50 | Format-List

        Collects 50 samples and displays detailed metrics in list format

    .EXAMPLE
        PS > $metrics = Get-NetworkMetrics -HostName 'api.example.com' -Port 8080 -Count 100
        PS > $metrics.LatencyData | Measure-Object -Average -Minimum -Maximum

        Collect metrics and perform custom analysis on latency data

    .EXAMPLE
        PS > Get-NetworkMetrics -HostName 'database.local' -Port 5432 -Timeout 5000 -Count 30

        Test database server with 5-second timeout and 30 samples

    .EXAMPLE
        PS > 'google.com', 'cloudflare.com', 'github.com' | Get-NetworkMetrics -Count 25

        Test multiple hosts via pipeline with 25 samples each

    .EXAMPLE
        PS > $result = Get-NetworkMetrics -HostName 'vpn.company.com' -IncludeDns
        PS > if ($result.PacketLoss -gt 5) { Write-Warning "High packet loss: $($result.PacketLoss)%" }

        Collect metrics and conditionally alert on high packet loss

    .EXAMPLE
        PS > Get-NetworkMetrics -HostName '8.8.8.8' -Port 53 -Count 20 | Select-Object HostName, PacketLoss, LatencyAvg, Jitter

        Collect DNS server metrics and display specific properties

    .EXAMPLE
        PS > $metrics = Get-NetworkMetrics -HostName 'server.local' -Port 22 -Count 40
        PS > $metrics.LatencyData | Export-Csv -Path latency-log.csv -NoTypeInformation

        Collect metrics and export raw latency data to CSV for further analysis

    .EXAMPLE
        PS > # TROUBLESHOOTING: Slow application performance
        PS > $metrics = Get-NetworkMetrics -HostName 'app-server.com' -Count 30
        PS > if ($metrics.LatencyAvg -gt 100) {
        >>       "High latency detected: $($metrics.LatencyAvg)ms (threshold: 100ms)"
        >>       "Check: Network path, routing, server location"
        >>   }
        PS > if ($metrics.Jitter -gt 30) {
        >>       "High jitter detected: $($metrics.Jitter)ms (threshold: 30ms)"
        >>       "Check: Network congestion, QoS configuration"
        >>   }

        Diagnose application performance. Metrics point to specific network layer issues.
        Latency >100ms or Jitter >30ms indicate network problems.

    .EXAMPLE
        PS > # TROUBLESHOOTING: VoIP quality issues
        PS > # VoIP requirements: latency < 150ms, jitter < 30ms, packet loss < 1%
        PS > $voip = Get-NetworkMetrics -HostName 'sip.company.com' -Port 5060 -Count 100
        PS > $issues = @()
        PS > if ($voip.LatencyAvg -gt 150) { $issues += "Latency: $($voip.LatencyAvg)ms" }
        PS > if ($voip.Jitter -gt 30) { $issues += "Jitter: $($voip.Jitter)ms" }
        PS > if ($voip.PacketLoss -gt 1) { $issues += "Packet Loss: $($voip.PacketLoss)%" }
        PS > if ($issues) { "VoIP quality issues: $($issues -join ', ')" }

        Evaluate VoIP connection quality. Identify specific metrics failing VoIP requirements.
        Any metric exceeding thresholds will cause call quality degradation.

    .EXAMPLE
        PS > # TROUBLESHOOTING: Intermittent connection problems
        PS > $extended = Get-NetworkMetrics -HostName 'unreliable-host.com' -Count 200 -SampleDelayMilliseconds 50
        PS > $failures = $extended.LatencyData | Where-Object { $null -eq $_ }
        PS > "Total failures: $($failures.Count) out of $($extended.SamplesTotal)"
        PS > "Failure rate: $($extended.PacketLoss)%"
        PS > # Check if failures are clustered or random
        PS > $extended.LatencyData | ForEach-Object -Begin { $i=0 } -Process {
        >>       if ($null -eq $_) { "Failure at sample $i" }
        >>       $i++
        >>   }

        Diagnose intermittent issues. Pattern of failures (clustered vs random) indicates
        cause: clustered = routing flaps, random = congestion/interference.

    .EXAMPLE
        PS > # WORKFLOW: Comparing service endpoints
        PS > $endpoints = @('api-us-east.com', 'api-us-west.com', 'api-eu.com')
        PS > $results = foreach ($ep in $endpoints) {
        >>       Get-NetworkMetrics -HostName $ep -Port 8080 -Count 50
        >>   }
        PS > $results | Select-Object HostName,LatencyAvg,Jitter,PacketLoss | Format-Table
        PS > # Rank by overall quality
        PS > $best = $results | Sort-Object -Property @(
        >>       @{Expression={$_.PacketLoss}; Ascending=$true},
        >>       @{Expression={$_.LatencyAvg}; Ascending=$true},
        >>       @{Expression={$_.Jitter}; Ascending=$true}
        >>   ) | Select-Object -First 1
        PS > "Best endpoint: $($best.HostName)"

        Compare multiple endpoints quantitatively. Rank by packet loss (priority), then
        latency, then jitter to identify optimal endpoint.

    .EXAMPLE
        PS > # WORKFLOW: DNS performance investigation
        PS > $dns1 = Get-NetworkMetrics -HostName '8.8.8.8' -Port 53 -IncludeDns -Count 30
        PS > $dns2 = Get-NetworkMetrics -HostName '1.1.1.1' -Port 53 -IncludeDns -Count 30
        PS > "Google DNS: $($dns1.DnsResolution)ms avg latency: $($dns1.LatencyAvg)ms"
        PS > "Cloudflare DNS: $($dns2.DnsResolution)ms avg latency: $($dns2.LatencyAvg)ms"
        PS > $site = Get-NetworkMetrics -HostName 'slow-website.com' -IncludeDns -Count 20
        PS > if ($site.DnsResolution -gt $site.LatencyAvg) {
        >>     "DNS resolution ($($site.DnsResolution)ms) is slower than network latency ($($site.LatencyAvg)ms)"
        >>     "Consider: Using different DNS server or checking DNS infrastructure"
        >> }

        Identify whether DNS or network latency is the bottleneck. Compare DNS resolution
        time against network latency to isolate the problem.

    .EXAMPLE
        PS > # WORKFLOW: Service health baseline and comparison
        PS > # Step 1: Create baseline during healthy period
        PS > $baseline = Get-NetworkMetrics -HostName 'prod-database.com' -Port 3306 -Count 100
        PS > $baseline | Export-Clixml -Path 'db-baseline.xml'
        PS > # Step 2: During incident, compare to baseline
        PS > $current = Get-NetworkMetrics -HostName 'prod-database.com' -Port 3306 -Count 100
        PS > $baseline = Import-Clixml -Path 'db-baseline.xml'
        PS > $degradation = [PSCustomObject]@{
        >>       LatencyIncrease = $current.LatencyAvg - $baseline.LatencyAvg
        >>       JitterIncrease = $current.Jitter - $baseline.Jitter
        >>       PacketLossChange = $current.PacketLoss - $baseline.PacketLoss
        >>   }
        PS > $degradation | Format-List

        Quantify performance degradation vs. known good baseline. Establish baseline during
        healthy periods, then compare during incidents to measure impact.

    .OUTPUTS
        PSCustomObject with network metrics

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-NetworkMetrics.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$HostName,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [Int32]$Count = 10,

        [Parameter()]
        [ValidateRange(100, 30000)]
        [Int32]$Timeout = 2000,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [Int32]$Port = 443,

        [Parameter()]
        [Switch]$IncludeDns,

        [Parameter()]
        [ValidateRange(0, 5000)]
        [Int32]$SampleDelayMilliseconds = 100
    )

    begin
    {
        Write-Verbose "Starting network metrics collection for $HostName"

        # Initialize collections (allow nulls so we can mark failed samples)
        $latencies = [System.Collections.Generic.List[Nullable[Double]]]::new()
        $results = [System.Collections.Generic.List[Bool]]::new()
        $dnsTime = $null

        # DNS resolution if requested
        if ($IncludeDns)
        {
            Write-Verbose 'Measuring DNS resolution time'
            $dnsStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try
            {
                $null = [System.Net.Dns]::GetHostAddresses($HostName)
                $dnsStopwatch.Stop()
                $dnsTime = $dnsStopwatch.Elapsed.TotalMilliseconds
                Write-Verbose "DNS resolution: $([Math]::Round($dnsTime, 2))ms"
            }
            catch
            {
                Write-Verbose "DNS resolution failed: $($_.Exception.Message)"
                $dnsTime = $null
            }
        }
    }

    process
    {
        Write-Verbose "Testing connectivity to ${HostName}:${Port} ($Count samples)"

        for ($i = 1; $i -le $Count; $i++)
        {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $success = $false
            $tcpClient = $null

            try
            {
                $tcpClient = [System.Net.Sockets.TcpClient]::new()

                # Use BeginConnect/EndConnect with timeout for broad compatibility
                $asyncResult = $tcpClient.BeginConnect($HostName, $Port, $null, $null)
                $waitHandle = $asyncResult.AsyncWaitHandle

                if ($waitHandle.WaitOne($Timeout, $false))
                {
                    try
                    {
                        $tcpClient.EndConnect($asyncResult)
                        $stopwatch.Stop()
                        $latency = $stopwatch.Elapsed.TotalMilliseconds
                        $latencies.Add($latency)
                        $success = $true
                        Write-Verbose "Sample $i/$Count : $([Math]::Round($latency, 2))ms"
                    }
                    catch
                    {
                        $stopwatch.Stop()
                        Write-Verbose "Sample $i/$Count : Connection failed - $($_.Exception.Message)"
                        $latencies.Add($null)
                    }
                }
                else
                {
                    $stopwatch.Stop()
                    Write-Verbose "Sample $i/$Count : Timeout"
                    $latencies.Add($null)
                    $tcpClient.Close()
                }
            }
            catch
            {
                $stopwatch.Stop()
                Write-Verbose "Sample $i/$Count : Failed - $($_.Exception.Message)"
                $latencies.Add($null)
            }
            finally
            {
                if ($null -ne $tcpClient)
                {
                    $tcpClient.Close()
                    $tcpClient.Dispose()
                }
            }

            $results.Add($success)

            # Small delay between requests
            if ($i -lt $Count -and $SampleDelayMilliseconds -gt 0)
            {
                Start-Sleep -Milliseconds $SampleDelayMilliseconds
            }
        }
    }

    end
    {
        # Calculate metrics from valid latencies in a single pass
        $successCount = @($results | Where-Object { $_ -eq $true }).Count
        $failureCount = $results.Count - $successCount
        $packetLoss = [Math]::Round(($failureCount / $results.Count) * 100, 2)

        $validCount = 0
        $minLatency = [Double]::PositiveInfinity
        $maxLatency = [Double]::NegativeInfinity
        $sumLatency = 0.0
        $sumLatencySq = 0.0

        foreach ($latency in $latencies)
        {
            if ($null -eq $latency)
            {
                continue
            }

            $value = [double]$latency
            $validCount++
            if ($value -lt $minLatency) { $minLatency = $value }
            if ($value -gt $maxLatency) { $maxLatency = $value }
            $sumLatency += $value
            $sumLatencySq += ($value * $value)
        }

        if ($validCount -gt 0)
        {
            $avgLatency = $sumLatency / $validCount
            $variance = ([Math]::Max(0, ($sumLatencySq / $validCount) - ($avgLatency * $avgLatency)))
            $jitter = [Math]::Sqrt($variance)
        }
        else
        {
            $minLatency = $null
            $maxLatency = $null
            $avgLatency = $null
            $jitter = $null
        }

        Write-Verbose 'Metrics collection completed'

        # Return metrics object
        [PSCustomObject]@{
            HostName = $HostName
            Port = $Port
            SamplesTotal = $Count
            SamplesSuccess = $successCount
            SamplesFailure = $failureCount
            PacketLoss = $packetLoss
            LatencyMin = if ($null -ne $minLatency) { [Math]::Round($minLatency, 2) } else { $null }
            LatencyMax = if ($null -ne $maxLatency) { [Math]::Round($maxLatency, 2) } else { $null }
            LatencyAvg = if ($null -ne $avgLatency) { [Math]::Round($avgLatency, 2) } else { $null }
            Jitter = if ($null -ne $jitter) { [Math]::Round($jitter, 2) } else { $null }
            DnsResolution = if ($null -ne $dnsTime) { [Math]::Round($dnsTime, 2) } else { $null }
            LatencyData = $latencies.ToArray()
            Timestamp = Get-Date
        }
    }
}
