#Requires -Modules Pester

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Utilities/Get-FileEncoding.ps1"
    . "$PSScriptRoot/../../../Functions/Utilities/Set-FileEncoding.ps1"
}

Describe 'Set-FileEncoding' -Tag 'Unit' {
    BeforeEach {
        $script:TestDir = Join-Path -Path $TestDrive -ChildPath 'SetFileEncodingTests'
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
    }

    It 'Converts UTF8 without BOM to UTF8 with BOM' {
        $path = Join-Path -Path $script:TestDir -ChildPath 'utf8-no-bom.txt'
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($path, 'hello world', $utf8NoBom)

        $result = Set-FileEncoding -Path $path -Encoding UTF8BOM -PassThru

        $result.Success | Should -BeTrue
        $result.Skipped | Should -BeFalse
        $result.EncodingChanged | Should -BeTrue

        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF

        $detected = Get-FileEncoding -FilePath $path
        $detected.CodePage | Should -Be 65001
        $detected.GetPreamble().Length | Should -Be 3
    }

    It 'Skips files that already have the requested encoding' {
        $path = Join-Path -Path $script:TestDir -ChildPath 'utf16le.txt'
        [System.IO.File]::WriteAllText($path, 'hello world', [System.Text.Encoding]::Unicode)
        $beforeBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))

        $result = Set-FileEncoding -Path $path -Encoding UTF16LE -PassThru
        $afterBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))

        $result.Success | Should -BeTrue
        $result.Skipped | Should -BeTrue
        $result.EncodingChanged | Should -BeFalse
        $afterBytes | Should -Be $beforeBytes
    }

    It 'Rewrites matching encodings when Force is specified' {
        $path = Join-Path -Path $script:TestDir -ChildPath 'utf8-bom.txt'
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($path, 'hello world', $utf8Bom)

        $beforeWriteTime = (Get-Item -Path $path).LastWriteTimeUtc
        Start-Sleep -Milliseconds 1100

        $result = Set-FileEncoding -Path $path -Encoding UTF8BOM -Force -PassThru
        $afterWriteTime = (Get-Item -Path $path).LastWriteTimeUtc

        $result.Success | Should -BeTrue
        $result.Skipped | Should -BeFalse
        $result.Forced | Should -BeTrue
        $result.EncodingChanged | Should -BeFalse
        $afterWriteTime | Should -BeGreaterThan $beforeWriteTime
    }

    It 'Accepts pipeline input by FullName' {
        $path = Join-Path -Path $script:TestDir -ChildPath 'utf16le.txt'
        [System.IO.File]::WriteAllText($path, 'hello world', [System.Text.Encoding]::Unicode)

        $result = Get-Item -Path $path | Set-FileEncoding -Encoding UTF8 -PassThru
        $detected = Get-FileEncoding -FilePath $path

        $result.Success | Should -BeTrue
        $result.Skipped | Should -BeFalse
        $detected.CodePage | Should -Be 65001
        $detected.GetPreamble().Length | Should -Be 0
    }

    It 'Warns and skips binary files' {
        $path = Join-Path -Path $script:TestDir -ChildPath 'binary.dat'
        [System.IO.File]::WriteAllBytes($path, [byte[]](0, 1, 2, 3, 0, 255, 16, 32))
        $beforeBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))

        $result = Set-FileEncoding -Path $path -Encoding UTF8BOM -PassThru -WarningVariable warnings -WarningAction Continue
        $afterBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))

        $warnings | Should -Match 'binary'
        $result | Should -BeNullOrEmpty
        $afterBytes | Should -Be $beforeBytes
    }
}
