function Send-TcpRequest
{
    <#
    .SYNOPSIS
        Send a TCP request to a remote computer and return the response.
        Supports both interactive and scripted modes with optional SSL encryption.

    .DESCRIPTION
        This function establishes a TCP connection to a remote computer on a specified port
        and sends data to it. It can operate in two modes:
        - Scripted mode: Send predefined data and return the response
        - Interactive mode: Provide a command-line interface for real-time communication

        The function supports SSL/TLS encryption and includes connection testing capabilities.

    .PARAMETER ComputerName
        The hostname or IP address of the remote computer to connect to.
        Default is 'localhost'.

    .PARAMETER Port
        The TCP port number to connect to on the remote computer.
        Default is 80 (HTTP).

    .PARAMETER Test
        When specified, only tests the connection without sending data.
        Returns $true if connection is successful, $false otherwise.

    .PARAMETER UseSSL
        When specified, establishes an SSL/TLS encrypted connection.
        The SSL stream will authenticate as a client using the ComputerName.

    .PARAMETER InputObject
        The data to send to the remote host. If not provided, the function
        operates in interactive mode where you can type commands manually.

    .PARAMETER Delay
        The delay in milliseconds to wait between sending commands.
        Default is 100ms. Useful for rate limiting or ensuring proper command processing.

    .PARAMETER Timeout
        The timeout in seconds for connection and read operations.
        Default is 30 seconds.

    .EXAMPLE
        PS > Send-TcpRequest -ComputerName "www.google.com" -Port 80 -Test

        Test if a web server is accessible.

    .EXAMPLE
        PS > $httpRequest = @"
            GET / HTTP/1.1
            Host: www.example.com
            Connection: close
        "@

        Send-TcpRequest -ComputerName "www.example.com" -Port 80 -InputObject $httpRequest

        Send an HTTP GET request.

    .EXAMPLE
        PS > $httpsRequest = @"
            GET /api/status HTTP/1.1
            Host: api.example.com
        "@

        Send-TcpRequest -ComputerName "api.example.com" -Port 443 -UseSSL -InputObject $httpsRequest

        Connect to an HTTPS server.

    .EXAMPLE
        PS > Send-TcpRequest -ComputerName "telnet.server.com" -Port 23

        Interactive mode for debugging.

    .EXAMPLE
        PS > Send-TcpRequest -ComputerName "myserver.com" -Port 22 -Test

        Test SSH connectivity.

    .EXAMPLE
        PS > "QUIT" | Send-TcpRequest -ComputerName "mail.server.com" -Port 25 -Timeout 60

        Send data via pipeline with custom timeout.

    .OUTPUTS
        System.String
        Returns the response from the remote server when in scripted mode.
        In test mode, returns System.Boolean indicating connection success.

    .NOTES
        Author: Lee Holmes (adapted and enhanced)
        From: Windows PowerShell Cookbook (O'Reilly)
        URL: http://www.leeholmes.com/guide

        Enhanced with improved error handling, parameter validation, timeout support,
        and comprehensive documentation.
    #>

    [CmdletBinding()]
    param(
        ## The computer to connect to
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $ComputerName = 'localhost',

        ## The port to use
        [Parameter(Position = 1)]
        [ValidateRange(1, 65535)]
        [int] $Port = 80,

        ## A switch to determine if you just want to test the connection
        [switch] $Test,

        ## A switch to determine if the connection should be made using SSL
        [switch] $UseSSL,

        ## The input string to send to the remote host
        [Parameter(ValueFromPipeline = $true)]
        [string[]] $InputObject,

        ## The delay, in milliseconds, to wait between commands
        [ValidateRange(0, 60000)]
        [int] $Delay = 100,

        ## The timeout, in seconds, for connection and read operations
        [ValidateRange(1, 300)]
        [int] $Timeout = 30
    )

    begin
    {
        [string] $SCRIPT:output = ''
        $inputLines = @()
    }

    process
    {
        if ($InputObject)
        {
            $inputLines += $InputObject
        }
    }

    end
    {
        ## Store the input into an array that we can scan over. If there was no input,
        ## then we will be in interactive mode.
        $currentInput = $inputLines
        if (-not $currentInput -or $currentInput.Count -eq 0)
        {
            $currentInput = @()
        }
        $scriptedMode = ($currentInput.Count -gt 0) -or $Test

        function Main
        {
            ## Open the socket, and connect to the computer on the specified port
            if (-not $scriptedMode)
            {
                Write-Host "Connecting to $ComputerName on port $Port"
            }

            $socket = $null
            try
            {
                $socket = New-Object Net.Sockets.TcpClient
                $socket.ReceiveTimeout = $Timeout * 1000
                $socket.SendTimeout = $Timeout * 1000

                Write-Verbose "Attempting to connect to $ComputerName on port $Port"
                $connectTask = $socket.ConnectAsync($ComputerName, $Port)
                if (-not $connectTask.Wait($Timeout * 1000))
                {
                    throw "Connection timeout after $Timeout seconds"
                }
            }
            catch
            {
                if ($Test) { return $false }
                else
                {
                    Write-Error "Could not connect to remote computer: $_"
                    return
                }
            }

            ## If we're just testing the connection, we've made the connection
            ## successfully, so just return $true
            if ($Test)
            {
                $socket.Close()
                return $true
            }

            ## If this is interactive mode, supply the prompt
            if (-not $scriptedMode)
            {
                Write-Host "Connected.  Press ^D followed by [ENTER] to exit.`n"
            }

            $stream = $socket.GetStream()

            ## If we wanted to use SSL, set up that portion of the connection
            if ($UseSSL)
            {
                try
                {
                    $sslStream = New-Object System.Net.Security.SslStream $stream, $false
                    $sslStream.AuthenticateAsClient($ComputerName)
                    $stream = $sslStream
                    Write-Verbose 'SSL connection established successfully'
                }
                catch
                {
                    Write-Error "Failed to establish SSL connection: $_"
                    $socket.Close()
                    return
                }
            }

            $writer = New-Object System.IO.StreamWriter $stream

            try
            {
                while ($true)
                {
                    ## Receive the output that has buffered so far
                    $SCRIPT:output += GetOutput

                    ## If we're in scripted mode, send the commands,
                    ## receive the output, and exit.
                    if ($scriptedMode)
                    {
                        foreach ($line in $currentInput)
                        {
                            Write-Verbose "Sending: $line"
                            $writer.WriteLine($line)
                            $writer.Flush()
                            Start-Sleep -Milliseconds $Delay
                            $SCRIPT:output += GetOutput
                        }

                        break
                    }
                    ## If we're in interactive mode, write the buffered
                    ## output, and respond to input.
                    else
                    {
                        if ($output)
                        {
                            foreach ($line in $output.Split("`n"))
                            {
                                Write-Host $line
                            }
                            $SCRIPT:output = ''
                        }

                        ## Read the user's command, quitting if they hit ^D
                        $command = Read-Host
                        if ($command -eq ([char] 4)) { break; }

                        ## Otherwise, Write their command to the remote host
                        $writer.WriteLine($command)
                        $writer.Flush()
                    }
                }
            }
            catch
            {
                Write-Error "Error during communication: $_"
            }
            finally
            {
                ## Close the streams
                if ($writer) { $writer.Close() }
                if ($stream) { $stream.Close() }
                if ($socket) { $socket.Close() }
            }

            ## If we're in scripted mode, return the output
            if ($scriptedMode)
            {
                return $output
            }
        }

        ## Read output from a remote host
        function GetOutput
        {
            ## Create a buffer to receive the response
            $buffer = New-Object System.Byte[] 1024
            $encoding = New-Object System.Text.AsciiEncoding

            $outputBuffer = ''
            $foundMore = $false

            ## Read all the data available from the stream, writing it to the
            ## output buffer when done.
            do
            {
                ## Allow data to buffer for a bit
                Start-Sleep -Milliseconds 1000

                ## Read what data is available
                $foundMore = $false
                $stream.ReadTimeout = $Timeout * 1000

                do
                {
                    try
                    {
                        $read = $stream.Read($buffer, 0, 1024)

                        if ($read -gt 0)
                        {
                            $foundMore = $true
                            $outputBuffer += ($encoding.GetString($buffer, 0, $read))
                        }
                    }
                    catch
                    {
                        $foundMore = $false
                        $read = 0
                        Write-Verbose 'Read timeout or connection closed'
                    }
                } while ($read -gt 0)
            } while ($foundMore)

            return $outputBuffer
        }

        return (Main)
    } # end block
}
