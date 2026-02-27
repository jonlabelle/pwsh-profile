#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Show-ProfileFunctions function.

.DESCRIPTION
    Tests the Show-ProfileFunctions function including category filtering,
    short alias resolution, display name matching, and output formatting.

.NOTES
    These tests use a temporary Functions directory structure with mock .ps1 files
    to avoid coupling to the actual profile contents.
#>

BeforeAll {
    # Load the function under test
    . "$PSScriptRoot/../../../Functions/ProfileManagement/Show-ProfileFunctions.ps1"

    # Create a temporary Functions directory structure for testing
    $script:TestRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../../_tmp_/ShowProfileFunctionsTests'
    $script:TestFunctionsDir = Join-Path -Path $script:TestRoot -ChildPath 'Functions'

    # Clean up from any prior run
    if (Test-Path $script:TestRoot)
    {
        Remove-Item -Path $script:TestRoot -Recurse -Force
    }

    # Create category directories and mock function files
    $categories = @{
        'ActiveDirectory'      = @(
            @{ Name = 'Test-ADCredential'; Synopsis = 'Test Active Directory credentials.' }
        )
        'Developer'            = @(
            @{ Name = 'Import-DotEnv'; Synopsis = 'Loads environment variables from dotenv files.' }
            @{ Name = 'Get-DotNetVersion'; Synopsis = 'Gets installed .NET Framework versions.' }
        )
        'NetworkAndDns'        = @(
            @{ Name = 'Test-Port'; Synopsis = 'Tests TCP or UDP port connectivity.' }
            @{ Name = 'Get-DnsRecord'; Synopsis = 'Retrieves DNS records for a domain.' }
        )
        'SystemAdministration' = @(
            @{ Name = 'Test-Admin'; Synopsis = 'Determines if session has elevated privileges.' }
        )
        'Utilities'            = @(
            @{ Name = 'Format-Bytes'; Synopsis = 'Formats byte quantities into human-friendly units.' }
        )
    }

    foreach ($catName in $categories.Keys)
    {
        $catDir = Join-Path -Path $script:TestFunctionsDir -ChildPath $catName
        New-Item -Path $catDir -ItemType Directory -Force | Out-Null

        foreach ($func in $categories[$catName])
        {
            $funcContent = @"
function $($func.Name)
{
    <#
    .SYNOPSIS
        $($func.Synopsis)
    #>
    [CmdletBinding()]
    param()
    Write-Output 'mock'
}
"@
            $funcFile = Join-Path -Path $catDir -ChildPath "$($func.Name).ps1"
            [System.IO.File]::WriteAllText($funcFile, $funcContent, [System.Text.UTF8Encoding]::new($false))
        }
    }

    # Create a mock profile file so the function can resolve the Functions path
    $profileContent = '# mock profile'
    $profileFile = Join-Path -Path $script:TestRoot -ChildPath 'Microsoft.PowerShell_profile.ps1'
    [System.IO.File]::WriteAllText($profileFile, $profileContent, [System.Text.UTF8Encoding]::new($false))
}

AfterAll {
    if (Test-Path $script:TestRoot)
    {
        Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Show-ProfileFunctions' {
    BeforeAll {
        # Override $PROFILE so the function finds our test Functions directory
        $script:OriginalProfile = $PROFILE
        $global:PROFILE = Join-Path -Path $script:TestRoot -ChildPath 'Microsoft.PowerShell_profile.ps1'
    }

    AfterAll {
        $global:PROFILE = $script:OriginalProfile
    }

    Context 'No category filter (show all)' {
        It 'Should display all categories when no -Category is specified' {
            $output = Show-ProfileFunctions 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Active Directory'
            $outputText | Should -Match 'Developer'
            $outputText | Should -Match 'Network And Dns'
            $outputText | Should -Match 'System Administration'
            $outputText | Should -Match 'Utilities'
        }

        It 'Should display all function names when no -Category is specified' {
            $output = Show-ProfileFunctions 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Test-ADCredential'
            $outputText | Should -Match 'Import-DotEnv'
            $outputText | Should -Match 'Test-Port'
            $outputText | Should -Match 'Test-Admin'
            $outputText | Should -Match 'Format-Bytes'
        }

        It 'Should show correct total count across all categories' {
            $output = Show-ProfileFunctions 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match '7 functions'
            $outputText | Should -Match '5 categories'
        }
    }

    Context 'Category filtering with folder names' {
        It 'Should filter to a single category by exact folder name' {
            $output = Show-ProfileFunctions -Category 'ActiveDirectory' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Active Directory'
            $outputText | Should -Match 'Test-ADCredential'
            $outputText | Should -Match '1 functions'
            $outputText | Should -Match '1 categories'
        }

        It 'Should filter to a single category case-insensitively' {
            $output = Show-ProfileFunctions -Category 'activedirectory' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Active Directory'
            $outputText | Should -Match 'Test-ADCredential'
        }

        It 'Should filter to multiple categories by folder name' {
            $output = Show-ProfileFunctions -Category 'Developer', 'Utilities' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Developer'
            $outputText | Should -Match 'Import-DotEnv'
            $outputText | Should -Match 'Utilities'
            $outputText | Should -Match 'Format-Bytes'
            $outputText | Should -Match '3 functions'
            $outputText | Should -Match '2 categories'
        }

        It 'Should not show categories not requested' {
            $output = Show-ProfileFunctions -Category 'Utilities' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Not -Match 'Active Directory'
            $outputText | Should -Not -Match 'Developer'
            $outputText | Should -Not -Match 'Network And Dns'
        }
    }

    Context 'Category filtering with short aliases' {
        It 'Should resolve "ad" to ActiveDirectory' {
            $output = Show-ProfileFunctions -Category 'ad' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Active Directory'
            $outputText | Should -Match 'Test-ADCredential'
        }

        It 'Should resolve "dev" to Developer' {
            $output = Show-ProfileFunctions -Category 'dev' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Developer'
            $outputText | Should -Match 'Import-DotEnv'
        }

        It 'Should resolve "network" to NetworkAndDns' {
            $output = Show-ProfileFunctions -Category 'network' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Network And Dns'
            $outputText | Should -Match 'Test-Port'
        }

        It 'Should resolve "dns" to NetworkAndDns' {
            $output = Show-ProfileFunctions -Category 'dns' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Network And Dns'
        }

        It 'Should resolve "sysadmin" to SystemAdministration' {
            $output = Show-ProfileFunctions -Category 'sysadmin' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'System Administration'
            $outputText | Should -Match 'Test-Admin'
        }

        It 'Should resolve "sys" to SystemAdministration' {
            $output = Show-ProfileFunctions -Category 'sys' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'System Administration'
        }

        It 'Should resolve "admin" to SystemAdministration' {
            $output = Show-ProfileFunctions -Category 'admin' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'System Administration'
        }

        It 'Should resolve "utils" to Utilities' {
            $output = Show-ProfileFunctions -Category 'utils' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Utilities'
            $outputText | Should -Match 'Format-Bytes'
        }

        It 'Should resolve "util" to Utilities' {
            $output = Show-ProfileFunctions -Category 'util' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Utilities'
        }

        It 'Short aliases should be case-insensitive' {
            $output = Show-ProfileFunctions -Category 'AD' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Active Directory'
        }
    }

    Context 'Category filtering with display names (spaced)' {
        It 'Should resolve "Active Directory" (spaced display name)' {
            $output = Show-ProfileFunctions -Category 'Active Directory' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Active Directory'
            $outputText | Should -Match 'Test-ADCredential'
        }

        It 'Should resolve "Network And Dns" (spaced display name)' {
            $output = Show-ProfileFunctions -Category 'Network And Dns' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Network And Dns'
            $outputText | Should -Match 'Test-Port'
        }

        It 'Spaced display names should be case-insensitive' {
            $output = Show-ProfileFunctions -Category 'active directory' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Active Directory'
        }
    }

    Context 'Category positional parameter' {
        It 'Should accept Category as a positional parameter' {
            $output = Show-ProfileFunctions 'dev' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Developer'
            $outputText | Should -Match 'Import-DotEnv'
        }
    }

    Context 'Unknown category handling' {
        It 'Should warn for unknown category names' {
            $warnings = Show-ProfileFunctions -Category 'bogus' 3>&1
            ($warnings | Out-String) | Should -Match "Unknown category: 'bogus'"
        }

        It 'Should warn no valid categories when all are unknown' {
            $warnings = Show-ProfileFunctions -Category 'bogus' 3>&1
            ($warnings | Out-String) | Should -Match 'No valid categories specified'
        }

        It 'Should show valid category even if another is unknown' {
            $allOutput = Show-ProfileFunctions -Category 'dev', 'bogus' *>&1
            $outputText = ($allOutput | Out-String)

            $outputText | Should -Match 'Developer'
            $outputText | Should -Match "Unknown category: 'bogus'"
        }
    }

    Context 'Synopsis display' {
        It 'Should display the synopsis for each function' {
            $output = Show-ProfileFunctions -Category 'ad' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Test Active Directory credentials'
        }

        It 'Should display functions sorted alphabetically within a category' {
            $output = Show-ProfileFunctions -Category 'dev' 6>&1
            $outputText = ($output | Out-String)

            # Get-DotNetVersion should appear before Import-DotEnv
            $dotnetPos = $outputText.IndexOf('Get-DotNetVersion')
            $importPos = $outputText.IndexOf('Import-DotEnv')
            $dotnetPos | Should -BeLessThan $importPos
        }
    }

    Context 'Output footer' {
        It 'Should display Get-Help hint in footer' {
            $output = Show-ProfileFunctions -Category 'ad' 6>&1
            $outputText = ($output | Out-String)

            $outputText | Should -Match 'Get-Help'
        }

    }
}
