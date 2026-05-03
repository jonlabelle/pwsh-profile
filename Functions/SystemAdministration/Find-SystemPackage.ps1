function Find-SystemPackage
{
    <#
    .SYNOPSIS
        Searches native platform package registries.

    .DESCRIPTION
        Searches the supported native package registry for the current platform and returns
        normalized package records. Supported package managers are winget on Windows,
        Homebrew on macOS, and apt or apk on Linux.

        By default, searches open an interactive remote-search UI with a prompt-based search
        box and a neatly formatted results browser. From the browser, press I to install the
        current package or the selected packages. Use -PassThru to return the selected records
        instead of installing them.

        Use -NonInteractive to return search results as PowerShell objects so they can be
        filtered, formatted, or piped into Install-SystemPackage. Use -Top to cap broad
        searches and -ExcludePackage to remove unwanted matches from the normalized results.

    .PARAMETER Query
        Search text sent to the selected package manager.

    .PARAMETER NonInteractive
        Returns normalized package records without opening the interactive remote package
        search UI. Query is required in non-interactive mode.

    .PARAMETER PassThru
        Allows packages to be selected in the interactive UI and returns the selected package
        records when Enter is pressed.

    .PARAMETER ExcludePackage
        Optional package names or wildcard patterns to exclude from the normalized results.
        Matches package Name or Id.

    .PARAMETER Top
        Maximum number of search results to return after normalization and sorting. Use 0
        to return all matching results.

    .EXAMPLE
        PS > Find-SystemPackage -Query git

        Opens the interactive remote package search UI seeded with the git query. Press I
        to install the current package or the selected packages.

    .EXAMPLE
        PS > Find-SystemPackage -NonInteractive -Query 'visual studio code'

        Searches for packages matching the provided query text and returns objects.

    .EXAMPLE
        PS > Find-SystemPackage -NonInteractive -Query git -ExcludePackage 'git-lfs'

        Searches for git packages and excludes git-lfs from the returned results.

    .EXAMPLE
        PS > Find-SystemPackage -NonInteractive -Query git -Top 10

        Returns at most 10 normalized results.

    .EXAMPLE
        PS > Find-SystemPackage -NonInteractive -Query docker | Format-Table Name, Version, Source

        Searches for docker packages and formats the results.

    .EXAMPLE
        PS > Find-SystemPackage -Query git -PackageManager winget

        Opens the interactive search UI using winget.

    .EXAMPLE
        PS > Find-SystemPackage -Query git -PackageManager brew

        Opens the interactive search UI using Homebrew.

    .EXAMPLE
        PS > Find-SystemPackage -Query openssl -PackageManager apt

        Opens the interactive search UI using apt.

    .EXAMPLE
        PS > Find-SystemPackage -Query bash -PackageManager apk

        Opens the interactive search UI using apk.

    .EXAMPLE
        PS > Find-SystemPackage -Query nodejs -Verbose

        Opens the interactive search UI for nodejs and writes the detected package manager
        to verbose output.

    .EXAMPLE
        PS > Find-SystemPackage

        Opens the interactive remote package search UI and prompts for a query.

    .EXAMPLE
        PS > Find-SystemPackage -PassThru

        Opens the interactive UI, lets you select packages with the spacebar, and returns
        the selected package records when Enter is pressed.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Find-SystemPackage.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Find-SystemPackage.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [PSCustomObject[]], [Object[]])]
    param(
        [Parameter(Position = 0)]
        [Alias('Name', 'PackageName', 'Search')]
        [String]$Query,

        [Parameter()]
        [Switch]$NonInteractive,

        [Parameter()]
        [Switch]$PassThru,

        [Parameter()]
        [Alias('Exclude')]
        [String[]]$ExcludePackage = @(),

        [Parameter()]
        [ValidateRange(0, 500)]
        [Int32]$Top = 50,

        [Parameter(DontShow = $true)]
        [ValidateSet('Auto', 'winget', 'brew', 'apt', 'apk')]
        [String]$PackageManager = 'Auto',

        [Parameter(DontShow = $true)]
        [ScriptBlock]$CommandRunner,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$KeyReader,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$QueryReader,

        [Parameter(DontShow = $true)]
        [ValidateRange(0, 500)]
        [Int32]$PickerPageSize = 0
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

        function Get-AvailablePackageObject
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
                [String]$Version,

                [Parameter()]
                [String]$Source,

                [Parameter()]
                [String]$Description,

                [Parameter()]
                [Boolean]$Installed = $false,

                [Parameter()]
                [String]$Notes
            )

            [PSCustomObject]@{
                Name = $Name
                Id = $Id
                PackageManager = $Manager.Name
                PackageManagerDisplayName = $Manager.DisplayName
                Type = $Type
                Version = $Version
                Source = $Source
                Description = $Description
                Installed = $Installed
                Notes = $Notes
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
                    }
                }
                'brew'
                {
                    [PSCustomObject]@{
                        Name = 'brew'
                        DisplayName = 'Homebrew'
                        Command = 'brew'
                    }
                }
                'apt'
                {
                    [PSCustomObject]@{
                        Name = 'apt'
                        DisplayName = 'APT'
                        Command = 'apt'
                    }
                }
                'apk'
                {
                    [PSCustomObject]@{
                        Name = 'apk'
                        DisplayName = 'Alpine Package Keeper'
                        Command = 'apk'
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

        function Get-PackageLookupKey
        {
            param(
                [Parameter()]
                [String]$Type,

                [Parameter()]
                [String]$Value
            )

            if ([String]::IsNullOrWhiteSpace($Value))
            {
                return ''
            }

            $typeKey = if ([String]::IsNullOrWhiteSpace($Type)) { '' } else { $Type.Trim().ToLowerInvariant() }
            $valueKey = $Value.Trim().ToLowerInvariant()

            return "$typeKey|$valueKey"
        }

        function Add-PackageToInstalledLookup
        {
            param(
                [Parameter(Mandatory)]
                [Hashtable]$Lookup,

                [Parameter(Mandatory)]
                [PSCustomObject]$Package
            )

            $values = @($Package.Id, $Package.Name) |
            Where-Object { -not [String]::IsNullOrWhiteSpace("$_") } |
            ForEach-Object { "$_".Trim() } |
            Select-Object -Unique

            foreach ($value in $values)
            {
                $key = Get-PackageLookupKey -Type $Package.Type -Value $value
                if (-not [String]::IsNullOrWhiteSpace($key) -and -not $Lookup.ContainsKey($key))
                {
                    $Lookup[$key] = $Package
                }
            }
        }

        function Get-PackageFromInstalledLookup
        {
            param(
                [Parameter(Mandatory)]
                [Hashtable]$Lookup,

                [Parameter(Mandatory)]
                [PSCustomObject]$Package
            )

            $values = @($Package.Id, $Package.Name) |
            Where-Object { -not [String]::IsNullOrWhiteSpace("$_") } |
            ForEach-Object { "$_".Trim() } |
            Select-Object -Unique

            foreach ($value in $values)
            {
                $key = Get-PackageLookupKey -Type $Package.Type -Value $value
                if (-not [String]::IsNullOrWhiteSpace($key) -and $Lookup.ContainsKey($key))
                {
                    return $Lookup[$key]
                }

                if (-not ([String]::IsNullOrWhiteSpace($Package.Type) -or $Package.Type -eq 'Package'))
                {
                    continue
                }

                $fallbackKey = Get-PackageLookupKey -Value $value
                if (-not [String]::IsNullOrWhiteSpace($fallbackKey) -and $Lookup.ContainsKey($fallbackKey))
                {
                    return $Lookup[$fallbackKey]
                }
            }

            return $null
        }

        function Set-InstalledPackageState
        {
            param(
                [Parameter()]
                [PSCustomObject[]]$AvailablePackages = @(),

                [Parameter()]
                [PSCustomObject[]]$InstalledPackages = @()
            )

            if ($AvailablePackages.Count -eq 0 -or $InstalledPackages.Count -eq 0)
            {
                return @($AvailablePackages)
            }

            $installedLookup = @{}
            foreach ($installedPackage in $InstalledPackages)
            {
                if ($null -ne $installedPackage)
                {
                    Add-PackageToInstalledLookup -Lookup $installedLookup -Package $installedPackage
                }
            }

            foreach ($package in $AvailablePackages)
            {
                $installedPackage = Get-PackageFromInstalledLookup -Lookup $installedLookup -Package $package
                if ($null -eq $installedPackage)
                {
                    continue
                }

                $package.Installed = $true

                if ([String]::IsNullOrWhiteSpace($package.Notes) -and -not [String]::IsNullOrWhiteSpace($installedPackage.Notes))
                {
                    $package.Notes = $installedPackage.Notes
                }
            }

            return @($AvailablePackages)
        }

        function Get-InstalledPackagesForSearch
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            try
            {
                $getSystemPackageDependencyPath = Get-DependencyPathIfNeeded -FunctionName 'Get-SystemPackage' -RelativePath 'Get-SystemPackage.ps1'
            }
            catch
            {
                Write-Verbose "Unable to resolve Get-SystemPackage for installed-state detection: $($_.Exception.Message)"
                return @()
            }

            if (-not [String]::IsNullOrWhiteSpace($getSystemPackageDependencyPath))
            {
                try
                {
                    . $getSystemPackageDependencyPath
                    Write-Verbose "Loaded Get-SystemPackage from: $getSystemPackageDependencyPath"
                }
                catch
                {
                    Write-Verbose "Unable to load Get-SystemPackage for installed-state detection: $($_.Exception.Message)"
                    return @()
                }
            }

            try
            {
                return @(Get-SystemPackage -PackageManager $Manager.Name -CommandRunner $CommandRunner)
            }
            catch
            {
                Write-Verbose "Unable to query installed packages for $($Manager.DisplayName): $($_.Exception.Message)"
                return @()
            }
        }

        function ConvertFrom-WingetJsonSearchOutput
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
            elseif ($json.PSObject.Properties['Matches'])
            {
                $candidatePackages += @($json.Matches)
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
                $version = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Version', 'LatestVersion', 'CurrentVersion'))
                $source = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('CatalogName', 'Source', 'SourceName'))
                $description = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Description', 'Summary'))

                if ([String]::IsNullOrWhiteSpace($packageName))
                {
                    continue
                }

                $packages += Get-AvailablePackageObject -Manager $Manager -Name $packageName -Id $id -Type 'Package' -Version $version -Source $source -Description $description
            }

            return $packages
        }

        function ConvertFrom-WingetTableSearchOutput
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
            $matchStart = $header.IndexOf('Match')
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

            $versionEnd = if ($matchStart -ge 0) { $matchStart } elseif ($sourceStart -ge 0) { $sourceStart } else { -1 }

            $packages = @()
            for ($i = $headerIndex + 1; $i -lt $lines.Count; $i++)
            {
                $line = $lines[$i]
                if ([String]::IsNullOrWhiteSpace($line) -or $line -match '^-{3,}' -or $line -match '^No package found')
                {
                    continue
                }

                $packageName = Get-WingetTableCell -Line $line -Start $nameStart -End $idStart
                $id = Get-WingetTableCell -Line $line -Start $idStart -End $versionStart
                $version = Get-WingetTableCell -Line $line -Start $versionStart -End $versionEnd
                $source = if ($sourceStart -ge 0) { Get-WingetTableCell -Line $line -Start $sourceStart } else { '' }

                if ([String]::IsNullOrWhiteSpace($packageName))
                {
                    continue
                }

                $packages += Get-AvailablePackageObject -Manager $Manager -Name $packageName -Id $id -Type 'Package' -Version $version -Source $source
            }

            return $packages
        }

        function Find-WingetPackages
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [String]$QueryText
            )

            $packages = @()
            $jsonResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('search', $QueryText, '--accept-source-agreements', '--output', 'json')
            if ($jsonResult.ExitCode -eq 0)
            {
                $jsonPackages = @(ConvertFrom-WingetJsonSearchOutput -Manager $Manager -Output $jsonResult.Output)
                if ($jsonPackages.Count -gt 0)
                {
                    $packages = @($jsonPackages)
                }
                elseif (-not (($jsonResult.Output -join "`n") -match 'Name\s+Id\s+Version'))
                {
                    return @()
                }
            }

            if ($packages.Count -eq 0)
            {
                $tableResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('search', $QueryText, '--accept-source-agreements')
                if ($tableResult.ExitCode -ne 0)
                {
                    $message = ($tableResult.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                    throw "Failed to search winget packages: $message"
                }

                $packages = @(ConvertFrom-WingetTableSearchOutput -Manager $Manager -Output $tableResult.Output)
            }

            if ($packages.Count -eq 0)
            {
                return @()
            }

            return Set-InstalledPackageState -AvailablePackages $packages -InstalledPackages @(Get-InstalledPackagesForSearch -Manager $Manager)
        }

        function ConvertFrom-BrewSearchOutput
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

                $packageName = $trimmedLine
                $source = if ($Type -eq 'Cask') { 'homebrew/cask' } else { 'homebrew/core' }
                $packages += Get-AvailablePackageObject -Manager $Manager -Name $packageName -Id $packageName -Type $Type -Source $source
            }

            return $packages
        }

        function Test-BrewSearchNoResults
        {
            param(
                [Parameter()]
                [Object[]]$Output = @()
            )

            $message = (@($Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' ')
            return $message -match '(?i)\bNo (?:formulae? or casks?|formulae?|casks?) found for\b'
        }

        function Find-BrewPackages
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [String]$QueryText
            )

            $packages = @()

            $formulaResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('search', '--formulae', $QueryText)
            if ($formulaResult.ExitCode -ne 0)
            {
                $message = ($formulaResult.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                if (-not (Test-BrewSearchNoResults -Output $formulaResult.Output))
                {
                    throw "Failed to search Homebrew formulae: $message"
                }
            }
            else
            {
                $packages += ConvertFrom-BrewSearchOutput -Manager $Manager -Type 'Formula' -Output $formulaResult.Output
            }

            $caskResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('search', '--casks', $QueryText)
            if ($caskResult.ExitCode -ne 0)
            {
                $message = ($caskResult.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                if (-not (Test-BrewSearchNoResults -Output $caskResult.Output))
                {
                    throw "Failed to search Homebrew casks: $message"
                }
            }
            else
            {
                $packages += ConvertFrom-BrewSearchOutput -Manager $Manager -Type 'Cask' -Output $caskResult.Output
            }

            if ($packages.Count -eq 0)
            {
                return @()
            }

            return Set-InstalledPackageState -AvailablePackages $packages -InstalledPackages @(Get-InstalledPackagesForSearch -Manager $Manager)
        }

        function Find-AptPackages
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [String]$QueryText
            )

            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('search', '--names-only', $QueryText)
            if ($result.ExitCode -ne 0)
            {
                $message = ($result.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to search APT packages: $message"
            }

            $packages = @()
            $pendingPackage = $null

            foreach ($line in @($result.Output | ForEach-Object { "$_" }))
            {
                $trimmedLine = $line.TrimEnd()
                if ([String]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine -match '^Sorting' -or $trimmedLine -match '^Full Text Search' -or $trimmedLine -match '^WARNING:' -or $trimmedLine -match '^N:')
                {
                    continue
                }

                if ($trimmedLine -match '^(?<Name>[^/\s]+)/(?<Repository>\S+)\s+(?<Version>\S+)\s+(?<Architecture>\S+)(?:\s+\[(?<State>[^\]]+)\])?')
                {
                    if ($pendingPackage)
                    {
                        $packages += $pendingPackage
                    }

                    $packageName = $Matches['Name']
                    $repository = $Matches['Repository']
                    $version = $Matches['Version']
                    $architecture = $Matches['Architecture']
                    $state = if ($Matches['State']) { $Matches['State'] } else { '' }
                    $notes = if ($state -match 'automatic') { 'Automatic' } else { '' }
                    $pendingPackage = Get-AvailablePackageObject -Manager $Manager -Name $packageName -Id $packageName -Type $architecture -Version $version -Source $repository -Installed:($state -match 'installed') -Notes $notes
                    continue
                }

                if ($pendingPackage -and $line -match '^\s{2,}(?<Description>.+)$')
                {
                    $pendingPackage.Description = $Matches.Description.Trim()
                }
            }

            if ($pendingPackage)
            {
                $packages += $pendingPackage
            }

            return $packages
        }

        function Find-ApkPackages
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [String]$QueryText
            )

            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('search', '--description', $QueryText)
            if ($result.ExitCode -ne 0)
            {
                $message = ($result.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to search apk packages: $message"
            }

            $packages = @()
            foreach ($line in @($result.Output | ForEach-Object { "$_" }))
            {
                $trimmedLine = $line.Trim()
                if ([String]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine -match '^WARNING:')
                {
                    continue
                }

                if ($trimmedLine -match '^(?<Token>.+?)\s+--\s+(?<Description>.*?)(?:\s+\[(?<State>[^\]]+)\])?$')
                {
                    $packageInfo = Split-ApkPackageVersion -InstalledToken $Matches.Token.Trim()
                    if ([String]::IsNullOrWhiteSpace($packageInfo.Name))
                    {
                        continue
                    }

                    $packages += Get-AvailablePackageObject -Manager $Manager -Name $packageInfo.Name -Id $packageInfo.Name -Type 'Package' -Version $packageInfo.Version -Source 'apk' -Description $Matches.Description.Trim() -Installed:($Matches.State -match 'installed')
                }
            }

            return $packages
        }

        function Find-RegistryPackages
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [String]$QueryText
            )

            switch ($Manager.Name)
            {
                'winget' { return Find-WingetPackages -Manager $Manager -QueryText $QueryText }
                'brew' { return Find-BrewPackages -Manager $Manager -QueryText $QueryText }
                'apt' { return Find-AptPackages -Manager $Manager -QueryText $QueryText }
                'apk' { return Find-ApkPackages -Manager $Manager -QueryText $QueryText }
                default { throw "Unsupported package manager '$($Manager.Name)'." }
            }
        }

        function Get-InteractiveSearchQuery
        {
            param(
                [Parameter()]
                [String]$CurrentQuery = ''
            )

            if ($QueryReader)
            {
                return ConvertTo-PackageText -Value (& $QueryReader -CurrentQuery $CurrentQuery)
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
                throw 'Interactive package search requires an attached console. Use -NonInteractive with -Query for object output in non-interactive sessions.'
            }

            return ConvertTo-PackageText -Value (Read-Host -Prompt 'Search registry query (blank to exit)')
        }

        function Invoke-SelectedPackageInstallation
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter()]
                [Object[]]$SelectedPackages = @()
            )

            if ($SelectedPackages.Count -eq 0)
            {
                return @()
            }

            $installSystemPackageDependencyPath = Get-DependencyPathIfNeeded -FunctionName 'Install-SystemPackage' -RelativePath 'Install-SystemPackage.ps1'
            if (-not [String]::IsNullOrWhiteSpace($installSystemPackageDependencyPath))
            {
                try
                {
                    . $installSystemPackageDependencyPath
                    Write-Verbose "Loaded Install-SystemPackage from: $installSystemPackageDependencyPath"
                }
                catch
                {
                    throw "Failed to load required dependency 'Install-SystemPackage' from '$installSystemPackageDependencyPath': $($_.Exception.Message)"
                }
            }

            return @($SelectedPackages | Install-SystemPackage -PackageManager $Manager.Name -CommandRunner $CommandRunner)
        }

        function Show-AvailablePackageResults
        {
            param(
                [Parameter()]
                [PSCustomObject[]]$AvailablePackages = @(),

                [Parameter(Mandatory)]
                [String]$QueryText,

                [Parameter()]
                [ScriptBlock]$KeyReader,

                [Parameter()]
                [Int32]$PageSize = 0,

                [Parameter()]
                [Switch]$EnableSelection,

                [Parameter()]
                [Switch]$EnableReturnSelection
            )

            if ($AvailablePackages.Count -eq 0)
            {
                return [PSCustomObject]@{
                    Action = 'Empty'
                    SelectedPackages = @()
                }
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
                    throw 'Interactive package search requires an attached console. Use -NonInteractive with -Query for object output in non-interactive sessions.'
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
                        $reservedRows = 11
                        return [Math]::Min([Math]::Max(1, $windowHeight - $reservedRows), [Math]::Max(1, $ItemCount))
                    }
                }
                catch
                {
                    Write-Verbose "Unable to determine console height for package search browser: $($_.Exception.Message)"
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

            function Get-SelectedPackages
            {
                $selectedPackages = @()
                for ($selectionIndex = 0; $selectionIndex -lt $AvailablePackages.Count; $selectionIndex++)
                {
                    if ($selected[$selectionIndex])
                    {
                        $selectedPackages += $AvailablePackages[$selectionIndex]
                    }
                }

                return @($selectedPackages)
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

                $frameWidth = [Math]::Max(1, [Int32]$pickerRenderState.ConsoleBufferWidth)
                $blankLine = ''.PadRight($frameWidth)
                $frameLines = @(
                    foreach ($line in $Lines)
                    {
                        $text = Get-PickerFrameLineText -Line $line
                        if ($text.Length -ge $frameWidth)
                        {
                            if ($frameWidth -eq 1)
                            {
                                $text = $text.Substring(0, 1)
                            }
                            else
                            {
                                $text = $text.Substring(0, $frameWidth - 1) + '~'
                            }
                        }
                        else
                        {
                            $text = $text.PadRight($frameWidth)
                        }

                        Format-PickerFrameLine -Text $text -ForegroundColor (Get-PickerFrameLineColor -Line $line)
                    }
                )

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
                    $installedStatus = if ($currentPackage.Installed) { 'yes' } else { 'no' }

                    $frameLines = @(
                        "Find-SystemPackage - $($AvailablePackages[0].PackageManagerDisplayName)"
                        ''
                        ('Search: {0}' -f $QueryText)
                        ''
                    )
                    if ($EnableSelection -and $EnableReturnSelection)
                    {
                        $frameLines += 'Spacebar: select  Enter: return selected  I: install current/selected  S: new search  A: toggle all  Arrow keys/Home/End/PgUp/PgDn: navigate  Ctrl+C/Q/Esc: exit'
                    }
                    elseif ($EnableSelection)
                    {
                        $frameLines += 'Spacebar: select  I: install current/selected  S: new search  A: toggle all  Arrow keys/Home/End/PgUp/PgDn: navigate  Ctrl+C/Q/Esc: exit'
                    }
                    else
                    {
                        $frameLines += 'I: install current  S: new search  Arrow keys/Home/End/PgUp/PgDn: navigate  Ctrl+C/Q/Esc: exit'
                    }
                    $frameLines += ''

                    if ($EnableSelection)
                    {
                        $frameLines += ('  {0} {1} {2} {3} {4} {5}' -f 'Sel', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Version' -Width $versionWidth), (Format-PickerCell -Text 'Type' -Width $typeWidth), (Format-PickerCell -Text 'Source' -Width $sourceWidth), 'Inst')
                        $frameLines += ('  {0} {1} {2} {3} {4} {5}' -f '---', ('-' * $nameWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth), '----')
                    }
                    else
                    {
                        $frameLines += ('  {0} {1} {2} {3} {4}' -f (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Version' -Width $versionWidth), (Format-PickerCell -Text 'Type' -Width $typeWidth), (Format-PickerCell -Text 'Source' -Width $sourceWidth), 'Inst')
                        $frameLines += ('  {0} {1} {2} {3} {4}' -f ('-' * $nameWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth), '----')
                    }

                    for ($i = $topIndex; $i -le $bottomIndex; $i++)
                    {
                        $package = $AvailablePackages[$i]
                        $cursorMarker = if ($i -eq $cursor) { '>' } else { ' ' }
                        $installedCell = if ($package.Installed) { 'yes ' } else { 'no  ' }

                        if ($EnableSelection)
                        {
                            $selectedMarker = if ($selected[$i]) { '[x]' } else { '[ ]' }
                            $packageLine = ('{0} {1} {2} {3} {4} {5} {6}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Version -Width $versionWidth), (Format-PickerCell -Text $package.Type -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth), $installedCell)
                        }
                        else
                        {
                            $packageLine = ('{0} {1} {2} {3} {4} {5}' -f $cursorMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Version -Width $versionWidth), (Format-PickerCell -Text $package.Type -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth), $installedCell)
                        }

                        if ($package.Installed)
                        {
                            $frameLines += Format-PickerFrameLine -Text $packageLine -ForegroundColor DarkGray
                        }
                        else
                        {
                            $frameLines += $packageLine
                        }
                    }

                    $frameLines += ''
                    $frameLines += ('Current: {0} | Id: {1} | Installed: {2}' -f $currentPackage.Name, $currentPackage.Id, $installedStatus)
                    $frameLines += ('Description: {0}' -f $currentDescription)
                    if ($EnableSelection)
                    {
                        $frameLines += ''
                        $frameLines += "$(@($selected | Where-Object { $_ }).Count) of $($AvailablePackages.Count) package(s) selected."
                    }

                    Write-PickerFrame -Lines $frameLines

                    $key = & $KeyReader
                    if (Test-PackagePickerCancelKey -KeyInfo $key)
                    {
                        Clear-PickerFrame
                        return [PSCustomObject]@{
                            Action = 'Cancel'
                            SelectedPackages = @()
                        }
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
                        'S'
                        {
                            Clear-PickerFrame
                            return [PSCustomObject]@{
                                Action = 'SearchAgain'
                                SelectedPackages = @()
                            }
                        }
                        'Oem2'
                        {
                            if ($key.KeyChar -eq '/')
                            {
                                Clear-PickerFrame
                                return [PSCustomObject]@{
                                    Action = 'SearchAgain'
                                    SelectedPackages = @()
                                }
                            }
                        }
                        'Spacebar'
                        {
                            if ($EnableSelection)
                            {
                                $selected[$cursor] = -not $selected[$cursor]
                            }
                        }
                        'A'
                        {
                            if ($EnableSelection)
                            {
                                $selectAll = @($selected | Where-Object { -not $_ }).Count -gt 0
                                for ($i = 0; $i -lt $selected.Count; $i++)
                                {
                                    $selected[$i] = $selectAll
                                }
                            }
                        }
                        'Enter'
                        {
                            if (-not $EnableReturnSelection)
                            {
                                break
                            }

                            Clear-PickerFrame
                            return [PSCustomObject]@{
                                Action = 'Return'
                                SelectedPackages = @(Get-SelectedPackages)
                            }
                        }
                        'I'
                        {
                            Clear-PickerFrame
                            $selectedPackages = @()

                            if ($EnableSelection)
                            {
                                $selectedPackages = @(Get-SelectedPackages)
                            }

                            if ($selectedPackages.Count -eq 0)
                            {
                                $selectedPackages = @($AvailablePackages[$cursor])
                            }

                            return [PSCustomObject]@{
                                Action = 'Install'
                                SelectedPackages = @($selectedPackages)
                            }
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
    }

    process
    {
        $manager = Resolve-PackageManager
        Write-Verbose "Using package manager: $($manager.DisplayName) ($($manager.Command))"

        if ($NonInteractive -and $PassThru)
        {
            throw 'PassThru requires interactive package search. Omit -NonInteractive to select packages interactively.'
        }

        $useInteractive = -not $NonInteractive.IsPresent
        if ($useInteractive)
        {
            $queryText = ConvertTo-PackageText -Value $Query
            while ($true)
            {
                if ([String]::IsNullOrWhiteSpace($queryText))
                {
                    $queryText = Get-InteractiveSearchQuery -CurrentQuery $queryText
                }

                if ([String]::IsNullOrWhiteSpace($queryText))
                {
                    return @()
                }

                $packages = @(Find-RegistryPackages -Manager $manager -QueryText $queryText)

                if ($ExcludePackage -and $ExcludePackage.Count -gt 0)
                {
                    $packages = @($packages | Where-Object { -not (Test-PackagePatternMatch -Package $_ -Pattern $ExcludePackage) })
                }

                $packages = @($packages | Sort-Object -Property Name, Id)

                if ($Top -gt 0)
                {
                    $packages = @($packages | Select-Object -First $Top)
                }

                if ($packages.Count -eq 0)
                {
                    Write-Host ("No remote packages matched '{0}'." -f $queryText)
                    $queryText = Get-InteractiveSearchQuery -CurrentQuery $queryText
                    continue
                }

                $browserResult = Show-AvailablePackageResults -AvailablePackages $packages -QueryText $queryText -KeyReader $KeyReader -PageSize $PickerPageSize -EnableSelection -EnableReturnSelection:$PassThru.IsPresent
                if ($browserResult.Action -eq 'Return')
                {
                    return @($browserResult.SelectedPackages)
                }

                if ($browserResult.Action -eq 'Install')
                {
                    return @(Invoke-SelectedPackageInstallation -Manager $manager -SelectedPackages $browserResult.SelectedPackages)
                }

                if ($browserResult.Action -eq 'SearchAgain')
                {
                    $queryText = Get-InteractiveSearchQuery -CurrentQuery $queryText
                    continue
                }

                return @()
            }
        }

        if ([String]::IsNullOrWhiteSpace($Query))
        {
            throw 'Query is required when -NonInteractive is used.'
        }

        $queryText = $Query.Trim()
        if ([String]::IsNullOrWhiteSpace($queryText))
        {
            throw 'Query cannot be empty.'
        }

        $packages = @(Find-RegistryPackages -Manager $manager -QueryText $queryText)

        if ($ExcludePackage -and $ExcludePackage.Count -gt 0)
        {
            $packages = @($packages | Where-Object { -not (Test-PackagePatternMatch -Package $_ -Pattern $ExcludePackage) })
        }

        $packages = @($packages | Sort-Object -Property Name, Id)

        if ($Top -gt 0)
        {
            return @($packages | Select-Object -First $Top)
        }

        return $packages
    }
}
