Describe 'Start-KeepAlive function' {
    BeforeAll {
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
        $func = Join-Path -Path (Join-Path -Path $root -ChildPath 'Functions') -ChildPath 'Start-KeepAlive.ps1'
        . $func
    }

    It 'does not start on non-Windows platforms (throws)' {
        # On non-Windows platforms Start-KeepAlive throws during begin; assert that behavior where applicable
        if ($IsWindows) { return }
        { Start-KeepAlive -EndJob } | Should -Throw
    }

    It 'handles -EndJob gracefully when no job exists' {
        if (-not $IsWindows) { return }
        Mock -CommandName Get-Job -MockWith { $null }
        { Start-KeepAlive -EndJob } | Should -Not -Throw
    }
}
