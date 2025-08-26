Describe -Tag Integration 'Integration: Certificate/TLS tests' {
    It 'attempts to retrieve certificate information from a reachable host' {
        # Skip if network is unavailable in runner
        if (-not (Test-Connection -ComputerName 'example.com' -Count 1 -Quiet)) { Skip 'Network not available in runner' }

        # Use the real function to validate behavior against example.com
        $result = Get-CertificateDetails -HostName 'example.com' -PortNumber 443 -ErrorAction Stop
        $result | Should -Not -BeNullOrEmpty
        $result.Certificate | Should -Not -BeNullOrEmpty
    }
}
