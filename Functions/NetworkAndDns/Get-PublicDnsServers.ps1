function Get-PublicDnsServers
{
    <#
    .SYNOPSIS
        Returns a curated list of well-known public DNS servers.

    .DESCRIPTION
        Provides a structured list of well-known public DNS resolver services including their
        IPv4 addresses, IPv6 addresses, DNS-over-HTTPS (DoH) URLs, and privacy policy links.
        Useful as a reference utility or as input for other DNS functions such as
        Test-DnsPropagation.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Name
        Filter the list by provider name. Supports wildcards.
        For example, 'Cloud*' returns only Cloudflare entries.

    .PARAMETER IPv4Only
        Return only the primary IPv4 address strings instead of full objects.
        Useful for piping into other commands that need a simple list of server IPs.

    .EXAMPLE
        PS > Get-PublicDnsServers

        Name          IPv4Primary       IPv4Secondary   IPv6Primary            IPv6Secondary            DoHUrl
        ----          -----------       -------------   -----------            -------------            ------
        Cloudflare    1.1.1.1           1.0.0.1         2606:4700:4700::1111   2606:4700:4700::1001     https://cloudflare-dns.com/dns-query
        Google        8.8.8.8           8.8.4.4         2001:4860:4860::8888   2001:4860:4860::8844     https://dns.google/dns-query
        Quad9         9.9.9.9           149.112.112.112 2620:fe::fe            2620:fe::9               https://dns.quad9.net/dns-query
        OpenDNS       208.67.222.222    208.67.220.220  2620:119:35::35        2620:119:53::53          https://doh.opendns.com/dns-query
        Comodo Secure 8.26.56.26        8.20.247.20
        CleanBrowsing 185.228.168.9     185.228.169.9   2a0d:2a00:1::2         2a0d:2a00:2::2           https://doh.cleanbrowsing.org/doh/security-filter
        AdGuard DNS   94.140.14.14      94.140.15.15    2a10:50c0::ad1:ff      2a10:50c0::ad2:ff        https://dns.adguard-dns.com/dns-query
        Control D     76.76.2.0         76.76.10.0      2606:1a40::            2606:1a40:1::            https://freedns.controld.com/p0

        Returns all known public DNS servers.

    .EXAMPLE
        PS > Get-PublicDnsServers -Name 'Google'

        Name   IPv4Primary IPv4Secondary IPv6Primary          IPv6Secondary        DoHUrl
        ----   ----------- ------------- -----------          -------------        ------
        Google 8.8.8.8     8.8.4.4       2001:4860:4860::8888 2001:4860:4860::8844 https://dns.google/dns-query

        Returns only Google's DNS server information.

    .EXAMPLE
        PS > Get-PublicDnsServers -IPv4Only

        1.1.1.1
        8.8.8.8
        9.9.9.9
        208.67.222.222
        8.26.56.26
        185.228.168.9
        94.140.14.14
        76.76.2.0

        Returns just the primary IPv4 addresses for all providers.

    .EXAMPLE
        PS > Get-PublicDnsServers -IPv4Only | ForEach-Object { Test-Port -ComputerName $_ -Port 53 }

        Tests DNS port connectivity to all public DNS servers.

    .OUTPUTS
        PSCustomObject
        Returns objects with Name, IPv4Primary, IPv4Secondary, IPv6Primary, IPv6Secondary,
        DoHUrl, DoHJsonUrl, and PrivacyPolicyUrl properties.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-PublicDnsServers.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-PublicDnsServers.ps1
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Position = 0)]
        [String]
        $Name,

        [Parameter()]
        [Switch]
        $IPv4Only
    )

    begin
    {
        Write-Verbose 'Building public DNS server list'
    }

    process
    {
        $servers = @(
            [PSCustomObject]@{
                Name = 'Cloudflare'
                IPv4Primary = '1.1.1.1'
                IPv4Secondary = '1.0.0.1'
                IPv6Primary = '2606:4700:4700::1111'
                IPv6Secondary = '2606:4700:4700::1001'
                DoHUrl = 'https://cloudflare-dns.com/dns-query'
                DoHJsonUrl = 'https://cloudflare-dns.com/dns-query'
                PrivacyPolicyUrl = 'https://developers.cloudflare.com/1.1.1.1/privacy/public-dns-resolver/'
            }
            [PSCustomObject]@{
                Name = 'Google'
                IPv4Primary = '8.8.8.8'
                IPv4Secondary = '8.8.4.4'
                IPv6Primary = '2001:4860:4860::8888'
                IPv6Secondary = '2001:4860:4860::8844'
                DoHUrl = 'https://dns.google/dns-query'
                DoHJsonUrl = 'https://dns.google/resolve'
                PrivacyPolicyUrl = 'https://developers.google.com/speed/public-dns/privacy'
            }
            [PSCustomObject]@{
                Name = 'Quad9'
                IPv4Primary = '9.9.9.9'
                IPv4Secondary = '149.112.112.112'
                IPv6Primary = '2620:fe::fe'
                IPv6Secondary = '2620:fe::9'
                DoHUrl = 'https://dns.quad9.net/dns-query'
                DoHJsonUrl = $null
                PrivacyPolicyUrl = 'https://www.quad9.net/service/privacy/'
            }
            [PSCustomObject]@{
                Name = 'OpenDNS'
                IPv4Primary = '208.67.222.222'
                IPv4Secondary = '208.67.220.220'
                IPv6Primary = '2620:119:35::35'
                IPv6Secondary = '2620:119:53::53'
                DoHUrl = 'https://doh.opendns.com/dns-query'
                DoHJsonUrl = $null
                PrivacyPolicyUrl = 'https://www.cisco.com/c/en/us/about/legal/privacy-full.html'
            }
            [PSCustomObject]@{
                Name = 'Comodo Secure'
                IPv4Primary = '8.26.56.26'
                IPv4Secondary = '8.20.247.20'
                IPv6Primary = $null
                IPv6Secondary = $null
                DoHUrl = $null
                DoHJsonUrl = $null
                PrivacyPolicyUrl = 'https://www.comodo.com/repository/privacy.pdf'
            }
            [PSCustomObject]@{
                Name = 'CleanBrowsing'
                IPv4Primary = '185.228.168.9'
                IPv4Secondary = '185.228.169.9'
                IPv6Primary = '2a0d:2a00:1::2'
                IPv6Secondary = '2a0d:2a00:2::2'
                DoHUrl = 'https://doh.cleanbrowsing.org/doh/security-filter'
                DoHJsonUrl = $null
                PrivacyPolicyUrl = 'https://cleanbrowsing.org/privacy'
            }
            [PSCustomObject]@{
                Name = 'AdGuard DNS'
                IPv4Primary = '94.140.14.14'
                IPv4Secondary = '94.140.15.15'
                IPv6Primary = '2a10:50c0::ad1:ff'
                IPv6Secondary = '2a10:50c0::ad2:ff'
                DoHUrl = 'https://dns.adguard-dns.com/dns-query'
                DoHJsonUrl = $null
                PrivacyPolicyUrl = 'https://adguard-dns.io/en/privacy.html'
            }
            [PSCustomObject]@{
                Name = 'Control D'
                IPv4Primary = '76.76.2.0'
                IPv4Secondary = '76.76.10.0'
                IPv6Primary = '2606:1a40::'
                IPv6Secondary = '2606:1a40:1::'
                DoHUrl = 'https://freedns.controld.com/p0'
                DoHJsonUrl = $null
                PrivacyPolicyUrl = 'https://controld.com/privacy'
            }
        )

        # Apply name filter if specified
        if ($Name)
        {
            Write-Verbose "Filtering servers by name pattern: '$Name'"
            $servers = $servers | Where-Object { $_.Name -like $Name }
        }

        if ($IPv4Only)
        {
            Write-Verbose 'Returning IPv4 primary addresses only'
            $servers | ForEach-Object { $_.IPv4Primary }
        }
        else
        {
            $servers
        }
    }

    end
    {
        Write-Verbose "Returned $(@($servers).Count) DNS server(s)"
    }
}
