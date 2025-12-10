BeforeAll {
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Get-VideoDetails.ps1"
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Invoke-FFmpeg.ps1"
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Rename-VideoSeasonFile.ps1"

    # Check if required external dependencies are available
    $script:HasFFprobe = $null -ne (Get-Command 'ffprobe' -ErrorAction SilentlyContinue)
    $script:HasFFmpeg = $null -ne (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue)
}

Describe 'MediaProcessing Functions Integration' -Tag 'Integration' {
    Context 'Recurse Parameter Consistency' {
        It 'All functions should have Recurse parameter' {
            $functions = @('Get-VideoDetails', 'Invoke-FFmpeg', 'Rename-VideoSeasonFile')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $command.Parameters.ContainsKey('Recurse') | Should -Be $true -Because "$funcName should have Recurse parameter"
            }
        }

        It 'No functions should have NoRecursion parameter' {
            $functions = @('Get-VideoDetails', 'Invoke-FFmpeg', 'Rename-VideoSeasonFile')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $command.Parameters.ContainsKey('NoRecursion') | Should -Be $false -Because "$funcName should not have NoRecursion parameter"
            }
        }

        It 'All functions should have Exclude parameter' {
            $functions = @('Get-VideoDetails', 'Invoke-FFmpeg', 'Rename-VideoSeasonFile')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $command.Parameters.ContainsKey('Exclude') | Should -Be $true -Because "$funcName should have Exclude parameter"
            }
        }
    }

    Context 'Parameter Types Consistency' {
        It 'All Recurse parameters should be Switch type' {
            $functions = @('Get-VideoDetails', 'Invoke-FFmpeg', 'Rename-VideoSeasonFile')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $recurseParam = $command.Parameters['Recurse']
                $recurseParam.ParameterType.Name | Should -Be 'SwitchParameter' -Because "$funcName Recurse parameter should be Switch type"
            }
        }

        It 'All Exclude parameters should be String array type' {
            $functions = @('Get-VideoDetails', 'Invoke-FFmpeg', 'Rename-VideoSeasonFile')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $excludeParam = $command.Parameters['Exclude']
                $excludeParam.ParameterType.Name | Should -Be 'String[]' -Because "$funcName Exclude parameter should be String array type"
            }
        }
    }

    Context 'Default Behavior Verification' {
        BeforeAll {
            # Create test directory structure
            $testRoot = Join-Path -Path $TestDrive -ChildPath 'IntegrationTest'
            $subDir = Join-Path -Path $testRoot -ChildPath 'SubDirectory'
            $gitDir = Join-Path -Path $testRoot -ChildPath '.git'
            $nodeDir = Join-Path -Path $testRoot -ChildPath 'node_modules'

            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $subDir -ItemType Directory -Force | Out-Null
            New-Item -Path $gitDir -ItemType Directory -Force | Out-Null
            New-Item -Path $nodeDir -ItemType Directory -Force | Out-Null

            # Create mock files in different directories
            New-Item -Path (Join-Path -Path $testRoot -ChildPath 'video1.mp4') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $testRoot -ChildPath 'video1.mkv') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $testRoot -ChildPath 'Show.S01E01.mkv') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $subDir -ChildPath 'video2.mkv') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $subDir -ChildPath 'Show.S01E02.mkv') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $gitDir -ChildPath 'somefile.mkv') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $nodeDir -ChildPath 'package.mkv') -ItemType File -Force | Out-Null
        }

        It 'Should demonstrate non-recursive default behavior for all functions' -Skip:(-not ($script:HasFFprobe -and $script:HasFFmpeg)) {
            # Test that functions work with their new default non-recursive behavior
            # Use -WhatIf where available to avoid actual processing

            # Test all functions with default (non-recursive) behavior
            { Get-VideoDetails -Path $testRoot -Verbose } | Should -Not -Throw
            { Invoke-FFmpeg -Path $testRoot -WhatIf } | Should -Not -Throw
            { Rename-VideoSeasonFile -Path $testRoot -WhatIf } | Should -Not -Throw
        }
    }
}
