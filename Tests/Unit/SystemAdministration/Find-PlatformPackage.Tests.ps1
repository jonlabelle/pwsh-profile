#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Find-PlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Install-PlatformPackage.ps1"
    . "$PSScriptRoot/PlatformPackageTestHelpers.ps1"
}

Describe 'Find-PlatformPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        $script:HostOutput = New-Object 'System.Collections.Generic.List[Object]'
        $script:HostOutputRecords = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith {
            param(
                [Object]$Object,
                [ConsoleColor]$ForegroundColor
            )

            $script:HostOutput.Add($Object)
            $script:HostOutputRecords.Add([PSCustomObject]@{
                    Object = $Object
                    ForegroundColor = $ForegroundColor
                })
        }
        Mock -CommandName Clear-Host -MockWith {}
    }

    Context 'winget search' {
        It 'returns normalized results from JSON output' {
            $wingetJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.45.1'
                                CatalogName = 'winget'
                                Description = 'Distributed version control system'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget search git --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetJson)
            }

            $result = @(Find-PlatformPackage -PackageManager winget -NonInteractive -Query git -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'Git'
            $result[0].Id | Should -Be 'Git.Git'
            $result[0].Version | Should -Be '2.45.1'
            $result[0].Description | Should -Be 'Distributed version control system'
            $result[0].Publisher | Should -Be 'winget'
        }

        It 'marks search results as installed from winget list output' {
            $wingetSearchJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.45.1'
                                CatalogName = 'winget'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.44.0'
                                Source = 'winget'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget search git --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetSearchJson)
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
            }

            $result = @(Find-PlatformPackage -PackageManager winget -NonInteractive -Query git -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Installed | Should -BeTrue
        }

        It 'does not mark winget search results installed by display name when ids differ' {
            $wingetSearchJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                PackageName = 'Node.js'
                                PackageIdentifier = 'OpenJS.NodeJS'
                                Version = '25.9.0'
                                CatalogName = 'winget'
                            }
                            @{
                                PackageName = 'Node.js (LTS)'
                                PackageIdentifier = 'OpenJS.NodeJS.LTS'
                                Version = '24.15.0'
                                CatalogName = 'winget'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

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
                'winget search node --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetSearchJson)
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
            }

            $result = @(Find-PlatformPackage -PackageManager winget -NonInteractive -Query node -CommandRunner $runner)

            ($result | Where-Object { $_.Id -eq 'OpenJS.NodeJS' }).Installed | Should -BeFalse
            ($result | Where-Object { $_.Id -eq 'OpenJS.NodeJS.LTS' }).Installed | Should -BeTrue
        }

        It 'returns no results when winget reports no package found with progress output' {
            $progressLine = ('{0}{0}{1}{1} 7%' -f [Char]0x2588, [Char]0x2592)
            $runner = & $script:NewPackageCommandRunner @{
                'winget search codeql --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
                'winget search codeql --accept-source-agreements' = Get-TestCommandResponse -ExitCode 1 -Output @(
                    '   -     \     |     /'
                    $progressLine
                    'No package found matching input criteria.'
                )
            }

            $result = @(Find-PlatformPackage -PackageManager winget -NonInteractive -Query codeql -CommandRunner $runner)

            $result.Count | Should -Be 0
        }

        It 'strips winget progress output from search failure messages' {
            $progressLine = ('{0}{0}{1}{1} 7%' -f [Char]0x2588, [Char]0x2592)
            $runner = & $script:NewPackageCommandRunner @{
                'winget search git --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
                'winget search git --accept-source-agreements' = Get-TestCommandResponse -ExitCode 2 -Output @(
                    '   -     \     |     /'
                    $progressLine
                    'Failed when opening source(s); try source reset.'
                )
            }

            $thrown = $null
            try
            {
                $null = Find-PlatformPackage -PackageManager winget -NonInteractive -Query git -CommandRunner $runner
            }
            catch
            {
                $thrown = $_
            }

            ($null -eq $thrown) | Should -BeFalse
            $thrown.Exception.Message | Should -Be 'Failed to search winget packages: Failed when opening source(s); try source reset.'
            $thrown.Exception.Message | Should -Not -Match '\u2588'
            $thrown.Exception.Message | Should -Not -Match '\\\s+\|'
        }
    }

    Context 'Homebrew search' {
        It 'returns formula and cask results from separate searches' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @('git-credential-manager')
            }

            $result = @(Find-PlatformPackage -PackageManager brew -NonInteractive -Query git -CommandRunner $runner -Top 0)

            $result.Count | Should -Be 3
            ($result | Where-Object { $_.Name -eq 'git' }).Type | Should -Be 'Formula'
            ($result | Where-Object { $_.Name -eq 'git-credential-manager' }).Type | Should -Be 'Cask'
        }

        It 'marks formula search results as installed from Homebrew list output' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae jq' = Get-TestCommandResponse -Output @('gojq', 'jq', 'jq-lsp')
                'brew search --casks jq' = Get-TestCommandResponse -Output @('jquake')
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('jq 1.7.1')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $result = @(Find-PlatformPackage -PackageManager brew -NonInteractive -Query jq -CommandRunner $runner -Top 0)

            ($result | Where-Object { $_.Name -eq 'jq' }).Installed | Should -BeTrue
            ($result | Where-Object { $_.Name -eq 'gojq' }).Installed | Should -BeFalse
            ($result | Where-Object { $_.Name -eq 'jquake' }).Installed | Should -BeFalse
        }

        It 'keeps formula results when cask search reports no Homebrew matches' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae 7zip' = Get-TestCommandResponse -Output @('7zip')
                'brew search --casks 7zip' = Get-TestCommandResponse -ExitCode 1 -Output @('Error: No formulae or casks found for "7zip".')
            }

            $result = @(Find-PlatformPackage -PackageManager brew -NonInteractive -Query 7zip -CommandRunner $runner -Top 0)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be '7zip'
            $result[0].Type | Should -Be 'Formula'
        }

        It 'keeps cask results when formula search reports no Homebrew matches' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae code' = Get-TestCommandResponse -ExitCode 1 -Output @('Error: No formulae found for "code".')
                'brew search --casks code' = Get-TestCommandResponse -Output @('visual-studio-code')
            }

            $result = @(Find-PlatformPackage -PackageManager brew -NonInteractive -Query code -CommandRunner $runner -Top 0)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'visual-studio-code'
            $result[0].Type | Should -Be 'Cask'
        }
    }

    Context 'APT search' {
        It 'parses package descriptions and installed state' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt search --names-only openssl' = Get-TestCommandResponse -Output @(
                    'Sorting... Done'
                    'Full Text Search... Done'
                    'openssl/jammy-updates 3.0.2-0ubuntu1.15 amd64 [installed,automatic]'
                    '  Secure Sockets Layer toolkit - cryptographic utility'
                )
            }

            $result = @(Find-PlatformPackage -PackageManager apt -NonInteractive -Query openssl -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'openssl'
            $result[0].Installed | Should -BeTrue
            $result[0].Notes | Should -Be 'Automatic'
            $result[0].Description | Should -Be 'Secure Sockets Layer toolkit - cryptographic utility'
        }
    }

    Context 'apk search' {
        It 'parses versioned results and installed markers' {
            $runner = & $script:NewPackageCommandRunner @{
                'apk search --description bash' = Get-TestCommandResponse -Output @(
                    'bash-5.2.15-r5 -- GNU Bourne Again shell [installed]'
                    'bash-doc-5.2.15-r5 -- Documentation for bash'
                )
            }

            $result = @(Find-PlatformPackage -PackageManager apk -NonInteractive -Query bash -CommandRunner $runner -Top 0)

            $result.Count | Should -Be 2
            ($result | Where-Object { $_.Name -eq 'bash' }).Installed | Should -BeTrue
            ($result | Where-Object { $_.Name -eq 'bash-doc' }).Version | Should -Be '5.2.15-r5'
        }
    }

    Context 'result limiting and filtering' {
        It 'applies exclusions and top limits after normalization' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @('git-credential-manager')
            }

            $result = @(Find-PlatformPackage -PackageManager brew -NonInteractive -Query git -ExcludePackage 'git-lfs' -Top 1 -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
        }
    }

    Context 'mode validation' {
        It 'requires interactive mode when PassThru is used' {
            $runner = & $script:NewPackageCommandRunner @{}

            {
                Find-PlatformPackage -PackageManager brew -NonInteractive -PassThru -Query git -CommandRunner $runner
            } | Should -Throw -ExpectedMessage '*PassThru requires interactive package search*'
        }

        It 'requires a query in NonInteractive mode' {
            $runner = & $script:NewPackageCommandRunner @{}

            {
                Find-PlatformPackage -PackageManager brew -NonInteractive -CommandRunner $runner
            } | Should -Throw -ExpectedMessage '*Query is required when -NonInteractive is used*'
        }
    }

    Context 'interactive remote search UI' {
        It 'prompts for a query and renders remote registry results by default' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @('git-credential-manager')
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $queryReader = {
                'git'
            }
            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = @(Find-PlatformPackage -PackageManager brew -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Search: git' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: Space select  I install  V details  A toggle all' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq "1-3 of 3 visible  $([char]0x00B7)  3 total  $([char]0x00B7)  0 selected  $([char]0x00B7)  source: All" -and $ForegroundColor -eq 'White' } -Times 1
            @($script:HostOutputRecords | Where-Object { $_.ForegroundColor -eq [ConsoleColor]::DarkGray -and $_.Object -like '*git*' }).Count | Should -BeGreaterOrEqual 2
            @($script:HostOutput | Where-Object { [String]::IsNullOrEmpty([String]$_) }).Count | Should -Be 4
        }

        It 'allows a new query to be entered from the interactive browser' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
                'brew search --formulae code' = Get-TestCommandResponse -Output @()
                'brew search --casks code' = Get-TestCommandResponse -Output @('visual-studio-code')
            }

            $queries = [System.Collections.Generic.Queue[String]]::new()
            @('git', 'code') | ForEach-Object { $queries.Enqueue($_) }
            $queryReader = {
                return $queries.Dequeue()
            }.GetNewClosure()

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('/', [ConsoleKey]::Oem2, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Find-PlatformPackage -PackageManager brew -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader)

            $result.Count | Should -Be 0
            @($script:Invocations | Where-Object { $_.Key -eq 'brew search --formulae git' }).Count | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew search --casks code' }).Count | Should -Be 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Search: code' } -Times 1
        }

        It 'shows keyboard help from the search result picker' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
            }

            $queryReader = {
                'git'
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

            $result = @(Find-PlatformPackage -PackageManager brew -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Find-PlatformPackage Help' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq '/: ' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'start a new search' -and $ForegroundColor -eq 'DarkGray' } -Times 1
        }

        It 'returns selected packages when PassThru is used' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
            }

            $queryReader = {
                'git'
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Find-PlatformPackage -PackageManager brew -PassThru -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: Space select  Enter return  I install  V details  A toggle all' } -Times 1
        }

        It 'opens the result picker with the requested source filter' {
            $wingetSearchJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.45.1'
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
                                Version = '2.45.1'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @()
                    }
                )
            } | ConvertTo-Json -Depth 4 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget search git --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetSearchJson)
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
            }
            $queryReader = {
                'git'
            }
            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            }

            $result = @(Find-PlatformPackage -PackageManager winget -PassThru -FilterSource msstore -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader)

            $result.Count | Should -Be 1
            $result[0].Source | Should -Be 'msstore'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'S: \[msstore\]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*winget*' -and $Object -notlike '*msstore*' } -Times 0
        }

        It 'keeps picker table rows within the current console width' {
            $wingetSearchJson = @{
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
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @()
                    }
                )
            } | ConvertTo-Json -Depth 4 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget search sql --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetSearchJson)
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
            }
            $queryReader = {
                'sql'
            }
            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $null = Find-PlatformPackage -PackageManager winget -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader

            $tableLines = @(
                $script:HostOutput |
                ForEach-Object { "$_" } |
                Where-Object {
                    $_ -match '^\s+Sel\s+' -or
                    $_ -match '^[> ] \[[ x]\]\s+'
                }
            )

            $tableLines.Count | Should -BeGreaterThan 1
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+' } | Select-Object -First 1) | Should -Match '\bVer\b'
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+' } | Select-Object -First 1) | Should -Match '\bTyp\b'
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+' } | Select-Object -First 1) | Should -Match '\bSrc\b'
            ($tableLines | Where-Object { $_ -match '^[> ] \[[ x]\]\s+' } | Select-Object -First 1) | Should -Match 'homebrew/core'
            (($tableLines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum) | Should -BeLessOrEqual (Get-TestPickerLineLimit)
        }

        It 'returns the current package when PassThru is used without a selection' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
            }

            $queryReader = {
                'git'
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            }

            $result = @(Find-PlatformPackage -PackageManager brew -PassThru -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: Space select  Enter return  I install  V details  A toggle all' } -Times 1
        }

        It 'installs the selected package from the interactive browser' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
                'brew install git' = Get-TestCommandResponse -Output @('brew install git output')
            }

            $queryReader = {
                'git'
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('i', [ConsoleKey]::I, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Find-PlatformPackage -PackageManager brew -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader

            $result.Selected | Should -Be 1
            $result.Installed | Should -Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'brew install git' }).StreamOutput | Should -BeTrue
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'brew install git output' } -Times 1
        }

        It 'loads missing winget descriptions only when D is pressed' {
            $wingetSearchJson = @{
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
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @()
                    }
                )
            } | ConvertTo-Json -Depth 4 -Compress
            $wingetShowJson = @{
                DefaultLocale = @{
                    Description = 'Distributed version control system'
                }
            } | ConvertTo-Json -Depth 4 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget search git --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetSearchJson)
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
                'winget show --id Git.Git --exact --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetShowJson)
            }

            $queryReader = {
                'git'
            }
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('v', [ConsoleKey]::V, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Find-PlatformPackage -PackageManager winget -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: <press V to load>' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: retrieving description...' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: Distributed version control system' } -Times 1
            @($script:Invocations | Where-Object { $_.Key -eq 'winget show --id Git.Git --exact --accept-source-agreements --output json' }).Count | Should -Be 1
        }

        It 'does not suppress terminal echo when a custom key reader drives winget details' -Skip:($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) {
            $wingetSearchJson = @{
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
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @()
                    }
                )
            } | ConvertTo-Json -Depth 4 -Compress
            $wingetShowJson = @{
                DefaultLocale = @{
                    Description = 'Distributed version control system'
                }
            } | ConvertTo-Json -Depth 4 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget search git --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetSearchJson)
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
                'winget show --id Git.Git --exact --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetShowJson)
            }
            $queryReader = {
                'git'
            }
            $keyReader = & $script:NewKeyReader -Values @(
                [System.ConsoleKeyInfo]::new('v', [ConsoleKey]::V, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            )
            $echoActions = New-Object 'System.Collections.Generic.List[Object]'
            $terminalEchoController = & $script:NewTerminalEchoController -Actions $echoActions

            $result = @(Find-PlatformPackage -PackageManager winget -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader -TerminalEchoController $terminalEchoController)

            $result.Count | Should -Be 0
            $echoActions.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: Distributed version control system' } -Times 1
        }

        It 'restores terminal echo when winget details throw in the console key reader flow' -Skip:($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) {
            $wingetSearchJson = @{
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
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @()
                    }
                )
            } | ConvertTo-Json -Depth 4 -Compress
            $searchResponse = Get-TestCommandResponse -Output @($wingetSearchJson)
            $listResponse = Get-TestCommandResponse -Output @($wingetListJson)
            $runner = {
                param(
                    [Parameter(Mandatory)]
                    [String]$Command,

                    [Parameter()]
                    [String[]]$Arguments = @()
                )

                $key = "$Command $($Arguments -join ' ')".Trim()
                if ($key -eq 'winget search git --accept-source-agreements --output json')
                {
                    return $searchResponse
                }

                if ($key -eq 'winget list --accept-source-agreements --output json')
                {
                    return $listResponse
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
            $queryReader = {
                'git'
            }
            $keyReader = & $script:NewKeyReader -Values @(
                [System.ConsoleKeyInfo]::new('v', [ConsoleKey]::V, $false, $false, $false)
            )
            $echoActions = New-Object 'System.Collections.Generic.List[Object]'
            $terminalEchoController = & $script:NewTerminalEchoController -Actions $echoActions

            {
                Find-PlatformPackage -PackageManager winget -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader -TreatKeyReaderAsConsoleKeyReader -TerminalEchoController $terminalEchoController
            } | Should -Throw -ExpectedMessage '*winget details failed*'

            ($echoActions -join '|') | Should -Be 'Disable|Restore:saved-stty-state'
        }
    }
}
