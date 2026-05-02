function Install-SystemPackage
{
    <#
    .SYNOPSIS
        Installs packages with the native platform package manager.

    .DESCRIPTION
        Installs packages using the supported native package manager for the current platform.
        You can install packages directly by name or id, pipe normalized results from
        Find-SystemPackage, or start from a search query and select packages in an
        interactive console picker.

        Supported package managers:
        - Windows: winget
        - macOS: brew
        - Debian/Ubuntu Linux: apt
        - Alpine Linux: apk

        Install command output is streamed directly to the console so progress can be
        followed while packages are being installed.

    .PARAMETER Query
        Searches the package registry, opens an interactive picker, and installs the
        packages selected with the spacebar.

    .PARAMETER Name
        Installs one or more packages by name using the detected package manager.

    .PARAMETER Id
        Installs one or more packages by package identifier. This is most useful for
        package managers such as winget that distinguish names from ids.

    .PARAMETER InputObject
        One or more normalized package records, such as objects returned by
        Find-SystemPackage.

    .PARAMETER ExcludePackage
        Optional package names or wildcard patterns to exclude from query results before
        they are shown in the interactive picker.

    .PARAMETER Top
        Maximum number of query results to retrieve before opening the interactive picker.
        Use 0 to return all normalized search results to the picker.

    .PARAMETER NoSudo
        On Linux package managers that normally require elevated privileges, do not
        automatically prefix install commands with sudo.

    .EXAMPLE
        PS > Install-SystemPackage -Query git

        Searches the detected registry for git, opens the interactive picker, and installs
        the selected package or packages.

    .EXAMPLE
        PS > Install-SystemPackage -Name git

        Installs git by name using the detected package manager.

    .EXAMPLE
        PS > Install-SystemPackage -Id Git.Git -PackageManager winget

        Installs a package by winget identifier.

    .EXAMPLE
        PS > Find-SystemPackage -NonInteractive -Query code | Install-SystemPackage

        Pipes search results into Install-SystemPackage and installs the piped records.

    .EXAMPLE
        PS > Find-SystemPackage -NonInteractive -Query code -Top 5 | Where-Object Type -eq 'Cask' | Install-SystemPackage

        Filters search results before installing the selected pipeline records.

    .EXAMPLE
        PS > Install-SystemPackage -Query docker -ExcludePackage '*desktop*'

        Searches for docker packages and excludes Docker Desktop from the interactive list.

    .EXAMPLE
        PS > Install-SystemPackage -Query git -Top 10

        Searches for git and limits the interactive list to 10 normalized results.

    .EXAMPLE
        PS > Install-SystemPackage -Name openssl -NoSudo

        Installs openssl without automatically prefixing the package manager command with sudo.

    .EXAMPLE
        PS > Install-SystemPackage -Name git -WhatIf

        Shows which install commands would run without invoking the package manager.

    .EXAMPLE
        PS > Install-SystemPackage -Query 'visual studio code' -Verbose

        Searches for packages, opens the picker, and writes dependency-loading details to verbose output.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Install-SystemPackage.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Install-SystemPackage.ps1
    #>
    [CmdletBinding(DefaultParameterSetName = 'Query', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Query')]
        [ValidateNotNullOrEmpty()]
        [String]$Query,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Name')]
        [Alias('PackageName')]
        [String[]]$Name,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Id')]
        [String[]]$Id,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')]
        [Object]$InputObject,

        [Parameter(ParameterSetName = 'Query')]
        [Alias('Exclude')]
        [String[]]$ExcludePackage = @(),

        [Parameter(ParameterSetName = 'Query')]
        [ValidateRange(0, 500)]
        [Int32]$Top = 50,

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
        [Int32]$PickerPageSize = 0
    )

    begin
    {
        $pipelinePackages = New-Object 'System.Collections.Generic.List[Object]'

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

        $findSystemPackageDependencyPath = Get-DependencyPathIfNeeded -FunctionName 'Find-SystemPackage' -RelativePath 'Find-SystemPackage.ps1'
        if (-not [String]::IsNullOrWhiteSpace($findSystemPackageDependencyPath))
        {
            try
            {
                . $findSystemPackageDependencyPath
                Write-Verbose "Loaded Find-SystemPackage from: $findSystemPackageDependencyPath"
            }
            catch
            {
                throw "Failed to load required dependency 'Find-SystemPackage' from '$findSystemPackageDependencyPath': $($_.Exception.Message)"
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

            foreach ($propertyName in $PropertyName)
            {
                $property = $InputObject.PSObject.Properties[$propertyName]
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
                        NeedsSudo = $false
                    }
                }
                'brew'
                {
                    [PSCustomObject]@{
                        Name = 'brew'
                        DisplayName = 'Homebrew'
                        Command = 'brew'
                        NeedsSudo = $false
                    }
                }
                'apt'
                {
                    [PSCustomObject]@{
                        Name = 'apt'
                        DisplayName = 'APT'
                        Command = 'apt'
                        NeedsSudo = $true
                    }
                }
                'apk'
                {
                    [PSCustomObject]@{
                        Name = 'apk'
                        DisplayName = 'Alpine Package Keeper'
                        Command = 'apk'
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

        function Resolve-ManagerFromPackages
        {
            param(
                [Parameter()]
                [Object[]]$PackageRecords = @()
            )

            if ($PackageManager.ToLowerInvariant() -ne 'auto')
            {
                return Resolve-PackageManager
            }

            $packageManagers = @(
                $PackageRecords |
                Where-Object { $_ -and $_.PSObject.Properties['PackageManager'] -and -not [String]::IsNullOrWhiteSpace("$($_.PackageManager)") } |
                ForEach-Object { "$($_.PackageManager)".Trim().ToLowerInvariant() } |
                Select-Object -Unique
            )

            if ($packageManagers.Count -gt 1)
            {
                throw 'Install-SystemPackage does not support installing mixed package manager records in a single call.'
            }

            if ($packageManagers.Count -eq 1)
            {
                if (-not (Test-PackageManagerCommandAvailable -Name $packageManagers[0]))
                {
                    throw "Package manager '$($packageManagers[0])' is not installed or not available in PATH."
                }

                return Get-PackageManagerDefinition -Name $packageManagers[0]
            }

            return Resolve-PackageManager
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
                [Switch]$StreamOutput
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

            try
            {
                if ($StreamOutput)
                {
                    & $Command @Arguments
                    return [PSCustomObject]@{
                        ExitCode = if ($null -ne $LASTEXITCODE) { [Int32]$LASTEXITCODE } else { 0 }
                        Output = @()
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

            return [PSCustomObject]@{
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

        function ConvertTo-InstallPackageRecord
        {
            param(
                [Parameter(Mandatory)]
                [Object]$PackageRecord
            )

            $packageName = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $PackageRecord -PropertyName @('Name', 'PackageName'))
            $idValue = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $PackageRecord -PropertyName @('Id', 'PackageIdentifier', 'Identifier'))
            $type = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $PackageRecord -PropertyName @('Type'))
            $version = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $PackageRecord -PropertyName @('Version', 'InstalledVersion'))
            $source = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $PackageRecord -PropertyName @('Source'))
            $description = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $PackageRecord -PropertyName @('Description'))
            $notes = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $PackageRecord -PropertyName @('Notes'))
            $installedValue = Get-FirstPropertyValue -InputObject $PackageRecord -PropertyName @('Installed')
            $installed = $false
            if ($null -ne $installedValue)
            {
                $installed = [Boolean]$installedValue
            }

            if ([String]::IsNullOrWhiteSpace($packageName) -and -not [String]::IsNullOrWhiteSpace($idValue))
            {
                $packageName = $idValue
            }

            if ([String]::IsNullOrWhiteSpace($packageName))
            {
                throw 'Package records must include a Name or Id property.'
            }

            return [PSCustomObject]@{
                Name = $packageName
                Id = $idValue
                Type = $type
                Version = $version
                Source = $source
                Description = $description
                Installed = $installed
                Notes = $notes
            }
        }

        function Get-PackageInstallArguments
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [PSCustomObject]$Package
            )

            switch ($Manager.Name)
            {
                'winget'
                {
                    if (-not [String]::IsNullOrWhiteSpace($Package.Id))
                    {
                        return @('install', '--id', $Package.Id, '--exact', '--accept-source-agreements', '--accept-package-agreements')
                    }

                    return @('install', $Package.Name, '--accept-source-agreements', '--accept-package-agreements')
                }
                'brew'
                {
                    if ($Package.Type -eq 'Cask')
                    {
                        return @('install', '--cask', $Package.Name)
                    }

                    return @('install', $Package.Name)
                }
                'apt'
                {
                    return @('install', '-y', $Package.Name)
                }
                'apk'
                {
                    return @('add', $Package.Name)
                }
                default
                {
                    throw "Unsupported package manager '$($Manager.Name)'."
                }
            }
        }

        function Select-AvailablePackageRecords
        {
            param(
                [Parameter()]
                [PSCustomObject[]]$AvailablePackages = @(),

                [Parameter()]
                [ScriptBlock]$KeyReader,

                [Parameter()]
                [Int32]$PageSize = 0
            )

            if ($AvailablePackages.Count -eq 0)
            {
                return @()
            }

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
                    throw 'Interactive package installation requires an attached console. Use Find-SystemPackage -NonInteractive for object output or install explicit package names or ids in non-interactive sessions.'
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
                        $reservedRows = 10
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

            $nameWidth = [Math]::Min(36, [Math]::Max(4, (($AvailablePackages | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)))
            $versionWidth = [Math]::Min(20, [Math]::Max(7, (($AvailablePackages | ForEach-Object { $_.Version.Length } | Measure-Object -Maximum).Maximum)))
            $typeWidth = [Math]::Min(12, [Math]::Max(4, (($AvailablePackages | ForEach-Object { $_.Type.Length } | Measure-Object -Maximum).Maximum)))
            $sourceWidth = [Math]::Min(18, [Math]::Max(6, (($AvailablePackages | ForEach-Object { $_.Source.Length } | Measure-Object -Maximum).Maximum)))
            $pageSize = Get-PackagePickerPageSize -RequestedPageSize $PageSize -ItemCount $AvailablePackages.Count

            $selected = New-Object 'System.Boolean[]' $AvailablePackages.Count
            $cursor = 0
            $topIndex = 0
            $restoreTreatControlCAsInput = $false
            $previousTreatControlCAsInput = $false
            $pickerRenderState = @{
                UseInPlaceRedraw = $false
                ConsoleBufferWidth = 0
                RenderedLineCount = 0
            }

            function Write-PickerFrame
            {
                param(
                    [Parameter()]
                    [String[]]$Lines = @()
                )

                if (-not $pickerRenderState.UseInPlaceRedraw)
                {
                    Clear-Host
                    foreach ($line in $Lines)
                    {
                        Write-Host $line
                    }

                    return
                }

                $frameWidth = [Math]::Max(1, [Int32]$pickerRenderState.ConsoleBufferWidth)
                $blankLine = ''.PadRight($frameWidth)
                $frameLines = @(
                    foreach ($line in $Lines)
                    {
                        $text = if ($null -eq $line) { '' } else { "$line" }
                        if ($text.Length -ge $frameWidth)
                        {
                            if ($frameWidth -eq 1)
                            {
                                $text.Substring(0, 1)
                            }
                            else
                            {
                                $text.Substring(0, $frameWidth - 1) + '~'
                            }
                        }
                        else
                        {
                            $text.PadRight($frameWidth)
                        }
                    }
                )

                while ($frameLines.Count -lt $pickerRenderState.RenderedLineCount)
                {
                    $frameLines += $blankLine
                }

                try
                {
                    [Console]::SetCursorPosition(0, 0)
                    [Console]::Write(($frameLines -join "`r`n"))
                    $pickerRenderState.RenderedLineCount = $frameLines.Count
                }
                catch
                {
                    $pickerRenderState.UseInPlaceRedraw = $false
                    Clear-Host
                    foreach ($fallbackLine in $Lines)
                    {
                        Write-Host $fallbackLine
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
                        $frameWidth = [Math]::Max(1, [Int32]$pickerRenderState.ConsoleBufferWidth)
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

                    $maxTopIndex = [Math]::Max(0, $AvailablePackages.Count - $pageSize)
                    if ($topIndex -gt $maxTopIndex)
                    {
                        $topIndex = $maxTopIndex
                    }

                    $bottomIndex = [Math]::Min($AvailablePackages.Count - 1, $topIndex + $pageSize - 1)
                    $currentPackage = $AvailablePackages[$cursor]
                    $currentDescription = if ([String]::IsNullOrWhiteSpace($currentPackage.Description)) { 'n/a' } else { $currentPackage.Description }

                    $frameLines = @(
                        "Install-SystemPackage - $($AvailablePackages[0].PackageManagerDisplayName)"
                        'Spacebar: select  Enter: install selected  A: toggle all  Arrow keys/Home/End/PgUp/PgDn: navigate  Ctrl+C/Q/Esc: cancel'
                        ''
                        ('  {0} {1} {2} {3} {4}' -f 'Sel', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Version' -Width $versionWidth), (Format-PickerCell -Text 'Type' -Width $typeWidth), (Format-PickerCell -Text 'Source' -Width $sourceWidth))
                        ('  {0} {1} {2} {3} {4}' -f '---', ('-' * $nameWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth))
                    )

                    for ($i = $topIndex; $i -le $bottomIndex; $i++)
                    {
                        $package = $AvailablePackages[$i]
                        $cursorMarker = if ($i -eq $cursor) { '>' } else { ' ' }
                        $selectedMarker = if ($selected[$i]) { '[x]' } else { '[ ]' }
                        $frameLines += ('{0} {1} {2} {3} {4} {5}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Version -Width $versionWidth), (Format-PickerCell -Text $package.Type -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                    }

                    $frameLines += ''
                    $frameLines += ('Current: {0} | Id: {1} | Installed: {2}' -f $currentPackage.Name, $currentPackage.Id, ($(if ($currentPackage.Installed) { 'yes' } else { 'no' })))
                    $frameLines += ('Description: {0}' -f $currentDescription)
                    $frameLines += "$(@($selected | Where-Object { $_ }).Count) of $($AvailablePackages.Count) package(s) selected."

                    Write-PickerFrame -Lines $frameLines

                    $key = & $KeyReader
                    if (Test-PackagePickerCancelKey -KeyInfo $key)
                    {
                        Clear-PickerFrame
                        return @()
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
                            if ($cursor -lt ($AvailablePackages.Count - 1))
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
                            $cursor = [Math]::Min($AvailablePackages.Count - 1, $cursor + $pageSize)
                        }
                        'Home'
                        {
                            $cursor = 0
                        }
                        'End'
                        {
                            $cursor = $AvailablePackages.Count - 1
                        }
                        'Spacebar'
                        {
                            $selected[$cursor] = -not $selected[$cursor]
                        }
                        'A'
                        {
                            $selectAll = @($selected | Where-Object { -not $_ }).Count -gt 0
                            for ($i = 0; $i -lt $selected.Count; $i++)
                            {
                                $selected[$i] = $selectAll
                            }
                        }
                        'Enter'
                        {
                            Clear-PickerFrame

                            $selectedPackages = @()
                            for ($i = 0; $i -lt $AvailablePackages.Count; $i++)
                            {
                                if ($selected[$i])
                                {
                                    $selectedPackages += $AvailablePackages[$i]
                                }
                            }

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

        function Invoke-PackageInstallation
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [PSCustomObject]$Package
            )

            $versionText = if (-not [String]::IsNullOrWhiteSpace($Package.Version)) { " $($Package.Version)" } else { '' }
            $targetDescription = "$($Package.Name)$versionText"

            if ($Package.Installed)
            {
                return [PSCustomObject]@{
                    Name = $Package.Name
                    Id = $Package.Id
                    Version = $Package.Version
                    Status = 'Skipped'
                    ExitCode = 0
                    Message = 'Package is already installed'
                }
            }

            if (-not $PSCmdlet.ShouldProcess($targetDescription, "Install with $($Manager.DisplayName)"))
            {
                return [PSCustomObject]@{
                    Name = $Package.Name
                    Id = $Package.Id
                    Version = $Package.Version
                    Status = 'Skipped'
                    ExitCode = 0
                    Message = 'Installation skipped by ShouldProcess'
                }
            }

            Write-Host ''
            Write-Host "Installing $targetDescription with $($Manager.DisplayName)..."

            $installArguments = Get-PackageInstallArguments -Manager $Manager -Package $Package
            $invocation = Resolve-PackageManagerInvocation -Manager $Manager -Arguments $installArguments
            $result = Invoke-PackageManagerCommand -Command $invocation.Command -Arguments $invocation.Arguments -StreamOutput

            if ($result.ExitCode -eq 0)
            {
                return [PSCustomObject]@{
                    Name = $Package.Name
                    Id = $Package.Id
                    Version = $Package.Version
                    Status = 'Installed'
                    ExitCode = $result.ExitCode
                    Message = 'Installation completed'
                }
            }

            $message = Get-PackageCommandFailureMessage -Command $invocation.Command -Arguments $invocation.Arguments -ExitCode $result.ExitCode -Output $result.Output
            Write-Warning "Failed to install $($Package.Name): $message"

            return [PSCustomObject]@{
                Name = $Package.Name
                Id = $Package.Id
                Version = $Package.Version
                Status = 'Failed'
                ExitCode = $result.ExitCode
                Message = $message
            }
        }
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject' -and $null -ne $InputObject)
        {
            [void]$pipelinePackages.Add($InputObject)
        }
    }

    end
    {
        $manager = $null
        $candidatePackages = @()
        $selectedPackages = @()
        $totalMatched = 0
        $notSelected = 0

        switch ($PSCmdlet.ParameterSetName)
        {
            'Query'
            {
                $manager = Resolve-PackageManager
                $candidatePackages = @(
                    Find-SystemPackage -NonInteractive -Query $Query -ExcludePackage $ExcludePackage -Top $Top -PackageManager $manager.Name -CommandRunner $CommandRunner
                )
                $totalMatched = $candidatePackages.Count

                if ($candidatePackages.Count -eq 0)
                {
                    Write-Host 'No packages matched the requested query.'
                }
                else
                {
                    $selectedPackages = @(Select-AvailablePackageRecords -AvailablePackages $candidatePackages -KeyReader $KeyReader -PageSize $PickerPageSize)
                    $notSelected = $candidatePackages.Count - $selectedPackages.Count
                    if ($selectedPackages.Count -eq 0)
                    {
                        Write-Host 'No packages selected for installation.'
                    }
                }
            }
            'Name'
            {
                $manager = Resolve-PackageManager
                $selectedPackages = @(
                    foreach ($packageName in @($Name | Where-Object { -not [String]::IsNullOrWhiteSpace($_) }))
                    {
                        [PSCustomObject]@{
                            Name = $packageName.Trim()
                            Id = ''
                            Type = 'Package'
                            Version = ''
                            Source = ''
                            Description = ''
                            Installed = $false
                            Notes = ''
                        }
                    }
                )
                $totalMatched = $selectedPackages.Count
            }
            'Id'
            {
                $manager = Resolve-PackageManager
                $selectedPackages = @(
                    foreach ($packageId in @($Id | Where-Object { -not [String]::IsNullOrWhiteSpace($_) }))
                    {
                        $trimmedId = $packageId.Trim()
                        [PSCustomObject]@{
                            Name = $trimmedId
                            Id = $trimmedId
                            Type = 'Package'
                            Version = ''
                            Source = ''
                            Description = ''
                            Installed = $false
                            Notes = ''
                        }
                    }
                )
                $totalMatched = $selectedPackages.Count
            }
            'InputObject'
            {
                $selectedPackages = @(
                    foreach ($packageRecord in $pipelinePackages)
                    {
                        ConvertTo-InstallPackageRecord -PackageRecord $packageRecord
                    }
                )
                $manager = Resolve-ManagerFromPackages -PackageRecords $pipelinePackages
                $totalMatched = $selectedPackages.Count
            }
        }

        $results = @()
        foreach ($package in $selectedPackages)
        {
            $results += Invoke-PackageInstallation -Manager $manager -Package $package
        }

        $installedCount = @($results | Where-Object { $_.Status -eq 'Installed' }).Count
        $failedCount = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
        $skippedCount = @($results | Where-Object { $_.Status -eq 'Skipped' }).Count

        return [PSCustomObject]@{
            PackageManager = if ($manager) { $manager.Name } else { '' }
            PackageManagerDisplayName = if ($manager) { $manager.DisplayName } else { '' }
            TotalMatched = $totalMatched
            Selected = $selectedPackages.Count
            NotSelected = $notSelected
            Installed = $installedCount
            Failed = $failedCount
            Skipped = $skippedCount
            Results = @($results)
        }
    }
}
