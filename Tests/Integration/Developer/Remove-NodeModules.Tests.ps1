BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../../Functions/Developer/Remove-NodeModules.ps1"

    # Import test utilities
    . "$PSScriptRoot/../../TestCleanupUtilities.ps1"
}

Describe 'Remove-NodeModules Integration Tests' -Tag 'Integration' {
    BeforeAll {
        # Create base test directory
        $script:TestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "node-cleanup-integration-$(Get-Random)"
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

        It 'Should remove node_modules folder from Node.js project' {
            # Create package.json
            '{"name":"test","version":"1.0.0"}' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'package.json')

            # Create node_modules folder with files
            $NodeModulesPath = Join-Path -Path $script:ProjectPath -ChildPath 'node_modules'
            $PackagePath = Join-Path -Path $NodeModulesPath -ChildPath 'some-package'
            New-Item -ItemType Directory -Path $PackagePath -Force | Out-Null
            'module code' | Out-File (Join-Path -Path $PackagePath -ChildPath 'index.js')

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath -Recurse

            # Verify folder is removed
            Test-Path $NodeModulesPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
            $Result.TotalProjectsFound | Should -Be 1
        }

        It 'Should not remove node_modules without package.json' {
            # Create node_modules folder WITHOUT package.json
            $NodeModulesPath = Join-Path -Path $script:ProjectPath -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null
            'content' | Out-File (Join-Path -Path $NodeModulesPath -ChildPath 'file.txt')

            # Run cleanup (explicit recursion for nested projects)
            $Result = Remove-NodeModules -Path $script:ProjectPath -Recurse

            # Verify folder still exists (no package.json found)
            Test-Path $NodeModulesPath | Should -BeTrue
            $Result.FoldersRemoved | Should -Be 0
            $Result.TotalProjectsFound | Should -Be 0
        }

        It 'Should respect -WhatIf parameter' {
            # Create project with node_modules
            '{"name":"test"}' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'package.json')
            $NodeModulesPath = Join-Path -Path $script:ProjectPath -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null

            # Run with -WhatIf
            $null = Remove-NodeModules -Path $script:ProjectPath -WhatIf

            # Verify folder still exists
            Test-Path $NodeModulesPath | Should -BeTrue
        }

        It 'Should calculate space freed' {
            # Create project
            '{"name":"test"}' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'package.json')

            # Create node_modules with known size
            $NodeModulesPath = Join-Path -Path $script:ProjectPath -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null
            'x' * 2000 | Out-File (Join-Path -Path $NodeModulesPath -ChildPath 'package.js') -NoNewline

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath

            # Verify space calculation
            $Result.TotalSpaceFreed | Should -Not -Match 'Not calculated'
            $Result.TotalSpaceFreed | Should -Not -Be '0 bytes'
        }

        It 'Should skip size calculation with -NoSizeCalculation' {
            # Create project
            '{"name":"test"}' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'package.json')

            # Create node_modules
            $NodeModulesPath = Join-Path -Path $script:ProjectPath -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null
            'content' | Out-File (Join-Path -Path $NodeModulesPath -ChildPath 'index.js')

            # Run cleanup with -NoSizeCalculation
            $Result = Remove-NodeModules -Path $script:ProjectPath -NoSizeCalculation

            # Verify
            $Result.TotalSpaceFreed | Should -Match 'Not calculated'
            $Result.FoldersRemoved | Should -Be 1
        }

        It 'Should handle nested node_modules directories' {
            # Create project
            '{"name":"test"}' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'package.json')

            # Create node_modules with nested packages
            $NodeModulesPath = Join-Path -Path $script:ProjectPath -ChildPath 'node_modules'
            $Package1 = Join-Path -Path $NodeModulesPath -ChildPath 'package1'
            $Package2 = Join-Path -Path $NodeModulesPath -ChildPath 'package2'
            $NestedNodeModules = Join-Path -Path $Package1 -ChildPath 'node_modules'
            $NestedPackage = Join-Path -Path $NestedNodeModules -ChildPath 'nested-package'

            New-Item -ItemType Directory -Path $Package1 -Force | Out-Null
            New-Item -ItemType Directory -Path $Package2 -Force | Out-Null
            New-Item -ItemType Directory -Path $NestedPackage -Force | Out-Null
            'code' | Out-File (Join-Path -Path $Package1 -ChildPath 'index.js')
            'code' | Out-File (Join-Path -Path $NestedPackage -ChildPath 'index.js')

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath

            # Verify entire node_modules is removed (including nested)
            Test-Path $NodeModulesPath | Should -BeFalse
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
            $Project1 = Join-Path -Path $script:WorkspacePath -ChildPath 'frontend'
            $Project2 = Join-Path -Path $script:WorkspacePath -ChildPath 'backend'
            $packagesDir = Join-Path -Path $script:WorkspacePath -ChildPath 'packages'
            $Project3 = Join-Path -Path $packagesDir -ChildPath 'shared'

            foreach ($proj in @($Project1, $Project2, $Project3))
            {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                '{"name":"test"}' | Set-Content (Join-Path -Path $proj -ChildPath 'package.json')

                # Create node_modules
                $NodeModulesPath = Join-Path -Path $proj -ChildPath 'node_modules'
                $PackagePath = Join-Path -Path $NodeModulesPath -ChildPath '@types/node'
                New-Item -ItemType Directory -Path $PackagePath -Force | Out-Null
                'typings' | Out-File (Join-Path -Path $PackagePath -ChildPath 'index.d.ts')
            }

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:WorkspacePath -Recurse

            # Verify all node_modules removed
            Test-Path (Join-Path -Path $Project1 -ChildPath 'node_modules') | Should -BeFalse
            Test-Path (Join-Path -Path $Project2 -ChildPath 'node_modules') | Should -BeFalse
            Test-Path (Join-Path -Path $Project3 -ChildPath 'node_modules') | Should -BeFalse

            $Result.TotalProjectsFound | Should -Be 3
            $Result.FoldersRemoved | Should -Be 3
        }

        It 'Should limit scope without Recurse' {
            $rootProject = Join-Path -Path $script:WorkspacePath -ChildPath 'app'
            $nestedProject = Join-Path -Path (Join-Path -Path $script:WorkspacePath -ChildPath 'packages') -ChildPath 'lib'

            foreach ($proj in @($rootProject, $nestedProject))
            {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                '{"name":"test"}' | Set-Content (Join-Path -Path $proj -ChildPath 'package.json')
                New-Item -ItemType Directory -Path (Join-Path -Path $proj -ChildPath 'node_modules') -Force | Out-Null
            }

            $Result = Remove-NodeModules -Path $rootProject

            Test-Path (Join-Path -Path $rootProject -ChildPath 'node_modules') | Should -BeFalse
            Test-Path (Join-Path -Path $nestedProject -ChildPath 'node_modules') | Should -BeTrue
            $Result.FoldersRemoved | Should -Be 1
        }

        It 'Should handle projects without node_modules' {
            # Create projects, only one has node_modules
            $Project1 = Join-Path -Path $script:WorkspacePath -ChildPath 'project1'
            $Project2 = Join-Path -Path $script:WorkspacePath -ChildPath 'project2'

            New-Item -ItemType Directory -Path $Project1 -Force | Out-Null
            New-Item -ItemType Directory -Path $Project2 -Force | Out-Null
            '{"name":"test1"}' | Set-Content (Join-Path -Path $Project1 -ChildPath 'package.json')
            '{"name":"test2"}' | Set-Content (Join-Path -Path $Project2 -ChildPath 'package.json')

            # Only Project1 has node_modules
            $NodeModulesPath = Join-Path -Path $Project1 -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:WorkspacePath -Recurse

            # Verify
            Test-Path $NodeModulesPath | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 2
            $Result.FoldersRemoved | Should -Be 1
        }

        It 'Should handle monorepo structure' {
            # Create monorepo structure
            $RootPackageJson = Join-Path -Path $script:WorkspacePath -ChildPath 'package.json'
            '{"workspaces":["packages/*"]}' | Set-Content $RootPackageJson

            $RootNodeModules = Join-Path -Path $script:WorkspacePath -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $RootNodeModules -Force | Out-Null

            $PackagesDir = Join-Path -Path $script:WorkspacePath -ChildPath 'packages'
            $Package1 = Join-Path -Path $PackagesDir -ChildPath 'pkg1'
            $Package2 = Join-Path -Path $PackagesDir -ChildPath 'pkg2'

            foreach ($pkg in @($Package1, $Package2))
            {
                New-Item -ItemType Directory -Path $pkg -Force | Out-Null
                '{"name":"pkg"}' | Set-Content (Join-Path -Path $pkg -ChildPath 'package.json')
                $NodeModules = Join-Path -Path $pkg -ChildPath 'node_modules'
                New-Item -ItemType Directory -Path $NodeModules -Force | Out-Null
            }

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:WorkspacePath -Recurse

            # Verify all node_modules removed (root + packages)
            Test-Path $RootNodeModules | Should -BeFalse
            Test-Path (Join-Path -Path $Package1 -ChildPath 'node_modules') | Should -BeFalse
            Test-Path (Join-Path -Path $Package2 -ChildPath 'node_modules') | Should -BeFalse

            $Result.TotalProjectsFound | Should -Be 3
            $Result.FoldersRemoved | Should -Be 3
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
            # Create project in .git directory (should be excluded)
            $GitPath = Join-Path -Path $script:WorkspacePath -ChildPath '.git'
            $GitProject = Join-Path -Path $GitPath -ChildPath 'hooks/project'
            New-Item -ItemType Directory -Path $GitProject -Force | Out-Null
            '{"name":"git-hook"}' | Set-Content (Join-Path -Path $GitProject -ChildPath 'package.json')
            $GitNodeModules = Join-Path -Path $GitProject -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $GitNodeModules -Force | Out-Null

            # Create normal project
            $NormalProject = Join-Path -Path $script:WorkspacePath -ChildPath 'app'
            New-Item -ItemType Directory -Path $NormalProject -Force | Out-Null
            '{"name":"app"}' | Set-Content (Join-Path -Path $NormalProject -ChildPath 'package.json')
            $NormalNodeModules = Join-Path -Path $NormalProject -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $NormalNodeModules -Force | Out-Null

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:WorkspacePath -Recurse

            # Verify .git project was excluded
            Test-Path $GitNodeModules | Should -BeTrue
            Test-Path $NormalNodeModules | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 1
        }

        It 'Should respect custom ExcludeDirectory parameter' {
            # Create project in custom excluded directory
            $VendorPath = Join-Path -Path $script:WorkspacePath -ChildPath 'vendor'
            $VendorProject = Join-Path -Path $VendorPath -ChildPath 'library'
            New-Item -ItemType Directory -Path $VendorProject -Force | Out-Null
            '{"name":"vendor"}' | Set-Content (Join-Path -Path $VendorProject -ChildPath 'package.json')
            $VendorNodeModules = Join-Path -Path $VendorProject -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $VendorNodeModules -Force | Out-Null

            # Create normal project
            $NormalProject = Join-Path -Path $script:WorkspacePath -ChildPath 'src'
            New-Item -ItemType Directory -Path $NormalProject -Force | Out-Null
            '{"name":"src"}' | Set-Content (Join-Path -Path $NormalProject -ChildPath 'package.json')
            $NormalNodeModules = Join-Path -Path $NormalProject -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $NormalNodeModules -Force | Out-Null

            # Run cleanup with custom exclusion
            $Result = Remove-NodeModules -Path $script:WorkspacePath -ExcludeDirectory @('.git', 'vendor') -Recurse

            # Verify vendor was excluded, normal was cleaned
            Test-Path $VendorNodeModules | Should -BeTrue
            Test-Path $NormalNodeModules | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 1
        }

        It 'Should handle multiple excluded directories' {
            # Create projects in various excluded directories
            $Paths = @(
                (Join-Path -Path $script:WorkspacePath -ChildPath '.git/hooks'),
                (Join-Path -Path $script:WorkspacePath -ChildPath 'vendor/lib'),
                (Join-Path -Path $script:WorkspacePath -ChildPath 'archive/old')
            )

            foreach ($path in $Paths)
            {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                '{"name":"excluded"}' | Set-Content (Join-Path -Path $path -ChildPath 'package.json')
                $NodeModules = Join-Path -Path $path -ChildPath 'node_modules'
                New-Item -ItemType Directory -Path $NodeModules -Force | Out-Null
            }

            # Create normal project
            $NormalProject = Join-Path -Path $script:WorkspacePath -ChildPath 'project'
            New-Item -ItemType Directory -Path $NormalProject -Force | Out-Null
            '{"name":"project"}' | Set-Content (Join-Path -Path $NormalProject -ChildPath 'package.json')
            $NormalNodeModules = Join-Path -Path $NormalProject -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $NormalNodeModules -Force | Out-Null

            # Run cleanup with multiple exclusions
            $Result = Remove-NodeModules -Path $script:WorkspacePath -ExcludeDirectory @('.git', 'vendor', 'archive') -Recurse

            # Verify all excluded projects still have node_modules
            foreach ($path in $Paths)
            {
                Test-Path (Join-Path -Path $path -ChildPath 'node_modules') | Should -BeTrue
            }

            # Normal project should be cleaned
            Test-Path $NormalNodeModules | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 1
        }
    }

    Context 'Path Resolution' {
        BeforeEach {
            $script:ProjectPath = Join-Path -Path $script:TestRoot -ChildPath "path-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:ProjectPath -Force | Out-Null
            '{"name":"test"}' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'package.json')
            $NodeModulesPath = Join-Path -Path $script:ProjectPath -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null
            'module' | Out-File (Join-Path -Path $NodeModulesPath -ChildPath 'index.js')
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
                $Result = Remove-NodeModules -Path $RelativePath

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
                $Result = Remove-NodeModules

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

            { Remove-NodeModules -Path $InvalidPath -ErrorAction Stop } | Should -Throw
        }

        It 'Should handle path that is not a directory' {
            $FilePath = Join-Path -Path $script:TestRoot -ChildPath 'test-file.txt'
            'content' | Out-File $FilePath

            try
            {
                { Remove-NodeModules -Path $FilePath -ErrorAction Stop } | Should -Throw
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
                $Result = Remove-NodeModules -Path $EmptyPath

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

        It 'Should handle project with no node_modules' {
            # Create package.json without node_modules
            '{"name":"test"}' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'package.json')

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath -Recurse

            # Should complete successfully
            $Result.TotalProjectsFound | Should -Be 1
            $Result.FoldersRemoved | Should -Be 0
            $Result.Errors | Should -Be 0
        }

        It 'Should handle empty directory' {
            # Run on empty directory
            $Result = Remove-NodeModules -Path $script:ProjectPath

            # Should complete without errors
            $Result.TotalProjectsFound | Should -Be 0
            $Result.FoldersRemoved | Should -Be 0
            $Result.Errors | Should -Be 0
        }

        It 'Should handle package.json in subdirectories' {
            # Create root package.json
            '{"name":"root"}' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'package.json')
            $RootNodeModules = Join-Path -Path $script:ProjectPath -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $RootNodeModules -Force | Out-Null

            # Create subdirectory with its own package.json
            $SubProject = Join-Path -Path $script:ProjectPath -ChildPath 'tools/builder'
            New-Item -ItemType Directory -Path $SubProject -Force | Out-Null
            '{"name":"builder"}' | Set-Content (Join-Path -Path $SubProject -ChildPath 'package.json')
            $SubNodeModules = Join-Path -Path $SubProject -ChildPath 'node_modules'
            New-Item -ItemType Directory -Path $SubNodeModules -Force | Out-Null

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath -Recurse

            # Verify both removed
            Test-Path $RootNodeModules | Should -BeFalse
            Test-Path $SubNodeModules | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 2
            $Result.FoldersRemoved | Should -Be 2
        }

        It 'Should handle large node_modules with many files' {
            # Create package.json
            '{"name":"large-project"}' | Set-Content (Join-Path -Path $script:ProjectPath -ChildPath 'package.json')

            # Create node_modules with multiple packages
            $NodeModulesPath = Join-Path -Path $script:ProjectPath -ChildPath 'node_modules'
            for ($i = 1; $i -le 10; $i++)
            {
                $PackagePath = Join-Path -Path $NodeModulesPath -ChildPath "package$i"
                New-Item -ItemType Directory -Path $PackagePath -Force | Out-Null
                'code' | Out-File (Join-Path -Path $PackagePath -ChildPath 'index.js')
                'readme' | Out-File (Join-Path -Path $PackagePath -ChildPath 'README.md')
            }

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath

            # Verify removed
            Test-Path $NodeModulesPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
        }
    }
}
