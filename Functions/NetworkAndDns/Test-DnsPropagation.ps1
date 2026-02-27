function Test-DnsPropagation
{
    <#
    .SYNOPSIS
        Checks DNS propagation across multiple public DNS servers.

    .DESCRIPTION
        Queries a domain name against multiple well-known public DNS resolvers simultaneously
        and compares the results to determine if DNS changes have fully propagated. Uses
        DNS-over-HTTPS (DoH) for cross-platform compatibility and consistent results.

        This function leverages Get-PublicDnsServers for its resolver list and uses the
        same DoH approach as Get-DnsRecord.

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
        Mullvad        194.242.2.2      Resolved  204.79.197.200, ...   True
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

        # DNS record type numeric codes for DoH queries
        $typeCode = @{
            'A' = 1
            'AAAA' = 28
            'MX' = 15
            'TXT' = 16
            'NS' = 2
            'CNAME' = 5
            'SOA' = 6
        }
    }

    process
    {
        Write-Verbose "Checking DNS propagation for '$Name' (type: $Type)"

        # Get servers that have DoH URLs
        $servers = Get-PublicDnsServers | Where-Object { $_.DoHUrl }

        $results = @()

        foreach ($server in $servers)
        {
            Write-Verbose "Querying $($server.Name) ($($server.DoHUrl))"

            $status = 'Error'
            $records = @()

            try
            {
                $dohUrl = "$($server.DoHUrl)?name=$([uri]::EscapeDataString($Name))&type=$($typeCode[$Type])"

                # Use HttpClient for DoH query
                $handler = New-Object System.Net.Http.HttpClientHandler
                $handler.UseProxy = $false
                $client = New-Object System.Net.Http.HttpClient($handler)
                $client.Timeout = [TimeSpan]::FromSeconds($Timeout)
                $client.DefaultRequestHeaders.Accept.Clear()
                $client.DefaultRequestHeaders.Accept.Add(
                    [System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/dns-json')
                )

                try
                {
                    $response = $client.GetStringAsync($dohUrl).GetAwaiter().GetResult()
                    $dnsResult = $response | ConvertFrom-Json

                    if ($dnsResult.Answer -and $dnsResult.Answer.Count -gt 0)
                    {
                        $records = @($dnsResult.Answer | ForEach-Object {
                                $data = $_.data
                                # Clean up TXT record quoting
                                if ($Type -eq 'TXT' -and $data -match '^".*"$')
                                {
                                    $data = $data.Trim('"')
                                }
                                $data
                            })
                        $status = 'Resolved'
                    }
                    else
                    {
                        $status = 'NoRecords'
                    }
                }
                finally
                {
                    if ($client) { $client.Dispose() }
                    if ($handler) { $handler.Dispose() }
                }
            }
            catch
            {
                Write-Verbose "Error querying $($server.Name): $($_.Exception.Message)"

                # Retry with proxy
                try
                {
                    $handler2 = New-Object System.Net.Http.HttpClientHandler
                    $handler2.UseProxy = $true
                    $handler2.UseDefaultCredentials = $true
                    $client2 = New-Object System.Net.Http.HttpClient($handler2)
                    $client2.Timeout = [TimeSpan]::FromSeconds($Timeout)
                    $client2.DefaultRequestHeaders.Accept.Clear()
                    $client2.DefaultRequestHeaders.Accept.Add(
                        [System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/dns-json')
                    )

                    try
                    {
                        $response2 = $client2.GetStringAsync($dohUrl).GetAwaiter().GetResult()
                        $dnsResult2 = $response2 | ConvertFrom-Json

                        if ($dnsResult2.Answer -and $dnsResult2.Answer.Count -gt 0)
                        {
                            $records = @($dnsResult2.Answer | ForEach-Object { $_.data })
                            $status = 'Resolved'
                        }
                        else
                        {
                            $status = 'NoRecords'
                        }
                    }
                    finally
                    {
                        if ($client2) { $client2.Dispose() }
                        if ($handler2) { $handler2.Dispose() }
                    }
                }
                catch
                {
                    Write-Verbose "Proxy retry also failed for $($server.Name): $($_.Exception.Message)"
                    $status = 'Error'
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
