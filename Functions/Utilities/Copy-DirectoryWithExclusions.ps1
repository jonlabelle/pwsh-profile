function Copy-DirectoryWithExclusions
{
    <#
    .SYNOPSIS
        Copies a directory recursively with the ability to exclude specific directories.

    .DESCRIPTION
        Copies all files and directories from a source path to a destination path recursively.
        Provides the ability to exclude specific directories (e.g., .git, node_modules, bin, obj)
        from the copy operation. This is cross-platform compatible with PowerShell 5.1+ and
        PowerShell Core 6.2+.

    .PARAMETER Source
        The source directory path to copy from. Supports relative paths and tilde (~) expansion.

    .PARAMETER Destination
        The destination directory path to copy to. Will be created if it doesn't exist.
        Supports relative paths and tilde (~) expansion.

    .PARAMETER ExcludeDirectories
        An array of directory names to exclude from the copy operation. Directory names are
        matched case-insensitively. Common examples include: .git, node_modules, bin, obj,
        .vs, .vscode, packages, dist, build, out.

    .PARAMETER Force
        If specified, overwrites existing files at the destination without prompting.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs without actually performing the copy operation.

    .PARAMETER Confirm
        Prompts for confirmation before copying files.

    .EXAMPLE
        PS > Copy-DirectoryWithExclusions -Source '.\MyProject' -Destination 'C:\Backup\MyProject' -ExcludeDirectories '.git', 'node_modules'

        Copies the MyProject directory to C:\Backup\MyProject, excluding .git and node_modules directories.

    .EXAMPLE
        PS > Copy-DirectoryWithExclusions -Source 'C:\Dev\Project' -Destination 'D:\Archive\Project' -ExcludeDirectories 'bin', 'obj', '.vs' -Force

        Copies the project directory excluding build artifacts, overwriting existing files without prompting.

    .EXAMPLE
        PS > Copy-DirectoryWithExclusions -Source '~/Documents/Code' -Destination '~/Backup/Code' -ExcludeDirectories '.git', 'dist', 'build'

        Copies the Code directory from Documents to Backup, excluding version control and build directories.
        Uses tilde expansion which works cross-platform.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns an object with TotalFiles, TotalDirectories, ExcludedDirectories, and Duration properties.

    .NOTES
        Cross-platform compatible with PowerShell 5.1+ and PowerShell Core 6.2+.
        Uses .NET methods for path resolution to ensure cross-platform compatibility.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$Source,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [String]$Destination,

        [Parameter(Position = 2)]
        [ValidateNotNullOrEmpty()]
        [String[]]$ExcludeDirectories = @(),

        [Parameter()]
        [Switch]$Force
    )

    begin
    {
        Write-Verbose 'Starting Copy-DirectoryWithExclusions'

        # Resolve paths to absolute paths (cross-platform compatible)
        $Source = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Source)
        $Destination = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)

        Write-Verbose "Resolved source path: $Source"
        Write-Verbose "Resolved destination path: $Destination"

        # Validate source exists
        if (-not (Test-Path -Path $Source -PathType Container))
        {
            throw "Source directory does not exist: $Source"
        }

        # Create destination if it doesn't exist
        if (-not (Test-Path -Path $Destination))
        {
            if ($PSCmdlet.ShouldProcess($Destination, 'Create destination directory'))
            {
                Write-Verbose "Creating destination directory: $Destination"
                New-Item -Path $Destination -ItemType Directory -Force | Out-Null
            }
        }

        # Initialize counters
        $script:FilesCopied = 0
        $script:DirectoriesCreated = 0
        $script:DirectoriesExcluded = 0

        # Convert exclude list to lowercase for case-insensitive comparison
        $ExcludeLower = $ExcludeDirectories | ForEach-Object { $_.ToLowerInvariant() }

        Write-Verbose "Excluding directories: $($ExcludeDirectories -join ', ')"

        $StartTime = Get-Date
    }

    process
    {
        # Recursive function to copy directory contents
        function Copy-DirectoryRecursive
        {
            param(
                [String]$SourcePath,
                [String]$DestPath,
                [String[]]$Exclude
            )

            Write-Verbose "Processing directory: $SourcePath"

            # Get all items in current directory, excluding directories up front for performance
            try
            {
                # Get all items first
                $AllItems = Get-ChildItem -Path $SourcePath -Force -ErrorAction Stop

                # Separate files and directories, filtering excluded directories immediately
                $Files = $AllItems | Where-Object { -not $_.PSIsContainer }
                $Directories = $AllItems | Where-Object {
                    $_.PSIsContainer -and ($Exclude -notcontains $_.Name.ToLowerInvariant())
                }

                # Count excluded directories for reporting
                $ExcludedCount = ($AllItems | Where-Object {
                        $_.PSIsContainer -and ($Exclude -contains $_.Name.ToLowerInvariant())
                    }).Count

                if ($ExcludedCount -gt 0)
                {
                    $script:DirectoriesExcluded += $ExcludedCount
                    Write-Verbose "Excluded $ExcludedCount director(ies) in: $SourcePath"
                }
            }
            catch
            {
                Write-Warning "Failed to access directory: $SourcePath - $($_.Exception.Message)"
                return
            }

            # Process files first (more efficient I/O pattern)
            foreach ($File in $Files)
            {
                $DestFilePath = Join-Path -Path $DestPath -ChildPath $File.Name

                if ($PSCmdlet.ShouldProcess($DestFilePath, "Copy file from $($File.FullName)"))
                {
                    try
                    {
                        Write-Verbose "Copying file: $($File.FullName) -> $DestFilePath"
                        Copy-Item -Path $File.FullName -Destination $DestFilePath -Force:$Force -ErrorAction Stop
                        $script:FilesCopied++
                    }
                    catch
                    {
                        Write-Warning "Failed to copy file: $($File.FullName) - $($_.Exception.Message)"
                    }
                }
            }

            # Process directories (already filtered)
            foreach ($Directory in $Directories)
            {
                $DestDirPath = Join-Path -Path $DestPath -ChildPath $Directory.Name

                # Create directory at destination
                if (-not (Test-Path -Path $DestDirPath))
                {
                    if ($PSCmdlet.ShouldProcess($DestDirPath, 'Create directory'))
                    {
                        Write-Verbose "Creating directory: $DestDirPath"
                        New-Item -Path $DestDirPath -ItemType Directory -Force | Out-Null
                        $script:DirectoriesCreated++
                    }
                }

                # Recurse into subdirectory
                Copy-DirectoryRecursive -SourcePath $Directory.FullName -DestPath $DestDirPath -Exclude $Exclude
            }
        }

        # Start the recursive copy
        Copy-DirectoryRecursive -SourcePath $Source -DestPath $Destination -Exclude $ExcludeLower
    }

    end
    {
        $EndTime = Get-Date
        $Duration = $EndTime - $StartTime

        Write-Verbose 'Copy operation completed'
        Write-Verbose "Files copied: $script:FilesCopied"
        Write-Verbose "Directories created: $script:DirectoriesCreated"
        Write-Verbose "Directories excluded: $script:DirectoriesExcluded"
        Write-Verbose "Duration: $($Duration.TotalSeconds) seconds"

        # Return summary object
        [PSCustomObject]@{
            TotalFiles = $script:FilesCopied
            TotalDirectories = $script:DirectoriesCreated
            ExcludedDirectories = $script:DirectoriesExcluded
            Duration = $Duration
        }
    }
}
