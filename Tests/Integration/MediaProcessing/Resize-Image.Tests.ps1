$script:ResizeImageMagickCommand = Get-Command -Name 'magick' -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $script:ResizeImageMagickCommand -and $PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows)
{
    $script:ResizeImageMagickCommand = Get-Command -Name 'convert' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/MediaProcessing/Resize-Image.ps1"
}

Describe 'Resize-Image ImageMagick integration' -Tag 'Integration' -Skip:(-not $script:ResizeImageMagickCommand) {
    BeforeAll {
        $command = Get-Command -Name 'magick' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $command)
        {
            $command = Get-Command -Name 'convert' -CommandType Application -ErrorAction Stop |
                Select-Object -First 1
        }
        $script:ResizeImageMagickPath = $command.Path

        function Get-ResizeTestDimensions
        {
            param([String]$ImagePath)

            $dimensions = @(& $script:ResizeImageMagickPath $ImagePath '-format' '%w %h\n' 'info:' 2>&1)
            $LASTEXITCODE | Should -Be 0 -Because ($dimensions -join ' ')
            return $dimensions
        }
    }

    BeforeEach {
        $script:ResizeIntegrationRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('ResizeImageIntegration-' + [Guid]::NewGuid().ToString('N'))
        [System.IO.Directory]::CreateDirectory($script:ResizeIntegrationRoot) | Out-Null
        $script:ResizeIntegrationImage = Join-Path -Path $script:ResizeIntegrationRoot -ChildPath 'source image.png'
        $creationOutput = @(& $script:ResizeImageMagickPath -size '80x40' 'gradient:red-blue' $script:ResizeIntegrationImage 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($creationOutput -join ' ')
    }

    AfterEach {
        if ($script:ResizeIntegrationRoot -and (Test-Path -LiteralPath $script:ResizeIntegrationRoot))
        {
            Remove-Item -LiteralPath $script:ResizeIntegrationRoot -Recurse -Force -ErrorAction Stop
        }
    }

    It 'Produces <Expected> pixels for <Label>' -ForEach @(
        @{ Label = 'width-only fit'; Options = @{ Width = 20 }; Expected = '20 10' }
        @{ Label = 'height-only fit'; Options = @{ Height = 10 }; Expected = '20 10' }
        @{ Label = 'bounding box fit'; Options = @{ Width = 30; Height = 30 }; Expected = '30 15' }
        @{ Label = 'exact dimensions'; Options = @{ Width = 30; Height = 30; Mode = 'Exact' }; Expected = '30 30' }
        @{ Label = 'crop to fill'; Options = @{ Width = 30; Height = 30; Mode = 'Fill' }; Expected = '30 30' }
        @{ Label = 'percentage scaling'; Options = @{ Percentage = 25 }; Expected = '20 10' }
        @{ Label = 'enlargement'; Options = @{ Width = 160 }; Expected = '160 80' }
    ) {
        $originalHash = (Get-FileHash -LiteralPath $script:ResizeIntegrationImage).Hash
        $result = Resize-Image $script:ResizeIntegrationImage @Options -ImageMagickPath $script:ResizeImageMagickPath -PassThru -ErrorAction Stop

        $result.Resized | Should -BeTrue
        Get-ResizeTestDimensions -ImagePath $result.Path | Should -Be $Expected
        (Get-FileHash -LiteralPath $script:ResizeIntegrationImage).Hash | Should -Be $originalHash
        @(Get-ChildItem -LiteralPath $script:ResizeIntegrationRoot -Directory -Force).Count | Should -Be 0
    }

    It 'Crops the center rather than stretching or cropping an edge' {
        $creationArgs = @(
            '-size', '80x40', 'xc:lime',
            '-fill', 'red', '-draw', 'rectangle 0,0 19,39',
            '-fill', 'blue', '-draw', 'rectangle 60,0 79,39',
            $script:ResizeIntegrationImage
        )
        $creationOutput = @(& $script:ResizeImageMagickPath @creationArgs 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($creationOutput -join ' ')
        $result = Resize-Image $script:ResizeIntegrationImage -Width 40 -Height 40 -Mode Fill -ImageMagickPath $script:ResizeImageMagickPath -PassThru -ErrorAction Stop

        Get-ResizeTestDimensions -ImagePath $result.Path | Should -Be '40 40'
        $color = @(& $script:ResizeImageMagickPath $result.Path '-format' '%[fx:mean.r],%[fx:mean.g],%[fx:mean.b]' 'info:' 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($color -join ' ')
        $color -join '' | Should -Be '0,1,0'
    }

    It 'Replaces originals only when InPlace is specified' {
        $result = Resize-Image $script:ResizeIntegrationImage -Width 20 -InPlace -ImageMagickPath $script:ResizeImageMagickPath -PassThru -ErrorAction Stop
        $result.Resized | Should -BeTrue
        $result.Path | Should -Be $script:ResizeIntegrationImage
        Get-ResizeTestDimensions -ImagePath $script:ResizeIntegrationImage | Should -Be '20 10'
    }

    It 'Preserves transparency when resizing PNG files' {
        $creationOutput = @(& $script:ResizeImageMagickPath -size '80x40' 'xc:none' -fill red -draw 'rectangle 0,0 39,39' $script:ResizeIntegrationImage 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($creationOutput -join ' ')
        $result = Resize-Image $script:ResizeIntegrationImage -Width 20 -ImageMagickPath $script:ResizeImageMagickPath -PassThru -ErrorAction Stop

        $opaque = @(& $script:ResizeImageMagickPath $result.Path '-format' '%[opaque]' 'info:' 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($opaque -join ' ')
        $opaque -join '' | Should -Be 'false'
    }

    It 'Applies orientation before computing the resized dimensions' {
        $orientedImage = Join-Path -Path $script:ResizeIntegrationRoot -ChildPath 'portrait.tiff'
        $creationOutput = @(& $script:ResizeImageMagickPath -size '80x40' 'xc:red' -orient RightTop $orientedImage 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($creationOutput -join ' ')
        $orientation = @(& $script:ResizeImageMagickPath $orientedImage '-format' '%[orientation]' 'info:' 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($orientation -join ' ')
        $orientation -join '' | Should -Be 'RightTop'

        $result = Resize-Image $orientedImage -Height 20 -ImageMagickPath $script:ResizeImageMagickPath -PassThru -ErrorAction Stop
        Get-ResizeTestDimensions -ImagePath $result.Path | Should -Be '10 20'
    }

    It 'Handles spaces, apostrophes, and brackets in file names' {
        $specialImage = Join-Path -Path $script:ResizeIntegrationRoot -ChildPath "photo's [1].png"
        Copy-Item -LiteralPath $script:ResizeIntegrationImage -Destination $specialImage
        $result = Resize-Image $specialImage -Width 20 -ImageMagickPath $script:ResizeImageMagickPath -PassThru -ErrorAction Stop

        Get-ResizeTestDimensions -ImagePath $result.Path | Should -Be '20 10'
        Get-ResizeTestDimensions -ImagePath $specialImage | Should -Be '80 40'
    }

    It 'Resizes all GIF frames without discarding the animation' {
        $animation = Join-Path -Path $script:ResizeIntegrationRoot -ChildPath 'animation.gif'
        $creationOutput = @(& $script:ResizeImageMagickPath -delay 10 -size '80x40' 'xc:red' 'xc:blue' -loop 0 $animation 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($creationOutput -join ' ')
        $result = Resize-Image $animation -Percentage 50 -ImageMagickPath $script:ResizeImageMagickPath -PassThru -ErrorAction Stop

        $dimensions = @(Get-ResizeTestDimensions -ImagePath $result.Path)
        $dimensions.Count | Should -Be 2
        $dimensions[0] | Should -Be '40 20'
        $dimensions[1] | Should -Be '40 20'
        $delays = @(& $script:ResizeImageMagickPath $result.Path '-format' '%T\n' 'info:' 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($delays -join ' ')
        $delays -join ',' | Should -Be '10,10'
    }

    It 'Rejects multi-file frame output and cleans up without overwriting an existing copy' {
        $animation = Join-Path -Path $script:ResizeIntegrationRoot -ChildPath 'animation.gif'
        $creationOutput = @(& $script:ResizeImageMagickPath -size '80x40' 'xc:red' 'xc:blue' $animation 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($creationOutput -join ' ')
        $existingOutput = Join-Path -Path $script:ResizeIntegrationRoot -ChildPath 'existing.png'
        Copy-Item -LiteralPath $script:ResizeIntegrationImage -Destination $existingOutput
        $originalHash = (Get-FileHash -LiteralPath $existingOutput).Hash

        { Resize-Image $animation -Width 20 -OutputPath $existingOutput -Force -ImageMagickPath $script:ResizeImageMagickPath -ErrorAction Stop } |
            Should -Throw '*single output image*'
        (Get-FileHash -LiteralPath $existingOutput).Hash | Should -Be $originalHash
        @(Get-ChildItem -LiteralPath $script:ResizeIntegrationRoot -Directory -Force).Count | Should -Be 0
    }

    It 'Leaves corrupt source files unchanged on native processing failure' {
        [System.IO.File]::WriteAllText($script:ResizeIntegrationImage, 'invalid image data')
        $originalHash = (Get-FileHash -LiteralPath $script:ResizeIntegrationImage).Hash

        { Resize-Image $script:ResizeIntegrationImage -Width 20 -InPlace -ImageMagickPath $script:ResizeImageMagickPath -ErrorAction Stop } |
            Should -Throw '*ImageMagick failed*exit code*'
        (Get-FileHash -LiteralPath $script:ResizeIntegrationImage).Hash | Should -Be $originalHash
        @(Get-ChildItem -LiteralPath $script:ResizeIntegrationRoot -Directory -Force).Count | Should -Be 0
    }
}
