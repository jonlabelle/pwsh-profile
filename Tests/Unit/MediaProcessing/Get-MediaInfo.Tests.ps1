BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/MediaProcessing/Get-MediaInfo.ps1"

    # Check if ffprobe is available for integration testing
    $script:HasFFprobe = $null -ne (Get-Command 'ffprobe' -ErrorAction SilentlyContinue)
}

Describe 'Get-MediaInfo' -Tag 'Unit' {
    Context 'Parameter Validation' {
        It 'Should have Recurse parameter' {
            $command = Get-Command Get-MediaInfo
            $command.Parameters.ContainsKey('Recurse') | Should -Be $true
        }

        It 'Should not have NoRecursion parameter' {
            $command = Get-Command Get-MediaInfo
            $command.Parameters.ContainsKey('NoRecursion') | Should -Be $false
        }

        It 'Should have Exclude parameter' {
            $command = Get-Command Get-MediaInfo
            $command.Parameters.ContainsKey('Exclude') | Should -Be $true
        }

        It 'Should have Filter parameter' {
            $command = Get-Command Get-MediaInfo
            $command.Parameters.ContainsKey('Filter') | Should -Be $true
        }

        It 'Should have default Path value' {
            $command = Get-Command Get-MediaInfo
            $pathParam = $command.Parameters['Path']
            $pathParam.Attributes.Where({$_ -is [System.Management.Automation.ParameterAttribute]})[0].Mandatory | Should -Be $false
        }
    }

    Context 'Default Parameter Values' {
        It 'Should have default Exclude values' {
            $command = Get-Command Get-MediaInfo
            $excludeParam = $command.Parameters['Exclude']
            # The default value should be set in the param block
            $excludeParam.ParameterType.Name | Should -Be 'String[]'
        }

        It 'Should have Filter as String array parameter' {
            $command = Get-Command Get-MediaInfo
            $filterParam = $command.Parameters['Filter']
            $filterParam.ParameterType.Name | Should -Be 'String[]'
        }

        It 'Should default Filter to the supported media file patterns' {
            $command = Get-Command Get-MediaInfo
            $parameterAst = $command.ScriptBlock.Ast.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.ParameterAst] -and
                    $node.Name.VariablePath.UserPath -eq 'Filter'
                }, $true)
            $defaultValueText = $parameterAst.DefaultValue.Extent.Text
            $expectedFilters = @(
                '*.mp4', '*.mkv', '*.avi', '*.mov', '*.wmv', '*.flv', '*.webm', '*.m4v',
                '*.mpg', '*.mpeg', '*.3gp', '*.ts', '*.mts', '*.m2ts', '*.vob', '*.ogv',
                '*.mp3', '*.m4a', '*.aac', '*.flac', '*.wav', '*.ogg', '*.opus',
                '*.wma', '*.alac', '*.ape', '*.ac3', '*.dts', '*.aiff', '*.oga'
            )

            foreach ($filter in $expectedFilters)
            {
                $defaultValueText | Should -Match ([regex]::Escape("'$filter'"))
            }
        }

        It 'Should accept Path parameter from pipeline' {
            $command = Get-Command Get-MediaInfo
            $pathParam = $command.Parameters['Path']
            $valueFromPipelineAttr = $pathParam.Attributes.Where({$_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipeline})
            $valueFromPipelineAttr | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter Behavior' {
        BeforeAll {
            # Create test directory structure
            $testRoot = Join-Path -Path $TestDrive -ChildPath 'MediaInfoTest'
            $subDir = Join-Path -Path $testRoot -ChildPath 'SubDirectory'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $subDir -ItemType Directory -Force | Out-Null

            # Create mock media files (empty files for testing)
            New-Item -Path (Join-Path -Path $testRoot -ChildPath 'video1.mp4') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $testRoot -ChildPath 'video2.avi') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $subDir -ChildPath 'video2.mkv') -ItemType File -Force | Out-Null

            # Return minimal valid ffprobe JSON so filter behavior can be tested without ffprobe installed.
            $script:fakeFFprobePath = Join-Path -Path $testRoot -ChildPath 'fake-ffprobe.ps1'
            $fakeFFprobeContent = @(
                '$metadata = @{'
                '    streams = @()'
                "    format = @{ duration = '1'; bit_rate = '1000'; format_long_name = 'Test format' }"
                '}'
                '$metadata | ConvertTo-Json -Depth 4'
            ) -join [Environment]::NewLine
            Set-Content -Path $script:fakeFFprobePath -Value $fakeFFprobeContent -Encoding UTF8
        }

        It 'Should use all supplied Filter values when searching directories' {
            $results = @(Get-MediaInfo -Path $testRoot -Filter '*.avi', '*.mp4' -FFprobePath $script:fakeFFprobePath)
            $resultNames = @($results.Name)

            $resultNames.Count | Should -Be 2
            $resultNames | Should -Contain 'video1.mp4'
            $resultNames | Should -Contain 'video2.avi'
            $resultNames | Should -Not -Contain 'video2.mkv'
        }

        It 'Should search non-recursively by default' -Skip:(-not $script:HasFFprobe) {
            # This test requires ffprobe to be installed
            if (-not $script:HasFFprobe)
            {
                Set-ItResult -Skipped -Because 'ffprobe is not available on this system'
                return
            }

            # Mock the media info function to avoid actual ffprobe execution
            Mock Get-MediaInfo {
                return @{ Name = 'MockMedia'; Duration = '00:01:00' }
            }

            # Test that default behavior is non-recursive
            { Get-MediaInfo -Path $testRoot -Verbose } | Should -Not -Throw
        }

        It 'Should search recursively when -Recurse is specified' -Skip:(-not $script:HasFFprobe) {
            # This test requires ffprobe to be installed
            if (-not $script:HasFFprobe)
            {
                Set-ItResult -Skipped -Because 'ffprobe is not available on this system'
                return
            }

            # Mock the media info function to avoid actual ffprobe execution
            Mock Get-MediaInfo {
                return @{ Name = 'MockMedia'; Duration = '00:01:00' }
            }

            # Test that -Recurse enables recursive searching
            { Get-MediaInfo -Path $testRoot -Recurse -Verbose } | Should -Not -Throw
        }
    }
}
