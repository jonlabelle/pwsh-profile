function Invoke-BfgRepoCleaner
{
    <#
    .SYNOPSIS
        Runs BFG Repo-Cleaner against a Git repository.

    .DESCRIPTION
        Invoke-BfgRepoCleaner supports three runtime modes:
        - Auto   : Prefer local BFG from PATH, then fall back to Docker.
        - Local  : Require and use local BFG only.
        - Docker : Require and use Docker only.

        By default, Auto mode is used.

        In Docker mode, it mounts the current working directory into the container
        and passes the specified BFG options.

        BFG Repo-Cleaner is a simpler, faster alternative to git filter-branch for
        cleansing bad data out of your Git repository history. It protects your current
        commit by default - files in your HEAD commit are never modified, only their
        history is cleaned.

        Common operations:
        - Delete specific files from history
        - Remove folders from all commits
        - Strip blobs bigger than a given size
        - Replace sensitive text (passwords, API keys, etc.)

    .PARAMETER StripBlobsBiggerThan
        Removes all blobs bigger than the specified size from history. Use suffixes
        like K, M, G for kilobytes, megabytes, gigabytes (e.g. '100M', '1G', '500K').

    .PARAMETER StripBiggestBlobs
        Removes the N largest blobs from history, regardless of size. Specify an
        integer count (e.g. 100 to strip the 100 biggest blobs).

    .PARAMETER DeleteFiles
        Removes all files matching the specified glob expression from history. Uses
        standard glob syntax (e.g. 'passwords.txt', 'id_{dsa,rsa}', '*.zip').

    .PARAMETER DeleteFolders
        Removes all folders with the specified name from history (e.g. '.secrets',
        'node_modules').

    .PARAMETER ReplaceText
        Path to a text file containing replacement expressions. Each line should
        contain a pattern to match, optionally followed by '==>' and the replacement
        text. Lines can be prefixed with 'regex:' or 'glob:' for pattern matching.
        The file is passed directly to BFG in local mode or mounted into the
        container in Docker mode.

    .PARAMETER Repository
        The path to the Git repository (typically a bare mirror clone with .git suffix)
        relative to the current working directory. When omitted, BFG operates on the
        current directory.

    .PARAMETER NoBlobProtection
        Disables BFG's default protection of the HEAD commit. When specified, even
        files in the current commit can be modified. Use with caution.

    .PARAMETER ImageTag
        The Docker image tag to use for the jonlabelle/bfg image. Defaults to 'latest'.
        Use a specific version tag for reproducible results in Docker mode.

    .PARAMETER Runtime
        Controls how BFG is executed:
        - Auto   : Prefer local BFG from PATH, then fall back to Docker.
        - Local  : Use local BFG only and throw if not available.
        - Docker : Use Docker only and throw if Docker is not available.

    .PARAMETER AdditionalArgs
        Additional arguments to pass directly to the BFG command. Useful for advanced
        options not covered by the named parameters.

    .EXAMPLE
        Invoke-BfgRepoCleaner -StripBlobsBiggerThan 100M -Repository my-repo.git

        Removes all blobs bigger than 100MB from the repository history.

    .EXAMPLE
        Invoke-BfgRepoCleaner -DeleteFiles 'passwords.txt' -Repository my-repo.git

        Deletes all files named 'passwords.txt' from the repository history.

    .EXAMPLE
        Invoke-BfgRepoCleaner -DeleteFiles 'id_{dsa,rsa}' -Repository my-repo.git

        Deletes all files named 'id_dsa' or 'id_rsa' from the repository history.

    .EXAMPLE
        Invoke-BfgRepoCleaner -DeleteFolders '.secrets' -Repository my-repo.git

        Removes all folders named '.secrets' from the repository history.

    .EXAMPLE
        Invoke-BfgRepoCleaner -ReplaceText replacements.txt -Repository my-repo.git

        Replaces sensitive text in the repository history using patterns defined
        in replacements.txt. Example file format:
            PASSWORD1==>***REMOVED***
            api_key_12345==>***REMOVED***

    .EXAMPLE
        Invoke-BfgRepoCleaner -StripBiggestBlobs 10 -Repository my-repo.git

        Removes the 10 largest blobs from the repository history.

    .EXAMPLE
        Invoke-BfgRepoCleaner -StripBlobsBiggerThan 50M -NoBlobProtection -Repository my-repo.git

        Removes blobs bigger than 50MB including those in the current commit.

    .EXAMPLE
        Invoke-BfgRepoCleaner -DeleteFiles '*.zip' -Repository my-repo.git -ImageTag '1.15.0'

        Deletes all .zip files from history using a pinned image version.

    .EXAMPLE
        Invoke-BfgRepoCleaner -AdditionalArgs '--help'

        Displays the BFG Repo-Cleaner help text.

    .EXAMPLE
        Invoke-BfgRepoCleaner -StripBlobsBiggerThan 100M -Repository my-repo.git -Runtime Local

        Forces local BFG execution and throws if local BFG is unavailable.

    .EXAMPLE
        Invoke-BfgRepoCleaner -DeleteFiles '*.zip' -Repository my-repo.git -Runtime Docker

        Forces Docker execution even if local BFG is installed.

    .EXAMPLE
        Invoke-BfgRepoCleaner -DeleteFiles '*.env' -DeleteFolders 'node_modules' -Repository my-repo.git

        Combines multiple operations to delete .env files and node_modules folders.

    .OUTPUTS
        System.Int32
            Returns the BFG process exit code. 0 indicates success.
            Non-zero indicates an error occurred.

    .NOTES
        In Auto mode, if local BFG is not found in PATH, Docker Desktop (or
        Docker Engine) must be installed and running. The jonlabelle/bfg image
        is pulled from Docker Hub on first Docker use.

        BFG protects your current commit by default. Files in your HEAD commit are
        never modified - only their history is cleaned. Use -NoBlobProtection to
        override this behavior (not recommended).

        Typical workflow:
        1. git clone --mirror <repo-url>
        2. Invoke-BfgRepoCleaner -StripBlobsBiggerThan 100M -Repository repo.git
        3. cd repo.git
        4. git reflog expire --expire=now --all
        5. git gc --prune=now --aggressive
        6. git push --force-with-lease

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Invoke-BfgRepoCleaner.ps1

    .LINK
        https://rtyley.github.io/bfg-repo-cleaner/

    .LINK
        https://github.com/jonlabelle/docker-bfg

    .LINK
        https://hub.docker.com/r/jonlabelle/bfg

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Invoke-BfgRepoCleaner.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Int32])]
    param(
        [Parameter()]
        [ValidatePattern('^[0-9]+(B|K|M|G)$')]
        [String]$StripBlobsBiggerThan,

        [Parameter()]
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int32]$StripBiggestBlobs,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$DeleteFiles,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$DeleteFolders,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$ReplaceText,

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$Repository,

        [Parameter()]
        [Switch]$NoBlobProtection,

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
        $bfgCommand = $null
        $dockerCommand = $null
        $useDockerRuntime = $false

        switch ($Runtime)
        {
            'Local'
            {
                $bfgCommand = Get-Command -Name 'bfg' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
                Select-Object -First 1
                if (-not $bfgCommand)
                {
                    throw 'BFG Repo-Cleaner is not installed or not available in PATH. Install BFG or use -Runtime Docker.'
                }
                Write-Verbose "Runtime mode: Local (found at: $($bfgCommand.Source))"
            }

            'Docker'
            {
                Write-Verbose 'Runtime mode: Docker (forced by -Runtime Docker)'
                $useDockerRuntime = $true
            }

            default
            {
                # Auto mode: prefer local BFG, otherwise fall back to Docker.
                $bfgCommand = Get-Command -Name 'bfg' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
                Select-Object -First 1
                if ($bfgCommand)
                {
                    Write-Verbose "Runtime mode: Auto (using local BFG at: $($bfgCommand.Source))"
                }
                else
                {
                    Write-Verbose 'Runtime mode: Auto (local BFG not found; falling back to Docker)'
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
            $imageRef = "jonlabelle/bfg:${ImageTag}"
            Write-Verbose "Using image: $imageRef"
        }

        # Resolve PWD to an absolute path for path normalization and Docker mounts
        $resolvedPwd = $PWD.Path
    }

    process
    {
        # Resolve the replace-text file if specified
        $resolvedReplaceText = $null
        if ($PSBoundParameters.ContainsKey('ReplaceText'))
        {
            if (-not (Test-Path -LiteralPath $ReplaceText -PathType Leaf))
            {
                throw "Replace-text file not found: $ReplaceText"
            }
            $resolvedReplaceText = (Resolve-Path -LiteralPath $ReplaceText).Path
            Write-Verbose "Replace-text file resolved to: $resolvedReplaceText"
        }

        $replaceFileName = $null
        if ($resolvedReplaceText)
        {
            $replaceFileName = [System.IO.Path]::GetFileName($resolvedReplaceText)
        }

        # Build the BFG arguments
        $bfgArgs = @()
        if ($PSBoundParameters.ContainsKey('StripBlobsBiggerThan'))
        {
            $bfgArgs += @('--strip-blobs-bigger-than', $StripBlobsBiggerThan)
            Write-Verbose "Strip blobs bigger than: $StripBlobsBiggerThan"
        }

        if ($PSBoundParameters.ContainsKey('StripBiggestBlobs'))
        {
            $bfgArgs += @('--strip-biggest-blobs', $StripBiggestBlobs.ToString())
            Write-Verbose "Strip biggest blobs: $StripBiggestBlobs"
        }

        if ($PSBoundParameters.ContainsKey('DeleteFiles'))
        {
            $bfgArgs += @('--delete-files', $DeleteFiles)
            Write-Verbose "Delete files: $DeleteFiles"
        }

        if ($PSBoundParameters.ContainsKey('DeleteFolders'))
        {
            $bfgArgs += @('--delete-folders', $DeleteFolders)
            Write-Verbose "Delete folders: $DeleteFolders"
        }

        if ($resolvedReplaceText)
        {
            if ($useDockerRuntime)
            {
                $bfgArgs += @('--replace-text', "/config/${replaceFileName}")
                Write-Verbose "Replace text file: /config/${replaceFileName}"
            }
            else
            {
                $bfgArgs += @('--replace-text', $resolvedReplaceText)
                Write-Verbose "Replace text file: $resolvedReplaceText"
            }
        }

        if ($NoBlobProtection)
        {
            $bfgArgs += '--no-blob-protection'
            Write-Verbose 'Blob protection disabled'
        }

        # Append any additional user-supplied arguments
        if ($AdditionalArgs)
        {
            $bfgArgs += $AdditionalArgs
            Write-Verbose "Additional args: $($AdditionalArgs -join ' ')"
        }

        # Append the repository path if specified
        if ($PSBoundParameters.ContainsKey('Repository'))
        {
            $bfgArgs += $Repository
            Write-Verbose "Repository: $Repository"
        }

        $invokeCommandName = $null
        $invokeArgs = @()
        if ($useDockerRuntime)
        {
            # Build volume mount for the working directory
            $volWork = "${resolvedPwd}:/work"

            # Build the argument list for docker run
            $dockerArgs = @('run', '-i', '--rm')
            $dockerArgs += @('-v', $volWork)

            # Mount the replace-text file if specified
            if ($resolvedReplaceText)
            {
                $volReplace = "${resolvedReplaceText}:/config/${replaceFileName}"
                $dockerArgs += @('-v', $volReplace)
            }

            $dockerArgs += $imageRef
            $dockerArgs += $bfgArgs

            $invokeCommandName = $dockerCommand.Name
            $invokeArgs = $dockerArgs
            Write-Verbose "Docker command: docker $($invokeArgs -join ' ')"
        }
        else
        {
            $invokeCommandName = $bfgCommand.Name
            $invokeArgs = $bfgArgs
            Write-Verbose "BFG command: $($invokeCommandName) $($invokeArgs -join ' ')"
        }

        # Gate the operation behind ShouldProcess since BFG rewrites Git history
        $targetDescription = if ($PSBoundParameters.ContainsKey('Repository'))
        {
            $Repository
        }
        else
        {
            $resolvedPwd
        }

        if ($PSCmdlet.ShouldProcess($targetDescription, 'BFG Repo-Cleaner'))
        {
            $global:LASTEXITCODE = 0
            & $invokeCommandName @invokeArgs

            $exitCode = $LASTEXITCODE
            Write-Verbose "BFG exited with code: $exitCode"

            if ($exitCode -ne 0)
            {
                Write-Warning "BFG Repo-Cleaner failed (exit code: $exitCode)."
            }

            $exitCode
        }
    }
}

# Create 'bfg' alias only if it doesn't already exist
if (-not (Get-Command -Name 'bfg' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'bfg' alias for Invoke-BfgRepoCleaner"
        Set-Alias -Name 'bfg' -Value 'Invoke-BfgRepoCleaner' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Invoke-BfgRepoCleaner: Could not create 'bfg' alias: $($_.Exception.Message)"
    }
}
