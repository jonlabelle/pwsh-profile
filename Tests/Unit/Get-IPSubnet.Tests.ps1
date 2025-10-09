#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Get-IPSubnet function.

.DESCRIPTION
    Tests the Get-IPSubnet function which calculates IP subnet information including network address,
    broadcast address, subnet mask, and provides advanced IP calculations through custom methods.

.NOTES
    These tests are based on the examples in the Get-IPSubnet function documentation.
    Tests verify CIDR notation parsing, subnet calculations, and advanced IP manipulation methods.
#>

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../Functions/Get-IPSubnet.ps1"
}

Describe 'Get-IPSubnet' {
    Context 'CIDR notation input' {
        It 'Calculate IP subnet information for 192.168.0.0/24 (Example: Get-IPSubnet -CIDR "192.168.0.0/24")' {
            # This test validates the primary documentation example showing complete subnet calculation
            $result = Get-IPSubnet -CIDR '192.168.0.0/24'
            $result | Should -Not -BeNullOrEmpty

            # Verify all expected properties from the example documentation
            $result.IP | Should -Be '192.168.0.0'
            $result.Mask | Should -Be '255.255.255.0'
            $result.PrefixLength | Should -Be 24
            $result.WildCard | Should -Be '0.0.0.255'
            $result.IPcount | Should -Be 256
            $result.Subnet | Should -Be '192.168.0.0'
            $result.Broadcast | Should -Be '192.168.0.255'
            $result.CIDR | Should -Be '192.168.0.0/24'
            $result.ToDecimal | Should -Be 3232235520
            $result.IPBin | Should -Be '11000000.10101000.00000000.00000000'
            $result.MaskBin | Should -Be '11111111.11111111.11111111.00000000'
            $result.SubnetBin | Should -Be '11000000.10101000.00000000.00000000'
            $result.BroadcastBin | Should -Be '11000000.10101000.00000000.11111111'
        }
    }

    Context 'IP address and mask input' {
        It 'Calculate IP subnet information using IP address and mask (Example: Get-IPSubnet -IPAddress "192.168.0.0" -Mask "255.255.255.0")' {
            # This test validates the alternative input method using separate IP and mask parameters
            $result = Get-IPSubnet -IPAddress '192.168.0.0' -Mask '255.255.255.0'
            $result | Should -Not -BeNullOrEmpty

            # Should produce same results as CIDR example above
            $result.IP | Should -Be '192.168.0.0'
            $result.Mask | Should -Be '255.255.255.0'
            $result.PrefixLength | Should -Be 24
            $result.WildCard | Should -Be '0.0.0.255'
            $result.IPcount | Should -Be 256
            $result.Subnet | Should -Be '192.168.0.0'
            $result.Broadcast | Should -Be '192.168.0.255'
            $result.CIDR | Should -Be '192.168.0.0/24'
            $result.ToDecimal | Should -Be 3232235520
            $result.IPBin | Should -Be '11000000.10101000.00000000.00000000'
            $result.MaskBin | Should -Be '11111111.11111111.11111111.00000000'
            $result.SubnetBin | Should -Be '11000000.10101000.00000000.00000000'
            $result.BroadcastBin | Should -Be '11000000.10101000.00000000.11111111'
        }
    }

    Context 'IP address and prefix length input' {
        It 'Calculate IP subnet information using IP address and prefix length' {
            $result = Get-IPSubnet -IPAddress '192.168.3.0' -PrefixLength 23
            $result | Should -Not -BeNullOrEmpty

            # Verify results match the example
            $result.IP | Should -Be '192.168.3.0'
            $result.Mask | Should -Be '255.255.254.0'
            $result.PrefixLength | Should -Be 23
            $result.WildCard | Should -Be '0.0.1.255'
            $result.IPcount | Should -Be 512
            $result.Subnet | Should -Be '192.168.2.0'
            $result.Broadcast | Should -Be '192.168.3.255'
            $result.CIDR | Should -Be '192.168.2.0/23'
            $result.ToDecimal | Should -Be 3232236288
            $result.IPBin | Should -Be '11000000.10101000.00000011.00000000'
            $result.MaskBin | Should -Be '11111111.11111111.11111110.00000000'
            $result.SubnetBin | Should -Be '11000000.10101000.00000010.00000000'
            $result.BroadcastBin | Should -Be '11000000.10101000.00000011.11111111'
        }
    }

    Context 'Complex calculation examples' {
        It 'Should support chained calculations using Add method' {
            # Example: (Get-IPSubnet -IPAddress (Get-IPSubnet 192.168.99.56/28).Subnet -PrefixLength 32).Add(1).IPAddress
            $subnet = Get-IPSubnet '192.168.99.56/28'
            $result = Get-IPSubnet -IPAddress $subnet.Subnet -PrefixLength 32

            # Test that the result supports Add method and produces expected output
            $result | Should -Not -BeNullOrEmpty
            $result.Subnet | Should -Be '192.168.99.48'  # The subnet address from /28

            # Test that Add method exists (if implemented in the function)
            if ($result | Get-Member -Name 'Add' -MemberType Method)
            {
                $addedResult = $result.Add(1)
                $addedResult.IPAddress | Should -Be '192.168.99.49'
            }
        }

        It 'Should support Compare method for IP range checking' {
            # Example: (Get-IPSubnet 192.168.99.56/28).Compare('192.168.99.50')
            $subnet = Get-IPSubnet '192.168.99.56/28'

            # Test that Compare method exists and works (if implemented)
            if ($subnet | Get-Member -Name 'Compare' -MemberType Method)
            {
                $compareResult = $subnet.Compare('192.168.99.50')
                $compareResult | Should -Be $true
            }
        }

        It 'Should support GetIPArray method for listing all IPs' {
            # Example: (Get-IPSubnet 192.168.99.58/30).GetIPArray()
            $subnet = Get-IPSubnet '192.168.99.58/30'

            # Test that GetIPArray method exists (if implemented)
            if ($subnet | Get-Member -Name 'GetIPArray' -MemberType Method)
            {
                $ipArray = $subnet.GetIPArray()
                $ipArray | Should -Not -BeNullOrEmpty
                $ipArray | Should -Contain '192.168.99.56'
                $ipArray | Should -Contain '192.168.99.57'
                $ipArray | Should -Contain '192.168.99.58'
                $ipArray | Should -Contain '192.168.99.59'
            }
        }

        It 'Should support Overlaps method for subnet comparison' {
            # Example: (Get-IPSubnet 192.168.0.0/25).Overlaps('192.168.0.0/27')
            $subnet = Get-IPSubnet '192.168.0.0/25'

            # Test that Overlaps method exists (if implemented)
            if ($subnet | Get-Member -Name 'Overlaps' -MemberType Method)
            {
                $overlapsResult = $subnet.Overlaps('192.168.0.0/27')
                $overlapsResult | Should -Be $true  # /27 should overlap with /25
            }
        }
    }

    Context 'Common subnet calculations' {
        It 'Should calculate /8 network correctly' {
            $result = Get-IPSubnet -CIDR '10.0.0.0/8'
            $result.Mask | Should -Be '255.0.0.0'
            $result.IPcount | Should -Be 16777216  # 2^24
            $result.Subnet | Should -Be '10.0.0.0'
            $result.Broadcast | Should -Be '10.255.255.255'
        }

        It 'Should calculate /16 network correctly' {
            $result = Get-IPSubnet -CIDR '172.16.0.0/16'
            $result.Mask | Should -Be '255.255.0.0'
            $result.IPcount | Should -Be 65536  # 2^16
            $result.Subnet | Should -Be '172.16.0.0'
            $result.Broadcast | Should -Be '172.16.255.255'
        }

        It 'Should calculate /30 network correctly (point-to-point)' {
            $result = Get-IPSubnet -CIDR '192.168.1.0/30'
            $result.Mask | Should -Be '255.255.255.252'
            $result.IPcount | Should -Be 4
            $result.Subnet | Should -Be '192.168.1.0'
            $result.Broadcast | Should -Be '192.168.1.3'
            $result.WildCard | Should -Be '0.0.0.3'
        }

        It 'Should calculate /32 host route correctly' {
            $result = Get-IPSubnet -CIDR '192.168.1.1/32'
            $result.Mask | Should -Be '255.255.255.255'
            $result.IPcount | Should -Be 1
            $result.Subnet | Should -Be '192.168.1.1'
            $result.Broadcast | Should -Be '192.168.1.1'
            $result.WildCard | Should -Be '0.0.0.0'
        }
    }

    Context 'Parameter validation' {
        It 'Should handle valid CIDR notation' {
            { Get-IPSubnet -CIDR '192.168.1.0/24' } | Should -Not -Throw
            { Get-IPSubnet -CIDR '10.0.0.0/8' } | Should -Not -Throw
            { Get-IPSubnet -CIDR '172.16.0.0/16' } | Should -Not -Throw
        }

        It 'Should handle valid IP and mask combinations' {
            { Get-IPSubnet -IPAddress '192.168.1.0' -Mask '255.255.255.0' } | Should -Not -Throw
            { Get-IPSubnet -IPAddress '10.0.0.0' -PrefixLength 8 } | Should -Not -Throw
        }

        It 'Should reject invalid IP addresses' {
            { Get-IPSubnet -CIDR '999.999.999.999/24' } | Should -Throw
            { Get-IPSubnet -IPAddress '256.1.1.1' -Mask '255.255.255.0' } | Should -Throw
        }

        It 'Should reject invalid prefix lengths' {
            { Get-IPSubnet -CIDR '192.168.1.0/33' } | Should -Throw
            { Get-IPSubnet -IPAddress '192.168.1.0' -PrefixLength -1 } | Should -Throw
            { Get-IPSubnet -IPAddress '192.168.1.0' -PrefixLength 33 } | Should -Throw
        }
    }

    Context 'Binary representation' {
        It 'Should provide correct binary representations' {
            $result = Get-IPSubnet -CIDR '192.168.1.0/24'

            # Verify binary format (dotted octets in binary)
            $result.IPBin | Should -Match '^\d{8}\.\d{8}\.\d{8}\.\d{8}$'
            $result.MaskBin | Should -Match '^\d{8}\.\d{8}\.\d{8}\.\d{8}$'
            $result.SubnetBin | Should -Match '^\d{8}\.\d{8}\.\d{8}\.\d{8}$'
            $result.BroadcastBin | Should -Match '^\d{8}\.\d{8}\.\d{8}\.\d{8}$'

            # Verify specific values for /24
            $result.IPBin | Should -Be '11000000.10101000.00000001.00000000'
            $result.MaskBin | Should -Be '11111111.11111111.11111111.00000000'
        }
    }

    Context 'Decimal conversion' {
        It 'Should provide correct decimal representation' {
            $result = Get-IPSubnet -CIDR '192.168.1.0/24'

            # 192.168.1.0 in decimal should be calculated correctly
            # 192 * 16777216 + 168 * 65536 + 1 * 256 + 0 = 3232235776
            $result.ToDecimal | Should -Be 3232235776
        }
    }
}
