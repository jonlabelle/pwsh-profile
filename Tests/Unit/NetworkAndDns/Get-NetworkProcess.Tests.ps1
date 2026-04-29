#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Get-NetworkProcess function.

.DESCRIPTION
    Tests deterministic parsing and filtering for local network port/process mappings
    without relying on the host machine's current network state.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/NetworkAndDns/Get-NetworkProcess.ps1"

    $script:LsofSample = @(
        'p1234',
        'cnode',
        'f20',
        'PTCP',
        'n127.0.0.1:3000',
        'TST=LISTEN',
        'TQR=0',
        'TQS=0',
        'f21',
        'PTCP',
        'n127.0.0.1:50100->127.0.0.1:5432',
        'TST=ESTABLISHED',
        'TQR=0',
        'TQS=0',
        'p5678',
        'cpostgres',
        'f9',
        'PUDP',
        'n*:5353'
    )

    $script:NetstatSample = @(
        '  Proto  Local Address          Foreign Address        State           PID',
        '  TCP    0.0.0.0:443            0.0.0.0:0              LISTENING       4321',
        '  TCP    127.0.0.1:50000        93.184.216.34:443      ESTABLISHED     4321',
        '  UDP    [::]:5353              *:*                                    987'
    )
}

Describe 'Get-NetworkProcess' {
    Context 'lsof output parsing' {
        It 'Should parse TCP and UDP socket records' {
            $results = Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof

            @($results).Count | Should -Be 3

            $listener = $results | Where-Object { $_.LocalPort -eq 3000 }
            $listener.Protocol | Should -Be 'TCP'
            $listener.LocalAddress | Should -Be '127.0.0.1'
            $listener.State | Should -Be 'Listen'
            $listener.ProcessName | Should -Be 'node'
            $listener.ProcessId | Should -Be 1234

            $udp = $results | Where-Object { $_.LocalPort -eq 5353 }
            $udp.Protocol | Should -Be 'UDP'
            $udp.LocalAddress | Should -Be '*'
            $udp.State | Should -Be 'Unconnected'
            $udp.ProcessName | Should -Be 'postgres'
        }

        It 'Should parse remote endpoints on established connections' {
            $result = Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -Established

            @($result).Count | Should -Be 1
            $result.LocalPort | Should -Be 50100
            $result.RemoteAddress | Should -Be '127.0.0.1'
            $result.RemotePort | Should -Be 5432
            $result.State | Should -Be 'Established'
        }
    }

    Context 'netstat output parsing' {
        It 'Should parse Windows TCP and UDP netstat records' {
            $results = Get-NetworkProcess -RawConnectionOutput $script:NetstatSample -InputFormat Netstat

            @($results).Count | Should -Be 3

            $listener = $results | Where-Object { $_.LocalPort -eq 443 }
            $listener.Protocol | Should -Be 'TCP'
            $listener.LocalAddress | Should -Be '0.0.0.0'
            $listener.State | Should -Be 'Listen'
            $listener.ProcessId | Should -Be 4321

            $udp = $results | Where-Object { $_.LocalPort -eq 5353 }
            $udp.Protocol | Should -Be 'UDP'
            $udp.LocalAddress | Should -Be '::'
            $udp.RemoteAddress | Should -Be '*'
            $udp.State | Should -Be 'Unconnected'
        }
    }

    Context 'Filtering' {
        It 'Should filter by local port by default' {
            $results = Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -Port 3000

            @($results).Count | Should -Be 1
            $results.ProcessName | Should -Be 'node'
            $results.LocalPort | Should -Be 3000
        }

        It 'Should include remote ports when IncludeRemotePort is specified' {
            $localOnly = Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -Port 5432
            $withRemote = Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -Port 5432 -IncludeRemotePort

            @($localOnly).Count | Should -Be 0
            @($withRemote).Count | Should -Be 1
            $withRemote.RemotePort | Should -Be 5432
        }

        It 'Should filter by process ID' {
            $results = Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -ProcessId 1234

            @($results).Count | Should -Be 2
            $results | ForEach-Object { $_.ProcessId | Should -Be 1234 }
        }

        It 'Should filter by wildcard process name' {
            $results = Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -ProcessName 'post*'

            @($results).Count | Should -Be 1
            $results.ProcessName | Should -Be 'postgres'
            $results.LocalPort | Should -Be 5353
        }

        It 'Should filter by protocol' {
            $results = Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -Protocol UDP

            @($results).Count | Should -Be 1
            $results.Protocol | Should -Be 'UDP'
        }

        It 'Should filter listening and bound sockets' {
            $results = Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -Listening

            @($results).Count | Should -Be 2
            $results.LocalPort | Should -Contain 3000
            $results.LocalPort | Should -Contain 5353
        }
    }

    Context 'Parameter validation' {
        It 'Should reject invalid port numbers' {
            { Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -Port 0 } | Should -Throw
            { Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -Port 65536 } | Should -Throw
        }

        It 'Should reject invalid protocol values' {
            { Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -Protocol ICMP } | Should -Throw
        }

        It 'Should reject mutually exclusive state switches' {
            { Get-NetworkProcess -RawConnectionOutput $script:LsofSample -InputFormat Lsof -Listening -Established } | Should -Throw
        }
    }
}
