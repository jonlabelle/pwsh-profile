#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Remove-PlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Get-PlatformPackageDependency.ps1"
    . "$PSScriptRoot/PlatformPackageTestHelpers.ps1"
}

Describe 'Remove-PlatformPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        $script:HostOutput = New-Object 'System.Collections.Generic.List[Object]'
        $script:Warnings = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith { $script:HostOutput.Add($Object) }
        Mock -CommandName Write-Warning -MockWith { $script:Warnings.Add($Message) }
        Mock -CommandName Clear-Host -MockWith {}
    }

    Context 'Homebrew package discovery' {
        It 'returns formula and cask records from list output' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            }

            $result = @(Remove-PlatformPackage -PackageManager brew -NonInteractive -CommandRunner $runner)

            $result.Count | Should -Be 2

            $formula = $result | Where-Object { $_.Name -eq 'git' }
            $formula.PackageManager | Should -Be 'brew'
            $formula.Type | Should -Be 'Formula'
            $formula.InstalledVersion | Should -Be '2.44.0'
            (@($formula.RemoveArguments) -join '|') | Should -Be 'uninstall|git'

            $cask = $result | Where-Object { $_.Name -eq 'visual-studio-code' }
            $cask.Type | Should -Be 'Cask'
            (@($cask.RemoveArguments) -join '|') | Should -Be 'uninstall|--cask|visual-studio-code'
        }

        It 'keeps AsObject as an alias for NonInteractive discovery' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $result = @(Remove-PlatformPackage -PackageManager brew -AsObject -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            (@($result[0].RemoveArguments) -join '|') | Should -Be 'uninstall|git'
            @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).Count | Should -Be 0
        }

        It 'uses zap for casks when purge is requested' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @()
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            }

            $result = @(Remove-PlatformPackage -PackageManager brew -NonInteractive -Purge -CommandRunner $runner)

            (@($result[0].RemoveArguments) -join '|') | Should -Be 'uninstall|--cask|--zap|visual-studio-code'
        }

        It 'streams remove command output when removing all matching packages' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uninstall git' = Get-TestCommandResponse -Output @('brew uninstall git output')
            }

            $result = Remove-PlatformPackage -PackageManager brew -IncludePackage git -All -CommandRunner $runner -Confirm:$false

            $result.Removed | Should -Be 1
            $result.Failed | Should -Be 0
            $result.NotSelected | Should -Be 0

            ($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).StreamOutput | Should -BeTrue

            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'brew uninstall git output' } -Times 1
        }

        It 'captures post-removal instructions in the result object' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('python 3.12.1')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uninstall python' = Get-TestCommandResponse -Output @(
                    'Removing python...'
                    'Note:'
                    'Python user site-packages were left in place.'
                )
            }

            $result = Remove-PlatformPackage -PackageManager brew -IncludePackage python -All -CommandRunner $runner -Confirm:$false

            $result.Removed | Should -Be 1
            $result.Results[0].CapturedOutput | Should -Contain 'Removing python...'
            $result.Results[0].InformationalOutput | Should -Contain 'Note:'
            $result.InformationalResults.Count | Should -Be 1
            $result.InformationalResults[0].Lines | Should -Contain 'Python user site-packages were left in place.'
        }

        It 'reports streamed command failures with command context when captured output is unavailable' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uninstall git' = Get-TestCommandResponse -ExitCode 41 -Output @()
            }

            $result = Remove-PlatformPackage -PackageManager brew -IncludePackage git -All -CommandRunner $runner -Confirm:$false -WarningAction SilentlyContinue

            $result.Removed | Should -Be 0
            $result.Failed | Should -Be 1
            $result.Skipped | Should -Be 0
            $result.Results[0].Message | Should -Match 'brew uninstall git failed with exit code 41'
            $result.Results[0].Message | Should -Match 'streamed directly to the console'
        }

        It 'does not read stale LASTEXITCODE for unstructured command runner output' {
            $lastExitCode = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue

            try
            {
                $global:LASTEXITCODE = 41

                $runner = {
                    param(
                        [Parameter(Mandatory)]
                        [String]$Command,

                        [Parameter()]
                        [String[]]$Arguments = @(),

                        [Parameter()]
                        [Switch]$StreamOutput
                    )

                    $key = "$Command $($Arguments -join ' ')".Trim()

                    if ($key -eq 'brew list --formula --versions')
                    {
                        return [PSCustomObject]@{
                            ExitCode = 0
                            Output = @('git 2.44.0')
                        }
                    }

                    if ($key -eq 'brew list --cask --versions')
                    {
                        return [PSCustomObject]@{
                            ExitCode = 0
                            Output = @()
                        }
                    }

                    if ($key -eq 'brew uninstall git')
                    {
                        return 'brew uninstall git output'
                    }

                    return [PSCustomObject]@{
                        ExitCode = 127
                        Output = @("Unexpected command: $key")
                    }
                }.GetNewClosure()

                $result = Remove-PlatformPackage -PackageManager brew -IncludePackage git -All -CommandRunner $runner -Confirm:$false

                $result.Removed | Should -Be 1
                $result.Failed | Should -Be 0
                $result.Results[0].ExitCode | Should -Be 0
            }
            finally
            {
                if ($lastExitCode)
                {
                    $global:LASTEXITCODE = $lastExitCode.Value
                }
                else
                {
                    Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
                }
            }
        }

        It 'does not remove every installed package with -All unless an include filter is supplied' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            { Remove-PlatformPackage -PackageManager brew -All -CommandRunner $runner -Confirm:$false } |
            Should -Throw -ExpectedMessage '*without an include filter*'
        }

        It 'warns about installed Homebrew dependents before removing with -All' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('openssl 3.3.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uses --installed openssl' = Get-TestCommandResponse -Output @('curl')
                'brew uninstall openssl' = Get-TestCommandResponse -Output @('brew uninstall openssl output')
            }

            $result = Remove-PlatformPackage -PackageManager brew -IncludePackage openssl -All -CommandRunner $runner -Confirm:$false

            $result.Removed | Should -Be 1
            $result.Results[0].RequiredByCount | Should -Be 1
            $result.Results[0].RequiredByPackages | Should -Contain 'curl'
            $script:Warnings | Should -Contain 'openssl is required by 1 installed package(s): curl. Removing it may break dependent packages.'

            $keys = @($script:Invocations | ForEach-Object { $_.Key })
            [Array]::IndexOf($keys, 'brew uses --installed openssl') | Should -BeLessThan ([Array]::IndexOf($keys, 'brew uninstall openssl'))
        }
    }

    Context 'Linux package discovery' {
        It 'parses apt installed package output and uses purge when requested' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt list --installed' = Get-TestCommandResponse -Output @(
                    'Listing... Done'
                    'openssl/jammy-updates,now 3.0.2-0ubuntu1.15 arm64 [installed,automatic]'
                )
            }

            $result = @(Remove-PlatformPackage -PackageManager apt -NonInteractive -Purge -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'openssl'
            $result[0].PackageManager | Should -Be 'apt'
            $result[0].InstalledVersion | Should -Be '3.0.2-0ubuntu1.15'
            $result[0].Notes | Should -Be 'Automatic'
            (@($result[0].RemoveArguments) -join '|') | Should -Be 'purge|-y|openssl'
        }

        It 'parses apk package output and keeps hyphenated package names' {
            $runner = & $script:NewPackageCommandRunner @{
                'apk info -v' = Get-TestCommandResponse -Output @(
                    'busybox-1.36.1-r19'
                    'py3-requests-2.31.0-r0'
                )
            }

            $result = @(Remove-PlatformPackage -PackageManager apk -NonInteractive -Purge -CommandRunner $runner)

            $result.Count | Should -Be 2

            $busybox = $result | Where-Object { $_.Name -eq 'busybox' }
            $busybox.InstalledVersion | Should -Be '1.36.1-r19'
            (@($busybox.RemoveArguments) -join '|') | Should -Be 'del|--purge|busybox'

            $requests = $result | Where-Object { $_.Name -eq 'py3-requests' }
            $requests.InstalledVersion | Should -Be '2.31.0-r0'
        }

        It 'warns about installed APT dependents before removing the current interactive package' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt list --installed' = Get-TestCommandResponse -Output @(
                    'Listing... Done'
                    'openssl/jammy,now 3.0.2-0ubuntu1.15 amd64 [installed]'
                    'curl/jammy,now 8.5.0 amd64 [installed]'
                )
                'apt-cache rdepends openssl' = Get-TestCommandResponse -Output @(
                    'openssl'
                    'Reverse Depends:'
                    '  curl'
                )
                'apt remove -y openssl' = Get-TestCommandResponse -Output @('apt remove output')
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            }

            $result = Remove-PlatformPackage -PackageManager apt -IncludePackage openssl -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Removed | Should -Be 1
            $result.Results[0].RequiredByPackages | Should -Contain 'curl'
            $script:Warnings | Should -Contain 'openssl is required by 1 installed package(s): curl. Removing it may break dependent packages.'

            $keys = @($script:Invocations | ForEach-Object { $_.Key })
            [Array]::IndexOf($keys, 'apt-cache rdepends openssl') | Should -BeLessThan ([Array]::IndexOf($keys, 'apt remove -y openssl'))
        }

        It 'warns about installed apk dependents before removing with -All' {
            $runner = & $script:NewPackageCommandRunner @{
                'apk info -v' = Get-TestCommandResponse -Output @(
                    'pipewire-1.0.6-r1'
                    'pipewire-pulse-1.0.6-r1'
                )
                'apk info --rdepends pipewire' = Get-TestCommandResponse -Output @(
                    'pipewire-1.0.6-r1 is required by:'
                    'pipewire-pulse-1.0.6-r1'
                )
                'apk del pipewire' = Get-TestCommandResponse -Output @('apk del output')
            }

            $result = Remove-PlatformPackage -PackageManager apk -IncludePackage pipewire -All -CommandRunner $runner -Confirm:$false

            $result.Removed | Should -Be 1
            $result.Results[0].RequiredByPackages | Should -Contain 'pipewire-pulse'
            $script:Warnings | Should -Contain 'pipewire is required by 1 installed package(s): pipewire-pulse. Removing it may break dependent packages.'

            $keys = @($script:Invocations | ForEach-Object { $_.Key })
            [Array]::IndexOf($keys, 'apk info --rdepends pipewire') | Should -BeLessThan ([Array]::IndexOf($keys, 'apk del pipewire'))
        }
    }

    Context 'Interactive package selection' {
        It 'removes the current package when Enter is pressed without a selection' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uninstall git' = Get-TestCommandResponse -Output @('brew uninstall git output')
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            }

            $result = Remove-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 1
            $result.NotSelected | Should -Be 0
            $result.Removed | Should -Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).StreamOutput | Should -BeTrue
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq "Keys: Space select  P purge/zap  Enter remove  D deps  V details  A all  F: [all]" } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq "Nav: Home/End/PgUp/PgDn  ?: help  Q/Esc/Ctrl+C cancel" } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq "1-1 of 1 visible  $([char]0x00B7)  1 total  $([char]0x00B7)  0 selected" -and $ForegroundColor -eq 'White' } -Times 1
        }

        It 'shows keyboard help from the removal picker' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('?', [ConsoleKey]::Oem2, $true, $false, $false)
                [System.ConsoleKeyInfo]::new('x', [ConsoleKey]::X, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Remove-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 0
            $result.Removed | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Remove-PlatformPackage Help' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'P: ' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'toggle purge/zap removal for the current package' -and $ForegroundColor -eq 'DarkGray' } -Times 1
        }

        It 'treats Ctrl+C as a cancel command' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uninstall git' = Get-TestCommandResponse -Output @('brew uninstall git output')
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = Remove-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 0
            $result.NotSelected | Should -Be 1
            $result.Removed | Should -Be 0
            @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).Count | Should -Be 0
            @($script:HostOutput | Where-Object { [String]::IsNullOrEmpty([String]$_) }).Count | Should -Be 4
        }

        It 'ignores Backspace and Delete as manager navigation when not launched by the manager' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uninstall git' = Get-TestCommandResponse -Output @('brew uninstall git output')
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new([Char]8, [ConsoleKey]::Backspace, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]0, [ConsoleKey]::Delete, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Remove-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 0
            $result.Removed | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq "Keys: Space select  P purge/zap  Enter remove  D deps  V details  A all  F: [all]" } -Times 3
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Backspace/Delete: manager menu' } -Times 0
            @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).Count | Should -Be 0
        }

        It 'returns to the manager menu on <Name> when manager navigation is enabled' -TestCases @(
            @{ Name = 'Backspace'; Key = [ConsoleKey]::Backspace; Char = [Char]8 }
            @{ Name = 'Delete'; Key = [ConsoleKey]::Delete; Char = [Char]0 }
        ) {
            param($Name, $Key, $Char)

            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uninstall git' = Get-TestCommandResponse -Output @('brew uninstall git output')
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new($Char, $Key, $false, $false, $false)
            }.GetNewClosure()

            $result = Remove-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -ReturnToPlatformPackageManagerOnBackKey -Confirm:$false

            $result.Selected | Should -Be 0
            $result.Removed | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq "Keys: Space select  P purge/zap  Enter remove  D deps  V details  A all  F: [all]" } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Backspace/Delete: manager menu' } -Times 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).Count | Should -Be 0
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

            $null = Remove-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PickerPageSize 2 -Confirm:$false

            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-01*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-02*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-03*' } -Times 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-04*' } -Times 0
        }

        It 'allows purge behavior to be toggled for the selected package' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @()
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
                'brew uninstall --cask --zap visual-studio-code' = Get-TestCommandResponse -Output @('brew zap output')
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('p', [ConsoleKey]::P, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Remove-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Removed | Should -Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall --cask --zap visual-studio-code' }).StreamOutput | Should -BeTrue
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*P purge/zap*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'brew zap output' } -Times 1
        }

        It 'shows both dependency directions from the removal picker with D' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            Mock -CommandName Get-PlatformPackageDependency -MockWith {
                param(
                    [Object[]]$Package,
                    [String]$Direction,
                    [String]$PackageManager,
                    [ScriptBlock]$CommandRunner
                )

                if ($Direction -eq 'DependsOn')
                {
                    return @([PSCustomObject]@{ RelatedPackage = 'gettext'; DependencyType = 'Dependency'; Installed = $true })
                }

                return @([PSCustomObject]@{ RelatedPackage = 'curl'; DependencyType = 'Dependent'; Installed = $true })
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('d', [ConsoleKey]::D, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('b', [ConsoleKey]::B, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Remove-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Removed | Should -Be 0
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'DependsOn' } -Times 1
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'RequiredBy' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Resolving dependencies...' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Dependencies [DependsOn + RequiredBy]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Dependencies [DependsOn]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Dependencies [RequiredBy]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Press B/Backspace/Delete/LeftArrow to return to the package list.' } -Times 2
        }

        It 'returns from dependency view to the removal picker on <Name> when manager navigation is enabled' -TestCases @(
            @{ Name = 'Backspace'; Key = [ConsoleKey]::Backspace; Char = [Char]8 }
            @{ Name = 'Delete'; Key = [ConsoleKey]::Delete; Char = [Char]0 }
        ) {
            param($Name, $Key, $Char)

            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            Mock -CommandName Get-PlatformPackageDependency -MockWith {
                param(
                    [Object[]]$Package,
                    [String]$Direction,
                    [String]$PackageManager,
                    [ScriptBlock]$CommandRunner
                )

                return @([PSCustomObject]@{ RelatedPackage = 'gettext'; DependencyType = 'Dependency'; Installed = $true })
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('d', [ConsoleKey]::D, $false, $false, $false)
                [System.ConsoleKeyInfo]::new($Char, $Key, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Remove-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -ReturnToPlatformPackageManagerOnBackKey -Confirm:$false

            $result.Selected | Should -Be 0
            $result.Removed | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq "Keys: Space select  P purge/zap  Enter remove  D deps  V details  A all  F: [all]" } -Times 2
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Remove-PlatformPackage Dependencies - Homebrew' } -Times 2
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Press B/Backspace/Delete/LeftArrow to return to the package list.' } -Times 2
        }

        It 'filters picker results by package name when F is pressed' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0', 'curl 8.7.1')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uninstall git' = Get-TestCommandResponse -Output @('brew uninstall git output')
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('f', [ConsoleKey]::F, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('g', [ConsoleKey]::G, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Remove-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Removed | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).Count | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall curl' }).Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Current filter: g' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'F: \[g\]' } -Times 1
        }

        It 'treats lowercase q as filter text instead of cancel' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0', 'jq 1.7.1')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uninstall jq' = Get-TestCommandResponse -Output @('brew uninstall jq output')
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('f', [ConsoleKey]::F, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Remove-PlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Removed | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall jq' }).Count | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Current filter: q' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'F: \[q\]' } -Times 1
        }
    }

    Context 'winget package discovery' {
        It 'falls back to table parsing when JSON output is unavailable' {
            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
                'winget list --accept-source-agreements' = Get-TestCommandResponse -Output @(
                    'Name               Id                          Version Source'
                    '--------------------------------------------------------------'
                    'PowerShell         Microsoft.PowerShell        7.4.2   winget'
                    'Git                Git.Git                     2.44.0  winget'
                )
            }

            $result = @(Remove-PlatformPackage -PackageManager winget -NonInteractive -CommandRunner $runner)

            $result.Count | Should -Be 2

            $powershell = $result | Where-Object { $_.Name -eq 'PowerShell' }
            $powershell.Id | Should -Be 'Microsoft.PowerShell'
            $powershell.InstalledVersion | Should -Be '7.4.2'
            (@($powershell.RemoveArguments) -join '|') | Should -Be 'uninstall|--id|Microsoft.PowerShell|--exact|--source|winget|--accept-source-agreements'
        }

        It 'uses winget purge when purge is requested' {
            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
                'winget list --accept-source-agreements' = Get-TestCommandResponse -Output @(
                    'Name               Id                          Version Source'
                    '--------------------------------------------------------------'
                    'PowerShell         Microsoft.PowerShell        7.4.2   winget'
                )
            }

            $result = @(Remove-PlatformPackage -PackageManager winget -NonInteractive -Purge -CommandRunner $runner)

            (@($result[0].RemoveArguments) -join '|') | Should -Be 'uninstall|--id|Microsoft.PowerShell|--exact|--source|winget|--accept-source-agreements|--purge'
        }

        It 'passes the installed package source to winget uninstall commands' {
            $wingetListJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'msstore'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.44.0'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
                'winget uninstall --id Git.Git --exact --source msstore --accept-source-agreements' = Get-TestCommandResponse -Output @('winget uninstall output')
            }

            $result = Remove-PlatformPackage -PackageManager winget -IncludePackage Git -All -CommandRunner $runner -Confirm:$false

            $result.Removed | Should -Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'winget uninstall --id Git.Git --exact --source msstore --accept-source-agreements' }).StreamOutput | Should -BeTrue
        }

        It 'renders and applies the purge column for winget interactive removals' {
            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
                'winget list --accept-source-agreements' = Get-TestCommandResponse -Output @(
                    'Name               Id                          Version Source'
                    '--------------------------------------------------------------'
                    'PowerShell         Microsoft.PowerShell        7.4.2   winget'
                )
                'winget uninstall --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --purge' = Get-TestCommandResponse -Output @('winget purge output')
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('p', [ConsoleKey]::P, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Remove-PlatformPackage -PackageManager winget -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Removed | Should -Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'winget uninstall --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --purge' }).StreamOutput | Should -BeTrue
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -clike '*Purge*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'winget purge output' } -Times 1
        }

        It 'keeps picker table rows within the current console width' {
            $wingetListJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '17.0.1010.2'
                                Source = 'homebrew/core'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
            }
            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $null = Remove-PlatformPackage -PackageManager winget -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $tableLines = @(
                $script:HostOutput |
                ForEach-Object { "$_" } |
                Where-Object {
                    $_ -match '^\s+Sel\s+Purge\s+' -or
                    $_ -match '^[> ] \[[ x]\] \[[ p]\]\s+'
                }
            )

            $tableLines.Count | Should -BeGreaterThan 1
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+Purge\s+' } | Select-Object -First 1) | Should -Match '\bVer\b'
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+Purge\s+' } | Select-Object -First 1) | Should -Match '\bTyp\b'
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+Purge\s+' } | Select-Object -First 1) | Should -Match '\bSrc\b'
            ($tableLines | Where-Object { $_ -match '^[> ] \[[ x]\] \[[ p]\]\s+' } | Select-Object -First 1) | Should -Match 'homebrew/core'
            (($tableLines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum) | Should -BeLessOrEqual (Get-TestPickerLineLimit)
        }

        It 'defaults source filter to winget for the winget picker when multiple sources exist' {
            $wingetListJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.44.0'
                            }
                        )
                    }
                    @{
                        SourceDetails = @{
                            Name = 'msstore'
                        }
                        Packages = @(
                            @{
                                PackageName = 'App Installer'
                                PackageIdentifier = 'Microsoft.AppInstaller'
                                Version = '1.24.12371.0'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
            }
            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $null = Remove-PlatformPackage -PackageManager winget -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'S: \[winget\]' } -Times 1
        }

        It 'removes only the visible package when filtering duplicate winget ids by source' {
            $wingetListJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.44.0'
                            }
                        )
                    }
                    @{
                        SourceDetails = @{
                            Name = 'msstore'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.44.0'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
                'winget uninstall --id Git.Git --exact --source msstore --accept-source-agreements' = Get-TestCommandResponse -Output @('winget uninstall output')
            }
            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            }

            $result = Remove-PlatformPackage -PackageManager winget -FilterSource msstore -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 1
            $result.Removed | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'winget uninstall --id Git.Git --exact --source winget --accept-source-agreements' }).Count | Should -Be 0
            ($script:Invocations | Where-Object { $_.Key -eq 'winget uninstall --id Git.Git --exact --source msstore --accept-source-agreements' }).StreamOutput | Should -BeTrue
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'S: \[msstore\]' } -Times 1
        }
    }

    Context 'Filtering and dry runs' {
        It 'applies include and exclude filters to package names and ids' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @(
                    'git 2.44.0'
                    'node 22.0.0'
                    'git-lfs 3.5.0'
                )
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $result = @(Remove-PlatformPackage -PackageManager brew -NonInteractive -IncludePackage 'git*' -ExcludePackage 'git-lfs' -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
        }

        It 'honors -WhatIf for remove commands' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $result = Remove-PlatformPackage -PackageManager brew -IncludePackage git -All -WhatIf -CommandRunner $runner

            $result | Should -Not -BeNullOrEmpty
            $result.Selected | Should -Be 1
            $result.NotSelected | Should -Be 0
            $result.Removed | Should -Be 0
            $result.Skipped | Should -Be 1

            @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).Count | Should -Be 0
        }
    }
}
