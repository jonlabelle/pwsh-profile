function Remove-DockerArtifacts
{
    <#
    .SYNOPSIS
        Cleans up unused Docker artifacts with safety controls.

    .DESCRIPTION
        Removes unused Docker images, networks, build cache, and (optionally) stopped containers and volumes.
        Supports -WhatIf/-Confirm and lets you choose between pruning all unused images or only dangling ones.
        For -WhatIf, EstimatedReclaimable is calculated by scanning unused images so you know what would be freed.

        By default:
        - Unused images (not just dangling) are pruned
        - Unused networks and build cache are pruned
        - Stopped containers are NOT removed unless -IncludeStoppedContainers is specified
        - Volumes are NOT removed unless -IncludeVolumes is specified

        Cross-platform compatible with PowerShell 5.1+ on Windows, macOS, and Linux. Requires Docker CLI
        to be installed and available in PATH.

    .PARAMETER IncludeStoppedContainers
        Also remove stopped containers. When specified, cleanup uses 'docker system prune' to mirror Docker's
        built-in behavior (including images, networks, build cache, and optionally volumes).

    .PARAMETER DanglingImagesOnly
        Restrict image pruning to dangling images only (same as omitting '--all'). By default, all unused
        images are pruned to maximize reclaimed space.

    .PARAMETER IncludeVolumes
        Also prune unused volumes. Volumes can hold data you care about; use -WhatIf or -Confirm first if unsure.

    .EXAMPLE
        PS > Remove-DockerArtifacts
        PS > # Unused images (all), networks, and build cache pruned; containers and volumes untouched

        Runs a safe cleanup that leaves stopped containers and volumes alone while reclaiming image, network,
        and build cache space.

    .EXAMPLE
        PS > Remove-DockerArtifacts -IncludeStoppedContainers -IncludeVolumes

        Performs a full 'docker system prune --all --volumes', removing stopped containers, unused images,
        networks, build cache, and unused volumes.

    .EXAMPLE
        PS > Remove-DockerArtifacts -DanglingImagesOnly -IncludeStoppedContainers

        Mirrors 'docker system prune' default behavior: removes stopped containers, dangling images, unused
        networks, and build cache while keeping non-dangling unused images.

    .EXAMPLE
        PS > Remove-DockerArtifacts -IncludeStoppedContainers -WhatIf

        Shows what a full system prune would remove without actually deleting anything.

    .EXAMPLE
        PS > Remove-DockerArtifacts -IncludeVolumes -Confirm

        Prompts for confirmation before removing unused volumes along with images, networks, and build cache.

    .OUTPUTS
        [PSCustomObject]
        Returns an object with summary information:
        - ContainersPruned      : $true if stopped containers were included
        - VolumesPruned         : $true if volumes were included
        - ImageMode             : 'AllUnused' or 'DanglingOnly'
        - EstimatedReclaimable  : What could be reclaimed (unused images) when running with -WhatIf
        - TotalSpaceFreed       : Total space freed based on prune output (formatted string)
        - Errors                : Number of errors encountered

    .NOTES
        - Requires Docker CLI
        - Respects -WhatIf and -Confirm for safety
        - When -IncludeStoppedContainers is not used, pruning is composed of targeted image/network/builder
          commands to avoid touching containers

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Remove-DockerArtifacts.ps1

    .LINK
        https://docs.docker.com/reference/cli/docker/system/prune/

    .LINK
        https://docs.docker.com/reference/cli/docker/volume/prune/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [Switch]$IncludeStoppedContainers,

        [Parameter()]
        [Switch]$DanglingImagesOnly,

        [Parameter()]
        [Switch]$IncludeVolumes
    )

    begin
    {
        Write-Verbose 'Starting Docker artifacts cleanup'

        $stats = @{
            ContainersPruned = $false
            VolumesPruned = $false
            ImageMode = if ($DanglingImagesOnly) { 'DanglingOnly' } else { 'AllUnused' }
            SpaceFreedBytes = [int64]0
            EstimatedReclaimableBytes = [int64]0
            EstimatedReclaimableEstimateSucceeded = $false
            Errors = 0
        }

        $dockerCommand = Get-Command -Name 'docker' -ErrorAction SilentlyContinue
        if (-not $dockerCommand)
        {
            throw 'Docker is not installed or not available in PATH. Please install Docker and try again.'
        }

        Write-Verbose "Docker found at: $($dockerCommand.Source)"

        function Convert-SizeStringToBytes
        {
            param([String]$SizeString)

            if ([string]::IsNullOrWhiteSpace($SizeString))
            {
                return [int64]0
            }

            $clean = $SizeString.Trim()
            $clean = $clean -replace '\(.*\)', '' -replace '\s+', ''

            if ($clean -match '^(?<Value>[0-9]+(?:\.[0-9]+)?)(?<Unit>[kmgtpe]?i?b)?$')
            {
                $value = [double]$matches['Value']
                $unit = $matches['Unit'].ToLower()
                switch ($unit)
                {
                    'kb' { return [int64]($value * 1KB) }
                    'kib' { return [int64]($value * 1KB) }
                    'mb' { return [int64]($value * 1MB) }
                    'mib' { return [int64]($value * 1MB) }
                    'gb' { return [int64]($value * 1GB) }
                    'gib' { return [int64]($value * 1GB) }
                    'tb' { return [int64]($value * 1TB) }
                    'tib' { return [int64]($value * 1TB) }
                    default { return [int64]$value }
                }
            }

            return [int64]0
        }

        function Format-ByteSize
        {
            param([int64]$Bytes)

            switch ($Bytes)
            {
                { $_ -ge 1TB } { '{0:N2} TB' -f ($_ / 1TB); break }
                { $_ -ge 1GB } { '{0:N2} GB' -f ($_ / 1GB); break }
                { $_ -ge 1MB } { '{0:N2} MB' -f ($_ / 1MB); break }
                { $_ -ge 1KB } { '{0:N2} KB' -f ($_ / 1KB); break }
                default { '{0} bytes' -f $_ }
            }
        }

        function Convert-ImageId
        {
            param([string]$Id)
            if ([string]::IsNullOrWhiteSpace($Id))
            {
                return $null
            }

            $trimmed = $Id.Trim()
            if ($trimmed.Length -gt 12)
            {
                return $trimmed.Substring(0, 12)
            }

            return $trimmed
        }

        function Get-UnusedImageEstimate
        {
            param([Switch]$DanglingOnly)

            try
            {
                $inUseIds = @()
                try
                {
                    $inUseIds = & $dockerCommand.Name ps -a --format '{{.ImageID}}' 2>&1 | Where-Object { $_ -and $_.Trim() -ne '' }
                }
                catch
                {
                    Write-Verbose "Failed to collect in-use container images: $($_.Exception.Message)"
                }

                $inUseSet = New-Object System.Collections.Generic.HashSet[string]
                foreach ($id in $inUseIds)
                {
                    $normalized = Convert-ImageId $id
                    if ($normalized) { $null = $inUseSet.Add($normalized) }
                }

                $imagesOutput = & $dockerCommand.Name image ls --format '{{json .}}' 2>&1
                $totalBytes = [int64]0
                $count = 0

                foreach ($line in $imagesOutput)
                {
                    if (-not $line -or $line.Trim() -eq '') { continue }
                    try
                    {
                        $img = $line | ConvertFrom-Json
                        $imageId = Convert-ImageId $img.ID
                        $isDangling = ($img.Repository -eq '<none>') -or ($img.Tag -eq '<none>')

                        if ($DanglingOnly -and -not $isDangling)
                        {
                            continue
                        }

                        $isInUse = $false
                        if ($imageId)
                        {
                            foreach ($inUse in $inUseSet)
                            {
                                if ($inUse -and ($imageId.StartsWith($inUse, [System.StringComparison]::OrdinalIgnoreCase) -or
                                        $inUse.StartsWith($imageId, [System.StringComparison]::OrdinalIgnoreCase)))
                                {
                                    $isInUse = $true
                                    break
                                }
                            }
                        }

                        if (-not $isInUse)
                        {
                            $count++
                            $totalBytes += Convert-SizeStringToBytes $img.Size
                        }
                    }
                    catch
                    {
                        Write-Verbose "Failed to parse docker image entry for estimation: $($_.Exception.Message)"
                    }
                }

                return [PSCustomObject]@{
                    Count = $count
                    Bytes = $totalBytes
                }
            }
            catch
            {
                Write-Verbose "Failed to estimate unused images: $($_.Exception.Message)"
                return [PSCustomObject]@{
                    Count = 0
                    Bytes = 0
                }
            }
        }

        function Invoke-DockerPrune
        {
            param(
                [String[]]$Arguments,
                [String]$Description
            )

            $reclaimedBytes = [int64]0
            if ($PSCmdlet.ShouldProcess('Docker daemon', $Description))
            {
                try
                {
                    $output = & $dockerCommand.Name @Arguments 2>&1
                    foreach ($line in $output)
                    {
                        if ($line -match 'Total reclaimed space:\s*(.+)$')
                        {
                            $reclaimedBytes = Convert-SizeStringToBytes $matches[1]
                            break
                        }
                    }
                }
                catch
                {
                    $stats.Errors++
                    Write-Warning "Failed to run 'docker $($Arguments -join ' ')': $($_.Exception.Message)"
                }
            }
            else
            {
                Write-Verbose "WhatIf: Would run 'docker $($Arguments -join ' ')'"
            }

            return $reclaimedBytes
        }
    }

    process
    {
        # Estimate unused image space by scanning unused images
        $estimate = Get-UnusedImageEstimate -DanglingOnly:$DanglingImagesOnly
        if ($estimate)
        {
            $stats.EstimatedReclaimableEstimateSucceeded = $true
            $stats.EstimatedReclaimableBytes = $estimate.Bytes
        }

        $reclaimedTotal = [int64]0

        if ($IncludeStoppedContainers)
        {
            $stats.ContainersPruned = $true
            $systemPruneArgs = @('system', 'prune', '--force')
            if (-not $DanglingImagesOnly)
            {
                $systemPruneArgs += '--all'
            }
            if ($IncludeVolumes)
            {
                $stats.VolumesPruned = $true
                $systemPruneArgs += '--volumes'
            }

            $reclaimedTotal += Invoke-DockerPrune -Arguments $systemPruneArgs -Description "docker $($systemPruneArgs -join ' ')"
        }
        else
        {
            $imageArgs = @('image', 'prune', '--force')
            if (-not $DanglingImagesOnly)
            {
                $imageArgs += '--all'
            }
            $reclaimedTotal += Invoke-DockerPrune -Arguments $imageArgs -Description "docker $($imageArgs -join ' ')"

            $networkArgs = @('network', 'prune', '--force')
            $reclaimedTotal += Invoke-DockerPrune -Arguments $networkArgs -Description "docker $($networkArgs -join ' ')"

            $builderArgs = @('builder', 'prune', '--force')
            if (-not $DanglingImagesOnly)
            {
                $builderArgs += '--all'
            }
            $reclaimedTotal += Invoke-DockerPrune -Arguments $builderArgs -Description "docker $($builderArgs -join ' ')"

            if ($IncludeVolumes)
            {
                $stats.VolumesPruned = $true
                $volumeArgs = @('volume', 'prune', '--force')
                $reclaimedTotal += Invoke-DockerPrune -Arguments $volumeArgs -Description "docker $($volumeArgs -join ' ')"
            }
        }
    }

    end
    {
        $stats.SpaceFreedBytes = $reclaimedTotal

        $isWhatIf = $WhatIfPreference -eq $true
        $estimateSucceeded = $stats.EstimatedReclaimableEstimateSucceeded -eq $true
        $estimatedDisplay = if (-not $estimateSucceeded)
        {
            'Unable to estimate (unknown)'
        }
        elseif ($stats.EstimatedReclaimableBytes -gt 0)
        {
            Format-ByteSize $stats.EstimatedReclaimableBytes
        }
        else
        {
            '0 bytes (nothing unused detected)'
        }

        $result = [PSCustomObject]@{
            ContainersPruned = $stats.ContainersPruned
            VolumesPruned = $stats.VolumesPruned
            ImageMode = $stats.ImageMode
            EstimatedReclaimable = $estimatedDisplay
            TotalSpaceFreed = Format-ByteSize $stats.SpaceFreedBytes
            Errors = $stats.Errors
        }

        Write-Host "`nDocker Cleanup Summary:" -ForegroundColor Cyan
        Write-Host "  Containers pruned : $($result.ContainersPruned)" -ForegroundColor White
        Write-Host "  Volumes pruned    : $($result.VolumesPruned)" -ForegroundColor White
        Write-Host "  Image mode        : $($result.ImageMode)" -ForegroundColor White

        Write-Host "  Estimated reclaimable: $($result.EstimatedReclaimable)" -ForegroundColor Yellow
        if ($isWhatIf)
        {
            Write-Host '  No changes made (WhatIf).' -ForegroundColor Yellow
        }

        Write-Host "  Space freed       : $($result.TotalSpaceFreed)" -ForegroundColor Green

        if ($result.Errors -gt 0)
        {
            Write-Host "  Errors            : $($result.Errors)" -ForegroundColor Red
        }

        Write-Verbose 'Docker cleanup completed'
        return $result
    }
}
