function Get-ReverseDns
{
    <#
    .SYNOPSIS
        Performs reverse DNS (PTR) lookups for IP addresses.

    .DESCRIPTION
        Resolves IP addresses to their associated hostnames using reverse DNS (PTR) lookups.
        Uses the .NET System.Net.Dns class for cross-platform compatibility. Supports both
        IPv4 and IPv6 addresses, pipeline input, and batch processing.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER IPAddress
        The IP address(es) to perform reverse DNS lookups on.
        Accepts both IPv4 and IPv6 addresses. Supports pipeline input.

    .EXAMPLE
        PS > Get-ReverseDns -IPAddress '8.8.8.8'

        IPAddress Hostname        Status
        --------- --------        ------
        8.8.8.8   dns.google      Resolved

        Performs a reverse DNS lookup for Google's public DNS server.

    .EXAMPLE
        PS > Get-ReverseDns -IPAddress '1.1.1.1', '8.8.8.8'

        IPAddress Hostname        Status
        --------- --------        ------
        1.1.1.1   one.one.one.one Resolved
        8.8.8.8   dns.google      Resolved

        Performs reverse DNS lookups for multiple IP addresses.

    .EXAMPLE
        PS > '1.1.1.1', '9.9.9.9' | Get-ReverseDns

        IPAddress Hostname        Status
        --------- --------        ------
        1.1.1.1   one.one.one.one Resolved
        9.9.9.9   dns9.quad9.net  Resolved

        Pipeline input of multiple IP addresses.

    .EXAMPLE
        PS > Get-ReverseDns -IPAddress '192.0.2.1'

        IPAddress  Hostname Status
        ---------  -------- ------
        192.0.2.1           NotFound

        Shows output when no PTR record exists for an IP.

    .OUTPUTS
        PSCustomObject
        Returns objects with IPAddress, Hostname, and Status properties.
        Status is 'Resolved' when a PTR record is found, 'NotFound' when no record exists,
        or 'Error' when the lookup fails.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-ReverseDns.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-ReverseDns.ps1
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateScript({
                if (-not ([System.Net.IPAddress]::TryParse($_, [ref]$null)))
                {
                    throw "'$_' is not a valid IP address."
                }
                return $true
            })]
        [String[]]
        $IPAddress
    )

    begin
    {
        Write-Verbose 'Starting reverse DNS lookups'
    }

    process
    {
        foreach ($ip in $IPAddress)
        {
            Write-Verbose "Performing reverse DNS lookup for '$ip'"

            try
            {
                $hostEntry = [System.Net.Dns]::GetHostEntry($ip)
                $hostname = $hostEntry.HostName

                # If the hostname is just the IP address echoed back, there is no PTR record
                if ($hostname -eq $ip)
                {
                    Write-Verbose "No PTR record found for '$ip' (hostname equals IP)"
                    [PSCustomObject]@{
                        IPAddress = $ip
                        Hostname = $null
                        Status = 'NotFound'
                    }
                }
                else
                {
                    Write-Verbose "Resolved '$ip' to '$hostname'"
                    [PSCustomObject]@{
                        IPAddress = $ip
                        Hostname = $hostname
                        Status = 'Resolved'
                    }
                }
            }
            catch [System.Net.Sockets.SocketException]
            {
                Write-Verbose "No PTR record found for '$ip': $($_.Exception.Message)"
                [PSCustomObject]@{
                    IPAddress = $ip
                    Hostname = $null
                    Status = 'NotFound'
                }
            }
            catch
            {
                Write-Verbose "Error resolving '$ip': $($_.Exception.Message)"
                [PSCustomObject]@{
                    IPAddress = $ip
                    Hostname = $null
                    Status = 'Error'
                }
            }
        }
    }

    end
    {
        Write-Verbose 'Reverse DNS lookups completed'
    }
}
