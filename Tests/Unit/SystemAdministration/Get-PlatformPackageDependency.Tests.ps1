#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Get-PlatformPackageDependency.ps1"

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

Describe 'Get-PlatformPackageDependency' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
    }

    Context 'Homebrew dependency discovery' {
        It 'returns direct dependencies from brew deps' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew deps --direct git' = Get-TestCommandResponse -Output @(
                    'Warning: `brew deps` is not the actual runtime dependencies because --direct was passed!'
                    'This means dependencies may differ from a formula''s declared dependencies.'
                    'Hide these hints with `HOMEBREW_NO_ENV_HINTS=1` (see `man brew`).'
                    'gettext'
                    'pcre2'
                )
            }

            $result = @(Get-PlatformPackageDependency -PackageManager brew -Package git -CommandRunner $runner)

            $result.Count | Should -Be 2
            $result[0].Package | Should -Be 'git'
            $result[0].Direction | Should -Be 'DependsOn'
            $result[0].RelatedPackage | Should -Be 'gettext'
            $result[0].Relationship | Should -Be 'git -> gettext'
            $result[0].DependencyType | Should -Be 'Dependency'
        }

        It 'returns installed dependents from brew uses' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew uses --installed openssl' = Get-TestCommandResponse -Output @('curl')
            }

            $result = @(Get-PlatformPackageDependency -PackageManager brew -Package openssl -Direction RequiredBy -InstalledOnly -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Package | Should -Be 'openssl'
            $result[0].Direction | Should -Be 'RequiredBy'
            $result[0].RelatedPackage | Should -Be 'curl'
            $result[0].Relationship | Should -Be 'curl -> openssl'
            $result[0].Installed | Should -BeTrue
        }

        It 'uses eval-all for broad dependent discovery' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew uses --eval-all jq' = Get-TestCommandResponse -Output @('gojq')
            }

            $result = @(Get-PlatformPackageDependency -PackageManager brew -Package jq -Direction RequiredBy -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Package | Should -Be 'jq'
            $result[0].Direction | Should -Be 'RequiredBy'
            $result[0].RelatedPackage | Should -Be 'gojq'
        }
    }

    Context 'APT dependency discovery' {
        It 'returns Depends and PreDepends entries from apt-cache depends' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt-cache depends curl' = Get-TestCommandResponse -Output @(
                    'curl'
                    '  Depends: libc6'
                    '  Depends: libcurl4'
                    '  PreDepends: dpkg'
                    '  Recommends: ca-certificates'
                )
            }

            $result = @(Get-PlatformPackageDependency -PackageManager apt -Package curl -CommandRunner $runner)

            $result.Count | Should -Be 3
            $result.RelatedPackage | Should -Contain 'libc6'
            $result.RelatedPackage | Should -Contain 'libcurl4'
            $result.RelatedPackage | Should -Contain 'dpkg'
            $result.RelatedPackage | Should -Not -Contain 'ca-certificates'
            ($result | Where-Object { $_.RelatedPackage -eq 'dpkg' }).DependencyType | Should -Be 'PreDepends'
        }

        It 'filters reverse dependency records to installed APT packages' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt-cache rdepends openssl' = Get-TestCommandResponse -Output @(
                    'openssl'
                    'Reverse Depends:'
                    '  curl'
                    '  git'
                )
                'apt list --installed' = Get-TestCommandResponse -Output @(
                    'Listing... Done'
                    'curl/jammy,now 8.5.0 amd64 [installed]'
                )
            }

            $result = @(Get-PlatformPackageDependency -PackageManager apt -Package openssl -Direction RequiredBy -InstalledOnly -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].RelatedPackage | Should -Be 'curl'
            $result[0].Installed | Should -BeTrue
        }
    }

    Context 'apk dependency discovery' {
        It 'returns dependency and reverse dependency records from apk info' {
            $runner = & $script:NewPackageCommandRunner @{
                'apk info --depends pipewire' = Get-TestCommandResponse -Output @(
                    'pipewire-1.0.6-r1 depends on:'
                    '/bin/sh'
                    'so:libpipewire-0.3.so.0'
                )
                'apk info --rdepends pipewire' = Get-TestCommandResponse -Output @(
                    'pipewire-1.0.6-r1 is required by:'
                    'pipewire-pulse-1.0.6-r1'
                )
            }

            $result = @(Get-PlatformPackageDependency -PackageManager apk -Package pipewire -Direction Both -CommandRunner $runner)

            $result.Count | Should -Be 3
            ($result | Where-Object { $_.Direction -eq 'DependsOn' }).RelatedPackage | Should -Contain '/bin/sh'
            ($result | Where-Object { $_.Direction -eq 'DependsOn' }).RelatedPackage | Should -Contain 'so:libpipewire-0.3.so.0'
            ($result | Where-Object { $_.Direction -eq 'RequiredBy' }).RelatedPackage | Should -Be 'pipewire-pulse'
        }
    }

    Context 'winget dependency discovery' {
        It 'parses installer dependencies from winget show output' {
            $runner = & $script:NewPackageCommandRunner @{
                'winget show Git.Git --accept-source-agreements' = Get-TestCommandResponse -Output @(
                    'Found Git [Git.Git]'
                    'Version: 2.45.1'
                    'Dependencies:'
                    '  Package Dependencies:'
                    '    Microsoft.VCRedist.2015+.x64'
                    'Installer:'
                    '  Installer Type: exe'
                )
            }

            $result = @(Get-PlatformPackageDependency -PackageManager winget -Package Git.Git -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Package | Should -Be 'Git.Git'
            $result[0].RelatedPackage | Should -Be 'Microsoft.VCRedist.2015+.x64'
            $result[0].DependencyType | Should -Be 'Package Dependencies'
        }

        It 'returns no reverse dependencies for winget' {
            $runner = & $script:NewPackageCommandRunner @{}

            $result = @(Get-PlatformPackageDependency -PackageManager winget -Package Git.Git -Direction RequiredBy -CommandRunner $runner)

            $result.Count | Should -Be 0
            $script:Invocations.Count | Should -Be 0
        }

        It 'filters winget installed dependencies by id instead of ambiguous display name' {
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                Name = 'Node.js'
                                PackageIdentifier = 'OpenJS.NodeJS.LTS'
                                Version = '24.15.0'
                                Source = 'winget'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget show Git.Git --accept-source-agreements' = Get-TestCommandResponse -Output @(
                    'Found Git [Git.Git]'
                    'Version: 2.45.1'
                    'Dependencies:'
                    '  Package Dependencies:'
                    '    Node.js'
                    '    OpenJS.NodeJS.LTS'
                    'Installer:'
                    '  Installer Type: exe'
                )
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
            }

            $result = @(Get-PlatformPackageDependency -PackageManager winget -Package Git.Git -InstalledOnly -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].RelatedPackage | Should -Be 'OpenJS.NodeJS.LTS'
        }
    }

    Context 'Pipeline input' {
        It 'uses package object id and type when records are piped in' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew deps --direct --formula git' = Get-TestCommandResponse -Output @('gettext')
            }

            $package = [PSCustomObject]@{
                Name = 'git'
                Id = 'git'
                Type = 'Formula'
            }

            $result = @($package | Get-PlatformPackageDependency -PackageManager brew -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Package | Should -Be 'git'
            $result[0].Id | Should -Be 'git'
            $result[0].RelatedPackage | Should -Be 'gettext'
        }
    }
}
