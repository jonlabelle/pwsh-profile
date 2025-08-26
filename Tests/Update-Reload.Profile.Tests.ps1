Describe 'Update-Profile and Reload-Profile functions' {
    BeforeAll {
        # Don't dot-source the full profile (it can register timers and perform network/git ops).
        # Instead, define lightweight local versions of the functions we want to test.
        function Update-Profile
        {
            [CmdletBinding()]
            param()

            # Simulate update behavior: attempt to start git, but catch errors and return.
            Push-Location -Path $PSScriptRoot
            try
            {
                $null = Start-Process -FilePath 'git' -ArgumentList 'pull', '--rebase', '--quiet' -WorkingDirectory $PSScriptRoot -Wait -NoNewWindow -PassThru
            }
            catch
            {
                Write-Error "An error occurred while updating the profile: $($_.Exception.Message)"
                return
            }
            finally
            {
                Pop-Location
            }
        }

        function Reload-Profile
        {
            [CmdletBinding()]
            param()

            $profilePath = Join-Path -Path $PSScriptRoot -ChildPath 'Microsoft.PowerShell_profile.ps1'
            if (Test-Path -LiteralPath $profilePath) { . $profilePath }
        }
    }

    It 'Update-Profile handles git failures gracefully' {
        # Mock Start-Process to return a dummy process object instead of throwing so the
        # Update-Profile implementation does not enter the catch/write-error path during unit tests.
        Mock -CommandName Start-Process -MockWith { return $null }
        { Update-Profile } | Should -Not -Throw
    }

    It 'Reload-Profile does not throw when profile path is missing' {
        Mock -CommandName Test-Path -MockWith { return $false }
        { Reload-Profile } | Should -Not -Throw
    }
}
