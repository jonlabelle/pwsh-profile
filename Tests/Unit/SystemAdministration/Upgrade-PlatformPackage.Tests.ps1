#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Upgrade-PlatformPackage.ps1"
    . "$PSScriptRoot/PlatformPackageTestHelpers.ps1"
}

Describe 'Upgrade-PlatformPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        $script:HostOutput = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith { $script:HostOutput.Add($Object) }
        Mock -CommandName Clear-Host -MockWith {}
    }

    Context 'Homebrew package discovery' {
        It 'returns formula and cask update records from JSON output' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                        pinned = $false
                    }
                )
                casks = @(
                    @{
                        name = 'visual-studio-code'
                        installed_versions = @('1.88.0')
                        current_version = '1.89.0'
                        auto_updates = $false
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
            }

            $result = @(Upgrade-PlatformPackage -PackageManager brew -SkipRefresh -NonInteractive -CommandRunner $runner)

            $result.Count | Should -Be 2

            $formula = $result | Where-Object { $_.Name -eq 'git' }
            $formula.PackageManager | Should -Be 'brew'
            $formula.Type | Should -Be 'Formula'
            $formula.InstalledVersion | Should -Be '2.43.0'
            $formula.LatestVersion | Should -Be '2.44.0'
            (@($formula.UpgradeArguments) -join '|') | Should -Be 'upgrade|git'

            $cask = $result | Where-Object { $_.Name -eq 'visual-studio-code' }
            $cask.Type | Should -Be 'Cask'
            (@($cask.UpgradeArguments) -join '|') | Should -Be 'upgrade|--cask|visual-studio-code'
        }

        It 'keeps AsObject as an alias for NonInteractive discovery' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
            }

            $result = @(Upgrade-PlatformPackage -PackageManager brew -SkipRefresh -AsObject -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            (@($result[0].UpgradeArguments) -join '|') | Should -Be 'upgrade|git'
            @($script:Invocations | Where-Object { $_.Key -eq 'brew upgrade git' }).Count | Should -Be 0
        }

        It 'captures Homebrew refresh output and streams upgrade command output when upgrading all packages' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                        pinned = $false
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew update --quiet' = Get-TestCommandResponse -Output @('brew update output')
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
                'brew upgrade git' = Get-TestCommandResponse -Output @('brew upgrade git output')
            }

            $result = Upgrade-PlatformPackage -PackageManager brew -All -CommandRunner $runner -Confirm:$false

            $result.Upgraded | Should -Be 1
            $result.Failed | Should -Be 0
            $result.NotSelected | Should -Be 0

            ($script:Invocations | Where-Object { $_.Key -eq 'brew update --quiet' }).StreamOutput | Should -BeFalse
            ($script:Invocations | Where-Object { $_.Key -eq 'brew upgrade git' }).StreamOutput | Should -BeTrue

            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'brew update output' } -Times 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'brew upgrade git output' } -Times 1
        }

        It 'captures Homebrew refresh process output before the picker and streams upgrade process output' {
            $nativeCommandDirectory = Join-Path -Path $TestDrive -ChildPath "native-brew-$(Get-Random)"
            $brewPath = & $script:NewNativeBrewCommand -Directory $nativeCommandDirectory
            $brewLogPath = Join-Path -Path $nativeCommandDirectory -ChildPath 'brew-invocations.log'
            $childScriptPath = Join-Path -Path $TestDrive -ChildPath 'invoke-upgrade-platform-package.ps1'
            $functionPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '../../../Functions/SystemAdministration/Upgrade-PlatformPackage.ps1'))

            $childScript = @'
$ErrorActionPreference = 'Stop'

. $env:UPGRADE_TEST_FUNCTION_PATH

$keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
@(
    [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
    [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
) | ForEach-Object { $keys.Enqueue($_) }

$keyReader = {
    if ($keys.Count -eq 0)
    {
        throw 'Unexpected key read'
    }

    return $keys.Dequeue()
}.GetNewClosure()

$result = Upgrade-PlatformPackage -PackageManager brew -CommandPathOverrides @{ brew = $env:UPGRADE_TEST_BREW_PATH } -KeyReader $keyReader -Confirm:$false
"RESULT Upgraded=$($result.Upgraded) Failed=$($result.Failed) NotSelected=$($result.NotSelected)"
'@
            [System.IO.File]::WriteAllText($childScriptPath, $childScript, [System.Text.UTF8Encoding]::new($false))

            $powerShellCommand = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
            if (-not $powerShellCommand)
            {
                $powerShellCommand = Get-Command -Name 'powershell' -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            }

            $powerShellCommand | Should -Not -BeNullOrEmpty

            $previousFunctionPath = $env:UPGRADE_TEST_FUNCTION_PATH
            $previousBrewPath = $env:UPGRADE_TEST_BREW_PATH
            $previousBrewLogPath = $env:UPGRADE_TEST_BREW_LOG_PATH

            try
            {
                $env:UPGRADE_TEST_FUNCTION_PATH = $functionPath
                $env:UPGRADE_TEST_BREW_PATH = $brewPath
                $env:UPGRADE_TEST_BREW_LOG_PATH = $brewLogPath

                $childOutput = @(
                    & $powerShellCommand.Source -NoLogo -NoProfile -File $childScriptPath 2>&1 |
                    ForEach-Object { "$_" }
                )
                $childExitCode = $LASTEXITCODE
            }
            finally
            {
                if ($null -eq $previousFunctionPath)
                {
                    Remove-Item -Path Env:\UPGRADE_TEST_FUNCTION_PATH -ErrorAction SilentlyContinue
                }
                else
                {
                    $env:UPGRADE_TEST_FUNCTION_PATH = $previousFunctionPath
                }

                if ($null -eq $previousBrewPath)
                {
                    Remove-Item -Path Env:\UPGRADE_TEST_BREW_PATH -ErrorAction SilentlyContinue
                }
                else
                {
                    $env:UPGRADE_TEST_BREW_PATH = $previousBrewPath
                }

                if ($null -eq $previousBrewLogPath)
                {
                    Remove-Item -Path Env:\UPGRADE_TEST_BREW_LOG_PATH -ErrorAction SilentlyContinue
                }
                else
                {
                    $env:UPGRADE_TEST_BREW_LOG_PATH = $previousBrewLogPath
                }
            }

            $childExitCode | Should -Be 0
            $outputText = $childOutput -join "`n"
            $outputText | Should -Match 'Refreshing Homebrew package metadata'
            $outputText | Should -Match 'Upgrade-PlatformPackage - Homebrew'
            $outputText | Should -Not -Match ([Regex]::Escape('brew update stdout'))
            $outputText | Should -Not -Match ([Regex]::Escape('brew update stderr'))
            $outputText | Should -Match ([Regex]::Escape('brew upgrade stdout'))
            $outputText | Should -Match ([Regex]::Escape('brew upgrade stderr'))
            $outputText | Should -Match 'RESULT Upgraded=1 Failed=0 NotSelected=0'

            $brewInvocations = @(Get-Content -LiteralPath $brewLogPath)
            $brewInvocations | Should -Contain 'update --quiet'
            $brewInvocations | Should -Contain 'outdated --json=v2 --greedy'
            $brewInvocations | Should -Contain 'upgrade git'
        }

        It 'captures post-upgrade instructions in the result object' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'python'
                        installed_versions = @('3.12.0')
                        current_version = '3.12.1'
                        pinned = $false
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
                'brew upgrade python' = Get-TestCommandResponse -Output @(
                    'Upgrading python...'
                    '==> Caveats'
                    'Add /opt/homebrew/opt/python/libexec/bin to PATH'
                )
            }

            $result = Upgrade-PlatformPackage -PackageManager brew -SkipRefresh -All -CommandRunner $runner -Confirm:$false

            $result.Upgraded | Should -Be 1
            $result.Results[0].CapturedOutput | Should -Contain 'Upgrading python...'
            $result.Results[0].InformationalOutput | Should -Contain '==> Caveats'
            $result.InformationalResults.Count | Should -Be 1
            $result.InformationalResults[0].Lines | Should -Contain 'Add /opt/homebrew/opt/python/libexec/bin to PATH'
        }

        It 'reports streamed command failures with command context when captured output is unavailable' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                        pinned = $false
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
                'brew upgrade git' = Get-TestCommandResponse -ExitCode 42 -Output @()
            }

            $result = Upgrade-PlatformPackage -PackageManager brew -SkipRefresh -All -CommandRunner $runner -Confirm:$false -WarningAction SilentlyContinue

            $result.Failed | Should -Be 1
            $result.Skipped | Should -Be 0
            $result.NotSelected | Should -Be 0
            $result.Results[0].Message | Should -Match 'brew upgrade git failed with exit code 42'
            $result.Results[0].Message | Should -Match 'streamed directly to the console'
        }

        It 'does not read stale LASTEXITCODE for unstructured command runner output' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                        pinned = $false
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $lastExitCode = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue

            try
            {
                $global:LASTEXITCODE = 42

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

                    if ($key -eq 'brew outdated --json=v2 --greedy')
                    {
                        return [PSCustomObject]@{
                            ExitCode = 0
                            Output = @($brewJson)
                        }
                    }

                    if ($key -eq 'brew upgrade git')
                    {
                        return 'brew upgrade git output'
                    }

                    return [PSCustomObject]@{
                        ExitCode = 127
                        Output = @("Unexpected command: $key")
                    }
                }.GetNewClosure()

                $result = Upgrade-PlatformPackage -PackageManager brew -SkipRefresh -All -CommandRunner $runner -Confirm:$false

                $result.Upgraded | Should -Be 1
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
    }

    Context 'Linux package discovery' {
        It 'parses apt upgradable package output' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt list --upgradable' = Get-TestCommandResponse -Output @(
                    'Listing... Done'
                    'openssl/jammy-updates 3.0.2-0ubuntu1.15 arm64 [upgradable from: 3.0.2-0ubuntu1.14]'
                )
            }

            $result = @(Upgrade-PlatformPackage -PackageManager apt -SkipRefresh -NonInteractive -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'openssl'
            $result[0].PackageManager | Should -Be 'apt'
            $result[0].InstalledVersion | Should -Be '3.0.2-0ubuntu1.14'
            $result[0].LatestVersion | Should -Be '3.0.2-0ubuntu1.15'
            (@($result[0].UpgradeArguments) -join '|') | Should -Be 'install|--only-upgrade|-y|openssl'
        }

        It 'parses apk version output and keeps hyphenated package names' {
            $runner = & $script:NewPackageCommandRunner @{
                'apk version -l <' = Get-TestCommandResponse -Output @(
                    'busybox-1.36.1-r19 < 1.36.1-r20'
                    'py3-requests-2.31.0-r0 < 2.32.0-r0'
                )
            }

            $result = @(Upgrade-PlatformPackage -PackageManager apk -SkipRefresh -NonInteractive -CommandRunner $runner)

            $result.Count | Should -Be 2

            $busybox = $result | Where-Object { $_.Name -eq 'busybox' }
            $busybox.InstalledVersion | Should -Be '1.36.1-r19'
            $busybox.LatestVersion | Should -Be '1.36.1-r20'
            (@($busybox.UpgradeArguments) -join '|') | Should -Be 'add|--upgrade|busybox'

            $requests = $result | Where-Object { $_.Name -eq 'py3-requests' }
            $requests.InstalledVersion | Should -Be '2.31.0-r0'
            $requests.LatestVersion | Should -Be '2.32.0-r0'
        }
    }

    Context 'Interactive package selection' {
        It 'treats Ctrl+C as a cancel command' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                        pinned = $false
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
                'brew upgrade git' = Get-TestCommandResponse -Output @('brew upgrade git output')
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = Upgrade-PlatformPackage -PackageManager brew -SkipRefresh -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 0
            $result.NotSelected | Should -Be 1
            $result.Upgraded | Should -Be 0
            @($script:Invocations | Where-Object { $_.Key -eq 'brew upgrade git' }).Count | Should -Be 0
            @($script:HostOutput | Where-Object { [String]::IsNullOrEmpty([String]$_) }).Count | Should -Be 4
        }

        It 'shows keyboard help from the upgrade picker' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                        pinned = $false
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
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

            $result = Upgrade-PlatformPackage -PackageManager brew -SkipRefresh -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 0
            $result.Upgraded | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq "Keys: Space select  Enter upgrade  V details  A toggle all  F: [all]" } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq "1-1 of 1 visible  $([char]0x00B7)  1 total  $([char]0x00B7)  0 selected" -and $ForegroundColor -eq 'White' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Upgrade-PlatformPackage Help' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Enter: ' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'upgrade selected packages' -and $ForegroundColor -eq 'DarkGray' } -Times 1
        }

        It 'renders only the current viewport for long upgrade lists' {
            $brewJson = @{
                formulae = @(
                    @{ name = 'pkg-01'; installed_versions = @('1.0.0'); current_version = '1.1.0' }
                    @{ name = 'pkg-02'; installed_versions = @('1.0.0'); current_version = '1.1.0' }
                    @{ name = 'pkg-03'; installed_versions = @('1.0.0'); current_version = '1.1.0' }
                    @{ name = 'pkg-04'; installed_versions = @('1.0.0'); current_version = '1.1.0' }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $null = Upgrade-PlatformPackage -PackageManager brew -SkipRefresh -CommandRunner $runner -KeyReader $keyReader -PickerPageSize 2 -Confirm:$false

            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-01*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-02*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-03*' } -Times 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-04*' } -Times 0
        }

        It 'filters picker results by package name when F is pressed' {
            $brewJson = @{
                formulae = @(
                    @{ name = 'git'; installed_versions = @('2.43.0'); current_version = '2.44.0'; pinned = $false }
                    @{ name = 'curl'; installed_versions = @('8.6.0'); current_version = '8.7.1'; pinned = $false }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
                'brew upgrade git' = Get-TestCommandResponse -Output @('brew upgrade git output')
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

            $result = Upgrade-PlatformPackage -PackageManager brew -SkipRefresh -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Upgraded | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew upgrade git' }).Count | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew upgrade curl' }).Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Current filter: g' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'F: \[g\]' } -Times 1
        }

        It 'treats lowercase q as filter text instead of cancel' {
            $brewJson = @{
                formulae = @(
                    @{ name = 'git'; installed_versions = @('2.43.0'); current_version = '2.44.0'; pinned = $false }
                    @{ name = 'jq'; installed_versions = @('1.6'); current_version = '1.7.1'; pinned = $false }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
                'brew upgrade jq' = Get-TestCommandResponse -Output @('brew upgrade jq output')
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

            $result = Upgrade-PlatformPackage -PackageManager brew -SkipRefresh -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Upgraded | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew upgrade jq' }).Count | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew upgrade git' }).Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Current filter: q' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'F: \[q\]' } -Times 1
        }

        It 'upgrades only the visible package when filtering duplicate winget ids by source' {
            $wingetUpgradeJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.43.0'
                                Available = '2.44.0'
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
                                Version = '2.43.0'
                                Available = '2.44.0'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget upgrade --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetUpgradeJson)
                'winget upgrade --id Git.Git --exact --source msstore --accept-package-agreements --accept-source-agreements' = Get-TestCommandResponse -Output @('winget upgrade output')
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Upgrade-PlatformPackage -PackageManager winget -SkipRefresh -FilterSource msstore -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 1
            $result.Upgraded | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'winget upgrade --id Git.Git --exact --source winget --accept-package-agreements --accept-source-agreements' }).Count | Should -Be 0
            ($script:Invocations | Where-Object { $_.Key -eq 'winget upgrade --id Git.Git --exact --source msstore --accept-package-agreements --accept-source-agreements' }).StreamOutput | Should -BeTrue
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'S: \[msstore\]' } -Times 1
        }

        It 'does not suppress terminal echo when a custom key reader drives winget details' -Skip:($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) {
            $wingetUpgradeJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.43.0'
                                Available = '2.44.0'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $wingetShowJson = @{
                DefaultLocale = @{
                    Description = 'Distributed version control system'
                }
            } | ConvertTo-Json -Depth 4 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget upgrade --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetUpgradeJson)
                'winget show --id Git.Git --exact --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetShowJson)
            }
            $keyReader = & $script:NewKeyReader -Values @(
                [System.ConsoleKeyInfo]::new('v', [ConsoleKey]::V, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            )
            $echoActions = New-Object 'System.Collections.Generic.List[Object]'
            $terminalEchoController = & $script:NewTerminalEchoController -Actions $echoActions

            $result = Upgrade-PlatformPackage -PackageManager winget -SkipRefresh -CommandRunner $runner -KeyReader $keyReader -TerminalEchoController $terminalEchoController -Confirm:$false

            $result.Selected | Should -Be 0
            $echoActions.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: Distributed version control system' } -Times 1
        }

        It 'restores terminal echo when winget details throw in the console key reader flow' -Skip:($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) {
            $wingetUpgradeJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.43.0'
                                Available = '2.44.0'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $upgradeResponse = Get-TestCommandResponse -Output @($wingetUpgradeJson)
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
                if ($key -eq 'winget upgrade --accept-source-agreements --output json')
                {
                    return $upgradeResponse
                }

                if ($key -eq 'winget show --id Git.Git --exact --accept-source-agreements --output json')
                {
                    throw 'winget details failed'
                }

                return [PSCustomObject]@{
                    ExitCode = 127
                    Output = @("Unexpected command: $key")
                }
            }.GetNewClosure()
            $keyReader = & $script:NewKeyReader -Values @(
                [System.ConsoleKeyInfo]::new('v', [ConsoleKey]::V, $false, $false, $false)
            )
            $echoActions = New-Object 'System.Collections.Generic.List[Object]'
            $terminalEchoController = & $script:NewTerminalEchoController -Actions $echoActions

            {
                Upgrade-PlatformPackage -PackageManager winget -SkipRefresh -CommandRunner $runner -KeyReader $keyReader -TreatKeyReaderAsConsoleKeyReader -TerminalEchoController $terminalEchoController -Confirm:$false
            } | Should -Throw -ExpectedMessage '*winget details failed*'

            ($echoActions -join '|') | Should -Be 'Disable|Restore:saved-stty-state'
        }

        It 'keeps winget picker table rows within the current console width' {
            $wingetUpgradeJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '16.0.5685.0'
                                Available = '17.0.1010.2'
                                Source = 'homebrew/core'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget upgrade --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetUpgradeJson)
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $null = Upgrade-PlatformPackage -PackageManager winget -SkipRefresh -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $limit = 0
            try
            {
                if (-not [Console]::IsOutputRedirected)
                {
                    $limit = [Console]::BufferWidth - 1
                }
            }
            catch
            {
                $limit = 0
            }

            if ($limit -le 0)
            {
                try
                {
                    $limit = $Host.UI.RawUI.BufferSize.Width - 1
                }
                catch
                {
                    $limit = 0
                }
            }

            if ($limit -le 0)
            {
                $limit = 119
            }

            $limit = [Math]::Max(60, $limit)
            $tableLines = @(
                $script:HostOutput |
                ForEach-Object { "$_" } |
                Where-Object {
                    $_ -match '^\s+Sel\s+Unp\s+' -or
                    $_ -match '^[> ] \[[ x]\] \[[ u]\]\s+'
                }
            )

            $tableLines.Count | Should -BeGreaterThan 1
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+Unp\s+' } | Select-Object -First 1) | Should -Match '\bInst\b'
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+Unp\s+' } | Select-Object -First 1) | Should -Match '\bAvail\b'
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+Unp\s+' } | Select-Object -First 1) | Should -Match '\bTyp\b'
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+Unp\s+' } | Select-Object -First 1) | Should -Match '\bSrc\b'
            ($tableLines | Where-Object { $_ -match '^[> ] \[[ x]\] \[[ u]\]\s+' } | Select-Object -First 1) | Should -Match 'homebrew/core'
            (($tableLines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum) | Should -BeLessOrEqual $limit
        }
    }

    Context 'winget package discovery' {
        It 'does not stream winget source refresh output to the console' {
            $wingetUpgradeJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{ Name = 'winget' }
                        Packages = @(
                            @{ PackageName = 'PowerShell'; PackageIdentifier = 'Microsoft.PowerShell'; Version = '7.4.1'; Available = '7.4.2' }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget source update' = Get-TestCommandResponse -Output @(
                    'Updating all sources...'
                    'Updating source: msstore...'
                    'Done'
                )
                'winget upgrade --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetUpgradeJson)
            }

            $result = @(Upgrade-PlatformPackage -PackageManager winget -NonInteractive -CommandRunner $runner)

            $result.Count | Should -Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'winget source update' }).StreamOutput | Should -BeFalse
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like 'Updating all sources*' -or $Object -like 'Updating source:*' } -Times 0
        }

        It 'falls back to table parsing when JSON output is unavailable' {
            $runner = & $script:NewPackageCommandRunner @{
                'winget upgrade --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
                'winget upgrade --accept-source-agreements' = Get-TestCommandResponse -Output @(
                    'Name               Id                          Version Available Source'
                    '-----------------------------------------------------------------------'
                    'PowerShell         Microsoft.PowerShell        7.4.1   7.4.2     winget'
                    'Git                Git.Git                     2.43.0  2.44.0    winget'
                    '27 package(s) have version numbers that cannot be determined. Use --include-unknown to see all results.'
                )
            }

            $result = @(Upgrade-PlatformPackage -PackageManager winget -SkipRefresh -NonInteractive -CommandRunner $runner)

            $result.Count | Should -Be 2

            $powershell = $result | Where-Object { $_.Name -eq 'PowerShell' }
            $powershell.Id | Should -Be 'Microsoft.PowerShell'
            $powershell.InstalledVersion | Should -Be '7.4.1'
            $powershell.LatestVersion | Should -Be '7.4.2'
            (@($powershell.UpgradeArguments) -join '|') | Should -Be 'upgrade|--id|Microsoft.PowerShell|--exact|--source|winget|--accept-package-agreements|--accept-source-agreements'
        }

        It 'passes the package source to winget upgrade commands' {
            $wingetUpgradeJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'msstore'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.43.0'
                                Available = '2.44.0'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget upgrade --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetUpgradeJson)
                'winget upgrade --id Git.Git --exact --source msstore --accept-package-agreements --accept-source-agreements' = Get-TestCommandResponse -Output @('winget upgrade output')
            }

            $result = Upgrade-PlatformPackage -PackageManager winget -SkipRefresh -All -CommandRunner $runner -Confirm:$false

            $result.Upgraded | Should -Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'winget upgrade --id Git.Git --exact --source msstore --accept-package-agreements --accept-source-agreements' }).StreamOutput | Should -BeTrue
        }
    }

    Context 'Filtering and dry runs' {
        It 'applies include and exclude filters to package names and ids' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                    }
                    @{
                        name = 'node'
                        installed_versions = @('21.0.0')
                        current_version = '22.0.0'
                    }
                    @{
                        name = 'git-lfs'
                        installed_versions = @('3.4.0')
                        current_version = '3.5.0'
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
            }

            $result = @(Upgrade-PlatformPackage -PackageManager brew -SkipRefresh -NonInteractive -IncludePackage 'git*' -ExcludePackage 'git-lfs' -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
        }

        It 'honors -WhatIf for refresh and upgrade commands' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2 --greedy' = Get-TestCommandResponse -Output @($brewJson)
            }

            $result = Upgrade-PlatformPackage -PackageManager brew -All -WhatIf -CommandRunner $runner

            $result | Should -Not -BeNullOrEmpty
            $result.Selected | Should -Be 1
            $result.NotSelected | Should -Be 0
            $result.Upgraded | Should -Be 0
            $result.Skipped | Should -Be 1

            @($script:Invocations | Where-Object { $_.Key -eq 'brew update --quiet' }).Count | Should -Be 0
            @($script:Invocations | Where-Object { $_.Key -eq 'brew upgrade git' }).Count | Should -Be 0
        }
    }
}
