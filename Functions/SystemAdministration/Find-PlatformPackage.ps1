function Find-PlatformPackage
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
        current package or the selected packages. Use -PassThru to return the selected records,
        or the current package if nothing is selected, instead of installing them.

        Use -NonInteractive to return search results as PowerShell objects so they can be
        filtered, formatted, or piped into Install-PlatformPackage. Use -Top to cap broad
        searches and -ExcludePackage to remove unwanted matches from the normalized results.

    .PARAMETER Query
        Search text sent to the selected package manager.

    .PARAMETER NonInteractive
        Returns normalized package records without opening the interactive remote package
        search UI. Query is required in non-interactive mode.

    .PARAMETER PassThru
        Allows packages to be selected in the interactive UI and returns the selected package
        records when Enter is pressed. If nothing is selected, Enter returns the current
        package record.

    .PARAMETER ExcludePackage
        Optional package names or wildcard patterns to exclude from the normalized results.
        Matches package Name or Id.

    .PARAMETER Top
        Maximum number of search results to return after normalization and sorting. Use 0
        to return all matching results.

    .PARAMETER FilterSource
        Sets the initial source filter in the interactive result picker. When specified,
        the picker opens showing only packages from this source. Press S in the picker to
        cycle through available sources. Press / to start a new search.

    .EXAMPLE
        PS > Find-PlatformPackage -Query git

        Opens the interactive remote package search UI seeded with the git query. Press I
        to install the current package or the selected packages.

    .EXAMPLE
        PS > Find-PlatformPackage -NonInteractive -Query 'visual studio code'

        Searches for packages matching the provided query text and returns objects.

    .EXAMPLE
        PS > Find-PlatformPackage -NonInteractive -Query git -ExcludePackage 'git-lfs'

        Searches for git packages and excludes git-lfs from the returned results.

    .EXAMPLE
        PS > Find-PlatformPackage -NonInteractive -Query git -Top 10

        Returns at most 10 normalized results.

    .EXAMPLE
        PS > Find-PlatformPackage -NonInteractive -Query docker | Format-Table Name, Version, Source

        Searches for docker packages and formats the results.

    .EXAMPLE
        PS > Find-PlatformPackage -Query git -PackageManager winget

        Opens the interactive search UI using winget.

    .EXAMPLE
        PS > Find-PlatformPackage -Query git -PackageManager brew

        Opens the interactive search UI using Homebrew.

    .EXAMPLE
        PS > Find-PlatformPackage -Query openssl -PackageManager apt

        Opens the interactive search UI using apt.

    .EXAMPLE
        PS > Find-PlatformPackage -Query bash -PackageManager apk

        Opens the interactive search UI using apk.

    .EXAMPLE
        PS > Find-PlatformPackage -Query nodejs -Verbose

        Opens the interactive search UI for nodejs and writes the detected package manager
        to verbose output.

    .EXAMPLE
        PS > Find-PlatformPackage

        Opens the interactive remote package search UI and prompts for a query.

    .EXAMPLE
        PS > Find-PlatformPackage -PassThru

        Opens the interactive UI, lets you select packages with Space, and returns
        the selected package records when Enter is pressed.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Find-PlatformPackage.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Find-PlatformPackage.ps1
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

        [Parameter()]
        [String]$FilterSource = '',

        [Parameter(DontShow = $true)]
        [ValidateSet('Auto', 'winget', 'brew', 'apt', 'apk')]
        [String]$PackageManager = 'Auto',

        [Parameter(DontShow = $true)]
        [Switch]$SkipDescriptionEnrichment,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$CommandRunner,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$KeyReader,

        [Parameter(DontShow = $true)]
        [Switch]$TreatKeyReaderAsConsoleKeyReader,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$TerminalEchoController,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$QueryReader,

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
                [String]$Publisher,

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
                Publisher = if (-not [String]::IsNullOrWhiteSpace($Publisher)) { $Publisher } elseif ($Manager.Name -eq 'brew') { 'Homebrew' } elseif ($Manager.Name -eq 'apk') { 'Alpine' } elseif ($Manager.Name -eq 'apt' -and -not [String]::IsNullOrWhiteSpace($Source)) { $Source } elseif ($Manager.Name -eq 'apt') { 'APT' } elseif ($Manager.Name -eq 'winget' -and -not [String]::IsNullOrWhiteSpace($Source)) { $Source } else { '' }
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

        function Test-WingetNoPackageFoundOutput
        {
            param(
                [Parameter()]
                [Object[]]$Output = @()
            )

            $text = (@($Output | ForEach-Object { "$_" }) -join "`n")
            return $text -match '(?im)\bNo package found(?: matching input criteria)?\.?'
        }

        function Test-WingetProgressOutputLine
        {
            param(
                [Parameter()]
                [String]$Line = ''
            )

            $trimmedLine = $Line.Trim()
            if ([String]::IsNullOrWhiteSpace($trimmedLine))
            {
                return $true
            }

            if ($trimmedLine -match '[\u2580-\u259F]')
            {
                return $true
            }

            if ($trimmedLine -match '^[-\\/|\s]+$' -and $trimmedLine -match '[-\\/|]')
            {
                return $true
            }

            if ($trimmedLine -match '^\d{1,3}%$')
            {
                return $true
            }

            return $trimmedLine -match '^\d+(?:\.\d+)?\s*(?:B|KB|MB|GB|KiB|MiB|GiB)\s*/\s*\d+(?:\.\d+)?\s*(?:B|KB|MB|GB|KiB|MiB|GiB)$'
        }

        function Get-WingetCommandFailureMessage
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

            $messageLines = New-Object 'System.Collections.Generic.List[String]'
            foreach ($item in @($Output))
            {
                $text = "$item" -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
                foreach ($line in @($text -split '\r?\n|\r'))
                {
                    $normalizedLine = ($line -replace '[\x00-\x1F\x7F]', ' ').Trim()
                    $normalizedLine = $normalizedLine -replace '\s{2,}', ' '
                    if (Test-WingetProgressOutputLine -Line $normalizedLine)
                    {
                        continue
                    }

                    if (-not $messageLines.Contains($normalizedLine))
                    {
                        $messageLines.Add($normalizedLine)
                    }
                }
            }

            $message = ($messageLines -join ' ').Trim()
            if (-not [String]::IsNullOrWhiteSpace($message))
            {
                return $message
            }

            $commandText = "$Command $($Arguments -join ' ')".Trim()
            return "$commandText failed with exit code $ExitCode."
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

            function Get-PackageFromInstalledLookupValue
            {
                param(
                    [Parameter()]
                    [String]$Value
                )

                $key = Get-PackageLookupKey -Type $Package.Type -Value $Value
                if (-not [String]::IsNullOrWhiteSpace($key) -and $Lookup.ContainsKey($key))
                {
                    return $Lookup[$key]
                }

                if (-not ([String]::IsNullOrWhiteSpace($Package.Type) -or $Package.Type -eq 'Package'))
                {
                    return $null
                }

                $fallbackKey = Get-PackageLookupKey -Value $Value
                if (-not [String]::IsNullOrWhiteSpace($fallbackKey) -and $Lookup.ContainsKey($fallbackKey))
                {
                    return $Lookup[$fallbackKey]
                }

                return $null
            }

            foreach ($idValue in @($Package.Id | Where-Object { -not [String]::IsNullOrWhiteSpace("$_") } | ForEach-Object { "$_".Trim() } | Select-Object -Unique))
            {
                $installedPackage = Get-PackageFromInstalledLookupValue -Value $idValue
                if ($null -ne $installedPackage)
                {
                    return $installedPackage
                }
            }

            foreach ($nameValue in @($Package.Name | Where-Object { -not [String]::IsNullOrWhiteSpace("$_") } | ForEach-Object { "$_".Trim() } | Select-Object -Unique))
            {
                $installedPackage = Get-PackageFromInstalledLookupValue -Value $nameValue
                if ($null -ne $installedPackage)
                {
                    if (
                        $Package.PackageManager -eq 'winget' -and
                        -not [String]::IsNullOrWhiteSpace($Package.Id) -and
                        -not [String]::IsNullOrWhiteSpace($installedPackage.Id) -and
                        $Package.Id.Trim() -ne $installedPackage.Id.Trim()
                    )
                    {
                        continue
                    }

                    return $installedPackage
                }
            }

            return $null
        }

        function Resolve-InstalledPackageState
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
                $getPlatformPackageDependencyPath = Get-DependencyPathIfNeeded -FunctionName 'Get-PlatformPackage' -RelativePath 'Get-PlatformPackage.ps1'
            }
            catch
            {
                Write-Verbose "Unable to resolve Get-PlatformPackage for installed-state detection: $($_.Exception.Message)"
                return @()
            }

            if (-not [String]::IsNullOrWhiteSpace($getPlatformPackageDependencyPath))
            {
                try
                {
                    . $getPlatformPackageDependencyPath
                    Write-Verbose "Loaded Get-PlatformPackage from: $getPlatformPackageDependencyPath"
                }
                catch
                {
                    Write-Verbose "Unable to load Get-PlatformPackage for installed-state detection: $($_.Exception.Message)"
                    return @()
                }
            }

            try
            {
                return @(Get-PlatformPackage -PackageManager $Manager.Name -SkipDescriptionEnrichment -CommandRunner $CommandRunner)
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
                $publisher = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Publisher', 'PublisherName', 'Author'))
                $description = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $package -PropertyName @('Description', 'ShortDescription', 'Summary', 'PackageDescription'))

                if ([String]::IsNullOrWhiteSpace($packageName))
                {
                    continue
                }

                $packages += Get-AvailablePackageObject -Manager $Manager -Name $packageName -Id $id -Type 'Package' -Version $version -Source $source -Publisher $publisher -Description $description
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
            elseif (Test-WingetNoPackageFoundOutput -Output $jsonResult.Output)
            {
                return @()
            }

            if ($packages.Count -eq 0)
            {
                $tableArguments = @('search', $QueryText, '--accept-source-agreements')
                $tableResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments $tableArguments
                if ($tableResult.ExitCode -ne 0)
                {
                    if (Test-WingetNoPackageFoundOutput -Output $tableResult.Output)
                    {
                        return @()
                    }

                    $message = Get-WingetCommandFailureMessage -Command $Manager.Command -Arguments $tableArguments -ExitCode $tableResult.ExitCode -Output $tableResult.Output
                    throw "Failed to search winget packages: $message"
                }

                $packages = @(ConvertFrom-WingetTableSearchOutput -Manager $Manager -Output $tableResult.Output)
            }

            if ($packages.Count -eq 0)
            {
                return @()
            }

            return Resolve-InstalledPackageState -AvailablePackages $packages -InstalledPackages @(Get-InstalledPackagesForSearch -Manager $Manager)
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

            $packages = @(Resolve-BrewPackageDescriptions -Manager $Manager -Packages $packages)

            return Resolve-InstalledPackageState -AvailablePackages $packages -InstalledPackages @(Get-InstalledPackagesForSearch -Manager $Manager)
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

                    $packages += Get-AvailablePackageObject -Manager $Manager -Name $packageInfo.Name -Id $packageInfo.Name -Type 'Package' -Version $packageInfo.Version -Source 'apk' -Publisher 'Alpine' -Description $Matches.Description.Trim() -Installed:($Matches.State -match 'installed')
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

            while ($true)
            {
                $oldPromptColor = [Console]::ForegroundColor
                [Console]::Write('Search registry query ')
                [Console]::ForegroundColor = [ConsoleColor]::DarkGray
                [Console]::Write('(blank to exit, ? for help)')
                [Console]::ForegroundColor = $oldPromptColor
                [Console]::Write(': ')
                $value = ConvertTo-PackageText -Value ([Console]::ReadLine())
                if ($value -eq '?')
                {
                    Write-Host 'Enter a package name, package id, or registry search term.' -ForegroundColor White
                    Write-Host 'Blank input exits the search workflow.' -ForegroundColor White
                    Write-Host 'Use / from the result picker to start another search.' -ForegroundColor White
                    continue
                }

                return $value
            }
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

            $installPlatformPackageDependencyPath = Get-DependencyPathIfNeeded -FunctionName 'Install-PlatformPackage' -RelativePath 'Install-PlatformPackage.ps1'
            if (-not [String]::IsNullOrWhiteSpace($installPlatformPackageDependencyPath))
            {
                try
                {
                    . $installPlatformPackageDependencyPath
                    Write-Verbose "Loaded Install-PlatformPackage from: $installPlatformPackageDependencyPath"
                }
                catch
                {
                    throw "Failed to load required dependency 'Install-PlatformPackage' from '$installPlatformPackageDependencyPath': $($_.Exception.Message)"
                }
            }

            return @($SelectedPackages | Install-PlatformPackage -PackageManager $Manager.Name -CommandRunner $CommandRunner)
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
                [Switch]$EnableReturnSelection,

                [Parameter()]
                [String]$SourceFilter = '',

                [Parameter()]
                [Switch]$TreatKeyReaderAsConsoleKeyReader,

                [Parameter()]
                [ScriptBlock]$TerminalEchoController,

                [Parameter()]
                [Switch]$ReturnToPlatformPackageManagerOnBackKey
            )

            if ($AvailablePackages.Count -eq 0)
            {
                return [PSCustomObject]@{
                    Action = 'Empty'
                    SelectedPackages = @()
                }
            }

            $allPackages = $AvailablePackages
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

            $visiblePackages = @(
                if ($availableSources[$sourceFilterIndex] -eq 'All')
                {
                    $allPackages
                }
                else
                {
                    $allPackages | Where-Object { $_.Source -eq $availableSources[$sourceFilterIndex] }
                }
            )

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
                    throw 'Interactive package search requires an attached console. Use -NonInteractive with -Query for object output in non-interactive sessions.'
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
                return @($allPackages | Where-Object { $selectedKeys.Contains((Get-PackagePickerKey -Package $_)) })
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
                    [Switch]$IncludesSelection
                )

                $prefixWidth = if ($IncludesSelection) { 6 } else { 2 }
                return $prefixWidth + [Int32]$ColumnWidths.Name + 1 + [Int32]$ColumnWidths.Id + 1 + [Int32]$ColumnWidths.Version + 1 + [Int32]$ColumnWidths.Type + 1 + [Int32]$ColumnWidths.Source + 1 + 4
            }

            function Compress-PackagePickerTableWidths
            {
                param(
                    [Parameter(Mandatory)]
                    [PSCustomObject]$ColumnWidths,

                    [Parameter(Mandatory)]
                    [Int32]$MaximumWidth,

                    [Parameter()]
                    [Switch]$IncludesSelection
                )

                $minimumWidths = @{
                    Name = 12
                    Id = 14
                    Version = 8
                    Type = 3
                    Source = 5
                }
                $shrinkOrder = @('Id', 'Name', 'Version', 'Source', 'Type')

                while ((Get-PackagePickerTableLineWidth -ColumnWidths $ColumnWidths -IncludesSelection:$IncludesSelection.IsPresent) -gt $MaximumWidth)
                {
                    $shrunk = $false
                    foreach ($columnName in $shrinkOrder)
                    {
                        if ([Int32]$ColumnWidths.$columnName -gt [Int32]$minimumWidths[$columnName])
                        {
                            $ColumnWidths.$columnName = [Int32]$ColumnWidths.$columnName - 1
                            $shrunk = $true
                            if ((Get-PackagePickerTableLineWidth -ColumnWidths $ColumnWidths -IncludesSelection:$IncludesSelection.IsPresent) -le $MaximumWidth)
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

            $pickerFrameWidth = Get-PackagePickerFrameWidth
            $columnWidths = [PSCustomObject]@{
                Name = Get-PackagePickerTextMaximum -Values @($allPackages | ForEach-Object { $_.Name }) -Minimum 12 -Maximum 30
                Id = Get-PackagePickerTextMaximum -Values @($allPackages | ForEach-Object { $_.Id }) -Minimum 14 -Maximum 32
                Version = Get-PackagePickerTextMaximum -Values @($allPackages | ForEach-Object { $_.Version }) -Minimum 8 -Maximum 16
                Type = Get-PackagePickerTextMaximum -Values @($allPackages | ForEach-Object { Get-PackageTypeDisplay -Type $_.Type }) -Minimum 3 -Maximum 7
                Source = Get-PackagePickerTextMaximum -Values @($allPackages | ForEach-Object { $_.Source }) -Minimum 5 -Maximum 32
            }
            $columnWidths = Compress-PackagePickerTableWidths -ColumnWidths $columnWidths -MaximumWidth $pickerFrameWidth -IncludesSelection:$EnableSelection.IsPresent
            $nameWidth = [Int32]$columnWidths.Name
            $idWidth = [Int32]$columnWidths.Id
            $versionWidth = [Int32]$columnWidths.Version
            $typeWidth = [Int32]$columnWidths.Type
            $sourceWidth = [Int32]$columnWidths.Source
            $pageSize = Get-PackagePickerPageSize -RequestedPageSize $PageSize -ItemCount $allPackages.Count

            $selectedKeys = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
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
                Write-Host 'Find-PlatformPackage Help' -ForegroundColor Cyan
                Write-Host ''
                Write-Host 'Navigation' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'Up/Down' -Description 'move one package'
                Write-PackagePickerHelpItem -Shortcut 'PageUp/PageDown' -Description 'move one page'
                Write-PackagePickerHelpItem -Shortcut 'Home/End' -Description 'move to the first or last package'

                Write-Host ''
                Write-Host 'Search Actions' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut '/' -Description 'start a new search'
                Write-PackagePickerHelpItem -Shortcut 'I' -Description 'install selected packages, or the current package if none are selected'
                Write-PackagePickerHelpItem -Shortcut 'V' -Description 'load a missing winget description when available'
                Write-PackagePickerHelpItem -Shortcut 'Q, Esc, or Ctrl+C' -Description 'exit the search browser'
                Write-PackagePickerHelpItem -Shortcut '?' -Description 'show this help'

                if ($hasSourceFilter)
                {
                    Write-Host ''
                    Write-Host 'Source Filter' -ForegroundColor White
                    Write-PackagePickerHelpItem -Shortcut 'S' -Description "cycle source: $($availableSources -join ' | ')"
                }

                if ($EnableSelection)
                {
                    Write-Host ''
                    Write-Host 'Selection' -ForegroundColor White
                    Write-PackagePickerHelpItem -Shortcut 'Space' -Description 'select or clear the current package'
                    Write-PackagePickerHelpItem -Shortcut 'A' -Description 'select or clear all visible packages'
                }

                if ($EnableReturnSelection)
                {
                    Write-PackagePickerHelpItem -Shortcut 'Enter' -Description 'return selected packages, or the current package if none are selected'
                }

                Write-Host ''
                Write-Host 'Press any key to return to the picker. Q/Esc/Ctrl+C exits.' -ForegroundColor DarkGray

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
                    $currentDescription = if ($null -eq $currentPackage -or [String]::IsNullOrWhiteSpace($currentPackage.Description))
                    {
                        if ($isCurrentWingetDescriptionPending)
                        {
                            'retrieving description...'
                        }
                        elseif ($null -ne $currentPackage -and $currentPackage.PackageManager -eq 'winget' -and -not [String]::IsNullOrWhiteSpace($currentPackageLookupKey))
                        {
                            if ($wingetDescriptionAttempted.ContainsKey($currentPackageLookupKey)) { 'description unavailable' } else { '<press V to load>' }
                        }
                        else
                        {
                            'n/a'
                        }
                    }
                    else
                    {
                        $currentPackage.Description
                    }
                    $installedStatus = if ($null -ne $currentPackage -and $currentPackage.Installed) { 'yes' } else { 'no' }

                    $sourceHint = if ($hasSourceFilter) { "S: [$($availableSources[$sourceFilterIndex])]  " } else { '' }
                    $sourceSummary = if ($hasSourceFilter) { "source: $($availableSources[$sourceFilterIndex])" } else { '' }
                    $selectedSummary = if ($EnableSelection) { $selectedKeys.Count } else { -1 }
                    $frameLines = @(
                        (Format-PickerFrameLine -Text "Find-PlatformPackage - $($allPackages[0].PackageManagerDisplayName)" -ForegroundColor Cyan)
                        (Format-PickerFrameLine -Text ('Search: {0}' -f $QueryText) -ForegroundColor DarkGray)
                        (Format-PickerFrameLine -Text (Get-PickerViewportSummary -TopIndex $topIndex -BottomIndex $bottomIndex -VisibleCount $visiblePackages.Count -TotalCount $allPackages.Count -SelectedCount $selectedSummary -FilterText $sourceSummary) -ForegroundColor White)
                        ''
                    )
                    if ($EnableSelection -and $EnableReturnSelection)
                    {
                        $frameLines += Format-PickerFrameLine -Text 'Keys: Space select  Enter return  I install  V details  A toggle all' -ForegroundColor DarkGray
                    }
                    elseif ($EnableSelection)
                    {
                        $frameLines += Format-PickerFrameLine -Text 'Keys: Space select  I install  V details  A toggle all' -ForegroundColor DarkGray
                    }
                    else
                    {
                        $frameLines += Format-PickerFrameLine -Text 'Keys: I install current  V details' -ForegroundColor DarkGray
                    }
                    $frameLines += Format-PickerFrameLine -Text "Nav: ${sourceHint}/ search  Home/End/PgUp/PgDn  ?: help  Q/Esc/Ctrl+C exit" -ForegroundColor DarkGray
                    if ($ReturnToPlatformPackageManagerOnBackKey)
                    {
                        $frameLines += Format-PickerFrameLine -Text 'Backspace/Delete: manager menu' -ForegroundColor DarkGray
                    }
                    $frameLines += ''

                    if ($visiblePackages.Count -eq 0)
                    {
                        $frameLines += Format-PickerFrameLine -Text '  (No packages match this source filter. Press S to cycle.)' -ForegroundColor DarkYellow
                        Write-PickerFrame -Lines $frameLines

                        $key = & $KeyReader
                        if (Test-PackagePickerManagerBackKey -KeyInfo $key)
                        {
                            Clear-PickerFrame
                            return [PSCustomObject]@{
                                Action = 'Cancel'
                                SelectedPackages = @()
                            }
                        }

                        if (Test-PackagePickerCancelKey -KeyInfo $key)
                        {
                            Clear-PickerFrame
                            return [PSCustomObject]@{
                                Action = 'Cancel'
                                SelectedPackages = @()
                            }
                        }

                        if (Test-PackagePickerHelpKey -KeyInfo $key)
                        {
                            if (Show-PackagePickerHelp)
                            {
                                Clear-PickerFrame
                                return [PSCustomObject]@{
                                    Action = 'Cancel'
                                    SelectedPackages = @()
                                }
                            }

                            continue
                        }

                        if ($hasSourceFilter -and $key.Key -eq [ConsoleKey]::S)
                        {
                            $sourceFilterIndex = ($sourceFilterIndex + 1) % $availableSources.Count
                            $visiblePackages = @(
                                if ($availableSources[$sourceFilterIndex] -eq 'All')
                                {
                                    $allPackages
                                }
                                else
                                {
                                    $allPackages | Where-Object { $_.Source -eq $availableSources[$sourceFilterIndex] }
                                }
                            )
                            $cursor = 0
                            $topIndex = 0
                            continue
                        }

                        if ($key.Key -eq [ConsoleKey]::Oem2 -and $key.KeyChar -eq '/')
                        {
                            Clear-PickerFrame
                            return [PSCustomObject]@{
                                Action = 'SearchAgain'
                                SelectedPackages = @()
                            }
                        }

                        continue
                    }

                    if ($EnableSelection)
                    {
                        $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4} {5} {6}' -f 'Sel', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Id' -Width $idWidth), (Format-PickerCell -Text 'Ver' -Width $versionWidth), (Format-PickerCell -Text 'Typ' -Width $typeWidth), (Format-PickerCell -Text 'Src' -Width $sourceWidth), 'Inst') -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('- {0} {1} {2} {3} {4} {5} {6}' -f '---', ('-' * $nameWidth), ('-' * $idWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth), '----') -ForegroundColor DarkGray
                    }
                    else
                    {
                        $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4} {5}' -f (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Id' -Width $idWidth), (Format-PickerCell -Text 'Ver' -Width $versionWidth), (Format-PickerCell -Text 'Typ' -Width $typeWidth), (Format-PickerCell -Text 'Src' -Width $sourceWidth), 'Inst') -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('- {0} {1} {2} {3} {4} {5}' -f ('-' * $nameWidth), ('-' * $idWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth), '----') -ForegroundColor DarkGray
                    }

                    for ($i = $topIndex; $i -le $bottomIndex; $i++)
                    {
                        $package = $visiblePackages[$i]
                        $pkgKey = Get-PackagePickerKey -Package $package
                        $cursorMarker = if ($i -eq $cursor) { '>' } else { ' ' }
                        $installedCell = if ($package.Installed) { 'yes ' } else { 'no  ' }

                        if ($EnableSelection)
                        {
                            $selectedMarker = if ($selectedKeys.Contains($pkgKey)) { '[x]' } else { '[ ]' }
                            $packageLine = ('{0} {1} {2} {3} {4} {5} {6} {7}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Id -Width $idWidth), (Format-PickerCell -Text $package.Version -Width $versionWidth), (Format-PickerCell -Text (Get-PackageTypeDisplay -Type $package.Type) -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth), $installedCell)
                        }
                        else
                        {
                            $packageLine = ('{0} {1} {2} {3} {4} {5} {6}' -f $cursorMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Id -Width $idWidth), (Format-PickerCell -Text $package.Version -Width $versionWidth), (Format-PickerCell -Text (Get-PackageTypeDisplay -Type $package.Type) -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth), $installedCell)
                        }

                        if ($i -eq $cursor -and $EnableSelection -and $selectedKeys.Contains($pkgKey))
                        {
                            $frameLines += Format-PickerFrameLine -Text $packageLine -ForegroundColor Green
                        }
                        elseif ($i -eq $cursor)
                        {
                            $frameLines += Format-PickerFrameLine -Text $packageLine -ForegroundColor Cyan
                        }
                        elseif ($EnableSelection -and $selectedKeys.Contains($pkgKey))
                        {
                            $frameLines += Format-PickerFrameLine -Text $packageLine -ForegroundColor Green
                        }
                        elseif ($package.Installed)
                        {
                            $frameLines += Format-PickerFrameLine -Text $packageLine -ForegroundColor DarkGray
                        }
                        else
                        {
                            $frameLines += $packageLine
                        }
                    }

                    $frameLines += ''
                    $currentPublisher = if ([String]::IsNullOrWhiteSpace($currentPackage.Publisher)) { 'n/a' } else { $currentPackage.Publisher }
                    $currentSource = if ([String]::IsNullOrWhiteSpace($currentPackage.Source)) { 'n/a' } else { $currentPackage.Source }
                    $frameLines += Format-PickerFrameLine -Text ('Current: {0}' -f $currentPackage.Name) -ForegroundColor DarkGray
                    $frameLines += Format-PickerFrameLine -Text ('Id: {0} | Source: {1} | Publisher: {2} | Installed: {3}' -f $currentPackage.Id, $currentSource, $currentPublisher, $installedStatus) -ForegroundColor DarkGray
                    $frameLines += Format-PickerFrameLine -Text ('Description: {0}' -f $currentDescription) -ForegroundColor DarkGray
                    if ($EnableSelection)
                    {
                        $frameLines += ''
                        $countText = if ($hasSourceFilter -and $availableSources[$sourceFilterIndex] -ne 'All')
                        {
                            "$($selectedKeys.Count) of $($allPackages.Count) selected  |  $($visiblePackages.Count) of $($allPackages.Count) visible (filter: $($availableSources[$sourceFilterIndex]))"
                        }
                        else
                        {
                            "$($selectedKeys.Count) of $($allPackages.Count) package(s) selected."
                        }
                        $frameLines += Format-PickerFrameLine -Text $countText -ForegroundColor White
                    }

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
                        return [PSCustomObject]@{
                            Action = 'Cancel'
                            SelectedPackages = @()
                        }
                    }

                    if (Test-PackagePickerCancelKey -KeyInfo $key)
                    {
                        Clear-PickerFrame
                        return [PSCustomObject]@{
                            Action = 'Cancel'
                            SelectedPackages = @()
                        }
                    }

                    if (Test-PackagePickerHelpKey -KeyInfo $key)
                    {
                        if (Show-PackagePickerHelp)
                        {
                            Clear-PickerFrame
                            return [PSCustomObject]@{
                                Action = 'Cancel'
                                SelectedPackages = @()
                            }
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
                        'S'
                        {
                            if ($hasSourceFilter)
                            {
                                $sourceFilterIndex = ($sourceFilterIndex + 1) % $availableSources.Count
                                $visiblePackages = @(
                                    if ($availableSources[$sourceFilterIndex] -eq 'All')
                                    {
                                        $allPackages
                                    }
                                    else
                                    {
                                        $allPackages | Where-Object { $_.Source -eq $availableSources[$sourceFilterIndex] }
                                    }
                                )
                                $cursor = 0
                                $topIndex = 0
                            }
                            else
                            {
                                Clear-PickerFrame
                                return [PSCustomObject]@{
                                    Action = 'SearchAgain'
                                    SelectedPackages = @()
                                }
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
                                $pkgKey = Get-PackagePickerKey -Package $visiblePackages[$cursor]
                                if ($selectedKeys.Contains($pkgKey)) { [void]$selectedKeys.Remove($pkgKey) } else { [void]$selectedKeys.Add($pkgKey) }
                            }
                        }
                        'A'
                        {
                            if ($EnableSelection)
                            {
                                $allVisibleSelected = @($visiblePackages | Where-Object { $selectedKeys.Contains((Get-PackagePickerKey -Package $_)) }).Count -eq $visiblePackages.Count
                                foreach ($pkg in $visiblePackages)
                                {
                                    $pkgKey = Get-PackagePickerKey -Package $pkg
                                    if ($allVisibleSelected) { [void]$selectedKeys.Remove($pkgKey) } else { [void]$selectedKeys.Add($pkgKey) }
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
                        'Enter'
                        {
                            if (-not $EnableReturnSelection)
                            {
                                break
                            }

                            $selectedPackages = @(Get-SelectedPackages)
                            if ($selectedPackages.Count -eq 0)
                            {
                                $selectedPackages = @($visiblePackages[$cursor])
                            }

                            Clear-PickerFrame
                            return [PSCustomObject]@{
                                Action = 'Return'
                                SelectedPackages = @($selectedPackages)
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
                                $selectedPackages = @($visiblePackages[$cursor])
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
                    Write-Host ("No remote packages matched '{0}'." -f $queryText) -ForegroundColor White
                    $queryText = Get-InteractiveSearchQuery -CurrentQuery $queryText
                    continue
                }

                $browserResult = Show-AvailablePackageResults -AvailablePackages $packages -QueryText $queryText -KeyReader $KeyReader -PageSize $PickerPageSize -EnableSelection -EnableReturnSelection:$PassThru.IsPresent -SourceFilter $FilterSource -TreatKeyReaderAsConsoleKeyReader:$TreatKeyReaderAsConsoleKeyReader -TerminalEchoController $TerminalEchoController -ReturnToPlatformPackageManagerOnBackKey:$ReturnToPlatformPackageManagerOnBackKey
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

        if ($manager.Name -eq 'winget' -and -not $SkipDescriptionEnrichment)
        {
            $packages = @(Resolve-WingetPackageDescriptions -Manager $manager -Packages $packages)
        }

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
