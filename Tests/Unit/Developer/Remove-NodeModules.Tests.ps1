#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'
    . "$PSScriptRoot/../../../Functions/Developer/Remove-NodeModules.ps1"
}

Describe 'Remove-NodeModules' -Tag 'Unit' {
    It 'Removes project dependencies with a monochrome ANSI-free summary contract' {
        $projectRoot = Join-Path -Path $TestDrive -ChildPath 'node-project'
        $artifactRoot = Join-Path -Path $projectRoot -ChildPath 'node_modules'
        $packageRoot = Join-Path -Path $artifactRoot -ChildPath 'sample-package'
        New-Item -Path $packageRoot -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path -Path $projectRoot -ChildPath 'package.json') -Value '{}' -Encoding UTF8
        New-Item -Path (Join-Path -Path $packageRoot -ChildPath 'index.js') -ItemType File -Force | Out-Null

        $script:ThemeHostOutput = [System.Collections.Generic.List[String]]::new()
        Mock -CommandName Write-Host -MockWith {
            if ($null -ne $Object)
            {
                $script:ThemeHostOutput.Add([String]$Object)
            }
        }

        $result = Remove-NodeModules -Path $projectRoot -Confirm:$false
        $escapeCharacter = [String][Char]27
        $ansiPattern = "$escapeCharacter\[[0-9;]*m"
        $rawOutput = $script:ThemeHostOutput -join ''
        $codes = @([Regex]::Matches($rawOutput, $ansiPattern).Value | Sort-Object -Unique)

        Test-Path -Path $artifactRoot | Should-BeFalsy
        $result.TotalProjectsFound | Should-Be 1
        $result.FoldersRemoved | Should-Be 1
        $codes.Count | Should-Be 3
        $codes | Should-ContainCollection "$escapeCharacter[38;5;37m"
        $codes | Should-ContainCollection "$escapeCharacter[38;5;244m"
        $codes | Should-ContainCollection "$escapeCharacter[0m"
        $codes | Should-NotContainCollection "$escapeCharacter[33m"
        $codes | Should-NotContainCollection "$escapeCharacter[91m"
        ($result | ConvertTo-Json -Depth 5) | Should-NotMatchString ([Regex]::Escape($escapeCharacter))
    }
}
