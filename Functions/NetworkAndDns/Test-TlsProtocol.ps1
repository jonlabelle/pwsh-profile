function Test-TlsProtocol
{
    <#
    .SYNOPSIS
        Tests TLS protocol support and security evidence for a remote TCP service.

    .DESCRIPTION
        Tests one or more TLS versions by performing a real TLS handshake with a remote
        TCP service. Direct TLS is supported for HTTPS and other implicit-TLS services.
        Application-aware negotiation is available for SMTP, IMAP, POP3, FTP,
        PostgreSQL, MySQL, and SQL Server TDS 7.x endpoints.

        By default, the command preserves its original direct-TLS behavior and compact
        six-property result: Server, Port, Protocol, Supported, Status, and ResponseTime.

        Full mode replaces the compatibility Supported property with the explicitly
        scoped TlsHandshakeSupported and ServiceConnectionSupported properties. It also
        adds application-aware negotiation, requested and negotiated protocol evidence,
        cipher information, certificate identity and validation evidence, the validation
        scope, the failure stage and root cause, pre-TLS capabilities, and a security
        checkpoint based on MinimumProtocol.

        Full mode reports a failed or reset handshake as indeterminate
        unless the application negotiation provides direct evidence that TLS is
        unavailable. A network device, proxy, firewall, or inspection product can
        terminate a connection before it reaches the origin service.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER ComputerName
        The target server hostname or IP address. Default is 'localhost'.

    .PARAMETER Port
        The target TCP port. The basic mode defaults to 443. In Full mode,
        an omitted Port uses the conventional port for Service: Direct 443, SMTP 25,
        IMAP 143, POP3 110, FTP 21, PostgreSQL 5432, MySQL 3306, or SQL Server 1433.

    .PARAMETER Timeout
        The connection, application negotiation, and TLS I/O timeout in milliseconds.
        Default is 3000. Valid range: 100-30000.

    .PARAMETER Protocol
        The exact TLS protocol version or versions to test. If omitted, TLS 1.0, 1.1,
        1.2, and 1.3 are tested independently.

    .PARAMETER Service
        In Full mode, selects the application negotiation performed before
        the TLS handshake.

        Direct starts TLS immediately and covers HTTPS, LDAPS, SMTPS, IMAPS, POP3S,
        implicit FTPS, AMQPS, MQTT over TLS, and SQL Server TDS 8.0.

        Smtp, Imap, Pop3, and Ftp use their explicit STARTTLS or AUTH TLS commands.
        PostgreSql sends an SSLRequest, MySql sends an SSLRequest after the server
        handshake, and SqlServer performs TDS 7.x PRELOGIN encryption negotiation.

        SQL Server TDS 7.x encapsulates TLS handshake records in TDS packets and supports
        TLS through 1.2. To probe TDS 8.0 strict encryption, use Service Direct.

        This probe stops after PRELOGIN negotiation and the TLS handshake; it does not
        send LOGIN7 or authenticate to SQL Server. Some managed services, including Azure
        SQL Managed Instance, enforce their minimum TLS policy during SQL login rather
        than at this protocol layer. Review ValidationScope and ApplicationPolicyStatus
        before treating TlsHandshakeSupported as evidence that a SQL login would be
        accepted.

    .PARAMETER TlsHostName
        In Full mode, the DNS name used for SNI and certificate name
        validation. By default this is ComputerName. Set it when connecting to an IP
        address, alias, or load balancer whose certificate uses a different DNS name.

    .PARAMETER MinimumProtocol
        In Full mode, the minimum acceptable TLS protocol for the per-result
        SecurityStatus checkpoint. Default is Tls12. A successful handshake below this
        version normally fails the checkpoint. A SQL Server transport-layer result is
        reported as a warning when the application/login policy was not evaluated.

    .PARAMETER CheckCertificateRevocation
        In Full mode, requests certificate revocation checking during the
        handshake. This can add latency or fail on networks that cannot reach certificate
        revocation services.

    .PARAMETER Full
        Enables the application-aware and security-evidence result mode. This mode is
        required for Service, TlsHostName, MinimumProtocol, and CheckCertificateRevocation.
        Without this switch, the original direct TLS probe and compact output are used.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'www.example.com' -Protocol Tls12,Tls13

        Tests direct TLS 1.2 and 1.3 support on the default HTTPS port.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName '192.0.2.10' -Port 8443 -Protocol Tls12 -Full -TlsHostName 'db.example.test'

        Connects to an IP address while using db.example.test for SNI and certificate checks.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'mail.example.test' -Protocol Tls12 -Full -Service Smtp

        Reads SMTP capabilities, requires STARTTLS, and then tests TLS 1.2 on port 25.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'mail.example.test' -Protocol Tls12 -Full -Service Imap

        Uses IMAP CAPABILITY and STARTTLS on port 143 before the TLS handshake.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'mail.example.test' -Protocol Tls12 -Full -Service Pop3

        Uses POP3 CAPA and STLS on port 110 before the TLS handshake.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'files.example.test' -Protocol Tls12 -Full -Service Ftp

        Uses FTP FEAT and AUTH TLS on port 21 before the TLS handshake.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'postgres.example.test' -Protocol Tls12 -Full -Service PostgreSql

        Sends a PostgreSQL SSLRequest on port 5432 and tests TLS 1.2.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'mysql.example.test' -Protocol Tls12 -Full -Service MySql

        Checks the MySQL CLIENT_SSL capability and sends an SSLRequest on port 3306.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'sql.example.test' -Protocol Tls12 -Full -Service SqlServer

        Performs SQL Server TDS 7.x PRELOGIN negotiation and a TDS-framed TLS handshake.

    .EXAMPLE
        PS > Test-TlsProtocol -ComputerName 'sql.example.test' -Port 1433 -Protocol Tls12,Tls13 -Full -Service Direct

        Tests direct TLS used by SQL Server TDS 8.0 strict encryption.

    .EXAMPLE
        PS > Get-Content './tls-targets.txt' | Test-TlsProtocol -Protocol Tls12,Tls13 -Full | Where-Object SecurityStatus -ne 'Pass'

        Tests a checkpoint across multiple targets and returns results needing review.

    .OUTPUTS
        PSCustomObject
        Basic mode returns one compact compatibility object with Supported. Full mode
        returns one security evidence object with TlsHandshakeSupported and nullable
        ServiceConnectionSupported for each target and requested protocol.

    .NOTES
        In basic mode, Supported means that the TLS handshake completed with the exact
        requested version. In Full mode, that evidence is named TlsHandshakeSupported.
        Neither property means that a subsequent authenticated application request was
        accepted. ServiceConnectionSupported is null when the probe did not perform a
        post-handshake application transaction. ValidationScope identifies the tested
        layers and ApplicationPolicyStatus identifies whether an application/login policy
        was evaluated. CertificateValid is reported independently because the probe accepts
        an invalid certificate long enough to inventory TLS capabilities.

        Azure SQL Managed Instance enforces its minimum TLS setting at the SQL application
        layer. A protocol-layer TDS probe can therefore complete an older TLS handshake that
        a subsequent SQL login rejects with error 47072.

        Direct TcpClient connections do not automatically use browser proxy, PAC/WPAD, or
        HTTP CONNECT settings. Use packet capture, platform TLS logs, and proxy evidence
        when attribution of a reset or EOF matters.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Test-TlsProtocol.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Test-TlsProtocol.ps1

    .LINK
        https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/minimal-tls-version-configure
    #>
    [CmdletBinding(DefaultParameterSetName = 'Basic')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
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
        [String[]]$Protocol,

        [Parameter(Mandatory = $false, ParameterSetName = 'Full')]
        [ValidateSet('Direct', 'Smtp', 'Imap', 'Pop3', 'Ftp', 'PostgreSql', 'MySql', 'SqlServer')]
        [String]$Service = 'Direct',

        [Parameter(Mandatory = $false, ParameterSetName = 'Full')]
        [ValidateNotNullOrEmpty()]
        [Alias('SniName')]
        [String]$TlsHostName,

        [Parameter(Mandatory = $false, ParameterSetName = 'Full')]
        [ValidateSet('Tls12', 'Tls13')]
        [String]$MinimumProtocol = 'Tls12',

        [Parameter(Mandatory = $false, ParameterSetName = 'Full')]
        [Switch]$CheckCertificateRevocation,

        [Parameter(Mandatory, ParameterSetName = 'Full')]
        [Switch]$Full
    )

    begin
    {
        Write-Verbose 'Starting TLS protocol testing'

        if (-not $Protocol)
        {
            $Protocol = @('Tls', 'Tls11', 'Tls12', 'Tls13')
        }

        $protocolMapping = @{
            Tls = [System.Security.Authentication.SslProtocols]::Tls
            Tls11 = [System.Security.Authentication.SslProtocols]::Tls11
            Tls12 = [System.Security.Authentication.SslProtocols]::Tls12
        }

        try
        {
            $protocolMapping.Tls13 = [System.Security.Authentication.SslProtocols]::Tls13
        }
        catch
        {
            Write-Verbose 'TLS 1.3 is not available in this .NET runtime'
        }

        $protocolRank = @{
            Tls = 10
            Tls11 = 11
            Tls12 = 12
            Tls13 = 13
        }

        $servicePorts = @{
            Direct = 443
            Smtp = 25
            Imap = 143
            Pop3 = 110
            Ftp = 21
            PostgreSql = 5432
            MySql = 3306
            SqlServer = 1433
        }

        $writeTlsResult = {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Result
            )

            if ($Full)
            {
                return $Result
            }

            $legacyStatus = $Result.Status
            if ($Result.TlsHandshakeSupported -and $Result.Provider -eq 'OpenSSL')
            {
                $legacyStatus = 'Success (via OpenSSL)'
            }
            elseif ($legacyStatus -eq 'Indeterminate: peer closed connection during handshake')
            {
                $legacyStatus = 'Not supported by server (connection closed during handshake)'
            }
            elseif ($legacyStatus -eq 'TLS handshake rejected or failed')
            {
                $legacyStatus = 'Not supported by server'
            }

            return [PSCustomObject]@{
                Server = $Result.Server
                Port = $Result.Port
                Protocol = $Result.Protocol
                Supported = $Result.TlsHandshakeSupported
                Status = $legacyStatus
                ResponseTime = $Result.ResponseTime
            }
        }

        $opensslCommand = $null
        if ($PSVersionTable.PSVersion.Major -ge 6 -and ($IsMacOS -or $IsLinux))
        {
            $opensslCommands = @(Get-Command -Name 'openssl' -CommandType Application -ErrorAction SilentlyContinue)
            if ($opensslCommands.Count -gt 0)
            {
                $opensslCommand = $opensslCommands[0]
            }
        }

        $invokeOpenSslTls13 = {
            param(
                [Parameter(Mandatory)]
                [String]$Target,

                [Parameter(Mandatory)]
                [Int]$TargetPort,

                [Parameter(Mandatory)]
                [String]$ServerName,

                [Parameter(Mandatory)]
                [Int]$ProcessTimeout
            )

            if ($null -eq $opensslCommand)
            {
                return $null
            }

            $process = $null
            try
            {
                $connectTarget = if ($Target.Contains(':') -and -not $Target.StartsWith('['))
                {
                    "[$Target]:$TargetPort"
                }
                else
                {
                    "${Target}:$TargetPort"
                }

                $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                $startInfo.FileName = $opensslCommand.Source
                $startInfo.UseShellExecute = $false
                $startInfo.CreateNoWindow = $true
                $startInfo.RedirectStandardInput = $true
                $startInfo.RedirectStandardOutput = $true
                $startInfo.RedirectStandardError = $true

                $argumentListProperty = $startInfo.PSObject.Properties['ArgumentList']
                $arguments = @(
                    's_client', '-connect', $connectTarget, '-servername', $ServerName,
                    '-verify_hostname', $ServerName, '-tls1_3', '-showcerts', '-no_ign_eof'
                )

                if ($null -eq $argumentListProperty)
                {
                    if ($connectTarget -match '[\s"]' -or $ServerName -match '[\s"]')
                    {
                        throw 'OpenSSL fallback host names cannot contain whitespace or quotation marks on this runtime.'
                    }
                    $startInfo.Arguments = $arguments -join ' '
                }
                else
                {
                    foreach ($argument in $arguments)
                    {
                        $startInfo.ArgumentList.Add($argument)
                    }
                }

                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $startInfo
                if (-not $process.Start())
                {
                    throw 'OpenSSL could not be started.'
                }

                $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
                $standardErrorTask = $process.StandardError.ReadToEndAsync()
                $process.StandardInput.Close()

                if (-not $process.WaitForExit($ProcessTimeout))
                {
                    $process.Kill()
                    $process.WaitForExit()
                    return [PSCustomObject]@{
                        Supported = $false
                        Status = 'Handshake timeout'
                        NegotiatedProtocol = $null
                        CipherSuite = $null
                        CipherAlgorithm = $null
                        CipherStrength = $null
                        CertificateSubject = $null
                        CertificateIssuer = $null
                        CertificateThumbprint = $null
                        CertificateNotBefore = $null
                        CertificateNotAfter = $null
                        CertificateValid = $null
                        CertificatePolicyErrors = $null
                        CertificateChainStatus = [String[]]@()
                        ErrorMessage = "OpenSSL did not complete within ${ProcessTimeout}ms."
                    }
                }

                $opensslOutput = $standardOutputTask.Result + "`n" + $standardErrorTask.Result
                $protocolSucceeded = $process.ExitCode -eq 0 -and
                $opensslOutput -match '(?im)(Protocol\s*:\s*TLSv1\.3|Protocol version:\s*TLSv1\.3|New,\s*TLSv1\.3)'

                $cipherSuite = $null
                if ($opensslOutput -match '(?im)(?:Cipher is|Ciphersuite:)\s*(?<Cipher>\S+)')
                {
                    $cipherSuite = $Matches.Cipher
                }

                $cipherAlgorithm = $null
                $cipherStrength = $null
                if ($cipherSuite -match 'AES_256|AES256')
                {
                    $cipherAlgorithm = 'Aes256'
                    $cipherStrength = 256
                }
                elseif ($cipherSuite -match 'AES_128|AES128')
                {
                    $cipherAlgorithm = 'Aes128'
                    $cipherStrength = 128
                }
                elseif ($cipherSuite -match 'CHACHA20')
                {
                    $cipherAlgorithm = 'ChaCha20Poly1305'
                    $cipherStrength = 256
                }

                $certificateSubject = $null
                $certificateIssuer = $null
                $certificateThumbprint = $null
                $certificateNotBefore = $null
                $certificateNotAfter = $null
                if ($opensslOutput -match '(?s)-----BEGIN CERTIFICATE-----(?<Certificate>.*?)-----END CERTIFICATE-----')
                {
                    try
                    {
                        [Byte[]]$certificateBytes = [Convert]::FromBase64String(($Matches.Certificate -replace '\s', ''))
                        $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (, $certificateBytes)
                        $certificateSubject = $certificate.Subject
                        $certificateIssuer = $certificate.Issuer
                        $certificateThumbprint = $certificate.Thumbprint
                        $certificateNotBefore = $certificate.NotBefore
                        $certificateNotAfter = $certificate.NotAfter
                        $certificate.Dispose()
                    }
                    catch
                    {
                        Write-Verbose "Unable to parse the OpenSSL peer certificate: $($_.Exception.Message)"
                    }
                }

                $certificateValid = $null
                $certificatePolicyErrors = $null
                if ($opensslOutput -match '(?im)Verify return code:\s*(?<Code>[0-9]+)\s*\((?<Message>[^)]*)\)')
                {
                    $certificateValid = ($Matches.Code -eq '0')
                    $certificatePolicyErrors = if ($certificateValid)
                    {
                        'None'
                    }
                    else
                    {
                        "OpenSSL verify code $($Matches.Code): $($Matches.Message)"
                    }
                }

                $chainStatus = New-Object 'System.Collections.Generic.List[String]'
                foreach ($verifyMatch in [Regex]::Matches($opensslOutput, '(?im)verify error:num=[0-9]+:(?<Message>[^\r\n]+)'))
                {
                    $chainStatus.Add($verifyMatch.Groups['Message'].Value.Trim())
                }

                $errorMessage = $null
                $status = 'Success'
                if (-not $protocolSucceeded)
                {
                    $nonEmptyLines = @($opensslOutput -split '\r?\n' | Where-Object { -not [String]::IsNullOrWhiteSpace($_) })
                    if ($nonEmptyLines.Count -gt 0)
                    {
                        $errorMessage = $nonEmptyLines[$nonEmptyLines.Count - 1].Trim()
                    }
                    if ($opensslOutput -match 'Connection refused|connect:errno|Name or service not known|nodename nor servname')
                    {
                        $status = 'Connection failed'
                    }
                    else
                    {
                        $status = 'TLS handshake rejected or failed'
                    }
                }

                return [PSCustomObject]@{
                    Supported = [Boolean]$protocolSucceeded
                    Status = $status
                    NegotiatedProtocol = if ($protocolSucceeded) { 'Tls13' } else { $null }
                    CipherSuite = $cipherSuite
                    CipherAlgorithm = $cipherAlgorithm
                    CipherStrength = $cipherStrength
                    CertificateSubject = $certificateSubject
                    CertificateIssuer = $certificateIssuer
                    CertificateThumbprint = $certificateThumbprint
                    CertificateNotBefore = $certificateNotBefore
                    CertificateNotAfter = $certificateNotAfter
                    CertificateValid = $certificateValid
                    CertificatePolicyErrors = $certificatePolicyErrors
                    CertificateChainStatus = [String[]]$chainStatus.ToArray()
                    ErrorMessage = $errorMessage
                }
            }
            catch
            {
                $opensslException = $_.Exception.GetBaseException()
                return [PSCustomObject]@{
                    Supported = $false
                    Status = "OpenSSL error: $($opensslException.Message)"
                    NegotiatedProtocol = $null
                    CipherSuite = $null
                    CipherAlgorithm = $null
                    CipherStrength = $null
                    CertificateSubject = $null
                    CertificateIssuer = $null
                    CertificateThumbprint = $null
                    CertificateNotBefore = $null
                    CertificateNotAfter = $null
                    CertificateValid = $null
                    CertificatePolicyErrors = $null
                    CertificateChainStatus = [String[]]@()
                    ErrorMessage = $opensslException.Message
                }
            }
            finally
            {
                if ($null -ne $process)
                {
                    $process.Dispose()
                }
            }
        }

        $readExact = {
            param(
                [Parameter(Mandatory)]
                [System.IO.Stream]$Stream,

                [Parameter(Mandatory)]
                [Int]$Count
            )

            [Byte[]]$buffer = New-Object Byte[] $Count
            $offset = 0

            while ($offset -lt $Count)
            {
                $bytesRead = $Stream.Read($buffer, $offset, $Count - $offset)
                if ($bytesRead -eq 0)
                {
                    throw 'The peer closed the connection while application negotiation data was being read.'
                }

                $offset += $bytesRead
            }

            return , $buffer
        }

        $readAsciiLine = {
            param(
                [Parameter(Mandatory)]
                [System.IO.Stream]$Stream
            )

            $lineBytes = New-Object 'System.Collections.Generic.List[Byte]'
            [Byte[]]$singleByte = New-Object Byte[] 1

            while ($lineBytes.Count -lt 16384)
            {
                $bytesRead = $Stream.Read($singleByte, 0, 1)
                if ($bytesRead -eq 0)
                {
                    throw 'The peer closed the connection while an application response was being read.'
                }

                if ($singleByte[0] -eq 10)
                {
                    return [System.Text.Encoding]::ASCII.GetString($lineBytes.ToArray()).TrimEnd([Char]13)
                }

                $lineBytes.Add($singleByte[0])
            }

            throw 'The application response exceeded the 16384-byte line limit.'
        }

        $writeAsciiLine = {
            param(
                [Parameter(Mandatory)]
                [System.IO.Stream]$Stream,

                [Parameter(Mandatory)]
                [String]$Line
            )

            [Byte[]]$lineBytes = [System.Text.Encoding]::ASCII.GetBytes("$Line`r`n")
            $Stream.Write($lineBytes, 0, $lineBytes.Length)
            $Stream.Flush()
        }

        $readNumericReply = {
            param(
                [Parameter(Mandatory)]
                [System.IO.Stream]$Stream
            )

            $lines = New-Object 'System.Collections.Generic.List[String]'
            $firstLine = & $readAsciiLine -Stream $Stream
            $lines.Add($firstLine)

            if ($firstLine -notmatch '^(?<Code>[0-9]{3})(?<Continuation>[- ])')
            {
                throw "Unexpected application response: $firstLine"
            }

            $code = $Matches.Code
            if ($Matches.Continuation -eq '-')
            {
                for ($lineNumber = 0; $lineNumber -lt 100; $lineNumber++)
                {
                    $line = & $readAsciiLine -Stream $Stream
                    $lines.Add($line)
                    if ($line.StartsWith("$code ", [System.StringComparison]::Ordinal))
                    {
                        break
                    }
                }

                if (-not $lines[$lines.Count - 1].StartsWith("$code ", [System.StringComparison]::Ordinal))
                {
                    throw "The $code application response exceeded the 100-line limit."
                }
            }

            return [PSCustomObject]@{
                Code = $code
                Lines = [String[]]$lines.ToArray()
            }
        }

        $readTdsMessage = {
            param(
                [Parameter(Mandatory)]
                [System.IO.Stream]$Stream
            )

            $messageBytes = New-Object 'System.Collections.Generic.List[Byte]'
            $firstPacket = $true
            do
            {
                [Byte[]]$header = & $readExact -Stream $Stream -Count 8
                if ($firstPacket -and $header[0] -ne 4)
                {
                    throw "SQL Server returned unexpected TDS packet type $($header[0]) during PRELOGIN."
                }
                $firstPacket = $false
                $packetLength = ([Int]$header[2] -shl 8) -bor [Int]$header[3]
                if ($packetLength -lt 8)
                {
                    throw "SQL Server returned an invalid TDS packet length: $packetLength."
                }

                [Byte[]]$packetPayload = & $readExact -Stream $Stream -Count ($packetLength - 8)
                foreach ($payloadByte in $packetPayload)
                {
                    $messageBytes.Add($payloadByte)
                }

                $endOfMessage = (($header[1] -band 1) -eq 1)
            }
            while (-not $endOfMessage)

            return , $messageBytes.ToArray()
        }

        $tdsTlsStreamType = 'PwshProfile.Network.TdsTlsStream' -as [Type]
        if (-not $tdsTlsStreamType)
        {
            $tdsTlsStreamSource = @'
using System;
using System.IO;

namespace PwshProfile.Network
{
    public sealed class TdsTlsStream : Stream
    {
        private readonly Stream innerStream;
        private readonly bool leaveOpen;
        private byte[] readBuffer = new byte[0];
        private int readOffset;
        private byte packetId = 1;

        public TdsTlsStream(Stream innerStream, bool leaveOpen)
        {
            if (innerStream == null) throw new ArgumentNullException("innerStream");
            this.innerStream = innerStream;
            this.leaveOpen = leaveOpen;
        }

        public override bool CanRead { get { return innerStream.CanRead; } }
        public override bool CanSeek { get { return false; } }
        public override bool CanWrite { get { return innerStream.CanWrite; } }
        public override bool CanTimeout { get { return innerStream.CanTimeout; } }
        public override long Length { get { throw new NotSupportedException(); } }
        public override long Position
        {
            get { throw new NotSupportedException(); }
            set { throw new NotSupportedException(); }
        }
        public override int ReadTimeout
        {
            get { return innerStream.ReadTimeout; }
            set { innerStream.ReadTimeout = value; }
        }
        public override int WriteTimeout
        {
            get { return innerStream.WriteTimeout; }
            set { innerStream.WriteTimeout = value; }
        }

        public override void Flush()
        {
            innerStream.Flush();
        }

        private void ReadFully(byte[] buffer, int offset, int count)
        {
            while (count > 0)
            {
                int bytesRead = innerStream.Read(buffer, offset, count);
                if (bytesRead == 0) throw new EndOfStreamException("SQL Server closed the TDS TLS stream.");
                offset += bytesRead;
                count -= bytesRead;
            }
        }

        private void ReadPacket()
        {
            do
            {
                byte[] header = new byte[8];
                ReadFully(header, 0, header.Length);
                if (header[0] != 0x12) throw new IOException("SQL Server returned a non-PRELOGIN packet during TLS negotiation.");
                int packetLength = (header[2] << 8) | header[3];
                if (packetLength < 8) throw new IOException("SQL Server returned an invalid TDS TLS packet length.");
                readBuffer = new byte[packetLength - 8];
                ReadFully(readBuffer, 0, readBuffer.Length);
                readOffset = 0;
            }
            while (readBuffer.Length == 0);
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            if (readOffset >= readBuffer.Length) ReadPacket();
            int available = readBuffer.Length - readOffset;
            int bytesToCopy = Math.Min(available, count);
            Buffer.BlockCopy(readBuffer, readOffset, buffer, offset, bytesToCopy);
            readOffset += bytesToCopy;
            return bytesToCopy;
        }

        public override void Write(byte[] buffer, int offset, int count)
        {
            const int maximumPayload = 32759;
            while (count > 0)
            {
                int payloadLength = Math.Min(count, maximumPayload);
                int packetLength = payloadLength + 8;
                byte[] header = new byte[8];
                header[0] = 0x12;
                header[1] = (byte)(count <= maximumPayload ? 0x01 : 0x00);
                header[2] = (byte)(packetLength >> 8);
                header[3] = (byte)packetLength;
                header[6] = packetId++;
                innerStream.Write(header, 0, header.Length);
                innerStream.Write(buffer, offset, payloadLength);
                offset += payloadLength;
                count -= payloadLength;
            }
            innerStream.Flush();
        }

        public override long Seek(long offset, SeekOrigin origin)
        {
            throw new NotSupportedException();
        }

        public override void SetLength(long value)
        {
            throw new NotSupportedException();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && !leaveOpen) innerStream.Dispose();
            base.Dispose(disposing);
        }
    }
}
'@

            Add-Type -TypeDefinition $tdsTlsStreamSource -ErrorAction Stop
            $tdsTlsStreamType = 'PwshProfile.Network.TdsTlsStream' -as [Type]
        }
    }

    process
    {
        $effectivePort = if ($PSBoundParameters.ContainsKey('Port')) { $Port } else { $servicePorts[$Service] }
        $effectiveTlsHostName = if ($TlsHostName) { $TlsHostName } else { $ComputerName }

        foreach ($targetProtocol in $Protocol)
        {
            Write-Verbose "Testing $targetProtocol on ${ComputerName}:${effectivePort} using $Service negotiation"

            $result = [PSCustomObject]@{
                Server = $ComputerName
                Port = [Int]$effectivePort
                Service = $Service
                Provider = '.NET'
                TlsHostName = $effectiveTlsHostName
                Protocol = $targetProtocol
                TlsHandshakeSupported = $false
                ServiceConnectionSupported = $null
                Status = 'Unknown'
                FailureStage = $null
                ResponseTime = [TimeSpan]::Zero
                RemoteAddress = $null
                Negotiation = $null
                StartTlsAdvertised = $null
                PreTlsCapabilities = [String[]]@()
                ValidationScope = if ($Service -eq 'Direct') { 'TlsHandshake' } else { 'ServiceNegotiationAndTlsHandshake' }
                ApplicationPolicyStatus = 'NotEvaluated'
                NegotiatedProtocol = $null
                CipherSuite = $null
                CipherAlgorithm = $null
                CipherStrength = $null
                HashAlgorithm = $null
                KeyExchangeAlgorithm = $null
                CertificateSubject = $null
                CertificateIssuer = $null
                CertificateThumbprint = $null
                CertificateNotBefore = $null
                CertificateNotAfter = $null
                CertificateValid = $null
                CertificatePolicyErrors = $null
                CertificateChainStatus = [String[]]@()
                RevocationChecked = [Boolean]$CheckCertificateRevocation
                MinimumProtocol = $MinimumProtocol
                SecurityStatus = 'NotEvaluated'
                SecurityFindings = [String[]]@()
                ErrorType = $null
                SocketError = $null
                ErrorMessage = $null
            }

            if (-not $protocolMapping.ContainsKey($targetProtocol))
            {
                $result.Status = 'Protocol not available on this system'
                $result.FailureStage = 'Local'
                $result.SecurityFindings = [String[]]@('The requested protocol is unavailable in the local TLS runtime.')
                & $writeTlsResult -Result $result
                continue
            }

            if ($Service -eq 'SqlServer' -and $targetProtocol -eq 'Tls13')
            {
                $result.Status = 'TLS 1.3 requires SQL Server TDS 8.0; use Service Direct'
                $result.FailureStage = 'Local'
                $result.SecurityFindings = [String[]]@('TDS 7.x PRELOGIN encryption does not support TLS 1.3.')
                & $writeTlsResult -Result $result
                continue
            }

            $tcpClient = $null
            $networkStream = $null
            $tlsTransportStream = $null
            $sslStream = $null
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try
            {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $connectResult = $null
                $waitHandle = $null

                try
                {
                    $connectResult = $tcpClient.BeginConnect($ComputerName, $effectivePort, $null, $null)
                    $waitHandle = $connectResult.AsyncWaitHandle
                    if (-not $waitHandle.WaitOne($Timeout, $false))
                    {
                        $result.Status = 'Connection timeout'
                        $result.FailureStage = 'Connect'
                        $result.ErrorMessage = "The TCP connection did not complete within ${Timeout}ms."
                        $stopwatch.Stop()
                        $result.ResponseTime = $stopwatch.Elapsed
                        & $writeTlsResult -Result $result
                        continue
                    }

                    $tcpClient.EndConnect($connectResult)
                }
                catch
                {
                    $connectException = $_.Exception.GetBaseException()
                    $result.Status = "Connection failed: $($connectException.Message)"
                    $result.FailureStage = 'Connect'
                    $result.ErrorType = $connectException.GetType().FullName
                    $result.ErrorMessage = $connectException.Message
                    if ($connectException -is [System.Net.Sockets.SocketException])
                    {
                        $result.SocketError = $connectException.SocketErrorCode.ToString()
                    }
                    $stopwatch.Stop()
                    $result.ResponseTime = $stopwatch.Elapsed
                    & $writeTlsResult -Result $result
                    continue
                }
                finally
                {
                    if ($null -ne $waitHandle)
                    {
                        $waitHandle.Close()
                    }
                }

                if (-not $tcpClient.Connected)
                {
                    $result.Status = 'Connection failed'
                    $result.FailureStage = 'Connect'
                    $stopwatch.Stop()
                    $result.ResponseTime = $stopwatch.Elapsed
                    & $writeTlsResult -Result $result
                    continue
                }

                $result.RemoteAddress = $tcpClient.Client.RemoteEndPoint.Address.ToString()
                $networkStream = $tcpClient.GetStream()
                $networkStream.ReadTimeout = $Timeout
                $networkStream.WriteTimeout = $Timeout
                $tlsTransportStream = $networkStream

                try
                {
                    switch ($Service)
                    {
                        'Direct'
                        {
                            $result.Negotiation = 'ImplicitTls'
                        }

                        'Smtp'
                        {
                            $result.Negotiation = 'StartTls'
                            $banner = & $readNumericReply -Stream $networkStream
                            if ($banner.Code -ne '220')
                            {
                                throw "SMTP greeting was rejected with response $($banner.Code)."
                            }

                            & $writeAsciiLine -Stream $networkStream -Line 'EHLO tls-probe.invalid'
                            $capabilityReply = & $readNumericReply -Stream $networkStream
                            if ($capabilityReply.Code -ne '250')
                            {
                                throw "SMTP EHLO was rejected with response $($capabilityReply.Code)."
                            }

                            $result.PreTlsCapabilities = [String[]]$capabilityReply.Lines
                            $result.StartTlsAdvertised = [Boolean](($capabilityReply.Lines -join "`n") -match '(?im)^250[- ]STARTTLS(?:\s|$)')
                            if (-not $result.StartTlsAdvertised)
                            {
                                throw 'TLS upgrade not supported: SMTP STARTTLS was not advertised.'
                            }

                            & $writeAsciiLine -Stream $networkStream -Line 'STARTTLS'
                            $startTlsReply = & $readNumericReply -Stream $networkStream
                            if ($startTlsReply.Code -ne '220')
                            {
                                throw "TLS negotiation rejected: SMTP STARTTLS returned $($startTlsReply.Code)."
                            }
                        }

                        'Imap'
                        {
                            $result.Negotiation = 'StartTls'
                            $greeting = & $readAsciiLine -Stream $networkStream
                            if ($greeting -notmatch '^\*\s+(OK|PREAUTH)\b')
                            {
                                throw "Unexpected IMAP greeting: $greeting"
                            }

                            & $writeAsciiLine -Stream $networkStream -Line 'a001 CAPABILITY'
                            $imapCapabilityLines = New-Object 'System.Collections.Generic.List[String]'
                            for ($lineNumber = 0; $lineNumber -lt 100; $lineNumber++)
                            {
                                $line = & $readAsciiLine -Stream $networkStream
                                $imapCapabilityLines.Add($line)
                                if ($line -match '^a001\s+') { break }
                            }

                            if ($imapCapabilityLines[$imapCapabilityLines.Count - 1] -notmatch '^a001\s+OK\b')
                            {
                                throw 'IMAP CAPABILITY did not complete successfully.'
                            }

                            $result.PreTlsCapabilities = [String[]]$imapCapabilityLines.ToArray()
                            $result.StartTlsAdvertised = [Boolean](($result.PreTlsCapabilities -join ' ') -match '(?i)(?:^|\s)STARTTLS(?:\s|$)')
                            if (-not $result.StartTlsAdvertised)
                            {
                                throw 'TLS upgrade not supported: IMAP STARTTLS was not advertised.'
                            }

                            & $writeAsciiLine -Stream $networkStream -Line 'a002 STARTTLS'
                            $startTlsReply = & $readAsciiLine -Stream $networkStream
                            if ($startTlsReply -notmatch '^a002\s+OK\b')
                            {
                                throw "TLS negotiation rejected: IMAP STARTTLS returned '$startTlsReply'."
                            }
                        }

                        'Pop3'
                        {
                            $result.Negotiation = 'StartTls'
                            $greeting = & $readAsciiLine -Stream $networkStream
                            if ($greeting -notmatch '^\+OK\b')
                            {
                                throw "Unexpected POP3 greeting: $greeting"
                            }

                            & $writeAsciiLine -Stream $networkStream -Line 'CAPA'
                            $capaReply = & $readAsciiLine -Stream $networkStream
                            if ($capaReply -notmatch '^\+OK\b')
                            {
                                throw "POP3 CAPA was rejected: $capaReply"
                            }

                            $pop3Capabilities = New-Object 'System.Collections.Generic.List[String]'
                            $pop3CapabilityComplete = $false
                            for ($lineNumber = 0; $lineNumber -lt 100; $lineNumber++)
                            {
                                $line = & $readAsciiLine -Stream $networkStream
                                if ($line -eq '.')
                                {
                                    $pop3CapabilityComplete = $true
                                    break
                                }
                                $pop3Capabilities.Add($line)
                            }

                            if (-not $pop3CapabilityComplete)
                            {
                                throw 'The POP3 CAPA response exceeded the 100-line limit.'
                            }

                            $result.PreTlsCapabilities = [String[]]$pop3Capabilities.ToArray()
                            $result.StartTlsAdvertised = [Boolean](($result.PreTlsCapabilities -join "`n") -match '(?im)^STLS(?:\s|$)')
                            if (-not $result.StartTlsAdvertised)
                            {
                                throw 'TLS upgrade not supported: POP3 STLS was not advertised.'
                            }

                            & $writeAsciiLine -Stream $networkStream -Line 'STLS'
                            $startTlsReply = & $readAsciiLine -Stream $networkStream
                            if ($startTlsReply -notmatch '^\+OK\b')
                            {
                                throw "TLS negotiation rejected: POP3 STLS returned '$startTlsReply'."
                            }
                        }

                        'Ftp'
                        {
                            $result.Negotiation = 'AuthTls'
                            $banner = & $readNumericReply -Stream $networkStream
                            if ($banner.Code -ne '220')
                            {
                                throw "FTP greeting was rejected with response $($banner.Code)."
                            }

                            & $writeAsciiLine -Stream $networkStream -Line 'FEAT'
                            $featureReply = & $readNumericReply -Stream $networkStream
                            $result.PreTlsCapabilities = [String[]]$featureReply.Lines
                            $result.StartTlsAdvertised = [Boolean](($featureReply.Lines -join "`n") -match '(?im)(?:^|\s)AUTH\s+(?:TLS|TLS-C)(?:\s|$)')

                            & $writeAsciiLine -Stream $networkStream -Line 'AUTH TLS'
                            $authReply = & $readNumericReply -Stream $networkStream
                            if ($authReply.Code -ne '234')
                            {
                                throw "TLS negotiation rejected: FTP AUTH TLS returned $($authReply.Code)."
                            }
                        }

                        'PostgreSql'
                        {
                            $result.Negotiation = 'PostgreSqlSslRequest'
                            [Byte[]]$sslRequest = @(0, 0, 0, 8, 4, 210, 22, 47)
                            $networkStream.Write($sslRequest, 0, $sslRequest.Length)
                            $networkStream.Flush()
                            [Byte[]]$sslResponse = & $readExact -Stream $networkStream -Count 1
                            if ($sslResponse[0] -eq [Byte][Char]'N')
                            {
                                throw 'TLS upgrade not supported: PostgreSQL returned N to SSLRequest.'
                            }
                            if ($sslResponse[0] -ne [Byte][Char]'S')
                            {
                                throw "Unexpected PostgreSQL SSLRequest response byte: $($sslResponse[0])."
                            }
                        }

                        'MySql'
                        {
                            $result.Negotiation = 'MySqlSslRequest'
                            [Byte[]]$mysqlHeader = & $readExact -Stream $networkStream -Count 4
                            $mysqlPayloadLength = [Int]$mysqlHeader[0] -bor ([Int]$mysqlHeader[1] -shl 8) -bor ([Int]$mysqlHeader[2] -shl 16)
                            if ($mysqlPayloadLength -lt 1 -or $mysqlPayloadLength -gt 16777215)
                            {
                                throw "MySQL returned an invalid handshake packet length: $mysqlPayloadLength."
                            }

                            [Byte[]]$mysqlHandshake = & $readExact -Stream $networkStream -Count $mysqlPayloadLength
                            if ($mysqlHandshake[0] -ne 10)
                            {
                                throw "Unsupported MySQL handshake protocol version: $($mysqlHandshake[0])."
                            }

                            $serverVersionEnd = 1
                            while ($serverVersionEnd -lt $mysqlHandshake.Length -and $mysqlHandshake[$serverVersionEnd] -ne 0)
                            {
                                $serverVersionEnd++
                            }

                            $capabilityOffset = $serverVersionEnd + 14
                            if (($capabilityOffset + 1) -ge $mysqlHandshake.Length)
                            {
                                throw 'MySQL returned a truncated initial handshake.'
                            }

                            [UInt32]$serverCapabilities = [UInt32]$mysqlHandshake[$capabilityOffset] -bor ([UInt32]$mysqlHandshake[$capabilityOffset + 1] -shl 8)
                            if (($capabilityOffset + 6) -lt $mysqlHandshake.Length)
                            {
                                $serverCapabilities = $serverCapabilities -bor ([UInt32]$mysqlHandshake[$capabilityOffset + 5] -shl 16) -bor ([UInt32]$mysqlHandshake[$capabilityOffset + 6] -shl 24)
                            }

                            if (($serverCapabilities -band [UInt32]0x00000800) -eq 0)
                            {
                                throw 'TLS upgrade not supported: MySQL did not advertise CLIENT_SSL.'
                            }
                            if (($serverCapabilities -band [UInt32]0x00000200) -eq 0)
                            {
                                throw 'TLS upgrade not supported: MySQL did not advertise CLIENT_PROTOCOL_41.'
                            }

                            [UInt32]$clientCapabilities = [UInt32]0x00008A05
                            $clientCapabilities = $clientCapabilities -band $serverCapabilities
                            $clientCapabilities = $clientCapabilities -bor [UInt32]0x00000A00
                            [Byte[]]$mysqlSslRequest = New-Object Byte[] 32
                            [Byte[]]$capabilityBytes = [System.BitConverter]::GetBytes($clientCapabilities)
                            [System.Buffer]::BlockCopy($capabilityBytes, 0, $mysqlSslRequest, 0, 4)
                            $mysqlSslRequest[4] = 255
                            $mysqlSslRequest[5] = 255
                            $mysqlSslRequest[6] = 255
                            $mysqlSslRequest[7] = 0
                            $mysqlSslRequest[8] = 45

                            [Byte[]]$requestHeader = @(32, 0, 0, [Byte]($mysqlHeader[3] + 1))
                            $networkStream.Write($requestHeader, 0, $requestHeader.Length)
                            $networkStream.Write($mysqlSslRequest, 0, $mysqlSslRequest.Length)
                            $networkStream.Flush()
                        }

                        'SqlServer'
                        {
                            $result.Negotiation = 'Tds7Prelogin'
                            [Byte[]]$preloginPayload = @(
                                0, 0, 11, 0, 6,
                                1, 0, 17, 0, 1,
                                255,
                                0, 0, 0, 0, 0, 0,
                                1
                            )
                            $tdsPacketLength = $preloginPayload.Length + 8
                            [Byte[]]$tdsHeader = @(18, 1, [Byte]($tdsPacketLength -shr 8), [Byte]$tdsPacketLength, 0, 0, 1, 0)
                            $networkStream.Write($tdsHeader, 0, $tdsHeader.Length)
                            $networkStream.Write($preloginPayload, 0, $preloginPayload.Length)
                            $networkStream.Flush()

                            [Byte[]]$preloginResponse = & $readTdsMessage -Stream $networkStream
                            $encryptionValue = $null
                            for ($optionOffset = 0; $optionOffset -lt $preloginResponse.Length; $optionOffset += 5)
                            {
                                $optionToken = $preloginResponse[$optionOffset]
                                if ($optionToken -eq 255) { break }
                                if (($optionOffset + 4) -ge $preloginResponse.Length)
                                {
                                    throw 'SQL Server returned a truncated PRELOGIN option table.'
                                }

                                $dataOffset = ([Int]$preloginResponse[$optionOffset + 1] -shl 8) -bor [Int]$preloginResponse[$optionOffset + 2]
                                $dataLength = ([Int]$preloginResponse[$optionOffset + 3] -shl 8) -bor [Int]$preloginResponse[$optionOffset + 4]
                                if ($optionToken -eq 1)
                                {
                                    if ($dataLength -lt 1 -or $dataOffset -ge $preloginResponse.Length)
                                    {
                                        throw 'SQL Server returned an invalid PRELOGIN encryption option.'
                                    }
                                    $encryptionValue = $preloginResponse[$dataOffset]
                                    break
                                }
                            }

                            if ($null -eq $encryptionValue)
                            {
                                throw 'SQL Server PRELOGIN did not include an encryption option.'
                            }
                            if ($encryptionValue -eq 2)
                            {
                                throw 'TLS upgrade not supported: SQL Server returned ENCRYPT_NOT_SUP.'
                            }

                            $tlsTransportStream = New-Object PwshProfile.Network.TdsTlsStream($networkStream, $true)
                            $tlsTransportStream.ReadTimeout = $Timeout
                            $tlsTransportStream.WriteTimeout = $Timeout
                        }
                    }
                }
                catch
                {
                    $negotiationException = $_.Exception.GetBaseException()
                    $result.Status = $negotiationException.Message
                    $result.FailureStage = 'Negotiation'
                    $result.ErrorType = $negotiationException.GetType().FullName
                    $result.ErrorMessage = $negotiationException.Message
                    if ($negotiationException -is [System.Net.Sockets.SocketException])
                    {
                        $result.SocketError = $negotiationException.SocketErrorCode.ToString()
                    }

                    if ($negotiationException.Message -match 'not supported|not advertised|negotiation rejected')
                    {
                        $result.SecurityStatus = 'Fail'
                        $result.SecurityFindings = [String[]]@($negotiationException.Message)
                    }
                    $stopwatch.Stop()
                    $result.ResponseTime = $stopwatch.Elapsed
                    & $writeTlsResult -Result $result
                    continue
                }

                $certificateObservation = @{
                    Valid = $null
                    PolicyErrors = $null
                    Subject = $null
                    Issuer = $null
                    Thumbprint = $null
                    NotBefore = $null
                    NotAfter = $null
                    ChainStatus = [String[]]@()
                }

                $certCallback = {
                    param($certSender, $certificate, $chain, $sslPolicyErrors)

                    $certificateObservation.Valid = ($sslPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::None)
                    $certificateObservation.PolicyErrors = $sslPolicyErrors.ToString()

                    if ($null -ne $certificate)
                    {
                        [System.Security.Cryptography.X509Certificates.X509Certificate2]$certificate2 = $certificate
                        $certificateObservation.Subject = $certificate2.Subject
                        $certificateObservation.Issuer = $certificate2.Issuer
                        $certificateObservation.Thumbprint = $certificate2.Thumbprint
                        $certificateObservation.NotBefore = $certificate2.NotBefore
                        $certificateObservation.NotAfter = $certificate2.NotAfter
                    }

                    if ($null -ne $chain)
                    {
                        $chainStatus = New-Object 'System.Collections.Generic.List[String]'
                        foreach ($status in $chain.ChainStatus)
                        {
                            $statusText = $status.Status.ToString()
                            if (-not [String]::IsNullOrWhiteSpace($status.StatusInformation))
                            {
                                $statusText = "$statusText`: $($status.StatusInformation.Trim())"
                            }
                            $chainStatus.Add($statusText)
                        }
                        $certificateObservation.ChainStatus = [String[]]$chainStatus.ToArray()
                    }

                    return $true
                }

                $sslStream = New-Object System.Net.Security.SslStream(
                    $tlsTransportStream,
                    $false,
                    $certCallback
                )

                try
                {
                    $sslStream.AuthenticateAsClient(
                        $effectiveTlsHostName,
                        $null,
                        $protocolMapping[$targetProtocol],
                        [Boolean]$CheckCertificateRevocation
                    )

                    if (-not $sslStream.IsAuthenticated)
                    {
                        $result.Status = 'Authentication failed'
                        $result.FailureStage = 'Handshake'
                        $stopwatch.Stop()
                        $result.ResponseTime = $stopwatch.Elapsed
                        & $writeTlsResult -Result $result
                        continue
                    }

                    $result.NegotiatedProtocol = $sslStream.SslProtocol.ToString()
                    $result.CipherAlgorithm = $sslStream.CipherAlgorithm.ToString()
                    $result.CipherStrength = [Int]$sslStream.CipherStrength
                    $result.HashAlgorithm = $sslStream.HashAlgorithm.ToString()
                    $result.KeyExchangeAlgorithm = $sslStream.KeyExchangeAlgorithm.ToString()

                    $cipherSuiteProperty = $sslStream.PSObject.Properties['NegotiatedCipherSuite']
                    if ($null -ne $cipherSuiteProperty)
                    {
                        $result.CipherSuite = $cipherSuiteProperty.Value.ToString()
                    }

                    $result.CertificateSubject = $certificateObservation.Subject
                    $result.CertificateIssuer = $certificateObservation.Issuer
                    $result.CertificateThumbprint = $certificateObservation.Thumbprint
                    $result.CertificateNotBefore = $certificateObservation.NotBefore
                    $result.CertificateNotAfter = $certificateObservation.NotAfter
                    $result.CertificateValid = $certificateObservation.Valid
                    $result.CertificatePolicyErrors = $certificateObservation.PolicyErrors
                    $result.CertificateChainStatus = [String[]]$certificateObservation.ChainStatus

                    if ($result.NegotiatedProtocol -ne $targetProtocol)
                    {
                        $result.Status = "Protocol mismatch: requested $targetProtocol, negotiated $($result.NegotiatedProtocol)"
                        $result.FailureStage = 'Handshake'
                        $result.ErrorType = 'ProtocolConstraintMismatch'
                        $result.ErrorMessage = 'The TLS runtime did not negotiate the exact protocol requested by the probe.'
                        $result.SecurityStatus = 'Fail'
                        $result.SecurityFindings = [String[]]@($result.ErrorMessage)
                    }
                    else
                    {
                        $result.TlsHandshakeSupported = $true
                        $result.Status = if ($Service -eq 'SqlServer')
                        {
                            'Transport handshake succeeded; SQL login policy not evaluated'
                        }
                        else
                        {
                            'Success'
                        }

                        $securityFindings = New-Object 'System.Collections.Generic.List[String]'
                        $hasSecurityFailure = $false
                        $hasSecurityWarning = $false

                        if ($protocolRank[$targetProtocol] -lt $protocolRank[$MinimumProtocol])
                        {
                            if ($Service -eq 'SqlServer')
                            {
                                $securityFindings.Add(
                                    "The protocol-layer TLS handshake accepted $targetProtocol, below the $MinimumProtocol checkpoint; SQL login policy was not evaluated."
                                )
                                $hasSecurityWarning = $true
                            }
                            else
                            {
                                $securityFindings.Add("The endpoint accepted $targetProtocol, below the $MinimumProtocol minimum.")
                                $hasSecurityFailure = $true
                            }
                        }
                        if ($certificateObservation.Valid -eq $false)
                        {
                            $securityFindings.Add("Certificate validation failed: $($certificateObservation.PolicyErrors).")
                            $hasSecurityFailure = $true
                        }
                        elseif ($null -eq $certificateObservation.Valid)
                        {
                            $securityFindings.Add('Certificate validation evidence was not available.')
                            $hasSecurityWarning = $true
                        }
                        if ($null -ne $result.CipherStrength -and $result.CipherStrength -gt 0 -and $result.CipherStrength -lt 128)
                        {
                            $securityFindings.Add("The negotiated cipher strength is $($result.CipherStrength) bits.")
                            $hasSecurityFailure = $true
                        }
                        if ($Service -eq 'SqlServer')
                        {
                            $securityFindings.Add(
                                'SQL Server application/login policy was not evaluated; a subsequent SQL login can reject a transport-layer TLS handshake.'
                            )
                            $hasSecurityWarning = $true
                        }

                        $result.SecurityFindings = [String[]]$securityFindings.ToArray()
                        if ($hasSecurityFailure)
                        {
                            $result.SecurityStatus = 'Fail'
                        }
                        elseif ($hasSecurityWarning)
                        {
                            $result.SecurityStatus = 'Warning'
                        }
                        else
                        {
                            $result.SecurityStatus = 'Pass'
                        }
                    }
                }
                catch
                {
                    $handshakeException = $_.Exception
                    $baseException = $handshakeException.GetBaseException()
                    $errorMessage = $baseException.Message
                    $exceptionText = $handshakeException.ToString()
                    $socketError = $null
                    $usedOpenSslFallback = $false

                    $canUseOpenSslFallback = $targetProtocol -eq 'Tls13' -and
                    $Service -eq 'Direct' -and
                    $baseException -is [System.PlatformNotSupportedException] -and
                    $null -ne $opensslCommand

                    if ($canUseOpenSslFallback)
                    {
                        if ($null -ne $sslStream)
                        {
                            try { $sslStream.Dispose() } catch { $null = $_ }
                            $sslStream = $null
                        }
                        if ($null -ne $tcpClient)
                        {
                            try { $tcpClient.Dispose() } catch { $null = $_ }
                            $tcpClient = $null
                        }

                        Write-Verbose 'The local SslStream cannot pin TLS 1.3; using the bounded OpenSSL fallback'
                        $opensslResult = & $invokeOpenSslTls13 `
                            -Target $ComputerName `
                            -TargetPort $effectivePort `
                            -ServerName $effectiveTlsHostName `
                            -ProcessTimeout $Timeout

                        if ($null -ne $opensslResult)
                        {
                            $usedOpenSslFallback = $true
                            $result.Provider = 'OpenSSL'
                            $result.TlsHandshakeSupported = $opensslResult.Supported
                            $result.Status = $opensslResult.Status
                            $result.NegotiatedProtocol = $opensslResult.NegotiatedProtocol
                            $result.CipherSuite = $opensslResult.CipherSuite
                            $result.CipherAlgorithm = $opensslResult.CipherAlgorithm
                            $result.CipherStrength = $opensslResult.CipherStrength
                            $result.CertificateSubject = $opensslResult.CertificateSubject
                            $result.CertificateIssuer = $opensslResult.CertificateIssuer
                            $result.CertificateThumbprint = $opensslResult.CertificateThumbprint
                            $result.CertificateNotBefore = $opensslResult.CertificateNotBefore
                            $result.CertificateNotAfter = $opensslResult.CertificateNotAfter
                            $result.CertificateValid = $opensslResult.CertificateValid
                            $result.CertificatePolicyErrors = $opensslResult.CertificatePolicyErrors
                            $result.CertificateChainStatus = [String[]]$opensslResult.CertificateChainStatus
                            $result.RevocationChecked = $false
                            $result.ErrorType = if ($opensslResult.Supported) { $null } else { 'OpenSSL' }
                            $result.ErrorMessage = $opensslResult.ErrorMessage
                            $result.FailureStage = if ($opensslResult.Supported) { $null } else { 'Handshake' }

                            if ($opensslResult.Supported -and $opensslResult.NegotiatedProtocol -ne $targetProtocol)
                            {
                                $result.TlsHandshakeSupported = $false
                                $result.Status = "Protocol mismatch: requested $targetProtocol, negotiated $($opensslResult.NegotiatedProtocol)"
                                $result.FailureStage = 'Handshake'
                                $result.ErrorType = 'ProtocolConstraintMismatch'
                                $result.ErrorMessage = 'OpenSSL did not negotiate the exact protocol requested by the probe.'
                                $result.SecurityStatus = 'Fail'
                                $result.SecurityFindings = [String[]]@($result.ErrorMessage)
                            }
                            elseif ($opensslResult.Supported)
                            {
                                $opensslFindings = New-Object 'System.Collections.Generic.List[String]'
                                if ($opensslResult.CertificateValid -eq $false)
                                {
                                    $opensslFindings.Add("Certificate validation failed: $($opensslResult.CertificatePolicyErrors).")
                                }
                                elseif ($null -eq $opensslResult.CertificateValid)
                                {
                                    $opensslFindings.Add('Certificate validation evidence was not available from OpenSSL.')
                                }
                                if ($null -ne $opensslResult.CipherStrength -and
                                    $opensslResult.CipherStrength -gt 0 -and
                                    $opensslResult.CipherStrength -lt 128)
                                {
                                    $opensslFindings.Add("The negotiated cipher strength is $($opensslResult.CipherStrength) bits.")
                                }
                                if ($CheckCertificateRevocation)
                                {
                                    $opensslFindings.Add('Certificate revocation checking was not performed by the OpenSSL fallback.')
                                }

                                $result.SecurityFindings = [String[]]$opensslFindings.ToArray()
                                if ($opensslResult.CertificateValid -eq $false -or
                                    ($null -ne $opensslResult.CipherStrength -and $opensslResult.CipherStrength -lt 128))
                                {
                                    $result.SecurityStatus = 'Fail'
                                }
                                elseif ($opensslFindings.Count -gt 0)
                                {
                                    $result.SecurityStatus = 'Warning'
                                }
                                else
                                {
                                    $result.SecurityStatus = 'Pass'
                                }
                            }
                        }
                    }

                    if (-not $usedOpenSslFallback)
                    {
                        if ($baseException -is [System.Net.Sockets.SocketException])
                        {
                            $socketError = $baseException.SocketErrorCode
                            $result.SocketError = $socketError.ToString()
                        }

                        if ($socketError -eq [System.Net.Sockets.SocketError]::TimedOut -or
                            $exceptionText -match 'timed out')
                        {
                            $result.Status = 'Handshake timeout'
                        }
                        elseif ($socketError -in @(
                                [System.Net.Sockets.SocketError]::ConnectionAborted,
                                [System.Net.Sockets.SocketError]::ConnectionReset,
                                [System.Net.Sockets.SocketError]::Shutdown
                            ) -or
                            $exceptionText -match 'remote party has closed|unexpected EOF|0 bytes from the transport stream|closed the TDS TLS stream')
                        {
                            $result.Status = 'Indeterminate: peer closed connection during handshake'
                        }
                        elseif ($baseException -is [System.Security.Authentication.AuthenticationException])
                        {
                            $result.Status = 'TLS handshake rejected or failed'
                        }
                        else
                        {
                            $result.Status = "Handshake failed: $errorMessage"
                        }

                        $result.FailureStage = 'Handshake'
                        $result.ErrorType = $baseException.GetType().FullName
                        $result.ErrorMessage = $errorMessage
                        Write-Verbose "$targetProtocol handshake error ($($baseException.GetType().FullName)): $errorMessage"
                    }
                }
            }
            catch
            {
                $unexpectedException = $_.Exception.GetBaseException()
                $result.Status = "Error: $($unexpectedException.Message)"
                if (-not $result.FailureStage) { $result.FailureStage = 'Internal' }
                $result.ErrorType = $unexpectedException.GetType().FullName
                $result.ErrorMessage = $unexpectedException.Message
            }
            finally
            {
                $stopwatch.Stop()
                $result.ResponseTime = $stopwatch.Elapsed

                if ($null -ne $sslStream)
                {
                    try { $sslStream.Dispose() } catch { $null = $_ }
                }
                elseif ($null -ne $tlsTransportStream -and $tlsTransportStream -ne $networkStream)
                {
                    try { $tlsTransportStream.Dispose() } catch { $null = $_ }
                }

                if ($null -ne $tcpClient)
                {
                    try { $tcpClient.Dispose() } catch { $null = $_ }
                }
            }

            & $writeTlsResult -Result $result
        }
    }

    end
    {
        Write-Verbose 'TLS protocol testing completed'
    }
}
