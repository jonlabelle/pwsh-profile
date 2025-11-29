BeforeAll {
    $functionPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Functions\NetworkAndDns\Show-NetworkLatencyGraph.ps1'
    $functionPath = [System.IO.Path]::GetFullPath($functionPath)
    . $functionPath
}

Describe 'Show-NetworkLatencyGraph (Data mode)' {
    It 'returns non-empty string (Sparkline)' {
        $data = @(10, 20, 30, 40, 50)
        $result = Show-NetworkLatencyGraph -Data $data -GraphType 'Sparkline'

        $result | Should -BeOfType 'System.String'
        $result.Length | Should -BeGreaterThan 0
    }

    It 'includes stats when -ShowStats is set' {
        $data = @(20, 25, 30, 35, 40)
        $result = Show-NetworkLatencyGraph -Data $data -GraphType 'Sparkline' -ShowStats

        $result | Should -Match 'min:'
        $result | Should -Match 'max:'
        $result | Should -Match 'avg:'
    }
}
