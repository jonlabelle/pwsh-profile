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
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Set-PathPermission.ps1"
}

Describe 'Set-PathPermission' {
    BeforeEach {
        $script:TestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "set-pathpermission-tests-$(Get-Random)"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

        $script:RegularFile = Join-Path -Path $script:TestDir -ChildPath 'sample.txt'
        $script:LiteralWildcardFile = Join-Path -Path $script:TestDir -ChildPath '[wild].txt'
        $script:SampleDirectory = Join-Path -Path $script:TestDir -ChildPath 'folder'
        $script:ChildFile = Join-Path -Path $script:SampleDirectory -ChildPath 'child.txt'
        $script:NestedDirectory = Join-Path -Path $script:SampleDirectory -ChildPath 'nested'
        $script:NestedFile = Join-Path -Path $script:NestedDirectory -ChildPath 'deep.txt'

        Set-Content -LiteralPath $script:RegularFile -Value 'sample content' -NoNewline
        Set-Content -LiteralPath $script:LiteralWildcardFile -Value 'literal wildcard content' -NoNewline
        New-Item -Path $script:SampleDirectory -ItemType Directory -Force | Out-Null
        New-Item -Path $script:NestedDirectory -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath $script:ChildFile -Value 'child content' -NoNewline
        Set-Content -LiteralPath $script:NestedFile -Value 'deep content' -NoNewline

        if ($script:IsUnixTest)
        {
            chmod 644 $script:RegularFile
            chmod 600 $script:LiteralWildcardFile
            chmod 755 $script:SampleDirectory
            chmod 644 $script:ChildFile
            chmod 755 $script:NestedDirectory
            chmod 600 $script:NestedFile
        }
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestDir)
        {
            Remove-Item -LiteralPath $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'is available as a function' {
        $command = Get-Command -Name 'Set-PathPermission' -ErrorAction SilentlyContinue
        $command | Should -Not -BeNullOrEmpty
        $command.CommandType | Should -Be 'Function'
    }

    It 'supports ShouldProcess (WhatIf/Confirm)' {
        $command = Get-Command -Name 'Set-PathPermission' -ErrorAction SilentlyContinue
        $command.Parameters.ContainsKey('WhatIf') | Should -Be $true
        $command.Parameters.ContainsKey('Confirm') | Should -Be $true
    }

    It 'exposes portable and advanced permission parameters' {
        $command = Get-Command -Name 'Set-PathPermission' -ErrorAction SilentlyContinue

        $command.Parameters.ContainsKey('OwnerPermission') | Should -Be $true
        $command.Parameters.ContainsKey('GroupPermission') | Should -Be $true
        $command.Parameters.ContainsKey('OtherPermission') | Should -Be $true
        $command.Parameters.ContainsKey('Mode') | Should -Be $true
        $command.Parameters.ContainsKey('Permission') | Should -Be $true
        $command.Parameters.ContainsKey('Rights') | Should -Be $true
        $command.Parameters.ContainsKey('Idempotent') | Should -Be $true
    }

    It 'has a Recurse switch parameter' {
        $command = Get-Command -Name 'Set-PathPermission' -ErrorAction SilentlyContinue
        $command.Parameters['Recurse'].SwitchParameter | Should -BeTrue
    }

    It 'writes an error for missing paths and continues processing' {
        $missingPath = Join-Path -Path $script:TestDir -ChildPath 'does-not-exist.txt'
        $errors = $null

        @($script:RegularFile, $missingPath) | Set-PathPermission -OwnerPermission Read -ErrorAction Continue -ErrorVariable errors

        @($errors).Count | Should -BeGreaterThan 0
        $errors[0].FullyQualifiedErrorId | Should -Match '^PathNotFound'
    }

    It 'writes an error for non-filesystem providers' {
        $errors = $null

        Set-PathPermission -Path 'Variable:\PSVersionTable' -OwnerPermission Read -ErrorAction Continue -ErrorVariable errors

        @($errors).Count | Should -BeGreaterThan 0
        $errors[0].FullyQualifiedErrorId | Should -Match '^UnsupportedProvider'
    }

    It 'rejects None combined with another portable permission' {
        {
            Set-PathPermission -Path $script:RegularFile -OwnerPermission None, Read -ErrorAction Stop
        } | Should -Throw "Permission value 'None' cannot be combined*"
    }

    Context 'Portable Unix permission changes' -Skip:$script:SkipUnixContext {
        It 'applies owner, group, and other permissions using named values' {
            Set-PathPermission -Path $script:RegularFile -OwnerPermission Read, Write -GroupPermission Read -OtherPermission None

            $result = Get-PathPermission -Path $script:RegularFile
            $result.Octal | Should -Be '640'
        }

        It 'preserves unspecified role permissions' {
            Set-PathPermission -Path $script:RegularFile -OwnerPermission Read, Write, Execute

            $result = Get-PathPermission -Path $script:RegularFile
            $result.Octal | Should -Be '744'
        }

        It 'supports literal paths containing wildcard characters with the portable API' {
            Set-PathPermission -LiteralPath $script:LiteralWildcardFile -OwnerPermission Read, Write -GroupPermission Read -OtherPermission None

            $result = Get-PathPermission -LiteralPath $script:LiteralWildcardFile
            $result.Octal | Should -Be '640'
        }

        It 'applies the requested portable permissions recursively' {
            Set-PathPermission -Path $script:SampleDirectory -OwnerPermission Read, Write, Execute -GroupPermission None -OtherPermission None -Recurse

            $results = @(Get-PathPermission -Path $script:SampleDirectory -Recurse)
            $results.Count | Should -Be 4
            @($results.Octal | Select-Object -Unique) | Should -Be @('700')
        }

        It 'does not change permissions when -WhatIf is used with the portable API' {
            $before = Get-PathPermission -Path $script:RegularFile

            Set-PathPermission -Path $script:RegularFile -OwnerPermission Read, Write -GroupPermission Read -OtherPermission None -WhatIf

            $after = Get-PathPermission -Path $script:RegularFile
            $after.Octal | Should -Be $before.Octal
        }

        It 'returns summary objects with -PassThru for the portable API' {
            $result = Set-PathPermission -Path $script:RegularFile -OwnerPermission Read, Write -GroupPermission Read -OtherPermission None -PassThru

            $result.Path | Should -Be ([System.IO.Path]::GetFullPath($script:RegularFile))
            $result.Operation | Should -Be 'SetPortablePermission'
            $result.Applied | Should -BeTrue
            $result.Skipped | Should -BeFalse
            $result.OwnerPermission | Should -Be 'Read, Write'
            $result.GroupPermission | Should -Be 'Read'
            $result.OtherPermission | Should -Be 'None'
            $result.Mode | Should -Be '0640'
            $result.Platform | Should -Be 'Unix'
        }

        It 'skips portable updates that are already compliant when -Idempotent is used' {
            $result = Set-PathPermission -Path $script:RegularFile -OwnerPermission Read, Write -GroupPermission Read -OtherPermission Read -Idempotent -PassThru

            $result.Path | Should -Be ([System.IO.Path]::GetFullPath($script:RegularFile))
            $result.Operation | Should -Be 'SetPortablePermission'
            $result.Applied | Should -BeFalse
            $result.Skipped | Should -BeTrue
            $result.Reason | Should -Be 'AlreadyCompliant'
            $result.Mode | Should -Be '0644'

            (Get-PathPermission -Path $script:RegularFile).Octal | Should -Be '644'
        }

        It 'keeps the raw mode escape hatch available' {
            Set-PathPermission -Path $script:RegularFile -Mode 600

            $result = Get-PathPermission -Path $script:RegularFile
            $result.Octal | Should -Be '600'
        }

        It 'skips raw numeric mode updates that are already compliant when -Idempotent is used' {
            $result = Set-PathPermission -Path $script:RegularFile -Mode 0644 -Idempotent -PassThru

            $result.Operation | Should -Be 'SetMode'
            $result.Applied | Should -BeFalse
            $result.Skipped | Should -BeTrue
            $result.Reason | Should -Be 'AlreadyCompliant'
            $result.Mode | Should -Be '0644'
        }

        It 'rejects symbolic raw modes when -Idempotent is used' {
            {
                Set-PathPermission -Path $script:RegularFile -Mode 'u=rw,go=r' -Idempotent -ErrorAction Stop
            } | Should -Throw '*numeric octal permissions*'
        }
    }

    Context 'Windows ACL changes' -Skip:$script:SkipWindowsContext {
        It 'maps the portable API to owner and everyone ACL rules' {
            Set-PathPermission -Path $script:RegularFile -OwnerPermission Read, Write -OtherPermission Read

            $result = Get-PathPermission -Path $script:RegularFile -IncludeAcl

            @(
                $result.AccessRules | Where-Object {
                    [String]$_.IdentityReference -eq $result.Owner -and
                    [String]$_.AccessControlType -eq 'Allow' -and
                    ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Read) -eq [System.Security.AccessControl.FileSystemRights]::Read -and
                    ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Write) -eq [System.Security.AccessControl.FileSystemRights]::Write
                }
            ).Count | Should -BeGreaterThan 0

            @(
                $result.AccessRules | Where-Object {
                    [String]$_.IdentityReference -eq 'Everyone' -and
                    [String]$_.AccessControlType -eq 'Allow' -and
                    ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Read) -eq [System.Security.AccessControl.FileSystemRights]::Read
                }
            ).Count | Should -BeGreaterThan 0
        }

        It 'returns portable summary objects with -PassThru on Windows' {
            $result = Set-PathPermission -Path $script:RegularFile -OwnerPermission Read, Write -OtherPermission Read -PassThru

            $result.Path | Should -Be ([System.IO.Path]::GetFullPath($script:RegularFile))
            $result.Operation | Should -Be 'SetPortablePermission'
            $result.OwnerPermission | Should -Be 'Read, Write'
            $result.OtherPermission | Should -Be 'Read'
            $result.Platform | Should -Be 'Windows'
        }

        It 'supports named permissions for a specific identity' {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

            $result = Set-PathPermission -Path $script:RegularFile -Identity $currentUser -Permission Read -PassThru

            $result.Operation | Should -Be 'SetPermission'
            $result.Applied | Should -BeTrue
            $result.Skipped | Should -BeFalse
            $result.Identity | Should -Be $currentUser
            $result.Permission | Should -Be 'Read'
            $result.AccessType | Should -Be 'Allow'

            $aclResult = Get-PathPermission -Path $script:RegularFile -IncludeAcl
            @(
                $aclResult.AccessRules | Where-Object {
                    [String]$_.IdentityReference -eq $currentUser -and
                    [String]$_.AccessControlType -eq 'Allow' -and
                    ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Read) -eq [System.Security.AccessControl.FileSystemRights]::Read
                }
            ).Count | Should -BeGreaterThan 0
        }

        It 'skips identity permission updates that are already compliant when -Idempotent is used' {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            Set-PathPermission -Path $script:RegularFile -Identity $currentUser -Permission Read | Out-Null

            $result = Set-PathPermission -Path $script:RegularFile -Identity $currentUser -Permission Read -Idempotent -PassThru

            $result.Operation | Should -Be 'SetPermission'
            $result.Applied | Should -BeFalse
            $result.Skipped | Should -BeTrue
            $result.Reason | Should -Be 'AlreadyCompliant'
            $result.Identity | Should -Be $currentUser
            $result.Permission | Should -Be 'Read'
        }

        It 'keeps the raw rights escape hatch available' {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

            $result = Set-PathPermission -Path $script:RegularFile -Identity $currentUser -Rights Delete -PassThru

            $result.Operation | Should -Be 'SetAccessRule'
            $result.Applied | Should -BeTrue
            $result.Skipped | Should -BeFalse
            $result.Rights | Should -Match 'Delete'

            $aclResult = Get-PathPermission -Path $script:RegularFile -IncludeAcl
            @(
                $aclResult.AccessRules | Where-Object {
                    [String]$_.IdentityReference -eq $currentUser -and
                    [String]$_.AccessControlType -eq 'Allow' -and
                    ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Delete) -eq [System.Security.AccessControl.FileSystemRights]::Delete
                }
            ).Count | Should -BeGreaterThan 0
        }
    }
}
