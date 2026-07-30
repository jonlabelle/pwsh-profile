#Requires -Modules Pester

BeforeDiscovery {
    $script:GitAvailable = $null -ne (Get-Command -Name 'git' -ErrorAction SilentlyContinue)
}

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'
    . "$PSScriptRoot/../../../Functions/Developer/Remove-GitIgnoredFile.ps1"
}

Describe 'Remove-GitIgnoredFile' -Tag 'Unit' {
    It 'Removes ignored files with a monochrome ANSI-free summary contract' -Skip:(-not $script:GitAvailable) {
        $repositoryRoot = Join-Path -Path $TestDrive -ChildPath 'ignored-file-repository'
        New-Item -Path $repositoryRoot -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path -Path $repositoryRoot -ChildPath '.gitignore') -Value '*.tmp' -Encoding UTF8
        Set-Content -Path (Join-Path -Path $repositoryRoot -ChildPath 'ignored.tmp') -Value 'temporary data' -Encoding UTF8
        & git -C $repositoryRoot init --quiet
        $LASTEXITCODE | Should-Be 0

        $script:ThemeHostOutput = [System.Collections.Generic.List[String]]::new()
        Mock -CommandName Write-Host -MockWith {
            if ($null -ne $Object)
            {
                $script:ThemeHostOutput.Add([String]$Object)
            }
        }

        $result = Remove-GitIgnoredFile -Path $repositoryRoot -Confirm:$false
        $escapeCharacter = [String][Char]27
        $ansiPattern = "$escapeCharacter\[[0-9;]*m"
        $rawOutput = $script:ThemeHostOutput -join ''
        $codes = @([Regex]::Matches($rawOutput, $ansiPattern).Value | Sort-Object -Unique)

        Test-Path -Path (Join-Path -Path $repositoryRoot -ChildPath 'ignored.tmp') | Should-BeFalsy
        $result.FilesRemoved | Should-Be 1
        $codes.Count | Should-Be 3
        $codes | Should-ContainCollection "$escapeCharacter[38;5;37m"
        $codes | Should-ContainCollection "$escapeCharacter[38;5;244m"
        $codes | Should-ContainCollection "$escapeCharacter[0m"
        $codes | Should-NotContainCollection "$escapeCharacter[33m"
        $codes | Should-NotContainCollection "$escapeCharacter[91m"
        ($result | ConvertTo-Json -Depth 5) | Should-NotMatchString ([Regex]::Escape($escapeCharacter))
    }
}
