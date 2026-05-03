#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Show-PlatformPackage.ps1"

    function Get-TestCommandResponse
    {
        param(
            [Parameter()]
            [Int32]$ExitCode = 0,

            [Parameter()]
            [String[]]$Output = @()
        )

        [PSCustomObject]@{
            ExitCode = $ExitCode
            Output = @($Output)
        }
    }

    $script:NewPackageCommandRunner = {
        param(
            [Parameter(Mandatory)]
            [Hashtable]$Responses
        )

        $localResponses = $Responses
        $localInvocations = $script:Invocations

        return {
            param(
                [Parameter(Mandatory)]
                [String]$Command,

                [Parameter()]
                [String[]]$Arguments = @()
            )

            $key = "$Command $($Arguments -join ' ')".Trim()
            $localInvocations.Add([PSCustomObject]@{
                    Command = $Command
                    Arguments = @($Arguments)
                    Key = $key
                })

            if ($localResponses.ContainsKey($key))
            {
                return $localResponses[$key]
            }

            return Get-TestCommandResponse -ExitCode 127 -Output @("Unexpected command: $key")
        }.GetNewClosure()
    }
}

Describe 'Show-PlatformPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        $script:HostOutput = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith { $script:HostOutput.Add($Object) }
        Mock -CommandName Clear-Host -MockWith {}
    }

    Context 'Object output' {
        It 'returns installed packages as objects when NonInteractive is used' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            }

            $result = @(Show-PlatformPackage -PackageManager brew -NonInteractive -CommandRunner $runner)

            $result.Count | Should -Be 2
            ($result | Where-Object { $_.Name -eq 'git' }).InstalledVersion | Should -Be '2.44.0'
        }
    }

    Context 'Interactive browsing' {
        It 'returns no output when cancelled' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = @(Show-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Arrow keys/Home/End/PgUp/PgDn: navigate  Ctrl+C/Q/Esc: exit' } -Times 1
            @($script:HostOutput | Where-Object { [String]::IsNullOrEmpty([String]$_) }).Count | Should -Be 3
        }

        It 'does not exit when Enter is pressed in browse mode' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Arrow keys/Home/End/PgUp/PgDn: navigate  Ctrl+C/Q/Esc: exit' } -Times 2
        }

        It 'renders only the current viewport for long package lists' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @(
                    'pkg-01 1.0.0'
                    'pkg-02 1.0.0'
                    'pkg-03 1.0.0'
                    'pkg-04 1.0.0'
                )
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $null = Show-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PickerPageSize 2

            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-01*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-02*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-03*' } -Times 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-04*' } -Times 0
        }

        It 'returns selected packages when PassThru is used' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PassThru)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like 'Spacebar: select*' } -Times 1
        }

        It 'returns the current package when PassThru is used without a selection' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            }

            $result = @(Show-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PassThru)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Spacebar: select  Enter: return current/selected  A: toggle all  Arrow keys/Home/End/PgUp/PgDn: navigate  Ctrl+C/Q/Esc: exit' } -Times 1
        }
    }
}
