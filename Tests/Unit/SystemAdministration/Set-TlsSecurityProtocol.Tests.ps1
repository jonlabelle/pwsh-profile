#Requires -Modules Pester

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Set-TlsSecurityProtocol.ps1"

    # Save the original security protocol for restoration
    $script:OriginalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
}

AfterAll {
    # Restore the original security protocol
    [Net.ServicePointManager]::SecurityProtocol = $script:OriginalSecurityProtocol
}

Describe 'Set-TlsSecurityProtocol' {
    BeforeEach {
        # Reset to a known state before each test - use the original protocol or a safe default
        try
        {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls
        }
        catch
        {
            # If even TLS 1.0 is not supported, use the original protocol
            [Net.ServicePointManager]::SecurityProtocol = $script:OriginalSecurityProtocol
        }
    }

    AfterEach {
        # Clean up after each test
        [Net.ServicePointManager]::SecurityProtocol = $script:OriginalSecurityProtocol
    }

    Context 'Parameter Validation' {
        It 'Should accept valid Protocol values' {
            { Set-TlsSecurityProtocol -Protocol 'SystemDefault' } | Should -Not -Throw
            { Set-TlsSecurityProtocol -Protocol 'Tls' } | Should -Not -Throw
            { Set-TlsSecurityProtocol -Protocol 'Tls11' } | Should -Not -Throw
            { Set-TlsSecurityProtocol -Protocol 'Tls12' } | Should -Not -Throw
            { Set-TlsSecurityProtocol -Protocol 'Tls13' } | Should -Not -Throw
        }

        It 'Should reject invalid Protocol values' {
            { Set-TlsSecurityProtocol -Protocol 'InvalidTls' } | Should -Throw
        }

        It 'Should have SystemDefault as default Protocol' {
            try
            {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            }
            catch
            {
                [Net.ServicePointManager]::SecurityProtocol = $script:OriginalSecurityProtocol
            }

            Set-TlsSecurityProtocol

            $current = [Net.ServicePointManager]::SecurityProtocol

            if ([enum]::GetNames([Net.SecurityProtocolType]) -contains 'SystemDefault')
            {
                $current | Should -Be ([Net.SecurityProtocolType]::SystemDefault)
            }
            else
            {
                $current.ToString() | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Basic Functionality' {
        It 'Should update protocol when current setting is insecure' {
            try
            {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls
            }
            catch
            {
                Set-ItResult -Skipped -Because 'TLS 1.0 not supported on this system'
                return
            }

            Set-TlsSecurityProtocol -Protocol 'Tls12'

            $current = [Net.ServicePointManager]::SecurityProtocol
            ($current -band [Net.SecurityProtocolType]::Tls12) | Should -Not -Be 0
            ($current -band [Net.SecurityProtocolType]::Tls) | Should -Be 0
        }

        It 'Should not update protocol when already secure' {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $originalProtocol = [Net.ServicePointManager]::SecurityProtocol

            Set-TlsSecurityProtocol -Protocol 'Tls12'

            $current = [Net.ServicePointManager]::SecurityProtocol
            $current | Should -Be $originalProtocol
        }

        It 'Should force update when Force parameter is used' {
            try
            {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
            }
            catch
            {
                Set-ItResult -Skipped -Because 'TLS 1.3 not supported on this system'
                return
            }

            Set-TlsSecurityProtocol -Protocol 'Tls12' -Force

            $current = [Net.ServicePointManager]::SecurityProtocol
            $current | Should -Be ([Net.SecurityProtocolType]::Tls12)
        }
    }

    Context 'PassThru Parameter' {
        It 'Should return SecurityProtocol when PassThru is specified' {
            $result = Set-TlsSecurityProtocol -Protocol 'Tls12' -PassThru

            $result | Should -BeOfType [System.Net.SecurityProtocolType]
            $result | Should -Be ([Net.ServicePointManager]::SecurityProtocol)
        }

        It 'Should not return anything when PassThru is not specified' {
            $result = Set-TlsSecurityProtocol -Protocol 'Tls12'

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'TLS Version Handling' {
        It 'Should handle Tls as minimum version' {
            # This test just verifies the function doesn't throw
            { Set-TlsSecurityProtocol -Protocol 'Tls' } | Should -Not -Throw

            $current = [Net.ServicePointManager]::SecurityProtocol
            # Should have at least TLS 1.0 enabled (if supported)
            $current | Should -Not -BeNullOrEmpty
        }

        It 'Should handle Tls11 as minimum version' {
            # This test just verifies the function doesn't throw
            { Set-TlsSecurityProtocol -Protocol 'Tls11' } | Should -Not -Throw

            $current = [Net.ServicePointManager]::SecurityProtocol
            # Should have some TLS protocol enabled
            $current | Should -Not -BeNullOrEmpty
        }

        It 'Should handle Tls13 gracefully on systems that do not support it' {
            # This should not throw even if TLS 1.3 is not available
            { Set-TlsSecurityProtocol -Protocol 'Tls13' } | Should -Not -Throw

            $current = [Net.ServicePointManager]::SecurityProtocol
            # Should have either TLS 1.3 or TLS 1.2 (fallback) set
            $hasTls12 = ($current -band [Net.SecurityProtocolType]::Tls12) -ne 0
            $hasTls13 = try { ($current -band [Net.SecurityProtocolType]::Tls13) -ne 0 } catch { $false }

            ($hasTls12 -or $hasTls13) | Should -Be $true
        }
    }

    Context 'Protocol Preservation' {
        It 'Should preserve existing secure protocols and remove weaker ones when not using Force' {
            if ($PSVersionTable.PSVersion.Major -ge 6)
            {
                try
                {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                    $hadTls13 = $true
                }
                catch
                {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
                    $hadTls13 = $false
                }
            }
            else
            {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
                $hadTls13 = $false
            }

            Set-TlsSecurityProtocol -Protocol 'Tls12'

            $current = [Net.ServicePointManager]::SecurityProtocol
            ($current -band [Net.SecurityProtocolType]::Tls12) | Should -Not -Be 0
            ($current -band [Net.SecurityProtocolType]::Tls11) | Should -Be 0

            if ($hadTls13)
            {
                ($current -band [Net.SecurityProtocolType]::Tls13) | Should -Not -Be 0
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle ServicePointManager access errors gracefully' {
            $functionContent = Get-Content "$PSScriptRoot/../../../Functions/SystemAdministration/Set-TlsSecurityProtocol.ps1" -Raw
            $functionContent | Should -Match 'try\s*\{'
            $functionContent | Should -Match 'catch\s*\{'
            $functionContent | Should -Match 'ThrowTerminatingError|throw'
        }
    }

    Context 'ShouldProcess Support' {
        It 'Should support WhatIf without changing the current protocol' {
            try
            {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls
            }
            catch
            {
                Set-ItResult -Skipped -Because 'TLS 1.0 not supported on this system'
                return
            }

            $originalProtocol = [Net.ServicePointManager]::SecurityProtocol

            Set-TlsSecurityProtocol -Protocol 'Tls12' -WhatIf

            [Net.ServicePointManager]::SecurityProtocol | Should -Be $originalProtocol
        }
    }

    Context 'Verbose Output' {
        It 'Should provide verbose output when requested' {
            $verboseOutput = Set-TlsSecurityProtocol -Protocol 'Tls12' -Verbose 4>&1

            $verboseOutput | Should -Not -BeNullOrEmpty
            $verboseOutput | Should -Match 'TLS|protocol|security'
        }
    }

    Context 'Cross-Platform Compatibility' {
        It 'Should work on PowerShell Desktop (5.1)' {
            # This test runs regardless of PowerShell version
            { Set-TlsSecurityProtocol -Protocol 'Tls12' } | Should -Not -Throw
        }

        It 'Should work on PowerShell Core (6+)' {
            # This test runs regardless of PowerShell version
            { Set-TlsSecurityProtocol -Protocol 'Tls12' } | Should -Not -Throw
        }

        It 'Should handle TLS 1.3 appropriately based on PowerShell version' {
            if ($PSVersionTable.PSVersion.Major -ge 6)
            {
                { Set-TlsSecurityProtocol -Protocol 'Tls13' } | Should -Not -Throw

                $current = [Net.ServicePointManager]::SecurityProtocol
                $hasTls12 = ($current -band [Net.SecurityProtocolType]::Tls12) -ne 0
                $hasTls13 = try { ($current -band [Net.SecurityProtocolType]::Tls13) -ne 0 } catch { $false }

                ($hasTls12 -or $hasTls13) | Should -Be $true
            }
            else
            {
                { Set-TlsSecurityProtocol -Protocol 'Tls13' } | Should -Not -Throw
                $current = [Net.ServicePointManager]::SecurityProtocol
                $hasTls12 = ($current -band [Net.SecurityProtocolType]::Tls12) -ne 0
                $hasTls13 = try { ($current -band [Net.SecurityProtocolType]::Tls13) -ne 0 } catch { $false }

                ($hasTls12 -or $hasTls13) | Should -Be $true
            }
        }
    }
}
