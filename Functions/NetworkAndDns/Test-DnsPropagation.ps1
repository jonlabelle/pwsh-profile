function Test-DnsPropagation
{
    <#
    .SYNOPSIS
        Checks DNS propagation across multiple public DNS servers.

    .DESCRIPTION
        Queries a domain name against multiple well-known public DNS resolvers simultaneously
        and compares the results to determine if DNS changes have fully propagated.

        Uses DNS-over-HTTPS (DoH) JSON API for providers that support it (Cloudflare,
        Google, Control D), and falls back to direct DNS over UDP for all other providers
        (Quad9, OpenDNS, CleanBrowsing, AdGuard).

        This function leverages Get-PublicDnsServers for its resolver list.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Name
        The domain name to check propagation for.

    .PARAMETER Type
        The DNS record type to query. Default is 'A'.
        Valid values: A, AAAA, MX, TXT, NS, CNAME, SOA.

    .PARAMETER Timeout
        Timeout in seconds for each DNS-over-HTTPS query.
        Default is 5 seconds. Valid range: 1-30.

    .PARAMETER ExpectedValue
        If specified, each server's response is compared against this expected value.
        The Propagated column indicates whether the expected value was found.

    .EXAMPLE
        PS > Test-DnsPropagation -Name 'bing.com'

        Server         IPv4Primary      Status    Records               Propagated
        ------         -----------      ------    -------               ----------
        Cloudflare     1.1.1.1          Resolved  204.79.197.200, ...   True
        Google         8.8.8.8          Resolved  204.79.197.200, ...   True
        Quad9          9.9.9.9          Resolved  204.79.197.200, ...   True
        OpenDNS        208.67.222.222   Resolved  204.79.197.200, ...   True
        CleanBrowsing  185.228.168.9    Resolved  204.79.197.200, ...   True
        AdGuard DNS    94.140.14.14     Resolved  204.79.197.200, ...   True
        Control D      76.76.2.0        Resolved  204.79.197.200, ...   True

        Checks DNS propagation for bing.com across all public DNS servers.

    .EXAMPLE
        PS > Test-DnsPropagation -Name 'bing.com' -Type MX

        Checks MX record propagation across all public DNS servers.

    .EXAMPLE
        PS > Test-DnsPropagation -Name 'example.com' -ExpectedValue '93.184.216.34'

        Checks if the expected A record has propagated to all resolvers.

    .OUTPUTS
        PSCustomObject
        Returns objects with Server, IPv4Primary, Status, Records, and Propagated properties.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Test-DnsPropagation.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Test-DnsPropagation.ps1
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Name,

        [Parameter()]
        [ValidateSet('A', 'AAAA', 'MX', 'TXT', 'NS', 'CNAME', 'SOA')]
        [String]
        $Type = 'A',

        [Parameter()]
        [ValidateRange(1, 30)]
        [Int32]
        $Timeout = 5,

        [Parameter()]
        [String]
        $ExpectedValue
    )

    begin
    {
        Write-Verbose 'Starting DNS propagation check'

        # Helper function to load dependencies on demand
        function Import-DependencyIfNeeded
        {
            param(
                [Parameter(Mandatory)]
                [String]$FunctionName,

                [Parameter(Mandatory)]
                [String]$RelativePath
            )

            if (-not (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue))
            {
                Write-Verbose "$FunctionName is required - attempting to load it"

                $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath $RelativePath
                $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)

                if (Test-Path -Path $dependencyPath -PathType Leaf)
                {
                    try
                    {
                        . $dependencyPath
                        Write-Verbose "Loaded $FunctionName from: $dependencyPath"
                    }
                    catch
                    {
                        throw "Failed to load required dependency '$FunctionName' from '$dependencyPath': $($_.Exception.Message)"
                    }
                }
                else
                {
                    throw "Required function '$FunctionName' could not be found. Expected location: $dependencyPath"
                }
            }
            else
            {
                Write-Verbose "$FunctionName is already loaded"
            }
        }

        Import-DependencyIfNeeded -FunctionName 'Get-PublicDnsServers' -RelativePath 'Get-PublicDnsServers.ps1'

        # DNS record type numeric codes
        $typeCode = @{
            'A' = 1
            'AAAA' = 28
            'MX' = 15
            'TXT' = 16
            'NS' = 2
            'CNAME' = 5
            'SOA' = 6
        }

        # Helper: Read a DNS domain name from a wire-format byte array, handling compression pointers
        function Read-DnsNameFromPacket
        {
            param(
                [byte[]]$Packet,
                [int]$Offset
            )

            $labels = @()
            $pos = $Offset
            $maxJumps = 20

            while ($pos -lt $Packet.Length -and $maxJumps -gt 0)
            {
                $len = [int]$Packet[$pos]

                if ($len -eq 0)
                {
                    break
                }

                if (($len -band 0xC0) -eq 0xC0)
                {
                    # Compression pointer
                    $ptr = (($len -band 0x3F) -shl 8) -bor [int]$Packet[$pos + 1]
                    $pos = $ptr
                    $maxJumps--
                    continue
                }

                $pos++
                if (($pos + $len) -le $Packet.Length)
                {
                    $labels += [System.Text.Encoding]::ASCII.GetString($Packet, $pos, $len)
                }
                $pos += $len
            }

            return ($labels -join '.')
        }

        # Helper: Send a DNS query via UDP to a specific server and parse the response
        function Invoke-DnsUdpQuery
        {
            param(
                [String]$ServerIP,
                [String]$DomainName,
                [Int32]$RecordTypeCode,
                [String]$RecordTypeName,
                [Int32]$TimeoutMs
            )

            $udpClient = $null

            try
            {
                # Build DNS query packet
                $queryId = Get-Random -Minimum 1 -Maximum 65535
                $packet = [System.Collections.Generic.List[byte]]::new()

                # Header (12 bytes)
                $packet.Add([byte](($queryId -shr 8) -band 0xFF))
                $packet.Add([byte]($queryId -band 0xFF))
                $packet.Add([byte]0x01)  # Flags high: RD=1 (recursion desired)
                $packet.Add([byte]0x00)  # Flags low
                $packet.Add([byte]0x00)  # QDCOUNT high
                $packet.Add([byte]0x01)  # QDCOUNT low = 1
                $packet.Add([byte]0x00)  # ANCOUNT high
                $packet.Add([byte]0x00)  # ANCOUNT low = 0
                $packet.Add([byte]0x00)  # NSCOUNT high
                $packet.Add([byte]0x00)  # NSCOUNT low = 0
                $packet.Add([byte]0x00)  # ARCOUNT high
                $packet.Add([byte]0x00)  # ARCOUNT low = 0

                # Question section: QNAME (domain name as labels)
                foreach ($label in $DomainName.Split('.'))
                {
                    $labelBytes = [System.Text.Encoding]::ASCII.GetBytes($label)
                    $packet.Add([byte]$labelBytes.Length)
                    foreach ($b in $labelBytes)
                    {
                        $packet.Add($b)
                    }
                }
                $packet.Add([byte]0x00)  # Root label terminator

                # QTYPE
                $packet.Add([byte](($RecordTypeCode -shr 8) -band 0xFF))
                $packet.Add([byte]($RecordTypeCode -band 0xFF))
                # QCLASS = IN (1)
                $packet.Add([byte]0x00)
                $packet.Add([byte]0x01)

                # Send via UDP
                $udpClient = New-Object System.Net.Sockets.UdpClient
                $udpClient.Client.ReceiveTimeout = $TimeoutMs
                $udpClient.Client.SendTimeout = $TimeoutMs

                $endpoint = New-Object System.Net.IPEndPoint(
                    [System.Net.IPAddress]::Parse($ServerIP), 53
                )
                $queryBytes = $packet.ToArray()
                [void]$udpClient.Send($queryBytes, $queryBytes.Length, $endpoint)

                # Receive response
                $remoteEP = New-Object System.Net.IPEndPoint(
                    [System.Net.IPAddress]::Any, 0
                )
                $response = $udpClient.Receive([ref]$remoteEP)

                # Validate minimum response length (header = 12 bytes)
                if ($response.Length -lt 12)
                {
                    return @()
                }

                # Check RCODE (bits 0-3 of byte 3)
                $rcode = $response[3] -band 0x0F
                if ($rcode -ne 0)
                {
                    return @()
                }

                # Read ANCOUNT from header
                $anCount = ([int]$response[6] -shl 8) -bor [int]$response[7]
                if ($anCount -eq 0)
                {
                    return @()
                }

                # Skip header (12 bytes), then skip question section
                $offset = 12

                # Skip QNAME
                while ($offset -lt $response.Length -and $response[$offset] -ne 0)
                {
                    if (($response[$offset] -band 0xC0) -eq 0xC0)
                    {
                        $offset += 2
                        break
                    }
                    $offset += $response[$offset] + 1
                }
                if ($offset -lt $response.Length -and $response[$offset] -eq 0)
                {
                    $offset++
                }
                $offset += 4  # Skip QTYPE (2) + QCLASS (2)

                # Parse answer records
                $records = @()
                for ($i = 0; $i -lt $anCount -and ($offset + 10) -lt $response.Length; $i++)
                {
                    # Skip NAME field (may be compressed)
                    if (($response[$offset] -band 0xC0) -eq 0xC0)
                    {
                        $offset += 2
                    }
                    else
                    {
                        while ($offset -lt $response.Length -and $response[$offset] -ne 0)
                        {
                            $offset += $response[$offset] + 1
                        }
                        $offset++  # Skip null terminator
                    }

                    if (($offset + 10) -gt $response.Length) { break }

                    # Read TYPE (2), CLASS (2), TTL (4), RDLENGTH (2)
                    $rType = ([int]$response[$offset] -shl 8) -bor [int]$response[$offset + 1]
                    $offset += 2
                    $offset += 2  # CLASS
                    $offset += 4  # TTL
                    $rdLength = ([int]$response[$offset] -shl 8) -bor [int]$response[$offset + 1]
                    $offset += 2

                    $rdataStart = $offset

                    if (($offset + $rdLength) -gt $response.Length) { break }

                    # Parse RDATA based on record type
                    $data = $null
                    switch ($rType)
                    {
                        1
                        {
                            # A record: 4 bytes -> IPv4 address
                            if ($rdLength -eq 4)
                            {
                                $data = "$($response[$offset]).$($response[$offset + 1]).$($response[$offset + 2]).$($response[$offset + 3])"
                            }
                        }
                        28
                        {
                            # AAAA record: 16 bytes -> IPv6 address
                            if ($rdLength -eq 16)
                            {
                                $ipv6Bytes = $response[$offset..($offset + 15)]
                                $addr = New-Object System.Net.IPAddress(, [byte[]]$ipv6Bytes)
                                $data = $addr.ToString()
                            }
                        }
                        5
                        {
                            # CNAME record: domain name
                            $data = Read-DnsNameFromPacket -Packet $response -Offset $offset
                        }
                        2
                        {
                            # NS record: domain name
                            $data = Read-DnsNameFromPacket -Packet $response -Offset $offset
                        }
                        15
                        {
                            # MX record: 2 bytes preference + domain name
                            $preference = ([int]$response[$offset] -shl 8) -bor [int]$response[$offset + 1]
                            $exchange = Read-DnsNameFromPacket -Packet $response -Offset ($offset + 2)
                            $data = "$preference $exchange"
                        }
                        16
                        {
                            # TXT record: one or more length-prefixed strings
                            $txtParts = @()
                            $pos = $offset
                            while ($pos -lt ($offset + $rdLength))
                            {
                                $txtLen = [int]$response[$pos]
                                $pos++
                                if ($txtLen -gt 0 -and ($pos + $txtLen) -le $response.Length)
                                {
                                    $txtParts += [System.Text.Encoding]::UTF8.GetString($response, $pos, $txtLen)
                                }
                                $pos += $txtLen
                            }
                            $data = $txtParts -join ''
                        }
                        6
                        {
                            # SOA record: primary nameserver
                            $data = Read-DnsNameFromPacket -Packet $response -Offset $offset
                        }
                    }

                    if ($data)
                    {
                        $records += $data
                    }

                    $offset = $rdataStart + $rdLength
                }

                return $records
            }
            finally
            {
                if ($udpClient)
                {
                    $udpClient.Close()
                }
            }
        }

        # Helper: Query a DoH JSON API endpoint
        function Invoke-DohJsonQuery
        {
            param(
                [String]$DoHJsonUrl,
                [String]$DomainName,
                [Int32]$RecordTypeCode,
                [String]$RecordTypeName,
                [Int32]$TimeoutSeconds
            )

            $handler = $null
            $client = $null

            try
            {
                $url = "$DoHJsonUrl`?name=$([uri]::EscapeDataString($DomainName))&type=$RecordTypeCode"

                $handler = New-Object System.Net.Http.HttpClientHandler
                $handler.UseProxy = $false
                $client = New-Object System.Net.Http.HttpClient($handler)
                $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
                $client.DefaultRequestHeaders.Accept.Clear()
                $client.DefaultRequestHeaders.Accept.Add(
                    [System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/dns-json')
                )

                $response = $client.GetStringAsync($url).GetAwaiter().GetResult()
                $dnsResult = $response | ConvertFrom-Json

                if ($dnsResult.Answer -and $dnsResult.Answer.Count -gt 0)
                {
                    $records = @($dnsResult.Answer | ForEach-Object {
                            $data = $_.data
                            # Clean up TXT record quoting
                            if ($RecordTypeName -eq 'TXT' -and $data -match '^".*"$')
                            {
                                $data = $data.Trim('"')
                            }
                            $data
                        })
                    return $records
                }

                return @()
            }
            finally
            {
                if ($client) { $client.Dispose() }
                if ($handler) { $handler.Dispose() }
            }
        }

        # Helper: Query a DoH endpoint using RFC 8484 wire format (POST with application/dns-message)
        # Used as a fallback for servers that don't support JSON DoH and refuse plain UDP DNS
        function Invoke-DohWireQuery
        {
            param(
                [String]$DoHUrl,
                [String]$DomainName,
                [Int32]$RecordTypeCode,
                [String]$RecordTypeName,
                [Int32]$TimeoutSeconds
            )

            $handler = $null
            $client = $null

            try
            {
                # Build DNS wire-format query packet (same format as UDP)
                $queryId = Get-Random -Minimum 1 -Maximum 65535
                $packet = [System.Collections.Generic.List[byte]]::new()

                # Header
                $packet.Add([byte](($queryId -shr 8) -band 0xFF))
                $packet.Add([byte]($queryId -band 0xFF))
                $packet.Add([byte]0x01)
                $packet.Add([byte]0x00)
                $packet.Add([byte]0x00)
                $packet.Add([byte]0x01)
                $packet.Add([byte]0x00)
                $packet.Add([byte]0x00)
                $packet.Add([byte]0x00)
                $packet.Add([byte]0x00)
                $packet.Add([byte]0x00)
                $packet.Add([byte]0x00)

                # Question section
                foreach ($label in $DomainName.Split('.'))
                {
                    $labelBytes = [System.Text.Encoding]::ASCII.GetBytes($label)
                    $packet.Add([byte]$labelBytes.Length)
                    foreach ($b in $labelBytes) { $packet.Add($b) }
                }
                $packet.Add([byte]0x00)
                $packet.Add([byte](($RecordTypeCode -shr 8) -band 0xFF))
                $packet.Add([byte]($RecordTypeCode -band 0xFF))
                $packet.Add([byte]0x00)
                $packet.Add([byte]0x01)

                $queryBytes = $packet.ToArray()

                # Send via HTTPS POST with application/dns-message content type
                $handler = New-Object System.Net.Http.HttpClientHandler
                $handler.UseProxy = $false
                $client = New-Object System.Net.Http.HttpClient($handler)
                $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

                $content = New-Object System.Net.Http.ByteArrayContent(, $queryBytes)
                $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/dns-message')

                $httpResponse = $client.PostAsync($DoHUrl, $content).GetAwaiter().GetResult()

                if (-not $httpResponse.IsSuccessStatusCode)
                {
                    return @()
                }

                $response = $httpResponse.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()

                # Parse the wire-format response (same parsing as UDP response)
                if ($response.Length -lt 12) { return @() }

                $rcode = $response[3] -band 0x0F
                if ($rcode -ne 0) { return @() }

                $anCount = ([int]$response[6] -shl 8) -bor [int]$response[7]
                if ($anCount -eq 0) { return @() }

                # Skip header and question section
                $offset = 12
                while ($offset -lt $response.Length -and $response[$offset] -ne 0)
                {
                    if (($response[$offset] -band 0xC0) -eq 0xC0) { $offset += 2; break }
                    $offset += $response[$offset] + 1
                }
                if ($offset -lt $response.Length -and $response[$offset] -eq 0) { $offset++ }
                $offset += 4

                # Parse answer records
                $records = @()
                for ($i = 0; $i -lt $anCount -and ($offset + 10) -lt $response.Length; $i++)
                {
                    if (($response[$offset] -band 0xC0) -eq 0xC0) { $offset += 2 }
                    else
                    {
                        while ($offset -lt $response.Length -and $response[$offset] -ne 0)
                        {
                            $offset += $response[$offset] + 1
                        }
                        $offset++
                    }

                    if (($offset + 10) -gt $response.Length) { break }

                    $rType = ([int]$response[$offset] -shl 8) -bor [int]$response[$offset + 1]
                    $offset += 2
                    $offset += 2  # CLASS
                    $offset += 4  # TTL
                    $rdLength = ([int]$response[$offset] -shl 8) -bor [int]$response[$offset + 1]
                    $offset += 2
                    $rdataStart = $offset

                    if (($offset + $rdLength) -gt $response.Length) { break }

                    $data = $null
                    switch ($rType)
                    {
                        1
                        {
                            if ($rdLength -eq 4)
                            {
                                $data = "$($response[$offset]).$($response[$offset + 1]).$($response[$offset + 2]).$($response[$offset + 3])"
                            }
                        }
                        28
                        {
                            if ($rdLength -eq 16)
                            {
                                $ipv6Bytes = $response[$offset..($offset + 15)]
                                $addr = New-Object System.Net.IPAddress(, [byte[]]$ipv6Bytes)
                                $data = $addr.ToString()
                            }
                        }
                        5 { $data = Read-DnsNameFromPacket -Packet $response -Offset $offset }
                        2 { $data = Read-DnsNameFromPacket -Packet $response -Offset $offset }
                        15
                        {
                            $preference = ([int]$response[$offset] -shl 8) -bor [int]$response[$offset + 1]
                            $exchange = Read-DnsNameFromPacket -Packet $response -Offset ($offset + 2)
                            $data = "$preference $exchange"
                        }
                        16
                        {
                            $txtParts = @()
                            $pos = $offset
                            while ($pos -lt ($offset + $rdLength))
                            {
                                $txtLen = [int]$response[$pos]
                                $pos++
                                if ($txtLen -gt 0 -and ($pos + $txtLen) -le $response.Length)
                                {
                                    $txtParts += [System.Text.Encoding]::UTF8.GetString($response, $pos, $txtLen)
                                }
                                $pos += $txtLen
                            }
                            $data = $txtParts -join ''
                        }
                        6 { $data = Read-DnsNameFromPacket -Packet $response -Offset $offset }
                    }

                    if ($data) { $records += $data }
                    $offset = $rdataStart + $rdLength
                }

                return $records
            }
            finally
            {
                if ($client) { $client.Dispose() }
                if ($handler) { $handler.Dispose() }
            }
        }
    }

    process
    {
        Write-Verbose "Checking DNS propagation for '$Name' (type: $Type)"

        # Get all servers that can be queried (have DoH JSON URL or IPv4 address for UDP)
        $servers = Get-PublicDnsServers | Where-Object { $_.DoHJsonUrl -or $_.IPv4Primary }

        $results = @()
        $recordTypeCode = $typeCode[$Type]

        foreach ($server in $servers)
        {
            $status = 'Error'
            $records = @()

            if ($server.DoHJsonUrl)
            {
                # Query via DoH JSON API
                Write-Verbose "Querying $($server.Name) via DoH JSON ($($server.DoHJsonUrl))"

                try
                {
                    $records = @(Invoke-DohJsonQuery `
                            -DoHJsonUrl $server.DoHJsonUrl `
                            -DomainName $Name `
                            -RecordTypeCode $recordTypeCode `
                            -RecordTypeName $Type `
                            -TimeoutSeconds $Timeout)

                    $status = if ($records.Count -gt 0) { 'Resolved' } else { 'NoRecords' }
                }
                catch
                {
                    Write-Verbose "DoH JSON query failed for $($server.Name): $($_.Exception.Message)"
                    $status = 'Error'
                }
            }
            else
            {
                # Query via direct DNS over UDP, with DoH wire-format fallback
                Write-Verbose "Querying $($server.Name) via UDP DNS ($($server.IPv4Primary):53)"

                try
                {
                    $records = @(Invoke-DnsUdpQuery `
                            -ServerIP $server.IPv4Primary `
                            -DomainName $Name `
                            -RecordTypeCode $recordTypeCode `
                            -RecordTypeName $Type `
                            -TimeoutMs ($Timeout * 1000))

                    $status = if ($records.Count -gt 0) { 'Resolved' } else { 'NoRecords' }
                }
                catch
                {
                    Write-Verbose "UDP DNS query failed for $($server.Name): $($_.Exception.Message)"
                    $status = 'Error'
                }

                # If UDP returned no results or failed and server has a DoH URL,
                # retry using DoH wire format (RFC 8484) for servers that
                # refuse plain UDP DNS but have a DoH endpoint
                if ($status -ne 'Resolved' -and $server.DoHUrl)
                {
                    Write-Verbose "Retrying $($server.Name) via DoH wire format ($($server.DoHUrl))"

                    try
                    {
                        $records = @(Invoke-DohWireQuery `
                                -DoHUrl $server.DoHUrl `
                                -DomainName $Name `
                                -RecordTypeCode $recordTypeCode `
                                -RecordTypeName $Type `
                                -TimeoutSeconds $Timeout)

                        $status = if ($records.Count -gt 0) { 'Resolved' } else { 'NoRecords' }
                    }
                    catch
                    {
                        Write-Verbose "DoH wire query also failed for $($server.Name): $($_.Exception.Message)"
                        $status = 'Error'
                    }
                }
            }

            # Determine propagation status
            $propagated = $false
            if ($status -eq 'Resolved' -and $records.Count -gt 0)
            {
                if ($ExpectedValue)
                {
                    $propagated = $records -contains $ExpectedValue
                }
                else
                {
                    $propagated = $true
                }
            }

            $recordsStr = if ($records.Count -gt 0) { $records -join ', ' } else { '' }

            $results += [PSCustomObject]@{
                Server = $server.Name
                IPv4Primary = $server.IPv4Primary
                Status = $status
                Records = $recordsStr
                Propagated = $propagated
            }
        }

        $results

        # Summary
        $resolvedCount = @($results | Where-Object { $_.Status -eq 'Resolved' }).Count
        $propagatedCount = @($results | Where-Object { $_.Propagated -eq $true }).Count
        $totalCount = @($results).Count
        Write-Verbose "Propagation summary: $propagatedCount/$totalCount servers propagated ($resolvedCount resolved)"
    }

    end
    {
        Write-Verbose 'DNS propagation check completed'
    }
}
