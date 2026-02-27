function ConvertTo-CidrNotation
{
    <#
    .SYNOPSIS
        Converts between subnet mask, CIDR prefix length, and wildcard mask formats.

    .DESCRIPTION
        Converts subnet information between three common representations:
        - Dotted-decimal subnet mask (e.g., 255.255.255.0)
        - CIDR prefix length (e.g., 24)
        - Wildcard mask (e.g., 0.0.0.255)

        Accepts any one of these formats and returns an object with all three representations.
        Useful for quick conversions when scripting firewall rules, ACLs, or network configurations.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER SubnetMask
        A dotted-decimal subnet mask to convert (e.g., '255.255.255.0').

    .PARAMETER PrefixLength
        A CIDR prefix length to convert (e.g., 24). Valid range: 0-32.

    .PARAMETER WildcardMask
        A wildcard mask to convert (e.g., '0.0.0.255').

    .EXAMPLE
        PS > ConvertTo-CidrNotation -SubnetMask '255.255.255.0'

        PrefixLength SubnetMask    WildcardMask
        ------------ ----------    ------------
                  24 255.255.255.0 0.0.0.255

        Converts a subnet mask to all formats.

    .EXAMPLE
        PS > ConvertTo-CidrNotation -PrefixLength 16

        PrefixLength SubnetMask  WildcardMask
        ------------ ----------  ------------
                  16 255.255.0.0 0.0.255.255

        Converts a CIDR prefix length to all formats.

    .EXAMPLE
        PS > ConvertTo-CidrNotation -WildcardMask '0.0.0.63'

        PrefixLength SubnetMask      WildcardMask
        ------------ ----------      ------------
                  26 255.255.255.192 0.0.0.63

        Converts a wildcard mask to all formats.

    .EXAMPLE
        PS > 8, 16, 24, 32 | ConvertTo-CidrNotation

        PrefixLength SubnetMask      WildcardMask
        ------------ ----------      ------------
                   8 255.0.0.0       0.255.255.255
                  16 255.255.0.0     0.0.255.255
                  24 255.255.255.0   0.0.0.255
                  32 255.255.255.255 0.0.0.0

        Pipeline conversion of multiple prefix lengths.

    .OUTPUTS
        PSCustomObject
        Returns an object with PrefixLength, SubnetMask, and WildcardMask properties.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/ConvertTo-CidrNotation.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/ConvertTo-CidrNotation.ps1
    #>

    [CmdletBinding(DefaultParameterSetName = 'PrefixLength')]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(ParameterSetName = 'SubnetMask', Mandatory, Position = 0)]
        [ValidateScript({
                if (-not ([System.Net.IPAddress]::TryParse($_, [ref]$null)))
                {
                    throw "'$_' is not a valid IP address format."
                }
                # Validate it is a contiguous mask
                $ipAddr = [System.Net.IPAddress]::Parse($_)
                $bytes = $ipAddr.GetAddressBytes()
                $bits = ($bytes | ForEach-Object { [System.Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
                if ($bits -notmatch '^1*0*$')
                {
                    throw "'$_' is not a valid contiguous subnet mask."
                }
                return $true
            })]
        [String]
        $SubnetMask,

        [Parameter(ParameterSetName = 'PrefixLength', Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateRange(0, 32)]
        [Int32]
        $PrefixLength,

        [Parameter(ParameterSetName = 'WildcardMask', Mandatory, Position = 0)]
        [ValidateScript({
                if (-not ([System.Net.IPAddress]::TryParse($_, [ref]$null)))
                {
                    throw "'$_' is not a valid IP address format."
                }
                # Validate it is a valid wildcard mask (inverted contiguous mask)
                $ipAddr = [System.Net.IPAddress]::Parse($_)
                $bytes = $ipAddr.GetAddressBytes()
                $bits = ($bytes | ForEach-Object { [System.Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
                if ($bits -notmatch '^0*1*$')
                {
                    throw "'$_' is not a valid contiguous wildcard mask."
                }
                return $true
            })]
        [String]
        $WildcardMask
    )

    begin
    {
        Write-Verbose 'Starting subnet notation conversion'
    }

    process
    {
        # Determine prefix length from whichever input was provided
        [Int32]$resolvedPrefix = 0

        switch ($PSCmdlet.ParameterSetName)
        {
            'SubnetMask'
            {
                Write-Verbose "Converting subnet mask '$SubnetMask' to prefix length"
                $ipAddr = [System.Net.IPAddress]::Parse($SubnetMask)
                $bytes = $ipAddr.GetAddressBytes()
                $binaryString = ($bytes | ForEach-Object { [System.Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
                $resolvedPrefix = ($binaryString.ToCharArray() | Where-Object { $_ -eq '1' } | Measure-Object).Count
            }
            'PrefixLength'
            {
                Write-Verbose "Using prefix length $PrefixLength"
                $resolvedPrefix = $PrefixLength
            }
            'WildcardMask'
            {
                Write-Verbose "Converting wildcard mask '$WildcardMask' to prefix length"
                $ipAddr = [System.Net.IPAddress]::Parse($WildcardMask)
                $bytes = $ipAddr.GetAddressBytes()
                $binaryString = ($bytes | ForEach-Object { [System.Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
                $resolvedPrefix = ($binaryString.ToCharArray() | Where-Object { $_ -eq '0' } | Measure-Object).Count
            }
        }

        # Build subnet mask from prefix length using byte-level arithmetic
        # (avoids UInt32 overflow issues with PowerShell's bitwise operators)
        $maskBytes = [byte[]]::new(4)
        $fullBytes = [System.Math]::Floor($resolvedPrefix / 8)
        $remainBits = $resolvedPrefix % 8

        for ($i = 0; $i -lt $fullBytes; $i++)
        {
            $maskBytes[$i] = [byte]255
        }
        if ($remainBits -gt 0 -and $fullBytes -lt 4)
        {
            $maskBytes[$fullBytes] = [byte](256 - [System.Math]::Pow(2, 8 - $remainBits))
        }

        $maskAddress = [System.Net.IPAddress]::new($maskBytes)

        # Build wildcard mask (inverse of subnet mask)
        $wildcardBytes = [byte[]]::new(4)
        for ($i = 0; $i -lt 4; $i++)
        {
            $wildcardBytes[$i] = [byte](255 - $maskBytes[$i])
        }
        $wildcardAddress = [System.Net.IPAddress]::new($wildcardBytes)

        Write-Verbose "Prefix: /$resolvedPrefix | Mask: $($maskAddress.ToString()) | Wildcard: $($wildcardAddress.ToString())"

        [PSCustomObject]@{
            PrefixLength = $resolvedPrefix
            SubnetMask = $maskAddress.ToString()
            WildcardMask = $wildcardAddress.ToString()
        }
    }

    end
    {
        Write-Verbose 'Subnet notation conversion completed'
    }
}
