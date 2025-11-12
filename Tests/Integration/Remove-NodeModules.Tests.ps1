BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../Functions/Developer/Remove-NodeModules.ps1"

    # Import test utilities
    . "$PSScriptRoot/../TestCleanupUtilities.ps1"
}

Describe 'Remove-NodeModules Integration Tests' -Tag 'Integration' {
    BeforeAll {
        # Create base test directory
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "node-cleanup-integration-$(Get-Random)"
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

        It 'Should remove node_modules folder from Node.js project' {
            # Create package.json
            '{"name":"test","version":"1.0.0"}' | Set-Content (Join-Path $script:ProjectPath 'package.json')

            # Create node_modules folder with files
            $NodeModulesPath = Join-Path $script:ProjectPath 'node_modules'
            $PackagePath = Join-Path $NodeModulesPath 'some-package'
            New-Item -ItemType Directory -Path $PackagePath -Force | Out-Null
            'module code' | Out-File (Join-Path $PackagePath 'index.js')

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath

            # Verify folder is removed
            Test-Path $NodeModulesPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
            $Result.TotalProjectsFound | Should -Be 1
        }

        It 'Should not remove node_modules without package.json' {
            # Create node_modules folder WITHOUT package.json
            $NodeModulesPath = Join-Path $script:ProjectPath 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null
            'content' | Out-File (Join-Path $NodeModulesPath 'file.txt')

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath

            # Verify folder still exists (no package.json found)
            Test-Path $NodeModulesPath | Should -BeTrue
            $Result.FoldersRemoved | Should -Be 0
            $Result.TotalProjectsFound | Should -Be 0
        }

        It 'Should respect -WhatIf parameter' {
            # Create project with node_modules
            '{"name":"test"}' | Set-Content (Join-Path $script:ProjectPath 'package.json')
            $NodeModulesPath = Join-Path $script:ProjectPath 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null

            # Run with -WhatIf
            $null = Remove-NodeModules -Path $script:ProjectPath -WhatIf

            # Verify folder still exists
            Test-Path $NodeModulesPath | Should -BeTrue
        }

        It 'Should calculate space freed' {
            # Create project
            '{"name":"test"}' | Set-Content (Join-Path $script:ProjectPath 'package.json')

            # Create node_modules with known size
            $NodeModulesPath = Join-Path $script:ProjectPath 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null
            'x' * 2000 | Out-File (Join-Path $NodeModulesPath 'package.js') -NoNewline

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath

            # Verify space calculation
            $Result.TotalSpaceFreed | Should -Not -Match 'Not calculated'
            $Result.TotalSpaceFreed | Should -Not -Be '0 bytes'
        }

        It 'Should skip size calculation with -NoSizeCalculation' {
            # Create project
            '{"name":"test"}' | Set-Content (Join-Path $script:ProjectPath 'package.json')

            # Create node_modules
            $NodeModulesPath = Join-Path $script:ProjectPath 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null
            'content' | Out-File (Join-Path $NodeModulesPath 'index.js')

            # Run cleanup with -NoSizeCalculation
            $Result = Remove-NodeModules -Path $script:ProjectPath -NoSizeCalculation

            # Verify
            $Result.TotalSpaceFreed | Should -Match 'Not calculated'
            $Result.FoldersRemoved | Should -Be 1
        }

        It 'Should handle nested node_modules directories' {
            # Create project
            '{"name":"test"}' | Set-Content (Join-Path $script:ProjectPath 'package.json')

            # Create node_modules with nested packages
            $NodeModulesPath = Join-Path $script:ProjectPath 'node_modules'
            $Package1 = Join-Path $NodeModulesPath 'package1'
            $Package2 = Join-Path $NodeModulesPath 'package2'
            $NestedNodeModules = Join-Path $Package1 'node_modules'
            $NestedPackage = Join-Path $NestedNodeModules 'nested-package'

            New-Item -ItemType Directory -Path $Package1 -Force | Out-Null
            New-Item -ItemType Directory -Path $Package2 -Force | Out-Null
            New-Item -ItemType Directory -Path $NestedPackage -Force | Out-Null
            'code' | Out-File (Join-Path $Package1 'index.js')
            'code' | Out-File (Join-Path $NestedPackage 'index.js')

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath

            # Verify entire node_modules is removed (including nested)
            Test-Path $NodeModulesPath | Should -BeFalse
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
            $Project1 = Join-Path $script:WorkspacePath 'frontend'
            $Project2 = Join-Path $script:WorkspacePath 'backend'
            $Project3 = Join-Path (Join-Path $script:WorkspacePath 'packages') 'shared'

            foreach ($proj in @($Project1, $Project2, $Project3))
            {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                '{"name":"test"}' | Set-Content (Join-Path $proj 'package.json')

                # Create node_modules
                $NodeModulesPath = Join-Path $proj 'node_modules'
                $PackagePath = Join-Path $NodeModulesPath '@types/node'
                New-Item -ItemType Directory -Path $PackagePath -Force | Out-Null
                'typings' | Out-File (Join-Path $PackagePath 'index.d.ts')
            }

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:WorkspacePath

            # Verify all node_modules removed
            Test-Path (Join-Path $Project1 'node_modules') | Should -BeFalse
            Test-Path (Join-Path $Project2 'node_modules') | Should -BeFalse
            Test-Path (Join-Path $Project3 'node_modules') | Should -BeFalse

            $Result.TotalProjectsFound | Should -Be 3
            $Result.FoldersRemoved | Should -Be 3
        }

        It 'Should handle projects without node_modules' {
            # Create projects, only one has node_modules
            $Project1 = Join-Path $script:WorkspacePath 'project1'
            $Project2 = Join-Path $script:WorkspacePath 'project2'

            New-Item -ItemType Directory -Path $Project1 -Force | Out-Null
            New-Item -ItemType Directory -Path $Project2 -Force | Out-Null
            '{"name":"test1"}' | Set-Content (Join-Path $Project1 'package.json')
            '{"name":"test2"}' | Set-Content (Join-Path $Project2 'package.json')

            # Only Project1 has node_modules
            $NodeModulesPath = Join-Path $Project1 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:WorkspacePath

            # Verify
            Test-Path $NodeModulesPath | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 2
            $Result.FoldersRemoved | Should -Be 1
        }

        It 'Should handle monorepo structure' {
            # Create monorepo structure
            $RootPackageJson = Join-Path $script:WorkspacePath 'package.json'
            '{"workspaces":["packages/*"]}' | Set-Content $RootPackageJson

            $RootNodeModules = Join-Path $script:WorkspacePath 'node_modules'
            New-Item -ItemType Directory -Path $RootNodeModules -Force | Out-Null

            $PackagesDir = Join-Path $script:WorkspacePath 'packages'
            $Package1 = Join-Path $PackagesDir 'pkg1'
            $Package2 = Join-Path $PackagesDir 'pkg2'

            foreach ($pkg in @($Package1, $Package2))
            {
                New-Item -ItemType Directory -Path $pkg -Force | Out-Null
                '{"name":"pkg"}' | Set-Content (Join-Path $pkg 'package.json')
                $NodeModules = Join-Path $pkg 'node_modules'
                New-Item -ItemType Directory -Path $NodeModules -Force | Out-Null
            }

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:WorkspacePath

            # Verify all node_modules removed (root + packages)
            Test-Path $RootNodeModules | Should -BeFalse
            Test-Path (Join-Path $Package1 'node_modules') | Should -BeFalse
            Test-Path (Join-Path $Package2 'node_modules') | Should -BeFalse

            $Result.TotalProjectsFound | Should -Be 3
            $Result.FoldersRemoved | Should -Be 3
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
            # Create project in .git directory (should be excluded)
            $GitPath = Join-Path $script:WorkspacePath '.git'
            $GitProject = Join-Path $GitPath 'hooks/project'
            New-Item -ItemType Directory -Path $GitProject -Force | Out-Null
            '{"name":"git-hook"}' | Set-Content (Join-Path $GitProject 'package.json')
            $GitNodeModules = Join-Path $GitProject 'node_modules'
            New-Item -ItemType Directory -Path $GitNodeModules -Force | Out-Null

            # Create normal project
            $NormalProject = Join-Path $script:WorkspacePath 'app'
            New-Item -ItemType Directory -Path $NormalProject -Force | Out-Null
            '{"name":"app"}' | Set-Content (Join-Path $NormalProject 'package.json')
            $NormalNodeModules = Join-Path $NormalProject 'node_modules'
            New-Item -ItemType Directory -Path $NormalNodeModules -Force | Out-Null

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:WorkspacePath

            # Verify .git project was excluded
            Test-Path $GitNodeModules | Should -BeTrue
            Test-Path $NormalNodeModules | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 1
        }

        It 'Should respect custom ExcludeDirectory parameter' {
            # Create project in custom excluded directory
            $VendorPath = Join-Path $script:WorkspacePath 'vendor'
            $VendorProject = Join-Path $VendorPath 'library'
            New-Item -ItemType Directory -Path $VendorProject -Force | Out-Null
            '{"name":"vendor"}' | Set-Content (Join-Path $VendorProject 'package.json')
            $VendorNodeModules = Join-Path $VendorProject 'node_modules'
            New-Item -ItemType Directory -Path $VendorNodeModules -Force | Out-Null

            # Create normal project
            $NormalProject = Join-Path $script:WorkspacePath 'src'
            New-Item -ItemType Directory -Path $NormalProject -Force | Out-Null
            '{"name":"src"}' | Set-Content (Join-Path $NormalProject 'package.json')
            $NormalNodeModules = Join-Path $NormalProject 'node_modules'
            New-Item -ItemType Directory -Path $NormalNodeModules -Force | Out-Null

            # Run cleanup with custom exclusion
            $Result = Remove-NodeModules -Path $script:WorkspacePath -ExcludeDirectory @('.git', 'vendor')

            # Verify vendor was excluded, normal was cleaned
            Test-Path $VendorNodeModules | Should -BeTrue
            Test-Path $NormalNodeModules | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 1
        }

        It 'Should handle multiple excluded directories' {
            # Create projects in various excluded directories
            $Paths = @(
                (Join-Path $script:WorkspacePath '.git/hooks'),
                (Join-Path $script:WorkspacePath 'vendor/lib'),
                (Join-Path $script:WorkspacePath 'archive/old')
            )

            foreach ($path in $Paths)
            {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                '{"name":"excluded"}' | Set-Content (Join-Path $path 'package.json')
                $NodeModules = Join-Path $path 'node_modules'
                New-Item -ItemType Directory -Path $NodeModules -Force | Out-Null
            }

            # Create normal project
            $NormalProject = Join-Path $script:WorkspacePath 'project'
            New-Item -ItemType Directory -Path $NormalProject -Force | Out-Null
            '{"name":"project"}' | Set-Content (Join-Path $NormalProject 'package.json')
            $NormalNodeModules = Join-Path $NormalProject 'node_modules'
            New-Item -ItemType Directory -Path $NormalNodeModules -Force | Out-Null

            # Run cleanup with multiple exclusions
            $Result = Remove-NodeModules -Path $script:WorkspacePath -ExcludeDirectory @('.git', 'vendor', 'archive')

            # Verify all excluded projects still have node_modules
            foreach ($path in $Paths)
            {
                Test-Path (Join-Path $path 'node_modules') | Should -BeTrue
            }

            # Normal project should be cleaned
            Test-Path $NormalNodeModules | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 1
        }
    }

    Context 'Path Resolution' {
        BeforeEach {
            $script:ProjectPath = Join-Path $script:TestRoot "path-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:ProjectPath -Force | Out-Null
            '{"name":"test"}' | Set-Content (Join-Path $script:ProjectPath 'package.json')
            $NodeModulesPath = Join-Path $script:ProjectPath 'node_modules'
            New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null
            'module' | Out-File (Join-Path $NodeModulesPath 'index.js')
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
            $InvalidPath = Join-Path $script:TestRoot 'nonexistent-path'

            { Remove-NodeModules -Path $InvalidPath -ErrorAction Stop } | Should -Throw
        }

        It 'Should handle path that is not a directory' {
            $FilePath = Join-Path $script:TestRoot 'test-file.txt'
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
            $EmptyPath = Join-Path $script:TestRoot "empty-$(Get-Random)"
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
            $script:ProjectPath = Join-Path $script:TestRoot "edge-test-$(Get-Random)"
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
            '{"name":"test"}' | Set-Content (Join-Path $script:ProjectPath 'package.json')

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath

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
            '{"name":"root"}' | Set-Content (Join-Path $script:ProjectPath 'package.json')
            $RootNodeModules = Join-Path $script:ProjectPath 'node_modules'
            New-Item -ItemType Directory -Path $RootNodeModules -Force | Out-Null

            # Create subdirectory with its own package.json
            $SubProject = Join-Path $script:ProjectPath 'tools/builder'
            New-Item -ItemType Directory -Path $SubProject -Force | Out-Null
            '{"name":"builder"}' | Set-Content (Join-Path $SubProject 'package.json')
            $SubNodeModules = Join-Path $SubProject 'node_modules'
            New-Item -ItemType Directory -Path $SubNodeModules -Force | Out-Null

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath

            # Verify both removed
            Test-Path $RootNodeModules | Should -BeFalse
            Test-Path $SubNodeModules | Should -BeFalse
            $Result.TotalProjectsFound | Should -Be 2
            $Result.FoldersRemoved | Should -Be 2
        }

        It 'Should handle large node_modules with many files' {
            # Create package.json
            '{"name":"large-project"}' | Set-Content (Join-Path $script:ProjectPath 'package.json')

            # Create node_modules with multiple packages
            $NodeModulesPath = Join-Path $script:ProjectPath 'node_modules'
            for ($i = 1; $i -le 10; $i++)
            {
                $PackagePath = Join-Path $NodeModulesPath "package$i"
                New-Item -ItemType Directory -Path $PackagePath -Force | Out-Null
                'code' | Out-File (Join-Path $PackagePath 'index.js')
                'readme' | Out-File (Join-Path $PackagePath 'README.md')
            }

            # Run cleanup
            $Result = Remove-NodeModules -Path $script:ProjectPath

            # Verify removed
            Test-Path $NodeModulesPath | Should -BeFalse
            $Result.FoldersRemoved | Should -Be 1
        }
    }
}
