#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Export-InstalledPlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Get-PlatformPackageDependency.ps1"
}

Describe 'Export-InstalledPlatformPackage' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Clear-Host -MockWith {}
    }

    It 'exports piped package records to inferred JSON' {
        $packages = @(
            [PSCustomObject]@{
                Name = 'git'
                Id = 'git'
                PackageManager = 'brew'
                PackageManagerDisplayName = 'Homebrew'
                Type = 'Formula'
                InstalledVersion = '2.44.0'
                Source = 'homebrew/formula'
                Publisher = 'Homebrew'
                Description = ''
                Notes = ''
            }
            [PSCustomObject]@{
                Name = 'curl'
                Id = 'curl'
                PackageManager = 'brew'
                PackageManagerDisplayName = 'Homebrew'
                Type = 'Formula'
                InstalledVersion = '8.7.1'
                Source = 'homebrew/formula'
                Publisher = 'Homebrew'
                Description = ''
                Notes = ''
            }
        )

        $exportPath = Join-Path -Path $TestDrive -ChildPath 'packages.json'
        $result = @($packages | Export-InstalledPlatformPackage -Path $exportPath)

        $result.Count | Should -Be 1
        $result[0].Format | Should -Be 'JSON'
        $result[0].Count | Should -Be 2
        $exportedPackages = @(Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json)
        $exportedPackages.Count | Should -Be 2
        ($exportedPackages | Where-Object { $_.Name -eq 'git' }).InstalledVersion | Should -Be '2.44.0'
        Assert-MockCalled -CommandName Write-Host -Times 0
    }

    It 'exports CSV with direct dependencies' {
        $package = [PSCustomObject]@{
            Name = 'git'
            Id = 'git'
            PackageManager = 'brew'
            PackageManagerDisplayName = 'Homebrew'
            Type = 'Formula'
            InstalledVersion = '2.44.0'
            Source = 'homebrew/formula'
            Publisher = 'Homebrew'
            Description = ''
            Notes = ''
        }

        Mock -CommandName Get-PlatformPackageDependency -MockWith {
            param(
                [Object[]]$Package,
                [String]$Direction,
                [String]$PackageManager
            )

            [PSCustomObject]@{
                Direction = $Direction
                Relationship = "$($Package[0].Name) -> openssl"
                RelatedPackage = 'openssl'
                DependencyType = 'Dependency'
                Installed = $true
                Notes = ''
            }
        }

        $exportPath = Join-Path -Path $TestDrive -ChildPath 'packages.csv'
        $result = @(Export-InstalledPlatformPackage -Package $package -Path $exportPath -DependencyMode DependsOn)

        $result.Count | Should -Be 1
        $result[0].Format | Should -Be 'CSV'
        $result[0].DependencyMode | Should -Be 'DependsOn'
        $exportedPackages = @(Import-Csv -LiteralPath $exportPath)
        $exportedPackages.Count | Should -Be 1
        $exportedPackages[0].DependsOn | Should -Be 'openssl'
        $exportedPackages[0].RequiredBy | Should -Be ''
        Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'DependsOn' } -Times 1
        Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'RequiredBy' } -Times 0
    }
}
