#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Test-TlsProtocol function.

.DESCRIPTION
    Integration tests that verify Test-TlsProtocol functionality against real network services
    and external hosts. Tests actual TLS protocol support on well-known public endpoints.

.NOTES
    These integration tests validate real-world network scenarios including:
    - Testing against actual remote HTTPS services
    - TLS protocol version support validation
    - Network timeout handling
    - Performance characteristics

    Tests use well-known public endpoints with known TLS configurations.
#>

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Test-TlsProtocol.ps1"
}

Describe 'Test-TlsProtocol Integration Tests' {
    Context 'Real-world TLS protocol testing' {
        It 'Should successfully test TLS 1.2 on a known HTTPS endpoint' {
            # Test against a reliable public endpoint that supports TLS 1.2
            $result = Test-TlsProtocol -ComputerName 'www.google.com' -Protocol Tls12 -Timeout 10000

            $result | Should -Not -BeNullOrEmpty
            $result.Server | Should -Be 'www.google.com'
            $result.Port | Should -Be 443
            $result.Protocol | Should -Be 'Tls12'
            $result.Supported | Should -Be $true
            $result.Status | Should -Be 'Success'
            $result.ResponseTime | Should -BeGreaterThan ([TimeSpan]::Zero)
        }

        It 'Should successfully test TLS 1.3 on a modern HTTPS endpoint' {
            # Test TLS 1.3 on a known modern endpoint
            $result = Test-TlsProtocol -ComputerName 'www.cloudflare.com' -Protocol Tls13 -Timeout 10000

            $result | Should -Not -BeNullOrEmpty
            $result.Server | Should -Be 'www.cloudflare.com'
            $result.Protocol | Should -Be 'Tls13'
            # TLS 1.3 may or may not be supported depending on the .NET version
            $result.Supported | Should -BeOfType [Boolean]
            $result.Status | Should -Not -BeNullOrEmpty
        }

        It 'Should test multiple TLS protocols on modern endpoints' {
            # Test TLS 1.0 and 1.1 (whether supported or not depends on server configuration)
            $result = Test-TlsProtocol -ComputerName 'www.google.com' -Protocol Tls, Tls11 -Timeout 10000

            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 2

            # Verify protocols were tested
            $result[0].Protocol | Should -Be 'Tls'
            $result[1].Protocol | Should -Be 'Tls11'

            # Each result should have a status
            $result[0].Status | Should -Not -BeNullOrEmpty
            $result[1].Status | Should -Not -BeNullOrEmpty

            # Response times should be recorded
            $result[0].ResponseTime | Should -Not -BeNullOrEmpty
            $result[1].ResponseTime | Should -Not -BeNullOrEmpty
        }

        It 'Should test all protocols on a public endpoint' {
            # Test all protocols to get a complete picture
            $result = Test-TlsProtocol -ComputerName 'www.github.com' -Timeout 10000

            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 4

            # Verify all protocols were tested
            $protocols = $result | Select-Object -ExpandProperty Protocol
            $protocols | Should -Contain 'Tls'
            $protocols | Should -Contain 'Tls11'
            $protocols | Should -Contain 'Tls12'
            $protocols | Should -Contain 'Tls13'

            # GitHub should support at least TLS 1.2
            $tls12Result = $result | Where-Object { $_.Protocol -eq 'Tls12' }
            $tls12Result.Supported | Should -Be $true
        }
    }

    Context 'Error handling with real endpoints' {
        It 'Should handle non-existent hosts gracefully' {
            $result = Test-TlsProtocol -ComputerName 'this-host-absolutely-does-not-exist-12345.invalid' -Protocol Tls12 -Timeout 3000

            $result | Should -Not -BeNullOrEmpty
            $result.Supported | Should -Be $false
            $result.Status | Should -Not -Be 'Success'
        }

        It 'Should handle connection timeout to unreachable hosts' {
            # Use a non-routable IP address (TEST-NET-1 from RFC 5737)
            $result = Test-TlsProtocol -ComputerName '192.0.2.1' -Protocol Tls12 -Timeout 2000

            $result | Should -Not -BeNullOrEmpty
            $result.Supported | Should -Be $false
            $result.Status | Should -Match 'timeout|failed'
        }

        It 'Should handle non-HTTPS ports gracefully' {
            # Test a known HTTP port (80) which doesn't support TLS
            $result = Test-TlsProtocol -ComputerName 'www.google.com' -Port 80 -Protocol Tls12 -Timeout 5000

            $result | Should -Not -BeNullOrEmpty
            # Connection might succeed but TLS handshake should fail
            $result.Supported | Should -Be $false
        }
    }

    Context 'Performance characteristics' {
        It 'Should complete TLS testing within reasonable time' {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-TlsProtocol -ComputerName 'www.google.com' -Protocol Tls12 -Timeout 10000
            $stopwatch.Stop()

            # Should complete within timeout plus overhead (15 seconds total)
            $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 15
            $result.ResponseTime.TotalSeconds | Should -BeLessThan 10
        }

        It 'Should test multiple protocols efficiently' {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-TlsProtocol -ComputerName 'www.cloudflare.com' -Protocol Tls12, Tls13 -Timeout 10000
            $stopwatch.Stop()

            $result | Should -HaveCount 2
            # Testing 2 protocols should complete in reasonable time (30 seconds with overhead)
            $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 30
        }
    }

    Context 'Pipeline input with real endpoints' {
        It 'Should handle multiple servers via pipeline' {
            $servers = @('www.google.com', 'www.github.com')
            $result = $servers | Test-TlsProtocol -Protocol Tls12 -Timeout 10000

            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 2
            $result[0].Server | Should -Be 'www.google.com'
            $result[1].Server | Should -Be 'www.github.com'

            # Both should support TLS 1.2
            $result | ForEach-Object {
                $_.Protocol | Should -Be 'Tls12'
                $_.Supported | Should -Be $true
            }
        }
    }

    Context 'Custom ports' {
        It 'Should work with custom HTTPS ports if available' {
            # Most public services use 443, but this validates the port parameter works
            $result = Test-TlsProtocol -ComputerName 'www.google.com' -Port 443 -Protocol Tls12 -Timeout 10000

            $result | Should -Not -BeNullOrEmpty
            $result.Port | Should -Be 443
            $result.Supported | Should -Be $true
        }
    }
}
