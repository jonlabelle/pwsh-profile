BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/MediaProcessing/Resize-Image.ps1"
}

Describe 'Resize-Image' -Tag 'Unit' {
    BeforeEach {
        $script:ResizeTestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('ResizeImageUnit-' + [Guid]::NewGuid().ToString('N'))
        [System.IO.Directory]::CreateDirectory($script:ResizeTestRoot) | Out-Null
        $script:SampleImage = Join-Path -Path $script:ResizeTestRoot -ChildPath 'photo sample.png'
        [System.IO.File]::WriteAllText($script:SampleImage, 'original image bytes')
        $script:FakeImageMagick = Join-Path -Path $script:ResizeTestRoot -ChildPath 'magick.ps1'
        $script:ArgumentLog = Join-Path -Path $script:ResizeTestRoot -ChildPath 'arguments.clixml'
        $script:InvocationLog = Join-Path -Path $script:ResizeTestRoot -ChildPath 'invocations.log'
        $fakeContent = @'
param(
    [Parameter(ValueFromRemainingArguments)]
    [Object[]]$RemainingArgs
)
$RemainingArgs | Export-Clixml -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'arguments.clixml')
Add-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'invocations.log') -Value 'invoked'
$destination = [String]$RemainingArgs[-1]
$global:LASTEXITCODE = 0
if (Test-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'failure.marker'))
{
    [System.IO.File]::WriteAllText($destination, 'partial output')
    'simulated resize failure'
    $global:LASTEXITCODE = 7
    return
}
if (Test-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'missing.marker')) { return }
if (Test-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'multiple.marker'))
{
    [System.IO.File]::WriteAllText(($destination + '-0.png'), 'frame one')
    [System.IO.File]::WriteAllText(($destination + '-1.png'), 'frame two')
    return
}
if (Test-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'empty.marker'))
{
    [System.IO.File]::WriteAllText($destination, '')
    return
}
[System.IO.File]::WriteAllText($destination, 'resized image bytes')
if (Test-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'warning.marker')) { 'simulated encoder warning' }
'@
        Set-Content -LiteralPath $script:FakeImageMagick -Value $fakeContent -Encoding UTF8
    }

    AfterEach {
        if ($script:ResizeTestRoot -and (Test-Path -LiteralPath $script:ResizeTestRoot))
        {
            Remove-Item -LiteralPath $script:ResizeTestRoot -Recurse -Force -ErrorAction Stop
        }
    }

    Context 'Parameter validation' {
        It 'Requires dimensions or a percentage' {
            { Resize-Image -Path $script:SampleImage -WhatIf } | Should -Throw '*Specify Width*'
        }

        It 'Requires both dimensions for <Mode>' -ForEach @(
            @{ Mode = 'Exact' }
            @{ Mode = 'Fill' }
        ) {
            { Resize-Image -Path $script:SampleImage -Width 100 -Mode $Mode -WhatIf } |
            Should -Throw '*requires both Width and Height*'
        }

        It 'Rejects non-positive dimensions' {
            { Resize-Image -Path $script:SampleImage -Width 0 -WhatIf } | Should -Throw
            { Resize-Image -Path $script:SampleImage -Height -1 -WhatIf } | Should -Throw
        }

        It 'Rejects invalid percentages' {
            foreach ($value in @(0, -1, [Double]::NaN, [Double]::PositiveInfinity))
            {
                { Resize-Image -Path $script:SampleImage -Percentage $value -WhatIf } |
                Should -Throw '*positive, finite number*'
            }
        }

        It 'Keeps percentage and dimension parameters mutually exclusive' {
            { Resize-Image -Path $script:SampleImage -Width 100 -Percentage 50 -WhatIf } | Should -Throw
            { Resize-Image -Path $script:SampleImage -Mode Fit -Percentage 50 -WhatIf } | Should -Throw
        }

        It 'Rejects InPlace with OutputPath' {
            { Resize-Image -Path $script:SampleImage -Width 100 -InPlace -OutputPath './copy.png' -WhatIf } |
            Should -Throw '*cannot be combined*'
        }

        It 'Reports a missing executable with guidance' {
            $missingExecutable = Join-Path -Path $script:ResizeTestRoot -ChildPath 'missing-magick'
            { Resize-Image -Path $script:SampleImage -Width 100 -ImageMagickPath $missingExecutable } |
            Should -Throw '*ImageMagick executable not found*specify -ImageMagickPath*'
        }
    }

    Context 'ImageMagick arguments and result objects' {
        It 'Uses <Geometry> for <Label>' -ForEach @(
            @{ Label = 'width-only fit'; Options = @{ Width = 100 }; Geometry = '100x' }
            @{ Label = 'height-only fit'; Options = @{ Height = 50 }; Geometry = 'x50' }
            @{ Label = 'bounding box fit'; Options = @{ Width = 100; Height = 50 }; Geometry = '100x50' }
            @{ Label = 'exact dimensions'; Options = @{ Width = 100; Height = 50; Mode = 'Exact' }; Geometry = '100x50!' }
            @{ Label = 'crop to fill'; Options = @{ Width = 100; Height = 50; Mode = 'Fill' }; Geometry = '100x50^' }
            @{ Label = 'percentage scaling'; Options = @{ Percentage = 50.5 }; Geometry = '50.5%' }
        ) {
            $result = Resize-Image -Path $script:SampleImage @Options -ImageMagickPath $script:FakeImageMagick -PassThru
            $arguments = @(Import-Clixml -LiteralPath $script:ArgumentLog)

            $result.Resized | Should -BeTrue
            $result.Geometry | Should -Be $Geometry
            $result.ExitCode | Should -Be 0
            $arguments[0] | Should -Be $script:SampleImage
            $arguments[1] | Should -Be '-coalesce'
            $arguments[2] | Should -Be '-auto-orient'
            $arguments[3] | Should -Be '-resize'
            $arguments[4] | Should -Be $Geometry
            $arguments[-2] | Should -Be '+repage'
            if ($Options.Mode -eq 'Fill')
            {
                $arguments[5..8] -join ' ' | Should -Be '-gravity center -extent 100x50'
            }
            [System.IO.File]::ReadAllText($script:SampleImage) | Should -Be 'original image bytes'
            [System.IO.File]::ReadAllText($result.Path) | Should -Be 'resized image bytes'
            @(Get-ChildItem -LiteralPath $script:ResizeTestRoot -Directory -Force).Count | Should -Be 0
        }

        It 'Formats percentages independently of the current culture' {
            $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try
            {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
                $result = Resize-Image $script:SampleImage -Percentage 50.5 -ImageMagickPath $script:FakeImageMagick -PassThru
                $result.Geometry | Should -Be '50.5%'
            }
            finally
            {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
            }
        }

        It 'Produces no success-stream output without PassThru' {
            $result = @(Resize-Image $script:SampleImage -Width 100 -ImageMagickPath $script:FakeImageMagick)
            $result.Count | Should -Be 0
            Test-Path -LiteralPath (Join-Path -Path $script:ResizeTestRoot -ChildPath 'photo sample-resized.png') |
            Should -BeTrue
        }

        It 'Returns the documented result properties' {
            $result = Resize-Image $script:SampleImage -Width 100 -ImageMagickPath $script:FakeImageMagick -PassThru
            @($result.PSObject.Properties.Name) -join ',' |
            Should -Be 'SourcePath,Path,Name,Resized,InPlace,Mode,Geometry,ExitCode,Message'
            $result.SourcePath | Should -Be $script:SampleImage
            $result.Name | Should -Be 'photo sample-resized.png'
            $result.InPlace | Should -BeFalse
            $result.Mode | Should -Be 'Fit'
        }

        It 'Surfaces successful encoder diagnostics as warnings' {
            New-Item -Path (Join-Path -Path $script:ResizeTestRoot -ChildPath 'warning.marker') -ItemType File | Out-Null
            $result = Resize-Image $script:SampleImage -Width 100 -ImageMagickPath $script:FakeImageMagick -PassThru -WarningVariable warnings

            $result.Resized | Should -BeTrue
            $result.Message | Should -Be 'simulated encoder warning'
            $warnings -join ' ' | Should -BeLike '*simulated encoder warning*'
        }
    }

    Context 'Destinations and overwrite protection' {
        It 'Creates the parent directory for a new output file' {
            $outputFile = Join-Path -Path (Join-Path -Path $script:ResizeTestRoot -ChildPath 'new') -ChildPath 'small.jpg'
            $result = Resize-Image $script:SampleImage -Width 100 -OutputPath $outputFile -ImageMagickPath $script:FakeImageMagick -PassThru
            $result.Path | Should -Be $outputFile
            Test-Path -LiteralPath $outputFile -PathType Leaf | Should -BeTrue
        }

        It 'Uses original names in a new output directory' {
            $outputDirectory = Join-Path -Path $script:ResizeTestRoot -ChildPath 'copies'
            $result = Resize-Image $script:SampleImage -Width 100 -OutputPath $outputDirectory -ImageMagickPath $script:FakeImageMagick -PassThru
            $result.Path | Should -Be (Join-Path -Path $outputDirectory -ChildPath 'photo sample.png')
            $result.Resized | Should -BeTrue
        }

        It 'Recognizes an existing directory with a dotted name' {
            $outputDirectory = Join-Path -Path $script:ResizeTestRoot -ChildPath 'copies.v1'
            [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
            $result = Resize-Image $script:SampleImage -Width 100 -OutputPath $outputDirectory -ImageMagickPath $script:FakeImageMagick -PassThru
            $result.Path | Should -Be (Join-Path -Path $outputDirectory -ChildPath 'photo sample.png')
        }

        It 'Does not overwrite an existing copy without Force' {
            $outputFile = Join-Path -Path $script:ResizeTestRoot -ChildPath 'photo sample-resized.png'
            [System.IO.File]::WriteAllText($outputFile, 'existing copy')
            $result = Resize-Image $script:SampleImage -Width 100 -ImageMagickPath $script:FakeImageMagick -PassThru -ErrorAction SilentlyContinue -ErrorVariable errors

            $result.Resized | Should -BeFalse
            $errors.Count | Should -BeGreaterThan 0
            $result.Message | Should -BeLike '*Use -Force*'
            [System.IO.File]::ReadAllText($outputFile) | Should -Be 'existing copy'
            Test-Path -LiteralPath $script:InvocationLog | Should -BeFalse
        }

        It 'Overwrites an existing copy with Force without modifying the source' {
            $outputFile = Join-Path -Path $script:ResizeTestRoot -ChildPath 'photo sample-resized.png'
            [System.IO.File]::WriteAllText($outputFile, 'existing copy')
            $result = Resize-Image $script:SampleImage -Width 100 -Force -ImageMagickPath $script:FakeImageMagick -PassThru

            $result.Resized | Should -BeTrue
            [System.IO.File]::ReadAllText($outputFile) | Should -Be 'resized image bytes'
            [System.IO.File]::ReadAllText($script:SampleImage) | Should -Be 'original image bytes'
        }

        It 'Only replaces an original with explicit InPlace' {
            $result = Resize-Image $script:SampleImage -Percentage 50 -InPlace -ImageMagickPath $script:FakeImageMagick -PassThru
            $result.Resized | Should -BeTrue
            $result.InPlace | Should -BeTrue
            $result.Path | Should -Be $script:SampleImage
            [System.IO.File]::ReadAllText($script:SampleImage) | Should -Be 'resized image bytes'
        }

        It 'Rejects an output path equal to the source even with Force' {
            $result = Resize-Image $script:SampleImage -Width 100 -OutputPath $script:SampleImage -Force -ImageMagickPath $script:FakeImageMagick -PassThru -ErrorAction SilentlyContinue -ErrorVariable errors
            $result.Resized | Should -BeFalse
            $result.Message | Should -BeLike '*Use -InPlace*'
            $errors.Count | Should -BeGreaterThan 0
            Test-Path -LiteralPath $script:InvocationLog | Should -BeFalse
            [System.IO.File]::ReadAllText($script:SampleImage) | Should -Be 'original image bytes'
        }

        It 'Protects selected sources using platform-appropriate path comparisons' {
            $alternateCasePath = Join-Path -Path $script:ResizeTestRoot -ChildPath 'PHOTO SAMPLE.PNG'
            $result = Resize-Image $script:SampleImage -Width 100 -OutputPath $alternateCasePath -Force -ImageMagickPath $script:FakeImageMagick -PassThru -ErrorAction SilentlyContinue
            if ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows -or $IsMacOS)
            {
                $result.Resized | Should -BeFalse
                $result.Message | Should -BeLike '*Use -InPlace*'
            }
            else
            {
                $result.Resized | Should -BeTrue
            }
            [System.IO.File]::ReadAllText($script:SampleImage) | Should -Be 'original image bytes'
        }

        It 'Plans the entire FileInfo pipeline before choosing the output directory' {
            $secondImage = Join-Path -Path $script:ResizeTestRoot -ChildPath 'second.jpg'
            [System.IO.File]::WriteAllText($secondImage, 'second image')
            $outputDirectory = Join-Path -Path $script:ResizeTestRoot -ChildPath 'batch.png'
            $results = @(Get-Item -LiteralPath $script:SampleImage, $secondImage |
                Resize-Image -Width 100 -OutputPath $outputDirectory -ImageMagickPath $script:FakeImageMagick -PassThru)

            $results.Count | Should -Be 2
            @($results | Where-Object { $_.Resized }).Count | Should -Be 2
            Test-Path -LiteralPath $outputDirectory -PathType Container | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $outputDirectory -ChildPath 'photo sample.png') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $outputDirectory -ChildPath 'second.jpg') | Should -BeTrue
        }

        It 'Rejects all colliding output names across pipeline records even with Force' {
            $subdirectory = Join-Path -Path $script:ResizeTestRoot -ChildPath 'sub'
            [System.IO.Directory]::CreateDirectory($subdirectory) | Out-Null
            $secondImage = Join-Path -Path $subdirectory -ChildPath 'photo sample.png'
            [System.IO.File]::WriteAllText($secondImage, 'second image')
            $outputDirectory = Join-Path -Path $script:ResizeTestRoot -ChildPath 'copies'
            $results = @($script:SampleImage, $secondImage |
                Resize-Image -Width 100 -OutputPath $outputDirectory -Force -ImageMagickPath $script:FakeImageMagick -PassThru -ErrorAction SilentlyContinue -ErrorVariable errors)

            $results.Count | Should -Be 2
            @($results | Where-Object { $_.Resized }).Count | Should -Be 0
            $results[0].Message | Should -BeLike '*Multiple source images*'
            $errors.Count | Should -BeGreaterThan 0
            Test-Path -LiteralPath $script:InvocationLog | Should -BeFalse
            Test-Path -LiteralPath $outputDirectory | Should -BeFalse
        }
    }

    Context 'File selection and WhatIf' {
        It 'Does not invoke ImageMagick, validate dependencies, or create directories with WhatIf' {
            $outputDirectory = Join-Path -Path $script:ResizeTestRoot -ChildPath 'not-created'
            $result = Resize-Image $script:SampleImage -Width 100 -OutputPath $outputDirectory -ImageMagickPath './missing-magick' -WhatIf -PassThru

            $result.Resized | Should -BeFalse
            $result.Message | Should -Be 'Skipped by ShouldProcess.'
            $result.ExitCode | Should -BeNullOrEmpty
            Test-Path -LiteralPath $outputDirectory | Should -BeFalse
            Test-Path -LiteralPath $script:InvocationLog | Should -BeFalse
        }

        It 'Does not change originals with InPlace and WhatIf' {
            $result = Resize-Image $script:SampleImage -Percentage 50 -InPlace -WhatIf -PassThru
            $result.Resized | Should -BeFalse
            [System.IO.File]::ReadAllText($script:SampleImage) | Should -Be 'original image bytes'
        }

        It 'Searches non-recursively by default and honors Filter' {
            $subdirectory = Join-Path -Path $script:ResizeTestRoot -ChildPath 'sub'
            [System.IO.Directory]::CreateDirectory($subdirectory) | Out-Null
            [System.IO.File]::WriteAllText((Join-Path -Path $subdirectory -ChildPath 'nested.png'), 'nested')
            [System.IO.File]::WriteAllText((Join-Path -Path $script:ResizeTestRoot -ChildPath 'other.jpg'), 'other')
            $results = @(Resize-Image $script:ResizeTestRoot -Width 100 -Filter '*.png' -WhatIf -PassThru)

            $results.Count | Should -Be 1
            $results[0].SourcePath | Should -Be $script:SampleImage
        }

        It 'Recurses while skipping default and custom excluded directories' {
            foreach ($directoryName in @('sub', 'node_modules', 'raw'))
            {
                $directoryPath = Join-Path -Path $script:ResizeTestRoot -ChildPath $directoryName
                [System.IO.Directory]::CreateDirectory($directoryPath) | Out-Null
                [System.IO.File]::WriteAllText((Join-Path -Path $directoryPath -ChildPath "$directoryName.png"), 'nested')
            }
            $defaults = @(Resize-Image $script:ResizeTestRoot -Width 100 -Recurse -WhatIf -PassThru)
            $defaults.Count | Should -Be 3
            $custom = @(Resize-Image $script:ResizeTestRoot -Width 100 -Recurse -Exclude 'node_modules', 'raw' -WhatIf -PassThru)
            $custom.Count | Should -Be 2
            $custom.SourcePath | Should -Contain (Join-Path -Path (Join-Path -Path $script:ResizeTestRoot -ChildPath 'sub') -ChildPath 'sub.png')
        }

        It 'Uses the current directory when Path is omitted' {
            Push-Location -LiteralPath $script:ResizeTestRoot
            try
            {
                $results = @(Resize-Image -Width 100 -WhatIf -PassThru)
                $results.Count | Should -Be 1
                $results[0].SourcePath | Should -Be $script:SampleImage
            }
            finally
            {
                Pop-Location
            }
        }

        It 'Supports wildcard paths and overlapping filters without duplicate work' {
            $wildcard = Join-Path -Path $script:ResizeTestRoot -ChildPath '*.png'
            $results = @(Resize-Image -Path $wildcard, $script:ResizeTestRoot -Filter '*.png', 'photo*' -Width 100 -WhatIf -PassThru)
            $results.Count | Should -Be 1
        }

        It 'Deduplicates repeated pipeline inputs' {
            $results = @($script:SampleImage, $script:SampleImage |
                Resize-Image -Width 100 -ImageMagickPath $script:FakeImageMagick -PassThru)
            $results.Count | Should -Be 1
            @(Get-Content -LiteralPath $script:InvocationLog).Count | Should -Be 1
        }

        It 'Accepts literal bracket characters in existing input paths' {
            $bracketImage = Join-Path -Path $script:ResizeTestRoot -ChildPath 'photo[1].png'
            [System.IO.File]::WriteAllText($bracketImage, 'bracket image')
            $result = Resize-Image $bracketImage -Width 100 -ImageMagickPath $script:FakeImageMagick -PassThru
            $result.Resized | Should -BeTrue
            $result.Name | Should -Be 'photo[1]-resized.png'
        }

        It 'Warns when no files match the selected filters' {
            $result = @(Resize-Image $script:ResizeTestRoot -Width 100 -Filter '*.webp' -WhatIf -WarningVariable warnings)
            $result.Count | Should -Be 0
            $warnings -join ' ' | Should -BeLike '*No image files matched*'
        }

        It 'Reports missing input paths as errors' {
            $missingPath = Join-Path -Path $script:ResizeTestRoot -ChildPath 'missing.png'
            { Resize-Image $missingPath -Width 100 -WhatIf -ErrorAction Stop } | Should -Throw
        }

        It 'Warns rather than silently ignoring unsupported explicit files' {
            $textFile = Join-Path -Path $script:ResizeTestRoot -ChildPath 'notes.txt'
            [System.IO.File]::WriteAllText($textFile, 'notes')
            $null = Resize-Image $textFile -Width 100 -WhatIf -WarningVariable warnings
            $warnings -join ' ' | Should -BeLike '*unsupported image file extension*'
        }
    }

    Context 'Failure handling and cleanup' {
        It 'Preserves originals and removes staged files for <Marker> output' -ForEach @(
            @{ Marker = 'failure'; ExpectedMessage = '*exit code 7*simulated resize failure*' }
            @{ Marker = 'missing'; ExpectedMessage = '*did not produce a single output image*' }
            @{ Marker = 'multiple'; ExpectedMessage = '*did not produce a single output image*' }
            @{ Marker = 'empty'; ExpectedMessage = '*empty output image*' }
        ) {
            New-Item -Path (Join-Path -Path $script:ResizeTestRoot -ChildPath "$Marker.marker") -ItemType File | Out-Null
            $result = Resize-Image $script:SampleImage -Width 100 -InPlace -ImageMagickPath $script:FakeImageMagick -PassThru -ErrorAction SilentlyContinue -ErrorVariable errors

            $result.Resized | Should -BeFalse
            $result.Message | Should -BeLike $ExpectedMessage
            $errors.Count | Should -BeGreaterThan 0
            [System.IO.File]::ReadAllText($script:SampleImage) | Should -Be 'original image bytes'
            @(Get-ChildItem -LiteralPath $script:ResizeTestRoot -Directory -Force).Count | Should -Be 0
        }

        It 'Preserves an existing destination when resizing fails with Force' {
            New-Item -Path (Join-Path -Path $script:ResizeTestRoot -ChildPath 'failure.marker') -ItemType File | Out-Null
            $outputFile = Join-Path -Path $script:ResizeTestRoot -ChildPath 'small.png'
            [System.IO.File]::WriteAllText($outputFile, 'existing output')
            $result = Resize-Image $script:SampleImage -Width 100 -OutputPath $outputFile -Force -ImageMagickPath $script:FakeImageMagick -PassThru -ErrorAction SilentlyContinue

            $result.Resized | Should -BeFalse
            $result.ExitCode | Should -Be 7
            [System.IO.File]::ReadAllText($outputFile) | Should -Be 'existing output'
        }

        It 'Propagates ErrorAction Stop and still cleans up' {
            New-Item -Path (Join-Path -Path $script:ResizeTestRoot -ChildPath 'failure.marker') -ItemType File | Out-Null
            { Resize-Image $script:SampleImage -Width 100 -InPlace -ImageMagickPath $script:FakeImageMagick -ErrorAction Stop } |
            Should -Throw '*simulated resize failure*'
            [System.IO.File]::ReadAllText($script:SampleImage) | Should -Be 'original image bytes'
            @(Get-ChildItem -LiteralPath $script:ResizeTestRoot -Directory -Force).Count | Should -Be 0
        }
    }
}
