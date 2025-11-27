function Invoke-NetworkDiagnostic
{
    <#
    .SYNOPSIS
        Performs comprehensive network diagnostics with visual output

    .DESCRIPTION
        Tests network connectivity to one or more hosts and displays detailed metrics with
        ASCII graph visualizations. Collects latency, packet loss, jitter, and DNS resolution
        data over multiple samples.

        Features:
        - Multi-host testing with parallel execution
        - Visual sparkline graphs of latency trends
        - Detailed time-series graphs (optional)
        - Comprehensive statistics table
        - Cross-platform compatible (Windows, macOS, Linux)

        Uses TCP connectivity tests for reliability across all platforms.

    .PARAMETER HostName
        One or more hostnames or IP addresses to test. Supports pipeline input.

    .PARAMETER Count
        Number of test samples per host (default: 20)

    .PARAMETER Timeout
        Timeout in milliseconds for each connection attempt (default: 2000)

    .PARAMETER Port
        TCP port to test (default: 443 for HTTPS)

    .PARAMETER ShowGraph
        Display detailed time-series graph for each host

    .PARAMETER IncludeDns
        Measure and display DNS resolution time

    .PARAMETER Continuous
        Run continuously until stopped with Ctrl+C

    .PARAMETER Interval
        Interval in seconds between continuous test cycles (default: 5)

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'google.com'

        Tests google.com with default settings (20 samples, port 443)

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'google.com', '1.1.1.1', 'github.com' -Count 30

        Tests multiple hosts with 30 samples each

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'dns.google' -Port 53 -IncludeDns -ShowGraph

        Tests DNS server with detailed graph and DNS resolution metrics

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'cloudflare.com' -Continuous -Interval 10

        Continuously monitors cloudflare.com, updating every 10 seconds until Ctrl+C is pressed

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'google.com' -Continuous -ShowGraph -Interval 5

        Monitor with detailed time-series graphs, auto-refreshing every 5 seconds

    .EXAMPLE
        PS > 'google.com', 'cloudflare.com' | Invoke-NetworkDiagnostic -Count 50

        Tests hosts via pipeline with 50 samples each

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName '8.8.8.8', '1.1.1.1' -Port 53 -IncludeDns -Count 30

        Compare DNS server performance (Google DNS vs Cloudflare DNS) including DNS resolution time

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'github.com' -Continuous -Interval 2 -Count 15

        Quick continuous monitoring with 2-second refresh for troubleshooting intermittent issues

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'api.example.com' -Port 8080 -Count 100 -ShowGraph

        Test custom API endpoint on port 8080 with 100 samples and detailed graph

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'database.local' -Port 3306 -Timeout 5000 -Count 50

        Test database server connectivity with 5-second timeout per connection

    .EXAMPLE
        PS > $hosts = Get-Content hosts.txt
        PS > Invoke-NetworkDiagnostic -HostName $hosts -Count 25

        Test multiple hosts from a file with 25 samples each

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'vpn.company.com' -Port 443 -Continuous -ShowGraph

        Monitor VPN gateway continuously with visual graphs (default 5-second interval)

    .EXAMPLE
        PS > netdiag -HostName 'google.com' -Count 10

        Quick test using the 'netdiag' alias with 10 samples

    .OUTPUTS
        System.String (formatted diagnostic output)

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Invoke-NetworkDiagnostic.ps1
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Host', 'Target', 'ComputerName')]
        [String[]]$HostName,

        [Parameter()]
        [ValidateRange(5, 1000)]
        [Int32]$Count = 20,

        [Parameter()]
        [ValidateRange(100, 30000)]
        [Int32]$Timeout = 2000,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [Int32]$Port = 443,

        [Parameter()]
        [Switch]$ShowGraph,

        [Parameter()]
        [Switch]$IncludeDns,

        [Parameter()]
        [Switch]$Continuous,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [Int32]$Interval = 5
    )

    begin
    {
        Write-Verbose 'Starting network diagnostics'

        # Load Get-NetworkMetrics if needed
        if (-not (Get-Command -Name 'Get-NetworkMetrics' -ErrorAction SilentlyContinue))
        {
            Write-Verbose 'Get-NetworkMetrics is required - attempting to load it'
            $metricsPath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-NetworkMetrics.ps1'
            $metricsPath = [System.IO.Path]::GetFullPath($metricsPath)

            if (Test-Path -Path $metricsPath -PathType Leaf)
            {
                try
                {
                    . $metricsPath
                    Write-Verbose "Loaded Get-NetworkMetrics from: $metricsPath"
                }
                catch
                {
                    throw "Failed to load required dependency 'Get-NetworkMetrics' from '$metricsPath': $($_.Exception.Message)"
                }
            }
            else
            {
                throw "Required function 'Get-NetworkMetrics' could not be found. Expected location: $metricsPath"
            }
        }
        else
        {
            Write-Verbose 'Get-NetworkMetrics is already loaded'
        }

        # Load Show-NetworkLatencyGraph if needed
        if (-not (Get-Command -Name 'Show-NetworkLatencyGraph' -ErrorAction SilentlyContinue))
        {
            Write-Verbose 'Show-NetworkLatencyGraph is required - attempting to load it'
            $graphPath = Join-Path -Path $PSScriptRoot -ChildPath 'Show-NetworkLatencyGraph.ps1'
            $graphPath = [System.IO.Path]::GetFullPath($graphPath)

            if (Test-Path -Path $graphPath -PathType Leaf)
            {
                try
                {
                    . $graphPath
                    Write-Verbose "Loaded Show-NetworkLatencyGraph from: $graphPath"
                }
                catch
                {
                    throw "Failed to load required dependency 'Show-NetworkLatencyGraph' from '$graphPath': $($_.Exception.Message)"
                }
            }
            else
            {
                throw "Required function 'Show-NetworkLatencyGraph' could not be found. Expected location: $graphPath"
            }
        }
        else
        {
            Write-Verbose 'Show-NetworkLatencyGraph is already loaded'
        }

        # Collect all hosts from pipeline
        $allHosts = [System.Collections.Generic.List[String]]::new()

        # Helper function to format the output
        function Format-DiagnosticOutput
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject[]]$Results
            )

            $output = New-Object System.Text.StringBuilder

            [void]$output.AppendLine()
            [void]$output.AppendLine('═' * 80)
            [void]$output.AppendLine('  NETWORK DIAGNOSTIC RESULTS')
            [void]$output.AppendLine('═' * 80)
            [void]$output.AppendLine()

            foreach ($result in $Results)
            {
                # Determine overall status color based on packet loss and latency
                $statusColor = 'Green'
                if ($result.PacketLoss -gt 10 -or ($null -ne $result.LatencyAvg -and $result.LatencyAvg -gt 200))
                {
                    $statusColor = 'Red'
                }
                elseif ($result.PacketLoss -gt 2 -or ($null -ne $result.LatencyAvg -and $result.LatencyAvg -gt 100))
                {
                    $statusColor = 'Yellow'
                }

                # Host header with color coding
                Write-Host "┌─ $($result.HostName):$($result.Port)" -ForegroundColor $statusColor

                # Latency sparkline (already has color codes embedded)
                $sparkline = Show-NetworkLatencyGraph -Data $result.LatencyData -GraphType Sparkline
                if ($null -ne $result.LatencyAvg)
                {
                    $latencyColor = if ($result.LatencyAvg -lt 50) { 'Green' }
                    elseif ($result.LatencyAvg -lt 100) { 'Yellow' }
                    else { 'Red' }
                    Write-Host '│  Latency: ' -NoNewline
                    # Use default color to preserve ANSI codes in sparkline
                    Write-Host $sparkline
                }
                else
                {
                    Write-Host '│  Latency: ' -NoNewline
                    Write-Host $sparkline -ForegroundColor Red
                }

                # Statistics with color coding
                if ($null -ne $result.LatencyAvg)
                {
                    Write-Host '│  Stats  : ' -NoNewline
                    Write-Host 'min: ' -NoNewline -ForegroundColor Gray
                    Write-Host "$($result.LatencyMin)ms" -NoNewline -ForegroundColor Cyan
                    Write-Host ' | max: ' -NoNewline -ForegroundColor Gray
                    Write-Host "$($result.LatencyMax)ms" -NoNewline -ForegroundColor Cyan
                    Write-Host ' | avg: ' -NoNewline -ForegroundColor Gray
                    $avgColor = if ($result.LatencyAvg -lt 50) { 'Green' } elseif ($result.LatencyAvg -lt 100) { 'Yellow' } else { 'Red' }
                    Write-Host "$($result.LatencyAvg)ms" -NoNewline -ForegroundColor $avgColor
                    Write-Host ' | jitter: ' -NoNewline -ForegroundColor Gray
                    $jitterColor = if ($result.Jitter -lt 10) { 'Green' } elseif ($result.Jitter -lt 30) { 'Yellow' } else { 'Red' }
                    Write-Host "$($result.Jitter)ms" -ForegroundColor $jitterColor
                }
                else
                {
                    Write-Host '│  Stats  : No successful connections' -ForegroundColor Red
                }

                # Packet loss and success rate with color coding
                $successRate = [Math]::Round((($result.SamplesSuccess / $result.SamplesTotal) * 100), 1)
                Write-Host '│  Quality: ' -NoNewline
                Write-Host "$($result.SamplesSuccess)/$($result.SamplesTotal)" -NoNewline -ForegroundColor Cyan
                $qualityColor = if ($successRate -ge 98) { 'Green' } elseif ($successRate -ge 90) { 'Yellow' } else { 'Red' }
                Write-Host ' successful (' -NoNewline
                Write-Host "$successRate%" -NoNewline -ForegroundColor $qualityColor
                Write-Host ') | Packet Loss: ' -NoNewline
                $lossColor = if ($result.PacketLoss -eq 0) { 'Green' } elseif ($result.PacketLoss -lt 5) { 'Yellow' } else { 'Red' }
                Write-Host "$($result.PacketLoss)%" -ForegroundColor $lossColor

                # DNS resolution time with color coding
                if ($null -ne $result.DnsResolution)
                {
                    Write-Host '│  DNS    : ' -NoNewline
                    $dnsColor = if ($result.DnsResolution -lt 50) { 'Green' } elseif ($result.DnsResolution -lt 150) { 'Yellow' } else { 'Red' }
                    Write-Host "$($result.DnsResolution)ms" -NoNewline -ForegroundColor $dnsColor
                    Write-Host ' resolution time'
                }

                # Detailed graph if requested
                if ($ShowGraph -and $result.LatencyData.Count -gt 0)
                {
                    Write-Host '│'
                    $graph = Show-NetworkLatencyGraph -Data $result.LatencyData -GraphType TimeSeries -Width 70 -Height 8 -ShowStats
                    foreach ($line in $graph -split "`n")
                    {
                        if ($line.Trim())
                        {
                            # Don't override colors - graph has embedded ANSI codes
                            Write-Host "│  $line"
                        }
                    }
                }

                Write-Host ('└' + ('─' * 79)) -ForegroundColor $statusColor
                Write-Host
            }

            Write-Host "Test completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
            Write-Host

            return ''
        }
    }

    process
    {
        foreach ($hostTarget in $HostName)
        {
            $allHosts.Add($hostTarget)
        }
    }

    end
    {
        if ($allHosts.Count -eq 0)
        {
            Write-Warning 'No hosts specified'
            return
        }

        Write-Verbose "Testing $($allHosts.Count) host(s)"

        # Main test loop
        $iteration = 0
        $firstRun = $true
        do
        {
            $iteration++

            if ($Continuous)
            {
                if ($firstRun)
                {
                    Clear-Host
                    $firstRun = $false
                }
                else
                {
                    # Move cursor to top of screen for smooth animation
                    Write-Host "`e[H" -NoNewline
                }
                Write-Host "Network Diagnostic - Iteration $iteration (Press Ctrl+C to stop)" -ForegroundColor Cyan
                Write-Host "Interval: ${Interval}s | Samples per host: $Count | Port: $Port" -ForegroundColor Gray
            }

            # Collect metrics for all hosts
            $results = @()
            foreach ($hostTarget in $allHosts)
            {
                Write-Verbose "Collecting metrics for $hostTarget"

                $metrics = Get-NetworkMetrics -HostName $hostTarget -Count $Count -Timeout $Timeout -Port $Port -IncludeDns:$IncludeDns

                $results += $metrics
            }

            # Display formatted output
            Format-DiagnosticOutput -Results $results

            # Wait for next iteration if continuous
            if ($Continuous)
            {
                Write-Host "Waiting ${Interval} seconds until next test..." -ForegroundColor Gray
                Write-Host "`e[?25l" -NoNewline  # Hide cursor during wait
                Start-Sleep -Seconds $Interval
                Write-Host "`e[?25h" -NoNewline  # Show cursor
            }

        } while ($Continuous)

        Write-Verbose 'Network diagnostics completed'
    }
}

# Create alias 'netdiag' if it doesn't conflict
if (-not (Get-Command -Name 'netdiag' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'netdiag' alias for Invoke-NetworkDiagnostic"
        Set-Alias -Name 'netdiag' -Value 'Invoke-NetworkDiagnostic' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Invoke-NetworkDiagnostic: Could not create 'netdiag' alias: $($_.Exception.Message)"
    }
}
