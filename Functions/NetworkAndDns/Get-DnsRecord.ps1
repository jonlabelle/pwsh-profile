function Get-DnsRecord
{
    <#
    .SYNOPSIS
        Retrieves DNS records for a specified domain name.

    .DESCRIPTION
        Queries DNS records for a domain name supporting all common record types (A, AAAA, MX, TXT, NS, CNAME, SOA, SRV, PTR, CAA).
        This function provides cross-platform DNS resolution using DNS-over-HTTPS (DoH) APIs for comprehensive record type support,
        with fallback to native .NET DNS methods for basic A/AAAA queries.

        Uses Cloudflare's DNS-over-HTTPS API (1.1.1.1) by default for maximum compatibility and privacy.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Name
        The domain name to query for DNS records.
        Accepts pipeline input for querying multiple domains.

    .PARAMETER Type
        The DNS record type to query.
        Valid values: A, AAAA, MX, TXT, NS, CNAME, SOA, SRV, PTR, CAA, ANY
        Default is 'A'.

    .PARAMETER Server
        The DNS server to use for queries. Supports standard DNS servers and DNS-over-HTTPS endpoints.
        Default is 'cloudflare' which uses Cloudflare's 1.1.1.1 DoH service.
        Other options: 'google' (8.8.8.8), 'quad9' (9.9.9.9), or specify a custom DoH URL.

    .PARAMETER UseDNS
        Use native DNS resolution instead of DNS-over-HTTPS.
        Note: Native DNS only supports A and AAAA record types reliably across platforms.

    .PARAMETER Timeout
        Request timeout in seconds for DNS-over-HTTPS queries.
        Default is 10 seconds. Valid range: 1-60 seconds.

    .EXAMPLE
        PS > Get-DnsRecord -Name 'google.com'

        Retrieves A records for google.com using Cloudflare DoH.

    .EXAMPLE
        PS > Get-DnsRecord -Name 'google.com' -Type MX

        Retrieves MX (mail exchange) records for google.com.

    .EXAMPLE
        PS > Get-DnsRecord -Name 'google.com' -Type TXT

        Retrieves TXT records (often used for SPF, DKIM, domain verification).

    .EXAMPLE
        PS > @('google.com', 'github.com', 'microsoft.com') | Get-DnsRecord -Type A

        Retrieves A records for multiple domains using pipeline input.

    .EXAMPLE
        PS > Get-DnsRecord -Name 'google.com' -Type AAAA -Server google

        Retrieves IPv6 (AAAA) records using Google's DNS-over-HTTPS service.

    .EXAMPLE
        PS > Get-DnsRecord -Name '_dmarc.google.com' -Type TXT

        Retrieves DMARC policy TXT record.

    .EXAMPLE
        PS > Get-DnsRecord -Name 'google.com' -Type NS

        Retrieves nameserver (NS) records for google.com.

    .EXAMPLE
        PS > Get-DnsRecord -Name 'google.com' -Type SOA

        Retrieves Start of Authority (SOA) record.

    .EXAMPLE
        PS > Get-DnsRecord -Name '_ldap._tcp.dc._msdcs.example.com' -Type SRV

        Retrieves SRV (service) records.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns objects with Name, Type, TTL, and Data properties for each DNS record found.

    .LINK
        https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/

    .LINK
        https://developers.google.com/speed/public-dns/docs/doh

    .NOTES
        Author: Jon LaBelle
        Date: November 9, 2025

        Dependencies:
        - Set-TlsSecurityProtocol (for HTTPS/TLS 1.2+ support)

        DNS-over-HTTPS Providers:
        - Cloudflare: https://cloudflare-dns.com/dns-query
        - Google: https://dns.google/resolve
        - Quad9: https://dns.quad9.net/dns-query

        Note: This function requires internet connectivity to reach DoH providers.
        For air-gapped environments, use -UseDNS flag with limited record type support.
    #>
    [CmdletBinding(DefaultParameterSetName = 'DoH')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('Domain', 'HostName')]
        [String]$Name,

        [Parameter(Position = 1)]
        [ValidateSet('A', 'AAAA', 'MX', 'TXT', 'NS', 'CNAME', 'SOA', 'SRV', 'PTR', 'CAA', 'ANY')]
        [String]$Type = 'A',

        [Parameter(ParameterSetName = 'DoH')]
        [ValidateSet('cloudflare', 'google', 'quad9')]
        [String]$Server = 'cloudflare',

        [Parameter(ParameterSetName = 'Native')]
        [Switch]$UseDNS,

        [Parameter()]
        [ValidateRange(1, 60)]
        [Int32]$Timeout = 10
    )

    begin
    {
        Write-Verbose 'Initializing DNS query'

        # Ensure TLS 1.2+ is enabled for HTTPS connections
        Set-TlsSecurityProtocol -MinimumVersion Tls12

        # DNS-over-HTTPS endpoints
        $dohEndpoints = @{
            cloudflare = 'https://cloudflare-dns.com/dns-query'
            google = 'https://dns.google/resolve'
            quad9 = 'https://dns.quad9.net/dns-query'
        }

        # DNS record type numeric codes (for DoH API)
        $recordTypes = @{
            A = 1
            NS = 2
            CNAME = 5
            SOA = 6
            PTR = 12
            MX = 15
            TXT = 16
            AAAA = 28
            SRV = 33
            CAA = 257
            ANY = 255
        }
    }

    process
    {
        Write-Verbose "Querying DNS records for '$Name' (Type: $Type)"

        try
        {
            if ($UseDNS)
            {
                # Use native .NET DNS resolution (limited to A/AAAA)
                Write-Verbose 'Using native DNS resolution'

                if ($Type -notin @('A', 'AAAA'))
                {
                    Write-Warning "Native DNS resolution only supports A and AAAA records. Use DNS-over-HTTPS (default) for $Type records."
                    return
                }

                $addresses = [System.Net.Dns]::GetHostAddresses($Name)

                if ($Type -eq 'A')
                {
                    $addresses = $addresses | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
                }
                elseif ($Type -eq 'AAAA')
                {
                    $addresses = $addresses | Where-Object { $_.AddressFamily -eq 'InterNetworkV6' }
                }

                foreach ($addr in $addresses)
                {
                    [PSCustomObject]@{
                        Name = $Name
                        Type = $Type
                        TTL = $null
                        Data = $addr.ToString()
                    }
                }
            }
            else
            {
                # Use DNS-over-HTTPS
                $dohUrl = $dohEndpoints[$Server]
                Write-Verbose "Using DNS-over-HTTPS: $dohUrl"

                # Prepare HTTP client
                $httpClient = [System.Net.Http.HttpClient]::new()
                $httpClient.Timeout = [TimeSpan]::FromSeconds($Timeout)
                $httpClient.DefaultRequestHeaders.Accept.Add([System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/dns-json'))

                # Build query URL
                $recordTypeCode = $recordTypes[$Type]
                $queryUrl = "${dohUrl}?name=${Name}&type=${recordTypeCode}"
                Write-Verbose "Query URL: $queryUrl"

                # Send request
                $response = $httpClient.GetAsync($queryUrl).GetAwaiter().GetResult()

                if ($response.IsSuccessStatusCode)
                {
                    $jsonContent = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    $dnsResponse = $jsonContent | ConvertFrom-Json

                    Write-Verbose "DNS query status: $($dnsResponse.Status)"

                    # Status codes: 0=NOERROR, 2=SERVFAIL, 3=NXDOMAIN
                    if ($dnsResponse.Status -eq 0 -and $dnsResponse.Answer)
                    {
                        foreach ($record in $dnsResponse.Answer)
                        {
                            # Parse the data field based on record type
                            $recordData = switch ($Type)
                            {
                                'MX'
                                {
                                    # MX records have priority and exchange
                                    "$($record.data)"
                                }
                                'SRV'
                                {
                                    # SRV records have priority, weight, port, target
                                    "$($record.data)"
                                }
                                'SOA'
                                {
                                    # SOA records have multiple fields
                                    "$($record.data)"
                                }
                                'TXT'
                                {
                                    # TXT records may need quotes removed
                                    $record.data -replace '^"(.*)"$', '$1'
                                }
                                default
                                {
                                    $record.data
                                }
                            }

                            [PSCustomObject]@{
                                Name = $record.name
                                Type = switch ($record.type)
                                {
                                    1 { 'A' }
                                    2 { 'NS' }
                                    5 { 'CNAME' }
                                    6 { 'SOA' }
                                    12 { 'PTR' }
                                    15 { 'MX' }
                                    16 { 'TXT' }
                                    28 { 'AAAA' }
                                    33 { 'SRV' }
                                    257 { 'CAA' }
                                    default { "TYPE$($record.type)" }
                                }
                                TTL = $record.TTL
                                Data = $recordData
                            }
                        }
                    }
                    elseif ($dnsResponse.Status -eq 3)
                    {
                        Write-Verbose "Domain not found (NXDOMAIN): $Name"
                        Write-Warning "DNS query returned NXDOMAIN: '$Name' does not exist"
                    }
                    elseif ($dnsResponse.Status -eq 2)
                    {
                        Write-Verbose "Server failure (SERVFAIL) for: $Name"
                        Write-Warning "DNS query returned SERVFAIL for '$Name'"
                    }
                    else
                    {
                        Write-Verbose "No records found for $Name (Type: $Type)"
                        if ($dnsResponse.Status -eq 0)
                        {
                            Write-Warning "No $Type records found for '$Name'"
                        }
                    }
                }
                else
                {
                    Write-Error "DNS-over-HTTPS request failed with status code: $($response.StatusCode)"
                }

                $response.Dispose()
                $httpClient.Dispose()
            }
        }
        catch [System.Net.Sockets.SocketException]
        {
            Write-Verbose "Socket exception: $($_.Exception.Message)"
            Write-Error "DNS resolution failed for '$Name': $($_.Exception.Message)"
        }
        catch [System.Net.Http.HttpRequestException]
        {
            Write-Verbose "HTTP request exception: $($_.Exception.Message)"
            Write-Error "DNS-over-HTTPS request failed for '$Name': $($_.Exception.Message)"
        }
        catch
        {
            Write-Verbose "Unexpected error: $($_.Exception.Message)"
            Write-Error "DNS query error for '$Name': $($_.Exception.Message)"
        }
    }

    end
    {
        Write-Verbose 'DNS query completed'
    }
}
