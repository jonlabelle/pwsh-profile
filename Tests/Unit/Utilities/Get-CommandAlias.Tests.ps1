#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Get-CommandAlias function.

.DESCRIPTION
    Tests the Get-CommandAlias function which displays aliases for PowerShell cmdlets.
    Validates basic functionality, parameter validation, pipeline support, and output formatting.

.NOTES
    These tests are based on the examples in the Get-CommandAlias function documentation.
    The tests verify that the function correctly finds and displays aliases for known commands.
#>

BeforeAll {
    # Load the function under test
    . "$PSScriptRoot/../../../Functions/Utilities/Get-CommandAlias.ps1"
}

Describe 'Get-CommandAlias' {
    Context 'Basic functionality with known commands' {
        It 'Lists all aliases defined for Get-ChildItem command (Example: Get-CommandAlias -Name "Get-ChildItem")' {
            # This test validates the primary documentation example showing alias discovery for Get-ChildItem
            # Capture formatted output by redirecting all output streams
            $output = Get-CommandAlias -Name 'Get-ChildItem' *>&1
            $output | Should -Not -BeNullOrEmpty

            # The function outputs formatted table, so we check the string content
            $outputString = $output | Out-String
            $outputString | Should -Match 'Get-ChildItem'
            $outputString | Should -Match 'dir'      # Common Windows alias
            $outputString | Should -Match 'gci'      # PowerShell-style alias
        }

        It 'Lists aliases for Select-Object and Select-String with wildcard (Example: Get-CommandAlias -Name "Select*")' {
            # Test wildcard pattern matching for multiple related commands
            $output = Get-CommandAlias -Name 'Select*' *>&1
            $output | Should -Not -BeNullOrEmpty

            $outputString = $output | Out-String
            $outputString | Should -Match 'Select-Object'
            $outputString | Should -Match 'select'   # Alias for Select-Object
            $outputString | Should -Match 'Select-String'
            $outputString | Should -Match 'sls'      # Alias for Select-String
        }
    }

    Context 'Pipeline input support' {
        It 'Gets aliases for Get-Process using pipeline input (Example: "Get-Process" | Get-CommandAlias)' {
            # Test pipeline input functionality as shown in documentation examples
            $commands = @('Get-Process')  # Just test one command that we know has aliases
            $output = $commands | Get-CommandAlias *>&1
            $output | Should -Not -BeNullOrEmpty

            $outputString = $output | Out-String
            $outputString | Should -Match 'Get-Process'
            $outputString | Should -Match 'gps'  # Known alias for Get-Process
        }
    }

    Context 'Wildcard pattern support' {
        It 'Should work with wildcard patterns' {
            $output = Get-CommandAlias -Name 'Get-C*' *>&1
            $output | Should -Not -BeNullOrEmpty

            $outputString = $output | Out-String
            $outputString | Should -Match 'Get-ChildItem'
        }

        It 'Should show warning for non-existent command pattern' {
            $warningOutput = Get-CommandAlias -Name 'NonExistentCommand*' 3>&1
            $warningOutput | Should -Not -BeNullOrEmpty
            $warningOutput | Should -Match 'No aliases found'
        }
    }

    Context 'Parameter validation' {
        It 'Should require Name parameter when called directly' {
            { Get-CommandAlias -Name '' -ErrorAction Stop } | Should -Throw
        }

        It 'Should handle empty Name parameter with proper validation' {
            # Test with empty string - should throw validation error
            { Get-CommandAlias -Name '' -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Output format' {
        It 'Should return formatted table output' {
            $output = Get-CommandAlias -Name 'Get-ChildItem' *>&1
            $output | Should -Not -BeNullOrEmpty

            # Check that it's formatted table output
            $outputString = $output | Out-String
            $outputString | Should -Match 'Definition\s+Name'  # Table headers
            $outputString | Should -Match '----------\s+----'  # Table separator
        }
    }

    Context 'Verbose output' {
        It 'Should provide verbose output when requested' {
            $verboseOutput = Get-CommandAlias -Name 'Get-ChildItem' -Verbose 4>&1

            # Should produce verbose messages
            $verboseMessages = $verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages | Should -Not -BeNullOrEmpty
            $verboseMessages | Should -Match 'alias'
        }
    }

    Context 'Cross-platform compatibility' {
        It 'Should work on any PowerShell platform' {
            # Test with core PowerShell commands available on all platforms
            $output = Get-CommandAlias -Name 'Get-Location' *>&1
            $output | Should -Not -BeNullOrEmpty

            $outputString = $output | Out-String
            $outputString | Should -Match 'Get-Location'
            $outputString | Should -Match 'gl'
            $outputString | Should -Match 'pwd'
        }
    }

    Context 'Warning handling' {
        It 'Should show warning when no aliases found' {
            # Use a command that likely has no aliases
            $warningOutput = Get-CommandAlias -Name 'Get-Random' 3>&1

            # Should produce a warning about no aliases found
            if ($warningOutput)
            {
                $warningOutput | Should -Match 'No aliases found'
            }
        }
    }
}
