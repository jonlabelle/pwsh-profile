function Test-DnsNameResolution
{
    <#
    .SYNOPSIS
        Tests if a DNS name can be resolved.

    .DESCRIPTION
        This function checks if a given DNS name can be resolved using the system's DNS configuration.
        It uses .NET DNS resolution methods for cross-platform compatibility (Windows, macOS, Linux).
        Returns a boolean value indicating whether resolution was successful.

    .PARAMETER Name
        The DNS name to resolve. This parameter is mandatory.

    .PARAMETER Server
        The DNS server(s) to use for resolution. NOTE: Due to cross-platform limitations with .NET DNS methods,
        custom DNS servers are currently not supported. The system's default DNS servers will be used regardless.
        You can specify servers for documentation purposes, but they won't affect resolution.

    .PARAMETER Type
        The DNS record type to query. Supported types: 'A' (IPv4), 'AAAA' (IPv6).
        Other types (CNAME, MX, etc.) will fall back to basic host resolution.
        Defaults to 'A' record.

    .EXAMPLE
        PS > Test-DnsNameResolution -Name 'google.com'
        True

        Tests whether google.com can be resolved using the system's default DNS servers.

    .EXAMPLE
        PS > Test-DnsNameResolution -Name 'google.com' -Server '8.8.8.8','8.8.4.4'
        True

        Tests whether google.com can be resolved.
        Note: Custom DNS servers are specified but system DNS will be used for cross-platform compatibility.

    .EXAMPLE
        PS > Test-DnsNameResolution -Name 'google.com' -Type 'AAAA' -Verbose
        True

        Tests whether google.com has an IPv6 (AAAA) record with verbose output.

    .OUTPUTS
        System.Boolean
        Returns $true if the DNS name can be resolved, otherwise $false.

    .LINK
        https://github.com/adbertram/Random-PowerShell-Work/blob/master/DNS/Test-DnsNameResolution.ps1

    .LINK
        https://adamtheautomator.com/resolve-dnsname/

    .LINK
        https://jonlabelle.com/snippets/view/powershell/test-dns-name-in-powershell
  #>

    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Name,

        [Parameter()]
        [ValidateScript({
                foreach ($serverAddress in $_)
                {
                    if (-not ([System.Net.IPAddress]::TryParse($serverAddress, [ref]$null)))
                    {
                        throw "Server '$serverAddress' is not a valid IP address."
                    }
                }
                return $true
            })]
        [String[]]
        $Server,

        [Parameter()]
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'NS', 'PTR', 'SOA', 'SRV', 'TXT')]
        [String]
        $Type = 'A'
    )

    begin
    {
        Write-Verbose 'Starting DNS name resolution test'
    }

    process
    {
        if ([string]::IsNullOrWhiteSpace($Name))
        {
            throw 'Parameter -Name is required.'
        }

        Write-Verbose "Testing DNS resolution for '$Name'"

        try
        {
            Write-Verbose 'Attempting DNS resolution'

            if ($Server -and $Server.Count -gt 0)
            {
                Write-Verbose "Using DNS servers: $($Server -join ', ')"
                # Note: Custom DNS servers require platform-specific implementation
                # For cross-platform compatibility, we'll use system DNS when custom servers are specified
                Write-Verbose 'Custom DNS servers specified, but using system DNS for cross-platform compatibility'
            }
            else
            {
                Write-Verbose 'Using system default DNS servers'
            }

            # Use .NET DNS resolution methods for cross-platform compatibility
            switch ($Type)
            {
                'A'
                {
                    $result = [System.Net.Dns]::GetHostAddresses($Name) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
                }
                'AAAA'
                {
                    $result = [System.Net.Dns]::GetHostAddresses($Name) | Where-Object { $_.AddressFamily -eq 'InterNetworkV6' }
                }
                default
                {
                    # For other record types (CNAME, MX, etc.), fall back to basic host resolution
                    Write-Verbose "Record type '$Type' not directly supported with .NET methods, using basic host resolution"
                    $result = [System.Net.Dns]::GetHostAddresses($Name)
                }
            }

            if ($result -and $result.Count -gt 0)
            {
                Write-Verbose "DNS resolution successful. Found $($result.Count) address(es): $($result -join ', ')"
                return $true
            }
            else
            {
                Write-Verbose 'DNS resolution returned no results'
                return $false
            }
        }
        catch [System.Net.Sockets.SocketException]
        {
            $errorMessage = $_.Exception.Message
            Write-Verbose "Socket exception during DNS resolution: $errorMessage"

            # Handle common DNS resolution failures
            if ($_.Exception.SocketErrorCode -in @('HostNotFound', 'TryAgain', 'NoRecovery'))
            {
                Write-Verbose "DNS name not found or temporary failure (SocketErrorCode: $($_.Exception.SocketErrorCode))"
                return $false
            }
            else
            {
                Write-Verbose "Unexpected socket error occurred, re-throwing: $errorMessage"
                throw $_
            }
        }
        catch
        {
            $errorMessage = $_.Exception.Message
            Write-Verbose "Exception during DNS resolution: $errorMessage"

            # Handle common "not found" errors consistently across platforms
            if ($errorMessage -match '(No such host is known)|(nodename nor servname provided)|(Name or service not known)|(Host not found)')
            {
                Write-Verbose 'DNS name not found'
                return $false
            }
            else
            {
                # Re-throw unexpected errors for troubleshooting
                Write-Verbose "Unexpected error occurred, re-throwing: $errorMessage"
                throw $_
            }
        }
    }

    end
    {
        Write-Verbose 'DNS name resolution test completed'
    }
}
