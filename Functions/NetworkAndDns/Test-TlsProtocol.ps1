function Test-TlsProtocol
{
    <#
    .SYNOPSIS
        Tests which TLS protocols are supported by a remote server.

    .DESCRIPTION
        Tests TLS protocol support on remote servers by attempting connections using
        different TLS versions (TLS 1.0, 1.1, 1.2, and 1.3). It works with any TCP-based
        service that uses TLS for encryption, not just HTTPS. Returns detailed information
        about which protocols are supported or rejected.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER ComputerName
        The target server hostname or IP address to test.
        Default is 'localhost'.

    .PARAMETER Port
        The TCP port to test. Default is 443 (HTTPS).
        Valid range: 1-65535.

    .PARAMETER Timeout
        Connection timeout in milliseconds. Default is 3000 (3 seconds).
        Valid range: 100-30000 (30 seconds).

    .PARAMETER Protocol
        Specific TLS protocol(s) to test. If not specified, all protocols are tested.
        Valid values: Tls, Tls11, Tls12, Tls13

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'bing.com'

        Server       : bing.com
        Port         : 443
        Protocol     : Tls
        Supported    : False
        Status       : Connection failed
        ResponseTime : 00:00:00.0234567

        Server       : bing.com
        Port         : 443
        Protocol     : Tls11
        Supported    : False
        Status       : Connection failed
        ResponseTime : 00:00:00.0187654

        Server       : bing.com
        Port         : 443
        Protocol     : Tls12
        Supported    : True
        Status       : Success
        ResponseTime : 00:00:00.1234567

        Server       : bing.com
        Port         : 443
        Protocol     : Tls13
        Supported    : True
        Status       : Success
        ResponseTime : 00:00:00.1123456

        Tests all TLS protocols on bing.com:443.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'github.com' -Protocol Tls12,Tls13

        Server       : github.com
        Port         : 443
        Protocol     : Tls12
        Supported    : True
        Status       : Success
        ResponseTime : 00:00:00.2345678

        Server       : github.com
        Port         : 443
        Protocol     : Tls13
        Supported    : True
        Status       : Success
        ResponseTime : 00:00:00.2123456

        Tests only TLS 1.2 and 1.3 on github.com:443.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'example.com' -Port 8443 -Timeout 10000

        Tests TLS protocols on example.com:8443 with a 10-second timeout.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'server.com' | Where-Object { $_.Supported }

        Tests all TLS protocols and filters to show only supported ones.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'smtp.gmail.com' -Port 465

        Server       : smtp.gmail.com
        Port         : 465
        Protocol     : Tls
        Supported    : True
        Status       : Success
        ResponseTime : 00:00:00.3033514

        Server       : smtp.gmail.com
        Port         : 465
        Protocol     : Tls11
        Supported    : True
        Status       : Success
        ResponseTime : 00:00:00.1057390

        Server       : smtp.gmail.com
        Port         : 465
        Protocol     : Tls12
        Supported    : True
        Status       : Success
        ResponseTime : 00:00:00.1216716

        Server       : smtp.gmail.com
        Port         : 465
        Protocol     : Tls13
        Supported    : True
        Status       : Success
        ResponseTime : 00:00:00.0887873

        Tests TLS protocols on the Gmail SMTPS service.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'imap.mail.me.com' -Port 993

        Server       : imap.mail.me.com
        Port         : 993
        Protocol     : Tls
        Supported    : False
        Status       : Not supported by server
        ResponseTime : 00:00:00.1503006

        Server       : imap.mail.me.com
        Port         : 993
        Protocol     : Tls11
        Supported    : False
        Status       : Not supported by server
        ResponseTime : 00:00:00.0866580

        Server       : imap.mail.me.com
        Port         : 993
        Protocol     : Tls12
        Supported    : True
        Status       : Success
        ResponseTime : 00:00:00.2287825

        Server       : imap.mail.me.com
        Port         : 993
        Protocol     : Tls13
        Supported    : True
        Status       : Success
        ResponseTime : 00:00:00.0850641

        Tests TLS protocols on the iCloud IMAPS service.

    .OUTPUTS
        PSCustomObject
        Returns objects with Server, Port, Protocol, Supported, Status, and ResponseTime properties.

    .NOTES
        This function uses .NET's SslStream class for cross-platform TLS testing.
        On macOS and Linux, if OpenSSL is available, it will be used as a fallback for more
        accurate TLS protocol detection when .NET limitations are encountered.

        Some older TLS versions (1.0, 1.1) may not be available on modern systems.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Test-TlsProtocol.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Test-TlsProtocol.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('Server', 'Host', 'HostName')]
        [String]$ComputerName = 'localhost',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [Int]$Port = 443,

        [Parameter(Mandatory = $false)]
        [ValidateRange(100, 30000)]
        [Int]$Timeout = 3000,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Tls', 'Tls11', 'Tls12', 'Tls13')]
        [String[]]$Protocol
    )

    begin
    {
        Write-Verbose 'Starting TLS protocol testing'

        # Detect platform for platform-specific behavior
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # PowerShell 5.1 - Windows only
            $isMacOsPlatform = $false
            $isLinuxPlatform = $false
            $useOpenSslFallback = $false
        }
        else
        {
            # PowerShell Core - use built-in variables
            $isMacOsPlatform = $IsMacOS
            $isLinuxPlatform = $IsLinux

            # Check if OpenSSL is available on macOS/Linux for fallback
            $useOpenSslFallback = $false
            if ($isMacOsPlatform -or $isLinuxPlatform)
            {
                $opensslPath = Get-Command -Name 'openssl' -CommandType Application -ErrorAction SilentlyContinue
                if ($opensslPath)
                {
                    $useOpenSslFallback = $true
                    Write-Verbose "OpenSSL found at: $($opensslPath.Source)"
                }
                else
                {
                    Write-Verbose 'OpenSSL not found - will use .NET only (may have TLS 1.3 limitations)'
                }
            }
        }

        # Define all TLS protocols to test if not specified
        if (-not $Protocol)
        {
            $Protocol = @('Tls', 'Tls11', 'Tls12', 'Tls13')
            Write-Verbose "No specific protocols specified, testing all: $($Protocol -join ', ')"
        }

        # Map protocol names to .NET SslProtocols enum values (for SslStream)
        # This ensures we test the exact protocol, not allowing fallback/negotiation
        $protocolMapping = @{
            'Tls' = [System.Security.Authentication.SslProtocols]::Tls
            'Tls11' = [System.Security.Authentication.SslProtocols]::Tls11
            'Tls12' = [System.Security.Authentication.SslProtocols]::Tls12
        }

        # TLS 1.3 support (available in .NET Core 3.0+ and .NET Framework 4.8+)
        if ($PSVersionTable.PSVersion.Major -ge 6)
        {
            # PowerShell Core - TLS 1.3 may be available
            try
            {
                $tls13Value = [System.Security.Authentication.SslProtocols]::Tls13
                $protocolMapping['Tls13'] = $tls13Value
                Write-Verbose 'TLS 1.3 support detected'
            }
            catch
            {
                Write-Verbose 'TLS 1.3 not available in this .NET version'
            }
        }
        else
        {
            # PowerShell 5.1 - Check if running on .NET Framework 4.8+
            try
            {
                $frameworkVersion = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
                Write-Verbose "Framework: $frameworkVersion"

                # Try to access Tls13 enum value
                $tls13Value = [System.Security.Authentication.SslProtocols]::Tls13
                $protocolMapping['Tls13'] = $tls13Value
                Write-Verbose 'TLS 1.3 support detected'
            }
            catch
            {
                Write-Verbose 'TLS 1.3 not available in this .NET version'
            }
        }

        # Map protocol names to OpenSSL protocol flags
        $opensslProtocolMap = @{
            'Tls' = '-tls1'
            'Tls11' = '-tls1_1'
            'Tls12' = '-tls1_2'
            'Tls13' = '-tls1_3'
        }
    }

    process
    {
        foreach ($targetProtocol in $Protocol)
        {
            Write-Verbose "Testing $targetProtocol on ${ComputerName}:${Port}"

            $result = [PSCustomObject]@{
                Server = $ComputerName
                Port = $Port
                Protocol = $targetProtocol
                Supported = $false
                Status = 'Unknown'
                ResponseTime = [TimeSpan]::Zero
            }

            # Check if this protocol is available on this system
            if (-not $protocolMapping.ContainsKey($targetProtocol))
            {
                $result.Supported = $false
                $result.Status = 'Protocol not available on this system'
                Write-Verbose "$targetProtocol is not available on this system"
                $result
                continue
            }

            # Determine if we should use OpenSSL fallback for this test
            $shouldUseOpenSsl = $false
            if ($useOpenSslFallback)
            {
                # Use OpenSSL fallback for TLS 1.3 on macOS/Linux due to .NET limitations
                if ($targetProtocol -eq 'Tls13' -and ($isMacOsPlatform -or $isLinuxPlatform))
                {
                    $shouldUseOpenSsl = $true
                    $platformName = if ($isMacOsPlatform) { 'macOS' } else { 'Linux' }
                    Write-Verbose "Using OpenSSL fallback for $targetProtocol on $platformName"
                }
            }

            # Test using OpenSSL if appropriate
            if ($shouldUseOpenSsl)
            {
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                try
                {
                    $opensslFlag = $opensslProtocolMap[$targetProtocol]

                    Write-Verbose "Running: Write-Output '' | openssl s_client -connect ${ComputerName}:${Port} $opensslFlag -servername ${ComputerName}"

                    # Run OpenSSL s_client to test the protocol
                    $opensslOutput = Write-Output '' | openssl s_client -connect "${ComputerName}:${Port}" $opensslFlag -servername $ComputerName 2>&1 $stopwatch.Stop()

                    # Check if connection was successful
                    if ($opensslOutput -match 'Protocol\s*:\s*TLSv')
                    {
                        $negotiatedProtocol = ($opensslOutput | Select-String 'Protocol\s*:\s*(\S+)').Matches.Groups[1].Value
                        $result.Supported = $true
                        $result.Status = 'Success (via OpenSSL)'
                        $result.ResponseTime = $stopwatch.Elapsed
                        Write-Verbose "$targetProtocol handshake successful via OpenSSL - Negotiated: $negotiatedProtocol"
                    }
                    elseif ($opensslOutput -match 'ssl handshake failure|wrong version number|no protocols available|unsupported protocol')
                    {
                        $result.Supported = $false
                        $result.Status = 'Not supported by server'
                        $result.ResponseTime = $stopwatch.Elapsed
                        Write-Verbose "$targetProtocol not supported (OpenSSL handshake failed)"
                    }
                    elseif ($opensslOutput -match 'Connection refused|Connection timed out|Name or service not known')
                    {
                        $result.Supported = $false
                        $result.Status = 'Connection failed'
                        $result.ResponseTime = $stopwatch.Elapsed
                        Write-Verbose "$targetProtocol connection failed via OpenSSL"
                    }
                    else
                    {
                        $result.Supported = $false
                        $result.Status = 'Unable to determine (OpenSSL test inconclusive)'
                        $result.ResponseTime = $stopwatch.Elapsed
                        Write-Verbose "$targetProtocol OpenSSL test inconclusive"
                    }
                }
                catch
                {
                    $stopwatch.Stop()
                    $result.Status = "OpenSSL error: $($_.Exception.Message)"
                    $result.ResponseTime = $stopwatch.Elapsed
                    Write-Verbose "OpenSSL error for $targetProtocol : $($_.Exception.Message)"
                }

                $result
                continue
            }

            # Use .NET SslStream for testing
            $tcpClient = $null
            $sslStream = $null
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try
            {
                # Create TCP connection with proper timeout handling
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                Write-Verbose "Connecting to ${ComputerName}:${Port}..."

                # Attempt TCP connection with timeout using IAsyncResult pattern
                try
                {
                    $connectResult = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
                    $waitHandle = $connectResult.AsyncWaitHandle

                    # Wait for connection with timeout
                    if (-not $waitHandle.WaitOne($Timeout, $false))
                    {
                        # Timeout occurred
                        $stopwatch.Stop()
                        $tcpClient.Close()
                        $result.Status = 'Connection timeout'
                        $result.ResponseTime = $stopwatch.Elapsed
                        Write-Verbose "Connection timeout after ${Timeout}ms"
                        $result
                        continue
                    }

                    # Complete the connection
                    $tcpClient.EndConnect($connectResult)
                    $waitHandle.Close()
                }
                catch
                {
                    $stopwatch.Stop()
                    $result.Status = "Connection failed: $($_.Exception.InnerException.Message)"
                    $result.ResponseTime = $stopwatch.Elapsed
                    Write-Verbose "Failed to connect to ${ComputerName}:${Port} - $($_.Exception.InnerException.Message)"
                    $result
                    continue
                }

                if (-not $tcpClient.Connected)
                {
                    $stopwatch.Stop()
                    $result.Status = 'Connection failed'
                    $result.ResponseTime = $stopwatch.Elapsed
                    Write-Verbose "Failed to connect to ${ComputerName}:${Port}"
                    $result
                    continue
                }

                Write-Verbose 'TCP connection established'

                # Create a simple certificate validation callback that accepts all certificates
                # This is needed for testing TLS protocol support regardless of certificate validity
                $certCallback = {
                    param($certSender, $certificate, $chain, $sslPolicyErrors)
                    return $true
                }

                # Set timeouts for SSL stream
                $networkStream = $tcpClient.GetStream()
                $networkStream.ReadTimeout = $Timeout
                $networkStream.WriteTimeout = $Timeout

                # Create SSL stream with specific TLS protocol
                $sslStream = New-Object System.Net.Security.SslStream(
                    $networkStream,
                    $false,
                    $certCallback
                )

                # Get the protocol value from mapping
                $protocolValue = $protocolMapping[$targetProtocol]
                Write-Verbose "Attempting TLS handshake with protocol: $targetProtocol ($protocolValue)"

                # Attempt SSL/TLS handshake with specific protocol
                try
                {
                    # Use the AuthenticateAsClient overload that accepts specific SslProtocols
                    # This prevents protocol negotiation and tests only the specified protocol
                    $sslStream.AuthenticateAsClient(
                        $ComputerName,
                        $null,  # client certificates
                        $protocolValue,  # enabled SSL protocols (specific one we're testing)
                        $false  # check certificate revocation
                    )

                    if ($sslStream.IsAuthenticated)
                    {
                        $stopwatch.Stop()
                        $result.Supported = $true
                        $result.Status = 'Success'
                        $result.ResponseTime = $stopwatch.Elapsed
                        Write-Verbose "$targetProtocol handshake successful in $($stopwatch.ElapsedMilliseconds)ms"
                    }
                    else
                    {
                        $stopwatch.Stop()
                        $result.Status = 'Authentication failed'
                        $result.ResponseTime = $stopwatch.Elapsed
                        Write-Verbose "$targetProtocol authentication failed"
                    }
                }
                catch
                {
                    $stopwatch.Stop()

                    # Provide helpful error messages
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'Authentication failed')
                    {
                        $result.Status = 'Not supported by server'
                    }
                    else
                    {
                        $result.Status = "Handshake failed: $errorMessage"
                    }

                    $result.ResponseTime = $stopwatch.Elapsed
                    Write-Verbose "$targetProtocol handshake error: $errorMessage"
                }
            }
            catch
            {
                $stopwatch.Stop()
                $result.Status = "Error: $($_.Exception.Message)"
                $result.ResponseTime = $stopwatch.Elapsed
                Write-Verbose "Error testing $targetProtocol : $($_.Exception.Message)"
            }
            finally
            {
                # Clean up resources
                if ($null -ne $sslStream)
                {
                    try { $sslStream.Dispose() } catch { $null = $_ }
                }
                if ($null -ne $tcpClient)
                {
                    try { $tcpClient.Dispose() } catch { $null = $_ }
                }
            }

            # Output result
            $result
        }
    }

    end
    {
        Write-Verbose 'TLS protocol testing completed'
    }
}
