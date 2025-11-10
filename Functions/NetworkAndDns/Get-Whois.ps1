function Get-Whois
{
    <#
    .SYNOPSIS
        Performs WHOIS lookups for domain names and IP addresses.

    .DESCRIPTION
        Queries WHOIS servers to retrieve registration information for domain names and IP addresses.
        Supports multiple TLDs and provides detailed registration information including registrar,
        creation date, expiration date, nameservers, and contact information.

        Uses direct TCP connections to WHOIS servers for cross-platform compatibility without
        requiring external tools or platform-specific commands.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Domain
        The domain name or IP address to query.
        Accepts pipeline input for bulk WHOIS lookups.
        Examples: 'google.com', 'github.com', '8.8.8.8'

    .PARAMETER Server
        Specify a custom WHOIS server to query.
        If not specified, the function automatically determines the appropriate WHOIS server
        based on the domain TLD.
        Example: 'whois.verisign-grs.com'

    .PARAMETER Port
        The port to connect to on the WHOIS server.
        Default is 43 (standard WHOIS port).

    .PARAMETER Timeout
        Connection timeout in seconds.
        Default is 15 seconds. Valid range: 5-60 seconds.

    .PARAMETER Raw
        Return the raw WHOIS response without parsing.
        Useful for debugging or when you need the complete unprocessed output.

    .EXAMPLE
        PS > Get-Whois -Domain 'google.com'

        Performs a WHOIS lookup for google.com and returns parsed registration information.

    .EXAMPLE
        PS > Get-Whois -Domain 'github.com' -Raw

        Returns the raw WHOIS response for github.com without parsing.

    .EXAMPLE
        PS > @('google.com', 'github.com', 'microsoft.com') | Get-Whois

        Performs WHOIS lookups for multiple domains using pipeline input.

    .EXAMPLE
        PS > Get-Whois -Domain '8.8.8.8'

        Performs a WHOIS lookup for an IP address.

    .EXAMPLE
        PS > Get-Whois -Domain 'example.com' -Server 'whois.verisign-grs.com'

        Queries a specific WHOIS server for domain information.

    .EXAMPLE
        PS > Get-Whois -Domain 'google.co.uk'

        Performs a WHOIS lookup for a country-code TLD domain.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns an object with Domain, Registrar, CreationDate, ExpirationDate, NameServers, and RawResponse properties.
        When -Raw is specified, returns the raw string response.

    .LINK
        https://www.iana.org/whois

    .NOTES
        Author: Jon LaBelle
        Date: November 9, 2025

        WHOIS Server Selection:
        - Automatically selects appropriate server based on TLD
        - Falls back to IANA WHOIS for unknown TLDs
        - Supports referrals to authoritative WHOIS servers

        Common WHOIS Servers:
        - .com/.net: whois.verisign-grs.com
        - .org: whois.pir.org
        - .info: whois.afilias.net
        - IP addresses: whois.arin.net (and regional registries)

        Note: Some domains may be privacy-protected and show limited information.
        Rate limiting may apply for bulk queries.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('Name', 'DomainName', 'IPAddress')]
        [String]$Domain,

        [Parameter()]
        [String]$Server,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [Int32]$Port = 43,

        [Parameter()]
        [ValidateRange(5, 60)]
        [Int32]$Timeout = 15,

        [Parameter()]
        [Switch]$Raw
    )

    begin
    {
        Write-Verbose 'Initializing WHOIS query'

        # Common WHOIS servers for popular TLDs
        $whoisServers = @{
            'com' = 'whois.verisign-grs.com'
            'net' = 'whois.verisign-grs.com'
            'org' = 'whois.pir.org'
            'info' = 'whois.afilias.net'
            'biz' = 'whois.biz'
            'us' = 'whois.nic.us'
            'uk' = 'whois.nic.uk'
            'co.uk' = 'whois.nic.uk'
            'ca' = 'whois.cira.ca'
            'au' = 'whois.auda.org.au'
            'de' = 'whois.denic.de'
            'jp' = 'whois.jprs.jp'
            'fr' = 'whois.afnic.fr'
            'it' = 'whois.nic.it'
            'nl' = 'whois.domain-registry.nl'
            'eu' = 'whois.eu'
            'ru' = 'whois.tcinet.ru'
            'cn' = 'whois.cnnic.cn'
            'br' = 'whois.registro.br'
            'in' = 'whois.registry.in'
            'mx' = 'whois.mx'
            'se' = 'whois.iis.se'
            'no' = 'whois.norid.no'
            'ch' = 'whois.nic.ch'
            'at' = 'whois.nic.at'
            'dk' = 'whois.dk-hostmaster.dk'
            'tv' = 'whois.nic.tv'
            'io' = 'whois.nic.io'
            'co' = 'whois.nic.co'
            'me' = 'whois.nic.me'
            'be' = 'whois.dns.be'
            'nz' = 'whois.srs.net.nz'
            'ai' = 'whois.nic.ai'
            'dev' = 'whois.nic.google'
            'app' = 'whois.nic.google'
        }

        # Default WHOIS server for IP addresses and unknown TLDs
        $defaultWhoisServer = 'whois.iana.org'
    }

    process
    {
        $domainToQuery = $Domain.Trim().ToLower()
        Write-Verbose "Performing WHOIS lookup for: $domainToQuery"

        try
        {
            # Determine WHOIS server if not specified
            if (-not $Server)
            {
                # Check if it's an IP address
                try
                {
                    [void][System.Net.IPAddress]::Parse($domainToQuery)
                    Write-Verbose 'Detected IP address, using ARIN WHOIS server'
                    $whoisServer = 'whois.arin.net'
                }
                catch
                {
                    # Extract TLD from domain
                    $parts = $domainToQuery.Split('.')
                    if ($parts.Count -ge 2)
                    {
                        # Try country-code TLD first (e.g., co.uk)
                        $tld = "$($parts[-2]).$($parts[-1])"
                        if ($whoisServers.ContainsKey($tld))
                        {
                            $whoisServer = $whoisServers[$tld]
                            Write-Verbose "Using WHOIS server for .$tld : $whoisServer"
                        }
                        else
                        {
                            # Try single TLD
                            $tld = $parts[-1]
                            if ($whoisServers.ContainsKey($tld))
                            {
                                $whoisServer = $whoisServers[$tld]
                                Write-Verbose "Using WHOIS server for .$tld : $whoisServer"
                            }
                            else
                            {
                                Write-Verbose "No specific WHOIS server found for .$tld, using IANA"
                                $whoisServer = $defaultWhoisServer
                            }
                        }
                    }
                    else
                    {
                        Write-Verbose 'Invalid domain format, using default WHOIS server'
                        $whoisServer = $defaultWhoisServer
                    }
                }
            }
            else
            {
                $whoisServer = $Server
                Write-Verbose "Using specified WHOIS server: $whoisServer"
            }

            # Connect to WHOIS server
            Write-Verbose "Connecting to $whoisServer on port $Port"

            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connectTask = $tcpClient.ConnectAsync($whoisServer, $Port)
            $timeoutMs = $Timeout * 1000

            if (-not $connectTask.Wait($timeoutMs))
            {
                $tcpClient.Close()
                throw "Connection to WHOIS server '$whoisServer' timed out after $Timeout seconds"
            }

            if (-not $tcpClient.Connected)
            {
                throw "Failed to connect to WHOIS server '$whoisServer'"
            }

            Write-Verbose 'Connected to WHOIS server, sending query'

            # Send query
            $stream = $tcpClient.GetStream()
            $stream.ReadTimeout = $timeoutMs
            $stream.WriteTimeout = $timeoutMs

            $query = "$domainToQuery`r`n"
            $queryBytes = [System.Text.Encoding]::ASCII.GetBytes($query)
            $stream.Write($queryBytes, 0, $queryBytes.Length)
            $stream.Flush()

            Write-Verbose 'Query sent, reading response'

            # Read response
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
            $response = $reader.ReadToEnd()

            # Cleanup
            $reader.Close()
            $stream.Close()
            $tcpClient.Close()

            Write-Verbose "Received response ($($response.Length) bytes)"

            # Check for referral to another WHOIS server
            if ($response -match 'Registrar WHOIS Server:\s*(.+?)(\r|\n)' -or
                $response -match 'whois:\s*(.+?)(\r|\n)' -or
                $response -match 'refer:\s*(.+?)(\r|\n)')
            {
                $referralServer = $matches[1].Trim()
                if ($referralServer -and $referralServer -ne $whoisServer -and -not $Server)
                {
                    Write-Verbose "Following referral to authoritative WHOIS server: $referralServer"
                    # Recursive call to referred server
                    return Get-Whois -Domain $domainToQuery -Server $referralServer -Port $Port -Timeout $Timeout -Raw:$Raw
                }
            }

            # Return raw response if requested
            if ($Raw)
            {
                Write-Output $response
                return
            }

            # Parse response
            Write-Verbose 'Parsing WHOIS response'

            $result = [PSCustomObject]@{
                Domain = $domainToQuery
                WhoisServer = $whoisServer
                Registrar = $null
                CreationDate = $null
                UpdatedDate = $null
                ExpirationDate = $null
                Status = @()
                NameServers = @()
                DNSSEC = $null
                RawResponse = $response
            }

            # Extract registrar
            if ($response -match '(?:Registrar|Organization):\s*(.+?)(\r|\n)')
            {
                $result.Registrar = $matches[1].Trim()
            }

            # Extract dates (various formats)
            if ($response -match 'Creation Date:\s*(.+?)(\r|\n|T)')
            {
                $dateStr = $matches[1].Trim()
                try
                {
                    $result.CreationDate = [DateTime]::Parse($dateStr)
                }
                catch
                {
                    Write-Verbose "Could not parse creation date: $dateStr"
                }
            }

            if ($response -match 'Updated Date:\s*(.+?)(\r|\n|T)')
            {
                $dateStr = $matches[1].Trim()
                try
                {
                    $result.UpdatedDate = [DateTime]::Parse($dateStr)
                }
                catch
                {
                    Write-Verbose "Could not parse updated date: $dateStr"
                }
            }

            if ($response -match 'Registry Expiry Date:\s*(.+?)(\r|\n|T)' -or
                $response -match 'Expiration Date:\s*(.+?)(\r|\n|T)')
            {
                $dateStr = $matches[1].Trim()
                try
                {
                    $result.ExpirationDate = [DateTime]::Parse($dateStr)
                }
                catch
                {
                    Write-Verbose "Could not parse expiration date: $dateStr"
                }
            }

            # Extract domain status
            $statusMatches = [regex]::Matches($response, 'Domain Status:\s*(.+?)(\r|\n)')
            foreach ($match in $statusMatches)
            {
                $status = $match.Groups[1].Value.Trim()
                if ($status -and $status -notin $result.Status)
                {
                    $result.Status += $status
                }
            }

            # Extract nameservers
            $nsMatches = [regex]::Matches($response, 'Name Server:\s*(.+?)(\r|\n)')
            foreach ($match in $nsMatches)
            {
                $ns = $match.Groups[1].Value.Trim().ToLower()
                if ($ns -and $ns -notin $result.NameServers)
                {
                    $result.NameServers += $ns
                }
            }

            # Extract DNSSEC
            if ($response -match 'DNSSEC:\s*(.+?)(\r|\n)')
            {
                $result.DNSSEC = $matches[1].Trim()
            }

            Write-Output $result
        }
        catch [System.Net.Sockets.SocketException]
        {
            Write-Error "Network error during WHOIS lookup for '$domainToQuery': $($_.Exception.Message)"
        }
        catch
        {
            Write-Error "WHOIS lookup failed for '$domainToQuery': $($_.Exception.Message)"
        }
    }

    end
    {
        Write-Verbose 'WHOIS query completed'
    }
}
