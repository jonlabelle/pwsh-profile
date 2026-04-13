function Upgrade-Package
{
    <#
    .SYNOPSIS
        Upgrades outdated packages with the native platform package manager.

    .DESCRIPTION
        Detects the supported package manager for the current platform, refreshes package
        registry metadata, lists packages with available upgrades, and opens an interactive
        console picker where packages can be selected with the spacebar.

        Supported package managers:
        - Windows: winget
        - macOS: brew
        - Debian/Ubuntu Linux: apt
        - Alpine Linux: apk

        Refresh and upgrade command output is streamed directly to the console so the
        operation can be followed while it runs. Use -AsObject to return the discovered
        package update list without starting the interactive picker, or -All to upgrade
        every discovered package without prompting.

    .PARAMETER IncludePackage
        Optional package names or wildcard patterns to include. Matches package Name or Id.

    .PARAMETER ExcludePackage
        Optional package names or wildcard patterns to exclude. Matches package Name or Id.

    .PARAMETER All
        Upgrades all matching outdated packages without opening the interactive picker.

    .PARAMETER SkipRefresh
        Skips refreshing package registry metadata before checking for upgrades.

    .PARAMETER AsObject
        Returns the discovered outdated package records without upgrading anything.

    .PARAMETER NoSudo
        On Linux package managers that normally require elevated privileges, do not
        automatically prefix refresh and upgrade commands with sudo.

    .EXAMPLE
        PS > Upgrade-Package

        Refreshes package registry metadata, opens the interactive picker, and upgrades
        the packages selected with the spacebar.

    .EXAMPLE
        PS > Upgrade-Package -All

        Refreshes package registry metadata and upgrades all discovered outdated packages.

    .EXAMPLE
        PS > Upgrade-Package -IncludePackage 'git*','curl' -ExcludePackage '*preview*'

        Opens the picker for matching git and curl packages except packages whose name or id
        matches '*preview*'.

    .EXAMPLE
        PS > Upgrade-Package -AsObject -SkipRefresh | Format-Table

        Lists outdated packages from the current package cache without running upgrades.

    .EXAMPLE
        PS > Upgrade-Package -All -WhatIf

        Shows the package upgrades that would run without invoking the package manager.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns package records when -AsObject is used. Otherwise returns an upgrade summary
        object with package manager, selection counts, NotSelected, selected-package
        skip/failure counts, and per-package results.

    .NOTES
        - winget is used on Windows.
        - brew is used on macOS.
        - apt is used on Debian/Ubuntu-style Linux distributions.
        - apk is used on Alpine Linux.
        - apt and apk operations are prefixed with sudo when needed and available.
        - Query commands are parsed to build the picker; refresh and upgrade commands stream
          their native output to the console.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Upgrade-Package.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Upgrade-Package.ps1
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
        [Switch]$AsObject,

        [Parameter()]
        [Switch]$NoSudo,

        [Parameter(DontShow = $true)]
        [ValidateSet('Auto', 'winget', 'brew', 'apt', 'apk')]
        [String]$PackageManager = 'Auto',

        [Parameter(DontShow = $true)]
        [ScriptBlock]$CommandRunner
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
                        RefreshArguments = @('update')
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

            $output = @()

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

            Write-Host "Refreshing $($Manager.DisplayName) package metadata..."

            $invocation = Resolve-PackageManagerInvocation -Manager $Manager -Arguments $Manager.RefreshArguments
            $result = Invoke-PackageManagerCommand -Command $invocation.Command -Arguments $invocation.Arguments -StreamOutput

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
                        $candidatePackages += @($source.Packages)
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

                if ([String]::IsNullOrWhiteSpace($name) -or [String]::IsNullOrWhiteSpace($latestVersion))
                {
                    continue
                }

                $upgradeArguments = if (-not [String]::IsNullOrWhiteSpace($id))
                {
                    @('upgrade', '--id', $id, '--exact', '--accept-package-agreements', '--accept-source-agreements')
                }
                else
                {
                    @('upgrade', $name, '--accept-package-agreements', '--accept-source-agreements')
                }

                $updates += Get-PackageUpdateObject -Manager $Manager -Name $name -Id $id -Type 'Package' -InstalledVersion $installedVersion -LatestVersion $latestVersion -Source $source -UpgradeArguments $upgradeArguments
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
                if ([String]::IsNullOrWhiteSpace($line) -or $line -match '^-{3,}' -or $line -match '^\d+\s+upgrades?\s+available')
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

                $upgradeArguments = if (-not [String]::IsNullOrWhiteSpace($id))
                {
                    @('upgrade', '--id', $id, '--exact', '--accept-package-agreements', '--accept-source-agreements')
                }
                else
                {
                    @('upgrade', $name, '--accept-package-agreements', '--accept-source-agreements')
                }

                $updates += Get-PackageUpdateObject -Manager $Manager -Name $name -Id $id -Type 'Package' -InstalledVersion $installedVersion -LatestVersion $latestVersion -Source $source -UpgradeArguments $upgradeArguments
            }

            return $updates
        }

        function Get-WingetPackageUpdates
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            $jsonResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('upgrade', '--accept-source-agreements', '--output', 'json')
            if ($jsonResult.ExitCode -eq 0)
            {
                $jsonUpdates = @(ConvertFrom-WingetJsonOutput -Manager $Manager -Output $jsonResult.Output)
                if ($jsonUpdates.Count -gt 0)
                {
                    return $jsonUpdates
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

            ConvertFrom-WingetTableOutput -Manager $Manager -Output $tableResult.Output
        }

        function Get-BrewPackageUpdates
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('outdated', '--json=v2')
            if ($result.ExitCode -ne 0)
            {
                $message = ($result.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to query Homebrew upgrades: $message"
            }

            $jsonText = ($result.Output | ForEach-Object { "$_" }) -join "`n"
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
                $updates += Get-PackageUpdateObject -Manager $Manager -Name $name -Id $name -Type 'Formula' -InstalledVersion (ConvertTo-PackageText -Value $formula.installed_versions) -LatestVersion (ConvertTo-PackageText -Value $formula.current_version) -Source 'homebrew/core' -Notes $notes -UpgradeArguments @('upgrade', $name)
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
                $updates += Get-PackageUpdateObject -Manager $Manager -Name $name -Id $name -Type 'Cask' -InstalledVersion (ConvertTo-PackageText -Value $cask.installed_versions) -LatestVersion (ConvertTo-PackageText -Value $cask.current_version) -Source 'homebrew/cask' -Notes $notes -UpgradeArguments @('upgrade', '--cask', $name)
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
                [PSCustomObject]$Manager
            )

            switch ($Manager.Name)
            {
                'winget' { Get-WingetPackageUpdates -Manager $Manager }
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
                [PSCustomObject[]]$PackageUpdates = @()
            )

            if ($PackageUpdates.Count -eq 0)
            {
                return @()
            }

            try
            {
                if ([Console]::IsInputRedirected)
                {
                    throw 'Console input is redirected.'
                }
            }
            catch
            {
                throw 'Interactive package selection requires an attached console. Use -All, -AsObject, or -IncludePackage with -All in non-interactive sessions.'
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

            $nameWidth = [Math]::Min(36, [Math]::Max(4, (($PackageUpdates | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)))
            $installedWidth = [Math]::Min(20, [Math]::Max(9, (($PackageUpdates | ForEach-Object { $_.InstalledVersion.Length } | Measure-Object -Maximum).Maximum)))
            $latestWidth = [Math]::Min(20, [Math]::Max(6, (($PackageUpdates | ForEach-Object { $_.LatestVersion.Length } | Measure-Object -Maximum).Maximum)))
            $typeWidth = [Math]::Min(12, [Math]::Max(4, (($PackageUpdates | ForEach-Object { $_.Type.Length } | Measure-Object -Maximum).Maximum)))

            $selected = New-Object 'System.Boolean[]' $PackageUpdates.Count
            $cursor = 0

            while ($true)
            {
                Clear-Host
                Write-Host "Upgrade-Package - $($PackageUpdates[0].PackageManagerDisplayName)"
                Write-Host 'Space: select  Enter: upgrade selected  A: toggle all  Q/Esc: cancel'
                Write-Host ''
                Write-Host ('  {0} {1} {2} {3} {4}' -f 'Sel', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Installed' -Width $installedWidth), (Format-PickerCell -Text 'Available' -Width $latestWidth), (Format-PickerCell -Text 'Type' -Width $typeWidth))
                Write-Host ('  {0} {1} {2} {3} {4}' -f '---', ('-' * $nameWidth), ('-' * $installedWidth), ('-' * $latestWidth), ('-' * $typeWidth))

                for ($i = 0; $i -lt $PackageUpdates.Count; $i++)
                {
                    $package = $PackageUpdates[$i]
                    $cursorMarker = if ($i -eq $cursor) { '>' } else { ' ' }
                    $selectedMarker = if ($selected[$i]) { '[x]' } else { '[ ]' }
                    Write-Host ('{0} {1} {2} {3} {4} {5}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $installedWidth), (Format-PickerCell -Text $package.LatestVersion -Width $latestWidth), (Format-PickerCell -Text $package.Type -Width $typeWidth))
                }

                Write-Host ''
                Write-Host "$(@($selected | Where-Object { $_ }).Count) of $($PackageUpdates.Count) package(s) selected."

                $key = [Console]::ReadKey($true)
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
                        if ($cursor -lt ($PackageUpdates.Count - 1))
                        {
                            $cursor++
                        }
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
                        $selectedPackages = @()
                        for ($i = 0; $i -lt $PackageUpdates.Count; $i++)
                        {
                            if ($selected[$i])
                            {
                                $selectedPackages += $PackageUpdates[$i]
                            }
                        }

                        Clear-Host
                        return $selectedPackages
                    }
                    { $_ -in @('Escape', 'Q') }
                    {
                        Clear-Host
                        return @()
                    }
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
            Write-Host "Upgrading $($Package.Name) ($versionText) with $($Manager.DisplayName)..."

            $invocation = Resolve-PackageManagerInvocation -Manager $Manager -Arguments $Package.UpgradeArguments
            $result = Invoke-PackageManagerCommand -Command $invocation.Command -Arguments $invocation.Arguments -StreamOutput

            if ($result.ExitCode -eq 0)
            {
                [PSCustomObject]@{
                    Name = $Package.Name
                    Id = $Package.Id
                    InstalledVersion = $Package.InstalledVersion
                    LatestVersion = $Package.LatestVersion
                    Status = 'Upgraded'
                    ExitCode = $result.ExitCode
                    Message = 'Upgrade completed'
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

        Write-Host "Checking for available upgrades with $($manager.DisplayName)..."
        $packageUpdates = @(Get-PackageUpdates -Manager $manager)

        if ($IncludePackage -and $IncludePackage.Count -gt 0)
        {
            $packageUpdates = @($packageUpdates | Where-Object { Test-PackagePatternMatch -Package $_ -Pattern $IncludePackage })
        }

        if ($ExcludePackage -and $ExcludePackage.Count -gt 0)
        {
            $packageUpdates = @($packageUpdates | Where-Object { -not (Test-PackagePatternMatch -Package $_ -Pattern $ExcludePackage) })
        }

        $packageUpdates = @($packageUpdates | Sort-Object -Property Name, Id)

        if ($AsObject)
        {
            return $packageUpdates
        }

        if ($packageUpdates.Count -eq 0)
        {
            Write-Host 'No package upgrades are available.'
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
                Select-PackageUpdateRecords -PackageUpdates $packageUpdates
            }
        )

        if ($selectedPackages.Count -eq 0)
        {
            Write-Host 'No packages selected for upgrade.'
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
                }
            }
        }

        $upgradedCount = @($results | Where-Object { $_.Status -eq 'Upgraded' }).Count
        $failedCount = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
        $skippedCount = @($results | Where-Object { $_.Status -eq 'Skipped' }).Count
        $notSelectedCount = $packageUpdates.Count - $selectedPackages.Count

        [PSCustomObject]@{
            PackageManager = $manager.Name
            PackageManagerDisplayName = $manager.DisplayName
            TotalAvailable = $packageUpdates.Count
            Selected = $selectedPackages.Count
            NotSelected = $notSelectedCount
            Upgraded = $upgradedCount
            Failed = $failedCount
            Skipped = $skippedCount
            Results = $results
        }
    }
}
