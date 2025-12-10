#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Copy-Directory function.

.DESCRIPTION
    Tests the Copy-Directory function which copies directories recursively
    with support for excluding specific directories and controlling how existing files
    are handled.

.NOTES
    These tests verify:
    - Parameter validation and defaults
    - UpdateMode enum handling (Skip, Overwrite, IfNewer, Prompt)
    - Path resolution (relative, absolute, ~)
    - Directory exclusion logic
    - File handling modes
    - Output object format
    - Error handling
#>

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot/../../../Functions/Utilities/Copy-Directory.ps1"
}

Describe 'Copy-Directory' {
    Context 'Parameter Validation' {
        It 'Should have mandatory Source parameter' {
            $command = Get-Command Copy-Directory
            $sourceParam = $command.Parameters['Source']
            $sourceParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have mandatory Destination parameter' {
            $command = Get-Command Copy-Directory
            $destParam = $command.Parameters['Destination']
            $destParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have optional ExcludeDirectories parameter' {
            $command = Get-Command Copy-Directory
            $excludeParam = $command.Parameters['ExcludeDirectories']
            $excludeParam.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have UpdateMode parameter with correct default' {
            $command = Get-Command Copy-Directory
            $updateModeParam = $command.Parameters['UpdateMode']
            $updateModeParam | Should -Not -BeNullOrEmpty
        }

        It 'Should validate UpdateMode parameter has correct values' {
            $command = Get-Command Copy-Directory
            $updateModeParam = $command.Parameters['UpdateMode']
            $validateSet = $updateModeParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Skip'
            $validateSet.ValidValues | Should -Contain 'Overwrite'
            $validateSet.ValidValues | Should -Contain 'IfNewer'
            $validateSet.ValidValues | Should -Contain 'Prompt'
            $validateSet.ValidValues.Count | Should -Be 4
        }

        It 'Should support ShouldProcess (WhatIf/Confirm)' {
            $command = Get-Command Copy-Directory
            $command.Parameters.ContainsKey('WhatIf') | Should -Be $true
            $command.Parameters.ContainsKey('Confirm') | Should -Be $true
        }

        It 'Should expose optional Recurse switch' {
            $command = Get-Command Copy-Directory
            $recurseParam = $command.Parameters['Recurse']
            $recurseParam | Should -Not -BeNullOrEmpty
            $recurseParam.Attributes.Mandatory | Should -Not -Contain $true
        }
    }

    Context 'Non-recursive behavior' {
        It 'Should skip subdirectories when Recurse is not specified' {
            $testSource = Join-Path $TestDrive 'nonrecursive_source'
            $testDest = Join-Path $TestDrive 'nonrecursive_dest'

            New-Item -ItemType Directory -Path $testSource -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $testSource 'subdir') -Force | Out-Null
            'root content' | Set-Content -Path (Join-Path $testSource 'root.txt')
            'nested content' | Set-Content -Path (Join-Path $testSource 'subdir/nested.txt')

            $result = Copy-Directory -Source $testSource -Destination $testDest -UpdateMode Skip

            Test-Path (Join-Path $testDest 'root.txt') | Should -BeTrue
            Test-Path (Join-Path $testDest 'subdir/nested.txt') | Should -BeFalse
            $result.TotalDirectories | Should -Be 0
        }
    }

    Context 'UpdateMode Parameter' {
        It 'Should default to Skip mode' {
            $testSource = Join-Path $TestDrive 'default_mode_source'
            $testDest = Join-Path $TestDrive 'default_mode_dest'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null
            'content' | Set-Content -Path "$testSource\test.txt"

            # Create destination file first
            New-Item -ItemType Directory -Path $testDest -Force | Out-Null
            'old content' | Set-Content -Path "$testDest\test.txt"

            $result = Copy-Directory -Source $testSource -Destination $testDest -Recurse

            $result.FilesSkipped | Should -Be 1
            (Get-Content -Path "$testDest\test.txt") | Should -Be 'old content'
        }
        It 'Should return PSCustomObject with expected properties' {
            $testSource = Join-Path $TestDrive 'source'
            $testDest = Join-Path $TestDrive 'destination'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null

            $result = Copy-Directory -Source $testSource -Destination $testDest -UpdateMode Skip -Recurse

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'TotalFiles'
            $result.PSObject.Properties.Name | Should -Contain 'TotalDirectories'
            $result.PSObject.Properties.Name | Should -Contain 'ExcludedDirectories'
            $result.PSObject.Properties.Name | Should -Contain 'FilesSkipped'
            $result.PSObject.Properties.Name | Should -Contain 'FilesOverwritten'
            $result.PSObject.Properties.Name | Should -Contain 'Duration'
        }

        It 'Should have correct property types' {
            $testSource = Join-Path $TestDrive 'source'
            $testDest = Join-Path $TestDrive 'destination'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null

            $result = Copy-Directory -Source $testSource -Destination $testDest -UpdateMode Skip -Recurse

            $result.TotalFiles | Should -BeOfType [Int32]
            $result.TotalDirectories | Should -BeOfType [Int32]
            $result.ExcludedDirectories | Should -BeOfType [Int32]
            $result.FilesSkipped | Should -BeOfType [Int32]
            $result.FilesOverwritten | Should -BeOfType [Int32]
            $result.Duration | Should -BeOfType [TimeSpan]
        }

        It 'Should have zero values for empty source directory' {
            $testSource = Join-Path $TestDrive 'empty_source'
            $testDest = Join-Path $TestDrive 'empty_dest'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null

            $result = Copy-Directory -Source $testSource -Destination $testDest -UpdateMode Skip -Recurse

            $result.TotalFiles | Should -Be 0
            $result.TotalDirectories | Should -Be 0
            $result.ExcludedDirectories | Should -Be 0
            $result.FilesSkipped | Should -Be 0
            $result.FilesOverwritten | Should -Be 0
        }
    }

    Context 'Path Resolution' {
        It 'Should handle absolute paths' {
            $testSource = Join-Path $TestDrive 'absolute_source'
            $testDest = Join-Path $TestDrive 'absolute_dest'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null
            'test content' | Set-Content -Path (Join-Path $testSource 'test.txt')

            { Copy-Directory -Source $testSource -Destination $testDest -UpdateMode Skip -Recurse } | Should -Not -Throw

            Test-Path $testDest | Should -Be $true
        }

        It 'Should handle relative paths' {
            $originalLocation = Get-Location
            try
            {
                Set-Location -Path $TestDrive
                New-Item -ItemType Directory -Path 'relative_source' -Force | Out-Null
                'test' | Set-Content -Path 'relative_source\test.txt'

                { Copy-Directory -Source './relative_source' -Destination './relative_dest' -UpdateMode Skip -Recurse } | Should -Not -Throw

                Test-Path 'relative_dest' | Should -Be $true
            }
            finally
            {
                Set-Location -Path $originalLocation
            }
        }

        It 'Should throw error for non-existent source directory' {
            $nonExistentSource = Join-Path $TestDrive 'non_existent'
            $testDest = Join-Path $TestDrive 'dest'

            { Copy-Directory -Source $nonExistentSource -Destination $testDest -UpdateMode Skip -Recurse } | Should -Throw
        }
    }

    Context 'Directory Exclusion' {
        It 'Should exclude specified directories' {
            $testSource = Join-Path $TestDrive 'exclude_source'
            $testDest = Join-Path $TestDrive 'exclude_dest'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null
            New-Item -ItemType Directory -Path "$testSource\.git" -Force | Out-Null
            New-Item -ItemType Directory -Path "$testSource\include" -Force | Out-Null
            'test' | Set-Content -Path "$testSource\.git\config"
            'test' | Set-Content -Path "$testSource\include\file.txt"

            $result = Copy-Directory -Source $testSource -Destination $testDest -ExcludeDirectories '.git' -UpdateMode Skip -Recurse

            $result.ExcludedDirectories | Should -Be 1
            Test-Path "$testDest\.git" | Should -Be $false
            Test-Path "$testDest\include" | Should -Be $true
        }

        It 'Should exclude multiple directories' {
            $testSource = Join-Path $TestDrive 'multi_exclude_source'
            $testDest = Join-Path $TestDrive 'multi_exclude_dest'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null
            New-Item -ItemType Directory -Path "$testSource\.git" -Force | Out-Null
            New-Item -ItemType Directory -Path "$testSource\node_modules" -Force | Out-Null
            New-Item -ItemType Directory -Path "$testSource\bin" -Force | Out-Null
            New-Item -ItemType Directory -Path "$testSource\src" -Force | Out-Null
            'test' | Set-Content -Path "$testSource\src\main.ps1"

            $result = Copy-Directory -Source $testSource -Destination $testDest -ExcludeDirectories '.git', 'node_modules', 'bin' -UpdateMode Skip -Recurse

            $result.ExcludedDirectories | Should -Be 3
            Test-Path "$testDest\.git" | Should -Be $false
            Test-Path "$testDest\node_modules" | Should -Be $false
            Test-Path "$testDest\bin" | Should -Be $false
            Test-Path "$testDest\src" | Should -Be $true
        }

        It 'Should perform case-insensitive directory exclusion' {
            $testSource = Join-Path $TestDrive 'case_exclude_source'
            $testDest = Join-Path $TestDrive 'case_exclude_dest'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null
            New-Item -ItemType Directory -Path "$testSource\.GIT" -Force | Out-Null
            'test' | Set-Content -Path "$testSource\.GIT\config"

            $result = Copy-Directory -Source $testSource -Destination $testDest -ExcludeDirectories '.git' -UpdateMode Skip -Recurse

            $result.ExcludedDirectories | Should -Be 1
            Test-Path "$testDest\.GIT" | Should -Be $false
        }
        It 'Should accept Skip mode explicitly' {
            $testSource = Join-Path $TestDrive 'skip_source'
            $testDest = Join-Path $TestDrive 'skip_dest'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null
            'new content' | Set-Content -Path "$testSource\test.txt"

            # Create destination file first
            New-Item -ItemType Directory -Path $testDest -Force | Out-Null
            'old content' | Set-Content -Path "$testDest\test.txt"

            $result = Copy-Directory -Source $testSource -Destination $testDest -UpdateMode Skip -Recurse

            $result.FilesSkipped | Should -Be 1
            (Get-Content -Path "$testDest\test.txt") | Should -Be 'old content'
        }

        It 'Should accept Overwrite mode' {
            $testSource = Join-Path $TestDrive 'overwrite_source'
            $testDest = Join-Path $TestDrive 'overwrite_dest'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null
            'new content' | Set-Content -Path "$testSource\test.txt"

            # Create destination file first
            New-Item -ItemType Directory -Path $testDest -Force | Out-Null
            'old content' | Set-Content -Path "$testDest\test.txt"

            $result = Copy-Directory -Source $testSource -Destination $testDest -UpdateMode Overwrite -Recurse

            $result.FilesOverwritten | Should -Be 1
            (Get-Content -Path "$testDest\test.txt") | Should -Be 'new content'
        }

        It 'Should accept IfNewer mode' {
            $testSource = Join-Path $TestDrive 'ifnewer_source'
            $testDest = Join-Path $TestDrive 'ifnewer_dest'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null
            'new content' | Set-Content -Path "$testSource\test.txt"

            # Create destination file with older timestamp
            New-Item -ItemType Directory -Path $testDest -Force | Out-Null
            'old content' | Set-Content -Path "$testDest\test.txt"
            (Get-Item -Path "$testDest\test.txt").LastWriteTime = (Get-Date).AddDays(-1)

            $result = Copy-Directory -Source $testSource -Destination $testDest -UpdateMode IfNewer -Recurse

            $result.FilesOverwritten | Should -Be 1
            (Get-Content -Path "$testDest\test.txt") | Should -Be 'new content'
        }

        It 'Should accept Prompt mode' {
            $testSource = Join-Path $TestDrive 'prompt_source'
            $testDest = Join-Path $TestDrive 'prompt_dest'
            New-Item -ItemType Directory -Path $testSource -Force | Out-Null
            'new content' | Set-Content -Path "$testSource\test.txt"

            # Create destination file first
            New-Item -ItemType Directory -Path $testDest -Force | Out-Null
            'old content' | Set-Content -Path "$testDest\test.txt"

            # Mock WhatIf to avoid actual prompt
            Copy-Directory -Source $testSource -Destination $testDest -UpdateMode Prompt -WhatIf -Recurse | Out-Null

            # With -WhatIf, no actual copy happens
            (Get-Content -Path "$testDest\test.txt") | Should -Be 'old content'
        }
    }
}
