#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Get-PublicDnsServers function.

.DESCRIPTION
    Tests the Get-PublicDnsServers function which returns a curated list of
    well-known public DNS servers with their addresses and DoH URLs.
#>

BeforeAll {
    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Get-PublicDnsServers.ps1"
}

Describe 'Get-PublicDnsServers' {
    Context 'Default output (no parameters)' {
        It 'Should return multiple DNS server entries' {
            $results = Get-PublicDnsServers
            @($results).Count | Should -BeGreaterThan 5
        }

        It 'Should return objects with expected properties' {
            $results = Get-PublicDnsServers
            $first = $results | Select-Object -First 1
            $first.PSObject.Properties.Name | Should -Contain 'Name'
            $first.PSObject.Properties.Name | Should -Contain 'IPv4Primary'
            $first.PSObject.Properties.Name | Should -Contain 'IPv4Secondary'
            $first.PSObject.Properties.Name | Should -Contain 'IPv6Primary'
            $first.PSObject.Properties.Name | Should -Contain 'IPv6Secondary'
            $first.PSObject.Properties.Name | Should -Contain 'DoHUrl'
            $first.PSObject.Properties.Name | Should -Contain 'PrivacyPolicyUrl'
        }

        It 'Should include well-known providers (Cloudflare, Google, Quad9)' {
            $results = Get-PublicDnsServers
            $names = $results | ForEach-Object { $_.Name }
            $names | Should -Contain 'Cloudflare'
            $names | Should -Contain 'Google'
            $names | Should -Contain 'Quad9'
        }

        It 'Should have valid IPv4 addresses for all entries' {
            $results = Get-PublicDnsServers
            foreach ($server in $results)
            {
                $parsed = $null
                [System.Net.IPAddress]::TryParse($server.IPv4Primary, [ref]$parsed) | Should -Be $true
            }
        }
    }

    Context 'Name filter' {
        It 'Should filter by exact name' {
            $results = Get-PublicDnsServers -Name 'Google'
            @($results).Count | Should -Be 1
            $results.Name | Should -Be 'Google'
            $results.IPv4Primary | Should -Be '8.8.8.8'
        }

        It 'Should support wildcard filtering' {
            $results = Get-PublicDnsServers -Name 'Cloud*'
            @($results).Count | Should -Be 1
            $results.Name | Should -Be 'Cloudflare'
        }

        It 'Should return empty for non-matching name' {
            $results = Get-PublicDnsServers -Name 'NonExistentProvider'
            $results | Should -BeNullOrEmpty
        }
    }

    Context 'IPv4Only switch' {
        It 'Should return only IPv4 address strings' {
            $results = Get-PublicDnsServers -IPv4Only
            foreach ($ip in $results)
            {
                $ip | Should -BeOfType [String]
                $parsed = $null
                [System.Net.IPAddress]::TryParse($ip, [ref]$parsed) | Should -Be $true
            }
        }

        It 'Should return the same count as full results' {
            $full = Get-PublicDnsServers
            $ipsOnly = Get-PublicDnsServers -IPv4Only
            @($ipsOnly).Count | Should -Be @($full).Count
        }

        It 'Should include well-known IPs' {
            $results = Get-PublicDnsServers -IPv4Only
            $results | Should -Contain '1.1.1.1'
            $results | Should -Contain '8.8.8.8'
            $results | Should -Contain '9.9.9.9'
        }
    }

    Context 'Known server data integrity' {
        It 'Should have correct Cloudflare data' {
            $cf = Get-PublicDnsServers -Name 'Cloudflare'
            $cf.IPv4Primary | Should -Be '1.1.1.1'
            $cf.IPv4Secondary | Should -Be '1.0.0.1'
            $cf.DoHUrl | Should -Be 'https://cloudflare-dns.com/dns-query'
        }

        It 'Should have correct Google data' {
            $g = Get-PublicDnsServers -Name 'Google'
            $g.IPv4Primary | Should -Be '8.8.8.8'
            $g.IPv4Secondary | Should -Be '8.8.4.4'
            $g.DoHUrl | Should -Be 'https://dns.google/dns-query'
        }
    }
}
