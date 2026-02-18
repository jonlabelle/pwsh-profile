function Get-CertificateExpiration
{
    <#
    .SYNOPSIS
        Gets the expiration date of an SSL/TLS certificate from a remote host or certificate file.

    .DESCRIPTION
        This function retrieves the certificate's expiration date (NotAfter) from either a remote host
        via SSL/TLS or from local certificate files (.cer/.crt/.der/.pem). It can check multiple hosts
        or files, provides options for timeout configuration, and can return detailed certificate information.
        Values passed through ComputerName (or positional input) are automatically interpreted as host/URL targets
        or local certificate paths.

    .PARAMETER ComputerName
        The hostname, IP address, URL, or certificate path to check for SSL certificate expiration.
        Accepts an array of values and auto-detects whether each one is a remote endpoint or local cert file.
        Defaults to 'localhost' if not specified.

    .PARAMETER Path
        Path to one or more certificate files to inspect.
        Supports wildcard paths and PEM files with one or more certificate blocks.

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
        PS > Get-CertificateExpiration -ComputerName 'bing.com'

        Monday, January 5, 2026 3:37:32 AM

        Gets the SSL certificate expiration date for bing.com on port 443.

    .EXAMPLE
        PS > Get-CertificateExpiration -ComputerName 'example.com' -Port 8443

        Gets the SSL certificate expiration date for example.com on port 8443.

    .EXAMPLE
        PS > @('bing.com', 'github.com', 'stackoverflow.com') | Get-CertificateExpiration

        Gets SSL certificate expiration dates for multiple hosts using pipeline input.

    .EXAMPLE
        PS > Get-CertificateExpiration -ComputerName 'expired.badssl.com' -WarnIfExpiresSoon -DaysToWarn 90

        WARNING: Certificate for expired.badssl.com:443 EXPIRED 3867 days ago on 2015-04-12 19:59:59

        Sunday, April 12, 2015 7:59:59 PM

        Gets the certificate expiration date and warns if it expires within 90 days.

    .EXAMPLE
        PS > Get-CertificateExpiration -ComputerName 'jonlabelle.com' -IncludeCertificateDetails

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
        Version             : 3
        HasPrivateKey       : False

        Gets detailed certificate information including expiration date, subject, issuer, and thumbprint.

    .EXAMPLE
        PS > Get-CertificateExpiration -ComputerName 'internal.company.com' -Port 8443 -Timeout 5000

        Gets certificate expiration with a 5-second timeout for internal servers.

    .EXAMPLE
        PS > $hosts = kubectl get ingress --all-namespaces -o json | ConvertFrom-Json | % { $_.spec.rules.host }
        PS > $hosts | Get-CertificateExpiration -WarnIfExpiresSoon -DaysToWarn 21 | Out-String | Send-TeamMessage -Channel '#alerts'

        Pulls hostnames from Kubernetes ingress objects, checks for certificates expiring within 21 days, and posts the results to a team chat.

    .EXAMPLE
        PS > Get-CertificateExpiration -Path './certs/public.pem', './certs/internal.cer' -IncludeCertificateDetails

        Reads local certificate files and returns expiration details for each certificate.

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

    .NOTES
        Network connectivity is required only for host/URL targets.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Security/Get-CertificateExpiration.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Security/Get-CertificateExpiration.ps1
    #>

    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    [OutputType([System.DateTime], [System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(ParameterSetName = 'ComputerName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('HostName', 'Server', 'Name')]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $ComputerName = 'localhost',

        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [Alias('FilePath', 'LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Path,

        [Parameter(ParameterSetName = 'ComputerName')]
        [ValidateRange(1, 65535)]
        [Int32]
        $Port = 443,

        [Parameter(ParameterSetName = 'ComputerName')]
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

        function Resolve-CertificateTarget
        {
            param
            (
                [String]$InputValue,
                [Int32]$DefaultPort,
                [Switch]$ForcePath
            )

            if ([string]::IsNullOrWhiteSpace($InputValue))
            {
                return $null
            }

            $trimmedValue = $InputValue.Trim()

            if ($ForcePath)
            {
                return [PSCustomObject]@{
                    Type = 'Path'
                    Path = $trimmedValue
                    HostName = $null
                    Port = $null
                }
            }

            # Existing files/wildcards should always be treated as local certificate paths.
            try
            {
                if (Resolve-Path -Path $trimmedValue -ErrorAction Stop)
                {
                    return [PSCustomObject]@{
                        Type = 'Path'
                        Path = $trimmedValue
                        HostName = $null
                        Port = $null
                    }
                }
            }
            catch
            {
                Write-Verbose "Input '$trimmedValue' did not resolve as an existing path. Continuing with host/URL detection."
            }

            $absoluteUri = $null
            if ([Uri]::TryCreate($trimmedValue, [UriKind]::Absolute, [ref]$absoluteUri))
            {
                if ($absoluteUri.IsFile)
                {
                    return [PSCustomObject]@{
                        Type = 'Path'
                        Path = $absoluteUri.LocalPath
                        HostName = $null
                        Port = $null
                    }
                }

                if ($absoluteUri.Host)
                {
                    $resolvedPort = if (($absoluteUri.Port -ge 1) -and ($absoluteUri.Port -le 65535))
                    {
                        if ($absoluteUri.IsDefaultPort -or ($absoluteUri.Scheme -eq 'http' -and $absoluteUri.Port -eq 80))
                        {
                            $DefaultPort
                        }
                        else
                        {
                            $absoluteUri.Port
                        }
                    }
                    else
                    {
                        $DefaultPort
                    }

                    return [PSCustomObject]@{
                        Type = 'Host'
                        Path = $null
                        HostName = $absoluteUri.DnsSafeHost
                        Port = $resolvedPort
                    }
                }
            }

            $looksLikePath = $trimmedValue -match '^[a-zA-Z]:[\\/]' -or
                $trimmedValue -match '^[\\/]{2}' -or
                $trimmedValue.StartsWith('./') -or
                $trimmedValue.StartsWith('.\\') -or
                $trimmedValue.StartsWith('../') -or
                $trimmedValue.StartsWith('..\\') -or
                $trimmedValue.StartsWith('~/') -or
                $trimmedValue.StartsWith('~\\') -or
                $trimmedValue -match '[\\/]' -or
                $trimmedValue -like '*`**' -or
                $trimmedValue -match '\.(cer|crt|der|pem|p7b|pfx|p12)$'

            if ($looksLikePath)
            {
                return [PSCustomObject]@{
                    Type = 'Path'
                    Path = $trimmedValue
                    HostName = $null
                    Port = $null
                }
            }

            $tcpUri = $null
            if ([Uri]::TryCreate("tcp://$trimmedValue", [UriKind]::Absolute, [ref]$tcpUri) -and $tcpUri.Host)
            {
                $resolvedPort = if (($tcpUri.Port -ge 1) -and ($tcpUri.Port -le 65535) -and -not $tcpUri.IsDefaultPort)
                {
                    $tcpUri.Port
                }
                else
                {
                    $DefaultPort
                }

                return [PSCustomObject]@{
                    Type = 'Host'
                    Path = $null
                    HostName = $tcpUri.DnsSafeHost
                    Port = $resolvedPort
                }
            }

            return [PSCustomObject]@{
                Type = 'Host'
                Path = $null
                HostName = $trimmedValue
                Port = $DefaultPort
            }
        }

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

        function Get-CertificatesFromPemText
        {
            param
            (
                [String]$PemText
            )

            $certificates = @()
            $pemPattern = '-----BEGIN CERTIFICATE-----\s*(?<Body>.*?)\s*-----END CERTIFICATE-----'
            $pemMatches = [System.Text.RegularExpressions.Regex]::Matches(
                $PemText,
                $pemPattern,
                [System.Text.RegularExpressions.RegexOptions]::Singleline
            )

            foreach ($pemMatch in $pemMatches)
            {
                $base64Body = ($pemMatch.Groups['Body'].Value -replace '\s', '')
                if ([string]::IsNullOrWhiteSpace($base64Body))
                {
                    continue
                }

                $certificateBytes = [Convert]::FromBase64String($base64Body)
                $certificates += [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificateBytes)
            }

            return $certificates
        }

        function Get-CertificateFromFile
        {
            param
            (
                [String]$CertificatePath
            )

            $resolvedPaths = @()

            try
            {
                $resolvedPaths = Resolve-Path -Path $CertificatePath -ErrorAction Stop
            }
            catch
            {
                Write-Error "Failed to resolve certificate path '$CertificatePath' - $($_.Exception.Message)"
                return @()
            }

            $results = @()

            foreach ($resolvedPath in $resolvedPaths)
            {
                $fullPath = $resolvedPath.ProviderPath

                if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf))
                {
                    Write-Error "Certificate path '$fullPath' is not a file."
                    continue
                }

                try
                {
                    Write-Verbose "Loading certificate file: $fullPath"

                    $certificates = @()
                    $fileText = Get-Content -LiteralPath $fullPath -Raw -ErrorAction Stop

                    if ($fileText -match '-----BEGIN CERTIFICATE-----')
                    {
                        $certificates = Get-CertificatesFromPemText -PemText $fileText
                    }

                    if ($certificates.Count -eq 0)
                    {
                        $certificates = @([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($fullPath))
                    }

                    if ($certificates.Count -eq 0)
                    {
                        throw "No certificates were found in '$fullPath'."
                    }

                    foreach ($certificate in $certificates)
                    {
                        $results += [PSCustomObject]@{
                            Certificate = $certificate
                            CertificatePath = $fullPath
                        }
                    }
                }
                catch
                {
                    Write-Error "Failed to load certificate file '$fullPath' - $($_.Exception.Message)"
                }
            }

            return $results
        }
    }

    process
    {
        $isPathParameterSet = $PSCmdlet.ParameterSetName -eq 'Path'
        $inputValues = if ($isPathParameterSet) { $Path } else { $ComputerName }

        foreach ($inputValue in $inputValues)
        {
            $target = Resolve-CertificateTarget -InputValue $inputValue -DefaultPort $Port -ForcePath:$isPathParameterSet
            if (-not $target)
            {
                continue
            }

            if ($target.Type -eq 'Path')
            {
                Write-Verbose "Processing certificate file path: $($target.Path)"

                $certificateEntries = Get-CertificateFromFile -CertificatePath $target.Path

                foreach ($certificateEntry in $certificateEntries)
                {
                    $certificate = $certificateEntry.Certificate

                    if (-not $certificate)
                    {
                        continue
                    }

                    $expirationDate = $certificate.NotAfter
                    $daysUntilExpiration = ($expirationDate - (Get-Date)).Days

                    # Check if warning should be displayed
                    if ($WarnIfExpiresSoon -and $daysUntilExpiration -le $DaysToWarn)
                    {
                        if ($daysUntilExpiration -lt 0)
                        {
                            Write-Warning "Certificate in file $($certificateEntry.CertificatePath) EXPIRED $([Math]::Abs($daysUntilExpiration)) days ago on $($expirationDate.ToString('yyyy-MM-dd HH:mm:ss'))"
                        }
                        else
                        {
                            Write-Warning "Certificate in file $($certificateEntry.CertificatePath) expires in $daysUntilExpiration days on $($expirationDate.ToString('yyyy-MM-dd HH:mm:ss'))"
                        }
                    }

                    if ($IncludeCertificateDetails)
                    {
                        # Return detailed certificate information
                        [PSCustomObject]@{
                            ComputerName = $null
                            Port = $null
                            CertificatePath = $certificateEntry.CertificatePath
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
                continue
            }

            Write-Verbose "Processing host: $($target.HostName)"

            $certificate = Get-CertificateFromHost -HostName $target.HostName -PortNumber $target.Port -TimeoutMs $Timeout

            if ($certificate)
            {
                $expirationDate = $certificate.NotAfter
                $daysUntilExpiration = ($expirationDate - (Get-Date)).Days

                # Check if warning should be displayed
                if ($WarnIfExpiresSoon -and $daysUntilExpiration -le $DaysToWarn)
                {
                    if ($daysUntilExpiration -lt 0)
                    {
                        Write-Warning "Certificate for $($target.HostName):$($target.Port) EXPIRED $([Math]::Abs($daysUntilExpiration)) days ago on $($expirationDate.ToString('yyyy-MM-dd HH:mm:ss'))"
                    }
                    else
                    {
                        Write-Warning "Certificate for $($target.HostName):$($target.Port) expires in $daysUntilExpiration days on $($expirationDate.ToString('yyyy-MM-dd HH:mm:ss'))"
                    }
                }

                if ($IncludeCertificateDetails)
                {
                    # Return detailed certificate information
                    [PSCustomObject]@{
                        ComputerName = $target.HostName
                        Port = $target.Port
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
