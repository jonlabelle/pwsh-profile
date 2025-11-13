function Get-CertificateDetails
{
    <#
    .SYNOPSIS
        Gets detailed SSL/TLS certificate information from remote hosts.

    .DESCRIPTION
        This function connects to remote hosts via SSL/TLS and retrieves comprehensive certificate details
        including subject, issuer, expiration dates, thumbprint, serial number, signature algorithm, and more.
        It supports checking multiple hosts and ports with configurable timeout settings. The function is
        cross-platform compatible and works with PowerShell 5.1+ on Windows, macOS, and Linux.

    .PARAMETER ComputerName
        The hostname or IP address to retrieve SSL certificate details from.
        Accepts an array of computer names. Defaults to 'localhost' if not specified.

    .PARAMETER Port
        The port number to connect to for SSL certificate retrieval.
        Defaults to 443 (standard HTTPS port).

    .PARAMETER Timeout
        Connection timeout in milliseconds. Defaults to 10000 (10 seconds).
        Valid range is 1000-300000 milliseconds (1 second to 5 minutes).

    .PARAMETER IncludeChain
        If specified, includes the full certificate chain information in the output.
        This provides details about intermediate and root certificates.

    .PARAMETER IncludeExtensions
        If specified, includes certificate extensions information such as Subject Alternative Names (SAN),
        Key Usage, Extended Key Usage, and other X.509 extensions.

    .EXAMPLE
        PS > Get-CertificateDetails -ComputerName 'jonlabelle.com'

        ComputerName        : jonlabelle.com
        Port                : 443
        Subject             : CN=jonlabelle.com
        Issuer              : CN=E7, O=Let's Encrypt, C=US
        NotBefore           : 10/18/2025 11:04:17 PM
        NotAfter            : 1/16/2026 10:04:16 PM
        Thumbprint          : FF17282B73B22DF319B705F3197948CCABF6C5D7
        SerialNumber        : 05366C8540C1118373AE7974C87C6B0DD64C
        DaysUntilExpiration : 64
        IsExpired           : False
        SignatureAlgorithm  : sha384ECDSA
        PublicKeyAlgorithm  : ECC
        KeySize             :
        Version             : 3
        HasPrivateKey       : False
        FriendlyName        :
        Archived            : False

        Gets detailed SSL certificate information for google.com on port 443.

    .EXAMPLE
        PS > Get-CertificateDetails -ComputerName 'example.com' -Port 8443

        Gets detailed SSL certificate information for example.com on port 8443.

    .EXAMPLE
        PS > @('google.com', 'github.com', 'stackoverflow.com') | Get-CertificateDetails

        Gets detailed SSL certificate information for multiple hosts using pipeline input.

    .EXAMPLE
        PS > Get-CertificateDetails -ComputerName 'secure.company.com' -Timeout 5000 -IncludeChain

        Gets certificate details with a 5-second timeout and includes certificate chain information.

    .EXAMPLE
        PS > Get-CertificateDetails -ComputerName 'google.com' -IncludeExtensions

        ComputerName        : jonlabelle.com
        Port                : 443
        Subject             : CN=jonlabelle.com
        Issuer              : CN=E7, O=Let's Encrypt, C=US
        NotBefore           : 10/18/2025 11:04:17 PM
        NotAfter            : 1/16/2026 10:04:16 PM
        Thumbprint          : FF17282B73B22DF319B705F3197948CCABF6C5D7
        SerialNumber        : 05366C8540C1118373AE7974C87C6B0DD64C
        DaysUntilExpiration : 64
        IsExpired           : False
        SignatureAlgorithm  : sha384ECDSA
        PublicKeyAlgorithm  : ECC
        KeySize             :
        Version             : 3
        HasPrivateKey       : False
        FriendlyName        :
        Archived            : False
        Extensions          : {[X509v3 Basic Constraints, 3000], [X509v3 Subject Key Identifier,
                            04146C3FD1BB47BA89B36B6807950DFDDB952C12CBF8], [2.5.29.32, 300A3008060667810C010201], [Authority
                            Information Access, 3024302206082B060105050730028616687474703A2F2F65372E692E6C656E63722E6F72672F]…}

        Gets certificate details including X.509 extensions like Subject Alternative Names.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns detailed certificate information including subject, issuer, dates, thumbprint, and other properties.

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.security.cryptography.x509certificates.x509certificate2

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.net.security.sslstream

    .NOTES
        This function requires network connectivity to the target host and port.
        The certificate validation callback is set to always return true to retrieve certificates
        even if they have validation issues (expired, self-signed, etc.).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('HostName', 'Server', 'Name')]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $ComputerName = 'localhost',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [Int32]
        $Port = 443,

        [Parameter()]
        [ValidateRange(1000, 300000)]
        [Int32]
        $Timeout = 10000,

        [Parameter()]
        [Switch]
        $IncludeChain,

        [Parameter()]
        [Switch]
        $IncludeExtensions
    )

    begin
    {
        Write-Verbose 'Starting SSL certificate details retrieval'

        function Get-CertificateFromHost
        {
            param
            (
                [String]$HostName,
                [Int32]$PortNumber,
                [Int32]$TimeoutMs
            )

            $tcpClient = $null
            $sslStream = $null

            try
            {
                Write-Verbose "Connecting to $HostName`:$PortNumber with timeout ${TimeoutMs}ms"

                # Create TCP client with timeout
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $tcpClient.ReceiveTimeout = $TimeoutMs
                $tcpClient.SendTimeout = $TimeoutMs

                # Connect to the host
                $connectTask = $tcpClient.ConnectAsync($HostName, $PortNumber)
                if (-not $connectTask.Wait($TimeoutMs))
                {
                    throw "Connection to $HostName`:$PortNumber timed out after ${TimeoutMs}ms"
                }

                # Create SSL stream with certificate validation callback that always returns true
                $sslStream = New-Object System.Net.Security.SslStream(
                    $tcpClient.GetStream(),
                    $false,
                    { param($senderObject, $certificate, $chain, $sslPolicyErrors) return $true }
                )

                # Authenticate as client to get the certificate
                $sslStream.AuthenticateAsClient($HostName)

                # Get the certificate and chain
                $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $sslStream.RemoteCertificate

                $result = @{
                    Certificate = $certificate
                    Chain = $null
                }

                # Get certificate chain if requested
                if ($IncludeChain)
                {
                    try
                    {
                        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
                        $chain.Build($certificate) | Out-Null
                        $result.Chain = $chain
                    }
                    catch
                    {
                        Write-Verbose "Could not build certificate chain: $($_.Exception.Message)"
                    }
                }

                return $result
            }
            catch
            {
                Write-Error "Failed to retrieve SSL certificate from $HostName`:$PortNumber - $($_.Exception.Message)"
                return $null
            }
            finally
            {
                # Clean up connections
                if ($sslStream)
                {
                    $sslStream.Close()
                    $sslStream.Dispose()
                }
                if ($tcpClient)
                {
                    $tcpClient.Close()
                    $tcpClient.Dispose()
                }
            }
        }

        function Get-CertificateExtensions
        {
            param
            (
                [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
            )

            $extensions = @{}

            foreach ($extension in $Certificate.Extensions)
            {
                switch ($extension.Oid.FriendlyName)
                {
                    'Subject Alternative Name'
                    {
                        $san = New-Object System.Security.Cryptography.X509Certificates.X509Extension $extension, $false
                        $extensions['SubjectAlternativeName'] = $san.Format($false)
                    }
                    'Key Usage'
                    {
                        $keyUsage = [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]$extension
                        $extensions['KeyUsage'] = $keyUsage.KeyUsages.ToString()
                    }
                    'Enhanced Key Usage'
                    {
                        $enhancedKeyUsage = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]$extension
                        $extensions['EnhancedKeyUsage'] = ($enhancedKeyUsage.EnhancedKeyUsages | ForEach-Object { $_.FriendlyName }) -join ', '
                    }
                    'Basic Constraints'
                    {
                        $basicConstraints = [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]$extension
                        $extensions['BasicConstraints'] = "CA=$($basicConstraints.CertificateAuthority), PathLength=$($basicConstraints.PathLengthConstraint)"
                    }
                    default
                    {
                        # Use OID value if FriendlyName is null
                        $keyName = if ($extension.Oid.FriendlyName) { $extension.Oid.FriendlyName } else { $extension.Oid.Value }
                        if ($keyName)
                        {
                            $extensions[$keyName] = $extension.Format($false)
                        }
                    }
                }
            }

            return $extensions
        }
    }

    process
    {
        foreach ($computer in $ComputerName)
        {
            Write-Verbose "Processing host: $computer"

            $certResult = Get-CertificateFromHost -HostName $computer -PortNumber $Port -TimeoutMs $Timeout

            if ($certResult -and $certResult.Certificate)
            {
                $certificate = $certResult.Certificate
                $expirationDate = $certificate.NotAfter
                $daysUntilExpiration = ($expirationDate - (Get-Date)).Days

                # Build the main certificate details object
                $details = [PSCustomObject]@{
                    ComputerName = $computer
                    Port = $Port
                    Subject = $certificate.Subject
                    Issuer = $certificate.Issuer
                    NotBefore = $certificate.NotBefore
                    NotAfter = $certificate.NotAfter
                    Thumbprint = $certificate.Thumbprint
                    SerialNumber = $certificate.SerialNumber
                    DaysUntilExpiration = $daysUntilExpiration
                    IsExpired = $daysUntilExpiration -lt 0
                    SignatureAlgorithm = $certificate.SignatureAlgorithm.FriendlyName
                    PublicKeyAlgorithm = $certificate.PublicKey.Oid.FriendlyName
                    KeySize = $certificate.PublicKey.Key.KeySize
                    Version = $certificate.Version
                    HasPrivateKey = $certificate.HasPrivateKey
                    FriendlyName = $certificate.FriendlyName
                    Archived = $certificate.Archived
                }

                # Add certificate extensions if requested
                if ($IncludeExtensions)
                {
                    $extensions = Get-CertificateExtensions -Certificate $certificate
                    $details | Add-Member -MemberType NoteProperty -Name 'Extensions' -Value $extensions
                }

                # Add certificate chain if requested and available
                if ($IncludeChain -and $certResult.Chain)
                {
                    $chainInfo = @()
                    foreach ($chainElement in $certResult.Chain.ChainElements)
                    {
                        $chainInfo += [PSCustomObject]@{
                            Subject = $chainElement.Certificate.Subject
                            Issuer = $chainElement.Certificate.Issuer
                            Thumbprint = $chainElement.Certificate.Thumbprint
                            NotBefore = $chainElement.Certificate.NotBefore
                            NotAfter = $chainElement.Certificate.NotAfter
                            ChainElementStatus = $chainElement.ChainElementStatus
                        }
                    }
                    $details | Add-Member -MemberType NoteProperty -Name 'CertificateChain' -Value $chainInfo
                    $details | Add-Member -MemberType NoteProperty -Name 'ChainStatus' -Value $certResult.Chain.ChainStatus
                }

                # Output the details
                $details
            }
        }
    }

    end
    {
        Write-Verbose 'SSL certificate details retrieval completed'
    }
}
