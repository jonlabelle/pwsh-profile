function Get-CertificateExpiration
{
    <#
    .SYNOPSIS
        Gets the expiration date of an SSL/TLS certificate from a remote host.

    .DESCRIPTION
        This function connects to a remote host via SSL/TLS and retrieves the certificate's expiration date.
        It can check multiple hosts and ports, and provides options for timeout configuration and
        detailed certificate information. The function returns the certificate's NotAfter date which
        indicates when the certificate expires.

    .PARAMETER ComputerName
        The hostname or IP address to check for SSL certificate expiration.
        Accepts an array of computer names. Defaults to 'localhost' if not specified.

    .PARAMETER Port
        The port number to connect to for SSL certificate retrieval.
        Defaults to 443 (standard HTTPS port).

    .PARAMETER Timeout
        Connection timeout in milliseconds. Defaults to 10000 (10 seconds).

    .PARAMETER IncludeCertificateDetails
        If specified, returns detailed certificate information including subject, issuer,
        thumbprint, and other certificate properties instead of just the expiration date.

    .PARAMETER WarnIfExpiresSoon
        If specified, displays a warning if the certificate expires within the specified number of days.
        Defaults to 30 days if the switch is used without a value.

    .PARAMETER DaysToWarn
        Number of days before expiration to show warning. Only used when WarnIfExpiresSoon is specified.
        Defaults to 30 days.

    .EXAMPLE
        PS > Get-CertificateExpiration -ComputerName 'google.com'

        Gets the SSL certificate expiration date for google.com on port 443.

    .EXAMPLE
        PS > Get-CertificateExpiration -ComputerName 'example.com' -Port 8443

        Gets the SSL certificate expiration date for example.com on port 8443.

    .EXAMPLE
        PS > @('google.com', 'github.com', 'stackoverflow.com') | Get-CertificateExpiration

        Gets SSL certificate expiration dates for multiple hosts using pipeline input.

    .EXAMPLE
        PS > Get-CertificateExpiration -ComputerName 'expired.badssl.com' -WarnIfExpiresSoon -DaysToWarn 90

        Gets the certificate expiration date and warns if it expires within 90 days.

    .EXAMPLE
        PS > Get-CertificateExpiration -ComputerName 'google.com' -IncludeCertificateDetails

        Gets detailed certificate information including expiration date, subject, issuer, and thumbprint.

    .EXAMPLE
        PS > Get-CertificateExpiration -ComputerName 'internal.company.com' -Port 8443 -Timeout 5000

        Gets certificate expiration with a 5-second timeout for internal servers.

    .OUTPUTS
        System.DateTime
        Returns the certificate expiration date when IncludeCertificateDetails is not specified.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns detailed certificate information when IncludeCertificateDetails is specified.

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.security.cryptography.x509certificates.x509certificate2

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.net.security.sslstream
    #>

    [CmdletBinding()]
    [OutputType([System.DateTime], [System.Management.Automation.PSCustomObject])]
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
        $IncludeCertificateDetails,

        [Parameter()]
        [Switch]
        $WarnIfExpiresSoon,

        [Parameter()]
        [ValidateRange(1, 365)]
        [Int32]
        $DaysToWarn = 30
    )

    begin
    {
        Write-Verbose 'Starting SSL certificate expiration check'

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

                # Get the certificate
                $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $sslStream.RemoteCertificate

                return $certificate
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
    }

    process
    {
        foreach ($computer in $ComputerName)
        {
            Write-Verbose "Processing host: $computer"

            $certificate = Get-CertificateFromHost -HostName $computer -PortNumber $Port -TimeoutMs $Timeout

            if ($certificate)
            {
                $expirationDate = $certificate.NotAfter
                $daysUntilExpiration = ($expirationDate - (Get-Date)).Days

                # Check if warning should be displayed
                if ($WarnIfExpiresSoon -and $daysUntilExpiration -le $DaysToWarn)
                {
                    if ($daysUntilExpiration -lt 0)
                    {
                        Write-Warning "Certificate for $computer`:$Port EXPIRED $([Math]::Abs($daysUntilExpiration)) days ago on $($expirationDate.ToString('yyyy-MM-dd HH:mm:ss'))"
                    }
                    else
                    {
                        Write-Warning "Certificate for $computer`:$Port expires in $daysUntilExpiration days on $($expirationDate.ToString('yyyy-MM-dd HH:mm:ss'))"
                    }
                }

                if ($IncludeCertificateDetails)
                {
                    # Return detailed certificate information
                    [PSCustomObject]@{
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
                        Version = $certificate.Version
                        HasPrivateKey = $certificate.HasPrivateKey
                    }
                }
                else
                {
                    # Return just the expiration date
                    $expirationDate
                }
            }
        }
    }

    end
    {
        Write-Verbose 'SSL certificate expiration check completed'
    }
}
