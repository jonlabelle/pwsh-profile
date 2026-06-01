#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Update-DotNetTool.

.DESCRIPTION
    Validates local manifest discovery, global fallback behavior, dotnet argument
    construction, ShouldProcess handling, and result reporting.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Update-DotNetTool.ps1"

    $script:DotNetCommandName = 'pwshDotNetToolTestShim'
    $script:DotNetInvocations = @()
    $script:DotNetListOutput = @()
    $script:DotNetListExitCode = 0
    $script:DotNetSearchOutputByPackage = @{}
    $script:DotNetUpdateExitCodes = @{}

    function pwshDotNetToolTestShim
    {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [Object[]]$RemainingArgs
        )

        $argsArray = @($RemainingArgs)
        $script:DotNetInvocations += , $argsArray

        if ($argsArray.Count -ge 2 -and $argsArray[0] -eq 'tool' -and $argsArray[1] -eq 'list')
        {
            $global:LASTEXITCODE = $script:DotNetListExitCode
            return $script:DotNetListOutput
        }

        if ($argsArray.Count -ge 3 -and $argsArray[0] -eq 'tool' -and $argsArray[1] -eq 'search')
        {
            $packageId = [String]$argsArray[2]
            $global:LASTEXITCODE = 0
            if ($script:DotNetSearchOutputByPackage.ContainsKey($packageId))
            {
                return $script:DotNetSearchOutputByPackage[$packageId]
            }

            return @(
                'Package ID      Latest Version      Authors      Downloads      Verified'
                '------------------------------------------------------------------------'
                "$packageId      9.9.9               Tests        1"
            )
        }

        if ($argsArray.Count -ge 3 -and $argsArray[0] -eq 'tool' -and $argsArray[1] -eq 'update')
        {
            $packageId = [String]$argsArray[2]
            if ($script:DotNetUpdateExitCodes.ContainsKey($packageId))
            {
                $global:LASTEXITCODE = $script:DotNetUpdateExitCodes[$packageId]
            }
            else
            {
                $global:LASTEXITCODE = 0
            }

            if ($global:LASTEXITCODE -eq 0)
            {
                return "Tool '$packageId' was successfully updated."
            }

            return "Tool '$packageId' failed to update."
        }

        $global:LASTEXITCODE = 1
        return 'Unexpected dotnet invocation.'
    }
}

AfterAll {
    Remove-Item -Path Function:\pwshDotNetToolTestShim -ErrorAction SilentlyContinue
}

Describe 'Update-DotNetTool' {
    BeforeEach {
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dotnet-tool-tests-$(Get-Random)"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        $script:DotNetInvocations = @()
        $script:DotNetListOutput = @('{"version":1,"data":[{"packageId":"dotnetsay","version":"2.1.7","commands":["dotnetsay"]}]}')
        $script:DotNetListExitCode = 0
        $script:DotNetSearchOutputByPackage = @{}
        $script:DotNetUpdateExitCodes = @{}

        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'dotnet' } -MockWith {
            [PSCustomObject]@{
                Name = $script:DotNetCommandName
                Source = '/usr/local/bin/dotnet'
            }
        }
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestDir)
        {
            Remove-Item -LiteralPath $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Prerequisite validation' {
        It 'Throws when dotnet is not available' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'dotnet' } -MockWith { $null }

            { Update-DotNetTool -Path $script:TestDir } | Should -Throw 'dotnet CLI is not installed or not available in PATH. Install the .NET SDK and try again.'
        }
    }

    Context 'Scope detection' {
        It 'Updates local tools when a local manifest exists in the target directory' {
            $configDir = Join-Path -Path $script:TestDir -ChildPath '.config'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            $manifestPath = Join-Path -Path $configDir -ChildPath 'dotnet-tools.json'
            '{}' | Set-Content -LiteralPath $manifestPath

            $result = Update-DotNetTool -Path $script:TestDir

            $result.Scope | Should -Be 'Local'
            $result.ManifestPath | Should -Be $manifestPath
            $result.ToolsFound | Should -Be 1
            $result.Updated | Should -Be 1

            $listCall = $script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'list' } | Select-Object -First 1
            $updateCall = $script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'update' } | Select-Object -First 1

            $listCall | Should -Contain '--local'
            $updateCall | Should -Contain '--local'
            $updateCall | Should -Contain '--tool-manifest'
            $updateCall | Should -Contain $manifestPath
            $updateCall | Should -Not -Contain '--global'
        }

        It 'Finds a local manifest in a parent directory' {
            $configDir = Join-Path -Path $script:TestDir -ChildPath '.config'
            $childDir = Join-Path -Path $script:TestDir -ChildPath 'src'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null
            $manifestPath = Join-Path -Path $configDir -ChildPath 'dotnet-tools.json'
            '{}' | Set-Content -LiteralPath $manifestPath

            $result = Update-DotNetTool -Path $childDir

            $result.Scope | Should -Be 'Local'
            $result.ManifestPath | Should -Be $manifestPath
            $result.WorkingDirectory | Should -Be $childDir
        }

        It 'Updates global tools when no local manifest exists' {
            $result = Update-DotNetTool -Path $script:TestDir

            $result.Scope | Should -Be 'Global'
            $result.ManifestPath | Should -BeNullOrEmpty
            $result.ToolsFound | Should -Be 1
            $result.Updated | Should -Be 1

            $listCall = $script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'list' } | Select-Object -First 1
            $updateCall = $script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'update' } | Select-Object -First 1

            $listCall | Should -Contain '--global'
            $updateCall | Should -Contain '--global'
            $updateCall | Should -Not -Contain '--local'
        }

        It 'Uses global tools when global scope is explicitly requested and a local manifest exists' {
            $configDir = Join-Path -Path $script:TestDir -ChildPath '.config'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            '{}' | Set-Content -LiteralPath (Join-Path -Path $configDir -ChildPath 'dotnet-tools.json')

            $result = Update-DotNetTool -Path $script:TestDir -Scope Global

            $result.Scope | Should -Be 'Global'
            $result.ManifestPath | Should -BeNullOrEmpty

            $updateCall = $script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'update' } | Select-Object -First 1
            $updateCall | Should -Contain '--global'
            $updateCall | Should -Not -Contain '--local'
        }

        It 'Writes an error when local scope is requested without a local manifest' {
            { Update-DotNetTool -Path $script:TestDir -Scope Local -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Tool listing and updates' {
        It 'Skips update calls when no tools are installed' {
            $script:DotNetListOutput = @('{"version":1,"data":[]}')

            $result = Update-DotNetTool -Path $script:TestDir

            $result.ToolsFound | Should -Be 0
            $result.Updated | Should -Be 0
            $result.Failed | Should -Be 0
            $script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'update' } | Should -BeNullOrEmpty
        }

        It 'Updates every package returned by dotnet tool list' {
            $script:DotNetListOutput = @('{"version":1,"data":[{"packageId":"dotnetsay","version":"2.1.7","commands":["dotnetsay"]},{"packageId":"csharpier","version":"1.2.5","commands":["csharpier"]}]}')

            $result = Update-DotNetTool -Path $script:TestDir

            $result.ToolsFound | Should -Be 2
            $result.Updated | Should -Be 2
            $result.Failed | Should -Be 0

            $updateCalls = @($script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'update' })
            $updateCalls.Count | Should -Be 2
            ($updateCalls | ForEach-Object { $_[2] }) | Should -Contain 'dotnetsay'
            ($updateCalls | ForEach-Object { $_[2] }) | Should -Contain 'csharpier'
        }

        It 'Reports failed updates and continues updating remaining tools' {
            $script:DotNetListOutput = @('{"version":1,"data":[{"packageId":"dotnetsay","version":"2.1.7","commands":["dotnetsay"]},{"packageId":"csharpier","version":"1.2.5","commands":["csharpier"]}]}')
            $script:DotNetUpdateExitCodes = @{
                dotnetsay = 1
                csharpier = 0
            }

            $result = Update-DotNetTool -Path $script:TestDir -WarningAction SilentlyContinue

            $result.ToolsFound | Should -Be 2
            $result.Updated | Should -Be 1
            $result.Failed | Should -Be 1
            $result.ExitCode | Should -Be 1

            ($result.Results | Where-Object { $_.PackageId -eq 'dotnetsay' }).Status | Should -Be 'Failed'
            ($result.Results | Where-Object { $_.PackageId -eq 'csharpier' }).Status | Should -Be 'Success'
        }

        It 'Passes update options through to dotnet' {
            $null = Update-DotNetTool -Path $script:TestDir -Prerelease -Interactive -IgnoreFailedSources -NoHttpCache -DisableParallel -Framework 'net8.0' -AdditionalArgs '--verbosity', 'minimal'

            $updateCall = $script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'update' } | Select-Object -First 1

            $updateCall | Should -Contain '--prerelease'
            $updateCall | Should -Contain '--interactive'
            $updateCall | Should -Contain '--ignore-failed-sources'
            $updateCall | Should -Contain '--no-http-cache'
            $updateCall | Should -Contain '--disable-parallel'
            $updateCall | Should -Contain '--framework'
            $updateCall | Should -Contain 'net8.0'
            $updateCall | Should -Contain '--verbosity'
            $updateCall | Should -Contain 'minimal'
        }

        It 'Falls back to table output when JSON list parsing fails' {
            $script:DotNetListOutput = @(
                'Package Id      Version      Commands'
                '--------------------------------------'
                'dotnetsay       2.1.7        dotnetsay'
            )

            $result = Update-DotNetTool -Path $script:TestDir

            $result.ToolsFound | Should -Be 1
            $result.Results[0].PackageId | Should -Be 'dotnetsay'
        }
    }

    Context 'Outdated display' {
        It 'Displays only outdated global tools without updating them' {
            $script:DotNetListOutput = @('{"version":1,"data":[{"packageId":"dotnetsay","version":"2.1.7","commands":["dotnetsay"]},{"packageId":"csharpier","version":"1.2.5","commands":["csharpier"]}]}')
            $script:DotNetSearchOutputByPackage = @{
                dotnetsay = @(
                    'Package ID      Latest Version      Authors      Downloads      Verified'
                    '------------------------------------------------------------------------'
                    'dotnetsay       2.1.7               Tests        1'
                )
                csharpier = @(
                    'Package ID      Latest Version      Authors      Downloads      Verified'
                    '------------------------------------------------------------------------'
                    'csharpier       1.2.6               Tests        1'
                )
            }

            $result = @(Update-DotNetTool -Path $script:TestDir -Scope Global -ListOutdated)

            $result.Count | Should -Be 1
            $result[0].Scope | Should -Be 'Global'
            $result[0].PackageId | Should -Be 'csharpier'
            $result[0].CurrentVersion | Should -Be '1.2.5'
            $result[0].LatestVersion | Should -Be '1.2.6'
            $script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'update' } | Should -BeNullOrEmpty
        }

        It 'Displays outdated local tools when local scope is explicitly requested' {
            $configDir = Join-Path -Path $script:TestDir -ChildPath '.config'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            $manifestPath = Join-Path -Path $configDir -ChildPath 'dotnet-tools.json'
            '{}' | Set-Content -LiteralPath $manifestPath
            $script:DotNetSearchOutputByPackage = @{
                dotnetsay = @(
                    'Package ID      Latest Version      Authors      Downloads      Verified'
                    '------------------------------------------------------------------------'
                    'dotnetsay       2.1.8               Tests        1'
                )
            }

            $result = @(Update-DotNetTool -Path $script:TestDir -Scope Local -ListOutdated)

            $result.Count | Should -Be 1
            $result[0].Scope | Should -Be 'Local'
            $result[0].ManifestPath | Should -Be $manifestPath
            $result[0].PackageId | Should -Be 'dotnetsay'

            $listCall = $script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'list' } | Select-Object -First 1
            $listCall | Should -Contain '--local'
        }

        It 'Passes prerelease through to dotnet tool search in list-outdated mode' {
            $null = Update-DotNetTool -Path $script:TestDir -Scope Global -ListOutdated -Prerelease

            $searchCall = $script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'search' } | Select-Object -First 1
            $searchCall | Should -Contain '--prerelease'
        }
    }

    Context 'ShouldProcess and validation' {
        It 'Skips update commands when WhatIf is specified' {
            $result = Update-DotNetTool -Path $script:TestDir -WhatIf

            $result.ToolsFound | Should -Be 1
            $result.Updated | Should -Be 0
            $result.Skipped | Should -Be 1
            $result.Results[0].Status | Should -Be 'Skipped'
            $script:DotNetInvocations | Where-Object { $_[0] -eq 'tool' -and $_[1] -eq 'update' } | Should -BeNullOrEmpty
        }

        It 'Writes an error for an invalid path' {
            $missingPath = Join-Path -Path $script:TestDir -ChildPath 'missing'

            { Update-DotNetTool -Path $missingPath -ErrorAction Stop } | Should -Throw
        }
    }
}
