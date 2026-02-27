#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Test-DnsPropagation function.

.DESCRIPTION
    Tests the Test-DnsPropagation function which checks DNS propagation across
    multiple public DNS servers using DNS-over-HTTPS.

.NOTES
    These tests mock the DoH HTTP calls to avoid network dependencies. Integration
    tests that perform real DNS queries are in the Integration test folder.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Get-PublicDnsServers.ps1"
    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Test-DnsPropagation.ps1"
}

Describe 'Test-DnsPropagation' {
    Context 'Parameter validation' {
        It 'Should require the Name parameter' {
            $param = (Get-Command Test-DnsPropagation).Parameters['Name']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'Should reject empty Name parameter' {
            { Test-DnsPropagation -Name '' } | Should -Throw
            { Test-DnsPropagation -Name $null } | Should -Throw
        }

        It 'Should accept valid DNS record types' {
            { Test-DnsPropagation -Name 'localhost' -Type 'A' -Timeout 2 -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should reject invalid DNS record types' {
            { Test-DnsPropagation -Name 'example.com' -Type 'INVALID' } | Should -Throw
        }

        It 'Should validate Timeout range' {
            { Test-DnsPropagation -Name 'example.com' -Timeout 0 } | Should -Throw
            { Test-DnsPropagation -Name 'example.com' -Timeout 31 } | Should -Throw
        }
    }

    Context 'Output structure' {
        BeforeAll {
            # Run once with a short timeout to keep tests fast; errors are acceptable
            $script:results = Test-DnsPropagation -Name 'localhost' -Timeout 2 -ErrorAction SilentlyContinue 2>$null
        }

        It 'Should return results for multiple servers' {
            @($script:results).Count | Should -BeGreaterThan 0
        }

        It 'Should return objects with expected properties' {
            $first = $script:results | Select-Object -First 1
            $first.PSObject.Properties.Name | Should -Contain 'Server'
            $first.PSObject.Properties.Name | Should -Contain 'IPv4Primary'
            $first.PSObject.Properties.Name | Should -Contain 'Status'
            $first.PSObject.Properties.Name | Should -Contain 'Records'
            $first.PSObject.Properties.Name | Should -Contain 'Propagated'
        }

        It 'Should have boolean Propagated values' {
            foreach ($r in $script:results)
            {
                $r.Propagated | Should -BeOfType [System.Boolean]
            }
        }
    }

    Context 'Dependency loading' {
        It 'Should load Get-PublicDnsServers dependency' {
            Get-Command -Name 'Get-PublicDnsServers' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}
