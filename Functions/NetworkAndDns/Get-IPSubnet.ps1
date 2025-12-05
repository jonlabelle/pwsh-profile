function Get-IPSubnet
{
    <#
    .SYNOPSIS
        Calculate IP subnet information including network address, broadcast address, and subnet mask.

    .DESCRIPTION
        Calculates comprehensive IP subnet information including network address, broadcast address,
        subnet mask, wildcard mask, IP count, and binary representations. Supports multiple input
        formats including CIDR notation, IP address with subnet mask, IP address with prefix length,
        and wildcard masks.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER CIDR
        IP address and prefix length in CIDR notation (e.g., '192.168.1.0/24').
        Supports both forward slash and backslash as separators.

    .PARAMETER IPAddress
        The IP address to calculate subnet information for.
        Used in combination with Mask, PrefixLength, or WildCard parameters.

    .PARAMETER Mask
        The subnet mask in dotted decimal notation (e.g., '255.255.255.0').

    .PARAMETER PrefixLength
        The subnet prefix length (0-32). Also known as network bits or CIDR prefix.

    .PARAMETER WildCard
        The wildcard mask (inverse of subnet mask).

    .PARAMETER UsableIPs
        When specified, includes usable IP address information in the output.
        Adds UsableIPCount (excluding network and broadcast addresses) and
        FirstUsableIP/LastUsableIP properties to the result object.

        Special handling for edge cases:
        - /32 subnets (host routes): 1 usable IP (the IP itself)
        - /31 subnets (point-to-point links): 2 usable IPs per RFC 3021
        - All other subnets: Total IPs minus 2 (network and broadcast)

    .EXAMPLE
        PS > Get-IPSubnet -CIDR '192.168.0.0/24'

        IPAddress    : 192.168.0.0
        Mask         : 255.255.255.0
        PrefixLength : 24
        WildCard     : 0.0.0.255
        Subnet       : 192.168.0.0
        Broadcast    : 192.168.0.255
        CIDR         : 192.168.0.0/24
        ToDecimal    : 3232235520

        Calculate basic subnet information using CIDR notation.

    .EXAMPLE
        PS > Get-IPSubnet -IPAddress '192.168.0.0' -Mask '255.255.255.0'

        IPAddress    : 192.168.0.0
        Mask         : 255.255.255.0
        PrefixLength : 24
        WildCard     : 0.0.0.255
        Subnet       : 192.168.0.0
        Broadcast    : 192.168.0.255
        CIDR         : 192.168.0.0/24
        ToDecimal    : 3232235520

        Calculate subnet information using IP address and subnet mask.

    .EXAMPLE
        PS > Get-IPSubnet -IPAddress '192.168.3.0' -PrefixLength 23

        IPAddress    : 192.168.3.0
        Mask         : 255.255.254.0
        PrefixLength : 23
        WildCard     : 0.0.1.255
        Subnet       : 192.168.2.0
        Broadcast    : 192.168.3.255
        CIDR         : 192.168.2.0/23
        ToDecimal    : 3232236288

        Calculate subnet information using IP address and prefix length.

    .EXAMPLE
        PS > Get-IPSubnet -IPAddress '10.0.0.0' -PrefixLength 8

        IPAddress    : 10.0.0.0
        Mask         : 255.0.0.0
        PrefixLength : 8
        WildCard     : 0.255.255.255
        Subnet       : 10.0.0.0
        Broadcast    : 10.255.255.255
        CIDR         : 10.0.0.0/8
        ToDecimal    : 167772160

        Calculate Class A network information.

    .EXAMPLE
        PS > Get-IPSubnet -IPAddress '172.16.0.0' -PrefixLength 16

        IPAddress    : 172.16.0.0
        Mask         : 255.255.0.0
        PrefixLength : 16
        WildCard     : 0.0.255.255
        Subnet       : 172.16.0.0
        Broadcast    : 172.16.255.255
        CIDR         : 172.16.0.0/16
        ToDecimal    : 2886729728

        Calculate Class B network information.

    .EXAMPLE
        PS > Get-IPSubnet -IPAddress '192.168.1.0' -PrefixLength 30

        IPAddress    : 192.168.1.0
        Mask         : 255.255.255.252
        PrefixLength : 30
        WildCard     : 0.0.0.3
        Subnet       : 192.168.1.0
        Broadcast    : 192.168.1.3
        CIDR         : 192.168.1.0/30
        ToDecimal    : 3232235776

        Calculate point-to-point link subnet (4 total IPs, 2 usable).

    .EXAMPLE
        PS > Get-IPSubnet -IPAddress '192.168.1.1' -PrefixLength 32

        IPAddress    : 192.168.1.1
        Mask         : 255.255.255.255
        PrefixLength : 32
        WildCard     : 0.0.0.0
        Subnet       : 192.168.1.1
        Broadcast    : 192.168.1.1
        CIDR         : 192.168.1.1/32
        ToDecimal    : 3232235777

        Calculate host route (single IP address).

    .EXAMPLE
        PS > $subnet = Get-IPSubnet -CIDR '192.168.1.0/24'
        PS > $subnet.IPcount
        256

        Access the IP count property to see total addresses in subnet.

    .EXAMPLE
        PS > $subnet = Get-IPSubnet -CIDR '192.168.1.0/24'
        PS > $subnet.IPBin
        11000000.10101000.00000001.00000000

        View the binary representation of the IP address.

    .EXAMPLE
        PS > $result = Get-IPSubnet -CIDR '172.16.10.0/28'
        PS > $result | Select-Object IPBin, MaskBin, SubnetBin, BroadcastBin

        IPBin       : 10101100.00010000.00001010.00000000
        MaskBin     : 11111111.11111111.11111111.11110000
        SubnetBin   : 10101100.00010000.00001010.00000000
        BroadcastBin: 10101100.00010000.00001010.00001111

        Display binary representations and decimal conversion for detailed subnet analysis.

    .EXAMPLE
        PS > $results = @('192.168.1.0/24', '10.0.0.0/8', '172.16.0.0/16') | ForEach-Object { Get-IPSubnet -CIDR $_ }
        PS > $results | Select-Object CIDR, IPcount, Subnet, Broadcast

        CIDR            IPcount Subnet      Broadcast
        ----            ------- ------      ---------
        192.168.1.0/24      256 192.168.1.0 192.168.1.255
        10.0.0.0/8     16777216 10.0.0.0    10.255.255.255
        172.16.0.0/16     65536 172.16.0.0  172.16.255.255

        Calculate subnet information for multiple networks.

    .EXAMPLE
        PS > Get-IPSubnet -CIDR '192.168.100.50/28' | Select-Object Subnet, Broadcast, IPcount

        Subnet      Broadcast       IPcount
        ------      ---------       -------
        192.168.100.48 192.168.100.63      16

        Find which subnet a specific IP address belongs to.

    .EXAMPLE
        PS > $subnets = @('192.168.1.0/25', '192.168.1.128/25')
        PS > $subnets | ForEach-Object { Get-IPSubnet -CIDR $_ } | Format-Table CIDR, IPcount, Subnet, Broadcast

        CIDR              IPcount Subnet         Broadcast
        ----              ------- ------         ---------
        192.168.1.0/25        128 192.168.1.0    192.168.1.127
        192.168.1.128/25      128 192.168.1.128  192.168.1.255

        Calculate VLSM (Variable Length Subnet Mask) subnets.

    .EXAMPLE
        PS > $large = Get-IPSubnet -CIDR '10.0.0.0/8'
        PS > "Network: {0}, Usable IPs: {1:N0}" -f $large.CIDR, ($large.IPcount - 2)
        Network: 10.0.0.0/8, Usable IPs: 16,777,214

        Calculate usable IP addresses (excluding network and broadcast).

    .EXAMPLE
        PS > Get-IPSubnet -CIDR '192.168.1.0/24' -UsableIPs

        IPAddress      : 192.168.1.0
        Mask           : 255.255.255.0
        PrefixLength   : 24
        WildCard       : 0.0.0.255
        Subnet         : 192.168.1.0
        Broadcast      : 192.168.1.255
        CIDR           : 192.168.1.0/24
        ToDecimal      : 3232235776
        UsableIPCount  : 254
        FirstUsableIP  : 192.168.1.1
        LastUsableIP   : 192.168.1.254

        Calculate subnet with usable IP information (excludes network and broadcast).

    .EXAMPLE
        PS > Get-IPSubnet -CIDR '192.168.1.0/30' -UsableIPs | Select-Object CIDR, IPcount, UsableIPCount, FirstUsableIP, LastUsableIP

        CIDR           IPcount UsableIPCount FirstUsableIP LastUsableIP
        ----           ------- ------------- ------------- ------------
        192.168.1.0/30       4             2 192.168.1.1   192.168.1.2

        Point-to-point subnet showing 2 usable IPs out of 4 total.

    .EXAMPLE
        PS > Get-IPSubnet -CIDR '192.168.1.1/32' -UsableIPs

        IPAddress      : 192.168.1.1
        Mask           : 255.255.255.255
        PrefixLength   : 32
        WildCard       : 0.0.0.0
        Subnet         : 192.168.1.1
        Broadcast      : 192.168.1.1
        CIDR           : 192.168.1.1/32
        ToDecimal      : 3232235777
        UsableIPCount  : 1
        FirstUsableIP  : 192.168.1.1
        LastUsableIP   : 192.168.1.1

        Host route showing the single usable IP address.

    .EXAMPLE
        PS > Get-IPSubnet -CIDR '192.168.1.0/31' -UsableIPs

        IPAddress      : 192.168.1.0
        Mask           : 255.255.255.254
        PrefixLength   : 31
        WildCard       : 0.0.0.1
        Subnet         : 192.168.1.0
        Broadcast      : 192.168.1.1
        CIDR           : 192.168.1.0/31
        ToDecimal      : 3232235776
        UsableIPCount  : 2
        FirstUsableIP  : 192.168.1.0
        LastUsableIP   : 192.168.1.1

        Point-to-point link (RFC 3021) showing both IPs are usable.

    .EXAMPLE
        PS > @('/24', '/25', '/26', '/27', '/28', '/29', '/30') | ForEach-Object { Get-IPSubnet -CIDR "192.168.1.0$_" -UsableIPs } | Select-Object PrefixLength, IPcount, UsableIPCount

        PrefixLength IPcount UsableIPCount
        ------------ ------- -------------
                  24     256           254
                  25     128           126
                  26      64            62
                  27      32            30
                  28      16            14
                  29       8             6
                  30       4             2

        Compare total vs usable IP counts across common subnet sizes.

    .EXAMPLE
        PS > Get-IPSubnet -IPAddress '192.168.1.100' -WildCard '0.0.0.31'

        IPAddress    : 192.168.1.100
        Mask         : 255.255.255.224
        PrefixLength : 27
        WildCard     : 0.0.0.31
        Subnet       : 192.168.1.96
        Broadcast    : 192.168.1.127
        CIDR         : 192.168.1.96/27
        ToDecimal    : 3232235876

        Calculate subnet using wildcard mask (useful for ACLs and route maps).

    .OUTPUTS
        NetWork.IPCalcResult
        Returns a custom object with subnet calculation results including:
        - IPAddress: Original IP address
        - Mask: Subnet mask in dotted decimal notation
        - PrefixLength: CIDR prefix length (network bits)
        - WildCard: Wildcard mask (inverse of subnet mask)
        - IPcount: Total number of IP addresses in subnet
        - Subnet: Network address
        - Broadcast: Broadcast address
        - CIDR: CIDR notation (network/prefix)
        - ToDecimal: IP address in decimal format
        - IPBin: Binary representation of IP address (dotted)
        - MaskBin: Binary representation of subnet mask (dotted)
        - SubnetBin: Binary representation of network address (dotted)
        - BroadcastBin: Binary representation of broadcast address (dotted)

        When -UsableIPs is specified, additional properties are included:
        - UsableIPCount: Number of usable IP addresses (excluding network/broadcast)
        - FirstUsableIP: First usable IP address in the subnet
        - LastUsableIP: Last usable IP address in the subnet

    .LINK
        https://jonlabelle.com/snippets/view/markdown/ipv4-cidr-notation-reference-guide

    .LINK
        https://jonlabelle.com/snippets/view/powershell/ip-subnet-calculator

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-IPSubnet.ps1

    .NOTES
        Binary Representations:
        All binary values are displayed in dotted octet format (e.g., 11000000.10101000.00000001.00000000)
        for easy reading and comparison with subnet masks.

        Decimal Conversion:
        The ToDecimal property contains the 32-bit decimal representation of the IP address,
        useful for IP address arithmetic and sorting operations.

        Network Planning:
        - IPcount includes all addresses (network, broadcast, and hosts)
        - Standard subnets: Usable IPs = IPcount - 2 (subtract network and broadcast)
        - /30 subnets: 2 usable IPs (common for point-to-point links)
        - /31 subnets: 2 usable IPs per RFC 3021 (no network/broadcast concept)
        - /32 subnets: 1 usable IP (host route, network=broadcast=usable)
        - Use -UsableIPs switch for automatic usable IP calculations

        Original Author: saw-friendship@yandex.ru
        Description: IP Subnet Calculator WildCard CIDR
        URL: https://sawfriendship.wordpress.com/

        Enhanced by: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-IPSubnet.ps1
    #>
    [CmdletBinding(DefaultParameterSetName = 'CIDR')]
    [OutputType('NetWork.IPCalcResult')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'CIDR', ValueFromPipelineByPropertyName = $true, Position = 0)]
        [ValidateScript({ $array = ($_ -split '\\|\/'); ($array[0] -as [IPAddress]).AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and [string[]](0..32) -contains $array[1] })]
        [Alias('DestinationPrefix')]
        [string]$CIDR,

        [parameter(ParameterSetName = 'Mask')][parameter(ParameterSetName = ('PrefixLength'), ValueFromPipelineByPropertyName = $true)][parameter(ParameterSetName = ('WildCard'))]
        [ValidateScript({ ($_ -as [IPAddress]).AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork })]
        [Alias('IP')]
        [IPAddress]$IPAddress,

        [Parameter(Mandatory = $true, ParameterSetName = 'Mask')]
        [IPAddress]$Mask,

        [parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'PrefixLength')]
        [ValidateRange(0, 32)]
        [int]$PrefixLength,

        [parameter(Mandatory = $true, ParameterSetName = 'WildCard')]
        [IPAddress]$WildCard,

        [Parameter()]
        [switch]$UsableIPs
    )

    process
    {
        if ($CIDR)
        {
            [IPAddress]$IPAddress = ($CIDR -split '\\|\/')[0]
            [int]$PrefixLength = ($CIDR -split '\\|\/')[1]
            [IPAddress]$Mask = [IPAddress]([string](4gb - ([System.Math]::Pow(2, (32 - $PrefixLength)))))
        }

        if ($PrefixLength -and !$Mask)
        {
            [IPAddress]$Mask = [IPAddress]([string](4gb - ([System.Math]::Pow(2, (32 - $PrefixLength)))))
        }

        if ($WildCard)
        {
            [IPAddress]$Mask = $WildCard.GetAddressBytes().ForEach({ 255 - $_ }) -join '.'
        }

        if (!$PrefixLength -and $Mask)
        {
            $PrefixLength = 32 - ($Mask.GetAddressBytes().ForEach({ [System.Math]::Log((256 - $_), 2) }) | Measure-Object -Sum).Sum
        }

        [int[]]$splitIPAddress = $IPAddress.GetAddressBytes()
        [int64]$toDecimal = $splitIPAddress[0] * 16mb + $splitIPAddress[1] * 64kb + $splitIPAddress[2] * 256 + $splitIPAddress[3]

        [int[]]$splitMask = $Mask.GetAddressBytes()
        $ipBin = ($splitIPAddress.ForEach({ [System.Convert]::ToString($_, 2).PadLeft(8, '0') })) -join '.'
        $maskBin = ($splitMask.ForEach({ [System.Convert]::ToString($_, 2).PadLeft(8, '0') })) -join '.'

        if ((($maskBin -replace '\.').TrimStart('1').Contains('1')) -and (!$WildCard))
        {
            Write-Warning 'Mask Length error, you can try put WildCard'; break
        }
        if (!$WildCard)
        {
            [IPAddress]$WildCard = $splitMask.ForEach({ 255 - $_ }) -join '.'
        }
        if ($WildCard)
        {
            [int[]]$splitWildCard = $WildCard.GetAddressBytes()
        }

        [IPAddress]$subnet = $IPAddress.Address -band $Mask.Address
        [int[]]$splitSubnet = $subnet.GetAddressBytes()
        [string]$subnetBin = $splitSubnet.ForEach({ [System.Convert]::ToString($_, 2).PadLeft(8, '0') }) -join '.'
        [IPAddress]$broadcast = @(0..3).ForEach({ [int]($splitSubnet[$_]) + [int]($splitWildCard[$_]) }) -join '.'
        [int[]]$splitBroadcast = $broadcast.GetAddressBytes()
        [string]$broadcastBin = $splitBroadcast.ForEach({ [System.Convert]::ToString($_, 2).PadLeft(8, '0') }) -join '.'
        [string]$CIDR = "$($subnet.IPAddressToString)/$PrefixLength"
        [int64]$ipCount = [System.Math]::Pow(2, $(32 - $PrefixLength))

        # Calculate usable IP information if requested
        $usableIPCount = $null
        $firstUsableIP = $null
        $lastUsableIP = $null

        if ($UsableIPs)
        {
            if ($PrefixLength -eq 32)
            {
                # /32 subnet (host route) - the IP itself is the only usable IP
                $usableIPCount = 1
                $firstUsableIP = $IPAddress
                $lastUsableIP = $IPAddress
            }
            elseif ($PrefixLength -eq 31)
            {
                # /31 subnet (RFC 3021 point-to-point) - both IPs are usable, no network/broadcast
                $usableIPCount = 2
                $firstUsableIP = $subnet
                $lastUsableIP = $broadcast
            }
            else
            {
                # Standard subnets - exclude network (first) and broadcast (last) addresses
                $usableIPCount = $ipCount - 2
                if ($usableIPCount -gt 0)
                {
                    # Calculate first usable IP (network + 1)
                    $subnetBytes = $subnet.GetAddressBytes()
                    $firstUsableBytes = $subnetBytes.Clone()
                    $firstUsableBytes[3] = $firstUsableBytes[3] + 1
                    $firstUsableIP = [IPAddress]($firstUsableBytes -join '.')

                    # Calculate last usable IP (broadcast - 1)
                    $broadcastBytes = $broadcast.GetAddressBytes()
                    $lastUsableBytes = $broadcastBytes.Clone()
                    $lastUsableBytes[3] = $lastUsableBytes[3] - 1
                    $lastUsableIP = [IPAddress]($lastUsableBytes -join '.')
                }
                else
                {
                    # Edge case: no usable IPs (shouldn't happen with valid subnets)
                    $firstUsableIP = $null
                    $lastUsableIP = $null
                }
            }
        }

        $object = [PSCustomObject][Ordered]@{
            IPAddress = $IPAddress.IPAddressToString
            Mask = $Mask.IPAddressToString
            PrefixLength = $PrefixLength
            WildCard = $WildCard.IPAddressToString
            IPcount = $ipCount
            Subnet = $subnet
            Broadcast = $broadcast
            CIDR = $CIDR
            ToDecimal = $toDecimal
            IPBin = $ipBin
            MaskBin = $maskBin
            SubnetBin = $subnetBin
            BroadcastBin = $broadcastBin
            PSTypeName = 'NetWork.IPCalcResult'
        }

        # Add usable IP properties if requested
        if ($UsableIPs)
        {
            Add-Member -InputObject $object -NotePropertyName 'UsableIPCount' -NotePropertyValue $usableIPCount
            Add-Member -InputObject $object -NotePropertyName 'FirstUsableIP' -NotePropertyValue $firstUsableIP
            Add-Member -InputObject $object -NotePropertyName 'LastUsableIP' -NotePropertyValue $lastUsableIP
        }

        # Set default display properties based on whether UsableIPs was requested
        if ($UsableIPs)
        {
            [string[]]$defaultProperties = @('IPAddress', 'Mask', 'PrefixLength', 'WildCard', 'Subnet', 'Broadcast', 'CIDR', 'ToDecimal', 'UsableIPCount', 'FirstUsableIP', 'LastUsableIP')
        }
        else
        {
            [string[]]$defaultProperties = @('IPAddress', 'Mask', 'PrefixLength', 'WildCard', 'Subnet', 'Broadcast', 'CIDR', 'ToDecimal')
        }

        Add-Member -InputObject $object -MemberType AliasProperty -Name IP -Value IPAddress

        Add-Member -InputObject $object -MemberType:ScriptMethod -Force -Name ToString -Value {
            $This.CIDR
        }

        $psPropertySet = New-Object -TypeName System.Management.Automation.PSPropertySet -ArgumentList @('DefaultDisplayPropertySet', $defaultProperties)
        $psStandardMembers = [System.Management.Automation.PSMemberInfo[]]$psPropertySet
        Add-Member -InputObject $object -MemberType MemberSet -Name PSStandardMembers -Value $psStandardMembers

        Write-Output -InputObject $object
    }
}
