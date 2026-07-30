function Get-IPAddress
{
    <#
    .SYNOPSIS
        Retrieves local network interface IP addresses and the public external IP address.

    .DESCRIPTION
        Gets IP address information from local network interfaces and, by default, queries an
        external service to include your public-facing IP address in the same result set. Each
        result includes a Scope value such as Public, Private, Loopback, or LinkLocal.
        Local results also include the interface network in CIDR notation.

        Use -Public to return only the public-facing address, or -SkipPublic to return only local
        interface addresses without contacting an external service. Supports filtering by address
        family (IPv4/IPv6), interface status, and provides detailed network adapter information.

        Public IP lookup services report the observed address but not the network prefix assigned
        by an ISP or upstream NAT device, so CIDR is empty for public lookup results. If a public
        address is assigned directly to a local interface, its local result includes the real CIDR.

        For public IP queries, uses multiple fallback services for reliability:
        - ipinfo.io (default, provides geolocation data)
        - ifconfig.me
        - icanhazip.com
        - api.ipify.org

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Public
        Return only your public-facing IP address by querying external services.
        Without this switch, the public address is included with local interface addresses.

    .PARAMETER SkipPublic
        Return only local interface addresses and do not contact an external public IP service.

    .PARAMETER AddressFamily
        Filter IP addresses by address family.
        Valid values: 'IPv4', 'IPv6', 'All'
        Default is 'All' which returns both IPv4 and IPv6 addresses.

    .PARAMETER ActiveOnly
        Only return IP addresses from active/operational network interfaces.
        Excludes interfaces that are down, disabled, or not connected.
        The public address lookup is still performed unless -SkipPublic is specified.

    .PARAMETER IncludeDetails
        Include additional details such as interface name, description, MAC address, and network prefix.
        Only applicable for local IP addresses (not used with -Public).

    .PARAMETER Service
        Specify which external service to use for public IP lookup.
        Valid values: 'ipinfo', 'ifconfig', 'icanhazip', 'ipify', 'auto'
        Default is 'auto' which tries multiple services for reliability.
        Applies to both the default combined lookup and -Public.

    .PARAMETER Timeout
        Timeout in seconds for public IP service queries.
        Default is 5 seconds. Valid range: 1-30 seconds.
        Applies to both the default combined lookup and -Public.

    .EXAMPLE
        PS > Get-IPAddress

        Address       Family Scope    CIDR
        -------       ------ -----    ----
        127.0.0.1     IPv4   Loopback 127.0.0.0/8
        ::1           IPv6   Loopback ::1/128
        192.168.1.25  IPv4   Private  192.168.1.0/24
        192.0.0.9     IPv4   Public

        Gets local interface addresses with their networks and includes the public-facing address
        when available. The public row has no CIDR value because its prefix is unknown.

    .EXAMPLE
        PS > Get-IPAddress -Public

        Gets only your public-facing IP address by querying external services.

    .EXAMPLE
        PS > Get-IPAddress -SkipPublic

        Gets only local interface addresses without contacting an external service.

    .EXAMPLE
        PS > Get-IPAddress -AddressFamily IPv4

        Gets local and public IPv4 addresses.

    .EXAMPLE
        PS > Get-IPAddress -ActiveOnly

        Gets addresses from active local interfaces and includes the public-facing address.

    .EXAMPLE
        PS > Get-IPAddress -IncludeDetails

        Address       : 127.0.0.1
        Family        : IPv4
        Scope         : Loopback
        CIDR          : 127.0.0.0/8
        InterfaceName : lo0
        Description   : lo0
        Status        : Up
        InterfaceType : Loopback
        SubnetMask    : 255.0.0.0
        PrefixLength  : 8

        Address       : ::1
        Family        : IPv6
        Scope         : Loopback
        CIDR          : ::1/128
        InterfaceName : lo0
        Description   : lo0
        Status        : Up
        InterfaceType : Loopback
        PrefixLength  : 128

        Address       : 192.168.1.25
        Family        : IPv4
        Scope         : Private
        CIDR          : 192.168.1.0/24
        InterfaceName : en0
        Description   : en0
        Status        : Up
        InterfaceType : Wireless80211
        MACAddress    : 02:00:5E:10:00:00
        SubnetMask    : 255.255.255.0
        PrefixLength  : 24
        Speed         : 146Mbps

        Gets local IP addresses with detailed interface information and also includes the
        public-facing address. Public results do not contain interface details.

    .EXAMPLE
        PS > Get-IPAddress -Public -Service ipinfo

        Address      : <public IPv4 address>
        Family       : IPv4
        Scope        : Public
        CIDR         :
        Service      : ipinfo
        City         : <city>
        Region       : <region>
        Country      : <country code>
        Location     : <latitude,longitude>
        Organization : <network organization>
        Timezone     : <timezone>


        Gets public IP address using ipinfo.io service which includes geolocation data.

    .EXAMPLE
        PS > Get-IPAddress -AddressFamily IPv4 -ActiveOnly -IncludeDetails

        Gets detailed IPv4 address information from active local interfaces and includes the
        public-facing IPv4 address when available.

    .EXAMPLE
        PS > Get-IPAddress -Public -AddressFamily IPv4

        Gets only your public IPv4 address.

    .EXAMPLE
        PS > $ip = (Get-IPAddress -Public -Service ipify).Address
        PS > az network public-ip update --resource-group ExampleGroup --name ExampleGateway --dns-settings "{ fqdn: 'gateway.example.com', reverseFqdn: $ip }"

        Captures the current public IP and feeds it into an automation step that syncs Azure DNS entries.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Every result includes Address, Family, Scope, and CIDR. CIDR contains the
        calculated interface network for local addresses and is null for public lookup results.
        Local results can also include InterfaceName, Description, and related details. Public
        results include Service and can include geolocation data when ipinfo is used.

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.net.networkinformation.networkinterface

    .NOTES
        Public IP Services:
        - ipinfo.io - Provides geolocation data (city, region, country, org)
        - ifconfig.me - Simple IP return
        - icanhazip.com - Cloudflare service
        - api.ipify.org - Simple, reliable service

        Privacy Note: The default call and -Public send requests to external services.
        Use -SkipPublic to avoid external requests.

        Public CIDR Note: A public IP lookup does not reveal the routed subnet assigned by an ISP
        or upstream NAT device. Treating the observed address as /32 or /128 would describe a host
        route, not the actual public network, so public lookup results intentionally use a null
        CIDR. A publicly scoped address found on a local interface still uses that interface's
        actual prefix.

        Scope classifications follow the IANA IPv4 and IPv6 special-purpose registries.

        Author: Jon LaBelle
        License: MIT
    .LINK
        https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry.xhtml
    .LINK
        https://www.iana.org/assignments/iana-ipv6-special-registry/iana-ipv6-special-registry.xhtml
    .LINK
        https://learn.microsoft.com/en-us/dotnet/api/system.net.networkinformation.unicastipaddressinformation.prefixlength
    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-IPAddress.ps1

        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-IPAddress.ps1
    #>
    [CmdletBinding(DefaultParameterSetName = 'Local')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Public')]
        [Switch]$Public,

        [Parameter()]
        [ValidateSet('IPv4', 'IPv6', 'All')]
        [String]$AddressFamily = 'All',

        [Parameter(ParameterSetName = 'Local')]
        [Parameter(ParameterSetName = 'LocalOnly')]
        [Switch]$ActiveOnly,

        [Parameter(ParameterSetName = 'Local')]
        [Parameter(ParameterSetName = 'LocalOnly')]
        [Switch]$IncludeDetails,

        [Parameter(Mandatory, ParameterSetName = 'LocalOnly')]
        [Switch]$SkipPublic,

        [Parameter(ParameterSetName = 'Local')]
        [Parameter(ParameterSetName = 'Public')]
        [ValidateSet('ipinfo', 'ifconfig', 'icanhazip', 'ipify', 'auto')]
        [String]$Service = 'auto',

        [Parameter(ParameterSetName = 'Local')]
        [Parameter(ParameterSetName = 'Public')]
        [ValidateRange(1, 30)]
        [Int32]$Timeout = 5
    )

    begin
    {
        function Test-IPAddressInPrefix
        {
            [OutputType([Boolean])]
            param(
                [Parameter(Mandatory)]
                [System.Net.IPAddress]$Address,

                [Parameter(Mandatory)]
                [System.Net.IPAddress]$Network,

                [Parameter(Mandatory)]
                [Int32]$PrefixLength
            )

            $addressBytes = $Address.GetAddressBytes()
            $networkBytes = $Network.GetAddressBytes()

            if ($addressBytes.Length -ne $networkBytes.Length -or
                $PrefixLength -lt 0 -or
                $PrefixLength -gt ($addressBytes.Length * 8))
            {
                return $false
            }

            $wholeBytes = [Int32][Math]::Floor($PrefixLength / 8)
            for ($index = 0; $index -lt $wholeBytes; $index++)
            {
                if ($addressBytes[$index] -ne $networkBytes[$index])
                {
                    return $false
                }
            }

            $remainingBits = $PrefixLength % 8
            if ($remainingBits -eq 0)
            {
                return $true
            }

            $mask = [Byte]((0xFF -shl (8 - $remainingBits)) -band 0xFF)
            return (($addressBytes[$wholeBytes] -band $mask) -eq ($networkBytes[$wholeBytes] -band $mask))
        }

        function Get-IPAddressCidr
        {
            [OutputType([String])]
            param(
                [Parameter(Mandatory)]
                [System.Net.IPAddress]$Address,

                [Parameter(Mandatory)]
                [Int32]$PrefixLength
            )

            $addressBytes = $Address.GetAddressBytes()
            if ($PrefixLength -lt 0 -or $PrefixLength -gt ($addressBytes.Length * 8))
            {
                return $null
            }

            $networkBytes = [Byte[]]$addressBytes.Clone()
            $wholeBytes = [Int32][Math]::Floor($PrefixLength / 8)
            $remainingBits = $PrefixLength % 8

            if ($remainingBits -gt 0)
            {
                $mask = [Byte]((0xFF -shl (8 - $remainingBits)) -band 0xFF)
                $networkBytes[$wholeBytes] = $networkBytes[$wholeBytes] -band $mask
                $firstHostByte = $wholeBytes + 1
            }
            else
            {
                $firstHostByte = $wholeBytes
            }

            for ($index = $firstHostByte; $index -lt $networkBytes.Length; $index++)
            {
                $networkBytes[$index] = 0
            }

            $networkAddress = [System.Net.IPAddress]::new($networkBytes)
            return "$($networkAddress.ToString())/$PrefixLength"
        }

        $ipv4ScopeRules = @(
            @{ Network = [System.Net.IPAddress]::Parse('0.0.0.0'); PrefixLength = 32; Scope = 'Unspecified' }
            @{ Network = [System.Net.IPAddress]::Parse('192.0.0.9'); PrefixLength = 32; Scope = 'Public' }
            @{ Network = [System.Net.IPAddress]::Parse('192.0.0.10'); PrefixLength = 32; Scope = 'Public' }
            @{ Network = [System.Net.IPAddress]::Parse('10.0.0.0'); PrefixLength = 8; Scope = 'Private' }
            @{ Network = [System.Net.IPAddress]::Parse('100.64.0.0'); PrefixLength = 10; Scope = 'Shared' }
            @{ Network = [System.Net.IPAddress]::Parse('127.0.0.0'); PrefixLength = 8; Scope = 'Loopback' }
            @{ Network = [System.Net.IPAddress]::Parse('169.254.0.0'); PrefixLength = 16; Scope = 'LinkLocal' }
            @{ Network = [System.Net.IPAddress]::Parse('172.16.0.0'); PrefixLength = 12; Scope = 'Private' }
            @{ Network = [System.Net.IPAddress]::Parse('192.0.0.0'); PrefixLength = 24; Scope = 'Reserved' }
            @{ Network = [System.Net.IPAddress]::Parse('192.0.2.0'); PrefixLength = 24; Scope = 'Documentation' }
            @{ Network = [System.Net.IPAddress]::Parse('192.88.99.0'); PrefixLength = 24; Scope = 'Reserved' }
            @{ Network = [System.Net.IPAddress]::Parse('192.168.0.0'); PrefixLength = 16; Scope = 'Private' }
            @{ Network = [System.Net.IPAddress]::Parse('198.18.0.0'); PrefixLength = 15; Scope = 'Benchmark' }
            @{ Network = [System.Net.IPAddress]::Parse('198.51.100.0'); PrefixLength = 24; Scope = 'Documentation' }
            @{ Network = [System.Net.IPAddress]::Parse('203.0.113.0'); PrefixLength = 24; Scope = 'Documentation' }
            @{ Network = [System.Net.IPAddress]::Parse('224.0.0.0'); PrefixLength = 4; Scope = 'Multicast' }
            @{ Network = [System.Net.IPAddress]::Parse('240.0.0.0'); PrefixLength = 4; Scope = 'Reserved' }
            @{ Network = [System.Net.IPAddress]::Parse('0.0.0.0'); PrefixLength = 8; Scope = 'Reserved' }
        )

        $ipv6ScopeRules = @(
            @{ Network = [System.Net.IPAddress]::Parse('::'); PrefixLength = 128; Scope = 'Unspecified' }
            @{ Network = [System.Net.IPAddress]::Parse('2001:1::1'); PrefixLength = 128; Scope = 'Public' }
            @{ Network = [System.Net.IPAddress]::Parse('2001:1::2'); PrefixLength = 128; Scope = 'Public' }
            @{ Network = [System.Net.IPAddress]::Parse('2001:1::3'); PrefixLength = 128; Scope = 'Public' }
            @{ Network = [System.Net.IPAddress]::Parse('64:ff9b::'); PrefixLength = 96; Scope = 'Public' }
            @{ Network = [System.Net.IPAddress]::Parse('2001:4:112::'); PrefixLength = 48; Scope = 'Public' }
            @{ Network = [System.Net.IPAddress]::Parse('2001:3::'); PrefixLength = 32; Scope = 'Public' }
            @{ Network = [System.Net.IPAddress]::Parse('2001:20::'); PrefixLength = 28; Scope = 'Public' }
            @{ Network = [System.Net.IPAddress]::Parse('2001:30::'); PrefixLength = 28; Scope = 'Public' }
            @{ Network = [System.Net.IPAddress]::Parse('2001:2::'); PrefixLength = 48; Scope = 'Benchmark' }
            @{ Network = [System.Net.IPAddress]::Parse('2001:db8::'); PrefixLength = 32; Scope = 'Documentation' }
            @{ Network = [System.Net.IPAddress]::Parse('3fff::'); PrefixLength = 20; Scope = 'Documentation' }
            @{ Network = [System.Net.IPAddress]::Parse('fc00::'); PrefixLength = 7; Scope = 'Private' }
            @{ Network = [System.Net.IPAddress]::Parse('fe80::'); PrefixLength = 10; Scope = 'LinkLocal' }
            @{ Network = [System.Net.IPAddress]::Parse('ff00::'); PrefixLength = 8; Scope = 'Multicast' }
            @{ Network = [System.Net.IPAddress]::Parse('::ffff:0:0'); PrefixLength = 96; Scope = 'Reserved' }
            @{ Network = [System.Net.IPAddress]::Parse('64:ff9b:1::'); PrefixLength = 48; Scope = 'Reserved' }
            @{ Network = [System.Net.IPAddress]::Parse('100::'); PrefixLength = 64; Scope = 'Reserved' }
            @{ Network = [System.Net.IPAddress]::Parse('100:0:0:1::'); PrefixLength = 64; Scope = 'Reserved' }
            @{ Network = [System.Net.IPAddress]::Parse('2001::'); PrefixLength = 23; Scope = 'Reserved' }
            @{ Network = [System.Net.IPAddress]::Parse('2002::'); PrefixLength = 16; Scope = 'Reserved' }
            @{ Network = [System.Net.IPAddress]::Parse('5f00::'); PrefixLength = 16; Scope = 'Reserved' }
            @{ Network = [System.Net.IPAddress]::Parse('2000::'); PrefixLength = 3; Scope = 'Public' }
        )

        function Get-AddressClassification
        {
            [OutputType([String])]
            param(
                [Parameter(Mandatory)]
                [System.Net.IPAddress]$Address
            )

            if ([System.Net.IPAddress]::IsLoopback($Address))
            {
                return 'Loopback'
            }

            $scopeRules = switch ($Address.AddressFamily)
            {
                ([System.Net.Sockets.AddressFamily]::InterNetwork) { $ipv4ScopeRules; break }
                ([System.Net.Sockets.AddressFamily]::InterNetworkV6) { $ipv6ScopeRules; break }
                default { return 'Unknown' }
            }

            foreach ($rule in $scopeRules)
            {
                if (Test-IPAddressInPrefix -Address $Address -Network $rule.Network -PrefixLength $rule.PrefixLength)
                {
                    return $rule.Scope
                }
            }

            if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork)
            {
                return 'Public'
            }

            return 'Reserved'
        }

        $mode = if ($Public)
        {
            'Public'
        }
        elseif ($SkipPublic)
        {
            'LocalOnly'
        }
        else
        {
            'Combined'
        }

        $localIPAddressSet = @{}
        Write-Verbose "Getting IP addresses (Mode: $mode)"
    }

    process
    {
        if ($Public)
        {
            # Get public IP address from external services
            Write-Verbose 'Querying external services for public IP address'

            $services = @(
                @{ Name = 'ipinfo'; Url = 'https://ipinfo.io/json'; Type = 'json' }
                @{ Name = 'ifconfig'; Url = 'https://ifconfig.me/ip'; Type = 'text' }
                @{ Name = 'icanhazip'; Url = 'https://icanhazip.com'; Type = 'text' }
                @{ Name = 'ipify'; Url = 'https://api.ipify.org?format=json'; Type = 'json' }
            )

            # Filter services if specific one requested
            if ($Service -ne 'auto')
            {
                $services = $services | Where-Object { $_.Name -eq $Service }
            }

            $httpClient = $null
            try
            {
                $httpClient = [System.Net.Http.HttpClient]::new()
                $httpClient.Timeout = [TimeSpan]::FromSeconds($Timeout)
                $httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("PowerShell/$($PSVersionTable.PSVersion.ToString())")

                foreach ($svc in $services)
                {
                    try
                    {
                        Write-Verbose "Trying service: $($svc.Name) ($($svc.Url))"

                        $response = $httpClient.GetAsync($svc.Url).GetAwaiter().GetResult()

                        if ($response.IsSuccessStatusCode)
                        {
                            $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult().Trim()

                            if ($svc.Type -eq 'json')
                            {
                                $data = $content | ConvertFrom-Json

                                # Extract IP based on service format
                                $ipAddress = switch ($svc.Name)
                                {
                                    'ipinfo' { $data.ip }
                                    'ipify' { $data.ip }
                                    default { $data.ip }
                                }

                                # Determine address family
                                $parsedIP = [System.Net.IPAddress]::Parse($ipAddress)
                                $ipAddress = $parsedIP.ToString()
                                $family = if ($parsedIP.AddressFamily -eq 'InterNetwork') { 'IPv4' } else { 'IPv6' }

                                # Filter by address family if specified
                                if ($AddressFamily -ne 'All' -and $family -ne $AddressFamily)
                                {
                                    Write-Verbose "Skipping $family address (filtering for $AddressFamily)"
                                    $response.Dispose()
                                    continue
                                }

                                # Build result object
                                $result = [PSCustomObject]@{
                                    Address = $ipAddress
                                    Family = $family
                                    Scope = Get-AddressClassification -Address $parsedIP
                                    CIDR = $null
                                    Service = $svc.Name
                                }

                                # Add geolocation data if available (ipinfo service)
                                if ($svc.Name -eq 'ipinfo' -and $data.city)
                                {
                                    $result | Add-Member -NotePropertyName 'City' -NotePropertyValue $data.city
                                    $result | Add-Member -NotePropertyName 'Region' -NotePropertyValue $data.region
                                    $result | Add-Member -NotePropertyName 'Country' -NotePropertyValue $data.country
                                    $result | Add-Member -NotePropertyName 'Location' -NotePropertyValue $data.loc
                                    $result | Add-Member -NotePropertyName 'Organization' -NotePropertyValue $data.org
                                    $result | Add-Member -NotePropertyName 'Timezone' -NotePropertyValue $data.timezone
                                }

                                Write-Output $result
                                $response.Dispose()
                                return
                            }
                            else
                            {
                                # Plain text response
                                $ipAddress = $content

                                # Determine address family
                                $parsedIP = [System.Net.IPAddress]::Parse($ipAddress)
                                $ipAddress = $parsedIP.ToString()
                                $family = if ($parsedIP.AddressFamily -eq 'InterNetwork') { 'IPv4' } else { 'IPv6' }

                                # Filter by address family if specified
                                if ($AddressFamily -ne 'All' -and $family -ne $AddressFamily)
                                {
                                    Write-Verbose "Skipping $family address (filtering for $AddressFamily)"
                                    $response.Dispose()
                                    continue
                                }

                                Write-Output ([PSCustomObject]@{
                                        Address = $ipAddress
                                        Family = $family
                                        Scope = Get-AddressClassification -Address $parsedIP
                                        CIDR = $null
                                        Service = $svc.Name
                                    })

                                $response.Dispose()
                                return
                            }
                        }

                        $response.Dispose()
                    }
                    catch
                    {
                        Write-Verbose "Service $($svc.Name) failed: $($_.Exception.Message)"
                        # Continue to next service
                    }
                }

                Write-Error 'Failed to retrieve public IP address from all available services'
            }
            finally
            {
                if ($httpClient)
                {
                    $httpClient.Dispose()
                }
            }
        }
        else
        {
            # Get local IP addresses from network interfaces
            Write-Verbose 'Retrieving local network interface IP addresses'

            try
            {
                $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()

                foreach ($interface in $interfaces)
                {
                    # Filter by operational status if ActiveOnly is specified
                    if ($ActiveOnly -and $interface.OperationalStatus -ne 'Up')
                    {
                        Write-Verbose "Skipping interface '$($interface.Name)' (Status: $($interface.OperationalStatus))"
                        continue
                    }

                    # Get IP properties
                    $ipProps = $interface.GetIPProperties()

                    foreach ($unicastAddr in $ipProps.UnicastAddresses)
                    {
                        $addr = $unicastAddr.Address

                        # Determine address family
                        $family = if ($addr.AddressFamily -eq 'InterNetwork') { 'IPv4' } else { 'IPv6' }

                        # Filter by address family
                        if ($AddressFamily -ne 'All' -and $family -ne $AddressFamily)
                        {
                            continue
                        }

                        # Skip link-local IPv6 addresses unless specifically requesting IPv6
                        if ($family -eq 'IPv6' -and $addr.IsIPv6LinkLocal -and $AddressFamily -ne 'IPv6')
                        {
                            Write-Verbose "Skipping link-local IPv6 address: $($addr.ToString())"
                            continue
                        }

                        $prefixLength = $unicastAddr.PrefixLength

                        # Build result object
                        $result = [PSCustomObject]@{
                            Address = $addr.ToString()
                            Family = $family
                            Scope = Get-AddressClassification -Address $addr
                            CIDR = Get-IPAddressCidr -Address $addr -PrefixLength $prefixLength
                        }

                        $localIPAddressSet[$result.Address] = $true

                        # Add detailed information if requested
                        if ($IncludeDetails)
                        {
                            $result | Add-Member -NotePropertyName 'InterfaceName' -NotePropertyValue $interface.Name
                            $result | Add-Member -NotePropertyName 'Description' -NotePropertyValue $interface.Description
                            $result | Add-Member -NotePropertyName 'Status' -NotePropertyValue $interface.OperationalStatus.ToString()
                            $result | Add-Member -NotePropertyName 'InterfaceType' -NotePropertyValue $interface.NetworkInterfaceType.ToString()

                            # Add MAC address
                            $macAddress = $interface.GetPhysicalAddress().ToString()
                            if ($macAddress)
                            {
                                # Format MAC address with colons
                                $formattedMac = ($macAddress -replace '(.{2})', '$1:').TrimEnd(':')
                                $result | Add-Member -NotePropertyName 'MACAddress' -NotePropertyValue $formattedMac
                            }

                            # Add subnet mask/prefix length
                            if ($family -eq 'IPv4' -and $unicastAddr.IPv4Mask)
                            {
                                $result | Add-Member -NotePropertyName 'SubnetMask' -NotePropertyValue $unicastAddr.IPv4Mask.ToString()
                            }

                            $result | Add-Member -NotePropertyName 'PrefixLength' -NotePropertyValue $prefixLength

                            # Add speed if available
                            if ($interface.Speed -gt 0)
                            {
                                $speedMbps = [Math]::Round($interface.Speed / 1000000, 0)
                                $result | Add-Member -NotePropertyName 'Speed' -NotePropertyValue "${speedMbps}Mbps"
                            }
                        }

                        Write-Output $result
                    }
                }
            }
            catch
            {
                Write-Error "Failed to retrieve local IP addresses: $($_.Exception.Message)"
            }

            if (-not $SkipPublic)
            {
                Write-Verbose 'Appending public-facing IP address'

                $publicParameters = @{
                    Public = $true
                    AddressFamily = $AddressFamily
                    Service = $Service
                    Timeout = $Timeout
                }

                try
                {
                    $publicResults = @(Get-IPAddress @publicParameters -ErrorAction SilentlyContinue)

                    foreach ($publicResult in $publicResults)
                    {
                        $parsedPublicAddress = $null
                        if (-not [System.Net.IPAddress]::TryParse(
                                [String]$publicResult.Address,
                                [Ref]$parsedPublicAddress))
                        {
                            Write-Verbose "Ignoring invalid public IP response: '$($publicResult.Address)'"
                            continue
                        }

                        $normalizedPublicAddress = $parsedPublicAddress.ToString()
                        if ($localIPAddressSet.ContainsKey($normalizedPublicAddress))
                        {
                            Write-Verbose "Public IP address '$normalizedPublicAddress' is already present on a local interface"
                            continue
                        }

                        $publicResult.Address = $normalizedPublicAddress
                        $publicResult.Family = $(
                            if ($parsedPublicAddress.AddressFamily -eq 'InterNetwork') { 'IPv4' } else { 'IPv6' }
                        )
                        $publicResult.Scope = $(
                            Get-AddressClassification -Address $parsedPublicAddress
                        )
                        $publicResult.CIDR = $null

                        Write-Output $publicResult
                    }

                    if ($publicResults.Count -eq 0)
                    {
                        Write-Verbose 'Public IP address is unavailable; returning local interface addresses only'
                    }
                }
                catch
                {
                    Write-Verbose "Public IP lookup failed; returning local interface addresses only: $($_.Exception.Message)"
                }
            }
        }
    }

    end
    {
        Write-Verbose 'IP address retrieval completed'
    }
}
