#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Get-IPAddress.

.DESCRIPTION
    Verifies local-only retrieval, default public-address inclusion, scope
    classification, CIDR calculation, filtering, and parameter-set behavior without
    using public network endpoints.
#>

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Get-IPAddress.ps1"
    $script:GetIPAddressImplementation = (Get-Command -Name 'Get-IPAddress').ScriptBlock
    $script:GetExpectedCidr = {
        param(
            [System.Net.IPAddress]$Address,
            [Int32]$PrefixLength
        )

        $addressBits = ($Address.GetAddressBytes() | ForEach-Object {
                [Convert]::ToString($_, 2).PadLeft(8, '0')
            }) -join ''
        $networkBits = $addressBits.Substring(0, $PrefixLength).PadRight($addressBits.Length, '0')
        [Byte[]]$networkBytes = @()

        for ($offset = 0; $offset -lt $networkBits.Length; $offset += 8)
        {
            $networkBytes += [Convert]::ToByte($networkBits.Substring($offset, 8), 2)
        }

        $networkAddress = [System.Net.IPAddress]::new($networkBytes)
        "$($networkAddress.ToString())/$PrefixLength"
    }
}

Describe 'Get-IPAddress' {
    Context 'Local-only retrieval' {
        It 'Returns local addresses without making a public lookup' {
            Mock -CommandName Get-IPAddress -ParameterFilter { $Public } -MockWith {
                throw 'The public lookup should not run.'
            }

            $results = @(& $script:GetIPAddressImplementation -SkipPublic)

            $results.Count | Should-BeGreaterThan 0
            Should-Invoke -CommandName Get-IPAddress -ParameterFilter { $Public } -Times 0 -Exactly
        }

        It 'Adds the default output properties to every local result' {
            $results = @(& $script:GetIPAddressImplementation -SkipPublic)

            foreach ($result in $results)
            {
                (($result.PSObject.Properties.Name | Select-Object -First 4) -join ',') |
                    Should-Be 'Address,Family,Scope,CIDR'
                $result.Scope | Should -Not -BeNullOrEmpty
                $result.CIDR | Should -Not -BeNullOrEmpty
            }
        }

        It 'Returns normalized IPv4 and IPv6 network ranges in CIDR notation' {
            $results = @(& $script:GetIPAddressImplementation -SkipPublic)

            foreach ($result in $results)
            {
                $cidrParts = @($result.CIDR -split '/', 2)
                $address = [System.Net.IPAddress]::Parse($result.Address)
                $prefixLength = [Int32]$cidrParts[1]
                $expectedCidr = & $script:GetExpectedCidr -Address $address -PrefixLength $prefixLength

                $cidrParts.Count | Should-Be 2
                $result.CIDR | Should-Be $expectedCidr
            }
        }

        It 'Classifies local loopback addresses' {
            $results = @(& $script:GetIPAddressImplementation -SkipPublic)
            $ipv4Loopback = $results | Where-Object { $_.Address -eq '127.0.0.1' } | Select-Object -First 1

            $ipv4Loopback | Should -Not -BeNullOrEmpty
            $ipv4Loopback.Scope | Should-Be 'Loopback'
            $ipv4Loopback.CIDR | Should-Be '127.0.0.0/8'
            foreach ($loopbackResult in @($results | Where-Object { $_.Address -in @('127.0.0.1', '::1') }))
            {
                $loopbackResult.Scope | Should-Be 'Loopback'
            }
        }

        It 'Honors the IPv4 address-family filter' {
            $results = @(& $script:GetIPAddressImplementation -SkipPublic -AddressFamily IPv4)

            $results.Count | Should-BeGreaterThan 0
            @($results | Where-Object { $_.Family -ne 'IPv4' }).Count | Should-Be 0
        }
    }

    Context 'Default combined retrieval' {
        BeforeEach {
            $script:PublicFixtureAddress = '192.0.0.9'
            Mock -CommandName Get-IPAddress -ParameterFilter { $Public } -MockWith {
                [PSCustomObject]@{
                    Address = $script:PublicFixtureAddress
                    Family = 'IPv4'
                    Scope = 'IncorrectFixtureValue'
                    CIDR = '192.0.0.9/32'
                    Service = 'fixture'
                }
            }
        }

        It 'Appends the public address by default' {
            $results = @(& $script:GetIPAddressImplementation -AddressFamily IPv4)
            $publicResult = $results | Where-Object { $_.Address -eq $script:PublicFixtureAddress }

            $publicResult | Should -Not -BeNullOrEmpty
            (($publicResult.PSObject.Properties.Name | Select-Object -First 4) -join ',') |
                Should-Be 'Address,Family,Scope,CIDR'
            $publicResult.Scope | Should-Be 'Public'
            $publicResult.PSObject.Properties.Name | Should-ContainCollection 'CIDR'
            $publicResult.CIDR | Should -BeNullOrEmpty
            $publicResult.Service | Should-Be 'fixture'
            Should-Invoke -CommandName Get-IPAddress -ParameterFilter {
                $Public -and $AddressFamily -eq 'IPv4' -and $Service -eq 'auto' -and $Timeout -eq 5
            } -Times 1 -Exactly
        }

        It 'Does not duplicate a public address already assigned to a local interface' {
            $localResults = @(& $script:GetIPAddressImplementation -SkipPublic -AddressFamily IPv4)
            $script:PublicFixtureAddress = $localResults[0].Address

            $results = @(& $script:GetIPAddressImplementation -AddressFamily IPv4)
            $matchingResults = @($results | Where-Object { $_.Address -eq $script:PublicFixtureAddress })

            $matchingResults.Count | Should-Be 1
            $matchingResults[0].PSObject.Properties.Name | Should -Not -Contain 'Service'
        }

        It 'Falls back to local results when the public lookup is unavailable' {
            Mock -CommandName Get-IPAddress -ParameterFilter { $Public } -MockWith {
                Write-Error 'Fixture public lookup failure'
            }

            $results = @(& $script:GetIPAddressImplementation -AddressFamily IPv4)

            $results.Count | Should-BeGreaterThan 0
            @($results | Where-Object { $_.PSObject.Properties['Service'] }).Count | Should-Be 0
        }
    }

    Context 'Scope classification' {
        It 'Classifies <Address> as <ExpectedScope>' -ForEach @(
            @{ Address = '10.254.253.252'; ExpectedScope = 'Private' }
            @{ Address = '100.64.0.25'; ExpectedScope = 'Shared' }
            @{ Address = '169.254.10.25'; ExpectedScope = 'LinkLocal' }
            @{ Address = '192.0.0.9'; ExpectedScope = 'Public' }
            @{ Address = '192.0.2.25'; ExpectedScope = 'Documentation' }
            @{ Address = '198.18.0.25'; ExpectedScope = 'Benchmark' }
            @{ Address = '::1'; ExpectedScope = 'Loopback' }
            @{ Address = 'fd00::25'; ExpectedScope = 'Private' }
            @{ Address = 'fe80::25'; ExpectedScope = 'LinkLocal' }
            @{ Address = '2001:1::1'; ExpectedScope = 'Public' }
            @{ Address = '2001:db8::25'; ExpectedScope = 'Documentation' }
            @{ Address = 'ff02::1'; ExpectedScope = 'Multicast' }
            @{ Address = '100::25'; ExpectedScope = 'Reserved' }
        ) {
            $script:PublicFixtureAddress = $Address
            Mock -CommandName Get-IPAddress -ParameterFilter { $Public } -MockWith {
                [PSCustomObject]@{
                    Address = $script:PublicFixtureAddress
                    Family = 'FixtureValue'
                    Scope = 'IncorrectFixtureValue'
                    CIDR = "$($script:PublicFixtureAddress)/32"
                    Service = 'fixture'
                }
            }

            $results = @(& $script:GetIPAddressImplementation)
            $classifiedResult = $results | Where-Object { $_.Address -eq $Address }

            $classifiedResult | Should -Not -BeNullOrEmpty
            $classifiedResult.Scope | Should-Be $ExpectedScope
        }
    }

    Context 'Parameter contract' {
        It 'Preserves Local as the default parameter-set name' {
            $command = Get-Command -Name 'Get-IPAddress'
            $defaultSet = $command.ParameterSets | Where-Object { $_.IsDefault }

            $defaultSet.Name | Should-Be 'Local'
        }

        It 'Provides explicit public-only and local-only selectors' {
            $command = Get-Command -Name 'Get-IPAddress'
            $command.Parameters.Keys | Should-ContainCollection 'Public'
            $command.Parameters.Keys | Should-ContainCollection 'SkipPublic'

            ($command.ParameterSets | Where-Object { $_.Name -eq 'Public' }).IsDefault | Should-Be $false
            ($command.ParameterSets | Where-Object { $_.Name -eq 'LocalOnly' }).IsDefault | Should-Be $false
        }
    }
}
