BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/MediaProcessing/Get-ImageMetadata.ps1"

    function Get-FakeExifTool
    {
        param([String]$RootPath)

        $logPath = Join-Path -Path $RootPath -ChildPath 'exiftool-args.log'
        $toolPath = Join-Path -Path $RootPath -ChildPath 'exiftool.ps1'
        $escapedLogPath = $logPath.Replace("'", "''")

        $fakeExifToolContent = @(
            'param(',
            '    [Parameter(ValueFromRemainingArguments = $true)]',
            '    [Object[]]$RemainingArgs',
            ')',
            ("`$RemainingArgs -join [Environment]::NewLine | Add-Content -LiteralPath '{0}' -Encoding UTF8" -f $escapedLogPath),
            ("Add-Content -LiteralPath '{0}' -Value '---' -Encoding UTF8" -f $escapedLogPath),
            '$filePath = [String]$RemainingArgs[$RemainingArgs.Count - 1]',
            '$metadata = [ordered]@{}',
            '$metadata[''SourceFile''] = $filePath',
            '$metadata[''File:FileName''] = [System.IO.Path]::GetFileName($filePath)',
            '$metadata[''File:ImageWidth''] = 1024',
            '$metadata[''File:ImageHeight''] = 768',
            '$metadata[''EXIF:Make''] = ''Test Camera''',
            '$metadata[''EXIF:Model''] = ''''',
            '$metadata[''GPS:GPSLatitude''] = 41.88',
            '$metadata[''XMP:Title''] = ''Sample Title''',
            '$global:LASTEXITCODE = 0',
            '[PSCustomObject]$metadata | ConvertTo-Json -Depth 8'
        ) -join [Environment]::NewLine

        Set-Content -LiteralPath $toolPath -Value $fakeExifToolContent -Encoding UTF8

        return [PSCustomObject]@{
            Path = $toolPath
            LogPath = $logPath
        }
    }
}

Describe 'Get-ImageMetadata' -Tag 'Unit' {
    Context 'Parameter Validation' {
        It 'Should have Recurse parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters.ContainsKey('Recurse') | Should -Be $true
        }

        It 'Should have Exclude parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters.ContainsKey('Exclude') | Should -Be $true
        }

        It 'Should have Filters parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters.ContainsKey('Filters') | Should -Be $true
        }

        It 'Should have ExifToolPath parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters.ContainsKey('ExifToolPath') | Should -Be $true
        }

        It 'Should have Tag parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters.ContainsKey('Tag') | Should -Be $true
        }

        It 'Should have Flatten parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters.ContainsKey('Flatten') | Should -Be $true
        }

        It 'Should have NoEmptyProperties parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters.ContainsKey('NoEmptyProperties') | Should -Be $true
        }

        It 'Should have Numeric parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters.ContainsKey('Numeric') | Should -Be $true
        }

        It 'Should have IncludeRawExifToolData parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters.ContainsKey('IncludeRawExifToolData') | Should -Be $true
        }

        It 'Should accept Path parameter from pipeline and by property name' {
            $command = Get-Command Get-ImageMetadata
            $pathParam = $command.Parameters['Path']
            $pipelineAttributes = $pathParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pipelineSupport = $pipelineAttributes | Where-Object { $_.ValueFromPipeline -eq $true -or $_.ValueFromPipelineByPropertyName -eq $true }

            $pipelineSupport | Should -Not -BeNullOrEmpty
        }

        It 'Should include file and directory aliases for Path' {
            $command = Get-Command Get-ImageMetadata
            $aliases = $command.Parameters['Path'].Aliases

            $aliases | Should -Contain 'FilePath'
            $aliases | Should -Contain 'FullName'
            $aliases | Should -Contain 'Directory'
        }

        It 'Should include Tags alias for Tag' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters['Tag'].Aliases | Should -Contain 'Tags'
        }
    }

    Context 'Parameter Types' {
        It 'Should have Recurse as Switch parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters['Recurse'].ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have Exclude as String array parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters['Exclude'].ParameterType.Name | Should -Be 'String[]'
        }

        It 'Should have Filters as String array parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters['Filters'].ParameterType.Name | Should -Be 'String[]'
        }

        It 'Should have Tag as String array parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters['Tag'].ParameterType.Name | Should -Be 'String[]'
        }

        It 'Should have Flatten as Switch parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters['Flatten'].ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have Numeric as Switch parameter' {
            $command = Get-Command Get-ImageMetadata
            $command.Parameters['Numeric'].ParameterType.Name | Should -Be 'SwitchParameter'
        }
    }

    Context 'Dependency Install Hints' {
        It 'Should include an Install-PlatformPackage hint when ExifTool is missing' {
            $missingExifToolPath = Join-Path -Path $TestDrive -ChildPath 'missing-exiftool'
            $exception = $null

            try
            {
                Get-ImageMetadata -Path $TestDrive -ExifToolPath $missingExifToolPath -ErrorAction Stop
            }
            catch
            {
                $exception = $_.Exception
            }

            $exception | Should -Not -BeNullOrEmpty
            $exception.Message | Should -BeLike '*Install-PlatformPackage.ps1*'
            $exception.Message | Should -Not -BeLike '*. ./Functions/SystemAdministration/Install-PlatformPackage.ps1*'
            $exception.Message | Should -Not -BeLike '*-PackageManager*'
            $exception.Message | Should -Not -BeLike '*-Id*'
            $exception.Message | Should -Match '(-Name OliverBetz\.ExifTool|-Name exiftool|-Name libimage-exiftool-perl)'
        }
    }

    Context 'Default Behavior' {
        BeforeEach {
            $script:TestRoot = Join-Path -Path $TestDrive -ChildPath "ImageMetadataTest-$(Get-Random)"
            $script:SubDir = Join-Path -Path $script:TestRoot -ChildPath 'SubDirectory'
            $script:GitDir = Join-Path -Path $script:TestRoot -ChildPath '.git'

            New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $script:SubDir -ItemType Directory -Force | Out-Null
            New-Item -Path $script:GitDir -ItemType Directory -Force | Out-Null

            New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'photo1.jpg') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'photo2.png') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'notes.txt') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:SubDir -ChildPath 'photo3.jpg') -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:GitDir -ChildPath 'hidden.jpg') -ItemType File -Force | Out-Null

            $script:FakeExifTool = Get-FakeExifTool -RootPath $script:TestRoot
        }

        It 'Should inspect image files non-recursively by default' {
            $results = @(Get-ImageMetadata -Path $script:TestRoot -ExifToolPath $script:FakeExifTool.Path)

            $results.Count | Should -Be 2
            $results.Name | Should -Contain 'photo1.jpg'
            $results.Name | Should -Contain 'photo2.png'
            $results.Name | Should -Not -Contain 'photo3.jpg'
            $results.Name | Should -Not -Contain 'notes.txt'
        }

        It 'Should inspect recursively when -Recurse is specified' {
            $results = @(Get-ImageMetadata -Path $script:TestRoot -Recurse -ExifToolPath $script:FakeExifTool.Path)

            $results.Name | Should -Contain 'photo1.jpg'
            $results.Name | Should -Contain 'photo2.png'
            $results.Name | Should -Contain 'photo3.jpg'
            $results.Name | Should -Not -Contain 'hidden.jpg'
        }

        It 'Should respect Exclude parameter when using -Recurse' {
            $results = @(Get-ImageMetadata -Path $script:TestRoot -Recurse -Exclude @('.git', 'SubDirectory') -ExifToolPath $script:FakeExifTool.Path)

            $results.Name | Should -Contain 'photo1.jpg'
            $results.Name | Should -Contain 'photo2.png'
            $results.Name | Should -Not -Contain 'photo3.jpg'
            $results.Name | Should -Not -Contain 'hidden.jpg'
        }

        It 'Should honor custom Filters' {
            $results = @(Get-ImageMetadata -Path $script:TestRoot -Filters '*.png' -ExifToolPath $script:FakeExifTool.Path)

            $results.Count | Should -Be 1
            $results.Name | Should -Contain 'photo2.png'
        }
    }

    Context 'Individual File Support' {
        BeforeEach {
            $script:FileTestRoot = Join-Path -Path $TestDrive -ChildPath "ImageMetadataFileTest-$(Get-Random)"
            New-Item -Path $script:FileTestRoot -ItemType Directory -Force | Out-Null

            $script:TestImageFile = Join-Path -Path $script:FileTestRoot -ChildPath 'single-photo.jpg'
            $script:TestNonImageFile = Join-Path -Path $script:FileTestRoot -ChildPath 'document.txt'

            New-Item -Path $script:TestImageFile -ItemType File -Force | Out-Null
            New-Item -Path $script:TestNonImageFile -ItemType File -Force | Out-Null

            $script:FakeExifTool = Get-FakeExifTool -RootPath $script:FileTestRoot
        }

        It 'Should accept an individual image file path' {
            $result = @(Get-ImageMetadata -Path $script:TestImageFile -ExifToolPath $script:FakeExifTool.Path)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'single-photo.jpg'
        }

        It 'Should warn when an individual file does not match supported filters' {
            $result = @(Get-ImageMetadata -Path $script:TestNonImageFile -ExifToolPath $script:FakeExifTool.Path -WarningAction SilentlyContinue -WarningVariable warnings)

            $result.Count | Should -Be 0
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Should report an error for a missing path' {
            $missingPath = Join-Path -Path $TestDrive -ChildPath 'missing-photo.jpg'

            $null = Get-ImageMetadata -Path $missingPath -ExifToolPath $script:FakeExifTool.Path -ErrorAction SilentlyContinue -ErrorVariable errors

            $errors.Count | Should -BeGreaterThan 0
            $errors[0].Exception.Message | Should -BeLike '*not found*'
        }

        It 'Should accept image files from the pipeline' {
            $result = @(Get-Item -LiteralPath $script:TestImageFile | Get-ImageMetadata -ExifToolPath $script:FakeExifTool.Path)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'single-photo.jpg'
        }
    }

    Context 'ExifTool Invocation' {
        BeforeEach {
            $script:InvokeTestRoot = Join-Path -Path $TestDrive -ChildPath "ExifToolMetadataTest-$(Get-Random)"
            New-Item -Path $script:InvokeTestRoot -ItemType Directory -Force | Out-Null

            $script:SampleImage = Join-Path -Path $script:InvokeTestRoot -ChildPath 'metadata-photo.jpg'
            New-Item -Path $script:SampleImage -ItemType File -Force | Out-Null

            $script:FakeExifTool = Get-FakeExifTool -RootPath $script:InvokeTestRoot
        }

        It 'Should call ExifTool with default JSON metadata arguments' {
            $result = Get-ImageMetadata -Path $script:SampleImage -ExifToolPath $script:FakeExifTool.Path

            $loggedArgs = Get-Content -LiteralPath $script:FakeExifTool.LogPath
            $loggedArgs | Should -Contain '-j'
            $loggedArgs | Should -Contain '-a'
            $loggedArgs | Should -Contain '-G1'
            $loggedArgs | Should -Contain '-struct'
            $loggedArgs | Should -Contain '-all:all'
            $loggedArgs | Should -Contain $script:SampleImage
            $result.Metadata.Keys | Should -Contain 'EXIF:Make'
            $result.Metadata['EXIF:Make'] | Should -Be 'Test Camera'
        }

        It 'Should call ExifTool with selected tags and numeric output' {
            $result = Get-ImageMetadata -Path $script:SampleImage -Tag 'EXIF:Make', 'GPS:all' -Numeric -NoEmptyProperties -IncludeRawExifToolData -ExifToolPath $script:FakeExifTool.Path

            $loggedArgs = Get-Content -LiteralPath $script:FakeExifTool.LogPath
            $loggedArgs | Should -Contain '-EXIF:Make'
            $loggedArgs | Should -Contain '-GPS:all'
            $loggedArgs | Should -Contain '-n'
            $loggedArgs | Should -Not -Contain '-all:all'
            $result.Metadata.Keys | Should -Contain 'EXIF:Make'
            $result.Metadata.Keys | Should -Not -Contain 'EXIF:Model'
            $result.RawExifToolData.PSObject.Properties.Name | Should -Contain 'EXIF:Make'
        }

        It 'Should not add a second dash to tag arguments that already include one' {
            $null = Get-ImageMetadata -Path $script:SampleImage -Tag '-DateTimeOriginal' -ExifToolPath $script:FakeExifTool.Path

            $loggedArgs = Get-Content -LiteralPath $script:FakeExifTool.LogPath
            $loggedArgs | Should -Contain '-DateTimeOriginal'
            $loggedArgs | Should -Not -Contain '--DateTimeOriginal'
        }

        It 'Should return flattened metadata rows when Flatten is specified' {
            $rows = @(Get-ImageMetadata -Path $script:SampleImage -Flatten -NoEmptyProperties -ExifToolPath $script:FakeExifTool.Path)
            $makeRow = $rows | Where-Object { $_.MetadataName -eq 'EXIF:Make' }

            $rows.MetadataName | Should -Contain 'EXIF:Make'
            $rows.MetadataName | Should -Not -Contain 'EXIF:Model'
            $makeRow.Group | Should -Be 'EXIF'
            $makeRow.Tag | Should -Be 'Make'
            $makeRow.Value | Should -Be 'Test Camera'
        }
    }
}
