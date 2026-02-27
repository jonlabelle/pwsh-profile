function Trace-Route
{
    <#
    .SYNOPSIS
        Performs a cross-platform traceroute to a destination host.

    .DESCRIPTION
        Traces the route packets take to reach a destination host by sending ICMP echo
        requests with incrementing TTL (Time To Live) values. Each hop along the path
        is reported with its IP address, hostname (via reverse DNS), and round-trip latency.

        Uses the .NET System.Net.NetworkInformation.Ping class with incrementing TTL for
        cross-platform compatibility across Windows, macOS, and Linux.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER ComputerName
        The destination host to trace the route to. Accepts hostnames or IP addresses.

    .PARAMETER MaxHops
        Maximum number of hops to trace. Default is 30. Valid range: 1-64.

    .PARAMETER Timeout
        Timeout in milliseconds for each probe. Default is 5000 (5 seconds).
        Valid range: 100-30000.

    .PARAMETER Queries
        Number of probes to send per hop. Default is 1. Valid range: 1-5.
        Multiple queries show latency variation at each hop.

    .PARAMETER ResolveNames
        Attempt reverse DNS lookup for each hop's IP address.
        Enabled by default. Use -ResolveNames:$false to disable for faster results.

    .PARAMETER BufferSize
        Size of the ICMP data buffer in bytes. Default is 32. Valid range: 0-65500.

    .EXAMPLE
        PS > Trace-Route -ComputerName 'bing.com'

        Hop IP              Hostname         Latency Status
        --- --              --------         ------- ------
          1 192.168.1.1     router.local     1.2ms   TtlExpired
          2 10.0.0.1        isp-gw.example   8.5ms   TtlExpired
          3 72.14.215.85    ...              12.3ms  TtlExpired
          4 204.79.197.200  bing.com         28.1ms  Success

        Traces the route to bing.com, resolving hostnames at each hop.

    .EXAMPLE
        PS > Trace-Route -ComputerName '8.8.8.8' -MaxHops 15 -ResolveNames:$false

        Traces the route to Google DNS without reverse DNS lookups (faster).

    .EXAMPLE
        PS > Trace-Route -ComputerName 'github.com' -Queries 3

        Sends 3 probes per hop to show latency variation.

    .OUTPUTS
        PSCustomObject
        Returns objects with Hop, IP, Hostname, Latency, and Status properties.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Trace-Route.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Trace-Route.ps1
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ComputerName,

        [Parameter()]
        [ValidateRange(1, 64)]
        [Int32]
        $MaxHops = 30,

        [Parameter()]
        [ValidateRange(100, 30000)]
        [Int32]
        $Timeout = 5000,

        [Parameter()]
        [ValidateRange(1, 5)]
        [Int32]
        $Queries = 1,

        [Parameter()]
        [Bool]
        $ResolveNames = $true,

        [Parameter()]
        [ValidateRange(0, 65500)]
        [Int32]
        $BufferSize = 32
    )

    begin
    {
        Write-Verbose 'Starting traceroute'
    }

    process
    {
        Write-Verbose "Tracing route to '$ComputerName' (max hops: $MaxHops, timeout: ${Timeout}ms)"

        # Resolve destination to IP address
        try
        {
            $destAddresses = [System.Net.Dns]::GetHostAddresses($ComputerName)
            $destIP = ($destAddresses | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1)

            if (-not $destIP)
            {
                $destIP = $destAddresses | Select-Object -First 1
            }

            Write-Verbose "Resolved '$ComputerName' to $($destIP.ToString())"
        }
        catch
        {
            Write-Error "Cannot resolve hostname '$ComputerName': $($_.Exception.Message)"
            return
        }

        # Build the ICMP buffer
        $buffer = New-Object Byte[] $BufferSize
        for ($i = 0; $i -lt $BufferSize; $i++)
        {
            $buffer[$i] = [Byte](65 + ($i % 23))
        }

        $pinger = New-Object System.Net.NetworkInformation.Ping
        $reachedDestination = $false

        try
        {
            for ($ttl = 1; $ttl -le $MaxHops; $ttl++)
            {
                if ($reachedDestination) { break }

                $hopResults = @()

                for ($q = 0; $q -lt $Queries; $q++)
                {
                    $options = New-Object System.Net.NetworkInformation.PingOptions($ttl, $true)

                    try
                    {
                        $reply = $pinger.Send($destIP, $Timeout, $buffer, $options)

                        $hopResults += [PSCustomObject]@{
                            Status = $reply.Status.ToString()
                            IP = if ($reply.Address) { $reply.Address.ToString() } else { '*' }
                            LatencyMs = if ($reply.Status -eq 'Success' -or $reply.Status -eq 'TtlExpired') { $reply.RoundtripTime } else { -1 }
                        }

                        if ($reply.Status -eq 'Success')
                        {
                            $reachedDestination = $true
                        }
                    }
                    catch
                    {
                        Write-Verbose "Hop $ttl query $($q + 1) error: $($_.Exception.Message)"
                        $hopResults += [PSCustomObject]@{
                            Status = 'Error'
                            IP = '*'
                            LatencyMs = -1
                        }
                    }
                }

                # Determine the hop's representative IP and status
                $bestResult = $hopResults | Where-Object { $_.IP -ne '*' } | Select-Object -First 1
                if (-not $bestResult)
                {
                    $bestResult = $hopResults | Select-Object -First 1
                }

                $hopIP = $bestResult.IP
                $hopStatus = $bestResult.Status

                # Calculate average latency across queries
                $validLatencies = @($hopResults | Where-Object { $_.LatencyMs -ge 0 } | ForEach-Object { $_.LatencyMs })
                if ($validLatencies.Count -gt 0)
                {
                    $avgLatency = ($validLatencies | Measure-Object -Average).Average
                    $latencyStr = "$([math]::Round($avgLatency, 1))ms"
                }
                else
                {
                    $latencyStr = '*'
                }

                # Resolve hostname if requested
                $hostname = ''
                if ($ResolveNames -and $hopIP -ne '*')
                {
                    try
                    {
                        $hostEntry = [System.Net.Dns]::GetHostEntry($hopIP)
                        if ($hostEntry.HostName -ne $hopIP)
                        {
                            $hostname = $hostEntry.HostName
                        }
                    }
                    catch
                    {
                        Write-Verbose "Could not resolve hostname for $hopIP"
                    }
                }

                Write-Verbose "Hop $ttl : $hopIP ($hostname) - $latencyStr [$hopStatus]"

                [PSCustomObject]@{
                    Hop = $ttl
                    IP = $hopIP
                    Hostname = $hostname
                    Latency = $latencyStr
                    Status = $hopStatus
                }
            }

            if (-not $reachedDestination)
            {
                Write-Verbose "Destination '$ComputerName' not reached within $MaxHops hops"
            }
        }
        finally
        {
            if ($pinger)
            {
                $pinger.Dispose()
            }
        }
    }

    end
    {
        Write-Verbose 'Traceroute completed'
    }
}
