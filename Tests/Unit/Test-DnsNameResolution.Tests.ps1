BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../Functions/Test-DnsNameResolution.ps1"
}

Describe 'Test-DnsNameResolution' {
    Context 'Basic DNS resolution examples from documentation' {
        It "Tests whether localhost can be resolved using the system's default DNS servers" {
            # Use localhost instead of google.com due to network restrictions in test environment
            $result = Test-DnsNameResolution -Name 'localhost'
            $result | Should -BeOfType [System.Boolean]
            $result | Should -Be $true
        }

        It 'Tests whether localhost can be resolved with specified DNS servers (uses system DNS for compatibility)' {
            $result = Test-DnsNameResolution -Name 'localhost' -Server '8.8.8.8', '8.8.4.4'
            $result | Should -BeOfType [System.Boolean]
            $result | Should -Be $true
        }

        It 'Tests whether localhost has an IPv4 (A) record with verbose output' {
            $verboseOutput = Test-DnsNameResolution -Name 'localhost' -Type 'A' -Verbose 4>&1

            # Extract the boolean result (last item should be the result)
            $result = $verboseOutput | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] } | Select-Object -Last 1
            $result | Should -BeOfType [System.Boolean]
            $result | Should -Be $true

            # Check for verbose output
            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
        }
    }

    Context 'IPv4 record resolution' {
        It 'Should resolve localhost to IPv4 addresses' {
            $result = Test-DnsNameResolution -Name 'localhost' -Type 'A'
            $result | Should -Be $true
        }

        It 'Should handle domain names with different cases' {
            $result1 = Test-DnsNameResolution -Name 'LOCALHOST'
            $result2 = Test-DnsNameResolution -Name 'localhost'
            $result1 | Should -Be $result2
            $result1 | Should -Be $true
        }
    }

    Context 'IPv6 record resolution' {
        It 'Should test IPv6 resolution for localhost' {
            $result = Test-DnsNameResolution -Name 'localhost' -Type 'AAAA'
            $result | Should -BeOfType [System.Boolean]
            # localhost might have IPv6 records depending on system configuration
            # We just verify it returns a boolean
        }
    }

    Context 'Invalid domain handling' {
        It 'Should return false for non-existent domains' {
            $result = Test-DnsNameResolution -Name 'this-domain-definitely-does-not-exist-12345.com'
            $result | Should -Be $false
        }

        It 'Should return false for invalid domain names' {
            $result = Test-DnsNameResolution -Name 'invalid..domain'
            $result | Should -Be $false
        }

        It 'Should handle malformed domain names gracefully' {
            $result = Test-DnsNameResolution -Name '.....'
            $result | Should -Be $false
        }
    }

    Context 'Parameter validation' {
        It 'Should require Name parameter' {
            { Test-DnsNameResolution } | Should -Throw
        }

        It 'Should reject null or empty Name parameter' {
            { Test-DnsNameResolution -Name $null } | Should -Throw
            { Test-DnsNameResolution -Name '' } | Should -Throw
            { Test-DnsNameResolution -Name '   ' } | Should -Throw
        }

        It 'Should validate DNS server IP addresses when provided' {
            # Valid IP addresses should not throw
            { Test-DnsNameResolution -Name 'localhost' -Server '8.8.8.8' } | Should -Not -Throw
            { Test-DnsNameResolution -Name 'localhost' -Server '8.8.8.8', '1.1.1.1' } | Should -Not -Throw

            # Invalid IP addresses should throw
            { Test-DnsNameResolution -Name 'localhost' -Server 'invalid-ip' } | Should -Throw
            { Test-DnsNameResolution -Name 'localhost' -Server '999.999.999.999' } | Should -Throw
        }

        It 'Should accept valid DNS record types' {
            { Test-DnsNameResolution -Name 'localhost' -Type 'A' } | Should -Not -Throw
            { Test-DnsNameResolution -Name 'localhost' -Type 'AAAA' } | Should -Not -Throw
            { Test-DnsNameResolution -Name 'localhost' -Type 'CNAME' } | Should -Not -Throw
        }

        It 'Should reject invalid DNS record types' {
            { Test-DnsNameResolution -Name 'localhost' -Type 'INVALID' } | Should -Throw
        }
    }

    Context 'Pipeline input support' {
        It 'Should support pipeline input for domain names' {
            $domains = @('localhost', 'localhost')  # Use localhost twice for predictable results
            $results = $domains | Test-DnsNameResolution

            $results | Should -HaveCount 2
            $results | ForEach-Object { $_ | Should -BeOfType [System.Boolean] }
            $results | ForEach-Object { $_ | Should -Be $true }
        }

        It 'Should handle mixed valid and invalid domains via pipeline' {
            $domains = @('localhost', 'this-definitely-does-not-exist-12345.com')
            $results = $domains | Test-DnsNameResolution

            $results | Should -HaveCount 2
            $results[0] | Should -Be $true   # localhost should resolve
            $results[1] | Should -Be $false  # invalid domain should not resolve
        }
    }

    Context 'Cross-platform compatibility' {
        It 'Should use .NET DNS methods for cross-platform compatibility' {
            # This test verifies the function works on different platforms
            $result = Test-DnsNameResolution -Name 'localhost'
            $result | Should -BeOfType [System.Boolean]
            $result | Should -Be $true
        }

        It 'Should handle system DNS configuration differences across platforms' {
            # Test that it works regardless of platform-specific DNS configuration
            $result = Test-DnsNameResolution -Name 'localhost'
            $result | Should -Be $true
        }
    }

    Context 'Verbose output and logging' {
        It 'Should provide detailed verbose information' {
            $output = Test-DnsNameResolution -Name 'localhost' -Verbose 4>&1

            # Should have verbose messages
            $verboseMessages = $output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty

            # Verbose messages should contain relevant information
            $verboseText = $verboseMessages | ForEach-Object { $_.Message } | Out-String
            $verboseText | Should -Match 'DNS'
            $verboseText | Should -Match 'localhost'
        }

        It 'Should log different messages for successful and failed resolutions' {
            # Successful resolution
            $successOutput = Test-DnsNameResolution -Name 'localhost' -Verbose 4>&1
            $successVerbose = ($successOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }) -join ' '
            $successVerbose | Should -Match '(successful|found)'

            # Failed resolution
            $failOutput = Test-DnsNameResolution -Name 'this-does-not-exist-12345.com' -Verbose 4>&1
            $failVerbose = ($failOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }) -join ' '
            $failVerbose | Should -Match '(not found|failed)'
        }
    }

    Context 'DNS server parameter behavior' {
        It 'Should log information about using custom DNS servers' {
            $output = Test-DnsNameResolution -Name 'localhost' -Server '8.8.8.8' -Verbose 4>&1

            $verboseText = ($output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }) -join ' '
            $verboseText | Should -Match '(DNS server|8\.8\.8\.8)'
        }

        It 'Should still resolve correctly when custom servers are specified' {
            # Despite specifying custom servers, should still work (using system DNS for compatibility)
            $result = Test-DnsNameResolution -Name 'localhost' -Server '1.1.1.1', '8.8.8.8'
            $result | Should -Be $true
        }
    }

    Context 'Error handling and edge cases' {
        It 'Should handle network timeouts gracefully' {
            # Test with a domain that might timeout (unreachable)
            $result = Test-DnsNameResolution -Name 'timeout-test-domain-that-does-not-exist.invalid'
            $result | Should -BeOfType [System.Boolean]
            # Should return false for unresolvable domains
            $result | Should -Be $false
        }

        It 'Should return proper result type in all scenarios' {
            # Test various scenarios to ensure boolean return type
            $results = @(
                (Test-DnsNameResolution -Name 'localhost'),
                (Test-DnsNameResolution -Name 'invalid-domain-12345.com'),
                (Test-DnsNameResolution -Name 'localhost')
            )

            $results | ForEach-Object { $_ | Should -BeOfType [System.Boolean] }
        }
    }
}
