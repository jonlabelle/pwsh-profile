function Invoke-Magika
{
    <#
    .SYNOPSIS
        Runs Magika file-type detection against files and folders.

    .DESCRIPTION
        Invoke-Magika supports three runtime modes:
        - Auto   : Prefer local Magika from PATH, then fall back to Docker.
        - Local  : Require and use local Magika only.
        - Docker : Require and use Docker only.

        By default, Auto mode is used.

        In Docker fallback mode, it mounts the current working directory into the
        container (read-only) and passes the specified paths and arguments.

        Path behavior:
        - By default (no path provided), the current working directory is scanned.
        - -Path supports wildcard expansion.
        - -LiteralPath treats wildcard characters literally.
        - In Docker fallback mode, paths must resolve inside the current working
          directory so they can be accessed via the container mount at /workspace.

    .PARAMETER Path
        One or more file or directory paths to analyze. Supports wildcard patterns
        (for example, *.ps1) and accepts pipeline input.

    .PARAMETER LiteralPath
        One or more literal file or directory paths to analyze. Unlike -Path,
        wildcard characters are treated literally.

    .PARAMETER ImageTag
        The Docker image tag to use for the jonlabelle/magika image. Defaults to
        'latest'. Use a specific version tag for reproducible results when running
        in Docker mode.

    .PARAMETER Runtime
        Controls how Magika is executed:
        - Auto   : Prefer local Magika from PATH, then fall back to Docker.
        - Local  : Use local Magika only and throw if not available.
        - Docker : Use Docker only and throw if Docker is not available.

    .PARAMETER AdditionalArgs
        Additional arguments to pass directly to the Magika command
        (for example, --json, --help, --verbose).

    .EXAMPLE
        Invoke-Magika -Path README.md

        Analyzes README.md and outputs Magika detection results.

    .EXAMPLE
        Invoke-Magika README.md

        Analyzes README.md using positional binding to -Path.

    .EXAMPLE
        Invoke-Magika -Path '*.ps1' -AdditionalArgs '--json'

        Analyzes all PowerShell files in the current directory and returns JSON
        output from Magika.

    .EXAMPLE
        Invoke-Magika -LiteralPath 'report[1].txt'

        Analyzes a file whose name contains wildcard characters.

    .EXAMPLE
        Get-ChildItem -Filter *.pdf | Invoke-Magika

        Analyzes all PDF files in the current directory via pipeline input.

    .EXAMPLE
        Invoke-Magika -AdditionalArgs '--help'

        Displays Magika help output.

    .EXAMPLE
        Invoke-Magika -Path . -ImageTag 'latest'

        Analyzes the current directory explicitly using the latest Docker image
        tag when Docker mode is used.

    .EXAMPLE
        Invoke-Magika -Path README.md -Runtime Local

        Forces local Magika execution and throws if local Magika is unavailable.

    .EXAMPLE
        Invoke-Magika -Path README.md -Runtime Docker

        Forces Docker execution even if local Magika is installed.

    .OUTPUTS
        System.Int32
            Returns the Magika process exit code. 0 indicates success.
            Non-zero indicates an error occurred.

    .NOTES
        In Auto mode, if local Magika is not found in PATH, Docker Desktop (or
        Docker Engine) must be installed and running. The jonlabelle/magika image
        is pulled from Docker Hub on first Docker use.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Invoke-Magika.ps1

    .LINK
        https://github.com/google/magika

    .LINK
        https://github.com/jonlabelle/docker-magika

    .LINK
        https://hub.docker.com/r/jonlabelle/magika

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Invoke-Magika.ps1
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([System.Int32])]
    param(
        [Parameter(ParameterSetName = 'Path', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path,

        [Parameter(ParameterSetName = 'LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [String[]]$LiteralPath,

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
        $magikaCommand = $null
        $dockerCommand = $null
        $useDockerFallback = $false

        switch ($Runtime)
        {
            'Local'
            {
                $magikaCommand = Get-Command -Name 'magika' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
                Select-Object -First 1
                if (-not $magikaCommand)
                {
                    throw 'Magika is not installed or not available in PATH. Install Magika or use -Runtime Docker.'
                }
                Write-Verbose "Runtime mode: Local (found at: $($magikaCommand.Source))"
            }

            'Docker'
            {
                Write-Verbose 'Runtime mode: Docker (forced by -Runtime Docker)'
                $useDockerFallback = $true
            }

            default
            {
                # Auto mode: prefer local Magika, otherwise fall back to Docker.
                $magikaCommand = Get-Command -Name 'magika' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
                Select-Object -First 1

                if ($magikaCommand)
                {
                    Write-Verbose "Runtime mode: Auto (using local Magika at: $($magikaCommand.Source))"
                }
                else
                {
                    Write-Verbose 'Runtime mode: Auto (local Magika not found; falling back to Docker)'
                    $useDockerFallback = $true
                }
            }
        }

        if ($useDockerFallback)
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
            $imageRef = "jonlabelle/magika:${ImageTag}"
            Write-Verbose "Using image: $imageRef"
        }

        # Resolve PWD to an absolute path for Docker mounts and path normalization
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

        # Default to current working directory when no path is provided
        if ($inputPaths.Count -eq 0)
        {
            $inputPaths = @('.')
        }

        # Resolve and normalize all input paths
        $targetPaths = @()
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
                # -Path supports wildcard expansion; Resolve-Path may return multiple matches
                $resolvedItems = @(Resolve-Path -Path $item -ErrorAction Stop)
            }

            foreach ($resolvedItem in $resolvedItems)
            {
                $resolvedInputPath = [System.IO.Path]::GetFullPath($resolvedItem.Path)

                if ($useDockerFallback)
                {
                    # Ensure resolved paths are inside the mounted working directory
                    if ($resolvedInputPath.Equals($resolvedPwd, $pathComparison))
                    {
                        $normalizedPath = '.'
                    }
                    elseif ($resolvedInputPath.StartsWith($cwdPrefix, $pathComparison))
                    {
                        $normalizedPath = $resolvedInputPath.Substring($cwdPrefix.Length)
                    }
                    else
                    {
                        throw "Path '$item' resolves to '$resolvedInputPath', which is outside the current working directory '$resolvedPwd'. Change to the appropriate directory and try again."
                    }

                    # Convert Windows separators for the Linux container path
                    $targetPaths += $normalizedPath.Replace('\', '/')
                }
                else
                {
                    # For local Magika execution, keep relative paths for files under
                    # the current directory and absolute paths otherwise.
                    if ($resolvedInputPath.Equals($resolvedPwd, $pathComparison))
                    {
                        $targetPaths += '.'
                    }
                    elseif ($resolvedInputPath.StartsWith($cwdPrefix, $pathComparison))
                    {
                        $targetPaths += $resolvedInputPath.Substring($cwdPrefix.Length)
                    }
                    else
                    {
                        $targetPaths += $resolvedInputPath
                    }

                    continue
                }
            }
        }

        $targetPaths = @($targetPaths | Select-Object -Unique)
        if ($targetPaths.Count -eq 0)
        {
            return
        }

        if ($useDockerFallback)
        {
            # Build volume mount and docker arguments
            $volWork = "${resolvedPwd}:/workspace:ro"
            $dockerArgs = @('run', '-i', '--rm')
            $dockerArgs += @('-v', $volWork)
            $dockerArgs += @('-w', '/workspace')
            $dockerArgs += $imageRef

            # Append any additional user-supplied arguments
            if ($AdditionalArgs)
            {
                $dockerArgs += $AdditionalArgs
                Write-Verbose "Additional args: $($AdditionalArgs -join ' ')"
            }

            # Append normalized path arguments
            $dockerArgs += $targetPaths

            Write-Verbose "Docker command: docker $($dockerArgs -join ' ')"

            $global:LASTEXITCODE = 0
            & $dockerCommand.Name @dockerArgs
        }
        else
        {
            $magikaArgs = @()

            if ($AdditionalArgs)
            {
                $magikaArgs += $AdditionalArgs
                Write-Verbose "Additional args: $($AdditionalArgs -join ' ')"
            }

            $magikaArgs += $targetPaths

            Write-Verbose "Magika command: $($magikaCommand.Name) $($magikaArgs -join ' ')"

            $global:LASTEXITCODE = 0
            & $magikaCommand.Name @magikaArgs
        }

        $exitCode = $LASTEXITCODE
        Write-Verbose "Magika exited with code: $exitCode"

        if ($exitCode -ne 0)
        {
            Write-Warning "Magika failed (exit code: $exitCode)."
        }

        $exitCode
    }
}
