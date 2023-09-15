function Test-Port
{
    <#
    .SYNOPSIS
        Tests a TCP or UPP port for connectivity.

    .DESCRIPTION
        Tests a TCP or UPP port for connectivity.

    .PARAMETER ComputerName
        Name of server to test the port connection on.

    .PARAMETER Port
        Port to test

    .PARAMETER Tcp
        Use tcp port.

    .PARAMETER Udp
        Use udp port

    .PARAMETER Timeout
        Sets a timeout (in milliseconds) for port query.
        The default is '3000' (3 seconds).

    .NOTES
        Name: Test-Port.ps1
        Author: Boe Prox
        DateCreated: 18Aug2010
        List of Ports: http://www.iana.org/assignments/port-numbers

        Update by Jon LaBelle, 9/29/2022
        TODO: Add capability to run background jobs for each host to shorten the time to scan.

    .EXAMPLE
        PS > Test-Port -ComputerName 'server' -Port 80

        Checks port 80 on server 'server' to see if it is listening

    .EXAMPLE
        PS > 'server' | Test-Port -Port 80

        Checks port 80 on server 'server' to see if it is listening

    .EXAMPLE
        PS > Test-Port -ComputerName @("server1","server2") -Port 80

        Checks port 80 on server1 and server2 to see if it is listening

    .EXAMPLE
        PS > Test-Port -ComputerName dc1 -Port 17 -Udp -Timeout 10000

        Server   : dc1
        Port     : 17
        TypePort : UDP
        Open     : True
        Status   : Connection successful.

        Queries port 17 (qotd) on the UDP port and returns whether port is open or not.

    .EXAMPLE
        PS > @("server1","server2") | Test-Port -Port 80

        Checks port 80 on server1 and server2 to see if it is listening.

    .EXAMPLE
        PS > (Get-Content hosts.txt) | Test-Port -Port 80

        Checks port 80 on servers in host file to see if it is listening.

    .EXAMPLE
        PS > Test-Port -ComputerName (Get-Content hosts.txt) -Port 80

        Checks port 80 on servers in host file to see if it is listening.

    .EXAMPLE
        PS > Test-Port -ComputerName (Get-Content hosts.txt) -Port @(1..59)

        Checks a range of ports from 1-59 on all servers in the hosts.txt file.

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
                    $output = '' | Select-Object Server, Port, TypePort, Open, Status

                    # Create object for connecting to port on ComputerName
                    $tcpobject = New-Object System.Net.Sockets.TcpClient

                    # Connect to remote machine's port
                    $connect = $tcpobject.BeginConnect($computer, $targetPort, $null, $null)

                    # Configure a timeout before quitting
                    $wait = $connect.AsyncWaitHandle.WaitOne($Timeout, $false)

                    # if timeout
                    if (!$wait)
                    {
                        # Close connection
                        $tcpobject.Close()

                        Write-Verbose 'Connection timeout'

                        # Build report
                        $output.Server = $computer
                        $output.Port = $targetPort
                        $output.TypePort = 'TCP'
                        $output.Open = $false
                        $output.Status = 'Connection timed out.'
                    }
                    else
                    {
                        $error.Clear()
                        $tcpobject.EndConnect($connect) | Out-Null

                        # if error
                        if ($error[0])
                        {
                            # Begin making error more readable in report
                            [string]$string = ($error[0].exception).message
                            $message = (($string.split(':')[1]).replace('"', '')).TrimStart()
                            $failed = $true
                        }

                        # Close connection
                        $tcpobject.Close()

                        # if unable to query port to due failure
                        if ($failed)
                        {
                            # Build report
                            $output.Server = $computer
                            $output.Port = $targetPort
                            $output.TypePort = 'TCP'
                            $output.Open = $false
                            $output.Status = "$message"
                        }
                        else
                        {
                            # Build report
                            $output.Server = $computer
                            $output.Port = $targetPort
                            $output.TypePort = 'TCP'
                            $output.Open = 'True'
                            $output.Status = 'Connection successful.'
                        }
                    }

                    # Reset failed value
                    $failed = $Null

                    # Merge temp array with report
                    $report += $output
                }

                if ($Udp)
                {
                    # Create temporary holder
                    $output = '' | Select-Object Server, Port, TypePort, Open, Status

                    # Create object for connecting to port on ComputerName
                    $udpobject = New-Object System.Net.Sockets.Udpclient

                    # Set a timeout on receiving message
                    $udpobject.client.ReceiveTimeout = $Timeout

                    # Connect to remote machine's port
                    Write-Verbose 'Making UDP connection to remote server'
                    $udpobject.Connect("$computer", $targetPort)

                    # Sends a message to the host to which you have connected.
                    Write-Verbose 'Sending message to remote host'
                    $a = New-Object system.text.asciiencoding
                    $byte = $a.GetBytes("$(Get-Date)")
                    [void]$udpobject.Send($byte, $byte.length)

                    # IPEndPoint object will allow us to read datagrams sent from any source.
                    Write-Verbose 'Creating remote endpoint'

                    $remoteendpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)

                    try
                    {
                        # Blocks until a message returns on this socket from a remote host.
                        Write-Verbose 'Waiting for message return'
                        $receivebytes = $udpobject.Receive([ref]$remoteendpoint)

                        [string]$returndata = $a.GetString($receivebytes)
                        if ($returndata)
                        {
                            Write-Verbose 'Connection successful'

                            # Build report
                            $output.Server = $computer
                            $output.Port = $targetPort
                            $output.TypePort = 'UDP'
                            $output.Open = 'True'
                            $output.Status = $returndata
                            $udpobject.close()
                        }
                    }
                    catch
                    {
                        if ($Error[0].ToString() -match '\bRespond after a period of time\b')
                        {
                            # Close connection
                            $udpobject.Close()

                            # Make sure that the host is online and not a false-positive
                            if (Test-Connection -comp $computer -Count 1 -Quiet)
                            {
                                Write-Verbose 'Connection Open'

                                # Build report
                                $output.Server = $computer
                                $output.Port = $targetPort
                                $output.TypePort = 'UDP'
                                $output.Open = 'True'
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
                                $output.TypePort = 'UDP'
                                $output.Open = $false
                                $output.Status = 'Host is unreachable.'
                            }
                        }
                        elseif ($Error[0].ToString() -match 'forcibly closed by the remote host' )
                        {
                            # Close connection
                            $udpobject.Close()

                            Write-Verbose 'Connection timeout'

                            # Build report
                            $output.Server = $computer
                            $output.Port = $targetPort
                            $output.TypePort = 'UDP'
                            $output.Open = $false
                            $output.Status = 'Connection timed out.'
                        }
                        else
                        {
                            $udpobject.close()
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
