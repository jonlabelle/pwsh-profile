function Show-NetworkLatencyGraph
{
    <#
    .SYNOPSIS
        Displays ASCII graph visualizations of network latency data

    .DESCRIPTION
        Creates visual ASCII representations of latency measurements including sparklines,
        bar charts, and time-series graphs. Supports both inline sparklines and detailed
        multi-line graphs. Cross-platform compatible.

        See NOTES for PowerShell 5.1 behavior in continuous mode.

    .PARAMETER Data
        Array of latency values in milliseconds. Supports $null values for failed requests.

    .PARAMETER GraphType
        Type of graph to display:
        - Sparkline: Inline bar chart using block characters
        - TimeSeries: Multi-line graph showing latency over time
        - Distribution: Histogram showing latency distribution

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

    .OUTPUTS
        System.String

    .NOTES
        POWERSHELL 5.1 BEHAVIOR:
        - PowerShell Desktop 5.1 does not support ANSI cursor control for in-place updates
        - Console is cleared between iterations using Clear-Host in continuous mode
        - ANSI colors are automatically disabled on 5.1 to prevent escape codes in output
        - PowerShell Core (6+) supports ANSI colors; cursor movement avoided for compatibility

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Show-NetworkLatencyGraph.ps1
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Data')]
        [AllowNull()]
        [Double[]]$Data,

        [Parameter(Mandatory, ParameterSetName = 'Continuous')]
        [ValidateNotNullOrEmpty()]
        [String]$HostName,

        [Parameter()]
        [ValidateSet('Sparkline', 'TimeSeries', 'Distribution')]
        [String]$GraphType = 'Sparkline',

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

        # ANSI color codes
        $script:ColorReset = if ($NoColor) { '' } else { "`e[0m" }
        $script:ColorGreen = if ($NoColor) { '' } else { "`e[32m" }
        $script:ColorYellow = if ($NoColor) { '' } else { "`e[33m" }
        $script:ColorRed = if ($NoColor) { '' } else { "`e[31m" }
        $script:ColorCyan = if ($NoColor) { '' } else { "`e[36m" }
        $script:ColorGray = if ($NoColor) { '' } else { "`e[90m" }

        # Disable ANSI colors automatically on PowerShell Desktop 5.1
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $script:ColorReset = ''
            $script:ColorGreen = ''
            $script:ColorYellow = ''
            $script:ColorRed = ''
            $script:ColorCyan = ''
            $script:ColorGray = ''
        }

        # Block characters for sparklines (8 levels)
        $script:SparkChars = @(' ', [char]0x2581, [char]0x2582, [char]0x2583, [char]0x2584, [char]0x2585, [char]0x2586, [char]0x2587, [char]0x2588)

        # Load Get-NetworkMetrics if in continuous mode
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

            Write-Verbose "Data range: min=$min, max=$max, avg=$([Math]::Round($avg, 2))"
        }
    }

    process
    {
        # Continuous mode
        if ($Continuous)
        {
            $iteration = 0
            $lastRenderLines = 0
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
                elseif ($effectiveRender -eq 'InPlace' -and ($iteration -gt 1) -and $lastRenderLines -gt 0)
                {
                    # Move cursor up to the start of the previous block and reset to column 1
                    Write-Host ("`e[{0}A" -f $lastRenderLines) -NoNewline
                    Write-Host "`e[1G" -NoNewline
                }

                Write-Host "${script:ColorCyan}Network Latency Graph - Iteration $iteration (Press Ctrl+C to stop)${script:ColorReset}"
                Write-Host "${script:ColorGray}Host: $HostName | Interval: ${Interval}s | Samples: $Count | Port: $Port${script:ColorReset}"
                Write-Host
                $linesPrinted = 3

                # Collect metrics
                $metrics = Get-NetworkMetrics -HostName $HostName -Count $Count -Port $Port
                $Data = $metrics.LatencyData

                # Filter and calculate for this iteration
                $validData = @($Data | Where-Object { $null -ne $_ })
                $failedCount = @($Data | Where-Object { $null -eq $_ }).Count

                if ($validData.Count -gt 0)
                {
                    $min = ($validData | Measure-Object -Minimum).Minimum
                    $max = ($validData | Measure-Object -Maximum).Maximum
                    $avg = ($validData | Measure-Object -Average).Average

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
                                    [void]$sparkline.Append('✖')
                                }
                                else
                                {
                                    if ($max -eq $min) { $index = 4 }
                                    else
                                    {
                                        $normalized = ($value - $min) / ($max - $min)
                                        $index = [Math]::Floor($normalized * 8)
                                        $index = [Math]::Min(8, [Math]::Max(0, $index))
                                    }
                                    [void]$sparkline.Append($script:SparkChars[$index])
                                }
                            }
                            $result = $sparkline.ToString()
                            if ($ShowStats)
                            {
                                $statsText = " ${script:ColorGray}(min: ${script:ColorCyan}$([Math]::Round($min, 1))ms${script:ColorGray}, max: ${script:ColorCyan}$([Math]::Round($max, 1))ms${script:ColorGray}, avg: "
                                $avgColor = if ($avg -lt 50) { $script:ColorGreen } elseif ($avg -lt 100) { $script:ColorYellow } else { $script:ColorRed }
                                $statsText += "$avgColor$([Math]::Round($avg, 1))ms${script:ColorGray}"
                                if ($failedCount -gt 0) { $statsText += ", failed: ${script:ColorRed}$failedCount${script:ColorGray}" }
                                $statsText += ")${script:ColorReset}"
                                $result += $statsText
                            }
                            else
                            {
                                # Provide a compact stats line under the sparkline in continuous mode
                                $avgColor = if ($avg -lt 50) { $script:ColorGreen } elseif ($avg -lt 100) { $script:ColorYellow } else { $script:ColorRed }
                                $compact = "`n${script:ColorGray}Min: ${script:ColorCyan}$([Math]::Round($min,1))ms ${script:ColorGray}| Max: ${script:ColorCyan}$([Math]::Round($max,1))ms ${script:ColorGray}| Avg: $avgColor$([Math]::Round($avg,1))ms ${script:ColorGray}| Samples: ${script:ColorCyan}$($validData.Count)${script:ColorReset}"
                                if ($failedCount -gt 0) { $compact += " ${script:ColorGray}| Failed: ${script:ColorRed}$failedCount${script:ColorReset}" }
                                $result += $compact
                            }
                            $result
                        }
                        'TimeSeries'
                        {
                            $output = New-Object System.Text.StringBuilder
                            $range = if (($max - $min) -eq 0) { 1 } else { $max - $min }
                            for ($row = $Height - 1; $row -ge 0; $row--)
                            {
                                $threshold = $min + ($range * ($row + 0.5) / $Height)
                                $yLabel = [Math]::Round($min + ($range * $row / $Height), 0)
                                [void]$output.Append($yLabel.ToString().PadLeft(5))
                                [void]$output.Append(' |')
                                $pointsToPlot = [Math]::Min($Width, $validData.Count)
                                for ($col = 0; $col -lt $pointsToPlot; $col++)
                                {
                                    $dataIndex = [Math]::Floor($col * $validData.Count / $pointsToPlot)
                                    $value = $validData[$dataIndex]
                                    if ($null -eq $value) { [void]$output.Append(' ') }
                                    elseif ($value -ge $threshold)
                                    {
                                        if ($row -eq $Height - 1 -or $validData[$dataIndex] -ge ($min + ($range * ($row + 1) / $Height)))
                                        { [void]$output.Append('█') }
                                        else { [void]$output.Append('▄') }
                                    }
                                    else { [void]$output.Append(' ') }
                                }
                                [void]$output.AppendLine()
                            }
                            [void]$output.Append('     +')
                            [void]$output.AppendLine('-' * $pointsToPlot)
                            if ($ShowStats)
                            {
                                $statsLine = "     ${script:ColorGray}Min: ${script:ColorCyan}$([Math]::Round($min, 1))ms ${script:ColorGray}| Max: ${script:ColorCyan}$([Math]::Round($max, 1))ms ${script:ColorGray}| Avg: "
                                $avgColor = if ($avg -lt 50) { $script:ColorGreen } elseif ($avg -lt 100) { $script:ColorYellow } else { $script:ColorRed }
                                $statsLine += "$avgColor$([Math]::Round($avg, 1))ms ${script:ColorGray}| Samples: ${script:ColorCyan}$($validData.Count)${script:ColorReset}"
                                [void]$output.AppendLine($statsLine)
                            }
                            $output.ToString()
                        }
                        'Distribution'
                        {
                            $output = New-Object System.Text.StringBuilder
                            $bucketCount = 10
                            $bucketSize = if (($max - $min) -eq 0) { 1 } else { ($max - $min) / $bucketCount }
                            $buckets = @{}
                            0..($bucketCount - 1) | ForEach-Object { $buckets[$_] = 0 }
                            foreach ($value in $validData)
                            {
                                $bucketIndex = [Math]::Floor(($value - $min) / $bucketSize)
                                $bucketIndex = [Math]::Min($bucketCount - 1, [Math]::Max(0, $bucketIndex))
                                $buckets[$bucketIndex]++
                            }
                            $maxCount = if (($buckets.Values | Measure-Object -Maximum).Maximum -eq 0) { 1 } else { ($buckets.Values | Measure-Object -Maximum).Maximum }
                            [void]$output.AppendLine("${script:ColorCyan}Latency Distribution:${script:ColorReset}")
                            for ($i = 0; $i -lt $bucketCount; $i++)
                            {
                                $rangeStart = [Math]::Round($min + ($i * $bucketSize), 1)
                                $rangeEnd = [Math]::Round($min + (($i + 1) * $bucketSize), 1)
                                $count = $buckets[$i]
                                $barWidth = [Math]::Floor(($count / $maxCount) * ($Width - 20))
                                $midpoint = ($rangeStart + $rangeEnd) / 2
                                $barColor = if ($midpoint -lt 50) { $script:ColorGreen } elseif ($midpoint -lt 100) { $script:ColorYellow } else { $script:ColorRed }
                                $label = "${script:ColorGray}$rangeStart-$rangeEnd ms${script:ColorReset}".PadRight(15 + ($script:ColorGray.Length + $script:ColorReset.Length))
                                $bar = "$barColor" + ('█' * $barWidth) + "$script:ColorReset"
                                $percentage = [Math]::Round(($count / $validData.Count) * 100, 1)
                                [void]$output.AppendLine("$label $bar ${script:ColorCyan}$count${script:ColorReset} ${script:ColorGray}($percentage%)${script:ColorReset}")
                            }
                            $output.ToString()
                        }
                    }

                    Write-Host $graphOutput
                    $graphLineCount = ($graphOutput -split "`n" | Where-Object { $_.Trim() }).Count
                    $linesPrinted += $graphLineCount
                }
                else
                {
                    Write-Host "${script:ColorRed}No successful connections${script:ColorReset}"
                    $linesPrinted += 1
                }

                Write-Host
                # Packet loss and jitter with dynamic color coding (green=good, yellow=medium, red=bad)
                $lossColor = if ($metrics.PacketLoss -eq 0) { $script:ColorGreen } elseif ($metrics.PacketLoss -lt 5) { $script:ColorYellow } else { $script:ColorRed }
                $jitterColor = if ($metrics.Jitter -lt 10) { $script:ColorGreen } elseif ($metrics.Jitter -lt 30) { $script:ColorYellow } else { $script:ColorRed }
                Write-Host "${script:ColorGray}Packet Loss: $lossColor$($metrics.PacketLoss)%${script:ColorGray} | Jitter: $jitterColor$($metrics.Jitter)ms${script:ColorReset}"
                $linesPrinted += 2
                $lastRenderLines = $linesPrinted
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
                        [void]$sparkline.Append('✖')
                    }
                    else
                    {
                        # Normalize value to 0-8 range
                        if ($max -eq $min)
                        {
                            $index = 4
                        }
                        else
                        {
                            $normalized = ($value - $min) / ($max - $min)
                            $index = [Math]::Floor($normalized * 8)
                            $index = [Math]::Min(8, [Math]::Max(0, $index))
                        }
                        [void]$sparkline.Append($script:SparkChars[$index])
                    }
                }

                $result = $sparkline.ToString()

                if ($ShowStats)
                {
                    $statsText = " ${script:ColorGray}(min: ${script:ColorCyan}$([Math]::Round($min, 1))ms${script:ColorGray}, max: ${script:ColorCyan}$([Math]::Round($max, 1))ms${script:ColorGray}, avg: "

                    # Color avg based on value
                    $avgColor = if ($avg -lt 50) { $script:ColorGreen } elseif ($avg -lt 100) { $script:ColorYellow } else { $script:ColorRed }
                    $statsText += "$avgColor$([Math]::Round($avg, 1))ms${script:ColorGray}"

                    if ($failedCount -gt 0)
                    {
                        $statsText += ", failed: ${script:ColorRed}$failedCount${script:ColorGray}"
                    }
                    $statsText += ")${script:ColorReset}"
                    $result += $statsText
                }

                return $result
            }

            'TimeSeries'
            {
                $output = New-Object System.Text.StringBuilder

                # Create Y-axis labels and grid
                $range = $max - $min
                if ($range -eq 0) { $range = 1 }

                # Build graph line by line from top to bottom
                for ($row = $Height - 1; $row -ge 0; $row--)
                {
                    $threshold = $min + ($range * ($row + 0.5) / $Height)
                    $yLabel = [Math]::Round($min + ($range * $row / $Height), 0)

                    # Y-axis label
                    [void]$output.Append($yLabel.ToString().PadLeft(5))
                    [void]$output.Append(' |')

                    # Plot points
                    $pointsToPlot = [Math]::Min($Width, $validData.Count)

                    for ($col = 0; $col -lt $pointsToPlot; $col++)
                    {
                        $dataIndex = [Math]::Floor($col * $validData.Count / $pointsToPlot)
                        $value = $validData[$dataIndex]

                        if ($null -eq $value)
                        {
                            [void]$output.Append(' ')
                        }
                        elseif ($value -ge $threshold)
                        {
                            # Determine character based on proximity
                            if ($row -eq $Height - 1 -or $validData[$dataIndex] -ge ($min + ($range * ($row + 1) / $Height)))
                            {
                                [void]$output.Append('█')
                            }
                            else
                            {
                                [void]$output.Append('▄')
                            }
                        }
                        else
                        {
                            [void]$output.Append(' ')
                        }
                    }

                    [void]$output.AppendLine()
                }

                # X-axis
                [void]$output.Append('     +')
                [void]$output.AppendLine('-' * $pointsToPlot)

                if ($ShowStats)
                {
                    $statsLine = "     ${script:ColorGray}Min: ${script:ColorCyan}$([Math]::Round($min, 1))ms ${script:ColorGray}| Max: ${script:ColorCyan}$([Math]::Round($max, 1))ms ${script:ColorGray}| Avg: "

                    # Color avg based on value
                    $avgColor = if ($avg -lt 50) { $script:ColorGreen } elseif ($avg -lt 100) { $script:ColorYellow } else { $script:ColorRed }
                    $statsLine += "$avgColor$([Math]::Round($avg, 1))ms ${script:ColorGray}| Samples: ${script:ColorCyan}$($validData.Count)${script:ColorReset}"

                    [void]$output.AppendLine($statsLine)
                }

                return $output.ToString()
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

                [void]$output.AppendLine("${script:ColorCyan}Latency Distribution:${script:ColorReset}")

                for ($i = 0; $i -lt $bucketCount; $i++)
                {
                    $rangeStart = [Math]::Round($min + ($i * $bucketSize), 1)
                    $rangeEnd = [Math]::Round($min + (($i + 1) * $bucketSize), 1)
                    $count = $buckets[$i]
                    $barWidth = [Math]::Floor(($count / $maxCount) * ($Width - 20))

                    # Color bar based on range midpoint
                    $midpoint = ($rangeStart + $rangeEnd) / 2
                    $barColor = if ($midpoint -lt 50) { $script:ColorGreen } elseif ($midpoint -lt 100) { $script:ColorYellow } else { $script:ColorRed }

                    $label = "${script:ColorGray}$rangeStart-$rangeEnd ms${script:ColorReset}".PadRight(15 + ($script:ColorGray.Length + $script:ColorReset.Length))
                    $bar = "$barColor" + ([char]0x2588 * $barWidth) + "$script:ColorReset"
                    $percentage = [Math]::Round(($count / $validData.Count) * 100, 1)

                    [void]$output.AppendLine("$label $bar ${script:ColorCyan}$count${script:ColorReset} ${script:ColorGray}($percentage`%)${script:ColorReset}")
                }

                return $output.ToString()
            }
        }
    }
}
