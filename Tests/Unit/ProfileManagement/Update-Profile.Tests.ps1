#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = (Resolve-Path "$PSScriptRoot/../../..").Path
    $script:updateProfileScript = Join-Path -Path $script:repoRoot -ChildPath 'Functions/ProfileManagement/Update-Profile.ps1'
    $script:gitCommand = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
    $script:gitExecutable = if ($script:gitCommand) { $script:gitCommand.Definition } else { $null }
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
    . $script:updateProfileScript
}

Describe 'Update-Profile' {
    It 'preserves protected local profile paths during a normal git update' -Skip:($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
        $testRoot = Join-Path -Path $TestDrive -ChildPath ('UpdateProfile_{0}' -f ([guid]::NewGuid().ToString('N')))
        $remoteRepo = Join-Path -Path $testRoot -ChildPath 'RemoteProfile'
        $profileRoot = Join-Path -Path $testRoot -ChildPath 'ProfileRoot'
        $oldProfile = $PROFILE

        try
        {
            New-Item -ItemType Directory -Path $remoteRepo -Force | Out-Null
            & $script:gitExecutable '-C' $remoteRepo 'init' | Out-Null
            & $script:gitExecutable '-C' $remoteRepo 'config' 'user.email' 'ci@example.com' | Out-Null
            & $script:gitExecutable '-C' $remoteRepo 'config' 'user.name' 'CI Bot' | Out-Null

            New-Item -ItemType Directory -Path (Join-Path -Path $remoteRepo -ChildPath 'Functions/Local') -Force | Out-Null
            Set-Content -Path (Join-Path -Path $remoteRepo -ChildPath '.gitignore') -Value @(
                '/powershell.config.json'
                '/Functions/Local/**/*'
                '!/Functions/Local/README.md'
            )
            Set-Content -Path (Join-Path -Path $remoteRepo -ChildPath 'Microsoft.PowerShell_profile.ps1') -Value '# initial profile'
            Set-Content -Path (Join-Path -Path $remoteRepo -ChildPath 'Functions/Local/README.md') -Value '# local functions'

            & $script:gitExecutable '-C' $remoteRepo 'add' '.' | Out-Null
            & $script:gitExecutable '-C' $remoteRepo 'commit' '-m' 'initial profile' | Out-Null

            & $script:gitExecutable 'clone' '--quiet' $remoteRepo $profileRoot | Out-Null

            Set-Variable -Name PROFILE -Value (Join-Path -Path $profileRoot -ChildPath 'Microsoft.PowerShell_profile.ps1') -Scope Local
            Set-Content -Path (Join-Path -Path $profileRoot -ChildPath 'powershell.config.json') -Value '{ "local": true }'
            Set-Content -Path (Join-Path -Path $profileRoot -ChildPath 'Functions/Local/Private.ps1') -Value 'function Invoke-LocalOnly { "local" }'

            Set-Content -Path (Join-Path -Path $remoteRepo -ChildPath 'Microsoft.PowerShell_profile.ps1') -Value '# updated profile'
            Set-Content -Path (Join-Path -Path $remoteRepo -ChildPath 'powershell.config.json') -Value '{ "remote": true }'
            Set-Content -Path (Join-Path -Path $remoteRepo -ChildPath 'Functions/Local/Private.ps1') -Value 'function Invoke-LocalOnly { "remote" }'

            & $script:gitExecutable '-C' $remoteRepo 'add' 'Microsoft.PowerShell_profile.ps1' | Out-Null
            & $script:gitExecutable '-C' $remoteRepo 'add' '-f' 'powershell.config.json' 'Functions/Local/Private.ps1' | Out-Null
            & $script:gitExecutable '-C' $remoteRepo 'commit' '-m' 'track protected profile paths' | Out-Null

            Update-Profile

            (Get-Content -Path (Join-Path -Path $profileRoot -ChildPath 'Microsoft.PowerShell_profile.ps1') -Raw).Trim() | Should -Be '# updated profile'
            (Get-Content -Path (Join-Path -Path $profileRoot -ChildPath 'powershell.config.json') -Raw).Trim() | Should -Be '{ "local": true }'
            (Get-Content -Path (Join-Path -Path $profileRoot -ChildPath 'Functions/Local/Private.ps1') -Raw).Trim() | Should -Be 'function Invoke-LocalOnly { "local" }'
        }
        finally
        {
            Set-Variable -Name PROFILE -Value $oldProfile -Scope Local
            if (Test-Path -Path $testRoot)
            {
                Remove-TestDirectory -Path $testRoot
            }
        }
    }
}
