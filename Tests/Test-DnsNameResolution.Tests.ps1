Describe 'Test-DnsNameResolution' {
    BeforeAll {
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
        $func = Join-Path -Path $root -ChildPath 'Functions' | Join-Path -ChildPath 'Test-DnsNameResolution.ps1'
        . $func
    }

    It 'returns true when DNS resolves (or skip if no network)' {
        # Quick network check: if DNS resolution is not possible in CI, skip this test
        try { [System.Net.Dns]::GetHostAddresses('localhost') | Out-Null }
        catch { Skip -Reason 'Network unavailable for DNS resolution in this environment' }

        (Test-DnsNameResolution -Name 'localhost') | Should -BeTrue
    }

    It 'returns false for an obviously invalid name' {
        (Test-DnsNameResolution -Name 'no-such-host.invalid-for-tests') | Should -BeFalse
    }
}
