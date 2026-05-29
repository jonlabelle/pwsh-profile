#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Remove-PythonArtifact.

.DESCRIPTION
    Validates Python artifact cleanup logic including directory and file removal,
    recursion behavior, -WhatIf safety, exclusion filtering, and return value shape.
#>

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    # Load the function under test
    . "$PSScriptRoot/../../../Functions/Developer/Remove-PythonArtifact.ps1"
}

Describe 'Remove-PythonArtifact' {
    BeforeEach {
        $script:TestRoot = [System.IO.Path]::Combine(
            [System.IO.Path]::GetTempPath(),
            'Remove-PythonArtifact-Tests',
            [System.IO.Path]::GetRandomFileName()
        )
        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -Path $script:TestRoot)
        {
            Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Parameter validation' {
        It 'Should throw when Path is empty' {
            { Remove-PythonArtifact -Path '' } | Should -Throw
        }

        It 'Should write an error for a non-existent path' {
            $err = $null
            Remove-PythonArtifact -Path '/nonexistent/path/xyz123' -ErrorVariable err 2>&1 | Out-Null
            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Artifact directory removal' {
        It 'Should remove __pycache__ directory' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '__pycache__') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
            $result.DirsRemoved | Should -Be 1
        }

        It 'Should remove .pytest_cache directory' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '.pytest_cache') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
            $result.DirsRemoved | Should -Be 1
        }

        It 'Should remove .mypy_cache directory' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '.mypy_cache') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
        }

        It 'Should remove .ruff_cache directory' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '.ruff_cache') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
        }

        It 'Should remove .venv directory' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '.venv') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
        }

        It 'Should remove venv directory' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'venv') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
        }

        It 'Should remove .tox directory' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '.tox') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
        }

        It 'Should remove .nox directory' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '.nox') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
        }

        It 'Should remove htmlcov directory' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'htmlcov') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
        }

        It 'Should remove dist directory' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'dist') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
        }

        It 'Should remove build directory' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'build') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
        }

        It 'Should remove *.egg-info directories' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'mypackage.egg-info') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $dir.FullName | Should -BeFalse
            $result.DirsRemoved | Should -Be 1
        }

        It 'Should remove multiple artifact directories and count them correctly' {
            New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '__pycache__') -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '.pytest_cache') -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '.mypy_cache') -ItemType Directory -Force | Out-Null

            $result = Remove-PythonArtifact -Path $script:TestRoot

            $result.DirsRemoved | Should -Be 3
        }

        It 'Should not remove non-artifact directories' {
            $srcDir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'src') -ItemType Directory -Force

            Remove-PythonArtifact -Path $script:TestRoot | Out-Null

            Test-Path -Path $srcDir.FullName | Should -BeTrue
        }
    }

    Context 'Artifact file removal' {
        It 'Should remove .pyc files' {
            $file = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'module.pyc') -ItemType File -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $file.FullName | Should -BeFalse
            $result.FilesRemoved | Should -Be 1
        }

        It 'Should remove .pyo files' {
            $file = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'module.pyo') -ItemType File -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $file.FullName | Should -BeFalse
        }

        It 'Should remove .coverage file' {
            $file = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '.coverage') -ItemType File -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $file.FullName | Should -BeFalse
        }

        It 'Should remove .coverage.* parallel-mode files' {
            $file = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '.coverage.worker1') -ItemType File -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $file.FullName | Should -BeFalse
        }

        It 'Should remove coverage.xml file' {
            $file = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'coverage.xml') -ItemType File -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $file.FullName | Should -BeFalse
        }

        It 'Should remove .pdm-python file' {
            $file = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '.pdm-python') -ItemType File -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot

            Test-Path -Path $file.FullName | Should -BeFalse
        }

        It 'Should not remove non-artifact Python source files' {
            $file = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'main.py') -ItemType File -Force

            Remove-PythonArtifact -Path $script:TestRoot | Out-Null

            Test-Path -Path $file.FullName | Should -BeTrue
        }

        It 'Should remove both artifact directories and files in the same run' {
            New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '__pycache__') -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'module.pyc') -ItemType File -Force | Out-Null

            $result = Remove-PythonArtifact -Path $script:TestRoot

            $result.DirsRemoved | Should -Be 1
            $result.FilesRemoved | Should -Be 1
        }
    }

    Context 'Recursion behavior' {
        It 'Should not remove nested artifacts without -Recurse' {
            $subDir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'src') -ItemType Directory -Force
            $nestedCache = New-Item -Path (Join-Path -Path $subDir.FullName -ChildPath '__pycache__') -ItemType Directory -Force

            Remove-PythonArtifact -Path $script:TestRoot | Out-Null

            Test-Path -Path $nestedCache.FullName | Should -BeTrue
        }

        It 'Should remove nested artifacts with -Recurse' {
            $subDir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'src') -ItemType Directory -Force
            $nestedCache = New-Item -Path (Join-Path -Path $subDir.FullName -ChildPath '__pycache__') -ItemType Directory -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot -Recurse

            Test-Path -Path $nestedCache.FullName | Should -BeFalse
            $result.DirsRemoved | Should -Be 1
        }

        It 'Should remove nested artifact files with -Recurse' {
            $subDir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'src') -ItemType Directory -Force
            $nestedFile = New-Item -Path (Join-Path -Path $subDir.FullName -ChildPath 'util.pyc') -ItemType File -Force

            $result = Remove-PythonArtifact -Path $script:TestRoot -Recurse

            Test-Path -Path $nestedFile.FullName | Should -BeFalse
            $result.FilesRemoved | Should -Be 1
        }

        It 'Should not recurse into artifact directories' {
            # Create a __pycache__ that itself contains a subdirectory which looks like an artifact.
            # The outer __pycache__ should be removed as one unit; the inner dir must not be counted separately.
            $cacheDir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '__pycache__') -ItemType Directory -Force
            New-Item -Path (Join-Path -Path $cacheDir.FullName -ChildPath '.pytest_cache') -ItemType Directory -Force | Out-Null

            $result = Remove-PythonArtifact -Path $script:TestRoot -Recurse

            Test-Path -Path $cacheDir.FullName | Should -BeFalse
            $result.DirsRemoved | Should -Be 1
        }

        It 'Should preserve non-artifact parent directories when recursing' {
            $subDir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'src') -ItemType Directory -Force
            New-Item -Path (Join-Path -Path $subDir.FullName -ChildPath '__pycache__') -ItemType Directory -Force | Out-Null

            Remove-PythonArtifact -Path $script:TestRoot -Recurse | Out-Null

            Test-Path -Path $subDir.FullName | Should -BeTrue
        }
    }

    Context '-WhatIf behavior' {
        It 'Should not remove directories when -WhatIf is specified' {
            $dir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '__pycache__') -ItemType Directory -Force

            Remove-PythonArtifact -Path $script:TestRoot -WhatIf | Out-Null

            Test-Path -Path $dir.FullName | Should -BeTrue
        }

        It 'Should not remove files when -WhatIf is specified' {
            $file = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'module.pyc') -ItemType File -Force

            Remove-PythonArtifact -Path $script:TestRoot -WhatIf | Out-Null

            Test-Path -Path $file.FullName | Should -BeTrue
        }

        It 'Should report zero removals when -WhatIf is specified' {
            New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath '__pycache__') -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'module.pyc') -ItemType File -Force | Out-Null

            $result = Remove-PythonArtifact -Path $script:TestRoot -WhatIf

            $result.DirsRemoved | Should -Be 0
            $result.FilesRemoved | Should -Be 0
        }
    }

    Context '-ExcludeDirectory behavior' {
        It 'Should not recurse into excluded directories' {
            $vendorDir = New-Item -Path (Join-Path -Path $script:TestRoot -ChildPath 'vendor') -ItemType Directory -Force
            $nestedCache = New-Item -Path (Join-Path -Path $vendorDir.FullName -ChildPath '__pycache__') -ItemType Directory -Force

            Remove-PythonArtifact -Path $script:TestRoot -Recurse -ExcludeDirectory @('vendor') | Out-Null

            Test-Path -Path $nestedCache.FullName | Should -BeTrue
        }
    }

    Context 'Return value' {
        It 'Should return a PSCustomObject with all expected properties' {
            $result = Remove-PythonArtifact -Path $script:TestRoot

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'DirsRemoved'
            $result.PSObject.Properties.Name | Should -Contain 'FilesRemoved'
            $result.PSObject.Properties.Name | Should -Contain 'TotalSpaceFreed'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
        }

        It 'Should report zero removals for a directory with no artifacts' {
            $result = Remove-PythonArtifact -Path $script:TestRoot

            $result.DirsRemoved | Should -Be 0
            $result.FilesRemoved | Should -Be 0
            $result.Errors | Should -Be 0
        }

        It 'Should report TotalSpaceFreed as a string when -NoSizeCalculation is specified' {
            $result = Remove-PythonArtifact -Path $script:TestRoot -NoSizeCalculation

            $result.TotalSpaceFreed | Should -Be 'Not calculated (use without -NoSizeCalculation for details)'
        }

        It 'Should report TotalSpaceFreed as bytes string when no artifacts removed' {
            $result = Remove-PythonArtifact -Path $script:TestRoot

            $result.TotalSpaceFreed | Should -Be '0 bytes'
        }
    }
}
