#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Test-Port function.

.DESCRIPTION
    Tests the Test-Port function which checks TCP and UDP port connectivity using cross-platform
    .NET Socket classes for maximum compatibility across Windows, macOS, and Linux.

.NOTES
    These tests are based on the examples in the Test-Port function documentation.
    Tests verify port connectivity testing with various protocols and parameter combinations.
#>

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../Functions/Test-Port.ps1"
}

Describe 'Test-Port' {
    Context 'Basic functionality examples from documentation' {
        It 'Tests if TCP port 80 is accessible on localhost (Example: Test-Port -ComputerName server -Port 80)' {
            # Test basic TCP port connectivity - equivalent to first documentation example
            $result = Test-Port -ComputerName 'localhost' -Port 80
            $result | Should -Not -BeNullOrEmpty
            $result[0].Server | Should -Be 'localhost'
            $result[0].Port | Should -Be 80
            $result[0].Protocol | Should -Be 'TCP'
            $result[0].Open | Should -BeOfType [Boolean]
        }

        It 'Tests TCP port using pipeline input for port (Example: 80 | Test-Port)' {
            # Test pipeline input for port number - equivalent to second documentation example
            $result = 80 | Test-Port
            $result | Should -Not -BeNullOrEmpty
            $result[0].Port | Should -Be 80
            $result[0].Protocol | Should -Be 'TCP'
            $result[0].Server | Should -Be 'localhost'  # Default when no ComputerName specified
        }

        It 'Tests multiple TCP ports using pipeline input (Example: 22,80,443 | Test-Port)' {
            # Test multiple ports via pipeline - equivalent to third documentation example
            $result = 22, 80, 443 | Test-Port
            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 3
            $result[0].Port | Should -Be 22
            $result[1].Port | Should -Be 80
            $result[2].Port | Should -Be 443
            $result | ForEach-Object {
                $_.Protocol | Should -Be 'TCP'
                $_.Server | Should -Be 'localhost'
            }
        }

        It 'Tests port range using pipeline input (Example: 1..100 | Test-Port -ComputerName server)' {
            # Test a small port range to validate the concept from documentation example
            $result = 1..3 | Test-Port -ComputerName 'localhost'
            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 3
            $result[0].Port | Should -Be 1
            $result[1].Port | Should -Be 2
            $result[2].Port | Should -Be 3
            $result | ForEach-Object {
                $_.Server | Should -Be 'localhost'
                $_.Protocol | Should -Be 'TCP'
            }
        }

        It 'Tests multiple target computers (Example: Test-Port -ComputerName server1,server2 -Port 80)' {
            # Test multiple computers - equivalent to documentation example
            $result = Test-Port -ComputerName @('localhost', '127.0.0.1') -Port 80
            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 2
            $result[0].Server | Should -Be 'localhost'
            $result[1].Server | Should -Be '127.0.0.1'
            $result | ForEach-Object {
                $_.Port | Should -Be 80
                $_.Protocol | Should -Be 'TCP'
            }
        }
    }

    Context 'Pipeline input scenarios' {
        It 'Tests multiple ports on localhost using pipeline input for ports' {
            $result = 80, 443 | Test-Port -ComputerName 'localhost'
            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 2
            $result | ForEach-Object { $_.Server | Should -Be 'localhost' }
        }

        It 'Tests a range of ports using pipeline input' {
            $result = 1..3 | Test-Port -ComputerName 'localhost'
            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 3
            $result[0].Port | Should -Be 1
            $result[1].Port | Should -Be 2
            $result[2].Port | Should -Be 3
        }
    }

    Context 'Parameter validation' {
        It 'Should accept valid port numbers' {
            { Test-Port -Port 80 } | Should -Not -Throw
            { Test-Port -Port 1 } | Should -Not -Throw
            { Test-Port -Port 65535 } | Should -Not -Throw
        }

        It 'Should reject invalid port numbers' {
            { Test-Port -Port 0 } | Should -Throw
            { Test-Port -Port 65536 } | Should -Throw
            { Test-Port -Port -1 } | Should -Throw
        }

        It 'Should accept valid timeout values' {
            { Test-Port -Port 80 -Timeout 100 } | Should -Not -Throw
            { Test-Port -Port 80 -Timeout 300000 } | Should -Not -Throw
        }

        It 'Should reject invalid timeout values' {
            { Test-Port -Port 80 -Timeout 99 } | Should -Throw
            { Test-Port -Port 80 -Timeout 300001 } | Should -Throw
        }
    }

    Context 'Protocol selection' {
        It 'Should default to TCP when no protocol is specified' {
            $result = Test-Port -Port 80
            $result[0].Protocol | Should -Be 'TCP'
        }

        It 'Should use TCP when Tcp switch is specified' {
            $result = Test-Port -Port 80 -Tcp
            $result[0].Protocol | Should -Be 'TCP'
        }

        It 'Should use UDP when Udp switch is specified' {
            $result = Test-Port -Port 53 -Udp
            $result[0].Protocol | Should -Be 'UDP'
        }
    }

    Context 'Multiple computers support' {
        It 'Should handle multiple target computers' {
            # Test with localhost multiple times to simulate multiple computers
            $result = Test-Port -ComputerName @('localhost', '127.0.0.1') -Port 80
            $result | Should -HaveCount 2
            $result[0].Server | Should -Be 'localhost'
            $result[1].Server | Should -Be '127.0.0.1'
            $result | ForEach-Object { $_.Port | Should -Be 80 }
        }

        It 'Should skip empty or null computer names' {
            $result = Test-Port -ComputerName @('localhost', '', $null, 'localhost') -Port 80
            # Should only process the valid entries
            $result | Should -HaveCount 2
            $result | ForEach-Object { $_.Server | Should -Be 'localhost' }
        }
    }

    Context 'TCP specific tests' {
        It 'Should properly test TCP connections' {
            $result = Test-Port -Port 80 -Tcp -ComputerName 'localhost'
            $result[0].Protocol | Should -Be 'TCP'
            $result[0].Open | Should -BeOfType [Boolean]
        }

        It 'Should handle TCP connection failures appropriately' {
            # Test a port that's likely to be closed
            $result = Test-Port -Port 9998 -Tcp -ComputerName 'localhost' -Timeout 2000
            $result[0].Protocol | Should -Be 'TCP'
            $result[0].Open | Should -Be $false
        }
    }

    Context 'UDP specific tests' {
        It 'Should properly test UDP connections' {
            $result = Test-Port -Port 53 -Udp -ComputerName 'localhost'
            $result[0].Protocol | Should -Be 'UDP'
            $result[0].Open | Should -BeOfType [Boolean]
        }

        It 'Should handle UDP port testing with appropriate status messages' {
            $result = Test-Port -Port 9997 -Udp -ComputerName 'localhost' -Timeout 3000
            $result[0].Protocol | Should -Be 'UDP'
            # UDP results are often ambiguous, but should have a status
            $result[0].Status | Should -Not -BeNullOrEmpty
        }
    }
}
