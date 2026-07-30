#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'
    . "$PSScriptRoot/../../../Functions/Developer/Remove-DotNetBuildArtifact.ps1"
}

Describe 'Remove-DotNetBuildArtifact' -Tag 'Unit' {
    It 'Removes project artifacts with a monochrome ANSI-free summary contract' {
        $projectRoot = Join-Path -Path $TestDrive -ChildPath 'dotnet-project'
        $artifactRoot = Join-Path -Path $projectRoot -ChildPath 'bin'
        New-Item -Path $artifactRoot -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $projectRoot -ChildPath 'sample.csproj') -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path -Path $artifactRoot -ChildPath 'sample.dll') -ItemType File -Force | Out-Null

        $script:ThemeHostOutput = [System.Collections.Generic.List[String]]::new()
        Mock -CommandName Write-Host -MockWith {
            if ($null -ne $Object)
            {
                $script:ThemeHostOutput.Add([String]$Object)
            }
        }

        $result = Remove-DotNetBuildArtifact -Path $projectRoot -Confirm:$false
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
