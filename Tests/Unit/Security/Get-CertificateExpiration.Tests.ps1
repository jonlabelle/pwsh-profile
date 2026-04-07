#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Security/Get-CertificateExpiration.ps1"

    $script:TestPemCertificate = @'
-----BEGIN CERTIFICATE-----
MIIDHTCCAgWgAwIBAgIUcEQOnzT2Tl0qGMkXtwFSyXtRTvowDQYJKoZIhvcNAQEL
BQAwHjEcMBoGA1UEAwwTVW5pdFRlc3RDZXJ0aWZpY2F0ZTAeFw0yNjA0MDcxODQ4
NTZaFw0yNjA1MDcxODQ4NTZaMB4xHDAaBgNVBAMME1VuaXRUZXN0Q2VydGlmaWNh
dGUwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDSvjcL/1vRO+ylL33C
tDYU2DKYY52G900+0dqFettshF23Fb5d8QgfDIZi/w6tpJ6zdH4ggzmzcs56rTif
Z88w5o3wLkBZujkcd00sAkw3Q+KiPhym7LvYNLRq7WcM/rTnz35anS0MTKkRmin9
mpgvFZRBq7/Ar3TTkTJvGGmwrc1yW1leGbLl9+Jk0Ru1tDOJmpCC0ZDOaTmEHo4d
b4xBj/AVDmAZzq41flCwgSLA92d9Md7vii69q/8Tdu9a3AilIFhGj/tnt0LOutDk
cfayv4AxSqHEnAbnbmfWLzFAnKaRCp7axkmFFt4M+CiJ1FIEmr6gzuLgJJhidz2i
wPlTAgMBAAGjUzBRMB0GA1UdDgQWBBQq/oFxDDWFrnvGt00eji6qkzZZXjAfBgNV
HSMEGDAWgBQq/oFxDDWFrnvGt00eji6qkzZZXjAPBgNVHRMBAf8EBTADAQH/MA0G
CSqGSIb3DQEBCwUAA4IBAQBVzY7cOPS42LW9vZt1x/yeT+R0t8itf9LPkHUSweYc
rFEFmwvgV86m4xI7WQRJN6nVG4Q+UvLQNsnRneU24dZlGhHw2sfA92zl+qELsW2o
Rl6RWV1+r8PwxL4ruvLUBh7fEysmu5Q6BhHVTopqMI4909LaZu8ChjeqsxxVr/bc
d+B15BdlmKE3tMFG7iBdCwFADkV2lYPti2tPqBPbm9Z0WacIFtA9c/sk/Z3o3lzv
Fiv9e6lv0CDVNU5P1UVDXv/BuPmP7wkeOv/ZMiGNchXSAbxqSvctH0y+H3TY7nFn
ezQIMHy31om8TsM8Nk7/MUWB+VHQkcyQef9LRSi2gNDI
-----END CERTIFICATE-----
'@

    $script:ExpectedExpirationDate = [DateTimeOffset]'2026-05-07T18:48:56+00:00'
    $script:ExpectedExpirationLocalDate = $script:ExpectedExpirationDate.LocalDateTime

    function New-TestCertificateFile
    {
        [CmdletBinding(SupportsShouldProcess)]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        if ($PSCmdlet.ShouldProcess($Path, 'Create test certificate file'))
        {
            Set-Content -LiteralPath $Path -Value $script:TestPemCertificate -NoNewline
        }

        return $Path
    }
}

Describe 'Get-CertificateExpiration' {
    Context 'Default output contract' {
        It 'returns a PSCustomObject with ExpirationDate for certificate files' {
            $certPath = Join-Path -Path $TestDrive -ChildPath 'default-output.pem'

            New-TestCertificateFile -Path $certPath | Out-Null
            Mock Get-Date { $script:ExpectedExpirationLocalDate.AddDays(-31) }

            $result = @(Get-CertificateExpiration -Path $certPath)

            $result | Should -HaveCount 1
            $result[0] | Should -BeOfType [PSCustomObject]
            $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result[0].PSObject.Properties.Name | Should -Contain 'ExpirationDate'
            $result[0].PSObject.Properties.Name | Should -Contain 'ExpiresIn'
            $result[0].PSObject.Properties.Name | Should -Contain 'Status'
            $result[0].PSObject.Properties.Name | Should -Contain 'CertificatePath'
            $result[0].ComputerName | Should -Be $null
            $result[0].CertificatePath | Should -Be $certPath
            $result[0].ExpirationDate | Should -BeOfType [datetime]
            $result[0].ExpiresIn | Should -Be '31 days'
            $result[0].Status | Should -Be 'Valid'
            ($result[0].ExpirationDate).ToUniversalTime().ToString('o') | Should -Be $script:ExpectedExpirationDate.UtcDateTime.ToString('o')

            $renderedOutput = $result | Out-String
            $renderedOutput | Should -Match 'ComputerName\s+ExpirationDate\s+ExpiresIn\s+Status'
            $renderedOutput | Should -Not -Match 'ComputerName\s*:'
        }

        It 'treats an existing file path passed through ComputerName as a certificate path' {
            $certPath = Join-Path -Path $TestDrive -ChildPath 'computername-input.pem'

            New-TestCertificateFile -Path $certPath | Out-Null
            Mock Get-Date { $script:ExpectedExpirationLocalDate.AddDays(1) }

            $result = @(Get-CertificateExpiration -ComputerName $certPath)

            $result | Should -HaveCount 1
            $result[0].ComputerName | Should -Be $null
            $result[0].CertificatePath | Should -Be $certPath
            $result[0].ExpirationDate | Should -BeOfType [datetime]
            $result[0].ExpiresIn | Should -Be '1 day ago'
            $result[0].Status | Should -Be 'Expired'
        }
    }

    Context 'Detailed output contract' {
        It 'includes ExpirationDate alongside detailed certificate properties' {
            $certPath = Join-Path -Path $TestDrive -ChildPath 'detailed-output.pem'

            New-TestCertificateFile -Path $certPath | Out-Null
            Mock Get-Date { $script:ExpectedExpirationLocalDate.AddDays(-1) }

            $result = @(Get-CertificateExpiration -Path $certPath -Detailed -DaysToWarn 7)

            $result | Should -HaveCount 1
            $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result[0].PSObject.Properties.Name | Should -Contain 'ExpirationDate'
            $result[0].PSObject.Properties.Name | Should -Contain 'ExpiresIn'
            $result[0].PSObject.Properties.Name | Should -Contain 'Status'
            $result[0].PSObject.Properties.Name | Should -Contain 'NotAfter'
            $result[0].PSObject.Properties.Name | Should -Contain 'CertificatePath'
            $result[0].ComputerName | Should -Be $null
            $result[0].CertificatePath | Should -Be $certPath
            $result[0].ExpirationDate | Should -Be $result[0].NotAfter
            $result[0].ExpiresIn | Should -Be '1 day'
            $result[0].Status | Should -Be 'ExpiringSoon'
        }
    }
}
