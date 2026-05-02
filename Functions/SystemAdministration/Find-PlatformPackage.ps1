function Find-PlatformPackage
{
    <#
    .SYNOPSIS
        Searches native platform package registries.

    .DESCRIPTION
        Searches the supported native package registry for the current platform and returns
        normalized package records. Supported package managers are winget on Windows,
        Homebrew on macOS, and apt or apk on Linux.

        Search results are returned as PowerShell objects so they can be filtered, formatted,
        or piped into Install-PlatformPackage. Use -Top to cap broad searches and
        -ExcludePackage to remove unwanted matches from the normalized results.

    .PARAMETER Query
        Search text sent to the selected package manager.

    .PARAMETER ExcludePackage
        Optional package names or wildcard patterns to exclude from the normalized results.
        Matches package Name or Id.

    .PARAMETER Top
        Maximum number of search results to return after normalization and sorting. Use 0
        to return all matching results.

    .EXAMPLE
        PS > Find-PlatformPackage -Query git

        Searches the detected native package registry for git.

    .EXAMPLE
        PS > Find-PlatformPackage -Query 'visual studio code'

        Searches for packages matching the provided query text.

    .EXAMPLE
        PS > Find-PlatformPackage -Query git -ExcludePackage 'git-lfs'

        Searches for git packages and excludes git-lfs from the returned results.

    .EXAMPLE
        PS > Find-PlatformPackage -Query git -Top 10

        Returns at most 10 normalized results.

    .EXAMPLE
        PS > Find-PlatformPackage -Query docker | Format-Table Name, Version, Source

        Searches for docker packages and formats the results.

    .EXAMPLE
        PS > Find-PlatformPackage -Query git -PackageManager winget

        Searches for packages using winget.

    .EXAMPLE
        PS > Find-PlatformPackage -Query git -PackageManager brew

        Searches for packages using Homebrew.

    .EXAMPLE
        PS > Find-PlatformPackage -Query openssl -PackageManager apt

        Searches for packages using apt.

    .EXAMPLE
        PS > Find-PlatformPackage -Query bash -PackageManager apk

        Searches for packages using apk.

    .EXAMPLE
        PS > Find-PlatformPackage -Query nodejs -Verbose

        Searches for nodejs and writes the detected package manager to verbose output.

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
        [Parameter(Mandatory, Position = 0)]
        [Alias('Name', 'PackageName', 'Search')]
        [ValidateNotNullOrEmpty()]
        [String]$Query,

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

            $jsonResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('search', $QueryText, '--accept-source-agreements', '--output', 'json')
            if ($jsonResult.ExitCode -eq 0)
            {
                $jsonPackages = @(ConvertFrom-WingetJsonSearchOutput -Manager $Manager -Output $jsonResult.Output)
                if ($jsonPackages.Count -gt 0)
                {
                    return $jsonPackages
                }

                if (-not (($jsonResult.Output -join "`n") -match 'Name\s+Id\s+Version'))
                {
                    return @()
                }
            }

            $tableResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('search', $QueryText, '--accept-source-agreements')
            if ($tableResult.ExitCode -ne 0)
            {
                $message = ($tableResult.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to search winget packages: $message"
            }

            return ConvertFrom-WingetTableSearchOutput -Manager $Manager -Output $tableResult.Output
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
                throw "Failed to search Homebrew formulae: $message"
            }

            $packages += ConvertFrom-BrewSearchOutput -Manager $Manager -Type 'Formula' -Output $formulaResult.Output

            $caskResult = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments @('search', '--casks', $QueryText)
            if ($caskResult.ExitCode -ne 0)
            {
                $message = ($caskResult.Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
                throw "Failed to search Homebrew casks: $message"
            }

            $packages += ConvertFrom-BrewSearchOutput -Manager $Manager -Type 'Cask' -Output $caskResult.Output

            return $packages
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
    }

    process
    {
        $queryText = $Query.Trim()
        if ([String]::IsNullOrWhiteSpace($queryText))
        {
            throw 'Query cannot be empty.'
        }

        $manager = Resolve-PackageManager
        Write-Verbose "Using package manager: $($manager.DisplayName) ($($manager.Command))"

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
