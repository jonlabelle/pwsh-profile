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

    $script:NewNativeCommandDirectory = {
        param(
            [Parameter(Mandatory)]
            [string]$IdOutput,

            [Parameter()]
            [int]$IdExitCode = 0,

            [Parameter()]
            [switch]$IncludeSudo,

            [Parameter()]
            [int]$SudoExitCode = 0
        )

        $directory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "test-admin-native-$(Get-Random)"
        New-Item -Path $directory -ItemType Directory -Force | Out-Null

        $idScript = Join-Path -Path $directory -ChildPath 'id'
        $idContent = @"
#!/bin/sh
if [ "`$1" = "-u" ]; then
    echo "$IdOutput"
    exit $IdExitCode
fi

exit 1
"@
        [System.IO.File]::WriteAllText($idScript, $idContent, [System.Text.UTF8Encoding]::new($false))
        /bin/chmod 755 $idScript

        if ($IncludeSudo)
        {
            $sudoScript = Join-Path -Path $directory -ChildPath 'sudo'
            $sudoContent = @"
#!/bin/sh
exit $SudoExitCode
"@
            [System.IO.File]::WriteAllText($sudoScript, $sudoContent, [System.Text.UTF8Encoding]::new($false))
            /bin/chmod 755 $sudoScript
        }

        return $directory
    }
}

Describe 'Test-Admin' {
    BeforeEach {
        $script:OriginalSudoUser = $env:SUDO_USER
        $script:OriginalSudoUid = $env:SUDO_UID
        $script:OriginalPath = $env:PATH
        $script:NativeCommandTestDir = $null

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

        if ($script:NativeCommandTestDir -and (Test-Path -LiteralPath $script:NativeCommandTestDir))
        {
            Remove-Item -LiteralPath $script:NativeCommandTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }

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

        It 'does not treat sudo capability as elevation unless AllowSudo is specified' {
            $script:NativeCommandTestDir = & $script:NewNativeCommandDirectory -IdOutput '501' -IncludeSudo -SudoExitCode 0
            $env:PATH = $script:NativeCommandTestDir

            Test-Admin | Should -BeFalse
        }

        It 'returns true with AllowSudo when non-interactive sudo succeeds' {
            $script:NativeCommandTestDir = & $script:NewNativeCommandDirectory -IdOutput '501' -IncludeSudo -SudoExitCode 0
            $env:PATH = $script:NativeCommandTestDir

            Test-Admin -AllowSudo | Should -BeTrue
        }

        It 'returns false with AllowSudo when non-interactive sudo fails' {
            $script:NativeCommandTestDir = & $script:NewNativeCommandDirectory -IdOutput '501' -IncludeSudo -SudoExitCode 1
            $env:PATH = $script:NativeCommandTestDir

            Test-Admin -AllowSudo | Should -BeFalse
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
