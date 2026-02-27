# Check if Git is available early for Skip conditions (evaluated during discovery)
$script:GitAvailable = $null -ne (Get-Command 'git' -ErrorAction SilentlyContinue)

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function
    . "$PSScriptRoot/../../../Functions/Developer/Invoke-GitPull.ps1"

    # Import test utilities if available
    $testUtilitiesPath = "$PSScriptRoot/../../TestCleanupUtilities.ps1"
    if (Test-Path $testUtilitiesPath)
    {
        . $testUtilitiesPath
    }
}

Describe 'Invoke-GitPull Integration Tests' -Tag 'Integration' {
    BeforeAll {
        # Use system temp directory for test isolation
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "gitpull-integration-$(Get-Random)"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        # Helper function to run git commands silently (handles PS 5.1 stderr issues)
        # PowerShell 5.1 treats stderr output from native commands as errors in some contexts.
        # Setting ErrorActionPreference to SilentlyContinue within the function scope prevents
        # stderr-based ErrorRecords from being surfaced, even with 2>&1 redirection.
        function Invoke-GitSilent
        {
            param(
                [Parameter(Mandatory)]
                [String]$WorkingDirectory,
                [Parameter(Mandatory)]
                [String[]]$Arguments
            )

            $originalLocation = Get-Location
            $originalErrorAction = $ErrorActionPreference
            try
            {
                # Suppress errors at the function scope level for PS 5.1 compatibility
                $ErrorActionPreference = 'SilentlyContinue'
                Set-Location -Path $WorkingDirectory
                # Silently consume output - don't let stderr become errors
                $null = & git @Arguments 2>&1
            }
            finally
            {
                $ErrorActionPreference = $originalErrorAction
                Set-Location -Path $originalLocation
            }
        }

        # Helper function to run git and capture output (handles PS 5.1 stderr issues)
        function Invoke-GitWithOutput
        {
            param(
                [Parameter(Mandatory)]
                [String]$WorkingDirectory,
                [Parameter(Mandatory)]
                [String[]]$Arguments
            )

            $originalLocation = Get-Location
            try
            {
                Set-Location -Path $WorkingDirectory
                $output = & git @Arguments 2>&1 | Where-Object { $_ -is [String] -or $_.GetType().Name -ne 'ErrorRecord' }
                return ($output -join '').Trim()
            }
            finally
            {
                Set-Location -Path $originalLocation
            }
        }

        # Helper function to create a test Git repository with a remote
        function NewTestGitRepository
        {
            param(
                [String]$Path,
                [String]$Name = 'test-repo',
                [Switch]$WithRemote
            )

            $repoPath = Join-Path -Path $Path -ChildPath $Name
            New-Item -Path $repoPath -ItemType Directory -Force | Out-Null

            # Initialize the repository
            Invoke-GitSilent -WorkingDirectory $repoPath -Arguments @('init')
            Invoke-GitSilent -WorkingDirectory $repoPath -Arguments @('config', 'user.email', 'test@example.com')
            Invoke-GitSilent -WorkingDirectory $repoPath -Arguments @('config', 'user.name', 'TestUser')
            Invoke-GitSilent -WorkingDirectory $repoPath -Arguments @('config', 'core.autocrlf', 'false')

            # Create initial commit
            'Initial content' | Out-File (Join-Path -Path $repoPath -ChildPath 'README.md')
            Invoke-GitSilent -WorkingDirectory $repoPath -Arguments @('add', '.')
            Invoke-GitSilent -WorkingDirectory $repoPath -Arguments @('commit', '-m', 'InitialCommit')

            if ($WithRemote)
            {
                # Create a bare repository as a remote
                $remotePath = Join-Path -Path $Path -ChildPath "$Name-remote.git"
                Invoke-GitSilent -WorkingDirectory $Path -Arguments @('clone', '--bare', $repoPath, $remotePath)

                Invoke-GitSilent -WorkingDirectory $repoPath -Arguments @('remote', 'add', 'origin', $remotePath)
                Invoke-GitSilent -WorkingDirectory $repoPath -Arguments @('fetch', 'origin')

                # Get the current branch name (could be 'main' or 'master' depending on Git version)
                $branchName = Invoke-GitWithOutput -WorkingDirectory $repoPath -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
                Invoke-GitSilent -WorkingDirectory $repoPath -Arguments @('branch', '--set-upstream-to', "origin/$branchName", $branchName)

                return @{
                    RepoPath = $repoPath
                    RemotePath = $remotePath
                    BranchName = $branchName
                }
            }

            $branchName = Invoke-GitWithOutput -WorkingDirectory $repoPath -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')

            return @{
                RepoPath = $repoPath
                RemotePath = $null
                BranchName = $branchName
            }
        }
    }

    AfterAll {
        if (Test-Path $script:TestDir)
        {
            Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Single Repository Mode' -Skip:(-not $script:GitAvailable) {
        BeforeEach {
            $script:TestWorkspace = Join-Path -Path $script:TestDir -ChildPath "single-$(Get-Random)"
            New-Item -Path $script:TestWorkspace -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:TestWorkspace)
            {
                Remove-Item -Path $script:TestWorkspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should successfully pull from a repository with remote' {
            $repos = NewTestGitRepository -Path $script:TestWorkspace -Name 'test-repo' -WithRemote

            $result = Invoke-GitPull -Path $repos.RepoPath

            $result.RepositoriesProcessed | Should -Be 1
            $result.RepositoriesUpdated | Should -Be 1
            $result.RepositoriesFailed | Should -Be 0
        }

        It 'Should report already up to date' {
            $repos = NewTestGitRepository -Path $script:TestWorkspace -Name 'uptodate-repo' -WithRemote

            $result = Invoke-GitPull -Path $repos.RepoPath

            $result.RepositoriesUpdated | Should -Be 1
            $result.Results[0].Message | Should -Match 'up to date|Updated successfully'
        }

        It 'Should skip non-Git directory' {
            $nonGitDir = Join-Path -Path $script:TestWorkspace -ChildPath 'not-a-repo'
            New-Item -Path $nonGitDir -ItemType Directory -Force | Out-Null

            $result = Invoke-GitPull -Path $nonGitDir

            $result.RepositoriesSkipped | Should -Be 1
            $result.RepositoriesProcessed | Should -Be 0
        }

        It 'Should handle repository without remote gracefully' {
            $repos = NewTestGitRepository -Path $script:TestWorkspace -Name 'no-remote-repo'

            # This should fail but not throw (no remote configured)
            $result = Invoke-GitPull -Path $repos.RepoPath -Force -ErrorAction SilentlyContinue

            $result.RepositoriesProcessed | Should -Be 1
            $result.RepositoriesFailed | Should -Be 1
        }

        It 'Should respect -WhatIf and not make changes' {
            $repos = NewTestGitRepository -Path $script:TestWorkspace -Name 'whatif-repo' -WithRemote

            # Get the current HEAD before WhatIf (use 2>$null for PS 5.1 compatibility)
            $headBefore = & git -C $repos.RepoPath rev-parse HEAD 2>$null

            Invoke-GitPull -Path $repos.RepoPath -WhatIf

            # HEAD should be unchanged (use 2>$null for PS 5.1 compatibility)
            $headAfter = & git -C $repos.RepoPath rev-parse HEAD 2>$null
            $headAfter | Should -Be $headBefore
        }

        It 'Should use rebase by default' {
            $repos = NewTestGitRepository -Path $script:TestWorkspace -Name 'rebase-repo' -WithRemote

            # The command should succeed (rebase is default)
            $result = Invoke-GitPull -Path $repos.RepoPath

            $result.RepositoriesUpdated | Should -Be 1
        }

        It 'Should support -NoRebase option' {
            $repos = NewTestGitRepository -Path $script:TestWorkspace -Name 'norebase-repo' -WithRemote

            $result = Invoke-GitPull -Path $repos.RepoPath -NoRebase

            $result.RepositoriesUpdated | Should -Be 1
        }

        It 'Should support -Prune option' {
            $repos = NewTestGitRepository -Path $script:TestWorkspace -Name 'prune-repo' -WithRemote

            $result = Invoke-GitPull -Path $repos.RepoPath -Prune

            $result.RepositoriesUpdated | Should -Be 1
        }
    }

    Context 'Multiple Repositories Mode' -Skip:(-not $script:GitAvailable) {
        BeforeEach {
            $script:TestWorkspace = Join-Path -Path $script:TestDir -ChildPath "multi-$(Get-Random)"
            New-Item -Path $script:TestWorkspace -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:TestWorkspace)
            {
                Remove-Item -Path $script:TestWorkspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should process multiple paths' {
            $repos1 = NewTestGitRepository -Path $script:TestWorkspace -Name 'repo1' -WithRemote
            $repos2 = NewTestGitRepository -Path $script:TestWorkspace -Name 'repo2' -WithRemote

            $result = Invoke-GitPull -Path @($repos1.RepoPath, $repos2.RepoPath)

            $result.RepositoriesProcessed | Should -Be 2
            $result.RepositoriesUpdated | Should -Be 2
        }

        It 'Should accept paths from pipeline' {
            $repos1 = NewTestGitRepository -Path $script:TestWorkspace -Name 'pipe-repo1' -WithRemote
            $repos2 = NewTestGitRepository -Path $script:TestWorkspace -Name 'pipe-repo2' -WithRemote

            $result = @($repos1.RepoPath, $repos2.RepoPath) | Invoke-GitPull

            $result.RepositoriesProcessed | Should -Be 2
            $result.RepositoriesUpdated | Should -Be 2
        }

        It 'Should continue with -Force when one repository fails' {
            $repos1 = NewTestGitRepository -Path $script:TestWorkspace -Name 'force-repo1' -WithRemote
            $repos2 = NewTestGitRepository -Path $script:TestWorkspace -Name 'force-repo2'  # No remote - will fail

            $result = Invoke-GitPull -Path @($repos1.RepoPath, $repos2.RepoPath) -Force -ErrorAction SilentlyContinue

            $result.RepositoriesProcessed | Should -Be 2
            $result.RepositoriesUpdated | Should -BeGreaterOrEqual 1
            $result.RepositoriesFailed | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Recursive Mode' -Skip:(-not $script:GitAvailable) {
        BeforeEach {
            $script:TestWorkspace = Join-Path -Path $script:TestDir -ChildPath "recurse-$(Get-Random)"
            New-Item -Path $script:TestWorkspace -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:TestWorkspace)
            {
                Remove-Item -Path $script:TestWorkspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should find and pull all repositories recursively' {
            # Create repositories at different levels
            NewTestGitRepository -Path $script:TestWorkspace -Name 'level1-repo' -WithRemote

            $level2Dir = Join-Path -Path $script:TestWorkspace -ChildPath 'nested'
            New-Item -Path $level2Dir -ItemType Directory -Force | Out-Null
            NewTestGitRepository -Path $level2Dir -Name 'level2-repo' -WithRemote

            $result = Invoke-GitPull -Path $script:TestWorkspace -Recurse

            $result.RepositoriesProcessed | Should -Be 2
            $result.RepositoriesUpdated | Should -Be 2
        }

        It 'Should respect -Depth parameter' {
            # Create repository at level 1
            NewTestGitRepository -Path $script:TestWorkspace -Name 'depth-repo1' -WithRemote

            # Create repository at level 3 (deep nested)
            $deepDir = Join-Path -Path $script:TestWorkspace -ChildPath 'level1'
            $deepDir = Join-Path -Path $deepDir -ChildPath 'level2'
            New-Item -Path $deepDir -ItemType Directory -Force | Out-Null
            NewTestGitRepository -Path $deepDir -Name 'depth-repo2' -WithRemote

            # With depth 1, should only find level 1 repo
            $result = Invoke-GitPull -Path $script:TestWorkspace -Recurse -Depth 1

            $result.RepositoriesProcessed | Should -Be 1
        }

        It 'Should handle empty directory with -Recurse' {
            $emptyDir = Join-Path -Path $script:TestWorkspace -ChildPath 'empty'
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            $result = Invoke-GitPull -Path $emptyDir -Recurse

            $result.RepositoriesProcessed | Should -Be 0
        }

        It 'Should find repository when path is the repository itself with -Recurse' {
            $repos = NewTestGitRepository -Path $script:TestWorkspace -Name 'self-repo' -WithRemote

            $result = Invoke-GitPull -Path $repos.RepoPath -Recurse

            $result.RepositoriesProcessed | Should -Be 1
            $result.RepositoriesUpdated | Should -Be 1
        }
    }

    Context 'Result Object Validation' -Skip:(-not $script:GitAvailable) {
        BeforeEach {
            $script:TestWorkspace = Join-Path -Path $script:TestDir -ChildPath "results-$(Get-Random)"
            New-Item -Path $script:TestWorkspace -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:TestWorkspace)
            {
                Remove-Item -Path $script:TestWorkspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should return detailed results for each repository' {
            $repos = NewTestGitRepository -Path $script:TestWorkspace -Name 'detail-repo' -WithRemote

            $result = Invoke-GitPull -Path $repos.RepoPath

            $result.Results | Should -HaveCount 1
            $result.Results[0].Path | Should -Be $repos.RepoPath
            $result.Results[0].Name | Should -Be 'detail-repo'
            $result.Results[0].Success | Should -BeTrue
            $result.Results[0].Message | Should -Not -BeNullOrEmpty
        }

        It 'Should include error message in results when pull fails' {
            $repos = NewTestGitRepository -Path $script:TestWorkspace -Name 'error-repo'  # No remote

            $result = Invoke-GitPull -Path $repos.RepoPath -Force -ErrorAction SilentlyContinue

            $result.Results[0].Success | Should -BeFalse
            $result.Results[0].Message | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Edge Cases' -Skip:(-not $script:GitAvailable) {
        BeforeEach {
            $script:TestWorkspace = Join-Path -Path $script:TestDir -ChildPath "edge-$(Get-Random)"
            New-Item -Path $script:TestWorkspace -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:TestWorkspace)
            {
                Remove-Item -Path $script:TestWorkspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should handle paths with spaces' {
            $spacePath = Join-Path -Path $script:TestWorkspace -ChildPath 'path with spaces'
            New-Item -Path $spacePath -ItemType Directory -Force | Out-Null
            $repos = NewTestGitRepository -Path $spacePath -Name 'space repo' -WithRemote

            $result = Invoke-GitPull -Path $repos.RepoPath

            $result.RepositoriesUpdated | Should -Be 1
        }

        It 'Should handle mixed valid and invalid paths' {
            $repos = NewTestGitRepository -Path $script:TestWorkspace -Name 'valid-repo' -WithRemote
            $invalidPath = Join-Path -Path $script:TestWorkspace -ChildPath 'does-not-exist'

            $result = Invoke-GitPull -Path @($repos.RepoPath, $invalidPath) -WarningAction SilentlyContinue

            $result.RepositoriesUpdated | Should -Be 1
            $result.RepositoriesSkipped | Should -Be 1
        }
    }
}
