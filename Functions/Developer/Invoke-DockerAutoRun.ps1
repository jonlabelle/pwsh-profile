function Invoke-DockerAutoRun
{
    <#
    .SYNOPSIS
        Auto-detects a project, generates a Dockerfile, then builds and runs a container.

    .DESCRIPTION
        Detects common project types (Node.js, Python, .NET, Go) from files in the target
        directory. If a Dockerfile does not exist, the function generates one automatically.
        Then it builds the image and runs a container.

        If a Dockerfile already exists, that Dockerfile is used by default. Use -ForceDockerfile
        to overwrite an existing Dockerfile with a generated template.

        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

        When generating a Dockerfile, is goes without saying that the generated content is a starting
        point and may need adjustments for your specific project needs. Always review generated
        Dockerfiles before using them in production.

    .PARAMETER Path
        Project directory path. Defaults to the current directory.

    .PARAMETER ProjectType
        Project type template to generate. Defaults to Auto detection.
        Ignored when Dockerfile already exists unless -ForceDockerfile is specified.

    .PARAMETER ImageName
        Docker image name to build. Defaults to '<folder-name>-dev'.

    .PARAMETER ContainerName
        Container name passed to docker run. Defaults to '<image-name>-container'.

    .PARAMETER Port
        Port to map host:container using '-p <Port>:<Port>'.
        Defaults to detected EXPOSE port from Dockerfile or project template.

    .PARAMETER BuildArgument
        One or more docker build arguments (KEY=VALUE).

    .PARAMETER EnvironmentVariable
        One or more docker run environment variables (KEY=VALUE).

    .PARAMETER VolumeMapping
        One or more docker run volume mappings ('hostPath:containerPath').

    .PARAMETER RunArgument
        Additional arguments passed to docker run before the image name.

    .PARAMETER ContainerCommand
        Optional command and args appended after the image name in docker run.

    .PARAMETER EnvFile
        Path to an environment file passed to docker run via '--env-file'.

    .PARAMETER Network
        Docker network name passed to docker run via '--network'.

    .PARAMETER ForceDockerfile
        Overwrites an existing Dockerfile with an auto-generated template.

    .PARAMETER GenerateOnly
        Only generate Dockerfile content and skip build/run.

    .PARAMETER NoRun
        Build the image but do not run a container.

    .PARAMETER NoCache
        Build with '--no-cache'.

    .PARAMETER Detached
        Runs the container in detached mode ('-d').

    .PARAMETER Interactive
        Runs the container in interactive mode with a TTY ('-it').
        Cannot be used with -Detached.

    .PARAMETER NoDockerIgnore
        Skips automatic .dockerignore generation when creating a Dockerfile.

    .EXAMPLE
        PS > Invoke-DockerAutoRun

        Auto-detects project type in the current directory, generates Dockerfile if needed,
        builds an image, and runs the container.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -Path ~/code/my-app -ImageName my-app -ContainerName my-app-dev -Port 8080

        Builds image 'my-app' and runs container 'my-app-dev' with port mapping 8080:8080.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -GenerateOnly -ProjectType Node

        Generates a Node.js Dockerfile template in the current directory and skips build/run.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -NoRun -BuildArgument 'NODE_ENV=production' -NoCache

        Builds the image with a build argument and no cache, but does not run the container.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -Path ~/code/api-with-dockerfile -ImageName api-local

        Uses the existing Dockerfile in the project (without regenerating), builds image
        'api-local', and runs a container.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -Path ~/code/legacy-app -ProjectType DotNet -ForceDockerfile -NoRun

        Replaces an existing Dockerfile with a generated .NET template and builds the image
        without starting a container.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -Path ~/code/web -Detached -Port 5173

        Runs the container in detached mode and maps host port 5173 to container port 5173.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -EnvironmentVariable 'ASPNETCORE_ENVIRONMENT=Development' -EnvironmentVariable 'LOG_LEVEL=Debug'

        Passes multiple environment variables to docker run via '-e'.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -VolumeMapping "$PWD:/app" -RunArgument '--pull=always'

        Mounts the current directory into the container and adds an extra docker run argument.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -ContainerCommand @('python', '-m', 'http.server', '9000') -Port 9000

        Overrides the container startup command and maps port 9000.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -Interactive -ContainerCommand 'sh'

        Starts the container in interactive mode with a TTY, launching a shell.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -EnvFile '.env.local' -Network 'my-network'

        Passes an env-file and joins the container to Docker network 'my-network'.

    .EXAMPLE
        PS > Invoke-DockerAutoRun -Path ~/code/service -WhatIf

        Previews Dockerfile generation/build/run actions without making changes.

    .OUTPUTS
        [PSCustomObject]
        Returns summary details for detection, Dockerfile generation, build, and run.

    .NOTES
        - Requires Docker CLI for build/run operations
        - Supports -WhatIf/-Confirm via ShouldProcess

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Invoke-DockerAutoRun.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [String]$Path = '.',

        [Parameter()]
        [ValidateSet('Auto', 'Node', 'Python', 'DotNet', 'Go')]
        [String]$ProjectType = 'Auto',

        [Parameter()]
        [String]$ImageName,

        [Parameter()]
        [String]$ContainerName,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [Int]$Port,

        [Parameter()]
        [Alias('BuildArgs')]
        [String[]]$BuildArgument,

        [Parameter()]
        [Alias('Env')]
        [String[]]$EnvironmentVariable,

        [Parameter()]
        [Alias('Volume')]
        [String[]]$VolumeMapping,

        [Parameter()]
        [Alias('RunArgs')]
        [String[]]$RunArgument,

        [Parameter()]
        [String[]]$ContainerCommand,

        [Parameter()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [String]$EnvFile,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$Network,

        [Parameter()]
        [Switch]$ForceDockerfile,

        [Parameter()]
        [Switch]$GenerateOnly,

        [Parameter()]
        [Switch]$NoRun,

        [Parameter()]
        [Switch]$NoCache,

        [Parameter()]
        [Switch]$Detached,

        [Parameter()]
        [Switch]$Interactive,

        [Parameter()]
        [Switch]$NoDockerIgnore
    )

    begin
    {
        function Convert-ToDockerJsonArray
        {
            param([String[]]$CommandParts)

            if (-not $CommandParts -or $CommandParts.Count -eq 0)
            {
                return '"sh", "-c", "echo No command configured"'
            }

            $escapedParts = @()
            foreach ($part in $CommandParts)
            {
                $safePart = "$part" -replace '\\', '\\\\' -replace '"', '\"'
                $escapedParts += ('"{0}"' -f $safePart)
            }

            return ($escapedParts -join ', ')
        }

        function Get-FirstFile
        {
            param(
                [String]$ProjectRoot,
                [String[]]$Names
            )

            foreach ($name in $Names)
            {
                $candidate = Join-Path -Path $ProjectRoot -ChildPath $name
                if (Test-Path -LiteralPath $candidate -PathType Leaf)
                {
                    return $candidate
                }
            }

            return $null
        }

        function Get-NodeCommand
        {
            param([String]$ProjectRoot)

            $commandParts = @('npm', 'start')
            $packageJsonPath = Join-Path -Path $ProjectRoot -ChildPath 'package.json'

            if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf))
            {
                return $commandParts
            }

            try
            {
                $packageJson = Get-Content -LiteralPath $packageJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $scriptNames = @()
                if ($packageJson.scripts)
                {
                    $scriptNames = @($packageJson.scripts.PSObject.Properties.Name)
                }

                if ($scriptNames -contains 'start')
                {
                    return @('npm', 'start')
                }
                if ($scriptNames -contains 'dev')
                {
                    return @('npm', 'run', 'dev')
                }
                if ($packageJson.main)
                {
                    return @('node', [String]$packageJson.main)
                }
            }
            catch
            {
                Write-Verbose "Unable to parse package.json. Falling back to 'npm start'."
            }

            return $commandParts
        }

        function Get-AutoDetectedProjectType
        {
            param([String]$ProjectRoot)

            if (Test-Path -LiteralPath (Join-Path -Path $ProjectRoot -ChildPath 'package.json') -PathType Leaf)
            {
                return 'Node'
            }

            $csproj = Get-ChildItem -Path $ProjectRoot -Filter '*.csproj' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($csproj)
            {
                return 'DotNet'
            }

            if ((Test-Path -LiteralPath (Join-Path -Path $ProjectRoot -ChildPath 'requirements.txt') -PathType Leaf) -or
                (Test-Path -LiteralPath (Join-Path -Path $ProjectRoot -ChildPath 'pyproject.toml') -PathType Leaf) -or
                (Test-Path -LiteralPath (Join-Path -Path $ProjectRoot -ChildPath 'Pipfile') -PathType Leaf))
            {
                return 'Python'
            }

            if (Test-Path -LiteralPath (Join-Path -Path $ProjectRoot -ChildPath 'go.mod') -PathType Leaf)
            {
                return 'Go'
            }

            return $null
        }

        function Get-DockerfileTemplate
        {
            param(
                [String]$Type,
                [String]$ProjectRoot
            )

            switch ($Type)
            {
                'Node'
                {
                    $nodeCommand = Get-NodeCommand -ProjectRoot $ProjectRoot
                    $dockerfile = @"
FROM node:lts-alpine
WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts || npm install --omit=dev --ignore-scripts

COPY . .

ENV NODE_ENV=production
EXPOSE 3000
CMD [$(Convert-ToDockerJsonArray -CommandParts $nodeCommand)]
"@

                    return [PSCustomObject]@{
                        Type = 'Node'
                        Port = 3000
                        Detection = 'Detected package.json (Node.js project)'
                        Dockerfile = $dockerfile
                    }
                }

                'Python'
                {
                    $requirementsPath = Join-Path -Path $ProjectRoot -ChildPath 'requirements.txt'
                    $pyprojectPath = Join-Path -Path $ProjectRoot -ChildPath 'pyproject.toml'
                    $mainScriptPath = Get-FirstFile -ProjectRoot $ProjectRoot -Names @('app.py', 'main.py', 'manage.py')

                    $pythonCommand = @('python', 'app.py')
                    if ($mainScriptPath)
                    {
                        $mainScriptName = Split-Path -Path $mainScriptPath -Leaf
                        if ($mainScriptName -eq 'manage.py')
                        {
                            $pythonCommand = @('python', 'manage.py', 'runserver', '0.0.0.0:8000')
                        }
                        else
                        {
                            $pythonCommand = @('python', $mainScriptName)
                        }
                    }
                    else
                    {
                        $pythonCommand = @('python', '-m', 'http.server', '8000')
                    }

                    $lines = @(
                        'FROM python:3-alpine'
                        'WORKDIR /app'
                        ''
                        'ENV PYTHONDONTWRITEBYTECODE=1'
                        'ENV PYTHONUNBUFFERED=1'
                        ''
                    )

                    if (Test-Path -LiteralPath $requirementsPath -PathType Leaf)
                    {
                        $lines += 'COPY requirements.txt ./'
                        $lines += 'RUN pip install --no-cache-dir -r requirements.txt'
                        $lines += ''
                    }

                    $lines += 'COPY . .'

                    if ((-not (Test-Path -LiteralPath $requirementsPath -PathType Leaf)) -and
                        (Test-Path -LiteralPath $pyprojectPath -PathType Leaf))
                    {
                        $lines += 'RUN pip install --no-cache-dir .'
                    }

                    $lines += ''
                    $lines += 'EXPOSE 8000'
                    $lines += ('CMD [{0}]' -f (Convert-ToDockerJsonArray -CommandParts $pythonCommand))

                    return [PSCustomObject]@{
                        Type = 'Python'
                        Port = 8000
                        Detection = 'Detected Python dependency/entry files'
                        Dockerfile = ($lines -join [Environment]::NewLine)
                    }
                }

                'DotNet'
                {
                    $csproj = Get-ChildItem -Path $ProjectRoot -Filter '*.csproj' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if (-not $csproj)
                    {
                        throw 'DotNet project type selected but no .csproj file was found.'
                    }

                    $relativeCsproj = $csproj.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/') -replace '\\', '/'
                    $dllName = '{0}.dll' -f [System.IO.Path]::GetFileNameWithoutExtension($csproj.Name)

                    $dockerfile = @"
# syntax=docker/dockerfile:1

############################################
# Build stage
############################################

FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src
COPY . .
RUN dotnet publish "$relativeCsproj" -c Release -o /app/publish /p:UseAppHost=false

############################################
# Runtime stage
############################################

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS runtime
WORKDIR /app

# Globalization support (ICU) + timezone data
# ICU is required for cultures, collation, casing, etc.
RUN apk add --no-cache icu-libs tzdata

# Enable full globalization (disable invariant mode)
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false \
    # Optional but commonly useful locale defaults
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    # ASP.NET Core in containers typically binds to 8080 by convention
    ASPNETCORE_URLS=http://+:8080

# (Optional) run as non-root
# RUN addgroup -S app && adduser -S app -G app
# USER app

COPY --from=build /app/publish .

# Standard non-root port
EXPOSE 8080

ENTRYPOINT ["dotnet", "$dllName"]
"@

                    return [PSCustomObject]@{
                        Type = 'DotNet'
                        Port = 8080
                        Detection = "Detected $($csproj.Name) (.NET project)"
                        Dockerfile = $dockerfile
                    }
                }

                'Go'
                {
                    $dockerfile = @'
FROM golang:alpine AS build
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/app .

FROM alpine:latest
WORKDIR /app
COPY --from=build /app/app /app/app
EXPOSE 8080
ENTRYPOINT ["/app/app"]
'@

                    return [PSCustomObject]@{
                        Type = 'Go'
                        Port = 8080
                        Detection = 'Detected go.mod (Go project)'
                        Dockerfile = $dockerfile
                    }
                }

                default
                {
                    throw "Unsupported project type '$Type'."
                }
            }
        }

        function Get-DockerfileExposedPort
        {
            param([String]$DockerfilePath)

            if (-not (Test-Path -LiteralPath $DockerfilePath -PathType Leaf))
            {
                return $null
            }

            try
            {
                $lines = Get-Content -LiteralPath $DockerfilePath -ErrorAction Stop
                foreach ($line in $lines)
                {
                    if ($line -match '^\s*EXPOSE\s+(?<Port>[0-9]{1,5})(?:\/[a-zA-Z]+)?\b')
                    {
                        return [Int]$matches['Port']
                    }
                }
            }
            catch
            {
                Write-Verbose "Failed to parse EXPOSE port from Dockerfile: $($_.Exception.Message)"
            }

            return $null
        }

        function Get-DockerIgnoreContent
        {
            param([String]$Type)

            $common = @(
                '# Version control'
                '.git'
                '.gitignore'
                ''
                '# Docker'
                'Dockerfile'
                'Dockerfile.*'
                '.dockerignore'
                'docker-compose*.yml'
                'compose*.yml'
                ''
                '# IDE / Editor'
                '.vscode'
                '.idea'
                '*.swp'
                '*.swo'
                '*~'
                ''
                '# OS'
                '.DS_Store'
                'Thumbs.db'
            )

            $projectSpecific = @()
            switch ($Type)
            {
                'Node'
                {
                    $projectSpecific = @(
                        ''
                        '# Node.js'
                        'node_modules'
                        'npm-debug.log*'
                        '.npm'
                        'coverage'
                        'dist'
                    )
                }
                'Python'
                {
                    $projectSpecific = @(
                        ''
                        '# Python'
                        '__pycache__'
                        '*.pyc'
                        '*.pyo'
                        '.venv'
                        'venv'
                        '.env'
                        '*.egg-info'
                        '.pytest_cache'
                        '.mypy_cache'
                    )
                }
                'DotNet'
                {
                    $projectSpecific = @(
                        ''
                        '# .NET'
                        'bin/'
                        'obj/'
                        '*.user'
                        '*.suo'
                        'TestResults'
                    )
                }
                'Go'
                {
                    $projectSpecific = @(
                        ''
                        '# Go'
                        'vendor/'
                        '*.exe'
                        '*.test'
                    )
                }
            }

            return ($common + $projectSpecific) -join [Environment]::NewLine
        }

        function Remove-ExistingContainer
        {
            [CmdletBinding(SupportsShouldProcess)]
            param(
                [String]$DockerExe,
                [String]$Name
            )

            $global:LASTEXITCODE = 0
            $existing = & $DockerExe ps -a --filter "name=^${Name}$" --format '{{.ID}}' 2>&1
            if ($LASTEXITCODE -ne 0 -or [String]::IsNullOrWhiteSpace("$existing"))
            {
                return $false
            }

            if ($PSCmdlet.ShouldProcess($Name, 'Remove existing Docker container'))
            {
                Write-Verbose "Container '$Name' already exists (ID: $existing). Removing..."
                $global:LASTEXITCODE = 0
                & $DockerExe rm -f $Name 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0)
                {
                    Write-Warning "Failed to remove existing container '$Name'. docker run may fail."
                    return $false
                }

                Write-Verbose "Removed existing container '$Name'."
                return $true
            }

            Write-Verbose "Skipped removing existing container '$Name'."
            return $false
        }
    }

    process
    {
        if ($Interactive -and $Detached)
        {
            throw 'The -Interactive and -Detached switches cannot be used together.'
        }

        $resolvedProjectPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop | Select-Object -First 1).ProviderPath
        if (-not (Test-Path -LiteralPath $resolvedProjectPath -PathType Container))
        {
            throw "Path is not a directory: $resolvedProjectPath"
        }

        $dockerfilePath = Join-Path -Path $resolvedProjectPath -ChildPath 'Dockerfile'
        $dockerfileExists = Test-Path -LiteralPath $dockerfilePath -PathType Leaf
        $generated = $false
        $dockerIgnoreGenerated = $false

        $effectiveProjectType = 'ExistingDockerfile'
        $detection = 'Existing Dockerfile found; using it for build/run. Use -ForceDockerfile to regenerate.'
        $detectedPort = $null

        if (-not ($dockerfileExists -and -not $ForceDockerfile))
        {
            $effectiveProjectType = $ProjectType
            if ($effectiveProjectType -eq 'Auto')
            {
                $effectiveProjectType = Get-AutoDetectedProjectType -ProjectRoot $resolvedProjectPath
                if (-not $effectiveProjectType)
                {
                    throw @'
Unable to auto-detect project type. Add a Dockerfile or include one of these markers:
- Node.js: package.json
- Python: requirements.txt, pyproject.toml, or Pipfile
- .NET: *.csproj
- Go: go.mod
'@
                }
            }

            $template = Get-DockerfileTemplate -Type $effectiveProjectType -ProjectRoot $resolvedProjectPath
            $detection = $template.Detection
            $detectedPort = $template.Port

            if ($PSCmdlet.ShouldProcess($dockerfilePath, 'Write generated Dockerfile'))
            {
                $template.Dockerfile | Set-Content -LiteralPath $dockerfilePath -Encoding UTF8
                $generated = $true
                $dockerfileExists = $true
            }

            $dockerIgnorePath = Join-Path -Path $resolvedProjectPath -ChildPath '.dockerignore'
            if (-not $NoDockerIgnore -and -not (Test-Path -LiteralPath $dockerIgnorePath -PathType Leaf))
            {
                if ($PSCmdlet.ShouldProcess($dockerIgnorePath, 'Write generated .dockerignore'))
                {
                    $ignoreContent = Get-DockerIgnoreContent -Type $effectiveProjectType
                    $ignoreContent | Set-Content -LiteralPath $dockerIgnorePath -Encoding UTF8
                    $dockerIgnoreGenerated = $true
                    Write-Verbose "Generated .dockerignore for $effectiveProjectType project."
                }
            }
        }
        else
        {
            $detectedPort = Get-DockerfileExposedPort -DockerfilePath $dockerfilePath
        }

        if (-not $dockerfileExists)
        {
            throw "Dockerfile was not found or created at: $dockerfilePath"
        }

        $imageNameToUse = $ImageName
        if ([String]::IsNullOrWhiteSpace($imageNameToUse))
        {
            $imageNameToUse = (Split-Path -Path $resolvedProjectPath -Leaf).ToLowerInvariant()
            $imageNameToUse = $imageNameToUse -replace '[^a-z0-9._-]', '-'
            if ([String]::IsNullOrWhiteSpace($imageNameToUse))
            {
                $imageNameToUse = 'app'
            }
            $imageNameToUse = "$imageNameToUse-dev"
        }

        $containerNameToUse = $ContainerName
        if ([String]::IsNullOrWhiteSpace($containerNameToUse))
        {
            $containerNameToUse = $imageNameToUse -replace '[^a-zA-Z0-9_.-]', '-'
            $containerNameToUse = "$containerNameToUse-container"
        }

        $effectivePort = $detectedPort
        if ($PSBoundParameters.ContainsKey('Port'))
        {
            $effectivePort = $Port
        }

        $buildOutput = @()
        $runOutput = @()
        $buildExecuted = $false
        $runExecuted = $false
        $buildArgs = @()
        $runArgs = @()

        if (-not $GenerateOnly)
        {
            $dockerCommand = Get-Command -Name 'docker' -ErrorAction SilentlyContinue
            if (-not $dockerCommand)
            {
                throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
            }

            $buildArgs = @('build', '-f', $dockerfilePath, '-t', $imageNameToUse)
            if ($NoCache)
            {
                $buildArgs += '--no-cache'
            }
            foreach ($buildArg in $BuildArgument)
            {
                if (-not [String]::IsNullOrWhiteSpace($buildArg))
                {
                    $buildArgs += '--build-arg'
                    $buildArgs += $buildArg
                }
            }
            $buildArgs += $resolvedProjectPath

            if ($PSCmdlet.ShouldProcess($resolvedProjectPath, "Build Docker image '$imageNameToUse'"))
            {
                $global:LASTEXITCODE = 0
                $buildOutput = & $dockerCommand.Name @buildArgs 2>&1
                if ($LASTEXITCODE -ne 0)
                {
                    throw "Docker build failed: $($buildOutput -join [Environment]::NewLine)"
                }
                $buildExecuted = $true
            }

            if (-not $NoRun)
            {
                $runArgs = @('run', '--rm')
                if ($Detached)
                {
                    $runArgs += '-d'
                }
                if ($Interactive)
                {
                    $runArgs += '-i'
                    $runArgs += '-t'
                }

                if (-not [String]::IsNullOrWhiteSpace($containerNameToUse))
                {
                    # Remove existing container with the same name to avoid conflicts
                    Remove-ExistingContainer -DockerExe $dockerCommand.Name -Name $containerNameToUse | Out-Null

                    $runArgs += '--name'
                    $runArgs += $containerNameToUse
                }

                if ($effectivePort)
                {
                    $runArgs += '-p'
                    $runArgs += ('{0}:{1}' -f $effectivePort, $effectivePort)
                }

                if (-not [String]::IsNullOrWhiteSpace($EnvFile))
                {
                    $runArgs += '--env-file'
                    $runArgs += $EnvFile
                }

                if (-not [String]::IsNullOrWhiteSpace($Network))
                {
                    $runArgs += '--network'
                    $runArgs += $Network
                }

                foreach ($envSpec in $EnvironmentVariable)
                {
                    if (-not [String]::IsNullOrWhiteSpace($envSpec))
                    {
                        $runArgs += '-e'
                        $runArgs += $envSpec
                    }
                }

                foreach ($volumeSpec in $VolumeMapping)
                {
                    if (-not [String]::IsNullOrWhiteSpace($volumeSpec))
                    {
                        $runArgs += '-v'
                        $runArgs += $volumeSpec
                    }
                }

                foreach ($arg in $RunArgument)
                {
                    if (-not [String]::IsNullOrWhiteSpace($arg))
                    {
                        $runArgs += $arg
                    }
                }

                $runArgs += $imageNameToUse

                foreach ($containerArg in $ContainerCommand)
                {
                    if (-not [String]::IsNullOrWhiteSpace($containerArg))
                    {
                        $runArgs += $containerArg
                    }
                }

                if ($PSCmdlet.ShouldProcess($imageNameToUse, "Run Docker container '$containerNameToUse'"))
                {
                    $global:LASTEXITCODE = 0
                    $runOutput = & $dockerCommand.Name @runArgs 2>&1
                    if ($LASTEXITCODE -ne 0)
                    {
                        throw "Docker run failed: $($runOutput -join [Environment]::NewLine)"
                    }
                    $runExecuted = $true
                }
            }
        }

        return [PSCustomObject]@{
            ProjectPath = $resolvedProjectPath
            ProjectType = $effectiveProjectType
            Detection = $detection
            DockerfilePath = $dockerfilePath
            DockerfileGenerated = $generated
            DockerIgnoreGenerated = $dockerIgnoreGenerated
            ImageName = $imageNameToUse
            ContainerName = if ($NoRun -or $GenerateOnly) { $null } else { $containerNameToUse }
            Port = $effectivePort
            BuildExecuted = $buildExecuted
            RunExecuted = $runExecuted
            Detached = [Bool]$Detached
            Interactive = [Bool]$Interactive
            BuildCommand = if ($buildArgs.Count -gt 0) { 'docker ' + ($buildArgs -join ' ') } else { $null }
            RunCommand = if ($runArgs.Count -gt 0) { 'docker ' + ($runArgs -join ' ') } else { $null }
            BuildOutput = @($buildOutput)
            RunOutput = @($runOutput)
        }
    }
}
