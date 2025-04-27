function Test-DnsNameResolution
{
    <#
    .SYNOPSIS
        Tests if a DNS name can be resolved.

    .DESCRIPTION
        This function checks if a given DNS name can be resolved using the specified DNS servers.
        It returns a boolean value indicating whether resolution was successful.

    .PARAMETER Name
        The DNS name to resolve. This parameter is mandatory.

    .PARAMETER Server
        The DNS server(s) to use for resolution. If not specified, the system's default DNS servers are used.
        You can specify multiple DNS servers as an array.

    .EXAMPLE
        PS > Test-DnsNameResolution -Name 'google.com'
        True

        Tests whether google.com can be resolved using the system's default DNS servers.

    .EXAMPLE
        PS > Test-DnsNameResolution -Name 'google.com' -Server '8.8.8.8','8.8.4.4'
        True

        Tests whether google.com can be resolved using Google's public DNS servers (8.8.8.8 and 8.8.4.4).

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
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Name,

        [Parameter()]
        [String[]]
        $Server
        # $Server = @('8.8.8.8','8.8.4.4') # Google DNS server
    )

    $resolveParams = @{
        'DnsOnly' = $true
        'NoHostsFile' = $true
        'ErrorAction' = 'SilentlyContinue'
        'ErrorVariable' = 'err'
        'Name' = $Name
    }

    if ($Server -and $Server.Count -gt 0)
    {
        $resolveParams += @{Server = $Server}
    }

    try
    {
        if (Resolve-DnsName @resolveParams)
        {
            $true
        }
        elseif ($err -and ($err.Exception.Message -match '(DNS name does not exist)|(No such host is known)'))
        {
            $false
        }
        else
        {
            throw $err
        }
    }
    catch
    {
        if ($_.Exception.Message -match 'No such host is known')
        {
            $false
        }
        else
        {
            throw $_
        }
    }
}
