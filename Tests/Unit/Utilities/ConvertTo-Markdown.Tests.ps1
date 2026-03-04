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

        return @('# Converted Markdown', '', "Source: $($argsArray[-1])")
    }
}

AfterAll {
    Remove-Item -Path Function:\pwshPandocTestShim -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-Markdown' -Tag 'Unit' {
    BeforeEach {
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "convert-to-markdown-tests-$(Get-Random)"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        $script:PandocShimInvocations = @()
        $script:PandocShimExitCode = 0
    }

    AfterEach {
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

        It 'Converts a local file path and returns Markdown text' {
            $inputFile = Join-Path -Path $script:TestDir -ChildPath 'sample.html'
            '<h1>Hello</h1>' | Set-Content -LiteralPath $inputFile -NoNewline

            $result = ConvertTo-Markdown -InputObject $inputFile

            $result | Should -Match '^# Converted Markdown'
            $runCall = $script:PandocShimInvocations[0]
            $runCall | Should -Contain '--to'
            $runCall | Should -Contain 'gfm'
            $runCall | Should -Contain ([System.IO.Path]::GetFullPath($inputFile))
        }

        It 'Converts an HTTPS URL and passes it to pandoc' {
            $result = ConvertTo-Markdown -InputObject 'https://example.com/docs/page.html'

            $result | Should -Match 'example\.com/docs/page\.html'
            $runCall = $script:PandocShimInvocations[0]
            $runCall | Should -Contain 'https://example.com/docs/page.html'
        }

        It 'Throws when a local file path does not exist' {
            $missingPath = Join-Path -Path $script:TestDir -ChildPath 'missing.html'

            { ConvertTo-Markdown -InputObject $missingPath } |
            Should -Throw "*Input path does not exist or is not a file: $missingPath*"
        }

        It 'Accepts pipeline input' {
            $results = @('https://example.com/one', 'https://example.com/two') |
            ConvertTo-Markdown

            @($results).Count | Should -Be 2
            $results[0] | Should -Match 'example\.com/one'
            $results[1] | Should -Match 'example\.com/two'
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
            Should -Throw "*exit code 9*"
        }
    }
}
