#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Get-IPSubnet function.

.DESCRIPTION
    Tests the Get-IPSubnet function which calculates IP subnet information including network address,
    broadcast address, subnet mask, and binary representations. Tests verify CIDR notation parsing,
    subnet calculations, and proper handling of various subnet sizes and input formats.

.NOTES
    These tests verify core subnet calculation functionality following project conventions
    with comprehensive examples covering common networking scenarios.
#>BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Get-IPSubnet.ps1"
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

    Context 'Additional subnet examples' {
        It 'Should calculate /8 network (Class A) correctly' {
            $result = Get-IPSubnet -CIDR '10.0.0.0/8'
            $result.Mask | Should -Be '255.0.0.0'
            $result.IPcount | Should -Be 16777216  # 2^24
            $result.Subnet | Should -Be '10.0.0.0'
            $result.Broadcast | Should -Be '10.255.255.255'
            $result.WildCard | Should -Be '0.255.255.255'
        }

        It 'Should calculate /16 network (Class B) correctly' {
            $result = Get-IPSubnet -CIDR '172.16.0.0/16'
            $result.Mask | Should -Be '255.255.0.0'
            $result.IPcount | Should -Be 65536  # 2^16
            $result.Subnet | Should -Be '172.16.0.0'
            $result.Broadcast | Should -Be '172.16.255.255'
            $result.WildCard | Should -Be '0.0.255.255'
        }

        It 'Should calculate /28 network correctly' {
            $result = Get-IPSubnet -CIDR '192.168.1.16/28'
            $result.Mask | Should -Be '255.255.255.240'
            $result.IPcount | Should -Be 16
            $result.Subnet | Should -Be '192.168.1.16'
            $result.Broadcast | Should -Be '192.168.1.31'
            $result.WildCard | Should -Be '0.0.0.15'
        }

        It 'Should handle subnet calculation for arbitrary IP in range' {
            # Test that any IP in the range produces the same subnet
            $result1 = Get-IPSubnet -CIDR '192.168.100.50/28'
            $result2 = Get-IPSubnet -CIDR '192.168.100.60/28'

            # Both should resolve to the same subnet
            $result1.Subnet | Should -Be '192.168.100.48'
            $result2.Subnet | Should -Be '192.168.100.48'
            $result1.Broadcast | Should -Be '192.168.100.63'
            $result2.Broadcast | Should -Be '192.168.100.63'
        }

        It 'Should calculate VLSM subnets correctly' {
            $subnet1 = Get-IPSubnet -CIDR '192.168.1.0/25'
            $subnet2 = Get-IPSubnet -CIDR '192.168.1.128/25'

            # First half
            $subnet1.Subnet | Should -Be '192.168.1.0'
            $subnet1.Broadcast | Should -Be '192.168.1.127'
            $subnet1.IPcount | Should -Be 128

            # Second half
            $subnet2.Subnet | Should -Be '192.168.1.128'
            $subnet2.Broadcast | Should -Be '192.168.1.255'
            $subnet2.IPcount | Should -Be 128
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

    Context 'UsableIPs functionality' {
        It 'Calculate usable IPs for standard /24 subnet' {
            # Standard subnet should exclude network and broadcast addresses
            $result = Get-IPSubnet -CIDR '192.168.1.0/24' -UsableIPs
            $result | Should -Not -BeNullOrEmpty

            $result.IPcount | Should -Be 256
            $result.UsableIPCount | Should -Be 254
            $result.FirstUsableIP | Should -Be '192.168.1.1'
            $result.LastUsableIP | Should -Be '192.168.1.254'
            $result.Subnet | Should -Be '192.168.1.0'
            $result.Broadcast | Should -Be '192.168.1.255'
        }

        It 'Calculate usable IPs for point-to-point /30 subnet' {
            # /30 subnet with 4 total IPs should have 2 usable IPs
            $result = Get-IPSubnet -CIDR '192.168.1.0/30' -UsableIPs
            $result | Should -Not -BeNullOrEmpty

            $result.IPcount | Should -Be 4
            $result.UsableIPCount | Should -Be 2
            $result.FirstUsableIP | Should -Be '192.168.1.1'
            $result.LastUsableIP | Should -Be '192.168.1.2'
            $result.Subnet | Should -Be '192.168.1.0'
            $result.Broadcast | Should -Be '192.168.1.3'
        }

        It 'Calculate usable IPs for /31 subnet (RFC 3021 point-to-point)' {
            # /31 subnet should have both IPs usable (no network/broadcast concept)
            $result = Get-IPSubnet -CIDR '192.168.1.0/31' -UsableIPs
            $result | Should -Not -BeNullOrEmpty

            $result.IPcount | Should -Be 2
            $result.UsableIPCount | Should -Be 2
            $result.FirstUsableIP | Should -Be '192.168.1.0'
            $result.LastUsableIP | Should -Be '192.168.1.1'
            $result.Subnet | Should -Be '192.168.1.0'
            $result.Broadcast | Should -Be '192.168.1.1'
        }

        It 'Calculate usable IPs for /32 host route' {
            # /32 subnet should have 1 usable IP (the IP itself)
            $result = Get-IPSubnet -CIDR '192.168.1.100/32' -UsableIPs
            $result | Should -Not -BeNullOrEmpty

            $result.IPcount | Should -Be 1
            $result.UsableIPCount | Should -Be 1
            $result.FirstUsableIP | Should -Be '192.168.1.100'
            $result.LastUsableIP | Should -Be '192.168.1.100'
            $result.Subnet | Should -Be '192.168.1.100'
            $result.Broadcast | Should -Be '192.168.1.100'
        }

        It 'Calculate usable IPs for small /28 subnet' {
            # /28 subnet with 16 total IPs should have 14 usable IPs
            $result = Get-IPSubnet -CIDR '192.168.1.64/28' -UsableIPs
            $result | Should -Not -BeNullOrEmpty

            $result.IPcount | Should -Be 16
            $result.UsableIPCount | Should -Be 14
            $result.FirstUsableIP | Should -Be '192.168.1.65'
            $result.LastUsableIP | Should -Be '192.168.1.78'
            $result.Subnet | Should -Be '192.168.1.64'
            $result.Broadcast | Should -Be '192.168.1.79'
        }

        It 'Calculate usable IPs for large /16 subnet' {
            # /16 subnet should properly calculate large usable IP count
            $result = Get-IPSubnet -CIDR '172.16.0.0/16' -UsableIPs
            $result | Should -Not -BeNullOrEmpty

            $result.IPcount | Should -Be 65536
            $result.UsableIPCount | Should -Be 65534
            $result.FirstUsableIP | Should -Be '172.16.0.1'
            $result.LastUsableIP | Should -Be '172.16.255.254'
            $result.Subnet | Should -Be '172.16.0.0'
            $result.Broadcast | Should -Be '172.16.255.255'
        }

        It 'Should not include usable IP properties when UsableIPs switch is not used' {
            # Without UsableIPs switch, should not have usable IP properties
            $result = Get-IPSubnet -CIDR '192.168.1.0/24'
            $result | Should -Not -BeNullOrEmpty

            $result.PSObject.Properties.Name | Should -Not -Contain 'UsableIPCount'
            $result.PSObject.Properties.Name | Should -Not -Contain 'FirstUsableIP'
            $result.PSObject.Properties.Name | Should -Not -Contain 'LastUsableIP'
        }

        It 'Should include usable IP properties when UsableIPs is used' {
            # With UsableIPs switch, should have usable IP properties
            $result = Get-IPSubnet -CIDR '192.168.1.0/24' -UsableIPs
            $result | Should -Not -BeNullOrEmpty

            $result.PSObject.Properties.Name | Should -Contain 'UsableIPCount'
            $result.PSObject.Properties.Name | Should -Contain 'FirstUsableIP'
            $result.PSObject.Properties.Name | Should -Contain 'LastUsableIP'

            # Verify properties have correct values
            $result.UsableIPCount | Should -Be 254
            $result.FirstUsableIP | Should -Be '192.168.1.1'
            $result.LastUsableIP | Should -Be '192.168.1.254'
        }

        It 'Calculate usable IPs with IP and Mask parameters' {
            # Should work with alternative parameter sets
            $result = Get-IPSubnet -IPAddress '10.0.0.0' -Mask '255.255.255.0' -UsableIPs
            $result | Should -Not -BeNullOrEmpty

            $result.IPcount | Should -Be 256
            $result.UsableIPCount | Should -Be 254
            $result.FirstUsableIP | Should -Be '10.0.0.1'
            $result.LastUsableIP | Should -Be '10.0.0.254'
        }

        It 'Calculate usable IPs with IP and PrefixLength parameters' {
            # Should work with IP and PrefixLength parameter set
            $result = Get-IPSubnet -IPAddress '172.16.5.100' -PrefixLength 24 -UsableIPs
            $result | Should -Not -BeNullOrEmpty

            $result.IPcount | Should -Be 256
            $result.UsableIPCount | Should -Be 254
            $result.FirstUsableIP | Should -Be '172.16.5.1'
            $result.LastUsableIP | Should -Be '172.16.5.254'
            $result.Subnet | Should -Be '172.16.5.0'
            $result.Broadcast | Should -Be '172.16.5.255'
        }
    }

    Context 'UsableIPs edge cases' {
        It 'Calculate usable IPs for /29 subnet (8 total IPs)' {
            # Small subnet to verify calculation accuracy
            $result = Get-IPSubnet -CIDR '192.168.1.8/29' -UsableIPs
            $result | Should -Not -BeNullOrEmpty

            $result.IPcount | Should -Be 8
            $result.UsableIPCount | Should -Be 6
            $result.FirstUsableIP | Should -Be '192.168.1.9'
            $result.LastUsableIP | Should -Be '192.168.1.14'
            $result.Subnet | Should -Be '192.168.1.8'
            $result.Broadcast | Should -Be '192.168.1.15'
        }

        It 'Verify /31 and /30 subnets have different usable IP logic' {
            # Compare /30 (standard) vs /31 (RFC 3021) behavior
            $result30 = Get-IPSubnet -CIDR '192.168.1.0/30' -UsableIPs
            $result31 = Get-IPSubnet -CIDR '192.168.1.0/31' -UsableIPs

            # /30: 4 total, 2 usable (excludes network/broadcast)
            $result30.IPcount | Should -Be 4
            $result30.UsableIPCount | Should -Be 2
            $result30.FirstUsableIP | Should -Be '192.168.1.1'
            $result30.LastUsableIP | Should -Be '192.168.1.2'

            # /31: 2 total, 2 usable (both IPs usable)
            $result31.IPcount | Should -Be 2
            $result31.UsableIPCount | Should -Be 2
            $result31.FirstUsableIP | Should -Be '192.168.1.0'
            $result31.LastUsableIP | Should -Be '192.168.1.1'
        }

        It 'Verify multiple /32 host routes have correct usable IP calculations' {
            # Test different /32 addresses
            $addresses = @('10.1.1.1', '192.168.100.50', '172.16.254.1')

            foreach ($addr in $addresses)
            {
                $result = Get-IPSubnet -CIDR "$addr/32" -UsableIPs
                $result.IPcount | Should -Be 1
                $result.UsableIPCount | Should -Be 1
                $result.FirstUsableIP | Should -Be $addr
                $result.LastUsableIP | Should -Be $addr
                $result.Subnet | Should -Be $addr
                $result.Broadcast | Should -Be $addr
            }
        }
    }
}
