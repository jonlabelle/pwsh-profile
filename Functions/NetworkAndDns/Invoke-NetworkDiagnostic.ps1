function Invoke-NetworkDiagnostic
{
    <#
    .SYNOPSIS
        Performs comprehensive network diagnostics with visual output

    .DESCRIPTION
        Tests network connectivity to one or more hosts and displays detailed metrics with
        ASCII graph visualizations. Collects latency, packet loss, jitter, and DNS resolution
        data over multiple samples. Per-host headers display the time spent collecting that
        host's metrics (shown as "collect XXms").

        Features:
        - Multi-host testing with parallel execution
        - Visual sparkline graphs of latency trends
        - Detailed time-series graphs (optional)
        - Comprehensive statistics table
        - Cross-platform compatible (Windows, macOS, Linux)

        Uses TCP connectivity tests for reliability across all platforms.

        RELATED FUNCTIONS:
        This function requires and auto-loads:
        - Get-NetworkMetrics: Collects network performance data for each host
        - Show-NetworkLatencyGraph: Generates sparkline graphs and optional time-series visualizations

        All dependencies are automatically loaded if not already available.

        See NOTES for PowerShell 5.1 behavior in continuous mode.

    .PARAMETER HostName
        One or more hostnames or IP addresses to test. Supports pipeline input.

    .PARAMETER Count
        Number of test samples per host (default: 20)

    .PARAMETER Timeout
        Timeout in milliseconds for each connection attempt (default: 2000)

    .PARAMETER Port
        TCP port to test (default: 443 for HTTPS)

    .PARAMETER SampleDelayMilliseconds
        Delay between samples in milliseconds (default: 100). Set to 0 for back-to-back samples.

    .PARAMETER RenderMode
        Controls how the output refreshes during continuous runs.

        Valid values:
        - Auto   : PowerShell 5.1 uses Clear (screen wipe), PowerShell 6+ uses InPlace (default)
        - InPlace: Update the same block using ANSI cursor moves (Core only; falls back to Clear on 5.1)
        - Clear  : Clear the screen between iterations
        - Stack  : Append output without clearing (useful for logs/debugging)

    .PARAMETER ShowGraph
        Display detailed time-series graph for each host

    .PARAMETER IncludeDns
        Measure and display DNS resolution time

    .PARAMETER SummaryOnly
        Render a compact, summary-only view (no sparklines or time-series graphs)

    .PARAMETER Continuous
        Run continuously until stopped with Ctrl+C

        Continuous mode notes:
        - Use '-Continuous' to refresh output periodically until Ctrl+C is pressed
        - Set '-Interval' to control seconds between refreshes (default: 5)
        - For testing/CI: use '-MaxIterations' to limit iterations (0 = infinite)
          Example: -Continuous -MaxIterations 1 runs one iteration and exits

    .PARAMETER Interval
        Interval in seconds between continuous test cycles (default: 5)

    .PARAMETER MaxIterations
        Hidden parameter for testing/CI. Limits the number of iterations in continuous mode.
        Default: 0 (infinite). Set to a positive number to run a specific number of iterations and exit.

    .PARAMETER ThrottleLimit
        Degree of parallelism when testing multiple hosts on PowerShell 7+ (default: logical core count, minimum 2)

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
        PS > Invoke-NetworkDiagnostic -HostName 'cloudflare.com' -Continuous -Interval 2 -RenderMode InPlace

        PowerShell Core: refreshes the same output block in place (no stacking)

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'cloudflare.com' -Continuous -Interval 2 -RenderMode Clear

        Force screen clear between iterations (useful if in-place rendering isn't desired)

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'cloudflare.com' -Continuous -Interval 2 -RenderMode Stack -MaxIterations 1

        Append a single iteration (good for logs/tests); no clear or in-place refresh

    .EXAMPLE
        PS > 'google.com', 'cloudflare.com' | Invoke-NetworkDiagnostic -Count 50

        Tests hosts via pipeline with 50 samples each

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName '8.8.8.8', '1.1.1.1' -Port 53 -IncludeDns -Count 30

        Compare DNS server performance (Google DNS vs Cloudflare DNS) including DNS resolution time

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'cloudflare.com' -Count 10 -SampleDelayMilliseconds 10 -Interval 1 -Continuous -MaxIterations 1

        Faster sampling cadence by reducing delay between samples while keeping interval short

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

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'google.com','cloudflare.com','github.com' -Count 15 -SummaryOnly

        Parallel tests (PowerShell 7+) with a compact summary-only view for multiple hosts

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'api.example.com','db.example.com' -Continuous -Interval 3 -ThrottleLimit 4

        Continuous monitoring of multiple hosts with capped parallelism (PowerShell 7+)

    .OUTPUTS
        System.String (formatted diagnostic output)

    .NOTES
        POWERSHELL 5.1 BEHAVIOR:
        - PowerShell Desktop 5.1 does not support ANSI cursor control for in-place updates
        - Console is cleared between iterations using Clear-Host in continuous mode
        - ANSI colors are automatically disabled on 5.1 to prevent escape codes in output
        - PowerShell Core (6+) supports ANSI colors and in-place rendering
        - In continuous mode on Core, the default RenderMode is InPlace; use -RenderMode Clear for a full-screen refresh each loop or -RenderMode Stack to append output without clearing

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
        [ValidateRange(0, 5000)]
        [Int32]$SampleDelayMilliseconds = 100,

        [Parameter()]
        [Switch]$ShowGraph,

        [Parameter()]
        [Switch]$IncludeDns,

        [Parameter()]
        [Switch]$SummaryOnly,

        [Parameter()]
        [Switch]$Continuous,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [Int32]$Interval = 5,

        # Hidden/testing-only: limit iterations for continuous mode (0 = infinite)
        [Parameter()]
        [Int32]$MaxIterations = 0,

        [Parameter()]
        [ValidateSet('Auto', 'InPlace', 'Clear', 'Stack')]
        [String]$RenderMode = 'Auto',

        [Parameter()]
        [ValidateRange(1, 256)]
        [Int32]$ThrottleLimit = ([Math]::Max(2, [Environment]::ProcessorCount))
    )

    begin
    {
        Write-Verbose 'Starting network diagnostics'

        # Validate parameter combinations
        # -Interval, -MaxIterations, and non-Auto -RenderMode only apply when -Continuous is used
        if (-not $Continuous)
        {
            if ($PSBoundParameters.ContainsKey('Interval'))
            {
                throw 'The -Interval parameter can only be used with -Continuous.'
            }

            if ($PSBoundParameters.ContainsKey('MaxIterations'))
            {
                throw 'The -MaxIterations parameter can only be used with -Continuous.'
            }

            if ($PSBoundParameters.ContainsKey('RenderMode') -and $RenderMode -ne 'Auto')
            {
                throw 'The -RenderMode parameter only applies to -Continuous. Use -RenderMode Auto for non-continuous runs.'
            }
        }

        # Load Get-NetworkMetrics if needed
        if (-not (Get-Command -Name 'Get-NetworkMetrics' -ErrorAction SilentlyContinue))
        {
            Write-Verbose 'Get-NetworkMetrics is required - attempting to load it'
            $metricsPath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-NetworkMetrics.ps1'
            $metricsPath = [System.IO.Path]::GetFullPath($metricsPath)
            $script:MetricsPath = $metricsPath

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
            $existingMetricsPath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-NetworkMetrics.ps1'
            $existingMetricsPath = [System.IO.Path]::GetFullPath($existingMetricsPath)
            $script:MetricsPath = $existingMetricsPath
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
                [PSCustomObject[]]$Results,

                [Parameter()]
                [Switch]$Continuous,

                [Parameter()]
                [Switch]$ReturnLineCount,

                [Parameter()]
                [Switch]$InPlace,

                [Parameter()]
                [Switch]$SummaryOnly
            )

            $output = New-Object System.Text.StringBuilder
            $linesPrintedLocal = 0

            # Cache rendered graphs within an iteration to avoid duplicate string building
            $graphCache = [System.Collections.Generic.Dictionary[string, string]]::new()
            $getCachedGraph = {
                param(
                    [AllowNull()][Object[]]$Data,
                    [String]$GraphType,
                    [Int32]$Width = 0,
                    [Int32]$Height = 0,
                    [Bool]$ShowStats = $false
                )

                $dataKey = ($Data | ForEach-Object { if ($null -eq $_) { 'null' } else { $_ } }) -join ','
                $key = [string]::Join('|', @($GraphType, $Width, $Height, $ShowStats, $dataKey))

                if ($graphCache.ContainsKey($key))
                {
                    return $graphCache[$key]
                }

                $graphParams = @{
                    Data = $Data
                    GraphType = $GraphType
                }
                if ($Width -gt 0) { $graphParams['Width'] = $Width }
                if ($Height -gt 0) { $graphParams['Height'] = $Height }
                if ($ShowStats) { $graphParams['ShowStats'] = $true }

                $graph = Show-NetworkLatencyGraph @graphParams
                $graphCache[$key] = $graph
                return $graph
            }

            [void]$output.AppendLine()
            [void]$output.AppendLine('═' * 80)
            [void]$output.AppendLine('  NETWORK DIAGNOSTIC RESULTS')
            [void]$output.AppendLine('═' * 80)
            [void]$output.AppendLine()

            $clearTail = if ($InPlace) { "`e[K" } else { '' }

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

                $successRate = [Math]::Round((($result.SamplesSuccess / $result.SamplesTotal) * 100), 1)

                # Host header with color coding and elapsed time if available
                $elapsedText = ''
                if ($result.PSObject.Properties.Match('ElapsedMs'))
                {
                    $elapsedText = " (collect $([Math]::Round($result.ElapsedMs, 1))ms)"
                }
                Write-Host ("┌─ $($result.HostName):$($result.Port)$elapsedText$clearTail") -ForegroundColor $statusColor
                $linesPrintedLocal++

                if ($SummaryOnly)
                {
                    if ($null -ne $result.LatencyAvg)
                    {
                        Write-Host '│  Summary: ' -NoNewline
                        Write-Host 'avg ' -NoNewline -ForegroundColor Gray
                        $avgColor = if ($result.LatencyAvg -lt 50) { 'Green' } elseif ($result.LatencyAvg -lt 100) { 'Yellow' } else { 'Red' }
                        Write-Host "$($result.LatencyAvg)ms" -NoNewline -ForegroundColor $avgColor
                        Write-Host ' | jitter ' -NoNewline -ForegroundColor Gray
                        $jitterColor = if ($result.Jitter -lt 10) { 'Green' } elseif ($result.Jitter -lt 30) { 'Yellow' } else { 'Red' }
                        Write-Host "$($result.Jitter)ms" -NoNewline -ForegroundColor $jitterColor
                        Write-Host ' | loss ' -NoNewline -ForegroundColor Gray
                        $lossColor = if ($result.PacketLoss -eq 0) { 'Green' } elseif ($result.PacketLoss -lt 5) { 'Yellow' } else { 'Red' }
                        Write-Host "$($result.PacketLoss)%" -NoNewline -ForegroundColor $lossColor
                        Write-Host ' | success ' -NoNewline -ForegroundColor Gray
                        $qualityColor = if ($successRate -ge 98) { 'Green' } elseif ($successRate -ge 90) { 'Yellow' } else { 'Red' }
                        Write-Host "$($result.SamplesSuccess)/$($result.SamplesTotal)" -NoNewline -ForegroundColor $qualityColor
                        if ($null -ne $result.DnsResolution)
                        {
                            Write-Host ' | dns ' -NoNewline -ForegroundColor Gray
                            $dnsColor = if ($result.DnsResolution -lt 50) { 'Green' } elseif ($result.DnsResolution -lt 150) { 'Yellow' } else { 'Red' }
                            Write-Host "$($result.DnsResolution)ms" -NoNewline -ForegroundColor $dnsColor
                        }
                        Write-Host $clearTail
                    }
                    else
                    {
                        Write-Host ("│  Summary: No successful connections$clearTail") -ForegroundColor Red
                    }
                    $linesPrintedLocal++
                    Write-Host (('└' + ('─' * 79) + $clearTail)) -ForegroundColor $statusColor
                    Write-Host
                    $linesPrintedLocal += 2
                    continue
                }

                # Latency sparkline (already has color codes embedded)
                $sparkline = & $getCachedGraph $result.LatencyData 'Sparkline' 0 0 $false
                if ($null -ne $result.LatencyAvg)
                {
                    Write-Host '│  Latency: ' -NoNewline
                    # Use default color to preserve ANSI codes in sparkline
                    Write-Host ("$sparkline$clearTail")
                    $linesPrintedLocal++
                }
                else
                {
                    Write-Host '│  Latency: ' -NoNewline
                    Write-Host ("$sparkline$clearTail") -ForegroundColor Red
                    $linesPrintedLocal++
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
                    Write-Host ("$($result.Jitter)ms$clearTail") -ForegroundColor $jitterColor
                    $linesPrintedLocal++
                }
                else
                {
                    Write-Host ("│  Stats  : No successful connections$clearTail") -ForegroundColor Red
                    $linesPrintedLocal++
                }

                # Packet loss and success rate with color coding
                Write-Host '│  Quality: ' -NoNewline
                Write-Host "$($result.SamplesSuccess)/$($result.SamplesTotal)" -NoNewline -ForegroundColor Cyan
                $qualityColor = if ($successRate -ge 98) { 'Green' } elseif ($successRate -ge 90) { 'Yellow' } else { 'Red' }
                Write-Host ' successful (' -NoNewline
                Write-Host "$successRate%" -NoNewline -ForegroundColor $qualityColor
                Write-Host ') | Packet Loss: ' -NoNewline
                $lossColor = if ($result.PacketLoss -eq 0) { 'Green' } elseif ($result.PacketLoss -lt 5) { 'Yellow' } else { 'Red' }
                Write-Host ("$($result.PacketLoss)%$clearTail") -ForegroundColor $lossColor
                $linesPrintedLocal++

                # DNS resolution time with color coding
                if ($null -ne $result.DnsResolution)
                {
                    Write-Host '│  DNS    : ' -NoNewline
                    $dnsColor = if ($result.DnsResolution -lt 50) { 'Green' } elseif ($result.DnsResolution -lt 150) { 'Yellow' } else { 'Red' }
                    Write-Host "$($result.DnsResolution)ms" -NoNewline -ForegroundColor $dnsColor
                    Write-Host (" resolution time$clearTail")
                    $linesPrintedLocal++
                }

                # Detailed graph if requested
                if ($ShowGraph -and $result.LatencyData.Count -gt 0)
                {
                    Write-Host '│'
                    $graph = & $getCachedGraph $result.LatencyData 'TimeSeries' 70 8 $true
                    $graphLineCount = 0
                    foreach ($line in $graph -split "`n")
                    {
                        # Don't override colors - graph has embedded ANSI codes
                        Write-Host ("│  $line")
                        $graphLineCount++
                    }
                    # Include the pre-graph spacer line
                    $linesPrintedLocal += (1 + $graphLineCount)
                }

                Write-Host (('└' + ('─' * 79) + $clearTail)) -ForegroundColor $statusColor
                Write-Host
                $linesPrintedLocal += 2
            }

            if ($ReturnLineCount)
            {
                return $linesPrintedLocal
            }
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
        $lastRenderLines = 0
        do
        {
            $iteration++
            $iterationTimer = [System.Diagnostics.Stopwatch]::StartNew()
            # Determine effective render mode
            $effectiveRender = switch ($RenderMode)
            {
                'InPlace' { if ($PSVersionTable.PSVersion.Major -lt 6) { 'Clear' } else { 'InPlace' } }
                'Clear' { 'Clear' }
                'Stack' { 'Stack' }
                default { if ($PSVersionTable.PSVersion.Major -lt 6) { 'Clear' } else { 'InPlace' } }
            }

            if ($Continuous)
            {
                if ($effectiveRender -eq 'Clear' -and ($iteration -gt 1 -or $MaxIterations -eq 0))
                {
                    Clear-Host
                }
                elseif ($effectiveRender -eq 'InPlace' -and ($iteration -gt 1) -and $lastRenderLines -gt 0)
                {
                    # Move cursor up to the start of the previous block and reset to column 1
                    Write-Host ("`e[{0}A" -f $lastRenderLines) -NoNewline
                    Write-Host "`e[1G" -NoNewline
                }
            }
            if ($Continuous)
            {
                $clearTail = "`e[K"
                Write-Host ("Network Diagnostic - Iteration $iteration (Press Ctrl+C to stop)$clearTail") -ForegroundColor Cyan
                Write-Host ("Interval: ${Interval}s | Samples per host: $Count | Port: $Port$clearTail") -ForegroundColor Gray
            }
            $linesPrinted = if ($Continuous) { 2 } else { 0 }

            # Collect metrics for all hosts
            $results = @()
            $useParallel = ($PSVersionTable.PSVersion.Major -ge 7 -and $allHosts.Count -gt 1)
            if ($useParallel)
            {
                Write-Verbose "Collecting metrics in parallel (ThrottleLimit=$ThrottleLimit)"
                $indexedHosts = for ($i = 0; $i -lt $allHosts.Count; $i++) { [PSCustomObject]@{ HostName = $allHosts[$i]; Index = $i } }

                $results = $indexedHosts | ForEach-Object -Parallel {
                    if (-not (Get-Command -Name 'Get-NetworkMetrics' -ErrorAction SilentlyContinue) -and $using:MetricsPath)
                    {
                        try { . $using:MetricsPath } catch {}
                    }

                    $buildFailure = {
                        param($name, $port, $count)
                        [PSCustomObject]@{
                            HostName = $name
                            Port = $port
                            SamplesTotal = $count
                            SamplesSuccess = 0
                            SamplesFailure = $count
                            PacketLoss = 100
                            LatencyMin = $null
                            LatencyMax = $null
                            LatencyAvg = $null
                            Jitter = $null
                            DnsResolution = $null
                            LatencyData = @()
                            Timestamp = Get-Date
                        }
                    }

                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    $metrics = $null
                    try
                    {
                        $metrics = Get-NetworkMetrics -HostName $_.HostName -Count $using:Count -Timeout $using:Timeout -Port $using:Port -IncludeDns:$using:IncludeDns -SampleDelayMilliseconds $using:SampleDelayMilliseconds
                    }
                    catch
                    {
                        $metrics = & $buildFailure $_.HostName $using:Port $using:Count
                    }
                    $sw.Stop()
                    Add-Member -InputObject $metrics -NotePropertyName 'ElapsedMs' -NotePropertyValue ([Math]::Round($sw.Elapsed.TotalMilliseconds, 2)) -Force
                    [PSCustomObject]@{ Index = $_.Index; Metrics = $metrics }
                } -ThrottleLimit $ThrottleLimit

                $results = $results | Sort-Object Index | ForEach-Object { $_.Metrics }
            }
            else
            {
                foreach ($hostTarget in $allHosts)
                {
                    Write-Verbose "Collecting metrics for $hostTarget"
                    $sw = [System.Diagnostics.Stopwatch]::StartNew()

                    try
                    {
                        $metrics = Get-NetworkMetrics -HostName $hostTarget -Count $Count -Timeout $Timeout -Port $Port -IncludeDns:$IncludeDns -SampleDelayMilliseconds $SampleDelayMilliseconds
                    }
                    catch
                    {
                        $metrics = [PSCustomObject]@{
                            HostName = $hostTarget
                            Port = $Port
                            SamplesTotal = $Count
                            SamplesSuccess = 0
                            SamplesFailure = $Count
                            PacketLoss = 100
                            LatencyMin = $null
                            LatencyMax = $null
                            LatencyAvg = $null
                            Jitter = $null
                            DnsResolution = $null
                            LatencyData = @()
                            Timestamp = Get-Date
                        }
                    }
                    $sw.Stop()
                    Add-Member -InputObject $metrics -NotePropertyName 'ElapsedMs' -NotePropertyValue ([Math]::Round($sw.Elapsed.TotalMilliseconds, 2)) -Force

                    $results += $metrics
                }
            }

            # Ensure we have a non-null collection for formatting
            $results = @($results | Where-Object { $null -ne $_ })

            # Display formatted output and get accurate line count if needed
            $countOut = Format-DiagnosticOutput -Results $results -Continuous:$Continuous.IsPresent -ReturnLineCount:$Continuous.IsPresent -InPlace:($Continuous.IsPresent -and $effectiveRender -eq 'InPlace') -SummaryOnly:$SummaryOnly.IsPresent

            # Approximate lines printed per iteration for in-place refresh on Core and handle pacing
            if ($Continuous)
            {
                if ($null -ne $countOut) { $linesPrinted += [int]$countOut }

                if ($effectiveRender -eq 'InPlace')
                {
                    $lastRenderLines = $linesPrinted
                }
                else
                {
                    $lastRenderLines = 0
                }

                Start-Sleep -Seconds $Interval

            }

        } while ($Continuous -and ($MaxIterations -eq 0 -or $iteration -lt $MaxIterations))

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
