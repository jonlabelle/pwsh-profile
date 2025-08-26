BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../Functions/Test-Port.ps1"
}

Describe "Test-Port" {
    Context "Basic functionality examples from documentation" {
        It "Tests if TCP port 80 is open on localhost" {
            # Use localhost since we can't test external servers
            $result = Test-Port -ComputerName 'localhost' -Port 22  # SSH is more likely to be available
            $result | Should -Not -BeNullOrEmpty
            
            # Function returns an array even for single results
            if ($result.Count -eq 1) {
                $testResult = $result[0]
            } else {
                $testResult = $result
            }
            
            $testResult | Should -HaveProperty 'Server'
            $testResult | Should -HaveProperty 'Port'
            $testResult | Should -HaveProperty 'Protocol'
            $testResult | Should -HaveProperty 'Open'
            $testResult | Should -HaveProperty 'Status'
            $testResult | Should -HaveProperty 'ResponseTime'
            $testResult.Server | Should -Be 'localhost'
            $testResult.Port | Should -Be 22
            $testResult.Protocol | Should -Be 'TCP'
        }

        It "Tests if TCP port 80 is open on localhost using pipeline input for the port" {
            $result = 80 | Test-Port
            $result | Should -Not -BeNullOrEmpty
            
            $testResult = if ($result.Count -eq 1) { $result[0] } else { $result }
            $testResult.Port | Should -Be 80
            $testResult.Server | Should -Be 'localhost'  # Default when no ComputerName specified
        }

        It "Tests if TCP ports 22, 80, and 443 are open on localhost using pipeline input" {
            $result = 22,80,443 | Test-Port
            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 3
            $result[0].Port | Should -Be 22
            $result[1].Port | Should -Be 80
            $result[2].Port | Should -Be 443
            $result | ForEach-Object { $_.Server | Should -Be 'localhost' }
        }

        It "Tests TCP ports 1-5 on localhost using pipeline input for port range" {
            $result = 1..5 | Test-Port -ComputerName 'localhost'
            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 5
            $result[0].Port | Should -Be 1
            $result[4].Port | Should -Be 5
            $result | ForEach-Object { $_.Server | Should -Be 'localhost' }
        }

        It "Tests if TCP port 80 is open on localhost (array input)" {
            $result = Test-Port -ComputerName @("localhost") -Port 80
            $result | Should -Not -BeNullOrEmpty
            $result[0].Server | Should -Be 'localhost'
            $result[0].Port | Should -Be 80
        }

        It "Tests if UDP port 53 is open on localhost with timeout" {
            $result = Test-Port -ComputerName 'localhost' -Port 53 -Udp -Timeout 5000
            $result | Should -Not -BeNullOrEmpty
            $result[0].Protocol | Should -Be 'UDP'
            $result[0].Port | Should -Be 53
        }
    }

    Context "Pipeline input scenarios" {
        It "Tests multiple ports on localhost using pipeline input for ports" {
            $result = 80,443 | Test-Port -ComputerName 'localhost'
            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 2
            $result | ForEach-Object { $_.Server | Should -Be 'localhost' }
        }

        It "Tests a range of ports using pipeline input" {
            $result = 1..3 | Test-Port -ComputerName 'localhost'
            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 3
            $result[0].Port | Should -Be 1
            $result[1].Port | Should -Be 2
            $result[2].Port | Should -Be 3
        }
    }

    Context "Parameter validation" {
        It "Should accept valid port numbers" {
            { Test-Port -Port 80 } | Should -Not -Throw
            { Test-Port -Port 1 } | Should -Not -Throw
            { Test-Port -Port 65535 } | Should -Not -Throw
        }

        It "Should reject invalid port numbers" {
            { Test-Port -Port 0 } | Should -Throw
            { Test-Port -Port 65536 } | Should -Throw
            { Test-Port -Port -1 } | Should -Throw
        }

        It "Should accept valid timeout values" {
            { Test-Port -Port 80 -Timeout 100 } | Should -Not -Throw
            { Test-Port -Port 80 -Timeout 300000 } | Should -Not -Throw
        }

        It "Should reject invalid timeout values" {
            { Test-Port -Port 80 -Timeout 99 } | Should -Throw
            { Test-Port -Port 80 -Timeout 300001 } | Should -Throw
        }
    }

    Context "Protocol selection" {
        It "Should default to TCP when no protocol is specified" {
            $result = Test-Port -Port 80
            $result[0].Protocol | Should -Be 'TCP'
        }

        It "Should use TCP when Tcp switch is specified" {
            $result = Test-Port -Port 80 -Tcp
            $result[0].Protocol | Should -Be 'TCP'
        }

        It "Should use UDP when Udp switch is specified" {
            $result = Test-Port -Port 53 -Udp
            $result[0].Protocol | Should -Be 'UDP'
        }
    }

    Context "Output structure validation" {
        It "Should return objects with all required properties" {
            $result = Test-Port -Port 80
            $result | Should -Not -BeNullOrEmpty
            
            $testResult = if ($result.Count -eq 1) { $result[0] } else { $result }
            
            $testResult | Should -HaveProperty 'PSTypeName'
            $testResult | Should -HaveProperty 'Server'
            $testResult | Should -HaveProperty 'Port'
            $testResult | Should -HaveProperty 'Protocol'
            $testResult | Should -HaveProperty 'Open'
            $testResult | Should -HaveProperty 'Status'
            $testResult | Should -HaveProperty 'ResponseTime'
            
            # Check data types
            $testResult.PSTypeName | Should -Be 'PortTest.Result'
            $testResult.Server | Should -BeOfType [String]
            $testResult.Port | Should -BeOfType [Int32]
            $testResult.Protocol | Should -BeOfType [String]
            $testResult.Open | Should -BeOfType [Boolean]
            $testResult.Status | Should -BeOfType [String]
            $testResult.ResponseTime | Should -BeOfType [Int64]
        }

        It "Should have reasonable response times" {
            $result = Test-Port -Port 80 -ComputerName 'localhost'
            $testResult = if ($result.Count -eq 1) { $result[0] } else { $result }
            $testResult.ResponseTime | Should -BeGreaterOrEqual 0
            $testResult.ResponseTime | Should -BeLessOrEqual 10000  # 10 seconds should be more than enough for localhost
        }
    }

    Context "Multiple computers support" {
        It "Should handle multiple target computers" {
            # Test with localhost multiple times to simulate multiple computers
            $result = Test-Port -ComputerName @('localhost', '127.0.0.1') -Port 80
            $result | Should -HaveCount 2
            $result[0].Server | Should -Be 'localhost'
            $result[1].Server | Should -Be '127.0.0.1'
            $result | ForEach-Object { $_.Port | Should -Be 80 }
        }

        It "Should skip empty or null computer names" {
            $result = Test-Port -ComputerName @('localhost', '', $null, 'localhost') -Port 80
            # Should only process the valid entries
            $result | Should -HaveCount 2
            $result | ForEach-Object { $_.Server | Should -Be 'localhost' }
        }
    }

    Context "Error handling" {
        It "Should handle connection timeouts gracefully" {
            # Use a port that's likely closed to test timeout behavior
            $result = Test-Port -Port 9999 -Timeout 1000  # 1 second timeout
            $result | Should -Not -BeNullOrEmpty
            $result[0].Open | Should -Be $false
            $result[0].Status | Should -Match '(timeout|refused|failed)'
        }

        It "Should provide meaningful error messages" {
            $result = Test-Port -Port 9999 -ComputerName 'localhost'
            $result | Should -Not -BeNullOrEmpty
            $result[0].Status | Should -Not -BeNullOrEmpty
            # Status should be descriptive
            $result[0].Status | Should -Match '(refused|timeout|failed|unreachable)'
        }
    }

    Context "TCP specific tests" {
        It "Should properly test TCP connections" {
            $result = Test-Port -Port 80 -Tcp -ComputerName 'localhost'
            $result[0].Protocol | Should -Be 'TCP'
            $result[0].Open | Should -BeOfType [Boolean]
        }

        It "Should handle TCP connection failures appropriately" {
            # Test a port that's likely to be closed
            $result = Test-Port -Port 9998 -Tcp -ComputerName 'localhost' -Timeout 2000
            $result[0].Protocol | Should -Be 'TCP'
            $result[0].Open | Should -Be $false
        }
    }

    Context "UDP specific tests" {
        It "Should properly test UDP connections" {
            $result = Test-Port -Port 53 -Udp -ComputerName 'localhost'
            $result[0].Protocol | Should -Be 'UDP'
            $result[0].Open | Should -BeOfType [Boolean]
        }

        It "Should handle UDP port testing with appropriate status messages" {
            $result = Test-Port -Port 9997 -Udp -ComputerName 'localhost' -Timeout 3000
            $result[0].Protocol | Should -Be 'UDP'
            # UDP results are often ambiguous, but should have a status
            $result[0].Status | Should -Not -BeNullOrEmpty
        }
    }

    Context "Performance and reliability" {
        It "Should complete port tests within reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-Port -Port 80 -ComputerName 'localhost'
            $stopwatch.Stop()
            
            # Should complete quickly for localhost
            $stopwatch.ElapsedMilliseconds | Should -BeLessOrEqual 5000
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should handle port ranges efficiently" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = 80..85 | Test-Port -ComputerName 'localhost'
            $stopwatch.Stop()
            
            $result | Should -HaveCount 6
            # Should be reasonably fast for small ranges
            $stopwatch.ElapsedMilliseconds | Should -BeLessOrEqual 15000
        }
    }

    Context "Cross-platform compatibility" {
        It "Should work on current platform" {
            # Basic test to ensure it works on the current platform
            $result = Test-Port -Port 80 -ComputerName 'localhost'
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -HaveProperty 'Open'
            $result[0] | Should -HaveProperty 'Status'
        }
    }
}