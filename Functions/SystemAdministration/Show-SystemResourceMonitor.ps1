function Show-SystemResourceMonitor
{
    <#
    .SYNOPSIS
        Displays a visual monitor for CPU, memory, disk, and network activity.

    .DESCRIPTION
        Collects core system resource metrics and renders them in a compact, visual
        dashboard using text bars and history sparklines. Includes network activity
        throughput using cross-platform .NET interface counters. Works on Windows,
        macOS, and Linux with platform-specific collection logic and safe fallbacks.

        By default, the function returns a single dashboard snapshot as a string.
        Use -Continuous to keep refreshing the view until interrupted with Ctrl+C.
        Continuous mode includes refresh timestamps for better visibility.
        Use -AsObject for structured output suitable for scripts and automation.
        Dashboard status includes an overall health grade (A-F), status icon, findings
        summary, and collection elapsed time.
        Enable -IncludeTopProcesses to append the busiest running processes.
        Use -TopProcessName to filter process rows by wildcard name patterns.
        Use -MonitorProcessName to scope resource charts to matching processes.

    .PARAMETER Continuous
        Continuously refreshes the monitor output.

    .PARAMETER IntervalSeconds
        Number of seconds to wait between updates in continuous mode.

    .PARAMETER BarWidth
        Width of the visual usage bars.

    .PARAMETER HistoryLength
        Number of historical points to keep for sparkline trend rendering.

    .PARAMETER NoColor
        Disables ANSI color output.

    .PARAMETER Ascii
        Forces ASCII-only rendering for maximum terminal compatibility.

    .PARAMETER AsObject
        Returns structured metric objects instead of rendered dashboard text.

    .PARAMETER IncludeTopProcesses
        Includes top running process details in the dashboard and object output.

    .PARAMETER TopProcessCount
        Number of top processes to include when -IncludeTopProcesses is used.

    .PARAMETER TopProcessName
        One or more wildcard patterns used to filter top process names.
        Example: 'pwsh*' or @('chrome*', 'Code*').

    .PARAMETER MonitorProcessName
        One or more wildcard patterns used to scope monitor visualizations.
        When specified, CPU and memory metrics are calculated from matching
        processes only. Disk and network are shown as n/a in this scoped mode.
        Plain names without wildcard characters are treated as contains matches.

    .PARAMETER MaxIterations
        Maximum number of iterations for continuous mode. 0 means unlimited.
        Primarily useful for testing and automation.

    .EXAMPLE
        PS > Show-SystemResourceMonitor

        System Resource Monitor                                                      31.0% OK [A] ✓
        ───────────────────────────────────────────────────────────────────────────────────────────
        CPU     [███▌░░░░░░░░░░░░░░░░░░░░░░░░░░░░]   11.0% OK      0.9/8.0 logical cores busy
        Memory  [████████████████░░░░░░░░░░░░░░░░]   50.0% OK      12.1/24.0 GiB
        Disk    [██████████▌░░░░░░░░░░░░░░░░░░░░░]   33.0% OK      151.4/460.4 GiB on / (root fs)
        Network [░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]    0.0% IDLE    In 0 B/s | Out 0 B/s | Total 0 B/s
        ───────────────────────────────────────────────────────────────────────────────────────────

        Status   Platform: macOS │ Updated: 2026-02-17 19:16:30 │ Collect: 519.4ms
        History  Last 24 samples (oldest -> newest)

        Displays a single visual snapshot of system resource usage.

    .EXAMPLE
        PS > Show-SystemResourceMonitor -Continuous -IntervalSeconds 2

        Continuously monitors system resources, refreshing every 2 seconds.

    .EXAMPLE
        PS > Show-SystemResourceMonitor -AsObject | Format-List

        Returns structured metric data for scripting.

    .EXAMPLE
        PS > Show-SystemResourceMonitor -Continuous -Ascii

        Runs the monitor continuously using ASCII-safe visualization glyphs.

    .EXAMPLE
        PS > Show-SystemResourceMonitor -IncludeTopProcesses -TopProcessCount 5

        Displays the dashboard with a top processes section.

    .EXAMPLE
        PS > Show-SystemResourceMonitor -IncludeTopProcesses -TopProcessName 'pwsh*'

        Displays only top processes whose names match the wildcard filter.

    .EXAMPLE
        PS > Show-SystemResourceMonitor -MonitorProcessName 'pwsh*'

        Displays a scoped view where matching processes drive resource charts.

    .OUTPUTS
        System.String
        System.Management.Automation.PSCustomObject

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Show-SystemResourceMonitor.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Show-SystemResourceMonitor.ps1
    #>
    [CmdletBinding()]
    [OutputType([System.String], [PSCustomObject])]
    param(
        [Parameter()]
        [Switch]$Continuous,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [Int32]$IntervalSeconds = 2,

        [Parameter()]
        [ValidateRange(10, 120)]
        [Int32]$BarWidth = 32,

        [Parameter()]
        [ValidateRange(5, 120)]
        [Int32]$HistoryLength = 24,

        [Parameter()]
        [Switch]$NoColor,

        [Parameter()]
        [Switch]$Ascii,

        [Parameter()]
        [Switch]$AsObject,

        [Parameter()]
        [Switch]$IncludeTopProcesses,

        [Parameter()]
        [ValidateRange(1, 20)]
        [Int32]$TopProcessCount = 5,

        [Parameter()]
        [String[]]$TopProcessName,

        [Parameter()]
        [String[]]$MonitorProcessName,

        [Parameter(DontShow = $true)]
        [ValidateRange(0, [Int32]::MaxValue)]
        [Int32]$MaxIterations = 0
    )

    begin
    {
        # Platform detection compatible with both Windows PowerShell 5.1 and PowerShell Core.
        $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { $IsWindows }
        $isMacOSPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $false } else { $IsMacOS }
        $isLinuxPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $false } else { $IsLinux }

        $platformName = if ($isWindowsPlatform) { 'Windows' }
        elseif ($isMacOSPlatform) { 'macOS' }
        elseif ($isLinuxPlatform) { 'Linux' }
        else { 'Unknown' }

        $cpuFallbackState = @{
            Timestamp = $null
            TotalCpuSeconds = $null
        }

        $networkActivityState = @{
            Timestamp = $null
            TotalBytesReceived = $null
            TotalBytesSent = $null
        }

        $processScopeCpuState = @{
            Timestamp = $null
            TotalCpuSeconds = $null
        }

        $cpuHistory = New-Object 'System.Collections.Generic.List[double]'
        $memoryHistory = New-Object 'System.Collections.Generic.List[double]'
        $diskHistory = New-Object 'System.Collections.Generic.List[double]'
        $networkThroughputHistory = New-Object 'System.Collections.Generic.List[double]'
        $topProcessNameFilters = @(
            @($TopProcessName) |
            Where-Object { -not [String]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
        )
        $monitorProcessNameFilters = @(
            @($MonitorProcessName) |
            Where-Object { -not [String]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
        )
        $monitorProcessNameMatchFilters = @(
            $monitorProcessNameFilters |
            ForEach-Object {
                if ($_ -match '[\*\?\[]')
                {
                    $_
                }
                else
                {
                    '*' + $_ + '*'
                }
            }
        )
        $effectiveTopProcessNameFilters = @($topProcessNameFilters)
        $effectiveTopProcessNameMatchFilters = @($topProcessNameFilters)
        if ($effectiveTopProcessNameFilters.Count -eq 0 -and $monitorProcessNameFilters.Count -gt 0)
        {
            $effectiveTopProcessNameFilters = @($monitorProcessNameFilters)
            $effectiveTopProcessNameMatchFilters = @($monitorProcessNameMatchFilters)
        }

        $supportsAnsi = $false
        if (-not $NoColor)
        {
            try
            {
                if ($PSVersionTable.PSVersion.Major -ge 7 -and $Host.UI -and $Host.UI.SupportsVirtualTerminal)
                {
                    $supportsAnsi = $true
                }
            }
            catch
            {
                $supportsAnsi = $false
            }
        }

        $supportsUnicode = -not $Ascii
        if ($supportsUnicode)
        {
            try
            {
                $outputEncoding = [Console]::OutputEncoding
                if ($null -eq $outputEncoding)
                {
                    $supportsUnicode = $false
                }
                elseif ($outputEncoding.WebName -notmatch 'utf-8|utf-16|unicode')
                {
                    $supportsUnicode = $false
                }
            }
            catch
            {
                $supportsUnicode = $false
            }
        }

        $ansiReset = if ($supportsAnsi) { "$([char]27)[0m" } else { '' }

        $statusIcons = @{
            Healthy = if ($supportsUnicode) { [String][char]0x2713 } else { '+' }
            Warning = if ($supportsUnicode) { [String][char]0x26A0 } else { '!' }
            Critical = if ($supportsUnicode) { [String][char]0x2717 } else { 'x' }
        }

        function Add-HistoryValue
        {
            param(
                [AllowEmptyCollection()]
                [System.Collections.Generic.List[double]]$History,

                [Parameter()]
                [Nullable[Double]]$Value,

                [Parameter(Mandatory)]
                [Int32]$MaxLength
            )

            if ($null -eq $Value)
            {
                [void]$History.Add([Double]::NaN)
            }
            else
            {
                [void]$History.Add([Double]$Value)
            }

            while ($History.Count -gt $MaxLength)
            {
                $History.RemoveAt(0)
            }
        }

        function ConvertTo-Sparkline
        {
            param(
                [Parameter(Mandatory)]
                [Double[]]$Values
            )

            if ($supportsUnicode)
            {
                $levels = @(
                    [String][char]0x2581,
                    [String][char]0x2582,
                    [String][char]0x2583,
                    [String][char]0x2584,
                    [String][char]0x2585,
                    [String][char]0x2586,
                    [String][char]0x2587,
                    [String][char]0x2588
                )
                $missing = [String][char]0x2591
            }
            else
            {
                $levels = @('_', '.', ':', '-', '=', '+', '*', '#', '%', '@')
                $missing = '?'
            }

            $chars = foreach ($value in $Values)
            {
                if ([Double]::IsNaN($value))
                {
                    $missing
                    continue
                }

                $normalized = [Math]::Max(0, [Math]::Min(100, $value))
                $index = [Math]::Round(($normalized / 100) * ($levels.Count - 1))
                $levels[[Int32]$index]
            }

            -join $chars
        }

        function ConvertTo-UsageBar
        {
            param(
                [Parameter()]
                [Nullable[Double]]$Percent,

                [Parameter(Mandatory)]
                [Int32]$Width,

                [Parameter()]
                [Switch]$UseZeroFillWhenUnknown
            )

            if ($null -eq $Percent)
            {
                if (-not $UseZeroFillWhenUnknown)
                {
                    return '[' + ('?' * $Width) + ']'
                }
            }

            $percentForBar = if ($null -eq $Percent) { 0.0 } else { [Double]$Percent }
            $clamped = [Math]::Max(0, [Math]::Min(100, $percentForBar))
            if (-not $supportsUnicode)
            {
                $filled = [Math]::Round(($clamped / 100) * $Width)
                $filled = [Math]::Max(0, [Math]::Min($Width, [Int32]$filled))

                $empty = $Width - $filled
                $filledText = if ($filled -gt 0) { '#' * $filled } else { '' }
                $emptyText = if ($empty -gt 0) { '-' * $empty } else { '' }

                return '[' + $filledText + $emptyText + ']'
            }

            $fullGlyph = [String][char]0x2588
            $emptyGlyph = [String][char]0x2591
            $partials = @(
                '',
                [String][char]0x258F,
                [String][char]0x258E,
                [String][char]0x258D,
                [String][char]0x258C,
                [String][char]0x258B,
                [String][char]0x258A,
                [String][char]0x2589
            )

            $scaled = ($clamped / 100) * $Width
            $fullCount = [Int32][Math]::Floor($scaled)
            $fraction = $scaled - $fullCount
            $partialIndex = [Int32][Math]::Round($fraction * ($partials.Count - 1))

            if ($partialIndex -ge ($partials.Count - 1))
            {
                $fullCount = [Math]::Min($Width, $fullCount + 1)
                $partialIndex = 0
            }

            $segments = New-Object 'System.Collections.Generic.List[string]'
            if ($fullCount -gt 0)
            {
                [void]$segments.Add($fullGlyph * $fullCount)
            }

            $consumed = $fullCount
            if ($partialIndex -gt 0 -and $consumed -lt $Width)
            {
                [void]$segments.Add($partials[$partialIndex])
                $consumed++
            }

            $emptyCount = $Width - $consumed
            if ($emptyCount -gt 0)
            {
                [void]$segments.Add($emptyGlyph * $emptyCount)
            }

            return '[' + (-join $segments.ToArray()) + ']'
        }

        function Get-UsageStatus
        {
            param(
                [Parameter()]
                [Nullable[Double]]$Percent
            )

            if ($null -eq $Percent)
            {
                return 'N/A'
            }

            $value = [Double]$Percent
            if ($value -lt 60) { return 'OK' }
            if ($value -lt 85) { return 'WARN' }
            return 'CRIT'
        }

        function Get-OverallLoadPercent
        {
            param(
                [Parameter()]
                [Nullable[Double]]$CpuPercent,

                [Parameter()]
                [Nullable[Double]]$MemoryPercent,

                [Parameter()]
                [Nullable[Double]]$DiskPercent
            )

            $percentValues = @(
                $CpuPercent,
                $MemoryPercent,
                $DiskPercent
            ) | Where-Object { $null -ne $_ }

            if ($percentValues.Count -eq 0)
            {
                return $null
            }

            return [Math]::Round(($percentValues | Measure-Object -Average).Average, 1)
        }

        function Get-ResourceHealthGrade
        {
            param(
                [Parameter()]
                [Nullable[Double]]$CpuPercent,

                [Parameter()]
                [Nullable[Double]]$MemoryPercent,

                [Parameter()]
                [Nullable[Double]]$DiskPercent,

                [Parameter()]
                [Nullable[Double]]$OverallLoadPercent
            )

            $knownValues = @(
                $CpuPercent,
                $MemoryPercent,
                $DiskPercent
            ) | Where-Object { $null -ne $_ }

            if ($knownValues.Count -eq 0)
            {
                return 'F'
            }

            $score = 100
            foreach ($metric in @($CpuPercent, $MemoryPercent, $DiskPercent))
            {
                if ($null -eq $metric)
                {
                    $score -= 8
                    continue
                }

                $value = [Double]$metric
                if ($value -ge 95) { $score -= 35; continue }
                if ($value -ge 85) { $score -= 20; continue }
                if ($value -ge 70) { $score -= 8; continue }
                if ($value -ge 60) { $score -= 3 }
            }

            $overall = if ($null -eq $OverallLoadPercent)
            {
                Get-OverallLoadPercent -CpuPercent $CpuPercent -MemoryPercent $MemoryPercent -DiskPercent $DiskPercent
            }
            else
            {
                [Double]$OverallLoadPercent
            }

            if ($null -ne $overall)
            {
                if ($overall -ge 95) { $score -= 20 }
                elseif ($overall -ge 85) { $score -= 10 }
                elseif ($overall -ge 70) { $score -= 4 }
            }

            switch ($score)
            {
                { $_ -ge 90 } { return 'A' }
                { $_ -ge 75 } { return 'B' }
                { $_ -ge 60 } { return 'C' }
                { $_ -ge 40 } { return 'D' }
                default { return 'F' }
            }
        }

        function Get-HealthStatusIcon
        {
            param(
                [Parameter(Mandatory)]
                [String]$Grade
            )

            switch ($Grade)
            {
                { $_ -in 'A', 'B' } { return $statusIcons.Healthy }
                { $_ -in 'C', 'D' } { return $statusIcons.Warning }
                default { return $statusIcons.Critical }
            }
        }

        function Format-HealthGrade
        {
            param(
                [Parameter(Mandatory)]
                [String]$Grade
            )

            if (-not $supportsAnsi)
            {
                return $Grade
            }

            $esc = [char]27
            $gradeColor = switch ($Grade)
            {
                'A' { "$esc[32m" }
                'B' { "$esc[36m" }
                'C' { "$esc[33m" }
                'D' { "$esc[33m" }
                default { "$esc[31m" }
            }

            return $gradeColor + $Grade + $ansiReset
        }

        function Get-ResourceFindings
        {
            param(
                [Parameter()]
                [Nullable[Double]]$CpuPercent,

                [Parameter()]
                [Nullable[Double]]$MemoryPercent,

                [Parameter()]
                [Nullable[Double]]$DiskPercent
            )

            $findings = New-Object 'System.Collections.Generic.List[string]'

            $addFinding = {
                param(
                    [Parameter(Mandatory)]
                    [String]$Name,

                    [Parameter()]
                    [Nullable[Double]]$Percent
                )

                if ($null -eq $Percent)
                {
                    [void]$findings.Add("$Name unavailable")
                    return
                }

                $value = [Double]$Percent
                if ($value -ge 95)
                {
                    [void]$findings.Add(('{0} critical ({1:N1}%)' -f $Name, $value))
                }
                elseif ($value -ge 85)
                {
                    [void]$findings.Add(('{0} high ({1:N1}%)' -f $Name, $value))
                }
                elseif ($value -ge 70)
                {
                    [void]$findings.Add(('{0} elevated ({1:N1}%)' -f $Name, $value))
                }
            }

            & $addFinding -Name 'CPU' -Percent $CpuPercent
            & $addFinding -Name 'Memory' -Percent $MemoryPercent
            & $addFinding -Name 'Disk' -Percent $DiskPercent

            return @($findings.ToArray())
        }

        function Get-TrendIndicator
        {
            param(
                [Parameter(Mandatory)]
                [Double[]]$Values
            )

            $validValues = @($Values | Where-Object { -not [Double]::IsNaN($_) })
            if ($validValues.Count -lt 2)
            {
                if ($supportsUnicode)
                {
                    return [String][char]0x2022
                }

                return '~'
            }

            $delta = $validValues[-1] - $validValues[-2]
            if ([Math]::Abs($delta) -lt 0.25)
            {
                if ($supportsUnicode)
                {
                    return [String][char]0x2192
                }

                return '='
            }

            if ($delta -gt 0)
            {
                if ($supportsUnicode)
                {
                    return [String][char]0x2197
                }

                return '^'
            }

            if ($supportsUnicode)
            {
                return [String][char]0x2198
            }

            return 'v'
        }

        function Get-ResolvedBarWidth
        {
            param(
                [Parameter(Mandatory)]
                [Int32]$RequestedWidth,

                [Parameter(Mandatory)]
                [Int32]$RenderedHistoryLength
            )

            $resolvedWidth = $RequestedWidth
            try
            {
                if ($Host.UI -and $Host.UI.RawUI)
                {
                    $windowWidth = [Int32]$Host.UI.RawUI.WindowSize.Width
                    if ($windowWidth -gt 0)
                    {
                        $reservedWidth = 52 + $RenderedHistoryLength
                        $availableWidth = $windowWidth - $reservedWidth
                        if ($availableWidth -ge 10)
                        {
                            $resolvedWidth = [Math]::Min($resolvedWidth, $availableWidth)
                        }
                        elseif ($windowWidth -lt 100)
                        {
                            $resolvedWidth = [Math]::Min($resolvedWidth, 16)
                        }
                    }
                }
            }
            catch
            {
                Write-Verbose "Unable to read host window width. Using requested bar width: $($_.Exception.Message)"
            }

            return [Math]::Max(10, $resolvedWidth)
        }

        function Format-Percent
        {
            param(
                [Parameter()]
                [Nullable[Double]]$Percent
            )

            if ($null -eq $Percent)
            {
                return '  n/a  '
            }

            $clamped = [Math]::Max(0, [Math]::Min(100, [Double]$Percent))
            return ('{0,6:N1}%' -f $clamped)
        }

        function Format-GiB
        {
            param(
                [Parameter()]
                [Nullable[Double]]$Value
            )

            if ($null -eq $Value)
            {
                return 'n/a'
            }

            return ('{0:N1}' -f [Double]$Value)
        }

        function Format-MiB
        {
            param(
                [Parameter()]
                [Nullable[Double]]$Value
            )

            if ($null -eq $Value)
            {
                return 'n/a'
            }

            return ('{0:N1}' -f [Double]$Value)
        }

        function Format-BytesPerSecond
        {
            param(
                [Parameter()]
                [Nullable[Double]]$Value
            )

            if ($null -eq $Value)
            {
                return 'n/a'
            }

            $bytesPerSecond = [Math]::Max(0.0, [Double]$Value)

            if ($bytesPerSecond -ge 1GB)
            {
                return ('{0:N2} GiB/s' -f ($bytesPerSecond / 1GB))
            }

            if ($bytesPerSecond -ge 1MB)
            {
                return ('{0:N2} MiB/s' -f ($bytesPerSecond / 1MB))
            }

            if ($bytesPerSecond -ge 1KB)
            {
                return ('{0:N1} KiB/s' -f ($bytesPerSecond / 1KB))
            }

            return ('{0:N0} B/s' -f $bytesPerSecond)
        }

        function Format-CpuCoreReadout
        {
            param(
                [Parameter()]
                [Nullable[Double]]$Percent
            )

            $logicalCoreCount = [Math]::Max(1, [Environment]::ProcessorCount)
            $totalCoreText = ('{0:N1}' -f [Double]$logicalCoreCount)

            if ($null -eq $Percent)
            {
                return ('n/a/{0} logical cores busy' -f $totalCoreText)
            }

            $clampedPercent = [Math]::Max(0, [Math]::Min(100, [Double]$Percent))
            $busyCoreCount = [Math]::Round(($clampedPercent / 100) * $logicalCoreCount, 1)
            $busyCoreText = ('{0:N1}' -f $busyCoreCount)

            return ('{0}/{1} logical cores busy' -f $busyCoreText, $totalCoreText)
        }

        function ConvertTo-RelativePercentHistory
        {
            param(
                [Parameter(Mandatory)]
                [Double[]]$Values
            )

            if ($Values.Count -eq 0)
            {
                return @()
            }

            $validValues = @($Values | Where-Object { -not [Double]::IsNaN($_) -and $_ -ge 0 })
            if ($validValues.Count -eq 0)
            {
                return @($Values | ForEach-Object { [Double]::NaN })
            }

            $peakValue = [Double](($validValues | Measure-Object -Maximum).Maximum)
            if ($peakValue -le 0)
            {
                return @(
                    $Values | ForEach-Object {
                        if ([Double]::IsNaN($_))
                        {
                            [Double]::NaN
                        }
                        else
                        {
                            0.0
                        }
                    }
                )
            }

            return @(
                $Values | ForEach-Object {
                    if ([Double]::IsNaN($_))
                    {
                        [Double]::NaN
                    }
                    else
                    {
                        [Math]::Round(([Double]$_ / $peakValue) * 100, 1)
                    }
                }
            )
        }

        function Get-NetworkActivityStatus
        {
            param(
                [Parameter()]
                [Nullable[Double]]$RelativePercent
            )

            if ($null -eq $RelativePercent)
            {
                return 'N/A'
            }

            $value = [Double]$RelativePercent
            if ($value -lt 10) { return 'IDLE' }
            if ($value -lt 60) { return 'LIVE' }
            return 'PEAK'
        }

        function Format-CpuSeconds
        {
            param(
                [Parameter()]
                [Nullable[Double]]$Value
            )

            if ($null -eq $Value)
            {
                return 'n/a'
            }

            return ('{0:N1}s' -f [Double]$Value)
        }

        function Format-DiskRootLabel
        {
            param(
                [Parameter()]
                [String]$Root
            )

            if ([String]::IsNullOrWhiteSpace($Root))
            {
                return 'n/a'
            }

            $trimmed = $Root.Trim()
            if ($trimmed -eq '/')
            {
                return '/ (root fs)'
            }

            return $trimmed
        }

        function Get-UsageColor
        {
            param(
                [Parameter()]
                [Nullable[Double]]$Percent
            )

            if (-not $supportsAnsi -or $null -eq $Percent)
            {
                return ''
            }

            $value = [Double]$Percent
            if ($value -lt 60) { return "$([char]27)[32m" }
            if ($value -lt 85) { return "$([char]27)[33m" }
            return "$([char]27)[31m"
        }

        function Add-Color
        {
            param(
                [Parameter(Mandatory)]
                [String]$Text,

                [Parameter()]
                [Nullable[Double]]$Percent
            )

            if (-not $supportsAnsi)
            {
                return $Text
            }

            $color = Get-UsageColor -Percent $Percent
            if ([String]::IsNullOrWhiteSpace($color))
            {
                return $Text
            }

            return $color + $Text + $ansiReset
        }

        function Add-SubtleText
        {
            param(
                [Parameter(Mandatory)]
                [String]$Text
            )

            if (-not $supportsAnsi)
            {
                return $Text
            }

            $darkGray = "$([char]27)[90m"
            return $darkGray + $Text + $ansiReset
        }

        function Test-ProcessNameFilterMatch
        {
            param(
                [Parameter()]
                [String]$ProcessName,

                [Parameter()]
                [String[]]$NameFilters
            )

            $candidateName = if ([String]::IsNullOrWhiteSpace($ProcessName)) { '' } else { [String]$ProcessName }

            $effectiveNameFilters = @(
                @($NameFilters) |
                Where-Object { -not [String]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { $_.Trim() }
            )

            if ($effectiveNameFilters.Count -eq 0)
            {
                return $true
            }

            foreach ($filterPattern in $effectiveNameFilters)
            {
                if ($candidateName -like $filterPattern)
                {
                    return $true
                }
            }

            return $false
        }

        function Get-ProcessScopeUsageInfo
        {
            param(
                [Parameter(Mandatory)]
                [String[]]$NameFilters,

                [Parameter(Mandatory)]
                [hashtable]$CpuState
            )

            $matchedProcesses = New-Object 'System.Collections.Generic.List[PSCustomObject]'

            foreach ($process in (Get-Process -ErrorAction SilentlyContinue))
            {
                $processName = if ([String]::IsNullOrWhiteSpace($process.ProcessName)) { '' } else { [String]$process.ProcessName }
                if (-not (Test-ProcessNameFilterMatch -ProcessName $processName -NameFilters $NameFilters))
                {
                    continue
                }

                $cpuSeconds = $null
                $workingSetBytes = $null

                try
                {
                    if ($null -ne $process.CPU)
                    {
                        $cpuSeconds = [Double]$process.CPU
                    }
                }
                catch
                {
                    Write-Verbose "Unable to read CPU time for process $($process.Id): $($_.Exception.Message)"
                }

                try
                {
                    if ($null -ne $process.WorkingSet64)
                    {
                        $workingSetBytes = [Double]$process.WorkingSet64
                    }
                }
                catch
                {
                    Write-Verbose "Unable to read memory usage for process $($process.Id): $($_.Exception.Message)"
                }

                [void]$matchedProcesses.Add([PSCustomObject]@{
                    Name = if ([String]::IsNullOrWhiteSpace($processName)) { '<unknown>' } else { $processName }
                    CpuSeconds = $cpuSeconds
                    WorkingSetBytes = $workingSetBytes
                })
            }

            $totalCpuSeconds = 0.0
            $hasCpuSample = $false
            $totalWorkingSetBytes = 0.0
            $hasWorkingSetSample = $false

            foreach ($processInfo in $matchedProcesses)
            {
                if ($null -ne $processInfo.CpuSeconds)
                {
                    $totalCpuSeconds += [Double]$processInfo.CpuSeconds
                    $hasCpuSample = $true
                }

                if ($null -ne $processInfo.WorkingSetBytes)
                {
                    $totalWorkingSetBytes += [Double]$processInfo.WorkingSetBytes
                    $hasWorkingSetSample = $true
                }
            }

            $systemMemoryInfo = Get-MemoryUsageInfo
            $memoryTotalGiB = $null
            $memoryTotalBytes = $null
            if ($null -ne $systemMemoryInfo.TotalBytes -and [Double]$systemMemoryInfo.TotalBytes -gt 0)
            {
                $memoryTotalBytes = [Double]$systemMemoryInfo.TotalBytes
                $memoryTotalGiB = [Math]::Round($memoryTotalBytes / 1GB, 2)
            }

            if ($matchedProcesses.Count -eq 0)
            {
                $CpuState.Timestamp = $null
                $CpuState.TotalCpuSeconds = $null

                return @{
                    CpuPercent = 0.0
                    MemoryPercent = if ($null -eq $memoryTotalBytes) { $null } else { 0.0 }
                    MemoryUsedGiB = 0.0
                    MemoryTotalGiB = $memoryTotalGiB
                    MatchedProcessCount = 0
                }
            }

            $now = Get-Date
            $cpuPercent = $null

            if ($hasCpuSample -and $null -ne $CpuState.Timestamp -and $null -ne $CpuState.TotalCpuSeconds)
            {
                $elapsedSeconds = ($now - [DateTime]$CpuState.Timestamp).TotalSeconds
                if ($elapsedSeconds -gt 0)
                {
                    $cpuDelta = $totalCpuSeconds - [Double]$CpuState.TotalCpuSeconds
                    if ($cpuDelta -lt 0)
                    {
                        $cpuDelta = 0
                    }

                    $processorCount = [Math]::Max(1, [Environment]::ProcessorCount)
                    $cpuPercent = (($cpuDelta / ($elapsedSeconds * $processorCount)) * 100)
                    $cpuPercent = [Math]::Round([Math]::Max(0, [Math]::Min(100, $cpuPercent)), 1)
                }
            }

            $CpuState.Timestamp = $now
            $CpuState.TotalCpuSeconds = if ($hasCpuSample) { $totalCpuSeconds } else { $null }

            $memoryPercent = $null
            $memoryUsedGiB = $null

            if ($hasWorkingSetSample)
            {
                $memoryUsedGiB = [Math]::Round([Math]::Max(0.0, $totalWorkingSetBytes) / 1GB, 2)
            }

            if ($null -ne $memoryTotalBytes)
            {
                if ($hasWorkingSetSample)
                {
                    $memoryPercentRaw = ($totalWorkingSetBytes / $memoryTotalBytes) * 100
                    $memoryPercent = [Math]::Round([Math]::Max(0, [Math]::Min(100, $memoryPercentRaw)), 1)
                }
            }

            return @{
                CpuPercent = $cpuPercent
                MemoryPercent = $memoryPercent
                MemoryUsedGiB = $memoryUsedGiB
                MemoryTotalGiB = $memoryTotalGiB
                MatchedProcessCount = $matchedProcesses.Count
            }
        }

        function Get-CpuUsagePercentFallback
        {
            param(
                [Parameter(Mandatory)]
                [hashtable]$State
            )

            $totalCpuSeconds = 0.0
            foreach ($process in (Get-Process -ErrorAction SilentlyContinue))
            {
                try
                {
                    if ($null -ne $process.CPU)
                    {
                        $totalCpuSeconds += [Double]$process.CPU
                    }
                }
                catch
                {
                    # Keep sampling resilient when process metadata is inaccessible.
                    Write-Verbose "Skipping process CPU sample due to access error: $($_.Exception.Message)"
                }
            }

            $now = Get-Date
            $usage = $null

            if ($null -ne $State.Timestamp -and $null -ne $State.TotalCpuSeconds)
            {
                $elapsedSeconds = ($now - [DateTime]$State.Timestamp).TotalSeconds
                if ($elapsedSeconds -gt 0)
                {
                    $cpuDelta = $totalCpuSeconds - [Double]$State.TotalCpuSeconds
                    if ($cpuDelta -lt 0)
                    {
                        $cpuDelta = 0
                    }

                    $processorCount = [Math]::Max(1, [Environment]::ProcessorCount)
                    $usage = (($cpuDelta / ($elapsedSeconds * $processorCount)) * 100)
                    $usage = [Math]::Round([Math]::Max(0, [Math]::Min(100, $usage)), 1)
                }
            }

            $State.Timestamp = $now
            $State.TotalCpuSeconds = $totalCpuSeconds
            return $usage
        }

        function Get-CpuUsagePercent
        {
            param(
                [Parameter(Mandatory)]
                [hashtable]$FallbackState
            )

            if ($isWindowsPlatform)
            {
                try
                {
                    if (Get-Command -Name Get-Counter -ErrorAction SilentlyContinue)
                    {
                        $counter = Get-Counter -Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
                        $sample = $counter.CounterSamples | Select-Object -First 1
                        if ($sample -and $sample.CookedValue -ge 0)
                        {
                            return [Math]::Round([Double]$sample.CookedValue, 1)
                        }
                    }
                }
                catch
                {
                    Write-Verbose "Windows CPU counter read failed, using fallback: $($_.Exception.Message)"
                }
            }

            if ($isLinuxPlatform -and (Test-Path -LiteralPath '/proc/stat'))
            {
                try
                {
                    $first = Get-Content -LiteralPath '/proc/stat' -TotalCount 1 -ErrorAction Stop
                    Start-Sleep -Milliseconds 200
                    $second = Get-Content -LiteralPath '/proc/stat' -TotalCount 1 -ErrorAction Stop

                    $firstParts = $first -split '\s+' | Where-Object { $_ -ne '' }
                    $secondParts = $second -split '\s+' | Where-Object { $_ -ne '' }

                    if ($firstParts.Count -ge 5 -and $secondParts.Count -ge 5)
                    {
                        $firstValues = for ($i = 1; $i -lt $firstParts.Count; $i++) { [Double]$firstParts[$i] }
                        $secondValues = for ($i = 1; $i -lt $secondParts.Count; $i++) { [Double]$secondParts[$i] }

                        $firstIdle = $firstValues[3]
                        if ($firstValues.Count -gt 4) { $firstIdle += $firstValues[4] }

                        $secondIdle = $secondValues[3]
                        if ($secondValues.Count -gt 4) { $secondIdle += $secondValues[4] }

                        $firstTotal = ($firstValues | Measure-Object -Sum).Sum
                        $secondTotal = ($secondValues | Measure-Object -Sum).Sum

                        $totalDelta = $secondTotal - $firstTotal
                        $idleDelta = $secondIdle - $firstIdle

                        if ($totalDelta -gt 0)
                        {
                            $usage = (1 - ($idleDelta / $totalDelta)) * 100
                            return [Math]::Round([Math]::Max(0, [Math]::Min(100, $usage)), 1)
                        }
                    }
                }
                catch
                {
                    Write-Verbose "Linux CPU read from /proc/stat failed, using fallback: $($_.Exception.Message)"
                }
            }

            if ($isMacOSPlatform)
            {
                try
                {
                    $topOutput = top -l 1 2>$null
                    $cpuLine = $topOutput | Where-Object { $_ -match 'CPU usage' } | Select-Object -First 1
                    if ($cpuLine -and $cpuLine -match '([0-9]+(?:\.[0-9]+)?)%\s*idle')
                    {
                        $idle = [Double]$matches[1]
                        $usage = 100 - $idle
                        return [Math]::Round([Math]::Max(0, [Math]::Min(100, $usage)), 1)
                    }
                }
                catch
                {
                    Write-Verbose "macOS CPU read from top failed, using fallback: $($_.Exception.Message)"
                }
            }

            return Get-CpuUsagePercentFallback -State $FallbackState
        }

        function Get-MemoryUsageInfo
        {
            $totalBytes = $null
            $freeBytes = $null

            if ($isWindowsPlatform)
            {
                try
                {
                    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                    $totalBytes = [Double]([Int64]$os.TotalVisibleMemorySize * 1KB)
                    $freeBytes = [Double]([Int64]$os.FreePhysicalMemory * 1KB)
                }
                catch
                {
                    Write-Verbose "Windows memory read failed: $($_.Exception.Message)"
                }
            }
            elseif ($isLinuxPlatform -and (Test-Path -LiteralPath '/proc/meminfo'))
            {
                try
                {
                    $memInfo = Get-Content -LiteralPath '/proc/meminfo' -ErrorAction Stop
                    $memMap = @{}

                    foreach ($line in $memInfo)
                    {
                        if ($line -match '^(?<Key>\w+):\s+(?<Value>\d+)')
                        {
                            $memMap[$matches.Key] = [Double]$matches.Value * 1KB
                        }
                    }

                    if ($memMap.ContainsKey('MemTotal'))
                    {
                        $totalBytes = $memMap['MemTotal']
                    }

                    if ($memMap.ContainsKey('MemAvailable'))
                    {
                        $freeBytes = $memMap['MemAvailable']
                    }
                    elseif ($memMap.ContainsKey('MemFree'))
                    {
                        $freeBytes = $memMap['MemFree']
                    }
                }
                catch
                {
                    Write-Verbose "Linux memory read failed: $($_.Exception.Message)"
                }
            }
            elseif ($isMacOSPlatform)
            {
                try
                {
                    $totalMemText = sysctl -n hw.memsize 2>$null
                    if ($totalMemText -and $totalMemText -match '^\d+$')
                    {
                        $totalBytes = [Double][Int64]$totalMemText
                    }

                    $vmStatOutput = vm_stat 2>$null
                    if ($vmStatOutput)
                    {
                        $pageSize = 4096
                        foreach ($line in $vmStatOutput)
                        {
                            if ($line -match 'page size of (\d+) bytes')
                            {
                                $pageSize = [Int32]$matches[1]
                                break
                            }
                        }

                        $pageValues = @{}
                        $trackedKeys = @(
                            'Pages free',
                            'Pages active',
                            'Pages inactive',
                            'Pages speculative',
                            'Pages wired down',
                            'Pages occupied by compressor',
                            'Pages purgeable'
                        )

                        foreach ($key in $trackedKeys)
                        {
                            $pattern = '^' + [Regex]::Escape($key) + ':\s+(\d+)\.'
                            $line = $vmStatOutput | Where-Object { $_ -match $pattern } | Select-Object -First 1
                            if ($line -and $line -match $pattern)
                            {
                                $pageValues[$key] = [Double]$matches[1]
                            }
                        }

                        $availablePages = 0.0
                        $availablePageKeys = @('Pages free', 'Pages inactive', 'Pages speculative', 'Pages purgeable')
                        foreach ($key in $availablePageKeys)
                        {
                            if ($pageValues.ContainsKey($key))
                            {
                                $availablePages += $pageValues[$key]
                            }
                        }

                        if ($availablePages -gt 0)
                        {
                            $freeBytes = $availablePages * $pageSize
                        }

                        # Fallback total-memory estimate when sysctl is unavailable/restricted.
                        if ($null -eq $totalBytes -or $totalBytes -le 0)
                        {
                            $totalPages = 0.0
                            $totalPageKeys = @(
                                'Pages free',
                                'Pages active',
                                'Pages inactive',
                                'Pages speculative',
                                'Pages wired down',
                                'Pages occupied by compressor'
                            )

                            foreach ($key in $totalPageKeys)
                            {
                                if ($pageValues.ContainsKey($key))
                                {
                                    $totalPages += $pageValues[$key]
                                }
                            }

                            if ($totalPages -gt 0)
                            {
                                $totalBytes = $totalPages * $pageSize
                            }
                        }
                    }
                }
                catch
                {
                    Write-Verbose "macOS memory read failed: $($_.Exception.Message)"
                }
            }

            if ($null -eq $totalBytes -or $totalBytes -le 0 -or $null -eq $freeBytes)
            {
                return @{
                    Percent = $null
                    UsedGiB = $null
                    TotalGiB = $null
                    UsedBytes = $null
                    TotalBytes = $null
                }
            }

            $usedBytes = [Math]::Max(0.0, $totalBytes - $freeBytes)
            $percent = ($usedBytes / $totalBytes) * 100

            return @{
                Percent = [Math]::Round([Math]::Max(0, [Math]::Min(100, $percent)), 1)
                UsedGiB = [Math]::Round($usedBytes / 1GB, 2)
                TotalGiB = [Math]::Round($totalBytes / 1GB, 2)
                UsedBytes = [Math]::Round($usedBytes, 0)
                TotalBytes = [Math]::Round($totalBytes, 0)
            }
        }

        function Get-SystemDriveUsageInfo
        {
            try
            {
                $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady })
                if ($drives.Count -eq 0)
                {
                    return @{
                        Percent = $null
                        UsedGiB = $null
                        TotalGiB = $null
                        Root = $null
                    }
                }

                $drive = $null
                if ($isWindowsPlatform)
                {
                    $systemDrive = if ([String]::IsNullOrWhiteSpace($env:SystemDrive)) { 'C:' } else { $env:SystemDrive.TrimEnd('\') }
                    $drive = $drives | Where-Object { $_.Name.TrimEnd('\') -eq $systemDrive } | Select-Object -First 1
                }
                else
                {
                    $drive = $drives | Where-Object { $_.Name -eq '/' } | Select-Object -First 1
                }

                if (-not $drive)
                {
                    $drive = $drives | Sort-Object -Property TotalSize -Descending | Select-Object -First 1
                }

                $totalBytes = [Double]$drive.TotalSize
                $freeBytes = [Double]$drive.AvailableFreeSpace
                $usedBytes = [Math]::Max(0.0, $totalBytes - $freeBytes)
                $percent = if ($totalBytes -gt 0) { ($usedBytes / $totalBytes) * 100 } else { $null }

                return @{
                    Percent = if ($null -eq $percent) { $null } else { [Math]::Round([Math]::Max(0, [Math]::Min(100, $percent)), 1) }
                    UsedGiB = [Math]::Round($usedBytes / 1GB, 2)
                    TotalGiB = [Math]::Round($totalBytes / 1GB, 2)
                    Root = $drive.Name
                }
            }
            catch
            {
                Write-Verbose "Disk usage read failed: $($_.Exception.Message)"
                return @{
                    Percent = $null
                    UsedGiB = $null
                    TotalGiB = $null
                    Root = $null
                }
            }
        }

        function Get-NetworkActivityInfo
        {
            param(
                [Parameter(Mandatory)]
                [hashtable]$State
            )

            try
            {
                $activeInterfaces = @(
                    [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
                    Where-Object {
                        $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up -and
                        $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback -and
                        $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel
                    }
                )

                if ($activeInterfaces.Count -eq 0)
                {
                    $State.Timestamp = $null
                    $State.TotalBytesReceived = $null
                    $State.TotalBytesSent = $null

                    return @{
                        ReceiveBytesPerSecond = $null
                        SendBytesPerSecond = $null
                        TotalBytesPerSecond = $null
                        ActiveInterfaces = 0
                    }
                }

                $totalBytesReceived = 0.0
                $totalBytesSent = 0.0
                $sampledInterfaceCount = 0

                foreach ($networkInterface in $activeInterfaces)
                {
                    try
                    {
                        $interfaceStats = $null
                        try
                        {
                            $interfaceStats = $networkInterface.GetIPStatistics()
                        }
                        catch
                        {
                            $interfaceStats = $null
                        }

                        if ($null -eq $interfaceStats)
                        {
                            $interfaceStats = $networkInterface.GetIPv4Statistics()
                        }

                        if ($null -ne $interfaceStats)
                        {
                            $totalBytesReceived += [Double]$interfaceStats.BytesReceived
                            $totalBytesSent += [Double]$interfaceStats.BytesSent
                            $sampledInterfaceCount++
                        }
                    }
                    catch
                    {
                        Write-Verbose "Skipping network interface sample for $($networkInterface.Name): $($_.Exception.Message)"
                    }
                }

                if ($sampledInterfaceCount -eq 0)
                {
                    $State.Timestamp = $null
                    $State.TotalBytesReceived = $null
                    $State.TotalBytesSent = $null

                    return @{
                        ReceiveBytesPerSecond = $null
                        SendBytesPerSecond = $null
                        TotalBytesPerSecond = $null
                        ActiveInterfaces = 0
                    }
                }

                $now = Get-Date
                $receiveBytesPerSecond = $null
                $sendBytesPerSecond = $null
                $totalBytesPerSecond = $null

                if ($null -ne $State.Timestamp -and $null -ne $State.TotalBytesReceived -and $null -ne $State.TotalBytesSent)
                {
                    $elapsedSeconds = ($now - [DateTime]$State.Timestamp).TotalSeconds
                    if ($elapsedSeconds -gt 0)
                    {
                        $receivedDelta = [Math]::Max(0.0, $totalBytesReceived - [Double]$State.TotalBytesReceived)
                        $sentDelta = [Math]::Max(0.0, $totalBytesSent - [Double]$State.TotalBytesSent)

                        $receiveBytesPerSecond = [Math]::Round($receivedDelta / $elapsedSeconds, 1)
                        $sendBytesPerSecond = [Math]::Round($sentDelta / $elapsedSeconds, 1)
                        $totalBytesPerSecond = [Math]::Round($receiveBytesPerSecond + $sendBytesPerSecond, 1)
                    }
                }

                $State.Timestamp = $now
                $State.TotalBytesReceived = $totalBytesReceived
                $State.TotalBytesSent = $totalBytesSent

                return @{
                    ReceiveBytesPerSecond = if ($null -eq $receiveBytesPerSecond) { $null } else { [Math]::Max(0.0, [Double]$receiveBytesPerSecond) }
                    SendBytesPerSecond = if ($null -eq $sendBytesPerSecond) { $null } else { [Math]::Max(0.0, [Double]$sendBytesPerSecond) }
                    TotalBytesPerSecond = if ($null -eq $totalBytesPerSecond) { $null } else { [Math]::Max(0.0, [Double]$totalBytesPerSecond) }
                    ActiveInterfaces = $sampledInterfaceCount
                }
            }
            catch
            {
                Write-Verbose "Network activity read failed: $($_.Exception.Message)"

                $State.Timestamp = $null
                $State.TotalBytesReceived = $null
                $State.TotalBytesSent = $null

                return @{
                    ReceiveBytesPerSecond = $null
                    SendBytesPerSecond = $null
                    TotalBytesPerSecond = $null
                    ActiveInterfaces = 0
                }
            }
        }

        function Get-TopProcessInfo
        {
            param(
                [Parameter(Mandatory)]
                [Int32]$Count,

                [Parameter()]
                [String[]]$NameFilters
            )

            try
            {
                $effectiveNameFilters = @(
                    @($NameFilters) |
                    Where-Object { -not [String]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object { $_.Trim() }
                )

                $processes = @(
                    Get-Process -ErrorAction SilentlyContinue |
                    Where-Object {
                        Test-ProcessNameFilterMatch -ProcessName $_.ProcessName -NameFilters $effectiveNameFilters
                    } |
                    ForEach-Object {
                        $cpuSeconds = $null
                        $workingSetBytes = $null

                        try
                        {
                            if ($null -ne $_.CPU)
                            {
                                $cpuSeconds = [Double]$_.CPU
                            }
                        }
                        catch
                        {
                            Write-Verbose "Unable to read CPU time for process $($_.Id): $($_.Exception.Message)"
                        }

                        try
                        {
                            if ($null -ne $_.WorkingSet64)
                            {
                                $workingSetBytes = [Double]$_.WorkingSet64
                            }
                        }
                        catch
                        {
                            Write-Verbose "Unable to read memory usage for process $($_.Id): $($_.Exception.Message)"
                        }

                        [PSCustomObject]@{
                            Name = if ([String]::IsNullOrWhiteSpace($_.ProcessName)) { '<unknown>' } else { $_.ProcessName }
                            Id = [Int32]$_.Id
                            CpuSeconds = if ($null -eq $cpuSeconds) { $null } else { [Math]::Round([Math]::Max(0, $cpuSeconds), 1) }
                            WorkingSetMiB = if ($null -eq $workingSetBytes) { $null } else { [Math]::Round([Math]::Max(0, $workingSetBytes) / 1MB, 1) }
                            _SortCpu = if ($null -eq $cpuSeconds) { -1.0 } else { $cpuSeconds }
                            _SortMemory = if ($null -eq $workingSetBytes) { -1.0 } else { $workingSetBytes }
                        }
                    } |
                    Sort-Object -Property @{ Expression = '_SortCpu'; Descending = $true }, @{ Expression = '_SortMemory'; Descending = $true }, @{ Expression = 'Name'; Descending = $false } |
                    Select-Object -First $Count
                )

                if ($processes.Count -eq 0)
                {
                    return @()
                }

                return @(
                    $processes | ForEach-Object {
                        [PSCustomObject]@{
                            Name = $_.Name
                            Id = $_.Id
                            CpuSeconds = $_.CpuSeconds
                            WorkingSetMiB = $_.WorkingSetMiB
                        }
                    }
                )
            }
            catch
            {
                Write-Verbose "Top process sample failed: $($_.Exception.Message)"
                return @()
            }
        }

        function Get-SystemResourceSample
        {
            $collectStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $isProcessScoped = ($monitorProcessNameFilters.Count -gt 0)
            $matchedProcessCount = $null

            if ($isProcessScoped)
            {
                $scopedUsage = Get-ProcessScopeUsageInfo -NameFilters $monitorProcessNameMatchFilters -CpuState $processScopeCpuState
                $cpuPercent = $scopedUsage.CpuPercent
                if ($null -eq $cpuPercent)
                {
                    Start-Sleep -Milliseconds 200
                    $scopedUsage = Get-ProcessScopeUsageInfo -NameFilters $monitorProcessNameMatchFilters -CpuState $processScopeCpuState
                    $cpuPercent = $scopedUsage.CpuPercent
                }

                $memory = @{
                    Percent = $scopedUsage.MemoryPercent
                    UsedGiB = $scopedUsage.MemoryUsedGiB
                    TotalGiB = $scopedUsage.MemoryTotalGiB
                }

                # Per-process disk/network attribution is not available consistently across platforms.
                # In process-scoped mode these charts are intentionally reported as n/a.
                $disk = @{
                    Percent = $null
                    UsedGiB = $null
                    TotalGiB = $null
                    Root = $null
                }
                $network = @{
                    ReceiveBytesPerSecond = $null
                    SendBytesPerSecond = $null
                    TotalBytesPerSecond = $null
                    ActiveInterfaces = 0
                }

                $networkActivityState.Timestamp = $null
                $networkActivityState.TotalBytesReceived = $null
                $networkActivityState.TotalBytesSent = $null
                $matchedProcessCount = [Int32]$scopedUsage.MatchedProcessCount
            }
            else
            {
                $cpuPercent = Get-CpuUsagePercent -FallbackState $cpuFallbackState
                if ($null -eq $cpuPercent)
                {
                    Start-Sleep -Milliseconds 200
                    $cpuPercent = Get-CpuUsagePercent -FallbackState $cpuFallbackState
                }

                $memory = Get-MemoryUsageInfo
                $disk = Get-SystemDriveUsageInfo
                $network = Get-NetworkActivityInfo -State $networkActivityState
                if ($null -eq $network.TotalBytesPerSecond)
                {
                    Start-Sleep -Milliseconds 200
                    $network = Get-NetworkActivityInfo -State $networkActivityState
                }
            }

            $topProcesses = @()
            if ($IncludeTopProcesses)
            {
                $topProcesses = @(Get-TopProcessInfo -Count $TopProcessCount -NameFilters $effectiveTopProcessNameMatchFilters)
            }

            $overallLoad = Get-OverallLoadPercent -CpuPercent $cpuPercent -MemoryPercent $memory.Percent -DiskPercent $disk.Percent
            $healthGrade = Get-ResourceHealthGrade -CpuPercent $cpuPercent -MemoryPercent $memory.Percent -DiskPercent $disk.Percent -OverallLoadPercent $overallLoad
            $findings = @(Get-ResourceFindings -CpuPercent $cpuPercent -MemoryPercent $memory.Percent -DiskPercent $disk.Percent)

            $collectStopwatch.Stop()

            $sample = [PSCustomObject]@{
                Timestamp = Get-Date
                Platform = $platformName
                CpuUsagePercent = $cpuPercent
                MemoryUsagePercent = $memory.Percent
                MemoryUsedGiB = $memory.UsedGiB
                MemoryTotalGiB = $memory.TotalGiB
                DiskUsagePercent = $disk.Percent
                DiskUsedGiB = $disk.UsedGiB
                DiskTotalGiB = $disk.TotalGiB
                DiskRoot = $disk.Root
                NetworkReceiveBytesPerSecond = $network.ReceiveBytesPerSecond
                NetworkSendBytesPerSecond = $network.SendBytesPerSecond
                NetworkTotalBytesPerSecond = $network.TotalBytesPerSecond
                NetworkActiveInterfaces = $network.ActiveInterfaces
                OverallLoadPercent = $overallLoad
                OverallStatus = Get-UsageStatus -Percent $overallLoad
                HealthGrade = $healthGrade
                HealthIcon = Get-HealthStatusIcon -Grade $healthGrade
                Findings = $findings
                CollectMs = [Math]::Round($collectStopwatch.Elapsed.TotalMilliseconds, 1)
            }

            if ($IncludeTopProcesses)
            {
                $sample | Add-Member -NotePropertyName 'TopProcesses' -NotePropertyValue $topProcesses
            }

            if ($isProcessScoped)
            {
                $sample | Add-Member -NotePropertyName 'MonitorProcessName' -NotePropertyValue @($monitorProcessNameFilters)
                $sample | Add-Member -NotePropertyName 'MonitorProcessMatchCount' -NotePropertyValue $matchedProcessCount
            }

            return $sample
        }

        function Format-DashboardText
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Sample,

                [Parameter()]
                [Switch]$IncludeContinuousHint
            )

            $maxHistoryPoints = [Math]::Min(40, [Math]::Max(8, $HistoryLength))

            $cpuHistoryValues = @($cpuHistory.ToArray())
            if ($cpuHistoryValues.Count -gt $maxHistoryPoints)
            {
                $cpuHistoryValues = $cpuHistoryValues[($cpuHistoryValues.Count - $maxHistoryPoints)..($cpuHistoryValues.Count - 1)]
            }

            $memoryHistoryValues = @($memoryHistory.ToArray())
            if ($memoryHistoryValues.Count -gt $maxHistoryPoints)
            {
                $memoryHistoryValues = $memoryHistoryValues[($memoryHistoryValues.Count - $maxHistoryPoints)..($memoryHistoryValues.Count - 1)]
            }

            $diskHistoryValues = @($diskHistory.ToArray())
            if ($diskHistoryValues.Count -gt $maxHistoryPoints)
            {
                $diskHistoryValues = $diskHistoryValues[($diskHistoryValues.Count - $maxHistoryPoints)..($diskHistoryValues.Count - 1)]
            }

            $networkThroughputHistoryValues = @($networkThroughputHistory.ToArray())
            if ($networkThroughputHistoryValues.Count -gt $maxHistoryPoints)
            {
                $networkThroughputHistoryValues = $networkThroughputHistoryValues[($networkThroughputHistoryValues.Count - $maxHistoryPoints)..($networkThroughputHistoryValues.Count - 1)]
            }
            $networkRelativeHistoryValues = @(ConvertTo-RelativePercentHistory -Values $networkThroughputHistoryValues)

            $renderedBarWidth = Get-ResolvedBarWidth -RequestedWidth $BarWidth -RenderedHistoryLength $maxHistoryPoints

            $formatMetricLine = {
                param(
                    [Parameter(Mandatory)]
                    [String]$Name,

                    [Parameter()]
                    [Nullable[Double]]$Percent,

                    [Parameter(Mandatory)]
                    [Double[]]$History,

                    [Parameter()]
                    [String]$Details,

                    [Parameter()]
                    [ScriptBlock]$StatusResolver = { param([Nullable[Double]]$StatusPercent) Get-UsageStatus -Percent $StatusPercent },

                    [Parameter()]
                    [Switch]$UseZeroFillWhenUnavailable,

                    [Parameter()]
                    [Switch]$RenderUnavailableAsSubtle
                )

                $barText = ConvertTo-UsageBar -Percent $Percent -Width $renderedBarWidth -UseZeroFillWhenUnknown:$UseZeroFillWhenUnavailable
                $percentText = Format-Percent -Percent $Percent
                $resolvedStatus = & $StatusResolver $Percent
                if ([String]::IsNullOrWhiteSpace([String]$resolvedStatus))
                {
                    $resolvedStatus = 'N/A'
                }

                $statusText = ('{0,-5}' -f [String]$resolvedStatus)
                $trendText = Get-TrendIndicator -Values $History
                $sparkText = ConvertTo-Sparkline -Values $History

                $line = '{0,-7} {1} {2} {3} {4} {5}' -f $Name, $barText, $percentText, $statusText, $trendText, $sparkText
                if (-not [String]::IsNullOrWhiteSpace($Details))
                {
                    $line = $line + '  ' + $Details
                }

                $coloredLine = Add-Color -Text $line -Percent $Percent
                if ($RenderUnavailableAsSubtle -and $null -eq $Percent)
                {
                    return Add-SubtleText -Text $coloredLine
                }

                return $coloredLine
            }

            $cpuDetails = Format-CpuCoreReadout -Percent $Sample.CpuUsagePercent
            $memoryDetails = '{0}/{1} GiB' -f (Format-GiB -Value $Sample.MemoryUsedGiB), (Format-GiB -Value $Sample.MemoryTotalGiB)
            $diskRoot = Format-DiskRootLabel -Root $Sample.DiskRoot
            $diskDetails = '{0}/{1} GiB on {2}' -f (Format-GiB -Value $Sample.DiskUsedGiB), (Format-GiB -Value $Sample.DiskTotalGiB), $diskRoot
            $networkReceiveText = Format-BytesPerSecond -Value $Sample.NetworkReceiveBytesPerSecond
            $networkSendText = Format-BytesPerSecond -Value $Sample.NetworkSendBytesPerSecond
            $networkTotalText = Format-BytesPerSecond -Value $Sample.NetworkTotalBytesPerSecond
            $networkDetails = "In $networkReceiveText | Out $networkSendText | Total $networkTotalText"

            $networkActivityPercent = $null
            $networkValidHistory = @($networkRelativeHistoryValues | Where-Object { -not [Double]::IsNaN($_) })
            if ($networkValidHistory.Count -eq 0)
            {
                $networkRelativeHistoryValues = @($networkThroughputHistoryValues | ForEach-Object { [Double]::NaN })
            }
            elseif ($networkValidHistory.Count -lt 2)
            {
                # For single-snapshot views, render network as idle instead of unknown.
                $networkActivityPercent = 0.0
                $networkRelativeHistoryValues = @(
                    $networkThroughputHistoryValues | ForEach-Object {
                        if ([Double]::IsNaN($_))
                        {
                            [Double]::NaN
                        }
                        else
                        {
                            0.0
                        }
                    }
                )
            }
            else
            {
                $networkActivityPercent = [Double]$networkValidHistory[-1]
            }

            $cpuLine = & $formatMetricLine -Name 'CPU' -Percent $Sample.CpuUsagePercent -History $cpuHistoryValues -Details $cpuDetails
            $memoryLine = & $formatMetricLine -Name 'Memory' -Percent $Sample.MemoryUsagePercent -History $memoryHistoryValues -Details $memoryDetails
            $diskLine = & $formatMetricLine -Name 'Disk' -Percent $Sample.DiskUsagePercent -History $diskHistoryValues -Details $diskDetails -UseZeroFillWhenUnavailable -RenderUnavailableAsSubtle
            $networkLine = & $formatMetricLine -Name 'Network' -Percent $networkActivityPercent -History $networkRelativeHistoryValues -Details $networkDetails -StatusResolver { param([Nullable[Double]]$Percent) Get-NetworkActivityStatus -RelativePercent $Percent } -UseZeroFillWhenUnavailable -RenderUnavailableAsSubtle

            $overallLoad = $null
            if ($Sample.PSObject.Properties.Name -contains 'OverallLoadPercent' -and $null -ne $Sample.OverallLoadPercent)
            {
                $overallLoad = [Math]::Round([Double]$Sample.OverallLoadPercent, 1)
            }
            else
            {
                $overallLoad = Get-OverallLoadPercent -CpuPercent $Sample.CpuUsagePercent -MemoryPercent $Sample.MemoryUsagePercent -DiskPercent $Sample.DiskUsagePercent
            }

            $overallStatus = if ($Sample.PSObject.Properties.Name -contains 'OverallStatus' -and -not [String]::IsNullOrWhiteSpace([String]$Sample.OverallStatus))
            {
                [String]$Sample.OverallStatus
            }
            else
            {
                Get-UsageStatus -Percent $overallLoad
            }

            $healthGrade = if ($Sample.PSObject.Properties.Name -contains 'HealthGrade' -and -not [String]::IsNullOrWhiteSpace([String]$Sample.HealthGrade))
            {
                [String]$Sample.HealthGrade
            }
            else
            {
                Get-ResourceHealthGrade -CpuPercent $Sample.CpuUsagePercent -MemoryPercent $Sample.MemoryUsagePercent -DiskPercent $Sample.DiskUsagePercent -OverallLoadPercent $overallLoad
            }

            $statusIcon = if ($Sample.PSObject.Properties.Name -contains 'HealthIcon' -and -not [String]::IsNullOrWhiteSpace([String]$Sample.HealthIcon))
            {
                [String]$Sample.HealthIcon
            }
            else
            {
                Get-HealthStatusIcon -Grade $healthGrade
            }

            $collectText = 'n/a'
            if ($Sample.PSObject.Properties.Name -contains 'CollectMs' -and $null -ne $Sample.CollectMs)
            {
                $collectText = ('{0:N1}ms' -f [Double]$Sample.CollectMs)
            }

            if ($supportsUnicode)
            {
                $dividerChar = [String][char]0x2500
                $statusSeparator = [String][char]0x2502
            }
            else
            {
                $dividerChar = '-'
                $statusSeparator = '|'
            }

            $divider = $dividerChar * [Math]::Max(70, $renderedBarWidth + $maxHistoryPoints + 35)
            $gradeText = Format-HealthGrade -Grade $healthGrade
            $overallSummaryPlain = ('{0} {1} [{2}] {3}' -f (Format-Percent -Percent $overallLoad).Trim(), $overallStatus, $healthGrade, $statusIcon)
            $overallSummaryDisplay = ('{0} {1} [{2}] {3}' -f (Format-Percent -Percent $overallLoad).Trim(), $overallStatus, $gradeText, $statusIcon)
            $titleText = 'System Resource Monitor'

            $titleLine = $titleText
            $titlePadding = $divider.Length - $titleText.Length - $overallSummaryPlain.Length
            if ($titlePadding -ge 2)
            {
                $titleLine = $titleText + (' ' * $titlePadding) + $overallSummaryDisplay
            }
            else
            {
                $titleLine = $titleText + '  ' + $overallSummaryDisplay
            }

            $statusLine = ('Status   Platform: {0} {1} Updated: {2} {1} Collect: {3}' -f $Sample.Platform, $statusSeparator, $Sample.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'), $collectText)
            $historyLine = Add-SubtleText -Text ("History  Last $maxHistoryPoints samples (oldest -> newest)")
            $subtleDivider = Add-SubtleText -Text $divider
            $scopeLine = $null

            $scopedFilters = @()
            if ($Sample.PSObject.Properties.Name -contains 'MonitorProcessName')
            {
                $scopedFilters = @(
                    @($Sample.MonitorProcessName) |
                    Where-Object { -not [String]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object { $_.Trim() }
                )
            }

            if ($scopedFilters.Count -gt 0)
            {
                $scopeText = 'Scope    Process filter: ' + ($scopedFilters -join ', ')
                if ($Sample.PSObject.Properties.Name -contains 'MonitorProcessMatchCount' -and $null -ne $Sample.MonitorProcessMatchCount)
                {
                    $scopeText += (' | matches: {0}' -f [Int32]$Sample.MonitorProcessMatchCount)
                }

                $scopeLine = Add-SubtleText -Text $scopeText
            }

            $lines = @(
                $titleLine,
                $divider,
                $cpuLine,
                $memoryLine,
                $diskLine,
                $networkLine,
                $subtleDivider,
                '',
                (Add-SubtleText -Text $statusLine),
                $historyLine
            )

            if (-not [String]::IsNullOrWhiteSpace($scopeLine))
            {
                $lines += $scopeLine
            }

            if ($IncludeTopProcesses)
            {
                $topProcessHeader = "Top Processes (limit: $TopProcessCount)"
                if ($effectiveTopProcessNameFilters.Count -gt 0)
                {
                    $topProcessHeader += ' | filter: ' + ($effectiveTopProcessNameFilters -join ', ')
                }

                $lines += @(
                    '',
                    $subtleDivider,
                    (Add-SubtleText -Text $topProcessHeader)
                )

                $topProcesses = @()
                if ($Sample.PSObject.Properties.Name -contains 'TopProcesses')
                {
                    $topProcesses = @($Sample.TopProcesses | Where-Object { $null -ne $_ })
                }

                if ($topProcesses.Count -eq 0)
                {
                    $lines += (Add-SubtleText -Text '  n/a')
                }
                else
                {
                    foreach ($processInfo in $topProcesses)
                    {
                        $processName = [String]$processInfo.Name
                        if ([String]::IsNullOrWhiteSpace($processName))
                        {
                            $processName = '<unknown>'
                        }

                        if ($processName.Length -gt 18)
                        {
                            $processName = $processName.Substring(0, 15) + '...'
                        }

                        $processId = if ($null -eq $processInfo.Id) { 'n/a' } else { [String]$processInfo.Id }
                        $processCpu = Format-CpuSeconds -Value $processInfo.CpuSeconds
                        $processMemory = '{0} MiB' -f (Format-MiB -Value $processInfo.WorkingSetMiB)

                        $lines += ('  {0,-18} PID {1,6}  CPU {2,9}  MEM {3,12}' -f $processName, $processId, $processCpu, $processMemory)
                    }
                }
            }

            if ($IncludeContinuousHint)
            {
                $lines += @(
                    '',
                    $subtleDivider,
                    (Add-SubtleText -Text 'Press Ctrl+C to stop monitor.')
                )
            }

            return ($lines -join [Environment]::NewLine)
        }
    }

    process
    {
        $iterations = 0

        while ($true)
        {
            $iterations++
            $sample = Get-SystemResourceSample

            Add-HistoryValue -History $cpuHistory -Value $sample.CpuUsagePercent -MaxLength $HistoryLength
            Add-HistoryValue -History $memoryHistory -Value $sample.MemoryUsagePercent -MaxLength $HistoryLength
            Add-HistoryValue -History $diskHistory -Value $sample.DiskUsagePercent -MaxLength $HistoryLength
            Add-HistoryValue -History $networkThroughputHistory -Value $sample.NetworkTotalBytesPerSecond -MaxLength $HistoryLength

            if ($AsObject)
            {
                $sample
            }
            else
            {
                $dashboard = Format-DashboardText -Sample $sample -IncludeContinuousHint:$Continuous

                if ($Continuous)
                {
                    try
                    {
                        Clear-Host
                    }
                    catch
                    {
                        Write-Verbose "Clear-Host is not supported in this host: $($_.Exception.Message)"
                    }

                    Write-Host $dashboard
                }
                else
                {
                    $dashboard
                }
            }

            $isMaxed = ($MaxIterations -gt 0 -and $iterations -ge $MaxIterations)

            if (-not $Continuous -or $isMaxed)
            {
                break
            }

            Start-Sleep -Seconds $IntervalSeconds
        }
    }
}
