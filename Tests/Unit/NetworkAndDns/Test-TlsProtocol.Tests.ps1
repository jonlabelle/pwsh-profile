#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Test-TlsProtocol function.

.DESCRIPTION
    Tests command metadata, parameter validation, result shape, and failure handling
    for Test-TlsProtocol without relying on real TLS endpoints. Public endpoint
    coverage lives in the integration tests.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Import the function under test
    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Test-TlsProtocol.ps1"

    $script:Command = Get-Command -Name Test-TlsProtocol
    $script:FastFailureHost = 'this-hostname-definitely-does-not-exist-12345.invalid'

    function Get-TestTlsProtocolParameter
    {
        param(
            [Parameter(Mandatory)]
            [string]$Name
        )

        return $script:Command.Parameters[$Name]
    }

    function Get-TestTlsProtocolParameterDefaultText
    {
        param(
            [Parameter(Mandatory)]
            [string]$Name
        )

        $parameterAst = $script:Command.ScriptBlock.Ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.ParameterAst] -and
                $node.Name.VariablePath.UserPath -eq $Name
            }, $true)

        if (-not $parameterAst -or -not $parameterAst.DefaultValue)
        {
            return $null
        }

        return $parameterAst.DefaultValue.Extent.Text
    }
}

Describe 'Test-TlsProtocol' {
    Context 'Parameter metadata' {
        It 'Accepts ComputerName from pipeline input with supported aliases' {
            $parameter = Get-TestTlsProtocolParameter -Name 'ComputerName'

            $parameter.ParameterSets['__AllParameterSets'].ValueFromPipeline | Should -Be $true
            $parameter.ParameterSets['__AllParameterSets'].ValueFromPipelineByPropertyName | Should -Be $true
            $parameter.Aliases | Should -Contain 'Server'
            $parameter.Aliases | Should -Contain 'Host'
            $parameter.Aliases | Should -Contain 'HostName'
        }

        It 'Uses localhost as default ComputerName' {
            Get-TestTlsProtocolParameterDefaultText -Name 'ComputerName' | Should -Be "'localhost'"
        }

        It 'Accepts the valid port range' {
            $parameter = Get-TestTlsProtocolParameter -Name 'Port'
            $range = $parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }

            $range.MinRange | Should -Be 1
            $range.MaxRange | Should -Be 65535
        }

        It 'Rejects invalid port numbers' {
            { Test-TlsProtocol -Port 0 -Protocol Tls12 } | Should -Throw
            { Test-TlsProtocol -Port 65536 -Protocol Tls12 } | Should -Throw
            { Test-TlsProtocol -Port -1 -Protocol Tls12 } | Should -Throw
        }

        It 'Uses 443 as default port' {
            Get-TestTlsProtocolParameterDefaultText -Name 'Port' | Should -Be '443'
        }

        It 'Accepts the valid timeout range' {
            $parameter = Get-TestTlsProtocolParameter -Name 'Timeout'
            $range = $parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }

            $range.MinRange | Should -Be 100
            $range.MaxRange | Should -Be 30000
        }

        It 'Rejects invalid timeout values' {
            { Test-TlsProtocol -Timeout 99 -Protocol Tls12 } | Should -Throw
            { Test-TlsProtocol -Timeout 30001 -Protocol Tls12 } | Should -Throw
        }

        It 'Uses 3000ms as default timeout' {
            Get-TestTlsProtocolParameterDefaultText -Name 'Timeout' | Should -Be '3000'
        }

        It 'Accepts supported TLS protocol values' {
            $parameter = Get-TestTlsProtocolParameter -Name 'Protocol'
            $validateSet = $parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }

            $validateSet.ValidValues | Should -Be @('Tls', 'Tls11', 'Tls12', 'Tls13')
        }

        It 'Rejects invalid TLS protocol values' {
            { Test-TlsProtocol -Protocol 'InvalidProtocol' } | Should -Throw
            { Test-TlsProtocol -Protocol 'SSL3' } | Should -Throw
        }
    }

    Context 'Output structure' {
        It 'Returns objects with required properties' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.Properties.Name | Should -Contain 'Server'
            $result[0].PSObject.Properties.Name | Should -Contain 'Port'
            $result[0].PSObject.Properties.Name | Should -Contain 'Protocol'
            $result[0].PSObject.Properties.Name | Should -Contain 'Supported'
            $result[0].PSObject.Properties.Name | Should -Contain 'Status'
            $result[0].PSObject.Properties.Name | Should -Contain 'ResponseTime'
        }

        It 'Has correct property types' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100

            $result[0].Server | Should -BeOfType [String]
            $result[0].Port | Should -BeOfType [Int]
            $result[0].Protocol | Should -BeOfType [String]
            $result[0].Supported | Should -BeOfType [Boolean]
            $result[0].Status | Should -BeOfType [String]
            $result[0].ResponseTime | Should -BeOfType [TimeSpan]
        }

        It 'Populates Server property correctly' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100
            $result[0].Server | Should -Be $script:FastFailureHost
        }

        It 'Populates Port property correctly' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Port 8443 -Protocol Tls12 -Timeout 100
            $result[0].Port | Should -Be 8443
        }

        It 'Populates Protocol property correctly' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100
            $result[0].Protocol | Should -Be 'Tls12'
        }
    }

    Context 'Multiple protocol testing' {
        It 'Tests multiple protocols when specified' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12, Tls13 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 2
            $result[0].Protocol | Should -Be 'Tls12'
            $result[1].Protocol | Should -Be 'Tls13'
        }

        It 'Tests all protocols when none specified' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 4
            $result[0].Protocol | Should -Be 'Tls'
            $result[1].Protocol | Should -Be 'Tls11'
            $result[2].Protocol | Should -Be 'Tls12'
            $result[3].Protocol | Should -Be 'Tls13'
        }
    }

    Context 'Pipeline input support' {
        It 'Accepts pipeline input for ComputerName' {
            $result = $script:FastFailureHost | Test-TlsProtocol -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result[0].Server | Should -Be $script:FastFailureHost
        }

        It 'Handles multiple computer names via pipeline' {
            $servers = @($script:FastFailureHost, 'another-hostname-that-does-not-exist-12345.invalid')
            $result = $servers | Test-TlsProtocol -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 2
            $result[0].Server | Should -Be $servers[0]
            $result[1].Server | Should -Be $servers[1]
        }
    }

    Context 'Error handling' {
        It 'Handles connection failures gracefully' {
            $result = Test-TlsProtocol -ComputerName '192.0.2.1' -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result[0].Supported | Should -Be $false
            $result[0].Status | Should -Not -BeNullOrEmpty
        }

        It 'Handles invalid hostnames gracefully' {
            $result = Test-TlsProtocol -ComputerName $script:FastFailureHost -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result[0].Supported | Should -Be $false
        }

        It 'Handles timeout scenarios' {
            $result = Test-TlsProtocol -ComputerName '192.0.2.1' -Protocol Tls12 -Timeout 100

            $result | Should -Not -BeNullOrEmpty
            $result[0].Supported | Should -Be $false
            $result[0].Status | Should -Match 'timeout|failed'
        }
    }

    Context 'Alias support' {
        It 'Accepts Server alias for ComputerName' {
            $result = Test-TlsProtocol -Server $script:FastFailureHost -Protocol Tls12 -Timeout 100
            $result[0].Server | Should -Be $script:FastFailureHost
        }

        It 'Accepts Host alias for ComputerName' {
            $result = Test-TlsProtocol -Host $script:FastFailureHost -Protocol Tls12 -Timeout 100
            $result[0].Server | Should -Be $script:FastFailureHost
        }

        It 'Accepts HostName alias for ComputerName' {
            $result = Test-TlsProtocol -HostName $script:FastFailureHost -Protocol Tls12 -Timeout 100
            $result[0].Server | Should -Be $script:FastFailureHost
        }
    }
}
