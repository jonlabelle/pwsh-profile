BeforeAll {
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Invoke-FFmpeg.ps1"

    # Check if ffmpeg is available for integration testing
    $script:HasFFmpeg = $null -ne (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue)
}

Describe 'Invoke-FFmpeg' -Tag 'Unit' {
    Context 'Parameter Validation' {
        It 'Should have Recurse parameter' {
            $command = Get-Command Invoke-FFmpeg
            $command.Parameters.ContainsKey('Recurse') | Should -Be $true
        }

        It 'Should not have NoRecursion parameter' {
            $command = Get-Command Invoke-FFmpeg
            $command.Parameters.ContainsKey('NoRecursion') | Should -Be $false
        }

        It 'Should have Exclude parameter' {
            $command = Get-Command Invoke-FFmpeg
            $command.Parameters.ContainsKey('Exclude') | Should -Be $true
        }

        It 'Should have default Path value' {
            $command = Get-Command Invoke-FFmpeg
            $pathParam = $command.Parameters['Path']
            $pathParam.Attributes.Where({$_ -is [System.Management.Automation.ParameterAttribute]})[0].Mandatory | Should -Be $false
        }
    }

    Context 'Parameter Types' {
        It 'Should have Recurse as Switch parameter' {
            $command = Get-Command Invoke-FFmpeg
            $recurseParam = $command.Parameters['Recurse']
            $recurseParam.ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have Exclude as String array parameter' {
            $command = Get-Command Invoke-FFmpeg
            $excludeParam = $command.Parameters['Exclude']
            $excludeParam.ParameterType.Name | Should -Be 'String[]'
        }
    }

    Context 'Default Behavior' {
        BeforeAll {
            # Create test directory structure
            $testRoot = Join-Path $TestDrive 'FFmpegTest'
            $subDir = Join-Path $testRoot 'SubDirectory'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $subDir -ItemType Directory -Force | Out-Null

            # Create mock video files
            New-Item -Path (Join-Path $testRoot 'video1.mkv') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $subDir 'video2.mkv') -ItemType File -Force | Out-Null
        }

        It 'Should process non-recursively by default with -WhatIf' -Skip:(-not $script:HasFFmpeg) {
            # This test requires ffmpeg to be installed
            if (-not $script:HasFFmpeg)
            {
                Set-ItResult -Skipped -Because 'ffmpeg is not available on this system'
                return
            }

            # Test with -WhatIf to avoid actual processing
            { Invoke-FFmpeg -Path $testRoot -WhatIf } | Should -Not -Throw
        }

        It 'Should process recursively when -Recurse is specified with -WhatIf' -Skip:(-not $script:HasFFmpeg) {
            # This test requires ffmpeg to be installed
            if (-not $script:HasFFmpeg)
            {
                Set-ItResult -Skipped -Because 'ffmpeg is not available on this system'
                return
            }

            # Test with -WhatIf to avoid actual processing
            { Invoke-FFmpeg -Path $testRoot -Recurse -WhatIf } | Should -Not -Throw
        }
    }

    Context 'Individual File Support' {
        BeforeAll {
            # Create test directory and files
            $testRoot = Join-Path $TestDrive 'FFmpegFileTest'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            # Create mock video files
            $script:testVideoFile = Join-Path $testRoot 'test-video.mkv'
            $script:testNonVideoFile = Join-Path $testRoot 'test-document.txt'
            New-Item -Path $script:testVideoFile -ItemType File -Force | Out-Null
            New-Item -Path $script:testNonVideoFile -ItemType File -Force | Out-Null
        }

        It 'Should accept individual video file paths with -WhatIf' -Skip:(-not $script:HasFFmpeg) {
            if (-not $script:HasFFmpeg)
            {
                Set-ItResult -Skipped -Because 'ffmpeg is not available on this system'
                return
            }

            # Should not throw when given an individual video file
            { Invoke-FFmpeg -Path $script:testVideoFile -WhatIf } | Should -Not -Throw
        }

        It 'Should validate file extension for individual files' -Skip:(-not $script:HasFFmpeg) {
            if (-not $script:HasFFmpeg)
            {
                Set-ItResult -Skipped -Because 'ffmpeg is not available on this system'
                return
            }

            # Should warn when file extension doesn't match expected extension
            $output = Invoke-FFmpeg -Path $script:testNonVideoFile -WhatIf -WarningVariable warnings 2>&1
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Should handle non-existent file paths gracefully' -Skip:(-not $script:HasFFmpeg) {
            if (-not $script:HasFFmpeg)
            {
                Set-ItResult -Skipped -Because 'ffmpeg is not available on this system'
                return
            }

            $nonExistentFile = Join-Path $TestDrive 'does-not-exist.mkv'

            # Should handle gracefully and not crash
            { Invoke-FFmpeg -Path $nonExistentFile -WhatIf -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should support pipeline input for individual files' {
            $command = Get-Command Invoke-FFmpeg
            $pathParam = $command.Parameters['Path']

            # Check that Path parameter supports pipeline input
            $pipelineAttributes = $pathParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pipelineSupport = $pipelineAttributes | Where-Object { $_.ValueFromPipeline -eq $true -or $_.ValueFromPipelineByPropertyName -eq $true }
            $pipelineSupport | Should -Not -BeNullOrEmpty
        }
    }
}
