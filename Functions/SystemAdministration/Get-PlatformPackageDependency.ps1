function Get-PlatformPackageDependency
{
    <#
    .SYNOPSIS
        Gets package dependency relationships from the native platform package manager.

    .DESCRIPTION
        Queries the supported native package manager for dependency relationships for one
        or more packages and returns normalized PowerShell objects. Supported package
        managers are winget on Windows, Homebrew on macOS, and apt or apk on Linux.

        By default, the function returns packages that the requested package depends on.
        Use -Direction RequiredBy to return packages that depend on the requested package,
        or -Direction Both to return both relationship directions.

        Use -InstalledOnly to limit related packages to installed packages where the
        selected package manager supports that directly or where installed package
        metadata can be queried through Get-PlatformPackage.

        winget can report installer dependencies only when package manifest metadata
        includes them. winget does not expose reverse dependency metadata, so
        -Direction RequiredBy returns no records for winget.

    .PARAMETER Package
        Package names, ids, or normalized package records to query. Objects returned by
        Get-PlatformPackage can be piped directly into this function.

    .PARAMETER Direction
        Dependency direction to query. DependsOn returns packages the requested package
        depends on. RequiredBy returns packages that depend on the requested package.
        Both returns both directions.

    .PARAMETER InstalledOnly
        Limits related packages to installed packages when possible.

    .EXAMPLE
        PS > Get-PlatformPackageDependency git

        Returns direct dependency records for git using the detected package manager.

    .EXAMPLE
        PS > Get-PlatformPackageDependency openssl -Direction RequiredBy -InstalledOnly

        Returns installed packages that depend on openssl.

    .EXAMPLE
        PS > Get-PlatformPackageDependency jq -Direction Both | Format-Table -AutoSize

        Package Id PackageManager PackageManagerDisplayName Direction  Relationship    RelatedPackage DependencyType Installed Notes
        ------- -- -------------- ------------------------- ---------  ------------    -------------- -------------- --------- -----
        jq         brew           Homebrew                  DependsOn  jq -> oniguruma oniguruma      Dependency
        jq         brew           Homebrew                  RequiredBy todoman -> jq   todoman        Dependent
        jq         brew           Homebrew                  RequiredBy zsv -> jq       zsv            Dependent

    .EXAMPLE
        PS > Get-PlatformPackage -Name 'git' | Get-PlatformPackageDependency -Direction Both

        Pipes an installed package record into the dependency query and returns both
        dependency directions.

    .EXAMPLE
        PS > Get-PlatformPackageDependency pipewire -PackageManager apk -Direction Both

        Returns apk dependency and reverse-dependency records for pipewire.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        - winget is used on Windows.
        - brew is used on macOS.
        - apt is used on Debian/Ubuntu-style Linux distributions.
        - apk is used on Alpine Linux.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Get-PlatformPackageDependency.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Get-PlatformPackageDependency.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [PSCustomObject[]], [Object[]])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'Id', 'PackageName')]
        [Object[]]$Package,

        [Parameter()]
        [ValidateSet('DependsOn', 'RequiredBy', 'Both')]
        [String]$Direction = 'DependsOn',

        [Parameter()]
        [Switch]$InstalledOnly,

        [Parameter(DontShow = $true)]
        [ValidateSet('Auto', 'winget', 'brew', 'apt', 'apk')]
        [String]$PackageManager = 'Auto',

        [Parameter(DontShow = $true)]
        [ScriptBlock]$CommandRunner
    )

    begin
    {
        $installedPackageLookupCache = @{
            Lookup = $null
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

        function Get-PackageReference
        {
            param(
                [Parameter()]
                [Object]$InputObject
            )

            if ($null -eq $InputObject)
            {
                return $null
            }

            if ($InputObject -is [String])
            {
                $value = "$InputObject".Trim()
                if ([String]::IsNullOrWhiteSpace($value))
                {
                    return $null
                }

                return [PSCustomObject]@{
                    Name = $value
                    Id = ''
                    Type = ''
                    Query = $value
                }
            }

            $name = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $InputObject -PropertyName @('Name', 'PackageName'))
            $id = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $InputObject -PropertyName @('Id', 'PackageIdentifier', 'Identifier'))
            $type = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $InputObject -PropertyName @('Type'))
            $query = if (-not [String]::IsNullOrWhiteSpace($id)) { $id } else { $name }
            $displayName = if (-not [String]::IsNullOrWhiteSpace($name)) { $name } else { $query }

            if ([String]::IsNullOrWhiteSpace($query))
            {
                $text = "$InputObject".Trim()
                if ([String]::IsNullOrWhiteSpace($text))
                {
                    return $null
                }

                $displayName = $text
                $query = $text
            }

            [PSCustomObject]@{
                Name = $displayName
                Id = $id
                Type = $type
                Query = $query
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
                        Command = 'apt-cache'
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
                $commandName = if ($requestedManager -eq 'apt') { 'apt-cache' } else { $requestedManager }
                if (-not (Test-PackageManagerCommandAvailable -Name $commandName))
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

                if ($linuxFamily -match '\b(debian|ubuntu)\b' -and (Test-PackageManagerCommandAvailable -Name 'apt-cache'))
                {
                    return Get-PackageManagerDefinition -Name 'apt'
                }

                if (Test-PackageManagerCommandAvailable -Name 'apt-cache')
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
                $commandName = if ($fallbackManager -eq 'apt') { 'apt-cache' } else { $fallbackManager }
                if (Test-PackageManagerCommandAvailable -Name $commandName)
                {
                    return Get-PackageManagerDefinition -Name $fallbackManager
                }
            }

            throw 'No supported package manager was found. Install winget, brew, apt-cache, or apk and try again.'
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

            $restoreHomebrewNoEnvHints = $false
            $previousHomebrewNoEnvHints = $null

            if ($Command -eq 'brew')
            {
                $previousHomebrewNoEnvHints = $env:HOMEBREW_NO_ENV_HINTS
                $env:HOMEBREW_NO_ENV_HINTS = '1'
                $restoreHomebrewNoEnvHints = $true
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
            finally
            {
                if ($restoreHomebrewNoEnvHints)
                {
                    if ($null -eq $previousHomebrewNoEnvHints)
                    {
                        Remove-Item -Path Env:HOMEBREW_NO_ENV_HINTS -ErrorAction SilentlyContinue
                    }
                    else
                    {
                        $env:HOMEBREW_NO_ENV_HINTS = $previousHomebrewNoEnvHints
                    }
                }
            }
        }

        function Get-PackageCommandFailureMessage
        {
            param(
                [Parameter(Mandatory)]
                [String]$Command,

                [Parameter()]
                [String[]]$Arguments = @(),

                [Parameter(Mandatory)]
                [Int32]$ExitCode,

                [Parameter()]
                [Object[]]$Output = @()
            )

            $commandText = "$Command $($Arguments -join ' ')".Trim()
            $message = ($Output | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }) -join ' '
            if ([String]::IsNullOrWhiteSpace($message))
            {
                $message = "Command exited with code $ExitCode."
            }

            "Failed to query package dependencies with '$commandText': $message"
        }

        function Get-PlatformPackageDependencyObject
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [PSCustomObject]$PackageReference,

                [Parameter(Mandatory)]
                [ValidateSet('DependsOn', 'RequiredBy')]
                [String]$RelationshipDirection,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$RelatedPackage,

                [Parameter()]
                [String]$DependencyType = '',

                [Parameter()]
                [String]$Notes = ''
            )

            $relationship = if ($RelationshipDirection -eq 'DependsOn')
            {
                "$($PackageReference.Name) -> $RelatedPackage"
            }
            else
            {
                "$RelatedPackage -> $($PackageReference.Name)"
            }

            [PSCustomObject]@{
                Package = $PackageReference.Name
                Id = $PackageReference.Id
                PackageManager = $Manager.Name
                PackageManagerDisplayName = $Manager.DisplayName
                Direction = $RelationshipDirection
                Relationship = $relationship
                RelatedPackage = $RelatedPackage
                DependencyType = $DependencyType
                Installed = $null
                Notes = $Notes
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

        function Get-CleanRelatedPackageName
        {
            param(
                [Parameter()]
                [String]$Value
            )

            if ([String]::IsNullOrWhiteSpace($Value))
            {
                return ''
            }

            $cleanValue = $Value.Trim()
            $cleanValue = $cleanValue -replace '^\|\s*', ''
            $cleanValue = $cleanValue -replace '^[-*]\s*', ''
            $cleanValue = $cleanValue.Trim().Trim(',')

            if ($cleanValue.StartsWith('<') -and $cleanValue.EndsWith('>') -and $cleanValue.Length -gt 2)
            {
                $cleanValue = $cleanValue.Substring(1, $cleanValue.Length - 2)
            }

            return $cleanValue.Trim()
        }

        function Get-InstalledPackageLookup
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            $getPlatformPackageDependencyPath = Get-DependencyPathIfNeeded -FunctionName 'Get-PlatformPackage' -RelativePath 'Get-PlatformPackage.ps1'
            if (-not [String]::IsNullOrWhiteSpace($getPlatformPackageDependencyPath))
            {
                try
                {
                    . $getPlatformPackageDependencyPath
                    Write-Verbose "Loaded Get-PlatformPackage from: $getPlatformPackageDependencyPath"
                }
                catch
                {
                    throw "Failed to load required dependency 'Get-PlatformPackage' from '$getPlatformPackageDependencyPath': $($_.Exception.Message)"
                }
            }

            $getPlatformPackageParameters = @{
                PackageManager = $Manager.Name
                CommandRunner = $CommandRunner
            }
            if ($Manager.Name -eq 'winget')
            {
                $getPlatformPackageParameters.SkipDescriptionEnrichment = $true
            }

            $lookup = @{}
            foreach ($installedPackage in @(Get-PlatformPackage @getPlatformPackageParameters))
            {
                foreach ($value in @($installedPackage.Name, $installedPackage.Id))
                {
                    $text = ConvertTo-PackageText -Value $value
                    if ([String]::IsNullOrWhiteSpace($text))
                    {
                        continue
                    }

                    $key = $text.Trim().ToLowerInvariant()
                    if (-not $lookup.ContainsKey($key))
                    {
                        $lookup[$key] = $installedPackage
                    }
                }
            }

            return $lookup
        }

        function Get-PackageLookupCandidates
        {
            param(
                [Parameter()]
                [String]$Value,

                [Parameter()]
                [String]$ManagerName
            )

            if ([String]::IsNullOrWhiteSpace($Value))
            {
                return @()
            }

            $candidates = New-Object 'System.Collections.Generic.List[String]'
            $cleanValue = Get-CleanRelatedPackageName -Value $Value

            foreach ($candidate in @($Value, $cleanValue))
            {
                if (-not [String]::IsNullOrWhiteSpace($candidate) -and -not $candidates.Contains($candidate))
                {
                    $candidates.Add($candidate)
                }
            }

            if ($ManagerName -eq 'apk' -and -not [String]::IsNullOrWhiteSpace($cleanValue) -and $cleanValue -notmatch '^(?:/|so:|cmd:|pc:)')
            {
                $apkPackage = Split-ApkPackageVersion -InstalledToken $cleanValue
                if (-not [String]::IsNullOrWhiteSpace($apkPackage.Name) -and -not $candidates.Contains($apkPackage.Name))
                {
                    $candidates.Add($apkPackage.Name)
                }
            }

            if ($ManagerName -eq 'apt' -and $cleanValue -match '^(?<Name>[^:]+):(?:any|native|[A-Za-z0-9_]+)$')
            {
                $aptName = $Matches.Name
                if (-not [String]::IsNullOrWhiteSpace($aptName) -and -not $candidates.Contains($aptName))
                {
                    $candidates.Add($aptName)
                }
            }

            return @($candidates)
        }

        function Test-RelatedPackageInstalled
        {
            param(
                [Parameter(Mandatory)]
                [Hashtable]$Lookup,

                [Parameter(Mandatory)]
                [PSCustomObject]$Record
            )

            foreach ($candidate in @(Get-PackageLookupCandidates -Value $Record.RelatedPackage -ManagerName $Record.PackageManager))
            {
                $key = $candidate.Trim().ToLowerInvariant()
                if ($Lookup.ContainsKey($key))
                {
                    return $true
                }
            }

            return $false
        }

        function Select-InstalledDependencyRecords
        {
            param(
                [Parameter()]
                [PSCustomObject[]]$Records = @(),

                [Parameter(Mandatory)]
                [PSCustomObject]$Manager
            )

            if ($Records.Count -eq 0)
            {
                return @()
            }

            if ($Manager.Name -eq 'brew')
            {
                foreach ($record in $Records)
                {
                    $record.Installed = $true
                }

                return @($Records)
            }

            if ($null -eq $installedPackageLookupCache.Lookup)
            {
                $installedPackageLookupCache.Lookup = Get-InstalledPackageLookup -Manager $Manager
            }

            $filteredRecords = @()
            foreach ($record in $Records)
            {
                if (Test-RelatedPackageInstalled -Lookup $installedPackageLookupCache.Lookup -Record $record)
                {
                    $record.Installed = $true
                    $filteredRecords += $record
                }
            }

            return $filteredRecords
        }

        function Get-BrewPackageDependencyRecords
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [PSCustomObject]$PackageReference,

                [Parameter(Mandatory)]
                [ValidateSet('DependsOn', 'RequiredBy')]
                [String]$RelationshipDirection
            )

            $arguments = @(
                if ($RelationshipDirection -eq 'DependsOn')
                {
                    'deps'
                    '--direct'
                }
                else
                {
                    'uses'
                }
            )

            if ($RelationshipDirection -eq 'DependsOn' -and -not [String]::IsNullOrWhiteSpace($PackageReference.Type))
            {
                if ($PackageReference.Type -eq 'Formula')
                {
                    $arguments += '--formula'
                }
                elseif ($PackageReference.Type -eq 'Cask')
                {
                    $arguments += '--cask'
                }
            }

            if ($RelationshipDirection -eq 'RequiredBy')
            {
                if ($InstalledOnly)
                {
                    $arguments += '--installed'
                }
                else
                {
                    $arguments += '--eval-all'
                }
            }
            elseif ($InstalledOnly)
            {
                $arguments += '--installed'
            }

            $arguments += $PackageReference.Query
            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments $arguments
            if ($result.ExitCode -ne 0)
            {
                throw (Get-PackageCommandFailureMessage -Command $Manager.Command -Arguments $arguments -ExitCode $result.ExitCode -Output $result.Output)
            }

            $records = @()
            foreach ($line in @($result.Output | ForEach-Object { "$_" }))
            {
                if ($line -match '^Warning:' -or $line -match '^This means dependencies may differ\b' -or $line -match '^Hide these hints with\b')
                {
                    continue
                }

                $relatedPackage = Get-CleanRelatedPackageName -Value $line
                if ([String]::IsNullOrWhiteSpace($relatedPackage) -or $relatedPackage -match '^Warning:')
                {
                    continue
                }

                $dependencyType = if ($RelationshipDirection -eq 'DependsOn') { 'Dependency' } else { 'Dependent' }
                $records += Get-PlatformPackageDependencyObject -Manager $Manager -PackageReference $PackageReference -RelationshipDirection $RelationshipDirection -RelatedPackage $relatedPackage -DependencyType $dependencyType
            }

            return $records
        }

        function Get-AptPackageDependencyRecords
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [PSCustomObject]$PackageReference,

                [Parameter(Mandatory)]
                [ValidateSet('DependsOn', 'RequiredBy')]
                [String]$RelationshipDirection
            )

            $arguments = if ($RelationshipDirection -eq 'DependsOn')
            {
                @('depends', $PackageReference.Query)
            }
            else
            {
                @('rdepends', $PackageReference.Query)
            }

            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments $arguments
            if ($result.ExitCode -ne 0)
            {
                throw (Get-PackageCommandFailureMessage -Command $Manager.Command -Arguments $arguments -ExitCode $result.ExitCode -Output $result.Output)
            }

            $records = @()
            $inReverseDependencies = $false

            foreach ($line in @($result.Output | ForEach-Object { "$_" }))
            {
                $trimmedLine = $line.Trim()
                if ([String]::IsNullOrWhiteSpace($trimmedLine))
                {
                    continue
                }

                if ($RelationshipDirection -eq 'DependsOn')
                {
                    if ($trimmedLine -match '^(?:\|\s*)?(?<Type>PreDepends|Depends):\s*(?<Package>\S+)')
                    {
                        $relatedPackage = Get-CleanRelatedPackageName -Value $Matches.Package
                        if (-not [String]::IsNullOrWhiteSpace($relatedPackage))
                        {
                            $records += Get-PlatformPackageDependencyObject -Manager $Manager -PackageReference $PackageReference -RelationshipDirection $RelationshipDirection -RelatedPackage $relatedPackage -DependencyType $Matches.Type
                        }
                    }

                    continue
                }

                if ($trimmedLine -match '^Reverse Depends:')
                {
                    $inReverseDependencies = $true
                    continue
                }

                if (-not $inReverseDependencies)
                {
                    continue
                }

                $relatedPackage = Get-CleanRelatedPackageName -Value (($trimmedLine -split '\s+')[0])
                if ([String]::IsNullOrWhiteSpace($relatedPackage))
                {
                    continue
                }

                $records += Get-PlatformPackageDependencyObject -Manager $Manager -PackageReference $PackageReference -RelationshipDirection $RelationshipDirection -RelatedPackage $relatedPackage -DependencyType 'Dependent'
            }

            return $records
        }

        function Get-ApkPackageDependencyRecords
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [PSCustomObject]$PackageReference,

                [Parameter(Mandatory)]
                [ValidateSet('DependsOn', 'RequiredBy')]
                [String]$RelationshipDirection
            )

            $arguments = if ($RelationshipDirection -eq 'DependsOn')
            {
                @('info', '--depends', $PackageReference.Query)
            }
            else
            {
                @('info', '--rdepends', $PackageReference.Query)
            }

            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments $arguments
            if ($result.ExitCode -ne 0)
            {
                throw (Get-PackageCommandFailureMessage -Command $Manager.Command -Arguments $arguments -ExitCode $result.ExitCode -Output $result.Output)
            }

            $records = @()
            foreach ($line in @($result.Output | ForEach-Object { "$_" }))
            {
                $trimmedLine = $line.Trim()
                if ([String]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine -match '^WARNING:')
                {
                    continue
                }

                if ($trimmedLine -match ' (?:depends on|is required by):$')
                {
                    continue
                }

                $relatedPackage = Get-CleanRelatedPackageName -Value $trimmedLine
                if ($RelationshipDirection -eq 'RequiredBy' -and $relatedPackage -notmatch '^(?:/|so:|cmd:|pc:)')
                {
                    $relatedPackage = (Split-ApkPackageVersion -InstalledToken $relatedPackage).Name
                }

                if ([String]::IsNullOrWhiteSpace($relatedPackage))
                {
                    continue
                }

                $dependencyType = if ($RelationshipDirection -eq 'DependsOn') { 'Dependency' } else { 'Dependent' }
                $records += Get-PlatformPackageDependencyObject -Manager $Manager -PackageReference $PackageReference -RelationshipDirection $RelationshipDirection -RelatedPackage $relatedPackage -DependencyType $dependencyType
            }

            return $records
        }

        function Get-WingetPackageDependencyRecords
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [PSCustomObject]$PackageReference,

                [Parameter(Mandatory)]
                [ValidateSet('DependsOn', 'RequiredBy')]
                [String]$RelationshipDirection
            )

            if ($RelationshipDirection -eq 'RequiredBy')
            {
                Write-Verbose 'winget does not expose reverse dependency metadata.'
                return @()
            }

            $arguments = @('show')
            if (-not [String]::IsNullOrWhiteSpace($PackageReference.Id))
            {
                $arguments += @('--id', $PackageReference.Id, '--exact')
            }
            else
            {
                $arguments += $PackageReference.Query
            }

            $arguments += '--accept-source-agreements'
            $result = Invoke-PackageManagerCommand -Command $Manager.Command -Arguments $arguments
            if ($result.ExitCode -ne 0)
            {
                throw (Get-PackageCommandFailureMessage -Command $Manager.Command -Arguments $arguments -ExitCode $result.ExitCode -Output $result.Output)
            }

            $records = @()
            $inDependencies = $false
            $dependencyType = 'Dependency'

            foreach ($line in @($result.Output | ForEach-Object { "$_" }))
            {
                $trimmedLine = $line.Trim()
                if ([String]::IsNullOrWhiteSpace($trimmedLine))
                {
                    continue
                }

                if ($trimmedLine -match '^Dependencies\s*:\s*$')
                {
                    $inDependencies = $true
                    continue
                }

                if ($trimmedLine -match '^Dependencies\s*:\s*(?<Package>.+)$')
                {
                    $inDependencies = $true
                    $relatedPackage = Get-CleanRelatedPackageName -Value $Matches.Package
                    if (-not [String]::IsNullOrWhiteSpace($relatedPackage) -and $relatedPackage -notmatch '^(?:none|n/a)$')
                    {
                        $records += Get-PlatformPackageDependencyObject -Manager $Manager -PackageReference $PackageReference -RelationshipDirection $RelationshipDirection -RelatedPackage $relatedPackage -DependencyType $dependencyType
                    }

                    continue
                }

                if (-not $inDependencies)
                {
                    continue
                }

                if ($line -match '^\S' -and $trimmedLine -match '^[A-Za-z][A-Za-z\s]+:' -and $trimmedLine -notmatch '^(?:Package Dependencies|External Dependencies|Windows Features|Windows Libraries)\s*:')
                {
                    break
                }

                if ($trimmedLine -match '^(?<Type>Package Dependencies|External Dependencies|Windows Features|Windows Libraries)\s*:\s*$')
                {
                    $dependencyType = $Matches.Type
                    continue
                }

                if ($trimmedLine -match '^(?<Type>Package Dependencies|External Dependencies|Windows Features|Windows Libraries)\s*:\s*(?<Package>.+)$')
                {
                    $dependencyType = $Matches.Type
                    $trimmedLine = $Matches.Package
                }

                $relatedPackage = Get-CleanRelatedPackageName -Value $trimmedLine
                if ([String]::IsNullOrWhiteSpace($relatedPackage))
                {
                    continue
                }

                $records += Get-PlatformPackageDependencyObject -Manager $Manager -PackageReference $PackageReference -RelationshipDirection $RelationshipDirection -RelatedPackage $relatedPackage -DependencyType $dependencyType
            }

            return $records
        }

        function Get-PackageDependencyRecords
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Manager,

                [Parameter(Mandatory)]
                [PSCustomObject]$PackageReference,

                [Parameter(Mandatory)]
                [ValidateSet('DependsOn', 'RequiredBy')]
                [String]$RelationshipDirection
            )

            switch ($Manager.Name)
            {
                'winget' { return Get-WingetPackageDependencyRecords -Manager $Manager -PackageReference $PackageReference -RelationshipDirection $RelationshipDirection }
                'brew' { return Get-BrewPackageDependencyRecords -Manager $Manager -PackageReference $PackageReference -RelationshipDirection $RelationshipDirection }
                'apt' { return Get-AptPackageDependencyRecords -Manager $Manager -PackageReference $PackageReference -RelationshipDirection $RelationshipDirection }
                'apk' { return Get-ApkPackageDependencyRecords -Manager $Manager -PackageReference $PackageReference -RelationshipDirection $RelationshipDirection }
                default { throw "Unsupported package manager '$($Manager.Name)'." }
            }
        }
    }

    process
    {
        $manager = Resolve-PackageManager
        Write-Verbose "Using package manager: $($manager.DisplayName) ($($manager.Command))"

        $relationshipDirections = if ($Direction -eq 'Both')
        {
            @('DependsOn', 'RequiredBy')
        }
        else
        {
            @($Direction)
        }

        foreach ($packageItem in @($Package))
        {
            $packageReference = Get-PackageReference -InputObject $packageItem
            if ($null -eq $packageReference)
            {
                continue
            }

            foreach ($relationshipDirection in $relationshipDirections)
            {
                $records = @(Get-PackageDependencyRecords -Manager $manager -PackageReference $packageReference -RelationshipDirection $relationshipDirection)
                if ($InstalledOnly)
                {
                    $records = @(Select-InstalledDependencyRecords -Records $records -Manager $manager)
                }

                foreach ($record in $records)
                {
                    $record
                }
            }
        }
    }
}
