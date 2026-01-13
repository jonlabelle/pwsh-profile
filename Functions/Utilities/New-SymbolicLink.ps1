function New-SymbolicLink
{
    <#
    .SYNOPSIS
        Creates a symbolic link to a file or directory.

    .DESCRIPTION
        Creates a symbolic link (symlink) at the specified path pointing to the target file or directory.
        This function is cross-platform compatible and works on Windows, macOS, and Linux.

        On Windows, creating symbolic links may require elevated privileges (Administrator) or
        Developer Mode to be enabled. On Unix-like systems (macOS/Linux), symbolic links can
        typically be created by any user with appropriate file system permissions.

        The function supports both file and directory targets and automatically detects the
        target type unless explicitly specified.

    .PARAMETER Path
        The path where the symbolic link will be created. This is the symlink itself.
        Supports relative paths and tilde (~) expansion.

    .PARAMETER Target
        The path to the target file or directory that the symbolic link will point to.
        The target must exist unless -Force is specified.
        Supports relative paths and tilde (~) expansion.

    .PARAMETER ItemType
        Specifies the type of symbolic link to create. Valid values are:
        - Auto: Automatically detect based on target type (default)
        - File: Create a symbolic link to a file
        - Directory: Create a symbolic link to a directory

        This parameter is primarily useful when the target does not exist and -Force is used.

    .PARAMETER Force
        When specified, allows creating symbolic links to targets that do not exist,
        and overwrites existing files or symbolic links at the Path location.

    .PARAMETER PassThru
        Returns the FileInfo or DirectoryInfo object representing the created symbolic link.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs without actually creating the symbolic link.

    .PARAMETER Confirm
        Prompts for confirmation before creating the symbolic link.

    .EXAMPLE
        PS > New-SymbolicLink -Path '~/link-to-docs' -Target '~/Documents'

        Creates a symbolic link named 'link-to-docs' in the home directory pointing to the Documents folder.

    .EXAMPLE
        PS > New-SymbolicLink -Path 'C:\MyLink.txt' -Target 'C:\Original\File.txt' -PassThru

        Creates a symbolic link to a file and returns the FileInfo object for the created link.

    .EXAMPLE
        PS > New-SymbolicLink -Path './config' -Target '/etc/myapp/config' -Force

        Creates a symbolic link to a directory, overwriting any existing file or link at './config'.

    .EXAMPLE
        PS > New-SymbolicLink -Path '.\future-link' -Target '.\will-exist-later' -ItemType File -Force

        Creates a symbolic link to a file that doesn't exist yet. Useful for setting up links
        before the target is created.

    .EXAMPLE
        PS > Get-ChildItem -File | ForEach-Object { New-SymbolicLink -Path "~/links/$($_.Name)" -Target $_.FullName }

        Creates symbolic links in ~/links for each file in the current directory.

    .OUTPUTS
        None by default.
        [System.IO.FileSystemInfo] when -PassThru is specified.

    .NOTES
        Windows Requirements:
        - Windows Vista or later
        - Administrator privileges OR Developer Mode enabled (Windows 10 build 14972+)
        - To enable Developer Mode: Settings > Update & Security > For Developers > Developer Mode

        Unix Requirements (macOS/Linux):
        - Write permission to the parent directory of the symbolic link path
        - No special privileges required for most file systems

        Symbolic Link vs Hard Link:
        - Symbolic links can point to files or directories on different volumes/drives
        - Symbolic links can point to targets that don't exist
        - Symbolic links are resolved at access time
        - Hard links only work for files on the same volume and the target must exist

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/New-SymbolicLink.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/New-SymbolicLink.ps1

    .LINK
        Remove-SymbolicLink

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.management/new-item
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileSystemInfo])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$Path,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [Alias('Value', 'TargetPath')]
        [String]$Target,

        [Parameter()]
        [ValidateSet('Auto', 'File', 'Directory')]
        [String]$ItemType = 'Auto',

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        # Detect platform using cross-platform detection pattern from project instructions
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # PowerShell 5.1 - Windows only
            $script:IsWindowsPlatform = $true
        }
        else
        {
            # PowerShell Core - use built-in variables
            $script:IsWindowsPlatform = $IsWindows
        }

        Write-Verbose 'Starting symbolic link creation'
    }

    process
    {
        # Resolve paths using cross-platform compatible method
        $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $resolvedTarget = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target)

        Write-Verbose "Symbolic link path: $resolvedPath"
        Write-Verbose "Target path: $resolvedTarget"

        # Check if target exists
        $targetExists = Test-Path -Path $resolvedTarget
        if (-not $targetExists -and -not $Force)
        {
            Write-Error "Target path does not exist: $resolvedTarget. Use -Force to create symbolic links to non-existent targets."
            return
        }

        # Determine the item type for the symbolic link
        $linkType = 'SymbolicLink'
        if ($ItemType -eq 'Auto')
        {
            if ($targetExists)
            {
                $targetItem = Get-Item -Path $resolvedTarget -ErrorAction SilentlyContinue
                if ($targetItem.PSIsContainer)
                {
                    Write-Verbose 'Auto-detected target type: Directory'
                }
                else
                {
                    Write-Verbose 'Auto-detected target type: File'
                }
            }
            else
            {
                Write-Verbose 'Target does not exist, defaulting to file symbolic link'
            }
        }
        else
        {
            Write-Verbose "Using specified item type: $ItemType"
        }

        # Check if the symlink path already exists
        if (Test-Path -Path $resolvedPath)
        {
            if (-not $Force)
            {
                Write-Error "Path already exists: $resolvedPath. Use -Force to overwrite."
                return
            }

            # Remove the existing item if Force is specified
            if ($PSCmdlet.ShouldProcess($resolvedPath, 'Remove existing item'))
            {
                try
                {
                    $existingItem = Get-Item -Path $resolvedPath -Force
                    $isSymlink = $existingItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint

                    if ($isSymlink)
                    {
                        Write-Verbose "Removing existing symbolic link at: $resolvedPath"
                        # Do NOT use -Recurse on symbolic links, especially on Windows PowerShell 5.1.
                        # Using -Recurse on a directory symlink attempts to recurse into the target directory.
                        Remove-Item -Path $resolvedPath -Force -ErrorAction Stop
                    }
                    else
                    {
                        Write-Verbose "Removing existing item at: $resolvedPath"
                        # Only use -Recurse for non-symlink directories
                        Remove-Item -Path $resolvedPath -Force -Recurse -ErrorAction Stop
                    }
                }
                catch
                {
                    Write-Error "Failed to remove existing item at '$resolvedPath': $($_.Exception.Message)"
                    return
                }
            }
        }

        # Create the parent directory if it doesn't exist
        $parentPath = Split-Path -Path $resolvedPath -Parent
        if (-not [String]::IsNullOrEmpty($parentPath) -and -not (Test-Path -Path $parentPath))
        {
            if ($PSCmdlet.ShouldProcess($parentPath, 'Create parent directory'))
            {
                try
                {
                    New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
                    Write-Verbose "Created parent directory: $parentPath"
                }
                catch
                {
                    Write-Error "Failed to create parent directory '$parentPath': $($_.Exception.Message)"
                    return
                }
            }
        }

        # Create the symbolic link
        if ($PSCmdlet.ShouldProcess($resolvedPath, "Create symbolic link to '$resolvedTarget'"))
        {
            try
            {
                # PowerShell 5.1 on Windows has a limitation: New-Item cannot create symlinks to non-existent targets.
                # For non-existent targets on Windows PS 5.1, we need to use cmd.exe's mklink command.
                $useNativeCommand = $false
                if ($script:IsWindowsPlatform -and $PSVersionTable.PSVersion.Major -lt 6 -and -not $targetExists)
                {
                    Write-Verbose 'PowerShell 5.1 detected with non-existent target; using cmd.exe mklink'
                    $useNativeCommand = $true
                }

                if ($useNativeCommand)
                {
                    # Use cmd.exe mklink for PowerShell 5.1 with non-existent targets
                    $mklinkType = if ($ItemType -eq 'Auto' -or $ItemType -eq 'File') { '' } else { '/D' }
                    $cmdArgs = if ($mklinkType) { "/c mklink $mklinkType `"$resolvedPath`" `"$resolvedTarget`"" } else { "/c mklink `"$resolvedPath`" `"$resolvedTarget`"" }

                    Write-Verbose "Executing: cmd.exe $cmdArgs"
                    $processOutput = cmd.exe /c mklink $(if ($mklinkType) { $mklinkType }) "$resolvedPath" "$resolvedTarget" 2>&1
                    $exitCode = $LASTEXITCODE

                    if ($exitCode -ne 0)
                    {
                        throw "mklink failed with exit code $exitCode : $processOutput"
                    }

                    Write-Verbose "Successfully created symbolic link via mklink: $resolvedPath -> $resolvedTarget"

                    if ($PassThru)
                    {
                        return Get-Item -Path $resolvedPath -Force
                    }
                }
                else
                {
                    # Use New-Item for PowerShell Core or existing targets
                    $newItemParams = @{
                        Path = $resolvedPath
                        ItemType = $linkType
                        Value = $resolvedTarget
                        Force = $Force.IsPresent
                        ErrorAction = 'Stop'
                    }

                    $result = New-Item @newItemParams

                    Write-Verbose "Successfully created symbolic link: $resolvedPath -> $resolvedTarget"

                    if ($PassThru)
                    {
                        return $result
                    }
                }
            }
            catch
            {
                $errorMessage = $_.Exception.Message

                # Provide helpful error message for Windows privilege issues
                if ($script:IsWindowsPlatform -and ($errorMessage -match 'privilege' -or $errorMessage -match '1314' -or $errorMessage -match 'A required privilege is not held'))
                {
                    Write-Error @"
Failed to create symbolic link: $errorMessage

On Windows, creating symbolic links requires one of the following:

1. Run PowerShell as Administrator
2. Enable Developer Mode: Settings > Update & Security > For Developers > Developer Mode
3. Grant the 'Create symbolic links' privilege to your user account via Local Security Policy
"@
                }
                else
                {
                    Write-Error "Failed to create symbolic link '$resolvedPath' -> '$resolvedTarget': $errorMessage"
                }
            }
        }
    }

    end
    {
        Write-Verbose 'Symbolic link creation completed'
    }
}
