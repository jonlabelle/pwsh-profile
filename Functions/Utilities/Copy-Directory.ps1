function Copy-Directory
{
    <#
    .SYNOPSIS
        Copies a directory with optional recursion, directory exclusions, and parallel processing.

    .DESCRIPTION
        Copies files from a source path to a destination path, optionally recursing into
        subdirectories. Provides the ability to exclude specific directories (e.g., .git,
        node_modules, bin, obj) from the copy operation.

        Supports multi-threaded copying for improved performance with large directory trees.

        For very large trees, you can opt in to OS-native copy tools (robocopy on Windows,
        rsync on macOS/Linux) using -UseNativeTools. This is cross-platform compatible
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
        Default is based on logical CPU count (min 2, max 32). Set to 1 to disable
        parallel processing. Valid range is 1-32.

        Note: Parallel processing is automatically disabled when UpdateMode is 'Prompt' since
        user prompts cannot be handled across multiple threads.

        For PowerShell 7+, uses ForEach-Object -Parallel for optimal performance.
        For PowerShell 5.1/6.x, uses runspace pools for parallel execution.

    .PARAMETER UseNativeTools
        When specified, uses OS-native copy tools for large directory trees (robocopy on Windows,
        rsync on macOS/Linux). Requires -Recurse and does not support UpdateMode 'Prompt'.
        Output properties are limited to those supported by the native tool. Native-tool summaries
        are best-effort for some counters.

        For best performance, and large-scale copies, this option is HIGHLY recommended.

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

    .EXAMPLE
        PS > Copy-Directory -Source 'C:\LargeProject' -Destination 'D:\Backup' -Recurse -UseNativeTools -ThrottleLimit 16

        Copies a large directory tree using OS-native tools (robocopy on Windows, rsync on macOS/Linux).

    .OUTPUTS
        System.Management.Automation.PSCustomObject

        Returns an object with:
        - TotalFiles
        - TotalDirectories
        - ExcludedDirectories
        - FilesSkipped
        - FilesOverwritten
        - Duration

        When -UseNativeTools is specified, the output only includes properties supported by the native tool...

        robocopy:
        - TotalFiles
        - TotalDirectories
        - FilesSkipped
        - Duration

        rsync:
        - TotalFiles
        - Duration

    .NOTES
        Parallel Processing:
        - PowerShell 7+: Uses ForEach-Object -Parallel for native parallel processing
        - PowerShell 5.1/6.x: Uses runspace pools for parallel execution
        - Thread-safe counters using synchronized hashtables with Monitor locks
        - Directory structure is created sequentially to ensure proper ordering
        - Only file copy operations are parallelized

        Native Tools (opt-in):
        - Windows: robocopy
        - macOS/Linux: rsync
        - Requires -Recurse and does not support UpdateMode 'Prompt'
        - UpdateMode mappings are best-effort and may not be exact
        - ThrottleLimit maps to robocopy /MT on Windows and is ignored by rsync
        - ExcludeDirectories matching follows native tool behavior (case sensitivity may differ)
        - FilesOverwritten counts are not available from native tools

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
        [Int32]$ThrottleLimit = ([Math]::Min(32, [Math]::Max(2, [Environment]::ProcessorCount))),

        [Parameter()]
        [Switch]$UseNativeTools
    )

    begin
    {
        Write-Verbose 'Starting Copy-Directory'

        # Resolve paths to absolute paths (cross-platform compatible)
        $Source = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Source)
        $Destination = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)

        Write-Verbose "Resolved source path: $Source"
        Write-Verbose "Resolved destination path: $Destination"

        # Validate parameter combinations
        if ($UseNativeTools -and -not $Recurse)
        {
            throw 'The -UseNativeTools parameter requires -Recurse to be specified. Native copy tools (robocopy/rsync) only support recursive directory operations.'
        }

        if ($UseNativeTools -and $UpdateMode -eq 'Prompt')
        {
            throw "The -UseNativeTools parameter cannot be used with -UpdateMode 'Prompt'. Native copy tools do not support interactive prompts for file overwrites."
        }

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
        $script:UsedNativeTools = $false
        $script:NativeToolName = $null

        # Use a HashSet for fast, case-insensitive directory exclusion checks
        $ExcludeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($excludeDir in $ExcludeDirectories)
        {
            $null = $ExcludeSet.Add($excludeDir)
        }

        Write-Verbose "Excluding directories: $($ExcludeDirectories -join ', ')"
        Write-Verbose "UpdateMode: $UpdateMode"
        Write-Verbose "ThrottleLimit: $ThrottleLimit"
        Write-Verbose "UseNativeTools: $UseNativeTools"

        # Check if parallel processing should be used
        $UseParallel = $ThrottleLimit -gt 1 -and $UpdateMode -ne 'Prompt'
        if ($UpdateMode -eq 'Prompt' -and $ThrottleLimit -gt 1)
        {
            Write-Warning "Parallel processing disabled: UpdateMode 'Prompt' requires sequential processing for user interaction."
            $UseParallel = $false
        }

        $IncludeLastWriteTime = $UpdateMode -eq 'IfNewer'

        # Detect PowerShell version for parallel implementation choice
        $IsPowerShell7OrLater = $PSVersionTable.PSVersion.Major -ge 7
        $IsWindowsPlatform = $IsWindows -or $env:OS -eq 'Windows_NT'

        Write-Verbose "UseParallel: $UseParallel"
        Write-Verbose "PowerShell 7+: $IsPowerShell7OrLater"

        $StartTime = Get-Date
    }

    process
    {
        function Invoke-NativeDirectoryCopy
        {
            param(
                [String]$SourcePath,
                [String]$DestPath,
                [String[]]$ExcludeDirs,
                [String]$Mode,
                [Int32]$Throttle,
                [Bool]$EnableRecurse,
                [Bool]$IsWindowsPlatform,
                [hashtable]$CountersRef
            )

            $nativeTool = $null
            $nativeToolName = $null
            $nativeArgs = @()

            if ($IsWindowsPlatform)
            {
                $command = Get-Command -Name 'robocopy' -ErrorAction SilentlyContinue
                if ($command)
                {
                    $nativeTool = if ($command.Source) { $command.Source } else { $command.Path }
                }

                if (-not $nativeTool)
                {
                    Write-Warning 'Native tool copy requested, but robocopy was not found. Falling back to PowerShell copy.'
                    return $false
                }

                $nativeToolName = 'robocopy'
                $nativeArgs += $SourcePath
                $nativeArgs += $DestPath
                $nativeArgs += '/E'
                $nativeArgs += '/NJH'
                $nativeArgs += '/NP'
                $nativeArgs += '/NDL'
                $nativeArgs += '/NFL'
                $nativeArgs += '/R:1'
                $nativeArgs += '/W:1'

                if ($Throttle -gt 1)
                {
                    $nativeArgs += "/MT:$Throttle"
                }

                switch ($Mode)
                {
                    'Skip'
                    {
                        $nativeArgs += '/XC'
                        $nativeArgs += '/XN'
                        $nativeArgs += '/XO'
                    }
                    'Overwrite'
                    {
                        $nativeArgs += '/IS'
                        $nativeArgs += '/IT'
                    }
                    'IfNewer'
                    {
                        $nativeArgs += '/XO'
                    }
                }

                if ($ExcludeDirs -and $ExcludeDirs.Count -gt 0)
                {
                    $nativeArgs += '/XD'
                    $nativeArgs += $ExcludeDirs
                }
            }
            else
            {
                $command = Get-Command -Name 'rsync' -ErrorAction SilentlyContinue
                if ($command)
                {
                    $nativeTool = if ($command.Source) { $command.Source } else { $command.Path }
                }

                if (-not $nativeTool)
                {
                    Write-Warning 'Native tool copy requested, but rsync was not found. Falling back to PowerShell copy.'
                    return $false
                }

                $nativeToolName = 'rsync'
                $nativeArgs += '-a'
                $nativeArgs += '--stats'

                switch ($Mode)
                {
                    'Skip'
                    {
                        $nativeArgs += '--ignore-existing'
                    }
                    'Overwrite'
                    {
                        $nativeArgs += '--ignore-times'
                    }
                    'IfNewer'
                    {
                        $nativeArgs += '-u'
                    }
                }

                if ($ExcludeDirs -and $ExcludeDirs.Count -gt 0)
                {
                    foreach ($excludeDir in $ExcludeDirs)
                    {
                        if (-not [String]::IsNullOrWhiteSpace($excludeDir))
                        {
                            $nativeArgs += "--exclude=$excludeDir/"
                        }
                    }
                }

                $separatorChars = @([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
                $sourceNormalized = $SourcePath.TrimEnd($separatorChars) + [System.IO.Path]::DirectorySeparatorChar
                $destNormalized = $DestPath.TrimEnd($separatorChars) + [System.IO.Path]::DirectorySeparatorChar

                $nativeArgs += $sourceNormalized
                $nativeArgs += $destNormalized
            }

            Write-Verbose "Using native tool: $nativeToolName"
            $script:UsedNativeTools = $true
            $script:NativeToolName = $nativeToolName

            if (-not $PSCmdlet.ShouldProcess($DestPath, "Copy directory from $SourcePath using $nativeToolName"))
            {
                return $true
            }

            try
            {
                $nativeOutput = & $nativeTool @nativeArgs 2>&1
            }
            catch
            {
                Write-Warning "Native tool copy failed to start: $($_.Exception.Message)"
                return $true
            }

            $exitCode = $LASTEXITCODE

            if ($IsWindowsPlatform)
            {
                if ($exitCode -ge 8)
                {
                    Write-Warning "robocopy returned exit code $exitCode. See robocopy documentation for details."
                }

                foreach ($line in $nativeOutput)
                {
                    if ($line -match '^\s*Dirs\s*:\s*(\d+)\s+(\d+)\s+(\d+)')
                    {
                        $CountersRef.DirectoriesCreated = [Int32]$matches[2]
                    }
                    elseif ($line -match '^\s*Files\s*:\s*(\d+)\s+(\d+)\s+(\d+)')
                    {
                        $CountersRef.FilesCopied = [Int32]$matches[2]
                        $CountersRef.FilesSkipped = [Int32]$matches[3]
                    }
                }
            }
            else
            {
                if ($exitCode -ne 0)
                {
                    Write-Warning "rsync returned exit code $exitCode. See rsync documentation for details."
                }

                foreach ($line in $nativeOutput)
                {
                    if ($line -match '^Number of regular files transferred:\s*(\d+)')
                    {
                        $CountersRef.FilesCopied = [Int32]$matches[1]
                    }
                    elseif ($line -match '^Number of files transferred:\s*(\d+)')
                    {
                        $CountersRef.FilesCopied = [Int32]$matches[1]
                    }
                }
            }

            return $true
        }

        # Function to stream file operations while creating directories on the fly
        function Get-CopyFileOperations
        {
            param(
                [String]$SourcePath,
                [String]$DestPath,
                [System.Collections.Generic.HashSet[string]]$ExcludeSet,
                [Bool]$EnableRecurse,
                [Bool]$IncludeLastWriteTime,
                [hashtable]$CountersRef,
                [ref]$FoundFiles
            )

            $directoriesToProcess = [System.Collections.Queue]::new()
            $directoriesToProcess.Enqueue(@{ Source = $SourcePath; Dest = $DestPath })

            while ($directoriesToProcess.Count -gt 0)
            {
                $current = $directoriesToProcess.Dequeue()
                $currentSource = $current.Source
                $currentDest = $current.Dest

                try
                {
                    $directoryInfo = [System.IO.DirectoryInfo]::new($currentSource)

                    foreach ($entry in $directoryInfo.EnumerateFileSystemInfos())
                    {
                        if ($entry -is [System.IO.DirectoryInfo])
                        {
                            if ($ExcludeSet.Contains($entry.Name))
                            {
                                $CountersRef.DirectoriesExcluded++
                                continue
                            }

                            if (-not $EnableRecurse)
                            {
                                $CountersRef.DirectoriesExcluded++
                                continue
                            }

                            $destDirPath = [System.IO.Path]::Combine($currentDest, $entry.Name)

                            if (-not (Test-Path -Path $destDirPath))
                            {
                                if ($PSCmdlet.ShouldProcess($destDirPath, 'Create directory'))
                                {
                                    Write-Verbose "Creating directory: $destDirPath"
                                    New-Item -Path $destDirPath -ItemType Directory -Force | Out-Null
                                    $CountersRef.DirectoriesCreated++
                                }
                            }

                            $directoriesToProcess.Enqueue(@{ Source = $entry.FullName; Dest = $destDirPath })
                        }
                        else
                        {
                            $FoundFiles.Value = $true
                            $destFilePath = [System.IO.Path]::Combine($currentDest, $entry.Name)
                            @{
                                SourcePath = $entry.FullName
                                DestPath = $destFilePath
                                LastWriteTime = if ($IncludeLastWriteTime) { $entry.LastWriteTime } else { $null }
                            }
                        }
                    }
                }
                catch
                {
                    Write-Warning "Failed to access directory: $currentSource - $($_.Exception.Message)"
                }
            }
        }

        $usedNativeTools = $false
        if ($UseNativeTools)
        {
            $usedNativeTools = Invoke-NativeDirectoryCopy -SourcePath $Source -DestPath $Destination -ExcludeDirs $ExcludeDirectories -Mode $UpdateMode -Throttle $ThrottleLimit -EnableRecurse $Recurse.IsPresent -IsWindowsPlatform $IsWindowsPlatform -CountersRef $script:Counters
        }

        $hasFiles = $false

        if (-not $usedNativeTools)
        {
            if (-not $UseParallel)
            {
                $copyHeaderWritten = $false

                foreach ($fileOp in Get-CopyFileOperations -SourcePath $Source -DestPath $Destination -ExcludeSet $ExcludeSet -EnableRecurse $Recurse.IsPresent -IncludeLastWriteTime $IncludeLastWriteTime -CountersRef $script:Counters -FoundFiles ([ref]$hasFiles))
                {
                    if (-not $copyHeaderWritten)
                    {
                        Write-Verbose 'Copying files sequentially...'
                        $copyHeaderWritten = $true
                    }

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
                $copyHeaderWritten = $false

                # Use synchronized hashtable for thread-safe counter access across parallel runspaces
                $countersRef = $script:Counters
                $updateModeValue = $UpdateMode
                $whatIfEnabled = $WhatIfPreference

                Get-CopyFileOperations -SourcePath $Source -DestPath $Destination -ExcludeSet $ExcludeSet -EnableRecurse $Recurse.IsPresent -IncludeLastWriteTime $IncludeLastWriteTime -CountersRef $script:Counters -FoundFiles ([ref]$hasFiles) | ForEach-Object {
                    if (-not $copyHeaderWritten)
                    {
                        Write-Verbose "Copying files in parallel (ThrottleLimit: $ThrottleLimit, PowerShell 7+ mode)..."
                        $copyHeaderWritten = $true
                    }
                    $_
                } | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                    $fileOp = $_
                    $localMode = $using:updateModeValue
                    $localCounters = $using:countersRef
                    $whatIfEnabled = $using:whatIfEnabled

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

                    if ($shouldCopyFile -and -not $whatIfEnabled)
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
                $copyHeaderWritten = $false

                # Create runspace pool
                $runspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit)
                $runspacePool.Open()

                $runspaces = [System.Collections.ArrayList]::new()

                # Use synchronized hashtable for thread-safe counter access
                $countersRef = $script:Counters
                $updateModeValue = $UpdateMode
                $whatIfEnabled = $WhatIfPreference
                $queueCapacity = [Math]::Max(32, $ThrottleLimit * 8)
                $workQueue = [System.Collections.Concurrent.BlockingCollection[hashtable]]::new($queueCapacity)

                for ($workerIndex = 0; $workerIndex -lt $ThrottleLimit; $workerIndex++)
                {
                    $powershell = [System.Management.Automation.PowerShell]::Create()
                    $powershell.RunspacePool = $runspacePool

                    $null = $powershell.AddScript({
                            param(
                                [System.Collections.Concurrent.BlockingCollection[hashtable]]$WorkQueue,
                                [String]$Mode,
                                [hashtable]$Counters,
                                [Bool]$WhatIfEnabled
                            )

                            foreach ($fileOp in $WorkQueue.GetConsumingEnumerable())
                            {
                                $shouldCopyFile = $true
                                $destExists = Test-Path -Path $fileOp.DestPath -PathType Leaf

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
                                            $destFile = Get-Item -Path $fileOp.DestPath
                                            if ($fileOp.LastWriteTime -gt $destFile.LastWriteTime)
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

                                if ($shouldCopyFile -and -not $WhatIfEnabled)
                                {
                                    try
                                    {
                                        Copy-Item -Path $fileOp.SourcePath -Destination $fileOp.DestPath -Force -ErrorAction Stop
                                        [System.Threading.Monitor]::Enter($Counters.SyncRoot)
                                        try { $Counters.FilesCopied++ }
                                        finally { [System.Threading.Monitor]::Exit($Counters.SyncRoot) }
                                    }
                                    catch
                                    {
                                        Write-Warning "Failed to copy file: $($fileOp.SourcePath) - $($_.Exception.Message)"
                                    }
                                }
                            }
                        })

                    $null = $powershell.AddParameter('WorkQueue', $workQueue)
                    $null = $powershell.AddParameter('Mode', $updateModeValue)
                    $null = $powershell.AddParameter('Counters', $countersRef)
                    $null = $powershell.AddParameter('WhatIfEnabled', $whatIfEnabled)

                    $handle = $powershell.BeginInvoke()
                    $null = $runspaces.Add(@{
                            PowerShell = $powershell
                            Handle = $handle
                        })
                }

                try
                {
                    foreach ($fileOp in Get-CopyFileOperations -SourcePath $Source -DestPath $Destination -ExcludeSet $ExcludeSet -EnableRecurse $Recurse.IsPresent -IncludeLastWriteTime $IncludeLastWriteTime -CountersRef $script:Counters -FoundFiles ([ref]$hasFiles))
                    {
                        if (-not $copyHeaderWritten)
                        {
                            Write-Verbose "Copying files in parallel (ThrottleLimit: $ThrottleLimit, Runspace pool mode)..."
                            $copyHeaderWritten = $true
                        }
                        $workQueue.Add($fileOp)
                    }
                }
                finally
                {
                    $workQueue.CompleteAdding()
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

            if (-not $hasFiles)
            {
                Write-Verbose 'No files to copy'
            }
        }
    }

    end
    {
        $EndTime = Get-Date
        $Duration = $EndTime - $StartTime

        Write-Verbose 'Copy operation completed'

        if ($script:UsedNativeTools)
        {
            Write-Verbose "Files copied: $($script:Counters.FilesCopied)"
            if ($script:NativeToolName -eq 'robocopy')
            {
                Write-Verbose "Directories created: $($script:Counters.DirectoriesCreated)"
                Write-Verbose "Files skipped: $($script:Counters.FilesSkipped)"
            }
            Write-Verbose "Duration: $($Duration.TotalSeconds) seconds"

            $nativeOutput = [ordered]@{
                TotalFiles = [Int32]$script:Counters.FilesCopied
            }
            if ($script:NativeToolName -eq 'robocopy')
            {
                $nativeOutput.TotalDirectories = [Int32]$script:Counters.DirectoriesCreated
                $nativeOutput.FilesSkipped = [Int32]$script:Counters.FilesSkipped
            }
            $nativeOutput.Duration = $Duration

            [PSCustomObject]$nativeOutput
            return
        }

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
