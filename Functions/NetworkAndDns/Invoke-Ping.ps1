function Invoke-Ping
{
    <#
    .SYNOPSIS
        Sends ICMP echo requests (ping) to test network connectivity.

    .DESCRIPTION
        Sends ICMP echo request packets to one or more hosts and returns detailed response information
        including round-trip time, TTL, packet loss, and response status. This function provides a
        reliable cross-platform alternative to Test-Connection with consistent behavior across
        PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

        Use -Tcp (or -Port) to run TCP connect probes instead of ICMP when echo requests are blocked.
        Use -Continuous to repeat ping batches until Ctrl+C is pressed.

        Uses the System.Net.NetworkInformation.Ping class for cross-platform compatibility.

    .PARAMETER ComputerName
        The target host(s) to ping. Accepts hostnames or IP addresses.
        Supports pipeline input for testing multiple hosts.
        Defaults to 'localhost' if not specified.

    .PARAMETER Count
        Number of echo requests to send to each host.
        Default is 4. Valid range: 1-100.

    .PARAMETER Timeout
        Timeout in milliseconds for each ping request.
        Default is 5000 (5 seconds). Valid range: 100-60000 (1 minute).

    .PARAMETER BufferSize
        Size of the data buffer sent with each ping request in bytes.
        Default is 32 bytes. Valid range: 0-65500.
        Applies only to ICMP mode.

    .PARAMETER DontFragment
        Sets the Don't Fragment flag on the ping packet.
        Useful for MTU path discovery. Not supported on all platforms.
        Applies only to ICMP mode.

    .PARAMETER TTL
        Time To Live value for the ping packet.
        Default is 128. Valid range: 1-255.
        Applies only to ICMP mode.

    .PARAMETER Tcp
        Uses TCP connect probes instead of ICMP echo requests.
        Useful when firewalls block ICMP (default port is 443).

    .PARAMETER Port
        TCP port to probe when -Tcp is used.
        Default is 443. Valid range: 1-65535.
        Specifying -Port also enables TCP mode.

    .PARAMETER Quiet
        Returns only a boolean value indicating if at least one ping succeeded.
        Useful for simple connectivity checks in scripts.

    .PARAMETER Delay
        Delay in milliseconds between ping requests.
        Default is 1000 (1 second). Valid range: 0-10000.

    .PARAMETER Continuous
        Continuously repeats ping batches until Ctrl+C is pressed.
        Each batch uses -Count and -Delay, then waits -Interval seconds.

    .PARAMETER Interval
        Seconds to wait between continuous ping batches.
        Default is 5. Valid range: 1-3600.

    .PARAMETER MaxIterations
        Hidden/testing-only: limits continuous mode to a fixed number of batches (0 = infinite).

    .EXAMPLE
        PS > Invoke-Ping -ComputerName 'bing.com'

        Host        : bing.com
        Sent        : 4
        Received    : 4
        Lost        : 0
        LossPercent : 0
        MinTime     : 25
        MaxTime     : 33
        AvgTime     : 29
        BufferSize  : 32
        Status      : Success
        IPAddress   : 150.171.27.10
        TTL         : 128

        Sends 4 ping requests to bing.com and displays response details.

    .EXAMPLE
        PS > Invoke-Ping -ComputerName 'bing.com' -Count 10 -Timeout 2000

        Host        : bing.com
        Sent        : 10
        Received    : 10
        Lost        : 0
        LossPercent : 0
        MinTime     : 25
        MaxTime     : 37
        AvgTime     : 31.8
        BufferSize  : 32
        Status      : Success
        IPAddress   : 150.171.27.10
        TTL         : 128

        Sends 10 ping requests with a 2-second timeout.

    .EXAMPLE
        PS > Invoke-Ping -ComputerName 'github.com' -Tcp

        Uses TCP connect probes on port 443 when ICMP is blocked by firewalls.

    .EXAMPLE
        PS > Invoke-Ping -ComputerName 'bing.com' -Continuous -Interval 2

        Continuously pings bing.com in batches, waiting 2 seconds between batches.

    .EXAMPLE
        PS > @('bing.com', 'github.com', '8.8.8.8') | Invoke-Ping -Quiet

        Tests connectivity to multiple hosts and returns boolean results.

    .EXAMPLE
        PS > Invoke-Ping -ComputerName '192.168.1.1' -Count 100 -BufferSize 1472 -DontFragment

        Performs MTU path discovery by sending large packets with Don't Fragment flag.

    .EXAMPLE
        PS > Invoke-Ping -ComputerName 'server.local' -Count 5 -Delay 2000 -Verbose

        Pings a host 5 times with a 2-second delay between requests with verbose output.

    .EXAMPLE
        PS > Get-Content hosts.txt | Invoke-Ping -Count 2

        Pings all hosts listed in a text file.

    .EXAMPLE
        PS > if (-not (Invoke-Ping -ComputerName 'db.internal' -Quiet -Timeout 1000)) { throw 'Database not reachable' }

        Uses the Quiet switch to gate a deployment step until a dependency responds to ICMP.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns objects with detailed ping statistics including Host, Sent, Received, Lost,
        LossPercent, MinTime, MaxTime, AvgTime, and Protocol (ICMP or TCP).
        When -Tcp is used, Port is included and timing reflects TCP connection latency.
        Continuous mode emits results for each batch until stopped.

        System.Boolean (when -Quiet is specified)
        Returns $true if at least one ping succeeded, otherwise $false.

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.net.networkinformation.ping

    .NOTES
        Platform Notes:
        - ICMP ping requires elevated privileges on some Linux systems
        - The DontFragment flag may not be supported on all platforms
        - Some firewalls block ICMP echo requests
        - Use -Tcp (or -Port) to test TCP connectivity when ICMP is blocked
        - Use -Continuous to keep pinging until Ctrl+C

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Invoke-Ping.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Invoke-Ping.ps1
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('Host', 'HostName', 'IPAddress', 'CN', 'Server', 'Target')]
        [String[]]$ComputerName,

        [Parameter()]
        [ValidateRange(1, 100)]
        [Int32]$Count = 4,

        [Parameter()]
        [ValidateRange(100, 60000)]
        [Int32]$Timeout = 5000,

        [Parameter()]
        [ValidateRange(0, 65500)]
        [Int32]$BufferSize = 32,

        [Parameter()]
        [Switch]$DontFragment,

        [Parameter()]
        [ValidateRange(1, 255)]
        [Int32]$TTL = 128,

        [Parameter()]
        [Switch]$Tcp,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [Alias('TcpPort')]
        [Int32]$Port = 443,

        [Parameter()]
        [Switch]$Quiet,

        [Parameter()]
        [ValidateRange(0, 10000)]
        [Int32]$Delay = 1000,

        [Parameter()]
        [Switch]$Continuous,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [Int32]$Interval = 5,

        # Hidden/testing-only: limit iterations for continuous mode (0 = infinite)
        [Parameter()]
        [Int32]$MaxIterations = 0
    )

    begin
    {
        Write-Verbose 'Initializing ping operations'

        $useTcp = $Tcp.IsPresent -or $PSBoundParameters.ContainsKey('Port')
        if ($useTcp)
        {
            Write-Verbose "Using TCP probe mode on port $Port"
        }
        else
        {
            # Create data buffer
            $buffer = New-Object Byte[] $BufferSize
            for ($i = 0; $i -lt $BufferSize; $i++)
            {
                $buffer[$i] = [Byte](65 + ($i % 23))  # Fill with ASCII characters A-W
            }
        }

        # Validate parameter combinations
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
        }

        if ($Continuous)
        {
            $targets = New-Object System.Collections.ArrayList
        }

        function Invoke-PingTarget
        {
            param(
                [Parameter(Mandatory)]
                [String]$Target
            )

            if ($useTcp)
            {
                Write-Verbose "Probing ${Target}:${Port} with $Count TCP attempts"
            }
            else
            {
                Write-Verbose "Pinging $Target with $Count packets ($BufferSize bytes each)"
            }

            try
            {
                $ping = $null
                # Arrays to track results
                $replies = @()
                $responseTimes = @()
                $successCount = 0
                $failureCount = 0
                $firstSuccessIp = $null

                if ($useTcp)
                {
                    # Send TCP probes
                    for ($i = 1; $i -le $Count; $i++)
                    {
                        $tcpClient = $null
                        $connectResult = $null

                        try
                        {
                            Write-Verbose "Opening TCP connection $i of $Count to ${Target}:${Port}"

                            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                            $tcpClient = New-Object System.Net.Sockets.TcpClient
                            $connectResult = $tcpClient.BeginConnect($Target, $Port, $null, $null)
                            $connected = $connectResult.AsyncWaitHandle.WaitOne($Timeout, $false)

                            if (-not $connected)
                            {
                                throw [System.TimeoutException]::new("TCP connection to ${Target}:${Port} timed out after ${Timeout}ms")
                            }

                            $tcpClient.EndConnect($connectResult)
                            $stopwatch.Stop()

                            $successCount++
                            $responseTimes += $stopwatch.ElapsedMilliseconds

                            if (-not $firstSuccessIp -and $tcpClient.Client -and $tcpClient.Client.RemoteEndPoint -is [System.Net.IPEndPoint])
                            {
                                $firstSuccessIp = $tcpClient.Client.RemoteEndPoint.Address.ToString()
                            }

                            Write-Verbose "Connected to ${Target}:${Port} in $($stopwatch.ElapsedMilliseconds)ms"
                        }
                        catch
                        {
                            $failureCount++
                            Write-Verbose "TCP probe failed: $($_.Exception.Message)"
                        }
                        finally
                        {
                            if ($connectResult -and $connectResult.AsyncWaitHandle)
                            {
                                $connectResult.AsyncWaitHandle.Close()
                            }

                            if ($tcpClient)
                            {
                                $tcpClient.Close()
                            }
                        }

                        # Add delay between probes (except after the last one)
                        if ($i -lt $Count -and $Delay -gt 0)
                        {
                            Start-Sleep -Milliseconds $Delay
                        }
                    }
                }
                else
                {
                    # Create ping object
                    $ping = New-Object System.Net.NetworkInformation.Ping

                    # Configure ping options
                    $pingOptions = New-Object System.Net.NetworkInformation.PingOptions($TTL, $DontFragment.IsPresent)

                    # Send ping requests
                    for ($i = 1; $i -le $Count; $i++)
                    {
                        try
                        {
                            Write-Verbose "Sending ping $i of $Count to $Target"

                            $reply = $ping.Send($Target, $Timeout, $buffer, $pingOptions)
                            $replies += $reply

                            if ($reply.Status -eq 'Success')
                            {
                                $successCount++
                                $responseTimes += $reply.RoundtripTime

                                Write-Verbose "Reply from ${Target}: bytes=$BufferSize time=$($reply.RoundtripTime)ms TTL=$($reply.Options.Ttl)"
                            }
                            else
                            {
                                $failureCount++
                                Write-Verbose "Ping failed: $($reply.Status)"
                            }
                        }
                        catch
                        {
                            $failureCount++
                            Write-Verbose "Ping error: $($_.Exception.Message)"
                        }

                        # Add delay between pings (except after the last one)
                        if ($i -lt $Count -and $Delay -gt 0)
                        {
                            Start-Sleep -Milliseconds $Delay
                        }
                    }
                }

                # Calculate statistics
                $sent = $Count
                $received = $successCount
                $lost = $failureCount
                $lossPercent = if ($sent -gt 0) { [Math]::Round(($lost / $sent) * 100, 2) } else { 0 }

                $minTime = if ($responseTimes.Count -gt 0) { ($responseTimes | Measure-Object -Minimum).Minimum } else { $null }
                $maxTime = if ($responseTimes.Count -gt 0) { ($responseTimes | Measure-Object -Maximum).Maximum } else { $null }
                $avgTime = if ($responseTimes.Count -gt 0) { [Math]::Round(($responseTimes | Measure-Object -Average).Average, 2) } else { $null }

                # Return results
                if ($Quiet)
                {
                    Write-Output ($successCount -gt 0)
                }
                else
                {
                    $result = [PSCustomObject]@{
                        Host = $Target
                        Sent = $sent
                        Received = $received
                        Lost = $lost
                        LossPercent = $lossPercent
                        MinTime = $minTime
                        MaxTime = $maxTime
                        AvgTime = $avgTime
                        BufferSize = $BufferSize
                        Status = if ($received -gt 0) { 'Success' } else { 'Failed' }
                        Protocol = if ($useTcp) { 'TCP' } else { 'ICMP' }
                    }

                    if ($useTcp)
                    {
                        $result | Add-Member -NotePropertyName 'Port' -NotePropertyValue $Port

                        if ($firstSuccessIp)
                        {
                            $result | Add-Member -NotePropertyName 'IPAddress' -NotePropertyValue $firstSuccessIp
                        }
                    }
                    else
                    {
                        # Add first successful reply details if available
                        $successfulReply = $replies | Where-Object { $_.Status -eq 'Success' } | Select-Object -First 1
                        if ($successfulReply)
                        {
                            $result | Add-Member -NotePropertyName 'IPAddress' -NotePropertyValue $successfulReply.Address.ToString()
                            $result | Add-Member -NotePropertyName 'TTL' -NotePropertyValue $successfulReply.Options.Ttl
                        }
                    }

                    Write-Output $result
                }

                # Cleanup
                if ($ping)
                {
                    $ping.Dispose()
                }
            }
            catch [System.Net.NetworkInformation.PingException]
            {
                Write-Verbose "Ping exception for ${Target}: $($_.Exception.Message)"

                if ($Quiet)
                {
                    Write-Output $false
                }
                else
                {
                    $result = [PSCustomObject]@{
                        Host = $Target
                        Sent = $Count
                        Received = 0
                        Lost = $Count
                        LossPercent = 100
                        MinTime = $null
                        MaxTime = $null
                        AvgTime = $null
                        BufferSize = $BufferSize
                        Status = 'Error'
                        Error = $_.Exception.Message
                        Protocol = if ($useTcp) { 'TCP' } else { 'ICMP' }
                    }

                    if ($useTcp)
                    {
                        $result | Add-Member -NotePropertyName 'Port' -NotePropertyValue $Port
                    }

                    Write-Output $result
                }
            }
            catch
            {
                Write-Verbose "Unexpected error for ${Target}: $($_.Exception.Message)"

                if ($Quiet)
                {
                    Write-Output $false
                }
                else
                {
                    $result = [PSCustomObject]@{
                        Host = $Target
                        Sent = $Count
                        Received = 0
                        Lost = $Count
                        LossPercent = 100
                        MinTime = $null
                        MaxTime = $null
                        AvgTime = $null
                        BufferSize = $BufferSize
                        Status = 'Error'
                        Error = $_.Exception.Message
                        Protocol = if ($useTcp) { 'TCP' } else { 'ICMP' }
                    }

                    if ($useTcp)
                    {
                        $result | Add-Member -NotePropertyName 'Port' -NotePropertyValue $Port
                    }

                    Write-Output $result
                }
            }
        }
    }

    process
    {
        if ($Continuous)
        {
            foreach ($target in $ComputerName)
            {
                if ([string]::IsNullOrWhiteSpace($target))
                {
                    continue
                }

                [void]$targets.Add($target)
            }
        }
        else
        {
            foreach ($target in $ComputerName)
            {
                Invoke-PingTarget -Target $target
            }
        }
    }

    end
    {
        if ($Continuous)
        {
            if ($targets.Count -eq 0)
            {
                Write-Error 'No valid target hosts specified.'
                return
            }

            $iteration = 0
            do
            {
                $iteration++
                foreach ($target in $targets)
                {
                    Invoke-PingTarget -Target $target
                }

                if ($Continuous -and ($MaxIterations -eq 0 -or $iteration -lt $MaxIterations))
                {
                    Start-Sleep -Seconds $Interval
                }
            } while ($Continuous -and ($MaxIterations -eq 0 -or $iteration -lt $MaxIterations))
        }

        Write-Verbose 'Ping operations completed'
    }
}
