function Upgrade-PlatformPackage
{
    <#
    .SYNOPSIS
        Upgrades outdated packages with the native platform package manager.

    .DESCRIPTION
        Detects the supported package manager for the current platform, refreshes package
        registry metadata, lists packages with available upgrades, and opens an interactive
        console picker where packages can be selected with Space.

        Supported package managers:
        - Windows: winget
        - macOS: brew
        - Debian/Ubuntu Linux: apt
        - Alpine Linux: apk

        Package refresh output is captured where package managers are known to produce
        noisy progress output before the picker starts. Upgrade command output is streamed
        directly to the console so the operation can be followed while it runs. Use
        -NonInteractive to return the discovered package update list without starting the
        interactive picker, or -All to upgrade every discovered package without prompting.

    .PARAMETER IncludePackage
        Optional package names or wildcard patterns to include. Matches package Name or Id.

    .PARAMETER ExcludePackage
        Optional package names or wildcard patterns to exclude. Matches package Name or Id.

    .PARAMETER All
        Upgrades all matching outdated packages without opening the interactive picker.

    .PARAMETER SkipRefresh
        Skips refreshing package registry metadata before checking for upgrades.

    .PARAMETER NonInteractive
        Returns the discovered outdated package records without upgrading anything. The
        previous -AsObject spelling is retained as an alias.

    .PARAMETER FilterSource
        Sets the initial source filter in the interactive picker. When specified, the picker
        opens showing only packages from this source. Press S in the picker to cycle through
        available sources. Only applicable when multiple package sources are present.

    .PARAMETER UninstallPrevious
        When upgrading with winget, passes --uninstall-previous to remove the previously
        installed version before installing the new one. Has no effect on other package
        managers (brew, apt, apk), which replace packages atomically as part of their
        normal upgrade process.

    .PARAMETER NoSudo
        On Linux package managers that normally require elevated privileges, do not
        automatically prefix refresh and upgrade commands with sudo.

    .EXAMPLE
        PS > Upgrade-PlatformPackage

        Refreshes package registry metadata, opens the interactive picker, and upgrades
        the packages selected with Space.

    .EXAMPLE
        PS > Upgrade-PlatformPackage -All

        Refreshes package registry metadata and upgrades all discovered outdated packages.

    .EXAMPLE
        PS > Upgrade-PlatformPackage -IncludePackage 'git*','curl' -ExcludePackage '*preview*'

        Opens the picker for matching git and curl packages except packages whose name or id
        matches '*preview*'.

    .EXAMPLE
        PS > Upgrade-PlatformPackage -NonInteractive -SkipRefresh | Format-Table

        Lists outdated packages from the current package cache without running upgrades.

    .EXAMPLE
        PS > Upgrade-PlatformPackage -All -WhatIf

        Shows the package upgrades that would run without invoking the package manager.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns package records when -NonInteractive is used. Otherwise returns an upgrade
        summary object with package manager, selection counts, NotSelected,
        selected-package skip/failure counts, and per-package results.

    .NOTES
        - winget is used on Windows.
        - brew is used on macOS.
        - apt is used on Debian/Ubuntu-style Linux distributions.
        - apk is used on Alpine Linux.
        - apt and apk operations are prefixed with sudo when needed and available.
        - Query commands are parsed to build the picker; upgrade commands stream their
          native output to the console.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Upgrade-PlatformPackage.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Upgrade-PlatformPackage.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Function name requested by the profile owner.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject], [PSCustomObject[]], [Object[]])]
    param(
        [Parameter()]
        [Alias('Name', 'PackageName', 'Include')]
        [String[]]$IncludePackage = @(),

        [Parameter()]
        [Alias('Exclude')]
        [String[]]$ExcludePackage = @(),

        [Parameter()]
        [Switch]$All,

        [Parameter()]
        [Switch]$SkipRefresh,

        [Parameter()]
        [Alias('AsObject')]
        [Switch]$NonInteractive,

        [Parameter()]
        [String]$FilterSource = '',

        [Parameter()]
        [Switch]$UninstallPrevious,

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
        [Switch]$TreatKeyReaderAsConsoleKeyReader,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$TerminalEchoController,

        [Parameter(DontShow = $true)]
        [ValidateRange(0, 500)]
        [Int32]$PickerPageSize = 0,

        [Parameter(DontShow = $true)]
        [Switch]$ReturnToPlatformPackageManagerOnBackKey
    )

    begin
    {
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

        function Get-PackageUpdateObject
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
                [String]$LatestVersion,

                [Parameter()]
                [String]$Source,

                [Parameter()]
                [String]$Publisher,

                [Parameter()]
                [String]$Description,

                [Parameter()]
                [String]$Notes,

                [Parameter(Mandatory)]
                [String[]]$UpgradeArguments
            )

            [PSCustomObject]@{
                Name = $Name
                Id = $Id
                PackageManager = $Manager.Name
                PackageManagerDisplayName = $Manager.DisplayName
                Type = $Type
                InstalledVersion = $InstalledVersion
                LatestVersion = $LatestVersion
                Source = $Source
                Publisher = if (-not [String]::IsNullOrWhiteSpace($Publisher)) { $Publisher } elseif ($Manager.Name -eq 'brew') { 'Homebrew' } elseif ($Manager.Name -eq 'apk') { 'Alpine' } elseif ($Manager.Name -eq 'apt' -and -not [String]::IsNullOrWhiteSpace($Source)) { $Source } elseif ($Manager.Name -eq 'apt') { 'APT' } elseif ($Manager.Name -eq 'winget' -and -not [String]::IsNullOrWhiteSpace($Source)) { $Source } else { '' }
                Description = if (-not [String]::IsNullOrWhiteSpace($Description)) { $Description } else { $Notes }
                Notes = $Notes
                Command = $Manager.Command
                UpgradeArguments = @($UpgradeArguments)
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
                        RefreshArguments = @('source', 'update')
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
                        RefreshArguments = @('update', '--quiet')
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
                        RefreshArguments = @('update')
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
                        RefreshArguments = @('update')
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

        function Invoke-PackageRegistryRefresh
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            if (-not $Manager.RefreshArguments -or $Manager.RefreshArguments.Count -eq 0)
            {
                return
            }

            Write-Host "Refreshing $($Manager.DisplayName) package metadata..." -ForegroundColor White

            $invocation = Resolve-PackageManagerInvocation -Manager $Manager -Arguments $Manager.RefreshArguments
            $streamOutput = $Manager.Name -in @('apt', 'apk')
            $result = Invoke-PackageManagerCommand -Command $invocation.Command -Arguments $invocation.Arguments -StreamOutput:$streamOutput

            if ($result.ExitCode -ne 0)
            {
                $message = Get-PackageCommandFailureMessage -Command $invocation.Command -Arguments $invocation.Arguments -ExitCode $result.ExitCode -Output $result.Output

                throw "Failed to refresh $($Manager.DisplayName) package metadata: $message"
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

            $updates = @()
            foreach ($package in $candidatePackages)
            {
                if ($null -eq $package)
                {
                    continue
                }

                $name = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Name', 'PackageName'))
                $id = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Id', 'PackageIdentifier', 'Identifier'))
                $installedVersion = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('InstalledVersion', 'Version', 'CurrentVersion'))
                $latestVersion = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('AvailableVersion', 'Available', 'LatestVersion', 'NewVersion'))
                $source = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Source', 'SourceName'))
                $description = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Description', 'ShortDescription', 'Summary', 'PackageDescription'))

                if ([String]::IsNullOrWhiteSpace($name) -or [String]::IsNullOrWhiteSpace($latestVersion))
                {
                    continue
                }

                $sourceArguments = if (-not [String]::IsNullOrWhiteSpace($source))
                {
                    @('--source', $source)
                }
                else
                {
                    @()
                }

                $upgradeArguments = if (-not [String]::IsNullOrWhiteSpace($id))
                {
                    @('upgrade', '--id', $id, '--exact') + $sourceArguments + @('--accept-package-agreements', '--accept-source-agreements')
                }
                else
                {
                    @('upgrade', $name) + $sourceArguments + @('--accept-package-agreements', '--accept-source-agreements')
                }

                $updates += Get-PackageUpdateObject -Manager $Manager -Name $name -Id $id -Type 'Package' -InstalledVersion $installedVersion -LatestVersion $latestVersion -Source $source -Description $description -UpgradeArguments $upgradeArguments
            }

            return $updates
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
                if ($lines[$i] -match 'Name\s+Id\s+Version\s+Available')
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
            $availableStart = $header.IndexOf('Available')
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

            $updates = @()
            for ($i = $headerIndex + 1; $i -lt $lines.Count; $i++)
            {
                $line = $lines[$i]
                if ([String]::IsNullOrWhiteSpace($line) -or $line -match '^-{3,}' -or $line -match '^\d+\s+upgrades?\s+available' -or $line -match '^\d+\s+package\(s\)\s+have version numbers that cannot be determined\.')
                {
                    continue
                }

                $name = Get-WingetTableCell -Line $line -Start $nameStart -End $idStart
                $id = Get-WingetTableCell -Line $line -Start $idStart -End $versionStart
                $installedVersion = Get-WingetTableCell -Line $line -Start $versionStart -End $availableStart
                $latestVersion = if ($sourceStart -ge 0)
                {
                    Get-WingetTableCell -Line $line -Start $availableStart -End $sourceStart
                }
                else
                {
                    Get-WingetTableCell -Line $line -Start $availableStart
                }
                $source = if ($sourceStart -ge 0) { Get-WingetTableCell -Line $line -Start $sourceStart } else { '' }

                if ([String]::IsNullOrWhiteSpace($name) -or [String]::IsNullOrWhiteSpace($latestVersion))
                {
                    continue
                }

                $sourceArguments = if (-not [String]::IsNullOrWhiteSpace($source))
                {
                    @('--source', $source)
                }
                else
                {
                    @()
                }

                $upgradeArguments = if (-not [String]::IsNullOrWhiteSpace($id))
                {
                    @('upgrade', '--id', $id, '--exact') + $sourceArguments + @('--accept-package-agreements', '--accept-source-agreements')
                }
                else
                {
                    @('upgrade', $name) + $sourceArguments + @('--accept-package-agreements', '--accept-source-agreements')
                }

                $updates += Get-PackageUpdateObject -Manager $Manager -Name $name -Id $id -Type 'Package' -InstalledVersion $installedVersion -LatestVersion $latestVersion -Source $source -UpgradeArguments $upgradeArguments
            }

            return $updates
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

        function Get-WingetPackageUpdates
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter()]
                [Switch]$SkipDescriptionEnrichment
            )

            $jsonResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('upgrade', '--accept-source-agreements', '--output', 'json')
            if ($jsonResult.ExitCode -eq 0)
            {
                $jsonUpdates = @(ConvertFrom-WingetJsonOutput -Manager $Manager -Output $jsonResult.Output)
                if ($jsonUpdates.Count -gt 0)
                {
                    if ($SkipDescriptionEnrichment)
                    {
                        return $jsonUpdates
                    }

                    return @(Resolve-WingetPackageDescriptions -Manager $Manager -Packages $jsonUpdates)
                }

                if (-not (($jsonResult.Output -join "`n") -match 'Name\s+Id\s+Version\s+Available'))
                {
                    return @()
                }
            }

            $tableResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('upgrade', '--accept-source-agreements')
            if ($tableResult.ExitCode -ne 0)
            {
                $message = ($tableResult.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to query winget upgrades: $message"
            }

            $tableUpdates = @(ConvertFrom-WingetTableOutput -Manager $Manager -Output $tableResult.Output)
            if ($SkipDescriptionEnrichment)
            {
                return $tableUpdates
            }

            return @(Resolve-WingetPackageDescriptions -Manager $Manager -Packages $tableUpdates)
        }

        function Get-BrewPackageUpdates
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('outdated', '--json=v2', '--greedy')
            if ($result.ExitCode -ne 0)
            {
                $message = ($result.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to query Homebrew upgrades: $message"
            }

            $lines = @($result.Output | ForEach-Object { "$($_)" })
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
                $data = $jsonText | ConvertFrom-Json
            }
            catch
            {
                throw "Failed to parse Homebrew outdated JSON output: $($_.Exception.Message)"
            }

            $updates = @()
            foreach ($formula in @($data.formulae))
            {
                if ($null -eq $formula)
                {
                    continue
                }

                $name = ConvertTo-PackageText -Value $formula.name
                if ([String]::IsNullOrWhiteSpace($name))
                {
                    continue
                }

                $notes = if ($formula.PSObject.Properties['pinned'] -and $formula.pinned) { 'Pinned' } else { '' }
                $description = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $formula -PropertyName @('desc', 'description', 'summary'))
                $updates += Get-PackageUpdateObject -Manager $Manager -Name $name -Id $name -Type 'Formula' -InstalledVersion (ConvertTo-PackageText -Value $formula.installed_versions) -LatestVersion (ConvertTo-PackageText -Value $formula.current_version) -Source 'homebrew/core' -Description $description -Notes $notes -UpgradeArguments @('upgrade', $name)
            }

            foreach ($cask in @($data.casks))
            {
                if ($null -eq $cask)
                {
                    continue
                }

                $name = ConvertTo-PackageText -Value $cask.name
                if ([String]::IsNullOrWhiteSpace($name))
                {
                    continue
                }

                $notes = if ($cask.PSObject.Properties['auto_updates'] -and $cask.auto_updates) { 'Auto-updates' } else { '' }
                $description = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $cask -PropertyName @('desc', 'description', 'summary'))
                $updates += Get-PackageUpdateObject -Manager $Manager -Name $name -Id $name -Type 'Cask' -InstalledVersion (ConvertTo-PackageText -Value $cask.installed_versions) -LatestVersion (ConvertTo-PackageText -Value $cask.current_version) -Source 'homebrew/cask' -Description $description -Notes $notes -UpgradeArguments @('upgrade', '--cask', $name)
            }

            if ($CommandRunner)
            {
                return $updates
            }

            $formulaNames = @($updates |
                Where-Object {
                    $_.Type -eq 'Formula' -and
                    -not [String]::IsNullOrWhiteSpace($_.Name) -and
                    [String]::IsNullOrWhiteSpace($_.Description)
                } |
                ForEach-Object { $_.Name } |
                Select-Object -Unique)

            $caskNames = @($updates |
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

            foreach ($update in $updates)
            {
                if (-not [String]::IsNullOrWhiteSpace($update.Description))
                {
                    continue
                }

                if ([String]::IsNullOrWhiteSpace($update.Name))
                {
                    continue
                }

                $key = $update.Name.Trim().ToLowerInvariant()
                if ($descriptionLookup.ContainsKey($key))
                {
                    $update.Description = $descriptionLookup[$key]
                }
            }

            return $updates
        }

        function Get-AptPackageUpdates
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('list', '--upgradable')
            if ($result.ExitCode -ne 0)
            {
                $message = ($result.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to query APT upgrades: $message"
            }

            $updates = @()
            foreach ($line in @($result.Output | ForEach-Object { "$_" }))
            {
                $trimmedLine = $line.Trim()
                if ([String]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine -match '^Listing' -or $trimmedLine -match '^WARNING:' -or $trimmedLine -match '^N:')
                {
                    continue
                }

                if ($trimmedLine -match '^(?<Name>[^/\s]+)/(?<Repository>\S+)\s+(?<Latest>\S+)\s+(?<Architecture>\S+)\s+\[upgradable from:\s+(?<Installed>[^\]]+)\]')
                {
                    $name = $Matches.Name
                    $updates += Get-PackageUpdateObject -Manager $Manager -Name $name -Id $name -Type $Matches.Architecture -InstalledVersion $Matches.Installed -LatestVersion $Matches.Latest -Source $Matches.Repository -UpgradeArguments @('install', '--only-upgrade', '-y', $name)
                }
            }

            return $updates
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

        function Get-ApkPackageUpdates
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('version', '-l', '<')
            if ($result.ExitCode -ne 0)
            {
                $message = ($result.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to query apk upgrades: $message"
            }

            $updates = @()
            foreach ($line in @($result.Output | ForEach-Object { "$_" }))
            {
                $trimmedLine = $line.Trim()
                if ([String]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine -match '^WARNING:')
                {
                    continue
                }

                if ($trimmedLine -match '^(?<InstalledToken>\S+)\s+<\s+(?<Latest>\S+)')
                {
                    $packageInfo = Split-ApkPackageVersion -InstalledToken $Matches.InstalledToken
                    if ([String]::IsNullOrWhiteSpace($packageInfo.Name))
                    {
                        continue
                    }

                    $updates += Get-PackageUpdateObject -Manager $Manager -Name $packageInfo.Name -Id $packageInfo.Name -Type 'Package' -InstalledVersion $packageInfo.Version -LatestVersion $Matches.Latest -Source 'apk' -UpgradeArguments @('add', '--upgrade', $packageInfo.Name)
                }
            }

            return $updates
        }

        function Get-PackageUpdates
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter()]
                [Switch]$SkipDescriptionEnrichment
            )

            switch ($Manager.Name)
            {
                'winget' { Get-WingetPackageUpdates -Manager $Manager -SkipDescriptionEnrichment:$SkipDescriptionEnrichment.IsPresent }
                'brew' { Get-BrewPackageUpdates -Manager $Manager }
                'apt' { Get-AptPackageUpdates -Manager $Manager }
                'apk' { Get-ApkPackageUpdates -Manager $Manager }
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

        function Select-PackageUpdateRecords
        {
            param(
                [Parameter()]
                [PSCustomObject[]]$PackageUpdates = @(),

                [Parameter()]
                [ScriptBlock]$KeyReader,

                [Parameter()]
                [Int32]$PageSize = 0,

                [Parameter()]
                [String]$PackageManagerName = '',

                [Parameter()]
                [String]$SourceFilter = '',

                [Parameter()]
                [Switch]$TreatKeyReaderAsConsoleKeyReader,

                [Parameter()]
                [ScriptBlock]$TerminalEchoController,

                [Parameter()]
                [Switch]$ReturnToPlatformPackageManagerOnBackKey
            )

            if ($PackageUpdates.Count -eq 0)
            {
                return @()
            }

            $allPackages = $PackageUpdates
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
                        Write-Host 'Filter upgradable packages' -ForegroundColor Cyan
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
            $usePickerTerminalEchoControl = $false
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
                $usePickerTerminalEchoControl = $true
            }
            elseif ($TreatKeyReaderAsConsoleKeyReader)
            {
                $usePickerTerminalEchoControl = $true
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
                        $reservedRows = 16
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
                    [Switch]$IncludesUninstallPrevious
                )

                $prefixWidth = if ($IncludesUninstallPrevious) { 10 } else { 6 }
                return $prefixWidth + [Int32]$ColumnWidths.Name + 1 + [Int32]$ColumnWidths.Id + 1 + [Int32]$ColumnWidths.Installed + 1 + [Int32]$ColumnWidths.Latest + 1 + [Int32]$ColumnWidths.Type + 1 + [Int32]$ColumnWidths.Source
            }

            function Compress-PackagePickerTableWidths
            {
                param(
                    [Parameter(Mandatory)]
                    [PSCustomObject]$ColumnWidths,

                    [Parameter(Mandatory)]
                    [Int32]$MaximumWidth,

                    [Parameter()]
                    [Switch]$IncludesUninstallPrevious
                )

                $minimumWidths = @{
                    Name = 12
                    Id = 14
                    Installed = 8
                    Latest = 8
                    Type = 3
                    Source = 5
                }
                $shrinkOrder = @('Id', 'Name', 'Installed', 'Latest', 'Source', 'Type')

                while ((Get-PackagePickerTableLineWidth -ColumnWidths $ColumnWidths -IncludesUninstallPrevious:$IncludesUninstallPrevious.IsPresent) -gt $MaximumWidth)
                {
                    $shrunk = $false
                    foreach ($columnName in $shrinkOrder)
                    {
                        if ([Int32]$ColumnWidths.$columnName -gt [Int32]$minimumWidths[$columnName])
                        {
                            $ColumnWidths.$columnName = [Int32]$ColumnWidths.$columnName - 1
                            $shrunk = $true
                            if ((Get-PackagePickerTableLineWidth -ColumnWidths $ColumnWidths -IncludesUninstallPrevious:$IncludesUninstallPrevious.IsPresent) -le $MaximumWidth)
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

            $showUninstallPrevious = $PackageManagerName -eq 'winget'
            $pickerFrameWidth = Get-PackagePickerFrameWidth
            $columnWidths = [PSCustomObject]@{
                Name = Get-PackagePickerTextMaximum -Values @($allPackages | ForEach-Object { $_.Name }) -Minimum 12 -Maximum 30
                Id = Get-PackagePickerTextMaximum -Values @($allPackages | ForEach-Object { $_.Id }) -Minimum 14 -Maximum 32
                Installed = Get-PackagePickerTextMaximum -Values @($allPackages | ForEach-Object { $_.InstalledVersion }) -Minimum 8 -Maximum 16
                Latest = Get-PackagePickerTextMaximum -Values @($allPackages | ForEach-Object { $_.LatestVersion }) -Minimum 8 -Maximum 16
                Type = Get-PackagePickerTextMaximum -Values @($allPackages | ForEach-Object { Get-PackageTypeDisplay -Type $_.Type }) -Minimum 3 -Maximum 7
                Source = Get-PackagePickerTextMaximum -Values @($allPackages | ForEach-Object { $_.Source }) -Minimum 5 -Maximum 32
            }
            $columnWidths = Compress-PackagePickerTableWidths -ColumnWidths $columnWidths -MaximumWidth $pickerFrameWidth -IncludesUninstallPrevious:$showUninstallPrevious
            $nameWidth = [Int32]$columnWidths.Name
            $idWidth = [Int32]$columnWidths.Id
            $installedWidth = [Int32]$columnWidths.Installed
            $latestWidth = [Int32]$columnWidths.Latest
            $typeWidth = [Int32]$columnWidths.Type
            $sourceWidth = [Int32]$columnWidths.Source
            $pageSize = Get-PackagePickerPageSize -RequestedPageSize $PageSize -ItemCount $allPackages.Count

            $selectedKeys = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $uninstallPreviousKeys = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $wingetDescriptionAttempted = @{}
            $pendingWingetDescriptionLookupKey = ''
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
                    $originalForegroundColor = [Console]::ForegroundColor
                    try
                    {
                        [Console]::SetCursorPosition(0, 0)
                        for ($lineIndex = 0; $lineIndex -lt $frameLines.Count; $lineIndex++)
                        {
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

                            if ($lineIndex -lt ($frameLines.Count - 1))
                            {
                                [Console]::Write("`r`n")
                            }
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
                if (-not $usePickerTerminalEchoControl)
                {
                    return $null
                }

                $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { [Bool]$IsWindows }
                if ($isWindowsPlatform)
                {
                    return $null
                }

                if ($TerminalEchoController)
                {
                    try
                    {
                        return (& $TerminalEchoController -Action 'Disable')
                    }
                    catch
                    {
                        Write-Verbose "Unable to disable terminal echo: $($_.Exception.Message)"
                        return $null
                    }
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

                if ($TerminalEchoController)
                {
                    try
                    {
                        $null = & $TerminalEchoController -Action 'Restore' -State $State
                    }
                    catch
                    {
                        Write-Verbose "Unable to restore terminal echo: $($_.Exception.Message)"
                    }

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
                Write-Host 'Upgrade-PlatformPackage Help' -ForegroundColor Cyan
                Write-Host ''
                Write-Host 'Navigation' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'Up/Down' -Description 'move one package'
                Write-PackagePickerHelpItem -Shortcut 'PageUp/PageDown' -Description 'move one page'
                Write-PackagePickerHelpItem -Shortcut 'Home/End' -Description 'move to the first or last package'

                Write-Host ''
                Write-Host 'Selection' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'Space' -Description 'select or clear the current package'
                Write-PackagePickerHelpItem -Shortcut 'A' -Description 'select or clear all visible packages'
                Write-PackagePickerHelpItem -Shortcut 'Enter' -Description 'upgrade selected packages'

                if ($showUninstallPrevious)
                {
                    Write-PackagePickerHelpItem -Shortcut 'U' -Description 'toggle winget --uninstall-previous for the current package'
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
                Write-PackagePickerHelpItem -Shortcut 'V' -Description 'load a missing winget description when available'
                Write-PackagePickerHelpItem -Shortcut 'Q, Esc, or Ctrl+C' -Description 'cancel upgrades'
                Write-PackagePickerHelpItem -Shortcut '?' -Description 'show this help'

                Write-Host ''
                Write-Host 'Press any key to return to the picker. Q/Esc/Ctrl+C cancels.' -ForegroundColor DarkGray

                $helpKey = & $KeyReader
                Clear-Host
                $pickerRenderState.UseInPlaceRedraw = $restoreInPlaceRedraw
                $pickerRenderState.RenderedLineCount = 0
                return (Test-PackagePickerCancelKey -KeyInfo $helpKey)
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
                    $selectionHint = if ($showUninstallPrevious)
                    {
                        "Keys: Space select  U uninstall previous  Enter upgrade  V details  A toggle all  F: [$nameFilterHintValue]"
                    }
                    else
                    {
                        "Keys: Space select  Enter upgrade  V details  A toggle all  F: [$nameFilterHintValue]"
                    }
                    $filterSummary = @()
                    if (-not [String]::IsNullOrWhiteSpace($nameFilterText))
                    {
                        $filterSummary += "filter: $nameFilterHintValue"
                    }
                    if ($hasSourceFilter)
                    {
                        $filterSummary += "source: $($availableSources[$sourceFilterIndex])"
                    }
                    $navigationHint = "Nav: ${sourceHint}Home/End/PgUp/PgDn  ?: help  Q/Esc/Ctrl+C cancel"
                    $frameLines = @(
                        (Format-PickerFrameLine -Text "Upgrade-PlatformPackage - $($allPackages[0].PackageManagerDisplayName)" -ForegroundColor Cyan)
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
                    if ($visiblePackages.Count -eq 0)
                    {
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
                            if (Show-PackagePickerHelp)
                            {
                                Clear-PickerFrame
                                return @()
                            }

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

                    if ($showUninstallPrevious)
                    {
                        $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4} {5} {6} {7}' -f 'Sel', 'Unp', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Id' -Width $idWidth), (Format-PickerCell -Text 'Inst' -Width $installedWidth), (Format-PickerCell -Text 'Avail' -Width $latestWidth), (Format-PickerCell -Text 'Typ' -Width $typeWidth), (Format-PickerCell -Text 'Src' -Width $sourceWidth)) -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('- {0} {1} {2} {3} {4} {5} {6} {7}' -f '---', '---', ('-' * $nameWidth), ('-' * $idWidth), ('-' * $installedWidth), ('-' * $latestWidth), ('-' * $typeWidth), ('-' * $sourceWidth)) -ForegroundColor DarkGray
                    }
                    else
                    {
                        $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4} {5} {6}' -f 'Sel', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Id' -Width $idWidth), (Format-PickerCell -Text 'Inst' -Width $installedWidth), (Format-PickerCell -Text 'Avail' -Width $latestWidth), (Format-PickerCell -Text 'Typ' -Width $typeWidth), (Format-PickerCell -Text 'Src' -Width $sourceWidth)) -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('- {0} {1} {2} {3} {4} {5} {6}' -f '---', ('-' * $nameWidth), ('-' * $idWidth), ('-' * $installedWidth), ('-' * $latestWidth), ('-' * $typeWidth), ('-' * $sourceWidth)) -ForegroundColor DarkGray
                    }

                    for ($i = $topIndex; $i -le $bottomIndex; $i++)
                    {
                        $package = $visiblePackages[$i]
                        $pkgKey = Get-PackagePickerKey -Package $package
                        $cursorMarker = if ($i -eq $cursor) { '>' } else { ' ' }
                        $selectedMarker = if ($selectedKeys.Contains($pkgKey)) { '[x]' } else { '[ ]' }
                        if ($showUninstallPrevious)
                        {
                            $uninstallMarker = if ($uninstallPreviousKeys.Contains($pkgKey)) { '[u]' } else { '[ ]' }
                            $packageLine = ('{0} {1} {2} {3} {4} {5} {6} {7} {8}' -f $cursorMarker, $selectedMarker, $uninstallMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Id -Width $idWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $installedWidth), (Format-PickerCell -Text $package.LatestVersion -Width $latestWidth), (Format-PickerCell -Text (Get-PackageTypeDisplay -Type $package.Type) -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                        }
                        else
                        {
                            $packageLine = ('{0} {1} {2} {3} {4} {5} {6} {7}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Id -Width $idWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $installedWidth), (Format-PickerCell -Text $package.LatestVersion -Width $latestWidth), (Format-PickerCell -Text (Get-PackageTypeDisplay -Type $package.Type) -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                        }

                        if ($i -eq $cursor -and $selectedKeys.Contains($pkgKey))
                        {
                            $frameLines += Format-PickerFrameLine -Text $packageLine -ForegroundColor Green
                        }
                        elseif ($i -eq $cursor)
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
                    $currentInstalledVersion = if ([String]::IsNullOrWhiteSpace($currentPackage.InstalledVersion)) { 'n/a' } else { $currentPackage.InstalledVersion }
                    $currentLatestVersion = if ([String]::IsNullOrWhiteSpace($currentPackage.LatestVersion)) { 'n/a' } else { $currentPackage.LatestVersion }
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
                    $frameLines += Format-PickerFrameLine -Text ('Version: {0} -> {1}' -f $currentInstalledVersion, $currentLatestVersion) -ForegroundColor DarkGray
                    $frameLines += Format-PickerFrameLine -Text ('Description: {0}' -f $currentDescription) -ForegroundColor DarkGray
                    $frameLines += ''
                    $countText = if ($hasSourceFilter -and $availableSources[$sourceFilterIndex] -ne 'All')
                    {
                        "$($selectedKeys.Count) of $($allPackages.Count) selected  |  $($visiblePackages.Count) of $($allPackages.Count) visible (filter: $($availableSources[$sourceFilterIndex]))"
                    }
                    else
                    {
                        "$($selectedKeys.Count) of $($allPackages.Count) package(s) selected."
                    }
                    $frameLines += $countText

                    Write-PickerFrame -Lines $frameLines

                    if ($isCurrentWingetDescriptionPending)
                    {
                        $wingetDescriptionAttempted[$currentPackageLookupKey] = $true
                        $terminalEchoState = Disable-PickerTerminalEcho
                        try
                        {
                            $resolvedDescription = Get-WingetPackageDescription -Manager ([PSCustomObject]@{
                                Name = $currentPackage.PackageManager
                                DisplayName = $currentPackage.PackageManagerDisplayName
                                Command = $currentPackage.PackageManager
                            }) -Package $currentPackage
                        }
                        finally
                        {
                            Restore-PickerTerminalEcho -State $terminalEchoState
                        }

                        if (-not [String]::IsNullOrWhiteSpace($resolvedDescription))
                        {
                            $currentPackage.Description = $resolvedDescription
                        }

                        $pendingWingetDescriptionLookupKey = ''
                        Clear-PendingConsoleInput
                        continue
                    }

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
                            if ($selectedKeys.Contains($pkgKey)) { [void]$selectedKeys.Remove($pkgKey) } else { [void]$selectedKeys.Add($pkgKey) }
                        }
                        'A'
                        {
                            $allVisibleSelected = @($visiblePackages | Where-Object { $selectedKeys.Contains((Get-PackagePickerKey -Package $_)) }).Count -eq $visiblePackages.Count
                            foreach ($pkg in $visiblePackages)
                            {
                                $pkgKey = Get-PackagePickerKey -Package $pkg
                                if ($allVisibleSelected) { [void]$selectedKeys.Remove($pkgKey) } else { [void]$selectedKeys.Add($pkgKey) }
                            }
                        }
                        'V'
                        {
                            if ($canResolveCurrentWingetDescription)
                            {
                                $pendingWingetDescriptionLookupKey = $currentPackageLookupKey
                            }
                        }
                        'U'
                        {
                            if ($showUninstallPrevious)
                            {
                                $pkgKey = Get-PackagePickerKey -Package $visiblePackages[$cursor]
                                if ($uninstallPreviousKeys.Contains($pkgKey)) { [void]$uninstallPreviousKeys.Remove($pkgKey) } else { [void]$uninstallPreviousKeys.Add($pkgKey) }
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
                                $pkg | Add-Member -NotePropertyName 'UninstallPrevious' -NotePropertyValue ($uninstallPreviousKeys.Contains($pkgKey)) -Force
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

        function Invoke-PackageUpgrade
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [PSCustomObject]$Package
            )

            $versionText = "$($Package.InstalledVersion) -> $($Package.LatestVersion)"

            Write-Host ''
            Write-Host "Upgrading $($Package.Name) ($versionText) with $($Manager.DisplayName)..." -ForegroundColor White

            $upgradeArguments = $Package.UpgradeArguments
            $perPackageUninstall = $Package.PSObject.Properties['UninstallPrevious'] -and [Boolean]$Package.UninstallPrevious
            if (($UninstallPrevious -or $perPackageUninstall) -and $Manager.Name -eq 'winget')
            {
                $upgradeArguments = @($upgradeArguments) + @('--uninstall-previous')
            }

            $invocation = Resolve-PackageManagerInvocation -Manager $Manager -Arguments $upgradeArguments
            $result = Invoke-PackageManagerCommand -Command $invocation.Command -Arguments $invocation.Arguments -StreamOutput -PreserveConsoleOutput:($Manager.Name -eq 'winget')

            if ($result.ExitCode -eq 0)
            {
                $informationalOutput = @(Get-PackageInformationalOutput -Output $result.Output)
                [PSCustomObject]@{
                    Name = $Package.Name
                    Id = $Package.Id
                    InstalledVersion = $Package.InstalledVersion
                    LatestVersion = $Package.LatestVersion
                    Status = 'Upgraded'
                    ExitCode = $result.ExitCode
                    Message = 'Upgrade completed'
                    CapturedOutput = @($result.Output)
                    InformationalOutput = @($informationalOutput)
                }
            }
            else
            {
                $message = Get-PackageCommandFailureMessage -Command $invocation.Command -Arguments $invocation.Arguments -ExitCode $result.ExitCode -Output $result.Output

                Write-Warning "Failed to upgrade $($Package.Name): $message"
                [PSCustomObject]@{
                    Name = $Package.Name
                    Id = $Package.Id
                    InstalledVersion = $Package.InstalledVersion
                    LatestVersion = $Package.LatestVersion
                    Status = 'Failed'
                    ExitCode = $result.ExitCode
                    Message = $message
                    CapturedOutput = @($result.Output)
                    InformationalOutput = @($message)
                }
            }
        }
    }

    process
    {
        $manager = Resolve-PackageManager
        Write-Verbose "Using package manager: $($manager.DisplayName) ($($manager.Command))"

        if (-not $SkipRefresh -and $PSCmdlet.ShouldProcess($manager.DisplayName, 'Refresh package metadata'))
        {
            Invoke-PackageRegistryRefresh -Manager $manager
        }

        Write-Host "Checking for available upgrades with $($manager.DisplayName)..." -ForegroundColor White
        $packageUpdates = @(Get-PackageUpdates -Manager $manager -SkipDescriptionEnrichment:($manager.Name -eq 'winget' -and -not $NonInteractive))

        if ($IncludePackage -and $IncludePackage.Count -gt 0)
        {
            $packageUpdates = @($packageUpdates | Where-Object { Test-PackagePatternMatch -Package $_ -Pattern $IncludePackage })
        }

        if ($ExcludePackage -and $ExcludePackage.Count -gt 0)
        {
            $packageUpdates = @($packageUpdates | Where-Object { -not (Test-PackagePatternMatch -Package $_ -Pattern $ExcludePackage) })
        }

        $packageUpdates = @($packageUpdates | Sort-Object -Property Name, Id)

        if ($NonInteractive)
        {
            return $packageUpdates
        }

        if ($packageUpdates.Count -eq 0)
        {
            Write-Host 'No package upgrades are available.' -ForegroundColor White
            return [PSCustomObject]@{
                PackageManager = $manager.Name
                PackageManagerDisplayName = $manager.DisplayName
                TotalAvailable = 0
                Selected = 0
                NotSelected = 0
                Upgraded = 0
                Failed = 0
                Skipped = 0
                Results = @()
            }
        }

        $selectedPackages = @(
            if ($All)
            {
                $packageUpdates
            }
            else
            {
                Select-PackageUpdateRecords -PackageUpdates $packageUpdates -KeyReader $KeyReader -PageSize $PickerPageSize -PackageManagerName $manager.Name -SourceFilter $FilterSource -TreatKeyReaderAsConsoleKeyReader:$TreatKeyReaderAsConsoleKeyReader -TerminalEchoController $TerminalEchoController -ReturnToPlatformPackageManagerOnBackKey:$ReturnToPlatformPackageManagerOnBackKey
            }
        )

        if ($selectedPackages.Count -eq 0)
        {
            Write-Host 'No packages selected for upgrade.' -ForegroundColor White
            return [PSCustomObject]@{
                PackageManager = $manager.Name
                PackageManagerDisplayName = $manager.DisplayName
                TotalAvailable = $packageUpdates.Count
                Selected = 0
                NotSelected = $packageUpdates.Count
                Upgraded = 0
                Failed = 0
                Skipped = 0
                Results = @()
            }
        }

        $results = @()
        foreach ($package in $selectedPackages)
        {
            $displayTarget = if (-not [String]::IsNullOrWhiteSpace($package.Id)) { $package.Id } else { $package.Name }
            $versionText = "$($package.InstalledVersion) -> $($package.LatestVersion)"

            if ($PSCmdlet.ShouldProcess("$displayTarget ($versionText)", "Upgrade with $($manager.DisplayName)"))
            {
                $results += Invoke-PackageUpgrade -Manager $manager -Package $package
            }
            else
            {
                $results += [PSCustomObject]@{
                    Name = $package.Name
                    Id = $package.Id
                    InstalledVersion = $package.InstalledVersion
                    LatestVersion = $package.LatestVersion
                    Status = 'Skipped'
                    ExitCode = $null
                    Message = 'Skipped by ShouldProcess'
                    CapturedOutput = @()
                    InformationalOutput = @()
                }
            }
        }

        $upgradedCount = @($results | Where-Object { $_.Status -eq 'Upgraded' }).Count
        $failedCount = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
        $skippedCount = @($results | Where-Object { $_.Status -eq 'Skipped' }).Count
        $notSelectedCount = $packageUpdates.Count - $selectedPackages.Count
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
            TotalAvailable = $packageUpdates.Count
            Selected = $selectedPackages.Count
            NotSelected = $notSelectedCount
            Upgraded = $upgradedCount
            Failed = $failedCount
            Skipped = $skippedCount
            InformationalResults = @($informationalResults)
            Results = $results
        }
    }
}

# Create 'Update-PlatformPackage' alias only if it doesn't already exist
if (-not (Get-Alias -Name 'Update-PlatformPackage' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'Update-PlatformPackage' alias for Upgrade-PlatformPackage"
        Set-Alias -Name 'Update-PlatformPackage' -Value 'Upgrade-PlatformPackage' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Upgrade-PlatformPackage: Could not create 'Update-PlatformPackage' alias: $($_.Exception.Message)"
    }
}

# Create 'upgrade' alias only if it doesn't already exist
if (-not (Get-Alias -Name 'upgrade' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'upgrade' alias for Upgrade-PlatformPackage"
        Set-Alias -Name 'upgrade' -Value 'Upgrade-PlatformPackage' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Upgrade-PlatformPackage: Could not create 'upgrade' alias: $($_.Exception.Message)"
    }
}

# Create 'update' alias only if it doesn't already exist
if (-not (Get-Alias -Name 'update' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'update' alias for Upgrade-PlatformPackage"
        Set-Alias -Name 'update' -Value 'Upgrade-PlatformPackage' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Upgrade-PlatformPackage: Could not create 'update' alias: $($_.Exception.Message)"
    }
}
