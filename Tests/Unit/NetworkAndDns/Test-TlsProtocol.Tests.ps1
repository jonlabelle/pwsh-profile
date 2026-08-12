#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Test-TlsProtocol function.

.DESCRIPTION
    Tests command metadata, parameter validation, result shape, and failure handling
    for Test-TlsProtocol without relying on real TLS endpoints. Public endpoint
    coverage lives in the integration tests.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Import the function under test
    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Test-TlsProtocol.ps1"

    $script:Command = Get-Command -Name Test-TlsProtocol
    $script:FastFailureHost = 'this-hostname-definitely-does-not-exist-12345.invalid'

    function Get-TestTlsProtocolParameter
    {
        param(
            [Parameter(Mandatory)]
            [string]$Name
        )

        return $script:Command.Parameters[$Name]
    }

    function Get-TestTlsProtocolParameterDefaultText
    {
        param(
            [Parameter(Mandatory)]
            [string]$Name
        )

        $parameterAst = $script:Command.ScriptBlock.Ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.ParameterAst] -and
                $node.Name.VariablePath.UserPath -eq $Name
            }, $true)

        if (-not $parameterAst -or -not $parameterAst.DefaultValue)
        {
            return $null
        }

        return $parameterAst.DefaultValue.Extent.Text
    }

    if (-not ('TlsProbeFixture.Server' -as [Type]))
    {
        $fixtureSource = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace TlsProbeFixture
{
    public static class Server
    {
        private static readonly ConcurrentDictionary<int, Thread> Threads = new ConcurrentDictionary<int, Thread>();
        private static readonly ConcurrentDictionary<int, string> Errors = new ConcurrentDictionary<int, string>();

        public static int Start(string scenario)
        {
            TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            Thread thread = new Thread(delegate() { Run(listener, port, scenario); });
            thread.IsBackground = true;
            Threads[port] = thread;
            thread.Start();
            return port;
        }

        public static string Wait(int port)
        {
            Thread thread;
            if (!Threads.TryGetValue(port, out thread)) return "Fixture thread was not registered.";
            if (!thread.Join(10000)) return "Fixture thread did not finish within 10 seconds.";
            string error;
            return Errors.TryGetValue(port, out error) ? error : null;
        }

        private static void Run(TcpListener listener, int port, string scenario)
        {
            try
            {
                using (TcpClient client = listener.AcceptTcpClient())
                using (NetworkStream stream = client.GetStream())
                {
                    stream.ReadTimeout = 7000;
                    stream.WriteTimeout = 7000;
                    switch (scenario)
                    {
                        case "SmtpStartTls":
                            WriteAscii(stream, "220 fixture.example.test ESMTP ready\r\n");
                            ExpectLine(stream, "EHLO tls-probe.invalid");
                            WriteAscii(stream, "250-fixture.example.test\r\n250-PIPELINING\r\n250 STARTTLS\r\n");
                            ExpectLine(stream, "STARTTLS");
                            WriteAscii(stream, "220 Ready to start TLS\r\n");
                            ExpectTlsClientHello(stream);
                            break;
                        case "SmtpNoStartTls":
                            WriteAscii(stream, "220 fixture.example.test ESMTP ready\r\n");
                            ExpectLine(stream, "EHLO tls-probe.invalid");
                            WriteAscii(stream, "250 fixture.example.test\r\n");
                            break;
                        case "ImapStartTls":
                            WriteAscii(stream, "* OK fixture.example.test ready\r\n");
                            ExpectLine(stream, "a001 CAPABILITY");
                            WriteAscii(stream, "* CAPABILITY IMAP4rev1 STARTTLS\r\na001 OK CAPABILITY completed\r\n");
                            ExpectLine(stream, "a002 STARTTLS");
                            WriteAscii(stream, "a002 OK Begin TLS negotiation\r\n");
                            ExpectTlsClientHello(stream);
                            break;
                        case "Pop3StartTls":
                            WriteAscii(stream, "+OK fixture.example.test ready\r\n");
                            ExpectLine(stream, "CAPA");
                            WriteAscii(stream, "+OK Capability list follows\r\nUSER\r\nSTLS\r\n.\r\n");
                            ExpectLine(stream, "STLS");
                            WriteAscii(stream, "+OK Begin TLS negotiation\r\n");
                            ExpectTlsClientHello(stream);
                            break;
                        case "FtpStartTls":
                            WriteAscii(stream, "220 fixture.example.test FTP ready\r\n");
                            ExpectLine(stream, "FEAT");
                            WriteAscii(stream, "211-Features\r\n AUTH TLS\r\n PBSZ\r\n211 End\r\n");
                            ExpectLine(stream, "AUTH TLS");
                            WriteAscii(stream, "234 Proceed with TLS\r\n");
                            ExpectTlsClientHello(stream);
                            break;
                        case "PostgreSql":
                            byte[] sslRequest = ReadExact(stream, 8);
                            byte[] expected = new byte[] { 0, 0, 0, 8, 4, 210, 22, 47 };
                            AssertBytes(sslRequest, expected, "PostgreSQL SSLRequest");
                            stream.WriteByte((byte)'S');
                            stream.Flush();
                            ExpectTlsClientHello(stream);
                            break;
                        case "PostgreSqlNoTls":
                            byte[] rejectedSslRequest = ReadExact(stream, 8);
                            byte[] expectedRejected = new byte[] { 0, 0, 0, 8, 4, 210, 22, 47 };
                            AssertBytes(rejectedSslRequest, expectedRejected, "PostgreSQL SSLRequest");
                            stream.WriteByte((byte)'N');
                            stream.Flush();
                            break;
                        case "MySql":
                            WriteMySqlHandshake(stream, true);
                            byte[] requestHeader = ReadExact(stream, 4);
                            if (requestHeader[0] != 32 || requestHeader[1] != 0 || requestHeader[2] != 0 || requestHeader[3] != 1)
                                throw new InvalidDataException("Unexpected MySQL SSLRequest packet header.");
                            byte[] mysqlRequest = ReadExact(stream, 32);
                            uint capabilities = BitConverter.ToUInt32(mysqlRequest, 0);
                            if ((capabilities & 0x00000800U) == 0 || (capabilities & 0x00000200U) == 0)
                                throw new InvalidDataException("MySQL SSLRequest omitted CLIENT_SSL or CLIENT_PROTOCOL_41.");
                            ExpectTlsClientHello(stream);
                            break;
                        case "MySqlNoTls":
                            WriteMySqlHandshake(stream, false);
                            break;
                        case "SqlServer":
                            byte[] tdsHeader = ReadExact(stream, 8);
                            if (tdsHeader[0] != 0x12) throw new InvalidDataException("Expected a SQL Server PRELOGIN packet.");
                            int packetLength = (tdsHeader[2] << 8) | tdsHeader[3];
                            byte[] prelogin = ReadExact(stream, packetLength - 8);
                            if (prelogin.Length != 18 || prelogin[5] != 1 || prelogin[17] != 1)
                                throw new InvalidDataException("Unexpected SQL Server PRELOGIN encryption request.");
                            WriteSqlServerPreloginResponse(stream, 1);
                            byte[] tlsHeader = ReadExact(stream, 8);
                            if (tlsHeader[0] != 0x12) throw new InvalidDataException("TLS ClientHello was not wrapped in a TDS PRELOGIN packet.");
                            int tlsPacketLength = (tlsHeader[2] << 8) | tlsHeader[3];
                            byte[] tlsPayload = ReadExact(stream, tlsPacketLength - 8);
                            if (tlsPayload.Length == 0 || tlsPayload[0] != 0x16)
                                throw new InvalidDataException("TDS packet did not contain a TLS ClientHello record.");
                            break;
                        case "SqlServerNoTls":
                            byte[] rejectedTdsHeader = ReadExact(stream, 8);
                            int rejectedPacketLength = (rejectedTdsHeader[2] << 8) | rejectedTdsHeader[3];
                            ReadExact(stream, rejectedPacketLength - 8);
                            WriteSqlServerPreloginResponse(stream, 2);
                            break;
                        default:
                            throw new ArgumentOutOfRangeException("scenario", scenario, "Unknown fixture scenario.");
                    }
                }
            }
            catch (Exception exception)
            {
                Errors[port] = exception.GetType().FullName + ": " + exception.Message;
            }
            finally
            {
                listener.Stop();
            }
        }

        private static void WriteAscii(Stream stream, string value)
        {
            byte[] bytes = Encoding.ASCII.GetBytes(value);
            stream.Write(bytes, 0, bytes.Length);
            stream.Flush();
        }

        private static string ReadLine(Stream stream)
        {
            List<byte> bytes = new List<byte>();
            while (bytes.Count < 16384)
            {
                int value = stream.ReadByte();
                if (value < 0) throw new EndOfStreamException("Client closed before sending a complete line.");
                if (value == 10) return Encoding.ASCII.GetString(bytes.ToArray()).TrimEnd('\r');
                bytes.Add((byte)value);
            }
            throw new InvalidDataException("Client line exceeded fixture limit.");
        }

        private static void ExpectLine(Stream stream, string expected)
        {
            string actual = ReadLine(stream);
            if (!String.Equals(actual, expected, StringComparison.Ordinal))
                throw new InvalidDataException("Expected '" + expected + "' but received '" + actual + "'.");
        }

        private static byte[] ReadExact(Stream stream, int count)
        {
            byte[] buffer = new byte[count];
            int offset = 0;
            while (offset < count)
            {
                int bytesRead = stream.Read(buffer, offset, count - offset);
                if (bytesRead == 0) throw new EndOfStreamException("Client closed while fixture data was being read.");
                offset += bytesRead;
            }
            return buffer;
        }

        private static void AssertBytes(byte[] actual, byte[] expected, string name)
        {
            if (actual.Length != expected.Length) throw new InvalidDataException(name + " length differed.");
            for (int index = 0; index < actual.Length; index++)
            {
                if (actual[index] != expected[index]) throw new InvalidDataException(name + " bytes differed.");
            }
        }

        private static void ExpectTlsClientHello(Stream stream)
        {
            int contentType = stream.ReadByte();
            if (contentType != 0x16) throw new InvalidDataException("Expected a TLS ClientHello record.");
        }

        private static void WriteMySqlHandshake(Stream stream, bool supportsTls)
        {
            uint capabilities = supportsTls ? 0x00008A05U : 0x00008205U;
            List<byte> payload = new List<byte>();
            payload.Add(10);
            payload.AddRange(Encoding.ASCII.GetBytes("8.0.0-fixture"));
            payload.Add(0);
            payload.AddRange(BitConverter.GetBytes((uint)1));
            payload.AddRange(Encoding.ASCII.GetBytes("12345678"));
            payload.Add(0);
            payload.Add((byte)(capabilities & 0xFF));
            payload.Add((byte)((capabilities >> 8) & 0xFF));
            payload.Add(45);
            payload.Add(2);
            payload.Add(0);
            payload.Add((byte)((capabilities >> 16) & 0xFF));
            payload.Add((byte)((capabilities >> 24) & 0xFF));
            payload.Add(21);
            payload.AddRange(new byte[10]);
            payload.AddRange(Encoding.ASCII.GetBytes("abcdefghijkl\0"));

            int length = payload.Count;
            byte[] header = new byte[] { (byte)length, (byte)(length >> 8), (byte)(length >> 16), 0 };
            stream.Write(header, 0, header.Length);
            byte[] payloadBytes = payload.ToArray();
            stream.Write(payloadBytes, 0, payloadBytes.Length);
            stream.Flush();
        }

        private static void WriteSqlServerPreloginResponse(Stream stream, byte encryptionValue)
        {
            byte[] payload = new byte[]
            {
                0, 0, 11, 0, 6,
                1, 0, 17, 0, 1,
                255,
                0, 0, 0, 0, 0, 0,
                encryptionValue
            };
            int length = payload.Length + 8;
            byte[] header = new byte[] { 4, 1, (byte)(length >> 8), (byte)length, 0, 0, 1, 0 };
            stream.Write(header, 0, header.Length);
            stream.Write(payload, 0, payload.Length);
            stream.Flush();
        }
    }
}
'@

        Add-Type -TypeDefinition $fixtureSource -ErrorAction Stop
    }

    function Assert-TlsProbeFixture
    {
        param(
            [Parameter(Mandatory)]
            [Int]$Port
        )

        [TlsProbeFixture.Server]::Wait($Port) | Should -BeNullOrEmpty
    }
}

Describe 'Test-TlsProtocol' {
    Context 'Parameter metadata' {
        It 'Accepts ComputerName from pipeline input with supported aliases' {
            $parameter = Get-TestTlsProtocolParameter -Name 'ComputerName'

            $parameter.ParameterSets['__AllParameterSets'].ValueFromPipeline | Should-Be $true
            $parameter.ParameterSets['__AllParameterSets'].ValueFromPipelineByPropertyName | Should-Be $true
            $parameter.ParameterSets['__AllParameterSets'].Position | Should-Be 0
            $parameter.Aliases | Should-ContainCollection 'Server'
            $parameter.Aliases | Should-ContainCollection 'Host'
            $parameter.Aliases | Should-ContainCollection 'HostName'
        }

        It 'Accepts ComputerName as the first positional argument' {
            $result = Test-TlsProtocol $script:FastFailureHost -Protocol Tls12 -Timeout 100

            $result.Server | Should-Be $script:FastFailureHost
        }

        It 'Uses localhost as default ComputerName' {
            Get-TestTlsProtocolParameterDefaultText -Name 'ComputerName' | Should-Be "'localhost'"
        }

        It 'Accepts the valid port range' {
            $parameter = Get-TestTlsProtocolParameter -Name 'Port'
            $range = $parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }

            $range.MinRange | Should-Be 1
            $range.MaxRange | Should-Be 65535
        }

        It 'Rejects invalid port numbers' {
            { Test-TlsProtocol -Port 0 -Protocol Tls12 } | Should-Throw
            { Test-TlsProtocol -Port 65536 -Protocol Tls12 } | Should-Throw
            { Test-TlsProtocol -Port -1 -Protocol Tls12 } | Should-Throw
        }

        It 'Uses 443 as default port' {
            Get-TestTlsProtocolParameterDefaultText -Name 'Port' | Should-Be '443'
        }

        It 'Accepts the valid timeout range' {
            $parameter = Get-TestTlsProtocolParameter -Name 'Timeout'
            $range = $parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }

            $range.MinRange | Should-Be 100
            $range.MaxRange | Should-Be 30000
        }

        It 'Rejects invalid timeout values' {
            { Test-TlsProtocol -Timeout 99 -Protocol Tls12 } | Should-Throw
            { Test-TlsProtocol -Timeout 30001 -Protocol Tls12 } | Should-Throw
        }

        It 'Uses 3000ms as default timeout' {
            Get-TestTlsProtocolParameterDefaultText -Name 'Timeout' | Should-Be '3000'
        }

        It 'Accepts supported TLS protocol values' {
            $parameter = Get-TestTlsProtocolParameter -Name 'Protocol'
            $validateSet = $parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }

            $validateSet.ValidValues | Should-BeCollection @('Tls', 'Tls11', 'Tls12', 'Tls13')
        }

        It 'Rejects invalid TLS protocol values' {
            { Test-TlsProtocol -Protocol 'InvalidProtocol' } | Should-Throw
            { Test-TlsProtocol -Protocol 'SSL3' } | Should-Throw
        }

        It 'Accepts supported application negotiation modes' {
            $parameter = Get-TestTlsProtocolParameter -Name 'Service'
            $validateSet = $parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }

            $validateSet.ValidValues | Should-BeCollection @(
                'Direct', 'Smtp', 'Imap', 'Pop3', 'Ftp', 'PostgreSql', 'MySql', 'SqlServer'
            )
        }

        It 'Keeps Basic as the default mode and requires the Full switch for expanded parameters' {
            $basicSet = $script:Command.ParameterSets | Where-Object Name -eq 'Basic'
            $fullSet = $script:Command.ParameterSets | Where-Object Name -eq 'Full'
            $fullSwitch = $fullSet.Parameters | Where-Object Name -eq 'Full'

            $basicSet.IsDefault | Should-Be $true
            $fullSet.IsDefault | Should-Be $false
            $fullSwitch.IsMandatory | Should-Be $true
            $basicSet.Parameters.Name | Should -Not -Contain 'Service'
            $fullSet.Parameters.Name | Should-ContainCollection 'Service'
        }

        It 'Uses Full as the canonical switch without compatibility aliases' {
            $fullParameter = Get-TestTlsProtocolParameter -Name 'Full'

            @($fullParameter.Aliases).Count | Should-Be 0
            $fullParameter.SwitchParameter | Should-Be $true
        }

        It 'Uses Direct as the default service' {
            Get-TestTlsProtocolParameterDefaultText -Name 'Service' | Should-Be "'Direct'"
        }

        It 'Rejects unsupported application negotiation modes' {
            { Test-TlsProtocol -Full -Service 'Https' -Protocol Tls12 } | Should-Throw
        }

        It 'Accepts SniName as an alias for TlsHostName' {
            $parameter = Get-TestTlsProtocolParameter -Name 'TlsHostName'
            $parameter.Aliases | Should-ContainCollection 'SniName'
        }

        It 'Uses TLS 1.2 as the default minimum security checkpoint' {
            Get-TestTlsProtocolParameterDefaultText -Name 'MinimumProtocol' | Should-Be "'Tls12'"
        }

        It 'Accepts only TLS 1.2 or TLS 1.3 as minimum security checkpoints' {
            $parameter = Get-TestTlsProtocolParameter -Name 'MinimumProtocol'
            $validateSet = $parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }

            $validateSet.ValidValues | Should-BeCollection @('Tls12', 'Tls13')
            { Test-TlsProtocol -Full -MinimumProtocol Tls11 -Protocol Tls12 } | Should-Throw
        }
    }

    Context 'Output structure' {
        It 'Returns objects with required properties' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'Server'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'Port'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'Protocol'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'Supported'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'Status'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'ResponseTime'
            $result[0].PSObject.Properties.Name | Should-BeCollection @(
                'Server', 'Port', 'Protocol', 'Supported', 'Status', 'ResponseTime'
            )
        }

        It 'Returns expanded evidence only in Full mode' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100 -Full

            $result[0].PSObject.Properties.Name | Should-ContainCollection 'Service'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'Provider'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'FailureStage'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'ValidationScope'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'ApplicationPolicyStatus'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'TlsHandshakeSupported'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'ServiceConnectionSupported'
            $result[0].PSObject.Properties.Name | Should-NotContainCollection 'Supported'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'NegotiatedProtocol'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'CipherSuite'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'CertificateValid'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'SecurityStatus'
            $result[0].PSObject.Properties.Name | Should-ContainCollection 'ErrorMessage'
        }

        It 'Has correct property types' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100

            $result[0].Server | Should-HaveType ([String])
            $result[0].Port | Should-HaveType ([Int])
            $result[0].Protocol | Should-HaveType ([String])
            $result[0].Supported | Should-HaveType ([Boolean])
            $result[0].Status | Should-HaveType ([String])
            $result[0].ResponseTime | Should-HaveType ([TimeSpan])
        }

        It 'Populates Server property correctly' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100
            $result[0].Server | Should-Be $script:FastFailureHost
        }

        It 'Populates Port property correctly' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Port 8443 -Protocol Tls12 -Timeout 100
            $result[0].Port | Should-Be 8443
        }

        It 'Populates Protocol property correctly' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100
            $result[0].Protocol | Should-Be 'Tls12'
        }

        It 'Uses an explicit SNI and certificate-validation hostname' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100 -Full -SniName 'service.example.test'
            $result[0].TlsHostName | Should-Be 'service.example.test'
        }

        It 'Separates connection failures from TLS handshake failures' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100 -Full

            $result[0].FailureStage | Should-Be 'Connect'
            $result[0].ValidationScope | Should-Be 'TlsHandshake'
            $result[0].ApplicationPolicyStatus | Should-Be 'NotEvaluated'
            $result[0].TlsHandshakeSupported | Should-Be $false
            ($null -eq $result[0].ServiceConnectionSupported) | Should-Be $true
            $result[0].ErrorType | Should -Not -BeNullOrEmpty
            $result[0].SecurityStatus | Should-Be 'NotEvaluated'
        }
    }

    Context 'Service-specific default ports' {
        It 'Uses port <ExpectedPort> for <Service> when Port is omitted' -ForEach @(
            @{ Service = 'Direct'; ExpectedPort = 443 }
            @{ Service = 'Smtp'; ExpectedPort = 25 }
            @{ Service = 'Imap'; ExpectedPort = 143 }
            @{ Service = 'Pop3'; ExpectedPort = 110 }
            @{ Service = 'Ftp'; ExpectedPort = 21 }
            @{ Service = 'PostgreSql'; ExpectedPort = 5432 }
            @{ Service = 'MySql'; ExpectedPort = 3306 }
            @{ Service = 'SqlServer'; ExpectedPort = 1433 }
        ) {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100 -Full -Service $Service

            $result.Port | Should-Be $ExpectedPort
            $result.Service | Should-Be $Service
        }

        It 'Preserves an explicit custom port for an application-aware service' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Port 15432 -Protocol Tls12 -Timeout 100 -Full -Service PostgreSql
            $result.Port | Should-Be 15432
        }
    }

    Context 'Application-aware TLS negotiation' {
        It 'Discovers SMTP STARTTLS before attempting the handshake' {
            $fixturePort = [TlsProbeFixture.Server]::Start('SmtpStartTls')

            $result = Test-TlsProtocol -ComputerName '127.0.0.1' -Port $fixturePort -Protocol Tls12 -Timeout 3000 -Full -Service Smtp

            Assert-TlsProbeFixture -Port $fixturePort
            $result.Negotiation | Should-Be 'StartTls'
            $result.StartTlsAdvertised | Should-Be $true
            $result.PreTlsCapabilities -join "`n" | Should-MatchString 'STARTTLS'
            $result.FailureStage | Should-Be 'Handshake'
        }

        It 'Reports a missing SMTP STARTTLS capability as a security failure' {
            $fixturePort = [TlsProbeFixture.Server]::Start('SmtpNoStartTls')

            $result = Test-TlsProtocol -ComputerName '127.0.0.1' -Port $fixturePort -Protocol Tls12 -Timeout 3000 -Full -Service Smtp

            Assert-TlsProbeFixture -Port $fixturePort
            $result.TlsHandshakeSupported | Should-Be $false
            ($null -eq $result.ServiceConnectionSupported) | Should-Be $true
            $result.StartTlsAdvertised | Should-Be $false
            $result.FailureStage | Should-Be 'Negotiation'
            $result.SecurityStatus | Should-Be 'Fail'
            $result.Status | Should-MatchString 'not advertised'
        }

        It 'Uses IMAP CAPABILITY and STARTTLS before TLS' {
            $fixturePort = [TlsProbeFixture.Server]::Start('ImapStartTls')

            $result = Test-TlsProtocol -ComputerName '127.0.0.1' -Port $fixturePort -Protocol Tls12 -Timeout 3000 -Full -Service Imap

            Assert-TlsProbeFixture -Port $fixturePort
            $result.Negotiation | Should-Be 'StartTls'
            $result.StartTlsAdvertised | Should-Be $true
            $result.FailureStage | Should-Be 'Handshake'
        }

        It 'Uses POP3 CAPA and STLS before TLS' {
            $fixturePort = [TlsProbeFixture.Server]::Start('Pop3StartTls')

            $result = Test-TlsProtocol -ComputerName '127.0.0.1' -Port $fixturePort -Protocol Tls12 -Timeout 3000 -Full -Service Pop3

            Assert-TlsProbeFixture -Port $fixturePort
            $result.Negotiation | Should-Be 'StartTls'
            $result.StartTlsAdvertised | Should-Be $true
            $result.FailureStage | Should-Be 'Handshake'
        }

        It 'Uses FTP FEAT and AUTH TLS before TLS' {
            $fixturePort = [TlsProbeFixture.Server]::Start('FtpStartTls')

            $result = Test-TlsProtocol -ComputerName '127.0.0.1' -Port $fixturePort -Protocol Tls12 -Timeout 3000 -Full -Service Ftp

            Assert-TlsProbeFixture -Port $fixturePort
            $result.Negotiation | Should-Be 'AuthTls'
            $result.StartTlsAdvertised | Should-Be $true
            $result.FailureStage | Should-Be 'Handshake'
        }

        It 'Sends the PostgreSQL SSLRequest before TLS' {
            $fixturePort = [TlsProbeFixture.Server]::Start('PostgreSql')

            $result = Test-TlsProtocol -ComputerName '127.0.0.1' -Port $fixturePort -Protocol Tls12 -Timeout 3000 -Full -Service PostgreSql

            Assert-TlsProbeFixture -Port $fixturePort
            $result.Negotiation | Should-Be 'PostgreSqlSslRequest'
            $result.FailureStage | Should-Be 'Handshake'
        }

        It 'Reports a PostgreSQL SSLRequest rejection as a security failure' {
            $fixturePort = [TlsProbeFixture.Server]::Start('PostgreSqlNoTls')

            $result = Test-TlsProtocol -ComputerName '127.0.0.1' -Port $fixturePort -Protocol Tls12 -Timeout 3000 -Full -Service PostgreSql

            Assert-TlsProbeFixture -Port $fixturePort
            $result.FailureStage | Should-Be 'Negotiation'
            $result.SecurityStatus | Should-Be 'Fail'
            $result.Status | Should-MatchString 'returned N'
        }

        It 'Sends a MySQL CLIENT_SSL request before TLS' {
            $fixturePort = [TlsProbeFixture.Server]::Start('MySql')

            $result = Test-TlsProtocol -ComputerName '127.0.0.1' -Port $fixturePort -Protocol Tls12 -Timeout 3000 -Full -Service MySql

            Assert-TlsProbeFixture -Port $fixturePort
            $result.Negotiation | Should-Be 'MySqlSslRequest'
            $result.FailureStage | Should-Be 'Handshake'
        }

        It 'Reports a missing MySQL CLIENT_SSL capability as a security failure' {
            $fixturePort = [TlsProbeFixture.Server]::Start('MySqlNoTls')

            $result = Test-TlsProtocol -ComputerName '127.0.0.1' -Port $fixturePort -Protocol Tls12 -Timeout 3000 -Full -Service MySql

            Assert-TlsProbeFixture -Port $fixturePort
            $result.FailureStage | Should-Be 'Negotiation'
            $result.SecurityStatus | Should-Be 'Fail'
            $result.Status | Should-MatchString 'CLIENT_SSL'
        }

        It 'Wraps a SQL Server TLS ClientHello in TDS PRELOGIN packets' {
            $fixturePort = [TlsProbeFixture.Server]::Start('SqlServer')

            $result = Test-TlsProtocol -ComputerName '127.0.0.1' -Port $fixturePort -Protocol Tls12 -Timeout 3000 -Full -Service SqlServer

            Assert-TlsProbeFixture -Port $fixturePort
            $result.Negotiation | Should-Be 'Tds7Prelogin'
            $result.ValidationScope | Should-Be 'ServiceNegotiationAndTlsHandshake'
            $result.ApplicationPolicyStatus | Should-Be 'NotEvaluated'
            ($null -eq $result.ServiceConnectionSupported) | Should-Be $true
            $result.FailureStage | Should-Be 'Handshake'
        }

        It 'Reports SQL Server ENCRYPT_NOT_SUP as a security failure' {
            $fixturePort = [TlsProbeFixture.Server]::Start('SqlServerNoTls')

            $result = Test-TlsProtocol -ComputerName '127.0.0.1' -Port $fixturePort -Protocol Tls12 -Timeout 3000 -Full -Service SqlServer

            Assert-TlsProbeFixture -Port $fixturePort
            $result.FailureStage | Should-Be 'Negotiation'
            $result.SecurityStatus | Should-Be 'Fail'
            $result.Status | Should-MatchString 'ENCRYPT_NOT_SUP'
        }

        It 'Directs SQL Server TLS 1.3 probes to TDS 8.0 direct TLS' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls13 -Timeout 100 -Full -Service SqlServer

            $result.Port | Should-Be 1433
            $result.FailureStage | Should-Be 'Local'
            $result.Status | Should-MatchString 'TDS 8.0'
        }
    }

    Context 'Multiple protocol testing' {
        It 'Tests multiple protocols when specified' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12, Tls13 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result | Should-BeCollection -Count 2
            $result[0].Protocol | Should-Be 'Tls12'
            $result[1].Protocol | Should-Be 'Tls13'
        }

        It 'Tests all protocols when none specified' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result | Should-BeCollection -Count 4
            $result[0].Protocol | Should-Be 'Tls'
            $result[1].Protocol | Should-Be 'Tls11'
            $result[2].Protocol | Should-Be 'Tls12'
            $result[3].Protocol | Should-Be 'Tls13'
        }
    }

    Context 'Pipeline input support' {
        It 'Accepts pipeline input for ComputerName' {
            $result = $script:FastFailureHost | Test-TlsProtocol -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result[0].Server | Should-Be $script:FastFailureHost
        }

        It 'Handles multiple computer names via pipeline' {
            $servers = @($script:FastFailureHost, 'another-hostname-that-does-not-exist-12345.invalid')
            $result = $servers | Test-TlsProtocol -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result | Should-BeCollection -Count 2
            $result[0].Server | Should-Be $servers[0]
            $result[1].Server | Should-Be $servers[1]
        }
    }

    Context 'Error handling' {
        It 'Handles connection failures gracefully' {
            $result = Test-TlsProtocol -ComputerName '192.0.2.1' -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result[0].Supported | Should-Be $false
            $result[0].Status | Should -Not -BeNullOrEmpty
        }

        It 'Handles invalid hostnames gracefully' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result[0].Supported | Should-Be $false
        }

        It 'Handles timeout scenarios' {
            $result = Test-TlsProtocol -ComputerName '192.0.2.1' -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result[0].Supported | Should-Be $false
            $result[0].Status | Should-MatchString 'timeout|failed'
        }
    }

    Context 'Alias support' {
        It 'Accepts Server alias for ComputerName' {
            $result = Test-TlsProtocol -Server $script:FastFailureHost -Protocol Tls12 -Timeout 100
            $result[0].Server | Should-Be $script:FastFailureHost
        }

        It 'Accepts Host alias for ComputerName' {
            $result = Test-TlsProtocol -Host $script:FastFailureHost -Protocol Tls12 -Timeout 100
            $result[0].Server | Should-Be $script:FastFailureHost
        }

        It 'Accepts HostName alias for ComputerName' {
            $result = Test-TlsProtocol -HostName $script:FastFailureHost -Protocol Tls12 -Timeout 100
            $result[0].Server | Should-Be $script:FastFailureHost
        }
    }
}
