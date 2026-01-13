function Remove-SymbolicLink
{
    <#
    .SYNOPSIS
        Removes a symbolic link without deleting the target.

    .DESCRIPTION
        Safely removes a symbolic link (symlink) at the specified path without affecting the
        target file or directory that it points to. This function is cross-platform compatible
        and works on Windows, macOS, and Linux.

        The function validates that the specified path is actually a symbolic link before
        attempting removal, preventing accidental deletion of regular files or directories.

    .PARAMETER Path
        The path to the symbolic link to remove. This must be an existing symbolic link.
        Supports relative paths and tilde (~) expansion.
        Accepts pipeline input and can process multiple paths.

    .PARAMETER Force
        When specified, suppresses the validation that the path is a symbolic link and
        removes the item regardless. Use with caution as this could delete regular files
        or directories.

    .PARAMETER PassThru
        Returns information about the removed symbolic link including its former target.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs without actually removing the symbolic link.

    .PARAMETER Confirm
        Prompts for confirmation before removing the symbolic link.

    .EXAMPLE
        PS > Remove-SymbolicLink -Path '~/link-to-docs'

        Removes the symbolic link named 'link-to-docs' from the home directory.

    .EXAMPLE
        PS > Remove-SymbolicLink -Path 'C:\MyLink.txt' -PassThru

        Removes the symbolic link and returns information about what was removed.

    .EXAMPLE
        PS > Get-ChildItem -Path '~/links' | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | Remove-SymbolicLink

        Removes all symbolic links in the ~/links directory via pipeline.

    .EXAMPLE
        PS > Remove-SymbolicLink -Path './config', './data', './logs' -WhatIf

        Shows what would happen when removing multiple symbolic links.

    .EXAMPLE
        PS > 'link1', 'link2', 'link3' | Remove-SymbolicLink -Confirm

        Removes multiple symbolic links with confirmation prompts for each.

    .OUTPUTS
        None by default.
        [PSCustomObject] when -PassThru is specified, containing:
        - Path: The path of the removed symbolic link
        - Target: The target the symbolic link pointed to
        - ItemType: Whether it was a file or directory symbolic link
        - Removed: Boolean indicating successful removal

    .NOTES
        Symbolic Link Detection:
        - On all platforms, symbolic links have the ReparsePoint attribute
        - The function checks this attribute to verify the path is a symbolic link
        - Use -Force to bypass this check (not recommended)

        Safety Features:
        - Validates the path exists before attempting removal
        - Validates the path is a symbolic link (unless -Force is used)
        - Does not follow the symbolic link or affect the target
        - Supports -WhatIf and -Confirm for safe operation

        Cross-Platform Behavior:
        - Windows: Uses Remove-Item which properly handles reparse points
        - macOS/Linux: Uses Remove-Item which properly handles symbolic links

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Remove-SymbolicLink.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Remove-SymbolicLink.ps1

    .LINK
        New-SymbolicLink

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.management/remove-item
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('FullName', 'LiteralPath')]
        [String[]]$Path,

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        Write-Verbose 'Starting symbolic link removal'
        $results = [System.Collections.ArrayList]::new()
    }

    process
    {
        foreach ($symlinkPath in $Path)
        {
            # Resolve paths using cross-platform compatible method
            $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($symlinkPath)

            Write-Verbose "Processing symbolic link: $resolvedPath"

            # Check if the path exists
            if (-not (Test-Path -Path $resolvedPath))
            {
                Write-Error "Path not found: $resolvedPath"
                if ($PassThru)
                {
                    $result = [PSCustomObject]@{
                        Path = $resolvedPath
                        Target = $null
                        ItemType = $null
                        Removed = $false
                        Error = 'Path not found'
                    }
                    $null = $results.Add($result)
                }
                continue
            }

            # Get the item to check if it's a symbolic link
            # Note: On Windows PowerShell 5.1, Get-Item can have issues with directory symbolic links
            # where $item.Attributes may be null, causing NullReferenceException when checking attributes.
            # We use [System.IO.File]::GetAttributes() as a more reliable alternative.
            $item = $null
            $itemAttributes = $null
            try
            {
                $item = Get-Item -Path $resolvedPath -Force -ErrorAction Stop
                # Try to get attributes via .NET for more reliable detection on PS 5.1
                $itemAttributes = [System.IO.File]::GetAttributes($resolvedPath)
            }
            catch
            {
                # If Get-Item fails but path exists, try .NET approach for attributes
                if (Test-Path -Path $resolvedPath)
                {
                    try
                    {
                        $itemAttributes = [System.IO.File]::GetAttributes($resolvedPath)
                    }
                    catch
                    {
                        Write-Error "Failed to access item at '$resolvedPath': $($_.Exception.Message)"
                        if ($PassThru)
                        {
                            $result = [PSCustomObject]@{
                                Path = $resolvedPath
                                Target = $null
                                ItemType = $null
                                Removed = $false
                                Error = $_.Exception.Message
                            }
                            $null = $results.Add($result)
                        }
                        continue
                    }
                }
                else
                {
                    Write-Error "Failed to access item at '$resolvedPath': $($_.Exception.Message)"
                    if ($PassThru)
                    {
                        $result = [PSCustomObject]@{
                            Path = $resolvedPath
                            Target = $null
                            ItemType = $null
                            Removed = $false
                            Error = $_.Exception.Message
                        }
                        $null = $results.Add($result)
                    }
                    continue
                }
            }

            # Check if it's a symbolic link (ReparsePoint attribute)
            # Use .NET attributes for reliable detection, especially on Windows PowerShell 5.1
            $isSymbolicLink = $false
            if ($null -ne $itemAttributes)
            {
                $isSymbolicLink = $itemAttributes -band [System.IO.FileAttributes]::ReparsePoint
            }
            elseif ($null -ne $item -and $null -ne $item.Attributes)
            {
                $isSymbolicLink = $item.Attributes -band [System.IO.FileAttributes]::ReparsePoint
            }

            if (-not $isSymbolicLink -and -not $Force)
            {
                # Determine item type for error reporting
                $errorItemType = 'File'
                if ($null -ne $item -and $item.PSIsContainer)
                {
                    $errorItemType = 'Directory'
                }
                elseif ($null -ne $itemAttributes -and ($itemAttributes -band [System.IO.FileAttributes]::Directory))
                {
                    $errorItemType = 'Directory'
                }

                Write-Error "Path is not a symbolic link: $resolvedPath. Use -Force to remove anyway (not recommended)."
                if ($PassThru)
                {
                    $result = [PSCustomObject]@{
                        Path = $resolvedPath
                        Target = $null
                        ItemType = $errorItemType
                        Removed = $false
                        Error = 'Not a symbolic link'
                    }
                    $null = $results.Add($result)
                }
                continue
            }

            # Get the target of the symbolic link for reporting
            $linkTarget = $null
            # Determine item type - check $item first, fall back to .NET attributes
            $itemType = 'File'
            if ($null -ne $item -and $item.PSIsContainer)
            {
                $itemType = 'Directory'
            }
            elseif ($null -ne $itemAttributes -and ($itemAttributes -band [System.IO.FileAttributes]::Directory))
            {
                $itemType = 'Directory'
            }

            if ($isSymbolicLink)
            {
                try
                {
                    # PowerShell 6+ has LinkTarget property, PowerShell 5.1 needs different approach
                    if ($PSVersionTable.PSVersion.Major -ge 6)
                    {
                        $linkTarget = $item.LinkTarget
                    }
                    else
                    {
                        # For PowerShell 5.1 on Windows, use Target property if available
                        if ($item.Target)
                        {
                            $linkTarget = $item.Target
                        }
                    }
                }
                catch
                {
                    Write-Verbose "Could not determine symbolic link target: $($_.Exception.Message)"
                }
            }

            # Remove the symbolic link
            $actionDescription = if ($isSymbolicLink)
            {
                "Remove symbolic link (target: $linkTarget)"
            }
            else
            {
                'Remove item (Force mode - not a symbolic link)'
            }

            if ($PSCmdlet.ShouldProcess($resolvedPath, $actionDescription))
            {
                try
                {
                    # Remove the symbolic link
                    # Note: Directory symlinks on Windows PowerShell 5.1 can be problematic with Remove-Item.
                    # We use a multi-tier approach for reliable removal:
                    # 1. Try [System.IO.Directory]::Delete() for directory symlinks (most reliable on PS 5.1)
                    # 2. Fall back to cmd.exe rmdir for directory symlinks on Windows
                    # 3. Use Remove-Item as last resort

                    $removed = $false
                    $isDirectory = $itemType -eq 'Directory'

                    if ($isDirectory -and $PSVersionTable.PSVersion.Major -lt 6)
                    {
                        # Windows PowerShell 5.1 - use .NET method for directory symlinks
                        try
                        {
                            [System.IO.Directory]::Delete($resolvedPath)
                            $removed = $true
                            Write-Verbose "Removed directory symlink using .NET method: $resolvedPath"
                        }
                        catch
                        {
                            Write-Verbose ".NET Directory.Delete failed: $($_.Exception.Message). Trying cmd.exe rmdir..."

                            # Try cmd.exe rmdir as fallback for Windows
                            try
                            {
                                $null = cmd.exe /c "rmdir `"$resolvedPath`"" 2>&1
                                if (-not (Test-Path -Path $resolvedPath))
                                {
                                    $removed = $true
                                    Write-Verbose "Removed directory symlink using cmd.exe rmdir: $resolvedPath"
                                }
                            }
                            catch
                            {
                                Write-Verbose "cmd.exe rmdir failed: $($_.Exception.Message)"
                            }
                        }
                    }

                    # If not removed yet, use standard Remove-Item
                    if (-not $removed)
                    {
                        # IMPORTANT: Do NOT use -Recurse on symbolic links, especially on Windows PowerShell 5.1.
                        # Using -Recurse on a directory symlink attempts to recurse into the target directory,
                        # which can fail or delete target contents. We only remove the symlink itself.
                        Remove-Item -Path $resolvedPath -Force -ErrorAction Stop
                        $removed = $true
                    }

                    Write-Verbose "Successfully removed symbolic link: $resolvedPath"

                    if ($PassThru)
                    {
                        $result = [PSCustomObject]@{
                            Path = $resolvedPath
                            Target = $linkTarget
                            ItemType = $itemType
                            Removed = $true
                            Error = $null
                        }
                        $null = $results.Add($result)
                    }
                }
                catch
                {
                    Write-Error "Failed to remove symbolic link '$resolvedPath': $($_.Exception.Message)"

                    if ($PassThru)
                    {
                        $result = [PSCustomObject]@{
                            Path = $resolvedPath
                            Target = $linkTarget
                            ItemType = $itemType
                            Removed = $false
                            Error = $_.Exception.Message
                        }
                        $null = $results.Add($result)
                    }
                }
            }
            else
            {
                # WhatIf mode - still add to results if PassThru
                if ($PassThru)
                {
                    $result = [PSCustomObject]@{
                        Path = $resolvedPath
                        Target = $linkTarget
                        ItemType = $itemType
                        Removed = $false
                        Error = 'WhatIf mode - not removed'
                    }
                    $null = $results.Add($result)
                }
            }
        }
    }

    end
    {
        if ($PassThru)
        {
            return @($results)
        }

        Write-Verbose 'Symbolic link removal completed'
    }
}
