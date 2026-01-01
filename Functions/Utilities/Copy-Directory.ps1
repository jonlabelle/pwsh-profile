function Copy-Directory
{
    <#
    .SYNOPSIS
        Copies a directory with optional recursion, directory exclusions, and parallel processing.

    .DESCRIPTION
        Copies files from a source path to a destination path, optionally recursing into
        subdirectories. Provides the ability to exclude specific directories (e.g., .git,
        node_modules, bin, obj) from the copy operation. Supports multi-threaded copying
        for improved performance with large directory trees. This is cross-platform compatible
        with PowerShell 5.1+ and PowerShell Core 6.2+.

    .PARAMETER Source
        The source directory path to copy from. Supports relative paths and tilde (~) expansion.

    .PARAMETER Destination
        The destination directory path to copy to. Will be created if it doesn't exist.
        Supports relative paths and tilde (~) expansion.

    .PARAMETER ExcludeDirectories
        An array of directory names to exclude from the copy operation. Directory names are
        matched case-insensitively. Common examples include: .git, node_modules, bin, obj,
        .vs, .vscode, packages, dist, build, out.

    .PARAMETER UpdateMode
        Specifies how to handle existing files at the destination.

        Valid values are:
        - Skip: Do not copy files if they already exist at the destination (default)
        - Overwrite: Always overwrite existing files without prompting
        - IfNewer: Only overwrite if the source file is newer than the destination file
        - Prompt: Ask for confirmation for each existing file (not compatible with parallel mode)

    .PARAMETER Recurse
        When specified, copies subdirectories recursively. Without this switch, only files in the
        root of the source directory are copied.

    .PARAMETER ThrottleLimit
        Specifies the maximum number of concurrent copy operations when using parallel processing.
        Default is 4. Set to 1 to disable parallel processing. Valid range is 1-32.

        Note: Parallel processing is automatically disabled when UpdateMode is 'Prompt' since
        user prompts cannot be handled across multiple threads.

        For PowerShell 7+, uses ForEach-Object -Parallel for optimal performance.
        For PowerShell 5.1/6.x, uses runspace pools for parallel execution.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs without actually performing the copy operation.

    .PARAMETER Confirm
        Prompts for confirmation before copying files.

    .EXAMPLE
        PS > Copy-Directory -Source '.\MyProject' -Destination 'C:\Backup\MyProject' -ExcludeDirectories '.git', 'node_modules' -Recurse

        Copies the MyProject directory to C:\Backup\MyProject, excluding '.git' and 'node_modules' directories.

    .EXAMPLE
        PS > Copy-Directory -Source 'C:\Dev\Project' -Destination 'D:\Archive\Project' -ExcludeDirectories 'bin', 'obj', '.vs' -UpdateMode Overwrite -Recurse

        Copies the project directory excluding build artifacts, overwriting existing files without prompting.

    .EXAMPLE
        PS > Copy-Directory -Source '~/Documents/Code' -Destination '~/Backup/Code' -ExcludeDirectories '.git', 'dist', 'build' -Recurse

        Copies the Code directory from Documents to Backup, excluding version control and build directories.
        Uses tilde expansion which works cross-platform.

    .EXAMPLE
        PS > Copy-Directory -Source './app' -Destination './staging/app' -ExcludeDirectories '.git', '.github', 'node_modules', 'tests' -Recurse
        PS > Compress-Archive -Path './staging/app/*' -DestinationPath './artifacts/app.zip' -Force

        Prepares a clean deployable archive by copying only runtime assets before zipping for release.

    .EXAMPLE
        PS > Copy-Directory -Source 'C:\LargeProject' -Destination 'D:\Backup' -ThrottleLimit 8 -Recurse

        Copies a large project using 8 parallel threads for faster copying.

    .EXAMPLE
        PS > Copy-Directory -Source '.\Project' -Destination '.\Backup' -ThrottleLimit 1 -Recurse

        Copies the project using single-threaded mode (parallel processing disabled).

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns an object with TotalFiles, TotalDirectories, ExcludedDirectories, FilesSkipped,
        FilesOverwritten, and Duration properties.

    .NOTES
        Cross-platform compatible with PowerShell 5.1+ and PowerShell Core 6.2+.
        Uses .NET methods for path resolution to ensure cross-platform compatibility.

        Parallel Processing:
        - PowerShell 7+: Uses ForEach-Object -Parallel for native parallel processing
        - PowerShell 5.1/6.x: Uses runspace pools for parallel execution
        - Thread-safe counters using synchronized hashtables with Monitor locks
        - Directory structure is created sequentially to ensure proper ordering
        - Only file copy operations are parallelized

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Copy-Directory.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Copy-Directory.ps1
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
        [ValidateSet('Skip', 'Overwrite', 'IfNewer', 'Prompt')]
        [String]$UpdateMode = 'Skip',

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [ValidateRange(1, 32)]
        [Int32]$ThrottleLimit = 4
    )

    begin
    {
        Write-Verbose 'Starting Copy-Directory'

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

        # Initialize thread-safe counters
        # For PS7+ parallel mode, we use a synchronized hashtable that works across runspaces
        # For PS5.1/6.x runspace pools, we use [ref] types with Interlocked operations
        $script:Counters = [hashtable]::Synchronized(@{
            FilesCopied = 0
            DirectoriesCreated = 0
            DirectoriesExcluded = 0
            FilesSkipped = 0
            FilesOverwritten = 0
        })

        # Convert exclude list to lowercase for case-insensitive comparison
        $ExcludeLower = $ExcludeDirectories | ForEach-Object { $_.ToLowerInvariant() }

        Write-Verbose "Excluding directories: $($ExcludeDirectories -join ', ')"
        Write-Verbose "UpdateMode: $UpdateMode"
        Write-Verbose "ThrottleLimit: $ThrottleLimit"

        # Check if parallel processing should be used
        $UseParallel = $ThrottleLimit -gt 1 -and $UpdateMode -ne 'Prompt'
        if ($UpdateMode -eq 'Prompt' -and $ThrottleLimit -gt 1)
        {
            Write-Warning "Parallel processing disabled: UpdateMode 'Prompt' requires sequential processing for user interaction."
            $UseParallel = $false
        }

        # Detect PowerShell version for parallel implementation choice
        $IsPowerShell7OrLater = $PSVersionTable.PSVersion.Major -ge 7

        Write-Verbose "UseParallel: $UseParallel"
        Write-Verbose "PowerShell 7+: $IsPowerShell7OrLater"

        $StartTime = Get-Date
    }

    process
    {
        # Function to collect all files and directories to process
        function Get-CopyOperations
        {
            param(
                [String]$SourcePath,
                [String]$DestPath,
                [String[]]$Exclude,
                [Bool]$EnableRecurse,
                [hashtable]$CountersRef
            )

            $operations = @{
                Files = [System.Collections.ArrayList]::new()
                Directories = [System.Collections.ArrayList]::new()
            }

            $directoriesToProcess = [System.Collections.Queue]::new()
            $directoriesToProcess.Enqueue(@{ Source = $SourcePath; Dest = $DestPath })

            while ($directoriesToProcess.Count -gt 0)
            {
                $current = $directoriesToProcess.Dequeue()
                $currentSource = $current.Source
                $currentDest = $current.Dest

                try
                {
                    $allItems = Get-ChildItem -Path $currentSource -Force -ErrorAction Stop

                    # Separate files and directories
                    $files = $allItems | Where-Object { -not $_.PSIsContainer }
                    $directories = $allItems | Where-Object {
                        $_.PSIsContainer -and ($Exclude -notcontains $_.Name.ToLowerInvariant())
                    }

                    # Count excluded directories
                    $excludedCount = ($allItems | Where-Object {
                            $_.PSIsContainer -and ($Exclude -contains $_.Name.ToLowerInvariant())
                        }).Count

                    if ($excludedCount -gt 0)
                    {
                        $CountersRef.DirectoriesExcluded += $excludedCount
                    }

                    # Add files to operations list
                    foreach ($file in $files)
                    {
                        $destFilePath = Join-Path -Path $currentDest -ChildPath $file.Name
                        $null = $operations.Files.Add(@{
                                SourcePath = $file.FullName
                                DestPath = $destFilePath
                                LastWriteTime = $file.LastWriteTime
                            })
                    }

                    # Process directories
                    foreach ($directory in $directories)
                    {
                        $destDirPath = Join-Path -Path $currentDest -ChildPath $directory.Name

                        if (-not $EnableRecurse)
                        {
                            $CountersRef.DirectoriesExcluded++
                            continue
                        }

                        # Add directory to create
                        $null = $operations.Directories.Add($destDirPath)

                        # Queue subdirectory for processing
                        $directoriesToProcess.Enqueue(@{ Source = $directory.FullName; Dest = $destDirPath })
                    }
                }
                catch
                {
                    Write-Warning "Failed to access directory: $currentSource - $($_.Exception.Message)"
                }
            }

            return $operations
        }

        # Collect all operations first (sequential - needed for directory structure)
        Write-Verbose 'Collecting file and directory information...'
        $operations = Get-CopyOperations -SourcePath $Source -DestPath $Destination -Exclude $ExcludeLower -EnableRecurse $Recurse.IsPresent -CountersRef $script:Counters

        # Create all directories first (must be sequential to maintain structure)
        foreach ($dirPath in $operations.Directories)
        {
            if (-not (Test-Path -Path $dirPath))
            {
                if ($PSCmdlet.ShouldProcess($dirPath, 'Create directory'))
                {
                    Write-Verbose "Creating directory: $dirPath"
                    New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
                    $script:Counters.DirectoriesCreated++
                }
            }
        }

        # Handle file copying based on mode
        if ($operations.Files.Count -eq 0)
        {
            Write-Verbose 'No files to copy'
        }
        elseif (-not $UseParallel -or $operations.Files.Count -lt 4)
        {
            # Sequential mode (for single-threaded, Prompt mode, or small file counts)
            Write-Verbose "Copying $($operations.Files.Count) file(s) sequentially..."

            foreach ($fileOp in $operations.Files)
            {
                $shouldCopyFile = $true

                if (Test-Path -Path $fileOp.DestPath -PathType Leaf)
                {
                    switch ($UpdateMode)
                    {
                        'Skip'
                        {
                            Write-Verbose "Skipping existing file: $($fileOp.DestPath)"
                            $script:Counters.FilesSkipped++
                            $shouldCopyFile = $false
                        }
                        'Overwrite'
                        {
                            Write-Verbose "Overwriting existing file: $($fileOp.DestPath)"
                            $script:Counters.FilesOverwritten++
                        }
                        'IfNewer'
                        {
                            $destFile = Get-Item -Path $fileOp.DestPath
                            if ($fileOp.LastWriteTime -gt $destFile.LastWriteTime)
                            {
                                Write-Verbose "Overwriting with newer file: $($fileOp.DestPath)"
                                $script:Counters.FilesOverwritten++
                            }
                            else
                            {
                                Write-Verbose "Destination file is up-to-date, skipping: $($fileOp.DestPath)"
                                $script:Counters.FilesSkipped++
                                $shouldCopyFile = $false
                            }
                        }
                        'Prompt'
                        {
                            if (-not $PSCmdlet.ShouldProcess($fileOp.DestPath, "Overwrite existing file from $($fileOp.SourcePath)"))
                            {
                                Write-Verbose "User declined to overwrite: $($fileOp.DestPath)"
                                $script:Counters.FilesSkipped++
                                $shouldCopyFile = $false
                            }
                            else
                            {
                                Write-Verbose "User confirmed overwriting: $($fileOp.DestPath)"
                                $script:Counters.FilesOverwritten++
                            }
                        }
                    }
                }

                if ($shouldCopyFile -and $PSCmdlet.ShouldProcess($fileOp.DestPath, "Copy file from $($fileOp.SourcePath)"))
                {
                    try
                    {
                        Write-Verbose "Copying file: $($fileOp.SourcePath) -> $($fileOp.DestPath)"
                        Copy-Item -Path $fileOp.SourcePath -Destination $fileOp.DestPath -Force -ErrorAction Stop
                        $script:Counters.FilesCopied++
                    }
                    catch
                    {
                        Write-Warning "Failed to copy file: $($fileOp.SourcePath) - $($_.Exception.Message)"
                    }
                }
            }
        }
        elseif ($IsPowerShell7OrLater)
        {
            # PowerShell 7+ parallel mode using ForEach-Object -Parallel
            Write-Verbose "Copying $($operations.Files.Count) file(s) in parallel (ThrottleLimit: $ThrottleLimit, PowerShell 7+ mode)..."

            # Use synchronized hashtable for thread-safe counter access across parallel runspaces
            $countersRef = $script:Counters
            $updateModeValue = $UpdateMode

            $operations.Files | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                $fileOp = $_
                $localMode = $using:updateModeValue
                $localCounters = $using:countersRef

                $shouldCopyFile = $true
                $destExists = Test-Path -Path $fileOp.DestPath -PathType Leaf

                if ($destExists)
                {
                    switch ($localMode)
                    {
                        'Skip'
                        {
                            # Thread-safe increment on synchronized hashtable
                            [System.Threading.Monitor]::Enter($localCounters.SyncRoot)
                            try { $localCounters.FilesSkipped++ }
                            finally { [System.Threading.Monitor]::Exit($localCounters.SyncRoot) }
                            $shouldCopyFile = $false
                        }
                        'Overwrite'
                        {
                            [System.Threading.Monitor]::Enter($localCounters.SyncRoot)
                            try { $localCounters.FilesOverwritten++ }
                            finally { [System.Threading.Monitor]::Exit($localCounters.SyncRoot) }
                        }
                        'IfNewer'
                        {
                            $destFile = Get-Item -Path $fileOp.DestPath
                            if ($fileOp.LastWriteTime -gt $destFile.LastWriteTime)
                            {
                                [System.Threading.Monitor]::Enter($localCounters.SyncRoot)
                                try { $localCounters.FilesOverwritten++ }
                                finally { [System.Threading.Monitor]::Exit($localCounters.SyncRoot) }
                            }
                            else
                            {
                                [System.Threading.Monitor]::Enter($localCounters.SyncRoot)
                                try { $localCounters.FilesSkipped++ }
                                finally { [System.Threading.Monitor]::Exit($localCounters.SyncRoot) }
                                $shouldCopyFile = $false
                            }
                        }
                    }
                }

                if ($shouldCopyFile)
                {
                    try
                    {
                        Copy-Item -Path $fileOp.SourcePath -Destination $fileOp.DestPath -Force -ErrorAction Stop
                        [System.Threading.Monitor]::Enter($localCounters.SyncRoot)
                        try { $localCounters.FilesCopied++ }
                        finally { [System.Threading.Monitor]::Exit($localCounters.SyncRoot) }
                    }
                    catch
                    {
                        Write-Warning "Failed to copy file: $($fileOp.SourcePath) - $($_.Exception.Message)"
                    }
                }
            }
        }
        else
        {
            # PowerShell 5.1/6.x parallel mode using runspace pools
            Write-Verbose "Copying $($operations.Files.Count) file(s) in parallel (ThrottleLimit: $ThrottleLimit, Runspace pool mode)..."

            # Create runspace pool
            $runspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit)
            $runspacePool.Open()

            $runspaces = [System.Collections.ArrayList]::new()

            # Use synchronized hashtable for thread-safe counter access
            $countersRef = $script:Counters

            foreach ($fileOp in $operations.Files)
            {
                $powershell = [System.Management.Automation.PowerShell]::Create()
                $powershell.RunspacePool = $runspacePool

                $null = $powershell.AddScript({
                        param(
                            [String]$SourceFilePath,
                            [String]$DestFilePath,
                            [DateTime]$SourceLastWriteTime,
                            [String]$Mode,
                            [hashtable]$Counters
                        )

                        $shouldCopyFile = $true
                        $destExists = Test-Path -Path $DestFilePath -PathType Leaf

                        if ($destExists)
                        {
                            switch ($Mode)
                            {
                                'Skip'
                                {
                                    [System.Threading.Monitor]::Enter($Counters.SyncRoot)
                                    try { $Counters.FilesSkipped++ }
                                    finally { [System.Threading.Monitor]::Exit($Counters.SyncRoot) }
                                    $shouldCopyFile = $false
                                }
                                'Overwrite'
                                {
                                    [System.Threading.Monitor]::Enter($Counters.SyncRoot)
                                    try { $Counters.FilesOverwritten++ }
                                    finally { [System.Threading.Monitor]::Exit($Counters.SyncRoot) }
                                }
                                'IfNewer'
                                {
                                    $destFile = Get-Item -Path $DestFilePath
                                    if ($SourceLastWriteTime -gt $destFile.LastWriteTime)
                                    {
                                        [System.Threading.Monitor]::Enter($Counters.SyncRoot)
                                        try { $Counters.FilesOverwritten++ }
                                        finally { [System.Threading.Monitor]::Exit($Counters.SyncRoot) }
                                    }
                                    else
                                    {
                                        [System.Threading.Monitor]::Enter($Counters.SyncRoot)
                                        try { $Counters.FilesSkipped++ }
                                        finally { [System.Threading.Monitor]::Exit($Counters.SyncRoot) }
                                        $shouldCopyFile = $false
                                    }
                                }
                            }
                        }

                        if ($shouldCopyFile)
                        {
                            try
                            {
                                Copy-Item -Path $SourceFilePath -Destination $DestFilePath -Force -ErrorAction Stop
                                [System.Threading.Monitor]::Enter($Counters.SyncRoot)
                                try { $Counters.FilesCopied++ }
                                finally { [System.Threading.Monitor]::Exit($Counters.SyncRoot) }
                            }
                            catch
                            {
                                Write-Warning "Failed to copy file: $SourceFilePath - $($_.Exception.Message)"
                            }
                        }
                    })

                $null = $powershell.AddParameter('SourceFilePath', $fileOp.SourcePath)
                $null = $powershell.AddParameter('DestFilePath', $fileOp.DestPath)
                $null = $powershell.AddParameter('SourceLastWriteTime', $fileOp.LastWriteTime)
                $null = $powershell.AddParameter('Mode', $UpdateMode)
                $null = $powershell.AddParameter('Counters', $countersRef)

                $handle = $powershell.BeginInvoke()
                $null = $runspaces.Add(@{
                        PowerShell = $powershell
                        Handle = $handle
                    })
            }

            # Wait for all runspaces to complete
            foreach ($runspace in $runspaces)
            {
                try
                {
                    $runspace.PowerShell.EndInvoke($runspace.Handle)
                }
                catch
                {
                    Write-Warning "Runspace error: $($_.Exception.Message)"
                }
                finally
                {
                    $runspace.PowerShell.Dispose()
                }
            }

            # Clean up runspace pool
            $runspacePool.Close()
            $runspacePool.Dispose()
        }
    }

    end
    {
        $EndTime = Get-Date
        $Duration = $EndTime - $StartTime

        Write-Verbose 'Copy operation completed'
        Write-Verbose "Files copied: $($script:Counters.FilesCopied)"
        Write-Verbose "Directories created: $($script:Counters.DirectoriesCreated)"
        Write-Verbose "Directories excluded: $($script:Counters.DirectoriesExcluded)"
        Write-Verbose "Files skipped: $($script:Counters.FilesSkipped)"
        Write-Verbose "Files overwritten: $($script:Counters.FilesOverwritten)"
        Write-Verbose "Duration: $($Duration.TotalSeconds) seconds"

        # Return summary object
        [PSCustomObject]@{
            TotalFiles = [Int32]$script:Counters.FilesCopied
            TotalDirectories = [Int32]$script:Counters.DirectoriesCreated
            ExcludedDirectories = [Int32]$script:Counters.DirectoriesExcluded
            FilesSkipped = [Int32]$script:Counters.FilesSkipped
            FilesOverwritten = [Int32]$script:Counters.FilesOverwritten
            Duration = $Duration
        }
    }
}
