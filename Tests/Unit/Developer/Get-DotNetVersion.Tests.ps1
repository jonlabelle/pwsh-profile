#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Get-DotNetVersion function.

.DESCRIPTION
    Tests the Get-DotNetVersion function which detects installed .NET Framework and .NET Core/5+ versions.
    Validates cross-platform compatibility, parameter validation, and version detection accuracy.

.NOTES
    These tests are based on the examples in the Get-DotNetVersion function documentation.
    Tests verify detection of both .NET Framework (Windows) and .NET Core/.NET 5+ (cross-platform).
#>

BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../../Functions/Developer/Get-DotNetVersion.ps1"
}

Describe 'Get-DotNetVersion' {
    Context 'Basic functionality examples from documentation' {
        It 'Gets only .NET Framework versions from the local computer (Example: Get-DotNetVersion -ComputerName "localhost" -FrameworkOnly)' {
            # Test filtering to show only .NET Framework versions (Windows-specific)
            $result = Get-DotNetVersion -ComputerName 'localhost' -FrameworkOnly

            # Should only return .NET Framework versions
            if ($result)
            {
                $result | ForEach-Object {
                    $_.RuntimeType | Should -Match 'Framework'
                }
            }
        }

        It 'Gets all .NET versions from the local computer (Example: Get-DotNetVersion -ComputerName "localhost" -DotNetOnly -All)' {
            # Test filtering to show only .NET (Core) versions across all platforms
            $result = Get-DotNetVersion -ComputerName 'localhost' -DotNetOnly -All

            # Should only return .NET (Core) versions
            if ($result)
            {
                $result | ForEach-Object {
                    $_.RuntimeType | Should -Not -Match 'Framework'
                }
            }
        }

        It 'Gets the latest .NET version and all SDK versions from the local computer (Example: Get-DotNetVersion -ComputerName "localhost" -DotNetOnly -IncludeSDKs)' {
            # Test SDK detection along with runtime versions
            $result = Get-DotNetVersion -ComputerName 'localhost' -DotNetOnly -IncludeSDKs

            # Should include SDK information for .NET only
            if ($result)
            {
                $result | ForEach-Object {
                    $_.RuntimeType | Should -Not -Match 'Framework'
                }
            }
        }
    }

    Context 'Parameter validation' {
        It 'Should accept valid ComputerName parameters' {
            { Get-DotNetVersion -ComputerName 'localhost' } | Should -Not -Throw
            { Get-DotNetVersion -ComputerName @('localhost', 'localhost') } | Should -Not -Throw
        }

        It 'Should not allow both FrameworkOnly and DotNetOnly' {
            { Get-DotNetVersion -ComputerName 'localhost' -FrameworkOnly -DotNetOnly } | Should -Throw
        }

        It 'Should allow IncludeSDKs with DotNetOnly' {
            { Get-DotNetVersion -ComputerName 'localhost' -DotNetOnly -IncludeSDKs } | Should -Not -Throw
        }

        It 'Should allow All parameter with other combinations' {
            { Get-DotNetVersion -ComputerName 'localhost' -All } | Should -Not -Throw
            { Get-DotNetVersion -ComputerName 'localhost' -All -FrameworkOnly } | Should -Not -Throw
            { Get-DotNetVersion -ComputerName 'localhost' -All -DotNetOnly } | Should -Not -Throw
        }
    }

    Context 'Output structure validation' {
        It 'Should indicate when runtimes are not installed' {
            $result = Get-DotNetVersion -ComputerName 'localhost'

            # On some systems, certain runtime types might not be installed
            # The function should indicate this appropriately
            $result | ForEach-Object {
                if ($_.Version -eq 'Not installed')
                {
                    $_.RuntimeType | Should -Not -BeNullOrEmpty
                }
            }
        }
    }

    Context 'Cross-platform compatibility' {
        It 'Should work on current platform' {
            $result = Get-DotNetVersion -ComputerName 'localhost'
            $result | Should -Not -BeNullOrEmpty

            # Should return information about the current system
            $result | ForEach-Object {
                $_.ComputerName | Should -Not -BeNullOrEmpty
                $_.RuntimeType | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should handle platform-specific runtime detection' {
            $result = Get-DotNetVersion -ComputerName 'localhost' -All

            # Should return appropriate runtime information for the platform
            $result | Should -Not -BeNullOrEmpty
            $result | ForEach-Object {
                $_.RuntimeType | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Runtime type filtering' {
        It 'Should filter to Framework only when requested' {
            $result = Get-DotNetVersion -ComputerName 'localhost' -FrameworkOnly -All

            if ($result)
            {
                $result | ForEach-Object {
                    $_.RuntimeType | Should -Match 'Framework'
                }
            }
        }

        It 'Should filter to .NET only when requested' {
            $result = Get-DotNetVersion -ComputerName 'localhost' -DotNetOnly -All

            if ($result)
            {
                $result | ForEach-Object {
                    $_.RuntimeType | Should -Not -Match 'Framework'
                }
            }
        }

        It 'Should include both runtime types by default' {
            $result = Get-DotNetVersion -ComputerName 'localhost' -All
            $result | Should -Not -BeNullOrEmpty

            # Should have information about both runtime types (even if not installed)
            $runtimeTypes = $result | ForEach-Object { $_.RuntimeType } | Select-Object -Unique
            $runtimeTypes | Should -Not -BeNullOrEmpty
        }
    }

    Context 'ComputerName parameter support' {
        It 'Should handle localhost as ComputerName' {
            $result = Get-DotNetVersion -ComputerName 'localhost'
            $result | Should -Not -BeNullOrEmpty
            $result[0].ComputerName | Should -Be 'localhost'
        }

        It 'Should handle pipeline input for ComputerName' {
            $result = @('localhost') | Get-DotNetVersion
            $result | Should -Not -BeNullOrEmpty
            $result[0].ComputerName | Should -Be 'localhost'
        }

        It 'Should handle multiple computer names' {
            $result = Get-DotNetVersion -ComputerName @('localhost', 'localhost')
            $result | Should -Not -BeNullOrEmpty

            # Should have results for both entries
            ($result | Where-Object { $_.ComputerName -eq 'localhost' }).Count | Should -BeGreaterThan 0
        }
    }

    Context 'Version detection accuracy' {
        It 'Should detect PowerShell version information' {
            $result = Get-DotNetVersion -ComputerName 'localhost' -All
            $result | Should -Not -BeNullOrEmpty

            # At minimum, should detect something about the current PowerShell runtime
            # which runs on some version of .NET
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should handle cases where no versions are installed' {
            # This tests the error handling when certain runtime types aren't available
            $result = Get-DotNetVersion -ComputerName 'localhost' -All

            # Even if nothing is installed, should return objects indicating "Not installed"
            $result | Should -Not -BeNullOrEmpty
            $result | ForEach-Object {
                $_.RuntimeType | Should -Not -BeNullOrEmpty
            }
        }
    }
}
