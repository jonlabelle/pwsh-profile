function Test-DnsNameResolution
{
    <#
      .DESCRIPTION
          A script to test if a DNS name can be resolved.

      .EXAMPLE
          PS > .\Test-DnsNameResolution.ps1 -Name 'google.com'
          True

          Test whether google.com can be resolved.

      .EXAMPLE
          PS > .\Test-DnsNameResolution.ps1 -Name 'google.com' -Server '8.8.8.8','8.8.4.4'
          True

          Specify DNS servers to use; in this case, Google's public DNS servers.

      .LINK
          https://github.com/adbertram/Random-PowerShell-Work/blob/master/DNS/Test-DnsNameResolution.ps1

      .LINK
          https://adamtheautomator.com/resolve-dnsname/
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

    $resolvParams = @{
        'DnsOnly' = $true
        'NoHostsFile' = $true
        'ErrorAction' = 'SilentlyContinue'
        'ErrorVariable' = 'err'
        'Name' = $Name
    }

    if ($Server -and $Server.Count -gt 0)
    {
        $resolvParams += @{Server = $Server}
    }

    try
    {
        if (Resolve-DnsName @resolvParams)
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
