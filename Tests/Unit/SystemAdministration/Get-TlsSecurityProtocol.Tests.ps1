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
            { Get-TlsSecurityProtocol -Protocol 'InvalidTls' } | Should-Throw
        }
    }

    Context 'Output Structure' {
        It 'returns current session TLS details' {
            $result = Get-TlsSecurityProtocol

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should-ContainCollection 'CurrentProtocol'
            $result.PSObject.Properties.Name | Should-ContainCollection 'CurrentProtocolDisplay'
            $result.PSObject.Properties.Name | Should-ContainCollection 'EnabledProtocols'
            $result.PSObject.Properties.Name | Should-ContainCollection 'AvailableProtocols'
            $result.PSObject.Properties.Name | Should-ContainCollection 'ConfigurationMode'
            $result.PSObject.Properties.Name | Should-ContainCollection 'SupportsSystemDefault'
            $result.PSObject.Properties.Name | Should-ContainCollection 'IsSystemDefault'
            $result.PSObject.Properties.Name | Should-ContainCollection 'EffectiveProtocolKnown'
            $result.PSObject.Properties.Name | Should-ContainCollection 'EffectiveProtocolNote'

            $result.CurrentProtocol | Should-HaveType ([System.Net.SecurityProtocolType])
            $result.CurrentProtocolDisplay | Should-HaveType ([String])
            $result.EnabledProtocols.GetType().FullName | Should-Be 'System.String[]'
            $result.AvailableProtocols.GetType().FullName | Should-Be 'System.String[]'
        }

        It 'returns evaluation details when Protocol is specified' {
            $result = Get-TlsSecurityProtocol -Protocol 'Tls12'

            $result.PSObject.Properties.Name | Should-ContainCollection 'RequestedProtocol'
            $result.PSObject.Properties.Name | Should-ContainCollection 'RequestedProtocolAvailable'
            $result.PSObject.Properties.Name | Should-ContainCollection 'ResolvedProtocol'
            $result.PSObject.Properties.Name | Should-ContainCollection 'TargetProtocol'
            $result.PSObject.Properties.Name | Should-ContainCollection 'TargetProtocolDisplay'
            $result.PSObject.Properties.Name | Should-ContainCollection 'ForceTargetProtocol'
            $result.PSObject.Properties.Name | Should-ContainCollection 'ForceTargetProtocolDisplay'
            $result.PSObject.Properties.Name | Should-ContainCollection 'FallbackUsed'
            $result.PSObject.Properties.Name | Should-ContainCollection 'FallbackDirection'
            $result.PSObject.Properties.Name | Should-ContainCollection 'ChangeRequired'
            $result.PSObject.Properties.Name | Should-ContainCollection 'ForceRequired'
            $result.PSObject.Properties.Name | Should-ContainCollection 'EvaluationNote'

            $result.RequestedProtocol | Should-Be 'Tls12'
            $result.TargetProtocol | Should-HaveType ([System.Net.SecurityProtocolType])
            $result.ForceTargetProtocol | Should-HaveType ([System.Net.SecurityProtocolType])
            $result.ChangeRequired | Should-HaveType ([Boolean])
            $result.ForceRequired | Should-HaveType ([Boolean])
        }
    }

    Context 'Request Evaluation' {
        It 'reports no change required when the requested configuration is already satisfied' {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            $result = Get-TlsSecurityProtocol -Protocol 'Tls12'

            $result.ChangeRequired | Should-Be $false
            $result.TargetProtocol | Should-Be ([Net.SecurityProtocolType]::Tls12)
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

            $result.ChangeRequired | Should-Be $true
            ($result.TargetProtocol -band [Net.SecurityProtocolType]::Tls12) | Should-NotBe 0
            ($result.TargetProtocol -band [Net.SecurityProtocolType]::Tls) | Should-Be 0
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

            $result.ChangeRequired | Should-Be $false
            ($result.TargetProtocol -band [Net.SecurityProtocolType]::Tls12) | Should-NotBe 0
            ($result.TargetProtocol -band [Net.SecurityProtocolType]::Tls13) | Should-NotBe 0
        }

        It 'handles TLS 1.3 evaluation gracefully when it is unavailable' {
            $result = Get-TlsSecurityProtocol -Protocol 'Tls13'

            $result | Should -Not -BeNullOrEmpty
            $result.RequestedProtocol | Should-Be 'Tls13'
            $result.ChangeRequired | Should-HaveType ([Boolean])
            $result.ResolvedProtocol | Should -Not -BeNullOrEmpty
        }

        It 'evaluates SystemDefault requests without throwing' {
            $result = Get-TlsSecurityProtocol -Protocol 'SystemDefault'

            $result.RequestedProtocol | Should-Be 'SystemDefault'
            $result.TargetProtocolDisplay | Should -Not -BeNullOrEmpty
            $result.ChangeRequired | Should-HaveType ([Boolean])
        }

        It 'treats explicit requests as no-op when the current session is SystemDefault' {
            if (-not ([enum]::GetNames([Net.SecurityProtocolType]) -contains 'SystemDefault'))
            {
                Set-ItResult -Skipped -Because 'SystemDefault is not available on this system'
                return
            }

            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::SystemDefault

            $result = Get-TlsSecurityProtocol -Protocol 'Tls12'

            $result.IsSystemDefault | Should-Be $true
            $result.ConfigurationMode | Should-Be 'SystemDefault'
            $result.EffectiveProtocolKnown | Should-Be $false
            $result.ChangeRequired | Should-Be $false
            $result.ForceRequired | Should-Be $true
            $result.ResolvedProtocol | Should-Be 'SystemDefault'
            $result.TargetProtocol | Should-Be ([Net.SecurityProtocolType]::SystemDefault)
            $result.TargetProtocolDisplay | Should-Be 'SystemDefault'
            $result.ForceTargetProtocolDisplay | Should-Be 'Tls12'
            $result.EvaluationNote | Should-MatchString 'SystemDefault|OS-managed|Force'
        }
    }
}
