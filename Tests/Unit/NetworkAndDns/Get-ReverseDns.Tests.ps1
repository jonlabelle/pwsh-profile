#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Get-ReverseDns function.

.DESCRIPTION
    Tests the Get-ReverseDns function which performs reverse DNS (PTR) lookups
    for IP addresses using .NET methods for cross-platform compatibility.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Get-ReverseDns.ps1"
}

Describe 'Get-ReverseDns' {
    Context 'Basic reverse DNS lookups' {
        It 'Should return an object with expected properties' {
            $result = Get-ReverseDns -IPAddress '127.0.0.1'
            $result.PSObject.Properties.Name | Should-ContainCollection 'IPAddress'
            $result.PSObject.Properties.Name | Should-ContainCollection 'Hostname'
            $result.PSObject.Properties.Name | Should-ContainCollection 'Status'
        }

        It 'Should resolve localhost (127.0.0.1)' {
            $result = Get-ReverseDns -IPAddress '127.0.0.1'
            $result.IPAddress | Should-Be '127.0.0.1'
            @('Resolved', 'NotFound') | Should-ContainCollection $result.Status
        }

        It 'Should return Resolved or NotFound status for valid IPs' {
            $result = Get-ReverseDns -IPAddress '127.0.0.1'
            @('Resolved', 'NotFound') | Should-ContainCollection $result.Status
        }
    }

    Context 'Multiple IP addresses' {
        It 'Should accept multiple IPs via parameter' {
            $results = Get-ReverseDns -IPAddress '127.0.0.1', '127.0.0.1'
            @($results).Count | Should-Be 2
        }

        It 'Should accept IPs from the pipeline' {
            $results = '127.0.0.1', '127.0.0.1' | Get-ReverseDns
            @($results).Count | Should-Be 2
        }
    }

    Context 'Non-resolvable IP handling' {
        It 'Should return NotFound for documentation IPs (RFC 5737)' {
            $result = Get-ReverseDns -IPAddress '192.0.2.1'
            @('NotFound', 'Error') | Should-ContainCollection $result.Status
            $result.IPAddress | Should-Be '192.0.2.1'
        }
    }

    Context 'Parameter validation' {
        It 'Should require the IPAddress parameter' {
            $param = (Get-Command Get-ReverseDns).Parameters['IPAddress']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            ForEach-Object { $_.Mandatory } | Should-ContainCollection $true
        }

        It 'Should reject invalid IP addresses' {
            { Get-ReverseDns -IPAddress 'not-an-ip' } | Should-Throw
            { Get-ReverseDns -IPAddress '999.999.999.999' } | Should-Throw
        }

        It 'Should reject empty or null values' {
            { Get-ReverseDns -IPAddress '' } | Should-Throw
            { Get-ReverseDns -IPAddress $null } | Should-Throw
        }
    }

    Context 'Verbose output' {
        It 'Should produce verbose messages' {
            $verboseOutput = Get-ReverseDns -IPAddress '127.0.0.1' -Verbose 4>&1
            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }
}
