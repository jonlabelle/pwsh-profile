function Invoke-GitPull
{
    <#
    .SYNOPSIS
        Performs a git pull with rebase on one or more Git repositories.

    .DESCRIPTION
        Updates Git repositories by performing 'git pull --rebase' on the specified paths.
        Supports multiple paths, recursive searching for Git repositories, and automatically
        skips directories that are not Git repositories.

        When using -Recurse, the function searches for directories containing a .git folder
        and performs the pull operation on each discovered repository.

        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux.

        Requires Git to be installed and available in PATH.

    .PARAMETER Path
        The path(s) to Git repositories or directories containing Git repositories.
        Defaults to the current directory.
        Supports ~ for home directory expansion.
        Accepts pipeline input and multiple paths.

        Without -Recurse: Each path must be within a Git repository.
        With -Recurse: Searches for Git repositories within each path.

    .PARAMETER Recurse
        Searches for Git repositories recursively within the specified Path(s) and pulls each one.
        Useful for workspace directories containing multiple Git repositories.

        Example use case: Update all projects in ~/Projects

    .PARAMETER Depth
        Maximum depth to search for Git repositories when using -Recurse.
        Default is unlimited. Use this to limit search depth in large directory trees.

    .PARAMETER NoRebase
        Performs a regular git pull without the --rebase option.
        By default, git pull --rebase is used to maintain a linear history.

    .PARAMETER Prune
        Adds the --prune flag to remove remote-tracking references that no longer exist on the remote.

    .PARAMETER Force
        Continue processing remaining repositories even if one fails.
        Without this, the function stops on the first error.

    .EXAMPLE
        PS > Invoke-GitPull

        Performs git pull --rebase on the Git repository in the current directory.

    .EXAMPLE
        PS > Invoke-GitPull -Path ~/Projects/MyRepo

        Performs git pull --rebase on the specified repository.

    .EXAMPLE
        PS > Invoke-GitPull -Path ~/Projects -Recurse

        Finds all Git repositories within ~/Projects and performs git pull --rebase on each one.

    .EXAMPLE
        PS > Invoke-GitPull -Path ~/Projects -Recurse -Depth 2

        Finds Git repositories within ~/Projects up to 2 levels deep.

    .EXAMPLE
        PS > Invoke-GitPull -Path @('~/Project1', '~/Project2')

        Performs git pull --rebase on multiple specified repositories.

    .EXAMPLE
        PS > Get-ChildItem ~/Projects -Directory | Invoke-GitPull

        Performs git pull --rebase on each directory piped in (if it's a Git repository).

    .EXAMPLE
        PS > Invoke-GitPull -NoRebase

        Performs a regular git pull without rebase on the current directory.

    .EXAMPLE
        PS > Invoke-GitPull -Path ~/Projects -Recurse -Prune

        Updates all repositories and prunes deleted remote-tracking branches.

    .EXAMPLE
        PS > Invoke-GitPull -Path ~/Projects -Recurse -Force

        Updates all repositories, continuing even if some fail.

    .EXAMPLE
        PS > Invoke-GitPull -Verbose

        Performs git pull --rebase with detailed verbose output.

    .OUTPUTS
        [PSCustomObject]
        Returns an object with summary information about the operation:
        - RepositoriesProcessed: Number of Git repositories processed
        - RepositoriesUpdated: Number of repositories successfully updated
        - RepositoriesSkipped: Number of directories skipped (not Git repositories)
        - RepositoriesFailed: Number of repositories that failed to update
        - Results: Array of per-repository results (when multiple repositories processed)

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Invoke-GitPull.ps1

        - Requires PowerShell 5.1 or later
        - Requires Git to be installed and available in PATH
        - Uses 'git pull --rebase' by default for cleaner history
        - With -Recurse: Finds .git directories to locate repositories
        - Non-Git directories are silently skipped (or reported with -Verbose)

    .LINK
        https://git-scm.com/docs/git-pull

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Invoke-GitPull.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path = (Get-Location).Path,

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$Depth,

        [Parameter()]
        [Switch]$NoRebase,

        [Parameter()]
        [Switch]$Prune,

        [Parameter()]
        [Switch]$Force
    )

    begin
    {
        Write-Verbose 'Starting Invoke-GitPull'

        # Check if Git is available
        $gitCommand = Get-Command -Name 'git' -ErrorAction SilentlyContinue
        if (-not $gitCommand)
        {
            throw 'Git is not installed or not found in PATH. Please install Git and try again.'
        }

        # Statistics tracking
        $stats = @{
            RepositoriesProcessed = 0
            RepositoriesUpdated = 0
            RepositoriesSkipped = 0
            RepositoriesFailed = 0
            RepositoriesAlreadyUpToDate = 0
        }

        $results = [System.Collections.ArrayList]::new()

        # Helper function to check if path is a Git repository
        function Test-GitRepository
        {
            param([String]$TestPath)

            $gitDir = Join-Path -Path $TestPath -ChildPath '.git'
            return Test-Path -Path $gitDir
        }

        # Helper function to perform git pull on a repository
        function Invoke-GitPullOnRepository
        {
            param(
                [String]$RepoPath,
                [Bool]$UseRebase,
                [Bool]$UsePrune,
                [Bool]$IsWhatIf
            )

            $repoName = Split-Path -Path $RepoPath -Leaf
            Write-Verbose "Processing repository: $RepoPath"

            # Build git arguments
            $gitArgs = @('pull')

            if ($UseRebase)
            {
                $gitArgs += '--rebase'
            }

            if ($UsePrune)
            {
                $gitArgs += '--prune'
            }

            $resultObj = [PSCustomObject]@{
                Path = $RepoPath
                Name = $repoName
                Success = $false
                HadUpdates = $false
                Message = ''
                Output = ''
            }

            if ($IsWhatIf)
            {
                $resultObj.Message = 'Would perform git pull'
                $resultObj.Success = $true
                return $resultObj
            }

            try
            {
                # Execute git pull using .NET Process class for reliable output capture
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = 'git'
                $psi.Arguments = $gitArgs -join ' '
                $psi.WorkingDirectory = $RepoPath
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.CreateNoWindow = $true

                $proc = New-Object System.Diagnostics.Process
                $proc.StartInfo = $psi

                $null = $proc.Start()
                $stdoutContent = $proc.StandardOutput.ReadToEnd()
                $stderrContent = $proc.StandardError.ReadToEnd()
                $proc.WaitForExit()

                $exitCode = $proc.ExitCode

                if ($exitCode -eq 0)
                {
                    $resultObj.Success = $true
                    $resultObj.Output = $stdoutContent.Trim()

                    if ([String]::IsNullOrWhiteSpace($stdoutContent) -or $stdoutContent -match 'Already up to date')
                    {
                        $resultObj.Message = 'Already up to date'
                        $resultObj.HadUpdates = $false
                        Write-Host "  [OK] $repoName (already up to date)" -ForegroundColor Green
                    }
                    else
                    {
                        $resultObj.Message = 'Updated successfully'
                        $resultObj.HadUpdates = $true
                        Write-Host "  [OK] $repoName (pulled updates)" -ForegroundColor Green
                    }
                }
                else
                {
                    $resultObj.Success = $false
                    $resultObj.Message = 'Pull failed'
                    $resultObj.Output = $stderrContent.Trim()

                    Write-Host "  [FAILED] $repoName - $($stderrContent.Trim())" -ForegroundColor Red
                }
            }
            catch
            {
                $resultObj.Success = $false
                $resultObj.Message = $_.Exception.Message
                $resultObj.Output = $_.Exception.Message

                Write-Host "  [ERROR] $repoName - $($_.Exception.Message)" -ForegroundColor Red
            }

            return $resultObj
        }

        # Helper function to find Git repositories recursively
        function Find-GitRepositories
        {
            param(
                [String]$SearchPath,
                [Int]$MaxDepth = -1
            )

            $repos = [System.Collections.ArrayList]::new()

            # Check if the search path itself is a repository
            if (Test-GitRepository -TestPath $SearchPath)
            {
                $null = $repos.Add($SearchPath)
                return $repos
            }

            # Search for .git directories
            $getChildItemParams = @{
                Path = $SearchPath
                Filter = '.git'
                Directory = $true
                Force = $true
                Recurse = $true
                ErrorAction = 'SilentlyContinue'
            }

            if ($MaxDepth -gt 0)
            {
                $getChildItemParams.Depth = $MaxDepth
            }

            $gitDirs = Get-ChildItem @getChildItemParams

            foreach ($gitDir in $gitDirs)
            {
                $repoPath = Split-Path -Path $gitDir.FullName -Parent
                $null = $repos.Add($repoPath)
            }

            return $repos
        }

        # Collection to accumulate paths from pipeline
        $allPaths = [System.Collections.ArrayList]::new()
    }

    process
    {
        foreach ($currentPath in $Path)
        {
            $null = $allPaths.Add($currentPath)
        }
    }

    end
    {
        $useRebase = -not $NoRebase.IsPresent

        Write-Host 'Git Pull Operation' -ForegroundColor Cyan
        Write-Host ('-' * 40) -ForegroundColor DarkGray

        foreach ($currentPath in $allPaths)
        {
            # Normalize path (expand ~ and resolve)
            $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($currentPath)

            if (-not (Test-Path -Path $resolvedPath))
            {
                Write-Warning "Path not found: $resolvedPath"
                $stats.RepositoriesSkipped++
                continue
            }

            $item = Get-Item -Path $resolvedPath

            if (-not $item.PSIsContainer)
            {
                Write-Warning "Path is not a directory: $resolvedPath"
                $stats.RepositoriesSkipped++
                continue
            }

            if ($Recurse)
            {
                # Find all Git repositories in the path
                $maxDepth = if ($PSBoundParameters.ContainsKey('Depth')) { $Depth } else { -1 }
                $repositories = Find-GitRepositories -SearchPath $resolvedPath -MaxDepth $maxDepth

                if ($repositories.Count -eq 0)
                {
                    Write-Verbose "No Git repositories found in: $resolvedPath"
                    continue
                }

                Write-Host "Found $($repositories.Count) Git repositor$(if ($repositories.Count -eq 1) { 'y' } else { 'ies' }) in: $resolvedPath" -ForegroundColor Cyan

                foreach ($repoPath in $repositories)
                {
                    if ($PSCmdlet.ShouldProcess($repoPath, 'git pull'))
                    {
                        $result = Invoke-GitPullOnRepository -RepoPath $repoPath -UseRebase $useRebase -UsePrune $Prune.IsPresent -IsWhatIf $WhatIfPreference

                        $stats.RepositoriesProcessed++

                        if ($result.Success)
                        {
                            $stats.RepositoriesUpdated++
                            if (-not $result.HadUpdates)
                            {
                                $stats.RepositoriesAlreadyUpToDate++
                            }
                        }
                        else
                        {
                            $stats.RepositoriesFailed++

                            if (-not $Force)
                            {
                                Write-Error "Failed to update repository '$repoPath': $($result.Message)"
                                break
                            }
                        }

                        $null = $results.Add($result)
                    }
                }
            }
            else
            {
                # Single repository mode
                if (-not (Test-GitRepository -TestPath $resolvedPath))
                {
                    Write-Verbose "Skipping non-Git directory: $resolvedPath"
                    $stats.RepositoriesSkipped++
                    continue
                }

                if ($PSCmdlet.ShouldProcess($resolvedPath, 'git pull'))
                {
                    $result = Invoke-GitPullOnRepository -RepoPath $resolvedPath -UseRebase $useRebase -UsePrune $Prune.IsPresent -IsWhatIf $WhatIfPreference

                    $stats.RepositoriesProcessed++

                    if ($result.Success)
                    {
                        $stats.RepositoriesUpdated++
                        if (-not $result.HadUpdates)
                        {
                            $stats.RepositoriesAlreadyUpToDate++
                        }
                    }
                    else
                    {
                        $stats.RepositoriesFailed++

                        if (-not $Force)
                        {
                            Write-Error "Failed to update repository '$resolvedPath': $($result.Message)"
                        }
                    }

                    $null = $results.Add($result)
                }
            }
        }

        # Summary
        Write-Host ''
        Write-Host 'Summary:' -ForegroundColor Cyan
        Write-Host "  Repositories processed: $($stats.RepositoriesProcessed)" -ForegroundColor Gray
        Write-Host "  Updated successfully:   $($stats.RepositoriesUpdated)" -ForegroundColor Green
        if ($stats.RepositoriesAlreadyUpToDate -gt 0)
        {
            Write-Host "  Already up to date:     $($stats.RepositoriesAlreadyUpToDate)" -ForegroundColor DarkGreen
        }
        if ($stats.RepositoriesSkipped -gt 0)
        {
            Write-Host "  Skipped (not Git):      $($stats.RepositoriesSkipped)" -ForegroundColor Yellow
        }
        if ($stats.RepositoriesFailed -gt 0)
        {
            Write-Host "  Failed:                 $($stats.RepositoriesFailed)" -ForegroundColor Red
        }

        # Return summary object
        $summary = [PSCustomObject]@{
            RepositoriesProcessed = $stats.RepositoriesProcessed
            RepositoriesUpdated = $stats.RepositoriesUpdated
            RepositoriesAlreadyUpToDate = $stats.RepositoriesAlreadyUpToDate
            RepositoriesSkipped = $stats.RepositoriesSkipped
            RepositoriesFailed = $stats.RepositoriesFailed
            Results = @($results)
        }

        Write-Verbose 'Invoke-GitPull completed'

        return $summary
    }
}
