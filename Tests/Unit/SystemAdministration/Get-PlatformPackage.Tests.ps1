#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Get-PlatformPackage.ps1"
    . "$PSScriptRoot/PlatformPackageTestHelpers.ps1"
}

Describe 'Get-PlatformPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
    }

    Context 'Homebrew package discovery' {
        It 'returns formula and cask records from list output' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            }

            $result = @(Get-PlatformPackage -PackageManager brew -CommandRunner $runner)

            $result.Count | Should-Be 2

            $formula = $result | Where-Object { $_.Name -eq 'git' }
            $formula.PackageManager | Should-Be 'brew'
            $formula.Type | Should-Be 'Formula'
            $formula.InstalledVersion | Should-Be '2.44.0'
            $formula.Publisher | Should-Be 'Homebrew'
            $formula.PSObject.Properties.Name | Should-NotContainCollection 'RemoveArguments'

            $cask = $result | Where-Object { $_.Name -eq 'visual-studio-code' }
            $cask.Type | Should-Be 'Cask'
            $cask.Source | Should-Be 'homebrew/cask'
        }

        It 'selects requested formulae and warns that casks are excluded' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0', 'curl 8.7.1')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
                'brew list --installed-on-request' = Get-TestCommandResponse -Output @('curl')
            }

            $result = @(Get-PlatformPackage -PackageManager brew -ExplicitOnly -CommandRunner $runner -WarningAction SilentlyContinue)

            $result.Count | Should-Be 1
            $result[0].Name | Should-Be 'curl'
            $result[0].Type | Should-Be 'Formula'
        }
    }

    Context 'Winget package discovery' {
        It 'returns installed packages from JSON output' {
            $wingetJson = @{
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

            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetJson)
            }

            $result = @(Get-PlatformPackage -PackageManager winget -CommandRunner $runner)

            $result.Count | Should-Be 1
            $result[0].Name | Should-Be 'Git'
            $result[0].Id | Should-Be 'Git.Git'
            $result[0].InstalledVersion | Should-Be '2.45.1'
            $result[0].Source | Should-Be 'winget'
            $result[0].Publisher | Should-Be 'winget'
        }
    }

    Context 'Linux package discovery' {
        It 'parses apt installed package output and keeps automatic state in notes' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt list --installed' = Get-TestCommandResponse -Output @(
                    'Listing... Done'
                    'openssl/jammy-updates,now 3.0.2-0ubuntu1.15 arm64 [installed,automatic]'
                )
            }

            $result = @(Get-PlatformPackage -PackageManager apt -CommandRunner $runner)

            $result.Count | Should-Be 1
            $result[0].Name | Should-Be 'openssl'
            $result[0].Type | Should-Be 'arm64'
            $result[0].InstalledVersion | Should-Be '3.0.2-0ubuntu1.15'
            $result[0].Notes | Should-Be 'Automatic'
        }

        It 'parses apk output and keeps hyphenated package names' {
            $runner = & $script:NewPackageCommandRunner @{
                'apk info -v' = Get-TestCommandResponse -Output @(
                    'busybox-1.36.1-r19'
                    'py3-requests-2.31.0-r0'
                )
            }

            $result = @(Get-PlatformPackage -PackageManager apk -CommandRunner $runner)

            $result.Count | Should-Be 2

            $busybox = $result | Where-Object { $_.Name -eq 'busybox' }
            $busybox.InstalledVersion | Should-Be '1.36.1-r19'

            $requests = $result | Where-Object { $_.Name -eq 'py3-requests' }
            $requests.InstalledVersion | Should-Be '2.31.0-r0'
        }

        It 'selects manually installed apt packages' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt list --installed' = Get-TestCommandResponse -Output @(
                    'Listing... Done'
                    'curl/jammy,now 7.81.0-1 arm64 [installed]'
                    'libcurl4/jammy,now 7.81.0-1 arm64 [installed,automatic]'
                )
            }

            $result = @(Get-PlatformPackage -PackageManager apt -ExplicitOnly -CommandRunner $runner)

            $result.Count | Should-Be 1
            $result[0].Name | Should-Be 'curl'
        }

        It 'selects installed apk packages matching world constraints and preserves those constraints' {
            Mock -CommandName Get-Content -MockWith {
                @('busybox', 'py3-requests=2.31.0-r0', 'cmd:unmatched')
            } -ParameterFilter { $LiteralPath -eq '/etc/apk/world' }
            $runner = & $script:NewPackageCommandRunner @{
                'apk info -v' = Get-TestCommandResponse -Output @(
                    'busybox-1.36.1-r19'
                    'py3-requests-2.31.0-r0'
                    'curl-8.5.0-r0'
                )
            }

            $result = @(Get-PlatformPackage -PackageManager apk -ExplicitOnly -CommandRunner $runner)

            $result.Count | Should-Be 2
            ($result | Where-Object { $_.Name -eq 'busybox' }).RequestedConstraint | Should-Be 'busybox'
            ($result | Where-Object { $_.Name -eq 'py3-requests' }).RequestedConstraint | Should-Be 'py3-requests=2.31.0-r0'
            $result.Name | Should-NotContainCollection 'curl'
        }
    }

    Context 'Explicit-only selection' {
        It 'rejects explicit-only selection for winget' {
            { Get-PlatformPackage -PackageManager winget -ExplicitOnly -CommandRunner { } } |
            Should-Throw -ExceptionMessage "*Explicit-only package selection is not supported by package manager 'winget'*"
        }
    }

    Context 'Filtering' {
        It 'filters by include and exclude patterns against name or id' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0', 'gh 2.51.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            }

            $result = @(Get-PlatformPackage -PackageManager brew -Name 'g*' -ExcludePackage 'gh' -CommandRunner $runner)

            $result.Count | Should-Be 1
            $result[0].Name | Should-Be 'git'
        }

        It 'returns empty when brew list output is empty' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @()
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $result = @(Get-PlatformPackage -PackageManager brew -CommandRunner $runner)

            $result.Count | Should-Be 0
        }

        It 'excludes winget packages matched by wildcard ExcludePackage pattern' {
            $wingetJson = @{
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
                                PackageName = 'GitHub Desktop'
                                PackageIdentifier = 'GitHub.GitHubDesktop'
                                Version = '3.3.6'
                                Source = 'winget'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetJson)
            }

            $result = @(Get-PlatformPackage -PackageManager winget -ExcludePackage '*Desktop*' -SkipDescriptionEnrichment -CommandRunner $runner)

            $result.Count | Should-Be 1
            $result[0].Name | Should-Be 'Git'
        }

        It 'falls back to winget table output when the JSON command fails' {
            $tableOutput = @(
                'Name                                Id                  Version     Available Source'
                '-----------------------------------------------------------------------------------------------------------'
                'Git                                 Git.Git             2.45.1                winget'
            )

            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @()
                'winget list --accept-source-agreements' = Get-TestCommandResponse -Output $tableOutput
            }

            $result = @(Get-PlatformPackage -PackageManager winget -SkipDescriptionEnrichment -CommandRunner $runner)

            $result.Count | Should-Be 1
            $result[0].Name | Should-Be 'Git'
        }
    }
}
