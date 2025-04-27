function Test-Port
{
    <#
    .SYNOPSIS
        Tests TCP or UDP port connectivity to target hosts.

    .DESCRIPTION
        Tests whether specific TCP or UDP ports are open and accessible on target hosts.
        Provides detailed connection information including success status and connection details.

    .PARAMETER Port
        Port numbers to test. Accepts an array of port numbers.

    .PARAMETER ComputerName
        Target hosts to test. Accepts an array of computer names or IP addresses.
        If not specified, 'localhost' is used as the default.

    .PARAMETER Timeout
        Sets a timeout (in milliseconds) for port query.
        The default is 3000 (3 seconds).

    .PARAMETER Tcp
        Use this switch to test TCP ports. If neither Tcp nor Udp is specified, Tcp is used by default.

    .PARAMETER Udp
        Use this switch to test UDP ports.

    .EXAMPLE
        PS > Test-Port -ComputerName 'server' -Port 80
        Tests if TCP port 80 is open on server 'server'.

    .EXAMPLE
        PS > 'server' | Test-Port -Port 80
        Tests if TCP port 80 is open on server 'server' using pipeline input.

    .EXAMPLE
        PS > Test-Port -ComputerName @("server1","server2") -Port 80
        Tests if TCP port 80 is open on both server1 and server2.

    .EXAMPLE
        PS > Test-Port -ComputerName dc1 -Port 17 -Udp -Timeout 10000
        Tests if UDP port 17 is open on server dc1 with a 10-second timeout.

    .EXAMPLE
        PS > @("server1","server2") | Test-Port -Port 80
        Tests if TCP port 80 is open on both server1 and server2 using pipeline input.

    .EXAMPLE
        PS > (Get-Content hosts.txt) | Test-Port -Port 80
        Tests if TCP port 80 is open on all servers listed in the hosts.txt file.

    .EXAMPLE
        PS > Test-Port -ComputerName (Get-Content hosts.txt) -Port @(1..59)
        Tests a range of ports from 1-59 on all servers in the hosts.txt file.

    .OUTPUTS
        System.Object[]
        Returns custom objects with server, port, protocol, connection status, and details.

    .NOTES
        Name: Test-Port.ps1
        Author: Boe Prox
        DateCreated: 18Aug2010
        Updated by Jon LaBelle, 9/29/2022

        Ports reference: http://www.iana.org/assignments/port-numbers

    .LINK
        https://learn-powershell.net/2011/02/21/querying-udp-ports-with-powershell/

    .LINK
        https://jonlabelle.com/snippets/view/powershell/test-tcp-or-udp-network-port-in-powershell
    #>
    [CmdletBinding(ConfirmImpact = 'low')]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [Int[]]$Port,

        [Parameter(Position = 1, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Alias('IPAddress', '__Server', 'CN')]
        [String[]]$ComputerName,

        [Parameter()]
        [Int]$Timeout = 3000,

        [Parameter()]
        [Switch]$Tcp,

        [Parameter()]
        [switch]$Udp
    )
    begin
    {
        if (!$Tcp -and !$Udp) {$Tcp = $true}

        if (-not $ComputerName -or $ComputerName.Count -eq 0)
        {
            $ComputerName = 'localhost'
        }

        # Typically you never do this, but in this case I felt it was for the benefit of the function
        # as any errors will be noted in the output of the report.
        #$ErrorActionPreference = 'SilentlyContinue'

        $report = @()
    }
    process
    {
        foreach ($computer in $ComputerName)
        {
            foreach ($targetPort in $Port)
            {
                if ($targetPort -gt 65535)
                {
                    throw ("Port '{0}' is out of range, and cannot be higher than 65,535." -f $targetPort)
                }

                if ($targetPort -le 0)
                {
                    throw ("Port '{0}' is out of range, and cannot be less than or equal to zero." -f $targetPort)
                }

                if ($Tcp)
                {
                    # Create temporary holder
                    $output = '' | Select-Object Server, Port, Protocol, Open, Status

                    # Create object for connecting to port on ComputerName
                    $tcpObject = New-Object System.Net.Sockets.TcpClient

                    # Connect to remote machine's port
                    $connect = $tcpObject.BeginConnect($computer, $targetPort, $null, $null)

                    # Configure a timeout before quitting
                    $wait = $connect.AsyncWaitHandle.WaitOne($Timeout, $false)

                    # if timeout
                    if (!$wait)
                    {
                        # Close connection
                        $tcpObject.Close()

                        Write-Verbose 'Connection timeout'

                        # Build report
                        $output.Server = $computer
                        $output.Port = $targetPort
                        $output.Protocol = 'TCP'
                        $output.Open = $false
                        $output.Status = 'Connection timed out.'
                    }
                    else
                    {
                        $error.Clear()

                        $failed = $false

                        try
                        {
                            $tcpObject.EndConnect($connect) | Out-Null
                        }
                        catch
                        {
                            if ($error[0])
                            {
                                # Begin making error more readable in report
                                [string]$string = ($error[0].exception).message
                                $message = (($string.split(':')[1]).replace('"', '')).TrimStart()
                                $failed = $true
                            }
                        }
                        finally
                        {
                            $tcpObject.Close()
                        }

                        # if unable to query port to due failure
                        if ($failed)
                        {
                            # Build report
                            $output.Server = $computer
                            $output.Port = $targetPort
                            $output.Protocol = 'TCP'
                            $output.Open = $false
                            $output.Status = "$message"
                        }
                        else
                        {
                            # Build report
                            $output.Server = $computer
                            $output.Port = $targetPort
                            $output.Protocol = 'TCP'
                            $output.Open = $true
                            $output.Status = 'Connection successful.'
                        }
                    }

                    # Reset failed value
                    $failed = $false

                    # Merge temp array with report
                    $report += $output
                }

                if ($Udp)
                {
                    # Create temporary holder
                    $output = '' | Select-Object Server, Port, Protocol, Open, Status

                    # Create object for connecting to port on ComputerName
                    $udpObject = New-Object System.Net.Sockets.UdpClient

                    # Set a timeout on receiving message
                    $udpObject.client.ReceiveTimeout = $Timeout

                    # Connect to remote machine's port
                    Write-Verbose 'Making UDP connection to remote server'
                    $udpObject.Connect("$computer", $targetPort)

                    # Sends a message to the host to which you have connected.
                    Write-Verbose 'Sending message to remote host'
                    $a = New-Object System.Text.ASCIIEncoding
                    $byte = $a.GetBytes("$(Get-Date)")
                    [void]$udpObject.Send($byte, $byte.length)

                    # IPEndPoint object will allow us to read data-grams sent from any source.
                    Write-Verbose 'Creating remote endpoint'

                    $remoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)

                    try
                    {
                        # Blocks until a message returns on this socket from a remote host.
                        Write-Verbose 'Waiting for message return'
                        $receiveBytes = $udpObject.Receive([ref]$remoteEndpoint)

                        [string]$returnData = $a.GetString($receiveBytes)
                        if ($returnData)
                        {
                            Write-Verbose 'Connection successful'

                            # Build report
                            $output.Server = $computer
                            $output.Port = $targetPort
                            $output.Protocol = 'UDP'
                            $output.Open = $true
                            $output.Status = $returnData
                            $udpObject.close()
                        }
                    }
                    catch
                    {
                        if ($Error[0].ToString() -match '\bRespond after a period of time\b')
                        {
                            # Close connection
                            $udpObject.Close()

                            # Make sure that the host is online and not a false-positive
                            if (Test-Connection -comp $computer -Count 1 -Quiet)
                            {
                                Write-Verbose 'Connection Open'

                                # Build report
                                $output.Server = $computer
                                $output.Port = $targetPort
                                $output.Protocol = 'UDP'
                                $output.Open = $true
                                $output.Status = 'Connection successful.'
                            }
                            else
                            {
                                <#
                                    It is possible that is online, but ICMP is blocked by a
                                    firewall and this port is actually open.
                                #>
                                Write-Verbose 'Host unreachable'

                                # Build report
                                $output.Server = $computer
                                $output.Port = $targetPort
                                $output.Protocol = 'UDP'
                                $output.Open = $false
                                $output.Status = 'Host is unreachable.'
                            }
                        }
                        elseif ($Error[0].ToString() -match 'forcibly closed by the remote host' )
                        {
                            # Close connection
                            $udpObject.Close()

                            Write-Verbose 'Connection timeout'

                            # Build report
                            $output.Server = $computer
                            $output.Port = $targetPort
                            $output.Protocol = 'UDP'
                            $output.Open = $false
                            $output.Status = 'Connection timed out.'
                        }
                        else
                        {
                            $udpObject.close()
                        }
                    }

                    # Merge temp array with report
                    $report += $output
                }
            }
        }
    }
    end
    {
        # Generate Report
        $report
    }
}
