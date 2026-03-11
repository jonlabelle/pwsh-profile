function Set-PathPermission
{
    <#
    .SYNOPSIS
        Sets filesystem permissions for files and directories.

    .DESCRIPTION
        Applies permission changes to one or more filesystem paths using a portable
        permission model by default, with advanced platform-specific escape hatches
        when needed.

        The default cross-platform API uses named permissions instead of raw chmod
        characters or Windows ACL flags:
        - OwnerPermission
        - GroupPermission
        - OtherPermission

        These parameters accept Read, Write, Execute, or None. On macOS and Linux,
        they translate to owner/group/other mode bits. On Windows, they translate
        to explicit ACL rules for the file owner, the ACL group, and Everyone.

        The portable API intentionally standardizes on Read, Write, and Execute.
        Delete is not included there because it does not mean the same thing across
        platforms: on Unix-like systems deletion is controlled by the parent directory,
        while on Windows it is a file or directory ACL right. For advanced scenarios
        such as Delete, Modify, FullControl, deny rules, or raw chmod modes, use the
        advanced parameter sets:
        -Mode on macOS/Linux
        -Identity with -Permission or -Rights on Windows

        The Windows-only Identity parameter is intentionally not exposed on macOS/Linux.
        Unix-style permissions are based on owner/group/other mode bits, while arbitrary
        named identities require platform-specific ACLs. Changing the owning user or group
        is also a separate operation from setting permissions.

        Use -Recurse to apply changes to a directory and all child items beneath it.
        Supports -WhatIf and -Confirm via ShouldProcess.

        When -Idempotent is specified, the function first inspects the current item
        with Get-PathPermission and skips updates for targets that already match the
        requested permission state.

    .PARAMETER Path
        One or more paths to update. Supports wildcards and pipeline input.

    .PARAMETER LiteralPath
        One or more literal paths to update. Wildcards are treated as literal characters.

    .PARAMETER OwnerPermission
        Cross-platform. Sets permissions for the owner role using named permissions:
        Read, Write, Execute, or None.

        On macOS/Linux, this updates the owner mode bits.
        On Windows, this updates the explicit ACL rule for the current item owner.

    .PARAMETER GroupPermission
        Cross-platform. Sets permissions for the group role using named permissions:
        Read, Write, Execute, or None.

        On macOS/Linux, this updates the group mode bits.
        On Windows, this updates the explicit ACL rule for the ACL group identity.

    .PARAMETER OtherPermission
        Cross-platform. Sets permissions for the everyone/other role using named permissions:
        Read, Write, Execute, or None.

        On macOS/Linux, this updates the "other" mode bits.
        On Windows, this updates the explicit ACL rule for Everyone.

    .PARAMETER Mode
        Advanced macOS/Linux-only escape hatch. Applies a raw chmod-compatible mode.
        Examples: 644, 0755, u=rw,go=, u+rwx,go-rwx

    .PARAMETER Identity
        Advanced Windows-only parameter. The user or group identity to grant, deny,
        or replace permissions for.

        This parameter is Windows-only because Windows exposes first-class per-identity
        filesystem ACL rules. On macOS/Linux, named identities would require platform-
        specific ACL support, while owner/group changes are separate chown/chgrp-style
        operations rather than permission grants.

    .PARAMETER Permission
        Advanced Windows-only parameter. Uses the same portable named permissions as
        the cross-platform API, but applies them to a specific Windows identity.
        Accepts Read, Write, Execute, or None.

    .PARAMETER Rights
        Advanced Windows-only escape hatch. One or more raw FileSystemRights values
        to apply for the specified identity. Use this for permissions such as Delete,
        Modify, or FullControl.

    .PARAMETER AccessType
        Advanced Windows-only parameter. Specifies whether the rule should Allow or
        Deny the requested permissions. Defaults to Allow.

    .PARAMETER Idempotent
        Checks the current permission state before applying changes and skips targets
        that already match the requested permissions.

        This uses Get-PathPermission to inspect the existing state.

        For raw Unix -Mode updates, -Idempotent currently supports numeric octal modes
        such as 600, 0644, or 4755. Symbolic chmod expressions are not supported with
        -Idempotent because they do not describe a single fixed target state.

    .PARAMETER Recurse
        Applies the permission change to the target item and all child items when the
        target is a directory.

    .PARAMETER PassThru
        Returns a PSCustomObject describing each updated item.

    .EXAMPLE
        PS > Set-PathPermission -Path ~/.ssh/config -OwnerPermission Read, Write -GroupPermission None -OtherPermission None

        Sets a private file permission model using the portable API.

    .EXAMPLE
        PS > Set-PathPermission -Path ~/Projects/shared.txt -OwnerPermission Read, Write -GroupPermission Read -OtherPermission Read

        Creates a 644-style permission layout using named permissions instead of octal notation.

    .EXAMPLE
        PS > Set-PathPermission -Path ~/bin/tool.sh -OwnerPermission Read, Write, Execute -GroupPermission Read, Execute -OtherPermission Read, Execute

        Creates a 755-style executable permission layout using the portable API.

    .EXAMPLE
        PS > Set-PathPermission -LiteralPath './file[1].txt' -OwnerPermission Read, Write -GroupPermission Read -OtherPermission None

        Updates a literal path that contains wildcard-like characters.

    .EXAMPLE
        PS > Get-ChildItem ./Functions/SystemAdministration -File | Set-PathPermission -OwnerPermission Read, Write -GroupPermission Read -OtherPermission Read

        Uses pipeline input to apply a shared read-only layout to several files.

    .EXAMPLE
        PS > Set-PathPermission -Path ~/Projects/private -OwnerPermission Read, Write, Execute -GroupPermission None -OtherPermission None -Recurse

        Applies a private directory layout recursively.

    .EXAMPLE
        PS > Set-PathPermission -OwnerPermission Read, Write, Execute -GroupPermission Read, Execute -OtherPermission Read, Execute

        Applies permissions to the current directory because -Path defaults to the current location.

    .EXAMPLE
        PS > Set-PathPermission -Path ~/Projects/private -OwnerPermission Read, Write, Execute -GroupPermission None -OtherPermission None -WhatIf

        Previews a portable recursive permission change without modifying any files.

    .EXAMPLE
        PS > Set-PathPermission -Path ~/.ssh/config -OwnerPermission Read, Write -GroupPermission None -OtherPermission None -Idempotent

        Skips the update when the file already matches the requested permission state.

    .EXAMPLE
        PS > Set-PathPermission -Path ~/bin/tool.sh -OwnerPermission Read, Write, Execute -GroupPermission Read, Execute -OtherPermission Read, Execute -PassThru

        Applies a portable permission model and returns a summary object for the changed item.

    .EXAMPLE
        PS > Set-PathPermission -Path ~/.ssh/config -Mode 600

        On macOS or Linux, uses the advanced raw chmod mode escape hatch.

    .EXAMPLE
        PS > Set-PathPermission -Path ~/.ssh/config -Mode 600 -Idempotent

        On macOS or Linux, skips the raw chmod operation when the numeric mode already matches.

    .EXAMPLE
        PS > Set-PathPermission -Path ~/Projects/scripts -Mode 'u=rwx,go=rx' -Recurse

        On macOS or Linux, uses symbolic chmod syntax for a recursive change.

    .EXAMPLE
        PS > $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        PS > Set-PathPermission -Path "$env:TEMP\example.txt" -Identity $currentUser -Permission Read, Write

        On Windows, applies named permissions to a specific identity instead of the owner/group/other roles.

    .EXAMPLE
        PS > Set-PathPermission -LiteralPath 'C:\Temp\file[1].txt' -Identity 'BUILTIN\Users' -Permission Read

        On Windows, applies a named permission rule to a literal path.

    .EXAMPLE
        PS > $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        PS > Set-PathPermission -Path "$env:TEMP\important.log" -Identity $currentUser -Permission Write -AccessType Deny

        On Windows, creates or replaces an explicit Deny rule using named permissions.

    .EXAMPLE
        PS > Set-PathPermission -Path "$env:TEMP\Example" -Identity 'BUILTIN\Administrators' -Rights FullControl

        On Windows, uses the advanced raw ACL escape hatch for FullControl.

    .EXAMPLE
        PS > Set-PathPermission -Path "$env:TEMP\important.log" -Identity 'BUILTIN\Users' -Rights Delete

        On Windows, uses raw FileSystemRights for Delete, which is intentionally not part of the portable API.

    .EXAMPLE
        PS > $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        PS > Set-PathPermission -Path "$env:TEMP\Reports" -Identity $currentUser -Permission Read, Write -Recurse -PassThru

        On Windows, applies named permissions to a specific identity recursively and returns summary objects.

    .OUTPUTS
        None by default.
        When -PassThru is specified, returns System.Management.Automation.PSCustomObject.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Set-PathPermission.ps1

        - PowerShell 5.1 is supported on Windows via ACL operations
        - macOS/Linux use the native chmod executable for raw mode changes
        - The default API uses named permissions rather than rwx abbreviations
        - Delete, Modify, and FullControl remain advanced Windows ACL scenarios
        - Idempotent raw Unix -Mode checks currently support numeric octal modes only

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Set-PathPermission.ps1

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.security/set-acl
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'PortablePath')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'PortablePath', Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Parameter(ParameterSetName = 'ModePath', Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Parameter(ParameterSetName = 'IdentityPermissionPath', Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Parameter(ParameterSetName = 'RightsPath', Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'PSPath')]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path = (Get-Location).Path,

        [Parameter(Mandatory, ParameterSetName = 'PortableLiteralPath', ValueFromPipelineByPropertyName = $true)]
        [Parameter(Mandatory, ParameterSetName = 'ModeLiteralPath', ValueFromPipelineByPropertyName = $true)]
        [Parameter(Mandatory, ParameterSetName = 'IdentityPermissionLiteralPath', ValueFromPipelineByPropertyName = $true)]
        [Parameter(Mandatory, ParameterSetName = 'RightsLiteralPath', ValueFromPipelineByPropertyName = $true)]
        [Alias('LP')]
        [ValidateNotNullOrEmpty()]
        [String[]]$LiteralPath,

        [Parameter(ParameterSetName = 'PortablePath')]
        [Parameter(ParameterSetName = 'PortableLiteralPath')]
        [ValidateSet('None', 'Read', 'Write', 'Execute')]
        [String[]]$OwnerPermission,

        [Parameter(ParameterSetName = 'PortablePath')]
        [Parameter(ParameterSetName = 'PortableLiteralPath')]
        [ValidateSet('None', 'Read', 'Write', 'Execute')]
        [String[]]$GroupPermission,

        [Parameter(ParameterSetName = 'PortablePath')]
        [Parameter(ParameterSetName = 'PortableLiteralPath')]
        [ValidateSet('None', 'Read', 'Write', 'Execute')]
        [String[]]$OtherPermission,

        [Parameter(Mandatory, ParameterSetName = 'ModePath')]
        [Parameter(Mandatory, ParameterSetName = 'ModeLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [String]$Mode,

        [Parameter(Mandatory, ParameterSetName = 'IdentityPermissionPath')]
        [Parameter(Mandatory, ParameterSetName = 'IdentityPermissionLiteralPath')]
        [Parameter(Mandatory, ParameterSetName = 'RightsPath')]
        [Parameter(Mandatory, ParameterSetName = 'RightsLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [String]$Identity,

        [Parameter(Mandatory, ParameterSetName = 'IdentityPermissionPath')]
        [Parameter(Mandatory, ParameterSetName = 'IdentityPermissionLiteralPath')]
        [ValidateSet('None', 'Read', 'Write', 'Execute')]
        [String[]]$Permission,

        [Parameter(ParameterSetName = 'IdentityPermissionPath')]
        [Parameter(ParameterSetName = 'IdentityPermissionLiteralPath')]
        [Parameter(ParameterSetName = 'RightsPath')]
        [Parameter(ParameterSetName = 'RightsLiteralPath')]
        [System.Security.AccessControl.AccessControlType]$AccessType = [System.Security.AccessControl.AccessControlType]::Allow,

        [Parameter(Mandatory, ParameterSetName = 'RightsPath')]
        [Parameter(Mandatory, ParameterSetName = 'RightsLiteralPath')]
        [ValidateNotNullOrEmpty()]
        [System.Security.AccessControl.FileSystemRights[]]$Rights,

        [Parameter()]
        [Switch]$Idempotent,

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $isWindowsPlatform = $true
            $isUnixPlatform = $false
        }
        else
        {
            $isWindowsPlatform = $IsWindows
            $isUnixPlatform = $IsLinux -or $IsMacOS
        }

        $portableParameterSetNames = @('PortablePath', 'PortableLiteralPath')
        $modeParameterSetNames = @('ModePath', 'ModeLiteralPath')
        $identityPermissionParameterSetNames = @('IdentityPermissionPath', 'IdentityPermissionLiteralPath')
        $rightsParameterSetNames = @('RightsPath', 'RightsLiteralPath')
        $portablePermissionOrder = @('Read', 'Write', 'Execute', 'None')

        $isPortableOperation = $portableParameterSetNames -contains $PSCmdlet.ParameterSetName
        $isModeOperation = $modeParameterSetNames -contains $PSCmdlet.ParameterSetName
        $isIdentityPermissionOperation = $identityPermissionParameterSetNames -contains $PSCmdlet.ParameterSetName
        $isRightsOperation = $rightsParameterSetNames -contains $PSCmdlet.ParameterSetName
        $hasOwnerPermission = $PSBoundParameters.ContainsKey('OwnerPermission')
        $hasGroupPermission = $PSBoundParameters.ContainsKey('GroupPermission')
        $hasOtherPermission = $PSBoundParameters.ContainsKey('OtherPermission')
        $chmodCommand = $null
        $getPathPermissionCommand = $null

        if ($isPortableOperation -and -not ($hasOwnerPermission -or $hasGroupPermission -or $hasOtherPermission))
        {
            throw 'Specify at least one of -OwnerPermission, -GroupPermission, or -OtherPermission.'
        }

        if ($isModeOperation -and -not $isUnixPlatform)
        {
            throw 'The -Mode parameter is only supported on macOS and Linux.'
        }

        if (($isIdentityPermissionOperation -or $isRightsOperation) -and -not $isWindowsPlatform)
        {
            throw 'Advanced identity-based permission changes are only supported on Windows. Use the portable owner/group/other parameters or -Mode on macOS/Linux.'
        }

        if ($isModeOperation -or ($isPortableOperation -and $isUnixPlatform))
        {
            $chmodCommand = Get-Command -Name 'chmod' -CommandType Application -ErrorAction SilentlyContinue
            if (-not $chmodCommand)
            {
                throw 'The chmod executable was not found in PATH. Install chmod or ensure it is available before using -Mode.'
            }
        }

        if ($Idempotent)
        {
            $getPathPermissionCommand = Get-Command -Name 'Get-PathPermission' -ErrorAction SilentlyContinue
            if (-not $getPathPermissionCommand)
            {
                throw 'The -Idempotent switch requires Get-PathPermission to be available in the current session.'
            }
        }

        function Resolve-PortablePermissions
        {
            param(
                [Parameter()]
                [String[]]$Permissions
            )

            if ($null -eq $Permissions -or $Permissions.Count -eq 0)
            {
                return $null
            }

            $present = @{}
            foreach ($permission in @($Permissions))
            {
                if ([String]::IsNullOrWhiteSpace([String]$permission))
                {
                    continue
                }

                $matchedPermission = $portablePermissionOrder | Where-Object { $_ -ieq $permission } | Select-Object -First 1
                if ($matchedPermission)
                {
                    $present[$matchedPermission] = $true
                }
            }

            if ($present.Count -eq 0)
            {
                return $null
            }

            if ($present.ContainsKey('None') -and $present.Count -gt 1)
            {
                throw "Permission value 'None' cannot be combined with Read, Write, or Execute."
            }

            return @($portablePermissionOrder | Where-Object { $present.ContainsKey($_) })
        }

        function Format-PortablePermissions
        {
            param(
                [Parameter()]
                [String[]]$Permissions
            )

            $normalizedPermissions = Resolve-PortablePermissions -Permissions $Permissions
            if ($null -eq $normalizedPermissions)
            {
                return $null
            }

            return [String]::Join(', ', $normalizedPermissions)
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

        function ConvertTo-UnixPermissionDigit
        {
            param(
                [Parameter()]
                [String[]]$Permissions
            )

            $normalizedPermissions = Resolve-PortablePermissions -Permissions $Permissions
            if ($null -eq $normalizedPermissions)
            {
                return $null
            }

            if ($normalizedPermissions.Count -eq 1 -and $normalizedPermissions[0] -eq 'None')
            {
                return '0'
            }

            $permissionValue = 0
            if ($normalizedPermissions -contains 'Read') { $permissionValue += 4 }
            if ($normalizedPermissions -contains 'Write') { $permissionValue += 2 }
            if ($normalizedPermissions -contains 'Execute') { $permissionValue += 1 }

            return [String]$permissionValue
        }

        function ConvertTo-UnixPermissionSegment
        {
            param(
                [Parameter()]
                [String[]]$Permissions
            )

            $normalizedPermissions = Resolve-PortablePermissions -Permissions $Permissions
            if ($null -eq $normalizedPermissions -or ($normalizedPermissions.Count -eq 1 -and $normalizedPermissions[0] -eq 'None'))
            {
                return '---'
            }

            return '{0}{1}{2}' -f `
            $(if ($normalizedPermissions -contains 'Read') { 'r' } else { '-' }), `
            $(if ($normalizedPermissions -contains 'Write') { 'w' } else { '-' }), `
            $(if ($normalizedPermissions -contains 'Execute') { 'x' } else { '-' })
        }

        function Get-NormalizedUnixRawMode
        {
            param(
                [Parameter(Mandatory)]
                [String]$RequestedMode
            )

            if ($RequestedMode -match '^[0-7]{3}$')
            {
                return "0$RequestedMode"
            }

            if ($RequestedMode -match '^[0-7]{4}$')
            {
                return $RequestedMode
            }

            return $null
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

        function Get-PermissionSnapshot
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item,

                [Parameter()]
                [Switch]$IncludeAcl
            )

            if (-not $Idempotent)
            {
                return $null
            }

            return & $getPathPermissionCommand -LiteralPath $Item.FullName -IncludeAcl:$IncludeAcl
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

        function Join-ExternalCommandOutput
        {
            param(
                [Parameter()]
                [Object[]]$Output
            )

            if ($null -eq $Output -or $Output.Count -eq 0)
            {
                return $null
            }

            return [String]::Join(
                [Environment]::NewLine,
                @($Output | ForEach-Object {
                        if ($null -eq $_)
                        {
                            return ''
                        }

                        return $_.ToString().TrimEnd()
                    })
            ).Trim()
        }

        function Get-CurrentUnixPermissionDigits
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item
            )

            if (-not $Item.PSObject.Properties['UnixStat'] -or $null -eq $Item.UnixStat)
            {
                throw "Unix permission metadata is not available for '$($Item.FullName)'."
            }

            $modeValue = [Int32]$Item.UnixStat.Mode
            $permissionAndSpecialBits = $modeValue -band 4095
            $octalWithSpecial = ConvertTo-OctalString -Value $permissionAndSpecialBits -PadLeft 4

            return @{
                Special = $octalWithSpecial.Substring(0, 1)
                Owner = $octalWithSpecial.Substring(1, 1)
                Group = $octalWithSpecial.Substring(2, 1)
                Other = $octalWithSpecial.Substring(3, 1)
            }
        }

        function Invoke-UnixModeChange
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item,

                [Parameter(Mandatory)]
                [String]$RequestedMode,

                [Parameter(Mandatory)]
                [String]$OperationDescription
            )

            $modeForOutput = $RequestedMode
            if ($Idempotent)
            {
                $normalizedRequestedMode = Get-NormalizedUnixRawMode -RequestedMode $RequestedMode
                if ($null -eq $normalizedRequestedMode)
                {
                    throw 'The -Idempotent switch currently supports raw -Mode values only when they are numeric octal permissions such as 600, 0644, or 4755.'
                }

                $modeForOutput = $normalizedRequestedMode
                $permissionInfo = Get-PermissionSnapshot -Item $Item
                if ($permissionInfo.OctalWithSpecial -eq $normalizedRequestedMode)
                {
                    Write-Verbose "Skipping '$($Item.FullName)' because the requested permissions are already present."
                    return @{
                        Applied = $false
                        Skipped = $true
                        Reason = 'AlreadyCompliant'
                        Mode = $normalizedRequestedMode
                    }
                }
            }

            if (-not $PSCmdlet.ShouldProcess($Item.FullName, $OperationDescription))
            {
                return @{
                    Applied = $false
                    Skipped = $false
                    Reason = $null
                    Mode = $modeForOutput
                }
            }

            $commandOutput = @()
            try
            {
                $commandOutput = & $($chmodCommand.Path) $RequestedMode $Item.FullName 2>&1
                if ($LASTEXITCODE -ne 0)
                {
                    $message = Join-ExternalCommandOutput -Output $commandOutput
                    if ([String]::IsNullOrWhiteSpace($message))
                    {
                        $message = "chmod exited with code $LASTEXITCODE."
                    }

                    $exception = New-Object System.InvalidOperationException("Failed to set permissions on '$($Item.FullName)': $message")
                    $errorRecord = New-Object System.Management.Automation.ErrorRecord(
                        $exception,
                        'PermissionChangeFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $Item.FullName
                    )
                    $PSCmdlet.WriteError($errorRecord)
                    return @{
                        Applied = $false
                        Skipped = $false
                        Reason = $null
                        Mode = $modeForOutput
                    }
                }

                return @{
                    Applied = $true
                    Skipped = $false
                    Reason = $null
                    Mode = $modeForOutput
                }
            }
            catch
            {
                $PSCmdlet.WriteError($_)
                return @{
                    Applied = $false
                    Skipped = $false
                    Reason = $null
                    Mode = $modeForOutput
                }
            }
        }

        function ConvertTo-WindowsPortableRights
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item,

                [Parameter()]
                [String[]]$Permissions
            )

            $normalizedPermissions = Resolve-PortablePermissions -Permissions $Permissions
            if ($null -eq $normalizedPermissions)
            {
                return [System.Security.AccessControl.FileSystemRights]0
            }

            if ($normalizedPermissions.Count -eq 1 -and $normalizedPermissions[0] -eq 'None')
            {
                return [System.Security.AccessControl.FileSystemRights]0
            }

            $rightsValue = [System.Security.AccessControl.FileSystemRights]0
            if ($normalizedPermissions -contains 'Read')
            {
                $rightsValue = $rightsValue -bor [System.Security.AccessControl.FileSystemRights]::Read
            }

            if ($normalizedPermissions -contains 'Write')
            {
                $rightsValue = $rightsValue -bor [System.Security.AccessControl.FileSystemRights]::Write
            }

            if ($normalizedPermissions -contains 'Execute')
            {
                $executeRight = if ($Item.PSIsContainer)
                {
                    [System.Security.AccessControl.FileSystemRights]::Traverse
                }
                else
                {
                    [System.Security.AccessControl.FileSystemRights]::ExecuteFile
                }

                $rightsValue = $rightsValue -bor $executeRight
            }

            return $rightsValue
        }

        function Get-WindowsExplicitRuleRights
        {
            param(
                [Parameter()]
                [Object[]]$AccessRules,

                [Parameter(Mandatory)]
                [String]$TargetIdentity,

                [Parameter(Mandatory)]
                [System.Security.AccessControl.AccessControlType]$RuleAccessType
            )

            $combinedRights = [System.Security.AccessControl.FileSystemRights]0
            foreach ($accessRule in @($AccessRules))
            {
                if ($null -eq $accessRule)
                {
                    continue
                }

                if ($accessRule.IsInherited)
                {
                    continue
                }

                if ([String]$accessRule.IdentityReference -ne $TargetIdentity)
                {
                    continue
                }

                if ([String]$accessRule.AccessControlType -ne [String]$RuleAccessType)
                {
                    continue
                }

                $combinedRights = $combinedRights -bor ([System.Security.AccessControl.FileSystemRights]$accessRule.FileSystemRights)
            }

            return $combinedRights
        }

        function Get-ExplicitAccessRules
        {
            param(
                [Parameter(Mandatory)]
                [Object]$Acl,

                [Parameter(Mandatory)]
                [String]$TargetIdentity,

                [Parameter(Mandatory)]
                [System.Security.AccessControl.AccessControlType]$RuleAccessType
            )

            return @(
                $Acl.Access | Where-Object {
                    -not $_.IsInherited -and
                    [String]$_.IdentityReference -eq $TargetIdentity -and
                    $_.AccessControlType -eq $RuleAccessType
                }
            )
        }

        function ConvertTo-WindowsAccessRule
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item,

                [Parameter(Mandatory)]
                [String]$TargetIdentity,

                [Parameter(Mandatory)]
                [System.Security.AccessControl.FileSystemRights]$RuleRights,

                [Parameter(Mandatory)]
                [System.Security.AccessControl.AccessControlType]$RuleAccessType
            )

            if ($Item.PSIsContainer)
            {
                return New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $TargetIdentity,
                    $RuleRights,
                    [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
                    [System.Security.AccessControl.PropagationFlags]::None,
                    $RuleAccessType
                )
            }

            return New-Object System.Security.AccessControl.FileSystemAccessRule(
                $TargetIdentity,
                $RuleRights,
                $RuleAccessType
            )
        }

        function ConvertTo-NormalizedWindowsRuleRights
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item,

                [Parameter(Mandatory)]
                [String]$TargetIdentity,

                [Parameter(Mandatory)]
                [System.Security.AccessControl.FileSystemRights]$RuleRights,

                [Parameter(Mandatory)]
                [System.Security.AccessControl.AccessControlType]$RuleAccessType
            )

            if ([Int64]$RuleRights -eq 0)
            {
                return [System.Security.AccessControl.FileSystemRights]0
            }

            $rule = ConvertTo-WindowsAccessRule -Item $Item -TargetIdentity $TargetIdentity -RuleRights $RuleRights -RuleAccessType $RuleAccessType
            return [System.Security.AccessControl.FileSystemRights]$rule.FileSystemRights
        }

        function Invoke-UnixPortablePermissionChange
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item
            )

            try
            {
                $currentDigits = Get-CurrentUnixPermissionDigits -Item $Item
            }
            catch
            {
                $PSCmdlet.WriteError($_)
                return @{
                    Applied = $false
                }
            }

            $resolvedOwnerPermission = Resolve-PortablePermissions -Permissions $OwnerPermission
            $resolvedGroupPermission = Resolve-PortablePermissions -Permissions $GroupPermission
            $resolvedOtherPermission = Resolve-PortablePermissions -Permissions $OtherPermission

            $targetOwnerDigit = if ($hasOwnerPermission)
            {
                ConvertTo-UnixPermissionDigit -Permissions $resolvedOwnerPermission
            }
            else
            {
                $currentDigits.Owner
            }

            $targetGroupDigit = if ($hasGroupPermission)
            {
                ConvertTo-UnixPermissionDigit -Permissions $resolvedGroupPermission
            }
            else
            {
                $currentDigits.Group
            }

            $targetOtherDigit = if ($hasOtherPermission)
            {
                ConvertTo-UnixPermissionDigit -Permissions $resolvedOtherPermission
            }
            else
            {
                $currentDigits.Other
            }

            $requestedMode = '{0}{1}{2}{3}' -f $currentDigits.Special, $targetOwnerDigit, $targetGroupDigit, $targetOtherDigit

            $descriptionParts = New-Object 'System.Collections.Generic.List[string]'
            if ($hasOwnerPermission)
            {
                $descriptionParts.Add("owner=$([String](Format-PortablePermissions -Permissions $resolvedOwnerPermission))")
            }
            if ($hasGroupPermission)
            {
                $descriptionParts.Add("group=$([String](Format-PortablePermissions -Permissions $resolvedGroupPermission))")
            }
            if ($hasOtherPermission)
            {
                $descriptionParts.Add("other=$([String](Format-PortablePermissions -Permissions $resolvedOtherPermission))")
            }

            $operationDescription = "Set permissions to $([String]::Join('; ', $descriptionParts)) (mode $requestedMode)"
            if ($Idempotent)
            {
                $permissionInfo = Get-PermissionSnapshot -Item $Item
                $isCompliant = $true

                if ($hasOwnerPermission -and $permissionInfo.OwnerPermissions -ne (ConvertTo-UnixPermissionSegment -Permissions $resolvedOwnerPermission))
                {
                    $isCompliant = $false
                }

                if ($hasGroupPermission -and $permissionInfo.GroupPermissions -ne (ConvertTo-UnixPermissionSegment -Permissions $resolvedGroupPermission))
                {
                    $isCompliant = $false
                }

                if ($hasOtherPermission -and $permissionInfo.OtherPermissions -ne (ConvertTo-UnixPermissionSegment -Permissions $resolvedOtherPermission))
                {
                    $isCompliant = $false
                }

                if ($isCompliant)
                {
                    Write-Verbose "Skipping '$($Item.FullName)' because the requested permissions are already present."
                    return @{
                        Applied = $false
                        Skipped = $true
                        Reason = 'AlreadyCompliant'
                        Mode = $requestedMode
                        OwnerPermission = $resolvedOwnerPermission
                        GroupPermission = $resolvedGroupPermission
                        OtherPermission = $resolvedOtherPermission
                    }
                }
            }

            $modeResult = Invoke-UnixModeChange -Item $Item -RequestedMode $requestedMode -OperationDescription $operationDescription

            return @{
                Applied = $modeResult.Applied
                Skipped = $modeResult.Skipped
                Reason = $modeResult.Reason
                Mode = if ($modeResult.ContainsKey('Mode')) { $modeResult.Mode } else { $requestedMode }
                OwnerPermission = $resolvedOwnerPermission
                GroupPermission = $resolvedGroupPermission
                OtherPermission = $resolvedOtherPermission
            }
        }

        function Invoke-WindowsPortablePermissionChange
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item
            )

            try
            {
                $acl = Get-Acl -LiteralPath $Item.FullName -ErrorAction Stop
            }
            catch
            {
                $PSCmdlet.WriteError($_)
                return @{
                    Applied = $false
                }
            }

            $targets = New-Object 'System.Collections.Generic.List[object]'

            if ($hasOwnerPermission)
            {
                $ownerIdentity = [String]$acl.Owner
                if ([String]::IsNullOrWhiteSpace($ownerIdentity))
                {
                    $exception = New-Object System.InvalidOperationException("The item owner could not be determined for '$($Item.FullName)'.")
                    $errorRecord = New-Object System.Management.Automation.ErrorRecord(
                        $exception,
                        'OwnerIdentityUnavailable',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $Item.FullName
                    )
                    $PSCmdlet.WriteError($errorRecord)
                }
                else
                {
                    $resolvedOwnerPermission = Resolve-PortablePermissions -Permissions $OwnerPermission
                    $targets.Add([PSCustomObject]@{
                            Role = 'Owner'
                            Identity = $ownerIdentity
                            Permission = $resolvedOwnerPermission
                            Rights = ConvertTo-WindowsPortableRights -Item $Item -Permissions $resolvedOwnerPermission
                        })
                }
            }

            if ($hasGroupPermission)
            {
                $groupProperty = $acl.PSObject.Properties['Group']
                $groupIdentity = if ($groupProperty -and $null -ne $groupProperty.Value)
                {
                    [String]$groupProperty.Value
                }
                else
                {
                    $null
                }

                if ([String]::IsNullOrWhiteSpace($groupIdentity))
                {
                    $exception = New-Object System.InvalidOperationException("The item group could not be determined for '$($Item.FullName)'.")
                    $errorRecord = New-Object System.Management.Automation.ErrorRecord(
                        $exception,
                        'GroupIdentityUnavailable',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $Item.FullName
                    )
                    $PSCmdlet.WriteError($errorRecord)
                }
                else
                {
                    $resolvedGroupPermission = Resolve-PortablePermissions -Permissions $GroupPermission
                    $targets.Add([PSCustomObject]@{
                            Role = 'Group'
                            Identity = $groupIdentity
                            Permission = $resolvedGroupPermission
                            Rights = ConvertTo-WindowsPortableRights -Item $Item -Permissions $resolvedGroupPermission
                        })
                }
            }

            if ($hasOtherPermission)
            {
                $resolvedOtherPermission = Resolve-PortablePermissions -Permissions $OtherPermission
                $targets.Add([PSCustomObject]@{
                        Role = 'Other'
                        Identity = 'Everyone'
                        Permission = $resolvedOtherPermission
                        Rights = ConvertTo-WindowsPortableRights -Item $Item -Permissions $resolvedOtherPermission
                    })
            }

            if ($targets.Count -eq 0)
            {
                return @{
                    Applied = $false
                    Skipped = $false
                    Reason = $null
                }
            }

            $description = [String]::Join('; ', @($targets | ForEach-Object {
                        '{0}:{1}={2}' -f $_.Role, $_.Identity, (Format-PortablePermissions -Permissions $_.Permission)
                    }))

            if ($Idempotent)
            {
                $permissionInfo = Get-PermissionSnapshot -Item $Item -IncludeAcl
                $isCompliant = $true

                foreach ($target in $targets)
                {
                    $normalizedRights = ConvertTo-NormalizedWindowsRuleRights -Item $Item -TargetIdentity $target.Identity -RuleRights $target.Rights -RuleAccessType ([System.Security.AccessControl.AccessControlType]::Allow)
                    $currentRights = Get-WindowsExplicitRuleRights -AccessRules $permissionInfo.AccessRules -TargetIdentity $target.Identity -RuleAccessType ([System.Security.AccessControl.AccessControlType]::Allow)
                    if ([Int64]$currentRights -ne [Int64]$normalizedRights)
                    {
                        $isCompliant = $false
                        break
                    }
                }

                if ($isCompliant)
                {
                    Write-Verbose "Skipping '$($Item.FullName)' because the requested permissions are already present."
                    return @{
                        Applied = $false
                        Skipped = $true
                        Reason = 'AlreadyCompliant'
                        Targets = $targets.ToArray()
                        OwnerPermission = if ($hasOwnerPermission) { Resolve-PortablePermissions -Permissions $OwnerPermission } else { $null }
                        GroupPermission = if ($hasGroupPermission) { Resolve-PortablePermissions -Permissions $GroupPermission } else { $null }
                        OtherPermission = if ($hasOtherPermission) { Resolve-PortablePermissions -Permissions $OtherPermission } else { $null }
                    }
                }
            }

            if (-not $PSCmdlet.ShouldProcess($Item.FullName, "Set permissions $description"))
            {
                return @{
                    Applied = $false
                    Skipped = $false
                    Reason = $null
                    Targets = $targets.ToArray()
                    OwnerPermission = if ($hasOwnerPermission) { Resolve-PortablePermissions -Permissions $OwnerPermission } else { $null }
                    GroupPermission = if ($hasGroupPermission) { Resolve-PortablePermissions -Permissions $GroupPermission } else { $null }
                    OtherPermission = if ($hasOtherPermission) { Resolve-PortablePermissions -Permissions $OtherPermission } else { $null }
                }
            }

            try
            {
                foreach ($target in $targets)
                {
                    foreach ($matchingRule in (Get-ExplicitAccessRules -Acl $acl -TargetIdentity $target.Identity -RuleAccessType ([System.Security.AccessControl.AccessControlType]::Allow)))
                    {
                        $null = $acl.RemoveAccessRuleSpecific($matchingRule)
                    }

                    if ([Int64]$target.Rights -ne 0)
                    {
                        $rule = ConvertTo-WindowsAccessRule -Item $Item -TargetIdentity $target.Identity -RuleRights $target.Rights -RuleAccessType ([System.Security.AccessControl.AccessControlType]::Allow)
                        $null = $acl.AddAccessRule($rule)
                    }
                }

                Set-Acl -LiteralPath $Item.FullName -AclObject $acl -ErrorAction Stop

                return @{
                    Applied = $true
                    Skipped = $false
                    Reason = $null
                    Targets = $targets.ToArray()
                    OwnerPermission = if ($hasOwnerPermission) { Resolve-PortablePermissions -Permissions $OwnerPermission } else { $null }
                    GroupPermission = if ($hasGroupPermission) { Resolve-PortablePermissions -Permissions $GroupPermission } else { $null }
                    OtherPermission = if ($hasOtherPermission) { Resolve-PortablePermissions -Permissions $OtherPermission } else { $null }
                }
            }
            catch
            {
                $PSCmdlet.WriteError($_)
                return @{
                    Applied = $false
                    Skipped = $false
                    Reason = $null
                    Targets = $targets.ToArray()
                    OwnerPermission = if ($hasOwnerPermission) { Resolve-PortablePermissions -Permissions $OwnerPermission } else { $null }
                    GroupPermission = if ($hasGroupPermission) { Resolve-PortablePermissions -Permissions $GroupPermission } else { $null }
                    OtherPermission = if ($hasOtherPermission) { Resolve-PortablePermissions -Permissions $OtherPermission } else { $null }
                }
            }
        }

        function Invoke-WindowsIdentityPermissionChange
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item
            )

            $resolvedPermission = Resolve-PortablePermissions -Permissions $Permission
            $translatedRights = ConvertTo-WindowsPortableRights -Item $Item -Permissions $resolvedPermission
            $permissionLabel = Format-PortablePermissions -Permissions $resolvedPermission

            if ($Idempotent)
            {
                $permissionInfo = Get-PermissionSnapshot -Item $Item -IncludeAcl
                $normalizedRights = ConvertTo-NormalizedWindowsRuleRights -Item $Item -TargetIdentity $Identity -RuleRights $translatedRights -RuleAccessType $AccessType
                $currentRights = Get-WindowsExplicitRuleRights -AccessRules $permissionInfo.AccessRules -TargetIdentity $Identity -RuleAccessType $AccessType

                if ([Int64]$currentRights -eq [Int64]$normalizedRights)
                {
                    Write-Verbose "Skipping '$($Item.FullName)' because the requested permissions are already present."
                    return @{
                        Applied = $false
                        Skipped = $true
                        Reason = 'AlreadyCompliant'
                        Permission = $resolvedPermission
                        Rights = $normalizedRights
                    }
                }
            }

            $operationDescription = if ($resolvedPermission.Count -eq 1 -and $resolvedPermission[0] -eq 'None')
            {
                "Clear explicit $AccessType permissions for '$Identity'"
            }
            else
            {
                "Set $AccessType permissions for '$Identity' to '$permissionLabel'"
            }

            if (-not $PSCmdlet.ShouldProcess($Item.FullName, $operationDescription))
            {
                return @{
                    Applied = $false
                    Skipped = $false
                    Reason = $null
                    Permission = $resolvedPermission
                    Rights = $translatedRights
                }
            }

            try
            {
                $acl = Get-Acl -LiteralPath $Item.FullName -ErrorAction Stop
                foreach ($matchingRule in (Get-ExplicitAccessRules -Acl $acl -TargetIdentity $Identity -RuleAccessType $AccessType))
                {
                    $null = $acl.RemoveAccessRuleSpecific($matchingRule)
                }

                if ([Int64]$translatedRights -ne 0)
                {
                    $rule = ConvertTo-WindowsAccessRule -Item $Item -TargetIdentity $Identity -RuleRights $translatedRights -RuleAccessType $AccessType
                    $null = $acl.AddAccessRule($rule)
                }

                Set-Acl -LiteralPath $Item.FullName -AclObject $acl -ErrorAction Stop

                return @{
                    Applied = $true
                    Skipped = $false
                    Reason = $null
                    Permission = $resolvedPermission
                    Rights = $translatedRights
                }
            }
            catch
            {
                $PSCmdlet.WriteError($_)
                return @{
                    Applied = $false
                    Skipped = $false
                    Reason = $null
                    Permission = $resolvedPermission
                    Rights = $translatedRights
                }
            }
        }

        function Invoke-WindowsRightsChange
        {
            param(
                [Parameter(Mandatory)]
                [System.IO.FileSystemInfo]$Item,

                [Parameter(Mandatory)]
                [System.Security.AccessControl.FileSystemRights[]]$PermissionRights
            )

            $combinedRights = [System.Security.AccessControl.FileSystemRights]0
            foreach ($permissionRight in $PermissionRights)
            {
                $combinedRights = $combinedRights -bor $permissionRight
            }

            if ($Idempotent)
            {
                $permissionInfo = Get-PermissionSnapshot -Item $Item -IncludeAcl
                $normalizedRights = ConvertTo-NormalizedWindowsRuleRights -Item $Item -TargetIdentity $Identity -RuleRights $combinedRights -RuleAccessType $AccessType
                $currentRights = Get-WindowsExplicitRuleRights -AccessRules $permissionInfo.AccessRules -TargetIdentity $Identity -RuleAccessType $AccessType

                if ([Int64]$currentRights -eq [Int64]$normalizedRights)
                {
                    Write-Verbose "Skipping '$($Item.FullName)' because the requested permissions are already present."
                    return @{
                        Applied = $false
                        Skipped = $true
                        Reason = 'AlreadyCompliant'
                        Rights = $normalizedRights
                    }
                }
            }

            $operationDescription = "Set $AccessType ACL rule for '$Identity' to '$combinedRights'"
            if (-not $PSCmdlet.ShouldProcess($Item.FullName, $operationDescription))
            {
                return @{
                    Applied = $false
                    Skipped = $false
                    Reason = $null
                    Rights = $combinedRights
                }
            }

            try
            {
                $acl = Get-Acl -LiteralPath $Item.FullName -ErrorAction Stop
                foreach ($matchingRule in (Get-ExplicitAccessRules -Acl $acl -TargetIdentity $Identity -RuleAccessType $AccessType))
                {
                    $null = $acl.RemoveAccessRuleSpecific($matchingRule)
                }

                if ([Int64]$combinedRights -ne 0)
                {
                    $rule = ConvertTo-WindowsAccessRule -Item $Item -TargetIdentity $Identity -RuleRights $combinedRights -RuleAccessType $AccessType
                    $null = $acl.AddAccessRule($rule)
                }

                Set-Acl -LiteralPath $Item.FullName -AclObject $acl -ErrorAction Stop

                return @{
                    Applied = $true
                    Skipped = $false
                    Reason = $null
                    Rights = $combinedRights
                }
            }
            catch
            {
                $PSCmdlet.WriteError($_)
                return @{
                    Applied = $false
                    Skipped = $false
                    Reason = $null
                    Rights = $combinedRights
                }
            }
        }
    }

    process
    {
        $useLiteralPath = $PSCmdlet.ParameterSetName -like '*LiteralPath'
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
                    $resultInfo = $null
                    $operationName = $null

                    if ($isPortableOperation)
                    {
                        $operationName = 'SetPortablePermission'
                        if ($isUnixPlatform)
                        {
                            $resultInfo = Invoke-UnixPortablePermissionChange -Item $targetItem
                        }
                        else
                        {
                            $resultInfo = Invoke-WindowsPortablePermissionChange -Item $targetItem
                        }
                    }
                    elseif ($isModeOperation)
                    {
                        $operationName = 'SetMode'
                        $resultInfo = Invoke-UnixModeChange -Item $targetItem -RequestedMode $Mode -OperationDescription "Set permissions to '$Mode'"
                    }
                    elseif ($isIdentityPermissionOperation)
                    {
                        $operationName = 'SetPermission'
                        $resultInfo = Invoke-WindowsIdentityPermissionChange -Item $targetItem
                    }
                    else
                    {
                        $operationName = 'SetAccessRule'
                        $resultInfo = Invoke-WindowsRightsChange -Item $targetItem -PermissionRights $Rights
                    }

                    if ($PassThru -and $resultInfo -and ($resultInfo.Applied -or $resultInfo.Skipped))
                    {
                        [PSCustomObject]@{
                            InputPath = $inputPath
                            Path = $targetItem.FullName
                            ItemType = Get-ItemTypeName -Item $targetItem
                            Platform = if ($isWindowsPlatform) { 'Windows' } else { 'Unix' }
                            Operation = $operationName
                            Applied = [Boolean]$resultInfo.Applied
                            Skipped = [Boolean]$resultInfo.Skipped
                            Reason = if ($resultInfo.ContainsKey('Reason')) { $resultInfo.Reason } else { $null }
                            OwnerPermission = if ($resultInfo.ContainsKey('OwnerPermission')) { Format-PortablePermissions -Permissions $resultInfo.OwnerPermission } else { $null }
                            GroupPermission = if ($resultInfo.ContainsKey('GroupPermission')) { Format-PortablePermissions -Permissions $resultInfo.GroupPermission } else { $null }
                            OtherPermission = if ($resultInfo.ContainsKey('OtherPermission')) { Format-PortablePermissions -Permissions $resultInfo.OtherPermission } else { $null }
                            Mode = if ($resultInfo.ContainsKey('Mode')) { [String]$resultInfo.Mode } else { $null }
                            Identity = if ($isIdentityPermissionOperation -or $isRightsOperation) { $Identity } else { $null }
                            Permission = if ($resultInfo.ContainsKey('Permission')) { Format-PortablePermissions -Permissions $resultInfo.Permission } else { $null }
                            Rights = if ($resultInfo.ContainsKey('Rights') -and $null -ne $resultInfo.Rights) { [String]$resultInfo.Rights } else { $null }
                            AccessType = if ($isIdentityPermissionOperation -or $isRightsOperation) { [String]$AccessType } else { $null }
                        }
                    }
                }
            }
        }
    }
}
