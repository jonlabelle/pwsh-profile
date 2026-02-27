#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Get-NetworkRoute function.

.DESCRIPTION
    Tests the Get-NetworkRoute function which displays the local routing table
    as structured PowerShell objects across Windows, macOS, and Linux.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Get-NetworkRoute.ps1"
}

Describe 'Get-NetworkRoute' {
    Context 'Basic routing table retrieval' {
        It 'Should return at least one route' {
            $results = Get-NetworkRoute
            @($results).Count | Should -BeGreaterThan 0
        }

        It 'Should return objects with expected properties' {
            $results = Get-NetworkRoute
            $first = $results | Select-Object -First 1
            $first.PSObject.Properties.Name | Should -Contain 'Destination'
            $first.PSObject.Properties.Name | Should -Contain 'Gateway'
            $first.PSObject.Properties.Name | Should -Contain 'Interface'
            $first.PSObject.Properties.Name | Should -Contain 'Metric'
        }

        It 'Should have non-empty Destination values' {
            $results = Get-NetworkRoute
            foreach ($route in $results)
            {
                $route.Destination | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'AddressFamily parameter' {
        It 'Should accept IPv4 address family' {
            { Get-NetworkRoute -AddressFamily 'IPv4' } | Should -Not -Throw
        }

        It 'Should accept IPv6 address family' {
            { Get-NetworkRoute -AddressFamily 'IPv6' } | Should -Not -Throw
        }

        It 'Should accept All address family' {
            { Get-NetworkRoute -AddressFamily 'All' } | Should -Not -Throw
        }

        It 'Should reject invalid AddressFamily values' {
            { Get-NetworkRoute -AddressFamily 'IPX' } | Should -Throw
        }
    }

    Context 'Verbose output' {
        It 'Should produce verbose messages' {
            $verboseOutput = Get-NetworkRoute -Verbose 4>&1
            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }
}
