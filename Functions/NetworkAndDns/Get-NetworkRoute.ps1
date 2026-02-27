function Get-NetworkRoute
{
    <#
    .SYNOPSIS
        Displays the local routing table as structured PowerShell objects.

    .DESCRIPTION
        Retrieves the system routing table and returns structured objects with destination,
        gateway, interface, and metric information. Provides a cross-platform wrapper
        around platform-specific routing table commands.

        On Windows, uses Get-NetRoute when available (PowerShell 5.1+), falling back to
        'route print' parsing. On macOS and Linux, parses 'netstat -rn' output.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER AddressFamily
        Filter routes by address family. Valid values: 'IPv4', 'IPv6', 'All'.
        Default is 'IPv4'.

    .EXAMPLE
        PS > Get-NetworkRoute

        Destination     Gateway         Interface       Metric Type
        -----------     -------         ---------       ------ ----
        default         192.168.1.1     en0             0
        127.0.0.1       127.0.0.1       lo0             0
        192.168.1.0/24  link#4          en0             0
        ...

        Displays the IPv4 routing table.

    .EXAMPLE
        PS > Get-NetworkRoute -AddressFamily IPv6

        Displays the IPv6 routing table.

    .EXAMPLE
        PS > Get-NetworkRoute | Where-Object { $_.Gateway -ne '*' -and $_.Gateway }

        Shows only routes with a specific gateway (excluding directly connected networks).

    .OUTPUTS
        PSCustomObject
        Returns objects with Destination, Gateway, Interface, Metric, and Type properties.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-NetworkRoute.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-NetworkRoute.ps1
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Position = 0)]
        [ValidateSet('IPv4', 'IPv6', 'All')]
        [String]
        $AddressFamily = 'IPv4'
    )

    begin
    {
        Write-Verbose 'Retrieving routing table'

        # Detect platform
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $isWindowsPlatform = $true
            $isMacOSPlatform = $false
            $isLinuxPlatform = $false
        }
        else
        {
            $isWindowsPlatform = $IsWindows
            $isMacOSPlatform = $IsMacOS
            $isLinuxPlatform = $IsLinux
        }
    }

    process
    {
        if ($isWindowsPlatform)
        {
            Write-Verbose 'Using Windows routing table retrieval'

            # Try Get-NetRoute cmdlet first (available on Windows 8+/Server 2012+)
            if (Get-Command -Name 'Get-NetRoute' -ErrorAction SilentlyContinue)
            {
                Write-Verbose 'Using Get-NetRoute cmdlet'

                $netRouteParams = @{}
                switch ($AddressFamily)
                {
                    'IPv4' { $netRouteParams['AddressFamily'] = 'IPv4' }
                    'IPv6' { $netRouteParams['AddressFamily'] = 'IPv6' }
                }

                try
                {
                    $routes = Get-NetRoute @netRouteParams -ErrorAction Stop

                    foreach ($route in $routes)
                    {
                        $destination = if ($route.DestinationPrefix)
                        {
                            $route.DestinationPrefix
                        }
                        else
                        {
                            'unknown'
                        }

                        [PSCustomObject]@{
                            Destination = $destination
                            Gateway = if ($route.NextHop) { $route.NextHop } else { '' }
                            Interface = if ($route.InterfaceAlias) { $route.InterfaceAlias } else { "ifIndex:$($route.InterfaceIndex)" }
                            Metric = $route.RouteMetric
                            Type = if ($route.TypeOfRoute) { $route.TypeOfRoute.ToString() } else { '' }
                        }
                    }
                    return
                }
                catch
                {
                    Write-Verbose "Get-NetRoute failed: $($_.Exception.Message). Falling back to route print."
                }
            }

            # Fallback: parse 'route print'
            Write-Verbose 'Parsing route print output'
            try
            {
                $routeOutput = & route print 2>&1
                $inActiveRoutes = $false

                foreach ($line in $routeOutput)
                {
                    $trimmed = $line.Trim()

                    if ($trimmed -match 'Active Routes')
                    {
                        $inActiveRoutes = $true
                        continue
                    }

                    if ($trimmed -match '={5,}' -or $trimmed -match 'Persistent Routes' -or [string]::IsNullOrWhiteSpace($trimmed))
                    {
                        if ($inActiveRoutes -and $trimmed -match 'Persistent Routes')
                        {
                            $inActiveRoutes = $false
                        }
                        continue
                    }

                    if ($trimmed -match 'Network Destination|Metric')
                    {
                        continue
                    }

                    if ($inActiveRoutes)
                    {
                        $parts = $trimmed -split '\s+' | Where-Object { $_ }
                        if ($parts.Count -ge 4)
                        {
                            [PSCustomObject]@{
                                Destination = $parts[0]
                                Gateway = $parts[2]
                                Interface = $parts[3]
                                Metric = if ($parts.Count -ge 5) { [int]$parts[4] } else { 0 }
                                Type = ''
                            }
                        }
                    }
                }
            }
            catch
            {
                Write-Error "Failed to retrieve routing table: $($_.Exception.Message)"
            }
        }
        elseif ($isMacOSPlatform -or $isLinuxPlatform)
        {
            Write-Verbose "Using Unix routing table retrieval ($(if ($isMacOSPlatform) { 'macOS' } else { 'Linux' }))"

            # Try 'ip route' on Linux first, fall back to 'netstat -rn'
            if ($isLinuxPlatform -and (Get-Command -Name 'ip' -CommandType Application -ErrorAction SilentlyContinue))
            {
                Write-Verbose 'Parsing ip route output'
                try
                {
                    $ipArgs = if ($AddressFamily -eq 'IPv6') { @('-6', 'route', 'show') } else { @('-4', 'route', 'show') }
                    Write-Verbose "Executing: ip $($ipArgs -join ' ')"
                    $routeOutput = & ip @ipArgs 2>&1

                    foreach ($line in $routeOutput)
                    {
                        $trimmed = $line.Trim()
                        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

                        $destination = ($trimmed -split '\s+')[0]
                        $gateway = ''
                        $iface = ''
                        $metric = 0

                        if ($trimmed -match '\bvia\s+(\S+)') { $gateway = $Matches[1] }
                        if ($trimmed -match '\bdev\s+(\S+)') { $iface = $Matches[1] }
                        if ($trimmed -match '\bmetric\s+(\d+)') { $metric = [int]$Matches[1] }

                        [PSCustomObject]@{
                            Destination = $destination
                            Gateway = $gateway
                            Interface = $iface
                            Metric = $metric
                            Type = ''
                        }
                    }
                    return
                }
                catch
                {
                    Write-Verbose "ip route failed: $($_.Exception.Message). Falling back to netstat."
                }
            }

            # Fallback: netstat -rn (works on macOS and Linux)
            Write-Verbose 'Parsing netstat -rn output'
            try
            {
                $family = if ($AddressFamily -eq 'IPv6') { 'inet6' } elseif ($AddressFamily -eq 'IPv4') { 'inet' } else { '' }
                $netstatArgs = @('-rn')
                if ($family -and $isMacOSPlatform)
                {
                    $netstatArgs += '-f'
                    $netstatArgs += $family
                }

                $routeOutput = & netstat @netstatArgs 2>&1

                $headerFound = $false

                foreach ($line in $routeOutput)
                {
                    $trimmed = $line.Trim()

                    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

                    # Skip until we find the header line
                    if ($trimmed -match '^Destination\s+Gateway')
                    {
                        $headerFound = $true
                        continue
                    }

                    if (-not $headerFound) { continue }

                    # Skip separator lines or section headers
                    if ($trimmed -match '^(-+|Internet|Routing)') { continue }

                    $parts = $trimmed -split '\s+' | Where-Object { $_ }
                    if ($parts.Count -ge 2)
                    {
                        $dest = $parts[0]
                        $gw = $parts[1]
                        $iface = ''
                        $met = 0

                        if ($isMacOSPlatform)
                        {
                            # macOS netstat: Destination Gateway Flags Netif Expire
                            if ($parts.Count -ge 4) { $iface = $parts[3] }
                        }
                        else
                        {
                            # Linux netstat: Destination Gateway Genmask Flags Metric Ref Use Iface
                            if ($parts.Count -ge 8) { $iface = $parts[7] }
                            if ($parts.Count -ge 5)
                            {
                                $metricStr = $parts[4]
                                if ($metricStr -match '^\d+$') { $met = [int]$metricStr }
                            }
                        }

                        # Filter by address family on Linux netstat (no -f flag)
                        if ($isLinuxPlatform -and $AddressFamily -eq 'IPv6' -and $dest -notmatch ':') { continue }
                        if ($isLinuxPlatform -and $AddressFamily -eq 'IPv4' -and $dest -match ':') { continue }

                        [PSCustomObject]@{
                            Destination = $dest
                            Gateway = $gw
                            Interface = $iface
                            Metric = $met
                            Type = ''
                        }
                    }
                }
            }
            catch
            {
                Write-Error "Failed to retrieve routing table: $($_.Exception.Message)"
            }
        }
        else
        {
            Write-Error 'Unsupported platform for Get-NetworkRoute.'
        }
    }

    end
    {
        Write-Verbose 'Routing table retrieval completed'
    }
}
