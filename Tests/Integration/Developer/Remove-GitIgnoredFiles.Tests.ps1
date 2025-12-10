BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../../Functions/Developer/Remove-GitIgnoredFiles.ps1"

    # Import test utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"

    # Check if Git is available
    $script:GitAvailable = $null -ne (Get-Command 'git' -ErrorAction SilentlyContinue)
}

Describe 'Remove-GitIgnoredFiles Integration Tests' -Tag 'Integration' {
    BeforeAll {
        # Create base test directory
        $script:TestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "git-cleanup-integration-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:TestRoot)
        {
            Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Single Repository Mode' {
        BeforeEach {
            # Create a test repository
            $script:RepoPath = Join-Path -Path $script:TestRoot -ChildPath "test-repo-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:RepoPath -Force | Out-Null

            # Initialize Git repository
            $null = & git -C $script:RepoPath init 2>&1
            $null = & git -C $script:RepoPath config user.email 'test@example.com' 2>&1
            $null = & git -C $script:RepoPath config user.name 'Test User' 2>&1
            $null = & git -C $script:RepoPath config core.autocrlf false 2>&1

            # Create .gitignore
            @'
*.log
*.tmp
build/
temp/
'@ | Set-Content (Join-Path -Path $script:RepoPath -ChildPath '.gitignore')

            # Add and commit .gitignore
            $null = & git -C $script:RepoPath add .gitignore 2>&1
            $null = & git -C $script:RepoPath commit -m 'Initial commit' 2>&1
        }

        AfterEach {
            if (Test-Path $script:RepoPath)
            {
                Remove-Item -Path $script:RepoPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should remove ignored files' {
            # Create ignored files
            'test log' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'test.log')
            'test tmp' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'test.tmp')

            # Run cleanup
            $Result = Remove-GitIgnoredFiles -Path $script:RepoPath

            # Verify files are removed
            Test-Path (Join-Path -Path $script:RepoPath -ChildPath 'test.log') | Should -BeFalse
            Test-Path (Join-Path -Path $script:RepoPath -ChildPath 'test.tmp') | Should -BeFalse
            $Result.FilesRemoved | Should -Be 2
        }

        It 'Should remove ignored directories' {
            # Create ignored directory with files
            $BuildDir = Join-Path -Path $script:RepoPath -ChildPath 'build'
            New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
            'artifact' | Out-File (Join-Path -Path $BuildDir -ChildPath 'output.dll')

            # Run cleanup
            $Result = Remove-GitIgnoredFiles -Path $script:RepoPath

            # Verify directory is removed
            Test-Path $BuildDir | Should -BeFalse
            $Result.DirectoriesRemoved | Should -Be 1
        }

        It 'Should not remove tracked files' {
            # Create a tracked file
            'readme content' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'README.md')
            $null = & git -C $script:RepoPath add 'README.md' 2>&1
            $null = & git -C $script:RepoPath commit -m 'Add README' 2>&1

            # Create ignored file
            'log' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'test.log')

            # Run cleanup
            $null = Remove-GitIgnoredFiles -Path $script:RepoPath

            # Verify tracked file still exists
            Test-Path (Join-Path -Path $script:RepoPath -ChildPath 'README.md') | Should -BeTrue
            Test-Path (Join-Path -Path $script:RepoPath -ChildPath 'test.log') | Should -BeFalse
        }

        It 'Should not remove untracked files by default' {
            # Create untracked file (not in .gitignore)
            'untracked' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'untracked.txt')

            # Create ignored file
            'log' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'test.log')

            # Run cleanup without -IncludeUntracked
            $null = Remove-GitIgnoredFiles -Path $script:RepoPath

            # Verify untracked file still exists, ignored file removed
            Test-Path (Join-Path -Path $script:RepoPath -ChildPath 'untracked.txt') | Should -BeTrue
            Test-Path (Join-Path -Path $script:RepoPath -ChildPath 'test.log') | Should -BeFalse
        }

        It 'Should remove untracked files with -IncludeUntracked' {
            # Create untracked file
            'untracked' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'untracked.txt')

            # Create ignored file
            'log' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'test.log')

            # Run cleanup with -IncludeUntracked
            $Result = Remove-GitIgnoredFiles -Path $script:RepoPath -IncludeUntracked

            # Verify both files are removed
            Test-Path (Join-Path -Path $script:RepoPath -ChildPath 'untracked.txt') | Should -BeFalse
            Test-Path (Join-Path -Path $script:RepoPath -ChildPath 'test.log') | Should -BeFalse
            $Result.FilesRemoved | Should -Be 2
        }

        It 'Should respect -WhatIf parameter' {
            # Create ignored files
            'test log' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'test.log')

            # Run with -WhatIf
            $null = Remove-GitIgnoredFiles -Path $script:RepoPath -WhatIf

            # Verify file still exists
            Test-Path (Join-Path -Path $script:RepoPath -ChildPath 'test.log') | Should -BeTrue
        }

        It 'Should handle repository with no ignored files' {
            # Run cleanup on clean repository
            $Result = Remove-GitIgnoredFiles -Path $script:RepoPath

            # Should complete successfully with no removals
            $Result.FilesRemoved | Should -Be 0
            $Result.DirectoriesRemoved | Should -Be 0
            $Result.Errors | Should -Be 0
        }

        It 'Should calculate space freed' {
            # Create ignored file with known size
            $TestFile = Join-Path -Path $script:RepoPath -ChildPath 'test.log'
            'x' * 1000 | Out-File $TestFile -NoNewline

            # Run cleanup
            $Result = Remove-GitIgnoredFiles -Path $script:RepoPath

            # Verify space was calculated (not "Not calculated")
            $Result.TotalSpaceFreed | Should -Not -Match 'Not calculated'
            $Result.TotalSpaceFreed | Should -Not -Be '0 bytes'
        }

        It 'Should skip size calculation with -NoSizeCalculation' {
            # Create ignored file
            'test log' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'test.log')

            # Run cleanup with -NoSizeCalculation
            $Result = Remove-GitIgnoredFiles -Path $script:RepoPath -NoSizeCalculation

            # Verify size calculation was skipped
            $Result.TotalSpaceFreed | Should -Match 'Not calculated'
            $Result.FilesRemoved | Should -Be 1
        }

        It 'Should error when path is not a Git repository' {
            $NonGitPath = Join-Path -Path $script:TestRoot -ChildPath "not-a-repo-$(Get-Random)"
            New-Item -ItemType Directory -Path $NonGitPath -Force | Out-Null

            try
            {
                # Should throw an error
                { Remove-GitIgnoredFiles -Path $NonGitPath -ErrorAction Stop } | Should -Throw '*git repository*'
            }
            finally
            {
                Remove-Item -Path $NonGitPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Recursive Mode - Multiple Repositories' {
        BeforeEach {
            # Create workspace directory
            $script:WorkspacePath = Join-Path -Path $script:TestRoot -ChildPath "workspace-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:WorkspacePath -Force | Out-Null

            # Create multiple repositories
            $script:Repo1 = Join-Path -Path $script:WorkspacePath -ChildPath 'project1'
            $script:Repo2 = Join-Path -Path $script:WorkspacePath -ChildPath 'project2'
            $nestedRepo = Join-Path -Path $script:WorkspacePath -ChildPath 'nested'
            $script:Repo3 = Join-Path -Path $nestedRepo -ChildPath 'project3'

            foreach ($repoPath in @($script:Repo1, $script:Repo2, $script:Repo3))
            {
                New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
                $null = & git -C $repoPath init 2>&1
                $null = & git -C $repoPath config user.email 'test@example.com' 2>&1
                $null = & git -C $repoPath config user.name 'Test User' 2>&1
                $null = & git -C $repoPath config core.autocrlf false 2>&1

                # Create .gitignore
                '*.log' | Set-Content (Join-Path -Path $repoPath -ChildPath '.gitignore')
                $null = & git -C $repoPath add .gitignore 2>&1
                $null = & git -C $repoPath commit -m 'Initial commit' 2>&1
            }
        }

        AfterEach {
            if (Test-Path $script:WorkspacePath)
            {
                Remove-Item -Path $script:WorkspacePath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should find and clean multiple repositories' {
            # Create ignored files in each repository
            'log1' | Out-File (Join-Path -Path $script:Repo1 -ChildPath 'test.log')
            'log2' | Out-File (Join-Path -Path $script:Repo2 -ChildPath 'test.log')
            'log3' | Out-File (Join-Path -Path $script:Repo3 -ChildPath 'test.log')

            # Run cleanup with -Recurse
            $Result = Remove-GitIgnoredFiles -Path $script:WorkspacePath -Recurse

            # Verify all files are removed
            Test-Path (Join-Path -Path $script:Repo1 -ChildPath 'test.log') | Should -BeFalse
            Test-Path (Join-Path -Path $script:Repo2 -ChildPath 'test.log') | Should -BeFalse
            Test-Path (Join-Path -Path $script:Repo3 -ChildPath 'test.log') | Should -BeFalse
            $Result.RepositoriesProcessed | Should -Be 3
            $Result.FilesRemoved | Should -Be 3
        }

        It 'Should handle repositories with no ignored files' {
            # Create ignored file in only one repository
            'log' | Out-File (Join-Path -Path $script:Repo1 -ChildPath 'test.log')

            # Run cleanup with -Recurse
            $Result = Remove-GitIgnoredFiles -Path $script:WorkspacePath -Recurse

            # Verify correct statistics
            $Result.RepositoriesProcessed | Should -Be 1
            $Result.FilesRemoved | Should -Be 1
        }

        It 'Should respect -WhatIf in recursive mode' {
            # Create ignored files
            'log1' | Out-File (Join-Path -Path $script:Repo1 -ChildPath 'test.log')
            'log2' | Out-File (Join-Path -Path $script:Repo2 -ChildPath 'test.log')

            # Run with -WhatIf
            $null = Remove-GitIgnoredFiles -Path $script:WorkspacePath -Recurse -WhatIf

            # Verify files still exist
            Test-Path (Join-Path -Path $script:Repo1 -ChildPath 'test.log') | Should -BeTrue
            Test-Path (Join-Path -Path $script:Repo2 -ChildPath 'test.log') | Should -BeTrue
        }

        It 'Should handle workspace with no repositories' {
            # Create directory with no Git repositories
            $EmptyWorkspace = Join-Path -Path $script:TestRoot -ChildPath "empty-workspace-$(Get-Random)"
            New-Item -ItemType Directory -Path $EmptyWorkspace -Force | Out-Null

            try
            {
                # Should complete without errors but report no repositories
                $Result = Remove-GitIgnoredFiles -Path $EmptyWorkspace -Recurse

                $Result.RepositoriesProcessed | Should -Be 0
                $Result.FilesRemoved | Should -Be 0
                $Result.Errors | Should -Be 0
            }
            finally
            {
                Remove-Item -Path $EmptyWorkspace -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should calculate total space freed across all repositories' {
            # Create ignored files with known sizes
            'x' * 500 | Out-File (Join-Path -Path $script:Repo1 -ChildPath 'test.log') -NoNewline
            'x' * 500 | Out-File (Join-Path -Path $script:Repo2 -ChildPath 'test.log') -NoNewline

            # Run cleanup
            $Result = Remove-GitIgnoredFiles -Path $script:WorkspacePath -Recurse

            # Verify cumulative space calculation
            $Result.TotalSpaceFreed | Should -Not -Match 'Not calculated'
            $Result.TotalSpaceFreed | Should -Not -Be '0 bytes'
            $Result.RepositoriesProcessed | Should -Be 2
        }
    }

    Context 'Path Resolution' {
        BeforeEach {
            $script:RepoPath = Join-Path -Path $script:TestRoot -ChildPath "path-test-repo-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:RepoPath -Force | Out-Null

            $null = & git -C $script:RepoPath init 2>&1
            $null = & git -C $script:RepoPath config user.email 'test@example.com' 2>&1
            $null = & git -C $script:RepoPath config user.name 'Test User' 2>&1
            $null = & git -C $script:RepoPath config core.autocrlf false 2>&1

            '*.log' | Set-Content (Join-Path -Path $script:RepoPath -ChildPath '.gitignore')
            $null = & git -C $script:RepoPath add .gitignore 2>&1
            $null = & git -C $script:RepoPath commit -m 'Initial commit' 2>&1
        }

        AfterEach {
            if (Test-Path $script:RepoPath)
            {
                Remove-Item -Path $script:RepoPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should resolve relative paths' {
            # Create ignored file
            'log' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'test.log')

            # Change to parent directory
            Push-Location (Split-Path $script:RepoPath -Parent)
            try
            {
                # Use relative path
                $RelativePath = Split-Path $script:RepoPath -Leaf
                $Result = Remove-GitIgnoredFiles -Path $RelativePath

                $Result.FilesRemoved | Should -Be 1
            }
            finally
            {
                Pop-Location
            }
        }

        It 'Should handle current directory (default path)' {
            # Create ignored file
            'log' | Out-File (Join-Path -Path $script:RepoPath -ChildPath 'test.log')

            # Change to repository directory
            Push-Location $script:RepoPath
            try
            {
                # Run without specifying path (should use current directory)
                $Result = Remove-GitIgnoredFiles

                $Result.FilesRemoved | Should -Be 1
            }
            finally
            {
                Pop-Location
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle invalid path' {
            $InvalidPath = Join-Path -Path $script:TestRoot -ChildPath 'nonexistent-path'

            # Should handle gracefully
            { Remove-GitIgnoredFiles -Path $InvalidPath -ErrorAction Stop } | Should -Throw
        }

        It 'Should return error count when issues occur' {
            # This is a basic check - specific error scenarios would be tested here
            $Result = Remove-GitIgnoredFiles -Path $script:TestRoot -Recurse

            # Result should have Errors property
            $Result.PSObject.Properties.Name | Should -Contain 'Errors'
            $Result.Errors | Should -BeOfType [int]
        }
    }
}
