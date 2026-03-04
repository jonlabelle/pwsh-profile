#Requires -Modules Pester

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    $script:FunctionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../Functions/Developer/Get-DotNetVersion.ps1'

    . $script:FunctionPath
}

Describe 'Get-DotNetVersion' {
    Context 'Parameter and output basics' {
        It 'Supports local invocation with default parameters' {
            $result = Get-DotNetVersion
            $result | Should -Not -BeNullOrEmpty
            $result | ForEach-Object {
                $_.PSObject.Properties.Name | Should -Contain 'ComputerName'
                $_.PSObject.Properties.Name | Should -Contain 'RuntimeType'
                $_.PSObject.Properties.Name | Should -Contain 'Version'
                $_.PSObject.Properties.Name | Should -Contain 'Type'
            }
        }

        It 'Rejects mutually exclusive -FrameworkOnly and -DotNetOnly' {
            { Get-DotNetVersion -FrameworkOnly -DotNetOnly } | Should -Throw
        }

    }

    Context 'Local target detection' {
        It 'Treats loopback addresses as local and does not create a PSSession' {
            Mock New-PSSession {
                throw 'New-PSSession should not be called for local loopback addresses'
            }

            { Get-DotNetVersion -ComputerName '127.0.0.1' -DotNetOnly | Out-Null } | Should -Not -Throw
            { Get-DotNetVersion -ComputerName '::1' -DotNetOnly | Out-Null } | Should -Not -Throw
        }
    }

    Context 'Remote error output filtering' {
        BeforeAll {
            $script:RemoteTestComputerName = "host-$(Get-Random)"
        }

        It 'Returns only .NET error rows with -DotNetOnly' {
            Mock New-PSSession {
                throw 'session failure'
            }

            $result = Get-DotNetVersion -ComputerName $script:RemoteTestComputerName -DotNetOnly -WarningAction SilentlyContinue

            $result | Should -HaveCount 1
            $result[0].RuntimeType | Should -Be '.NET'
            $result[0].Version | Should -Be 'Error'
            $result[0].Error | Should -Match 'session failure'
        }

        It 'Returns only .NET Framework error rows with -FrameworkOnly' {
            Mock New-PSSession {
                throw 'session failure'
            }

            $result = Get-DotNetVersion -ComputerName $script:RemoteTestComputerName -FrameworkOnly -WarningAction SilentlyContinue

            $result | Should -HaveCount 1
            $result[0].RuntimeType | Should -Be '.NET Framework'
            $result[0].Version | Should -Be 'Error'
            $result[0].Error | Should -Match 'session failure'
        }
    }

    Context 'dotnet CLI parsing and version precedence' {
        BeforeEach {
            function Invoke-MockDotNet
            {
                param(
                    [Parameter(ValueFromRemainingArguments = $true)]
                    [string[]]$RemainingArgs
                )

                if ($RemainingArgs[0] -eq '--list-runtimes')
                {
                    $global:LASTEXITCODE = 0
                    return @(
                        'Microsoft.NETCore.App 10.0.0-preview.7.25380.108 [/mock/shared/Microsoft.NETCore.App]',
                        'Microsoft.NETCore.App 10.0.0 [/mock/shared/Microsoft.NETCore.App]',
                        'Microsoft.AspNetCore.App 10.0.0 [/mock/shared/Microsoft.AspNetCore.App]'
                    )
                }

                if ($RemainingArgs[0] -eq '--list-sdks')
                {
                    $global:LASTEXITCODE = 0
                    return @('10.0.100-preview.2.25164.34 [/mock/sdk]')
                }

                $global:LASTEXITCODE = 1
                return @()
            }

            Mock Get-Command {
                [PSCustomObject]@{
                    Source = 'Invoke-MockDotNet'
                }
            } -ParameterFilter { $Name -eq 'dotnet' }
        }

        AfterEach {
            Remove-Item -Path Function:\Invoke-MockDotNet -ErrorAction SilentlyContinue
        }

        It 'Parses prerelease runtime versions and prefers stable as latest' {
            $result = Get-DotNetVersion -ComputerName 'localhost' -DotNetOnly -All
            $netRows = $result | Where-Object { $_.RuntimeType -eq '.NET' }

            $netRows | Should -Not -BeNullOrEmpty
            @($netRows | Where-Object { $_.Version -eq '10.0.0-preview.7.25380.108' }).Count | Should -Be 1
            @($netRows | Where-Object { $_.Version -eq '10.0.0' -and $_.IsLatest }).Count | Should -Be 1
        }

        It 'Includes SDK rows when -All is used without -IncludeSDKs' {
            $result = Get-DotNetVersion -ComputerName 'localhost' -DotNetOnly -All
            $sdkRows = $result | Where-Object { $_.RuntimeType -eq '.NET SDK' -and $_.Type -eq 'SDK' }

            $sdkRows | Should -Not -BeNullOrEmpty
            @($sdkRows | Where-Object { $_.Version -eq '10.0.100-preview.2.25164.34' }).Count | Should -Be 1
        }
    }

    Context 'Directory fallback behavior' {
        It 'Falls back to runtime directory scanning when dotnet command is unavailable' {
            $originalDotnetRoot = $env:DOTNET_ROOT
            $env:DOTNET_ROOT = '/fake/dotnet'
            $script:RuntimeFallbackPath = Join-Path -Path (Join-Path -Path $env:DOTNET_ROOT -ChildPath 'shared') -ChildPath 'Microsoft.NETCore.App'
            $script:RuntimeFallbackVersionPath = Join-Path -Path $script:RuntimeFallbackPath -ChildPath '8.0.14'

            try
            {
                Mock Get-Command { $null } -ParameterFilter { $Name -eq 'dotnet' }

                Mock Test-Path {
                    if ($Path -eq $script:RuntimeFallbackPath) { return $true }
                    return $false
                }

                Mock Get-ChildItem {
                    @(
                        [PSCustomObject]@{
                            Name = '8.0.14'
                            FullName = $script:RuntimeFallbackVersionPath
                        }
                    )
                } -ParameterFilter { $Path -eq $script:RuntimeFallbackPath -and $Directory }

                $result = Get-DotNetVersion -ComputerName 'localhost' -DotNetOnly
                $netRow = $result | Where-Object { $_.RuntimeType -eq '.NET' } | Select-Object -First 1

                $netRow | Should -Not -BeNullOrEmpty
                $netRow.Version | Should -Be '8.0.14'
                $netRow.Type | Should -Be 'Runtime'
            }
            finally
            {
                $env:DOTNET_ROOT = $originalDotnetRoot
                Remove-Variable -Name RuntimeFallbackPath, RuntimeFallbackVersionPath -Scope Script -ErrorAction SilentlyContinue
            }
        }

        It 'Falls back to SDK directory scanning when runtime CLI output exists but SDK CLI output is missing' {
            $originalDotnetRoot = $env:DOTNET_ROOT
            $env:DOTNET_ROOT = '/fake/dotnet'
            $script:SdkFallbackPath = Join-Path -Path $env:DOTNET_ROOT -ChildPath 'sdk'
            $script:SdkFallbackVersionPath = Join-Path -Path $script:SdkFallbackPath -ChildPath '10.0.200'

            try
            {
                function Invoke-MockDotNet
                {
                    param(
                        [Parameter(ValueFromRemainingArguments = $true)]
                        [string[]]$RemainingArgs
                    )

                    if ($RemainingArgs[0] -eq '--list-runtimes')
                    {
                        $global:LASTEXITCODE = 0
                        return @('Microsoft.NETCore.App 10.0.1 [/mock/shared/Microsoft.NETCore.App]')
                    }

                    if ($RemainingArgs[0] -eq '--list-sdks')
                    {
                        $global:LASTEXITCODE = 1
                        return @()
                    }

                    $global:LASTEXITCODE = 1
                    return @()
                }

                Mock Get-Command {
                    [PSCustomObject]@{
                        Source = 'Invoke-MockDotNet'
                    }
                } -ParameterFilter { $Name -eq 'dotnet' }

                Mock Test-Path {
                    if ($Path -eq $script:SdkFallbackPath) { return $true }
                    return $false
                }

                Mock Get-ChildItem {
                    @(
                        [PSCustomObject]@{
                            Name = '10.0.200'
                            FullName = $script:SdkFallbackVersionPath
                        }
                    )
                } -ParameterFilter { $Path -eq $script:SdkFallbackPath -and $Directory }

                $result = Get-DotNetVersion -ComputerName 'localhost' -DotNetOnly -IncludeSDKs
                $sdkRow = $result | Where-Object { $_.RuntimeType -eq '.NET SDK' } | Select-Object -First 1

                $sdkRow | Should -Not -BeNullOrEmpty
                $sdkRow.Version | Should -Be '10.0.200'
                $sdkRow.Type | Should -Be 'SDK'
            }
            finally
            {
                Remove-Item -Path Function:\Invoke-MockDotNet -ErrorAction SilentlyContinue
                $env:DOTNET_ROOT = $originalDotnetRoot
                Remove-Variable -Name SdkFallbackPath, SdkFallbackVersionPath -Scope Script -ErrorAction SilentlyContinue
            }
        }
    }
}
