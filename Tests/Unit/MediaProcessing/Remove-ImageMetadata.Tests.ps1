BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/MediaProcessing/Remove-ImageMetadata.ps1"
}

Describe 'Remove-ImageMetadata' -Tag 'Unit' {
    Context 'Parameter Validation' {
        It 'Should have Recurse parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('Recurse') | Should -Be $true
        }

        It 'Should have Exclude parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('Exclude') | Should -Be $true
        }

        It 'Should have Filters parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('Filters') | Should -Be $true
        }

        It 'Should have ExifToolPath parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('ExifToolPath') | Should -Be $true
        }

        It 'Should have ImageMagickPath parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('ImageMagickPath') | Should -Be $true
        }

        It 'Should have OutputPath parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('OutputPath') | Should -Be $true
        }

        It 'Should have Force parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('Force') | Should -Be $true
        }

        It 'Should have KeepBackup parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('KeepBackup') | Should -Be $true
        }

        It 'Should have PreserveFileTimestamp parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('PreserveFileTimestamp') | Should -Be $true
        }

        It 'Should have ResetFileTimestamp parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('ResetFileTimestamp') | Should -Be $true
        }

        It 'Should have ResetTimestamp parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('ResetTimestamp') | Should -Be $true
        }

        It 'Should have Paranoid parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('Paranoid') | Should -Be $true
        }

        It 'Should have Verify parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('Verify') | Should -Be $true
        }

        It 'Should have PassThru parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters.ContainsKey('PassThru') | Should -Be $true
        }
    }

    Context 'Parameter Types' {
        It 'Should have Recurse as Switch parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters['Recurse'].ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have Exclude as String array parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters['Exclude'].ParameterType.Name | Should -Be 'String[]'
        }

        It 'Should have Filters as String array parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters['Filters'].ParameterType.Name | Should -Be 'String[]'
        }

        It 'Should have OutputPath as String parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters['OutputPath'].ParameterType.Name | Should -Be 'String'
        }

        It 'Should have ResetTimestamp as DateTime parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters['ResetTimestamp'].ParameterType.Name | Should -Be 'DateTime'
        }

        It 'Should have Paranoid as Switch parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters['Paranoid'].ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have Verify as Switch parameter' {
            $command = Get-Command Remove-ImageMetadata
            $command.Parameters['Verify'].ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should support pipeline input for Path' {
            $command = Get-Command Remove-ImageMetadata
            $pathParam = $command.Parameters['Path']
            $pipelineAttributes = $pathParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pipelineSupport = $pipelineAttributes | Where-Object { $_.ValueFromPipeline -eq $true -or $_.ValueFromPipelineByPropertyName -eq $true }
            $pipelineSupport | Should -Not -BeNullOrEmpty
        }

        It 'Should include file and directory aliases for Path' {
            $command = Get-Command Remove-ImageMetadata
            $aliases = $command.Parameters['Path'].Aliases
            $aliases | Should -Contain 'FilePath'
            $aliases | Should -Contain 'FullName'
            $aliases | Should -Contain 'Directory'
        }
    }

    Context 'Default Behavior' {
        BeforeAll {
            $script:TestRoot = Join-Path -Path $TestDrive -ChildPath 'ImageMetadataTest'
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
        }

        It 'Should process image files non-recursively by default with -WhatIf' {
            $results = Remove-ImageMetadata -Path $script:TestRoot -WhatIf -PassThru

            $results.Count | Should -Be 2
            $results.Name | Should -Contain 'photo1.jpg'
            $results.Name | Should -Contain 'photo2.png'
            $results.Name | Should -Not -Contain 'photo3.jpg'
            $results.Name | Should -Not -Contain 'notes.txt'
        }

        It 'Should process recursively when -Recurse is specified with -WhatIf' {
            $results = Remove-ImageMetadata -Path $script:TestRoot -Recurse -WhatIf -PassThru

            $results.Name | Should -Contain 'photo1.jpg'
            $results.Name | Should -Contain 'photo2.png'
            $results.Name | Should -Contain 'photo3.jpg'
        }

        It 'Should respect Exclude parameter when using -Recurse with -WhatIf' {
            $results = Remove-ImageMetadata -Path $script:TestRoot -Recurse -Exclude @('.git', 'SubDirectory') -WhatIf -PassThru

            $results.Name | Should -Contain 'photo1.jpg'
            $results.Name | Should -Contain 'photo2.png'
            $results.Name | Should -Not -Contain 'photo3.jpg'
            $results.Name | Should -Not -Contain 'hidden.jpg'
        }

        It 'Should honor custom Filters with -WhatIf' {
            $results = @(Remove-ImageMetadata -Path $script:TestRoot -Filters '*.png' -WhatIf -PassThru)

            $results.Count | Should -Be 1
            $results.Name | Should -Contain 'photo2.png'
        }
    }

    Context 'Individual File Support' {
        BeforeAll {
            $script:FileTestRoot = Join-Path -Path $TestDrive -ChildPath 'ImageMetadataFileTest'
            New-Item -Path $script:FileTestRoot -ItemType Directory -Force | Out-Null

            $script:TestImageFile = Join-Path -Path $script:FileTestRoot -ChildPath 'single-photo.jpg'
            $script:TestNonImageFile = Join-Path -Path $script:FileTestRoot -ChildPath 'document.txt'

            New-Item -Path $script:TestImageFile -ItemType File -Force | Out-Null
            New-Item -Path $script:TestNonImageFile -ItemType File -Force | Out-Null
        }

        It 'Should accept an individual image file path with -WhatIf' {
            { Remove-ImageMetadata -Path $script:TestImageFile -WhatIf } | Should -Not -Throw
        }

        It 'Should warn when an individual file does not match supported filters' {
            $null = Remove-ImageMetadata -Path $script:TestNonImageFile -WhatIf -WarningVariable warnings 2>&1
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Should report an error for a missing path' {
            $missingPath = Join-Path -Path $TestDrive -ChildPath 'missing-photo.jpg'

            $null = Remove-ImageMetadata -Path $missingPath -WhatIf -ErrorAction SilentlyContinue -ErrorVariable errors

            $errors.Count | Should -BeGreaterThan 0
            $errors[0].Exception.Message | Should -BeLike '*not found*'
        }

        It 'Should accept image files from the pipeline with -WhatIf' {
            $result = @(Get-Item -LiteralPath $script:TestImageFile | Remove-ImageMetadata -WhatIf -PassThru)

            $result.Count | Should -Be 1
            $result.Name | Should -Be 'single-photo.jpg'
        }
    }

    Context 'ExifTool Invocation' {
        BeforeEach {
            $script:InvokeTestRoot = Join-Path -Path $TestDrive -ChildPath "ExifToolInvokeTest-$(Get-Random)"
            New-Item -Path $script:InvokeTestRoot -ItemType Directory -Force | Out-Null

            $script:SampleImage = Join-Path -Path $script:InvokeTestRoot -ChildPath 'metadata-photo.jpg'
            $script:ExifToolLogPath = Join-Path -Path $script:InvokeTestRoot -ChildPath 'exiftool-args.log'
            $script:FakeExifToolPath = Join-Path -Path $script:InvokeTestRoot -ChildPath 'exiftool.ps1'

            'fake image bytes' | Set-Content -LiteralPath $script:SampleImage -Encoding UTF8

            $escapedLogPath = $script:ExifToolLogPath.Replace("'", "''")
            $fakeExifToolContent = @(
                'param(',
                '    [Parameter(ValueFromRemainingArguments = $true)]',
                '    [Object[]]$RemainingArgs',
                ')',
                ("`$RemainingArgs -join [Environment]::NewLine | Set-Content -LiteralPath '{0}' -Encoding UTF8" -f $escapedLogPath),
                '$global:LASTEXITCODE = 0',
                "'1 image files updated'"
            ) -join [Environment]::NewLine

            Set-Content -LiteralPath $script:FakeExifToolPath -Value $fakeExifToolContent -Encoding UTF8
        }

        It 'Should call ExifTool with metadata removal arguments' {
            $result = Remove-ImageMetadata -Path $script:SampleImage -ExifToolPath $script:FakeExifToolPath -PassThru

            $loggedArgs = Get-Content -LiteralPath $script:ExifToolLogPath
            $loggedArgs | Should -Contain '-overwrite_original'
            $loggedArgs | Should -Contain '-all='
            $loggedArgs | Should -Contain $script:SampleImage
            $result.MetadataRemoved | Should -Be $true
            $result.ExitCode | Should -Be 0
        }

        It 'Should omit overwrite_original when KeepBackup is specified' {
            Remove-ImageMetadata -Path $script:SampleImage -ExifToolPath $script:FakeExifToolPath -KeepBackup | Out-Null

            $loggedArgs = Get-Content -LiteralPath $script:ExifToolLogPath
            $loggedArgs | Should -Not -Contain '-overwrite_original'
            $loggedArgs | Should -Contain '-all='
        }

        It 'Should pass -P when PreserveFileTimestamp is specified' {
            Remove-ImageMetadata -Path $script:SampleImage -ExifToolPath $script:FakeExifToolPath -PreserveFileTimestamp | Out-Null

            $loggedArgs = Get-Content -LiteralPath $script:ExifToolLogPath
            $loggedArgs | Should -Contain '-P'
            $loggedArgs | Should -Contain '-all='
        }
    }

    Context 'Additional Privacy Modes' {
        BeforeEach {
            $script:PrivacyTestRoot = Join-Path -Path $TestDrive -ChildPath "PrivacyModeTest-$(Get-Random)"
            New-Item -Path $script:PrivacyTestRoot -ItemType Directory -Force | Out-Null

            $script:PrivacySourceImage = Join-Path -Path $script:PrivacyTestRoot -ChildPath 'private-photo.jpg'
            $script:PrivacyOutputDir = Join-Path -Path $script:PrivacyTestRoot -ChildPath 'clean'
            $script:PrivacyOutputImage = Join-Path -Path $script:PrivacyOutputDir -ChildPath 'private-photo.jpg'
            $script:PrivacyExifToolLogPath = Join-Path -Path $script:PrivacyTestRoot -ChildPath 'exiftool-privacy-args.log'
            $script:PrivacyImageMagickLogPath = Join-Path -Path $script:PrivacyTestRoot -ChildPath 'imagemagick-args.log'
            $script:PrivacyFakeExifToolPath = Join-Path -Path $script:PrivacyTestRoot -ChildPath 'exiftool.ps1'
            $script:PrivacyFakeImageMagickPath = Join-Path -Path $script:PrivacyTestRoot -ChildPath 'magick.ps1'

            'source image bytes' | Set-Content -LiteralPath $script:PrivacySourceImage -Encoding UTF8

            $escapedExifLogPath = $script:PrivacyExifToolLogPath.Replace("'", "''")
            $fakeExifToolContent = @(
                'param(',
                '    [Parameter(ValueFromRemainingArguments = $true)]',
                '    [Object[]]$RemainingArgs',
                ')',
                ("`$RemainingArgs -join [Environment]::NewLine | Add-Content -LiteralPath '{0}' -Encoding UTF8" -f $escapedExifLogPath),
                "Add-Content -LiteralPath '$escapedExifLogPath' -Value '---' -Encoding UTF8",
                'if ($RemainingArgs -contains ''-all='') {',
                '    $global:LASTEXITCODE = 0',
                '    ''1 image files updated''',
                '}',
                'else {',
                '    $global:LASTEXITCODE = 0',
                '    if ($env:PWSH_PROFILE_FAKE_EXIFTOOL_REMAINING_TAG) {',
                '        ''[EXIF]          Make                            : Test Camera''',
                '    }',
                '}'
            ) -join [Environment]::NewLine

            Set-Content -LiteralPath $script:PrivacyFakeExifToolPath -Value $fakeExifToolContent -Encoding UTF8

            $escapedImageMagickLogPath = $script:PrivacyImageMagickLogPath.Replace("'", "''")
            $fakeImageMagickContent = @(
                'param(',
                '    [Parameter(ValueFromRemainingArguments = $true)]',
                '    [Object[]]$RemainingArgs',
                ')',
                ("`$RemainingArgs -join [Environment]::NewLine | Set-Content -LiteralPath '{0}' -Encoding UTF8" -f $escapedImageMagickLogPath),
                '$sourcePath = [String]$RemainingArgs[0]',
                '$destinationPath = [String]$RemainingArgs[$RemainingArgs.Count - 1]',
                'Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force',
                '$global:LASTEXITCODE = 0',
                "''"
            ) -join [Environment]::NewLine

            Set-Content -LiteralPath $script:PrivacyFakeImageMagickPath -Value $fakeImageMagickContent -Encoding UTF8
        }

        It 'Should write sanitized copies to OutputPath without modifying the source path' {
            $result = Remove-ImageMetadata -Path $script:PrivacySourceImage -OutputPath $script:PrivacyOutputDir -ExifToolPath $script:PrivacyFakeExifToolPath -PassThru

            Test-Path -LiteralPath $script:PrivacyOutputImage | Should -Be $true
            Test-Path -LiteralPath $script:PrivacySourceImage | Should -Be $true
            $result.SourcePath | Should -Be $script:PrivacySourceImage
            $result.Path | Should -Be $script:PrivacyOutputImage
            $result.OutputCopied | Should -Be $true
            $result.MetadataRemoved | Should -Be $true
        }

        It 'Should not overwrite an existing OutputPath target unless Force is specified' {
            New-Item -Path $script:PrivacyOutputDir -ItemType Directory -Force | Out-Null
            'existing clean image' | Set-Content -LiteralPath $script:PrivacyOutputImage -Encoding UTF8

            $null = Remove-ImageMetadata -Path $script:PrivacySourceImage -OutputPath $script:PrivacyOutputDir -ExifToolPath $script:PrivacyFakeExifToolPath -PassThru -ErrorAction SilentlyContinue -ErrorVariable errors

            $errors.Count | Should -BeGreaterThan 0
            $errors[0].Exception.Message | Should -BeLike '*already exists*'
            Get-Content -LiteralPath $script:PrivacyOutputImage | Should -Be 'existing clean image'
        }

        It 'Should reset filesystem timestamps when ResetFileTimestamp is specified' {
            $resetTimestamp = [DateTime]::SpecifyKind([DateTime]'1999-12-31T00:00:00', [DateTimeKind]::Utc)

            $result = Remove-ImageMetadata -Path $script:PrivacySourceImage -OutputPath $script:PrivacyOutputDir -ExifToolPath $script:PrivacyFakeExifToolPath -ResetFileTimestamp -ResetTimestamp $resetTimestamp -PassThru
            $outputFile = Get-Item -LiteralPath $script:PrivacyOutputImage

            $result.TimestampReset | Should -Be $true
            $outputFile.LastWriteTimeUtc.ToString('o') | Should -Be $resetTimestamp.ToString('o')
        }

        It 'Should reject conflicting timestamp options' {
            { Remove-ImageMetadata -Path $script:PrivacySourceImage -ExifToolPath $script:PrivacyFakeExifToolPath -PreserveFileTimestamp -ResetFileTimestamp } |
            Should -Throw '*cannot be used together*'
        }

        It 'Should re-encode through ImageMagick in Paranoid mode' {
            $result = Remove-ImageMetadata -Path $script:PrivacySourceImage -OutputPath $script:PrivacyOutputDir -ExifToolPath $script:PrivacyFakeExifToolPath -ImageMagickPath $script:PrivacyFakeImageMagickPath -Paranoid -PassThru

            Test-Path -LiteralPath $script:PrivacyOutputImage | Should -Be $true
            $imageMagickArgs = Get-Content -LiteralPath $script:PrivacyImageMagickLogPath
            $imageMagickArgs | Should -Contain $script:PrivacySourceImage
            $imageMagickArgs | Should -Contain '-strip'
            $result.Paranoid | Should -Be $true
            $result.MetadataRemoved | Should -Be $true
        }

        It 'Should return verification details when Verify is specified' {
            $env:PWSH_PROFILE_FAKE_EXIFTOOL_REMAINING_TAG = '1'
            try
            {
                $result = Remove-ImageMetadata -Path $script:PrivacySourceImage -OutputPath $script:PrivacyOutputDir -ExifToolPath $script:PrivacyFakeExifToolPath -Verify
            }
            finally
            {
                Remove-Item -Path Env:\PWSH_PROFILE_FAKE_EXIFTOOL_REMAINING_TAG -ErrorAction SilentlyContinue
            }

            $result | Should -Not -BeNullOrEmpty
            $result.Verified | Should -Be $false
            $result.RemainingMetadataTags | Should -Contain '[EXIF] Make'
        }
    }
}
