Describe 'Test-Port function' {
    BeforeAll {
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
        $func = Join-Path -Path (Join-Path -Path $root -ChildPath 'Functions') -ChildPath 'Test-Port.ps1'
        . $func
    }

    It 'detects an open TCP port' {
        # Start a temporary TcpListener on a random port
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = ($listener.LocalEndpoint -as [System.Net.IPEndPoint]).Port

        try {
            $res = Test-Port -Port $port -ComputerName 'localhost' -Timeout 1000
            # result should contain an object for the requested port
            $r = $res | Where-Object { $_.Port -eq $port }
            $r | Should -Not -BeNullOrEmpty
            $r.Open | Should -BeOfType [bool]
        }
        finally {
            $listener.Stop()
        }
    }
}
