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
        - Health grade assessment (A/B/C/D/F)
        - Color-coded status indicators
        - Cross-platform compatible (Windows, macOS, Linux)

        Uses TCP connectivity tests for reliability across all platforms.

        OUTPUT FORMAT:

        Each host result displays:
        ┌─ ✓ hostname:port [A] (collect XXms)
        │  Latency: ▂▃▄▂▁▂▃ (sparkline graph)
        │  Stats  : min: Xms | max: Xms | avg: Xms | jitter: Xms
        │  Quality: X/X successful (X%) | Packet Loss: X%
        │  Findings: Healthy ✓ (or list of issues)
        └───────────────────────────────────

        HEALTH GRADE SYSTEM:

        An overall letter grade (A-F) provides quick assessment of connection quality:
        - A: Excellent (score ≥90) - Low latency, no packet loss, minimal jitter
        - B: Good (score ≥75) - Acceptable for most applications
        - C: Acceptable (score ≥60) - Some issues but usable
        - D: Poor (score ≥40) - Significant problems affecting quality
        - F: Critical (score <40) - Severe issues or unreachable

        STATUS ICONS:

        Visual indicators for quick scanning:
        - ✓ (checkmark): Healthy connection (grade A or B)
        - ⚠ (warning): Degraded connection (grade C or D)
        - ✗ (cross): Critical issues or unreachable (grade F)

        COLOR THRESHOLDS:

        Metrics are color-coded based on industry standards:
        - Latency: Green <50ms | Yellow 50-99ms | Red ≥100ms
        - Jitter: Green <10ms | Yellow 10-29ms | Red ≥30ms
        - Packet Loss: Green 0% | Yellow 1-9% | Red ≥10%
        - DNS Resolution: Green <50ms | Yellow 50-149ms | Red ≥150ms

        Note: The "Findings" line uses higher thresholds for flagging issues:
        - Latency flagged at ≥100ms (yellow) or ≥200ms (red)
        - Jitter flagged at ≥30ms (yellow) or ≥50ms (red)
        - Packet Loss flagged at >2% (yellow) or ≥10% (red)

        TROUBLESHOOTING USE CASES:

        This function is essential for diagnosing network connectivity issues by providing
        visual, statistical insights that help identify:

        1. INTERMITTENT CONNECTIVITY ISSUES
           Problem: Users report occasional disconnections or slowness
           What to look for: Sparkline graphs showing periodic spikes or gray bars at baseline
           indicating packet loss patterns or connection timeouts

        2. NETWORK PATH DEGRADATION
           Problem: Application performance degrading over time
           What to look for: Ascending latency trend or increasing jitter values indicating
           progressive network congestion or routing changes

        3. PACKET LOSS DIAGNOSIS
           Problem: VoIP calls dropping or video conferencing issues
           What to look for: Packet loss > 2% indicates quality issues affecting real-time
           applications; > 5% is critical

        4. DNS RESOLUTION PROBLEMS
           Problem: Slow website loading or application startup delays
           What to look for: DNS resolution > 100ms or highly variable DNS times indicating
           DNS server performance issues or network path to DNS

        5. MULTI-PATH COMPARISON
           Problem: Choosing between multiple servers or CDN endpoints
           What to look for: Lower average latency, lower jitter, zero packet loss identifies
           optimal endpoint for routing decisions

        6. SERVICE AVAILABILITY MONITORING
           Problem: Need to verify service uptime during maintenance
           What to look for: Success rate dropping below 100% or sudden latency spikes
           indicating service degradation or failures

        7. NETWORK JITTER ANALYSIS
           Problem: Real-time applications experiencing inconsistent performance
           What to look for: Jitter > 30ms indicates unstable connection unsuitable for
           real-time apps; > 50ms is critical for VoIP/gaming

        8. FIREWALL/SECURITY TESTING
           Problem: Verify specific ports are accessible after firewall changes
           What to look for: 100% packet loss indicates port blocked by firewall or
           security policy; timeouts suggest filtering

        See EXAMPLES for practical troubleshooting workflows and usage scenarios.

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

        Note: When testing multiple hosts in parallel (PowerShell 7+), there may be brief output
        mixing during transitions. Use -RenderMode Clear for the cleanest output with multiple hosts.

    .PARAMETER ShowGraph
        Display detailed time-series graph for each host

    .PARAMETER Style
        Visualization style for time-series graphs when ShowGraph is used:
        - Dots: Clean dot plot showing only data points (default, easiest to read)
        - Bars: Vertical bars from baseline showing magnitude
        - Line: Simple line connections between points

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
        PS > Invoke-NetworkDiagnostic -HostName 'bing.com'

        Tests bing.com with default settings (20 samples, port 443)

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'bing.com', '1.1.1.1', 'github.com' -Count 30

        Tests multiple hosts with 30 samples each

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'dns.google' -Port 53 -IncludeDns -ShowGraph

        Tests DNS server with detailed graph and DNS resolution metrics

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'cloudflare.com' -Continuous -Interval 10

        Continuously monitors cloudflare.com, updating every 10 seconds until Ctrl+C is pressed

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'bing.com' -Continuous -ShowGraph -Interval 5

        Monitor with detailed time-series graphs, auto-refreshing every 5 seconds

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'api.example.com' -ShowGraph -Style Dots

        Test with clean dot plot visualization (default style, easiest to read)

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'api.example.com' -ShowGraph -Style Bars

        Test with bar chart visualization showing magnitude from baseline

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'api.example.com' -ShowGraph -Style Line

        Test with line plot visualization connecting data points

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
        PS > 'bing.com', 'cloudflare.com' | Invoke-NetworkDiagnostic -Count 50

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
        PS > netdiag -HostName 'bing.com' -Count 10

        Quick test using the 'netdiag' alias with 10 samples

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'bing.com','cloudflare.com','github.com' -Count 15 -SummaryOnly

        Parallel tests (PowerShell 7+) with a compact summary-only view for multiple hosts

    .EXAMPLE
        PS > Invoke-NetworkDiagnostic -HostName 'api.example.com','db.example.com' -Continuous -Interval 3 -ThrottleLimit 4

        Continuous monitoring of multiple hosts with capped parallelism (PowerShell 7+)

    .EXAMPLE
        PS > # TROUBLESHOOTING: Intermittent connectivity issues
        PS > # Problem: Users report occasional disconnections or slowness
        PS > Invoke-NetworkDiagnostic -HostName 'vpn.company.com' -Continuous -Interval 2

        Monitor continuously to catch sporadic failures. Look for sparkline graphs showing
        periodic spikes or gray bars at baseline indicating packet loss.

    .EXAMPLE
        PS > # TROUBLESHOOTING: Network path degradation
        PS > # Problem: Application performance degrading over time
        PS > Invoke-NetworkDiagnostic -HostName 'api.example.com' -ShowGraph -Count 100

        Monitor latency trends with visual graphs. Look for ascending latency trend or
        increasing jitter values indicating network congestion.

    .EXAMPLE
        PS > # TROUBLESHOOTING: VoIP quality issues
        PS > # Problem: VoIP calls dropping or video conferencing issues
        PS > Invoke-NetworkDiagnostic -HostName 'teams.microsoft.com' -Port 443 -Count 200

        Measure packet loss percentage over sustained period. Packet loss > 2% indicates
        quality issues affecting real-time applications.

    .EXAMPLE
        PS > # TROUBLESHOOTING: DNS resolution problems
        PS > # Problem: Slow website loading or application startup delays
        PS > Invoke-NetworkDiagnostic -HostName 'github.com' -IncludeDns -Count 50

        Include DNS resolution time in metrics. Look for DNS resolution > 100ms or highly
        variable DNS times indicating DNS server performance issues.

    .EXAMPLE
        PS > # TROUBLESHOOTING: Choosing between CDN endpoints
        PS > # Problem: Need to select optimal server from multiple options
        PS > Invoke-NetworkDiagnostic -HostName 'cdn1.example.com','cdn2.example.com' -Count 100

        Test multiple hosts simultaneously to compare performance. Choose endpoint with
        lowest average latency, lower jitter, and zero packet loss.

    .EXAMPLE
        PS > # TROUBLESHOOTING: Service availability during maintenance
        PS > # Problem: Need to verify service uptime during maintenance window
        PS > Invoke-NetworkDiagnostic -HostName 'database.local' -Port 5432 -Continuous

        Continuous monitoring with auto-refresh. Watch for success rate dropping below 100%
        or sudden latency spikes indicating service issues.

    .EXAMPLE
        PS > # TROUBLESHOOTING: Real-time application performance
        PS > # Problem: Gaming or real-time apps experiencing inconsistent performance
        PS > Invoke-NetworkDiagnostic -HostName 'game-server.net' -Port 27015 -ShowGraph -Count 200

        Monitor jitter (latency variance) over time. Jitter > 30ms indicates unstable
        connection unsuitable for real-time applications.

    .EXAMPLE
        PS > # TROUBLESHOOTING: Firewall port accessibility
        PS > # Problem: Verify specific ports are accessible after firewall changes
        PS > Invoke-NetworkDiagnostic -HostName 'smtp.company.com' -Port 587 -Count 20

        Test custom ports with detailed metrics. 100% packet loss indicates port blocked
        by firewall or security policy.

    .EXAMPLE
        PS > # WORKFLOW: Progressive diagnosis for slow website
        PS > # Step 1: Quick latency check
        PS > Get-NetworkMetrics -HostName 'website.com' -Count 10
        PS > # Step 2: If high latency, visualize the pattern
        PS > $metrics = Get-NetworkMetrics -HostName 'website.com' -Count 50
        PS > Show-NetworkLatencyGraph -Data $metrics.LatencyData -GraphType TimeSeries -ShowStats
        PS > # Step 3: Check if DNS is the culprit
        PS > Invoke-NetworkDiagnostic -HostName 'website.com' -IncludeDns -Count 30

        Progressive diagnosis workflow. Compare LatencyAvg vs DnsResolution to identify
        whether issue is network latency or DNS performance.

    .EXAMPLE
        PS > # WORKFLOW: API endpoint comparison
        PS > $api1 = Get-NetworkMetrics -HostName 'api-us-east.example.com' -Port 8080 -Count 100
        PS > $api2 = Get-NetworkMetrics -HostName 'api-us-west.example.com' -Port 8080 -Count 100
        PS > Show-NetworkLatencyGraph -Data $api1.LatencyData -GraphType Sparkline -ShowStats
        PS > Show-NetworkLatencyGraph -Data $api2.LatencyData -GraphType Sparkline -ShowStats
        PS > Invoke-NetworkDiagnostic -HostName 'api-us-east.example.com','api-us-west.example.com' -Port 8080 -Count 100 -ShowGraph

        Compare multiple API endpoints. Visualize side-by-side, then run comprehensive
        diagnostic to choose endpoint with best performance characteristics.

    .EXAMPLE
        PS > # WORKFLOW: Diagnosing intermittent connection drops
        PS > # Step 1: Monitor continuously to catch failures
        PS > Invoke-NetworkDiagnostic -HostName 'vpn.company.com' -Continuous -Interval 3
        PS > # Step 2: When drops occur, collect detailed samples
        PS > $metrics = Get-NetworkMetrics -HostName 'vpn.company.com' -Count 200 -SampleDelayMilliseconds 50
        PS > # Step 3: Analyze distribution pattern
        PS > Show-NetworkLatencyGraph -Data $metrics.LatencyData -GraphType Distribution -Width 80

        Diagnose intermittent issues. Bimodal distribution suggests routing flaps;
        consistent failures suggest firewall/ACL issues.

    .EXAMPLE
        PS > # WORKFLOW: Real-time application baseline comparison
        PS > $baseline = Get-NetworkMetrics -HostName 'game-server.net' -Port 27015 -Count 100
        PS > Invoke-NetworkDiagnostic -HostName 'game-server.net' -Port 27015 -Continuous -ShowGraph -Interval 5
        PS > "Baseline Jitter: $($baseline.Jitter)ms"  # Should be < 20ms for gaming

        Baseline during good period, then monitor during problems. Jitter increase > 50%
        indicates network path congestion or routing changes.

    .EXAMPLE
        PS > # WORKFLOW: Multi-service health check
        PS > $services = @('web.company.com:443', 'api.company.com:8080', 'db.company.com:5432')
        PS > foreach ($svc in $services) {
        >>       $host,$port = $svc -split ':'
        >>       Get-NetworkMetrics -HostName $host -Port $port -Count 10 | Select-Object HostName,Port,PacketLoss,LatencyAvg
        >>   }
        PS > Invoke-NetworkDiagnostic -HostName 'db.company.com' -Port 5432 -ShowGraph -Count 100

        Quick parallel test of critical services, then deep dive on problematic ones.
        Identify whether issues are service-specific or systemic network problems.

    .OUTPUTS
        None. Writes formatted diagnostic output to the host.

    .NOTES
        CONTINUOUS MODE:
        - Timestamps are shown for each refresh cycle: [HH:mm:ss] Refresh #N
        - Use '-Continuous' to monitor until Ctrl+C is pressed
        - Set '-Interval' to control seconds between refreshes (default: 5)

        POWERSHELL 5.1 BEHAVIOR:
        - PowerShell Desktop 5.1 does not support ANSI cursor control for in-place updates
        - Console is cleared between iterations using Clear-Host in continuous mode
        - ANSI colors are automatically disabled on 5.1 to prevent escape codes in output
        - PowerShell Core (6+) supports ANSI colors and in-place rendering
        - In continuous mode on Core, the default RenderMode is InPlace; use -RenderMode Clear for a full-screen refresh each loop or -RenderMode Stack to append output without clearing

        Author: Jon LaBelle
        License: MIT
    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Invoke-NetworkDiagnostic.ps1

        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Invoke-NetworkDiagnostic.ps1
    #>
    [CmdletBinding()]
    [OutputType([void])]
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
        [ValidateSet('Dots', 'Bars', 'Line')]
        [String]$Style = 'Dots',

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

        # Shared threshold constants for consistent color coding across all output
        # These align with industry standards for network quality assessment
        $script:Thresholds = @{
            Latency = @{
                Good = 50      # Green: < 50ms - suitable for real-time apps
                Warning = 100  # Yellow: 50-100ms - noticeable for interactive apps
                Critical = 200 # Red: > 200ms - degraded experience
            }
            Jitter = @{
                Good = 10      # Green: < 10ms - excellent for VoIP/gaming
                Warning = 30   # Yellow: 10-30ms - acceptable for most apps
                Critical = 50  # Red: > 50ms - unsuitable for real-time
            }
            PacketLoss = @{
                Good = 0       # Green: 0% - perfect connectivity
                Warning = 2    # Yellow: 0-2% - minor issues
                Critical = 10  # Red: > 10% - significant problems
            }
            Dns = @{
                Good = 50      # Green: < 50ms - fast DNS
                Warning = 100  # Yellow: 50-100ms - acceptable
                Critical = 150 # Red: > 150ms - slow DNS
            }
        }

        # Health grade calculation based on combined metrics
        # Returns: A (excellent), B (good), C (acceptable), D (poor), F (critical)
        function Get-NetworkHealthGrade
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Metrics,

                [Parameter()]
                [hashtable]$Thresholds = $script:Thresholds
            )

            if ($Metrics.SamplesSuccess -eq 0) { return 'F' }

            $score = 100

            # Deduct points for latency issues
            if ($null -ne $Metrics.LatencyAvg)
            {
                if ($Metrics.LatencyAvg -ge $Thresholds.Latency.Critical) { $score -= 40 }
                elseif ($Metrics.LatencyAvg -ge $Thresholds.Latency.Warning) { $score -= 20 }
                elseif ($Metrics.LatencyAvg -ge $Thresholds.Latency.Good) { $score -= 5 }
            }

            # Deduct points for jitter
            if ($null -ne $Metrics.Jitter)
            {
                if ($Metrics.Jitter -ge $Thresholds.Jitter.Critical) { $score -= 30 }
                elseif ($Metrics.Jitter -ge $Thresholds.Jitter.Warning) { $score -= 15 }
                elseif ($Metrics.Jitter -ge $Thresholds.Jitter.Good) { $score -= 5 }
            }

            # Deduct points for packet loss (most impactful)
            if ($Metrics.PacketLoss -ge $Thresholds.PacketLoss.Critical) { $score -= 50 }
            elseif ($Metrics.PacketLoss -gt $Thresholds.PacketLoss.Warning) { $score -= 25 }
            elseif ($Metrics.PacketLoss -gt $Thresholds.PacketLoss.Good) { $score -= 10 }

            # Convert score to grade
            switch ($score)
            {
                { $_ -ge 90 } { return 'A' }
                { $_ -ge 75 } { return 'B' }
                { $_ -ge 60 } { return 'C' }
                { $_ -ge 40 } { return 'D' }
                default { return 'F' }
            }
        }

        # Unicode status icons for visual health indicators
        $script:StatusIcons = @{
            Healthy = [char]0x2713   # ✓ checkmark
            Warning = [char]0x26A0  # ⚠ warning sign
            Critical = [char]0x2717 # ✗ cross mark
        }

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
                [Switch]$ReturnLineCount,

                [Parameter()]
                [Switch]$InPlace,

                [Parameter()]
                [Switch]$SummaryOnly
            )

            $linesPrintedLocal = 0
            $graphCache = [System.Collections.Generic.Dictionary[string, string]]::new()
            $getCachedGraph = {
                param(
                    [AllowNull()][Object[]]$Data,
                    [String]$GraphType,
                    [Int32]$Width = 0,
                    [Int32]$Height = 0,
                    [Bool]$ShowStats = $false,
                    [String]$GraphStyle = 'Dots'
                )

                $dataKey = ($Data | ForEach-Object { if ($null -eq $_) { 'null' } else { $_ } }) -join ','
                $key = [string]::Join('|', @($GraphType, $Width, $Height, $ShowStats, $GraphStyle, $dataKey))

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
                if ($GraphType -eq 'TimeSeries') { $graphParams['Style'] = $GraphStyle }

                $graph = Show-NetworkLatencyGraph @graphParams
                $graphCache[$key] = $graph
                return $graph
            }

            # Nested function for building issue flags
            # Takes thresholds as a parameter to avoid scope issues in continuous mode
            function Build-IssueFlags
            {
                param(
                    [PSCustomObject]$Result,
                    [hashtable]$Thresholds
                )

                # Use a flexible list so we don't trip over strict Add overloads on different PS versions
                $flags = [System.Collections.Generic.List[Object]]::new()

                if ($Result.SamplesSuccess -eq 0)
                {
                    $flags.Add([PSCustomObject]@{ Text = 'Unreachable'; Color = 'Red' })
                    return $flags
                }

                # Use passed thresholds for consistent evaluation
                $t = $Thresholds

                if ($Result.PacketLoss -ge $t.PacketLoss.Critical) { $flags.Add([PSCustomObject]@{ Text = "Loss $($Result.PacketLoss)%"; Color = 'Red' }) }
                elseif ($Result.PacketLoss -gt $t.PacketLoss.Warning) { $flags.Add([PSCustomObject]@{ Text = "Loss $($Result.PacketLoss)%"; Color = 'Yellow' }) }

                if ($null -ne $Result.LatencyAvg)
                {
                    if ($Result.LatencyAvg -ge $t.Latency.Critical) { $flags.Add([PSCustomObject]@{ Text = "Latency $($Result.LatencyAvg)ms"; Color = 'Red' }) }
                    elseif ($Result.LatencyAvg -ge $t.Latency.Warning) { $flags.Add([PSCustomObject]@{ Text = "Latency $($Result.LatencyAvg)ms"; Color = 'Yellow' }) }
                }

                if ($null -ne $Result.Jitter)
                {
                    if ($Result.Jitter -ge $t.Jitter.Critical) { $flags.Add([PSCustomObject]@{ Text = "Jitter $($Result.Jitter)ms"; Color = 'Red' }) }
                    elseif ($Result.Jitter -ge $t.Jitter.Warning) { $flags.Add([PSCustomObject]@{ Text = "Jitter $($Result.Jitter)ms"; Color = 'Yellow' }) }
                }

                if ($null -ne $Result.DnsResolution)
                {
                    if ($Result.DnsResolution -ge $t.Dns.Critical) { $flags.Add([PSCustomObject]@{ Text = "DNS $($Result.DnsResolution)ms"; Color = 'Yellow' }) }
                    elseif ($Result.DnsResolution -ge $t.Dns.Warning) { $flags.Add([PSCustomObject]@{ Text = "DNS $($Result.DnsResolution)ms"; Color = 'DarkYellow' }) }
                }

                if ($null -ne $Result.LatencyMax -and $null -ne $Result.LatencyAvg -and $Result.LatencyAvg -gt 0)
                {
                    $ratio = $Result.LatencyMax / $Result.LatencyAvg
                    if ($ratio -ge 2.5) { $flags.Add([PSCustomObject]@{ Text = "Spikes to $($Result.LatencyMax)ms"; Color = 'Red' }) }
                    elseif ($ratio -ge 1.8) { $flags.Add([PSCustomObject]@{ Text = "Spikes to $($Result.LatencyMax)ms"; Color = 'Yellow' }) }
                }

                return $flags
            }

            # Only use ANSI clear tail on PowerShell Core
            $clearTail = if ($InPlace -and $PSVersionTable.PSVersion.Major -ge 6) { "`e[K" } else { '' }
            # Only use ANSI reset codes on PowerShell Core
            $resetEsc = if ($PSVersionTable.PSVersion.Major -ge 6) { "`e[0m" } else { '' }

            function Write-FramePrefix
            {
                param(
                    [string]$FrameColor,
                    [string]$Text = ''
                )

                Write-Host '│' -NoNewline -ForegroundColor $FrameColor
                if (-not [string]::IsNullOrEmpty($Text))
                {
                    Write-Host $Text -NoNewline
                }
            }

            if ($Results.Count -eq 0)
            {
                Write-Host $clearTail
                Write-Host '  No results to display. All connection attempts may have failed.' -ForegroundColor Red
                Write-Host ("  Check your internet connection or firewall settings.$clearTail") -ForegroundColor Yellow
                Write-Host $clearTail
                $linesPrintedLocal += 3

                if ($ReturnLineCount)
                {
                    return $linesPrintedLocal
                }
                return ''
            }

            # Capture thresholds once at the start to avoid scope issues in nested functions
            $thresholds = $script:Thresholds

            foreach ($result in $Results)
            {
                $flags = Build-IssueFlags -Result $result -Thresholds $thresholds
                $t = $thresholds

                # Determine overall status color based on packet loss and latency using threshold constants
                $statusColor = 'Green'
                if ($result.PacketLoss -gt $t.PacketLoss.Critical -or ($null -ne $result.LatencyAvg -and $result.LatencyAvg -gt $t.Latency.Critical) -or ($null -ne $result.Jitter -and $result.Jitter -ge $t.Jitter.Critical))
                {
                    $statusColor = 'Red'
                }
                elseif ($result.PacketLoss -gt $t.PacketLoss.Warning -or ($null -ne $result.LatencyAvg -and $result.LatencyAvg -gt $t.Latency.Warning) -or ($null -ne $result.Jitter -and $result.Jitter -ge $t.Jitter.Warning))
                {
                    $statusColor = 'Yellow'
                }
                if ($flags | Where-Object { $_.Color -eq 'Red' })
                {
                    $statusColor = 'Red'
                }
                elseif ($statusColor -ne 'Red' -and ($flags | Where-Object { $_.Color -like '*Yellow*' }))
                {
                    $statusColor = 'Yellow'
                }

                # Calculate health grade for quick assessment
                $healthGrade = Get-NetworkHealthGrade -Metrics $result -Thresholds $thresholds
                $gradeColor = switch ($healthGrade)
                {
                    'A' { 'Green' }
                    'B' { 'Cyan' }
                    'C' { 'Yellow' }
                    'D' { 'DarkYellow' }
                    default { 'Red' }
                }

                # Select status icon based on health
                $statusIcon = switch ($healthGrade)
                {
                    { $_ -in 'A', 'B' } { $script:StatusIcons.Healthy }
                    { $_ -in 'C', 'D' } { $script:StatusIcons.Warning }
                    default { $script:StatusIcons.Critical }
                }

                $successRate = [Math]::Round((($result.SamplesSuccess / $result.SamplesTotal) * 100), 1)

                # Host header with color coding, health grade, and elapsed time if available
                $elapsedText = ''
                if ($result.PSObject.Properties.Match('ElapsedMs'))
                {
                    $elapsedText = " (collect $([Math]::Round($result.ElapsedMs, 1))ms)"
                }
                Write-Host ("┌─ $statusIcon ") -ForegroundColor $statusColor -NoNewline
                Write-Host "$($result.HostName):$($result.Port)" -ForegroundColor $statusColor -NoNewline
                Write-Host ' [' -ForegroundColor DarkGray -NoNewline
                Write-Host $healthGrade -ForegroundColor $gradeColor -NoNewline
                Write-Host ']' -ForegroundColor DarkGray -NoNewline
                if ($elapsedText)
                {
                    Write-Host "$elapsedText" -ForegroundColor DarkGray -NoNewline
                }
                Write-Host $clearTail -ForegroundColor $statusColor
                $linesPrintedLocal++

                if ($SummaryOnly)
                {
                    if ($null -ne $result.LatencyAvg)
                    {
                        Write-FramePrefix -FrameColor $statusColor -Text '  Summary: '
                        Write-Host 'avg ' -NoNewline -ForegroundColor Gray
                        $avgColor = if ($result.LatencyAvg -lt $t.Latency.Good) { 'Green' } elseif ($result.LatencyAvg -lt $t.Latency.Warning) { 'Yellow' } else { 'Red' }
                        Write-Host "$($result.LatencyAvg)ms" -NoNewline -ForegroundColor $avgColor
                        Write-Host ' | jitter ' -NoNewline -ForegroundColor Gray
                        $jitterColor = if ($result.Jitter -lt $t.Jitter.Good) { 'Green' } elseif ($result.Jitter -lt $t.Jitter.Warning) { 'Yellow' } else { 'Red' }
                        Write-Host "$($result.Jitter)ms" -NoNewline -ForegroundColor $jitterColor
                        Write-Host ' | loss ' -NoNewline -ForegroundColor Gray
                        $lossColor = if ($result.PacketLoss -eq $t.PacketLoss.Good) { 'Green' } elseif ($result.PacketLoss -lt $t.PacketLoss.Critical) { 'Yellow' } else { 'Red' }
                        Write-Host "$($result.PacketLoss)%" -NoNewline -ForegroundColor $lossColor
                        Write-Host ' | success ' -NoNewline -ForegroundColor Gray
                        $qualityColor = if ($successRate -ge 98) { 'Green' } elseif ($successRate -ge 90) { 'Yellow' } else { 'Red' }
                        Write-Host "$($result.SamplesSuccess)/$($result.SamplesTotal)" -NoNewline -ForegroundColor $qualityColor
                        if ($null -ne $result.DnsResolution)
                        {
                            Write-Host ' | dns ' -NoNewline -ForegroundColor Gray
                            $dnsColor = if ($result.DnsResolution -lt $t.Dns.Good) { 'Green' } elseif ($result.DnsResolution -lt $t.Dns.Critical) { 'Yellow' } else { 'Red' }
                            Write-Host "$($result.DnsResolution)ms" -NoNewline -ForegroundColor $dnsColor
                        }
                        if ($flags.Count -gt 0)
                        {
                            $flagPreview = ($flags | Select-Object -First 2 | ForEach-Object { $_.Text }) -join ', '
                            $flagColor = ($flags | Select-Object -First 1).Color
                            Write-Host ' | flags ' -NoNewline -ForegroundColor Gray
                            Write-Host $flagPreview -NoNewline -ForegroundColor $flagColor
                            if ($flags.Count -gt 2)
                            {
                                Write-Host " +$($flags.Count - 2)" -NoNewline -ForegroundColor DarkGray
                            }
                        }
                        Write-Host $clearTail
                    }
                    else
                    {
                        Write-FramePrefix -FrameColor $statusColor -Text '  '
                        Write-Host ("Summary: No successful connections$clearTail") -ForegroundColor Red
                    }
                    $linesPrintedLocal++
                    Write-Host (('└' + ('─' * 79) + $clearTail)) -ForegroundColor $statusColor
                    Write-Host
                    $linesPrintedLocal += 2
                    continue
                }

                # Latency visualization - show appropriate graph based on ShowGraph parameter
                if ($ShowGraph)
                {
                    # Show detailed TimeSeries graph only
                    if ($result.LatencyData.Count -gt 0)
                    {
                        Write-FramePrefix -FrameColor $statusColor
                        Write-Host ("$resetEsc$clearTail")
                        $graph = & $getCachedGraph $result.LatencyData 'TimeSeries' 70 8 $true $Style
                        $graphLineCount = 0

                        # Check if graph actually contains content
                        if ($graph -and $graph.Trim())
                        {
                            # Split and process each line of the graph output
                            $graphLines = $graph -split "`r?`n"
                            foreach ($line in $graphLines)
                            {
                                # Skip empty lines at the end
                                if ($line.Trim() -or $graphLineCount -eq 0)
                                {
                                    # Use Write-Host for better Unicode handling in modern terminals
                                    Write-FramePrefix -FrameColor $statusColor -Text '  '
                                    Write-Host ("$line$clearTail")
                                    $graphLineCount++
                                }
                            }
                        }
                        else
                        {
                            Write-FramePrefix -FrameColor $statusColor -Text '  '
                            Write-Host ("Graph data unavailable$clearTail") -ForegroundColor DarkGray
                            $graphLineCount = 1
                        }
                        $linesPrintedLocal += ($graphLineCount + 1)
                    }
                }
                else
                {
                    # Show sparkline and stats for compact view
                    $sparkline = & $getCachedGraph $result.LatencyData 'Sparkline' 0 0 $false
                    if ($null -ne $result.LatencyAvg)
                    {
                        Write-FramePrefix -FrameColor $statusColor -Text '  Latency: '
                        # Use default color to preserve ANSI codes in sparkline
                        Write-Host ("$resetEsc$sparkline$resetEsc$clearTail")
                        $linesPrintedLocal++
                    }
                    else
                    {
                        Write-FramePrefix -FrameColor $statusColor -Text '  Latency: '
                        Write-Host ("$resetEsc$sparkline$resetEsc$clearTail") -ForegroundColor Red
                        $linesPrintedLocal++
                    }

                    # Statistics with color coding using threshold constants
                    if ($null -ne $result.LatencyAvg)
                    {
                        Write-FramePrefix -FrameColor $statusColor -Text '  Stats  : '
                        Write-Host 'min: ' -NoNewline -ForegroundColor Gray
                        Write-Host "$($result.LatencyMin)ms" -NoNewline -ForegroundColor Cyan
                        Write-Host ' | max: ' -NoNewline -ForegroundColor Gray
                        Write-Host "$($result.LatencyMax)ms" -NoNewline -ForegroundColor Cyan
                        Write-Host ' | avg: ' -NoNewline -ForegroundColor Gray
                        $avgColor = if ($result.LatencyAvg -lt $t.Latency.Good) { 'Green' } elseif ($result.LatencyAvg -lt $t.Latency.Warning) { 'Yellow' } else { 'Red' }
                        Write-Host "$($result.LatencyAvg)ms" -NoNewline -ForegroundColor $avgColor
                        Write-Host ' | jitter: ' -NoNewline -ForegroundColor Gray
                        $jitterColor = if ($result.Jitter -lt $t.Jitter.Good) { 'Green' } elseif ($result.Jitter -lt $t.Jitter.Warning) { 'Yellow' } else { 'Red' }
                        Write-Host "$($result.Jitter)ms" -NoNewline -ForegroundColor $jitterColor
                        Write-Host ' | samples: ' -NoNewline -ForegroundColor Gray
                        Write-Host ("$($result.SamplesTotal)$clearTail") -ForegroundColor Cyan
                        $linesPrintedLocal++
                    }
                    else
                    {
                        Write-FramePrefix -FrameColor $statusColor -Text '  '
                        Write-Host ("Stats  : No successful connections$clearTail") -ForegroundColor Red
                        $linesPrintedLocal++
                    }
                }

                # Packet loss and success rate with color coding
                Write-FramePrefix -FrameColor $statusColor -Text '  Quality: '
                Write-Host "$($result.SamplesSuccess)/$($result.SamplesTotal)" -NoNewline -ForegroundColor Cyan
                $qualityColor = if ($successRate -ge 98) { 'Green' } elseif ($successRate -ge 90) { 'Yellow' } else { 'Red' }
                Write-Host ' successful (' -NoNewline
                Write-Host "$successRate%" -NoNewline -ForegroundColor $qualityColor
                Write-Host ') | Packet Loss: ' -NoNewline
                $lossColor = if ($result.PacketLoss -eq $t.PacketLoss.Good) { 'Green' } elseif ($result.PacketLoss -lt $t.PacketLoss.Critical) { 'Yellow' } else { 'Red' }
                Write-Host ("$($result.PacketLoss)%$clearTail") -ForegroundColor $lossColor
                $linesPrintedLocal++

                # Call out issues inline with quick flags
                Write-FramePrefix -FrameColor $statusColor -Text '  Findings: '
                if ($flags.Count -eq 0)
                {
                    Write-Host ("Healthy $($script:StatusIcons.Healthy)$clearTail") -ForegroundColor Green
                }
                else
                {
                    $flagIndex = 0
                    foreach ($flag in $flags)
                    {
                        if ($flagIndex -gt 0)
                        {
                            Write-Host ' | ' -NoNewline -ForegroundColor DarkGray
                        }
                        Write-Host $flag.Text -NoNewline -ForegroundColor $flag.Color
                        $flagIndex++
                    }
                    Write-Host $clearTail
                }
                $linesPrintedLocal++

                # DNS resolution time with color coding
                if ($null -ne $result.DnsResolution)
                {
                    Write-FramePrefix -FrameColor $statusColor -Text '  DNS    : '
                    $dnsColor = if ($result.DnsResolution -lt $t.Dns.Good) { 'Green' } elseif ($result.DnsResolution -lt $t.Dns.Critical) { 'Yellow' } else { 'Red' }
                    Write-Host "$($result.DnsResolution)ms" -NoNewline -ForegroundColor $dnsColor
                    Write-Host (" resolution time$clearTail")
                    $linesPrintedLocal++
                }

                # Reset the console color so following output doesn't inherit previous foreground settings
                try
                {
                    [Console]::ResetColor()
                }
                catch
                {
                    Write-Verbose "Failed to reset console color: $($_.Exception.Message)"
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
            # Determine effective render mode
            # Test if ANSI escape sequences are actually supported
            $ansiSupported = $false
            if ($PSVersionTable.PSVersion.Major -ge 6)
            {
                try
                {
                    # Test if we can actually use ANSI by checking console capabilities
                    # More robust ANSI detection - check multiple indicators
                    $hasTermVar = -not [String]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('TERM'))
                    $hasValidBufferSize = $Host.UI.RawUI.BufferSize.Width -gt 0
                    $isNotRedirected = [Console]::IsOutputRedirected -eq $false
                    $isInteractiveHost = $Host.Name -ne 'Default Host' -and $Host.UI.SupportsVirtualTerminal

                    $ansiSupported = $isNotRedirected -and ($hasTermVar -or $hasValidBufferSize -or $isInteractiveHost)
                }
                catch
                {
                    $ansiSupported = $false
                }
            }

            $effectiveRender = switch ($RenderMode)
            {
                'InPlace'
                {
                    if ($ansiSupported) { 'InPlace' } else { 'Clear' }  # Fall back to Clear if ANSI not supported
                }
                'Clear' { 'Clear' }
                'Stack' { 'Stack' }
                default
                {
                    # Auto mode: prefer InPlace if ANSI is supported, otherwise Clear (not Stack)
                    if ($ansiSupported) { 'InPlace' } else { 'Clear' }
                }
            }

            Write-Verbose "Render mode: $RenderMode -> $effectiveRender (ANSI: $ansiSupported)"

            # Collect metrics for all hosts FIRST, before any display changes
            $results = @()
            $useParallel = ($PSVersionTable.PSVersion.Major -ge 7 -and $allHosts.Count -gt 1)
            if ($useParallel)
            {
                Write-Verbose "Collecting metrics in parallel (ThrottleLimit=$ThrottleLimit)"
                $indexedHosts = for ($i = 0; $i -lt $allHosts.Count; $i++) { [PSCustomObject]@{ HostName = $allHosts[$i]; Index = $i } }

                # Use pipeline with proper completion waiting
                $parallelResults = @($indexedHosts | ForEach-Object -Parallel {
                        # Each parallel runspace starts clean; ensure the dependency is loaded locally using the captured path
                        if (-not (Get-Command -Name 'Get-NetworkMetrics' -ErrorAction SilentlyContinue) -and $using:MetricsPath)
                        {
                            try { . $using:MetricsPath } catch
                            {
                                throw "Failed to load required dependency 'Get-NetworkMetrics' from '$using:MetricsPath': $($_.Exception.Message)"
                            }
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
                    } -ThrottleLimit $ThrottleLimit)

                # Wait for all parallel jobs to complete and sort results by index to maintain host order
                $results = @($parallelResults | Sort-Object Index | ForEach-Object { $_.Metrics })

                # Ensure all parallel outputs are flushed
                [Console]::Out.Flush()
                [Console]::Error.Flush()
                Start-Sleep -Milliseconds 50
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

            # NOW that we have all the data, handle the display refresh
            if ($Continuous)
            {
                # For parallel execution, add extra synchronization to prevent mixed output
                if ($useParallel)
                {
                    # Allow any background output to complete
                    [Console]::Out.Flush()
                    [Console]::Error.Flush()
                    Start-Sleep -Milliseconds 200
                }

                if ($effectiveRender -eq 'Clear' -and $iteration -gt 1)
                {
                    Clear-Host
                }
                elseif ($effectiveRender -eq 'InPlace' -and $iteration -gt 1 -and $lastRenderLines -gt 0)
                {
                    # CRITICAL: Ensure all previous output is completely finished before cursor movement
                    [Console]::Out.Flush()
                    [Console]::Error.Flush()
                    Start-Sleep -Milliseconds 150  # Longer pause for parallel execution

                    # For in-place rendering, move cursor up and clear remainder of screen
                    # Use proper PowerShell escape character - no fallback to Clear-Host
                    $esc = [char]27
                    # Move up more lines than calculated to ensure we clear everything
                    $moveUpLines = [Math]::Max(20, $lastRenderLines + 5)  # More conservative for parallel
                    $upSequence = "$esc[{0}A" -f $moveUpLines  # Move cursor up
                    $clearSequence = "$esc[0J"                # Clear from cursor to end of screen
                    [Console]::Write($upSequence + $clearSequence)
                    [Console]::Out.Flush()  # Ensure cursor movement is applied immediately
                }

                # Print the header only on the first iteration to avoid repetitive noise
                if ($iteration -eq 1)
                {
                    Write-Host ('Network Diagnostic - Continuous Mode (Press Ctrl+C to stop)') -ForegroundColor DarkGray
                    Write-Host ("Interval: ${Interval}s | Samples per host: $Count | Port: $Port") -ForegroundColor Gray
                    Write-Host
                }

                # Show timestamp for each refresh cycle
                $timestamp = (Get-Date).ToString('HH:mm:ss')
                Write-Host "[$timestamp] " -ForegroundColor DarkGray -NoNewline
                Write-Host "Refresh #$iteration" -ForegroundColor Gray
                Write-Host
            }
            $linesPrinted = if ($Continuous) { 3 } else { 0 }

            # Ensure we have a non-null collection for formatting
            $results = @($results | Where-Object { $null -ne $_ })

            # Display formatted output and get accurate line count if needed
            $countOut = Format-DiagnosticOutput -Results $results -ReturnLineCount:$Continuous.IsPresent -InPlace:($Continuous.IsPresent -and $effectiveRender -eq 'InPlace') -SummaryOnly:$SummaryOnly.IsPresent

            # Ensure all output is flushed before proceeding to timing calculations
            if ($Continuous)
            {
                [Console]::Out.Flush()
                [Console]::Error.Flush()

                # For parallel execution, add extra stabilization time
                if ($useParallel)
                {
                    Start-Sleep -Milliseconds 100
                }
            }

            # Approximate lines printed per iteration for in-place refresh on Core and handle pacing
            if ($Continuous)
            {
                if ($null -ne $countOut) { $linesPrinted += [int]$countOut }

                # Set lastRenderLines BEFORE sleep so it's available for next iteration
                if ($effectiveRender -eq 'InPlace')
                {
                    $lastRenderLines = $linesPrinted
                }
                else
                {
                    $lastRenderLines = 0
                }

                # Final flush before sleep to ensure all output is complete
                [Console]::Out.Flush()
                [Console]::Error.Flush()
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
