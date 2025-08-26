Describe 'Get-CertificateDetails function' {
    BeforeAll {
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
        $functionsDir = Join-Path -Path $root -ChildPath 'Functions'
        $func = Join-Path -Path $functionsDir -ChildPath 'Get-CertificateDetails.ps1'

        if (Test-Path -Path $func) { . $func }
        else { return }
    }

    It 'is defined after dot-sourcing its file' {
        (Get-Command -Name 'Get-CertificateDetails' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    Context 'Parameter validation' {
        It 'throws on invalid Port (0)' {
            { Get-CertificateDetails -ComputerName 'x' -Port 0 } | Should -Throw
        }

        It 'throws on invalid Port (65536)' {
            { Get-CertificateDetails -ComputerName 'x' -Port 65536 } | Should -Throw
        }

        It 'throws on invalid Timeout (too low)' {
            { Get-CertificateDetails -ComputerName 'x' -Timeout 999 } | Should -Throw
        }

        It 'throws on invalid Timeout (too high)' {
            { Get-CertificateDetails -ComputerName 'x' -Timeout 300001 } | Should -Throw
        }

        It 'throws on empty ComputerName' {
            { Get-CertificateDetails -ComputerName '' } | Should -Throw
        }
    }

    Context 'Connection timeout handling (mocked)' {
        BeforeEach {
            # Ensure deterministic behavior: mock the TcpClient creation to simulate a connect timeout
            Mock -CommandName New-Object -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' } -MockWith {
                    # Provide an object that supports ReceiveTimeout/SendTimeout and methods used by the function
                    $client = New-Object PSObject
                    $client | Add-Member -MemberType NoteProperty -Name ReceiveTimeout -Value $null -Force
                    $client | Add-Member -MemberType NoteProperty -Name SendTimeout -Value $null -Force
                    $client | Add-Member -MemberType NoteProperty -Name HostName -Value $null -Force
                    $client | Add-Member -MemberType NoteProperty -Name PortNumber -Value $null -Force

                    $client | Add-Member -MemberType ScriptMethod -Name ConnectAsync -Value {
                        param([string]$h, [int]$p)
                        $this.HostName = $h
                        $this.PortNumber = $p
                        # Return a task-like object whose Wait($ms) returns $false to simulate timeout
                        $task = New-Object PSObject
                        $task | Add-Member -MemberType ScriptMethod -Name Wait -Value { param([int]$ms) return $false } -Force
                        return $task
                    } -Force

                    $client | Add-Member -MemberType ScriptMethod -Name GetStream -Value {
                        # Return a simple stream-like object placeholder for SslStream constructor
                        return New-Object PSObject
                    } -Force

                    $client | Add-Member -MemberType ScriptMethod -Name Close -Value { } -Force
                    $client | Add-Member -MemberType ScriptMethod -Name Dispose -Value { } -Force
                    return $client
            }
        }

        It 'returns no objects and writes an error when connection times out' {
            $errs = @()
            $result = Get-CertificateDetails -ComputerName 'timeout.mock' -ErrorAction SilentlyContinue -ErrorVariable +errs

            $result | Should -BeNullOrEmpty
            $errs.Count | Should -BeGreaterThan 0
            ($errs[0].ToString()) | Should -Match 'Failed to retrieve SSL certificate|timed out'
        }
        }

    # Network/SSL integration tests removed from CI suite to avoid brittle discovery/runtime errors
    }
