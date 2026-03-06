function Invoke-SqlFluff
{
    <#
    .SYNOPSIS
        Runs SQLFluff lint, fix, or format against SQL files.

    .DESCRIPTION
        Invoke-SqlFluff supports three runtime modes:
        - Auto   : Prefer local SQLFluff from PATH, then fall back to Docker.
        - Local  : Require and use local SQLFluff only.
        - Docker : Require and use Docker only.

        By default, Auto mode is used.

        In Docker mode, it mounts the current working directory and a configurable
        .sqlfluff configuration file into the container, then executes the specified
        SQLFluff mode against the target file.

        Modes:
        - lint   : Check for SQL violations without modifying files.
        - fix    : Auto-fix rule-based violations in place.
        - format : Auto-fix formatting violations in place (a subset of fix).

    .PARAMETER Mode
        The SQLFluff operation to perform.

        - 'lint'   checks for violations without modifying files.

        - 'fix'    auto-fixes all rule-based violations in place, including keyword
                   capitalization, aliasing, join syntax, keyword order, and formatting.
                   This is a superset of 'format' — running 'fix' already applies all
                   formatting rules, so there is no need to run both.

        - 'format' auto-fixes only whitespace and layout violations in place, such as
                   indentation, spacing, trailing whitespace, and line length. This is
                   a safe subset of 'fix' that does not alter the semantic structure of
                   your SQL.

    .PARAMETER Path
        One or more paths to SQL files or directories to process. Accepts pipeline
        input (including FileInfo objects from Get-ChildItem). Supports wildcard
        patterns (for example, *.sql).

        In Docker mode, paths must resolve inside the current working directory so
        they can be accessed via the container mount at /sql.

        When a directory is provided, all *.sql files in that directory are processed.
        Use -Recurse to include subdirectories.

        When omitted entirely, the function discovers all *.sql files in the current
        working directory. Use -Recurse to include subdirectories.

    .PARAMETER LiteralPath
        One or more literal paths to SQL files or directories to process. Unlike -Path,
        wildcard characters are treated literally. Use this when file or directory names
        contain wildcard characters such as [] or *.

    .PARAMETER Recurse
        When -Path/-LiteralPath is omitted or points to a directory, searches for
        *.sql files recursively in subdirectories. Has no effect when the input
        points to file(s).

    .PARAMETER ConfigPath
        The local file system path to the .sqlfluff configuration file. This file is
        passed via --config. In Docker mode, it is mounted into the container.
        Defaults to $HOME/.sqlfluff.

        When the config file is not found (and -ConfigPath was not explicitly specified),
        SQLFluff runs without a config file. In that case, if -Dialect is not provided,
        Invoke-SqlFluff defaults to the 'ansi' dialect.

    .PARAMETER Dialect
        The SQL dialect to use for parsing. Overrides any dialect set in the config file.
        If omitted and no config file is used, Invoke-SqlFluff defaults to 'ansi'.
        Common dialects include: ansi, tsql, mysql, postgres, bigquery, sparksql, sqlite,
        clickhouse, duckdb, hive, redshift, snowflake, soql, trino.

        For the full list, see https://docs.sqlfluff.com/en/stable/dialects.html

    .PARAMETER ImageTag
        The Docker image tag to use for the sqlfluff/sqlfluff image. Defaults to 'latest'.
        Use a specific version tag (e.g. '3.0.0') for reproducible results in Docker mode.

    .PARAMETER Runtime
        Controls how SQLFluff is executed:
        - Auto   : Prefer local SQLFluff from PATH, then fall back to Docker.
        - Local  : Use local SQLFluff only and throw if not available.
        - Docker : Use Docker only and throw if Docker is not available.

    .PARAMETER AdditionalArgs
        Additional arguments to pass directly to the SQLFluff command. Useful for options
        such as --exclude-rules, --rules, --ignore, --processes, etc.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint -Path query.sql

        Lints query.sql using the default config at $HOME/.sqlfluff.

    .EXAMPLE
        Invoke-SqlFluff -Mode format -Path query.sql

        Formats query.sql in place, auto-fixing formatting violations.

    .EXAMPLE
        Invoke-SqlFluff -Mode fix -Path query.sql -Dialect tsql

        Fixes rule violations in query.sql using the T-SQL dialect.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint -Path "stored_procedures/spPurgeFile.sql"

        Lints a SQL file in a subdirectory of the current working directory.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint -Path query.sql -ConfigPath "C:\team-configs\.sqlfluff"

        Lints query.sql using a shared team configuration file.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint -Path query.sql -ImageTag '3.0.0'

        Lints query.sql using a pinned SQLFluff version for reproducible results.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint -Path query.sql -AdditionalArgs '--exclude-rules', 'LT01,LT02'

        Lints query.sql while excluding specific rules.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint -Path query.sql, migrations.sql

        Lints multiple SQL files in a single call.

    .EXAMPLE
        Invoke-SqlFluff -Mode format -Path *.sql

        Formats all SQL files in the current working directory via wildcard expansion.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint -LiteralPath 'report[1].sql'

        Lints a file whose name contains wildcard characters.

    .EXAMPLE
        Get-ChildItem -Filter *.sql | Invoke-SqlFluff -Mode lint

        Lints all SQL files in the current directory via pipeline input.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint

        Discovers and lints all *.sql files in the current working directory.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint -Recurse

        Discovers and lints all *.sql files in the current working directory and
        all subdirectories.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint -Path ./stored_procedures -Recurse

        Lints all *.sql files in the stored_procedures directory and its subdirectories.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint -Path query.sql -Runtime Local

        Forces local SQLFluff execution and throws if local SQLFluff is unavailable.

    .EXAMPLE
        Invoke-SqlFluff -Mode lint -Path query.sql -Runtime Docker

        Forces Docker execution even if local SQLFluff is installed.

    .OUTPUTS
        System.Int32
            Returns the SQLFluff process exit code. 0 indicates success (no violations for
            lint, or successful fix/format). Non-zero indicates violations were found or
            an error occurred.

    .NOTES
        In Auto mode, if local SQLFluff is not found in PATH, Docker Desktop (or
        Docker Engine) must be installed and running. The sqlfluff/sqlfluff image
        is pulled from Docker Hub on first Docker use.
        See https://docs.sqlfluff.com/en/stable/configuration.html for config options.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Invoke-SqlFluff.ps1

    .LINK
        https://github.com/sqlfluff/sqlfluff

    .LINK
        https://docs.sqlfluff.com/en/stable/dialects.html

    .LINK
        https://hub.docker.com/r/sqlfluff/sqlfluff

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Invoke-SqlFluff.ps1
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Path')]
    [OutputType([System.Int32])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('lint', 'fix', 'format')]
        [String]$Mode,

        [Parameter(ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path,

        [Parameter(ParameterSetName = 'LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [String[]]$LiteralPath,

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [String]$ConfigPath = (Join-Path -Path $HOME -ChildPath '.sqlfluff'),

        [Parameter()]
        [ValidateSet(
            'ansi', 'athena', 'bigquery', 'clickhouse', 'databricks', 'db2',
            'duckdb', 'exasol', 'greenplum', 'hive', 'materialize', 'mysql',
            'oracle', 'postgres', 'redshift', 'snowflake', 'soql', 'sparksql',
            'sqlite', 'starrocks', 'teradata', 'trino', 'tsql', 'vertica'
        )]
        [String]$Dialect,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$ImageTag = 'latest',

        [Parameter()]
        [ValidateSet('Auto', 'Local', 'Docker')]
        [String]$Runtime = 'Auto',

        [Parameter()]
        [String[]]$AdditionalArgs
    )

    begin
    {
        $sqlFluffCommand = $null
        $dockerCommand = $null
        $useDockerRuntime = $false
        $effectiveDialect = $null

        switch ($Runtime)
        {
            'Local'
            {
                $sqlFluffCommand = Get-Command -Name 'sqlfluff' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
                Select-Object -First 1
                if (-not $sqlFluffCommand)
                {
                    throw 'SQLFluff is not installed or not available in PATH. Install SQLFluff or use -Runtime Docker.'
                }
                Write-Verbose "Runtime mode: Local (found at: $($sqlFluffCommand.Source))"
            }

            'Docker'
            {
                Write-Verbose 'Runtime mode: Docker (forced by -Runtime Docker)'
                $useDockerRuntime = $true
            }

            default
            {
                # Auto mode: prefer local SQLFluff, otherwise fall back to Docker.
                $sqlFluffCommand = Get-Command -Name 'sqlfluff' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
                Select-Object -First 1
                if ($sqlFluffCommand)
                {
                    Write-Verbose "Runtime mode: Auto (using local SQLFluff at: $($sqlFluffCommand.Source))"
                }
                else
                {
                    Write-Verbose 'Runtime mode: Auto (local SQLFluff not found; falling back to Docker)'
                    $useDockerRuntime = $true
                }
            }
        }

        if ($useDockerRuntime)
        {
            # Verify Docker is installed and available in PATH
            $dockerCommand = Get-Command -Name 'docker' -ErrorAction SilentlyContinue
            if (-not $dockerCommand)
            {
                throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
            }
            Write-Verbose "Docker found at: $($dockerCommand.Source)"

            # Verify the Docker daemon is running
            $global:LASTEXITCODE = 0
            & $dockerCommand.Name info *> $null
            if ($LASTEXITCODE -ne 0)
            {
                throw 'Docker is installed but the daemon is not running. Please start Docker Desktop (or the Docker service) and try again.'
            }
            Write-Verbose 'Docker daemon is running'

            # Build the Docker image reference with tag
            $imageRef = "sqlfluff/sqlfluff:${ImageTag}"
            Write-Verbose "Using image: $imageRef"
        }

        # Check if the config file exists. When explicitly provided via -ConfigPath,
        # throw on missing file. Otherwise, run without config and apply dialect
        # fallback logic below.
        $resolvedConfig = $null
        if (Test-Path -LiteralPath $ConfigPath -PathType Leaf)
        {
            $resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
            Write-Verbose "Config file resolved to: $resolvedConfig"
        }
        elseif ($PSBoundParameters.ContainsKey('ConfigPath'))
        {
            # User explicitly specified a config path that doesn't exist
            throw "Config file not found: $ConfigPath"
        }
        else
        {
            Write-Verbose "No config file found at default path '$ConfigPath'. Running without a config file."
        }

        if ($PSBoundParameters.ContainsKey('Dialect'))
        {
            $effectiveDialect = $Dialect
            Write-Verbose "Using dialect from -Dialect: $effectiveDialect"
        }
        elseif (-not $resolvedConfig)
        {
            $effectiveDialect = 'ansi'
            Write-Verbose "No config file and no -Dialect specified. Defaulting dialect to: $effectiveDialect"
        }

        # Resolve PWD to an absolute path for path normalization and Docker mounts
        $resolvedPwd = (Resolve-Path -LiteralPath $PWD.Path -ErrorAction Stop).Path
        $cwdPrefix = $resolvedPwd.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar

        # Windows paths are case-insensitive; Unix-like paths are case-sensitive.
        $pathComparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\')
        {
            [System.StringComparison]::OrdinalIgnoreCase
        }
        else
        {
            [System.StringComparison]::Ordinal
        }
    }

    process
    {
        # Determine which path input to use (wildcard-aware -Path or literal -LiteralPath)
        $inputPaths = @()
        $useLiteralPath = $PSBoundParameters.ContainsKey('LiteralPath')
        if ($useLiteralPath)
        {
            $inputPaths = @($LiteralPath)
        }
        elseif ($PSBoundParameters.ContainsKey('Path') -and $Path)
        {
            $inputPaths = @($Path)
        }

        # When no input path is provided, discover *.sql files in the working directory
        if ($inputPaths.Count -eq 0)
        {
            $gciParams = @{
                Path = $resolvedPwd
                Filter = '*.sql'
                File = $true
            }
            if ($Recurse)
            {
                $gciParams['Recurse'] = $true
            }

            $discovered = @(Get-ChildItem @gciParams)
            if ($discovered.Count -eq 0)
            {
                Write-Warning "No *.sql files found in '$resolvedPwd'$(if ($Recurse) { ' (recursive)' })."
                return
            }

            $inputPaths = $discovered.FullName
            Write-Verbose "Discovered $($inputPaths.Count) SQL file(s) in '$resolvedPwd'"
        }

        # Expand any directories in the input paths to their contained *.sql files
        $expandedPaths = @()
        foreach ($item in $inputPaths)
        {
            $resolvedItems = @()
            if ($useLiteralPath)
            {
                if (Test-Path -LiteralPath $item)
                {
                    $resolvedItems += (Resolve-Path -LiteralPath $item -ErrorAction Stop)
                }
                else
                {
                    throw "Cannot find path '$item' because it does not exist."
                }
            }
            else
            {
                $hasWildcard = [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($item)

                # For wildcard patterns with -Recurse, discover file matches recursively.
                # This enables patterns like '*.sql' to match files in subdirectories.
                if ($Recurse -and $hasWildcard)
                {
                    $recursiveMatches = @(Get-ChildItem -Path $item -File -Recurse -ErrorAction SilentlyContinue)
                    if ($recursiveMatches.Count -gt 0)
                    {
                        Write-Verbose "Discovered $($recursiveMatches.Count) file(s) from wildcard path '$item' recursively"
                        $expandedPaths += $recursiveMatches.FullName
                        continue
                    }
                }

                # -Path supports wildcard expansion; Resolve-Path may return multiple matches.
                # For unmatched wildcard patterns, Resolve-Path returns no results.
                $resolvedItems = @(Resolve-Path -Path $item -ErrorAction SilentlyContinue)
                if ($resolvedItems.Count -eq 0)
                {
                    if ($hasWildcard)
                    {
                        Write-Warning "No files matched path pattern '$item'$(if ($Recurse) { ' (recursive)' })."
                        continue
                    }

                    throw "Cannot find path '$item' because it does not exist."
                }
            }

            foreach ($resolvedItem in $resolvedItems)
            {
                $resolvedInputPath = $resolvedItem.Path
                if (Test-Path -LiteralPath $resolvedInputPath -PathType Container)
                {
                    $gciParams = @{
                        Path = $resolvedInputPath
                        Filter = '*.sql'
                        File = $true
                    }
                    if ($Recurse)
                    {
                        $gciParams['Recurse'] = $true
                    }

                    $dirFiles = @(Get-ChildItem @gciParams)
                    if ($dirFiles.Count -eq 0)
                    {
                        Write-Warning "No *.sql files found in directory '$resolvedInputPath'$(if ($Recurse) { ' (recursive)' })."
                    }
                    else
                    {
                        Write-Verbose "Discovered $($dirFiles.Count) SQL file(s) in '$resolvedInputPath'"
                        $expandedPaths += $dirFiles.FullName
                    }
                }
                else
                {
                    $expandedPaths += $resolvedInputPath
                }
            }
        }

        if ($expandedPaths.Count -eq 0)
        {
            return
        }

        foreach ($sqlFile in $expandedPaths)
        {
            # Resolve the SQL file path using -LiteralPath to handle special characters
            # (e.g., brackets in filenames like report[1].sql)
            $resolvedPath = Resolve-Path -LiteralPath $sqlFile -ErrorAction Stop
            $resolvedSqlPath = [System.IO.Path]::GetFullPath($resolvedPath.Path)
            $invokeCommandName = $null
            $invokeArgs = @()

            if ($useDockerRuntime)
            {
                # Ensure SQL file is inside the mounted working directory.
                $dockerSqlPath = $null
                if ($resolvedSqlPath.Equals($resolvedPwd, $pathComparison))
                {
                    $dockerSqlPath = '.'
                }
                elseif ($resolvedSqlPath.StartsWith($cwdPrefix, $pathComparison))
                {
                    $dockerSqlPath = $resolvedSqlPath.Substring($cwdPrefix.Length)
                }
                else
                {
                    throw "Path '$sqlFile' resolves to '$resolvedSqlPath', which is outside the current working directory '$resolvedPwd'. Change to the appropriate directory and try again."
                }

                # Convert backslashes to forward slashes for the Linux container.
                $dockerSqlPath = $dockerSqlPath.Replace('\', '/')
                Write-Verbose "SQL file resolved to: $dockerSqlPath"

                # Build volume mount strings as variables. PowerShell automatically wraps
                # arguments containing spaces in quotes when passing to native commands,
                # so paths like "OneDrive - Company Name" are handled correctly.
                $volSql = "${resolvedPwd}:/sql"

                # Build the argument list for docker run.
                # Use -i (interactive) without -t (TTY) to avoid TTY errors in
                # non-interactive environments such as CI pipelines and scheduled tasks.
                $dockerArgs = @('run', '-i', '--rm')
                $dockerArgs += @('-v', $volSql)

                # Mount the config file only when one was found
                if ($resolvedConfig)
                {
                    $volConfig = "${resolvedConfig}:/config/.sqlfluff"
                    $dockerArgs += @('-v', $volConfig)
                }

                $dockerArgs += $imageRef
                $dockerArgs += $Mode
                $dockerArgs += $dockerSqlPath

                # Pass --config only when a config file is mounted
                if ($resolvedConfig)
                {
                    $dockerArgs += @('--config', '/config/.sqlfluff')
                }

                # Append --dialect when explicitly provided, or default to ansi when
                # no config file is available.
                if ($effectiveDialect)
                {
                    $dockerArgs += @('--dialect', $effectiveDialect)
                }

                # Append any additional user-supplied arguments
                if ($AdditionalArgs)
                {
                    $dockerArgs += $AdditionalArgs
                    Write-Verbose "Additional args: $($AdditionalArgs -join ' ')"
                }

                $invokeCommandName = $dockerCommand.Name
                $invokeArgs = $dockerArgs
                Write-Verbose "Docker command: docker $($invokeArgs -join ' ')"
            }
            else
            {
                # Keep relative paths for files under the current directory and
                # absolute paths otherwise.
                $localSqlPath = $null
                if ($resolvedSqlPath.Equals($resolvedPwd, $pathComparison))
                {
                    $localSqlPath = '.'
                }
                elseif ($resolvedSqlPath.StartsWith($cwdPrefix, $pathComparison))
                {
                    $localSqlPath = $resolvedSqlPath.Substring($cwdPrefix.Length)
                }
                else
                {
                    $localSqlPath = $resolvedSqlPath
                }

                Write-Verbose "SQL file resolved to: $localSqlPath"

                $localArgs = @($Mode, $localSqlPath)

                # Pass --config when a config file is available.
                if ($resolvedConfig)
                {
                    $localArgs += @('--config', $resolvedConfig)
                }

                # Append --dialect when explicitly provided, or default to ansi when
                # no config file is available.
                if ($effectiveDialect)
                {
                    $localArgs += @('--dialect', $effectiveDialect)
                }

                # Append any additional user-supplied arguments
                if ($AdditionalArgs)
                {
                    $localArgs += $AdditionalArgs
                    Write-Verbose "Additional args: $($AdditionalArgs -join ' ')"
                }

                $invokeCommandName = $sqlFluffCommand.Name
                $invokeArgs = $localArgs
                Write-Verbose "SQLFluff command: $($invokeCommandName) $($invokeArgs -join ' ')"
            }

            # Gate state-changing operations (fix/format) behind ShouldProcess
            $shouldRun = $true
            if ($Mode -ne 'lint')
            {
                $shouldRun = $PSCmdlet.ShouldProcess($sqlFile, "SQLFluff $Mode")
            }

            if ($shouldRun)
            {
                $global:LASTEXITCODE = 0
                & $invokeCommandName @invokeArgs

                $exitCode = $LASTEXITCODE
                Write-Verbose "SQLFluff exited with code: $exitCode"

                if ($exitCode -ne 0 -and $Mode -eq 'lint')
                {
                    Write-Warning "SQLFluff found violations in '$sqlFile' (exit code: $exitCode)."
                }
                elseif ($exitCode -ne 0)
                {
                    Write-Warning "SQLFluff $Mode failed for '$sqlFile' (exit code: $exitCode)."
                }

                $exitCode
            }
        }
    }
}

# Create 'format-sql' alias only if it doesn't already exist
if (-not (Get-Command -Name 'format-sql' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'format-sql' alias for Invoke-SqlFluff"
        Set-Alias -Name 'format-sql' -Value 'Invoke-SqlFluff' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Invoke-SqlFluff: Could not create 'format-sql' alias: $($_.Exception.Message)"
    }
}
