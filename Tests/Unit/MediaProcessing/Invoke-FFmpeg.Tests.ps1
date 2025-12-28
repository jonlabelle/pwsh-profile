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
            $testRoot = Join-Path -Path $TestDrive -ChildPath 'FFmpegTest'
            $subDir = Join-Path -Path $testRoot -ChildPath 'SubDirectory'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $subDir -ItemType Directory -Force | Out-Null

            # Create mock video files
            New-Item -Path (Join-Path -Path $testRoot -ChildPath 'video1.mkv') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $subDir -ChildPath 'video2.mkv') -ItemType File -Force | Out-Null
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
            $testRoot = Join-Path -Path $TestDrive -ChildPath 'FFmpegFileTest'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            # Create mock video files
            $script:testVideoFile = Join-Path -Path $testRoot -ChildPath 'test-video.mkv'
            $script:testNonVideoFile = Join-Path -Path $testRoot -ChildPath 'test-document.txt'
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
            Invoke-FFmpeg -Path $script:testNonVideoFile -WhatIf -WarningVariable warnings 2>&1 | Out-Null
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Should handle non-existent file paths gracefully' -Skip:(-not $script:HasFFmpeg) {
            if (-not $script:HasFFmpeg)
            {
                Set-ItResult -Skipped -Because 'ffmpeg is not available on this system'
                return
            }

            $nonExistentFile = Join-Path -Path $TestDrive -ChildPath 'does-not-exist.mkv'

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

    Context 'Closed Captions' {
        BeforeAll {
            $testRoot = Join-Path -Path $TestDrive -ChildPath 'FFmpegClosedCaptions'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            $script:ccVideoPath = Join-Path -Path $testRoot -ChildPath 'cc-source.mkv'
            Set-Content -Path $script:ccVideoPath -Value 'fake video data'

            $script:ffmpegLogPath = Join-Path -Path $testRoot -ChildPath 'ffmpeg-args.log'
            $script:fakeFFmpegPath = Join-Path -Path $testRoot -ChildPath 'ffmpeg.ps1'
            $ffprobeShimPath = Join-Path -Path $testRoot -ChildPath 'ffprobe.ps1'

            # Fake ffmpeg shim writes received arguments to a log file for inspection
            $ffmpegShimContent = @(
                'param(',
                '    [Parameter(ValueFromRemainingArguments = $true)]',
                '    [string[]]$Args',
                ')',
                ("`$Args -join ' ' | Out-File -FilePath '{0}' -Append -Encoding utf8" -f $script:ffmpegLogPath),
                'exit 0'
            ) -join [Environment]::NewLine
            Set-Content -Path $script:fakeFFmpegPath -Value $ffmpegShimContent -Encoding UTF8

            # Provide a stub ffprobe path for dependency resolution
            Set-Content -Path $ffprobeShimPath -Value '#!/usr/bin/env pwsh' -Encoding UTF8
        }

        BeforeEach {
            if (Test-Path -Path $script:ffmpegLogPath)
            {
                Remove-Item -Path $script:ffmpegLogPath -Force
            }
        }

        It 'Should map closed captions from input to output when subtitles are included' {
            Mock -CommandName Get-MediaInfo -MockWith {
                [pscustomobject]@{
                    Audio = @(
                        [pscustomobject]@{
                            Channels = 2
                            SampleRate = 48000
                            Codec = 'aac'
                        }
                    )
                    Subtitles = @(
                        [pscustomobject]@{
                            Index = 2
                            Codec = 'eia_608'
                            CodecLong = 'CEA-608 closed captions'
                            Language = 'eng'
                            Title = 'CC'
                            Forced = $false
                            Default = $true
                            HearingImpaired = $false
                        }
                    )
                }
            }

            Invoke-FFmpeg -Path $script:ccVideoPath -FFmpegPath $script:fakeFFmpegPath -Force | Out-Null

            $loggedArgs = Get-Content -Path $script:ffmpegLogPath
            $loggedArgs | Should -Not -BeNullOrEmpty
            ($loggedArgs -join ' ') | Should -Match '-scodec mov_text'
            ($loggedArgs -join ' ') | Should -Match '-map 0:2'
        }
    }
}
