#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Export-InstalledPlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Show-InstalledPlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Get-PlatformPackageDependency.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Remove-PlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Upgrade-PlatformPackage.ps1"
    . "$PSScriptRoot/PlatformPackageTestHelpers.ps1"
}

Describe 'Show-InstalledPlatformPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        $script:HostOutput = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith { $script:HostOutput.Add($Object) }
        Mock -CommandName Clear-Host -MockWith {}
    }

    Context 'Object output' {
        It 'returns installed packages as objects when NonInteractive is used' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @('visual-studio-code 1.89.0'))
            }

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -NonInteractive -CommandRunner $runner)

            $result.Count | Should -Be 2
            ($result | Where-Object { $_.Name -eq 'git' }).InstalledVersion | Should -Be '2.44.0'
            ($result | Where-Object { $_.Name -eq 'git' }).Publisher | Should -Be 'Homebrew'
        }

        It 'keeps AsObject as an alias for NonInteractive output' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -AsObject -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            $result[0].PackageManager | Should -Be 'brew'
            Assert-MockCalled -CommandName Write-Host -Times 0
        }

        It 'exports installed packages to inferred JSON without opening the picker' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0', 'curl 8.7.1'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $exportPath = Join-Path -Path $TestDrive -ChildPath 'installed-packages.json'
            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -ExportPath $exportPath)

            $result.Count | Should -Be 1
            $result[0].Format | Should -Be 'JSON'
            $result[0].Count | Should -Be 2
            $result[0].DependencyMode | Should -Be 'None'
            Test-Path -LiteralPath $exportPath | Should -BeTrue
            $exportedPackages = Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json
            $exportedPackages.Count | Should -Be 2
            ($exportedPackages | Where-Object { $_.Name -eq 'git' }).InstalledVersion | Should -Be '2.44.0'
            Assert-MockCalled -CommandName Write-Host -Times 0
        }

        It 'exports installed packages to explicit CSV with dependency relationships' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
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
                    return @([PSCustomObject]@{
                            Direction = $Direction
                            Relationship = "$($Package[0].Name) -> openssl"
                            RelatedPackage = 'openssl'
                            DependencyType = 'Dependency'
                            Installed = $true
                            Notes = ''
                        })
                }

                return @([PSCustomObject]@{
                        Direction = $Direction
                        Relationship = "git-extras -> $($Package[0].Name)"
                        RelatedPackage = 'git-extras'
                        DependencyType = 'Dependent'
                        Installed = $false
                        Notes = ''
                    })
            }

            $exportPath = Join-Path -Path $TestDrive -ChildPath 'installed-packages-export'
            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -ExportPath $exportPath -ExportFormat Csv -ExportDependencyMode Both)

            $result.Count | Should -Be 1
            $result[0].Format | Should -Be 'CSV'
            $result[0].DependencyMode | Should -Be 'Both'
            $exportedPackages = @(Import-Csv -LiteralPath $exportPath)
            $exportedPackages.Count | Should -Be 1
            $exportedPackages[0].DependsOn | Should -Be 'openssl'
            $exportedPackages[0].RequiredBy | Should -Be 'git-extras'
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'DependsOn' } -Times 1
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'RequiredBy' } -Times 1
            Assert-MockCalled -CommandName Write-Host -Times 0
        }

        It 'shows dependency resolution progress when export progress is requested' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            Mock -CommandName Get-PlatformPackageDependency -MockWith {
                param(
                    [Object[]]$Package,
                    [String]$Direction,
                    [String]$PackageManager,
                    [ScriptBlock]$CommandRunner
                )

                [PSCustomObject]@{
                    Direction = $Direction
                    Relationship = "$($Package[0].Name) -> openssl"
                    RelatedPackage = 'openssl'
                    DependencyType = 'Dependency'
                    Installed = $true
                    Notes = ''
                }
            }

            $exportPath = Join-Path -Path $TestDrive -ChildPath 'installed-packages-progress.csv'
            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -ExportPath $exportPath -ExportFormat Csv -ExportDependencyMode Both -ShowExportProgress)

            $result.Count | Should -Be 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Exporting installed packages...' -and $ForegroundColor -eq 'Cyan' } -Times 2
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Package: 1 of 1 - git' -and $ForegroundColor -eq 'White' } -Times 2
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Resolving: DependsOn' -and $ForegroundColor -eq 'White' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Resolving: RequiredBy' -and $ForegroundColor -eq 'White' } -Times 1
        }
    }

    Context 'Interactive browsing' {
        It 'returns no output when cancelled' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: D deps  V details  E export  R remove  U upgrade  F: [all]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Nav: Home/End/PgUp/PgDn  ?: help  Q/Esc/Ctrl+C exit' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq "1-1 of 1 visible  $([char]0x00B7)  1 total  $([char]0x00B7)  filter: all" -and $ForegroundColor -eq 'White' } -Times 1
            @($script:HostOutput | Where-Object { [String]::IsNullOrEmpty([String]$_) }).Count | Should -Be 2
        }

        It 'does not exit when Enter is pressed in browse mode' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: D deps  V details  E export  R remove  U upgrade  F: [all]' } -Times 2
        }

        It 'ignores Backspace and Delete as manager navigation when not launched by the manager' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
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

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: D deps  V details  E export  R remove  U upgrade  F: [all]' } -Times 3
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Backspace/Delete: manager menu' } -Times 0
        }

        It 'returns to the manager menu on <Name> when manager navigation is enabled' -TestCases @(
            @{ Name = 'Backspace'; Key = [ConsoleKey]::Backspace; Char = [Char]8 }
            @{ Name = 'Delete'; Key = [ConsoleKey]::Delete; Char = [Char]0 }
        ) {
            param($Name, $Key, $Char)

            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new($Char, $Key, $false, $false, $false)
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -ReturnToPlatformPackageManagerOnBackKey)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: D deps  V details  E export  R remove  U upgrade  F: [all]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Backspace/Delete: manager menu' } -Times 1
        }

        It 'renders only the current viewport for long package lists' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @(
                        'pkg-01 1.0.0'
                        'pkg-02 1.0.0'
                        'pkg-03 1.0.0'
                        'pkg-04 1.0.0'
                    ))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $null = Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PickerPageSize 2

            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-01*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-02*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-03*' } -Times 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-04*' } -Times 0
        }

        It 'returns selected packages when PassThru is used' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @('visual-studio-code 1.89.0'))
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PassThru)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: Space select  Enter return  D deps  V details  E export  R remove  U upgrade  A toggle all  F: [all]' } -Times 1
        }

        It 'returns the current package when PassThru is used without a selection' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @('visual-studio-code 1.89.0'))
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            }

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PassThru)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: Space select  Enter return  D deps  V details  E export  R remove  U upgrade  A toggle all  F: [all]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Nav: S: [All]  Home/End/PgUp/PgDn  ?: help  Q/Esc/Ctrl+C exit' } -Times 1
        }

        It 'shows keyboard help from the picker when question mark is pressed' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
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

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Show-InstalledPlatformPackage Help' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'D: ' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'open or close the dependency view for the current package' -and $ForegroundColor -eq 'DarkGray' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'B: ' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'return to the package list from the dependency view' -and $ForegroundColor -eq 'DarkGray' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'V: ' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'load a missing winget description when available' -and $ForegroundColor -eq 'DarkGray' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'E: ' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'export visible packages, or selected packages when any are selected, to JSON or CSV' -and $ForegroundColor -eq 'DarkGray' } -Times 1
        }

        It 'loads missing winget descriptions only when V is pressed' {
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.45.1'
                                Source = 'winget'
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
                'winget list --accept-source-agreements --output json' = (& $script:NewTestCommandResponse -Output @($wingetListJson))
                'winget show --id Git.Git --exact --accept-source-agreements --output json' = (& $script:NewTestCommandResponse -Output @($wingetShowJson))
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('v', [ConsoleKey]::V, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager winget -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: <press V to load>' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: retrieving description...' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: Distributed version control system' } -Times 1
            @($script:Invocations | Where-Object { $_.Key -eq 'winget show --id Git.Git --exact --accept-source-agreements --output json' }).Count | Should -Be 1
        }

        It 'defaults source filter to winget for the winget picker when multiple sources exist' {
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.45.1'
                                Source = 'winget'
                            }
                            @{
                                PackageName = 'App Installer'
                                PackageIdentifier = 'Microsoft.AppInstaller'
                                Version = '1.24.12371.0'
                                Source = 'msstore'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = (& $script:NewTestCommandResponse -Output @($wingetListJson))
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = @(Show-InstalledPlatformPackage -PackageManager winget -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'S: \[winget\]' } -Times 1
        }

        It 'keeps picker table rows within the current console width' {
            $wingetListJson = @{
                Sources = @(
                    @{
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
                'winget list --accept-source-agreements --output json' = (& $script:NewTestCommandResponse -Output @($wingetListJson))
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $null = Show-InstalledPlatformPackage -PackageManager winget -CommandRunner $runner -KeyReader $keyReader

            $tableLines = @(
                $script:HostOutput |
                ForEach-Object { "$_" } |
                Where-Object {
                    $_ -match '^\s+Name\s+' -or
                    $_ -match '^>\s+'
                }
            )

            $tableLines.Count | Should -BeGreaterThan 1
            ($tableLines | Where-Object { $_ -match '^\s+Name\s+' } | Select-Object -First 1) | Should -Match '\bVer\b'
            ($tableLines | Where-Object { $_ -match '^\s+Name\s+' } | Select-Object -First 1) | Should -Match '\bTyp\b'
            ($tableLines | Where-Object { $_ -match '^\s+Name\s+' } | Select-Object -First 1) | Should -Match '\bSrc\b'
            ($tableLines | Where-Object { $_ -match '^>\s+' } | Select-Object -First 1) | Should -Match 'homebrew/core'
            (($tableLines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum) | Should -BeLessOrEqual (Get-TestPickerLineLimit)
        }

        It 'shows both dependency directions from the picker with D' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
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
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'DependsOn' } -Times 1
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'RequiredBy' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Show-InstalledPlatformPackage Dependencies - Homebrew' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Resolving dependencies...' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Dependencies [DependsOn + RequiredBy]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Dependencies [DependsOn]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Dependencies [RequiredBy]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Press B/Backspace/Delete/LeftArrow to return to the package list.' } -Times 1
        }

        It 'returns from dependency view to the package list on <Name> when manager navigation is enabled' -TestCases @(
            @{ Name = 'Backspace'; Key = [ConsoleKey]::Backspace; Char = [Char]8 }
            @{ Name = 'Delete'; Key = [ConsoleKey]::Delete; Char = [Char]0 }
        ) {
            param($Name, $Key, $Char)

            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
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

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -ReturnToPlatformPackageManagerOnBackKey)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: D deps  V details  E export  R remove  U upgrade  F: [all]' } -Times 2
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Show-InstalledPlatformPackage Dependencies - Homebrew' } -Times 2
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Press B/Backspace/Delete/LeftArrow to return to the package list.' } -Times 2
        }

        It 'invokes Remove-PlatformPackage from the picker when R is confirmed' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            Mock -CommandName Remove-PlatformPackage -MockWith {
                [PSCustomObject]@{
                    Removed = 1
                    Failed = 0
                    Skipped = 0
                }
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('r', [ConsoleKey]::R, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Remove-PlatformPackage -ParameterFilter {
                $PackageManager -eq 'brew' -and
                $All -and
                @($IncludePackage).Count -eq 1 -and
                @($IncludePackage)[0] -eq 'git'
            } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Status: Removed: 1, Failed: 0, Skipped: 0' } -Times 1
        }

        It 'shows winget remediation text after a browser-launched remove failure' {
            $wingetListJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Pandoc'
                                PackageIdentifier = 'JohnMacFarlane.Pandoc'
                                Version = '3.9.0.2'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $removeFailureMessage = 'winget uninstall --id JohnMacFarlane.Pandoc --exact --source winget --accept-source-agreements failed. Remediation: close running Pandoc processes and retry the uninstall.'
            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = (& $script:NewTestCommandResponse -Output @($wingetListJson))
                'winget uninstall --id JohnMacFarlane.Pandoc --exact --source winget --accept-source-agreements' = (& $script:NewTestCommandResponse -ExitCode 1603 -Output @($removeFailureMessage))
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('r', [ConsoleKey]::R, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager winget -CommandRunner $runner -KeyReader $keyReader -ReturnToPlatformPackageManagerOnBackKey -WarningAction SilentlyContinue)

            $result.Count | Should -Be 0
            $visibleOutput = ($script:HostOutput | ForEach-Object { "$_" }) -join "`n"
            $visibleOutput | Should -Match 'Status: Removed: 0, Failed: 1, Skipped: 0'
            $visibleOutput | Should -Match 'winget uninstall --id JohnMacFarlane\.Pandoc --exact --source winget --accept-source-agreements'
            $visibleOutput | Should -Match 'Remediation: close running Pandoc processes and retry the uninstall'
        }

        It 'invokes Upgrade-PlatformPackage from the picker when U is confirmed' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            Mock -CommandName Upgrade-PlatformPackage -MockWith {
                [PSCustomObject]@{
                    Upgraded = 1
                    Failed = 0
                    Skipped = 0
                }
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('u', [ConsoleKey]::U, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Upgrade-PlatformPackage -ParameterFilter {
                $PackageManager -eq 'brew' -and
                $All -and
                $SkipRefresh -and
                @($IncludePackage).Count -eq 1 -and
                @($IncludePackage)[0] -eq 'git'
            } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Status: Upgraded: 1, Failed: 0, Skipped: 0' } -Times 1
        }

        It 'shows winget remediation text after a browser-launched upgrade failure' {
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                PackageName = 'Pandoc 3.9.0.2'
                                PackageIdentifier = 'JohnMacFarlane.Pandoc'
                                Version = '3.9.0.2'
                                Source = 'winget'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $wingetUpgradeJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Pandoc 3.9.0.2'
                                PackageIdentifier = 'JohnMacFarlane.Pandoc'
                                Version = '3.9.0.2'
                                Available = '3.10'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = (& $script:NewTestCommandResponse -Output @($wingetListJson))
                'winget upgrade --accept-source-agreements --output json' = (& $script:NewTestCommandResponse -Output @($wingetUpgradeJson))
                'winget upgrade --id JohnMacFarlane.Pandoc --exact --source winget --accept-package-agreements --accept-source-agreements' = (& $script:NewTestCommandResponse -ExitCode -1978335184 -Output @())
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('u', [ConsoleKey]::U, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager winget -CommandRunner $runner -KeyReader $keyReader -ReturnToPlatformPackageManagerOnBackKey -WarningAction SilentlyContinue)

            $result.Count | Should -Be 0
            $visibleOutput = ($script:HostOutput | ForEach-Object { "$_" }) -join "`n"
            $visibleOutput | Should -Match 'Status: Upgraded: 0, Failed: 1, Skipped: 0'
            $visibleOutput | Should -Match 'APPINSTALLER_CLI_ERROR_EXEC_UNINSTALL_COMMAND_FAILED'
            $visibleOutput | Should -Match 'Running uninstall command failed'
            $visibleOutput | Should -Match 'winget uninstall --id JohnMacFarlane\.Pandoc --exact --source winget'
            $visibleOutput | Should -Match 'winget install --id JohnMacFarlane\.Pandoc --exact --source winget'
        }

        It 'exports visible packages to JSON from the picker when E is used' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0', 'curl 8.7.1'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $exportPath = Join-Path -Path $TestDrive -ChildPath 'installed-packages.json'
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            $keys.Enqueue([System.ConsoleKeyInfo]::new('e', [ConsoleKey]::E, $false, $false, $false))
            foreach ($pathChar in $exportPath.ToCharArray())
            {
                $keys.Enqueue([System.ConsoleKeyInfo]::new($pathChar, [ConsoleKey]::A, $false, $false, $false))
            }
            $keys.Enqueue([System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false))
            $keys.Enqueue([System.ConsoleKeyInfo]::new('n', [ConsoleKey]::N, $false, $false, $false))
            $keys.Enqueue([System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true))
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Test-Path -LiteralPath $exportPath | Should -BeTrue
            $exportedPackages = Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json
            $exportedPackages.Count | Should -Be 2
            ($exportedPackages | Where-Object { $_.Name -eq 'git' }).InstalledVersion | Should -Be '2.44.0'
            ($exportedPackages | Where-Object { $_.Name -eq 'curl' }).PackageManager | Should -Be 'brew'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like 'Status: Exported 2 package(s) to *installed-packages.json (JSON)' } -Times 1
        }

        It 'exports selected packages to CSV with dependencies from the picker' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0', 'curl 8.7.1'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
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
                    return @([PSCustomObject]@{
                            Direction = $Direction
                            Relationship = "$($Package[0].Name) -> openssl"
                            RelatedPackage = 'openssl'
                            DependencyType = 'Dependency'
                            Installed = $true
                            Notes = ''
                        })
                }

                return @([PSCustomObject]@{
                        Direction = $Direction
                        Relationship = "git-extras -> $($Package[0].Name)"
                        RelatedPackage = 'git-extras'
                        DependencyType = 'Dependent'
                        Installed = $false
                        Notes = ''
                    })
            }

            $exportPath = Join-Path -Path $TestDrive -ChildPath 'selected-packages.csv'
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            $keys.Enqueue([System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false))
            $keys.Enqueue([System.ConsoleKeyInfo]::new('e', [ConsoleKey]::E, $false, $false, $false))
            foreach ($pathChar in $exportPath.ToCharArray())
            {
                $keys.Enqueue([System.ConsoleKeyInfo]::new($pathChar, [ConsoleKey]::A, $false, $false, $false))
            }
            $keys.Enqueue([System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false))
            $keys.Enqueue([System.ConsoleKeyInfo]::new('b', [ConsoleKey]::B, $false, $false, $false))
            $keys.Enqueue([System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true))
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PassThru)

            $result.Count | Should -Be 0
            Test-Path -LiteralPath $exportPath | Should -BeTrue
            $exportedPackages = @(Import-Csv -LiteralPath $exportPath)
            $exportedPackages.Count | Should -Be 1
            $exportedPackages[0].Name | Should -Be 'curl'
            $exportedPackages[0].DependsOn | Should -Be 'openssl'
            $exportedPackages[0].RequiredBy | Should -Be 'git-extras'
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'DependsOn' } -Times 1
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'RequiredBy' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like 'Status: Exported 1 package(s) with dependencies and required-by relationships to *selected-packages.csv (CSV)' } -Times 1
        }

        It 'exports direct dependencies without resolving required-by relationships' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            Mock -CommandName Get-PlatformPackageDependency -MockWith {
                param(
                    [Object[]]$Package,
                    [String]$Direction,
                    [String]$PackageManager,
                    [ScriptBlock]$CommandRunner
                )

                return @([PSCustomObject]@{
                        Direction = $Direction
                        Relationship = "$($Package[0].Name) -> openssl"
                        RelatedPackage = 'openssl'
                        DependencyType = 'Dependency'
                        Installed = $true
                        Notes = ''
                    })
            }

            $exportPath = Join-Path -Path $TestDrive -ChildPath 'direct-dependencies.csv'
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            $keys.Enqueue([System.ConsoleKeyInfo]::new('e', [ConsoleKey]::E, $false, $false, $false))
            foreach ($pathChar in $exportPath.ToCharArray())
            {
                $keys.Enqueue([System.ConsoleKeyInfo]::new($pathChar, [ConsoleKey]::A, $false, $false, $false))
            }
            $keys.Enqueue([System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false))
            $keys.Enqueue([System.ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            $keys.Enqueue([System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true))
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            $exportedPackages = @(Import-Csv -LiteralPath $exportPath)
            $exportedPackages[0].DependsOn | Should -Be 'openssl'
            $exportedPackages[0].RequiredBy | Should -Be ''
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'DependsOn' } -Times 1
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'RequiredBy' } -Times 0
        }

        It 'filters picker results by package name when F is pressed' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0', 'curl 8.7.1'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('f', [ConsoleKey]::F, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('g', [ConsoleKey]::G, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PassThru)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Current filter: g' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'F: \[g\]' } -Times 1
        }

        It 'treats lowercase q as filter text instead of cancel' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0', 'jq 1.7.1'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('f', [ConsoleKey]::F, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PassThru)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'jq'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Current filter: q' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'F: \[q\]' } -Times 1
        }
    }
}
