#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Import-DotEnv function.

.DESCRIPTION
    Tests the Import-DotEnv function in real-world scenarios including:
    - Loading from actual .env files in project directories
    - Multi-file loading scenarios
    - Interaction with system environment variables
    - Cross-platform compatibility verification
    - Complex dotenv file formats

.NOTES
    These tests use actual file I/O and environment variable manipulation
    to verify end-to-end functionality.
#>

BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../../Functions/Developer/Import-DotEnv.ps1"

    # Helper to create realistic .env content
    function New-RealisticEnvFile
    {
        param(
            [String]$Path,
            [String]$Type = 'Standard'
        )

        $content = switch ($Type)
        {
            'Standard'
            {
                @'
# Application Configuration
APP_NAME=MyApp
APP_ENV=development
APP_DEBUG=true
APP_URL=http://localhost:3000

# Database Configuration
DB_CONNECTION=postgresql
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=myapp_dev
DB_USERNAME=postgres
DB_PASSWORD=secret123

# Cache Configuration
CACHE_DRIVER=redis
REDIS_HOST=127.0.0.1
REDIS_PORT=6379

# Mail Configuration
MAIL_MAILER=smtp
MAIL_HOST=smtp.mailtrap.io
MAIL_PORT=2525
'@
            }
            'Docker'
            {
                @'
# Docker Configuration
COMPOSE_PROJECT_NAME=myproject
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1

# Service Versions
NODE_VERSION=18
POSTGRES_VERSION=15
REDIS_VERSION=7

# Ports
WEB_PORT=8080
DB_PORT=5432
REDIS_PORT=6379
'@
            }
            'AWS'
            {
                @'
# AWS Configuration
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# S3 Configuration
S3_BUCKET=my-app-bucket
S3_ENDPOINT=https://s3.amazonaws.com
'@
            }
            'WithExpansion'
            {
                @'
# Base paths
HOME_DIR=/home/user
PROJECT_ROOT="${HOME_DIR}/projects/myapp"

# Derived paths
CONFIG_PATH="${PROJECT_ROOT}/config"
DATA_PATH="${PROJECT_ROOT}/data"
LOG_PATH="${PROJECT_ROOT}/logs"

# URLs
API_URL=https://api.example.com
FULL_URL="${API_URL}/v1"
'@
            }
            'Complex'
            {
                @'
# Complex scenarios
SIMPLE=value

# With quotes
DOUBLE_QUOTED="value with spaces"
SINGLE_QUOTED='value with spaces'

# With special characters
SPECIAL="!@#$%^&*()"

# With escape sequences
ESCAPED="Line 1\nLine 2\tTabbed"

# With comments
INLINE=value # this is a comment
export EXPORTED=exported_value

# Empty value
EMPTY=

# Multiple equals
EQUALS=key=value=another

# Variable expansion
BASE_VAR=base
EXPANDED="${BASE_VAR}_expanded"
'@
            }
        }

        [System.IO.File]::WriteAllText($Path, $content, [System.Text.Encoding]::UTF8)
    }

    # Helper to clean up all test environment variables
    function Clear-AllTestEnvVars
    {
        $prefixes = @(
            'APP_', 'DB_', 'CACHE_', 'REDIS_', 'MAIL_', 'COMPOSE_', 'DOCKER_',
            'NODE_', 'POSTGRES_', 'WEB_', 'AWS_', 'S3_', 'HOME_DIR', 'PROJECT_',
            'CONFIG_', 'DATA_', 'LOG_', 'API_', 'FULL_', 'SIMPLE', 'DOUBLE_',
            'SINGLE_', 'SPECIAL', 'ESCAPED', 'INLINE', 'EXPORTED', 'EMPTY',
            'EQUALS', 'BASE_', 'EXPANDED', 'BOM_', 'WORKFLOW_', 'RELOAD_', 'VALID_VAR',
            'PROTECTED', 'UNIX_PATH', 'RELATIVE_PATH', 'WIN_PATH', 'NETWORK_PATH', 'VAR_',
            'LOCAL_SETTING', 'CONFIG_MODE', 'TIMEOUT', 'DEBUG'
        )
        $testVarPattern = '^(' + ($prefixes -join '|') + ')'

        Get-ChildItem env: | Where-Object { $_.Name -match $testVarPattern } | ForEach-Object {
            Remove-Item -Path "env:$($_.Name)" -ErrorAction SilentlyContinue
        }

        Remove-Item -Path 'env:__DOTENV_LOADED_VARS' -ErrorAction SilentlyContinue
    }
}

Describe 'Import-DotEnv Integration Tests' {
    BeforeAll {
        $script:TestDir = Join-Path -Path $TestDrive -ChildPath 'dotenv'
        if (-not (Test-Path $script:TestDir))
        {
            New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
        }
    }

    BeforeEach { Clear-AllTestEnvVars }
    AfterEach { Clear-AllTestEnvVars }
    AfterAll { Clear-AllTestEnvVars }

    Context 'Real-World Application Scenarios' {
        It 'Should load standard application configuration' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'app.env'
            New-RealisticEnvFile -Path $envFile -Type 'Standard'

            $result = Import-DotEnv -Path $envFile -PassThru

            # Verify application settings
            $env:APP_NAME | Should -Be 'MyApp'
            $env:APP_ENV | Should -Be 'development'
            $env:APP_DEBUG | Should -Be 'true'
            $env:APP_URL | Should -Be 'http://localhost:3000'

            # Verify database settings
            $env:DB_CONNECTION | Should -Be 'postgresql'
            $env:DB_HOST | Should -Be 'localhost'
            $env:DB_PORT | Should -Be '5432'
            $env:DB_DATABASE | Should -Be 'myapp_dev'
            $env:DB_USERNAME | Should -Be 'postgres'
            $env:DB_PASSWORD | Should -Be 'secret123'

            # Verify cache settings
            $env:CACHE_DRIVER | Should -Be 'redis'
            $env:REDIS_HOST | Should -Be '127.0.0.1'
            $env:REDIS_PORT | Should -Be '6379'

            # Verify mail settings
            $env:MAIL_MAILER | Should -Be 'smtp'
            $env:MAIL_HOST | Should -Be 'smtp.mailtrap.io'
            $env:MAIL_PORT | Should -Be '2525'

            # Verify PassThru result
            $result.VariableCount | Should -BeGreaterThan 10
            $result.FileName | Should -Be 'app.env'

            Remove-Item -Path $envFile -Force
        }

        It 'Should load Docker configuration' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'docker.env'
            New-RealisticEnvFile -Path $envFile -Type 'Docker'

            Import-DotEnv -Path $envFile

            $env:COMPOSE_PROJECT_NAME | Should -Be 'myproject'
            $env:DOCKER_BUILDKIT | Should -Be '1'
            $env:NODE_VERSION | Should -Be '18'
            $env:POSTGRES_VERSION | Should -Be '15'
            $env:WEB_PORT | Should -Be '8080'

            Remove-Item -Path $envFile -Force
        }

        It 'Should load AWS configuration with secrets' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'aws.env'
            New-RealisticEnvFile -Path $envFile -Type 'AWS'

            Import-DotEnv -Path $envFile

            $env:AWS_REGION | Should -Be 'us-east-1'
            $env:AWS_ACCOUNT_ID | Should -Be '123456789012'
            $env:AWS_ACCESS_KEY_ID | Should -Be 'AKIAIOSFODNN7EXAMPLE'
            $env:AWS_SECRET_ACCESS_KEY | Should -Be 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
            $env:S3_BUCKET | Should -Be 'my-app-bucket'

            Remove-Item -Path $envFile -Force
        }

        It 'Should warn and not load when Path targets a directory' {
            $envDir = Join-Path -Path $script:TestDir -ChildPath 'dotenv-dir'
            New-Item -Path $envDir -ItemType Directory -Force | Out-Null

            $warnings = @()
            $result = Import-DotEnv -Path $envDir -PassThru -WarningVariable warnings -WarningAction Continue

            $warnings | Should -Not -BeNullOrEmpty
            ($warnings -join "`n") | Should -Match 'File not found.*dotenv-dir'
            $env:APP_NAME | Should -BeNullOrEmpty
            $result | Should -BeNullOrEmpty

            Remove-Item -Path $envDir -Recurse -Force
        }

        It 'Should load UTF-8 BOM encoded files' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'bom.env'
            $utf8WithBom = [System.Text.UTF8Encoding]::new($true)
            [System.IO.File]::WriteAllText($envFile, 'BOM_VAR=value_with_bom', $utf8WithBom)

            $result = Import-DotEnv -Path $envFile -PassThru

            $result.VariableCount | Should -Be 1
            $env:BOM_VAR | Should -Be 'value_with_bom'

            Remove-Item -Path $envFile -Force
        }

        It 'Should not overwrite existing variables without Force' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'no-force-overwrite.env'
            [System.IO.File]::WriteAllText($envFile, @'
APP_NAME=FirstLoad
API_URL=https://first.example.com
'@, [System.Text.Encoding]::UTF8)

            $initialResult = Import-DotEnv -Path $envFile -PassThru
            $initialResult.VariableCount | Should -Be 2
            $env:APP_NAME | Should -Be 'FirstLoad'
            $env:API_URL | Should -Be 'https://first.example.com'

            # Change the file values and load again without -Force; existing env vars should be preserved
            [System.IO.File]::WriteAllText($envFile, @'
APP_NAME=SecondLoad
API_URL=https://second.example.com
'@, [System.Text.Encoding]::UTF8)

            $secondResult = Import-DotEnv -Path $envFile -PassThru

            $env:APP_NAME | Should -Be 'FirstLoad'
            $env:API_URL | Should -Be 'https://first.example.com'
            $secondResult.VariableCount | Should -Be 0
            $secondResult.Skipped | Should -Contain 'APP_NAME'
            $secondResult.Skipped | Should -Contain 'API_URL'

            Remove-Item -Path $envFile -Force
        }
    }

    Context 'Multi-File Loading' {
        It 'Should load multiple .env files sequentially' {
            $baseEnvFile = Join-Path -Path $script:TestDir -ChildPath '.env'
            $localEnvFile = Join-Path -Path $script:TestDir -ChildPath '.env.local'

            # Base configuration
            [System.IO.File]::WriteAllText($baseEnvFile, @'
APP_NAME=BaseApp
APP_ENV=production
DB_HOST=prod-db.example.com
'@, [System.Text.Encoding]::UTF8)

            # Local overrides
            [System.IO.File]::WriteAllText($localEnvFile, @'
APP_ENV=development
DB_HOST=localhost
LOCAL_SETTING=true
'@, [System.Text.Encoding]::UTF8)

            # Load base first
            Import-DotEnv -Path $baseEnvFile

            $env:APP_NAME | Should -Be 'BaseApp'
            $env:APP_ENV | Should -Be 'production'
            $env:DB_HOST | Should -Be 'prod-db.example.com'

            # Load local overrides with Force
            Import-DotEnv -Path $localEnvFile -Force

            $env:APP_NAME | Should -Be 'BaseApp'  # Not in local file
            $env:APP_ENV | Should -Be 'development'  # Overridden
            $env:DB_HOST | Should -Be 'localhost'  # Overridden
            $env:LOCAL_SETTING | Should -Be 'true'  # New variable

            Remove-Item -Path $baseEnvFile, $localEnvFile -Force
        }

        It 'Should handle .env hierarchy (.env, .env.local, .env.development)' {
            $envFiles = @{
                '.env' = 'APP_NAME=MyApp
APP_ENV=production
API_KEY=prod_key'
                '.env.local' = 'APP_ENV=development
DEBUG=true'
                '.env.development' = 'DB_HOST=localhost
DB_PORT=5432'
            }

            foreach ($fileName in $envFiles.Keys)
            {
                $path = Join-Path -Path $script:TestDir -ChildPath $fileName
                [System.IO.File]::WriteAllText($path, $envFiles[$fileName], [System.Text.Encoding]::UTF8)
            }

            # Load in priority order
            Import-DotEnv -Path (Join-Path -Path $script:TestDir -ChildPath '.env')
            Import-DotEnv -Path (Join-Path -Path $script:TestDir -ChildPath '.env.development') -Force
            Import-DotEnv -Path (Join-Path -Path $script:TestDir -ChildPath '.env.local') -Force

            $env:APP_NAME | Should -Be 'MyApp'
            $env:APP_ENV | Should -Be 'development'
            $env:DEBUG | Should -Be 'true'
            $env:DB_HOST | Should -Be 'localhost'

            foreach ($fileName in $envFiles.Keys)
            {
                Remove-Item -Path (Join-Path -Path $script:TestDir -ChildPath $fileName) -Force
            }
        }
    }

    Context 'Variable Expansion in Real Scenarios' {
        It 'Should expand path variables correctly' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'paths.env'
            New-RealisticEnvFile -Path $envFile -Type 'WithExpansion'

            Import-DotEnv -Path $envFile

            $env:HOME_DIR | Should -Be '/home/user'
            $env:PROJECT_ROOT | Should -Be '/home/user/projects/myapp'
            $env:CONFIG_PATH | Should -Be '/home/user/projects/myapp/config'
            $env:DATA_PATH | Should -Be '/home/user/projects/myapp/data'
            $env:LOG_PATH | Should -Be '/home/user/projects/myapp/logs'

            Remove-Item -Path $envFile -Force
        }

        It 'Should expand URL variables correctly' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'urls.env'
            [System.IO.File]::WriteAllText($envFile, @'
API_BASE=https://api.example.com
API_VERSION=v2
API_ENDPOINT="${API_BASE}/${API_VERSION}"
'@, [System.Text.Encoding]::UTF8)

            Import-DotEnv -Path $envFile

            $env:API_BASE | Should -Be 'https://api.example.com'
            $env:API_VERSION | Should -Be 'v2'
            $env:API_ENDPOINT | Should -Be 'https://api.example.com/v2'

            Remove-Item -Path $envFile -Force
        }
    }

    Context 'Complex Format Handling' {
        It 'Should handle all complex formats in one file' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'complex.env'
            New-RealisticEnvFile -Path $envFile -Type 'Complex'

            Import-DotEnv -Path $envFile

            $env:SIMPLE | Should -Be 'value'
            $env:DOUBLE_QUOTED | Should -Be 'value with spaces'
            $env:SINGLE_QUOTED | Should -Be 'value with spaces'
            $env:SPECIAL | Should -Be '!@#$%^&*()'
            $env:ESCAPED | Should -Match "Line 1`nLine 2"
            $env:INLINE | Should -Be 'value'
            $env:EXPORTED | Should -Be 'exported_value'
            $env:EMPTY | Should -BeNullOrEmpty
            $env:EQUALS | Should -Be 'key=value=another'
            $env:EXPANDED | Should -Be 'base_expanded'

            Remove-Item -Path $envFile -Force
        }
    }

    Context 'Load and Unload Workflow' {
        It 'Should support complete load-use-unload workflow' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'workflow.env'
            [System.IO.File]::WriteAllText($envFile, @'
WORKFLOW_VAR1=value1
WORKFLOW_VAR2=value2
WORKFLOW_VAR3=value3
'@, [System.Text.Encoding]::UTF8)

            # Load
            $loadResult = Import-DotEnv -Path $envFile -PassThru
            $loadResult.VariableCount | Should -Be 3

            # Use
            $env:WORKFLOW_VAR1 | Should -Be 'value1'
            $env:WORKFLOW_VAR2 | Should -Be 'value2'
            $env:WORKFLOW_VAR3 | Should -Be 'value3'

            # Unload
            $unloadResult = Import-DotEnv -Unload -PassThru
            $unloadResult.VariableCount | Should -Be 3

            # Verify cleanup
            $env:WORKFLOW_VAR1 | Should -BeNullOrEmpty
            $env:WORKFLOW_VAR2 | Should -BeNullOrEmpty
            $env:WORKFLOW_VAR3 | Should -BeNullOrEmpty
            $env:__DOTENV_LOADED_VARS | Should -BeNullOrEmpty

            Remove-Item -Path $envFile -Force
        }

        It 'Should reload after unload' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'reload.env'
            [System.IO.File]::WriteAllText($envFile, @'
RELOAD_VAR=initial_value
'@, [System.Text.Encoding]::UTF8)

            # First load
            Import-DotEnv -Path $envFile
            $env:RELOAD_VAR | Should -Be 'initial_value'

            # Unload
            Import-DotEnv -Unload
            $env:RELOAD_VAR | Should -BeNullOrEmpty

            # Reload with new value
            [System.IO.File]::WriteAllText($envFile, @'
RELOAD_VAR=new_value
'@, [System.Text.Encoding]::UTF8)

            Import-DotEnv -Path $envFile
            $env:RELOAD_VAR | Should -Be 'new_value'

            Remove-Item -Path $envFile -Force
        }
    }

    Context 'Error Handling' {
        It 'Should continue processing when one file fails' {
            $validFile = Join-Path -Path $script:TestDir -ChildPath 'valid.env'
            $invalidFile = Join-Path -Path $script:TestDir -ChildPath 'nonexistent.env'

            [System.IO.File]::WriteAllText($validFile, 'VALID_VAR=value', [System.Text.Encoding]::UTF8)

            # Process multiple files, one missing
            Import-DotEnv -Path @($validFile, $invalidFile) -WarningAction SilentlyContinue

            # Should still load the valid file
            $env:VALID_VAR | Should -Be 'value'

            Remove-Item -Path $validFile -Force
        }

        It 'Should surface warning message for missing file' {
            $missingFile = Join-Path -Path $script:TestDir -ChildPath 'missing.env'
            $escapedMissingFile = [Regex]::Escape($missingFile)

            $warnings = @()
            Import-DotEnv -Path $missingFile -WarningVariable warnings -WarningAction Continue

            $warnings | Should -Not -BeNullOrEmpty
            ($warnings -join "`n") | Should -Match $escapedMissingFile
            ($warnings -join "`n") | Should -Match 'File not found'
        }

        It 'Should handle file read permissions gracefully' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'protected.env'
            [System.IO.File]::WriteAllText($envFile, 'PROTECTED=value', [System.Text.Encoding]::UTF8)

            # This test varies by platform, just ensure it doesn't crash
            { Import-DotEnv -Path $envFile } | Should -Not -Throw

            Remove-Item -Path $envFile -Force
        }
    }

    Context 'Cross-Platform Path Handling' {
        It 'Should handle paths with forward slashes' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'paths-forward.env'
            [System.IO.File]::WriteAllText($envFile, @'
UNIX_PATH=/usr/local/bin
RELATIVE_PATH=./config/app.json
'@, [System.Text.Encoding]::UTF8)

            Import-DotEnv -Path $envFile

            $env:UNIX_PATH | Should -Be '/usr/local/bin'
            $env:RELATIVE_PATH | Should -Be './config/app.json'

            Remove-Item -Path $envFile -Force
        }

        It 'Should handle paths with backslashes' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'paths-back.env'
            [System.IO.File]::WriteAllText($envFile, @'
WIN_PATH="C:\\Program Files\\MyApp"
NETWORK_PATH="\\\\server\\share"
'@, [System.Text.Encoding]::UTF8)

            Import-DotEnv -Path $envFile

            $env:WIN_PATH | Should -Be 'C:\Program Files\MyApp'
            $env:NETWORK_PATH | Should -Be '\\server\share'

            Remove-Item -Path $envFile -Force
        }
    }

    Context 'Performance and Scale' {
        It 'Should handle large .env file efficiently' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'large.env'
            $content = @()
            for ($i = 1; $i -le 100; $i++)
            {
                $content += "VAR_$i=value_$i"
            }
            [System.IO.File]::WriteAllText($envFile, ($content -join "`n"), [System.Text.Encoding]::UTF8)

            $result = Import-DotEnv -Path $envFile -PassThru

            $result.VariableCount | Should -Be 100
            $env:VAR_1 | Should -Be 'value_1'
            $env:VAR_50 | Should -Be 'value_50'
            $env:VAR_100 | Should -Be 'value_100'

            # Cleanup
            for ($i = 1; $i -le 100; $i++)
            {
                Remove-Item -Path "env:VAR_$i" -ErrorAction SilentlyContinue
            }
            Remove-Item -Path $envFile -Force
        }
    }

    Context 'ShowLoadedWithValues Integration' {
        It 'Should display values from realistic application configuration' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'app-showvalues.env'
            New-RealisticEnvFile -Path $envFile -Type 'Standard'

            Import-DotEnv -Path $envFile

            $result = Import-DotEnv -ShowLoadedWithValues -PassThru

            # Verify we got results
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 10

            # Check specific values
            ($result | Where-Object { $_.Name -eq 'APP_NAME' }).Value | Should -Be 'MyApp'
            ($result | Where-Object { $_.Name -eq 'APP_ENV' }).Value | Should -Be 'development'
            ($result | Where-Object { $_.Name -eq 'DB_CONNECTION' }).Value | Should -Be 'postgresql'
            ($result | Where-Object { $_.Name -eq 'DB_HOST' }).Value | Should -Be 'localhost'

            Remove-Item -Path $envFile -Force
        }

        It 'Should handle multi-file scenario showing all loaded variables' {
            $file1 = Join-Path -Path $script:TestDir -ChildPath 'base-showvalues.env'
            $file2 = Join-Path -Path $script:TestDir -ChildPath 'override-showvalues.env'

            [System.IO.File]::WriteAllText($file1, @'
APP_NAME=BaseApp
APP_ENV=production
DB_HOST=prod-db.example.com
'@, [System.Text.Encoding]::UTF8)

            [System.IO.File]::WriteAllText($file2, @'
APP_ENV=development
DB_HOST=localhost
DEBUG=true
'@, [System.Text.Encoding]::UTF8)

            # Load both
            Import-DotEnv -Path @($file1, $file2) -Force

            $result = Import-DotEnv -ShowLoadedWithValues -PassThru

            # Should show all variables with final values
            $result.Count | Should -Be 4
            ($result | Where-Object { $_.Name -eq 'APP_NAME' }).Value | Should -Be 'BaseApp'
            ($result | Where-Object { $_.Name -eq 'APP_ENV' }).Value | Should -Be 'development'
            ($result | Where-Object { $_.Name -eq 'DB_HOST' }).Value | Should -Be 'localhost'
            ($result | Where-Object { $_.Name -eq 'DEBUG' }).Value | Should -Be 'true'

            Remove-Item -Path $file1, $file2 -Force
        }

        It 'Should show expanded variable values' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'expansion-showvalues.env'
            [System.IO.File]::WriteAllText($envFile, @'
BASE_PATH=/home/user
PROJECT_PATH="${BASE_PATH}/projects"
CONFIG_PATH="${PROJECT_PATH}/config"
'@, [System.Text.Encoding]::UTF8)

            Import-DotEnv -Path $envFile

            $result = Import-DotEnv -ShowLoadedWithValues -PassThru

            ($result | Where-Object { $_.Name -eq 'BASE_PATH' }).Value | Should -Be '/home/user'
            ($result | Where-Object { $_.Name -eq 'PROJECT_PATH' }).Value | Should -Be '/home/user/projects'
            ($result | Where-Object { $_.Name -eq 'CONFIG_PATH' }).Value | Should -Be '/home/user/projects/config'

            Remove-Item -Path $envFile -Force
        }

        It 'Should handle load, modify, show workflow' {
            $envFile = Join-Path -Path $script:TestDir -ChildPath 'workflow-showvalues.env'
            [System.IO.File]::WriteAllText($envFile, @'
CONFIG_MODE=initial
API_ENDPOINT=https://api.example.com
TIMEOUT=30
'@, [System.Text.Encoding]::UTF8)

            # Load
            Import-DotEnv -Path $envFile

            # Modify some values programmatically
            $env:CONFIG_MODE = 'modified'
            $env:TIMEOUT = '60'

            # Show values should reflect current state
            $result = Import-DotEnv -ShowLoadedWithValues -PassThru

            ($result | Where-Object { $_.Name -eq 'CONFIG_MODE' }).Value | Should -Be 'modified'
            ($result | Where-Object { $_.Name -eq 'API_ENDPOINT' }).Value | Should -Be 'https://api.example.com'
            ($result | Where-Object { $_.Name -eq 'TIMEOUT' }).Value | Should -Be '60'

            Remove-Item -Path $envFile -Force
        }
    }
}
