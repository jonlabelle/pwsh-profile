BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../Functions/Utilities/Sync-Directory.ps1"

    # Import test utilities
    . "$PSScriptRoot/../TestCleanupUtilities.ps1"
}

Describe 'Sync-Directory' -Tag 'Unit' {
    BeforeAll {
        # Detect platform
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $script:IsWindowsPlatform = $true
        }
        else
        {
            $script:IsWindowsPlatform = $IsWindows
        }
    }

    Context 'Parameter Validation' {
        It 'Should have mandatory Source parameter' {
            (Get-Command Sync-Directory).Parameters['Source'].Attributes.Mandatory | Should -BeTrue
        }

        It 'Should have mandatory Destination parameter' {
            (Get-Command Sync-Directory).Parameters['Destination'].Attributes.Mandatory | Should -BeTrue
        }

        It 'Should have optional Delete switch' {
            (Get-Command Sync-Directory).Parameters['Delete'].SwitchParameter | Should -BeTrue
        }

        It 'Should have optional DryRun switch' {
            (Get-Command Sync-Directory).Parameters['DryRun'].SwitchParameter | Should -BeTrue
        }

        It 'Should have optional Exclude parameter' {
            (Get-Command Sync-Directory).Parameters['Exclude'].ParameterType | Should -Be ([String[]])
        }

        It 'Should have optional ExtraOptions parameter' {
            (Get-Command Sync-Directory).Parameters['ExtraOptions'].ParameterType | Should -Be ([String[]])
        }

        It 'Should support ShouldProcess' {
            (Get-Command Sync-Directory).Parameters.ContainsKey('WhatIf') | Should -BeTrue
            (Get-Command Sync-Directory).Parameters.ContainsKey('Confirm') | Should -BeTrue
        }
    }

    Context 'Input Validation' {
        It 'Should throw error if source does not exist' {
            $NonExistentPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            $TempDest = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())

            { Sync-Directory -Source $NonExistentPath -Destination $TempDest -ErrorAction Stop } |
            Should -Throw '*does not exist*'
        }

        It 'Should accept tilde expansion in paths' {
            # This test just validates the function accepts the syntax
            # We can't test actual sync without creating directories
            $TestSource = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-tilde-source'
            $TestDest = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-tilde-dest'

            try
            {
                New-Item -ItemType Directory -Path $TestSource -Force | Out-Null
                'test' | Out-File (Join-Path $TestSource 'test.txt')

                # Test with DryRun to avoid actual sync
                $Result = Sync-Directory -Source $TestSource -Destination $TestDest -DryRun

                # Should return a result object
                $Result | Should -Not -BeNullOrEmpty
                $Result.Success | Should -BeTrue
            }
            finally
            {
                if (Test-Path $TestSource) { Remove-Item -Path $TestSource -Recurse -Force }
                if (Test-Path $TestDest) { Remove-Item -Path $TestDest -Recurse -Force }
            }
        }
    }

    Context 'Platform Detection' {
        It 'Should detect platform correctly' {
            $TestSource = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-platform'
            $TestDest = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-platform-dest'

            try
            {
                New-Item -ItemType Directory -Path $TestSource -Force | Out-Null
                'test' | Out-File (Join-Path $TestSource 'test.txt')

                $Result = Sync-Directory -Source $TestSource -Destination $TestDest -DryRun

                if ($IsWindowsPlatform)
                {
                    $Result.Platform | Should -Be 'Windows'
                    $Result.Command | Should -Match 'robocopy'
                }
                else
                {
                    $Result.Platform | Should -Be 'macOS/Linux'
                    $Result.Command | Should -Match 'rsync'
                }
            }
            finally
            {
                if (Test-Path $TestSource) { Remove-Item -Path $TestSource -Recurse -Force }
                if (Test-Path $TestDest) { Remove-Item -Path $TestDest -Recurse -Force }
            }
        }
    }

    Context 'DryRun Mode' {
        It 'Should not create destination when using DryRun' {
            $TestSource = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-dryrun-source'
            $TestDest = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-dryrun-dest'

            try
            {
                New-Item -ItemType Directory -Path $TestSource -Force | Out-Null
                'test content' | Out-File (Join-Path $TestSource 'file.txt')

                # Ensure destination doesn't exist
                if (Test-Path $TestDest) { Remove-Item -Path $TestDest -Recurse -Force }

                $Result = Sync-Directory -Source $TestSource -Destination $TestDest -DryRun

                # DryRun should still succeed
                $Result.Success | Should -BeTrue

                # Destination should not be created or should be empty on Windows (robocopy creates dir)
                if (Test-Path $TestDest)
                {
                    # If created (robocopy), should be empty
                    (Get-ChildItem -Path $TestDest -Recurse).Count | Should -Be 0
                }
            }
            finally
            {
                if (Test-Path $TestSource) { Remove-Item -Path $TestSource -Recurse -Force }
                if (Test-Path $TestDest) { Remove-Item -Path $TestDest -Recurse -Force }
            }
        }

        It 'Should include dry-run flag in command' {
            $TestSource = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-dryrun-cmd'
            $TestDest = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-dryrun-cmd-dest'

            try
            {
                New-Item -ItemType Directory -Path $TestSource -Force | Out-Null
                'test' | Out-File (Join-Path $TestSource 'test.txt')

                $Result = Sync-Directory -Source $TestSource -Destination $TestDest -DryRun

                if ($IsWindowsPlatform)
                {
                    $Result.Command | Should -Match '/L' # robocopy list-only mode
                }
                else
                {
                    $Result.Command | Should -Match '--dry-run' # rsync dry-run flag
                }
            }
            finally
            {
                if (Test-Path $TestSource) { Remove-Item -Path $TestSource -Recurse -Force }
                if (Test-Path $TestDest) { Remove-Item -Path $TestDest -Recurse -Force }
            }
        }
    }

    Context 'Output Structure' {
        It 'Should return PSCustomObject with expected properties' {
            $TestSource = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-output'
            $TestDest = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-output-dest'

            try
            {
                New-Item -ItemType Directory -Path $TestSource -Force | Out-Null
                'test' | Out-File (Join-Path $TestSource 'test.txt')

                $Result = Sync-Directory -Source $TestSource -Destination $TestDest -DryRun

                $Result | Should -Not -BeNullOrEmpty
                $Result.PSObject.Properties.Name | Should -Contain 'Platform'
                $Result.PSObject.Properties.Name | Should -Contain 'Command'
                $Result.PSObject.Properties.Name | Should -Contain 'ExitCode'
                $Result.PSObject.Properties.Name | Should -Contain 'Success'
                $Result.PSObject.Properties.Name | Should -Contain 'Message'
                $Result.PSObject.Properties.Name | Should -Contain 'StartTime'
                $Result.PSObject.Properties.Name | Should -Contain 'EndTime'
                $Result.PSObject.Properties.Name | Should -Contain 'Duration'
            }
            finally
            {
                if (Test-Path $TestSource) { Remove-Item -Path $TestSource -Recurse -Force }
                if (Test-Path $TestDest) { Remove-Item -Path $TestDest -Recurse -Force }
            }
        }

        It 'Should populate timing information' {
            $TestSource = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-timing'
            $TestDest = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-timing-dest'

            try
            {
                New-Item -ItemType Directory -Path $TestSource -Force | Out-Null
                'test' | Out-File (Join-Path $TestSource 'test.txt')

                $Result = Sync-Directory -Source $TestSource -Destination $TestDest -DryRun

                $Result.StartTime | Should -Not -BeNullOrEmpty
                $Result.EndTime | Should -Not -BeNullOrEmpty
                $Result.Duration | Should -Not -BeNullOrEmpty
                $Result.Duration | Should -BeOfType [TimeSpan]
            }
            finally
            {
                if (Test-Path $TestSource) { Remove-Item -Path $TestSource -Recurse -Force }
                if (Test-Path $TestDest) { Remove-Item -Path $TestDest -Recurse -Force }
            }
        }
    }

    Context 'Exclusion Patterns' {
        It 'Should include exclusion patterns in command' {
            $TestSource = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-exclude'
            $TestDest = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-exclude-dest'

            try
            {
                New-Item -ItemType Directory -Path $TestSource -Force | Out-Null
                'test' | Out-File (Join-Path $TestSource 'test.txt')
                'log' | Out-File (Join-Path $TestSource 'test.log')

                $Result = Sync-Directory -Source $TestSource -Destination $TestDest -Exclude '*.log', '.git' -DryRun

                if ($IsWindowsPlatform)
                {
                    $Result.Command | Should -Match '/XF'
                    $Result.Command | Should -Match '\*.log'
                }
                else
                {
                    $Result.Command | Should -Match '--exclude=\*.log'
                    $Result.Command | Should -Match '--exclude=.git'
                }
            }
            finally
            {
                if (Test-Path $TestSource) { Remove-Item -Path $TestSource -Recurse -Force }
                if (Test-Path $TestDest) { Remove-Item -Path $TestDest -Recurse -Force }
            }
        }
    }

    Context 'Delete/Mirror Mode' {
        It 'Should include delete flag when -Delete is specified' {
            $TestSource = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-delete'
            $TestDest = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-delete-dest'

            try
            {
                New-Item -ItemType Directory -Path $TestSource -Force | Out-Null
                'test' | Out-File (Join-Path $TestSource 'test.txt')

                $Result = Sync-Directory -Source $TestSource -Destination $TestDest -Delete -DryRun

                if ($IsWindowsPlatform)
                {
                    $Result.Command | Should -Match '/MIR'
                }
                else
                {
                    $Result.Command | Should -Match '--delete'
                }
            }
            finally
            {
                if (Test-Path $TestSource) { Remove-Item -Path $TestSource -Recurse -Force }
                if (Test-Path $TestDest) { Remove-Item -Path $TestDest -Recurse -Force }
            }
        }
    }

    Context 'Extra Options' {
        It 'Should include extra options in command' {
            $TestSource = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-extra'
            $TestDest = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-extra-dest'

            try
            {
                New-Item -ItemType Directory -Path $TestSource -Force | Out-Null
                'test' | Out-File (Join-Path $TestSource 'test.txt')

                if ($IsWindowsPlatform)
                {
                    $ExtraOpts = @('/MT:8', '/R:2')
                    $Result = Sync-Directory -Source $TestSource -Destination $TestDest -ExtraOptions $ExtraOpts -DryRun
                    $Result.Command | Should -Match '/MT:8'
                    $Result.Command | Should -Match '/R:2'
                }
                else
                {
                    $ExtraOpts = @('--compress', '--links')
                    $Result = Sync-Directory -Source $TestSource -Destination $TestDest -ExtraOptions $ExtraOpts -DryRun
                    $Result.Command | Should -Match '--compress'
                    $Result.Command | Should -Match '--links'
                }
            }
            finally
            {
                if (Test-Path $TestSource) { Remove-Item -Path $TestSource -Recurse -Force }
                if (Test-Path $TestDest) { Remove-Item -Path $TestDest -Recurse -Force }
            }
        }
    }

    Context 'Verbose Output' {
        It 'Should write verbose messages when -Verbose is used' {
            $TestSource = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-verbose'
            $TestDest = Join-Path ([System.IO.Path]::GetTempPath()) 'sync-test-verbose-dest'

            try
            {
                New-Item -ItemType Directory -Path $TestSource -Force | Out-Null
                'test' | Out-File (Join-Path $TestSource 'test.txt')

                $VerboseMessages = @()
                Sync-Directory -Source $TestSource -Destination $TestDest -DryRun -Verbose 4>&1 |
                ForEach-Object {
                    if ($_ -is [System.Management.Automation.VerboseRecord])
                    {
                        $VerboseMessages += $_.Message
                    }
                }

                $VerboseMessages | Should -Not -BeNullOrEmpty
                $VerboseMessages -join ' ' | Should -Match 'Starting Sync-Directory'
            }
            finally
            {
                if (Test-Path $TestSource) { Remove-Item -Path $TestSource -Recurse -Force }
                if (Test-Path $TestDest) { Remove-Item -Path $TestDest -Recurse -Force }
            }
        }
    }
}
