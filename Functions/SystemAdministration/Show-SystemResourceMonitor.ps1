function Show-SystemResourceMonitor
{
    <#
    .SYNOPSIS
        Displays a visual monitor for CPU, memory, and disk usage.

    .DESCRIPTION
        Collects core system resource metrics and renders them in a compact, visual
        dashboard using text bars and history sparklines. Works on Windows, macOS,
        and Linux with platform-specific collection logic and safe fallbacks.

        By default, the function returns a single dashboard snapshot as a string.
        Use -Continuous to keep refreshing the view until interrupted with Ctrl+C.
        Use -AsObject for structured output suitable for scripts and automation.

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

    .PARAMETER MaxIterations
        Maximum number of iterations for continuous mode. 0 means unlimited.
        Primarily useful for testing and automation.

    .EXAMPLE
        PS > Show-SystemResourceMonitor

        System Resource Monitor

        History window: last 24 samples (oldest -> newest)
        ───────────────────────────────────────────────────────────────────────────────────────────
        CPU    [███▏░░░░░░░░░░░░░░░░░░░░░░░░░░░░]   10.0% OK   • ▂
        Memory [█████████▊░░░░░░░░░░░░░░░░░░░░░░]   31.0% OK   • ▃  7.3/24.0 GiB
        Disk   [██████████▌░░░░░░░░░░░░░░░░░░░░░]   33.0% OK   • ▃  152.4/460.4 GiB on / (root fs)

        • │ Platform: macOS │ Updated: 2026-02-16 18:19:51 │ Overall: 25.0% OK

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

        $cpuHistory = New-Object 'System.Collections.Generic.List[double]'
        $memoryHistory = New-Object 'System.Collections.Generic.List[double]'
        $diskHistory = New-Object 'System.Collections.Generic.List[double]'

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
                [Int32]$Width
            )

            if ($null -eq $Percent)
            {
                return '[' + ('?' * $Width) + ']'
            }

            $clamped = [Math]::Max(0, [Math]::Min(100, [Double]$Percent))
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
                }
            }

            $usedBytes = [Math]::Max(0.0, $totalBytes - $freeBytes)
            $percent = ($usedBytes / $totalBytes) * 100

            return @{
                Percent = [Math]::Round([Math]::Max(0, [Math]::Min(100, $percent)), 1)
                UsedGiB = [Math]::Round($usedBytes / 1GB, 2)
                TotalGiB = [Math]::Round($totalBytes / 1GB, 2)
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

        function Get-SystemResourceSample
        {
            $cpuPercent = Get-CpuUsagePercent -FallbackState $cpuFallbackState
            if ($null -eq $cpuPercent)
            {
                Start-Sleep -Milliseconds 200
                $cpuPercent = Get-CpuUsagePercent -FallbackState $cpuFallbackState
            }

            $memory = Get-MemoryUsageInfo
            $disk = Get-SystemDriveUsageInfo

            [PSCustomObject]@{
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
            }
        }

        function Format-DashboardText
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Sample
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
                    [String]$Details
                )

                $barText = ConvertTo-UsageBar -Percent $Percent -Width $renderedBarWidth
                $percentText = Format-Percent -Percent $Percent
                $statusText = ('{0,-4}' -f (Get-UsageStatus -Percent $Percent))
                $trendText = Get-TrendIndicator -Values $History
                $sparkText = ConvertTo-Sparkline -Values $History

                $line = '{0,-6} {1} {2} {3} {4} {5}' -f $Name, $barText, $percentText, $statusText, $trendText, $sparkText
                if (-not [String]::IsNullOrWhiteSpace($Details))
                {
                    $line = $line + '  ' + $Details
                }

                return Add-Color -Text $line -Percent $Percent
            }

            $memoryDetails = '{0}/{1} GiB' -f (Format-GiB -Value $Sample.MemoryUsedGiB), (Format-GiB -Value $Sample.MemoryTotalGiB)
            $diskRoot = Format-DiskRootLabel -Root $Sample.DiskRoot
            $diskDetails = '{0}/{1} GiB on {2}' -f (Format-GiB -Value $Sample.DiskUsedGiB), (Format-GiB -Value $Sample.DiskTotalGiB), $diskRoot

            $cpuLine = & $formatMetricLine -Name 'CPU' -Percent $Sample.CpuUsagePercent -History $cpuHistoryValues
            $memoryLine = & $formatMetricLine -Name 'Memory' -Percent $Sample.MemoryUsagePercent -History $memoryHistoryValues -Details $memoryDetails
            $diskLine = & $formatMetricLine -Name 'Disk' -Percent $Sample.DiskUsagePercent -History $diskHistoryValues -Details $diskDetails

            $percentValues = @(
                $Sample.CpuUsagePercent,
                $Sample.MemoryUsagePercent,
                $Sample.DiskUsagePercent
            ) | Where-Object { $null -ne $_ }

            $overallLoad = $null
            if ($percentValues.Count -gt 0)
            {
                $overallLoad = [Math]::Round(($percentValues | Measure-Object -Average).Average, 1)
            }

            if ($supportsUnicode)
            {
                $dividerChar = [String][char]0x2500
                $bullet = [String][char]0x2022
                $statusSeparator = [String][char]0x2502
            }
            else
            {
                $dividerChar = '-'
                $bullet = '*'
                $statusSeparator = '|'
            }

            $divider = $dividerChar * [Math]::Max(70, $renderedBarWidth + $maxHistoryPoints + 35)

            $lines = @(
                'System Resource Monitor',
                '',
                "History window: last $maxHistoryPoints samples (oldest -> newest)",
                $divider,
                $cpuLine,
                $memoryLine,
                $diskLine,
                '',
                ('{0} {1} Platform: {2} {1} Updated: {3} {1} Overall: {4} {5}' -f $bullet, $statusSeparator, $Sample.Platform, $Sample.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'), (Format-Percent -Percent $overallLoad).Trim(), (Get-UsageStatus -Percent $overallLoad))
            )

            if ($Continuous)
            {
                $lines += @(
                    '',
                    'Press Ctrl+C to stop monitoring.'
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
            $sample = Get-SystemResourceSample

            Add-HistoryValue -History $cpuHistory -Value $sample.CpuUsagePercent -MaxLength $HistoryLength
            Add-HistoryValue -History $memoryHistory -Value $sample.MemoryUsagePercent -MaxLength $HistoryLength
            Add-HistoryValue -History $diskHistory -Value $sample.DiskUsagePercent -MaxLength $HistoryLength

            if ($AsObject)
            {
                $sample
            }
            else
            {
                $dashboard = Format-DashboardText -Sample $sample

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

            $iterations++
            $isMaxed = ($MaxIterations -gt 0 -and $iterations -ge $MaxIterations)

            if (-not $Continuous -or $isMaxed)
            {
                break
            }

            Start-Sleep -Seconds $IntervalSeconds
        }
    }
}
