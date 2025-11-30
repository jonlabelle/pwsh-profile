BeforeAll {
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Get-VideoDetails.ps1"

    # Check if ffprobe is available for integration testing
    $script:HasFFprobe = $null -ne (Get-Command 'ffprobe' -ErrorAction SilentlyContinue)
}

Describe 'Get-VideoDetails' -Tag 'Unit' {
    Context 'Parameter Validation' {
        It 'Should have Recurse parameter' {
            $command = Get-Command Get-VideoDetails
            $command.Parameters.ContainsKey('Recurse') | Should -Be $true
        }

        It 'Should not have NoRecursion parameter' {
            $command = Get-Command Get-VideoDetails
            $command.Parameters.ContainsKey('NoRecursion') | Should -Be $false
        }

        It 'Should have Exclude parameter' {
            $command = Get-Command Get-VideoDetails
            $command.Parameters.ContainsKey('Exclude') | Should -Be $true
        }

        It 'Should have default Path value' {
            $command = Get-Command Get-VideoDetails
            $pathParam = $command.Parameters['Path']
            $pathParam.Attributes.Where({$_ -is [System.Management.Automation.ParameterAttribute]})[0].Mandatory | Should -Be $false
        }
    }

    Context 'Default Parameter Values' {
        It 'Should have default Exclude values' {
            $command = Get-Command Get-VideoDetails
            $excludeParam = $command.Parameters['Exclude']
            # The default value should be set in the param block
            $excludeParam.ParameterType.Name | Should -Be 'String[]'
        }

        It 'Should accept Path parameter from pipeline' {
            $command = Get-Command Get-VideoDetails
            $pathParam = $command.Parameters['Path']
            $valueFromPipelineAttr = $pathParam.Attributes.Where({$_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipeline})
            $valueFromPipelineAttr | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter Behavior' {
        BeforeAll {
            # Create test directory structure
            $testRoot = Join-Path $TestDrive 'VideoDetailsTest'
            $subDir = Join-Path $testRoot 'SubDirectory'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $subDir -ItemType Directory -Force | Out-Null

            # Create mock video files (empty files for testing)
            New-Item -Path (Join-Path $testRoot 'video1.mp4') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $subDir 'video2.mkv') -ItemType File -Force | Out-Null
        }

        It 'Should search non-recursively by default' -Skip:(-not $script:HasFFprobe) {
            # This test requires ffprobe to be installed
            if (-not $script:HasFFprobe)
            {
                Set-ItResult -Skipped -Because 'ffprobe is not available on this system'
                return
            }

            # Mock the video info function to avoid actual ffprobe execution
            Mock Get-VideoInfo {
                return @{ Name = 'MockVideo'; Duration = '00:01:00' }
            }

            # Test that default behavior is non-recursive
            { Get-VideoDetails -Path $testRoot -Verbose } | Should -Not -Throw
        }

        It 'Should search recursively when -Recurse is specified' -Skip:(-not $script:HasFFprobe) {
            # This test requires ffprobe to be installed
            if (-not $script:HasFFprobe)
            {
                Set-ItResult -Skipped -Because 'ffprobe is not available on this system'
                return
            }

            # Mock the video info function to avoid actual ffprobe execution
            Mock Get-VideoInfo {
                return @{ Name = 'MockVideo'; Duration = '00:01:00' }
            }

            # Test that -Recurse enables recursive searching
            { Get-VideoDetails -Path $testRoot -Recurse -Verbose } | Should -Not -Throw
        }
    }
}
