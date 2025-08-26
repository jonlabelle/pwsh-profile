BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../Functions/Test-Port.ps1"
}

Describe "Test-Port Integration Tests" {
    Context "Real-world port testing scenarios" {
        It "Should test common well-known ports on localhost" {
            # Test common ports that might be available on localhost
            $ports = @(22, 80, 443, 53, 25)  # SSH, HTTP, HTTPS, DNS, SMTP
            $result = $ports | Test-Port -ComputerName 'localhost' -Timeout 3000
            
            $result | Should -HaveCount 5
            $result | ForEach-Object {
                $_.Server | Should -Be 'localhost'
                $_.Protocol | Should -Be 'TCP'
                $_.Open | Should -BeOfType [Boolean]
                $_.Status | Should -Not -BeNullOrEmpty
                $_.ResponseTime | Should -BeGreaterOrEqual 0
            }
        }

        It "Should handle mixed TCP and UDP testing" {
            # Test TCP port first
            $tcpResult = Test-Port -Port 80 -ComputerName 'localhost' -Tcp
            $tcpResult[0].Protocol | Should -Be 'TCP'
            
            # Test UDP port
            $udpResult = Test-Port -Port 53 -ComputerName 'localhost' -Udp
            $udpResult[0].Protocol | Should -Be 'UDP'
            
            # Both should return valid results
            $tcpResult[0].Open | Should -BeOfType [Boolean]
            $udpResult[0].Open | Should -BeOfType [Boolean]
        }

        It "Should efficiently test port ranges" {
            # Test a small range of ports
            $result = 8080..8085 | Test-Port -ComputerName 'localhost' -Timeout 2000
            
            $result | Should -HaveCount 6
            $result | ForEach-Object {
                $_.Port | Should -BeGreaterOrEqual 8080
                $_.Port | Should -BeLessOrEqual 8085
                $_.Server | Should -Be 'localhost'
            }
        }

        It "Should handle timeout scenarios gracefully" {
            # Use a very short timeout to test timeout handling
            $result = Test-Port -Port 9999 -ComputerName 'localhost' -Timeout 500
            
            $result | Should -Not -BeNullOrEmpty
            $result[0].Open | Should -Be $false
            $result[0].Status | Should -Match '(timeout|refused|failed)'
        }
    }

    Context "Performance testing" {
        It "Should complete localhost tests quickly" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = 80,443,22 | Test-Port -ComputerName 'localhost'
            $stopwatch.Stop()
            
            # Should complete reasonably quickly for localhost
            $stopwatch.ElapsedMilliseconds | Should -BeLessOrEqual 10000  # 10 seconds
            $result | Should -HaveCount 3
        }

        It "Should handle concurrent port tests efficiently" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-Port -ComputerName @('localhost', '127.0.0.1') -Port @(80, 443)
            $stopwatch.Stop()
            
            # Should test 2 hosts × 2 ports = 4 tests
            $result | Should -HaveCount 4
            # Should be efficient enough to complete quickly
            $stopwatch.ElapsedMilliseconds | Should -BeLessOrEqual 15000
        }
    }

    Context "Network edge cases" {
        It "Should handle unreachable hosts appropriately" {
            # Use a reserved IP that should be unreachable
            $result = Test-Port -ComputerName '192.0.2.1' -Port 80 -Timeout 2000
            
            $result | Should -Not -BeNullOrEmpty
            $result[0].Open | Should -Be $false
            $result[0].Status | Should -Match '(timeout|unreachable|failed)'
        }

        It "Should distinguish between different failure types" {
            # Test a closed port vs timeout
            $closedPortResult = Test-Port -Port 9998 -ComputerName 'localhost' -Timeout 2000
            
            $closedPortResult | Should -Not -BeNullOrEmpty
            $closedPortResult[0].Open | Should -Be $false
            # Status should indicate the type of failure
            $closedPortResult[0].Status | Should -Not -BeNullOrEmpty
        }
    }

    Context "Protocol-specific behavior" {
        It "Should handle TCP connection states properly" {
            # Test both potentially open and definitely closed ports
            $results = @(
                (Test-Port -Port 80 -ComputerName 'localhost' -Tcp),
                (Test-Port -Port 9997 -ComputerName 'localhost' -Tcp -Timeout 2000)
            )
            
            $results | Should -HaveCount 2
            $results | ForEach-Object {
                $_[0].Protocol | Should -Be 'TCP'
                $_[0].Open | Should -BeOfType [Boolean]
                $_[0].Status | Should -Not -BeNullOrEmpty
            }
        }

        It "Should handle UDP port testing characteristics" {
            # UDP testing is inherently different from TCP
            $result = Test-Port -Port 53 -ComputerName 'localhost' -Udp -Timeout 3000
            
            $result[0].Protocol | Should -Be 'UDP'
            $result[0].Open | Should -BeOfType [Boolean]
            
            # UDP results often have specific status messages
            $result[0].Status | Should -Match '(response|timeout|unreachable|filtered|open)'
        }
    }

    Context "Real-world usage patterns" {
        It "Should support common network troubleshooting scenarios" {
            # Simulate checking if web services are running
            $webPorts = @(80, 443, 8080)
            $result = $webPorts | Test-Port -ComputerName 'localhost'
            
            $result | Should -HaveCount 3
            $result | ForEach-Object {
                $_.Port | Should -BeIn $webPorts
                $_.Protocol | Should -Be 'TCP'  # Default protocol
            }
        }

        It "Should handle service discovery patterns" {
            # Test multiple services on localhost
            $services = @{
                'SSH' = 22
                'HTTP' = 80
                'HTTPS' = 443
                'DNS' = 53
            }
            
            $results = $services.Values | Test-Port -ComputerName 'localhost'
            
            $results | Should -HaveCount 4
            $results | ForEach-Object {
                $_.Port | Should -BeIn $services.Values
                $_.Server | Should -Be 'localhost'
            }
        }

        It "Should provide actionable information for network diagnostics" {
            $result = Test-Port -Port 80 -ComputerName 'localhost'
            
            # Should provide enough information for diagnostics
            $result[0] | Should -HaveProperty 'Server'
            $result[0] | Should -HaveProperty 'Port'
            $result[0] | Should -HaveProperty 'Protocol'
            $result[0] | Should -HaveProperty 'Open'
            $result[0] | Should -HaveProperty 'Status'
            $result[0] | Should -HaveProperty 'ResponseTime'
            
            # All properties should have meaningful values
            $result[0].Server | Should -Not -BeNullOrEmpty
            $result[0].Port | Should -BeGreaterThan 0
            $result[0].Protocol | Should -Not -BeNullOrEmpty
            $result[0].Status | Should -Not -BeNullOrEmpty
            $result[0].ResponseTime | Should -BeGreaterOrEqual 0
        }
    }

    Context "Stress and reliability testing" {
        It "Should handle a moderate number of port tests" {
            # Test 10 ports to ensure it can handle moderate loads
            $result = 8000..8009 | Test-Port -ComputerName 'localhost' -Timeout 1500
            
            $result | Should -HaveCount 10
            $result | ForEach-Object {
                $_ | Should -Not -BeNullOrEmpty
                $_.Port | Should -BeGreaterOrEqual 8000
                $_.Port | Should -BeLessOrEqual 8009
            }
        }

        It "Should maintain consistency across multiple runs" {
            # Run the same test twice and compare results for consistency
            $result1 = Test-Port -Port 80 -ComputerName 'localhost'
            $result2 = Test-Port -Port 80 -ComputerName 'localhost'
            
            # Results should be consistent for the same port/host
            $result1[0].Server | Should -Be $result2[0].Server
            $result1[0].Port | Should -Be $result2[0].Port
            $result1[0].Protocol | Should -Be $result2[0].Protocol
            # Open status should be the same for the same service
            $result1[0].Open | Should -Be $result2[0].Open
        }
    }
}