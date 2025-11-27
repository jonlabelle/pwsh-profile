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
        - Latency (min/max/avg/current)
        - Packet loss percentage
        - Jitter (latency variance)
        - DNS resolution time
        - Success/failure counts

    .PARAMETER HostName
        Target hostname or IP address to test

    .PARAMETER Count
        Number of test iterations to perform (default: 10)

    .PARAMETER Timeout
        Timeout in milliseconds for each test (default: 2000)

    .PARAMETER Port
        TCP port to test (default: 443)

    .PARAMETER IncludeDns
        Include DNS resolution time in metrics

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
        PS > Get-NetworkMetrics -HostName 'database.local' -Port 3306 -Timeout 5000 -Count 30

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
        [Switch]$IncludeDns
    )

    begin
    {
        Write-Verbose "Starting network metrics collection for $HostName"

        # Initialize collections
        $latencies = [System.Collections.Generic.List[Double]]::new()
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
                $tcpClient = New-Object System.Net.Sockets.TcpClient

                # Use BeginConnect/EndConnect for timeout support
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
                        Write-Verbose "Sample $i/$Count : Connection failed - $($_.Exception.Message)"
                        $latencies.Add($null)
                    }
                }
                else
                {
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
            if ($i -lt $Count)
            {
                Start-Sleep -Milliseconds 100
            }
        }
    }

    end
    {
        # Calculate metrics from valid latencies
        $validLatencies = @($latencies | Where-Object { $null -ne $_ })
        $successCount = @($results | Where-Object { $_ -eq $true }).Count
        $failureCount = $results.Count - $successCount
        $packetLoss = [Math]::Round(($failureCount / $results.Count) * 100, 2)

        if ($validLatencies.Count -gt 0)
        {
            $minLatency = ($validLatencies | Measure-Object -Minimum).Minimum
            $maxLatency = ($validLatencies | Measure-Object -Maximum).Maximum
            $avgLatency = ($validLatencies | Measure-Object -Average).Average

            # Calculate jitter (standard deviation)
            $variance = 0
            foreach ($latency in $validLatencies)
            {
                $variance += [Math]::Pow($latency - $avgLatency, 2)
            }
            $jitter = [Math]::Sqrt($variance / $validLatencies.Count)
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
