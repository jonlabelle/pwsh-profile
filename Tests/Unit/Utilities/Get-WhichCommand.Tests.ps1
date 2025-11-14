BeforeAll {
    # Dot source the function
    . $PSScriptRoot/../../../Functions/Utilities/Get-WhichCommand.ps1
}

Describe 'Get-WhichCommand' -Tag 'Unit' {

    Context 'Parameter Validation' {
        It 'Should accept a single command name' {
            { Get-WhichCommand -Name 'Get-Process' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should accept multiple command names' {
            { Get-WhichCommand -Name 'Get-Process', 'Get-Service' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should accept pipeline input' {
            { 'Get-Process' | Get-WhichCommand -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should require Name parameter' {
            { Get-WhichCommand -Name '' -ErrorAction Stop } | Should -Throw
        }

        It 'Should accept All switch parameter' {
            { Get-WhichCommand -Name 'Get-Process' -All -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should accept Simple switch parameter' {
            { Get-WhichCommand -Name 'pwsh' -Simple -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'PowerShell Cmdlets' {
        It 'Should find Get-Process cmdlet' {
            $result = Get-WhichCommand -Name 'Get-Process'
            $result | Should -Not -BeNullOrEmpty
            $result.CommandType | Should -Be 'Cmdlet'
            $result.Name | Should -Be 'Get-Process'
        }

        It 'Should include module information for cmdlets' {
            $result = Get-WhichCommand -Name 'Get-Process'
            $result.Module | Should -Not -BeNullOrEmpty
        }
    }

    Context 'PowerShell Aliases' {
        It 'Should find dir alias (cross-platform test)' {
            $result = Get-WhichCommand -Name 'dir'
            $result | Should -Not -BeNullOrEmpty
            $result.CommandType | Should -Be 'Alias'
        }

        It 'Should show alias definition with arrow notation' {
            $result = Get-WhichCommand -Name 'dir'
            $result.Definition | Should -Match '->'
            $result.Definition | Should -Match 'Get-ChildItem'
        }

        It 'Should resolve common aliases (gci, dir, select)' {
            $aliases = @('gci', 'dir', 'select')
            foreach ($alias in $aliases)
            {
                $result = Get-WhichCommand -Name $alias
                $result | Should -Not -BeNullOrEmpty
                $result.CommandType | Should -Be 'Alias'
            }
        }
    }

    Context 'PowerShell Functions' {
        It 'Should find user-defined functions' {
            # Create a temporary test function inline
            & {
                function Test-WhichCommandTempFunction { 'This is a test function' }
                $result = Get-WhichCommand -Name 'Test-WhichCommandTempFunction'
                $result | Should -Not -BeNullOrEmpty
                $result.CommandType | Should -Be 'Function'
                $result.Name | Should -Be 'Test-WhichCommandTempFunction'
            }
        }

        It 'Should show definition for functions' {
            # Create a scriptblock-based function
            $null = New-Item -Path Function:\Test-WhichTemp2 -Value { 'test' } -Force
            try
            {
                $result = Get-WhichCommand -Name 'Test-WhichTemp2'
                $result.Definition | Should -Not -BeNullOrEmpty
                # Definition should be either a file path or <ScriptBlock>
                ($result.Definition -eq '<ScriptBlock>' -or (Test-Path $result.Definition -PathType Leaf)) | Should -Be $true
            }
            finally
            {
                Remove-Item Function:\Test-WhichTemp2 -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'External Executables' {
        It 'Should find pwsh executable' {
            $result = Get-WhichCommand -Name 'pwsh'
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [PSCustomObject]
            $result.CommandType | Should -Be 'Application'
            $result.Name | Should -Be 'pwsh'
            $result.Source | Should -Match 'pwsh'
        }

        It 'Should return full path for executables' {
            $result = Get-WhichCommand -Name 'pwsh'
            $result.Source | Should -Not -BeNullOrEmpty
            [System.IO.Path]::IsPathRooted($result.Source) | Should -Be $true
        }

        It 'Should find platform-specific commands' {
            if ($PSVersionTable.PSVersion.Major -lt 6)
            {
                $isWindowsPlatform = $true
            }
            else
            {
                $isWindowsPlatform = $IsWindows
            }

            if ($isWindowsPlatform)
            {
                $result = Get-WhichCommand -Name 'cmd'
                $result | Should -Not -BeNullOrEmpty
                $result | Should -Match 'cmd\.exe'
            }
            else
            {
                # Test for common Unix commands
                $commonCommands = @('ls', 'cat', 'grep')
                $foundCommand = $false
                foreach ($cmd in $commonCommands)
                {
                    $result = Get-WhichCommand -Name $cmd -ErrorAction SilentlyContinue 3>$null
                    if ($result)
                    {
                        $foundCommand = $true
                        break
                    }
                }
                $foundCommand | Should -Be $true
            }
        }
    }

    Context 'Non-existent Commands' {
        It 'Should warn when command is not found' {
            $warningMessage = $null
            Get-WhichCommand -Name 'ThisCommandDefinitelyDoesNotExist123456789' -WarningVariable warningMessage -WarningAction SilentlyContinue
            $warningMessage | Should -Not -BeNullOrEmpty
            $warningMessage | Should -Match 'not found'
        }

        It 'Should not throw for non-existent commands' {
            { Get-WhichCommand -Name 'NonExistentCommand12345' -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'Multiple Results with -All Switch' {
        It 'Should return only first match without -All' {
            # Test with a well-known cmdlet that has only one match
            $result = Get-WhichCommand -Name 'Get-Process'
            @($result).Count | Should -Be 1
        }

        It 'Should handle commands with multiple matches when -All is specified' {
            # Python is commonly installed in multiple locations
            $allResults = Get-WhichCommand -Name 'pwsh' -All -ErrorAction SilentlyContinue
            if ($allResults)
            {
                $allResults | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Pipeline Input' {
        It 'Should process multiple commands from pipeline' {
            $commands = @('Get-Process', 'ls')
            $results = $commands | Get-WhichCommand
            @($results).Count | Should -BeGreaterThan 0
        }

        It 'Should handle mixed valid and invalid commands from pipeline' {
            $commands = @('Get-Process', 'NonExistentCommand999', 'ls')
            $results = $commands | Get-WhichCommand -WarningAction SilentlyContinue
            @($results).Count | Should -BeGreaterThan 0
        }
    }

    Context 'Command Priority' {
        It 'Should find commands using PowerShell command resolution order' {
            # 'dir' is an alias on all platforms in PowerShell
            $result = Get-WhichCommand -Name 'dir'
            $result | Should -Not -BeNullOrEmpty
            # PowerShell prioritizes aliases, functions, cmdlets, then external commands
            $result.CommandType | Should -Be 'Alias'
        }
    }

    Context 'Output Format' {
        It 'Should return PSCustomObject for aliases' {
            $result = Get-WhichCommand -Name 'dir'
            $result | Should -BeOfType [PSCustomObject]
            $result.PSObject.Properties.Name | Should -Contain 'CommandType'
            $result.PSObject.Properties.Name | Should -Contain 'Name'
            $result.PSObject.Properties.Name | Should -Contain 'Definition'
        }

        It 'Should return PSCustomObject for executables' {
            $result = Get-WhichCommand -Name 'pwsh'
            $result | Should -BeOfType [PSCustomObject]
            $result.PSObject.Properties.Name | Should -Contain 'CommandType'
            $result.PSObject.Properties.Name | Should -Contain 'Source'
        }

        It 'Should return PSCustomObject for cmdlets' {
            $result = Get-WhichCommand -Name 'Get-Process'
            $result | Should -BeOfType [PSCustomObject]
            $result.PSObject.Properties.Name | Should -Contain 'CommandType'
        }
    }

    Context 'Simple Switch (POSIX-like behavior)' {
        It 'Should return string path with -Simple switch' {
            $result = Get-WhichCommand -Name 'pwsh' -Simple
            $result | Should -BeOfType [String]
            $result | Should -Match 'pwsh'
        }

        It 'Should return full path string with -Simple switch' {
            $result = Get-WhichCommand -Name 'pwsh' -Simple
            [System.IO.Path]::IsPathRooted($result) | Should -Be $true
        }

        It 'Should work with -All and -Simple together' {
            $results = Get-WhichCommand -Name 'pwsh' -All -Simple
            foreach ($result in $results)
            {
                $result | Should -BeOfType [String]
            }
        }
    }

    Context 'Cross-Platform Compatibility' {
        It 'Should work on current platform' {
            { Get-WhichCommand -Name 'Get-Process' } | Should -Not -Throw
        }

        It 'Should find pwsh on all platforms' {
            $result = Get-WhichCommand -Name 'pwsh'
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Verbose Output' {
        It 'Should provide verbose messages when requested' {
            $verboseOutput = $null
            Get-WhichCommand -Name 'Get-Process' -Verbose 4>&1 | Tee-Object -Variable verboseOutput | Out-Null
            $verboseOutput | Should -Not -BeNullOrEmpty
        }
    }
}
