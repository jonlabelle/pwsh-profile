function Remove-Package
{
    <#
    .SYNOPSIS
        Removes installed packages with the native platform package manager.

    .DESCRIPTION
        Detects the supported package manager for the current platform, lists installed
        packages, and opens an interactive console picker where packages can be selected
        with the spacebar before removal.

        Supported package managers:
        - Windows: winget
        - macOS: brew
        - Debian/Ubuntu Linux: apt
        - Alpine Linux: apk

        Removal command output is streamed directly to the console so the operation can
        be followed while it runs. Use -AsObject to return the discovered installed
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
        Uses package-manager-specific purge or zap behavior when supported. This uses
        apt purge, apk del --purge, and brew uninstall --zap for casks. It has no effect
        for winget or Homebrew formulae.

    .PARAMETER AsObject
        Returns the discovered installed package records without removing anything.

    .PARAMETER NoSudo
        On Linux package managers that normally require elevated privileges, do not
        automatically prefix remove commands with sudo.

    .EXAMPLE
        PS > Remove-Package

        Lists installed packages, opens the interactive picker, and removes the packages
        selected with the spacebar.

    .EXAMPLE
        PS > Remove-Package -IncludePackage 'git*' -All

        Removes every installed package whose name or id matches 'git*' without prompting.

    .EXAMPLE
        PS > Remove-Package -IncludePackage 'node*' -ExcludePackage 'node@18'

        Opens the picker for matching node packages except packages whose name or id
        matches 'node@18'.

    .EXAMPLE
        PS > Remove-Package -IncludePackage 'openssl' -Purge -All

        Removes the matching package and requests package-manager-specific purge behavior
        where supported.

    .EXAMPLE
        PS > Remove-Package -AsObject | Format-Table

        Lists installed packages for the detected package manager without removing anything.

    .EXAMPLE
        PS > Remove-Package -IncludePackage 'git' -All -WhatIf

        Shows the package removal that would run without invoking the package manager.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns package records when -AsObject is used. Otherwise returns a removal summary
        object with package manager, selection counts, NotSelected, selected-package
        skip/failure counts, and per-package results.

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
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Remove-Package.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Remove-Package.ps1
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
        [Switch]$AsObject,

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
                [String]$Type
            )

            switch ($Manager.Name)
            {
                'winget'
                {
                    if (-not [String]::IsNullOrWhiteSpace($Id))
                    {
                        return @('uninstall', '--id', $Id, '--exact', '--accept-source-agreements')
                    }

                    return @('uninstall', $Name, '--accept-source-agreements')
                }
                'brew'
                {
                    if ($Type -eq 'Cask')
                    {
                        if ($Purge)
                        {
                            return @('uninstall', '--cask', '--zap', $Name)
                        }

                        return @('uninstall', '--cask', $Name)
                    }

                    return @('uninstall', $Name)
                }
                'apt'
                {
                    if ($Purge)
                    {
                        return @('purge', '-y', $Name)
                    }

                    return @('remove', '-y', $Name)
                }
                'apk'
                {
                    if ($Purge)
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

        function Get-PackageInstallObject
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
                Notes = $Notes
                Command = $Manager.Command
                RemoveArguments = @(Get-PackageRemoveArguments -Manager $Manager -Name $Name -Id $Id -Type $Type)
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

                if ([String]::IsNullOrWhiteSpace($name))
                {
                    continue
                }

                $packages += Get-PackageInstallObject -Manager $Manager -Name $name -Id $id -Type 'Package' -InstalledVersion $installedVersion -Source $source
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

                $packages += Get-PackageInstallObject -Manager $Manager -Name $name -Id $id -Type 'Package' -InstalledVersion $installedVersion -Source $source
            }

            return $packages
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
                    return $jsonPackages
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

            ConvertFrom-WingetTableOutput -Manager $Manager -Output $tableResult.Output
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

                $packages += Get-PackageInstallObject -Manager $Manager -Name $name -Id $name -Type $Type -InstalledVersion $version -Source $source
            }

            return $packages
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
                    $packages += Get-PackageInstallObject -Manager $Manager -Name $name -Id $name -Type $architecture -InstalledVersion $version -Source $repository -Notes $notes
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

                $packages += Get-PackageInstallObject -Manager $Manager -Name $packageInfo.Name -Id $packageInfo.Name -Type 'Package' -InstalledVersion $packageInfo.Version -Source 'apk'
            }

            return $packages
        }

        function Get-InstalledPackages
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
                [Int32]$PageSize = 0
            )

            if ($InstalledPackages.Count -eq 0)
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
                    throw 'Interactive package selection requires an attached console. Use -All, -AsObject, or -IncludePackage with -All in non-interactive sessions.'
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
                        $reservedRows = 8
                        return [Math]::Min([Math]::Max(1, $windowHeight - $reservedRows), [Math]::Max(1, $ItemCount))
                    }
                }
                catch
                {
                    Write-Verbose "Unable to determine console height for package picker: $($_.Exception.Message)"
                }

                return $fallbackPageSize
            }

            $nameWidth = [Math]::Min(36, [Math]::Max(4, (($InstalledPackages | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)))
            $versionWidth = [Math]::Min(20, [Math]::Max(7, (($InstalledPackages | ForEach-Object { $_.InstalledVersion.Length } | Measure-Object -Maximum).Maximum)))
            $typeWidth = [Math]::Min(12, [Math]::Max(4, (($InstalledPackages | ForEach-Object { $_.Type.Length } | Measure-Object -Maximum).Maximum)))
            $sourceWidth = [Math]::Min(18, [Math]::Max(6, (($InstalledPackages | ForEach-Object { $_.Source.Length } | Measure-Object -Maximum).Maximum)))
            $pageSize = Get-PackagePickerPageSize -RequestedPageSize $PageSize -ItemCount $InstalledPackages.Count

            $selected = New-Object 'System.Boolean[]' $InstalledPackages.Count
            $cursor = 0
            $topIndex = 0
            $restoreTreatControlCAsInput = $false
            $previousTreatControlCAsInput = $false

            try
            {
                if ($usingConsoleKeyReader)
                {
                    $previousTreatControlCAsInput = [Console]::TreatControlCAsInput
                    [Console]::TreatControlCAsInput = $true
                    $restoreTreatControlCAsInput = $true
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

                    $maxTopIndex = [Math]::Max(0, $InstalledPackages.Count - $pageSize)
                    if ($topIndex -gt $maxTopIndex)
                    {
                        $topIndex = $maxTopIndex
                    }

                    $bottomIndex = [Math]::Min($InstalledPackages.Count - 1, $topIndex + $pageSize - 1)

                    Clear-Host
                    Write-Host "Remove-Package - $($InstalledPackages[0].PackageManagerDisplayName)"
                    Write-Host 'Space: select  Enter: remove selected  A: toggle all  Home/End/PgUp/PgDn: navigate  Ctrl+C/Q/Esc: cancel'
                    Write-Host ''
                    Write-Host ('  {0} {1} {2} {3} {4}' -f 'Sel', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Version' -Width $versionWidth), (Format-PickerCell -Text 'Type' -Width $typeWidth), (Format-PickerCell -Text 'Source' -Width $sourceWidth))
                    Write-Host ('  {0} {1} {2} {3} {4}' -f '---', ('-' * $nameWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth))

                    for ($i = $topIndex; $i -le $bottomIndex; $i++)
                    {
                        $package = $InstalledPackages[$i]
                        $cursorMarker = if ($i -eq $cursor) { '>' } else { ' ' }
                        $selectedMarker = if ($selected[$i]) { '[x]' } else { '[ ]' }
                        Write-Host ('{0} {1} {2} {3} {4} {5}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $versionWidth), (Format-PickerCell -Text $package.Type -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                    }

                    Write-Host ''
                    Write-Host "$(@($selected | Where-Object { $_ }).Count) of $($InstalledPackages.Count) package(s) selected."

                    $key = & $KeyReader
                    if (Test-PackagePickerCancelKey -KeyInfo $key)
                    {
                        Clear-Host
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
                            if ($cursor -lt ($InstalledPackages.Count - 1))
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
                            $cursor = [Math]::Min($InstalledPackages.Count - 1, $cursor + $pageSize)
                        }
                        'Home'
                        {
                            $cursor = 0
                        }
                        'End'
                        {
                            $cursor = $InstalledPackages.Count - 1
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
                            for ($i = 0; $i -lt $InstalledPackages.Count; $i++)
                            {
                                if ($selected[$i])
                                {
                                    $selectedPackages += $InstalledPackages[$i]
                                }
                            }

                            Clear-Host
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
            Write-Host "Removing $($Package.Name)$versionText with $($Manager.DisplayName)..."

            $invocation = Resolve-PackageManagerInvocation -Manager $Manager -Arguments $Package.RemoveArguments
            $result = Invoke-PackageManagerCommand -Command $invocation.Command -Arguments $invocation.Arguments -StreamOutput

            if ($result.ExitCode -eq 0)
            {
                [PSCustomObject]@{
                    Name = $Package.Name
                    Id = $Package.Id
                    InstalledVersion = $Package.InstalledVersion
                    Status = 'Removed'
                    ExitCode = $result.ExitCode
                    Message = 'Removal completed'
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
                }
            }
        }
    }

    process
    {
        $manager = Resolve-PackageManager
        Write-Verbose "Using package manager: $($manager.DisplayName) ($($manager.Command))"

        Write-Host "Checking installed packages with $($manager.DisplayName)..."
        $installedPackages = @(Get-InstalledPackages -Manager $manager)

        if ($IncludePackage -and $IncludePackage.Count -gt 0)
        {
            $installedPackages = @($installedPackages | Where-Object { Test-PackagePatternMatch -Package $_ -Pattern $IncludePackage })
        }

        if ($ExcludePackage -and $ExcludePackage.Count -gt 0)
        {
            $installedPackages = @($installedPackages | Where-Object { -not (Test-PackagePatternMatch -Package $_ -Pattern $ExcludePackage) })
        }

        $installedPackages = @($installedPackages | Sort-Object -Property Name, Id)

        if ($AsObject)
        {
            return $installedPackages
        }

        if ($installedPackages.Count -eq 0)
        {
            Write-Host 'No installed packages matched the requested filters.'
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
                Select-PackageInstallRecords -InstalledPackages $installedPackages -KeyReader $KeyReader -PageSize $PickerPageSize
            }
        )

        if ($selectedPackages.Count -eq 0)
        {
            Write-Host 'No packages selected for removal.'
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

        $results = @()
        foreach ($package in $selectedPackages)
        {
            $displayTarget = if (-not [String]::IsNullOrWhiteSpace($package.Id)) { $package.Id } else { $package.Name }
            $versionText = if (-not [String]::IsNullOrWhiteSpace($package.InstalledVersion)) { " $($package.InstalledVersion)" } else { '' }

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
                }
            }
        }

        $removedCount = @($results | Where-Object { $_.Status -eq 'Removed' }).Count
        $failedCount = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
        $skippedCount = @($results | Where-Object { $_.Status -eq 'Skipped' }).Count
        $notSelectedCount = $installedPackages.Count - $selectedPackages.Count

        [PSCustomObject]@{
            PackageManager = $manager.Name
            PackageManagerDisplayName = $manager.DisplayName
            TotalMatched = $installedPackages.Count
            Selected = $selectedPackages.Count
            NotSelected = $notSelectedCount
            Removed = $removedCount
            Failed = $failedCount
            Skipped = $skippedCount
            Results = $results
        }
    }
}
