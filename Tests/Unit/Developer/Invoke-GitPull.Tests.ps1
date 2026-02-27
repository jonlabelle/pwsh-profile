#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Invoke-GitPull function.

.DESCRIPTION
    Tests the Invoke-GitPull function which performs git pull operations on Git repositories.
    Validates parameter handling, path resolution, and error handling.

.NOTES
    These tests verify the function works correctly with PowerShell 5.1+ on all platforms.
    Tests include: parameter validation, path handling, Git availability checks, and WhatIf support.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function
    . "$PSScriptRoot/../../../Functions/Developer/Invoke-GitPull.ps1"

    # Check if Git is available
    $script:GitAvailable = $null -ne (Get-Command 'git' -ErrorAction SilentlyContinue)
}

Describe 'Invoke-GitPull' {
    BeforeAll {
        # Use system temp directory for test isolation
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "gitpull-unit-$(Get-Random)"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:TestDir)
        {
            Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Parameter Validation' {
        It 'Should have Path parameter that accepts pipeline input' {
            $command = Get-Command -Name 'Invoke-GitPull'
            $pathParam = $command.Parameters['Path']

            $pathParam | Should -Not -BeNullOrEmpty
            $pathParam.Attributes | Where-Object { $_ -is [Parameter] } |
            ForEach-Object { $_.ValueFromPipeline } | Should -Contain $true
        }

        It 'Should have Path parameter that accepts FullName property' {
            $command = Get-Command -Name 'Invoke-GitPull'
            $pathParam = $command.Parameters['Path']

            $pathParam.Aliases | Should -Contain 'FullName'
        }

        It 'Should have Recurse switch parameter' {
            $command = Get-Command -Name 'Invoke-GitPull'
            $command.Parameters['Recurse'].SwitchParameter | Should -BeTrue
        }

        It 'Should have Depth parameter with valid range' {
            $command = Get-Command -Name 'Invoke-GitPull'
            $depthParam = $command.Parameters['Depth']

            $depthParam | Should -Not -BeNullOrEmpty
            $depthParam.ParameterType | Should -Be ([Int])
        }

        It 'Should have NoRebase switch parameter' {
            $command = Get-Command -Name 'Invoke-GitPull'
            $command.Parameters['NoRebase'].SwitchParameter | Should -BeTrue
        }

        It 'Should have Prune switch parameter' {
            $command = Get-Command -Name 'Invoke-GitPull'
            $command.Parameters['Prune'].SwitchParameter | Should -BeTrue
        }

        It 'Should have Force switch parameter' {
            $command = Get-Command -Name 'Invoke-GitPull'
            $command.Parameters['Force'].SwitchParameter | Should -BeTrue
        }

        It 'Should support ShouldProcess (WhatIf/Confirm)' {
            $command = Get-Command -Name 'Invoke-GitPull'
            $command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
            $command.Parameters.ContainsKey('Confirm') | Should -BeTrue
        }
    }

    Context 'Path Resolution' {
        It 'Should handle non-existent path gracefully' {
            $nonExistentPath = Join-Path -Path $script:TestDir -ChildPath 'does-not-exist'

            # Should warn but not throw
            $result = Invoke-GitPull -Path $nonExistentPath -WarningAction SilentlyContinue

            $result.RepositoriesSkipped | Should -Be 1
            $result.RepositoriesProcessed | Should -Be 0
        }

        It 'Should handle file path (not directory) gracefully' {
            $filePath = Join-Path -Path $script:TestDir -ChildPath 'testfile.txt'
            'test content' | Out-File -FilePath $filePath

            try
            {
                $result = Invoke-GitPull -Path $filePath -WarningAction SilentlyContinue

                $result.RepositoriesSkipped | Should -Be 1
                $result.RepositoriesProcessed | Should -Be 0
            }
            finally
            {
                Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should skip directory without .git folder' {
            $nonGitDir = Join-Path -Path $script:TestDir -ChildPath "not-a-repo-$(Get-Random)"
            New-Item -Path $nonGitDir -ItemType Directory -Force | Out-Null

            try
            {
                $result = Invoke-GitPull -Path $nonGitDir

                $result.RepositoriesSkipped | Should -Be 1
                $result.RepositoriesProcessed | Should -Be 0
            }
            finally
            {
                Remove-Item -Path $nonGitDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should accept multiple paths' {
            $dir1 = Join-Path -Path $script:TestDir -ChildPath "multi1-$(Get-Random)"
            $dir2 = Join-Path -Path $script:TestDir -ChildPath "multi2-$(Get-Random)"
            New-Item -Path $dir1 -ItemType Directory -Force | Out-Null
            New-Item -Path $dir2 -ItemType Directory -Force | Out-Null

            try
            {
                $result = Invoke-GitPull -Path @($dir1, $dir2)

                $result.RepositoriesSkipped | Should -Be 2
            }
            finally
            {
                Remove-Item -Path $dir1 -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $dir2 -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Output Object' {
        It 'Should return PSCustomObject with expected properties' {
            $nonGitDir = Join-Path -Path $script:TestDir -ChildPath "output-test-$(Get-Random)"
            New-Item -Path $nonGitDir -ItemType Directory -Force | Out-Null

            try
            {
                $result = Invoke-GitPull -Path $nonGitDir

                $result | Should -BeOfType [PSCustomObject]
                $result.PSObject.Properties.Name | Should -Contain 'RepositoriesProcessed'
                $result.PSObject.Properties.Name | Should -Contain 'RepositoriesUpdated'
                $result.PSObject.Properties.Name | Should -Contain 'RepositoriesSkipped'
                $result.PSObject.Properties.Name | Should -Contain 'RepositoriesFailed'
                $result.PSObject.Properties.Name | Should -Contain 'Results'
            }
            finally
            {
                Remove-Item -Path $nonGitDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should have Results as array or empty collection' {
            $nonGitDir = Join-Path -Path $script:TestDir -ChildPath "results-test-$(Get-Random)"
            New-Item -Path $nonGitDir -ItemType Directory -Force | Out-Null

            try
            {
                $result = Invoke-GitPull -Path $nonGitDir

                # Results should be an array (possibly empty)
                $result.Results.GetType().IsArray -or $result.Results.Count -eq 0 | Should -BeTrue
            }
            finally
            {
                Remove-Item -Path $nonGitDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'WhatIf Support' {
        It 'Should support -WhatIf parameter without making changes' -Skip:(-not $script:GitAvailable) {
            # Create a minimal Git repo for WhatIf test
            $repoPath = Join-Path -Path $script:TestDir -ChildPath "whatif-repo-$(Get-Random)"
            New-Item -Path $repoPath -ItemType Directory -Force | Out-Null

            try
            {
                # Initialize a Git repo using Set-Location and 2>&1 for reliable PS 5.1 behavior
                # PowerShell 5.1 treats stderr output from native commands as errors in some contexts
                $originalLocation = Get-Location
                Set-Location -Path $repoPath
                try
                {
                    $null = & git init 2>&1
                    $null = & git config user.email 'test@example.com' 2>&1
                    $null = & git config user.name 'TestUser' 2>&1
                }
                finally
                {
                    Set-Location -Path $originalLocation
                }

                # WhatIf should not throw and should return result
                $result = Invoke-GitPull -Path $repoPath -WhatIf

                $result | Should -Not -BeNullOrEmpty
            }
            finally
            {
                Remove-Item -Path $repoPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Recursive Mode' {
        It 'Should find no repositories in empty directory with -Recurse' {
            $emptyDir = Join-Path -Path $script:TestDir -ChildPath "empty-recurse-$(Get-Random)"
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            try
            {
                $result = Invoke-GitPull -Path $emptyDir -Recurse

                $result.RepositoriesProcessed | Should -Be 0
            }
            finally
            {
                Remove-Item -Path $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Git Availability' {
        It 'Should throw when Git is not available' {
            # Mock Get-Command to return null for git
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'git' }

            # Re-dot-source the function to pick up the mock
            . "$PSScriptRoot/../../../Functions/Developer/Invoke-GitPull.ps1"

            { Invoke-GitPull } | Should -Throw '*Git*not*'

            # Restore the function
            . "$PSScriptRoot/../../../Functions/Developer/Invoke-GitPull.ps1"
        }
    }
}
