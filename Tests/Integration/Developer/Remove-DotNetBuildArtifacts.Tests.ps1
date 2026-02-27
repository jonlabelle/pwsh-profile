BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function
    . "$PSScriptRoot/../../../Functions/Developer/Remove-DotNetBuildArtifacts.ps1"

    # Import test utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Remove-DotNetBuildArtifacts Integration Tests' -Tag 'Integration' {
    BeforeAll {
        # Create base test directory
        $script:TestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dotnet-cleanup-integration-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:TestRoot)
        {
            Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Single Project Cleanup' {
        BeforeEach {
            # Create a test project directory
            $script:ProjectPath = Join-Path -Path $script:TestRoot -ChildPath "test-project-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:ProjectPath -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:ProjectPath)
            {
                Remove-Item -Path $script:ProjectPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should remove bin and obj folders from C# projects' {
            # Create .csproj file
            '<Project Sdk="Microsoft.NET.Sdk"></Project>' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'TestProject.csproj')

            # Create bin and obj folders with files
            $BinPath = Join-Path -Path $script:ProjectPath -ChildPath 'bin'
            $ObjPath = Join-Path -Path $script:ProjectPath -ChildPath 'obj'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            New-Item -ItemType Directory -Path $ObjPath -Force | Out-Null
            'dll content' | Out-File (Join-Path -Path $BinPath -ChildPath 'output.dll')
            'cache content' | Out-File (Join-Path -Path $ObjPath -ChildPath 'cache.txt')

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath -Recurse

            # Verify folders are removed
            Test-Path $BinPath | Should -BeFalse
            Test-Path $ObjPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 2
            $Result.TotalProjectsFound | Should -Be 1
        }

        It 'Should remove bin and obj folders from VB.NET projects' {
            # Create .vbproj file
            '<Project></Project>' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'TestProject.vbproj')

            # Create bin and obj folders
            $BinPath = Join-Path -Path $script:ProjectPath -ChildPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            'exe content' | Out-File (Join-Path -Path $BinPath -ChildPath 'output.exe')

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath -Recurse

            # Verify
            Test-Path $BinPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
        }

        It 'Should remove bin and obj folders from F# projects' {
            # Create .fsproj file
            '<Project></Project>' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'TestProject.fsproj')

            # Create obj folder
            $ObjPath = Join-Path -Path $script:ProjectPath -ChildPath 'obj'
            New-Item -ItemType Directory -Path $ObjPath -Force | Out-Null
            'cache' | Out-File (Join-Path -Path $ObjPath -ChildPath 'project.assets.json')

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath -Recurse

            # Verify
            Test-Path $ObjPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
        }

        It 'Should remove bin and obj folders from SQL projects' {
            # Create .sqlproj file
            '<Project></Project>' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'Database.sqlproj')

            # Create bin folder
            $BinPath = Join-Path -Path $script:ProjectPath -ChildPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            'dacpac' | Out-File (Join-Path -Path $BinPath -ChildPath 'database.dacpac')

            # Run cleanup (explicit recursion for nested projects)
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath -Recurse

            # Verify
            Test-Path $BinPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
        }

        It 'Should not remove bin/obj folders without project file' {
            # Create bin and obj folders WITHOUT project file
            $BinPath = Join-Path -Path $script:ProjectPath -ChildPath 'bin'
            $ObjPath = Join-Path -Path $script:ProjectPath -ChildPath 'obj'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            New-Item -ItemType Directory -Path $ObjPath -Force | Out-Null

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath

            # Verify folders still exist (no project file found)
            Test-Path $BinPath | Should -BeTrue
            Test-Path $ObjPath | Should -BeTrue
            $Result.FoldersRemoved | Should -Be 0
            $Result.TotalProjectsFound | Should -Be 0
        }

        It 'Should respect -WhatIf parameter' {
            # Create project with artifacts
            '<Project></Project>' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'Test.csproj')
            $BinPath = Join-Path -Path $script:ProjectPath -ChildPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null

            # Run with -WhatIf
            $null = Remove-DotNetBuildArtifacts -Path $script:ProjectPath -WhatIf

            # Verify folder still exists
            Test-Path $BinPath | Should -BeTrue
        }

        It 'Should calculate space freed' {
            # Create project
            '<Project></Project>' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'Test.csproj')

            # Create bin folder with known size
            $BinPath = Join-Path -Path $script:ProjectPath -ChildPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            'x' * 1000 | Out-File (Join-Path -Path $BinPath -ChildPath 'output.dll') -NoNewline

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath

            # Verify space calculation
            $Result.TotalSpaceFreed | Should -Not -Match 'Not calculated'
            $Result.TotalSpaceFreed | Should -Not -Be '0 bytes'
        }

        It 'Should skip size calculation with -NoSizeCalculation' {
            # Create project
            '<Project></Project>' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'Test.csproj')

            # Create bin folder
            $BinPath = Join-Path -Path $script:ProjectPath -ChildPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            'content' | Out-File (Join-Path -Path $BinPath -ChildPath 'output.dll')

            # Run cleanup with -NoSizeCalculation
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath -NoSizeCalculation

            # Verify
            $Result.TotalSpaceFreed | Should -Match 'Not calculated'
            $Result.FoldersRemoved | Should -Be 1
        }
    }

    Context 'Multiple Projects' {
        BeforeEach {
            $script:WorkspacePath = Join-Path -Path $script:TestRoot -ChildPath "workspace-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:WorkspacePath -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:WorkspacePath)
            {
                Remove-Item -Path $script:WorkspacePath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should clean multiple projects recursively' {
            # Create multiple projects
            $Project1 = Join-Path -Path $script:WorkspacePath -ChildPath 'Project1'
            $Project2 = Join-Path -Path $script:WorkspacePath -ChildPath 'Project2'
            $nestedDir = Join-Path -Path $script:WorkspacePath -ChildPath 'nested'
            $Project3 = Join-Path -Path $nestedDir -ChildPath 'Project3'

            foreach ($proj in @($Project1, $Project2, $Project3))
            {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                '<Project></Project>' | Set-Content (Join-Path -Path $proj -ChildPath 'Project.csproj')

                # Create bin and obj folders
                $BinPath = Join-Path -Path $proj -ChildPath 'bin'
                $ObjPath = Join-Path -Path $proj -ChildPath 'obj'
                New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
                New-Item -ItemType Directory -Path $ObjPath -Force | Out-Null
                'artifact' | Out-File (Join-Path -Path $BinPath -ChildPath 'output.dll')
                'cache' | Out-File (Join-Path -Path $ObjPath -ChildPath 'cache.txt')
            }

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath -Recurse

            # Verify all artifacts removed
            Test-Path (Join-Path -Path $Project1 -ChildPath 'bin') | Should -BeFalse
            Test-Path (Join-Path -Path $Project1 -ChildPath 'obj') | Should -BeFalse
            Test-Path (Join-Path -Path $Project2 -ChildPath 'bin') | Should -BeFalse
            Test-Path (Join-Path -Path $Project2 -ChildPath 'obj') | Should -BeFalse
            Test-Path (Join-Path -Path $Project3 -ChildPath 'bin') | Should -BeFalse
            Test-Path (Join-Path -Path $Project3 -ChildPath 'obj') | Should -BeFalse

            $Result.TotalProjectsFound | Should -Be 3
            $Result.FoldersRemoved | Should -Be 6
        }

        It 'Should limit scope without Recurse' {
            $rootProject = Join-Path -Path $script:WorkspacePath -ChildPath 'Api'
            $nestedProject = Join-Path -Path (Join-Path -Path $script:WorkspacePath -ChildPath 'src') -ChildPath 'Worker'

            foreach ($proj in @($rootProject, $nestedProject))
            {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                '<Project></Project>' | Set-Content (Join-Path -Path $proj -ChildPath 'Project.csproj')
                New-Item -ItemType Directory -Path (Join-Path -Path $proj -ChildPath 'bin') -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path -Path $proj -ChildPath 'obj') -Force | Out-Null
            }

            $Result = Remove-DotNetBuildArtifacts -Path $rootProject

            Test-Path (Join-Path -Path $rootProject -ChildPath 'bin') | Should -BeFalse
            Test-Path (Join-Path -Path $rootProject -ChildPath 'obj') | Should -BeFalse
            Test-Path (Join-Path -Path $nestedProject -ChildPath 'bin') | Should -BeTrue
            Test-Path (Join-Path -Path $nestedProject -ChildPath 'obj') | Should -BeTrue
            $Result.FoldersRemoved | Should -Be 2
        }

        It 'Should handle projects with only bin or only obj' {
            # Project with only bin
            $Project1 = Join-Path -Path $script:WorkspacePath -ChildPath 'ProjectBin'
            New-Item -ItemType Directory -Path $Project1 -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path -Path $Project1 -ChildPath 'Test.csproj')
            $BinPath = Join-Path -Path $Project1 -ChildPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null

            # Project with only obj
            $Project2 = Join-Path -Path $script:WorkspacePath -ChildPath 'ProjectObj'
            New-Item -ItemType Directory -Path $Project2 -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path -Path $Project2 -ChildPath 'Test.csproj')
            $ObjPath = Join-Path -Path $Project2 -ChildPath 'obj'
            New-Item -ItemType Directory -Path $ObjPath -Force | Out-Null

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath -Recurse

            # Verify
            Test-Path $BinPath | Should -BeFalse
            Test-Path $ObjPath | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 2
            $Result.FoldersRemoved | Should -Be 2
        }

        It 'Should handle nested bin/obj directories' {
            # Create project
            $ProjectPath = Join-Path -Path $script:WorkspacePath -ChildPath 'Project'
            New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path -Path $ProjectPath -ChildPath 'Test.csproj')

            # Create bin with subdirectories
            $BinPath = Join-Path -Path $ProjectPath -ChildPath 'bin'
            $BinDebug = Join-Path -Path $BinPath -ChildPath 'Debug'
            $BinRelease = Join-Path -Path $BinPath -ChildPath 'Release'
            New-Item -ItemType Directory -Path $BinDebug -Force | Out-Null
            New-Item -ItemType Directory -Path $BinRelease -Force | Out-Null
            'debug.dll' | Out-File (Join-Path -Path $BinDebug -ChildPath 'output.dll')
            'release.dll' | Out-File (Join-Path -Path $BinRelease -ChildPath 'output.dll')

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath -Recurse

            # Verify entire bin directory is removed
            Test-Path $BinPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
        }
    }

    Context 'ExcludeDirectory Parameter' {
        BeforeEach {
            $script:WorkspacePath = Join-Path -Path $script:TestRoot -ChildPath "exclude-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:WorkspacePath -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:WorkspacePath)
            {
                Remove-Item -Path $script:WorkspacePath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should exclude .git directories by default' {
            # Create project in .git directory (should be excluded by default)
            $GitPath = Join-Path -Path $script:WorkspacePath -ChildPath '.git'
            $GitProject = Join-Path -Path $GitPath -ChildPath 'hooks/project'
            New-Item -ItemType Directory -Path $GitProject -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path -Path $GitProject -ChildPath 'Test.csproj')
            $BinPath = Join-Path -Path $GitProject -ChildPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null

            # Create normal project
            $NormalProject = Join-Path -Path $script:WorkspacePath -ChildPath 'NormalProject'
            New-Item -ItemType Directory -Path $NormalProject -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path -Path $NormalProject -ChildPath 'Test.csproj')
            $NormalBin = Join-Path -Path $NormalProject -ChildPath 'bin'
            New-Item -ItemType Directory -Path $NormalBin -Force | Out-Null

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath -Recurse

            # Verify .git project was excluded
            Test-Path $BinPath | Should -BeTrue
            Test-Path $NormalBin | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 1
        }

        It 'Should exclude node_modules directories by default' {
            # Create project in node_modules (should be excluded)
            $NodeModulesPath = Join-Path -Path $script:WorkspacePath -ChildPath 'node_modules'
            $NodeProject = Join-Path -Path $NodeModulesPath -ChildPath 'some-package'
            New-Item -ItemType Directory -Path $NodeProject -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path -Path $NodeProject -ChildPath 'Test.csproj')
            $BinPath = Join-Path -Path $NodeProject -ChildPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath

            # Verify node_modules project was excluded
            Test-Path $BinPath | Should -BeTrue
            $Result.TotalProjectsFound | Should -Be 0
        }

        It 'Should respect custom ExcludeDirectory parameter' {
            # Create project in custom excluded directory
            $VendorPath = Join-Path -Path $script:WorkspacePath -ChildPath 'vendor'
            $VendorProject = Join-Path -Path $VendorPath -ChildPath 'library'
            New-Item -ItemType Directory -Path $VendorProject -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path -Path $VendorProject -ChildPath 'Test.csproj')
            $VendorBin = Join-Path -Path $VendorProject -ChildPath 'bin'
            New-Item -ItemType Directory -Path $VendorBin -Force | Out-Null

            # Create normal project
            $NormalProject = Join-Path -Path $script:WorkspacePath -ChildPath 'Project'
            New-Item -ItemType Directory -Path $NormalProject -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path -Path $NormalProject -ChildPath 'Test.csproj')
            $NormalBin = Join-Path -Path $NormalProject -ChildPath 'bin'
            New-Item -ItemType Directory -Path $NormalBin -Force | Out-Null

            # Run cleanup with custom exclusion
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath -ExcludeDirectory @('.git', 'node_modules', 'vendor') -Recurse

            # Verify vendor was excluded, normal was cleaned
            Test-Path $VendorBin | Should -BeTrue
            Test-Path $NormalBin | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 1
        }
    }

    Context 'Path Resolution' {
        BeforeEach {
            $script:ProjectPath = Join-Path -Path $script:TestRoot -ChildPath "path-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:ProjectPath -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'Test.csproj')
            $BinPath = Join-Path -Path $script:ProjectPath -ChildPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            'artifact' | Out-File (Join-Path -Path $BinPath -ChildPath 'output.dll')
        }

        AfterEach {
            if (Test-Path $script:ProjectPath)
            {
                Remove-Item -Path $script:ProjectPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should resolve relative paths' {
            Push-Location (Split-Path $script:ProjectPath -Parent)
            try
            {
                $RelativePath = Split-Path $script:ProjectPath -Leaf
                $Result = Remove-DotNetBuildArtifacts -Path $RelativePath

                $Result.FoldersRemoved | Should -Be 1
            }
            finally
            {
                Pop-Location
            }
        }

        It 'Should handle current directory (default path)' {
            Push-Location $script:ProjectPath
            try
            {
                $Result = Remove-DotNetBuildArtifacts

                $Result.FoldersRemoved | Should -Be 1
            }
            finally
            {
                Pop-Location
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle invalid path' {
            $InvalidPath = Join-Path -Path $script:TestRoot -ChildPath 'nonexistent-path'

            { Remove-DotNetBuildArtifacts -Path $InvalidPath -ErrorAction Stop } | Should -Throw
        }

        It 'Should handle path that is not a directory' {
            $FilePath = Join-Path -Path $script:TestRoot -ChildPath 'test-file.txt'
            'content' | Out-File $FilePath

            try
            {
                { Remove-DotNetBuildArtifacts -Path $FilePath -ErrorAction Stop } | Should -Throw
            }
            finally
            {
                Remove-Item $FilePath -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should return error count in result' {
            $EmptyPath = Join-Path -Path $script:TestRoot -ChildPath "empty-$(Get-Random)"
            New-Item -ItemType Directory -Path $EmptyPath -Force | Out-Null

            try
            {
                $Result = Remove-DotNetBuildArtifacts -Path $EmptyPath

                $Result.PSObject.Properties.Name | Should -Contain 'Errors'
                $Result.Errors | Should -BeOfType [int]
            }
            finally
            {
                Remove-Item $EmptyPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Edge Cases' {
        BeforeEach {
            $script:ProjectPath = Join-Path -Path $script:TestRoot -ChildPath "edge-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:ProjectPath -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:ProjectPath)
            {
                Remove-Item -Path $script:ProjectPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should handle project with no artifacts' {
            # Create project without bin/obj
            '<Project></Project>' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'Test.csproj')

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath

            # Should complete successfully
            $Result.TotalProjectsFound | Should -Be 1
            $Result.FoldersRemoved | Should -Be 0
            $Result.Errors | Should -Be 0
        }

        It 'Should handle empty directory' {
            # Run on empty directory
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath

            # Should complete without errors
            $Result.TotalProjectsFound | Should -Be 0
            $Result.FoldersRemoved | Should -Be 0
            $Result.Errors | Should -Be 0
        }

        It 'Should handle mixed project types' {
            # Create C# project
            '<Project></Project>' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'CSharp.csproj')
            $BinPath1 = Join-Path -Path $script:ProjectPath -ChildPath 'bin'
            New-Item -ItemType Directory -Path $BinPath1 -Force | Out-Null

            # Create F# project in subdirectory
            $SubDir = Join-Path -Path $script:ProjectPath -ChildPath 'FSharpProject'
            New-Item -ItemType Directory -Path $SubDir -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path -Path $SubDir -ChildPath 'FSharp.fsproj')
            $ObjPath = Join-Path -Path $SubDir -ChildPath 'obj'
            New-Item -ItemType Directory -Path $ObjPath -Force | Out-Null

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath -Recurse

            # Verify both projects cleaned
            Test-Path $BinPath1 | Should -BeFalse
            Test-Path $ObjPath | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 2
            $Result.FoldersRemoved | Should -Be 2
        }
    }
}
