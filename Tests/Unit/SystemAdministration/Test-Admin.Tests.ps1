#Requires -Modules Pester

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Test-Admin.ps1"

    $script:IsWindowsTest = if ($PSVersionTable.PSVersion.Major -lt 6)
    {
        $true
    }
    else
    {
        $IsWindows
    }

    $script:IsUnixTest = -not $script:IsWindowsTest
    $script:SkipUnixContext = -not $script:IsUnixTest

    if ($script:IsUnixTest)
    {
        $script:IdCommand = Get-Command -Name 'id' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        $script:HasUnixIdCommand = $null -ne $script:IdCommand
        $script:IsUnixElevatedSession = if ($script:HasUnixIdCommand)
        {
            (& $script:IdCommand.Source -u) -eq '0'
        }
        else
        {
            $false
        }
    }
    else
    {
        $script:IdCommand = $null
        $script:HasUnixIdCommand = $false
        $script:IsUnixElevatedSession = $false
    }
}

Describe 'Test-Admin' {
    BeforeEach {
        $script:OriginalSudoUser = $env:SUDO_USER
        $script:OriginalSudoUid = $env:SUDO_UID
        $script:OriginalPath = $env:PATH

        Remove-Variable -Name 'IsWindowsPlatform', 'IsMacOSPlatform', 'IsLinuxPlatform' -Scope Script -ErrorAction SilentlyContinue
    }

    AfterEach {
        if ($null -eq $script:OriginalSudoUser)
        {
            Remove-Item -Path Env:\SUDO_USER -ErrorAction SilentlyContinue
        }
        else
        {
            $env:SUDO_USER = $script:OriginalSudoUser
        }

        if ($null -eq $script:OriginalSudoUid)
        {
            Remove-Item -Path Env:\SUDO_UID -ErrorAction SilentlyContinue
        }
        else
        {
            $env:SUDO_UID = $script:OriginalSudoUid
        }

        $env:PATH = $script:OriginalPath

        Remove-Variable -Name 'IsWindowsPlatform', 'IsMacOSPlatform', 'IsLinuxPlatform' -Scope Script -ErrorAction SilentlyContinue
    }

    It 'is available as a function' {
        $command = Get-Command -Name 'Test-Admin' -ErrorAction SilentlyContinue

        $command | Should -Not -BeNullOrEmpty
        $command.CommandType | Should -Be 'Function'
    }

    It 'returns a boolean result' {
        $result = Test-Admin

        $result | Should -BeOfType [System.Boolean]
    }

    It 'creates the Test-Root alias' {
        $alias = Get-Alias -Name 'Test-Root' -ErrorAction SilentlyContinue

        $alias | Should -Not -BeNullOrEmpty
        $alias.Definition | Should -Be 'Test-Admin'
    }

    It 'creates the Test-Sudo alias' {
        $alias = Get-Alias -Name 'Test-Sudo' -ErrorAction SilentlyContinue

        $alias | Should -Not -BeNullOrEmpty
        $alias.Definition | Should -Be 'Test-Admin'
    }

    It 'does not leak platform variables into the caller script scope' {
        $null = Test-Admin

        Get-Variable -Name 'IsWindowsPlatform' -Scope Script -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Variable -Name 'IsMacOSPlatform' -Scope Script -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Variable -Name 'IsLinuxPlatform' -Scope Script -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    Context 'Unix privilege detection' -Skip:$script:SkipUnixContext {
        It 'matches the current process effective user ID' -Skip:(-not $script:HasUnixIdCommand) {
            Test-Admin | Should -Be $script:IsUnixElevatedSession
        }

        It 'does not treat SUDO_* environment variables as proof of elevation' -Skip:(-not $script:HasUnixIdCommand -or $script:IsUnixElevatedSession) {
            $env:SUDO_USER = 'root'
            $env:SUDO_UID = '0'

            Test-Admin | Should -BeFalse
        }

        It 'writes a warning and returns false when the id command cannot be resolved' {
            $env:PATH = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "test-admin-missing-path-$(Get-Random)"
            $warnings = $null

            $result = Test-Admin -WarningAction Continue -WarningVariable warnings

            $result | Should -BeFalse
            @($warnings).Count | Should -BeGreaterThan 0
            ($warnings | Out-String) | Should -Match 'Failed to determine privilege status'
        }

        It 'suppresses warning output with Quiet when the id command cannot be resolved' {
            $env:PATH = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "test-admin-missing-path-$(Get-Random)"
            $warnings = $null

            $result = Test-Admin -Quiet -WarningAction Continue -WarningVariable warnings

            $result | Should -BeFalse
            @($warnings).Count | Should -Be 0
        }
    }
}
