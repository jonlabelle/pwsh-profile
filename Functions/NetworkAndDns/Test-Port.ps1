function Test-Port
{
    <#
    .SYNOPSIS
        Tests TCP or UDP port connectivity to target hosts.

    .DESCRIPTION
        Tests whether specific TCP or UDP ports are open and accessible on target hosts.
        Provides detailed connection information including success status and connection details.
        Supports pipeline input for port numbers, allowing easy testing of multiple ports.
        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Port
        Port numbers to test. Accepts an array of port numbers (1-65535).
        Supports pipeline input for easy testing of multiple ports (e.g., 22,80,443 | Test-Port).

    .PARAMETER ComputerName
        Target hosts to test. Accepts an array of computer names or IP addresses.
        If not specified, 'localhost' is used as the default.
        Supports pipeline input by property name for object-based input.

    .PARAMETER Timeout
        Sets a timeout (in milliseconds) for port query.
        The default is 3000 (3 seconds). Valid range: 100-300000 (5 minutes).

    .PARAMETER Tcp
        Use this switch to test TCP ports.
        If neither Tcp nor Udp is specified, Tcp is used by default.

    .PARAMETER Udp
        Use this switch to test UDP ports.

    .EXAMPLE
        PS > Test-Port -ComputerName 'bing.com' -Port 80

        Server       : bing.com
        Port         : 80
        Protocol     : TCP
        Open         : True
        Status       : Connection successful
        ResponseTime : 35

        Tests if TCP port 80 is open on 'bing.com'.

    .EXAMPLE
        PS > 80 | Test-Port

        Server       : localhost
        Port         : 80
        Protocol     : TCP
        Open         : False
        Status       : Connection refused
        ResponseTime : 2

        Tests if TCP port 80 is open on localhost using pipeline input for the port.

    .EXAMPLE
        PS > 22,80,443 | Test-Port

        Server       : localhost
        Port         : 22
        Protocol     : TCP
        Open         : False
        Status       : Connection refused
        ResponseTime : 1

        Server       : localhost
        Port         : 80
        Protocol     : TCP
        Open         : False
        Status       : Connection refused
        ResponseTime : 1

        Server       : localhost
        Port         : 443
        Protocol     : TCP
        Open         : False
        Status       : Connection refused
        ResponseTime : 0

        Tests if TCP ports 22, 80, and 443 are open on localhost using pipeline input.

    .EXAMPLE
        PS > 1..100 | Test-Port -ComputerName 'server'

        Tests TCP ports 1-100 on 'server' using pipeline input for port range.

    .EXAMPLE
        PS > Test-Port -ComputerName @("server1","server2") -Port 80

        Tests if TCP port 80 is open on both server1 and server2.

    .EXAMPLE
        PS > Test-Port -ComputerName dc1 -Port 17 -Udp -Timeout 10000

        Tests if UDP port 17 is open on server dc1 with a 10-second timeout.

    .EXAMPLE
        PS > 80,443,8080 | Test-Port -ComputerName @("server1","server2")

        Tests multiple ports on multiple servers using pipeline input for ports.

    .EXAMPLE
        PS > Test-Port -ComputerName (Get-Content hosts.txt) -Port @(1..59)

        Tests a range of ports from 1-59 on all servers in the hosts.txt file.

    .OUTPUTS
        System.Object[]
        Returns custom objects with Server, Port, Protocol, Open, Status, and ResponseTime properties.

    .LINK
        https://learn-powershell.net/2011/02/21/querying-udp-ports-with-powershell/

    .LINK
        https://jonlabelle.com/snippets/view/powershell/test-tcp-or-udp-network-port-in-powershell

    .NOTES
        Original Author: Boe Prox
        Created: 18-Aug-2010
        Updated by: Jon LaBelle, 9/29/2022
        Enhanced: 8/16/2025 - Improved cross-platform compatibility, reliability, and performance

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Test-Port.ps1
    #>
    [CmdletBinding(ConfirmImpact = 'Low')]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, HelpMessage = 'Port numbers to test (1-65535)')]
        [ValidateRange(1, 65535)]
        [Int[]]$Port,

        [Parameter(Position = 1, ValueFromPipelineByPropertyName = $true, HelpMessage = 'Target hosts to test')]
        [AllowNull()]
        [AllowEmptyString()]
        [Alias('IPAddress', '__Server', 'CN', 'Server', 'Target')]
        [String[]]$ComputerName,

        [Parameter(HelpMessage = 'Timeout in milliseconds (100-300000)')]
        [ValidateRange(100, 300000)]
        [Int]$Timeout = 3000,

        [Parameter(HelpMessage = 'Test TCP ports')]
        [Switch]$Tcp,

        [Parameter(HelpMessage = 'Test UDP ports')]
        [Switch]$Udp
    )

    begin
    {
        # Set default protocol if neither is specified
        if (-not $Tcp -and -not $Udp)
        {
            $Tcp = $true
        }

        # Initialize results collection using ArrayList for better performance
        $results = New-Object System.Collections.ArrayList

        # Initialize port collection for pipeline input
        $allPorts = New-Object System.Collections.ArrayList
    }

    process
    {
        # Collect ports from pipeline input
        if ($Port)
        {
            foreach ($portNumber in $Port)
            {
                [void]$allPorts.Add($portNumber)
            }
        }
    }

    end
    {
        # Handle case where no ports were provided
        if ($allPorts.Count -eq 0)
        {
            Write-Error 'No ports specified for testing.'
            return
        }

        # Handle pipeline input and set default if empty
        if (-not $ComputerName -or $ComputerName.Count -eq 0)
        {
            $ComputerName = @('localhost')
        }

        foreach ($computer in $ComputerName)
        {
            # Skip empty/null computer names
            if ([string]::IsNullOrWhiteSpace($computer))
            {
                continue
            }

            Write-Verbose "Testing ports on $computer"

            foreach ($targetPort in $allPorts)
            {
                Write-Verbose "Testing $computer`:$targetPort"

                if ($Tcp)
                {
                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $tcpClient = $null

                    try
                    {
                        Write-Verbose "Testing TCP connection to ${computer}:${targetPort}"

                        $tcpClient = New-Object System.Net.Sockets.TcpClient
                        $connectTask = $tcpClient.BeginConnect($computer, $targetPort, $null, $null)
                        $success = $connectTask.AsyncWaitHandle.WaitOne($Timeout, $false)

                        if ($success)
                        {
                            try
                            {
                                $tcpClient.EndConnect($connectTask)
                                $stopwatch.Stop()

                                Write-Verbose "TCP connection to ${computer}:${targetPort} successful"

                                $result = [PSCustomObject]@{
                                    PSTypeName = 'PortTest.Result'
                                    Server = $computer
                                    Port = $targetPort
                                    Protocol = 'TCP'
                                    Open = $true
                                    Status = 'Connection successful'
                                    ResponseTime = $stopwatch.ElapsedMilliseconds
                                }
                                [void]$results.Add($result)
                            }
                            catch
                            {
                                $stopwatch.Stop()
                                $errorMessage = $_.Exception.Message

                                # Parse common connection errors for better user feedback
                                if ($errorMessage -match 'refused|rejected')
                                {
                                    $status = 'Connection refused'
                                }
                                elseif ($errorMessage -match 'unreachable')
                                {
                                    $status = 'Host unreachable'
                                }
                                elseif ($errorMessage -match 'timeout|timed out')
                                {
                                    $status = 'Connection timed out'
                                }
                                else
                                {
                                    $status = "Connection failed: $($errorMessage -replace '.*:', '' -replace '"', '' | ForEach-Object Trim)"
                                }

                                Write-Verbose "TCP connection to ${computer}:${targetPort} failed: $status"

                                $result = [PSCustomObject]@{
                                    PSTypeName = 'PortTest.Result'
                                    Server = $computer
                                    Port = $targetPort
                                    Protocol = 'TCP'
                                    Open = $false
                                    Status = $status
                                    ResponseTime = $stopwatch.ElapsedMilliseconds
                                }
                                [void]$results.Add($result)
                            }
                        }
                        else
                        {
                            $stopwatch.Stop()
                            Write-Verbose "TCP connection to ${computer}:${targetPort} timed out"

                            $result = [PSCustomObject]@{
                                PSTypeName = 'PortTest.Result'
                                Server = $computer
                                Port = $targetPort
                                Protocol = 'TCP'
                                Open = $false
                                Status = 'Connection timed out'
                                ResponseTime = $Timeout
                            }
                            [void]$results.Add($result)
                        }
                    }
                    catch
                    {
                        $stopwatch.Stop()
                        Write-Verbose "TCP test error for ${computer}:${targetPort}: $($_.Exception.Message)"

                        $result = [PSCustomObject]@{
                            PSTypeName = 'PortTest.Result'
                            Server = $computer
                            Port = $targetPort
                            Protocol = 'TCP'
                            Open = $false
                            Status = "Error: $($_.Exception.Message)"
                            ResponseTime = $stopwatch.ElapsedMilliseconds
                        }
                        [void]$results.Add($result)
                    }
                    finally
                    {
                        if ($null -ne $tcpClient)
                        {
                            try
                            {
                                $tcpClient.Close()
                            }
                            catch
                            {
                                Write-Debug "Error closing TCP client: $($_.Exception.Message)"
                            }
                            $tcpClient.Dispose()
                        }
                    }
                }

                if ($Udp)
                {
                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $udpClient = $null

                    try
                    {
                        Write-Verbose "Testing UDP connection to ${computer}:${targetPort}"

                        $udpClient = New-Object System.Net.Sockets.UdpClient
                        $udpClient.Client.ReceiveTimeout = $Timeout
                        $udpClient.Client.SendTimeout = $Timeout

                        # Connect to the remote endpoint
                        $udpClient.Connect($computer, $targetPort)

                        # Send a small test packet
                        $encoder = [System.Text.Encoding]::ASCII
                        $testData = $encoder.GetBytes("PowerShell-Test-$(Get-Date -Format 'yyyyMMddHHmmss')")
                        [void]$udpClient.Send($testData, $testData.Length)

                        # Try to receive a response
                        $remoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)

                        try
                        {
                            $responseBytes = $udpClient.Receive([ref]$remoteEndpoint)
                            $stopwatch.Stop()

                            if ($responseBytes.Length -gt 0)
                            {
                                Write-Verbose "UDP response received from ${computer}:${targetPort}"

                                $result = [PSCustomObject]@{
                                    PSTypeName = 'PortTest.Result'
                                    Server = $computer
                                    Port = $targetPort
                                    Protocol = 'UDP'
                                    Open = $true
                                    Status = 'Response received'
                                    ResponseTime = $stopwatch.ElapsedMilliseconds
                                }
                                [void]$results.Add($result)
                            }
                        }
                        catch [System.Net.Sockets.SocketException]
                        {
                            $stopwatch.Stop()

                            # UDP is connectionless, so we need to interpret the exception
                            $errorCode = $_.Exception.SocketErrorCode

                            if ($errorCode -eq [System.Net.Sockets.SocketError]::TimedOut)
                            {
                                # No response doesn't necessarily mean the port is closed for UDP
                                # For simplicity, we'll consider it potentially open but filtered
                                Write-Verbose "UDP test to ${computer}:${targetPort} - no response (may be open but not responding)"

                                $result = [PSCustomObject]@{
                                    PSTypeName = 'PortTest.Result'
                                    Server = $computer
                                    Port = $targetPort
                                    Protocol = 'UDP'
                                    Open = $true
                                    Status = 'No response (likely filtered or open)'
                                    ResponseTime = $Timeout
                                }
                                [void]$results.Add($result)
                            }
                            elseif ($errorCode -eq [System.Net.Sockets.SocketError]::ConnectionReset)
                            {
                                Write-Verbose "UDP test to ${computer}:${targetPort} - port closed (ICMP unreachable received)"

                                $result = [PSCustomObject]@{
                                    PSTypeName = 'PortTest.Result'
                                    Server = $computer
                                    Port = $targetPort
                                    Protocol = 'UDP'
                                    Open = $false
                                    Status = 'Port closed (ICMP unreachable)'
                                    ResponseTime = $stopwatch.ElapsedMilliseconds
                                }
                                [void]$results.Add($result)
                            }
                            else
                            {
                                Write-Verbose "UDP test to ${computer}:${targetPort} - socket error: $errorCode"

                                $result = [PSCustomObject]@{
                                    PSTypeName = 'PortTest.Result'
                                    Server = $computer
                                    Port = $targetPort
                                    Protocol = 'UDP'
                                    Open = $false
                                    Status = "Socket error: $errorCode"
                                    ResponseTime = $stopwatch.ElapsedMilliseconds
                                }
                                [void]$results.Add($result)
                            }
                        }
                        catch
                        {
                            $stopwatch.Stop()
                            Write-Verbose "UDP test to ${computer}:${targetPort} - unexpected error: $($_.Exception.Message)"

                            $result = [PSCustomObject]@{
                                PSTypeName = 'PortTest.Result'
                                Server = $computer
                                Port = $targetPort
                                Protocol = 'UDP'
                                Open = $false
                                Status = "Error: $($_.Exception.Message)"
                                ResponseTime = $stopwatch.ElapsedMilliseconds
                            }
                            [void]$results.Add($result)
                        }
                    }
                    catch
                    {
                        $stopwatch.Stop()
                        Write-Verbose "UDP test setup error for ${computer}:${targetPort}: $($_.Exception.Message)"

                        $result = [PSCustomObject]@{
                            PSTypeName = 'PortTest.Result'
                            Server = $computer
                            Port = $targetPort
                            Protocol = 'UDP'
                            Open = $false
                            Status = "Setup error: $($_.Exception.Message)"
                            ResponseTime = $stopwatch.ElapsedMilliseconds
                        }
                        [void]$results.Add($result)
                    }
                    finally
                    {
                        if ($null -ne $udpClient)
                        {
                            try
                            {
                                $udpClient.Close()
                            }
                            catch
                            {
                                Write-Debug "Error closing UDP client: $($_.Exception.Message)"
                            }
                            $udpClient.Dispose()
                        }
                    }
                }
            }
        }

        return $results.ToArray()
    }
}
