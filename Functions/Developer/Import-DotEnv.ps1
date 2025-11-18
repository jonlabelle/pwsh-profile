function Import-DotEnv
{
    <#
    .SYNOPSIS
        Loads environment variables from dotenv (.env) files into the current session.

    .DESCRIPTION
        Parses dotenv files and imports environment variables into the current PowerShell session.
        Supports standard dotenv format including comments, quoted values, variable expansion,
        and multi-line values. Can also unload previously loaded variables.

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

        Loads environment variables from .env in the current directory.

    .EXAMPLE
        PS > Import-DotEnv -Path ~/project/.env

        Loads environment variables from a specific .env file.

    .EXAMPLE
        PS > Import-DotEnv -Path .env -PassThru

        FileName      : .env
        VariableCount : 4
        Variables     : {DATABASE_URL, API_KEY, DEBUG, APP_NAME}
        Skipped       : {PATH}

        Loads variables and returns a summary of what was loaded.

    .EXAMPLE
        PS > Import-DotEnv -Path .env.local -Force

        Loads variables from .env.local, overwriting any existing environment variables.

    .EXAMPLE
        PS > Import-DotEnv -Unload

        Removes all environment variables that were previously loaded by Import-DotEnv.

    .EXAMPLE
        PS > Import-DotEnv -Path .env -Scope User

        Loads variables persistently for the current user (Windows only).

    .OUTPUTS
        None by default. With -PassThru, returns a PSCustomObject with load/unload details.

    .NOTES
        The function tracks loaded variable names in $env:__DOTENV_LOADED_VARS (pipe-delimited)
        to enable unloading. This tracking variable is also removed when using -Unload.

        Security Note: Be cautious with .env files containing sensitive data. Ensure
        appropriate file permissions and never commit them to version control.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Load')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Load', Position = 0)]
        [Alias('FilePath', 'EnvFile')]
        [String[]]$Path = '.env',

        [Parameter(Mandatory, ParameterSetName = 'Unload')]
        [Switch]$Unload,

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

        # Check for admin rights if Machine scope is requested
        if ($Scope -eq 'Machine')
        {
            $isAdmin = $false
            if ($script:IsWindowsPlatform)
            {
                $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            }

            if (-not $isAdmin)
            {
                throw 'Machine scope requires administrator privileges. Run PowerShell as Administrator or use Process/User scope.'
            }
        }

        $loadedVariables = [System.Collections.ArrayList]::new()
        $skippedVariables = [System.Collections.ArrayList]::new()
        $results = [System.Collections.ArrayList]::new()
    }

    process
    {
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
            if ($PSCmdlet.SessionState)
            {
                $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($envFile)
            }
            else
            {
                $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($envFile)
            }

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
                            [System.Environment]::SetEnvironmentVariable($varName, $varValue, [System.EnvironmentVariableTarget]::Machine)
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

# Create 'dotenv' alias if it doesn't already exist
if (-not (Get-Alias -Name 'dotenv' -ErrorAction SilentlyContinue))
{
    try
    {
        Set-Alias -Name 'dotenv' -Value 'Import-DotEnv' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Import-DotEnv: Could not create 'dotenv' alias: $($_.Exception.Message)"
    }
}
