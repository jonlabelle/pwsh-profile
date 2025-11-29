function Show-NetworkLatencyGraph
{
    <#
    .SYNOPSIS
        Displays ASCII graph visualizations of network latency data

    .DESCRIPTION
        Creates visual ASCII representations of latency measurements including sparklines,
        bar charts, and time-series graphs. Supports both inline sparklines and detailed
        multi-line graphs. Cross-platform compatible.

        PATTERN RECOGNITION:

        This function helps identify network performance patterns through visualization:

        1. SPARKLINE GRAPHS - Instant Visual Feedback
           Sparklines provide immediate insight into latency trends:
           - Flat line (▂▂▂▂▂): Stable, healthy connection suitable for all applications
           - Gradual climb (▁▂▃▅▆▇): Progressive degradation indicating congestion building
           - Sudden spikes (▂▂▇▂▂): Intermittent issues from routing flaps or packet bursts
           - Gaps with ✖ marks: Packet loss or timeouts requiring investigation
           - Highly variable (▁▇▂▇▃): High jitter unsuitable for VoIP/gaming applications

        2. TIME SERIES GRAPHS - Trend Analysis
           Time-series graphs reveal performance trends over longer periods:
           - Ascending trend: Network congestion increasing over time
           - Descending trend: Improvement (e.g., after route optimization)
           - Periodic pattern: Time-based issues (backup windows, scheduled tasks)
           - Stepped pattern: Route changes or failover events
           - Chaotic pattern: Unstable network path requiring investigation

        3. DISTRIBUTION GRAPHS - Consistency Analysis
           Distribution graphs identify latency consistency:
           - Single peak (normal distribution): Consistent, predictable latency
           - Bimodal distribution: Two routing paths or intermittent issues
           - Flat distribution: Highly unpredictable, problematic connection
           - Right-skewed: Occasional high latency outliers
           - Left-skewed: Baseline issues with occasional good performance

        INTERPRETING GRAPH PATTERNS:

        Healthy Network:
        ▂▂▂▂▂▃▂▂▂▂▂▂▃▂▂ (min: 12ms, max: 15ms, avg: 13ms, jitter: 1.2ms)
        - Tight range, low jitter, no gaps
        - Suitable for all applications including real-time

        Congested Network:
        ▁▂▃▅▆▇██▇▆▅▃▂▁ (min: 15ms, max: 95ms, avg: 55ms, jitter: 28ms)
        - Ascending then descending (congestion clearing)
        - High jitter, unsuitable for VoIP/gaming
        - Action: Investigate QoS, bandwidth utilization

        Packet Loss:
        ▂▂✖✖▂▂✖▂▂▂✖✖✖ (min: 12ms, max: 18ms, avg: 14ms, failed: 6)
        - Multiple ✖ marks indicating failures
        - Action: Check physical layer, firewall rules, routing

        Route Flapping:
        ▂▂▂████▂▂▂████▂▂▂ (min: 12ms, max: 120ms, avg: 45ms, jitter: 42ms)
        - Periodic spikes at regular intervals
        - Action: BGP route instability, check with ISP

        DNS Issues:
        First request: 250ms, subsequent: ▂▂▂▂▂ (avg: 13ms)
        - High initial latency, then normal
        - Action: DNS cache warming, check resolver performance

        See EXAMPLES for practical pattern interpretation workflows and usage scenarios.

        RELATED FUNCTIONS:
        This function is designed to work with:
        - Get-NetworkMetrics: Auto-loaded in continuous mode to collect latency samples
        - Invoke-NetworkDiagnostic: Calls Show-NetworkLatencyGraph to generate sparkline and time-series graphs

        Can also be used standalone with pre-collected latency data arrays.

        See NOTES for PowerShell 5.1 behavior in continuous mode.

    .PARAMETER Data
        Array of latency values in milliseconds. Supports $null values for failed requests.

    .PARAMETER GraphType
        Type of graph to display:
        - Sparkline: Inline bar chart using block characters
        - TimeSeries: Multi-line graph showing latency over time
        - Distribution: Histogram showing latency distribution

    .PARAMETER Style
        Visualization style for TimeSeries graphs:
        - Dots: Clean dot plot showing only data points (default, easiest to read)
        - Bars: Vertical bars from baseline showing magnitude
        - Line: Simple line connections between points

    .PARAMETER Width
        Width of the graph in characters (for TimeSeries and Distribution types)

    .PARAMETER Height
        Height of the graph in characters (for TimeSeries type)

    .PARAMETER ShowStats
        Include statistics (min/max/avg) in the output

    .PARAMETER NoColor
        Disable ANSI color codes in output (plain text only)

    .PARAMETER Continuous
        Run continuously until stopped with Ctrl+C, collecting new data samples

        Continuous mode notes:
        - Use -Continuous with -HostName to refresh graph periodically until Ctrl+C
        - Set -Interval to control seconds between refreshes (default: 5)
        - For testing/CI: hidden -MaxIterations parameter limits iterations (0 = infinite)
          Example: -Continuous -MaxIterations 1 runs one iteration and exits

    .PARAMETER Interval
        Interval in seconds between continuous updates (default: 5)

    .PARAMETER HostName
        Target hostname or IP address (required for continuous mode)

    .PARAMETER Count
        Number of samples to collect per cycle in continuous mode (default: 20)

    .PARAMETER Port
        TCP port to test in continuous mode (default: 443)

    .PARAMETER SampleDelayMilliseconds
        Delay between samples in continuous mode (default: 100). Set to 0 for back-to-back samples.

    .PARAMETER RenderMode
        Controls how the output refreshes during continuous runs.

        Valid values:
        - Auto   : PowerShell 5.1 uses Clear (screen wipe), PowerShell 6+ uses InPlace (default)
        - InPlace: Update the same block using ANSI cursor moves (Core only; falls back to Clear on 5.1)
        - Clear  : Clear the screen between iterations
        - Stack  : Append output without clearing (useful for logs/debugging)

    .EXAMPLE
        PS > $latencies = @(15, 14, 16, 22, 15, 14, 13, 16)
        PS > Show-NetworkLatencyGraph -Data $latencies -GraphType Sparkline

        ▂▁▂▅▂▁▁▂

    .EXAMPLE
        PS > $latencies = @(15, 14, 16, 22, 15, 14, 13, 16)
        PS > Show-NetworkLatencyGraph -Data $latencies -GraphType TimeSeries -Width 40 -Height 10

        Displays a detailed time-series graph of latency over time

    .EXAMPLE
        PS > $latencies = @(15, 14, 16, 22, 15, 14, 13, 16)
        PS > Show-NetworkLatencyGraph -Data $latencies -GraphType Sparkline -ShowStats

        ▂▁▂▅▂▁▁▂ (min: 13ms, max: 22ms, avg: 15.6ms)

    .EXAMPLE
        PS > $metrics = Get-NetworkMetrics -HostName 'google.com' -Count 30
        PS > Show-NetworkLatencyGraph -Data $metrics.LatencyData -GraphType TimeSeries -ShowStats

        Collect metrics and display as a time-series graph with statistics

    .EXAMPLE
        PS > $latencies = @(12, 15, 13, 45, 14, 16, 13, 12, 50, 14)
        PS > Show-NetworkLatencyGraph -Data $latencies -GraphType Distribution -Width 60

        Display latency distribution histogram to identify patterns and outliers

    .EXAMPLE
        PS > $data = 1..50 | ForEach-Object { Get-Random -Minimum 10 -Maximum 100 }
        PS > Show-NetworkLatencyGraph -Data $data -GraphType TimeSeries -Width 80 -Height 15

        Generate random latency data and display in a large detailed graph

    .EXAMPLE
        PS > $latencies = @(45, 50, 48, 52, 49, 51, 47, 53)
        PS > Show-NetworkLatencyGraph -Data $latencies -GraphType TimeSeries -Style Dots

        Display time-series with clean dot plot (default style, easiest to read)

    .EXAMPLE
        PS > $latencies = @(45, 50, 48, 52, 49, 51, 47, 53)
        PS > Show-NetworkLatencyGraph -Data $latencies -GraphType TimeSeries -Style Bars

        Display time-series with vertical bars showing magnitude from baseline

    .EXAMPLE
        PS > $latencies = @(45, 50, 48, 52, 49, 51, 47, 53)
        PS > Show-NetworkLatencyGraph -Data $latencies -GraphType TimeSeries -Style Line

        Display time-series with simple line connections between data points

    .EXAMPLE
        PS > $metrics = Get-NetworkMetrics -HostName 'cloudflare.com' -Count 40
        PS > Show-NetworkLatencyGraph -Data $metrics.LatencyData -GraphType Distribution

        Show distribution of latency values to analyze consistency

    .EXAMPLE
        PS > $latencies = @(20, 22, $null, 21, $null, 23, 20, 21)
        PS > Show-NetworkLatencyGraph -Data $latencies -GraphType Sparkline -ShowStats
             ▁▅✖▂✖█▁▂ (min: 20ms, max: 23ms, avg: 21.2ms, failed: 2)

        Displays graph with failed requests marked as ✖

    .EXAMPLE
        PS > Get-NetworkMetrics -HostName 'github.com' -Count 25 |
             ForEach-Object { Show-NetworkLatencyGraph -Data $_.LatencyData -GraphType Sparkline -ShowStats }

        Pipe metrics directly to graph for quick visualization

    .EXAMPLE
        PS > $latencies = @(45, 46, 47, 48, 47, 46, 45, 46)
        PS > Show-NetworkLatencyGraph -Data $latencies -GraphType Sparkline

        ▁▃▅▇▅▃▁▃
        Visualize small variations in relatively consistent latency

    .EXAMPLE
        PS > $results = @()
        PS > 1..5 | ForEach-Object {
                 $m = Get-NetworkMetrics -HostName 'api.example.com' -Count 20
                 $results += $m.LatencyData
             }
        PS > Show-NetworkLatencyGraph -Data $results -GraphType TimeSeries -Width 100 -Height 12

        Collect multiple metric sets over time and display combined time-series graph

    .EXAMPLE
        PS > Show-NetworkLatencyGraph -HostName 'google.com' -GraphType TimeSeries -Continuous -Interval 3

        Continuously monitor google.com with animated time-series graph, updating every 3 seconds

    .EXAMPLE
        PS > Show-NetworkLatencyGraph -HostName 'cloudflare.com' -GraphType Sparkline -Continuous -ShowStats

        Continuously monitor with sparkline graph and statistics (default 5-second interval)

    .EXAMPLE
        PS > Show-NetworkLatencyGraph -HostName 'cloudflare.com' -GraphType TimeSeries -Continuous -Interval 2 -RenderMode InPlace

        PowerShell Core: refreshes the same output block in place (no stacking)

    .EXAMPLE
        PS > Show-NetworkLatencyGraph -HostName 'cloudflare.com' -GraphType Sparkline -Continuous -Interval 2 -RenderMode Stack -MaxIterations 1

        Append a single iteration for testing/logging; no clear or in-place refresh

    .EXAMPLE
        PS > Show-NetworkLatencyGraph -HostName 'cloudflare.com' -GraphType Sparkline -Continuous -MaxIterations 1

        Run one continuous iteration for testing/CI (hidden parameter)

    .EXAMPLE
        PS > Show-NetworkLatencyGraph -HostName 'google.com' -GraphType Sparkline -Continuous -Count 10 -SampleDelayMilliseconds 10

        Faster sampling cadence by reducing the delay between samples in continuous mode

    .EXAMPLE
        PS > $latencies = @(20, $null, 30, 28, $null, 35, 32)
        PS > Show-NetworkLatencyGraph -Data $latencies -GraphType TimeSeries -Width 30 -Height 8

        Displays a time-series graph that preserves failed samples as ✖ gaps instead of collapsing the timeline

    .EXAMPLE
        PS > # PATTERN: Healthy network
        PS > # ▂▂▂▂▂▃▂▂▂▂▂▂▃▂▂ (min: 12ms, max: 15ms, avg: 13ms, jitter: 1.2ms)
        PS > # Interpretation: Tight range, low jitter, no gaps - suitable for all applications

        Flat sparkline pattern indicates stable, healthy connection suitable for real-time
        applications including VoIP and gaming.

    .EXAMPLE
        PS > # PATTERN: Congested network
        PS > # ▁▂▃▅▆▇██▇▆▅▃▂▁ (min: 15ms, max: 95ms, avg: 55ms, jitter: 28ms)
        PS > # Interpretation: Ascending then descending (congestion clearing)
        PS > # Action: Investigate QoS, bandwidth utilization

        Gradual climb pattern shows progressive degradation. High jitter makes connection
        unsuitable for VoIP/gaming. Indicates network congestion building then clearing.

    .EXAMPLE
        PS > # PATTERN: Packet loss
        PS > # ▂▂✖✖▂▂✖▂▂▂✖✖✖ (min: 12ms, max: 18ms, avg: 14ms, failed: 6)
        PS > # Interpretation: Multiple ✖ marks indicating failures
        PS > # Action: Check physical layer, firewall rules, routing

        Multiple ✖ marks indicate packet loss or timeouts. Check physical connections,
        firewall rules, and routing configuration.

    .EXAMPLE
        PS > # PATTERN: Route flapping
        PS > # ▂▂▂████▂▂▂████▂▂▂ (min: 12ms, max: 120ms, avg: 45ms, jitter: 42ms)
        PS > # Interpretation: Periodic spikes at regular intervals
        PS > # Action: BGP route instability, check with ISP

        Periodic spike pattern suggests route flapping or BGP instability.
        Contact ISP to investigate routing issues.

    .EXAMPLE
        PS > # PATTERN: DNS cache issue
        PS > # First request: 250ms, subsequent: ▂▂▂▂▂ (avg: 13ms)
        PS > # Interpretation: High initial latency, then normal
        PS > # Action: DNS cache warming, check resolver performance

        High initial latency followed by normal performance indicates DNS caching behavior.
        Consider DNS resolver performance or cache warming strategies.

    .EXAMPLE
        PS > # WORKFLOW: Quick visual triage
        PS > $metrics = Get-NetworkMetrics -HostName 'slow-api.example.com' -Count 50
        PS > Show-NetworkLatencyGraph -Data $metrics.LatencyData -GraphType Sparkline -ShowStats
        PS > # If pattern looks concerning, get detailed view
        PS > Show-NetworkLatencyGraph -Data $metrics.LatencyData -GraphType TimeSeries -Width 80 -Height 15 -ShowStats
        PS > # Check distribution for consistency
        PS > Show-NetworkLatencyGraph -Data $metrics.LatencyData -GraphType Distribution

        Progressive visualization workflow. Start with sparkline for quick assessment,
        expand to time-series for detail, check distribution for consistency.

    .EXAMPLE
        PS > # WORKFLOW: Comparing network paths
        PS > $primary = Get-NetworkMetrics -HostName 'primary.example.com' -Count 100
        PS > $backup = Get-NetworkMetrics -HostName 'backup.example.com' -Count 100
        PS > Write-Host "Primary: " -NoNewline
        PS > Show-NetworkLatencyGraph -Data $primary.LatencyData -GraphType Sparkline -ShowStats
        PS > Write-Host "Backup:  " -NoNewline
        PS > Show-NetworkLatencyGraph -Data $backup.LatencyData -GraphType Sparkline -ShowStats
        PS > Show-NetworkLatencyGraph -Data $primary.LatencyData -GraphType TimeSeries -ShowStats

        Side-by-side comparison of multiple network paths. Visual patterns quickly reveal
        performance differences for path selection decisions.

    .EXAMPLE
        PS > # WORKFLOW: Real-time performance monitoring
        PS > Show-NetworkLatencyGraph -HostName 'critical-service.com' -GraphType TimeSeries -Continuous -Interval 5
        PS > # Watch for pattern changes during maintenance
        PS > # When issue detected, switch to detailed diagnostic:
        PS > Invoke-NetworkDiagnostic -HostName 'critical-service.com' -ShowGraph -Count 200

        Live monitoring with auto-refresh. Graph updates every 5 seconds showing current
        state. Catch the exact moment when performance degrades.

    .EXAMPLE
        PS > # WORKFLOW: Historical pattern analysis
        PS > $morning = Get-NetworkMetrics -HostName 'database.local' -Port 5432 -Count 200
        PS > # ... collect at different times of day ...
        PS > $evening = Get-NetworkMetrics -HostName 'database.local' -Port 5432 -Count 200
        PS > Show-NetworkLatencyGraph -Data $morning.LatencyData -GraphType Distribution
        PS > Show-NetworkLatencyGraph -Data $evening.LatencyData -GraphType Distribution

        Compare distribution patterns across time periods. Identify time-based performance
        patterns like backup windows or usage peaks.

    .EXAMPLE
        PS > # WORKFLOW: Validating network configuration changes
        PS > $before = Get-NetworkMetrics -HostName 'endpoint.com' -Count 100
        PS > Show-NetworkLatencyGraph -Data $before.LatencyData -GraphType Sparkline -ShowStats
        PS > # Apply network configuration change (QoS, routing, etc.)
        PS > $after = Get-NetworkMetrics -HostName 'endpoint.com' -Count 100
        PS > Show-NetworkLatencyGraph -Data $after.LatencyData -GraphType Sparkline -ShowStats
        PS > Show-NetworkLatencyGraph -Data $before.LatencyData -GraphType Distribution -Width 60
        PS > Show-NetworkLatencyGraph -Data $after.LatencyData -GraphType Distribution -Width 60

        Baseline before/after comparison for configuration changes. Quantify improvement
        or degradation from QoS, routing, or other network modifications.

    .OUTPUTS
        System.String (static mode)
        None (continuous mode; writes directly to host)

    .NOTES
        POWERSHELL 5.1 BEHAVIOR:
        - PowerShell Desktop 5.1 does not support ANSI cursor control for in-place updates
        - Console is cleared between iterations using Clear-Host in continuous mode
        - ANSI colors are automatically disabled on 5.1 to prevent escape codes in output
        - PowerShell Core (6+) supports ANSI colors and uses ANSI cursor movement for in-place updates

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Show-NetworkLatencyGraph.ps1
    #>
    [CmdletBinding()]
    [OutputType([String], ParameterSetName = 'Data')]
    [OutputType([void], ParameterSetName = 'Continuous')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Data')]
        [AllowNull()]
        [Object[]]$Data,

        [Parameter(Mandatory, ParameterSetName = 'Continuous')]
        [ValidateNotNullOrEmpty()]
        [String]$HostName,

        [Parameter()]
        [ValidateSet('Sparkline', 'TimeSeries', 'Distribution')]
        [String]$GraphType = 'Sparkline',

        [Parameter()]
        [ValidateSet('Dots', 'Bars', 'Line')]
        [String]$Style = 'Dots',

        [Parameter()]
        [ValidateRange(20, 200)]
        [Int32]$Width = 60,

        [Parameter()]
        [ValidateRange(5, 50)]
        [Int32]$Height = 10,

        [Parameter()]
        [Switch]$ShowStats,

        [Parameter()]
        [Switch]$NoColor,

        [Parameter(ParameterSetName = 'Continuous')]
        [Switch]$Continuous,

        [Parameter(ParameterSetName = 'Continuous')]
        [ValidateRange(1, 3600)]
        [Int32]$Interval = 5,

        [Parameter(ParameterSetName = 'Continuous')]
        [ValidateRange(5, 1000)]
        [Int32]$Count = 20,

        [Parameter(ParameterSetName = 'Continuous')]
        [ValidateRange(1, 65535)]
        [Int32]$Port = 443,

        [Parameter(ParameterSetName = 'Continuous')]
        [ValidateRange(0, 5000)]
        [Int32]$SampleDelayMilliseconds = 100,

        # Hidden/testing-only: limit iterations for continuous mode (0 = infinite)
        [Parameter(ParameterSetName = 'Continuous')]
        [Int32]$MaxIterations = 0,

        [Parameter()]
        [ValidateSet('Auto', 'InPlace', 'Clear', 'Stack')]
        [String]$RenderMode = 'Auto'
    )

    begin
    {
        Write-Verbose "Creating $GraphType graph"
        $jitter = $null

        # ANSI color palette (respects -NoColor and OutputRendering=PlainText)
        $supportsColor = -not $NoColor.IsPresent
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $supportsColor = $false
        }
        elseif ($supportsColor -and $PSStyle -and $PSStyle.OutputRendering -eq 'PlainText')
        {
            $supportsColor = $false
        }

        $script:Palette = [PSCustomObject]@{
            Reset = if ($supportsColor) { "`e[0m" } else { '' }
            Green = if ($supportsColor) { "`e[32m" } else { '' }
            Yellow = if ($supportsColor) { "`e[33m" } else { '' }
            Red = if ($supportsColor) { "`e[31m" } else { '' }
            Cyan = if ($supportsColor) { "`e[36m" } else { '' }
            Gray = if ($supportsColor) { "`e[90m" } else { '' }
        }

        function script:Get-LatencyColor
        {
            param([double]$Value)
            if ($Value -lt 50) { return $script:Palette.Green }
            if ($Value -lt 100) { return $script:Palette.Yellow }
            return $script:Palette.Red
        }

        function script:Get-JitterColor
        {
            param([double]$Value)
            if ($Value -lt 10) { return $script:Palette.Green }
            if ($Value -lt 30) { return $script:Palette.Yellow }
            return $script:Palette.Red
        }

        function script:Calculate-Jitter
        {
            param([Object[]]$Values)
            if (-not $Values -or $Values.Count -eq 0) { return $null }
            if ($Values.Count -eq 1) { return 0 }

            $numeric = @()
            foreach ($v in $Values)
            {
                if ($null -ne $v)
                {
                    $numeric += [double]$v
                }
            }

            if ($numeric.Count -eq 0) { return $null }
            if ($numeric.Count -eq 1) { return 0 }

            $avg = ($numeric | Measure-Object -Average).Average
            $sumSq = 0.0
            foreach ($v in $numeric)
            {
                $diff = $v - $avg
                $sumSq += ($diff * $diff)
            }

            $variance = $sumSq / $numeric.Count
            return [Math]::Sqrt([Math]::Max(0, $variance))
        }

        # Block characters for sparklines (8 levels)
        $script:SparkChars = @([char]0x2581, [char]0x2582, [char]0x2583, [char]0x2584, [char]0x2585, [char]0x2586, [char]0x2587, [char]0x2588)

        function script:Build-TimeSeriesGraph
        {
            param(
                [Parameter(Mandatory)][Object[]]$Data,
                [Parameter(Mandatory)][double]$Min,
                [Parameter(Mandatory)][double]$Max,
                [Parameter(Mandatory)][int]$Width,
                [Parameter(Mandatory)][int]$Height,
                [Parameter(Mandatory)][bool]$ShowStats,
                [Parameter(Mandatory)][double]$Avg,
                [Parameter(Mandatory)][string]$Style,
                [Parameter()][Nullable[Double]]$Jitter
            )

            $range = if ($Max -eq $Min) { 1 } else { $Max - $Min }
            $scaleDenominator = [Math]::Max(1, $Height - 1)
            $pointsToPlot = [Math]::Min($Width, $Data.Count)

            # Pre-calculate scaled positions for all data points
            $scaledPoints = @()
            $rawValues = @()
            for ($col = 0; $col -lt $pointsToPlot; $col++)
            {
                $dataIndex = [Math]::Floor($col * $Data.Count / $pointsToPlot)
                $value = $Data[$dataIndex]

                if ($null -eq $value)
                {
                    $scaledPoints += $null
                    $rawValues += $null
                }
                else
                {
                    # Scale value to graph height (inverted: higher values = lower row numbers)
                    $normalized = ($value - $Min) / $range
                    $scaledRow = [Math]::Round(($Height - 1) - ($normalized * $scaleDenominator), 0)
                    $scaledRow = [Math]::Max(0, [Math]::Min($Height - 1, $scaledRow))
                    $scaledPoints += $scaledRow
                    $rawValues += [double]$value
                }
            }

            $output = New-Object System.Text.StringBuilder

            # Build each row of the graph based on style
            for ($row = 0; $row -lt $Height; $row++)
            {
                # Calculate the latency value this row represents
                $levelValue = $Min + (($Height - 1 - $row) / $scaleDenominator) * $range
                [void]$output.Append([Math]::Round($levelValue, 0).ToString().PadLeft(5))
                [void]$output.Append(' |')

                # Draw based on selected style
                for ($col = 0; $col -lt $pointsToPlot; $col++)
                {
                    $scaledRow = $scaledPoints[$col]

                    if ($null -eq $scaledRow)
                    {
                        # Failed connection
                        $failMark = "${script:Palette.Red}✖${script:Palette.Reset}"
                        [void]$output.Append($failMark)
                        continue
                    }

                    $pointColor = if ($rawValues[$col] -ne $null) { script:Get-LatencyColor -Value $rawValues[$col] } else { '' }
                    switch ($Style)
                    {
                        'Dots'
                        {
                            if ($scaledRow -eq $row)
                            {
                                [void]$output.Append("$pointColor●${script:Palette.Reset}")
                            }
                            else
                            {
                                [void]$output.Append(' ')
                            }
                        }
                        'Bars'
                        {
                            # Vertical bar from bottom up to the data point
                            $shouldFill = ($Height - 1 - $row) -le ($Height - 1 - $scaledRow)
                            if ($shouldFill)
                            {
                                [void]$output.Append("$pointColor█${script:Palette.Reset}")
                            }
                            else
                            {
                                [void]$output.Append(' ')
                            }
                        }
                        'Line'
                        {
                            # Simple line connecting points
                            if ($scaledRow -eq $row)
                            {
                                [void]$output.Append("$pointColor●${script:Palette.Reset}")
                            }
                            elseif ($col -gt 0 -and $null -ne $scaledPoints[$col - 1])
                            {
                                # Check if line passes through this row between previous and current point
                                $prevRow = $scaledPoints[$col - 1]
                                $currRow = $scaledRow
                                $prevValue = $rawValues[$col - 1]
                                $currValue = $rawValues[$col]
                                $connectorValue = if ($null -ne $prevValue -and $null -ne $currValue) { [Math]::Max($prevValue, $currValue) } else { $currValue }
                                $connectorColor = if ($null -ne $connectorValue) { script:Get-LatencyColor -Value $connectorValue } else { '' }

                                if (($prevRow -lt $row -and $currRow -gt $row) -or ($prevRow -gt $row -and $currRow -lt $row))
                                {
                                    [void]$output.Append("$connectorColor│${script:Palette.Reset}")
                                }
                                else
                                {
                                    [void]$output.Append(' ')
                                }
                            }
                            else
                            {
                                [void]$output.Append(' ')
                            }
                        }
                    }
                }

                [void]$output.AppendLine()
            }

            [void]$output.Append('     +')
            [void]$output.AppendLine('-' * $pointsToPlot)

            if ($ShowStats)
            {
                $avgColor = if ($Avg -lt 50) { $script:Palette.Green } elseif ($Avg -lt 100) { $script:Palette.Yellow } else { $script:Palette.Red }
                # Count valid vs failed samples to avoid duplicate or confusing sample display
                $validCount = @($Data | Where-Object { $null -ne $_ }).Count
                $failedCount = @($Data | Where-Object { $null -eq $_ }).Count
                $statsLine = "     ${script:Palette.Gray}Min: ${script:Palette.Cyan}$([Math]::Round($Min, 1))ms ${script:Palette.Gray}| Max: ${script:Palette.Cyan}$([Math]::Round($Max, 1))ms ${script:Palette.Gray}| Avg: $avgColor$([Math]::Round($Avg, 1))ms"
                if ($null -ne $Jitter)
                {
                    $jitterColor = script:Get-JitterColor -Value $Jitter
                    $statsLine += " ${script:Palette.Gray}| Jitter: $jitterColor$([Math]::Round($Jitter, 1))ms"
                }
                $statsLine += " ${script:Palette.Gray}| Samples: ${script:Palette.Cyan}$validCount${script:Palette.Reset}"
                if ($failedCount -gt 0) { $statsLine += " ${script:Palette.Gray}| Failed: ${script:Palette.Red}$failedCount${script:Palette.Reset}" }
                [void]$output.AppendLine($statsLine)
            }

            return $output.ToString()
        }        # Load Get-NetworkMetrics if in continuous mode
        if ($Continuous)
        {
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
        }

        # If we have data directly, process it
        if ($PSCmdlet.ParameterSetName -eq 'Data')
        {
            # Filter out null values but track them
            $validData = @($Data | Where-Object { $null -ne $_ })
            $failedCount = @($Data | Where-Object { $null -eq $_ }).Count

            if ($validData.Count -eq 0)
            {
                Write-Warning 'No valid data points to graph'
                return '(no data)'
            }

            # Calculate statistics
            $min = ($validData | Measure-Object -Minimum).Minimum
            $max = ($validData | Measure-Object -Maximum).Maximum
            $avg = ($validData | Measure-Object -Average).Average
            $jitter = script:Calculate-Jitter -Values $validData

            Write-Verbose "Data range: min=$min, max=$max, avg=$([Math]::Round($avg, 2))"
        }
    }

    process
    {
        # Continuous mode
        if ($Continuous)
        {
            $iteration = 0
            do
            {
                $iteration++

                $effectiveRender = switch ($RenderMode)
                {
                    'InPlace' { if ($PSVersionTable.PSVersion.Major -lt 6) { 'Clear' } else { 'InPlace' } }
                    'Clear' { 'Clear' }
                    'Stack' { 'Stack' }
                    default { if ($PSVersionTable.PSVersion.Major -lt 6) { 'Clear' } else { 'InPlace' } }
                }

                if ($effectiveRender -eq 'Clear' -and ($iteration -gt 1 -or $MaxIterations -eq 0))
                {
                    Clear-Host
                }
                elseif ($effectiveRender -eq 'InPlace' -and $iteration -eq 1)
                {
                    # On first iteration in InPlace mode, save cursor position for restoration
                    # This marks the start of our output block
                    [Console]::Write("`e7")  # Save cursor position
                }
                elseif ($effectiveRender -eq 'InPlace' -and $iteration -gt 1)
                {
                    # Restore cursor to the saved position (start of output block)
                    [Console]::Write("`e8")  # Restore cursor position
                }

                $clearTail = if ($effectiveRender -eq 'InPlace') { "`e[K" } else { '' }
                Write-Host "${script:Palette.Cyan}Network Latency Graph - Iteration $iteration (Press Ctrl+C to stop)${script:Palette.Reset}$clearTail"
                Write-Host "${script:Palette.Gray}Host: $HostName | Interval: ${Interval}s | Samples: $Count | Port: $Port${script:Palette.Reset}$clearTail"
                Write-Host "$clearTail"

                # Collect metrics
                $metrics = Get-NetworkMetrics -HostName $HostName -Count $Count -Port $Port -SampleDelayMilliseconds $SampleDelayMilliseconds
                $Data = $metrics.LatencyData

                # Filter and calculate for this iteration
                $validData = @($Data | Where-Object { $null -ne $_ })
                $failedCount = @($Data | Where-Object { $null -eq $_ }).Count

                if ($validData.Count -gt 0)
                {
                    $min = ($validData | Measure-Object -Minimum).Minimum
                    $max = ($validData | Measure-Object -Maximum).Maximum
                    $avg = ($validData | Measure-Object -Average).Average
                    $jitter = script:Calculate-Jitter -Values $validData

                    # Generate and display graph
                    $graphOutput = switch ($GraphType)
                    {
                        'Sparkline'
                        {
                            $sparkline = New-Object System.Text.StringBuilder
                            foreach ($value in $Data)
                            {
                                if ($null -eq $value)
                                {
                                    [void]$sparkline.Append("${script:Palette.Red}✖${script:Palette.Reset}")
                                }
                                else
                                {
                                    if ($max -eq $min) { $index = 3 }
                                    else
                                    {
                                        $normalized = ($value - $min) / ($max - $min)
                                        $index = [Math]::Floor($normalized * 8)
                                        $index = [Math]::Min(7, [Math]::Max(0, $index))
                                    }
                                    $color = script:Get-LatencyColor -Value $value
                                    [void]$sparkline.Append("$color$($script:SparkChars[$index])${script:Palette.Reset}")
                                }
                            }
                            $result = $sparkline.ToString()
                            if ($ShowStats)
                            {
                                $statsText = " ${script:Palette.Gray}(min: ${script:Palette.Cyan}$([Math]::Round($min, 1))ms${script:Palette.Gray}, max: ${script:Palette.Cyan}$([Math]::Round($max, 1))ms${script:Palette.Gray}, avg: "
                                $avgColor = if ($avg -lt 50) { $script:Palette.Green } elseif ($avg -lt 100) { $script:Palette.Yellow } else { $script:Palette.Red }
                                $statsText += "$avgColor$([Math]::Round($avg, 1))ms${script:Palette.Gray}"
                                if ($null -ne $jitter) { $statsText += ", jitter: $(script:Get-JitterColor -Value $jitter)$([Math]::Round($jitter, 1))ms${script:Palette.Gray}" }
                                if ($failedCount -gt 0) { $statsText += ", failed: ${script:Palette.Red}$failedCount${script:Palette.Gray}" }
                                $statsText += ")${script:Palette.Reset}"
                                $result += $statsText
                            }
                            $result
                        }
                        'TimeSeries'
                        {
                            script:Build-TimeSeriesGraph -Data $Data -Min $min -Max $max -Width $Width -Height $Height -ShowStats $ShowStats -Avg $avg -Style $Style -Jitter $jitter
                        }
                        'Distribution'
                        {
                            $output = New-Object System.Text.StringBuilder
                            $numBuckets = 10
                            $bucketSize = if (($max - $min) -eq 0) { 1 } else { ($max - $min) / $numBuckets }
                            $buckets = @{}
                            0..($numBuckets - 1) | ForEach-Object { $buckets[$_] = 0 }
                            foreach ($value in $validData)
                            {
                                $bucketIndex = [Math]::Floor(($value - $min) / $bucketSize)
                                $bucketIndex = [Math]::Min($numBuckets - 1, [Math]::Max(0, $bucketIndex))
                                $buckets[$bucketIndex]++
                            }
                            $maxCount = if (($buckets.Values | Measure-Object -Maximum).Maximum -eq 0) { 1 } else { ($buckets.Values | Measure-Object -Maximum).Maximum }
                            $clearTail = if ($effectiveRender -eq 'InPlace') { "`e[K" } else { '' }
                            [void]$output.AppendLine("${script:Palette.Cyan}Latency Distribution:${script:Palette.Reset}$clearTail")
                            for ($i = 0; $i -lt $numBuckets; $i++)
                            {
                                $rangeStart = [Math]::Round($min + ($i * $bucketSize), 1)
                                $rangeEnd = [Math]::Round($min + (($i + 1) * $bucketSize), 1)
                                $itemCount = $buckets[$i]
                                $barWidth = [Int32][Math]::Floor(($itemCount / $maxCount) * ($Width - 20))
                                $midpoint = ($rangeStart + $rangeEnd) / 2
                                $barColor = if ($midpoint -lt 50) { $script:Palette.Green } elseif ($midpoint -lt 100) { $script:Palette.Yellow } else { $script:Palette.Red }
                                $label = "$rangeStart-$rangeEnd ms".PadRight(15)
                                $bar = $barColor + ([char]0x2588).ToString() * $barWidth + $script:Palette.Reset
                                $percentage = [Math]::Round(($itemCount / $validData.Count) * 100, 1)
                                [void]$output.AppendLine("${script:Palette.Gray}$label${script:Palette.Reset} $bar ${script:Palette.Cyan}$itemCount${script:Palette.Reset} ${script:Palette.Gray}($percentage%)${script:Palette.Reset}$clearTail")
                            }
                            $output.ToString()
                        }
                    }

                    Write-Host $graphOutput
                }
                else
                {
                    Write-Host "${script:Palette.Red}No successful connections${script:Palette.Reset}"
                }

                Write-Host
                # Packet loss and jitter with dynamic color coding (green=good, yellow=medium, red=bad)
                $lossColor = if ($metrics.PacketLoss -eq 0) { $script:Palette.Green } elseif ($metrics.PacketLoss -lt 5) { $script:Palette.Yellow } else { $script:Palette.Red }
                $jitterColor = if ($metrics.Jitter -lt 10) { $script:Palette.Green } elseif ($metrics.Jitter -lt 30) { $script:Palette.Yellow } else { $script:Palette.Red }
                $clearTail = if ($effectiveRender -eq 'InPlace') { "`e[K" } else { '' }
                Write-Host "${script:Palette.Gray}Packet Loss: $lossColor$($metrics.PacketLoss)%${script:Palette.Gray} | Jitter: $jitterColor$($metrics.Jitter)ms${script:Palette.Reset}$clearTail" -NoNewline
                Write-Host  # Move to next line after stats
                Start-Sleep -Seconds $Interval

            } while ($MaxIterations -eq 0 -or $iteration -lt $MaxIterations)
            return
        }

        # Static mode (original behavior)
        switch ($GraphType)
        {
            'Sparkline'
            {
                $sparkline = New-Object System.Text.StringBuilder

                foreach ($value in $Data)
                {
                    if ($null -eq $value)
                    {
                        [void]$sparkline.Append("${script:Palette.Red}✖${script:Palette.Reset}")
                    }
                    else
                    {
                        # Normalize value to 0-7 range (8 characters in SparkChars array)
                        if ($max -eq $min)
                        {
                            $index = 3
                        }
                        else
                        {
                            $normalized = ($value - $min) / ($max - $min)
                            $index = [Math]::Floor($normalized * 8)
                            $index = [Math]::Min(7, [Math]::Max(0, $index))
                        }
                        $color = script:Get-LatencyColor -Value $value
                        [void]$sparkline.Append("$color$($script:SparkChars[$index])${script:Palette.Reset}")
                    }
                }

                $result = $sparkline.ToString()

                if ($ShowStats)
                {
                    $statsText = " ${script:Palette.Gray}(min: ${script:Palette.Cyan}$([Math]::Round($min, 1))ms${script:Palette.Gray}, max: ${script:Palette.Cyan}$([Math]::Round($max, 1))ms${script:Palette.Gray}, avg: "

                    # Color avg based on value
                    $avgColor = if ($avg -lt 50) { $script:Palette.Green } elseif ($avg -lt 100) { $script:Palette.Yellow } else { $script:Palette.Red }
                    $statsText += "$avgColor$([Math]::Round($avg, 1))ms${script:Palette.Gray}"
                    if ($null -ne $jitter)
                    {
                        $statsText += ", jitter: $(script:Get-JitterColor -Value $jitter)$([Math]::Round($jitter, 1))ms${script:Palette.Gray}"
                    }

                    if ($failedCount -gt 0)
                    {
                        $statsText += ", failed: ${script:Palette.Red}$failedCount${script:Palette.Gray}"
                    }
                    $statsText += ")${script:Palette.Reset}"
                    $result += $statsText
                }

                return $result
            }

            'TimeSeries'
            {
                return script:Build-TimeSeriesGraph -Data $Data -Min $min -Max $max -Width $Width -Height $Height -ShowStats $ShowStats -Avg $avg -Style $Style -Jitter $jitter
            }

            'Distribution'
            {
                $output = New-Object System.Text.StringBuilder

                # Create buckets
                $bucketCount = 10
                $bucketSize = ($max - $min) / $bucketCount
                if ($bucketSize -eq 0) { $bucketSize = 1 }

                $buckets = @{}
                for ($i = 0; $i -lt $bucketCount; $i++)
                {
                    $buckets[$i] = 0
                }

                # Fill buckets
                foreach ($value in $validData)
                {
                    $bucketIndex = [Math]::Floor(($value - $min) / $bucketSize)
                    $bucketIndex = [Math]::Min($bucketCount - 1, [Math]::Max(0, $bucketIndex))
                    $buckets[$bucketIndex]++
                }

                $maxCount = ($buckets.Values | Measure-Object -Maximum).Maximum
                if ($maxCount -eq 0) { $maxCount = 1 }

                [void]$output.AppendLine("${script:Palette.Cyan}Latency Distribution:${script:Palette.Reset}")

                for ($i = 0; $i -lt $bucketCount; $i++)
                {
                    $rangeStart = [Math]::Round($min + ($i * $bucketSize), 1)
                    $rangeEnd = [Math]::Round($min + (($i + 1) * $bucketSize), 1)
                    $bucketItemCount = $buckets[$i]
                    $barWidth = [Math]::Floor(($bucketItemCount / $maxCount) * ($Width - 20))

                    # Color bar based on range midpoint
                    $midpoint = ($rangeStart + $rangeEnd) / 2
                    $barColor = if ($midpoint -lt 50) { $script:Palette.Green } elseif ($midpoint -lt 100) { $script:Palette.Yellow } else { $script:Palette.Red }

                    $label = "$rangeStart-$rangeEnd ms".PadRight(15)
                    $bar = "$barColor" + ([char]0x2588 * $barWidth) + "$script:Palette.Reset"
                    $percentage = [Math]::Round(($bucketItemCount / $validData.Count) * 100, 1)

                    [void]$output.AppendLine("${script:Palette.Gray}$label${script:Palette.Reset} $bar ${script:Palette.Cyan}$bucketItemCount${script:Palette.Reset} ${script:Palette.Gray}($percentage`%)${script:Palette.Reset}")
                }

                return $output.ToString()
            }
        }
    }
}
