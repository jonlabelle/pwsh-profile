BeforeAll {
    $invokePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Functions\NetworkAndDns\Invoke-NetworkDiagnostic.ps1'
    $invokePath = [System.IO.Path]::GetFullPath($invokePath)

    function Get-NetworkMetrics
    {
        param(
            [Parameter(Mandatory)][string]$HostName,
            [int]$Count,
            [int]$Timeout,
            [int]$Port,
            [switch]$IncludeDns,
            [int]$SampleDelayMilliseconds
        )
        return $script:MockMetrics
    }

    function Show-NetworkLatencyGraph
    {
        param(
            [double[]]$Data,
            [string]$GraphType,
            [int]$Width,
            [int]$Height,
            [switch]$ShowStats,
            [switch]$NoColor
        )
        return 'SPARK'
    }

    . $invokePath
}

Describe 'Invoke-NetworkDiagnostic (Continuous single iteration via -MaxIterations)' {
    It 'prints expected output without timestamp or wait messages' {
        # Prepare canned metrics
        $script:MockLatencies = @(61, 62, 63, 64, 65)
        $script:MockMetrics = [PSCustomObject]@{
            HostName = 'example.com'
            Port = 443
            SamplesTotal = 5
            SamplesSuccess = 5
            PacketLoss = 0
            LatencyMin = 61.0
            LatencyMax = 65.0
            LatencyAvg = 63.0
            Jitter = 5.12
            DnsResolution = $null
            LatencyData = $script:MockLatencies
        }

        # Capture output
        $output = Invoke-NetworkDiagnostic -HostName 'example.com' -Continuous -Count 5 -MaxIterations 1 *>&1 | Out-String

        # Verify expected content
        $output | Should -Match 'Network Diagnostic'
        $output | Should -Match 'example\.com:443'
        $output | Should -Match 'Stats'
        $output | Should -Match 'Quality:'

        # Ensure NO timestamp or wait messages
        $output | Should -Not -Match 'Test completed at:'
        $output | Should -Not -Match 'Waiting'
    }
}
