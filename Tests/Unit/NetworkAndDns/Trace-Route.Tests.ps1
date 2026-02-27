#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Trace-Route function.

.DESCRIPTION
    Tests the Trace-Route function which performs cross-platform traceroute using
    .NET System.Net.NetworkInformation.Ping with incrementing TTL values.
#>

BeforeAll {
    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Trace-Route.ps1"
}

Describe 'Trace-Route' {
    Context 'Parameter validation' {
        It 'Should require the ComputerName parameter' {
            $param = (Get-Command Trace-Route).Parameters['ComputerName']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'Should reject empty ComputerName' {
            { Trace-Route -ComputerName '' } | Should -Throw
            { Trace-Route -ComputerName $null } | Should -Throw
        }

        It 'Should validate MaxHops range' {
            { Trace-Route -ComputerName 'localhost' -MaxHops 0 } | Should -Throw
            { Trace-Route -ComputerName 'localhost' -MaxHops 65 } | Should -Throw
        }

        It 'Should validate Timeout range' {
            { Trace-Route -ComputerName 'localhost' -Timeout 50 } | Should -Throw
            { Trace-Route -ComputerName 'localhost' -Timeout 31000 } | Should -Throw
        }

        It 'Should validate Queries range' {
            { Trace-Route -ComputerName 'localhost' -Queries 0 } | Should -Throw
            { Trace-Route -ComputerName 'localhost' -Queries 6 } | Should -Throw
        }

        It 'Should validate BufferSize range' {
            { Trace-Route -ComputerName 'localhost' -BufferSize -1 } | Should -Throw
        }
    }

    Context 'Localhost traceroute' {
        It 'Should trace route to localhost successfully' {
            $results = Trace-Route -ComputerName 'localhost' -MaxHops 3 -Timeout 2000
            @($results).Count | Should -BeGreaterThan 0
        }

        It 'Should return objects with expected properties' {
            $results = Trace-Route -ComputerName 'localhost' -MaxHops 3 -Timeout 2000
            $first = $results | Select-Object -First 1
            $first.PSObject.Properties.Name | Should -Contain 'Hop'
            $first.PSObject.Properties.Name | Should -Contain 'IP'
            $first.PSObject.Properties.Name | Should -Contain 'Hostname'
            $first.PSObject.Properties.Name | Should -Contain 'Latency'
            $first.PSObject.Properties.Name | Should -Contain 'Status'
        }

        It 'Should return valid status values for each hop' {
            $results = Trace-Route -ComputerName 'localhost' -MaxHops 3 -Timeout 2000
            $validStatuses = @('Success', 'TimedOut', 'TtlExpired', 'Error')
            $results | ForEach-Object { $_.Status | Should -BeIn $validStatuses }
        }

        It 'Should have Hop numbers starting at 1' {
            $results = Trace-Route -ComputerName 'localhost' -MaxHops 3 -Timeout 2000
            $results[0].Hop | Should -Be 1
        }
    }

    Context 'ResolveNames parameter' {
        It 'Should accept ResolveNames as true' {
            { Trace-Route -ComputerName 'localhost' -MaxHops 2 -Timeout 2000 -ResolveNames $true } | Should -Not -Throw
        }

        It 'Should accept ResolveNames as false' {
            { Trace-Route -ComputerName 'localhost' -MaxHops 2 -Timeout 2000 -ResolveNames $false } | Should -Not -Throw
        }
    }

    Context 'Error handling' {
        It 'Should handle unresolvable hostnames gracefully' {
            $results = Trace-Route -ComputerName 'this-host-definitely-does-not-exist-12345.invalid' -MaxHops 2 -Timeout 1000 -ErrorAction SilentlyContinue 2>$null
            # Should either return no results or produce an error (not throw)
        }
    }

    Context 'Verbose output' {
        It 'Should produce verbose messages' {
            $verboseOutput = Trace-Route -ComputerName 'localhost' -MaxHops 2 -Timeout 2000 -Verbose 4>&1
            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }
}
