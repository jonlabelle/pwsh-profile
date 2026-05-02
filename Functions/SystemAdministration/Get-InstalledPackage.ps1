function Get-InstalledPackage
{
    <#
    .SYNOPSIS
        Gets installed packages from the native platform package manager.

    .DESCRIPTION
        Detects the supported package manager for the current platform and returns
        installed package records as PowerShell objects. Supported package managers:
        winget on Windows, Homebrew on macOS, and apt or apk on Linux.

        Package records are normalized into a consistent object shape so they can be
        filtered, formatted, or piped into other commands. Use -Name and -ExcludePackage
        to apply wildcard filtering against the package Name or Id properties.

    .PARAMETER Name
        Optional package names or wildcard patterns to include. Matches package Name or Id.

    .PARAMETER ExcludePackage
        Optional package names or wildcard patterns to exclude. Matches package Name or Id.

    .EXAMPLE
        PS > Get-InstalledPackage

        Returns installed packages for the detected platform package manager.

    .EXAMPLE
        PS > Get-InstalledPackage -Name 'git*'

        Returns installed packages whose name or id matches git*.

    .EXAMPLE
        PS > Get-InstalledPackage -ExcludePackage '*preview*'

        Returns installed packages except those whose name or id matches *preview*.

    .EXAMPLE
        PS > Get-InstalledPackage | Format-Table Name, InstalledVersion, Source

        Formats installed package records as a table.

    .EXAMPLE
        PS > Get-InstalledPackage -Name 'node*' | Sort-Object -Property InstalledVersion

        Returns matching node packages sorted by installed version.

    .EXAMPLE
        PS > Get-InstalledPackage -PackageManager winget

        Returns installed packages using winget.

    .EXAMPLE
        PS > Get-InstalledPackage -PackageManager brew

        Returns installed packages using Homebrew.

    .EXAMPLE
        PS > Get-InstalledPackage -PackageManager apt

        Returns installed packages using apt.

    .EXAMPLE
        PS > Get-InstalledPackage -PackageManager apk

        Returns installed packages using apk.

    .EXAMPLE
        PS > Get-InstalledPackage -Verbose

        Returns installed packages and writes the detected package manager to verbose output.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        - winget is used on Windows.
        - brew is used on macOS.
        - apt is used on Debian/Ubuntu-style Linux distributions.
        - apk is used on Alpine Linux.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Get-InstalledPackage.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Get-InstalledPackage.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [PSCustomObject[]], [Object[]])]
    param(
        [Parameter(Position = 0)]
        [Alias('PackageName', 'Include', 'IncludePackage')]
        [String[]]$Name = @(),

        [Parameter()]
        [Alias('Exclude')]
        [String[]]$ExcludePackage = @(),

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

        function Get-InstalledPackageObject
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
                    }
                }
                'brew'
                {
                    [PSCustomObject]@{
                        Name = 'brew'
                        DisplayName = 'Homebrew'
                        Command = 'brew'
                        Platform = 'macOS'
                    }
                }
                'apt'
                {
                    [PSCustomObject]@{
                        Name = 'apt'
                        DisplayName = 'APT'
                        Command = 'apt'
                        Platform = 'Debian/Ubuntu Linux'
                    }
                }
                'apk'
                {
                    [PSCustomObject]@{
                        Name = 'apk'
                        DisplayName = 'Alpine Package Keeper'
                        Command = 'apk'
                        Platform = 'Alpine Linux'
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
                [String[]]$Arguments = @()
            )

            if ($CommandRunner)
            {
                $runnerOutput = & $CommandRunner -Command $Command -Arguments $Arguments
                $runnerOutputItems = @($runnerOutput)

                if ($runnerOutputItems.Count -eq 1)
                {
                    $item = $runnerOutputItems[0]

                    if ($item -is [System.Collections.IDictionary] -and $item.Contains('ExitCode') -and $item.Contains('Output'))
                    {
                        return [PSCustomObject]@{
                            ExitCode = [Int32]$item['ExitCode']
                            Output = @($item['Output'])
                        }
                    }

                    if ($item -and $item.PSObject.Properties['ExitCode'] -and $item.PSObject.Properties['Output'])
                    {
                        return [PSCustomObject]@{
                            ExitCode = [Int32]$item.ExitCode
                            Output = @($item.Output)
                        }
                    }
                }

                return [PSCustomObject]@{
                    ExitCode = 0
                    Output = @($runnerOutputItems)
                }
            }

            $output = @()

            try
            {
                $output = @(& $Command @Arguments 2>&1)

                return [PSCustomObject]@{
                    ExitCode = if ($null -ne $LASTEXITCODE) { [Int32]$LASTEXITCODE } else { 0 }
                    Output = @($output)
                }
            }
            catch
            {
                return [PSCustomObject]@{
                    ExitCode = 1
                    Output = @($_.Exception.Message)
                }
            }
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

                $packageName = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Name', 'PackageName'))
                $id = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Id', 'PackageIdentifier', 'Identifier'))
                $installedVersion = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('InstalledVersion', 'Version', 'CurrentVersion'))
                $source = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Source', 'SourceName'))

                if ([String]::IsNullOrWhiteSpace($packageName))
                {
                    continue
                }

                $packages += Get-InstalledPackageObject -Manager $Manager -Name $packageName -Id $id -Type 'Package' -InstalledVersion $installedVersion -Source $source
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

                $packageName = Get-WingetTableCell -Line $line -Start $nameStart -End $idStart
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

                if ([String]::IsNullOrWhiteSpace($packageName))
                {
                    continue
                }

                $packages += Get-InstalledPackageObject -Manager $Manager -Name $packageName -Id $id -Type 'Package' -InstalledVersion $installedVersion -Source $source
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

            return ConvertFrom-WingetTableOutput -Manager $Manager -Output $tableResult.Output
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

                $packageName = $parts[0]
                $version = if ($parts.Count -gt 1) { ($parts[1..($parts.Count - 1)] -join ', ') } else { '' }
                $source = if ($Type -eq 'Cask') { 'homebrew/cask' } else { 'homebrew/core' }

                $packages += Get-InstalledPackageObject -Manager $Manager -Name $packageName -Id $packageName -Type $Type -InstalledVersion $version -Source $source
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
                    $packageName = $Matches.Name
                    $repository = $Matches.Repository
                    $version = $Matches.Version
                    $architecture = $Matches.Architecture
                    $state = $Matches.State
                    $notes = if ($state -match 'automatic') { 'Automatic' } else { '' }
                    $packages += Get-InstalledPackageObject -Manager $Manager -Name $packageName -Id $packageName -Type $architecture -InstalledVersion $version -Source $repository -Notes $notes
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

            return [PSCustomObject]@{
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

                $packages += Get-InstalledPackageObject -Manager $Manager -Name $packageInfo.Name -Id $packageInfo.Name -Type 'Package' -InstalledVersion $packageInfo.Version -Source 'apk'
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
                'winget' { return Get-WingetInstalledPackages -Manager $Manager }
                'brew' { return Get-BrewInstalledPackages -Manager $Manager }
                'apt' { return Get-AptInstalledPackages -Manager $Manager }
                'apk' { return Get-ApkInstalledPackages -Manager $Manager }
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
    }

    process
    {
        $manager = Resolve-PackageManager
        Write-Verbose "Using package manager: $($manager.DisplayName) ($($manager.Command))"

        $installedPackages = @(Get-InstalledPackages -Manager $manager)

        if ($Name -and $Name.Count -gt 0)
        {
            $installedPackages = @($installedPackages | Where-Object { Test-PackagePatternMatch -Package $_ -Pattern $Name })
        }

        if ($ExcludePackage -and $ExcludePackage.Count -gt 0)
        {
            $installedPackages = @($installedPackages | Where-Object { -not (Test-PackagePatternMatch -Package $_ -Pattern $ExcludePackage) })
        }

        return @($installedPackages | Sort-Object -Property Name, Id)
    }
}
