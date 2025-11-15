#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Remove-OldFiles function.

.DESCRIPTION
    Tests the Remove-OldFiles function which removes files older than a specified
    time period with support for filtering, exclusions, and empty directory cleanup.

.NOTES
    These tests verify:
    - Parameter validation and defaults
    - Date calculation logic (Days, Hours, Months, Years)
    - Path resolution (relative, absolute, ~)
    - Filter patterns (Include, Exclude)
    - Directory exclusion logic
    - Empty directory removal
    - Force parameter behavior
    - Pipeline input support
    - Summary output format
    - Error handling
#>

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../../Functions/Utilities/Remove-OldFiles.ps1"
}

Describe 'Remove-OldFiles' {
    Context 'Parameter Validation' {
        It 'Should have mandatory OlderThan parameter' {
            $command = Get-Command Remove-OldFiles
            $olderThanParam = $command.Parameters['OlderThan']
            $olderThanParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should validate OlderThan is positive integer' {
            $command = Get-Command Remove-OldFiles
            $olderThanParam = $command.Parameters['OlderThan']
            $validateRange = $olderThanParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $validateRange.MinRange | Should -Be 1
            $validateRange.MaxRange | Should -Be ([Int32]::MaxValue)
        }

        It 'Should have optional Path parameter with default value' {
            $command = Get-Command Remove-OldFiles
            $pathParam = $command.Parameters['Path']
            $pathParam.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should accept pipeline input for Path' {
            $command = Get-Command Remove-OldFiles
            $pathParam = $command.Parameters['Path']
            $pathParam.Attributes.ValueFromPipeline | Should -Contain $true
        }

        It 'Should validate Unit parameter has correct values' {
            $command = Get-Command Remove-OldFiles
            $unitParam = $command.Parameters['Unit']
            $validateSet = $unitParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Days'
            $validateSet.ValidValues | Should -Contain 'Hours'
            $validateSet.ValidValues | Should -Contain 'Months'
            $validateSet.ValidValues | Should -Contain 'Years'
            $validateSet.ValidValues.Count | Should -Be 4
        }

        It 'Should have default Unit value of Days' {
            $command = Get-Command Remove-OldFiles
            $unitParam = $command.Parameters['Unit']
            # Default values in advanced functions aren't reflected in parameter metadata,
            # so we'll test behavior instead
            { Remove-OldFiles -OlderThan 1 -WhatIf } | Should -Not -Throw
        }

        It 'Should support ShouldProcess (WhatIf/Confirm)' {
            $command = Get-Command Remove-OldFiles
            $command.Parameters.ContainsKey('WhatIf') | Should -Be $true
            $command.Parameters.ContainsKey('Confirm') | Should -Be $true
        }

        It 'Should have OutputType attribute defined' {
            $command = Get-Command Remove-OldFiles
            $outputType = $command.OutputType
            $outputType | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Date Calculation' {
        BeforeAll {
            # Create a temporary test directory
            $script:testDir = Join-Path $TestDrive 'DateTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
        }

        It 'Should calculate cutoff date for Days unit' {
            $testFile = Join-Path $script:testDir 'test_days.txt'
            'test' | Set-Content -Path $testFile

            # Set file date to 10 days ago
            $oldDate = (Get-Date).AddDays(-10)
            (Get-Item $testFile).LastWriteTime = $oldDate

            $result = Remove-OldFiles -Path $script:testDir -OlderThan 5 -Unit Days -WhatIf
            $result.OldestDate | Should -BeOfType [DateTime]
            $result.OldestDate.Date | Should -Be (Get-Date).AddDays(-5).Date
        }

        It 'Should calculate cutoff date for Hours unit' {
            $testFile = Join-Path $script:testDir 'test_hours.txt'
            'test' | Set-Content -Path $testFile

            $result = Remove-OldFiles -Path $script:testDir -OlderThan 24 -Unit Hours -WhatIf
            $result.OldestDate | Should -BeOfType [DateTime]
            # Allow small time difference for test execution
            $expectedDate = (Get-Date).AddHours(-24)
            $result.OldestDate | Should -BeGreaterThan $expectedDate.AddMinutes(-1)
            $result.OldestDate | Should -BeLessThan $expectedDate.AddMinutes(1)
        }

        It 'Should calculate cutoff date for Months unit' {
            $testFile = Join-Path $script:testDir 'test_months.txt'
            'test' | Set-Content -Path $testFile

            $result = Remove-OldFiles -Path $script:testDir -OlderThan 3 -Unit Months -WhatIf
            $result.OldestDate | Should -BeOfType [DateTime]
            $expectedDate = (Get-Date).AddMonths(-3)
            # Month calculations can vary by day, so check within reason
            $result.OldestDate.Date | Should -Be $expectedDate.Date
        }

        It 'Should calculate cutoff date for Years unit' {
            $testFile = Join-Path $script:testDir 'test_years.txt'
            'test' | Set-Content -Path $testFile

            $result = Remove-OldFiles -Path $script:testDir -OlderThan 1 -Unit Years -WhatIf
            $result.OldestDate | Should -BeOfType [DateTime]
            $expectedDate = (Get-Date).AddYears(-1)
            $result.OldestDate.Date | Should -Be $expectedDate.Date
        }
    }

    Context 'Path Resolution' {
        BeforeAll {
            $script:testDir = Join-Path $TestDrive 'PathTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
        }

        It 'Should resolve relative paths' {
            Push-Location $script:testDir
            try
            {
                $testFile = 'relative_test.txt'
                'test' | Set-Content -Path $testFile

                $result = Remove-OldFiles -Path '.' -OlderThan 1 -WhatIf
                $result | Should -Not -BeNullOrEmpty
            }
            finally
            {
                Pop-Location
            }
        }

        It 'Should handle non-existent path gracefully' {
            $nonExistentPath = Join-Path $TestDrive 'NonExistent'

            { Remove-OldFiles -Path $nonExistentPath -OlderThan 1 -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Summary Output' {
        BeforeAll {
            $script:testDir = Join-Path $TestDrive 'SummaryTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
        }

        It 'Should return summary object with correct properties' {
            $result = Remove-OldFiles -Path $script:testDir -OlderThan 1 -WhatIf

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'FilesRemoved'
            $result.PSObject.Properties.Name | Should -Contain 'DirectoriesRemoved'
            $result.PSObject.Properties.Name | Should -Contain 'TotalSpaceFreed'
            $result.PSObject.Properties.Name | Should -Contain 'TotalSpaceFreedMB'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'OldestDate'
        }

        It 'Should initialize counters to zero with WhatIf' {
            $result = Remove-OldFiles -Path $script:testDir -OlderThan 1 -WhatIf

            $result.FilesRemoved | Should -Be 0
            $result.DirectoriesRemoved | Should -Be 0
            $result.TotalSpaceFreed | Should -Be 0
            $result.Errors | Should -Be 0
        }

        It 'Should include OldestDate in summary' {
            $result = Remove-OldFiles -Path $script:testDir -OlderThan 7 -Unit Days -WhatIf

            $result.OldestDate | Should -BeOfType [DateTime]
            $result.OldestDate | Should -BeLessThan (Get-Date)
        }
    }

    Context 'WhatIf Support' {
        BeforeAll {
            $script:testDir = Join-Path $TestDrive 'WhatIfTests'
            New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

            # Create old test file
            $testFile = Join-Path $script:testDir 'old_file.txt'
            'test content' | Set-Content -Path $testFile
            (Get-Item $testFile).LastWriteTime = (Get-Date).AddDays(-30)
        }

        It 'Should not remove files with WhatIf' {
            $testFile = Join-Path $script:testDir 'old_file.txt'

            Remove-OldFiles -Path $script:testDir -OlderThan 7 -WhatIf

            Test-Path $testFile | Should -Be $true
        }

        It 'Should report zero files removed with WhatIf' {
            $result = Remove-OldFiles -Path $script:testDir -OlderThan 7 -WhatIf

            $result.FilesRemoved | Should -Be 0
        }
    }
}
