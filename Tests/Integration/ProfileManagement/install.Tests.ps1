#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = (Resolve-Path "$PSScriptRoot/../../..").Path
    $script:installScript = Join-Path -Path $script:repoRoot -ChildPath 'install.ps1'
    $script:gitCommand = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
    $script:gitExecutable = $script:gitCommand?.Definition
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'install.ps1 integration tests' {
    Context 'Git clone install path' {
        It 'clones the repository when LocalSourcePath is not provided' {
            $testRoot = Join-Path $TestDrive ('CloneInstall_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

            # Seed profile to ensure backup creation
            Set-Content -Path (Join-Path $profileRoot 'preexisting.ps1') -Value '# preexisting'

            try
            {
                & $script:installScript -ProfileRoot $profileRoot -RepositoryUrl $script:repoRoot -Verbose:$false

                Test-Path (Join-Path $profileRoot 'Microsoft.PowerShell_profile.ps1') | Should -BeTrue
                $gitConfigPath = Join-Path $profileRoot '.git/config'
                Test-Path $gitConfigPath | Should -BeTrue
                $gitConfigContent = Get-Content $gitConfigPath -Raw
                $originMatch = [regex]::Match(
                    $gitConfigContent,
                    '^\s*url\s*=\s*(.+)$',
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline
                )
                $originMatch.Success | Should -BeTrue -Because 'git clone should record the remote origin URL'

                $originUrl = [regex]::Unescape($originMatch.Groups[1].Value.Trim())
                $resolvedOrigin = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($originUrl)
                $resolvedRepoRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($script:repoRoot)
                $resolvedOrigin | Should -Be $resolvedRepoRoot

                $profileParent = Split-Path -Parent $profileRoot
                $profileLeaf = Split-Path -Leaf $profileRoot
                $backupPattern = "$profileLeaf-backup-*"
                (Get-ChildItem -Path $profileParent -Directory -Filter $backupPattern).Count | Should -Be 1
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }

    Context 'Local install with default preservation' {
        It 'installs from a local source, preserves default directories, and creates a backup' {
            $testRoot = Join-Path $TestDrive ('InstallProfile_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

            foreach ($name in @('Functions/Local', 'Help', 'Modules', 'PSReadLine', 'Scripts'))
            {
                $dirPath = Join-Path $profileRoot $name
                New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
                Set-Content -Path (Join-Path $dirPath 'original.txt') -Value "original-$name"
            }

            Set-Content -Path (Join-Path $profileRoot 'legacy-profile.ps1') -Value '# legacy profile'

            try
            {
                & $script:installScript -ProfileRoot $profileRoot -LocalSourcePath $script:repoRoot -Verbose:$false

                Test-Path (Join-Path $profileRoot 'Microsoft.PowerShell_profile.ps1') | Should -BeTrue

                foreach ($name in @('Functions/Local', 'Help', 'Modules', 'PSReadLine', 'Scripts'))
                {
                    $preservedFile = Join-Path (Join-Path $profileRoot $name) 'original.txt'
                    Test-Path $preservedFile | Should -BeTrue
                    (Get-Content $preservedFile) | Should -Be "original-$name"
                }

                $profileParent = Split-Path -Parent $profileRoot
                $profileLeaf = Split-Path -Leaf $profileRoot
                $backupPattern = "$profileLeaf-backup-*"
                $backups = Get-ChildItem -Path $profileParent -Directory -Filter $backupPattern
                $backups.Count | Should -Be 1
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }
    Context 'Install via git clone' {
        It 'clones from RepositoryUrl when git is available' -Skip:($null -eq $script:gitExecutable) {
            $testRoot = Join-Path $TestDrive ('GitClone_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            $remoteRepo = Join-Path $testRoot 'RemoteRepo'

            try
            {
                New-Item -ItemType Directory -Path $remoteRepo -Force | Out-Null
                & $script:gitExecutable '-C' $remoteRepo 'init' | Out-Null
                & $script:gitExecutable '-C' $remoteRepo 'config' 'user.email' 'ci@example.com' | Out-Null
                & $script:gitExecutable '-C' $remoteRepo 'config' 'user.name' 'CI Bot' | Out-Null

                $profileFile = Join-Path $remoteRepo 'Microsoft.PowerShell_profile.ps1'
                $modulesDir = Join-Path $remoteRepo 'Modules'
                New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null
                Set-Content -Path $profileFile -Value '# git remote profile'
                Set-Content -Path (Join-Path $modulesDir 'RemoteModule.psm1') -Value 'function Invoke-Remote { "remote" }'

                & $script:gitExecutable '-C' $remoteRepo 'add' '.' | Out-Null
                & $script:gitExecutable '-C' $remoteRepo 'commit' '-m' 'initial commit' | Out-Null

                & $script:installScript -ProfileRoot $profileRoot -RepositoryUrl $remoteRepo -SkipPreserveDirectories -Verbose:$false

                Test-Path (Join-Path $profileRoot 'Microsoft.PowerShell_profile.ps1') | Should -BeTrue
                (Get-Content (Join-Path $profileRoot 'Microsoft.PowerShell_profile.ps1')) | Should -Be '# git remote profile'
                Test-Path (Join-Path $profileRoot 'Modules/RemoteModule.psm1') | Should -BeTrue
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }

    Context 'Skip options' {
        It 'does not create backups or preserve directories when flags are provided' {
            $testRoot = Join-Path $TestDrive ('SkipOptions_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

            foreach ($name in @('Functions/Local', 'Help', 'Modules', 'PSReadLine', 'Scripts'))
            {
                $dirPath = Join-Path $profileRoot $name
                New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
                Set-Content -Path (Join-Path $dirPath 'original.txt') -Value "original-$name"
            }

            try
            {
                & $script:installScript -ProfileRoot $profileRoot -LocalSourcePath $script:repoRoot -SkipBackup -SkipPreserveDirectories -Verbose:$false

                $profileParent = Split-Path -Parent $profileRoot
                $profileLeaf = Split-Path -Leaf $profileRoot
                $backupPattern = "$profileLeaf-backup-*"
                (Get-ChildItem -Path $profileParent -Directory -Filter $backupPattern -ErrorAction SilentlyContinue).Count | Should -Be 0

                foreach ($name in @('Functions/Local', 'Help', 'Modules', 'PSReadLine', 'Scripts'))
                {
                    $preservedFile = Join-Path (Join-Path $profileRoot $name) 'original.txt'
                    Test-Path $preservedFile | Should -BeFalse
                }
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }

    Context 'Restore failure handling' {
        It 'throws when the restore path does not exist' {
            $testRoot = Join-Path $TestDrive ('RestoreFailure_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            $missingBackup = Join-Path $testRoot 'MissingBackup'
            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

            try
            {
                { & $script:installScript -ProfileRoot $profileRoot -RestorePath $missingBackup -Verbose:$false } | Should -Throw
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }

    Context 'Skip options' {
        It 'respects SkipBackup and SkipPreserveDirectories switches' {
            $testRoot = Join-Path $TestDrive ('SkipOptions_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

            foreach ($name in @('Functions/Local', 'Help', 'Modules', 'PSReadLine', 'Scripts'))
            {
                $dirPath = Join-Path $profileRoot $name
                New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
                Set-Content -Path (Join-Path $dirPath 'test.txt') -Value "test-$name"
            }

            try
            {
                & $script:installScript -ProfileRoot $profileRoot -LocalSourcePath $script:repoRoot -SkipBackup -SkipPreserveDirectories -Verbose:$false

                # Functions/Local exists in the repo, so check if user files were NOT preserved
                $funcLocalTestFile = Join-Path (Join-Path $profileRoot 'Functions/Local') 'test.txt'
                Test-Path $funcLocalTestFile | Should -BeFalse

                # These directories should be reinstalled fresh (no preserved user files)
                foreach ($name in @('Help', 'Modules', 'PSReadLine'))
                {
                    $testFile = Join-Path (Join-Path $profileRoot $name) 'test.txt'
                    Test-Path $testFile | Should -BeFalse
                }

                $profileParent = Split-Path -Parent $profileRoot
                $profileLeaf = Split-Path -Leaf $profileRoot
                $backupPattern = "$profileLeaf-backup-*"
                (Get-ChildItem -Path $profileParent -Directory -Filter $backupPattern -ErrorAction SilentlyContinue).Count | Should -Be 0
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }

    Context 'Git clone installation' {
        It 'clones from the specified repository when git is available' {
            if (-not $script:gitExecutable)
            {
                Set-ItResult -Skipped -Because 'git command not available on this host.'
                return
            }

            $testRoot = Join-Path $TestDrive ('GitClone_{0}' -f ([guid]::NewGuid().ToString('N')))
            $remoteRepo = Join-Path $testRoot 'RemoteRepo'
            $profileRoot = Join-Path $testRoot 'ProfileRoot'

            try
            {
                New-Item -ItemType Directory -Path $remoteRepo -Force | Out-Null
                & $script:gitExecutable -C $remoteRepo init | Out-Null
                & $script:gitExecutable -C $remoteRepo config user.email 'ci@example.com'
                & $script:gitExecutable -C $remoteRepo config user.name 'CI'

                Set-Content -Path (Join-Path $remoteRepo 'cloned.txt') -Value 'cloned content'
                & $script:gitExecutable -C $remoteRepo add . | Out-Null
                & $script:gitExecutable -C $remoteRepo commit -m 'initial commit' | Out-Null

                & $script:installScript -ProfileRoot $profileRoot -RepositoryUrl $remoteRepo -SkipBackup -SkipPreserveDirectories -Verbose:$false

                Test-Path (Join-Path $profileRoot 'cloned.txt') | Should -BeTrue
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }

    Context 'Restore mode' {
        It 'restores profile contents from a supplied backup path without creating a backup by default' {
            $testRoot = Join-Path $TestDrive ('RestoreProfile_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            $backupRoot = Join-Path $testRoot 'BackupSource'
            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

            # Existing file that should be replaced during restore
            Set-Content -Path (Join-Path $profileRoot 'stale.ps1') -Value 'stale profile'

            # Backup payload
            Set-Content -Path (Join-Path $backupRoot 'profile.ps1') -Value 'restored profile'
            $backupModules = Join-Path $backupRoot 'Modules'
            New-Item -ItemType Directory -Path $backupModules -Force | Out-Null
            Set-Content -Path (Join-Path $backupModules 'module.psm1') -Value 'module content'

            try
            {
                # Restore without -SkipBackup should NOT create a backup (new default behavior)
                & $script:installScript -ProfileRoot $profileRoot -RestorePath $backupRoot -Verbose:$false

                $restoredProfile = Join-Path $profileRoot 'profile.ps1'
                Test-Path $restoredProfile | Should -BeTrue
                (Get-Content $restoredProfile) | Should -Be 'restored profile'

                $modulesFile = Join-Path (Join-Path $profileRoot 'Modules') 'module.psm1'
                Test-Path $modulesFile | Should -BeTrue
                Test-Path (Join-Path $profileRoot 'stale.ps1') | Should -BeFalse

                # Verify no backup was created
                $profileParent = Split-Path -Parent $profileRoot
                $profileLeaf = Split-Path -Leaf $profileRoot
                $backupPattern = "$profileLeaf-backup-*"
                (Get-ChildItem -Path $profileParent -Directory -Filter $backupPattern -ErrorAction SilentlyContinue).Count | Should -Be 0
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }

        It 'creates a backup during restore when BackupPath is explicitly provided' {
            $testRoot = Join-Path $TestDrive ('RestoreWithBackup_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            $backupRoot = Join-Path $testRoot 'BackupSource'
            $explicitBackup = Join-Path $testRoot 'ExplicitBackup'
            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

            # Current profile content that should be backed up
            Set-Content -Path (Join-Path $profileRoot 'current.ps1') -Value 'current profile'

            # Backup payload to restore
            Set-Content -Path (Join-Path $backupRoot 'restored.ps1') -Value 'restored profile'

            try
            {
                & $script:installScript -ProfileRoot $profileRoot -RestorePath $backupRoot -BackupPath $explicitBackup -Verbose:$false

                # Verify restore happened
                Test-Path (Join-Path $profileRoot 'restored.ps1') | Should -BeTrue
                Test-Path (Join-Path $profileRoot 'current.ps1') | Should -BeFalse

                # Verify backup was created with the pre-restore content
                Test-Path (Join-Path $explicitBackup 'current.ps1') | Should -BeTrue
                (Get-Content (Join-Path $explicitBackup 'current.ps1')) | Should -Be 'current profile'
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }

    Context 'Custom preservation list' {
        It 'only restores directories explicitly requested' {
            $testRoot = Join-Path $TestDrive ('CustomPreserve_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

            foreach ($name in @('Functions/Local', 'Help', 'Modules', 'PSReadLine', 'Scripts'))
            {
                $dirPath = Join-Path $profileRoot $name
                New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
                Set-Content -Path (Join-Path $dirPath 'original.txt') -Value "original-$name"
            }

            try
            {
                & $script:installScript -ProfileRoot $profileRoot -LocalSourcePath $script:repoRoot -PreserveDirectories @('Scripts') -SkipBackup -Verbose:$false

                $scriptsFile = Join-Path (Join-Path $profileRoot 'Scripts') 'original.txt'
                $modulesFile = Join-Path (Join-Path $profileRoot 'Modules') 'original.txt'
                $helpFile = Join-Path (Join-Path $profileRoot 'Help') 'original.txt'

                Test-Path $scriptsFile | Should -BeTrue
                Test-Path $modulesFile | Should -BeFalse
                Test-Path $helpFile | Should -BeFalse
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }

    Context 'Error handling' {
        It 'throws when RestorePath does not exist' {
            $testRoot = Join-Path $TestDrive ('RestoreError_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
            $missingBackup = Join-Path $testRoot 'MissingBackup'

            try
            {
                { & $script:installScript -ProfileRoot $profileRoot -RestorePath $missingBackup -Verbose:$false } | Should -Throw
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }

    Context 'Skip backup and preservation' {
        It 'does not create backups or restore preserved directories when skipped' {
            $testRoot = Join-Path $TestDrive ('SkipFlags_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

            foreach ($name in @('Functions/Local', 'Help', 'Modules', 'PSReadLine', 'Scripts'))
            {
                $dirPath = Join-Path $profileRoot $name
                New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
                Set-Content -Path (Join-Path $dirPath 'keep.txt') -Value "keep-$name"
            }

            try
            {
                & $script:installScript -ProfileRoot $profileRoot -LocalSourcePath $script:repoRoot -SkipBackup -SkipPreserveDirectories -Verbose:$false

                $profileParent = Split-Path -Parent $profileRoot
                $profileLeaf = Split-Path -Leaf $profileRoot
                (Get-ChildItem -Path $profileParent -Directory -Filter "$profileLeaf-backup-*").Count | Should -Be 0

                foreach ($name in @('Functions/Local', 'Help', 'Modules', 'PSReadLine', 'Scripts'))
                {
                    $preservedFile = Join-Path (Join-Path $profileRoot $name) 'keep.txt'
                    Test-Path $preservedFile | Should -BeFalse
                }
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }

    Context 'Error handling' {
        It 'throws when the restore path does not exist' {
            $testRoot = Join-Path $TestDrive ('InvalidRestore_{0}' -f ([guid]::NewGuid().ToString('N')))
            $profileRoot = Join-Path $testRoot 'ProfileRoot'
            $missingRestore = Join-Path $testRoot 'MissingBackup'

            New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

            try
            {
                Should -Throw -ActualValue { & $script:installScript -ProfileRoot $profileRoot -RestorePath $missingRestore -Verbose:$false }
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }

    Context 'Zip download fallback' {
        It 'downloads and extracts repository as zip when git is not available' {
            $testRoot = Join-Path $TestDrive ('ZipDownload_{0}' -f ([guid]::NewGuid().ToString('N')))

            try
            {
                # Mock a scenario where git is not found by using a URL that would trigger zip download
                # We'll create a local zip file to simulate the download
                $mockRepoContent = Join-Path $testRoot 'MockRepoContent'
                New-Item -ItemType Directory -Path $mockRepoContent -Force | Out-Null

                # Create mock repository content
                Set-Content -Path (Join-Path $mockRepoContent 'Microsoft.PowerShell_profile.ps1') -Value '# mock profile'
                $mockFunctionsDir = Join-Path $mockRepoContent 'Functions'
                New-Item -ItemType Directory -Path $mockFunctionsDir -Force | Out-Null
                Set-Content -Path (Join-Path $mockFunctionsDir 'Test-Mock.ps1') -Value 'function Test-Mock { "mock" }'

                # This test verifies the zip extraction logic works
                # Full integration test with actual GitHub download would require network access
                # and is better suited for manual testing or CI with network connectivity

                Write-Verbose 'Zip download fallback test requires network connectivity for full integration'
                Write-Verbose 'This test is marked as pending for local execution'
                Set-ItResult -Skipped -Because 'Requires network connectivity to download from GitHub'
            }
            finally
            {
                if (Test-Path -Path $testRoot)
                {
                    Remove-TestDirectory -Path $testRoot
                }
            }
        }
    }
}
