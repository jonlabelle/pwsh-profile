function Invoke-SqlFluff
{
    <#
    .SYNOPSIS
        Runs SQLFluff lint, fix, or format against SQL files using the official Docker image.

    .DESCRIPTION
        Invoke-SqlFluff is a wrapper around the SQLFluff Docker container that simplifies
        linting, fixing, and formatting SQL files from PowerShell. It mounts the current
        working directory and a configurable .sqlfluff configuration file into the container,
        then executes the specified SQLFluff mode against the target file.

        The function requires Docker to be installed and running. The sqlfluff/sqlfluff
        Docker image will be pulled automatically if not already present.

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
        input (including FileInfo objects from Get-ChildItem). Paths are resolved
        relative to the current working directory, which is mounted into the container
        at /sql.

        When a directory is provided, all *.sql files in that directory are processed.
        Use -Recurse to include subdirectories.

        When omitted entirely, the function discovers all *.sql files in the current
        working directory. Use -Recurse to include subdirectories.

    .PARAMETER Recurse
        When -Path is omitted or points to a directory, searches for *.sql files
        recursively in subdirectories. Has no effect when -Path points to file(s).

    .PARAMETER ConfigPath
        The local file system path to the .sqlfluff configuration file. This file is
        mounted into the container and passed via --config. Defaults to $HOME/.sqlfluff.

        When the config file is not found (and -ConfigPath was not explicitly specified),
        SQLFluff runs with its built-in defaults. You can still control behavior via
        -Dialect and -AdditionalArgs.

    .PARAMETER Dialect
        The SQL dialect to use for parsing. Overrides any dialect set in the config file.
        Common dialects include: ansi, tsql, mysql, postgres, bigquery, sparksql, sqlite,
        clickhouse, duckdb, hive, redshift, snowflake, soql, trino.

        For the full list, see https://docs.sqlfluff.com/en/stable/dialects.html

    .PARAMETER ImageTag
        The Docker image tag to use for the sqlfluff/sqlfluff image. Defaults to 'latest'.
        Use a specific version tag (e.g. '3.0.0') for reproducible results in CI pipelines.

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

    .OUTPUTS
        System.Int32
            Returns the Docker process exit code. 0 indicates success (no violations for
            lint, or successful fix/format). Non-zero indicates violations were found or
            an error occurred.

    .NOTES
        Requires Docker Desktop (or Docker Engine) to be installed and running.
        The sqlfluff/sqlfluff image is pulled from Docker Hub on first use.
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
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Int32])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('lint', 'fix', 'format')]
        [String]$Mode,

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path,

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
        [String[]]$AdditionalArgs
    )

    begin
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

        # Check if the config file exists. When explicitly provided via -ConfigPath,
        # throw on missing file. Otherwise, run without config using SQLFluff defaults.
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
            Write-Verbose "No config file found at default path '$ConfigPath'. Running with SQLFluff defaults."
        }

        # Resolve PWD to an absolute path for the Docker mount
        $resolvedPwd = $PWD.Path

        # Build the Docker image reference with tag
        $imageRef = "sqlfluff/sqlfluff:${ImageTag}"
        Write-Verbose "Using image: $imageRef"
    }

    process
    {
        # When no Path is provided, discover *.sql files in the working directory
        if (-not $PSBoundParameters.ContainsKey('Path') -and -not $Path)
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

            $Path = $discovered.FullName
            Write-Verbose "Discovered $($Path.Count) SQL file(s) in '$resolvedPwd'"
        }

        # Expand any directories in Path to their contained *.sql files
        $expandedPaths = @()
        foreach ($item in $Path)
        {
            if (Test-Path -LiteralPath $item -PathType Container)
            {
                $gciParams = @{
                    Path = $item
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
                    Write-Warning "No *.sql files found in directory '$item'$(if ($Recurse) { ' (recursive)' })."
                }
                else
                {
                    Write-Verbose "Discovered $($dirFiles.Count) SQL file(s) in '$item'"
                    $expandedPaths += $dirFiles.FullName
                }
            }
            else
            {
                $expandedPaths += $item
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

            # Build a clean relative path for the Linux container
            $normalizedPath = $resolvedPath.Path.Replace($resolvedPwd + [IO.Path]::DirectorySeparatorChar, '')
            # Convert any remaining backslashes to forward slashes for the Linux container
            $normalizedPath = $normalizedPath.Replace('\', '/')

            Write-Verbose "SQL file resolved to: $normalizedPath"

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
            $dockerArgs += $normalizedPath

            # Pass --config only when a config file is mounted
            if ($resolvedConfig)
            {
                $dockerArgs += @('--config', '/config/.sqlfluff')
            }

            # Append --dialect if specified
            if ($PSBoundParameters.ContainsKey('Dialect'))
            {
                $dockerArgs += @('--dialect', $Dialect)
                Write-Verbose "Using dialect: $Dialect"
            }

            # Append any additional user-supplied arguments
            if ($AdditionalArgs)
            {
                $dockerArgs += $AdditionalArgs
                Write-Verbose "Additional args: $($AdditionalArgs -join ' ')"
            }

            Write-Verbose "Docker command: docker $($dockerArgs -join ' ')"

            # Gate state-changing operations (fix/format) behind ShouldProcess
            $shouldRun = $true
            if ($Mode -ne 'lint')
            {
                $shouldRun = $PSCmdlet.ShouldProcess($sqlFile, "SQLFluff $Mode")
            }

            if ($shouldRun)
            {
                $global:LASTEXITCODE = 0
                & $dockerCommand.Name @dockerArgs

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
