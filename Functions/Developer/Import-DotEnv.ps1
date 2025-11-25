function Import-DotEnv
{
    <#
    .SYNOPSIS
        Loads environment variables from dotenv (.env) files.

    .DESCRIPTION
        Parses dotenv files and imports environment variables into the current PowerShell session.
        Supports standard dotenv format including comments, quoted values, and variable expansion.
        Can also unload previously loaded variables.

        The function follows common dotenv conventions:
        - Lines starting with # are comments
        - Empty lines are ignored
        - Format: KEY=value or KEY="value" or KEY='value'
        - Variable expansion: ${VAR_NAME} or $VAR_NAME in double-quoted values
        - Single quotes preserve literal values (no expansion)
        - Export prefix is optional: export KEY=value

        Compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

        Aliases:
        The 'dotenv' alias is created for this function if it doesn't already exist in the current environment.

    .PARAMETER Path
        Path to the .env file to load. Supports ~ expansion for home directory.
        If not specified, searches for .env in the current directory.
        Accepts pipeline input and multiple paths.

    .PARAMETER Unload
        If specified, removes environment variables that were previously loaded by this function.
        Uses tracking metadata stored in $env:__DOTENV_LOADED_VARS to identify which variables to remove.

    .PARAMETER ShowLoaded
        Displays the names of environment variables that were previously loaded by Import-DotEnv.
        This is a standalone operation that does not load any new files.
        Shows only variable names without values for security.

    .PARAMETER ShowLoadedWithValues
        Displays both names and values of environment variables that were previously loaded by Import-DotEnv.
        This is a standalone operation that does not load any new files.
        Returns an array of PSCustomObjects with Name and Value properties for clean display.
        WARNING: This will display sensitive values. Use with caution.

    .PARAMETER Scope
        Specifies the scope for environment variables. Valid values:
        - Process (default): Sets variables for the current process only
        - User: Sets variables for the current user (persistent across sessions) - Windows only
        - Machine: Sets variables system-wide (requires admin) - Windows only

        Note: User and Machine scopes only work on Windows. On macOS/Linux, only Process scope is available.

    .PARAMETER Force
        Overwrites existing environment variables. By default, existing variables are preserved.

    .PARAMETER PassThru
        Returns a summary object showing what variables were loaded or unloaded.

    .EXAMPLE
        PS > Import-DotEnv

        Loads environment variables from the .env file in the current directory.

    .EXAMPLE
        PS > Import-DotEnv -Path ~/project/.env
        PS > $env:DATABASE_URL
        postgresql://user:pass@localhost:5432/mydb

        Loads environment variables from a specific .env file, then accesses one of the loaded variables.

    .EXAMPLE
        PS > Import-DotEnv -Path .env -PassThru

        FileName      : .env
        FullPath      : /Users/jon/project/.env
        VariableCount : 4
        Variables     : {DATABASE_URL, API_KEY, DEBUG, APP_NAME}
        Skipped       : {PATH}
        Scope         : Process

        Loads variables and returns a summary object showing what was loaded and skipped.

    .EXAMPLE
        PS > Import-DotEnv -ShowLoaded
        Environment variables loaded by Import-DotEnv (4 total):
        APP_NAME, APP_ENV, APP_DEBUG, APP_URL

        Displays all environment variable names that were previously loaded by Import-DotEnv.

    .EXAMPLE
        PS > Import-DotEnv -ShowLoaded -PassThru

        VariableCount : 4
        Variables     : {APP_NAME, APP_ENV, APP_DEBUG, APP_URL}

        Shows loaded variables and returns a structured object for scripting.

    .EXAMPLE
        PS > Import-DotEnv -ShowLoadedWithValues

        Name        Value
        ----        -----
        APP_NAME    MyApp
        APP_ENV     development
        APP_DEBUG   true
        APP_URL     http://localhost:3000

        Displays all previously loaded environment variables with their current values.

    .EXAMPLE
        PS > Import-DotEnv -ShowLoadedWithValues -PassThru

        Returns an array of PSCustomObjects with Name and Value properties for programmatic access.

    .EXAMPLE
        PS > Import-DotEnv -Path .env.local -Force
        PS > $env:API_KEY
        sk-prod-abc123xyz789

        Loads variables from .env.local, overwriting any existing environment variables with -Force.

    .EXAMPLE
        PS > Import-DotEnv -Path @('.env', '.env.development') -Force
        PS > npm run dev

        Layered load similar to Next.js tooling: base .env first, then environment-specific overrides before starting the dev server.

    .EXAMPLE
        PS > Import-DotEnv -Path .env
        PS > $env:__DOTENV_LOADED_VARS -eq $null # APP_NAME|APP_ENV|APP_DEBUG|APP_URL
        False

        PS > Import-DotEnv -Unload
        PS > $env:__DOTENV_LOADED_VARS -eq $null
        True

        Loads environment variables then inspects the tracking variable that stores loaded variable names.
        Finally, environment variables are unloaded and again the tracking variable is checked to confirm removal.

    .EXAMPLE
        PS > Import-DotEnv -Unload -PassThru

        VariableCount : 4
        Variables     : {DATABASE_URL, API_KEY, DEBUG, APP_NAME}

        Removes all environment variables that were previously loaded and shows what was unloaded.

    .EXAMPLE
        PS > Import-DotEnv -Path '.env.ci' -PassThru | Out-Null
        PS > Invoke-Pester -Configuration ./Tests/PesterConfiguration.psd1

        Loads CI-specific secrets immediately before running the test suite so the pipeline remains self-contained.

    .EXAMPLE
        PS > dotenv -Path .env.development
        PS > $env:NODE_ENV
        development

        Uses the 'dotenv' alias to load environment variables from .env.development file.

    .EXAMPLE
        PS > Import-DotEnv -Path .env -Scope User

        Loads variables persistently for the current user (Windows only).

    .EXAMPLE
        PS > Get-ChildItem .env.* | Import-DotEnv -PassThru

        FileName      : .env.local
        FullPath      : /Users/jon/project/.env.local
        VariableCount : 2
        Variables     : {LOCAL_VAR, DEBUG_MODE}
        Skipped       : {}
        Scope         : Process

        FileName      : .env.test
        FullPath      : /Users/jon/project/.env.test
        VariableCount : 3
        Variables     : {TEST_DB, TEST_USER, TEST_PASS}
        Skipped       : {}
        Scope         : Process

        Loads multiple .env files via pipeline input and displays summary for each file.

    .OUTPUTS
        None by default. With -PassThru, returns a PSCustomObject or array of PSCustomObjects with load/unload details.
        With -ShowLoadedWithValues and -PassThru, returns an array of PSCustomObjects with Name and Value properties.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Import-DotEnv.ps1

        The function tracks loaded variable names in $env:__DOTENV_LOADED_VARS (pipe-delimited)
        to enable unloading. This tracking variable is also removed when using -Unload.

        Security Note: Be cautious with .env files containing sensitive data. Ensure
        appropriate file permissions and never commit them to version control.

        Dependencies:
        - Invoke-ElevatedCommand: Required when using -Scope Machine on Windows.
          This function must be available in the session for Machine scope to work.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Load')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    [OutputType([System.Object[]])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Load', Position = 0)]
        [Alias('FilePath', 'EnvFile')]
        [String[]]$Path = '.env',

        [Parameter(Mandatory, ParameterSetName = 'Unload')]
        [Switch]$Unload,

        [Parameter(Mandatory, ParameterSetName = 'ShowLoaded')]
        [Switch]$ShowLoaded,

        [Parameter(Mandatory, ParameterSetName = 'ShowLoadedWithValues')]
        [Switch]$ShowLoadedWithValues,

        [Parameter(ParameterSetName = 'Load')]
        [ValidateSet('Process', 'User', 'Machine')]
        [String]$Scope = 'Process',

        [Parameter(ParameterSetName = 'Load')]
        [Switch]$Force,

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        # Platform detection for PS 5.1 compatibility
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $script:IsWindowsPlatform = $true
            $script:IsMacOSPlatform = $false
            $script:IsLinuxPlatform = $false
        }
        else
        {
            $script:IsWindowsPlatform = $IsWindows
            $script:IsMacOSPlatform = $IsMacOS
            $script:IsLinuxPlatform = $IsLinux
        }

        # Validate scope for non-Windows platforms
        if (-not $script:IsWindowsPlatform -and $Scope -ne 'Process')
        {
            throw "Scope '$Scope' is only supported on Windows. On macOS and Linux, only 'Process' scope is available."
        }

        $loadedVariables = [System.Collections.ArrayList]::new()
        $skippedVariables = [System.Collections.ArrayList]::new()
        $results = [System.Collections.ArrayList]::new()
    }

    process
    {
        if ($ShowLoaded)
        {
            Write-Verbose 'Displaying previously loaded environment variables'

            # Get tracking variable
            $trackedVars = $env:__DOTENV_LOADED_VARS

            if ([String]::IsNullOrEmpty($trackedVars))
            {
                Write-Host 'No environment variables have been loaded by Import-DotEnv.' -ForegroundColor Yellow

                if ($PassThru)
                {
                    $result = [PSCustomObject]@{
                        VariableCount = 0
                        Variables = @()
                    }
                    $result.PSObject.TypeNames.Insert(0, 'DotEnv.ShowLoadedResult')
                    return $result
                }
                return
            }

            # Parse pipe-delimited variable names
            $varsLoaded = $trackedVars -split '\|' | Where-Object { -not [String]::IsNullOrWhiteSpace($_) }

            Write-Host "Environment variables loaded by Import-DotEnv ($($varsLoaded.Count) total):" -ForegroundColor Cyan
            Write-Host ($varsLoaded -join ', ') -ForegroundColor Green

            if ($PassThru)
            {
                $result = [PSCustomObject]@{
                    VariableCount = $varsLoaded.Count
                    Variables = $varsLoaded
                }
                $result.PSObject.TypeNames.Insert(0, 'DotEnv.ShowLoadedResult')
                return $result
            }
            return
        }

        if ($ShowLoadedWithValues)
        {
            Write-Verbose 'Displaying previously loaded environment variables with values'

            # Get tracking variable
            $trackedVars = $env:__DOTENV_LOADED_VARS

            if ([String]::IsNullOrEmpty($trackedVars))
            {
                Write-Host 'No environment variables have been loaded by Import-DotEnv.' -ForegroundColor Yellow

                if ($PassThru)
                {
                    return @()
                }
                return
            }

            # Parse pipe-delimited variable names
            $varsLoaded = $trackedVars -split '\|' | Where-Object { -not [String]::IsNullOrWhiteSpace($_) }

            # Build array of objects with Name and Value
            $varObjects = foreach ($varName in $varsLoaded)
            {
                $varValue = [System.Environment]::GetEnvironmentVariable($varName)
                [PSCustomObject]@{
                    Name = $varName
                    Value = $varValue
                }
            }

            if ($PassThru)
            {
                return $varObjects
            }
            else
            {
                # Display as table
                $varObjects | Format-Table -AutoSize
            }
            return
        }

        if ($Unload)
        {
            Write-Verbose 'Unloading environment variables from previous Import-DotEnv session'

            # Get tracking variable
            $trackedVars = $env:__DOTENV_LOADED_VARS

            if ([String]::IsNullOrEmpty($trackedVars))
            {
                Write-Verbose 'No tracked variables found to unload'
                if ($PassThru)
                {
                    $result = [PSCustomObject]@{
                        VariableCount = 0
                        Variables = @()
                    }
                    $result.PSObject.TypeNames.Insert(0, 'DotEnv.UnloadResult')
                    return $result
                }
                return
            }            # Parse pipe-delimited variable names
            $varsToRemove = $trackedVars -split '\|' | Where-Object { -not [String]::IsNullOrWhiteSpace($_) }

            Write-Verbose "Found $($varsToRemove.Count) variables to unload"

            foreach ($varName in $varsToRemove)
            {
                Write-Verbose "Removing environment variable: $varName"
                Remove-Item -Path "env:$varName" -ErrorAction SilentlyContinue
                [void]$loadedVariables.Add($varName)
            }

            # Remove tracking variable itself
            Remove-Item -Path 'env:__DOTENV_LOADED_VARS' -ErrorAction SilentlyContinue

            if ($PassThru)
            {
                $result = [PSCustomObject]@{
                    VariableCount = $loadedVariables.Count
                    Variables = $loadedVariables.ToArray()
                }
                $result.PSObject.TypeNames.Insert(0, 'DotEnv.UnloadResult')
                return $result
            }
            return
        }

        # Load mode
        foreach ($envFile in $Path)
        {
            # Resolve path with ~ expansion
            $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($envFile)

            Write-Verbose "Processing .env file: $resolvedPath"

            if (-not (Test-Path -Path $resolvedPath -PathType Leaf))
            {
                Write-Warning "File not found: $resolvedPath"
                continue
            }

            $fileLoadedVars = [System.Collections.ArrayList]::new()
            $fileSkippedVars = [System.Collections.ArrayList]::new()

            try
            {
                $content = Get-Content -Path $resolvedPath -Raw -ErrorAction Stop

                if ([String]::IsNullOrWhiteSpace($content))
                {
                    Write-Verbose "File is empty: $resolvedPath"
                    continue
                }

                # Split into lines for processing
                $lines = $content -split '\r?\n'

                for ($i = 0; $i -lt $lines.Count; $i++)
                {
                    $line = $lines[$i].Trim()

                    # Skip empty lines and comments
                    if ([String]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#'))
                    {
                        continue
                    }

                    # Remove 'export ' prefix if present
                    if ($line -match '^export\s+')
                    {
                        $line = $line -replace '^export\s+', ''
                    }

                    # Parse KEY=VALUE
                    if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$')
                    {
                        $varName = $matches[1]
                        $varValue = $matches[2]

                        Write-Verbose "Parsing variable: $varName"

                        # Handle quoted values
                        if ($varValue -match '^"(.*)"$')
                        {
                            # Double quotes: expand variables
                            $varValue = $matches[1]
                            # Expand ${VAR} and $VAR patterns
                            $varValue = [System.Text.RegularExpressions.Regex]::Replace(
                                $varValue,
                                '\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)',
                                {
                                    param($match)
                                    $envVarName = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
                                    $envValue = [System.Environment]::GetEnvironmentVariable($envVarName)
                                    if ($null -ne $envValue) { $envValue } else { $match.Value }
                                }
                            )
                            # Handle escape sequences
                            $varValue = $varValue -replace '\\n', "`n"
                            $varValue = $varValue -replace '\\r', "`r"
                            $varValue = $varValue -replace '\\t', "`t"
                            $varValue = $varValue -replace '\\\\', '\'
                            $varValue = $varValue -replace '\\"', '"'
                        }
                        elseif ($varValue -match "^'(.*)'$")
                        {
                            # Single quotes: literal value, no expansion
                            $varValue = $matches[1]
                        }
                        else
                        {
                            # Unquoted: trim trailing comments and whitespace
                            if ($varValue -match '^([^#]*?)\s*#.*$')
                            {
                                $varValue = $matches[1].TrimEnd()
                            }
                        }

                        # Check if variable already exists
                        $existingValue = [System.Environment]::GetEnvironmentVariable($varName)

                        if ($null -ne $existingValue -and -not $Force)
                        {
                            Write-Verbose "Skipping existing variable: $varName"
                            [void]$fileSkippedVars.Add($varName)
                            continue
                        }

                        # Set the environment variable
                        Write-Verbose "Setting environment variable: $varName"

                        if ($Scope -eq 'Process')
                        {
                            [System.Environment]::SetEnvironmentVariable($varName, $varValue)
                        }
                        elseif ($Scope -eq 'User' -and $script:IsWindowsPlatform)
                        {
                            [System.Environment]::SetEnvironmentVariable($varName, $varValue, [System.EnvironmentVariableTarget]::User)
                            # Also set in current session
                            [System.Environment]::SetEnvironmentVariable($varName, $varValue)
                        }
                        elseif ($Scope -eq 'Machine' -and $script:IsWindowsPlatform)
                        {
                            # Use Invoke-ElevatedCommand to set machine-level environment variable
                            Invoke-ElevatedCommand -Scriptblock {
                                param($VarName, $VarValue)
                                [System.Environment]::SetEnvironmentVariable($VarName, $VarValue, [System.EnvironmentVariableTarget]::Machine)
                            } -InputObject @($varName, $varValue) | Out-Null
                            # Also set in current session
                            [System.Environment]::SetEnvironmentVariable($varName, $varValue)
                        }

                        [void]$fileLoadedVars.Add($varName)
                    }
                }

                # Update tracking for loaded variables (only for Process scope)
                if ($Scope -eq 'Process' -and $fileLoadedVars.Count -gt 0)
                {
                    $existingTracked = $env:__DOTENV_LOADED_VARS
                    if ([String]::IsNullOrEmpty($existingTracked))
                    {
                        $newTracked = $fileLoadedVars -join '|'
                    }
                    else
                    {
                        $allTracked = @($existingTracked -split '\|') + $fileLoadedVars
                        $newTracked = ($allTracked | Select-Object -Unique) -join '|'
                    }
                    [System.Environment]::SetEnvironmentVariable('__DOTENV_LOADED_VARS', $newTracked)
                }

                [void]$loadedVariables.AddRange($fileLoadedVars)
                [void]$skippedVariables.AddRange($fileSkippedVars)

                if ($PassThru)
                {
                    $loadResult = [PSCustomObject]@{
                        FileName = [System.IO.Path]::GetFileName($resolvedPath)
                        FullPath = $resolvedPath
                        VariableCount = $fileLoadedVars.Count
                        Variables = $fileLoadedVars.ToArray()
                        Skipped = $fileSkippedVars.ToArray()
                        Scope = $Scope
                    }
                    $loadResult.PSObject.TypeNames.Insert(0, 'DotEnv.LoadResult')
                    [void]$results.Add($loadResult)
                }

                Write-Verbose "Loaded $($fileLoadedVars.Count) variables from $resolvedPath"
            }
            catch
            {
                # Avoid leaking file contents in error messages
                $errorMsg = $_.Exception.Message -replace '(?m)^.*?[A-Z_][A-Z0-9_]*\s*=.*$', '<content redacted>'
                Write-Error "Failed to process file '$resolvedPath': $errorMsg"
            }
        }
    }

    end
    {
        if ($PassThru -and -not $Unload -and $results.Count -gt 0)
        {
            return $results.ToArray()
        }
    }
}

# Create 'dotenv' alias only if it doesn't already exist
if (-not (Get-Command -Name 'dotenv' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'dotenv' alias for Import-DotEnv"
        Set-Alias -Name 'dotenv' -Value 'Import-DotEnv' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Import-DotEnv: Could not create 'dotenv' alias: $($_.Exception.Message)"
    }
}
