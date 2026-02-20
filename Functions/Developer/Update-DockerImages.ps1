function Update-DockerImages
{
    <#
    .SYNOPSIS
        Pulls the latest versions of all local Docker images from their remote registries.

    .DESCRIPTION
        Inspects all locally available Docker images and attempts to pull the latest version
        for each image that has a remote registry reference (i.e., excludes locally-built images
        without a repository or those tagged as '<none>').

        Images are identified by their Repository:Tag combination. Each eligible image is pulled
        using 'docker pull', and results are reported as a summary object. Use -Verbose to see
        detailed progress for each image.

        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux. Requires
        Docker CLI to be installed and available in PATH.

    .PARAMETER Filter
        An optional wildcard pattern to filter which images to update. Only images whose
        Repository:Tag matches the pattern will be pulled. Supports standard PowerShell
        wildcard characters (*, ?, []).

    .PARAMETER ExcludeFilter
        An optional wildcard pattern to exclude images from updating. Images whose
        Repository:Tag matches this pattern will be skipped.

    .PARAMETER PruneDanglingImages
        When specified, runs 'docker image prune --force' after pulls complete to remove
        dangling images.

    .EXAMPLE
        PS > Update-DockerImages

        Pulls the latest version of every local Docker image that has a remote registry reference.

    .EXAMPLE
        PS > Update-DockerImages -Verbose

        Pulls the latest images with detailed progress output for each image.

    .EXAMPLE
        PS > Update-DockerImages -Filter 'mcr.microsoft.com/*'

        Only updates images from the Microsoft Container Registry.

    .EXAMPLE
        PS > Update-DockerImages -ExcludeFilter '*dev*'

        Updates all images except those with 'dev' in their name.

    .EXAMPLE
        PS > Update-DockerImages -PruneDanglingImages

        Updates eligible images, then prunes dangling Docker images.

    .OUTPUTS
        [PSCustomObject]
        Returns an object with summary information:
        - TotalImages    : Total number of local images found
        - Eligible       : Number of images eligible for pulling (with remote registry)
        - Updated        : Number of images successfully pulled
        - Skipped        : Number of images skipped (no repository or filtered out)
        - Failed         : Number of images that failed to pull
        - Results        : Array of per-image result objects with Image, Status, and Message
        - DanglingPruneRequested : $true when -PruneDanglingImages is specified
        - DanglingPruneSucceeded : $true when dangling image prune completed successfully
        - DanglingPruneError     : Error text when dangling image prune fails, otherwise $null

    .NOTES
        - Requires Docker CLI in PATH
        - Images tagged as '<none>' are automatically skipped
        - Locally-built images without a registry push will attempt a pull and may fail gracefully
        - Use -PruneDanglingImages to remove dangling images after updating

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Update-DockerImages.ps1

    .LINK
        https://docs.docker.com/reference/cli/docker/image/pull/

    .LINK
        https://docs.docker.com/reference/cli/docker/image/ls/

    .LINK
        https://docs.docker.com/reference/cli/docker/image/prune/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [String]$Filter,

        [Parameter()]
        [String]$ExcludeFilter,

        [Parameter()]
        [Switch]$PruneDanglingImages
    )

    begin
    {
        Write-Verbose 'Starting Docker image update'

        $dockerCommand = Get-Command -Name 'docker' -ErrorAction SilentlyContinue
        if (-not $dockerCommand)
        {
            throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
        }

        Write-Verbose "Docker found at: $($dockerCommand.Source)"
    }

    process
    {
        # Get all local images in JSON format for reliable parsing
        $imageJson = & docker image ls --format '{{json .}}' 2>&1

        if ($LASTEXITCODE -ne 0)
        {
            throw "Failed to list Docker images: $imageJson"
        }

        $images = @()
        foreach ($line in $imageJson)
        {
            $trimmed = "$line".Trim()
            if ($trimmed -and $trimmed.StartsWith('{'))
            {
                try
                {
                    $images += $trimmed | ConvertFrom-Json
                }
                catch
                {
                    Write-Verbose "Skipping unparseable line: $trimmed"
                }
            }
        }

        Write-Verbose "Found $($images.Count) local Docker image(s)"

        # Deduplicate by Repository:Tag so we don't pull the same image twice
        $seen = @{}
        $uniqueImages = @()
        foreach ($img in $images)
        {
            $repo = $img.Repository
            $tag = $img.Tag

            # Skip images with no repository or tag
            if ([string]::IsNullOrWhiteSpace($repo) -or $repo -eq '<none>')
            {
                continue
            }
            if ([string]::IsNullOrWhiteSpace($tag) -or $tag -eq '<none>')
            {
                continue
            }

            $imageRef = '{0}:{1}' -f $repo, $tag
            if (-not $seen.ContainsKey($imageRef))
            {
                $seen[$imageRef] = $true
                $uniqueImages += [PSCustomObject]@{
                    Repository = $repo
                    Tag = $tag
                    ImageRef = $imageRef
                }
            }
        }

        Write-Verbose "$($uniqueImages.Count) unique image(s) with valid repository and tag"

        # Apply filters
        $eligibleImages = $uniqueImages
        if ($Filter)
        {
            $eligibleImages = @($eligibleImages | Where-Object { $_.ImageRef -like $Filter })
            Write-Verbose "$($eligibleImages.Count) image(s) matching filter '$Filter'"
        }
        if ($ExcludeFilter)
        {
            $eligibleImages = @($eligibleImages | Where-Object { $_.ImageRef -notlike $ExcludeFilter })
            Write-Verbose "$($eligibleImages.Count) image(s) after exclude filter '$ExcludeFilter'"
        }

        $totalImages = $images.Count
        $skippedCount = $totalImages - $eligibleImages.Count
        $updatedCount = 0
        $failedCount = 0
        $results = @()
        $danglingPruneSucceeded = $false
        $danglingPruneError = $null

        if ($eligibleImages.Count -eq 0)
        {
            Write-Verbose 'No eligible images to update'
        }

        foreach ($img in $eligibleImages)
        {
            $imageRef = $img.ImageRef

            if (-not $PSCmdlet.ShouldProcess($imageRef, 'Pull latest image'))
            {
                $skippedCount++
                $results += [PSCustomObject]@{
                    Image = $imageRef
                    Status = 'Skipped'
                    Message = 'Skipped by -WhatIf'
                }
                continue
            }

            Write-Verbose "Pulling $imageRef..."

            try
            {
                $pullOutput = & docker pull $imageRef 2>&1
                if ($LASTEXITCODE -eq 0)
                {
                    $statusMessage = 'Updated'

                    # Check if the image was already up to date
                    $outputText = $pullOutput -join "`n"
                    if ($outputText -match 'Image is up to date|Already exists')
                    {
                        $statusMessage = 'Already up to date'
                    }

                    $updatedCount++
                    $results += [PSCustomObject]@{
                        Image = $imageRef
                        Status = 'Success'
                        Message = $statusMessage
                    }

                    Write-Verbose "$imageRef : $statusMessage"
                }
                else
                {
                    $failedCount++
                    $errorMessage = ($pullOutput | Where-Object { $_ }) -join ' '
                    $results += [PSCustomObject]@{
                        Image = $imageRef
                        Status = 'Failed'
                        Message = $errorMessage
                    }

                    Write-Warning "Failed to pull ${imageRef}: $errorMessage"
                }
            }
            catch
            {
                $failedCount++
                $results += [PSCustomObject]@{
                    Image = $imageRef
                    Status = 'Failed'
                    Message = $_.Exception.Message
                }

                Write-Warning "Error pulling ${imageRef}: $($_.Exception.Message)"
            }
        }

        if ($PruneDanglingImages)
        {
            if ($PSCmdlet.ShouldProcess('Dangling Docker images', 'Prune'))
            {
                Write-Verbose 'Pruning dangling Docker images...'

                try
                {
                    $pruneOutput = & docker image prune --force 2>&1
                    if ($LASTEXITCODE -eq 0)
                    {
                        $danglingPruneSucceeded = $true
                        Write-Verbose 'Dangling Docker image prune completed'
                    }
                    else
                    {
                        $danglingPruneError = ($pruneOutput | Where-Object { $_ }) -join ' '
                        if (-not $danglingPruneError)
                        {
                            $danglingPruneError = 'docker image prune failed with an unknown error.'
                        }
                        Write-Warning "Failed to prune dangling images: $danglingPruneError"
                    }
                }
                catch
                {
                    $danglingPruneError = $_.Exception.Message
                    Write-Warning "Error pruning dangling images: $danglingPruneError"
                }
            }
            else
            {
                Write-Verbose 'Skipping dangling Docker image prune due to -WhatIf'
            }
        }
    }

    end
    {
        $summary = [PSCustomObject]@{
            TotalImages = $totalImages
            Eligible = $eligibleImages.Count
            Updated = $updatedCount
            Skipped = $skippedCount
            Failed = $failedCount
            Results = $results
            DanglingPruneRequested = $PruneDanglingImages.IsPresent
            DanglingPruneSucceeded = $danglingPruneSucceeded
            DanglingPruneError = $danglingPruneError
        }

        Write-Verbose "Update complete: $updatedCount updated, $failedCount failed, $skippedCount skipped"

        $summary
    }
}
