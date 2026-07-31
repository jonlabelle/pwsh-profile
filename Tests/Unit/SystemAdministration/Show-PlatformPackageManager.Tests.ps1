#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Show-PlatformPackageManager.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Export-InstalledPlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Show-InstalledPlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Install-PlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Upgrade-PlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Remove-PlatformPackage.ps1"
    . "$PSScriptRoot/PlatformPackageTestHelpers.ps1"
}

Describe 'Show-PlatformPackageManager' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Clear-Host -MockWith {}
    }

    It 'renders the unified menu and exits when quit is selected' {
        $promptReader = & $script:NewPromptReader @('q')

        $result = @(Show-PlatformPackageManager -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Platform Package Manager' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like "Manager: Auto $([Char]0x2192) *" } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*Installed packages*' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*Export installed*' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*Direct install*' } -Times 0 -Exactly
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*Dependencies*' } -Times 1
        $escapeCharacter = [String][Char]27
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[38;5;37m" } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[38;5;244m" } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[0m" } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[33m" } -Times 0 -Exactly
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[91m" } -Times 0 -Exactly
        Should-Invoke -CommandName Write-Host -ParameterFilter {
            $Separator -eq '' -and
            $Object.Count -eq 3 -and
            $Object[0] -eq "$escapeCharacter[38;5;37m" -and
            $Object[1] -eq 'Platform Package Manager' -and
            $Object[2] -eq "$escapeCharacter[0m"
        } -Times 1
    }

    It 'selects the upgrade workflow by default' {
        Mock -CommandName Upgrade-PlatformPackage -MockWith {}
        Mock -CommandName Install-PlatformPackage -MockWith {}
        Mock -CommandName Show-InstalledPlatformPackage -MockWith {}
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager brew -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Upgrade-PlatformPackage -Times 1
        Should-Invoke -CommandName Install-PlatformPackage -Times 0 -Exactly
        Should-Invoke -CommandName Show-InstalledPlatformPackage -Times 0 -Exactly
    }

    It 'exposes ShouldProcess safety switches for delegated operations' {
        $command = Get-Command -Name Show-PlatformPackageManager

        $command.Parameters.Keys | Should-ContainCollection 'WhatIf'
        $command.Parameters.Keys | Should-ContainCollection 'Confirm'
    }

    It 'rejects winget-only manager options for other package managers' {
        $promptReader = & $script:NewPromptReader @('q')

        { Show-PlatformPackageManager -PackageManager brew -Interactive -PromptReader $promptReader } |
            Should-Throw -ExceptionMessage "*Parameter -Interactive*package manager 'brew'*only supported by winget*"

        { Show-PlatformPackageManager -PackageManager apt -UninstallPrevious -PromptReader $promptReader } |
            Should-Throw -ExceptionMessage "*Parameter -UninstallPrevious*package manager 'apt'*only supported by winget*"
    }

    It 'rejects NoSudo for managers that do not use sudo' {
        $promptReader = & $script:NewPromptReader @('q')

        { Show-PlatformPackageManager -PackageManager winget -NoSudo -PromptReader $promptReader } |
            Should-Throw -ExceptionMessage "*Parameter -NoSudo*package manager 'winget'*only supported by apt and apk*"
    }

    It 'routes installed package browsing through Show-InstalledPlatformPackage without extra prompts' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0', 'gh 2.50.0')
            'brew list --cask --versions' = Get-TestCommandResponse -Output @()
        }
        Mock -CommandName Show-InstalledPlatformPackage -MockWith {
            @(
                [PSCustomObject]@{
                    Name = 'git'
                    Id = 'git'
                    PackageManager = 'brew'
                    PackageManagerDisplayName = 'Homebrew'
                    InstalledVersion = '2.44.0'
                    Source = 'homebrew/formula'
                }
                [PSCustomObject]@{
                    Name = 'gh'
                    Id = 'gh'
                    PackageManager = 'brew'
                    PackageManagerDisplayName = 'Homebrew'
                    InstalledVersion = '2.50.0'
                    Source = 'homebrew/formula'
                }
            )
        }
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('3', [ConsoleKey]::D3, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Show-InstalledPlatformPackage -ParameterFilter {
            $PackageManager -eq 'brew' -and
            $null -ne $CommandRunner -and
            $null -ne $KeyReader -and
            $ReturnToPlatformPackageManagerOnBackKey
        } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Installed Packages' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*git*' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*gh*' } -Times 1
    }

    It 'returns from the installed package browser to the manager menu on Backspace' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
            'brew list --cask --versions' = Get-TestCommandResponse -Output @()
        }
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('3', [ConsoleKey]::D3, $false, $false, $false)
            [System.ConsoleKeyInfo]::new([Char]8, [ConsoleKey]::Backspace, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Platform Package Manager' } -Times 2
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Show-InstalledPlatformPackage - Homebrew' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Backspace/Delete: manager menu' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Installed Packages' } -Times 0 -Exactly
    }

    It 'does not expose numbers outside 1-6 as valid actions' {
        $promptReader = & $script:NewPromptReader @('7', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*Direct install*' } -Times 0 -Exactly
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Choose 1-6 or Q.' } -Times 1
    }

    It 'supports arrow key navigation in the manager menu' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 1
                Selected = 1
                NotSelected = 0
                Installed = 1
                Skipped = 0
                Failed = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('git')
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new([Char]0, [ConsoleKey]::DownArrow, $false, $false, $false)
            [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager apt -NoSudo -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Install-PlatformPackage -ParameterFilter {
            $Query -eq 'git' -and
            $PackageManager -eq 'apt' -and
            $NoSudo -and
            $ReturnToPlatformPackageManagerOnBackKey
        } -Times 1
    }

    It 'shows keyboard help from the manager menu' {
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('?', [ConsoleKey]::Oem2, $true, $false, $false)
            [System.ConsoleKeyInfo]::new('x', [ConsoleKey]::X, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Platform Package Manager Help' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'B: ' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'browse installed packages' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'E: ' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'export installed packages' } -Times 1
    }

    It 'routes installed package export through Show-InstalledPlatformPackage from the manager shortcut' {
        Mock -CommandName Show-InstalledPlatformPackage -MockWith {
            [PSCustomObject]@{
                PSTypeName = 'InstalledPlatformPackage.ExportResult'
                Path = $ExportPath
                Format = 'JSON'
                Count = 2
                DependencyMode = $ExportDependencyMode
                IncludeDependencies = $false
            }
        }

        $exportPath = Join-Path -Path $TestDrive -ChildPath 'installed-packages.json'
        $promptReader = & $script:NewPromptReader @($exportPath, '')
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('e', [ConsoleKey]::E, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner { } -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Show-InstalledPlatformPackage -ParameterFilter {
            $PackageManager -eq 'brew' -and
            $ExportPath -eq $exportPath -and
            $ExportFormat -eq 'Json' -and
            $ExportDependencyMode -eq 'None' -and
            $ShowExportProgress -and
            $null -ne $ExportCancelRequested -and
            $NonInteractive
        } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Export Installed Packages' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Export completed.' } -Times 1
    }

    It 'shows keyboard help from a manager result screen' {
        Mock -CommandName Upgrade-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'brew'
                PackageManagerDisplayName = 'Homebrew'
                TotalAvailable = 1
                Selected = 1
                NotSelected = 0
                Upgraded = 1
                Failed = 0
                Skipped = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('1', [ConsoleKey]::D1, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('?', [ConsoleKey]::Oem2, $true, $false, $false)
            [System.ConsoleKeyInfo]::new('x', [ConsoleKey]::X, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager brew -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Platform Package Manager Help' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Any key or Enter: ' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'return to the manager menu' } -Times 1
    }

    It 'routes search installs through Install-PlatformPackage with NoSudo forwarded' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 1
                Selected = 1
                NotSelected = 0
                Installed = 1
                Skipped = 0
                Failed = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'git', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -NoSudo -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Install-PlatformPackage -ParameterFilter {
            $Query -eq 'git' -and
            $PackageManager -eq 'apt' -and
            $NoSudo -and
            $Top -eq 50 -and
            $ReturnToPlatformPackageManagerOnBackKey
        } -Times 1
    }

    It 'forwards FilterSource to search and upgrade pickers' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'winget'
                PackageManagerDisplayName = 'Windows Package Manager'
                TotalMatched = 1
                Selected = 0
                NotSelected = 1
                Installed = 0
                Skipped = 0
                Failed = 0
                Results = @()
            }
        }
        Mock -CommandName Upgrade-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'winget'
                PackageManagerDisplayName = 'Windows Package Manager'
                TotalAvailable = 1
                Selected = 0
                NotSelected = 1
                Upgraded = 0
                Failed = 0
                Skipped = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'git', '1', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -FilterSource msstore -SkipRefresh -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Install-PlatformPackage -ParameterFilter {
            $Query -eq 'git' -and
            $PackageManager -eq 'winget' -and
            $FilterSource -eq 'msstore' -and
            $ReturnToPlatformPackageManagerOnBackKey
        } -Times 1
        Should-Invoke -CommandName Upgrade-PlatformPackage -ParameterFilter {
            $PackageManager -eq 'winget' -and
            $FilterSource -eq 'msstore' -and
            $ReturnToPlatformPackageManagerOnBackKey
        } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*FilterSource=msstore*' } -Times 3
    }

    It 'forwards interactive mode to winget install and upgrade workflows' {
        Mock -CommandName Install-PlatformPackage -MockWith {}
        Mock -CommandName Upgrade-PlatformPackage -MockWith {}
        $promptReader = & $script:NewPromptReader @('2', 'git', '1', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -Interactive -SkipRefresh -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Install-PlatformPackage -ParameterFilter {
            $PackageManager -eq 'winget' -and $Interactive
        } -Times 1
        Should-Invoke -CommandName Upgrade-PlatformPackage -ParameterFilter {
            $PackageManager -eq 'winget' -and $Interactive
        } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*Interactive*' } -Times 3
    }

    It 'routes upgrade options and forwards winget uninstall-previous' {
        $runner = & $script:NewPackageCommandRunner @{
            'winget upgrade --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
            'winget upgrade --accept-source-agreements' = Get-TestCommandResponse -Output @(
                'Name               Id                          Version Available Source'
                '-----------------------------------------------------------------------'
                'Git                Git.Git                     2.43.0  2.44.0    winget'
            )
            'winget upgrade --id Git.Git --exact --source winget --accept-package-agreements --accept-source-agreements --uninstall-previous' = Get-TestCommandResponse -Output @('winget upgrade output')
        }
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('1', [ConsoleKey]::D1, $false, $false, $false)
            [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
            [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager winget -SkipRefresh -UninstallPrevious -CommandRunner $runner -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should-Be 0
        ($script:Invocations | Where-Object { $_.Key -eq 'winget upgrade --id Git.Git --exact --source winget --accept-package-agreements --accept-source-agreements --uninstall-previous' }).StreamOutput | Should-BeTruthy
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'winget upgrade output' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match 'Upgraded' } -Times 1
    }

    It 'routes remove options and forwards purge behavior' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew list --formula --versions' = Get-TestCommandResponse -Output @()
            'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            'brew uses --installed visual-studio-code' = Get-TestCommandResponse -Output @()
            'brew uninstall --cask --zap visual-studio-code' = Get-TestCommandResponse -Output @('brew zap output')
        }
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('4', [ConsoleKey]::D4, $false, $false, $false)
            [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(
            & {
                $ConfirmPreference = 'None'
                Show-PlatformPackageManager -PackageManager brew -Purge -CommandRunner $runner -PromptReader $promptReader -KeyReader $keyReader
            }
        )

        $result.Count | Should-Be 0
        ($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall --cask --zap visual-studio-code' }).StreamOutput | Should-BeTruthy
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'brew zap output' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match 'Removed' } -Times 1
    }

    It 'returns from the removal picker to the manager menu on Delete' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
            'brew list --cask --versions' = Get-TestCommandResponse -Output @()
        }
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('4', [ConsoleKey]::D4, $false, $false, $false)
            [System.ConsoleKeyInfo]::new([Char]0, [ConsoleKey]::Delete, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(
            & {
                $ConfirmPreference = 'None'
                Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader -KeyReader $keyReader
            }
        )

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Platform Package Manager' } -Times 2
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Remove-PlatformPackage - Homebrew' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Backspace/Delete: manager menu' } -Times 1
        @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).Count | Should-Be 0
    }

    It 'shows an accent status indicator after a successful upgrade' {
        $runner = & $script:NewPackageCommandRunner @{
            'winget upgrade --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
            'winget upgrade --accept-source-agreements' = Get-TestCommandResponse -Output @(
                'Name               Id                          Version Available Source'
                '-----------------------------------------------------------------------'
                'Git                Git.Git                     2.43.0  2.44.0    winget'
            )
            'winget upgrade --id Git.Git --exact --source winget --accept-package-agreements --accept-source-agreements' = Get-TestCommandResponse -Output @('winget upgrade output')
        }
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('1', [ConsoleKey]::D1, $false, $false, $false)
            [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
            [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager winget -SkipRefresh -CommandRunner $runner -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match 'Upgraded: 1' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match 'Failed: 0' } -Times 1
        $escapeCharacter = [String][Char]27
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[38;5;37m" } -Times 1
    }

    It 'shows an accent status indicator after a successful install' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 1
                Selected = 1
                NotSelected = 0
                Installed = 1
                Skipped = 0
                Failed = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'git', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -NoSudo -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match 'Installed: 1' } -Times 1
        $escapeCharacter = [String][Char]27
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[38;5;37m" } -Times 1
    }

    It 'shows captured informational output on the manager result screen' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'brew'
                PackageManagerDisplayName = 'Homebrew'
                TotalMatched = 1
                Selected = 1
                NotSelected = 0
                Installed = 1
                Skipped = 0
                Failed = 0
                InformationalResults = @(
                    [PSCustomObject]@{
                        Name = 'python'
                        Id = 'python'
                        Status = 'Installed'
                        Lines = @(
                            '==> Caveats'
                            'Add /opt/homebrew/opt/python/libexec/bin to PATH'
                        )
                    }
                )
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'python', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager brew -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Additional output' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'python' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq '  ==> Caveats' } -Times 1
    }

    It 'keeps detail rows within the separator width while retaining the full additional output' {
        $script:FullFailureMessage = 'winget upgrade --id Microsoft.Edge --exact --source winget --accept-package-agreements --accept-source-agreements failed with exit code -1978335090 (0x8A15008E). Run winget error -1978335090 for the WinGet error name. Full diagnostic sentinel.'
        $script:RenderedOutput = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith { [void]$script:RenderedOutput.Add($Object) }

        Mock -CommandName Upgrade-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'winget'
                PackageManagerDisplayName = 'WinGet'
                TotalAvailable = 1
                Selected = 1
                NotSelected = 0
                Upgraded = 0
                Skipped = 0
                Failed = 1
                InformationalResults = @(
                    [PSCustomObject]@{
                        Name = 'Microsoft Edge'
                        Id = 'Microsoft.Edge'
                        Status = 'Failed'
                        Lines = @($script:FullFailureMessage)
                    }
                )
                Results = @(
                    [PSCustomObject]@{
                        Name = 'Microsoft Edge'
                        Id = 'Microsoft.Edge'
                        InstalledVersion = '150.0.4078.48'
                        LatestVersion = '150.0.4078.65'
                        Status = 'Failed'
                        ExitCode = -1978335090
                        Message = $script:FullFailureMessage
                        CapturedOutput = @()
                        InformationalOutput = @($script:FullFailureMessage)
                    }
                )
            }
        }
        $promptReader = & $script:NewPromptReader @('1', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -SkipRefresh -PromptReader $promptReader)

        $result.Count | Should-Be 0
        $renderedText = @(
            $script:RenderedOutput |
            ForEach-Object { ([String]::Join('', [String[]]$_)) -replace "$([Char]27)\[[0-9;]*m", '' }
        )
        $detailSeparator = @($renderedText | Where-Object { $_ -match '^-{40,}$' })[0]
        $detailTable = @($renderedText | Where-Object { $_ -match 'InstalledVersion' })[0]
        $detailSeparator | Should -Not -BeNullOrEmpty
        $detailTable | Should -Not -BeNullOrEmpty
        @(
            "$detailTable" -split "`r?`n" |
            Where-Object { -not [String]::IsNullOrWhiteSpace($_) -and $_.Length -gt $detailSeparator.Length }
        ) | Should-BeCollection -Count 0
        $detailTable | Should-NotMatchString ([Regex]::Escape($script:FullFailureMessage))
        Should-Invoke -CommandName Write-Host -ParameterFilter {
            $Object -eq "  $script:FullFailureMessage"
        } -Times 1
    }

    It 'shows a red status indicator when an operation has failures' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 2
                Selected = 2
                NotSelected = 0
                Installed = 1
                Skipped = 0
                Failed = 1
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'git', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -NoSudo -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match 'Installed: 1' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match 'Failed: 1' } -Times 1
        $escapeCharacter = [String][Char]27
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[91m" } -Times 1
    }

    It 'shows a yellow status indicator when packages were skipped but none failed' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 3
                Selected = 3
                NotSelected = 0
                Installed = 2
                Skipped = 1
                Failed = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'git', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -NoSudo -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match 'Installed: 2' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match 'Skipped: 1' } -Times 1
        $escapeCharacter = [String][Char]27
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[33m" } -Times 1
    }

    It 'does not show a status indicator for dependency lookups' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew deps --direct git' = Get-TestCommandResponse -Output @('gettext')
        }
        $promptReader = & $script:NewPromptReader @('5', 'git', '1', 'n', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match 'Installed:|Upgraded:|Removed:' } -Times 0 -Exactly
    }

    It 'returns directly to the menu without a result screen when a search query is cancelled' {
        $promptReader = & $script:NewPromptReader @('2', '', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Search and Install Packages' } -Times 0 -Exactly
    }

    It 'returns directly to the menu without a result screen when no packages are selected in the picker' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 5
                Selected = 0
                NotSelected = 5
                Installed = 0
                Skipped = 0
                Failed = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'git', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Install-PlatformPackage -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Search and Install Packages' } -Times 0 -Exactly
    }

    It 'shows a notification in the menu when search returns no matches' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'winget'
                PackageManagerDisplayName = 'Windows Package Manager'
                TotalMatched = 0
                Selected = 0
                NotSelected = 0
                Installed = 0
                Skipped = 0
                Failed = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'codeql', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Install-PlatformPackage -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*No packages matched the requested search query*' } -Times 1
    }

    It 'shows a notification in the menu when winget search returns no registry matches' {
        $runner = & $script:NewPackageCommandRunner @{
            'winget search codeql --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
            'winget search codeql --accept-source-agreements' = Get-TestCommandResponse -ExitCode 1 -Output @('No package found matching input criteria.')
        }
        $promptReader = & $script:NewPromptReader @('2', 'codeql', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -CommandRunner $runner -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*No packages matched the requested search query*' } -Times 1
    }

    It 'shows a notification in the menu when no packages are available for upgrade' {
        Mock -CommandName Upgrade-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'brew'
                PackageManagerDisplayName = 'Homebrew'
                TotalAvailable = 0
                Selected = 0
                NotSelected = 0
                Upgraded = 0
                Failed = 0
                Skipped = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('1', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager brew -SkipRefresh -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Upgrade-PlatformPackage -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*No packages are currently available for upgrade*' } -Times 1
    }

    It 'shows a notification in the menu when no installed packages matched for removal' {
        Mock -CommandName Remove-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'brew'
                PackageManagerDisplayName = 'Homebrew'
                TotalMatched = 0
                Selected = 0
                NotSelected = 0
                Removed = 0
                Failed = 0
                Skipped = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('4', 'q')

        $result = @(
            & {
                $ConfirmPreference = 'None'
                Show-PlatformPackageManager -PackageManager brew -PromptReader $promptReader
            }
        )

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Remove-PlatformPackage -ParameterFilter {
            $PackageManager -eq 'brew' -and
            $ReturnToPlatformPackageManagerOnBackKey
        } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*No installed packages matched the requested filters*' } -Times 1
    }

    It 'does not show a notification when no packages are selected in the picker but packages are available' {
        Mock -CommandName Upgrade-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'brew'
                PackageManagerDisplayName = 'Homebrew'
                TotalAvailable = 3
                Selected = 0
                NotSelected = 3
                Upgraded = 0
                Failed = 0
                Skipped = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('1', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager brew -SkipRefresh -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*No packages*' } -Times 0 -Exactly
    }

    It 'shows dependency records from the manager' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew deps --direct git' = Get-TestCommandResponse -Output @('gettext')
        }
        $promptReader = & $script:NewPromptReader @('5', 'git', '1', 'n', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*Relationship*' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*git -> gettext*' } -Times 1
    }

    It 'explains that winget reverse dependency lookup is unavailable' {
        $promptReader = & $script:NewPromptReader @('5', 'Git.Git', '2', 'n', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*winget does not expose reverse dependency metadata*' } -Times 1
    }

    It 'rejects partial Both dependency lookup for winget' {
        $promptReader = & $script:NewPromptReader @('5', 'Git.Git', '3', 'n', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like "*Direction 'Both' is not supported by winget*Choose DependsOn*" } -Times 1
    }

    It 'keeps action results on a dedicated screen until the next action is chosen' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew deps --direct git' = Get-TestCommandResponse -Output @('gettext')
        }
        $promptReader = & $script:NewPromptReader @('5', 'git', '1', 'n', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader)

        $result.Count | Should-Be 0
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Platform Package Manager' } -Times 1
        Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Package Dependencies' } -Times 1
    }
}
