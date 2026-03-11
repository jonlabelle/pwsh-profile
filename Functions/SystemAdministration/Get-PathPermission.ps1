function Get-PathPermission
{
    <#
    .SYNOPSIS
        Shows file and directory permission details for one or more paths.

    .DESCRIPTION
        Retrieves permission metadata for files or directories, including symbolic permissions,
        octal values, ownership, and item type information.

        When -Recurse is specified for a directory path, the function returns permission
        details for the directory itself and all child items beneath it.

        On macOS/Linux, the function returns Unix-style permission fields such as:
        - Symbolic permissions (for example: -rwxr-xr-x)
        - Octal permissions (for example: 755)
        - Octal with special bits (for example: 0755)
        - Full mode octal including file type bits (for example: 100755)
        - Owner and group

        On Windows, Unix octal fields are not applicable and are returned as null.
        The function returns the file owner and a summarized ACL string, with optional
        detailed ACL rules when -IncludeAcl is specified.

    .PARAMETER Path
        One or more paths to inspect. Supports wildcards and pipeline input.
        If not specified, defaults to the current directory.

    .PARAMETER LiteralPath
        One or more literal paths to inspect. Wildcards are treated as literal characters.

    .PARAMETER Recurse
        When specified, recursively inspects directory paths and returns permission details
        for the directory itself and all child items. File paths are returned as-is.

    .PARAMETER IncludeAcl
        Includes detailed ACL rule objects in the AccessRules property.
        Primarily useful on Windows.

    .EXAMPLE
        PS > Get-PathPermission -Path ~/.ssh, ~/.config

        Displays permission details for both paths, including octal and symbolic values on Unix-like systems.

    .EXAMPLE
        PS > Get-ChildItem ./Functions/SystemAdministration | Get-PathPermission

        Retrieves permission details for each item from pipeline input.

    .EXAMPLE
        PS > Get-PathPermission -LiteralPath './file[1].txt'

        Retrieves permissions for a path that contains wildcard-like characters.

    .EXAMPLE
        PS > Get-PathPermission -Path ~/Projects -Recurse

        Retrieves permission details for the Projects directory and every file and
        subdirectory beneath it.

    .EXAMPLE
        PS > Get-PathPermission -Path . -IncludeAcl | Format-List

        Shows permission details for the current directory with expanded ACL rules.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Get-PathPermission.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Get-PathPermission.ps1
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Path', Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'PSPath')]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path = (Get-Location).Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName = $true)]
        [Alias('LP')]
        [ValidateNotNullOrEmpty()]
        [String[]]$LiteralPath,

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [Switch]$IncludeAcl
    )

    begin
    {
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # PowerShell 5.1 - Windows only
            $isWindowsPlatform = $true
            $isUnixPlatform = $false
        }
        else
        {
            # PowerShell Core - cross-platform
            $isWindowsPlatform = $IsWindows
            $isUnixPlatform = $IsLinux -or $IsMacOS
        }

        function ConvertTo-OctalString
        {
            param(
                [Parameter(Mandatory)]
                [Int32]$Value,

                [Parameter()]
                [ValidateRange(0, 12)]
                [Int32]$PadLeft = 0
            )

            $octalValue = [Convert]::ToString($Value, 8)
            if ($PadLeft -gt 0)
            {
                $octalValue = $octalValue.PadLeft($PadLeft, '0')
            }

            return $octalValue
        }

        function Get-ResolvedPaths
        {
            param(
                [Parameter(Mandatory)]
                [String]$InputPath,

                [Parameter(Mandatory)]
                [Boolean]$UseLiteralPath
            )

            if ($UseLiteralPath)
            {
                return @($InputPath)
            }

            try
            {
                return @(Resolve-Path -Path $InputPath -ErrorAction Stop | Select-Object -ExpandProperty Path)
            }
            catch
            {
                $message = "Path not found: $InputPath"
                $exception = New-Object System.IO.FileNotFoundException($message)
                $errorRecord = New-Object System.Management.Automation.ErrorRecord(
                    $exception,
                    'PathNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $InputPath
                )
                $PSCmdlet.WriteError($errorRecord)
                return @()
            }
        }

        function Get-ItemTypeName
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item
            )

            $linkTypeProperty = $Item.PSObject.Properties['LinkType']
            if ($linkTypeProperty -and -not [String]::IsNullOrWhiteSpace([String]$linkTypeProperty.Value))
            {
                return [String]$linkTypeProperty.Value
            }

            if ($Item.PSIsContainer)
            {
                return 'Directory'
            }

            if ($Item -is [System.IO.FileInfo])
            {
                return 'File'
            }

            return $Item.GetType().Name
        }

        function Get-TargetItems
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item,

                [Parameter(Mandatory)]
                [Boolean]$IncludeDescendants
            )

            $items = New-Object 'System.Collections.Generic.List[System.IO.FileSystemInfo]'
            $items.Add($Item)

            if (-not $IncludeDescendants -or -not $Item.PSIsContainer)
            {
                return $items.ToArray()
            }

            try
            {
                foreach ($childItem in (Get-ChildItem -LiteralPath $Item.FullName -Recurse -Force))
                {
                    if ($childItem -is [System.IO.FileSystemInfo])
                    {
                        $items.Add($childItem)
                    }
                }
            }
            catch
            {
                $PSCmdlet.WriteError($_)
            }

            return $items.ToArray()
        }

        function Get-AclSummary
        {
            param(
                [Parameter(Mandatory)]
                [Object]$Acl
            )

            $entries = @(
                $Acl.Access |
                Select-Object -Property IdentityReference, AccessControlType, FileSystemRights |
                Sort-Object -Property IdentityReference, AccessControlType, FileSystemRights -Unique |
                ForEach-Object {
                    '{0}:{1}:{2}' -f $_.IdentityReference, $_.AccessControlType, $_.FileSystemRights
                }
            )

            if ($entries.Count -eq 0)
            {
                return $null
            }

            return [String]::Join('; ', $entries)
        }
    }

    process
    {
        $useLiteralPath = $PSCmdlet.ParameterSetName -eq 'LiteralPath'
        $inputPaths = if ($useLiteralPath) { @($LiteralPath) } else { @($Path) }

        foreach ($inputPath in $inputPaths)
        {
            if ([String]::IsNullOrWhiteSpace($inputPath))
            {
                continue
            }

            $resolvedPaths = Get-ResolvedPaths -InputPath $inputPath -UseLiteralPath $useLiteralPath
            foreach ($resolvedPath in $resolvedPaths)
            {
                try
                {
                    $item = Get-Item -LiteralPath $resolvedPath -Force -ErrorAction Stop
                }
                catch
                {
                    $PSCmdlet.WriteError($_)
                    continue
                }

                if ($item.PSProvider.Name -ne 'FileSystem' -or $item -isnot [System.IO.FileSystemInfo])
                {
                    $message = "Path '$resolvedPath' is not a filesystem path. Only filesystem paths are supported."
                    $exception = New-Object System.InvalidOperationException($message)
                    $errorRecord = New-Object System.Management.Automation.ErrorRecord(
                        $exception,
                        'UnsupportedProvider',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $resolvedPath
                    )
                    $PSCmdlet.WriteError($errorRecord)
                    continue
                }

                foreach ($targetItem in (Get-TargetItems -Item $item -IncludeDescendants $Recurse.IsPresent))
                {
                    $itemType = Get-ItemTypeName -Item $targetItem
                    $owner = $null
                    $group = $null
                    $symbolic = $null
                    $permissions = $null
                    $ownerPermissions = $null
                    $groupPermissions = $null
                    $otherPermissions = $null
                    $octal = $null
                    $octalWithSpecial = $null
                    $fullOctal = $null
                    $specialFlags = $null
                    $accessSummary = $null
                    $accessRules = $null

                    if ($isUnixPlatform -and $targetItem.PSObject.Properties['UnixStat'])
                    {
                        $unixStat = $targetItem.UnixStat
                        $owner = [String]$targetItem.User
                        $group = [String]$targetItem.Group

                        $symbolic = if ($targetItem.PSObject.Properties['UnixMode'])
                        {
                            [String]$targetItem.UnixMode
                        }
                        else
                        {
                            [String]$unixStat.GetModeString()
                        }

                        if (-not [String]::IsNullOrWhiteSpace($symbolic) -and $symbolic.Length -ge 10)
                        {
                            $permissions = $symbolic.Substring(1, 9)
                            $ownerPermissions = $permissions.Substring(0, 3)
                            $groupPermissions = $permissions.Substring(3, 3)
                            $otherPermissions = $permissions.Substring(6, 3)
                        }

                        $modeValue = [Int32]$unixStat.Mode
                        $permissionBits = $modeValue -band 511
                        $permissionAndSpecialBits = $modeValue -band 4095

                        $octal = ConvertTo-OctalString -Value $permissionBits -PadLeft 3
                        $octalWithSpecial = ConvertTo-OctalString -Value $permissionAndSpecialBits -PadLeft 4
                        $fullOctal = ConvertTo-OctalString -Value $modeValue

                        $flags = New-Object 'System.Collections.Generic.List[string]'
                        if ($unixStat.IsSetUid) { $flags.Add('setuid') }
                        if ($unixStat.IsSetGid) { $flags.Add('setgid') }
                        if ($unixStat.IsSticky) { $flags.Add('sticky') }
                        if ($flags.Count -gt 0)
                        {
                            $specialFlags = [String]::Join(',', $flags)
                        }
                    }
                    elseif ($isWindowsPlatform)
                    {
                        try
                        {
                            $acl = Get-Acl -LiteralPath $targetItem.FullName -ErrorAction Stop
                            $owner = [String]$acl.Owner
                            $groupProperty = $acl.PSObject.Properties['Group']
                            if ($groupProperty -and $null -ne $groupProperty.Value)
                            {
                                $group = [String]$groupProperty.Value
                            }

                            $accessSummary = Get-AclSummary -Acl $acl

                            if ($IncludeAcl)
                            {
                                $accessRules = @(
                                    $acl.Access |
                                    Select-Object -Property IdentityReference, AccessControlType, FileSystemRights, IsInherited, InheritanceFlags, PropagationFlags
                                )
                            }
                        }
                        catch
                        {
                            Write-Verbose "Failed to read ACL for '$($targetItem.FullName)': $($_.Exception.Message)"
                        }
                    }

                    [PSCustomObject]@{
                        InputPath = $inputPath
                        Path = $targetItem.FullName
                        ItemType = $itemType
                        Owner = $owner
                        Group = $group
                        Symbolic = $symbolic
                        Permissions = $permissions
                        OwnerPermissions = $ownerPermissions
                        GroupPermissions = $groupPermissions
                        OtherPermissions = $otherPermissions
                        Octal = $octal
                        OctalWithSpecial = $octalWithSpecial
                        FullOctal = $fullOctal
                        SpecialFlags = $specialFlags
                        Mode = [String]$targetItem.Mode
                        Attributes = [String]$targetItem.Attributes
                        AccessSummary = $accessSummary
                        AccessRules = $accessRules
                    }
                }
            }
        }
    }
}
