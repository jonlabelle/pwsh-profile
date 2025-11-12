BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../Functions/Developer/Remove-DotNetBuildArtifacts.ps1"

    # Import test utilities
    . "$PSScriptRoot/../TestCleanupUtilities.ps1"
}

Describe 'Remove-DotNetBuildArtifacts Integration Tests' -Tag 'Integration' {
    BeforeAll {
        # Create base test directory
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dotnet-cleanup-integration-$(Get-Random)"
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
            $script:ProjectPath = Join-Path $script:TestRoot "test-project-$(Get-Random)"
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
            '<Project Sdk="Microsoft.NET.Sdk"></Project>' | Set-Content (Join-Path $script:ProjectPath 'TestProject.csproj')

            # Create bin and obj folders with files
            $BinPath = Join-Path $script:ProjectPath 'bin'
            $ObjPath = Join-Path $script:ProjectPath 'obj'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            New-Item -ItemType Directory -Path $ObjPath -Force | Out-Null
            'dll content' | Out-File (Join-Path $BinPath 'output.dll')
            'cache content' | Out-File (Join-Path $ObjPath 'cache.txt')

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath

            # Verify folders are removed
            Test-Path $BinPath | Should -BeFalse
            Test-Path $ObjPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 2
            $Result.TotalProjectsFound | Should -Be 1
        }

        It 'Should remove bin and obj folders from VB.NET projects' {
            # Create .vbproj file
            '<Project></Project>' | Set-Content (Join-Path $script:ProjectPath 'TestProject.vbproj')

            # Create bin and obj folders
            $BinPath = Join-Path $script:ProjectPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            'exe content' | Out-File (Join-Path $BinPath 'output.exe')

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath

            # Verify
            Test-Path $BinPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
        }

        It 'Should remove bin and obj folders from F# projects' {
            # Create .fsproj file
            '<Project></Project>' | Set-Content (Join-Path $script:ProjectPath 'TestProject.fsproj')

            # Create obj folder
            $ObjPath = Join-Path $script:ProjectPath 'obj'
            New-Item -ItemType Directory -Path $ObjPath -Force | Out-Null
            'cache' | Out-File (Join-Path $ObjPath 'project.assets.json')

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath

            # Verify
            Test-Path $ObjPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
        }

        It 'Should remove bin and obj folders from SQL projects' {
            # Create .sqlproj file
            '<Project></Project>' | Set-Content (Join-Path $script:ProjectPath 'Database.sqlproj')

            # Create bin folder
            $BinPath = Join-Path $script:ProjectPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            'dacpac' | Out-File (Join-Path $BinPath 'database.dacpac')

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath

            # Verify
            Test-Path $BinPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
        }

        It 'Should not remove bin/obj folders without project file' {
            # Create bin and obj folders WITHOUT project file
            $BinPath = Join-Path $script:ProjectPath 'bin'
            $ObjPath = Join-Path $script:ProjectPath 'obj'
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
            '<Project></Project>' | Set-Content (Join-Path $script:ProjectPath 'Test.csproj')
            $BinPath = Join-Path $script:ProjectPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null

            # Run with -WhatIf
            $null = Remove-DotNetBuildArtifacts -Path $script:ProjectPath -WhatIf

            # Verify folder still exists
            Test-Path $BinPath | Should -BeTrue
        }

        It 'Should calculate space freed' {
            # Create project
            '<Project></Project>' | Set-Content (Join-Path $script:ProjectPath 'Test.csproj')

            # Create bin folder with known size
            $BinPath = Join-Path $script:ProjectPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            'x' * 1000 | Out-File (Join-Path $BinPath 'output.dll') -NoNewline

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath

            # Verify space calculation
            $Result.TotalSpaceFreed | Should -Not -Match 'Not calculated'
            $Result.TotalSpaceFreed | Should -Not -Be '0 bytes'
        }

        It 'Should skip size calculation with -NoSizeCalculation' {
            # Create project
            '<Project></Project>' | Set-Content (Join-Path $script:ProjectPath 'Test.csproj')

            # Create bin folder
            $BinPath = Join-Path $script:ProjectPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            'content' | Out-File (Join-Path $BinPath 'output.dll')

            # Run cleanup with -NoSizeCalculation
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath -NoSizeCalculation

            # Verify
            $Result.TotalSpaceFreed | Should -Match 'Not calculated'
            $Result.FoldersRemoved | Should -Be 1
        }
    }

    Context 'Multiple Projects' {
        BeforeEach {
            $script:WorkspacePath = Join-Path $script:TestRoot "workspace-$(Get-Random)"
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
            $Project1 = Join-Path $script:WorkspacePath 'Project1'
            $Project2 = Join-Path $script:WorkspacePath 'Project2'
            $Project3 = Join-Path (Join-Path $script:WorkspacePath 'nested') 'Project3'

            foreach ($proj in @($Project1, $Project2, $Project3))
            {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                '<Project></Project>' | Set-Content (Join-Path $proj 'Project.csproj')

                # Create bin and obj folders
                $BinPath = Join-Path $proj 'bin'
                $ObjPath = Join-Path $proj 'obj'
                New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
                New-Item -ItemType Directory -Path $ObjPath -Force | Out-Null
                'artifact' | Out-File (Join-Path $BinPath 'output.dll')
                'cache' | Out-File (Join-Path $ObjPath 'cache.txt')
            }

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath

            # Verify all artifacts removed
            Test-Path (Join-Path $Project1 'bin') | Should -BeFalse
            Test-Path (Join-Path $Project1 'obj') | Should -BeFalse
            Test-Path (Join-Path $Project2 'bin') | Should -BeFalse
            Test-Path (Join-Path $Project2 'obj') | Should -BeFalse
            Test-Path (Join-Path $Project3 'bin') | Should -BeFalse
            Test-Path (Join-Path $Project3 'obj') | Should -BeFalse

            $Result.TotalProjectsFound | Should -Be 3
            $Result.FoldersRemoved | Should -Be 6
        }

        It 'Should handle projects with only bin or only obj' {
            # Project with only bin
            $Project1 = Join-Path $script:WorkspacePath 'ProjectBin'
            New-Item -ItemType Directory -Path $Project1 -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path $Project1 'Test.csproj')
            $BinPath = Join-Path $Project1 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null

            # Project with only obj
            $Project2 = Join-Path $script:WorkspacePath 'ProjectObj'
            New-Item -ItemType Directory -Path $Project2 -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path $Project2 'Test.csproj')
            $ObjPath = Join-Path $Project2 'obj'
            New-Item -ItemType Directory -Path $ObjPath -Force | Out-Null

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath

            # Verify
            Test-Path $BinPath | Should -BeFalse
            Test-Path $ObjPath | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 2
            $Result.FoldersRemoved | Should -Be 2
        }

        It 'Should handle nested bin/obj directories' {
            # Create project
            $ProjectPath = Join-Path $script:WorkspacePath 'Project'
            New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path $ProjectPath 'Test.csproj')

            # Create bin with subdirectories
            $BinPath = Join-Path $ProjectPath 'bin'
            $BinDebug = Join-Path $BinPath 'Debug'
            $BinRelease = Join-Path $BinPath 'Release'
            New-Item -ItemType Directory -Path $BinDebug -Force | Out-Null
            New-Item -ItemType Directory -Path $BinRelease -Force | Out-Null
            'debug.dll' | Out-File (Join-Path $BinDebug 'output.dll')
            'release.dll' | Out-File (Join-Path $BinRelease 'output.dll')

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath

            # Verify entire bin directory is removed
            Test-Path $BinPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
        }
    }

    Context 'ExcludeDirectory Parameter' {
        BeforeEach {
            $script:WorkspacePath = Join-Path $script:TestRoot "exclude-test-$(Get-Random)"
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
            $GitPath = Join-Path $script:WorkspacePath '.git'
            $GitProject = Join-Path $GitPath 'hooks/project'
            New-Item -ItemType Directory -Path $GitProject -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path $GitProject 'Test.csproj')
            $BinPath = Join-Path $GitProject 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null

            # Create normal project
            $NormalProject = Join-Path $script:WorkspacePath 'NormalProject'
            New-Item -ItemType Directory -Path $NormalProject -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path $NormalProject 'Test.csproj')
            $NormalBin = Join-Path $NormalProject 'bin'
            New-Item -ItemType Directory -Path $NormalBin -Force | Out-Null

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath

            # Verify .git project was excluded
            Test-Path $BinPath | Should -BeTrue
            Test-Path $NormalBin | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 1
        }

        It 'Should exclude node_modules directories by default' {
            # Create project in node_modules (should be excluded)
            $NodeModulesPath = Join-Path $script:WorkspacePath 'node_modules'
            $NodeProject = Join-Path $NodeModulesPath 'some-package'
            New-Item -ItemType Directory -Path $NodeProject -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path $NodeProject 'Test.csproj')
            $BinPath = Join-Path $NodeProject 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath

            # Verify node_modules project was excluded
            Test-Path $BinPath | Should -BeTrue
            $Result.TotalProjectsFound | Should -Be 0
        }

        It 'Should respect custom ExcludeDirectory parameter' {
            # Create project in custom excluded directory
            $VendorPath = Join-Path $script:WorkspacePath 'vendor'
            $VendorProject = Join-Path $VendorPath 'library'
            New-Item -ItemType Directory -Path $VendorProject -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path $VendorProject 'Test.csproj')
            $VendorBin = Join-Path $VendorProject 'bin'
            New-Item -ItemType Directory -Path $VendorBin -Force | Out-Null

            # Create normal project
            $NormalProject = Join-Path $script:WorkspacePath 'Project'
            New-Item -ItemType Directory -Path $NormalProject -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path $NormalProject 'Test.csproj')
            $NormalBin = Join-Path $NormalProject 'bin'
            New-Item -ItemType Directory -Path $NormalBin -Force | Out-Null

            # Run cleanup with custom exclusion
            $Result = Remove-DotNetBuildArtifacts -Path $script:WorkspacePath -ExcludeDirectory @('.git', 'node_modules', 'vendor')

            # Verify vendor was excluded, normal was cleaned
            Test-Path $VendorBin | Should -BeTrue
            Test-Path $NormalBin | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 1
        }
    }

    Context 'Path Resolution' {
        BeforeEach {
            $script:ProjectPath = Join-Path $script:TestRoot "path-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:ProjectPath -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path $script:ProjectPath 'Test.csproj')
            $BinPath = Join-Path $script:ProjectPath 'bin'
            New-Item -ItemType Directory -Path $BinPath -Force | Out-Null
            'artifact' | Out-File (Join-Path $BinPath 'output.dll')
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
            $InvalidPath = Join-Path $script:TestRoot 'nonexistent-path'

            { Remove-DotNetBuildArtifacts -Path $InvalidPath -ErrorAction Stop } | Should -Throw
        }

        It 'Should handle path that is not a directory' {
            $FilePath = Join-Path $script:TestRoot 'test-file.txt'
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
            $EmptyPath = Join-Path $script:TestRoot "empty-$(Get-Random)"
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
            $script:ProjectPath = Join-Path $script:TestRoot "edge-test-$(Get-Random)"
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
            '<Project></Project>' | Set-Content (Join-Path $script:ProjectPath 'Test.csproj')

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
            '<Project></Project>' | Set-Content (Join-Path $script:ProjectPath 'CSharp.csproj')
            $BinPath1 = Join-Path $script:ProjectPath 'bin'
            New-Item -ItemType Directory -Path $BinPath1 -Force | Out-Null

            # Create F# project in subdirectory
            $SubDir = Join-Path $script:ProjectPath 'FSharpProject'
            New-Item -ItemType Directory -Path $SubDir -Force | Out-Null
            '<Project></Project>' | Set-Content (Join-Path $SubDir 'FSharp.fsproj')
            $ObjPath = Join-Path $SubDir 'obj'
            New-Item -ItemType Directory -Path $ObjPath -Force | Out-Null

            # Run cleanup
            $Result = Remove-DotNetBuildArtifacts -Path $script:ProjectPath

            # Verify both projects cleaned
            Test-Path $BinPath1 | Should -BeFalse
            Test-Path $ObjPath | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 2
            $Result.FoldersRemoved | Should -Be 2
        }
    }
}
