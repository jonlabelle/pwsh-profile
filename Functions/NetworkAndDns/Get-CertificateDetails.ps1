function Get-CertificateDetails
{
    <#
    .SYNOPSIS
        Gets detailed SSL/TLS certificate information from remote hosts or certificate files.

    .DESCRIPTION
        This function retrieves comprehensive certificate details including subject, issuer, expiration dates,
        thumbprint, serial number, signature algorithm, and more. It supports checking remote hosts over SSL/TLS
        (with configurable timeout and port settings) and local certificate files (.cer/.crt/.der/.pem).
        The function is cross-platform compatible and works with PowerShell 5.1+ on Windows, macOS, and Linux.

    .PARAMETER ComputerName
        The hostname or IP address to retrieve SSL certificate details from.
        Accepts an array of computer names. Defaults to 'localhost' if not specified.

    .PARAMETER Path
        Path to one or more certificate files to inspect.
        Supports wildcard paths and PEM files with one or more certificate blocks.

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

        Gets detailed SSL certificate information for bing.com on port 443.

    .EXAMPLE
        PS > Get-CertificateDetails -ComputerName 'example.com' -Port 8443

        Gets detailed SSL certificate information for example.com on port 8443.

    .EXAMPLE
        PS > @('bing.com', 'github.com', 'stackoverflow.com') | Get-CertificateDetails

        Gets detailed SSL certificate information for multiple hosts using pipeline input.

    .EXAMPLE
        PS > Get-CertificateDetails -ComputerName 'secure.company.com' -Timeout 5000 -IncludeChain

        Gets certificate details with a 5-second timeout and includes certificate chain information.

    .EXAMPLE
        PS > Get-CertificateDetails -ComputerName 'bing.com' -IncludeExtensions

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

    .EXAMPLE
        PS > Get-Content ./hosts.txt | Get-CertificateDetails | Where-Object { $_.DaysUntilExpiration -lt 14 }

        Reads a list of customer domains from a file and surfaces any certificates expiring within two weeks for proactive renewals.

    .EXAMPLE
        PS > Get-CertificateDetails -Path './certs/api-gateway.pem', './certs/internal.cer'

        Reads certificate details from local certificate files.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns detailed certificate information including subject, issuer, dates, thumbprint, and other properties.

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.security.cryptography.x509certificates.x509certificate2

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.net.security.sslstream

    .NOTES
        Network connectivity is required only when using the ComputerName parameter set.
        The certificate validation callback is set to always return true to retrieve certificates
        even if they have validation issues (expired, self-signed, etc.).

        Author: Jon LaBelle
        License: MIT
    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-CertificateDetails.ps1

        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-CertificateDetails.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(ParameterSetName = 'ComputerName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('HostName', 'Server', 'Name')]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $ComputerName = 'localhost',

        [Parameter(Mandatory, ParameterSetName = 'Path')]
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

                    $result = @{
                        Certificate = $certificates[0]
                        Chain = $null
                        CertificatePath = $fullPath
                        AdditionalCertificates = @()
                    }

                    if ($certificates.Count -gt 1)
                    {
                        $result.AdditionalCertificates = $certificates[1..($certificates.Count - 1)]
                    }

                    if ($IncludeChain)
                    {
                        try
                        {
                            $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain

                            foreach ($extraCertificate in $result.AdditionalCertificates)
                            {
                                [void]$chain.ChainPolicy.ExtraStore.Add($extraCertificate)
                            }

                            $chain.Build($result.Certificate) | Out-Null
                            $result.Chain = $chain
                        }
                        catch
                        {
                            Write-Verbose "Could not build certificate chain for '$fullPath': $($_.Exception.Message)"
                        }
                    }

                    $results += $result
                }
                catch
                {
                    Write-Error "Failed to load certificate file '$fullPath' - $($_.Exception.Message)"
                }
            }

            return $results
        }

        function Get-CertificateDetailsObject
        {
            param
            (
                [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
                [String]$Computer,
                [Nullable[Int32]]$PortNumber,
                [String]$CertificatePath,
                [System.Security.Cryptography.X509Certificates.X509Chain]$Chain
            )

            $expirationDate = $Certificate.NotAfter
            $daysUntilExpiration = ($expirationDate - (Get-Date)).Days

            # Build the main certificate details object
            $details = [PSCustomObject]@{
                ComputerName = $Computer
                Port = $PortNumber
                Subject = $Certificate.Subject
                Issuer = $Certificate.Issuer
                NotBefore = $Certificate.NotBefore
                NotAfter = $Certificate.NotAfter
                Thumbprint = $Certificate.Thumbprint
                SerialNumber = $Certificate.SerialNumber
                DaysUntilExpiration = $daysUntilExpiration
                IsExpired = $daysUntilExpiration -lt 0
                SignatureAlgorithm = $Certificate.SignatureAlgorithm.FriendlyName
                PublicKeyAlgorithm = $Certificate.PublicKey.Oid.FriendlyName
                KeySize = $Certificate.PublicKey.Key.KeySize
                Version = $Certificate.Version
                HasPrivateKey = $Certificate.HasPrivateKey
                FriendlyName = $Certificate.FriendlyName
                Archived = $Certificate.Archived
            }

            if ($CertificatePath)
            {
                $details | Add-Member -MemberType NoteProperty -Name 'CertificatePath' -Value $CertificatePath
            }

            # Add certificate extensions if requested
            if ($IncludeExtensions)
            {
                $extensions = Get-CertificateExtensions -Certificate $Certificate
                $details | Add-Member -MemberType NoteProperty -Name 'Extensions' -Value $extensions
            }

            # Add certificate chain if requested and available
            if ($IncludeChain -and $Chain)
            {
                $chainInfo = @()
                foreach ($chainElement in $Chain.ChainElements)
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
                $details | Add-Member -MemberType NoteProperty -Name 'ChainStatus' -Value $Chain.ChainStatus
            }

            return $details
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
        if ($PSCmdlet.ParameterSetName -eq 'Path')
        {
            foreach ($certificatePath in $Path)
            {
                Write-Verbose "Processing certificate file path: $certificatePath"

                $certResults = Get-CertificateFromFile -CertificatePath $certificatePath

                foreach ($certResult in $certResults)
                {
                    if ($certResult -and $certResult.Certificate)
                    {
                        Get-CertificateDetailsObject `
                            -Certificate $certResult.Certificate `
                            -Computer $null `
                            -PortNumber $null `
                            -CertificatePath $certResult.CertificatePath `
                            -Chain $certResult.Chain
                    }
                }
            }
        }
        else
        {
            foreach ($computer in $ComputerName)
            {
                Write-Verbose "Processing host: $computer"

                $certResult = Get-CertificateFromHost -HostName $computer -PortNumber $Port -TimeoutMs $Timeout

                if ($certResult -and $certResult.Certificate)
                {
                    Get-CertificateDetailsObject `
                        -Certificate $certResult.Certificate `
                        -Computer $computer `
                        -PortNumber $Port `
                        -CertificatePath $null `
                        -Chain $certResult.Chain
                }
            }
        }
    }

    end
    {
        Write-Verbose 'SSL certificate details retrieval completed'
    }
}
