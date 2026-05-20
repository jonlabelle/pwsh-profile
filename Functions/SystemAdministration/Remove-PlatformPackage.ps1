function Remove-PlatformPackage
{
    <#
    .SYNOPSIS
        Removes installed packages with the native platform package manager.

    .DESCRIPTION
        Detects the supported package manager for the current platform, lists installed
        packages, and opens an interactive console picker where packages can be selected
        with Space before removal. In the picker, selecting a package controls
        whether it will be removed when Enter is pressed. If no package is selected,
        pressing Enter removes the current package. The purge/zap option is a separate
        per-package toggle that requests deeper cleanup for selected packages on package
        managers that support it.

        Supported package managers:
        - Windows: winget
        - macOS: brew
        - Debian/Ubuntu Linux: apt
        - Alpine Linux: apk

        Removal command output is streamed directly to the console so the operation can
        be followed while it runs. Use -NonInteractive to return the discovered installed
        package list without starting the interactive picker, or -All to remove every
        matching package without prompting.

    .PARAMETER IncludePackage
        Optional package names or wildcard patterns to include. Matches package Name or Id.

    .PARAMETER ExcludePackage
        Optional package names or wildcard patterns to exclude. Matches package Name or Id.

    .PARAMETER All
        Removes all matching installed packages without opening the interactive picker.
        To avoid accidental full-system package removal, -All requires -IncludePackage.

    .PARAMETER Purge
        Uses package-manager-specific purge or zap behavior for every package selected
        for removal. This requests deeper cleanup than a normal removal when supported:
        winget uses uninstall --purge for portable packages, apt uses purge,
        apk uses del --purge, and Homebrew casks use uninstall --zap. It has no
        effect for Homebrew formulae.

        In the interactive picker, Space marks a package for removal and P toggles this
        purge/zap behavior for the highlighted package. Pressing Enter removes the
        selected packages, or the current package when nothing is selected, using
        purge/zap only for packages where it was requested.

    .PARAMETER NonInteractive
        Returns the discovered installed package records without removing anything. The
        previous -AsObject spelling is retained as an alias.

    .PARAMETER FilterSource
        Sets the initial source filter in the interactive picker. When specified, the picker
        opens showing only packages from this source. Press S in the picker to cycle through
        available sources. Only applicable when multiple package sources are present.

    .PARAMETER NoSudo
        On Linux package managers that normally require elevated privileges, do not
        automatically prefix remove commands with sudo.

    .EXAMPLE
        PS > Remove-PlatformPackage

        Lists installed packages and opens the interactive picker. Press Space to select
        packages for removal, optionally press P to request purge/zap cleanup for a
        selected package, then press Enter to remove the selected packages or the current
        package when nothing is selected.

    .EXAMPLE
        PS > Remove-PlatformPackage -IncludePackage 'git*' -All

        Removes every installed package whose name or id matches 'git*' without prompting.

    .EXAMPLE
        PS > Remove-PlatformPackage -IncludePackage 'node*' -ExcludePackage 'node@18'

        Opens the picker for matching node packages except packages whose name or id
        matches 'node@18'.

    .EXAMPLE
        PS > Remove-PlatformPackage -IncludePackage 'openssl' -Purge -All

        Removes the matching package and requests package-manager-specific purge behavior
        where supported.

    .EXAMPLE
        PS > Remove-PlatformPackage -IncludePackage 'visual-studio-code'

        Opens the picker for matching packages. Selecting the Homebrew cask with Space
        removes it normally; pressing P before Enter changes that selected package to use
        brew uninstall --cask --zap instead.

    .EXAMPLE
        PS > Remove-PlatformPackage -NonInteractive | Format-Table

        Lists installed packages for the detected package manager without removing anything.

    .EXAMPLE
        PS > Remove-PlatformPackage -IncludePackage 'git' -All -WhatIf

        Shows the package removal that would run without invoking the package manager.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns package records when -NonInteractive is used. Otherwise returns a removal
        summary object with package manager, selection counts, NotSelected,
        selected-package skip/failure counts, and per-package results.

    .NOTES
        - winget is used on Windows.
        - brew is used on macOS.
        - apt is used on Debian/Ubuntu-style Linux distributions.
        - apk is used on Alpine Linux.
        - apt and apk remove operations are prefixed with sudo when needed and available.
        - Query commands are parsed to build the picker; remove commands stream their
          native output to the console.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Remove-PlatformPackage.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Remove-PlatformPackage.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Function name requested by the profile owner.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject], [PSCustomObject[]], [Object[]])]
    param(
        [Parameter(Position = 0)]
        [Alias('Name', 'PackageName', 'Include')]
        [String[]]$IncludePackage = @(),

        [Parameter()]
        [Alias('Exclude')]
        [String[]]$ExcludePackage = @(),

        [Parameter()]
        [Switch]$All,

        [Parameter()]
        [Switch]$Purge,

        [Parameter()]
        [Alias('AsObject')]
        [Switch]$NonInteractive,

        [Parameter()]
        [String]$FilterSource = '',

        [Parameter()]
        [Switch]$NoSudo,

        [Parameter(DontShow = $true)]
        [ValidateSet('Auto', 'winget', 'brew', 'apt', 'apk')]
        [String]$PackageManager = 'Auto',

        [Parameter(DontShow = $true)]
        [ScriptBlock]$CommandRunner,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$KeyReader,

        [Parameter(DontShow = $true)]
        [ValidateRange(0, 500)]
        [Int32]$PickerPageSize = 0,

        [Parameter(DontShow = $true)]
        [Switch]$ReturnToPlatformPackageManagerOnBackKey
    )

    begin
    {
        function Get-DependencyPathIfNeeded
        {
            param(
                [Parameter(Mandatory)]
                [String]$FunctionName,

                [Parameter(Mandatory)]
                [String]$RelativePath
            )

            if (-not (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue))
            {
                Write-Verbose "$FunctionName is required - attempting to load it"

                $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath $RelativePath
                $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)

                if (Test-Path -Path $dependencyPath -PathType Leaf)
                {
                    return $dependencyPath
                }

                throw "Required function '$FunctionName' could not be found. Expected location: $dependencyPath"
            }

            Write-Verbose "$FunctionName is already loaded"
            return $null
        }

        $getPlatformPackagePath = Get-DependencyPathIfNeeded -FunctionName 'Get-PlatformPackage' -RelativePath 'Get-PlatformPackage.ps1'
        if (-not [String]::IsNullOrWhiteSpace($getPlatformPackagePath))
        {
            try
            {
                . $getPlatformPackagePath
                Write-Verbose "Loaded Get-PlatformPackage from: $getPlatformPackagePath"
            }
            catch
            {
                throw "Failed to load required dependency 'Get-PlatformPackage' from '$getPlatformPackagePath': $($_.Exception.Message)"
            }
        }

        $getPlatformPackageDependencyPath = Get-DependencyPathIfNeeded -FunctionName 'Get-PlatformPackageDependency' -RelativePath 'Get-PlatformPackageDependency.ps1'
        if (-not [String]::IsNullOrWhiteSpace($getPlatformPackageDependencyPath))
        {
            try
            {
                . $getPlatformPackageDependencyPath
                Write-Verbose "Loaded Get-PlatformPackageDependency from: $getPlatformPackageDependencyPath"
            }
            catch
            {
                throw "Failed to load required dependency 'Get-PlatformPackageDependency' from '$getPlatformPackageDependencyPath': $($_.Exception.Message)"
            }
        }

        function ConvertTo-PackageText
        {
            param(
                [Parameter()]
                [Object]$Value
            )

            if ($null -eq $Value)
            {
                return ''
            }

            $items = @($Value) |
            Where-Object { $null -ne $_ -and -not [String]::IsNullOrWhiteSpace("$($_)") } |
            ForEach-Object { "$($_)".Trim() }

            return ($items -join ', ')
        }

        function Get-FirstPropertyValue
        {
            param(
                [Parameter()]
                [Object]$InputObject,

                [Parameter(Mandatory)]
                [String[]]$PropertyName
            )

            if ($null -eq $InputObject)
            {
                return $null
            }

            foreach ($name in $PropertyName)
            {
                $property = $InputObject.PSObject.Properties[$name]
                if ($property)
                {
                    $value = $property.Value
                    if ($null -ne $value -and -not [String]::IsNullOrWhiteSpace((ConvertTo-PackageText -Value $value)))
                    {
                        return $value
                    }
                }
            }

            return $null
        }

        function Get-PackageRemoveArguments
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Name,

                [Parameter()]
                [String]$Id,

                [Parameter()]
                [String]$Type,

                [Parameter()]
                [String]$Source,

                [Parameter()]
                [Switch]$UsePurge
            )

            switch ($Manager.Name)
            {
                'winget'
                {
                    $sourceArguments = if (-not [String]::IsNullOrWhiteSpace($Source))
                    {
                        @('--source', $Source)
                    }
                    else
                    {
                        @()
                    }

                    $arguments = if (-not [String]::IsNullOrWhiteSpace($Id))
                    {
                        @('uninstall', '--id', $Id, '--exact') + $sourceArguments + @('--accept-source-agreements')
                    }
                    else
                    {
                        @('uninstall', $Name) + $sourceArguments + @('--accept-source-agreements')
                    }

                    if ($UsePurge)
                    {
                        $arguments += '--purge'
                    }

                    return $arguments
                }
                'brew'
                {
                    if ($Type -eq 'Cask')
                    {
                        if ($UsePurge)
                        {
                            return @('uninstall', '--cask', '--zap', $Name)
                        }

                        return @('uninstall', '--cask', $Name)
                    }

                    return @('uninstall', $Name)
                }
                'apt'
                {
                    if ($UsePurge)
                    {
                        return @('purge', '-y', $Name)
                    }

                    return @('remove', '-y', $Name)
                }
                'apk'
                {
                    if ($UsePurge)
                    {
                        return @('del', '--purge', $Name)
                    }

                    return @('del', $Name)
                }
                default
                {
                    throw "Unsupported package manager '$($Manager.Name)'."
                }
            }
        }

        function Get-PackageRemoveObject
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Name,

                [Parameter()]
                [String]$Id,

                [Parameter()]
                [String]$Type,

                [Parameter()]
                [String]$InstalledVersion,

                [Parameter()]
                [String]$Source,

                [Parameter()]
                [String]$Publisher,

                [Parameter()]
                [String]$Description,

                [Parameter()]
                [String]$Notes
            )

            [PSCustomObject]@{
                Name = $Name
                Id = $Id
                PackageManager = $Manager.Name
                PackageManagerDisplayName = $Manager.DisplayName
                Type = $Type
                InstalledVersion = $InstalledVersion
                Source = $Source
                Publisher = if (-not [String]::IsNullOrWhiteSpace($Publisher)) { $Publisher } elseif ($Manager.Name -eq 'brew') { 'Homebrew' } elseif ($Manager.Name -eq 'apk') { 'Alpine' } elseif ($Manager.Name -eq 'apt' -and -not [String]::IsNullOrWhiteSpace($Source)) { $Source } elseif ($Manager.Name -eq 'apt') { 'APT' } elseif ($Manager.Name -eq 'winget' -and -not [String]::IsNullOrWhiteSpace($Source)) { $Source } else { '' }
                Description = if (-not [String]::IsNullOrWhiteSpace($Description)) { $Description } else { $Notes }
                Notes = $Notes
                Command = $Manager.Command
                RemoveArguments = @(Get-PackageRemoveArguments -Manager $Manager -Name $Name -Id $Id -Type $Type -Source $Source -UsePurge:$Purge.IsPresent)
            }
        }

        function Test-ReverseDependencyPreviewSupported
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            return $Manager.Name -in @('brew', 'apt', 'apk')
        }

        function Get-PackageIdentityKeys
        {
            param(
                [Parameter()]
                [Object]$Package
            )

            $keys = New-Object 'System.Collections.Generic.List[String]'
            foreach ($value in @(
                    (ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $Package -PropertyName @('Name', 'Package', 'PackageName')))
                    (ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $Package -PropertyName @('Id', 'PackageIdentifier', 'Identifier')))
                ))
            {
                if ([String]::IsNullOrWhiteSpace($value))
                {
                    continue
                }

                $key = $value.Trim().ToLowerInvariant()
                if (-not $keys.Contains($key))
                {
                    $keys.Add($key)
                }
            }

            return @($keys)
        }

        function Add-PackageRequiredByMetadata
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter()]
                [PSCustomObject[]]$Packages = @()
            )

            if ($Packages.Count -eq 0 -or -not (Test-ReverseDependencyPreviewSupported -Manager $Manager))
            {
                return
            }

            $requiredByLookup = @{}
            try
            {
                $dependencyRecords = @(Get-PlatformPackageDependency -Package $Packages -Direction RequiredBy -InstalledOnly -PackageManager $Manager.Name -CommandRunner $CommandRunner)
            }
            catch
            {
                Write-Verbose "Unable to check reverse dependencies before removal: $($_.Exception.Message)"
                return
            }

            foreach ($record in @($dependencyRecords | Where-Object { $_.Direction -eq 'RequiredBy' }))
            {
                foreach ($key in @(Get-PackageIdentityKeys -Package $record))
                {
                    if (-not $requiredByLookup.ContainsKey($key))
                    {
                        $requiredByLookup[$key] = New-Object 'System.Collections.Generic.List[Object]'
                    }

                    $requiredByLookup[$key].Add($record)
                }
            }

            foreach ($package in $Packages)
            {
                $records = New-Object 'System.Collections.Generic.List[Object]'
                foreach ($key in @(Get-PackageIdentityKeys -Package $package))
                {
                    if ($requiredByLookup.ContainsKey($key))
                    {
                        foreach ($record in $requiredByLookup[$key])
                        {
                            $records.Add($record)
                        }
                    }
                }

                $relatedPackages = @(
                    $records |
                    Where-Object { -not [String]::IsNullOrWhiteSpace($_.RelatedPackage) } |
                    ForEach-Object { $_.RelatedPackage } |
                    Select-Object -Unique
                )

                $package | Add-Member -NotePropertyName 'RequiredByPackages' -NotePropertyValue @($relatedPackages) -Force
                $package | Add-Member -NotePropertyName 'RequiredByCount' -NotePropertyValue $relatedPackages.Count -Force
            }
        }

        function Format-PackageRequiredByPreview
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Package,

                [Parameter()]
                [ValidateRange(1, 20)]
                [Int32]$Limit = 5
            )

            $requiredByPackages = @()
            if ($Package.PSObject.Properties['RequiredByPackages'])
            {
                $requiredByPackages = @($Package.RequiredByPackages | Where-Object { -not [String]::IsNullOrWhiteSpace($_) })
            }

            if ($requiredByPackages.Count -eq 0)
            {
                return ''
            }

            $preview = (@($requiredByPackages | Select-Object -First $Limit) -join ', ')
            if ($requiredByPackages.Count -gt $Limit)
            {
                $preview = "$preview, +$($requiredByPackages.Count - $Limit) more"
            }

            return "$($Package.Name) is required by $($requiredByPackages.Count) installed package(s): $preview"
        }

        function Write-PackageRequiredByWarnings
        {
            param(
                [Parameter()]
                [PSCustomObject[]]$Packages = @()
            )

            foreach ($package in $Packages)
            {
                $preview = Format-PackageRequiredByPreview -Package $package
                if (-not [String]::IsNullOrWhiteSpace($preview))
                {
                    Write-Warning "$preview. Removing it may break dependent packages."
                }
            }
        }

        function Get-PackageResultRequiredByProperties
        {
            param(
                [Parameter()]
                [PSCustomObject]$Package
            )

            $requiredByPackages = if ($Package -and $Package.PSObject.Properties['RequiredByPackages'])
            {
                @($Package.RequiredByPackages)
            }
            else
            {
                @()
            }

            [PSCustomObject]@{
                RequiredByCount = $requiredByPackages.Count
                RequiredByPackages = @($requiredByPackages)
            }
        }

        function Test-PackageManagerCommandAvailable
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Name
            )

            if ($CommandRunner)
            {
                return $true
            }

            return $null -ne (Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1)
        }

        function Get-LinuxDistributionInfo
        {
            $info = @{
                Id = ''
                IdLike = ''
            }

            if (-not (Test-Path -Path '/etc/os-release' -PathType Leaf))
            {
                return [PSCustomObject]$info
            }

            foreach ($line in (Get-Content -Path '/etc/os-release' -ErrorAction SilentlyContinue))
            {
                if ($line -match '^(?<Name>ID|ID_LIKE)=(?<Value>.+)$')
                {
                    $value = $Matches.Value.Trim().Trim('"')
                    if ($Matches.Name -eq 'ID')
                    {
                        $info.Id = $value
                    }
                    elseif ($Matches.Name -eq 'ID_LIKE')
                    {
                        $info.IdLike = $value
                    }
                }
            }

            [PSCustomObject]$info
        }

        function Get-PackageManagerDefinition
        {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('winget', 'brew', 'apt', 'apk')]
                [String]$Name
            )

            switch ($Name)
            {
                'winget'
                {
                    [PSCustomObject]@{
                        Name = 'winget'
                        DisplayName = 'Windows Package Manager'
                        Command = 'winget'
                        Platform = 'Windows'
                        NeedsSudo = $false
                    }
                }
                'brew'
                {
                    [PSCustomObject]@{
                        Name = 'brew'
                        DisplayName = 'Homebrew'
                        Command = 'brew'
                        Platform = 'macOS'
                        NeedsSudo = $false
                    }
                }
                'apt'
                {
                    [PSCustomObject]@{
                        Name = 'apt'
                        DisplayName = 'APT'
                        Command = 'apt'
                        Platform = 'Debian/Ubuntu Linux'
                        NeedsSudo = $true
                    }
                }
                'apk'
                {
                    [PSCustomObject]@{
                        Name = 'apk'
                        DisplayName = 'Alpine Package Keeper'
                        Command = 'apk'
                        Platform = 'Alpine Linux'
                        NeedsSudo = $true
                    }
                }
            }
        }

        function Resolve-PackageManager
        {
            $requestedManager = $PackageManager.ToLowerInvariant()
            if ($requestedManager -ne 'auto')
            {
                if (-not (Test-PackageManagerCommandAvailable -Name $requestedManager))
                {
                    throw "Package manager '$requestedManager' is not installed or not available in PATH."
                }

                return Get-PackageManagerDefinition -Name $requestedManager
            }

            $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { [Bool]$IsWindows }
            $isMacOSPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $false } else { [Bool]$IsMacOS }
            $isLinuxPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $false } else { [Bool]$IsLinux }

            if ($isWindowsPlatform -and (Test-PackageManagerCommandAvailable -Name 'winget'))
            {
                return Get-PackageManagerDefinition -Name 'winget'
            }

            if ($isMacOSPlatform -and (Test-PackageManagerCommandAvailable -Name 'brew'))
            {
                return Get-PackageManagerDefinition -Name 'brew'
            }

            if ($isLinuxPlatform)
            {
                $distributionInfo = Get-LinuxDistributionInfo
                $linuxFamily = "$($distributionInfo.Id) $($distributionInfo.IdLike)".Trim().ToLowerInvariant()

                if ($linuxFamily -match '\balpine\b' -and (Test-PackageManagerCommandAvailable -Name 'apk'))
                {
                    return Get-PackageManagerDefinition -Name 'apk'
                }

                if ($linuxFamily -match '\b(debian|ubuntu)\b' -and (Test-PackageManagerCommandAvailable -Name 'apt'))
                {
                    return Get-PackageManagerDefinition -Name 'apt'
                }

                if (Test-PackageManagerCommandAvailable -Name 'apt')
                {
                    return Get-PackageManagerDefinition -Name 'apt'
                }

                if (Test-PackageManagerCommandAvailable -Name 'apk')
                {
                    return Get-PackageManagerDefinition -Name 'apk'
                }
            }

            foreach ($fallbackManager in @('brew', 'winget', 'apt', 'apk'))
            {
                if (Test-PackageManagerCommandAvailable -Name $fallbackManager)
                {
                    return Get-PackageManagerDefinition -Name $fallbackManager
                }
            }

            throw 'No supported package manager was found. Install winget, brew, apt, or apk and try again.'
        }

        function Invoke-PackageManagerCommand
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Command,

                [Parameter()]
                [String[]]$Arguments = @(),

                [Parameter()]
                [Switch]$StreamOutput,

                [Parameter()]
                [Switch]$PreserveConsoleOutput
            )

            if ($CommandRunner)
            {
                $runnerOutput = & $CommandRunner -Command $Command -Arguments $Arguments -StreamOutput:$StreamOutput.IsPresent
                $runnerOutputItems = @($runnerOutput)

                if ($runnerOutputItems.Count -eq 1)
                {
                    $item = $runnerOutputItems[0]

                    if ($item -is [System.Collections.IDictionary] -and $item.Contains('ExitCode') -and $item.Contains('Output'))
                    {
                        $result = [PSCustomObject]@{
                            ExitCode = [Int32]$item['ExitCode']
                            Output = @($item['Output'])
                        }

                        if ($StreamOutput)
                        {
                            $result.Output | ForEach-Object { Write-Host "$_" }
                        }

                        return $result
                    }

                    if ($item -and $item.PSObject.Properties['ExitCode'] -and $item.PSObject.Properties['Output'])
                    {
                        $result = [PSCustomObject]@{
                            ExitCode = [Int32]$item.ExitCode
                            Output = @($item.Output)
                        }

                        if ($StreamOutput)
                        {
                            $result.Output | ForEach-Object { Write-Host "$_" }
                        }

                        return $result
                    }
                }

                if ($StreamOutput)
                {
                    $runnerOutputItems | ForEach-Object { Write-Host "$_" }
                }

                return [PSCustomObject]@{
                    ExitCode = 0
                    Output = @($runnerOutputItems)
                }
            }

            $output = @()

            try
            {
                if ($StreamOutput)
                {
                    if ($PreserveConsoleOutput)
                    {
                        $process = $null
                        try
                        {
                            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
                            $startInfo.FileName = $Command
                            $startInfo.UseShellExecute = $false
                            $startInfo.RedirectStandardOutput = $false
                            $startInfo.RedirectStandardError = $false
                            foreach ($argument in @($Arguments))
                            {
                                [void]$startInfo.ArgumentList.Add($argument)
                            }

                            $process = [System.Diagnostics.Process]::Start($startInfo)
                            if ($null -eq $process)
                            {
                                throw "Failed to start '$Command'."
                            }

                            $process.WaitForExit()

                            return [PSCustomObject]@{
                                ExitCode = [Int32]$process.ExitCode
                                Output = @()
                            }
                        }
                        finally
                        {
                            if ($null -ne $process)
                            {
                                $process.Dispose()
                            }
                        }
                    }

                    $capturedOutput = New-Object 'System.Collections.Generic.List[String]'
                    & $Command @Arguments 2>&1 | ForEach-Object {
                        $line = "$($_)"
                        [void]$capturedOutput.Add($line)
                        Write-Host $line
                    }

                    return [PSCustomObject]@{
                        ExitCode = if ($null -ne $LASTEXITCODE) { [Int32]$LASTEXITCODE } else { 0 }
                        Output = @($capturedOutput)
                    }
                }

                $output = @(& $Command @Arguments 2>&1)

                return [PSCustomObject]@{
                    ExitCode = if ($null -ne $LASTEXITCODE) { [Int32]$LASTEXITCODE } else { 0 }
                    Output = @($output)
                }
            }
            catch
            {
                if ($StreamOutput)
                {
                    Write-Host "$($_.Exception.Message)"
                }

                return [PSCustomObject]@{
                    ExitCode = 1
                    Output = @($_.Exception.Message)
                }
            }
        }

        function Test-CurrentUserIsRoot
        {
            if ($CommandRunner)
            {
                return $false
            }

            $idCommand = Get-Command -Name 'id' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1

            if (-not $idCommand)
            {
                return $false
            }

            try
            {
                $effectiveUserIdOutput = & $idCommand.Source -u 2>$null
                return "$($effectiveUserIdOutput | Select-Object -First 1)".Trim() -eq '0'
            }
            catch
            {
                return $false
            }
        }

        function Resolve-PackageManagerInvocation
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter()]
                [String[]]$Arguments = @()
            )

            if ($CommandRunner)
            {
                return [PSCustomObject]@{
                    Command = $Manager.Command
                    Arguments = @($Arguments)
                }
            }

            if ($Manager.NeedsSudo -and -not $NoSudo -and -not (Test-CurrentUserIsRoot))
            {
                if (Test-PackageManagerCommandAvailable -Name 'sudo')
                {
                    return [PSCustomObject]@{
                        Command = 'sudo'
                        Arguments = @($Manager.Command) + @($Arguments)
                    }
                }

                Write-Warning "The '$($Manager.Command)' operation may require root privileges, but sudo was not found. Running without sudo."
            }

            [PSCustomObject]@{
                Command = $Manager.Command
                Arguments = @($Arguments)
            }
        }

        function Get-PackageCommandFailureMessage
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Command,

                [Parameter()]
                [String[]]$Arguments = @(),

                [Parameter(Mandatory)]
                [Int32]$ExitCode,

                [Parameter()]
                [Object[]]$Output = @()
            )

            $message = ($Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
            if (-not [String]::IsNullOrWhiteSpace($message))
            {
                return $message
            }

            $commandText = "$Command $($Arguments -join ' ')".Trim()
            return "$commandText failed with exit code $ExitCode. Command output was streamed directly to the console above."
        }

        function Get-PackageInformationalOutput
        {
            param(
                [Parameter()]
                [Object[]]$Output = @()
            )

            $lines = @(
                $Output |
                Where-Object { $null -ne $_ } |
                ForEach-Object { "$($_)" } |
                Where-Object { -not [String]::IsNullOrWhiteSpace($_) }
            )

            if ($lines.Count -eq 0)
            {
                return @()
            }

            $anchorPattern = '^(==>\s+(Caveats|Next steps)|Caveats:?$|Next steps:?$|Warnings?:?$|Notes?:?$|Important:?$|To (restart|start|stop|use|finish|add|enable|disable|load|unload|link)\b|Service\b)'
            for ($i = 0; $i -lt $lines.Count; $i++)
            {
                if ($lines[$i] -match $anchorPattern)
                {
                    return @($lines[$i..($lines.Count - 1)])
                }
            }

            return @()
        }

        function ConvertFrom-WingetJsonOutput
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter()]
                [Object[]]$Output = @()
            )

            $lines = @($Output | ForEach-Object { "$_" })
            $startIndex = -1
            for ($i = 0; $i -lt $lines.Count; $i++)
            {
                $trimmedLine = $lines[$i].Trim()
                if ($trimmedLine.StartsWith('{') -or $trimmedLine.StartsWith('['))
                {
                    $startIndex = $i
                    break
                }
            }

            if ($startIndex -lt 0)
            {
                return @()
            }

            $jsonText = ($lines[$startIndex..($lines.Count - 1)] -join "`n").Trim()
            if ([String]::IsNullOrWhiteSpace($jsonText))
            {
                return @()
            }

            try
            {
                $json = $jsonText | ConvertFrom-Json
            }
            catch
            {
                Write-Verbose "Unable to parse winget JSON output: $($_.Exception.Message)"
                return @()
            }

            function Get-WingetJsonSourceName
            {
                param(
                    [Parameter()]
                    [Object]$SourceRecord
                )

                if ($null -eq $SourceRecord)
                {
                    return ''
                }

                foreach ($sourcePropertyName in @('Name', 'Source', 'SourceName'))
                {
                    $sourceProperty = $SourceRecord.PSObject.Properties[$sourcePropertyName]
                    if ($sourceProperty)
                    {
                        $sourceName = ConvertTo-PackageText -Value $sourceProperty.Value
                        if (-not [String]::IsNullOrWhiteSpace($sourceName))
                        {
                            return $sourceName
                        }
                    }
                }

                foreach ($detailsPropertyName in @('SourceDetails', 'Details'))
                {
                    $detailsProperty = $SourceRecord.PSObject.Properties[$detailsPropertyName]
                    if (-not $detailsProperty -or $null -eq $detailsProperty.Value)
                    {
                        continue
                    }

                    foreach ($sourcePropertyName in @('Name', 'Source', 'SourceName'))
                    {
                        $sourceProperty = $detailsProperty.Value.PSObject.Properties[$sourcePropertyName]
                        if ($sourceProperty)
                        {
                            $sourceName = ConvertTo-PackageText -Value $sourceProperty.Value
                            if (-not [String]::IsNullOrWhiteSpace($sourceName))
                            {
                                return $sourceName
                            }
                        }
                    }
                }

                return ''
            }

            $candidatePackages = @()
            if ($json -is [Array])
            {
                $candidatePackages += @($json)
            }
            elseif ($json.PSObject.Properties['Sources'])
            {
                foreach ($source in @($json.Sources))
                {
                    if ($source.PSObject.Properties['Packages'])
                    {
                        $sourceName = Get-WingetJsonSourceName -SourceRecord $source
                        foreach ($sourcePackage in @($source.Packages))
                        {
                            $packageSource = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $sourcePackage -PropertyName @('CatalogName', 'Source', 'SourceName'))
                            if ([String]::IsNullOrWhiteSpace($packageSource) -and -not [String]::IsNullOrWhiteSpace($sourceName))
                            {
                                $sourcePackage | Add-Member -NotePropertyName Source -NotePropertyValue $sourceName -Force
                            }
                            $candidatePackages += $sourcePackage
                        }
                    }
                }
            }
            elseif ($json.PSObject.Properties['Packages'])
            {
                $candidatePackages += @($json.Packages)
            }
            elseif ($json.PSObject.Properties['Data'])
            {
                $candidatePackages += @($json.Data)
            }

            $packages = @()
            foreach ($package in $candidatePackages)
            {
                if ($null -eq $package)
                {
                    continue
                }

                $name = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Name', 'PackageName'))
                $id = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Id', 'PackageIdentifier', 'Identifier'))
                $installedVersion = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('InstalledVersion', 'Version', 'CurrentVersion'))
                $source = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Source', 'SourceName'))
                $description = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Description', 'ShortDescription', 'Summary', 'PackageDescription'))

                if ([String]::IsNullOrWhiteSpace($name))
                {
                    continue
                }

                $packages += Get-PackageRemoveObject -Manager $Manager -Name $name -Id $id -Type 'Package' -InstalledVersion $installedVersion -Source $source -Description $description
            }

            return $packages
        }

        function ConvertFrom-WingetTableOutput
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter()]
                [Object[]]$Output = @()
            )

            $lines = @($Output | ForEach-Object { "$_" })
            $headerIndex = -1
            $header = $null
            for ($i = 0; $i -lt $lines.Count; $i++)
            {
                if ($lines[$i] -match 'Name\s+Id\s+Version')
                {
                    $headerIndex = $i
                    $header = $lines[$i]
                    break
                }
            }

            if ($headerIndex -lt 0 -or [String]::IsNullOrWhiteSpace($header))
            {
                return @()
            }

            $nameStart = $header.IndexOf('Name')
            $idStart = $header.IndexOf('Id')
            $versionStart = $header.IndexOf('Version')
            $sourceStart = $header.IndexOf('Source')

            function Get-WingetTableCell
            {
                param(
                    [Parameter(Mandatory)]
                    [String]$Line,

                    [Parameter(Mandatory)]
                    [Int32]$Start,

                    [Parameter()]
                    [Int32]$End = -1
                )

                if ($Start -lt 0 -or $Start -ge $Line.Length)
                {
                    return ''
                }

                $actualEnd = if ($End -lt 0 -or $End -gt $Line.Length) { $Line.Length } else { $End }
                if ($actualEnd -lt $Start)
                {
                    $actualEnd = $Line.Length
                }

                return $Line.Substring($Start, $actualEnd - $Start).Trim()
            }

            $packages = @()
            for ($i = $headerIndex + 1; $i -lt $lines.Count; $i++)
            {
                $line = $lines[$i]
                if ([String]::IsNullOrWhiteSpace($line) -or $line -match '^-{3,}' -or $line -match '^No installed package found' -or $line -match '^\d+\s+package\(s\)')
                {
                    continue
                }

                $name = Get-WingetTableCell -Line $line -Start $nameStart -End $idStart
                $id = Get-WingetTableCell -Line $line -Start $idStart -End $versionStart
                $installedVersion = if ($sourceStart -ge 0)
                {
                    Get-WingetTableCell -Line $line -Start $versionStart -End $sourceStart
                }
                else
                {
                    Get-WingetTableCell -Line $line -Start $versionStart
                }
                $source = if ($sourceStart -ge 0) { Get-WingetTableCell -Line $line -Start $sourceStart } else { '' }

                if ([String]::IsNullOrWhiteSpace($name))
                {
                    continue
                }

                $packages += Get-PackageRemoveObject -Manager $Manager -Name $name -Id $id -Type 'Package' -InstalledVersion $installedVersion -Source $source
            }

            return $packages
        }

        function Get-WingetPackageDescription
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [PSCustomObject]$Package
            )

            $arguments = @('show')
            if (-not [String]::IsNullOrWhiteSpace($Package.Id))
            {
                $arguments += @('--id', $Package.Id, '--exact')
            }
            elseif (-not [String]::IsNullOrWhiteSpace($Package.Name))
            {
                $arguments += $Package.Name
            }
            else
            {
                return ''
            }

            $jsonResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments ($arguments + @('--accept-source-agreements', '--output', 'json'))
            if ($jsonResult.ExitCode -eq 0)
            {
                $lines = @($jsonResult.Output | ForEach-Object { "$($_)" })
                $startIndex = -1
                for ($i = 0; $i -lt $lines.Count; $i++)
                {
                    $trimmedLine = $lines[$i].Trim()
                    if ($trimmedLine.StartsWith('{') -or $trimmedLine.StartsWith('['))
                    {
                        $startIndex = $i
                        break
                    }
                }

                if ($startIndex -ge 0)
                {
                    $jsonText = ($lines[$startIndex..($lines.Count - 1)] -join "`n").Trim()
                    if (-not [String]::IsNullOrWhiteSpace($jsonText))
                    {
                        try
                        {
                            $json = $jsonText | ConvertFrom-Json
                            $candidatePackages = @()

                            if ($json -is [Array])
                            {
                                $candidatePackages += @($json)
                            }
                            elseif ($json.PSObject.Properties['Data'])
                            {
                                $candidatePackages += @($json.Data)
                            }
                            elseif ($json.PSObject.Properties['Packages'])
                            {
                                $candidatePackages += @($json.Packages)
                            }
                            elseif ($json.PSObject.Properties['DefaultLocale'] -or $json.PSObject.Properties['Description'])
                            {
                                $candidatePackages += @($json)
                            }

                            foreach ($candidatePackage in $candidatePackages)
                            {
                                $description = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $candidatePackage -PropertyName @('Description', 'ShortDescription', 'Summary', 'PackageDescription'))
                                if (-not [String]::IsNullOrWhiteSpace($description))
                                {
                                    return $description
                                }

                                $defaultLocale = Get-FirstPropertyValue -InputObject $candidatePackage -PropertyName @('DefaultLocale', 'Locale')
                                if ($null -ne $defaultLocale)
                                {
                                    $description = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $defaultLocale -PropertyName @('Description', 'ShortDescription', 'Summary'))
                                    if (-not [String]::IsNullOrWhiteSpace($description))
                                    {
                                        return $description
                                    }
                                }
                            }
                        }
                        catch
                        {
                            Write-Verbose "Unable to parse winget show JSON output: $($_.Exception.Message)"
                        }
                    }
                }
            }

            $arguments += '--accept-source-agreements'
            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments $arguments
            if ($result.ExitCode -ne 0)
            {
                return ''
            }

            $descriptionLines = New-Object 'System.Collections.Generic.List[String]'
            $inDescription = $false

            foreach ($line in @($result.Output | ForEach-Object { "$($_)" }))
            {
                if (-not $inDescription)
                {
                    if ($line -match '^\s*Description\s*:\s*(?<Value>.*)$')
                    {
                        $inDescription = $true
                        $initialDescription = $Matches.Value.Trim()
                        if (-not [String]::IsNullOrWhiteSpace($initialDescription))
                        {
                            $descriptionLines.Add($initialDescription)
                        }
                    }

                    continue
                }

                if ($line -match '^[A-Za-z][A-Za-z\s]+\s*:')
                {
                    break
                }

                $trimmedLine = $line.Trim()
                if ([String]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine -match '^-{3,}$')
                {
                    continue
                }

                $descriptionLines.Add($trimmedLine)
            }

            return (($descriptionLines | Where-Object { -not [String]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()
        }

        function Resolve-WingetPackageDescriptions
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter()]
                [PSCustomObject[]]$Packages = @()
            )

            if ($Packages.Count -eq 0)
            {
                return @()
            }

            if ($CommandRunner)
            {
                return @($Packages)
            }

            $descriptionLookup = @{}
            foreach ($package in $Packages)
            {
                if (-not [String]::IsNullOrWhiteSpace($package.Description))
                {
                    continue
                }

                $key = if (-not [String]::IsNullOrWhiteSpace($package.Id))
                {
                    $package.Id.Trim().ToLowerInvariant()
                }
                elseif (-not [String]::IsNullOrWhiteSpace($package.Name))
                {
                    $package.Name.Trim().ToLowerInvariant()
                }
                else
                {
                    ''
                }

                if ([String]::IsNullOrWhiteSpace($key))
                {
                    continue
                }

                if (-not $descriptionLookup.ContainsKey($key))
                {
                    $descriptionLookup[$key] = Get-WingetPackageDescription -Manager $Manager -Package $package
                }

                if (-not [String]::IsNullOrWhiteSpace($descriptionLookup[$key]))
                {
                    $package.Description = $descriptionLookup[$key]
                }
            }

            return @($Packages)
        }

        function Get-WingetInstalledPackages
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            $jsonResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('list', '--accept-source-agreements', '--output', 'json')
            if ($jsonResult.ExitCode -eq 0)
            {
                $jsonPackages = @(ConvertFrom-WingetJsonOutput -Manager $Manager -Output $jsonResult.Output)
                if ($jsonPackages.Count -gt 0)
                {
                    return @(Resolve-WingetPackageDescriptions -Manager $Manager -Packages $jsonPackages)
                }

                if (-not (($jsonResult.Output -join "`n") -match 'Name\s+Id\s+Version'))
                {
                    return @()
                }
            }

            $tableResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('list', '--accept-source-agreements')
            if ($tableResult.ExitCode -ne 0)
            {
                $message = ($tableResult.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to query winget packages: $message"
            }

            $tablePackages = @(ConvertFrom-WingetTableOutput -Manager $Manager -Output $tableResult.Output)
            return @(Resolve-WingetPackageDescriptions -Manager $Manager -Packages $tablePackages)
        }

        function ConvertFrom-BrewListOutput
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [ValidateSet('Formula', 'Cask')]
                [String]$Type,

                [Parameter()]
                [Object[]]$Output = @()
            )

            $packages = @()
            foreach ($line in @($Output | ForEach-Object { "$_" }))
            {
                $trimmedLine = $line.Trim()
                if ([String]::IsNullOrWhiteSpace($trimmedLine))
                {
                    continue
                }

                $parts = $trimmedLine -split '\s+'
                if ($parts.Count -lt 1 -or [String]::IsNullOrWhiteSpace($parts[0]))
                {
                    continue
                }

                $name = $parts[0]
                $version = if ($parts.Count -gt 1) { ($parts[1..($parts.Count - 1)] -join ', ') } else { '' }
                $source = if ($Type -eq 'Cask') { 'homebrew/cask' } else { 'homebrew/core' }

                $packages += Get-PackageRemoveObject -Manager $Manager -Name $name -Id $name -Type $Type -InstalledVersion $version -Source $source
            }

            return $packages
        }

        function Resolve-BrewPackageDescriptions
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter()]
                [PSCustomObject[]]$Packages = @()
            )

            if ($Packages.Count -eq 0)
            {
                return @()
            }

            if ($CommandRunner)
            {
                return @($Packages)
            }

            $formulaNames = @($Packages |
                Where-Object {
                    $_.Type -eq 'Formula' -and
                    -not [String]::IsNullOrWhiteSpace($_.Name) -and
                    [String]::IsNullOrWhiteSpace($_.Description)
                } |
                ForEach-Object { $_.Name } |
                Select-Object -Unique)

            $caskNames = @($Packages |
                Where-Object {
                    $_.Type -eq 'Cask' -and
                    -not [String]::IsNullOrWhiteSpace($_.Name) -and
                    [String]::IsNullOrWhiteSpace($_.Description)
                } |
                ForEach-Object { $_.Name } |
                Select-Object -Unique)

            $descriptionLookup = @{}

            if ($formulaNames.Count -gt 0)
            {
                $formulaInfoResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments (@('info', '--json=v2', '--formula') + $formulaNames)
                if ($formulaInfoResult.ExitCode -eq 0)
                {
                    try
                    {
                        $formulaInfo = (($formulaInfoResult.Output | ForEach-Object { "$($_)" }) -join "`n") | ConvertFrom-Json
                        foreach ($formula in @($formulaInfo.formulae))
                        {
                            $name = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $formula -PropertyName @('name', 'full_name'))
                            $description = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $formula -PropertyName @('desc', 'description', 'summary'))
                            if (-not [String]::IsNullOrWhiteSpace($name) -and -not [String]::IsNullOrWhiteSpace($description))
                            {
                                $descriptionLookup[$name.Trim().ToLowerInvariant()] = $description
                            }
                        }
                    }
                    catch
                    {
                        Write-Verbose "Unable to parse Homebrew formula descriptions: $($_.Exception.Message)"
                    }
                }
            }

            if ($caskNames.Count -gt 0)
            {
                $caskInfoResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments (@('info', '--json=v2', '--cask') + $caskNames)
                if ($caskInfoResult.ExitCode -eq 0)
                {
                    try
                    {
                        $caskInfo = (($caskInfoResult.Output | ForEach-Object { "$($_)" }) -join "`n") | ConvertFrom-Json
                        foreach ($cask in @($caskInfo.casks))
                        {
                            $name = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $cask -PropertyName @('token', 'name'))
                            $description = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $cask -PropertyName @('desc', 'description', 'summary'))
                            if (-not [String]::IsNullOrWhiteSpace($name) -and -not [String]::IsNullOrWhiteSpace($description))
                            {
                                $descriptionLookup[$name.Trim().ToLowerInvariant()] = $description
                            }
                        }
                    }
                    catch
                    {
                        Write-Verbose "Unable to parse Homebrew cask descriptions: $($_.Exception.Message)"
                    }
                }
            }

            foreach ($package in $Packages)
            {
                if (-not [String]::IsNullOrWhiteSpace($package.Description))
                {
                    continue
                }

                if ([String]::IsNullOrWhiteSpace($package.Name))
                {
                    continue
                }

                $key = $package.Name.Trim().ToLowerInvariant()
                if ($descriptionLookup.ContainsKey($key))
                {
                    $package.Description = $descriptionLookup[$key]
                }
            }

            return @($Packages)
        }

        function Get-BrewInstalledPackages
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            $packages = @()
            $formulaResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('list', '--formula', '--versions')
            if ($formulaResult.ExitCode -ne 0)
            {
                $message = ($formulaResult.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to query Homebrew formulae: $message"
            }

            $packages += ConvertFrom-BrewListOutput -Manager $Manager -Type 'Formula' -Output $formulaResult.Output

            $caskResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('list', '--cask', '--versions')
            if ($caskResult.ExitCode -ne 0)
            {
                $message = ($caskResult.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to query Homebrew casks: $message"
            }

            $packages += ConvertFrom-BrewListOutput -Manager $Manager -Type 'Cask' -Output $caskResult.Output

            $packages = @(Resolve-BrewPackageDescriptions -Manager $Manager -Packages $packages)

            return $packages
        }

        function Get-AptInstalledPackages
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('list', '--installed')
            if ($result.ExitCode -ne 0)
            {
                $message = ($result.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to query APT packages: $message"
            }

            $packages = @()
            foreach ($line in @($result.Output | ForEach-Object { "$_" }))
            {
                $trimmedLine = $line.Trim()
                if ([String]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine -match '^Listing' -or $trimmedLine -match '^WARNING:' -or $trimmedLine -match '^N:')
                {
                    continue
                }

                if ($trimmedLine -match '^(?<Name>[^/\s]+)/(?<Repository>\S+)\s+(?<Version>\S+)\s+(?<Architecture>\S+)\s+\[(?<State>[^\]]+)\]')
                {
                    $name = $Matches.Name
                    $repository = $Matches.Repository
                    $version = $Matches.Version
                    $architecture = $Matches.Architecture
                    $state = $Matches.State
                    $notes = if ($state -match 'automatic') { 'Automatic' } else { '' }
                    $packages += Get-PackageRemoveObject -Manager $Manager -Name $name -Id $name -Type $architecture -InstalledVersion $version -Source $repository -Notes $notes
                }
            }

            return $packages
        }

        function Split-ApkPackageVersion
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$InstalledToken
            )

            $parts = $InstalledToken -split '-'
            if ($parts.Count -lt 2)
            {
                return [PSCustomObject]@{
                    Name = $InstalledToken
                    Version = ''
                }
            }

            for ($i = $parts.Count - 1; $i -gt 0; $i--)
            {
                $candidateVersion = ($parts[$i..($parts.Count - 1)] -join '-')
                if ($candidateVersion -match '^(?:[0-9]|v[0-9])')
                {
                    return [PSCustomObject]@{
                        Name = ($parts[0..($i - 1)] -join '-')
                        Version = $candidateVersion
                    }
                }
            }

            [PSCustomObject]@{
                Name = $InstalledToken
                Version = ''
            }
        }

        function Get-ApkInstalledPackages
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('info', '-v')
            if ($result.ExitCode -ne 0)
            {
                $message = ($result.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to query apk packages: $message"
            }

            $packages = @()
            foreach ($line in @($result.Output | ForEach-Object { "$_" }))
            {
                $trimmedLine = $line.Trim()
                if ([String]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine -match '^WARNING:')
                {
                    continue
                }

                $packageInfo = Split-ApkPackageVersion -InstalledToken $trimmedLine
                if ([String]::IsNullOrWhiteSpace($packageInfo.Name))
                {
                    continue
                }

                $packages += Get-PackageRemoveObject -Manager $Manager -Name $packageInfo.Name -Id $packageInfo.Name -Type 'Package' -InstalledVersion $packageInfo.Version -Source 'apk'
            }

            return $packages
        }

        function Get-PlatformPackages
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            switch ($Manager.Name)
            {
                'winget' { Get-WingetInstalledPackages -Manager $Manager }
                'brew' { Get-BrewInstalledPackages -Manager $Manager }
                'apt' { Get-AptInstalledPackages -Manager $Manager }
                'apk' { Get-ApkInstalledPackages -Manager $Manager }
                default { throw "Unsupported package manager '$($Manager.Name)'." }
            }
        }

        function Test-PackagePatternMatch
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Package,

                [Parameter()]
                [String[]]$Pattern = @()
            )

            if (-not $Pattern -or $Pattern.Count -eq 0)
            {
                return $false
            }

            foreach ($item in @($Pattern | Where-Object { -not [String]::IsNullOrWhiteSpace($_) }))
            {
                if ($Package.Name -like $item -or $Package.Id -like $item)
                {
                    return $true
                }
            }

            return $false
        }

        function Select-PackageInstallRecords
        {
            param(
                [Parameter()]
                [PSCustomObject[]]$InstalledPackages = @(),

                [Parameter()]
                [ScriptBlock]$KeyReader,

                [Parameter()]
                [Int32]$PageSize = 0,

                [Parameter()]
                [String]$PackageManagerName = '',

                [Parameter()]
                [String]$SourceFilter = '',

                [Parameter()]
                [Switch]$ReturnToPlatformPackageManagerOnBackKey
            )

            if ($InstalledPackages.Count -eq 0)
            {
                return @()
            }

            $allPackages = $InstalledPackages
            $uniqueSources = @($allPackages | ForEach-Object { $_.Source } | Where-Object { -not [String]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
            $hasEmptySource = @($allPackages | Where-Object { [String]::IsNullOrWhiteSpace($_.Source) }).Count -gt 0
            $availableSources = @('All') + $uniqueSources
            $hasSourceFilter = $uniqueSources.Count -gt 1 -or ($uniqueSources.Count -eq 1 -and $hasEmptySource)
            $sourceFilterIndex = 0
            if ($hasSourceFilter -and -not [String]::IsNullOrWhiteSpace($SourceFilter))
            {
                for ($si = 1; $si -lt $availableSources.Count; $si++)
                {
                    if ($availableSources[$si] -ieq $SourceFilter)
                    {
                        $sourceFilterIndex = $si
                        break
                    }
                }
            }
            elseif ($hasSourceFilter)
            {
                $isWingetContext = @($allPackages | Where-Object { "$($_.PackageManager)" -ieq 'winget' }).Count -gt 0
                if ($isWingetContext)
                {
                    for ($si = 1; $si -lt $availableSources.Count; $si++)
                    {
                        if ($availableSources[$si] -ieq 'winget')
                        {
                            $sourceFilterIndex = $si
                            break
                        }
                    }
                }
            }

            function Get-FilteredVisiblePackages
            {
                param(
                    [Parameter(Mandatory)]
                    [Int32]$SourceIndex,

                    [Parameter()]
                    [String]$NameFilter = ''
                )

                $sourcePackages = @(
                    if ($availableSources[$SourceIndex] -eq 'All')
                    {
                        $allPackages
                    }
                    else
                    {
                        $allPackages | Where-Object { $_.Source -eq $availableSources[$SourceIndex] }
                    }
                )

                if ([String]::IsNullOrWhiteSpace($NameFilter))
                {
                    return @($sourcePackages)
                }

                $namePattern = "*$NameFilter*"
                return @($sourcePackages | Where-Object { $_.Name -like $namePattern -or $_.Id -like $namePattern })
            }

            function Read-PackageNameFilter
            {
                param(
                    [Parameter()]
                    [String]$CurrentFilter = ''
                )

                $restoreInPlaceRedraw = $pickerRenderState.UseInPlaceRedraw
                $pickerRenderState.UseInPlaceRedraw = $false
                $pickerRenderState.RenderedLineCount = 0

                $workingFilter = "$CurrentFilter"
                try
                {
                    while ($true)
                    {
                        Clear-Host
                        Write-Host 'Filter removable packages' -ForegroundColor Cyan
                        Write-Host 'Type package name text to match Name or Id.' -ForegroundColor DarkGray
                        Write-Host ''
                        Write-Host "Current filter: $workingFilter" -ForegroundColor White
                        Write-Host ''
                        Write-Host 'Enter: apply filter  Backspace: delete  Ctrl+U: clear  Esc/Ctrl+C: cancel' -ForegroundColor DarkGray

                        $filterKey = & $KeyReader
                        $isFilterControlC = $filterKey.Key -eq [ConsoleKey]::C -and (($filterKey.Modifiers -band [ConsoleModifiers]::Control) -eq [ConsoleModifiers]::Control)
                        $isFilterControlC = $isFilterControlC -or ([Int32][Char]$filterKey.KeyChar -eq 3)
                        if ($filterKey.Key -eq [ConsoleKey]::Escape -or $isFilterControlC)
                        {
                            return [PSCustomObject]@{
                                Applied = $false
                                Value = $CurrentFilter
                            }
                        }

                        if ($filterKey.Key -eq [ConsoleKey]::Enter)
                        {
                            return [PSCustomObject]@{
                                Applied = $true
                                Value = $workingFilter.Trim()
                            }
                        }

                        if ($filterKey.Key -eq [ConsoleKey]::Backspace)
                        {
                            if ($workingFilter.Length -gt 0)
                            {
                                $workingFilter = $workingFilter.Substring(0, $workingFilter.Length - 1)
                            }

                            continue
                        }

                        $isCtrlU = $filterKey.Key -eq [ConsoleKey]::U -and (($filterKey.Modifiers -band [ConsoleModifiers]::Control) -eq [ConsoleModifiers]::Control)
                        if ($isCtrlU)
                        {
                            $workingFilter = ''
                            continue
                        }

                        if (-not [Char]::IsControl($filterKey.KeyChar))
                        {
                            $workingFilter += $filterKey.KeyChar
                        }
                    }
                }
                finally
                {
                    Clear-Host
                    $pickerRenderState.UseInPlaceRedraw = $restoreInPlaceRedraw
                    $pickerRenderState.RenderedLineCount = 0
                }
            }

            $nameFilterText = ''
            $visiblePackages = @(Get-FilteredVisiblePackages -SourceIndex $sourceFilterIndex -NameFilter $nameFilterText)

            $usingConsoleKeyReader = $false
            if ($null -eq $KeyReader)
            {
                try
                {
                    if ([Console]::IsInputRedirected)
                    {
                        throw 'Console input is redirected.'
                    }
                }
                catch
                {
                    throw 'Interactive package selection requires an attached console. Use -All, -NonInteractive, or -IncludePackage with -All in non-interactive sessions.'
                }

                $KeyReader = { [Console]::ReadKey($true) }
                $usingConsoleKeyReader = $true
            }

            function Format-PickerCell
            {
                param(
                    [Parameter()]
                    [String]$Text,

                    [Parameter(Mandatory)]
                    [Int32]$Width
                )

                $value = if ($null -eq $Text) { '' } else { $Text }
                if ($value.Length -gt $Width)
                {
                    return $value.Substring(0, [Math]::Max(1, $Width - 1)) + '~'
                }

                return $value.PadRight($Width)
            }

            function Test-PackagePickerCancelKey
            {
                param(
                    [Parameter(Mandatory)]
                    [ConsoleKeyInfo]$KeyInfo
                )

                $isControlC = $KeyInfo.Key -eq [ConsoleKey]::C -and (($KeyInfo.Modifiers -band [ConsoleModifiers]::Control) -eq [ConsoleModifiers]::Control)
                $isControlC = $isControlC -or ([Int32][Char]$KeyInfo.KeyChar -eq 3)

                return $KeyInfo.Key -in @([ConsoleKey]::Escape, [ConsoleKey]::Q) -or $isControlC
            }

            function Test-PackagePickerManagerBackKey
            {
                param(
                    [Parameter(Mandatory)]
                    [ConsoleKeyInfo]$KeyInfo
                )

                return $ReturnToPlatformPackageManagerOnBackKey -and $KeyInfo.Key -in @([ConsoleKey]::Backspace, [ConsoleKey]::Delete)
            }

            function Test-PackagePickerHelpKey
            {
                param(
                    [Parameter(Mandatory)]
                    [ConsoleKeyInfo]$KeyInfo
                )

                return $KeyInfo.KeyChar -eq '?'
            }

            function Get-PackagePickerPageSize
            {
                param(
                    [Parameter(Mandatory)]
                    [Int32]$RequestedPageSize,

                    [Parameter(Mandatory)]
                    [Int32]$ItemCount
                )

                if ($RequestedPageSize -gt 0)
                {
                    return [Math]::Min($RequestedPageSize, [Math]::Max(1, $ItemCount))
                }

                $fallbackPageSize = [Math]::Min(15, [Math]::Max(1, $ItemCount))

                try
                {
                    $windowHeight = 0

                    if ($Host -and $Host.UI -and $Host.UI.RawUI)
                    {
                        $windowHeight = [Int32]$Host.UI.RawUI.WindowSize.Height
                    }

                    if ($windowHeight -le 0 -and -not [Console]::IsOutputRedirected)
                    {
                        $windowHeight = [Console]::WindowHeight
                    }

                    if ($windowHeight -gt 0)
                    {
                        $reservedRows = 17
                        return [Math]::Min([Math]::Max(1, $windowHeight - $reservedRows), [Math]::Max(1, $ItemCount))
                    }
                }
                catch
                {
                    Write-Verbose "Unable to determine console height for package picker: $($_.Exception.Message)"
                }

                return $fallbackPageSize
            }

            function Get-PickerConsoleBufferWidth
            {
                $bufferWidth = 0

                try
                {
                    if (-not [Console]::IsOutputRedirected)
                    {
                        $bufferWidth = [Int32][Console]::BufferWidth
                    }
                }
                catch
                {
                    $bufferWidth = 0
                }

                if ($bufferWidth -le 0)
                {
                    try
                    {
                        if ($Host -and $Host.UI -and $Host.UI.RawUI)
                        {
                            $bufferWidth = [Int32]$Host.UI.RawUI.BufferSize.Width
                        }
                    }
                    catch
                    {
                        $bufferWidth = 0
                    }
                }

                return [Math]::Max(0, $bufferWidth)
            }

            function Get-PackagePickerKey
            {
                param(
                    [Parameter(Mandatory)]
                    [PSCustomObject]$Package
                )

                return "$($Package.PackageManager)::$($Package.Source)::$($Package.Id)::$($Package.Name)::$($Package.Type)"
            }

            function Get-PackageTypeDisplay
            {
                param(
                    [Parameter()]
                    [String]$Type
                )

                if ([String]::IsNullOrWhiteSpace($Type))
                {
                    return ''
                }

                switch -Regex ($Type)
                {
                    '^Package$' { return 'Pkg' }
                    '^Formula$' { return 'Form' }
                    default { return $Type }
                }
            }

            function Get-PackagePickerTextMaximum
            {
                param(
                    [Parameter()]
                    [Object[]]$Values = @(),

                    [Parameter(Mandatory)]
                    [Int32]$Minimum,

                    [Parameter(Mandatory)]
                    [Int32]$Maximum
                )

                $measuredMaximum = @(
                    $Values |
                    Where-Object { $null -ne $_ } |
                    ForEach-Object { "$_".Length } |
                    Measure-Object -Maximum
                )[0].Maximum

                if ($null -eq $measuredMaximum)
                {
                    $measuredMaximum = 0
                }

                return [Math]::Min($Maximum, [Math]::Max($Minimum, [Int32]$measuredMaximum))
            }

            function Get-PackagePickerFrameWidth
            {
                $bufferWidth = Get-PickerConsoleBufferWidth
                if ($bufferWidth -le 0)
                {
                    return 119
                }

                return [Math]::Max(60, ($bufferWidth - 1))
            }

            function Get-PackagePickerTableLineWidth
            {
                param(
                    [Parameter(Mandatory)]
                    [PSCustomObject]$ColumnWidths,

                    [Parameter()]
                    [Switch]$IncludesPurge
                )

                $prefixWidth = if ($IncludesPurge) { 12 } else { 6 }
                return $prefixWidth + [Int32]$ColumnWidths.Name + 1 + [Int32]$ColumnWidths.Id + 1 + [Int32]$ColumnWidths.Version + 1 + [Int32]$ColumnWidths.Type + 1 + [Int32]$ColumnWidths.Source
            }

            function Compress-PackagePickerTableWidths
            {
                param(
                    [Parameter(Mandatory)]
                    [PSCustomObject]$ColumnWidths,

                    [Parameter(Mandatory)]
                    [Int32]$MaximumWidth,

                    [Parameter()]
                    [Switch]$IncludesPurge
                )

                $minimumWidths = @{
                    Name = 12
                    Id = 14
                    Version = 8
                    Type = 3
                    Source = 5
                }
                $shrinkOrder = @('Id', 'Name', 'Version', 'Source', 'Type')

                while ((Get-PackagePickerTableLineWidth -ColumnWidths $ColumnWidths -IncludesPurge:$IncludesPurge.IsPresent) -gt $MaximumWidth)
                {
                    $shrunk = $false
                    foreach ($columnName in $shrinkOrder)
                    {
                        if ([Int32]$ColumnWidths.$columnName -gt [Int32]$minimumWidths[$columnName])
                        {
                            $ColumnWidths.$columnName = [Int32]$ColumnWidths.$columnName - 1
                            $shrunk = $true
                            if ((Get-PackagePickerTableLineWidth -ColumnWidths $ColumnWidths -IncludesPurge:$IncludesPurge.IsPresent) -le $MaximumWidth)
                            {
                                break
                            }
                        }
                    }

                    if (-not $shrunk)
                    {
                        break
                    }
                }

                return $ColumnWidths
            }

            $showPurge = $PackageManagerName -in @('winget', 'brew', 'apt', 'apk')
            $purgeWidth = 5
            $pickerFrameWidth = Get-PackagePickerFrameWidth
            $columnWidths = [PSCustomObject]@{
                Name = Get-PackagePickerTextMaximum -Values @($InstalledPackages | ForEach-Object { $_.Name }) -Minimum 12 -Maximum 30
                Id = Get-PackagePickerTextMaximum -Values @($InstalledPackages | ForEach-Object { $_.Id }) -Minimum 14 -Maximum 32
                Version = Get-PackagePickerTextMaximum -Values @($InstalledPackages | ForEach-Object { $_.InstalledVersion }) -Minimum 8 -Maximum 16
                Type = Get-PackagePickerTextMaximum -Values @($InstalledPackages | ForEach-Object { Get-PackageTypeDisplay -Type $_.Type }) -Minimum 3 -Maximum 7
                Source = Get-PackagePickerTextMaximum -Values @($InstalledPackages | ForEach-Object { $_.Source }) -Minimum 5 -Maximum 32
            }
            $columnWidths = Compress-PackagePickerTableWidths -ColumnWidths $columnWidths -MaximumWidth $pickerFrameWidth -IncludesPurge:$showPurge
            $nameWidth = [Int32]$columnWidths.Name
            $idWidth = [Int32]$columnWidths.Id
            $versionWidth = [Int32]$columnWidths.Version
            $typeWidth = [Int32]$columnWidths.Type
            $sourceWidth = [Int32]$columnWidths.Source
            $pageSize = Get-PackagePickerPageSize -RequestedPageSize $PageSize -ItemCount $InstalledPackages.Count

            $selectedKeys = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $purgeKeys = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $wingetDescriptionAttempted = @{}
            $pendingWingetDescriptionLookupKey = ''
            $actionStatus = ''
            $actionStatusColor = [ConsoleColor]::DarkGray
            $cursor = 0
            $topIndex = 0
            $restoreTreatControlCAsInput = $false
            $previousTreatControlCAsInput = $false
            $pickerRenderState = @{
                UseInPlaceRedraw = $false
                ConsoleBufferWidth = 0
                RenderedLineCount = 0
            }

            function Format-PickerFrameLine
            {
                param(
                    [Parameter()]
                    [String]$Text = '',

                    [Parameter()]
                    [Nullable[ConsoleColor]]$ForegroundColor
                )

                [PSCustomObject]@{
                    Text = $Text
                    ForegroundColor = $ForegroundColor
                }
            }

            function Get-PickerFrameLineText
            {
                param(
                    [Parameter()]
                    [Object]$Line
                )

                if ($null -eq $Line)
                {
                    return ''
                }

                $textProperty = @($Line.PSObject.Properties.Match('Text'))[0]
                if ($null -ne $textProperty)
                {
                    return "$($textProperty.Value)"
                }

                return "$Line"
            }

            function Get-PickerFrameLineColor
            {
                param(
                    [Parameter()]
                    [Object]$Line
                )

                if ($null -eq $Line)
                {
                    return $null
                }

                $colorProperty = @($Line.PSObject.Properties.Match('ForegroundColor'))[0]
                if ($null -eq $colorProperty -or $null -eq $colorProperty.Value)
                {
                    return $null
                }

                return [ConsoleColor]$colorProperty.Value
            }

            function Format-PickerColumnText
            {
                param(
                    [Parameter()]
                    [String]$Text,

                    [Parameter(Mandatory)]
                    [Int32]$Width
                )

                $value = if ($null -eq $Text) { '' } else { $Text }
                if ($value.Length -gt $Width)
                {
                    if ($Width -le 1)
                    {
                        return $value.Substring(0, 1)
                    }

                    return $value.Substring(0, [Math]::Max(1, $Width - 1)) + '~'
                }

                return $value.PadRight($Width)
            }

            function Get-SideBySideFrameLines
            {
                param(
                    [Parameter(Mandatory)]
                    [Object[]]$LeftLines,

                    [Parameter(Mandatory)]
                    [Object[]]$RightLines
                )

                $consoleWidth = if ($pickerRenderState.ConsoleBufferWidth -gt 0) { $pickerRenderState.ConsoleBufferWidth } else { 120 }
                $gapWidth = 4
                $usableWidth = [Math]::Max(40, $consoleWidth - $gapWidth)
                $leftWidth = [Math]::Max(38, [Int32][Math]::Floor($usableWidth * 0.62))
                if ($leftWidth -gt ($usableWidth - 20))
                {
                    $leftWidth = [Math]::Max(20, $usableWidth - 20)
                }

                $rightWidth = [Math]::Max(20, $usableWidth - $leftWidth)
                if (($leftWidth + $rightWidth) -gt $usableWidth)
                {
                    $leftWidth = [Math]::Max(20, $usableWidth - $rightWidth)
                }

                $lineCount = [Math]::Max($LeftLines.Count, $RightLines.Count)
                $combinedLines = @()

                for ($lineIndex = 0; $lineIndex -lt $lineCount; $lineIndex++)
                {
                    $leftLine = if ($lineIndex -lt $LeftLines.Count) { $LeftLines[$lineIndex] } else { $null }
                    $rightLine = if ($lineIndex -lt $RightLines.Count) { $RightLines[$lineIndex] } else { $null }

                    $leftText = Format-PickerColumnText -Text (Get-PickerFrameLineText -Line $leftLine) -Width $leftWidth
                    $rightText = Format-PickerColumnText -Text (Get-PickerFrameLineText -Line $rightLine) -Width $rightWidth
                    $combinedText = $leftText + (' ' * $gapWidth) + $rightText

                    $combinedColor = Get-PickerFrameLineColor -Line $leftLine
                    if ($null -eq $combinedColor)
                    {
                        $combinedColor = Get-PickerFrameLineColor -Line $rightLine
                    }

                    $combinedLines += Format-PickerFrameLine -Text $combinedText -ForegroundColor $combinedColor
                }

                return $combinedLines
            }

            function Write-PickerFrame
            {
                param(
                    [Parameter()]
                    [Object[]]$Lines = @()
                )

                if (-not $pickerRenderState.UseInPlaceRedraw)
                {
                    Clear-Host
                    foreach ($line in $Lines)
                    {
                        $lineText = Get-PickerFrameLineText -Line $line
                        $lineColor = Get-PickerFrameLineColor -Line $line
                        if ($null -eq $lineColor)
                        {
                            Write-Host $lineText
                        }
                        else
                        {
                            Write-Host $lineText -ForegroundColor $lineColor
                        }
                    }

                    return
                }

                $currentBufferWidth = Get-PickerConsoleBufferWidth
                if ($currentBufferWidth -gt 0)
                {
                    $pickerRenderState.ConsoleBufferWidth = $currentBufferWidth
                }

                # Writing exactly to the console width can trigger terminal auto-wrap,
                # which causes cursor jitter/artifacts in some Windows hosts.
                $frameWidth = [Math]::Max(1, ([Int32]$pickerRenderState.ConsoleBufferWidth - 1))
                $blankLine = ''.PadRight($frameWidth)
                $frameLines = @()
                foreach ($line in $Lines)
                {
                    $lineColor = Get-PickerFrameLineColor -Line $line
                    $text = Get-PickerFrameLineText -Line $line

                    if ([String]::IsNullOrEmpty($text))
                    {
                        $frameLines += Format-PickerFrameLine -Text $blankLine -ForegroundColor $lineColor
                        continue
                    }

                    $remaining = $text
                    while ($remaining.Length -gt $frameWidth)
                    {
                        $frameLines += Format-PickerFrameLine -Text $remaining.Substring(0, $frameWidth) -ForegroundColor $lineColor
                        $remaining = $remaining.Substring($frameWidth)
                    }

                    $frameLines += Format-PickerFrameLine -Text $remaining.PadRight($frameWidth) -ForegroundColor $lineColor
                }

                while ($frameLines.Count -lt $pickerRenderState.RenderedLineCount)
                {
                    $frameLines += Format-PickerFrameLine -Text $blankLine
                }

                try
                {
                    [Console]::SetCursorPosition(0, 0)
                    $originalForegroundColor = [Console]::ForegroundColor
                    try
                    {
                        for ($lineIndex = 0; $lineIndex -lt $frameLines.Count; $lineIndex++)
                        {
                            if ($lineIndex -gt 0)
                            {
                                [Console]::Write("`r`n")
                            }

                            $line = $frameLines[$lineIndex]
                            if ($null -eq $line.ForegroundColor)
                            {
                                [Console]::ForegroundColor = $originalForegroundColor
                            }
                            else
                            {
                                [Console]::ForegroundColor = $line.ForegroundColor
                            }

                            [Console]::Write($line.Text)
                        }
                    }
                    finally
                    {
                        [Console]::ForegroundColor = $originalForegroundColor
                    }

                    $pickerRenderState.RenderedLineCount = $frameLines.Count
                }
                catch
                {
                    $pickerRenderState.UseInPlaceRedraw = $false
                    Clear-Host
                    foreach ($fallbackLine in $Lines)
                    {
                        $fallbackLineText = Get-PickerFrameLineText -Line $fallbackLine
                        $fallbackLineColor = Get-PickerFrameLineColor -Line $fallbackLine
                        if ($null -eq $fallbackLineColor)
                        {
                            Write-Host $fallbackLineText
                        }
                        else
                        {
                            Write-Host $fallbackLineText -ForegroundColor $fallbackLineColor
                        }
                    }
                }
            }

            function Clear-PickerFrame
            {
                if (-not $pickerRenderState.UseInPlaceRedraw)
                {
                    Clear-Host
                    return
                }

                try
                {
                    if ($pickerRenderState.RenderedLineCount -gt 0)
                    {
                        $currentBufferWidth = Get-PickerConsoleBufferWidth
                        if ($currentBufferWidth -gt 0)
                        {
                            $pickerRenderState.ConsoleBufferWidth = $currentBufferWidth
                        }

                        $frameWidth = [Math]::Max(1, ([Int32]$pickerRenderState.ConsoleBufferWidth - 1))
                        $blankLine = ''.PadRight($frameWidth)
                        $clearLines = for ($lineIndex = 0; $lineIndex -lt $pickerRenderState.RenderedLineCount; $lineIndex++)
                        {
                            $blankLine
                        }

                        [Console]::SetCursorPosition(0, 0)
                        [Console]::Write(($clearLines -join "`r`n"))
                        [Console]::SetCursorPosition(0, 0)
                    }

                    $pickerRenderState.RenderedLineCount = 0
                }
                catch
                {
                    $pickerRenderState.UseInPlaceRedraw = $false
                    Clear-Host
                }
            }

            function Get-PickerViewportSummary
            {
                param(
                    [Parameter(Mandatory)]
                    [Int32]$TopIndex,

                    [Parameter(Mandatory)]
                    [Int32]$BottomIndex,

                    [Parameter(Mandatory)]
                    [Int32]$VisibleCount,

                    [Parameter(Mandatory)]
                    [Int32]$TotalCount,

                    [Parameter()]
                    [Int32]$SelectedCount = -1,

                    [Parameter()]
                    [String]$FilterText = ''
                )

                $visibleText = if ($VisibleCount -le 0)
                {
                    '0 visible'
                }
                else
                {
                    "$($TopIndex + 1)-$($BottomIndex + 1) of $VisibleCount visible"
                }

                $parts = @($visibleText, "$TotalCount total")
                if ($SelectedCount -ge 0)
                {
                    $parts += "$SelectedCount selected"
                }

                if (-not [String]::IsNullOrWhiteSpace($FilterText))
                {
                    $parts += $FilterText
                }

                return ($parts -join "  $([char]0x00B7)  ")
            }

            function Clear-PendingConsoleInput
            {
                if (-not $usingConsoleKeyReader)
                {
                    return
                }

                try
                {
                    if ([Console]::IsInputRedirected)
                    {
                        return
                    }

                    while ([Console]::KeyAvailable)
                    {
                        $null = [Console]::ReadKey($true)
                    }
                }
                catch
                {
                    Write-Verbose "Unable to clear pending console input: $($_.Exception.Message)"
                }
            }

            function Disable-PickerTerminalEcho
            {
                if (-not $usingConsoleKeyReader)
                {
                    return $null
                }

                $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { [Bool]$IsWindows }
                if ($isWindowsPlatform)
                {
                    return $null
                }

                try
                {
                    if ([Console]::IsInputRedirected)
                    {
                        return $null
                    }
                }
                catch
                {
                    return $null
                }

                $sttyCommand = Get-Command -Name 'stty' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -eq $sttyCommand)
                {
                    return $null
                }

                try
                {
                    $sttyState = @(& $sttyCommand.Source '-g' 2>$null) | Select-Object -First 1
                    if ([String]::IsNullOrWhiteSpace("$sttyState"))
                    {
                        return $null
                    }

                    $null = & $sttyCommand.Source '-echo' 2>$null
                    return "$sttyState"
                }
                catch
                {
                    Write-Verbose "Unable to disable terminal echo: $($_.Exception.Message)"
                    return $null
                }
            }

            function Restore-PickerTerminalEcho
            {
                param(
                    [Parameter()]
                    [String]$State
                )

                if ([String]::IsNullOrWhiteSpace($State))
                {
                    return
                }

                $sttyCommand = Get-Command -Name 'stty' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -eq $sttyCommand)
                {
                    return
                }

                try
                {
                    $null = & $sttyCommand.Source $State 2>$null
                }
                catch
                {
                    Write-Verbose "Unable to restore terminal echo: $($_.Exception.Message)"
                }
            }

            function Show-PackagePickerHelp
            {
                function Write-PackagePickerHelpItem
                {
                    param(
                        [Parameter(Mandatory)]
                        [String]$Shortcut,

                        [Parameter(Mandatory)]
                        [String]$Description
                    )

                    Write-Host '  - ' -NoNewline -ForegroundColor White
                    Write-Host "$Shortcut`: " -NoNewline -ForegroundColor White
                    Write-Host $Description -ForegroundColor DarkGray
                }

                $restoreInPlaceRedraw = $pickerRenderState.UseInPlaceRedraw
                $pickerRenderState.UseInPlaceRedraw = $false
                $pickerRenderState.RenderedLineCount = 0

                Clear-Host
                Write-Host 'Remove-PlatformPackage Help' -ForegroundColor Cyan
                Write-Host ''
                Write-Host 'Navigation' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'Up/Down' -Description 'move one package'
                Write-PackagePickerHelpItem -Shortcut 'PageUp/PageDown' -Description 'move one page'
                Write-PackagePickerHelpItem -Shortcut 'Home/End' -Description 'move to the first or last package'

                Write-Host ''
                Write-Host 'Selection' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'Space' -Description 'select or clear the current package'
                Write-PackagePickerHelpItem -Shortcut 'A' -Description 'toggle all visible packages'
                Write-PackagePickerHelpItem -Shortcut 'Enter' -Description 'remove selected packages, or the current package if none are selected'

                if ($showPurge)
                {
                    Write-PackagePickerHelpItem -Shortcut 'P' -Description 'toggle purge/zap removal for the current package'
                }

                if ($hasSourceFilter)
                {
                    Write-Host ''
                    Write-Host 'Source Filter' -ForegroundColor White
                    Write-PackagePickerHelpItem -Shortcut 'S' -Description "cycle source: $($availableSources -join ' | ')"
                }

                Write-Host ''
                Write-Host 'Name Filter' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'F' -Description 'set a name/id filter (blank value clears it)'

                Write-Host ''
                Write-Host 'Other Actions' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'D' -Description 'toggle dependency view for the current package'
                Write-PackagePickerHelpItem -Shortcut 'V' -Description 'load a missing winget description when available'
                Write-PackagePickerHelpItem -Shortcut 'Q, Esc, or Ctrl+C' -Description 'cancel removal'
                Write-PackagePickerHelpItem -Shortcut '?' -Description 'show this help'

                Write-Host ''
                Write-Host 'Press any key to return to the picker. Q/Esc/Ctrl+C cancels.' -ForegroundColor DarkGray

                $helpKey = & $KeyReader
                Clear-Host
                $pickerRenderState.UseInPlaceRedraw = $restoreInPlaceRedraw
                $pickerRenderState.RenderedLineCount = 0
                return (Test-PackagePickerCancelKey -KeyInfo $helpKey)
            }

            function Get-DependencyPanelSections
            {
                param(
                    [Parameter(Mandatory)]
                    [PSCustomObject]$Package
                )

                $sections = @()
                foreach ($direction in @('DependsOn', 'RequiredBy'))
                {
                    $dependencyParameters = @{
                        Package = @($Package)
                        Direction = $direction
                        PackageManager = $Package.PackageManager
                    }
                    if ($CommandRunner)
                    {
                        $dependencyParameters.CommandRunner = $CommandRunner
                    }

                    try
                    {
                        $records = @(Get-PlatformPackageDependency @dependencyParameters)
                        if ($records.Count -eq 0)
                        {
                            $sections += [PSCustomObject]@{
                                Direction = $direction
                                Error = ''
                                Lines = @('(none found)')
                            }
                            continue
                        }

                        $lines = @()
                        foreach ($record in $records | Select-Object -First 8)
                        {
                            $installedMarker = if ($record.Installed) { ' [installed]' } else { '' }
                            $lines += "- $($record.RelatedPackage) ($($record.DependencyType))$installedMarker"
                        }

                        if ($records.Count -gt $lines.Count)
                        {
                            $lines += "... and $($records.Count - $lines.Count) more"
                        }

                        $sections += [PSCustomObject]@{
                            Direction = $direction
                            Error = ''
                            Lines = $lines
                        }
                    }
                    catch
                    {
                        $sections += [PSCustomObject]@{
                            Direction = $direction
                            Error = $_.Exception.Message
                            Lines = @()
                        }
                    }
                }

                return $sections
            }

            try
            {
                if ($usingConsoleKeyReader)
                {
                    $previousTreatControlCAsInput = [Console]::TreatControlCAsInput
                    [Console]::TreatControlCAsInput = $true
                    $restoreTreatControlCAsInput = $true

                    $pickerRenderState.ConsoleBufferWidth = Get-PickerConsoleBufferWidth
                    if ($pickerRenderState.ConsoleBufferWidth -gt 0)
                    {
                        try
                        {
                            Clear-Host
                            $pickerRenderState.UseInPlaceRedraw = $true
                        }
                        catch
                        {
                            $pickerRenderState.UseInPlaceRedraw = $false
                        }
                    }
                }

                $showDependencyPanel = $false
                $dependencyPanelRestoreInPlaceRedraw = $null
                $dependencyPanelPackageKey = ''
                $dependencyPanelSections = @()
                $pendingDependencyPanelPackage = $null

                while ($true)
                {
                    if ($cursor -lt $topIndex)
                    {
                        $topIndex = $cursor
                    }
                    elseif ($cursor -ge ($topIndex + $pageSize))
                    {
                        $topIndex = $cursor - $pageSize + 1
                    }

                    if ($topIndex -lt 0)
                    {
                        $topIndex = 0
                    }

                    $maxTopIndex = [Math]::Max(0, $visiblePackages.Count - $pageSize)
                    if ($topIndex -gt $maxTopIndex)
                    {
                        $topIndex = $maxTopIndex
                    }

                    $bottomIndex = [Math]::Min($visiblePackages.Count - 1, $topIndex + $pageSize - 1)
                    $currentPackage = if ($visiblePackages.Count -gt 0) { $visiblePackages[$cursor] } else { $null }
                    $currentPackageLookupKey = if ($null -ne $currentPackage -and -not [String]::IsNullOrWhiteSpace($currentPackage.Id))
                    {
                        $currentPackage.Id.Trim().ToLowerInvariant()
                    }
                    elseif ($null -ne $currentPackage -and -not [String]::IsNullOrWhiteSpace($currentPackage.Name))
                    {
                        $currentPackage.Name.Trim().ToLowerInvariant()
                    }
                    else
                    {
                        ''
                    }
                    $isCurrentWingetDescriptionPending =
                    $null -ne $currentPackage -and
                    -not [String]::IsNullOrWhiteSpace($pendingWingetDescriptionLookupKey) -and
                    $pendingWingetDescriptionLookupKey -eq $currentPackageLookupKey
                    $canResolveCurrentWingetDescription =
                    $null -ne $currentPackage -and
                    $currentPackage.PackageManager -eq 'winget' -and
                    [String]::IsNullOrWhiteSpace($currentPackage.Description) -and
                    -not [String]::IsNullOrWhiteSpace($currentPackageLookupKey) -and
                    -not $wingetDescriptionAttempted.ContainsKey($currentPackageLookupKey)

                    $sourceHint = if ($hasSourceFilter) { "S: [$($availableSources[$sourceFilterIndex])]  " } else { '' }
                    $nameFilterHintValue = if ([String]::IsNullOrWhiteSpace($nameFilterText)) { 'all' } else { $nameFilterText }
                    $nameFilterHint = "F: [$nameFilterHintValue]  "

                    if ($showDependencyPanel -and $dependencyPanelPackageKey -ne $currentPackageLookupKey)
                    {
                        $pendingDependencyPanelPackage = $currentPackage
                        $dependencyPanelSections = @(
                            [PSCustomObject]@{
                                Direction = 'Resolving'
                                Error = ''
                                Lines = @('Resolving dependencies...')
                            }
                        )
                    }

                    if ($showDependencyPanel)
                    {
                        $currentVersion = if ([String]::IsNullOrWhiteSpace($currentPackage.InstalledVersion)) { 'n/a' } else { $currentPackage.InstalledVersion }
                        $currentSource = if ([String]::IsNullOrWhiteSpace($currentPackage.Source)) { 'n/a' } else { $currentPackage.Source }
                        $currentPublisher = if ([String]::IsNullOrWhiteSpace($currentPackage.Publisher)) { 'n/a' } else { $currentPackage.Publisher }
                        $currentDescription = if (-not [String]::IsNullOrWhiteSpace($currentPackage.Description))
                        {
                            $currentPackage.Description
                        }
                        elseif (-not [String]::IsNullOrWhiteSpace($currentPackage.Notes))
                        {
                            $currentPackage.Notes
                        }
                        elseif ($isCurrentWingetDescriptionPending)
                        {
                            'retrieving description...'
                        }
                        elseif ($currentPackage.PackageManager -eq 'winget' -and -not [String]::IsNullOrWhiteSpace($currentPackageLookupKey))
                        {
                            if ($wingetDescriptionAttempted.ContainsKey($currentPackageLookupKey)) { 'description unavailable' } else { '<press V to load>' }
                        }
                        else
                        {
                            'n/a'
                        }

                        $dependencyFilterSummary = @("filter: $nameFilterHintValue")
                        if ($hasSourceFilter)
                        {
                            $dependencyFilterSummary += "source: $($availableSources[$sourceFilterIndex])"
                        }

                        $frameLines = @(
                            (Format-PickerFrameLine -Text "Remove-PlatformPackage Dependencies - $($allPackages[0].PackageManagerDisplayName)" -ForegroundColor Cyan)
                            (Format-PickerFrameLine -Text (Get-PickerViewportSummary -TopIndex $topIndex -BottomIndex $bottomIndex -VisibleCount $visiblePackages.Count -TotalCount $allPackages.Count -SelectedCount $selectedKeys.Count -FilterText ($dependencyFilterSummary -join "  $([char]0x00B7)  ")) -ForegroundColor White)
                            ''
                            (Format-PickerFrameLine -Text 'Keys: B/Backspace/Delete/LeftArrow back  V details' -ForegroundColor DarkGray)
                            (Format-PickerFrameLine -Text "Nav: ${sourceHint}Home/End/PgUp/PgDn  ?: help  Q/Esc/Ctrl+C cancel" -ForegroundColor DarkGray)
                            ''
                            (Format-PickerFrameLine -Text ('Current: {0}' -f $currentPackage.Name) -ForegroundColor DarkGray)
                            (Format-PickerFrameLine -Text ('Id: {0} | Source: {1} | Publisher: {2}' -f $currentPackage.Id, $currentSource, $currentPublisher) -ForegroundColor DarkGray)
                            (Format-PickerFrameLine -Text ('Version: {0}' -f $currentVersion) -ForegroundColor DarkGray)
                            (Format-PickerFrameLine -Text ('Description: {0}' -f $currentDescription) -ForegroundColor DarkGray)
                            ''
                            (Format-PickerFrameLine -Text 'Dependencies [DependsOn + RequiredBy]' -ForegroundColor White)
                        )

                        foreach ($dependencySection in $dependencyPanelSections)
                        {
                            if ($dependencySection.Direction -eq 'Resolving')
                            {
                                $frameLines += ''
                                foreach ($dependencyLine in $dependencySection.Lines)
                                {
                                    $frameLines += Format-PickerFrameLine -Text $dependencyLine -ForegroundColor DarkGray
                                }

                                continue
                            }

                            $frameLines += ''
                            $frameLines += Format-PickerFrameLine -Text ("Dependencies [$($dependencySection.Direction)]") -ForegroundColor White

                            if (-not [String]::IsNullOrWhiteSpace($dependencySection.Error))
                            {
                                $frameLines += Format-PickerFrameLine -Text ("Dependency lookup failed: $($dependencySection.Error)") -ForegroundColor DarkYellow
                                continue
                            }

                            foreach ($dependencyLine in $dependencySection.Lines)
                            {
                                $frameLines += $dependencyLine
                            }
                        }

                        $frameLines += ''
                        $frameLines += Format-PickerFrameLine -Text 'Press B/Backspace/Delete/LeftArrow to return to the package list.' -ForegroundColor DarkGray
                        Write-PickerFrame -Lines $frameLines

                        if ($null -ne $pendingDependencyPanelPackage)
                        {
                            $terminalEchoState = Disable-PickerTerminalEcho
                            try
                            {
                                $dependencyPanelSections = @(Get-DependencyPanelSections -Package $pendingDependencyPanelPackage)
                            }
                            finally
                            {
                                Restore-PickerTerminalEcho -State $terminalEchoState
                            }

                            $dependencyPanelPackageKey = $currentPackageLookupKey
                            $pendingDependencyPanelPackage = $null
                            Clear-PendingConsoleInput
                            continue
                        }
                    }
                    else
                    {
                        $selectionHint = if ($showPurge)
                        {
                            "Keys: Space select  P purge/zap  Enter remove  D deps  V details  A all  F: [$nameFilterHintValue]"
                        }
                        else
                        {
                            "Keys: Space select  Enter remove  D deps  V details  A all  F: [$nameFilterHintValue]"
                        }
                        $filterSummary = @("filter: $nameFilterHintValue")
                        if ($hasSourceFilter)
                        {
                            $filterSummary += "source: $($availableSources[$sourceFilterIndex])"
                        }
                        $navigationHint = "Nav: ${sourceHint}Home/End/PgUp/PgDn  ?: help  Q/Esc/Ctrl+C cancel"
                        $frameLines = @(
                            (Format-PickerFrameLine -Text "Remove-PlatformPackage - $($allPackages[0].PackageManagerDisplayName)" -ForegroundColor Cyan)
                            (Format-PickerFrameLine -Text (Get-PickerViewportSummary -TopIndex $topIndex -BottomIndex $bottomIndex -VisibleCount $visiblePackages.Count -TotalCount $allPackages.Count -SelectedCount $selectedKeys.Count -FilterText ($filterSummary -join "  $([char]0x00B7)  ")) -ForegroundColor White)
                            ''
                            (Format-PickerFrameLine -Text $selectionHint -ForegroundColor DarkGray)
                            (Format-PickerFrameLine -Text $navigationHint -ForegroundColor DarkGray)
                        )
                        if ($ReturnToPlatformPackageManagerOnBackKey)
                        {
                            $frameLines += Format-PickerFrameLine -Text 'Backspace/Delete: manager menu' -ForegroundColor DarkGray
                        }
                        $frameLines += ''
                        if ($showPurge)
                        {
                            $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4} {5} {6}' -f 'Sel', (Format-PickerCell -Text 'Purge' -Width $purgeWidth), (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Id' -Width $idWidth), (Format-PickerCell -Text 'Ver' -Width $versionWidth), (Format-PickerCell -Text 'Typ' -Width $typeWidth), (Format-PickerCell -Text 'Src' -Width $sourceWidth)) -ForegroundColor DarkGray
                            $frameLines += Format-PickerFrameLine -Text ('- {0} {1} {2} {3} {4} {5} {6}' -f '---', ('-' * $purgeWidth), ('-' * $nameWidth), ('-' * $idWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth)) -ForegroundColor DarkGray
                        }
                        else
                        {
                            $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4} {5}' -f 'Sel', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Id' -Width $idWidth), (Format-PickerCell -Text 'Ver' -Width $versionWidth), (Format-PickerCell -Text 'Typ' -Width $typeWidth), (Format-PickerCell -Text 'Src' -Width $sourceWidth)) -ForegroundColor DarkGray
                            $frameLines += Format-PickerFrameLine -Text ('- {0} {1} {2} {3} {4} {5}' -f '---', ('-' * $nameWidth), ('-' * $idWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth)) -ForegroundColor DarkGray
                        }

                        if ($visiblePackages.Count -eq 0)
                        {
                            $frameLines += ''
                            if ([String]::IsNullOrWhiteSpace($nameFilterText))
                            {
                                $frameLines += Format-PickerFrameLine -Text '  (No packages match this source filter. Press S to cycle.)' -ForegroundColor DarkYellow
                            }
                            else
                            {
                                $emptyKeys = @('F')
                                if ($hasSourceFilter)
                                {
                                    $emptyKeys += 'S'
                                }

                                $frameLines += Format-PickerFrameLine -Text "  (No packages match the active filters. Press $($emptyKeys -join ' or ') to adjust.)" -ForegroundColor DarkYellow
                            }
                            Write-PickerFrame -Lines $frameLines

                            $key = & $KeyReader
                            if (Test-PackagePickerManagerBackKey -KeyInfo $key)
                            {
                                Clear-PickerFrame
                                return @()
                            }

                            if (Test-PackagePickerCancelKey -KeyInfo $key)
                            {
                                Clear-PickerFrame
                                return @()
                            }

                            if (Test-PackagePickerHelpKey -KeyInfo $key)
                            {
                                if (Show-PackagePickerHelp) { Clear-PickerFrame; return @() }
                                continue
                            }

                            if ($hasSourceFilter -and $key.Key -eq [ConsoleKey]::S)
                            {
                                $sourceFilterIndex = ($sourceFilterIndex + 1) % $availableSources.Count
                                $visiblePackages = @(Get-FilteredVisiblePackages -SourceIndex $sourceFilterIndex -NameFilter $nameFilterText)
                                $cursor = 0
                                $topIndex = 0
                            }

                            if ($key.Key -eq [ConsoleKey]::F)
                            {
                                $filterResult = Read-PackageNameFilter -CurrentFilter $nameFilterText
                                if ($filterResult.Applied)
                                {
                                    $nameFilterText = "$($filterResult.Value)"
                                    $visiblePackages = @(Get-FilteredVisiblePackages -SourceIndex $sourceFilterIndex -NameFilter $nameFilterText)
                                    $cursor = 0
                                    $topIndex = 0
                                }
                            }

                            continue
                        }

                        for ($i = $topIndex; $i -le $bottomIndex; $i++)
                        {
                            $package = $visiblePackages[$i]
                            $pkgKey = Get-PackagePickerKey -Package $package
                            $cursorMarker = if ($i -eq $cursor) { '>' } else { ' ' }
                            $selectedMarker = if ($selectedKeys.Contains($pkgKey)) { '[x]' } else { '[ ]' }
                            if ($showPurge)
                            {
                                $purgeMarker = if ($purgeKeys.Contains($pkgKey)) { '[p]' } else { '[ ]' }
                                $packageLine = ('{0} {1} {2} {3} {4} {5} {6} {7}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $purgeMarker -Width $purgeWidth), (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Id -Width $idWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $versionWidth), (Format-PickerCell -Text (Get-PackageTypeDisplay -Type $package.Type) -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                            }
                            else
                            {
                                $packageLine = ('{0} {1} {2} {3} {4} {5} {6}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Id -Width $idWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $versionWidth), (Format-PickerCell -Text (Get-PackageTypeDisplay -Type $package.Type) -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                            }

                            if ($i -eq $cursor)
                            {
                                $frameLines += Format-PickerFrameLine -Text $packageLine -ForegroundColor Cyan
                            }
                            elseif ($selectedKeys.Contains($pkgKey))
                            {
                                $frameLines += Format-PickerFrameLine -Text $packageLine -ForegroundColor Green
                            }
                            else
                            {
                                $frameLines += $packageLine
                            }
                        }

                        $frameLines += ''
                        $currentVersion = if ([String]::IsNullOrWhiteSpace($currentPackage.InstalledVersion)) { 'n/a' } else { $currentPackage.InstalledVersion }
                        $currentSource = if ([String]::IsNullOrWhiteSpace($currentPackage.Source)) { 'n/a' } else { $currentPackage.Source }
                        $currentPublisher = if ([String]::IsNullOrWhiteSpace($currentPackage.Publisher)) { 'n/a' } else { $currentPackage.Publisher }
                        $currentDescription = if (-not [String]::IsNullOrWhiteSpace($currentPackage.Description))
                        {
                            $currentPackage.Description
                        }
                        elseif (-not [String]::IsNullOrWhiteSpace($currentPackage.Notes))
                        {
                            $currentPackage.Notes
                        }
                        elseif ($isCurrentWingetDescriptionPending)
                        {
                            'retrieving description...'
                        }
                        elseif ($currentPackage.PackageManager -eq 'winget' -and -not [String]::IsNullOrWhiteSpace($currentPackageLookupKey))
                        {
                            if ($wingetDescriptionAttempted.ContainsKey($currentPackageLookupKey)) { 'description unavailable' } else { '<press V to load>' }
                        }
                        else
                        {
                            'n/a'
                        }

                        $frameLines += Format-PickerFrameLine -Text ('Current: {0}' -f $currentPackage.Name) -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('Id: {0} | Source: {1} | Publisher: {2}' -f $currentPackage.Id, $currentSource, $currentPublisher) -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('Version: {0}' -f $currentVersion) -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('Description: {0}' -f $currentDescription) -ForegroundColor DarkGray

                        if (-not [String]::IsNullOrWhiteSpace($actionStatus))
                        {
                            $frameLines += ''
                            $frameLines += Format-PickerFrameLine -Text ("Status: $actionStatus") -ForegroundColor $actionStatusColor
                        }

                        if ($showPurge)
                        {
                            $selCount = $selectedKeys.Count
                            $totalCount = $allPackages.Count
                            $countText = if ($hasSourceFilter -and $availableSources[$sourceFilterIndex] -ne 'All')
                            {
                                "$selCount of $totalCount selected  |  $($visiblePackages.Count) of $totalCount visible (filter: $($availableSources[$sourceFilterIndex]))"
                            }
                            else
                            {
                                "$selCount of $totalCount package(s) selected."
                            }
                            $frameLines += ''
                            $frameLines += Format-PickerFrameLine -Text $countText -ForegroundColor White
                        }

                        Write-PickerFrame -Lines $frameLines
                    }

                    if ($isCurrentWingetDescriptionPending)
                    {
                        $wingetDescriptionAttempted[$currentPackageLookupKey] = $true
                        $resolvedDescription = Get-WingetPackageDescription -Manager ([PSCustomObject]@{
                                Name = $currentPackage.PackageManager
                                DisplayName = $currentPackage.PackageManagerDisplayName
                                Command = $currentPackage.PackageManager
                            }) -Package $currentPackage

                        if (-not [String]::IsNullOrWhiteSpace($resolvedDescription))
                        {
                            $currentPackage.Description = $resolvedDescription
                        }

                        $pendingWingetDescriptionLookupKey = ''
                        continue
                    }

                    $key = & $KeyReader
                    if (-not $showDependencyPanel -and (Test-PackagePickerManagerBackKey -KeyInfo $key))
                    {
                        Clear-PickerFrame
                        return @()
                    }

                    if (Test-PackagePickerCancelKey -KeyInfo $key)
                    {
                        Clear-PickerFrame
                        return @()
                    }

                    if (Test-PackagePickerHelpKey -KeyInfo $key)
                    {
                        if (Show-PackagePickerHelp)
                        {
                            Clear-PickerFrame
                            return @()
                        }

                        continue
                    }

                    switch ($key.Key)
                    {
                        'UpArrow'
                        {
                            if ($cursor -gt 0)
                            {
                                $cursor--
                            }
                        }
                        'DownArrow'
                        {
                            if ($cursor -lt ($visiblePackages.Count - 1))
                            {
                                $cursor++
                            }
                        }
                        'PageUp'
                        {
                            $cursor = [Math]::Max(0, $cursor - $pageSize)
                        }
                        'PageDown'
                        {
                            $cursor = [Math]::Min($visiblePackages.Count - 1, $cursor + $pageSize)
                        }
                        'Home'
                        {
                            $cursor = 0
                        }
                        'End'
                        {
                            $cursor = $visiblePackages.Count - 1
                        }
                        'Spacebar'
                        {
                            $pkgKey = Get-PackagePickerKey -Package $visiblePackages[$cursor]
                            if ($selectedKeys.Contains($pkgKey)) { $null = $selectedKeys.Remove($pkgKey) }
                            else { $null = $selectedKeys.Add($pkgKey) }
                        }
                        'A'
                        {
                            $allVisibleSelected = @($visiblePackages | Where-Object { -not $selectedKeys.Contains((Get-PackagePickerKey -Package $_)) }).Count -eq 0
                            if ($allVisibleSelected)
                            {
                                foreach ($vp in $visiblePackages) { $null = $selectedKeys.Remove((Get-PackagePickerKey -Package $vp)) }
                            }
                            else
                            {
                                foreach ($vp in $visiblePackages) { $null = $selectedKeys.Add((Get-PackagePickerKey -Package $vp)) }
                            }
                        }
                        'D'
                        {
                            if (-not $showDependencyPanel)
                            {
                                $showDependencyPanel = $true
                                $dependencyPanelRestoreInPlaceRedraw = $pickerRenderState.UseInPlaceRedraw
                                $pickerRenderState.UseInPlaceRedraw = $false
                                $pickerRenderState.RenderedLineCount = 0
                                $dependencyPanelPackageKey = ''
                                $pendingDependencyPanelPackage = $null
                            }
                        }
                        'B'
                        {
                            if ($showDependencyPanel)
                            {
                                $showDependencyPanel = $false
                                if ($null -ne $dependencyPanelRestoreInPlaceRedraw)
                                {
                                    $pickerRenderState.UseInPlaceRedraw = $dependencyPanelRestoreInPlaceRedraw
                                    $dependencyPanelRestoreInPlaceRedraw = $null
                                    $pickerRenderState.RenderedLineCount = 0
                                    $pendingDependencyPanelPackage = $null
                                }
                            }
                        }
                        'Backspace'
                        {
                            if ($showDependencyPanel)
                            {
                                $showDependencyPanel = $false
                                if ($null -ne $dependencyPanelRestoreInPlaceRedraw)
                                {
                                    $pickerRenderState.UseInPlaceRedraw = $dependencyPanelRestoreInPlaceRedraw
                                    $dependencyPanelRestoreInPlaceRedraw = $null
                                    $pickerRenderState.RenderedLineCount = 0
                                    $pendingDependencyPanelPackage = $null
                                }
                            }
                        }
                        'Delete'
                        {
                            if ($showDependencyPanel)
                            {
                                $showDependencyPanel = $false
                                if ($null -ne $dependencyPanelRestoreInPlaceRedraw)
                                {
                                    $pickerRenderState.UseInPlaceRedraw = $dependencyPanelRestoreInPlaceRedraw
                                    $dependencyPanelRestoreInPlaceRedraw = $null
                                    $pickerRenderState.RenderedLineCount = 0
                                    $pendingDependencyPanelPackage = $null
                                }
                            }
                        }
                        'LeftArrow'
                        {
                            if ($showDependencyPanel)
                            {
                                $showDependencyPanel = $false
                                if ($null -ne $dependencyPanelRestoreInPlaceRedraw)
                                {
                                    $pickerRenderState.UseInPlaceRedraw = $dependencyPanelRestoreInPlaceRedraw
                                    $dependencyPanelRestoreInPlaceRedraw = $null
                                    $pickerRenderState.RenderedLineCount = 0
                                    $pendingDependencyPanelPackage = $null
                                }
                            }
                        }
                        'V'
                        {
                            if ($canResolveCurrentWingetDescription)
                            {
                                $pendingWingetDescriptionLookupKey = $currentPackageLookupKey
                            }
                        }
                        'P'
                        {
                            if ($showPurge)
                            {
                                $pkgKey = Get-PackagePickerKey -Package $visiblePackages[$cursor]
                                if ($purgeKeys.Contains($pkgKey)) { $null = $purgeKeys.Remove($pkgKey) }
                                else { $null = $purgeKeys.Add($pkgKey) }
                            }
                        }
                        'S'
                        {
                            if ($hasSourceFilter)
                            {
                                $sourceFilterIndex = ($sourceFilterIndex + 1) % $availableSources.Count
                                $visiblePackages = @(Get-FilteredVisiblePackages -SourceIndex $sourceFilterIndex -NameFilter $nameFilterText)
                                $cursor = 0
                                $topIndex = 0
                            }
                        }
                        'F'
                        {
                            $filterResult = Read-PackageNameFilter -CurrentFilter $nameFilterText
                            if ($filterResult.Applied)
                            {
                                $nameFilterText = "$($filterResult.Value)"
                                $visiblePackages = @(Get-FilteredVisiblePackages -SourceIndex $sourceFilterIndex -NameFilter $nameFilterText)
                                $cursor = 0
                                $topIndex = 0
                            }
                        }
                        'Enter'
                        {
                            $selectedPackages = @($allPackages | Where-Object { $selectedKeys.Contains((Get-PackagePickerKey -Package $_)) })
                            foreach ($pkg in $selectedPackages)
                            {
                                $pkgKey = Get-PackagePickerKey -Package $pkg
                                $pkg | Add-Member -NotePropertyName 'Purge' -NotePropertyValue ($purgeKeys.Contains($pkgKey)) -Force
                            }

                            if ($selectedPackages.Count -eq 0)
                            {
                                $pkg = $visiblePackages[$cursor]
                                $pkgKey = Get-PackagePickerKey -Package $pkg
                                $pkg | Add-Member -NotePropertyName 'Purge' -NotePropertyValue ($purgeKeys.Contains($pkgKey)) -Force
                                $selectedPackages = @($pkg)
                            }

                            Clear-PickerFrame
                            return $selectedPackages
                        }
                    }
                }
            }
            finally
            {
                if ($restoreTreatControlCAsInput)
                {
                    [Console]::TreatControlCAsInput = $previousTreatControlCAsInput
                }
            }
        }

        function Invoke-PackageRemoval
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [PSCustomObject]$Package
            )

            $versionText = if (-not [String]::IsNullOrWhiteSpace($Package.InstalledVersion)) { " $($Package.InstalledVersion)" } else { '' }

            Write-Host ''
            Write-Host "Removing $($Package.Name)$versionText with $($Manager.DisplayName)..." -ForegroundColor White

            $removeArguments = $Package.RemoveArguments
            $perPackagePurge = $Package.PSObject.Properties['Purge'] -and [Boolean]$Package.Purge
            if ($perPackagePurge -and -not $Purge)
            {
                $removeArguments = Get-PackageRemoveArguments -Manager $Manager -Name $Package.Name -Id $Package.Id -Type $Package.Type -Source $Package.Source -UsePurge
            }
            $requiredByProperties = Get-PackageResultRequiredByProperties -Package $Package

            $invocation = Resolve-PackageManagerInvocation -Manager $Manager -Arguments $removeArguments
            $result = Invoke-PackageManagerCommand -Command $invocation.Command -Arguments $invocation.Arguments -StreamOutput -PreserveConsoleOutput:($Manager.Name -eq 'winget')

            if ($result.ExitCode -eq 0)
            {
                $informationalOutput = @(Get-PackageInformationalOutput -Output $result.Output)
                [PSCustomObject]@{
                    Name = $Package.Name
                    Id = $Package.Id
                    InstalledVersion = $Package.InstalledVersion
                    Status = 'Removed'
                    ExitCode = $result.ExitCode
                    Message = 'Removal completed'
                    CapturedOutput = @($result.Output)
                    InformationalOutput = @($informationalOutput)
                    RequiredByCount = $requiredByProperties.RequiredByCount
                    RequiredByPackages = @($requiredByProperties.RequiredByPackages)
                }
            }
            else
            {
                $message = Get-PackageCommandFailureMessage -Command $invocation.Command -Arguments $invocation.Arguments -ExitCode $result.ExitCode -Output $result.Output

                Write-Warning "Failed to remove $($Package.Name): $message"
                [PSCustomObject]@{
                    Name = $Package.Name
                    Id = $Package.Id
                    InstalledVersion = $Package.InstalledVersion
                    Status = 'Failed'
                    ExitCode = $result.ExitCode
                    Message = $message
                    CapturedOutput = @($result.Output)
                    InformationalOutput = @()
                    RequiredByCount = $requiredByProperties.RequiredByCount
                    RequiredByPackages = @($requiredByProperties.RequiredByPackages)
                }
            }
        }
    }

    process
    {
        $manager = Resolve-PackageManager
        Write-Verbose "Using package manager: $($manager.DisplayName) ($($manager.Command))"

        Write-Host "Checking installed packages with $($manager.DisplayName)..." -ForegroundColor White
        $getPlatformPackageParameters = @{
            PackageManager = $manager.Name
            Name = $IncludePackage
            ExcludePackage = $ExcludePackage
            CommandRunner = $CommandRunner
        }
        if ($manager.Name -eq 'winget' -and -not $NonInteractive)
        {
            $getPlatformPackageParameters.SkipDescriptionEnrichment = $true
        }

        $installedPackages = @(Get-PlatformPackage @getPlatformPackageParameters)

        foreach ($installedPackage in $installedPackages)
        {
            $removeArguments = Get-PackageRemoveArguments -Manager $manager -Name $installedPackage.Name -Id $installedPackage.Id -Type $installedPackage.Type -Source $installedPackage.Source -UsePurge:$Purge.IsPresent
            $installedPackage | Add-Member -NotePropertyName 'RemoveArguments' -NotePropertyValue @($removeArguments) -Force
        }

        if ($NonInteractive)
        {
            return $installedPackages
        }

        if ($installedPackages.Count -eq 0)
        {
            Write-Host 'No installed packages matched the requested filters.' -ForegroundColor White
            return [PSCustomObject]@{
                PackageManager = $manager.Name
                PackageManagerDisplayName = $manager.DisplayName
                TotalMatched = 0
                Selected = 0
                NotSelected = 0
                Removed = 0
                Failed = 0
                Skipped = 0
                Results = @()
            }
        }

        if ($All -and (-not $IncludePackage -or $IncludePackage.Count -eq 0))
        {
            throw 'Refusing to remove every installed package without an include filter. Use -IncludePackage with -All, or omit -All and select packages interactively.'
        }

        $selectedPackages = @(
            if ($All)
            {
                $installedPackages
            }
            else
            {
                Select-PackageInstallRecords -InstalledPackages $installedPackages -KeyReader $KeyReader -PageSize $PickerPageSize -PackageManagerName $manager.Name -SourceFilter $FilterSource -ReturnToPlatformPackageManagerOnBackKey:$ReturnToPlatformPackageManagerOnBackKey
            }
        )

        if ($selectedPackages.Count -eq 0)
        {
            Write-Host 'No packages selected for removal.' -ForegroundColor White
            return [PSCustomObject]@{
                PackageManager = $manager.Name
                PackageManagerDisplayName = $manager.DisplayName
                TotalMatched = $installedPackages.Count
                Selected = 0
                NotSelected = $installedPackages.Count
                Removed = 0
                Failed = 0
                Skipped = 0
                Results = @()
            }
        }

        Add-PackageRequiredByMetadata -Manager $manager -Packages $selectedPackages
        Write-PackageRequiredByWarnings -Packages $selectedPackages

        $results = @()
        foreach ($package in $selectedPackages)
        {
            $displayTarget = if (-not [String]::IsNullOrWhiteSpace($package.Id)) { $package.Id } else { $package.Name }
            $versionText = if (-not [String]::IsNullOrWhiteSpace($package.InstalledVersion)) { " $($package.InstalledVersion)" } else { '' }
            $requiredByProperties = Get-PackageResultRequiredByProperties -Package $package

            if ($PSCmdlet.ShouldProcess("$displayTarget$versionText", "Remove with $($manager.DisplayName)"))
            {
                $results += Invoke-PackageRemoval -Manager $manager -Package $package
            }
            else
            {
                $results += [PSCustomObject]@{
                    Name = $package.Name
                    Id = $package.Id
                    InstalledVersion = $package.InstalledVersion
                    Status = 'Skipped'
                    ExitCode = $null
                    Message = 'Skipped by ShouldProcess'
                    CapturedOutput = @()
                    InformationalOutput = @()
                    RequiredByCount = $requiredByProperties.RequiredByCount
                    RequiredByPackages = @($requiredByProperties.RequiredByPackages)
                }
            }
        }

        $removedCount = @($results | Where-Object { $_.Status -eq 'Removed' }).Count
        $failedCount = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
        $skippedCount = @($results | Where-Object { $_.Status -eq 'Skipped' }).Count
        $notSelectedCount = $installedPackages.Count - $selectedPackages.Count
        $informationalResults = @(
            $results |
            Where-Object { $_.PSObject.Properties['InformationalOutput'] -and @($_.InformationalOutput).Count -gt 0 } |
            ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.Name
                    Id = $_.Id
                    Status = $_.Status
                    Lines = @($_.InformationalOutput)
                }
            }
        )

        [PSCustomObject]@{
            PackageManager = $manager.Name
            PackageManagerDisplayName = $manager.DisplayName
            TotalMatched = $installedPackages.Count
            Selected = $selectedPackages.Count
            NotSelected = $notSelectedCount
            Removed = $removedCount
            Failed = $failedCount
            Skipped = $skippedCount
            InformationalResults = @($informationalResults)
            Results = $results
        }
    }
}

# Create 'Uninstall-Package' alias only if it doesn't already exist
if (-not (Get-Alias -Name 'Uninstall-Package' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'Uninstall-Package' alias for Remove-PlatformPackage"
        Set-Alias -Name 'Uninstall-Package' -Value 'Remove-PlatformPackage' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Remove-PlatformPackage: Could not create 'Uninstall-Package' alias: $($_.Exception.Message)"
    }
}
