#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Get-DnsRecord function.

.DESCRIPTION
    Covers the default ANY behavior for DNS-over-HTTPS fan-out and native DNS
    resolution without requiring external network access.
#>

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    # Provides a command target for Pester. Get-DnsRecord defines its real
    # implementation locally when it runs.
    function Resolve-NativeDnsHostEntry
    {
        throw 'Resolve-NativeDnsHostEntry must be mocked by tests that use host names.'
    }

    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Get-DnsRecord.ps1"

    # Capture the implementation so recursive Get-DnsRecord calls can be mocked
    # without replacing the outer invocation under test.
    $script:GetDnsRecordImplementation = (Get-Command Get-DnsRecord).ScriptBlock
}

Describe 'Get-DnsRecord' {
    Context 'DNS-over-HTTPS ANY queries' {
        BeforeEach {
            Mock -CommandName Get-DnsRecord -MockWith {
                [PSCustomObject]@{
                    Name = $Name
                    Type = $Type
                    TTL = 60
                    Data = "mock-$Type"
                }
            }
        }

        It 'Fans out the default ANY query across every record type included in the DoH expansion' {
            $expectedTypes = @('A', 'AAAA', 'MX', 'TXT', 'NS', 'CNAME', 'SOA', 'SRV', 'CAA')

            $results = @(
                & $script:GetDnsRecordImplementation -Name 'example.test' -Server google -Timeout 23
            )

            @($results).Count | Should-Be $expectedTypes.Count
            ($results.Type -join ',') | Should-Be ($expectedTypes -join ',')

            Should-Invoke -CommandName Get-DnsRecord -Times $expectedTypes.Count -Exactly -ParameterFilter {
                $Name -eq 'example.test' -and
                $Type -in $expectedTypes -and
                $Server -eq 'google' -and
                $Timeout -eq 23 -and
                $WarningAction -eq 'SilentlyContinue'
            }
        }
    }

    Context 'Native DNS queries' {
        It 'Labels <Address> as an <ExpectedType> record' -TestCases @(
            @{ Address = '127.0.0.1'; ExpectedType = 'A' }
            @{ Address = '::1'; ExpectedType = 'AAAA' }
        ) {
            param($Address, $ExpectedType)

            $results = @(
                & $script:GetDnsRecordImplementation -Name $Address -Type ANY -UseDNS -ErrorAction Stop
            )

            @($results).Count | Should-Be 1
            $results[0].Name | Should-Be $Address
            $results[0].Type | Should-Be $ExpectedType
            $results[0].TTL | Should -BeNullOrEmpty
            $results[0].Data | Should-Be $Address
        }

        It 'Preserves a canonical CNAME and attributes addresses to its target for ANY queries' {
            Mock -CommandName Resolve-NativeDnsHostEntry -MockWith {
                $hostEntry = [System.Net.IPHostEntry]::new()
                $hostEntry.HostName = 'target.example.test'
                $hostEntry.Aliases = @()
                $hostEntry.AddressList = @(
                    [System.Net.IPAddress]::Parse('192.0.2.25'),
                    [System.Net.IPAddress]::Parse('2001:db8::25')
                )
                $hostEntry
            }

            $results = @(
                & $script:GetDnsRecordImplementation -Name 'alias.example.test' -UseDNS -ErrorAction Stop
            )

            @($results).Count | Should-Be 3
            ($results.Type -join ',') | Should-Be 'CNAME,A,AAAA'
            $results[0].Name | Should-Be 'alias.example.test'
            $results[0].Data | Should-Be 'target.example.test'
            $results[1].Name | Should-Be 'target.example.test'
            $results[1].Data | Should-Be '192.0.2.25'
            $results[2].Name | Should-Be 'target.example.test'
            $results[2].Data | Should-Be '2001:db8::25'

            Should-Invoke -CommandName Resolve-NativeDnsHostEntry -Times 1 -Exactly
        }

        It 'Returns only the canonical alias for an explicit native CNAME query' {
            Mock -CommandName Resolve-NativeDnsHostEntry -MockWith {
                $hostEntry = [System.Net.IPHostEntry]::new()
                $hostEntry.HostName = 'target.example.test'
                $hostEntry.Aliases = @()
                $hostEntry.AddressList = @([System.Net.IPAddress]::Parse('192.0.2.25'))
                $hostEntry
            }

            $results = @(
                & $script:GetDnsRecordImplementation `
                    -Name 'alias.example.test' `
                    -Type CNAME `
                    -UseDNS `
                    -ErrorAction Stop
            )

            @($results).Count | Should-Be 1
            $results[0].Name | Should-Be 'alias.example.test'
            $results[0].Type | Should-Be 'CNAME'
            $results[0].TTL | Should -BeNullOrEmpty
            $results[0].Data | Should-Be 'target.example.test'
        }

        It 'Does not report DNS search-suffix expansion as a CNAME' {
            Mock -CommandName Resolve-NativeDnsHostEntry -MockWith {
                $hostEntry = [System.Net.IPHostEntry]::new()
                $hostEntry.HostName = 'server.search.example.test'
                $hostEntry.Aliases = @()
                $hostEntry.AddressList = @([System.Net.IPAddress]::Parse('192.0.2.50'))
                $hostEntry
            }

            $warnings = @()
            $results = @(
                & $script:GetDnsRecordImplementation `
                    -Name 'server' `
                    -Type CNAME `
                    -UseDNS `
                    -WarningAction SilentlyContinue `
                    -WarningVariable warnings `
                    -ErrorAction Stop
            )

            @($results).Count | Should-Be 0
            @($warnings).Count | Should-Be 1
            $warnings[0].Message | Should-Be "No CNAME records found for 'server'"
        }

        It 'Warns and returns before resolving an unsupported native record type' {
            $warnings = @()

            $results = @(
                & $script:GetDnsRecordImplementation `
                    -Name 'invalid..name' `
                    -Type MX `
                    -UseDNS `
                    -WarningAction SilentlyContinue `
                    -WarningVariable warnings `
                    -ErrorAction Stop
            )

            @($results).Count | Should-Be 0
            @($warnings).Count | Should-Be 1
            $warnings[0].Message | Should-Be 'Native DNS resolution only supports A, AAAA, CNAME, and ANY records. Use DNS-over-HTTPS (default) for MX records.'
        }
    }
}
