#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Find-ProfileFunction function.

.DESCRIPTION
    Tests keyword search, ranking, category filtering, alias matching, and warning behavior
    for the Find-ProfileFunction profile discovery command.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function under test
    . "$PSScriptRoot/../../../Functions/ProfileManagement/Find-ProfileFunction.ps1"

    # Create a temporary Functions directory structure for testing
    $script:TestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "FindProfileFunctionTests-$(Get-Random)"
    $script:TestFunctionsDir = Join-Path -Path $script:TestRoot -ChildPath 'Functions'

    if (Test-Path -LiteralPath $script:TestRoot)
    {
        Remove-Item -Path $script:TestRoot -Recurse -Force
    }

    $definitions = @(
        @{
            Category = 'Developer'
            Name = 'Invoke-DockerAutoRun'
            Synopsis = 'Auto-detects project type and builds/runs a Docker container.'
            Alias = 'docker-auto'
        }
        @{
            Category = 'Developer'
            Name = 'Invoke-SqlFluff'
            Synopsis = 'Runs SQLFluff linting and auto-fixing via Docker.'
            Alias = ''
        }
        @{
            Category = 'NetworkAndDns'
            Name = 'Test-DnsPropagation'
            Synopsis = 'Checks DNS propagation across multiple public DNS servers.'
            Alias = ''
        }
        @{
            Category = 'SystemAdministration'
            Name = 'Test-PendingReboot'
            Synopsis = 'Checks if the system has pending reboot requirements.'
            Alias = ''
        }
        @{
            Category = 'Utilities'
            Name = 'ConvertTo-Markdown'
            Synopsis = 'Converts URLs or local files to Markdown with Pandoc.'
            Alias = ''
        }
        @{
            Category = 'Utilities'
            Name = 'Get-StringHash'
            Synopsis = 'Computes hash values for strings.'
            Alias = ''
        }
    )

    foreach ($entry in $definitions)
    {
        $categoryDir = Join-Path -Path $script:TestFunctionsDir -ChildPath $entry.Category
        New-Item -Path $categoryDir -ItemType Directory -Force | Out-Null

        $aliasLine = ''
        if (-not [string]::IsNullOrWhiteSpace($entry.Alias))
        {
            $aliasLine = "Set-Alias -Name '$($entry.Alias)' -Value '$($entry.Name)'"
        }

        $content = @"
function $($entry.Name)
{
    <#
    .SYNOPSIS
        $($entry.Synopsis)
    #>
    [CmdletBinding()]
    param()
    'mock'
}
$aliasLine
"@

        $filePath = Join-Path -Path $categoryDir -ChildPath "$($entry.Name).ps1"
        [System.IO.File]::WriteAllText($filePath, $content, [System.Text.UTF8Encoding]::new($false))
    }

    # Create a mock profile file so the function can resolve the Functions path
    $profileFile = Join-Path -Path $script:TestRoot -ChildPath 'Microsoft.PowerShell_profile.ps1'
    [System.IO.File]::WriteAllText($profileFile, '# mock profile', [System.Text.UTF8Encoding]::new($false))
}

AfterAll {
    if (Test-Path -LiteralPath $script:TestRoot)
    {
        Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Find-ProfileFunction' {
    BeforeAll {
        $script:OriginalProfile = $PROFILE
        Set-Variable -Name 'PROFILE' -Value (Join-Path -Path $script:TestRoot -ChildPath 'Microsoft.PowerShell_profile.ps1') -Scope Global
    }

    AfterAll {
        Set-Variable -Name 'PROFILE' -Value $script:OriginalProfile -Scope Global
    }

    Context 'Parameter Validation' {
        It 'Should have mandatory Query parameter' {
            $command = Get-Command Find-ProfileFunction
            $queryParam = $command.Parameters['Query']
            $queryParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should validate Top parameter range' {
            $command = Get-Command Find-ProfileFunction
            $topParam = $command.Parameters['Top']
            $validateRange = $topParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $validateRange.MinRange | Should -Be 1
            $validateRange.MaxRange | Should -Be 500
        }
    }

    Context 'Search behavior' {
        It 'Should find by function name keyword' {
            $results = @(Find-ProfileFunction -Query 'sqlfluff')
            $results | Should -Not -BeNullOrEmpty
            $results[0].Name | Should -Be 'Invoke-SqlFluff'
        }

        It 'Should find by synopsis keyword' {
            $results = @(Find-ProfileFunction -Query 'pandoc markdown')
            $results.Count | Should -Be 1
            $results[0].Name | Should -Be 'ConvertTo-Markdown'
        }

        It 'Should find by alias keyword' {
            $results = @(Find-ProfileFunction -Query 'docker-auto')
            $results.Count | Should -Be 1
            $results[0].Name | Should -Be 'Invoke-DockerAutoRun'
            $results[0].Aliases | Should -Match 'docker-auto'
        }

        It 'Should support MatchAny for multi-term queries' {
            $results = @(Find-ProfileFunction -Query 'docker reboot' -MatchAny)
            $results.Count | Should -BeGreaterThan 1
            $results.Name | Should -Contain 'Invoke-DockerAutoRun'
            $results.Name | Should -Contain 'Test-PendingReboot'
        }

        It 'Should rank stronger function name matches ahead of weaker matches' {
            $results = @(Find-ProfileFunction -Query 'docker')
            $results.Count | Should -BeGreaterThan 1
            $results[0].Name | Should -Be 'Invoke-DockerAutoRun'
            $results[0].Score | Should -BeGreaterOrEqual $results[1].Score
        }

        It 'Should apply Top result limiting' {
            $results = @(Find-ProfileFunction -Query 'docker' -Top 1)
            $results.Count | Should -Be 1
        }
    }

    Context 'Category filtering' {
        It 'Should filter by category alias' {
            $results = @(Find-ProfileFunction -Query 'docker' -Category 'dev')
            $results | Should -Not -BeNullOrEmpty
            ($results | Select-Object -ExpandProperty Category -Unique) | Should -Be 'Developer'
        }

        It 'Should filter by spaced category display name' {
            $results = @(Find-ProfileFunction -Query 'dns' -Category 'Network And Dns')
            $results.Count | Should -Be 1
            $results[0].Name | Should -Be 'Test-DnsPropagation'
            $results[0].Category | Should -Be 'Network And Dns'
        }

        It 'Should warn for unknown category values' {
            $warnings = Find-ProfileFunction -Query 'docker' -Category 'bogus' 3>&1
            ($warnings | Out-String) | Should -Match "Unknown category: 'bogus'"
            ($warnings | Out-String) | Should -Match 'No valid categories specified'
        }
    }

    Context 'No match behavior' {
        It 'Should warn when no results match the query' {
            $warnings = Find-ProfileFunction -Query 'no-such-function-keyword' 3>&1
            ($warnings | Out-String) | Should -Match 'No functions matched query'
        }
    }
}
