#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for ConvertTo-UrlSlug.

.DESCRIPTION
    Tests slug generation from arbitrary text and rename behavior for files/directories.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Utilities/ConvertTo-UrlSlug.ps1"
}

Describe 'ConvertTo-UrlSlug' -Tag 'Unit', 'Utilities' {
    Context 'String mode' {
        It 'Should convert text to a lowercase slug' {
            $result = ConvertTo-UrlSlug -InputObject 'Hello, World!'
            $result | Should -Be 'hello-world'
        }

        It 'Should strip diacritics by default' {
            $slugInput = ('Cr{0}me br{1}l{2}e & caf{2}' -f [char]0x00E8, [char]0x00FB, [char]0x00E9)
            $result = ConvertTo-UrlSlug -InputObject $slugInput
            $result | Should -Be 'creme-brulee-cafe'
        }

        It 'Should decode URL-encoded input' {
            $result = ConvertTo-UrlSlug -InputObject 'My%20Encoded%20Title'
            $result | Should -Be 'my-encoded-title'
        }

        It 'Should allow a custom separator' {
            $result = ConvertTo-UrlSlug -InputObject 'Hello World' -Separator '_'
            $result | Should -Be 'hello_world'
        }

        It 'Should preserve unicode characters when KeepUnicode is specified' {
            $slugInput = ('{0}{1} 2026' -f [char]0x6771, [char]0x4EAC)
            $expected = ('{0}{1}-2026' -f [char]0x6771, [char]0x4EAC)
            $result = ConvertTo-UrlSlug -InputObject $slugInput -KeepUnicode
            $result | Should -Be $expected
        }

        It 'Should accept multiple pipeline values' {
            $result = 'First Post', 'Second Post' | ConvertTo-UrlSlug
            $result.Count | Should -Be 2
            $result[0] | Should -Be 'first-post'
            $result[1] | Should -Be 'second-post'
        }
    }

    Context 'Rename mode' {
        BeforeEach {
            $script:testRoot = Join-Path -Path $TestDrive -ChildPath 'UrlSlugRenameTests'
            New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path -LiteralPath $script:testRoot)
            {
                Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should rename a file and preserve extension' {
            $filePath = Join-Path -Path $script:testRoot -ChildPath 'My Draft File.txt'
            'content' | Set-Content -LiteralPath $filePath -NoNewline

            ConvertTo-UrlSlug -LiteralPath $filePath

            Test-Path -LiteralPath (Join-Path -Path $script:testRoot -ChildPath 'my-draft-file.txt') | Should -Be $true
        }

        It 'Should rename a directory' {
            $directoryPath = Join-Path -Path $script:testRoot -ChildPath 'Release Notes 2026'
            New-Item -Path $directoryPath -ItemType Directory -Force | Out-Null

            ConvertTo-UrlSlug -LiteralPath $directoryPath

            Test-Path -LiteralPath (Join-Path -Path $script:testRoot -ChildPath 'release-notes-2026') | Should -Be $true
        }

        It 'Should resolve name collisions with numeric suffixes' {
            $existingPath = Join-Path -Path $script:testRoot -ChildPath 'my-file.txt'
            $renamePath = Join-Path -Path $script:testRoot -ChildPath 'My File.txt'

            'existing' | Set-Content -LiteralPath $existingPath -NoNewline
            'rename-me' | Set-Content -LiteralPath $renamePath -NoNewline

            ConvertTo-UrlSlug -LiteralPath $renamePath

            Test-Path -LiteralPath (Join-Path -Path $script:testRoot -ChildPath 'my-file-2.txt') | Should -Be $true
        }

        It 'Should support WhatIf and not rename when specified' {
            $filePath = Join-Path -Path $script:testRoot -ChildPath 'What If Name.txt'
            'content' | Set-Content -LiteralPath $filePath -NoNewline

            ConvertTo-UrlSlug -LiteralPath $filePath -WhatIf

            Test-Path -LiteralPath $filePath | Should -Be $true
            Test-Path -LiteralPath (Join-Path -Path $script:testRoot -ChildPath 'what-if-name.txt') | Should -Be $false
        }

        It 'Should return renamed item when PassThru is specified' {
            $filePath = Join-Path -Path $script:testRoot -ChildPath 'Pass Thru Me.txt'
            'content' | Set-Content -LiteralPath $filePath -NoNewline

            $result = ConvertTo-UrlSlug -LiteralPath $filePath -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'pass-thru-me.txt'
        }

        It 'Should rename from Get-ChildItem pipeline when PassThru is specified' {
            $filePath = Join-Path -Path $script:testRoot -ChildPath 'Pipeline Rename.txt'
            'content' | Set-Content -LiteralPath $filePath -NoNewline

            $result = Get-ChildItem -LiteralPath $script:testRoot -File | ConvertTo-UrlSlug -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Contain 'pipeline-rename.txt'
        }
    }
}
