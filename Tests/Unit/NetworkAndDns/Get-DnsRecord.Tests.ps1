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

            @($results).Count | Should -Be $expectedTypes.Count
            ($results.Type -join ',') | Should -Be ($expectedTypes -join ',')

            Should -Invoke -CommandName Get-DnsRecord -Times $expectedTypes.Count -Exactly -ParameterFilter {
                $Name -eq 'example.test' -and
                $Type -in $expectedTypes -and
                $Server -eq 'google' -and
                $Timeout -eq 23 -and
                $WarningAction -eq 'SilentlyContinue'
            }
        }
    }

    Context 'Native DNS ANY queries' {
        It 'Labels <Address> as an <ExpectedType> record' -TestCases @(
            @{ Address = '127.0.0.1'; ExpectedType = 'A' }
            @{ Address = '::1'; ExpectedType = 'AAAA' }
        ) {
            param($Address, $ExpectedType)

            $results = @(
                & $script:GetDnsRecordImplementation -Name $Address -Type ANY -UseDNS -ErrorAction Stop
            )

            @($results).Count | Should -Be 1
            $results[0].Name | Should -Be $Address
            $results[0].Type | Should -Be $ExpectedType
            $results[0].TTL | Should -BeNullOrEmpty
            $results[0].Data | Should -Be $Address
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

            @($results).Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            $warnings[0].Message | Should -Be 'Native DNS resolution only supports A, AAAA, and ANY records. Use DNS-over-HTTPS (default) for MX records.'
        }
    }
}
