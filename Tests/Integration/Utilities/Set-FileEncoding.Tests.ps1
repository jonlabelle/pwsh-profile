#Requires -Modules Pester

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Utilities/Get-FileEncoding.ps1"
    . "$PSScriptRoot/../../../Functions/Utilities/Set-FileEncoding.ps1"

    $script:TestDir = Join-Path -Path $TestDrive -ChildPath 'SetFileEncodingIntegrationTests'
    New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
}

Describe 'Set-FileEncoding Integration Tests' -Tag 'Integration' {
    It 'Converts wildcard-matched text files without touching non-target files' {
        $textDir = Join-Path -Path $script:TestDir -ChildPath 'wildcards'
        New-Item -Path $textDir -ItemType Directory -Force | Out-Null

        $firstTextFile = Join-Path -Path $textDir -ChildPath 'first.txt'
        $secondTextFile = Join-Path -Path $textDir -ChildPath 'second.txt'
        $markdownFile = Join-Path -Path $textDir -ChildPath 'notes.md'
        $binaryFile = Join-Path -Path $textDir -ChildPath 'archive.bin'

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($firstTextFile, 'alpha', $utf8NoBom)
        [System.IO.File]::WriteAllText($secondTextFile, 'beta', $utf8NoBom)
        [System.IO.File]::WriteAllText($markdownFile, '# notes', $utf8NoBom)
        [System.IO.File]::WriteAllBytes($binaryFile, [byte[]](77, 90, 144, 0, 3, 0, 0, 0))

        $binaryBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($binaryFile))

        $results = Set-FileEncoding -Path (Join-Path -Path $textDir -ChildPath '*.txt') -Encoding UTF16BE -PassThru

        $results.Count | Should -Be 2
        ($results | Where-Object { $_.Success }).Count | Should -Be 2
        ($results | Where-Object { -not $_.Skipped }).Count | Should -Be 2

        (Get-FileEncoding -FilePath $firstTextFile).CodePage | Should -Be 1201
        (Get-FileEncoding -FilePath $secondTextFile).CodePage | Should -Be 1201
        (Get-FileEncoding -FilePath $markdownFile).CodePage | Should -Be 65001
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($binaryFile)) | Should -Be $binaryBefore
    }

    It 'Works in the pipeline and returns one summary object per processed file' {
        $pipelineDir = Join-Path -Path $script:TestDir -ChildPath 'pipeline'
        New-Item -Path $pipelineDir -ItemType Directory -Force | Out-Null

        $firstScript = Join-Path -Path $pipelineDir -ChildPath 'first.ps1'
        $secondScript = Join-Path -Path $pipelineDir -ChildPath 'second.ps1'
        [System.IO.File]::WriteAllText($firstScript, 'Write-Host "first"', [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($secondScript, 'Write-Host "second"', [System.Text.Encoding]::ASCII)

        $results = Get-ChildItem -Path $pipelineDir -Filter '*.ps1' |
        Set-FileEncoding -Encoding UTF8BOM -PassThru

        $results.Count | Should -Be 2
        ($results | Where-Object { $_.Success }).Count | Should -Be 2
        ($results | Where-Object { $_.TargetEncoding -match 'UTF-8' }).Count | Should -Be 2

        (Get-FileEncoding -FilePath $firstScript).GetPreamble().Length | Should -Be 3
        (Get-FileEncoding -FilePath $secondScript).GetPreamble().Length | Should -Be 3
    }
}
