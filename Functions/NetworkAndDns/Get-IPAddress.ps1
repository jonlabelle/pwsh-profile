function Get-IPAddress
{
    <#
    .SYNOPSIS
        Retrieves local network interface IP addresses or public external IP address.

    .DESCRIPTION
        Gets IP address information from local network interfaces or queries external services
        to determine your public-facing IP address. Supports filtering by address family (IPv4/IPv6),
        interface status, and provides detailed network adapter information.

        For public IP queries, uses multiple fallback services for reliability:
        - ipinfo.io (default, provides geolocation data)
        - ifconfig.me
        - icanhazip.com
        - api.ipify.org

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Public
        Query external services to get your public-facing IP address.
        Returns the IP address that external servers see when you connect.

    .PARAMETER AddressFamily
        Filter IP addresses by address family.
        Valid values: 'IPv4', 'IPv6', 'All'
        Default is 'All' which returns both IPv4 and IPv6 addresses.

    .PARAMETER ActiveOnly
        Only return IP addresses from active/operational network interfaces.
        Excludes interfaces that are down, disabled, or not connected.

    .PARAMETER IncludeDetails
        Include additional details such as interface name, description, MAC address, and network prefix.
        Only applicable for local IP addresses (not used with -Public).

    .PARAMETER Service
        Specify which external service to use for public IP lookup.
        Valid values: 'ipinfo', 'ifconfig', 'icanhazip', 'ipify', 'auto'
        Default is 'auto' which tries multiple services for reliability.
        Only applicable with -Public flag.

    .PARAMETER Timeout
        Timeout in seconds for public IP service queries.
        Default is 5 seconds. Valid range: 1-30 seconds.

    .EXAMPLE
        PS > Get-IPAddress

        IPAddress  AddressFamily
        ---------  -------------
        127.0.0.1  IPv4
        ::1        IPv6
        10.0.10.39 IPv4

        Gets all local IP addresses from all network interfaces.

    .EXAMPLE
        PS > Get-IPAddress -Public

        Gets your public IP address by querying external services.

    .EXAMPLE
        PS > Get-IPAddress -AddressFamily IPv4

        Gets only IPv4 addresses from local network interfaces.

    .EXAMPLE
        PS > Get-IPAddress -ActiveOnly

        Gets IP addresses only from active network interfaces.

    .EXAMPLE
        PS > Get-IPAddress -IncludeDetails

        IPAddress     : 127.0.0.1
        AddressFamily : IPv4
        InterfaceName : lo0
        Description   : lo0
        Status        : Up
        InterfaceType : Loopback
        SubnetMask    : 255.0.0.0
        PrefixLength  : 8

        IPAddress     : ::1
        AddressFamily : IPv6
        InterfaceName : lo0
        Description   : lo0
        Status        : Up
        InterfaceType : Loopback
        PrefixLength  : 128

        IPAddress     : 10.0.10.39
        AddressFamily : IPv4
        InterfaceName : en0
        Description   : en0
        Status        : Up
        InterfaceType : Wireless80211
        MACAddress    : 02:7F:40:AB:AF:64
        SubnetMask    : 255.255.255.0
        PrefixLength  : 24
        Speed         : 146Mbps

        Gets local IP addresses with detailed interface information including MAC address and interface name.

    .EXAMPLE
        PS > Get-IPAddress -Public -Service ipinfo

        IPAddress     : 24.XX.XX.XX
        AddressFamily : IPv4
        Service       : ipinfo
        City          : Austin
        Region        : Texas
        Country       : US
        Location      : XX.XXXX,-XX.XXXX
        Organization  : AS20115 Charter Communications LLC
        Timezone      : America/Chicago


        Gets public IP address using ipinfo.io service which includes geolocation data.

    .EXAMPLE
        PS > Get-IPAddress -AddressFamily IPv4 -ActiveOnly -IncludeDetails

        Gets detailed IPv4 address information from active interfaces only.

    .EXAMPLE
        PS > Get-IPAddress -Public -AddressFamily IPv4

        Gets only your public IPv4 address.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        For local IPs: Returns objects with IPAddress, AddressFamily, and optionally InterfaceName, Description, etc.
        For public IPs: Returns objects with IPAddress, AddressFamily, and optionally City, Region, Country, etc. (ipinfo service).

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.net.networkinformation.networkinterface

    .NOTES
        Author: Jon LaBelle
        Date: November 9, 2025

        Dependencies:
        - Set-TlsSecurityProtocol (for HTTPS/TLS 1.2+ support)

        Public IP Services:
        - ipinfo.io - Provides geolocation data (city, region, country, org)
        - ifconfig.me - Simple IP return
        - icanhazip.com - Cloudflare service
        - api.ipify.org - Simple, reliable service

        Privacy Note: Public IP queries send requests to external services.
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
        [Switch]$ActiveOnly,

        [Parameter(ParameterSetName = 'Local')]
        [Switch]$IncludeDetails,

        [Parameter(ParameterSetName = 'Public')]
        [ValidateSet('ipinfo', 'ifconfig', 'icanhazip', 'ipify', 'auto')]
        [String]$Service = 'auto',

        [Parameter(ParameterSetName = 'Public')]
        [ValidateRange(1, 30)]
        [Int32]$Timeout = 5
    )

    begin
    {
        Write-Verbose "Getting IP addresses (Mode: $(if ($Public) { 'Public' } else { 'Local' }))"

        # Ensure TLS 1.2+ is enabled for HTTPS connections
        Set-TlsSecurityProtocol -MinimumVersion Tls12
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
                                    IPAddress = $ipAddress
                                    AddressFamily = $family
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
                                $family = if ($parsedIP.AddressFamily -eq 'InterNetwork') { 'IPv4' } else { 'IPv6' }

                                # Filter by address family if specified
                                if ($AddressFamily -ne 'All' -and $family -ne $AddressFamily)
                                {
                                    Write-Verbose "Skipping $family address (filtering for $AddressFamily)"
                                    $response.Dispose()
                                    continue
                                }

                                Write-Output ([PSCustomObject]@{
                                        IPAddress = $ipAddress
                                        AddressFamily = $family
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

                        # Build result object
                        $result = [PSCustomObject]@{
                            IPAddress = $addr.ToString()
                            AddressFamily = $family
                        }

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

                            $result | Add-Member -NotePropertyName 'PrefixLength' -NotePropertyValue $unicastAddr.PrefixLength

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
        }
    }

    end
    {
        Write-Verbose 'IP address retrieval completed'
    }
}
