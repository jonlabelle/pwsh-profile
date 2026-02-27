#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for ConvertTo-CidrNotation function.

.DESCRIPTION
    Tests the ConvertTo-CidrNotation function which converts between subnet mask,
    CIDR prefix length, and wildcard mask formats.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/NetworkAndDns/ConvertTo-CidrNotation.ps1"
}

Describe 'ConvertTo-CidrNotation' {
    Context 'Conversion from PrefixLength' {
        It 'Should convert /24 correctly' {
            $result = ConvertTo-CidrNotation -PrefixLength 24
            $result.PrefixLength | Should -Be 24
            $result.SubnetMask | Should -Be '255.255.255.0'
            $result.WildcardMask | Should -Be '0.0.0.255'
        }

        It 'Should convert /16 correctly' {
            $result = ConvertTo-CidrNotation -PrefixLength 16
            $result.PrefixLength | Should -Be 16
            $result.SubnetMask | Should -Be '255.255.0.0'
            $result.WildcardMask | Should -Be '0.0.255.255'
        }

        It 'Should convert /8 correctly' {
            $result = ConvertTo-CidrNotation -PrefixLength 8
            $result.PrefixLength | Should -Be 8
            $result.SubnetMask | Should -Be '255.0.0.0'
            $result.WildcardMask | Should -Be '0.255.255.255'
        }

        It 'Should convert /32 (host route) correctly' {
            $result = ConvertTo-CidrNotation -PrefixLength 32
            $result.PrefixLength | Should -Be 32
            $result.SubnetMask | Should -Be '255.255.255.255'
            $result.WildcardMask | Should -Be '0.0.0.0'
        }

        It 'Should convert /0 (default route) correctly' {
            $result = ConvertTo-CidrNotation -PrefixLength 0
            $result.PrefixLength | Should -Be 0
            $result.SubnetMask | Should -Be '0.0.0.0'
            $result.WildcardMask | Should -Be '255.255.255.255'
        }

        It 'Should convert /26 correctly' {
            $result = ConvertTo-CidrNotation -PrefixLength 26
            $result.PrefixLength | Should -Be 26
            $result.SubnetMask | Should -Be '255.255.255.192'
            $result.WildcardMask | Should -Be '0.0.0.63'
        }
    }

    Context 'Conversion from SubnetMask' {
        It 'Should convert 255.255.255.0 to /24' {
            $result = ConvertTo-CidrNotation -SubnetMask '255.255.255.0'
            $result.PrefixLength | Should -Be 24
            $result.SubnetMask | Should -Be '255.255.255.0'
            $result.WildcardMask | Should -Be '0.0.0.255'
        }

        It 'Should convert 255.255.0.0 to /16' {
            $result = ConvertTo-CidrNotation -SubnetMask '255.255.0.0'
            $result.PrefixLength | Should -Be 16
        }

        It 'Should convert 255.255.255.252 to /30' {
            $result = ConvertTo-CidrNotation -SubnetMask '255.255.255.252'
            $result.PrefixLength | Should -Be 30
            $result.WildcardMask | Should -Be '0.0.0.3'
        }

        It 'Should reject non-contiguous subnet masks' {
            { ConvertTo-CidrNotation -SubnetMask '255.0.255.0' } | Should -Throw
        }
    }

    Context 'Conversion from WildcardMask' {
        It 'Should convert 0.0.0.255 to /24' {
            $result = ConvertTo-CidrNotation -WildcardMask '0.0.0.255'
            $result.PrefixLength | Should -Be 24
            $result.SubnetMask | Should -Be '255.255.255.0'
        }

        It 'Should convert 0.0.0.63 to /26' {
            $result = ConvertTo-CidrNotation -WildcardMask '0.0.0.63'
            $result.PrefixLength | Should -Be 26
            $result.SubnetMask | Should -Be '255.255.255.192'
        }

        It 'Should reject non-contiguous wildcard masks' {
            { ConvertTo-CidrNotation -WildcardMask '0.255.0.255' } | Should -Throw
        }
    }

    Context 'Pipeline input' {
        It 'Should accept prefix lengths from the pipeline' {
            $results = 8, 16, 24 | ConvertTo-CidrNotation
            @($results).Count | Should -Be 3
            $results[0].PrefixLength | Should -Be 8
            $results[1].PrefixLength | Should -Be 16
            $results[2].PrefixLength | Should -Be 24
        }
    }

    Context 'Round-trip consistency' {
        It 'Should produce consistent results regardless of input format' {
            $fromPrefix = ConvertTo-CidrNotation -PrefixLength 24
            $fromMask = ConvertTo-CidrNotation -SubnetMask '255.255.255.0'
            $fromWildcard = ConvertTo-CidrNotation -WildcardMask '0.0.0.255'

            $fromPrefix.PrefixLength | Should -Be $fromMask.PrefixLength
            $fromPrefix.PrefixLength | Should -Be $fromWildcard.PrefixLength
            $fromPrefix.SubnetMask | Should -Be $fromMask.SubnetMask
            $fromPrefix.WildcardMask | Should -Be $fromWildcard.WildcardMask
        }
    }

    Context 'Parameter validation' {
        It 'Should reject prefix lengths outside 0-32 range' {
            { ConvertTo-CidrNotation -PrefixLength 33 } | Should -Throw
            { ConvertTo-CidrNotation -PrefixLength -1 } | Should -Throw
        }

        It 'Should reject invalid subnet mask format' {
            { ConvertTo-CidrNotation -SubnetMask 'not-an-ip' } | Should -Throw
        }
    }
}
