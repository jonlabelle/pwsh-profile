#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Test-ProfileUpdate.

.DESCRIPTION
    Covers repository validation, offline checks, fetch failures, no-op checks,
    and update notification output without requiring a real git repository or
    network access.
#>

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/ProfileManagement/Test-ProfileUpdate.ps1"

    function Invoke-TestProfileUpdateGitShim
    {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [Object[]]$RemainingArgs
        )

        $arguments = @($RemainingArgs)
        $script:GitInvocations += , $arguments

        if ($script:GitBehavior)
        {
            return & $script:GitBehavior -Arguments $arguments
        }

        $global:LASTEXITCODE = 0
        return @()
    }

    function New-TestProfileUpdateTestRoot
    {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper creates isolated TestDrive directories.')]
        param(
            [Switch]$GitRepository
        )

        $profileRoot = Join-Path -Path $TestDrive -ChildPath "profile-$(Get-Random)"
        New-Item -Path $profileRoot -ItemType Directory -Force | Out-Null

        if ($GitRepository)
        {
            New-Item -Path (Join-Path -Path $profileRoot -ChildPath '.git') -ItemType Directory -Force | Out-Null
        }

        return $profileRoot
    }
}

AfterAll {
    Remove-Item -Path Function:\Invoke-TestProfileUpdateGitShim -ErrorAction SilentlyContinue
    Remove-Item -Path Function:\New-TestProfileUpdateTestRoot -ErrorAction SilentlyContinue
}

Describe 'Test-ProfileUpdate' {
    BeforeEach {
        $script:OriginalLocation = Get-Location
        $script:GitInvocations = @()
        $script:GitBehavior = $null
        $script:ConnectivityHosts = @()
        $script:ConnectivityTest = {
            param([String]$Hostname)

            $script:ConnectivityHosts += $Hostname
            return $true
        }
        $global:LASTEXITCODE = 0
    }

    AfterEach {
        Set-Location -Path $script:OriginalLocation -ErrorAction SilentlyContinue
        Remove-Variable -Name OriginalLocation, GitInvocations, GitBehavior, ConnectivityHosts, ConnectivityTest -Scope Script -ErrorAction SilentlyContinue
        $global:LASTEXITCODE = 0
    }

    Context 'Repository validation' {
        It 'Returns null and skips git checks when the profile root is not a git repository' {
            $profileRoot = New-TestProfileUpdateTestRoot

            $result = Test-ProfileUpdate -ProfileRoot $profileRoot -GitRunner ${function:Invoke-TestProfileUpdateGitShim} -ConnectivityTest $script:ConnectivityTest -ErrorAction Stop

            $result | Should -Be $null
            $script:GitInvocations.Count | Should -Be 0
            $script:ConnectivityHosts.Count | Should -Be 0
            (Get-Location).Path | Should -Be $script:OriginalLocation.Path
        }

        It 'Returns null when remote.origin.url is missing' {
            $profileRoot = New-TestProfileUpdateTestRoot -GitRepository
            $script:GitBehavior = {
                param([Object[]]$Arguments)

                ($Arguments -join ' ') | Should -Be 'config --get remote.origin.url'
                $global:LASTEXITCODE = 1
                return @()
            }

            $result = Test-ProfileUpdate -ProfileRoot $profileRoot -GitRunner ${function:Invoke-TestProfileUpdateGitShim} -ConnectivityTest $script:ConnectivityTest -ErrorAction Stop

            $result | Should -Be $null
            $script:GitInvocations.Count | Should -Be 1
            $script:ConnectivityHosts.Count | Should -Be 0
        }
    }

    Context 'Remote reachability' {
        It 'Returns null and does not fetch when DNS or offline connectivity fails' {
            $profileRoot = New-TestProfileUpdateTestRoot -GitRepository
            $script:GitBehavior = {
                param([Object[]]$Arguments)

                if (($Arguments -join ' ') -eq 'config --get remote.origin.url')
                {
                    $global:LASTEXITCODE = 0
                    return 'https://github.com/jonlabelle/pwsh-profile.git'
                }

                throw "Unexpected git invocation: $($Arguments -join ' ')"
            }
            $script:ConnectivityTest = {
                param([String]$Hostname)

                $script:ConnectivityHosts += $Hostname
                throw 'DNS lookup failed'
            }

            $result = Test-ProfileUpdate -ProfileRoot $profileRoot -GitRunner ${function:Invoke-TestProfileUpdateGitShim} -ConnectivityTest $script:ConnectivityTest -ErrorAction Stop

            $result | Should -Be $null
            $script:ConnectivityHosts | Should -Contain 'github.com'

            $fetchInvocations = @($script:GitInvocations | Where-Object { ($_ -join ' ') -eq 'fetch origin' })
            $fetchInvocations.Count | Should -Be 0
        }

        It 'Returns null when git fetch origin fails' {
            $profileRoot = New-TestProfileUpdateTestRoot -GitRepository
            $script:GitBehavior = {
                param([Object[]]$Arguments)

                $commandLine = $Arguments -join ' '
                switch ($commandLine)
                {
                    'config --get remote.origin.url'
                    {
                        $global:LASTEXITCODE = 0
                        return 'https://github.com/jonlabelle/pwsh-profile.git'
                    }
                    'fetch origin'
                    {
                        $global:LASTEXITCODE = 128
                        return 'fatal: unable to access remote repository'
                    }
                    default
                    {
                        throw "Unexpected git invocation: $commandLine"
                    }
                }
            }

            $result = Test-ProfileUpdate -ProfileRoot $profileRoot -GitRunner ${function:Invoke-TestProfileUpdateGitShim} -ConnectivityTest $script:ConnectivityTest -ErrorAction Stop

            $result | Should -Be $null

            $fetchInvocations = @($script:GitInvocations | Where-Object { ($_ -join ' ') -eq 'fetch origin' })
            $fetchInvocations.Count | Should -Be 1

            $revParseInvocations = @($script:GitInvocations | Where-Object { ($_ -join ' ') -match '^rev-parse ' })
            $revParseInvocations.Count | Should -Be 0
        }
    }

    Context 'Update detection' {
        It 'Returns false when local and remote HEAD match' {
            $profileRoot = New-TestProfileUpdateTestRoot -GitRepository
            $script:GitBehavior = {
                param([Object[]]$Arguments)

                $commandLine = $Arguments -join ' '
                switch ($commandLine)
                {
                    'config --get remote.origin.url'
                    {
                        $global:LASTEXITCODE = 0
                        return 'https://github.com/jonlabelle/pwsh-profile.git'
                    }
                    'fetch origin'
                    {
                        $global:LASTEXITCODE = 0
                        return @()
                    }
                    'rev-parse HEAD'
                    {
                        $global:LASTEXITCODE = 0
                        return '1111111'
                    }
                    'rev-parse origin/main'
                    {
                        $global:LASTEXITCODE = 0
                        return '1111111'
                    }
                    default
                    {
                        throw "Unexpected git invocation: $commandLine"
                    }
                }
            }

            $result = Test-ProfileUpdate -ProfileRoot $profileRoot -GitRunner ${function:Invoke-TestProfileUpdateGitShim} -ConnectivityTest $script:ConnectivityTest -ErrorAction Stop

            $result | Should -BeFalse

            $revListInvocations = @($script:GitInvocations | Where-Object { ($_ -join ' ') -match '^rev-list ' })
            $logInvocations = @($script:GitInvocations | Where-Object { ($_ -join ' ') -match '^log ' })
            $revListInvocations.Count | Should -Be 0
            $logInvocations.Count | Should -Be 0
        }

        It 'Returns true and shows cleaned change bullets when updates are available with ShowChanges' {
            $profileRoot = New-TestProfileUpdateTestRoot -GitRepository
            $script:GitBehavior = {
                param([Object[]]$Arguments)

                $commandLine = $Arguments -join ' '
                switch ($commandLine)
                {
                    'config --get remote.origin.url'
                    {
                        $global:LASTEXITCODE = 0
                        return 'https://github.com/jonlabelle/pwsh-profile.git'
                    }
                    'fetch origin'
                    {
                        $global:LASTEXITCODE = 0
                        return @()
                    }
                    'rev-parse HEAD'
                    {
                        $global:LASTEXITCODE = 0
                        return '1111111'
                    }
                    'rev-parse origin/main'
                    {
                        $global:LASTEXITCODE = 0
                        return '2222222'
                    }
                    'rev-list --count 1111111..2222222'
                    {
                        $global:LASTEXITCODE = 0
                        return '2'
                    }
                    'log --oneline 1111111..origin/main'
                    {
                        $global:LASTEXITCODE = 0
                        return @(
                            '2222222 (HEAD -> main, origin/main) feat(profile): add updater coverage',
                            '3333333 docs: refresh update notes'
                        )
                    }
                    default
                    {
                        throw "Unexpected git invocation: $commandLine"
                    }
                }
            }

            $rawOutput = @(Test-ProfileUpdate -ProfileRoot $profileRoot -ShowChanges -GitRunner ${function:Invoke-TestProfileUpdateGitShim} -ConnectivityTest $script:ConnectivityTest -ErrorAction Stop 6>&1)

            $rawOutput | Should -Contain $true

            $hostOutput = @($rawOutput | Where-Object { $_ -isnot [Boolean] } | ForEach-Object { [String]$_ })
            $hostOutput | Should -Contain 'Profile updates are available!'
            $hostOutput | Should -Contain 'Here are the available changes:'
            $hostOutput | Should -Contain '  - feat: add updater coverage'
            $hostOutput | Should -Contain '  - docs: refresh update notes'
            $hostOutput | Should -Contain "Run 'Update-Profile' to apply these changes."

            $output = $hostOutput -join "`n"
            $output | Should -Not -Match '2222222'
            $output | Should -Not -Match 'HEAD -> main'
            $output | Should -Not -Match '\(profile\)'
        }
    }
}
