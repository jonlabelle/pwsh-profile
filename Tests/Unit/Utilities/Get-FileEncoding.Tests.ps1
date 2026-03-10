#Requires -Modules Pester

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Utilities/Get-FileEncoding.ps1"
}

Describe 'Get-FileEncoding' -Tag 'Unit' {
    BeforeEach {
        $script:TestDir = Join-Path -Path $TestDrive -ChildPath 'GetFileEncodingTests'
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
    }

    It 'Detects UTF8 without BOM' {
        $path = Join-Path -Path $script:TestDir -ChildPath 'utf8-no-bom.txt'
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($path, 'hello café', $utf8NoBom)

        $detected = Get-FileEncoding -FilePath $path
        $detected.CodePage | Should -Be 65001
        $detected.GetPreamble().Length | Should -Be 0
    }

    It 'Detects UTF8 with BOM' {
        $path = Join-Path -Path $script:TestDir -ChildPath 'utf8-bom.txt'
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($path, 'hello café', $utf8Bom)

        $detected = Get-FileEncoding -FilePath $path
        $detected.CodePage | Should -Be 65001
        $detected.GetPreamble().Length | Should -Be 3
    }

    It 'Detects UTF16LE with BOM' {
        $path = Join-Path -Path $script:TestDir -ChildPath 'utf16le.txt'
        [System.IO.File]::WriteAllText($path, 'hello world', [System.Text.Encoding]::Unicode)

        $detected = Get-FileEncoding -FilePath $path
        $detected.CodePage | Should -Be 1200
        $detected.GetPreamble().Length | Should -Be 2
    }

    It 'Returns UTF8 without BOM for empty files' {
        $path = Join-Path -Path $script:TestDir -ChildPath 'empty.txt'
        [System.IO.File]::WriteAllBytes($path, @())

        $detected = Get-FileEncoding -FilePath $path
        $detected.CodePage | Should -Be 65001
        $detected.GetPreamble().Length | Should -Be 0
    }
}
