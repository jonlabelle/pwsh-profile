#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Import-DotEnv function.

.DESCRIPTION
    Tests the Import-DotEnv function which loads and unloads environment variables from dotenv files.
    Validates parsing logic, variable expansion, quoting, cross-platform compatibility, and error handling.

.NOTES
    These tests verify the function works correctly with PowerShell 5.1+ on all platforms.
    Tests include: basic loading, quoted values, variable expansion, comments, unloading, and edge cases.
#>

BeforeAll {
    # Load the function
    . "$PSScriptRoot/../../../Functions/Developer/Import-DotEnv.ps1"

    # Helper function to create test .env files
    function New-TestEnvFile
    {
        param(
            [String]$Path,
            [String]$Content
        )
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
    }

    # Helper to clean up environment variables
    function Clear-TestEnvVars
    {
        param([String[]]$VarNames)
        foreach ($varName in $VarNames)
        {
            Remove-Item -Path "env:$varName" -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Import-DotEnv' {
    BeforeAll {
        $script:TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "dotenv-tests-$(Get-Random)"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:TestDir)
        {
            Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Basic Loading' {
        BeforeEach {
            $script:TestEnvFile = Join-Path $script:TestDir 'basic.env'
            Clear-TestEnvVars -VarNames @('TEST_VAR1', 'TEST_VAR2', 'TEST_VAR3', '__DOTENV_LOADED_VARS')
        }

        AfterEach {
            Clear-TestEnvVars -VarNames @('TEST_VAR1', 'TEST_VAR2', 'TEST_VAR3', '__DOTENV_LOADED_VARS')
            if (Test-Path $script:TestEnvFile)
            {
                Remove-Item -Path $script:TestEnvFile -Force
            }
        }

        It 'Should load simple key=value pairs' {
            $content = @'
TEST_VAR1=value1
TEST_VAR2=value2
TEST_VAR3=value3
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_VAR1 | Should -Be 'value1'
            $env:TEST_VAR2 | Should -Be 'value2'
            $env:TEST_VAR3 | Should -Be 'value3'
        }

        It 'Should handle spaces around equals sign' {
            $content = 'TEST_VAR1 = value with spaces'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_VAR1 | Should -Be 'value with spaces'
        }

        It 'Should skip empty lines' {
            $content = @'
TEST_VAR1=value1


TEST_VAR2=value2
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_VAR1 | Should -Be 'value1'
            $env:TEST_VAR2 | Should -Be 'value2'
        }

        It 'Should skip comment lines starting with #' {
            $content = @'
# This is a comment
TEST_VAR1=value1
# Another comment
TEST_VAR2=value2
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_VAR1 | Should -Be 'value1'
            $env:TEST_VAR2 | Should -Be 'value2'
        }

        It 'Should handle export prefix' {
            $content = @'
export TEST_VAR1=value1
export TEST_VAR2=value2
TEST_VAR3=value3
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_VAR1 | Should -Be 'value1'
            $env:TEST_VAR2 | Should -Be 'value2'
            $env:TEST_VAR3 | Should -Be 'value3'
        }

        It 'Should track loaded variables' {
            $content = @'
TEST_VAR1=value1
TEST_VAR2=value2
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:__DOTENV_LOADED_VARS | Should -Not -BeNullOrEmpty
            $env:__DOTENV_LOADED_VARS | Should -Match 'TEST_VAR1'
            $env:__DOTENV_LOADED_VARS | Should -Match 'TEST_VAR2'
        }

        It 'Should return results with PassThru' {
            $content = @'
TEST_VAR1=value1
TEST_VAR2=value2
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            $result = Import-DotEnv -Path $script:TestEnvFile -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should -Be 'DotEnv.LoadResult'
            $result.VariableCount | Should -Be 2
            $result.Variables | Should -Contain 'TEST_VAR1'
            $result.Variables | Should -Contain 'TEST_VAR2'
            $result.Scope | Should -Be 'Process'
        }
    }

    Context 'Quoted Values' {
        BeforeEach {
            $script:TestEnvFile = Join-Path $script:TestDir 'quoted.env'
            Clear-TestEnvVars -VarNames @('TEST_DOUBLE', 'TEST_SINGLE', 'TEST_UNQUOTED', '__DOTENV_LOADED_VARS')
        }

        AfterEach {
            Clear-TestEnvVars -VarNames @('TEST_DOUBLE', 'TEST_SINGLE', 'TEST_UNQUOTED', '__DOTENV_LOADED_VARS')
            if (Test-Path $script:TestEnvFile)
            {
                Remove-Item -Path $script:TestEnvFile -Force
            }
        }

        It 'Should handle double-quoted values' {
            $content = 'TEST_DOUBLE="double quoted value"'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_DOUBLE | Should -Be 'double quoted value'
        }

        It 'Should handle single-quoted values' {
            $content = "TEST_SINGLE='single quoted value'"
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_SINGLE | Should -Be 'single quoted value'
        }

        It 'Should handle unquoted values with trailing comments' {
            $content = 'TEST_UNQUOTED=value # this is a comment'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_UNQUOTED | Should -Be 'value'
        }

        It 'Should preserve spaces in double-quoted values' {
            $content = 'TEST_DOUBLE="  value with spaces  "'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_DOUBLE | Should -Be '  value with spaces  '
        }

        It 'Should preserve spaces in single-quoted values' {
            $content = "TEST_SINGLE='  value with spaces  '"
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_SINGLE | Should -Be '  value with spaces  '
        }

        It 'Should handle escape sequences in double-quoted values' {
            $content = 'TEST_DOUBLE="Line 1\nLine 2\tTabbed"'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_DOUBLE | Should -Match "Line 1`nLine 2`tTabbed"
        }

        It 'Should NOT expand escape sequences in single-quoted values' {
            $content = "TEST_SINGLE='Line 1\nLine 2'"
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_SINGLE | Should -Be 'Line 1\nLine 2'
        }

        It 'Should handle escaped quotes in double-quoted values' {
            $content = 'TEST_DOUBLE="She said \"Hello\""'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_DOUBLE | Should -Be 'She said "Hello"'
        }

        It 'Should handle backslashes in double-quoted values' {
            $content = 'TEST_DOUBLE="C:\\Windows\\System32"'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_DOUBLE | Should -Be 'C:\Windows\System32'
        }
    }

    Context 'Variable Expansion' {
        BeforeEach {
            $script:TestEnvFile = Join-Path $script:TestDir 'expansion.env'
            $env:EXISTING_VAR = 'existing_value'
            Clear-TestEnvVars -VarNames @('TEST_EXPAND1', 'TEST_EXPAND2', 'TEST_NO_EXPAND', 'NEW_VAR', '__DOTENV_LOADED_VARS')
        }

        AfterEach {
            Clear-TestEnvVars -VarNames @('TEST_EXPAND1', 'TEST_EXPAND2', 'TEST_NO_EXPAND', 'NEW_VAR', 'EXISTING_VAR', '__DOTENV_LOADED_VARS')
            if (Test-Path $script:TestEnvFile)
            {
                Remove-Item -Path $script:TestEnvFile -Force
            }
        }

        It 'Should expand variables with ${VAR} syntax in double quotes' {
            $content = 'TEST_EXPAND1="Value is ${EXISTING_VAR}"'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_EXPAND1 | Should -Be 'Value is existing_value'
        }

        It 'Should expand variables with $VAR syntax in double quotes' {
            $content = 'TEST_EXPAND2="Value is $EXISTING_VAR"'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_EXPAND2 | Should -Be 'Value is existing_value'
        }

        It 'Should NOT expand variables in single quotes' {
            $content = "TEST_NO_EXPAND='Value is `${EXISTING_VAR}'"
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_NO_EXPAND | Should -Be 'Value is ${EXISTING_VAR}'
        }

        It 'Should handle undefined variable expansion gracefully' {
            $content = 'NEW_VAR="Value is ${UNDEFINED_VAR}"'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            # Should keep the literal variable reference if undefined
            $env:NEW_VAR | Should -Be 'Value is ${UNDEFINED_VAR}'
        }

        It 'Should expand multiple variables in one value' {
            $env:VAR1 = 'first'
            $env:VAR2 = 'second'
            $content = 'TEST_EXPAND1="${VAR1} and $VAR2"'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:TEST_EXPAND1 | Should -Be 'first and second'

            Clear-TestEnvVars -VarNames @('VAR1', 'VAR2')
        }
    }

    Context 'Force Parameter' {
        BeforeEach {
            $script:TestEnvFile = Join-Path $script:TestDir 'force.env'
            $env:EXISTING_VAR = 'original_value'
            Clear-TestEnvVars -VarNames @('__DOTENV_LOADED_VARS')
        }

        AfterEach {
            Clear-TestEnvVars -VarNames @('EXISTING_VAR', '__DOTENV_LOADED_VARS')
            if (Test-Path $script:TestEnvFile)
            {
                Remove-Item -Path $script:TestEnvFile -Force
            }
        }

        It 'Should not overwrite existing variables by default' {
            $content = 'EXISTING_VAR=new_value'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            $result = Import-DotEnv -Path $script:TestEnvFile -PassThru

            $env:EXISTING_VAR | Should -Be 'original_value'
            $result.Skipped | Should -Contain 'EXISTING_VAR'
        }

        It 'Should overwrite existing variables with -Force' {
            $content = 'EXISTING_VAR=new_value'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile -Force

            $env:EXISTING_VAR | Should -Be 'new_value'
        }

        It 'Should track overwritten variables with -Force' {
            $content = 'EXISTING_VAR=forced_value'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile -Force

            $env:__DOTENV_LOADED_VARS | Should -Match 'EXISTING_VAR'
        }
    }

    Context 'Unload Functionality' {
        BeforeEach {
            $script:TestEnvFile = Join-Path $script:TestDir 'unload.env'
            Clear-TestEnvVars -VarNames @('UNLOAD_VAR1', 'UNLOAD_VAR2', 'UNLOAD_VAR3', '__DOTENV_LOADED_VARS')
        }

        AfterEach {
            Clear-TestEnvVars -VarNames @('UNLOAD_VAR1', 'UNLOAD_VAR2', 'UNLOAD_VAR3', '__DOTENV_LOADED_VARS')
            if (Test-Path $script:TestEnvFile)
            {
                Remove-Item -Path $script:TestEnvFile -Force
            }
        }

        It 'Should unload all previously loaded variables' {
            $content = @'
UNLOAD_VAR1=value1
UNLOAD_VAR2=value2
UNLOAD_VAR3=value3
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:UNLOAD_VAR1 | Should -Be 'value1'
            $env:UNLOAD_VAR2 | Should -Be 'value2'
            $env:UNLOAD_VAR3 | Should -Be 'value3'

            Import-DotEnv -Unload

            $env:UNLOAD_VAR1 | Should -BeNullOrEmpty
            $env:UNLOAD_VAR2 | Should -BeNullOrEmpty
            $env:UNLOAD_VAR3 | Should -BeNullOrEmpty
        }

        It 'Should remove tracking variable when unloading' {
            $content = 'UNLOAD_VAR1=value1'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile
            $env:__DOTENV_LOADED_VARS | Should -Not -BeNullOrEmpty

            Import-DotEnv -Unload
            $env:__DOTENV_LOADED_VARS | Should -BeNullOrEmpty
        }

        It 'Should return unload results with PassThru' {
            $content = @'
UNLOAD_VAR1=value1
UNLOAD_VAR2=value2
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $result = Import-DotEnv -Unload -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should -Be 'DotEnv.UnloadResult'
            $result.VariableCount | Should -Be 2
            $result.Variables | Should -Contain 'UNLOAD_VAR1'
            $result.Variables | Should -Contain 'UNLOAD_VAR2'
        }

        It 'Should handle unload when no variables were loaded' {
            $result = Import-DotEnv -Unload -PassThru

            $result.VariableCount | Should -Be 0
            $result.Variables | Should -BeNullOrEmpty
        }

        It 'Should handle multiple load sessions before unload' {
            $content1 = 'UNLOAD_VAR1=value1'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content1
            Import-DotEnv -Path $script:TestEnvFile

            $testEnvFile2 = Join-Path $script:TestDir 'unload2.env'
            $content2 = 'UNLOAD_VAR2=value2'
            New-TestEnvFile -Path $testEnvFile2 -Content $content2
            Import-DotEnv -Path $testEnvFile2

            $tracked = $env:__DOTENV_LOADED_VARS
            $tracked | Should -Match 'UNLOAD_VAR1'
            $tracked | Should -Match 'UNLOAD_VAR2'

            Import-DotEnv -Unload

            $env:UNLOAD_VAR1 | Should -BeNullOrEmpty
            $env:UNLOAD_VAR2 | Should -BeNullOrEmpty

            if (Test-Path $testEnvFile2)
            {
                Remove-Item -Path $testEnvFile2 -Force
            }
        }
    }

    Context 'Path Handling' {
        BeforeEach {
            Clear-TestEnvVars -VarNames @('PATH_VAR', '__DOTENV_LOADED_VARS')
        }

        AfterEach {
            Clear-TestEnvVars -VarNames @('PATH_VAR', '__DOTENV_LOADED_VARS')
        }

        It 'Should use .env in current directory by default' {
            $defaultEnvFile = Join-Path $script:TestDir '.env'
            $content = 'PATH_VAR=default'
            New-TestEnvFile -Path $defaultEnvFile -Content $content

            Push-Location $script:TestDir
            try
            {
                Import-DotEnv
                $env:PATH_VAR | Should -Be 'default'
            }
            finally
            {
                Pop-Location
                if (Test-Path $defaultEnvFile)
                {
                    Remove-Item -Path $defaultEnvFile -Force
                }
            }
        }

        It 'Should accept absolute path' {
            $absoluteFile = Join-Path $script:TestDir 'absolute.env'
            $content = 'PATH_VAR=absolute'
            New-TestEnvFile -Path $absoluteFile -Content $content

            Import-DotEnv -Path $absoluteFile

            $env:PATH_VAR | Should -Be 'absolute'

            if (Test-Path $absoluteFile)
            {
                Remove-Item -Path $absoluteFile -Force
            }
        }

        It 'Should handle multiple paths via pipeline' {
            $file1 = Join-Path $script:TestDir 'file1.env'
            $file2 = Join-Path $script:TestDir 'file2.env'
            New-TestEnvFile -Path $file1 -Content 'VAR1=value1'
            New-TestEnvFile -Path $file2 -Content 'VAR2=value2'

            @($file1, $file2) | Import-DotEnv

            $env:VAR1 | Should -Be 'value1'
            $env:VAR2 | Should -Be 'value2'

            Clear-TestEnvVars -VarNames @('VAR1', 'VAR2')
            Remove-Item -Path $file1, $file2 -Force
        }

        It 'Should warn when file does not exist' {
            $nonExistent = Join-Path $script:TestDir 'nonexistent.env'

            { Import-DotEnv -Path $nonExistent -WarningAction Stop } | Should -Throw
        }
    }

    Context 'Variable Name Validation' {
        BeforeEach {
            $script:TestEnvFile = Join-Path $script:TestDir 'validation.env'
            Clear-TestEnvVars -VarNames @('VALID_VAR', 'VALID_VAR_123', '_VALID_VAR', '__DOTENV_LOADED_VARS')
        }

        AfterEach {
            Clear-TestEnvVars -VarNames @('VALID_VAR', 'VALID_VAR_123', '_VALID_VAR', '__DOTENV_LOADED_VARS')
            if (Test-Path $script:TestEnvFile)
            {
                Remove-Item -Path $script:TestEnvFile -Force
            }
        }

        It 'Should accept uppercase variable names' {
            $content = 'VALID_VAR=value'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:VALID_VAR | Should -Be 'value'
        }

        It 'Should accept variable names with numbers' {
            $content = 'VALID_VAR_123=value'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:VALID_VAR_123 | Should -Be 'value'
        }

        It 'Should accept variable names starting with underscore' {
            $content = '_VALID_VAR=value'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:_VALID_VAR | Should -Be 'value'
        }

        It 'Should skip invalid variable names (starting with number)' {
            $content = @'
VALID_VAR=valid
123INVALID=invalid
ANOTHER_VALID=valid2
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:VALID_VAR | Should -Be 'valid'
            $env:ANOTHER_VALID | Should -Be 'valid2'
            # Invalid variable should not be set
        }
    }

    Context 'Edge Cases' {
        BeforeEach {
            $script:TestEnvFile = Join-Path $script:TestDir 'edge.env'
            Clear-TestEnvVars -VarNames @('EMPTY_VAR', 'EQUALS_VAR', 'SPECIAL_VAR', '__DOTENV_LOADED_VARS')
        }

        AfterEach {
            Clear-TestEnvVars -VarNames @('EMPTY_VAR', 'EQUALS_VAR', 'SPECIAL_VAR', '__DOTENV_LOADED_VARS')
            if (Test-Path $script:TestEnvFile)
            {
                Remove-Item -Path $script:TestEnvFile -Force
            }
        }

        It 'Should handle empty values' {
            $content = 'EMPTY_VAR='
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:EMPTY_VAR | Should -BeNullOrEmpty
        }

        It 'Should handle values containing equals signs' {
            $content = 'EQUALS_VAR=key=value'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:EQUALS_VAR | Should -Be 'key=value'
        }

        It 'Should handle empty file' {
            New-TestEnvFile -Path $script:TestEnvFile -Content ''

            { Import-DotEnv -Path $script:TestEnvFile } | Should -Not -Throw
        }

        It 'Should handle file with only comments' {
            $content = @'
# Comment 1
# Comment 2
# Comment 3
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            { Import-DotEnv -Path $script:TestEnvFile } | Should -Not -Throw
        }

        It 'Should handle values with special characters' {
            $content = 'SPECIAL_VAR="!@#$%^&*()[]{}|;:<>?,./"'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:SPECIAL_VAR | Should -Be '!@#$%^&*()[]{}|;:<>?,./'
        }

        It 'Should handle Windows-style line endings' {
            $content = "VAR1=value1`r`nVAR2=value2`r`n"
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:VAR1 | Should -Be 'value1'
            $env:VAR2 | Should -Be 'value2'

            Clear-TestEnvVars -VarNames @('VAR1', 'VAR2')
        }

        It 'Should handle Unix-style line endings' {
            $content = "VAR1=value1`nVAR2=value2`n"
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            Import-DotEnv -Path $script:TestEnvFile

            $env:VAR1 | Should -Be 'value1'
            $env:VAR2 | Should -Be 'value2'

            Clear-TestEnvVars -VarNames @('VAR1', 'VAR2')
        }
    }

    Context 'Scope Validation' {
        BeforeEach {
            $script:TestEnvFile = Join-Path $script:TestDir 'scope.env'
            Clear-TestEnvVars -VarNames @('SCOPE_VAR', '__DOTENV_LOADED_VARS')
        }

        AfterEach {
            Clear-TestEnvVars -VarNames @('SCOPE_VAR', '__DOTENV_LOADED_VARS')
            if (Test-Path $script:TestEnvFile)
            {
                Remove-Item -Path $script:TestEnvFile -Force
            }
        }

        It 'Should accept Process scope on all platforms' {
            $content = 'SCOPE_VAR=process_value'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            { Import-DotEnv -Path $script:TestEnvFile -Scope Process } | Should -Not -Throw
            $env:SCOPE_VAR | Should -Be 'process_value'
        }

        It 'Should throw error for User scope on non-Windows platforms' -Skip:($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
            $content = 'SCOPE_VAR=user_value'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            { Import-DotEnv -Path $script:TestEnvFile -Scope User } | Should -Throw '*only supported on Windows*'
        }

        It 'Should throw error for Machine scope on non-Windows platforms' -Skip:($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
            $content = 'SCOPE_VAR=machine_value'
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            { Import-DotEnv -Path $script:TestEnvFile -Scope Machine } | Should -Throw '*only supported on Windows*'
        }
    }

    Context 'Security - No Value Leakage' {
        BeforeEach {
            $script:TestEnvFile = Join-Path $script:TestDir 'secrets.env'
            Clear-TestEnvVars -VarNames @('SECRET_KEY', 'API_TOKEN', 'PASSWORD', '__DOTENV_LOADED_VARS')
        }

        AfterEach {
            Clear-TestEnvVars -VarNames @('SECRET_KEY', 'API_TOKEN', 'PASSWORD', '__DOTENV_LOADED_VARS')
            if (Test-Path $script:TestEnvFile)
            {
                Remove-Item -Path $script:TestEnvFile -Force
            }
        }

        It 'Should not leak variable values in verbose output' {
            $content = @'
SECRET_KEY=super_secret_12345
API_TOKEN=token_abcdef67890
PASSWORD=MyP@ssw0rd!
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            $verboseOutput = Import-DotEnv -Path $script:TestEnvFile -Verbose 4>&1 | Out-String

            # Verbose output should contain "Parsing variable" or "Setting" messages with variable names
            ($verboseOutput | Should -Match 'Parsing variable:|Setting environment variable:')

            # Verbose output should NOT contain the secret values
            $verboseOutput | Should -Not -Match 'super_secret_12345'
            $verboseOutput | Should -Not -Match 'token_abcdef67890'
            $verboseOutput | Should -Not -Match 'MyP@ssw0rd!'
        }

        It 'Should not leak values in PassThru output (only variable names)' {
            $content = @'
SECRET_KEY=super_secret_value
API_TOKEN=another_secret
'@
            New-TestEnvFile -Path $script:TestEnvFile -Content $content

            $result = Import-DotEnv -Path $script:TestEnvFile -PassThru

            # Result should contain variable names
            $result.Variables | Should -Contain 'SECRET_KEY'
            $result.Variables | Should -Contain 'API_TOKEN'

            # Convert result to string to check for leaks
            $resultString = $result | Out-String

            # Should NOT contain the secret values
            $resultString | Should -Not -Match 'super_secret_value'
            $resultString | Should -Not -Match 'another_secret'
        }
    }
}
