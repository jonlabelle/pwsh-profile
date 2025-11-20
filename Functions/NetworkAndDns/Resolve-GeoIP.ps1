function Resolve-GeoIP
{
    <#
    .SYNOPSIS
        Resolves IP addresses to geographic location information.

    .DESCRIPTION
        Queries IP geolocation services to retrieve geographic information for IP addresses
        including country, region, city, coordinates, timezone, ISP, and other location data.

        Supports multiple free geolocation API services with automatic fallback:
        - ipapi.co (default) - Comprehensive data with 1000 requests/day free tier
        - ip-api.com - No key required, detailed info, 45 requests/minute
        - ipinfo.io - Clean API with city/region/country
        - ipwhois.app - No registration required

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER IPAddress
        The IP address(es) to geolocate. Supports both IPv4 and IPv6.
        Accepts pipeline input for bulk lookups.
        If not specified, resolves the current public IP address.

    .PARAMETER Service
        The geolocation service to use.
        Valid values: 'ipapi', 'ip-api', 'ipinfo', 'ipwhois', 'auto'
        Default is 'auto' which tries multiple services for reliability.

    .PARAMETER Timeout
        Request timeout in seconds.
        Default is 10 seconds. Valid range: 5-30 seconds.

    .PARAMETER IncludeRaw
        Include the raw JSON response from the API in the output.
        Useful for debugging or accessing additional fields not parsed by default.

    .EXAMPLE
        PS > Resolve-GeoIP

        IP           : 201.XX.XX.XX
        City         : Austin
        Region       : Texas
        RegionCode   : TX
        Country      : United States
        CountryCode  : US
        Continent    : NA
        Latitude     : 99.9999
        Longitude    : -99.9999
        Timezone     : America/Chicago
        ISP          : CHARTER
        Organization : CHARTER
        ASN          : AS20115
        PostalCode   : XXXXX
        Service      : ipapi.co

        Gets geolocation information for your current public IP address.

    .EXAMPLE
        PS > Resolve-GeoIP -IPAddress '8.8.8.8'

        Gets geolocation information for Google's public DNS server.

    .EXAMPLE
        PS > Resolve-GeoIP -IPAddress '1.1.1.1' -Service ipapi

        Gets geolocation for Cloudflare DNS using the ipapi.co service.

    .EXAMPLE
        PS > @('8.8.8.8', '1.1.1.1', '208.67.222.222') | Resolve-GeoIP

        Gets geolocation for multiple IP addresses using pipeline input.

    .EXAMPLE
        PS > Resolve-GeoIP -IPAddress '8.8.8.8' -IncludeRaw

        Gets geolocation with raw API response included.

    .EXAMPLE
        PS > Resolve-GeoIP -IPAddress '2001:4860:4860::8888'

        Gets geolocation for an IPv6 address.

    .EXAMPLE
        PS > Get-Content ./failed-logins.txt | Resolve-GeoIP -Service ipwhois | Select-Object IP,Country,ISP

        Enriches a list of suspicious IPs captured from application logs before blocking them in a firewall rule.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns objects with IP, City, Region, Country, Latitude, Longitude, Timezone, ISP, and other properties.

    .LINK
        https://ipapi.co/api/

    .LINK
        https://ip-api.com/docs

    .LINK
        https://ipinfo.io/developers

    .NOTES
        Author: Jon LaBelle
        Date: November 9, 2025

        Dependencies:
        - Set-TlsSecurityProtocol (for HTTPS/TLS 1.2+ support)

        API Service Details:
        - ipapi.co: 1000 requests/day free, HTTPS, detailed data
        - ip-api.com: 45 requests/minute, no key required, comprehensive
        - ipinfo.io: 50k requests/month, simple and reliable
        - ipwhois.app: No registration, unlimited for non-commercial

        Rate Limiting: Free tiers have rate limits. For bulk queries, add delays
        between requests or use the auto service which handles fallback.

        Privacy: IP geolocation queries send IP addresses to external services.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [Alias('IP', 'Address')]
        [String[]]$IPAddress,

        [Parameter()]
        [ValidateSet('ipapi', 'ip-api', 'ipinfo', 'ipwhois', 'auto')]
        [String]$Service = 'auto',

        [Parameter()]
        [ValidateRange(5, 30)]
        [Int32]$Timeout = 10,

        [Parameter()]
        [Switch]$IncludeRaw
    )

    begin
    {
        Write-Verbose 'Initializing IP geolocation lookup'

        # Ensure TLS 1.2+ is enabled for HTTPS connections
        Set-TlsSecurityProtocol -MinimumVersion Tls12

        # API service configurations
        $services = @{
            'ipapi' = @{
                Name = 'ipapi.co'
                UrlBase = 'https://ipapi.co'
                Format = 'json'
            }
            'ip-api' = @{
                Name = 'ip-api.com'
                UrlBase = 'http://ip-api.com/json'
                Format = 'json'
            }
            'ipinfo' = @{
                Name = 'ipinfo.io'
                UrlBase = 'https://ipinfo.io'
                Format = 'json'
            }
            'ipwhois' = @{
                Name = 'ipwhois.app'
                UrlBase = 'https://ipwhois.app/json'
                Format = 'json'
            }
        }

        # Order for auto fallback
        $serviceOrder = @('ipapi', 'ip-api', 'ipinfo', 'ipwhois')
    }

    process
    {
        # If no IP specified, get current public IP
        if (-not $IPAddress)
        {
            Write-Verbose 'No IP address specified, resolving current public IP'
            $IPAddress = @('')  # Empty string means current IP for most services
        }

        foreach ($ip in $IPAddress)
        {
            Write-Verbose "Resolving geolocation for IP: $(if ($ip) { $ip } else { 'current public IP' })"

            $httpClient = $null
            try
            {
                $httpClient = [System.Net.Http.HttpClient]::new()
                $httpClient.Timeout = [TimeSpan]::FromSeconds($Timeout)
                $httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("PowerShell/$($PSVersionTable.PSVersion.ToString())")

                # Determine which services to try
                $servicesToTry = if ($Service -eq 'auto')
                {
                    $serviceOrder
                }
                else
                {
                    @($Service)
                }

                $success = $false
                foreach ($svc in $servicesToTry)
                {
                    try
                    {
                        $config = $services[$svc]
                        Write-Verbose "Trying service: $($config.Name)"

                        # Build URL
                        $url = switch ($svc)
                        {
                            'ipapi'
                            {
                                if ($ip)
                                {
                                    "$($config.UrlBase)/$ip/json/"
                                }
                                else
                                {
                                    "$($config.UrlBase)/json/"
                                }
                            }
                            'ip-api'
                            {
                                if ($ip)
                                {
                                    "$($config.UrlBase)/$ip"
                                }
                                else
                                {
                                    "$($config.UrlBase)"
                                }
                            }
                            'ipinfo'
                            {
                                if ($ip)
                                {
                                    "$($config.UrlBase)/$ip/json"
                                }
                                else
                                {
                                    "$($config.UrlBase)/json"
                                }
                            }
                            'ipwhois'
                            {
                                if ($ip)
                                {
                                    "$($config.UrlBase)/$ip"
                                }
                                else
                                {
                                    "$($config.UrlBase)"
                                }
                            }
                        }

                        Write-Verbose "Query URL: $url"

                        # Send request
                        $response = $httpClient.GetAsync($url).GetAwaiter().GetResult()

                        if ($response.IsSuccessStatusCode)
                        {
                            $jsonContent = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                            $data = $jsonContent | ConvertFrom-Json

                            # Check for API errors
                            $hasError = $false
                            if ($svc -eq 'ip-api' -and $data.status -eq 'fail')
                            {
                                Write-Verbose "Service returned error: $($data.message)"
                                $hasError = $true
                            }
                            elseif ($svc -eq 'ipapi' -and $data.error)
                            {
                                Write-Verbose "Service returned error: $($data.reason)"
                                $hasError = $true
                            }

                            if (-not $hasError)
                            {
                                # Parse response based on service format
                                $result = [PSCustomObject]@{
                                    IP = $null
                                    City = $null
                                    Region = $null
                                    RegionCode = $null
                                    Country = $null
                                    CountryCode = $null
                                    Continent = $null
                                    Latitude = $null
                                    Longitude = $null
                                    Timezone = $null
                                    ISP = $null
                                    Organization = $null
                                    ASN = $null
                                    PostalCode = $null
                                    Service = $config.Name
                                }

                                # Map fields based on service
                                switch ($svc)
                                {
                                    'ipapi'
                                    {
                                        $result.IP = $data.ip
                                        $result.City = $data.city
                                        $result.Region = $data.region
                                        $result.RegionCode = $data.region_code
                                        $result.Country = $data.country_name
                                        $result.CountryCode = $data.country_code
                                        $result.Continent = $data.continent_code
                                        $result.Latitude = $data.latitude
                                        $result.Longitude = $data.longitude
                                        $result.Timezone = $data.timezone
                                        $result.ISP = $data.org
                                        $result.Organization = $data.org
                                        $result.ASN = $data.asn
                                        $result.PostalCode = $data.postal
                                    }
                                    'ip-api'
                                    {
                                        $result.IP = $data.query
                                        $result.City = $data.city
                                        $result.Region = $data.regionName
                                        $result.RegionCode = $data.region
                                        $result.Country = $data.country
                                        $result.CountryCode = $data.countryCode
                                        $result.Continent = $data.continent
                                        $result.Latitude = $data.lat
                                        $result.Longitude = $data.lon
                                        $result.Timezone = $data.timezone
                                        $result.ISP = $data.isp
                                        $result.Organization = $data.org
                                        $result.ASN = $data.as
                                        $result.PostalCode = $data.zip
                                    }
                                    'ipinfo'
                                    {
                                        $result.IP = $data.ip
                                        $result.City = $data.city
                                        $result.Region = $data.region
                                        $result.Country = $data.country
                                        $result.Organization = $data.org

                                        # Parse location coordinates
                                        if ($data.loc)
                                        {
                                            $coords = $data.loc -split ','
                                            if ($coords.Count -eq 2)
                                            {
                                                $result.Latitude = [decimal]$coords[0]
                                                $result.Longitude = [decimal]$coords[1]
                                            }
                                        }

                                        $result.Timezone = $data.timezone
                                        $result.PostalCode = $data.postal
                                    }
                                    'ipwhois'
                                    {
                                        $result.IP = $data.ip
                                        $result.City = $data.city
                                        $result.Region = $data.region
                                        $result.Country = $data.country
                                        $result.CountryCode = $data.country_code
                                        $result.Continent = $data.continent
                                        $result.Latitude = $data.latitude
                                        $result.Longitude = $data.longitude
                                        $result.Timezone = $data.timezone
                                        $result.ISP = $data.isp
                                        $result.Organization = $data.org
                                        $result.ASN = $data.asn
                                    }
                                }

                                # Add raw response if requested
                                if ($IncludeRaw)
                                {
                                    $result | Add-Member -NotePropertyName 'RawResponse' -NotePropertyValue $data
                                }

                                Write-Output $result
                                $success = $true
                                $response.Dispose()
                                break
                            }
                        }

                        $response.Dispose()
                    }
                    catch
                    {
                        Write-Verbose "Service $($config.Name) failed: $($_.Exception.Message)"
                        # Continue to next service
                    }
                }

                if (-not $success)
                {
                    Write-Error "Failed to resolve geolocation for IP '$(if ($ip) { $ip } else { 'current' })' from all available services"
                }
            }
            catch
            {
                Write-Error "Geolocation lookup failed for IP '$(if ($ip) { $ip } else { 'current' })': $($_.Exception.Message)"
            }
            finally
            {
                if ($httpClient)
                {
                    $httpClient.Dispose()
                }
            }
        }
    }

    end
    {
        Write-Verbose 'IP geolocation lookup completed'
    }
}
