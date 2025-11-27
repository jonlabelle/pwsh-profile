function Show-NetworkLatencyGraph
{
    <#
    .SYNOPSIS
        Displays ASCII graph visualizations of network latency data

    .DESCRIPTION
        Creates visual ASCII representations of latency measurements including sparklines,
        bar charts, and time-series graphs. Supports both inline sparklines and detailed
        multi-line graphs. Cross-platform compatible.

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

    .OUTPUTS
        System.String

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Show-NetworkLatencyGraph.ps1
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [Double[]]$Data,

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
        [Switch]$ShowStats
    )

    begin
    {
        Write-Verbose "Creating $GraphType graph"

        # Block characters for sparklines (8 levels)
        $script:SparkChars = @(' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█')

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

    process
    {
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
                    $statsText = " (min: $([Math]::Round($min, 1))ms, max: $([Math]::Round($max, 1))ms, avg: $([Math]::Round($avg, 1))ms"
                    if ($failedCount -gt 0)
                    {
                        $statsText += ", failed: $failedCount"
                    }
                    $statsText += ')'
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
                    [void]$output.AppendLine("     Min: $([Math]::Round($min, 1))ms | Max: $([Math]::Round($max, 1))ms | Avg: $([Math]::Round($avg, 1))ms | Samples: $($validData.Count)")
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

                [void]$output.AppendLine('Latency Distribution:')

                for ($i = 0; $i -lt $bucketCount; $i++)
                {
                    $rangeStart = [Math]::Round($min + ($i * $bucketSize), 1)
                    $rangeEnd = [Math]::Round($min + (($i + 1) * $bucketSize), 1)
                    $count = $buckets[$i]
                    $barWidth = [Math]::Floor(($count / $maxCount) * ($Width - 20))

                    $label = "$rangeStart-$rangeEnd ms".PadRight(15)
                    $bar = '█' * $barWidth
                    $percentage = [Math]::Round(($count / $validData.Count) * 100, 1)

                    [void]$output.AppendLine("$label $bar $count ($percentage%)")
                }

                return $output.ToString()
            }
        }
    }
}
