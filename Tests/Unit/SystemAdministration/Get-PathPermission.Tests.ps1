#Requires -Modules Pester

$script:IsWindowsTest = if ($PSVersionTable.PSVersion.Major -lt 6)
{
    $true
}
else
{
    $IsWindows
}
$script:IsUnixTest = -not $script:IsWindowsTest
$script:SkipUnixContext = -not $script:IsUnixTest
$script:SkipWindowsContext = -not $script:IsWindowsTest

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Get-PathPermission.ps1"
}

Describe 'Get-PathPermission' {
    BeforeEach {
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "get-pathpermission-tests-$(Get-Random)"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        $script:RegularFile = Join-Path -Path $script:TestDir -ChildPath 'sample.txt'
        $script:LiteralWildcardFile = Join-Path -Path $script:TestDir -ChildPath '[wild].txt'
        $script:WildcardMatchFile1 = Join-Path -Path $script:TestDir -ChildPath 'wild-1.txt'
        $script:WildcardMatchFile2 = Join-Path -Path $script:TestDir -ChildPath 'wild-2.txt'
        $script:SampleDirectory = Join-Path -Path $script:TestDir -ChildPath 'folder'

        Set-Content -LiteralPath $script:RegularFile -Value 'sample content' -NoNewline
        Set-Content -LiteralPath $script:LiteralWildcardFile -Value 'literal wildcard content' -NoNewline
        Set-Content -LiteralPath $script:WildcardMatchFile1 -Value 'wildcard content 1' -NoNewline
        Set-Content -LiteralPath $script:WildcardMatchFile2 -Value 'wildcard content 2' -NoNewline
        New-Item -Path $script:SampleDirectory -ItemType Directory -Force | Out-Null

        if ($script:IsUnixTest)
        {
            chmod 640 $script:RegularFile
            chmod 600 $script:LiteralWildcardFile
            chmod 644 $script:WildcardMatchFile1
            chmod 644 $script:WildcardMatchFile2
            chmod 755 $script:SampleDirectory
        }
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestDir)
        {
            Remove-Item -LiteralPath $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'is available as a function' {
        $command = Get-Command -Name 'Get-PathPermission' -ErrorAction SilentlyContinue
        $command | Should -Not -BeNullOrEmpty
        $command.CommandType | Should -Be 'Function'
    }

    It 'returns permission details for a file path' {
        $result = Get-PathPermission -Path $script:RegularFile

        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'Path'
        $result.PSObject.Properties.Name | Should -Contain 'ItemType'
        $result.PSObject.Properties.Name | Should -Contain 'Permissions'
        $result.PSObject.Properties.Name | Should -Contain 'Octal'
        $result.Path | Should -Be ([System.IO.Path]::GetFullPath($script:RegularFile))
    }

    It 'supports pipeline input for multiple paths' {
        $results = @($script:RegularFile, $script:SampleDirectory) | Get-PathPermission

        @($results).Count | Should -Be 2
        @($results.Path) | Should -Contain ([System.IO.Path]::GetFullPath($script:RegularFile))
        @($results.Path) | Should -Contain ([System.IO.Path]::GetFullPath($script:SampleDirectory))
    }

    It 'supports wildcard expansion with -Path' {
        $wildcardPath = Join-Path -Path $script:TestDir -ChildPath 'wild-*.txt'
        $results = @(Get-PathPermission -Path $wildcardPath)

        $results.Count | Should -Be 2
        @($results.Path) | Should -Contain ([System.IO.Path]::GetFullPath($script:WildcardMatchFile1))
        @($results.Path) | Should -Contain ([System.IO.Path]::GetFullPath($script:WildcardMatchFile2))
    }

    It 'supports literal paths containing wildcard characters' {
        $result = Get-PathPermission -LiteralPath $script:LiteralWildcardFile

        $result | Should -Not -BeNullOrEmpty
        $result.InputPath | Should -Be $script:LiteralWildcardFile
        $result.Path | Should -Be ([System.IO.Path]::GetFullPath($script:LiteralWildcardFile))
    }

    It 'writes an error for missing paths and continues processing' {
        $missingPath = Join-Path -Path $script:TestDir -ChildPath 'does-not-exist.txt'
        $errors = $null
        $results = @($script:RegularFile, $missingPath) | Get-PathPermission -ErrorAction Continue -ErrorVariable errors

        @($results).Count | Should -Be 1
        @($errors).Count | Should -BeGreaterThan 0
        $errors[0].FullyQualifiedErrorId | Should -Match '^PathNotFound'
    }

    It 'writes an error for non-filesystem providers' {
        $errors = $null
        $result = Get-PathPermission -Path 'Variable:\PSVersionTable' -ErrorAction Continue -ErrorVariable errors

        $result | Should -BeNullOrEmpty
        @($errors).Count | Should -BeGreaterThan 0
        $errors[0].FullyQualifiedErrorId | Should -Match '^UnsupportedProvider'
    }

    Context 'Unix-style permission output' -Skip:$script:SkipUnixContext {
        It 'returns symbolic and octal values on Unix platforms' {
            $result = Get-PathPermission -Path $script:RegularFile

            $result.Symbolic | Should -Match '^[-dlcbps][rwxstST-]{9}$'
            $result.Permissions | Should -Match '^[rwxstST-]{9}$'
            $result.Octal | Should -Match '^[0-7]{3}$'
            $result.OctalWithSpecial | Should -Match '^[0-7]{4}$'
            $result.FullOctal | Should -Match '^[0-7]+$'
            $result.Owner | Should -Not -BeNullOrEmpty
            $result.Group | Should -Not -BeNullOrEmpty
        }

        It 'matches octal and split permission segments from filesystem metadata' {
            $item = Get-Item -LiteralPath $script:RegularFile
            $expectedSymbolic = [String]$item.UnixMode
            $expectedPermissions = $expectedSymbolic.Substring(1, 9)
            $expectedOctal = [Convert]::ToString(([Int32]$item.UnixStat.Mode -band 511), 8).PadLeft(3, '0')

            $result = Get-PathPermission -Path $script:RegularFile

            $result.Octal | Should -Be $expectedOctal
            $result.Permissions | Should -Be $expectedPermissions
            $result.OwnerPermissions | Should -Be $expectedPermissions.Substring(0, 3)
            $result.GroupPermissions | Should -Be $expectedPermissions.Substring(3, 3)
            $result.OtherPermissions | Should -Be $expectedPermissions.Substring(6, 3)
        }
    }

    Context 'Windows output' -Skip:$script:SkipWindowsContext {
        It 'returns null octal values and ACL summary on Windows' {
            $result = Get-PathPermission -Path $script:RegularFile

            $result.Octal | Should -BeNullOrEmpty
            $result.OctalWithSpecial | Should -BeNullOrEmpty
            $result.FullOctal | Should -BeNullOrEmpty
            $result.Owner | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'AccessSummary'
        }
    }
}
