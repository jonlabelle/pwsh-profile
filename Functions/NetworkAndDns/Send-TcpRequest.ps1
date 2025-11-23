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
        PS >
        $httpRequest = @"
            GET / HTTP/1.1
            Host: www.example.com
            Connection: close
        "@

        PS > Send-TcpRequest -ComputerName "www.example.com" -Port 80 -InputObject $httpRequest

        Send an HTTP GET request.

    .EXAMPLE
        PS > $httpsRequest = @"
            GET /api/status HTTP/1.1
            Host: api.example.com
        "@

        PS > Send-TcpRequest -ComputerName "api.example.com" -Port 443 -UseSSL -InputObject $httpsRequest

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

    .EXAMPLE
        PS > $smtpCommands = @(
            "HELO mydomain.com",
            "MAIL FROM:<test@mydomain.com>",
            "RCPT TO:<recipient@example.com>",
            "DATA",
            "Subject: Test Email",
            "",
            "This is a test message.",
            ".",
            "QUIT"
        )

        PS > Send-TcpRequest -ComputerName "smtp.server.com" -Port 587 -InputObject $smtpCommands

        Send multiple SMTP commands for email testing.

    .EXAMPLE
        PS > $ftpCommands = @(
            "USER anonymous",
            "PASS guest@example.com",
            "SYST",
            "PWD",
            "LIST",
            "QUIT"
        )

        PS > Send-TcpRequest -ComputerName "ftp.server.com" -Port 21 -InputObject $ftpCommands

        Connect to FTP server and execute basic commands.

    .EXAMPLE
        PS > $popCommands = @(
            "USER myusername",
            "PASS mypassword",
            "STAT",
            "LIST",
            "QUIT"
        )

        PS > Send-TcpRequest -ComputerName "pop.server.com" -Port 110 -InputObject $popCommands

        Check email via POP3 protocol.

    .EXAMPLE
        PS > $servers = @("web1.example.com", "web2.example.com", "web3.example.com")

        PS > $servers | ForEach-Object {
            "$_ : $(Send-TcpRequest -ComputerName $_ -Port 443 -Test)"
        }

        Test HTTPS connectivity across multiple servers.

    .EXAMPLE
        PS > $httpRequest = @"
            POST /api/data HTTP/1.1
            Host: api.example.com
            Content-Type: application/json
            Content-Length: 25

            {"key":"value","id":123}
        "@

        PS > Send-TcpRequest -ComputerName "api.example.com" -Port 443 -UseSSL -InputObject $httpRequest

        Send HTTP POST request with JSON payload over HTTPS.

    .EXAMPLE
        PS > Send-TcpRequest -ComputerName "irc.server.com" -Port 6667 -InputObject @(
            "NICK MyNickname",
            "USER MyNickname 0 * :Real Name",
            "JOIN #channel",
            "PRIVMSG #channel :Hello everyone!",
            "QUIT :Goodbye"
        )

        Connect to IRC server and send messages.

    .EXAMPLE
        PS > $redis = @("PING", "ECHO deploy-check") | ForEach-Object { "*1`r`n$($_.Length)`r`n$_`r`n" }
        PS > Send-TcpRequest -ComputerName 'cache.internal' -Port 6379 -InputObject $redis

        Smokes-tests a Redis instance from a build agent by sending RESP commands without needing redis-cli installed.

    .EXAMPLE
        PS > $timeRequest = [byte[]](0x1B) + [System.Text.Encoding]::ASCII.GetBytes(" ") * 47

        PS > Send-TcpRequest -ComputerName "time.nist.gov" -Port 37 -Test

        Test connection to time server (would need binary handling for actual time protocol).

    .EXAMPLE
        PS > $snppCommands = @(
            "PAGE 5551234567",
            "MESS Your server alert: Database backup completed successfully at $(Get-Date -Format 'HH:mm')",
            "SEND",
            "QUIT"
        )

        PS > Send-TcpRequest -ComputerName "pager.company.com" -Port 444 -InputObject $snppCommands

        Send a pager message using SNPP (Simple Network Paging Protocol).
        The protocol sends: PAGE (pager number), MESS (message text), SEND (transmit), QUIT (disconnect).

    .EXAMPLE
        PS > $wctpMessage = @"
            wctp-Submit: wctp-Submit
            wctp-Originator: admin@company.com
            wctp-Recipient: 5551234567@wireless.company.com
            wctp-MessageId: MSG$(Get-Random -Minimum 1000 -Maximum 9999)

            Subject: Server Alert

            URGENT: Web server disk space at 95% capacity. Immediate attention required.
        "@

        PS > Send-TcpRequest -ComputerName "wctp.gateway.com" -Port 444 -InputObject $wctpMessage

        Send a wireless message using WCTP (Wireless Communications Transfer Protocol).
        WCTP uses HTTP-style headers to send messages to wireless devices like pagers and phones.

    .OUTPUTS
        System.String
        Returns the response from the remote server when in scripted mode.
        In test mode, returns System.Boolean indicating connection success.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Send-TcpRequest.ps1

        Original Author: Lee Holmes, Windows PowerShell Cookbook (O'Reilly), https://www.leeholmes.com/guide

        Enhanced with improved error handling, parameter validation, timeout support,
        and comprehensive documentation.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '', Justification = 'Cleanup operations in finally block should not throw errors')]
    [CmdletBinding()]
    [OutputType([System.String], [System.Boolean])]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName = 'localhost',

        [Parameter(Position = 1)]
        [ValidateRange(1, 65535)]
        [Int32]$Port = 80,

        [Parameter()]
        [Switch]$Test,

        [Parameter()]
        [Switch]$UseSSL,

        [Parameter(ValueFromPipeline)]
        [String[]]$InputObject,

        [Parameter()]
        [ValidateRange(0, 60000)]
        [Int32]$Delay = 100,

        [Parameter()]
        [ValidateRange(1, 300)]
        [Int32]$Timeout = 30
    )

    begin
    {
        Write-Verbose 'Starting TCP request'

        # Initialize output buffer
        $outputBuffer = [System.Text.StringBuilder]::new()

        # Array to collect all input lines from pipeline
        $inputLines = [System.Collections.Generic.List[String]]::new()

        # Helper function to read available data from a network stream
        function Read-StreamOutput
        {
            [CmdletBinding()]
            [OutputType([String])]
            param(
                [Parameter(Mandatory)]
                [System.IO.Stream]$Stream,

                [Parameter(Mandatory)]
                [System.Text.Encoding]$Encoding,

                [Parameter(Mandatory)]
                [Int32]$Timeout
            )

            # Create 1KB buffer for receiving data
            $buffer = New-Object System.Byte[] 1024
            $outputData = [System.Text.StringBuilder]::new()
            $foundMore = $false

            # Read all available data from the stream
            do
            {
                # Allow time for data to buffer
                Start-Sleep -Milliseconds 1000

                # Attempt to read available data
                $foundMore = $false
                $Stream.ReadTimeout = $Timeout * 1000

                do
                {
                    try
                    {
                        $bytesRead = $Stream.Read($buffer, 0, 1024)
                        if ($bytesRead -gt 0)
                        {
                            $foundMore = $true
                            [void]$outputData.Append($Encoding.GetString($buffer, 0, $bytesRead))
                        }
                    }
                    catch [System.IO.IOException]
                    {
                        # Read timeout or connection closed - exit gracefully
                        $foundMore = $false
                        $bytesRead = 0
                        Write-Verbose 'Read timeout or connection closed'
                    }
                    catch
                    {
                        # Other exceptions
                        $foundMore = $false
                        $bytesRead = 0
                        Write-Verbose "Stream read error: $($_.Exception.Message)"
                    }
                } while ($bytesRead -gt 0)
            } while ($foundMore)

            return $outputData.ToString()
        }
    }

    process
    {
        # Collect input from pipeline if provided
        if ($InputObject)
        {
            foreach ($line in $InputObject)
            {
                $inputLines.Add($line)
            }
        }
    }

    end
    {
        # Determine operation mode: scripted (with input/test) or interactive
        $scriptedMode = ($inputLines.Count -gt 0) -or $Test

        # Display connection message in interactive mode
        if (-not $scriptedMode)
        {
            Write-Host "Connecting to $ComputerName on port $Port"
        }

        # Initialize TCP socket and configure timeouts
        $socket = $null
        $stream = $null
        $writer = $null

        try
        {
            $socket = New-Object System.Net.Sockets.TcpClient

            # Set timeouts in milliseconds
            $socket.ReceiveTimeout = $Timeout * 1000
            $socket.SendTimeout = $Timeout * 1000

            # Attempt async connection with timeout
            Write-Verbose "Attempting to connect to $ComputerName on port $Port"
            $connectTask = $socket.ConnectAsync($ComputerName, $Port)
            if (-not $connectTask.Wait($Timeout * 1000))
            {
                throw "Connection timeout after $Timeout seconds"
            }

            Write-Verbose 'Connection established successfully'

            # In test mode, connection was successful - return true
            if ($Test)
            {
                return $true
            }

            # Display interactive mode instructions
            if (-not $scriptedMode)
            {
                Write-Host "Connected. Press ^D followed by [ENTER] to exit.`n"
            }

            # Get the underlying network stream for communication
            $stream = $socket.GetStream()

            # Wrap the stream with SSL/TLS encryption if requested
            if ($UseSSL)
            {
                Write-Verbose 'Establishing SSL/TLS connection'
                $sslStream = New-Object System.Net.Security.SslStream $stream, $false
                $sslStream.AuthenticateAsClient($ComputerName)
                $stream = $sslStream
                Write-Verbose 'SSL connection established successfully'
            }

            # Create a StreamWriter for sending data to the remote host
            $writer = New-Object System.IO.StreamWriter $stream
            $encoding = New-Object System.Text.ASCIIEncoding

            # Main communication loop
            while ($true)
            {
                # Read any buffered output from the remote host
                $receivedData = Read-StreamOutput -Stream $stream -Encoding $encoding -Timeout $Timeout

                if ($receivedData)
                {
                    [void]$outputBuffer.Append($receivedData)
                }

                # Scripted mode: send all commands and collect responses
                if ($scriptedMode)
                {
                    foreach ($line in $inputLines)
                    {
                        Write-Verbose "Sending: $line"
                        $writer.WriteLine($line)
                        $writer.Flush()
                        Start-Sleep -Milliseconds $Delay

                        # Read response after each command
                        $receivedData = Read-StreamOutput -Stream $stream -Encoding $encoding -Timeout $Timeout
                        if ($receivedData)
                        {
                            [void]$outputBuffer.Append($receivedData)
                        }
                    }
                    break
                }
                # Interactive mode: display output and accept user input
                else
                {
                    # Display any received output
                    if ($receivedData)
                    {
                        foreach ($line in $receivedData.Split("`n"))
                        {
                            Write-Host $line
                        }
                    }

                    # Read user command, exit on Ctrl+D (character 4)
                    $command = Read-Host
                    if ($command -eq ([char]4))
                    {
                        break
                    }

                    # Send the user's command to the remote host
                    $writer.WriteLine($command)
                    $writer.Flush()
                }
            }

            # Return the collected output in scripted mode
            if ($scriptedMode)
            {
                return $outputBuffer.ToString()
            }
        }
        catch
        {
            # In test mode, return false on connection failure
            if ($Test)
            {
                Write-Verbose "Connection test failed: $($_.Exception.Message)"
                return $false
            }

            Write-Error "Error during TCP communication: $_"
        }
        finally
        {
            # Clean up all resources
            if ($writer)
            {
                try { $writer.Close() } catch { }
                try { $writer.Dispose() } catch { }
            }
            if ($stream)
            {
                try { $stream.Close() } catch { }
                try { $stream.Dispose() } catch { }
            }
            if ($socket)
            {
                try { $socket.Close() } catch { }
                try { $socket.Dispose() } catch { }
            }

            Write-Verbose 'TCP connection closed'
        }
    }
}
