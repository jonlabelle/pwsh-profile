$script:ExifToolCommand = Get-Command 'exiftool' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
Select-Object -First 1
$script:HasExifTool = $null -ne $script:ExifToolCommand
$script:HasImageMagick = $null -ne (Get-Command 'magick' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue)

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/MediaProcessing/Get-MediaInfo.ps1"
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Invoke-FFmpeg.ps1"
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Get-ImageMetadata.ps1"
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Remove-ImageMetadata.ps1"
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Resize-Image.ps1"
    . "$PSScriptRoot/../../../Functions/MediaProcessing/Rename-VideoSeasonFile.ps1"

    # Check if required external dependencies are available
    $script:HasFFprobe = $null -ne (Get-Command 'ffprobe' -ErrorAction SilentlyContinue)
    $script:HasFFmpeg = $null -ne (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue)
}

Describe 'MediaProcessing Functions Integration' -Tag 'Integration' {
    Context 'Recurse Parameter Consistency' {
        It 'All functions should have Recurse parameter' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile', 'Resize-Image')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $command.Parameters.ContainsKey('Recurse') | Should-Be $true -Because "$funcName should have Recurse parameter"
            }
        }

        It 'No functions should have NoRecursion parameter' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile', 'Resize-Image')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $command.Parameters.ContainsKey('NoRecursion') | Should-Be $false -Because "$funcName should not have NoRecursion parameter"
            }
        }

        It 'All functions should have Exclude parameter' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile', 'Resize-Image')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $command.Parameters.ContainsKey('Exclude') | Should-Be $true -Because "$funcName should have Exclude parameter"
            }
        }
    }

    Context 'Parameter Types Consistency' {
        It 'All Recurse parameters should be Switch type' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile', 'Resize-Image')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $recurseParam = $command.Parameters['Recurse']
                $recurseParam.ParameterType.Name | Should-Be 'SwitchParameter' -Because "$funcName Recurse parameter should be Switch type"
            }
        }

        It 'All Exclude parameters should be String array type' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile', 'Resize-Image')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $excludeParam = $command.Parameters['Exclude']
                $excludeParam.ParameterType.Name | Should-Be 'String[]' -Because "$funcName Exclude parameter should be String array type"
            }
        }
    }

    Context 'Filter Parameter Consistency' {
        It 'All functions should have Filter parameter' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile', 'Resize-Image')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $command.Parameters.ContainsKey('Filter') | Should-Be $true -Because "$funcName should have Filter parameter"
            }
        }

        It 'All Filter parameters should be String array type' {
            $functions = @('Get-MediaInfo', 'Invoke-FFmpeg', 'Remove-ImageMetadata', 'Rename-VideoSeasonFile', 'Resize-Image')

            foreach ($funcName in $functions)
            {
                $command = Get-Command $funcName
                $filterParam = $command.Parameters['Filter']
                $filterParam.ParameterType.Name | Should-Be 'String[]' -Because "$funcName Filter parameter should be String array type"
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
            { Resize-Image -Path $testRoot -Width 100 -WhatIf } | Should -Not -Throw
            { Rename-VideoSeasonFile -Path $testRoot -WhatIf } | Should -Not -Throw
        }
    }

    Context 'Image Metadata Cleanup' {
        It 'Should verify watched tags on a sanitized copy with a custom extension' -Skip:(-not $script:HasExifTool) {
            $testRoot = Join-Path -Path $TestDrive -ChildPath 'ImageMetadataRoundTrip'
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            $sampleImage = Join-Path -Path $testRoot -ChildPath 'private-comment.gif'
            $outputImage = Join-Path -Path $testRoot -ChildPath 'clean [1].dat'
            $sampleGifBytes = [Convert]::FromBase64String('R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==')
            [System.IO.File]::WriteAllBytes($sampleImage, $sampleGifBytes)

            $exifToolCommand = Get-Command 'exiftool' -CommandType Application, ExternalScript -ErrorAction Stop |
            Select-Object -First 1
            $exifToolPath = $exifToolCommand.Path
            $global:LASTEXITCODE = 0
            $metadataWriteOutput = @(& $exifToolPath -overwrite_original '-Comment=Private integration comment' $sampleImage 2>&1)
            $metadataWriteExitCode = $LASTEXITCODE
            $metadataWriteExitCode | Should-Be 0 -Because "ExifTool should stage the test metadata. Output: $($metadataWriteOutput -join ' ')"

            $beforeCleanup = Get-ImageMetadata -Path $sampleImage -ExifToolPath $exifToolPath -Tag 'Comment' -NoEmptyProperties
            $beforeCleanup.Metadata['File:Comment'] | Should-Be 'Private integration comment'

            $cleanupResult = Remove-ImageMetadata -Path $sampleImage -OutputPath $outputImage -ExifToolPath $exifToolPath -Verify

            $cleanupResult.MetadataRemoved | Should-Be $true
            $cleanupResult.RemovedMetadataTagCount | Should-BeGreaterThan 0
            $cleanupResult.RemovedMetadataTags | Should-ContainCollection 'File:Comment'
            $cleanupResult.Verified | Should-Be $true
            $cleanupResult.RemainingMetadataTags | Should -BeNullOrEmpty

            $afterCleanup = Get-ImageMetadata -Path $outputImage -Filter '*' -ExifToolPath $exifToolPath -PrivacyOnly
            $afterCleanup.TagCount | Should-Be 0
        }

        It 'Should verify paranoid JPEG cleanup when only the remover is loaded' -Skip:(-not ($script:HasExifTool -and $script:HasImageMagick)) {
            $sampleImage = Join-Path -Path $TestDrive -ChildPath 'photo [1].jpeg'
            $null = & magick -size 8x6 'xc:gold' $sampleImage
            $LASTEXITCODE | Should-Be 0
            $null = & exiftool -overwrite_original '-Make=Test Camera' '-Comment=Synthetic comment' $sampleImage
            $LASTEXITCODE | Should-Be 0

            $cleanerPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../Functions/MediaProcessing/Remove-ImageMetadata.ps1'
            $isolatedSession = [PowerShell]::Create()
            try
            {
                $null = $isolatedSession.AddScript({
                        param($ScriptPath, $ImagePath)
                        . $ScriptPath
                        Remove-ImageMetadata -Path $ImagePath -Paranoid -Verify -ErrorAction Stop
                    }).AddArgument($cleanerPath).AddArgument($sampleImage)
                $cleanupResult = $isolatedSession.Invoke()
            }
            finally
            {
                $isolatedSession.Dispose()
            }

            $cleanupResult.Count | Should-Be 1
            $cleanupResult.MetadataRemoved | Should-Be $true
            $cleanupResult.Verified | Should-Be $true
            $cleanupResult.RemovedMetadataTags | Should-ContainCollection 'File:Comment'
            $cleanupResult.RemovedMetadataTags | Should-ContainCollection 'IFD0:Make'

            $allTags = Get-ImageMetadata -Path $sampleImage
            $allTags.Metadata['File:ImageWidth'] | Should-Be 8
            $allTags.MetadataTags | Should-ContainCollection 'System:FileName'
            $privacyTags = Get-ImageMetadata -Path $sampleImage -PrivacyOnly
            $privacyTags.TagCount | Should-Be 0
        }

        It 'Should remove common TIFF metadata and retain the image fields' -Skip:(-not ($script:HasExifTool -and $script:HasImageMagick)) {
            $sampleImage = Join-Path -Path $TestDrive -ChildPath 'scan.tiff'
            $null = & magick -size 8x6 'xc:gold' -strip $sampleImage
            $LASTEXITCODE | Should-Be 0
            $metadataArgs = @(
                '-IFD0:Artist=Test Artist'
                '-IFD0:ModifyDate=2024:01:02 03:04:05'
                '-IFD0:DocumentName=Test Scan'
                '-IFD0:HostComputer=Test Host'
                '-IFD0:CameraSerialNumber=Synthetic serial'
            )
            $null = & exiftool -overwrite_original @metadataArgs $sampleImage
            $LASTEXITCODE | Should-Be 0

            $cleanupResult = Remove-ImageMetadata -Path $sampleImage -Verify

            $cleanupResult.Verified | Should-Be $true
            $cleanupResult.RemovedMetadataTags | Should-ContainCollection 'IFD0:Artist'
            $cleanupResult.RemovedMetadataTags | Should-ContainCollection 'IFD0:ModifyDate'
            $cleanupResult.RemovedMetadataTags | Should-ContainCollection 'IFD0:DocumentName'
            $cleanupResult.RemovedMetadataTags | Should-ContainCollection 'IFD0:HostComputer'
            $cleanupResult.RemovedMetadataTags | Should-ContainCollection 'IFD0:CameraSerialNumber'
            $afterCleanup = Get-ImageMetadata -Path $sampleImage
            $afterCleanup.Metadata['IFD0:ImageWidth'] | Should-Be 8
        }

        It 'Should detect and remove custom PNG text tags' -Skip:(-not ($script:HasExifTool -and $script:HasImageMagick)) {
            $sampleImage = Join-Path -Path $TestDrive -ChildPath 'custom-text.png'
            $null = & magick -size 8x6 'xc:gold' -set 'FixtureIdentifier' 'Synthetic text' $sampleImage
            $LASTEXITCODE | Should-Be 0

            $beforeCleanup = Get-ImageMetadata -Path $sampleImage -PrivacyOnly
            $beforeCleanup.Metadata['PNG:FixtureIdentifier'] | Should-Be 'Synthetic text'
            $beforeCleanup.Metadata.Contains('PNG:ImageWidth') | Should-Be $false

            $cleanupResult = Remove-ImageMetadata -Path $sampleImage -Verify

            $cleanupResult.Verified | Should-Be $true
            $cleanupResult.RemovedMetadataTags | Should-ContainCollection 'PNG:FixtureIdentifier'
        }
    }
}
