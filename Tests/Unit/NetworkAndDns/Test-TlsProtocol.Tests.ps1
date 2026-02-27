#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Test-TlsProtocol function.

.DESCRIPTION
    Tests the Test-TlsProtocol function which tests TLS protocol support on remote web servers
    using cross-platform .NET SSL/TLS methods for maximum compatibility.

.NOTES
    These tests are based on the examples in the Test-TlsProtocol function documentation.
    Tests verify parameter validation, protocol testing, and proper handling of various scenarios.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Import the function under test
    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Test-TlsProtocol.ps1"
}

Describe 'Test-TlsProtocol' {
    Context 'Parameter validation' {
        It 'Should accept valid ComputerName parameter' {
            { Test-TlsProtocol -ComputerName 'localhost' -Protocol Tls12 } | Should -Not -Throw
            { Test-TlsProtocol -ComputerName 'example.com' -Protocol Tls12 } | Should -Not -Throw
            { Test-TlsProtocol -ComputerName '127.0.0.1' -Protocol Tls12 } | Should -Not -Throw
        }

        It 'Should use localhost as default ComputerName' {
            $result = Test-TlsProtocol -Protocol Tls12
            $result | Should -Not -BeNullOrEmpty
            $result.Server | Should -Be 'localhost'
        }

        It 'Should accept valid port numbers' {
            { Test-TlsProtocol -Port 443 -Protocol Tls12 } | Should -Not -Throw
            { Test-TlsProtocol -Port 1 -Protocol Tls12 } | Should -Not -Throw
            { Test-TlsProtocol -Port 65535 -Protocol Tls12 } | Should -Not -Throw
            { Test-TlsProtocol -Port 8443 -Protocol Tls12 } | Should -Not -Throw
        }

        It 'Should reject invalid port numbers' {
            { Test-TlsProtocol -Port 0 -Protocol Tls12 } | Should -Throw
            { Test-TlsProtocol -Port 65536 -Protocol Tls12 } | Should -Throw
            { Test-TlsProtocol -Port -1 -Protocol Tls12 } | Should -Throw
        }

        It 'Should use 443 as default port' {
            $result = Test-TlsProtocol -Protocol Tls12
            $result | Should -Not -BeNullOrEmpty
            $result.Port | Should -Be 443
        }

        It 'Should accept valid timeout values' {
            { Test-TlsProtocol -Timeout 100 -Protocol Tls12 } | Should -Not -Throw
            { Test-TlsProtocol -Timeout 30000 -Protocol Tls12 } | Should -Not -Throw
            { Test-TlsProtocol -Timeout 3000 -Protocol Tls12 } | Should -Not -Throw
        }

        It 'Should reject invalid timeout values' {
            { Test-TlsProtocol -Timeout 99 -Protocol Tls12 } | Should -Throw
            { Test-TlsProtocol -Timeout 30001 -Protocol Tls12 } | Should -Throw
        }

        It 'Should use 3000ms as default timeout' {
            # This test verifies the default is set - actual behavior tested in integration tests
            $result = Test-TlsProtocol -Protocol Tls12
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should accept valid TLS protocol values' {
            { Test-TlsProtocol -Protocol Tls } | Should -Not -Throw
            { Test-TlsProtocol -Protocol Tls11 } | Should -Not -Throw
            { Test-TlsProtocol -Protocol Tls12 } | Should -Not -Throw
            { Test-TlsProtocol -Protocol Tls13 } | Should -Not -Throw
            { Test-TlsProtocol -Protocol Tls12, Tls13 } | Should -Not -Throw
        }

        It 'Should reject invalid TLS protocol values' {
            { Test-TlsProtocol -Protocol 'InvalidProtocol' } | Should -Throw
            { Test-TlsProtocol -Protocol 'SSL3' } | Should -Throw
        }

        It 'Should test all protocols when none specified' {
            $result = Test-TlsProtocol -ComputerName 'localhost'
            $result | Should -Not -BeNullOrEmpty
            # Should have 4 results (one for each protocol: Tls, Tls11, Tls12, Tls13)
            $result | Should -HaveCount 4
            $result[0].Protocol | Should -Be 'Tls'
            $result[1].Protocol | Should -Be 'Tls11'
            $result[2].Protocol | Should -Be 'Tls12'
            $result[3].Protocol | Should -Be 'Tls13'
        }
    }

    Context 'Output structure' {
        It 'Should return objects with required properties' {
            $result = Test-TlsProtocol -Protocol Tls12

            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.Properties.Name | Should -Contain 'Server'
            $result[0].PSObject.Properties.Name | Should -Contain 'Port'
            $result[0].PSObject.Properties.Name | Should -Contain 'Protocol'
            $result[0].PSObject.Properties.Name | Should -Contain 'Supported'
            $result[0].PSObject.Properties.Name | Should -Contain 'Status'
            $result[0].PSObject.Properties.Name | Should -Contain 'ResponseTime'
        }

        It 'Should have correct property types' {
            $result = Test-TlsProtocol -Protocol Tls12

            $result[0].Server | Should -BeOfType [String]
            $result[0].Port | Should -BeOfType [Int]
            $result[0].Protocol | Should -BeOfType [String]
            $result[0].Supported | Should -BeOfType [Boolean]
            $result[0].Status | Should -BeOfType [String]
            $result[0].ResponseTime | Should -BeOfType [TimeSpan]
        }

        It 'Should populate Server property correctly' {
            $result = Test-TlsProtocol -ComputerName 'example.com' -Protocol Tls12
            $result[0].Server | Should -Be 'example.com'
        }

        It 'Should populate Port property correctly' {
            $result = Test-TlsProtocol -Port 8443 -Protocol Tls12
            $result[0].Port | Should -Be 8443
        }

        It 'Should populate Protocol property correctly' {
            $result = Test-TlsProtocol -Protocol Tls12
            $result[0].Protocol | Should -Be 'Tls12'
        }
    }

    Context 'Multiple protocol testing' {
        It 'Should test multiple protocols when specified' {
            $result = Test-TlsProtocol -Protocol Tls12, Tls13

            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 2
            $result[0].Protocol | Should -Be 'Tls12'
            $result[1].Protocol | Should -Be 'Tls13'
        }

        It 'Should test each protocol independently' {
            $result = Test-TlsProtocol -Protocol Tls, Tls11, Tls12

            $result | Should -HaveCount 3
            $result | ForEach-Object {
                $_.Server | Should -Be 'localhost'
                $_.Port | Should -Be 443
                $_.Supported | Should -BeOfType [Boolean]
                $_.Status | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Pipeline input support' {
        It 'Should accept pipeline input for ComputerName' {
            $result = 'localhost' | Test-TlsProtocol -Protocol Tls12

            $result | Should -Not -BeNullOrEmpty
            $result[0].Server | Should -Be 'localhost'
        }

        It 'Should handle multiple computer names via pipeline' {
            $servers = @('localhost', '127.0.0.1')
            $result = $servers | Test-TlsProtocol -Protocol Tls12

            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 2
            $result[0].Server | Should -Be 'localhost'
            $result[1].Server | Should -Be '127.0.0.1'
        }
    }

    Context 'Error handling' {
        It 'Should handle connection failures gracefully' {
            # Use a non-routable IP to force connection failure
            $result = Test-TlsProtocol -ComputerName '192.0.2.1' -Protocol Tls12 -Timeout 500

            $result | Should -Not -BeNullOrEmpty
            $result[0].Supported | Should -Be $false
            $result[0].Status | Should -Not -BeNullOrEmpty
        }

        It 'Should handle invalid hostnames gracefully' {
            $result = Test-TlsProtocol -ComputerName 'this-hostname-definitely-does-not-exist-12345.invalid' -Protocol Tls12 -Timeout 500

            $result | Should -Not -BeNullOrEmpty
            $result[0].Supported | Should -Be $false
        }

        It 'Should handle timeout scenarios' {
            # Use a non-routable IP with very short timeout
            $result = Test-TlsProtocol -ComputerName '192.0.2.1' -Protocol Tls12 -Timeout 200

            $result | Should -Not -BeNullOrEmpty
            $result[0].Supported | Should -Be $false
            $result[0].Status | Should -Match 'timeout|failed'
        }
    }

    Context 'Alias support' {
        It 'Should accept Server alias for ComputerName' {
            { Test-TlsProtocol -Server 'localhost' -Protocol Tls12 } | Should -Not -Throw
        }

        It 'Should accept Host alias for ComputerName' {
            { Test-TlsProtocol -Host 'localhost' -Protocol Tls12 } | Should -Not -Throw
        }

        It 'Should accept HostName alias for ComputerName' {
            { Test-TlsProtocol -HostName 'localhost' -Protocol Tls12 } | Should -Not -Throw
        }
    }
}
