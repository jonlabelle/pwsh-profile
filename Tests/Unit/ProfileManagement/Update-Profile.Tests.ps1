#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Update-Profile.

.DESCRIPTION
    Covers git availability, repository validation, pull failures, and commit
    summary output without requiring a real git repository or network access.
#>

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/ProfileManagement/Update-Profile.ps1"

    function Invoke-UpdateProfileGitShim
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

    function New-UpdateProfileTestRoot
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
    Remove-Item -Path Function:\Invoke-UpdateProfileGitShim -ErrorAction SilentlyContinue
    Remove-Item -Path Function:\New-UpdateProfileTestRoot -ErrorAction SilentlyContinue
}

Describe 'Update-Profile' {
    BeforeEach {
        $script:GitInvocations = @()
        $script:GitBehavior = $null
        $global:LASTEXITCODE = 0
    }

    AfterEach {
        Remove-Variable -Name GitInvocations, GitBehavior -Scope Script -ErrorAction SilentlyContinue
        $global:LASTEXITCODE = 0
    }

    Context 'Prerequisite validation' {
        It 'Shows manual update guidance when Git is missing from PATH' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'git' } -MockWith { $null }

            $hostOutput = @(Update-Profile -ProfileRoot (New-UpdateProfileTestRoot) -ErrorAction Stop 6>&1 | ForEach-Object { [String]$_ })

            $output = $hostOutput -join "`n"
            $output | Should -Match 'Git is not installed or not found in PATH\.'
            $output | Should -Match 'install\.ps1'
            $script:GitInvocations.Count | Should -Be 0
        }

        It 'Writes an error when the profile root is not a git repository' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'git' } -MockWith {
                [PSCustomObject]@{
                    Name = 'Invoke-UpdateProfileGitShim'
                    Source = 'Invoke-UpdateProfileGitShim'
                }
            }

            $profileRoot = New-UpdateProfileTestRoot

            $null = Update-Profile -ProfileRoot $profileRoot -ErrorAction SilentlyContinue -ErrorVariable updateErrors 6>&1

            $updateErrors[0].Exception.Message | Should -Match 'is not a git repository'
            $script:GitInvocations.Count | Should -Be 0
        }
    }

    Context 'Pull behavior' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'git' } -MockWith {
                [PSCustomObject]@{
                    Name = 'Invoke-UpdateProfileGitShim'
                    Source = 'Invoke-UpdateProfileGitShim'
                }
            }
        }

        It 'Writes git output and an error when git pull --rebase fails' {
            $profileRoot = New-UpdateProfileTestRoot -GitRepository
            $script:GitBehavior = {
                param([Object[]]$Arguments)

                $commandLine = $Arguments -join ' '

                if ($commandLine -match 'rev-parse HEAD$')
                {
                    $global:LASTEXITCODE = 0
                    return '1111111'
                }

                if ($commandLine -match 'pull --rebase$')
                {
                    $global:LASTEXITCODE = 128
                    return @('fatal: cannot rebase: You have unstaged changes.')
                }

                $global:LASTEXITCODE = 0
                return @()
            }

            $hostOutput = @(Update-Profile -ProfileRoot $profileRoot -ErrorAction SilentlyContinue -ErrorVariable updateErrors 6>&1 | ForEach-Object { [String]$_ })

            $hostOutput | Should -Contain 'fatal: cannot rebase: You have unstaged changes.'
            $updateErrors[0].Exception.Message | Should -Match 'git pull failed with exit code 128'

            $pullInvocations = @($script:GitInvocations | Where-Object { ($_ -join ' ') -match 'pull --rebase$' })
            $pullInvocations.Count | Should -Be 1

            $logInvocations = @($script:GitInvocations | Where-Object { ($_ -join ' ') -match 'log --oneline' })
            $logInvocations.Count | Should -Be 0
        }

        It 'Shows the up-to-date message when HEAD is unchanged' {
            $profileRoot = New-UpdateProfileTestRoot -GitRepository
            $script:GitBehavior = {
                param([Object[]]$Arguments)

                $commandLine = $Arguments -join ' '

                if ($commandLine -match 'rev-parse HEAD$')
                {
                    $global:LASTEXITCODE = 0
                    return '1111111'
                }

                if ($commandLine -match 'pull --rebase$')
                {
                    $global:LASTEXITCODE = 0
                    return @('Already up to date.')
                }

                $global:LASTEXITCODE = 0
                return @()
            }

            $hostOutput = @(Update-Profile -ProfileRoot $profileRoot -ErrorAction Stop 6>&1 | ForEach-Object { [String]$_ })

            $hostOutput | Should -Contain 'Profile is already up to date.'
            $hostOutput | Should -Not -Contain 'Updates:'
        }

        It 'Prints cleaned commit summary bullets when HEAD changes' {
            $profileRoot = New-UpdateProfileTestRoot -GitRepository
            $script:RevParseCount = 0
            $script:GitBehavior = {
                param([Object[]]$Arguments)

                $commandLine = $Arguments -join ' '

                if ($commandLine -match 'rev-parse HEAD$')
                {
                    $script:RevParseCount++
                    $global:LASTEXITCODE = 0
                    if ($script:RevParseCount -eq 1)
                    {
                        return '1111111'
                    }

                    return '2222222'
                }

                if ($commandLine -match 'pull --rebase$')
                {
                    $global:LASTEXITCODE = 0
                    return @('Updating 1111111..2222222')
                }

                if ($commandLine -match 'log --oneline 1111111\.\.2222222$')
                {
                    $global:LASTEXITCODE = 0
                    return @(
                        '2222222 (HEAD -> main, origin/main) feat(profile): add updater coverage',
                        '3333333 docs: refresh update notes'
                    )
                }

                $global:LASTEXITCODE = 0
                return @()
            }

            $hostOutput = @(Update-Profile -ProfileRoot $profileRoot -ErrorAction Stop 6>&1 | ForEach-Object { [String]$_ })

            $hostOutput | Should -Contain 'Updates:'
            $hostOutput | Should -Contain '  - feat: add updater coverage'
            $hostOutput | Should -Contain '  - docs: refresh update notes'
            $hostOutput | Should -Contain 'Profile updated successfully! Restart your PowerShell session to reload your profile.'

            $output = $hostOutput -join "`n"
            $output | Should -Not -Match '2222222'
            $output | Should -Not -Match 'HEAD -> main'
            $output | Should -Not -Match '\(profile\)'

            Remove-Variable -Name RevParseCount -Scope Script -ErrorAction SilentlyContinue
        }
    }
}
