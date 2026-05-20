$script:ExifToolCommand = Get-Command 'exiftool' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
    Select-Object -First 1
$script:HasExifTool = $null -ne $script:ExifToolCommand

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/MediaProcessing/Get-MediaInfo.ps1"
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Invoke-FFmpeg.ps1"
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Get-ImageMetadata.ps1"
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Remove-ImageMetadata.ps1"
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Rename-VideoSeasonFile.ps1"

    # Check if required external dependencies are available
    $script:HasFFprobe = $null -ne (Get-Command 'ffprobe' -ErrorAction SilentlyContinue)
    $script:HasFFmpeg = $null -ne (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue)
}

Describe 'MediaProcessing Functions Integration' -Tag 'Integration' {
    Context 'Recurse Parameter Consistency' {
        It 'All functions should have Recurse parameter' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $command.Parameters.ContainsKey('Recurse') | Should -Be $true -Because "$funcName should have Recurse parameter"
            }
        }

        It 'No functions should have NoRecursion parameter' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $command.Parameters.ContainsKey('NoRecursion') | Should -Be $false -Because "$funcName should not have NoRecursion parameter"
            }
        }

        It 'All functions should have Exclude parameter' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $command.Parameters.ContainsKey('Exclude') | Should -Be $true -Because "$funcName should have Exclude parameter"
            }
        }
    }

    Context 'Parameter Types Consistency' {
        It 'All Recurse parameters should be Switch type' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $recurseParam = $command.Parameters['Recurse']
                $recurseParam.ParameterType.Name | Should -Be 'SwitchParameter' -Because "$funcName Recurse parameter should be Switch type"
            }
        }

        It 'All Exclude parameters should be String array type' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile')

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
            New-Item -Path (Join-Path -Path $testRoot -ChildPath 'photo1.jpg') -ItemType File -Force | Out-Null
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
            { Get-MediaInfo -Path $testRoot -Verbose } | Should -Not -Throw
            { Invoke-FFmpeg -Path $testRoot -WhatIf } | Should -Not -Throw
            { Remove-ImageMetadata -Path $testRoot -WhatIf } | Should -Not -Throw
            { Rename-VideoSeasonFile -Path $testRoot -WhatIf } | Should -Not -Throw
        }
    }

    Context 'Image Metadata Cleanup' {
        It 'Should remove watched metadata tags through the real ExifTool verification round trip' -Skip:(-not $script:HasExifTool) {
            $testRoot = Join-Path -Path $TestDrive -ChildPath 'ImageMetadataRoundTrip'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            $sampleImage = Join-Path -Path $testRoot -ChildPath 'private-comment.gif'
            $sampleGifBytes = [Convert]::FromBase64String('R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==')
            [System.IO.File]::WriteAllBytes($sampleImage, $sampleGifBytes)

            $exifToolCommand = Get-Command 'exiftool' -CommandType Application, ExternalScript -ErrorAction Stop |
                Select-Object -First 1
            $exifToolPath = $exifToolCommand.Path
            $global:LASTEXITCODE = 0
            $metadataWriteOutput = @(& $exifToolPath -overwrite_original '-Comment=Private integration comment' $sampleImage 2>&1)
            $metadataWriteExitCode = $LASTEXITCODE
            $metadataWriteExitCode | Should -Be 0 -Because "ExifTool should stage the test metadata. Output: $($metadataWriteOutput -join ' ')"

            $beforeCleanup = Get-ImageMetadata -Path $sampleImage -ExifToolPath $exifToolPath -Tag 'Comment' -NoEmptyProperties
            $beforeCleanup.Metadata['File:Comment'] | Should -Be 'Private integration comment'

            $cleanupResult = Remove-ImageMetadata -Path $sampleImage -ExifToolPath $exifToolPath -Verify -PassThru

            $cleanupResult.MetadataRemoved | Should -Be $true
            $cleanupResult.Verified | Should -Be $true
            $cleanupResult.RemainingMetadataTags | Should -BeNullOrEmpty

            $afterCleanup = Get-ImageMetadata -Path $sampleImage -ExifToolPath $exifToolPath -Tag 'Comment' -NoEmptyProperties
            $afterCleanup.Metadata.Contains('File:Comment') | Should -Be $false
        }
    }
}
