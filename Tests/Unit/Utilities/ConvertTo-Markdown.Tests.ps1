#Requires -Modules Pester

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Utilities/ConvertTo-Markdown.ps1"

    # Deterministic shim used by Get-Command mocks so tests do not depend on Pandoc being installed.
    $script:PandocCommandName = 'pwshPandocTestShim'
    $script:PandocShimInvocations = @()
    $script:PandocShimExitCode = 0

    function pwshPandocTestShim
    {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [Object[]]$RemainingArgs
        )

        $argsArray = @($RemainingArgs)
        $script:PandocShimInvocations += , $argsArray

        $global:LASTEXITCODE = $script:PandocShimExitCode
        if ($script:PandocShimExitCode -ne 0)
        {
            return @('pandoc error')
        }

        $markdownText = @(
            '# Converted Markdown',
            '',
            "Source: $($argsArray[-1])"
        ) -join [Environment]::NewLine

        $outputArgIndex = [Array]::IndexOf($argsArray, '-o')
        if ($outputArgIndex -ge 0 -and $outputArgIndex + 1 -lt $argsArray.Count)
        {
            $outputPath = [String]$argsArray[$outputArgIndex + 1]
            $outputDirectory = Split-Path -Path $outputPath -Parent
            if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container))
            {
                $null = New-Item -Path $outputDirectory -ItemType Directory -Force
            }

            Set-Content -LiteralPath $outputPath -Value $markdownText -NoNewline -Encoding UTF8
            return @()
        }

        return @($markdownText)
    }
}

AfterAll {
    Remove-Item -Path Function:\pwshPandocTestShim -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-Markdown' -Tag 'Unit' {
    BeforeEach {
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "convert-to-markdown-tests-$(Get-Random)"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
        Push-Location -Path $script:TestDir

        $script:PandocShimInvocations = @()
        $script:PandocShimExitCode = 0
    }

    AfterEach {
        Pop-Location

        if (Test-Path -LiteralPath $script:TestDir)
        {
            Remove-Item -LiteralPath $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Prerequisite validation' {
        It 'Throws when Pandoc is not installed' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'pandoc' } -MockWith { $null }

            { ConvertTo-Markdown -InputObject 'https://example.com' } |
            Should -Throw 'Pandoc is not installed or not available in PATH. Please install Pandoc and try again.'
        }
    }

    Context 'Alias' {
        It 'Creates url2markdown alias to ConvertTo-Markdown' {
            $aliasCommand = Get-Command -Name 'url2markdown' -ErrorAction SilentlyContinue

            $aliasCommand | Should -Not -BeNullOrEmpty
            $aliasCommand.CommandType | Should -Be 'Alias'
            $aliasCommand.Definition | Should -Be 'ConvertTo-Markdown'
        }
    }

    Context 'Input handling' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'pandoc' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:PandocCommandName
                    Source = '/usr/local/bin/pandoc'
                }
            }
        }

        It 'Converts a local file path and auto-saves markdown when -OutputPath is omitted' {
            $inputFile = Join-Path -Path $script:TestDir -ChildPath 'sample.html'
            '<h1>Hello</h1>' | Set-Content -LiteralPath $inputFile -NoNewline

            $result = ConvertTo-Markdown -InputObject $inputFile
            $expectedPath = Join-Path -Path $script:TestDir -ChildPath 'sample.md'

            $result | Should -BeNullOrEmpty
            Test-Path -LiteralPath $expectedPath | Should -BeTrue
            Get-Content -LiteralPath $expectedPath -Raw | Should -Match '^# Converted Markdown'
            $runCall = $script:PandocShimInvocations[0]
            $runCall | Should -Contain '--to'
            $runCall | Should -Contain 'gfm'
            $runCall | Should -Contain '-o'
            $runCall | Should -Contain $expectedPath
            $runCall | Should -Contain ([System.IO.Path]::GetFullPath($inputFile))
        }

        It 'Converts an HTTPS URL and writes to an auto-generated file path' {
            $result = ConvertTo-Markdown -InputObject 'https://example.com/docs/page.html'
            $expectedPath = Join-Path -Path $script:TestDir -ChildPath 'example-com-docs-page.md'

            $result | Should -BeNullOrEmpty
            Test-Path -LiteralPath $expectedPath | Should -BeTrue
            $runCall = $script:PandocShimInvocations[0]
            $runCall | Should -Contain '-o'
            $runCall | Should -Contain $expectedPath
            $runCall | Should -Contain 'https://example.com/docs/page.html'
        }

        It 'Auto-saves URL input using URI path segments when -OutputPath is omitted' {
            $result = ConvertTo-Markdown -InputObject 'https://example.com/docs/page.html'
            $expectedPath = Join-Path -Path $script:TestDir -ChildPath 'example-com-docs-page.md'

            $result | Should -BeNullOrEmpty
            Test-Path -LiteralPath $expectedPath | Should -BeTrue
            Get-Content -LiteralPath $expectedPath -Raw | Should -Match '^# Converted Markdown'
        }

        It 'Auto-saves base URL input as domain-derived markdown filename' {
            ConvertTo-Markdown -InputObject 'https://example.com' | Out-Null
            $expectedPath = Join-Path -Path $script:TestDir -ChildPath 'example-com.md'

            Test-Path -LiteralPath $expectedPath | Should -BeTrue
        }

        It 'Throws when a local file path does not exist' {
            $missingPath = Join-Path -Path $script:TestDir -ChildPath 'missing.html'

            { ConvertTo-Markdown -InputObject $missingPath } |
            Should -Throw "*Input path does not exist or is not a file: $missingPath*"
        }

        It 'Accepts pipeline input' {
            $results = @('https://example.com/one', 'https://example.com/two') |
            ConvertTo-Markdown

            $results | Should -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'example-com-one.md') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $script:TestDir -ChildPath 'example-com-two.md') | Should -BeTrue
        }
    }

    Context 'Argument handling' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'pandoc' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:PandocCommandName
                    Source = '/usr/local/bin/pandoc'
                }
            }
        }

        It 'Includes -From, -To, and additional Pandoc args' {
            $inputFile = Join-Path -Path $script:TestDir -ChildPath 'sample.html'
            '<h1>Hello</h1>' | Set-Content -LiteralPath $inputFile -NoNewline

            ConvertTo-Markdown -InputObject $inputFile -From html -To markdown -PandocArgs @('--wrap=none', '--strip-comments') | Out-Null

            $runCall = $script:PandocShimInvocations[0]
            $runCall | Should -Contain '--from'
            $runCall | Should -Contain 'html'
            $runCall | Should -Contain '--to'
            $runCall | Should -Contain 'markdown'
            $runCall | Should -Contain '--wrap=none'
            $runCall | Should -Contain '--strip-comments'
        }

        It 'Accepts Pandoc markdown output variants and extension modifiers for -To' {
            $inputFile = Join-Path -Path $script:TestDir -ChildPath 'sample.html'
            '<h1>Hello</h1>' | Set-Content -LiteralPath $inputFile -NoNewline

            ConvertTo-Markdown -InputObject $inputFile -To commonmark | Out-Null
            ConvertTo-Markdown -InputObject $inputFile -To markdown_strict | Out-Null
            ConvertTo-Markdown -InputObject $inputFile -To markua | Out-Null
            ConvertTo-Markdown -InputObject $inputFile -To 'gfm+task_lists+pipe_tables-smart' | Out-Null

            $runCall = $script:PandocShimInvocations[-1]
            $runCall | Should -Contain '--to'
            $runCall | Should -Contain 'gfm+task_lists+pipe_tables-smart'
        }

        It 'Rejects non-markdown or malformed values for -To' {
            $inputFile = Join-Path -Path $script:TestDir -ChildPath 'sample.html'
            '<h1>Hello</h1>' | Set-Content -LiteralPath $inputFile -NoNewline

            { ConvertTo-Markdown -InputObject $inputFile -To html } |
            Should -Throw "*Cannot validate argument on parameter 'To'*"

            { ConvertTo-Markdown -InputObject $inputFile -To 'gfm++task_lists' } |
            Should -Throw "*Cannot validate argument on parameter 'To'*"

            { ConvertTo-Markdown -InputObject $inputFile -To 'gfm+1invalid' } |
            Should -Throw "*Cannot validate argument on parameter 'To'*"
        }

        It 'Writes to -OutputPath and returns path with -PassThru' {
            $inputFile = Join-Path -Path $script:TestDir -ChildPath 'sample.html'
            '<h1>Hello</h1>' | Set-Content -LiteralPath $inputFile -NoNewline
            $outputPath = Join-Path -Path $script:TestDir -ChildPath 'output.md'

            $result = ConvertTo-Markdown -InputObject $inputFile -OutputPath $outputPath -PassThru

            $resolvedOutputPath = [System.IO.Path]::GetFullPath($outputPath)
            $result | Should -Be $resolvedOutputPath

            $runCall = $script:PandocShimInvocations[0]
            $runCall | Should -Contain '-o'
            $runCall | Should -Contain $resolvedOutputPath
            Test-Path -LiteralPath $resolvedOutputPath | Should -BeTrue
        }

        It 'Returns auto-generated output path with -PassThru when -OutputPath is omitted' {
            $result = ConvertTo-Markdown -InputObject 'https://example.com/notes' -PassThru
            $expectedPath = Join-Path -Path $script:TestDir -ChildPath 'example-com-notes.md'

            $result | Should -Be $expectedPath
            Test-Path -LiteralPath $expectedPath | Should -BeTrue
        }

        It 'Rejects multiple input values when -OutputPath is specified' {
            { @('https://example.com/one', 'https://example.com/two') | ConvertTo-Markdown -OutputPath (Join-Path -Path $script:TestDir -ChildPath 'out.md') } |
            Should -Throw '*only one InputObject value is supported*'
        }
    }

    Context 'Error handling' {
        BeforeEach {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'pandoc' } -MockWith {
                [PSCustomObject]@{
                    Name = $script:PandocCommandName
                    Source = '/usr/local/bin/pandoc'
                }
            }
        }

        It 'Throws when pandoc returns a non-zero exit code' {
            $script:PandocShimExitCode = 9

            { ConvertTo-Markdown -InputObject 'https://example.com/fail' } |
            Should -Throw '*exit code 9*'
        }
    }
}
