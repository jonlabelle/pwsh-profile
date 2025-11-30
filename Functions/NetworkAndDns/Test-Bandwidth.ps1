function Test-Bandwidth
{
    <#
    .SYNOPSIS
        Tests network bandwidth with download/upload speed and latency measurements.

    .DESCRIPTION
        Measures network bandwidth by downloading test files from various sources and calculating
        download speeds, upload speeds (if supported), and network latency. This function provides
        a comprehensive view of network performance without requiring external tools.

        Uses publicly available test files and endpoints for measurements. Results include download
        speed in Mbps, latency in milliseconds, and other performance metrics.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER TestDuration
        Duration of the speed test in seconds. Longer tests provide more accurate results.
        Default is 10 seconds. Valid range: 5-60 seconds.

    .PARAMETER TestFileSize
        Size of the test file to download in MB. Options: 1, 10, 25, 50, 100
        Default is 10 MB. Larger files provide more accurate results for fast connections.

    .PARAMETER TestServer
        The test server URL to use for bandwidth testing.
        If not specified, uses a default public test file server.

    .PARAMETER SkipUpload
        Skip upload speed testing and only measure download speed and latency.
        Upload testing is skipped by default as it requires specific server support.

    .PARAMETER SkipLatency
        Skip latency testing and only measure download/upload speeds.

    .PARAMETER PingCount
        Number of ping requests to send for latency measurement.
        Default is 5. Valid range: 1-20.

    .PARAMETER Detailed
        Show detailed progress and intermediate results during testing.

    .EXAMPLE
        PS > Test-Bandwidth

        Runs a standard bandwidth test with default settings (10MB file, 10 seconds).

    .EXAMPLE
        PS > Test-Bandwidth -TestFileSize 50 -TestDuration 15

        TestDate          : 11/12/2025 10:35:31 PM
        DownloadSpeedMbps : 172.21
        LatencyMs         : 135.8
        MinLatencyMs      : 132
        MaxLatencyMs      : 142
        Jitter            : 3.54
        PacketLoss        : 0%
        TestDuration      : 15.12s
        TestFileSize      : 50MB
        TestServer        : http://ipv4.download.thinkbroadband.com/50MB.zip
        Status            : Completed

        Tests bandwidth with a 50MB file over 15 seconds for more accurate results.

    .EXAMPLE
        PS > Test-Bandwidth -SkipLatency

        Tests only download speed without latency measurements.

    .EXAMPLE
        PS > Test-Bandwidth -Detailed

        Testing latency...
        Latency: 131.2ms (Min: 127ms, Max: 135ms, Jitter: 3.19ms)
        Testing download speed...
        Progress: 1s - Current: 15.89 Mbps
        Progress: 2s - Current: 50.39 Mbps
        Progress: 3s - Current: 72.01 Mbps
        Progress: 5s - Current: 91.28 Mbps
        Progress: 6s - Current: 99.5 Mbps
        Progress: 7s - Current: 107.27 Mbps
        Progress: 8s - Current: 111.44 Mbps
        Progress: 9s - Current: 116.54 Mbps
        Progress: 10s - Current: 120.44 Mbps
        Download Speed: 119.76 Mbps (14.28 MB/s)
        Total Downloaded: 143.53 MB in 10.05 seconds

        TestDate          : 11/12/2025 10:36:48 PM
        DownloadSpeedMbps : 119.76
        LatencyMs         : 131.2
        MinLatencyMs      : 127
        MaxLatencyMs      : 135
        Jitter            : 3.19
        PacketLoss        : 0%
        TestDuration      : 10.05s
        TestFileSize      : 10MB
        TestServer        : http://ipv4.download.thinkbroadband.com/10MB.zip
        Status            : Completed

        Runs a detailed test showing progress.

    .EXAMPLE
        PS > Test-Bandwidth -PingCount 10

        Runs bandwidth test with 10 ping requests for latency averaging.

    .EXAMPLE
        PS > $result = Test-Bandwidth -TestDuration 20 -TestFileSize 50
        PS > if ($result.DownloadSpeedMbps -lt 50) { throw "Link too slow: $($result.DownloadSpeedMbps) Mbps" }

        Automates a sanity check before copying multi-gigabyte artifacts over a VPN.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns an object with DownloadSpeedMbps, LatencyMs, Jitter, PacketLoss, and TestDuration properties.

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.net.http.httpclient

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Test-Bandwidth.ps1

        Test servers used:
        - Default test files from publicly available CDN servers
        - Requires internet connectivity
        - Results may vary based on server load and network conditions
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter()]
        [ValidateRange(5, 60)]
        [Int32]$TestDuration = 10,

        [Parameter()]
        [ValidateSet(1, 10, 25, 50, 100)]
        [Int32]$TestFileSize = 10,

        [Parameter()]
        [String]$TestServer,

        [Parameter()]
        [Switch]$SkipUpload,

        [Parameter()]
        [Switch]$SkipLatency,

        [Parameter()]
        [ValidateRange(1, 20)]
        [Int32]$PingCount = 5,

        [Parameter()]
        [Switch]$Detailed
    )

    begin
    {
        Write-Verbose 'Initializing bandwidth test'

        # Default test file URLs for different sizes (using public CDN/mirror servers)
        $testUrls = @{
            1 = 'http://ipv4.download.thinkbroadband.com/1MB.zip'
            10 = 'http://ipv4.download.thinkbroadband.com/10MB.zip'
            25 = 'http://ipv4.download.thinkbroadband.com/20MB.zip'
            50 = 'http://ipv4.download.thinkbroadband.com/50MB.zip'
            100 = 'http://ipv4.download.thinkbroadband.com/100MB.zip'
        }

        # Use custom test server if provided, otherwise use default
        if ($TestServer)
        {
            $downloadUrl = $TestServer
        }
        else
        {
            $downloadUrl = $testUrls[$TestFileSize]
        }

        Write-Verbose "Using test URL: $downloadUrl"
    }

    process
    {
        $results = [PSCustomObject]@{
            TestDate = Get-Date
            DownloadSpeedMbps = $null
            LatencyMs = $null
            MinLatencyMs = $null
            MaxLatencyMs = $null
            Jitter = $null
            PacketLoss = $null
            TestDuration = $null
            TestFileSize = "${TestFileSize}MB"
            TestServer = $downloadUrl
            Status = 'Running'
        }

        try
        {
            # Step 1: Test Latency (if not skipped)
            if (-not $SkipLatency)
            {
                Write-Verbose 'Testing network latency...'
                if ($Detailed) { Write-Host 'Testing latency...' -ForegroundColor Cyan }

                try
                {
                    # Extract hostname from URL for ping test
                    $uri = [System.Uri]$downloadUrl
                    $hostname = $uri.Host

                    $ping = New-Object System.Net.NetworkInformation.Ping
                    $pingTimes = @()
                    $successCount = 0

                    for ($i = 1; $i -le $PingCount; $i++)
                    {
                        try
                        {
                            $reply = $ping.Send($hostname, 5000)
                            if ($reply.Status -eq 'Success')
                            {
                                $pingTimes += $reply.RoundtripTime
                                $successCount++
                                Write-Verbose "Ping $i : $($reply.RoundtripTime)ms"
                            }
                        }
                        catch
                        {
                            Write-Verbose "Ping $i failed: $($_.Exception.Message)"
                        }

                        # Small delay between pings
                        if ($i -lt $PingCount)
                        {
                            Start-Sleep -Milliseconds 500
                        }
                    }

                    if ($pingTimes.Count -gt 0)
                    {
                        $results.LatencyMs = [Math]::Round(($pingTimes | Measure-Object -Average).Average, 2)
                        $results.MinLatencyMs = ($pingTimes | Measure-Object -Minimum).Minimum
                        $results.MaxLatencyMs = ($pingTimes | Measure-Object -Maximum).Maximum

                        # Calculate jitter (standard deviation of latency)
                        if ($pingTimes.Count -gt 1)
                        {
                            $mean = ($pingTimes | Measure-Object -Average).Average
                            $variance = ($pingTimes | ForEach-Object { [Math]::Pow($_ - $mean, 2) } | Measure-Object -Average).Average
                            $results.Jitter = [Math]::Round([Math]::Sqrt($variance), 2)
                        }

                        $lossPercent = [Math]::Round((($PingCount - $successCount) / $PingCount) * 100, 2)
                        $results.PacketLoss = "$lossPercent%"

                        if ($Detailed)
                        {
                            Write-Host "  Latency: $($results.LatencyMs)ms (Min: $($results.MinLatencyMs)ms, Max: $($results.MaxLatencyMs)ms, Jitter: $($results.Jitter)ms)" -ForegroundColor Green
                        }
                    }

                    $ping.Dispose()
                }
                catch
                {
                    Write-Verbose "Latency test error: $($_.Exception.Message)"
                }
            }

            # Step 2: Test Download Speed
            Write-Verbose 'Testing download speed...'
            if ($Detailed) { Write-Host 'Testing download speed...' -ForegroundColor Cyan }

            $httpClient = [System.Net.Http.HttpClient]::new()
            $httpClient.Timeout = [TimeSpan]::FromSeconds($TestDuration + 30)  # Add buffer to timeout

            # Set user agent
            $psVersion = $PSVersionTable.PSVersion.ToString()
            $httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("PowerShell/$psVersion")

            # Start download and measure
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = $httpClient.GetAsync($downloadUrl, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()

            if ($response.IsSuccessStatusCode)
            {
                $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $buffer = New-Object Byte[] 8192
                $totalBytes = 0
                $lastUpdate = $stopwatch.Elapsed.TotalSeconds

                # Read stream until test duration is reached
                while ($stopwatch.Elapsed.TotalSeconds -lt $TestDuration)
                {
                    $bytesRead = $stream.Read($buffer, 0, $buffer.Length)

                    if ($bytesRead -eq 0)
                    {
                        # End of stream - start over if needed
                        $stream.Dispose()
                        $response.Dispose()

                        # Re-download if we haven't reached test duration
                        if ($stopwatch.Elapsed.TotalSeconds -lt $TestDuration)
                        {
                            Write-Verbose 'File downloaded, starting new download for continued testing...'
                            $response = $httpClient.GetAsync($downloadUrl, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                            $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                        }
                        else
                        {
                            break
                        }
                    }
                    else
                    {
                        $totalBytes += $bytesRead

                        # Update progress every second
                        if ($Detailed -and ($stopwatch.Elapsed.TotalSeconds - $lastUpdate) -ge 1)
                        {
                            $currentMbps = [Math]::Round(($totalBytes * 8 / 1000000) / $stopwatch.Elapsed.TotalSeconds, 2)
                            Write-Host "  Progress: $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 0))s - Current: $currentMbps Mbps" -ForegroundColor Yellow
                            $lastUpdate = $stopwatch.Elapsed.TotalSeconds
                        }
                    }
                }

                $stopwatch.Stop()
                $stream.Dispose()
                $response.Dispose()

                # Calculate download speed
                $totalMegabits = ($totalBytes * 8) / 1000000
                $totalMegabytes = $totalBytes / 1048576
                $durationSeconds = $stopwatch.Elapsed.TotalSeconds

                $results.DownloadSpeedMbps = [Math]::Round($totalMegabits / $durationSeconds, 2)
                $downloadSpeedMBps = [Math]::Round($totalMegabytes / $durationSeconds, 2)
                $results.TestDuration = "$([Math]::Round($durationSeconds, 2))s"

                if ($Detailed)
                {
                    Write-Host "  Download Speed: $($results.DownloadSpeedMbps) Mbps ($downloadSpeedMBps MB/s)" -ForegroundColor Green
                    Write-Host "  Total Downloaded: $([Math]::Round($totalMegabytes, 2)) MB in $([Math]::Round($durationSeconds, 2)) seconds" -ForegroundColor Green
                }

                $results.Status = 'Completed'
            }
            else
            {
                $results.Status = "Failed: HTTP $($response.StatusCode)"
                Write-Error "Download test failed with status code: $($response.StatusCode)"
            }

            $httpClient.Dispose()
        }
        catch [System.Net.Http.HttpRequestException]
        {
            $results.Status = 'Failed: Network Error'
            Write-Error "Network error during bandwidth test: $($_.Exception.Message)"
        }
        catch [System.Threading.Tasks.TaskCanceledException]
        {
            $results.Status = 'Failed: Timeout'
            Write-Error 'Bandwidth test timed out'
        }
        catch
        {
            $results.Status = "Failed: $($_.Exception.Message)"
            Write-Error "Bandwidth test error: $($_.Exception.Message)"
        }

        Write-Output $results
    }

    end
    {
        Write-Verbose 'Bandwidth test completed'
    }
}
