#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Get-TlsSecurityProtocol.ps1"

    $script:OriginalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
}

AfterAll {
    [Net.ServicePointManager]::SecurityProtocol = $script:OriginalSecurityProtocol
}

Describe 'Get-TlsSecurityProtocol' {
    BeforeEach {
        [Net.ServicePointManager]::SecurityProtocol = $script:OriginalSecurityProtocol
    }

    AfterEach {
        [Net.ServicePointManager]::SecurityProtocol = $script:OriginalSecurityProtocol
    }

    Context 'Parameter Validation' {
        It 'accepts valid protocol values' {
            { Get-TlsSecurityProtocol -Protocol 'SystemDefault' } | Should -Not -Throw
            { Get-TlsSecurityProtocol -Protocol 'Tls' } | Should -Not -Throw
            { Get-TlsSecurityProtocol -Protocol 'Tls11' } | Should -Not -Throw
            { Get-TlsSecurityProtocol -Protocol 'Tls12' } | Should -Not -Throw
            { Get-TlsSecurityProtocol -Protocol 'Tls13' } | Should -Not -Throw
        }

        It 'rejects invalid protocol values' {
            { Get-TlsSecurityProtocol -Protocol 'InvalidTls' } | Should -Throw
        }
    }

    Context 'Output Structure' {
        It 'returns current session TLS details' {
            $result = Get-TlsSecurityProtocol

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'CurrentProtocol'
            $result.PSObject.Properties.Name | Should -Contain 'CurrentProtocolDisplay'
            $result.PSObject.Properties.Name | Should -Contain 'EnabledProtocols'
            $result.PSObject.Properties.Name | Should -Contain 'AvailableProtocols'
            $result.PSObject.Properties.Name | Should -Contain 'ConfigurationMode'
            $result.PSObject.Properties.Name | Should -Contain 'SupportsSystemDefault'
            $result.PSObject.Properties.Name | Should -Contain 'IsSystemDefault'
            $result.PSObject.Properties.Name | Should -Contain 'EffectiveProtocolKnown'
            $result.PSObject.Properties.Name | Should -Contain 'EffectiveProtocolNote'

            $result.CurrentProtocol | Should -BeOfType [System.Net.SecurityProtocolType]
            $result.CurrentProtocolDisplay | Should -BeOfType [String]
            $result.EnabledProtocols.GetType().FullName | Should -Be 'System.String[]'
            $result.AvailableProtocols.GetType().FullName | Should -Be 'System.String[]'
        }

        It 'returns evaluation details when Protocol is specified' {
            $result = Get-TlsSecurityProtocol -Protocol 'Tls12'

            $result.PSObject.Properties.Name | Should -Contain 'RequestedProtocol'
            $result.PSObject.Properties.Name | Should -Contain 'RequestedProtocolAvailable'
            $result.PSObject.Properties.Name | Should -Contain 'ResolvedProtocol'
            $result.PSObject.Properties.Name | Should -Contain 'TargetProtocol'
            $result.PSObject.Properties.Name | Should -Contain 'TargetProtocolDisplay'
            $result.PSObject.Properties.Name | Should -Contain 'ForceTargetProtocol'
            $result.PSObject.Properties.Name | Should -Contain 'ForceTargetProtocolDisplay'
            $result.PSObject.Properties.Name | Should -Contain 'FallbackUsed'
            $result.PSObject.Properties.Name | Should -Contain 'FallbackDirection'
            $result.PSObject.Properties.Name | Should -Contain 'ChangeRequired'
            $result.PSObject.Properties.Name | Should -Contain 'ForceRequired'
            $result.PSObject.Properties.Name | Should -Contain 'EvaluationNote'

            $result.RequestedProtocol | Should -Be 'Tls12'
            $result.TargetProtocol | Should -BeOfType [System.Net.SecurityProtocolType]
            $result.ForceTargetProtocol | Should -BeOfType [System.Net.SecurityProtocolType]
            $result.ChangeRequired | Should -BeOfType [Boolean]
            $result.ForceRequired | Should -BeOfType [Boolean]
        }
    }

    Context 'Request Evaluation' {
        It 'reports no change required when the requested configuration is already satisfied' {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            $result = Get-TlsSecurityProtocol -Protocol 'Tls12'

            $result.ChangeRequired | Should -Be $false
            $result.TargetProtocol | Should -Be ([Net.SecurityProtocolType]::Tls12)
        }

        It 'reports a change when weaker-only protocols are enabled' {
            try
            {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls
            }
            catch
            {
                Set-ItResult -Skipped -Because 'TLS 1.0 not supported on this system'
                return
            }

            $result = Get-TlsSecurityProtocol -Protocol 'Tls12'

            $result.ChangeRequired | Should -Be $true
            ($result.TargetProtocol -band [Net.SecurityProtocolType]::Tls12) | Should -Not -Be 0
            ($result.TargetProtocol -band [Net.SecurityProtocolType]::Tls) | Should -Be 0
        }

        It 'preserves stronger secure protocols when evaluating a lower secure request' {
            try
            {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
            }
            catch
            {
                Set-ItResult -Skipped -Because 'TLS 1.3 not supported on this system'
                return
            }

            $result = Get-TlsSecurityProtocol -Protocol 'Tls12'

            $result.ChangeRequired | Should -Be $false
            ($result.TargetProtocol -band [Net.SecurityProtocolType]::Tls12) | Should -Not -Be 0
            ($result.TargetProtocol -band [Net.SecurityProtocolType]::Tls13) | Should -Not -Be 0
        }

        It 'handles TLS 1.3 evaluation gracefully when it is unavailable' {
            $result = Get-TlsSecurityProtocol -Protocol 'Tls13'

            $result | Should -Not -BeNullOrEmpty
            $result.RequestedProtocol | Should -Be 'Tls13'
            $result.ChangeRequired | Should -BeOfType [Boolean]
            $result.ResolvedProtocol | Should -Not -BeNullOrEmpty
        }

        It 'evaluates SystemDefault requests without throwing' {
            $result = Get-TlsSecurityProtocol -Protocol 'SystemDefault'

            $result.RequestedProtocol | Should -Be 'SystemDefault'
            $result.TargetProtocolDisplay | Should -Not -BeNullOrEmpty
            $result.ChangeRequired | Should -BeOfType [Boolean]
        }

        It 'treats explicit requests as no-op when the current session is SystemDefault' {
            if (-not ([enum]::GetNames([Net.SecurityProtocolType]) -contains 'SystemDefault'))
            {
                Set-ItResult -Skipped -Because 'SystemDefault is not available on this system'
                return
            }

            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::SystemDefault

            $result = Get-TlsSecurityProtocol -Protocol 'Tls12'

            $result.IsSystemDefault | Should -Be $true
            $result.ConfigurationMode | Should -Be 'SystemDefault'
            $result.EffectiveProtocolKnown | Should -Be $false
            $result.ChangeRequired | Should -Be $false
            $result.ForceRequired | Should -Be $true
            $result.ResolvedProtocol | Should -Be 'SystemDefault'
            $result.TargetProtocol | Should -Be ([Net.SecurityProtocolType]::SystemDefault)
            $result.TargetProtocolDisplay | Should -Be 'SystemDefault'
            $result.ForceTargetProtocolDisplay | Should -Be 'Tls12'
            $result.EvaluationNote | Should -Match 'SystemDefault|OS-managed|Force'
        }
    }
}
