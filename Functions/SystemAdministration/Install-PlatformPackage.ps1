function Install-PlatformPackage
{
    <#
    .SYNOPSIS
        Installs packages with the native platform package manager.

    .DESCRIPTION
        Installs packages using the supported native package manager for the current platform.
        You can install packages directly by name or id, pipe normalized results from
        Find-PlatformPackage, or start from a search query and select packages in an
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
        packages selected with Space. If no package is selected, pressing Enter
        installs the current package.

    .PARAMETER Name
        Installs one or more packages by name using the detected package manager.

    .PARAMETER Id
        Installs one or more packages by package identifier. This is most useful for
        package managers such as winget that distinguish names from ids.

    .PARAMETER InputObject
        One or more normalized package records, such as objects returned by
        Find-PlatformPackage.

    .PARAMETER ExcludePackage
        Optional package names or wildcard patterns to exclude from query results before
        they are shown in the interactive picker.

    .PARAMETER Top
        Maximum number of query results to retrieve before opening the interactive picker.
        Use 0 to return all normalized search results to the picker.

    .PARAMETER NoSudo
        On Linux package managers that normally require elevated privileges, do not
        automatically prefix install commands with sudo.

    .PARAMETER FilterSource
        Pre-filters the interactive picker to show only packages from this source (e.g. 'winget').
        Press S in the picker to cycle through available sources interactively.

    .EXAMPLE
        PS > Install-PlatformPackage -Query git

        Searches the detected registry for git, opens the interactive picker, and installs
        the selected packages or the current package when nothing is selected.

    .EXAMPLE
        PS > Install-PlatformPackage -Name git

        Installs git by name using the detected package manager.

    .EXAMPLE
        PS > Install-PlatformPackage -Id Git.Git -PackageManager winget

        Installs a package by winget identifier.

    .EXAMPLE
        PS > Find-PlatformPackage -NonInteractive -Query code | Install-PlatformPackage

        Pipes search results into Install-PlatformPackage and installs the piped records.

    .EXAMPLE
        PS > Find-PlatformPackage -NonInteractive -Query code -Top 5 | Where-Object Type -eq 'Cask' | Install-PlatformPackage

        Filters search results before installing the selected pipeline records.

    .EXAMPLE
        PS > Install-PlatformPackage -Query docker -ExcludePackage '*desktop*'

        Searches for docker packages and excludes Docker Desktop from the interactive list.

    .EXAMPLE
        PS > Install-PlatformPackage -Query git -Top 10

        Searches for git and limits the interactive list to 10 normalized results.

    .EXAMPLE
        PS > Install-PlatformPackage -Name openssl -NoSudo

        Installs openssl without automatically prefixing the package manager command with sudo.

    .EXAMPLE
        PS > Install-PlatformPackage -Name git -WhatIf

        Shows which install commands would run without invoking the package manager.

    .EXAMPLE
        PS > Install-PlatformPackage -Query 'visual studio code' -Verbose

        Searches for packages, opens the picker, and writes dependency-loading details to verbose output.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Install-PlatformPackage.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Install-PlatformPackage.ps1
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

        [Parameter(ParameterSetName = 'Query')]
        [String]$FilterSource = '',

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

        $findPlatformPackageDependencyPath = Get-DependencyPathIfNeeded -FunctionName 'Find-PlatformPackage' -RelativePath 'Find-PlatformPackage.ps1'
        if (-not [String]::IsNullOrWhiteSpace($findPlatformPackageDependencyPath))
        {
            try
            {
                . $findPlatformPackageDependencyPath
                Write-Verbose "Loaded Find-PlatformPackage from: $findPlatformPackageDependencyPath"
            }
            catch
            {
                throw "Failed to load required dependency 'Find-PlatformPackage' from '$findPlatformPackageDependencyPath': $($_.Exception.Message)"
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
                throw 'Install-PlatformPackage does not support installing mixed package manager records in a single call.'
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
            $publisher = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $PackageRecord -PropertyName @('Publisher', 'PublisherName', 'Author'))
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
                Publisher = $publisher
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
                    $sourceArguments = if (-not [String]::IsNullOrWhiteSpace($Package.Source))
                    {
                        @('--source', $Package.Source)
                    }
                    else
                    {
                        @()
                    }

                    if (-not [String]::IsNullOrWhiteSpace($Package.Id))
                    {
                        return @('install', '--id', $Package.Id, '--exact') + $sourceArguments + @('--accept-source-agreements', '--accept-package-agreements')
                    }

                    return @('install', $Package.Name) + $sourceArguments + @('--accept-source-agreements', '--accept-package-agreements')
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
                [Int32]$PageSize = 0,

                [Parameter()]
                [String]$SourceFilter = '',

                [Parameter()]
                [Switch]$TreatKeyReaderAsConsoleKeyReader,

                [Parameter()]
                [ScriptBlock]$TerminalEchoController
            )

            if ($AvailablePackages.Count -eq 0)
            {
                return @()
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
                    throw 'Interactive package installation requires an attached console. Use Find-PlatformPackage -NonInteractive for object output or install explicit package names or ids in non-interactive sessions.'
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
                    [PSCustomObject]$ColumnWidths
                )

                return 6 + [Int32]$ColumnWidths.Name + 1 + [Int32]$ColumnWidths.Id + 1 + [Int32]$ColumnWidths.Version + 1 + [Int32]$ColumnWidths.Type + 1 + [Int32]$ColumnWidths.Source
            }

            function Compress-PackagePickerTableWidths
            {
                param(
                    [Parameter(Mandatory)]
                    [PSCustomObject]$ColumnWidths,

                    [Parameter(Mandatory)]
                    [Int32]$MaximumWidth
                )

                $minimumWidths = @{
                    Name = 12
                    Id = 14
                    Version = 8
                    Type = 3
                    Source = 5
                }
                $shrinkOrder = @('Id', 'Name', 'Version', 'Source', 'Type')

                while ((Get-PackagePickerTableLineWidth -ColumnWidths $ColumnWidths) -gt $MaximumWidth)
                {
                    $shrunk = $false
                    foreach ($columnName in $shrinkOrder)
                    {
                        if ([Int32]$ColumnWidths.$columnName -gt [Int32]$minimumWidths[$columnName])
                        {
                            $ColumnWidths.$columnName = [Int32]$ColumnWidths.$columnName - 1
                            $shrunk = $true
                            if ((Get-PackagePickerTableLineWidth -ColumnWidths $ColumnWidths) -le $MaximumWidth)
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
            $columnWidths = Compress-PackagePickerTableWidths -ColumnWidths $columnWidths -MaximumWidth $pickerFrameWidth
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

                return ($parts -join ' | ')
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
                Write-Host 'Install-PlatformPackage Help' -ForegroundColor Cyan
                Write-Host ''
                Write-Host 'Navigation' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'Up/Down' -Description 'move one package'
                Write-PackagePickerHelpItem -Shortcut 'PageUp/PageDown' -Description 'move one page'
                Write-PackagePickerHelpItem -Shortcut 'Home/End' -Description 'move to the first or last package'

                Write-Host ''
                Write-Host 'Selection' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'Space' -Description 'select or clear the current package'
                Write-PackagePickerHelpItem -Shortcut 'A' -Description 'toggle all visible packages'
                Write-PackagePickerHelpItem -Shortcut 'Enter' -Description 'install selected packages, or the current package if none are selected'

                if ($hasSourceFilter)
                {
                    Write-Host ''
                    Write-Host 'Source Filter' -ForegroundColor White
                    Write-PackagePickerHelpItem -Shortcut 'S' -Description "cycle source: $($availableSources -join ' | ')"
                }

                Write-Host ''
                Write-Host 'Other Actions' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'V' -Description 'load a missing winget description when available'
                Write-PackagePickerHelpItem -Shortcut 'Q, Esc, or Ctrl+C' -Description 'cancel installation'
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

                    $sourceHint = if ($hasSourceFilter) { "S: [$($availableSources[$sourceFilterIndex])]  " } else { '' }
                    $sourceSummary = if ($hasSourceFilter) { "source: $($availableSources[$sourceFilterIndex])" } else { '' }
                    $selectionHint = 'Keys: Space select  Enter install  V details  A all'
                    $navigationHint = "Nav: ${sourceHint}Home/End/PgUp/PgDn  ?: help  Q/Esc/Ctrl+C cancel"
                    $frameLines = @(
                        (Format-PickerFrameLine -Text "Install-PlatformPackage - $($allPackages[0].PackageManagerDisplayName)" -ForegroundColor Cyan)
                        (Format-PickerFrameLine -Text (Get-PickerViewportSummary -TopIndex $topIndex -BottomIndex $bottomIndex -VisibleCount $visiblePackages.Count -TotalCount $allPackages.Count -SelectedCount $selectedKeys.Count -FilterText $sourceSummary) -ForegroundColor White)
                        ''
                        (Format-PickerFrameLine -Text $selectionHint -ForegroundColor DarkGray)
                        (Format-PickerFrameLine -Text $navigationHint -ForegroundColor DarkGray)
                        ''
                        (Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4} {5}' -f 'Sel', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Id' -Width $idWidth), (Format-PickerCell -Text 'Ver' -Width $versionWidth), (Format-PickerCell -Text 'Typ' -Width $typeWidth), (Format-PickerCell -Text 'Src' -Width $sourceWidth)) -ForegroundColor DarkGray)
                        (Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4} {5}' -f '---', ('-' * $nameWidth), ('-' * $idWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth)) -ForegroundColor DarkGray)
                    )

                    if ($visiblePackages.Count -eq 0)
                    {
                        $frameLines += ''
                        $frameLines += Format-PickerFrameLine -Text '  (No packages match this source filter. Press S to cycle.)' -ForegroundColor DarkYellow
                        Write-PickerFrame -Lines $frameLines

                        $key = & $KeyReader
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

                        continue
                    }

                    for ($i = $topIndex; $i -le $bottomIndex; $i++)
                    {
                        $package = $visiblePackages[$i]
                        $pkgKey = Get-PackagePickerKey -Package $package
                        $cursorMarker = if ($i -eq $cursor) { '>' } else { ' ' }
                        $selectedMarker = if ($selectedKeys.Contains($pkgKey)) { '[x]' } else { '[ ]' }
                        $packageLine = ('{0} {1} {2} {3} {4} {5} {6}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Id -Width $idWidth), (Format-PickerCell -Text $package.Version -Width $versionWidth), (Format-PickerCell -Text (Get-PackageTypeDisplay -Type $package.Type) -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                        if ($package.Installed)
                        {
                            $frameLines += Format-PickerFrameLine -Text $packageLine -ForegroundColor DarkGray
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
                    $currentPublisher = if ($null -eq $currentPackage -or [String]::IsNullOrWhiteSpace($currentPackage.Publisher)) { 'n/a' } else { $currentPackage.Publisher }
                    $frameLines += Format-PickerFrameLine -Text ('Current: {0}' -f $currentPackage.Name) -ForegroundColor DarkGray
                    $frameLines += Format-PickerFrameLine -Text ('Id: {0} | Publisher: {1} | Installed: {2}' -f $currentPackage.Id, $currentPublisher, ($(if ($currentPackage.Installed) { 'yes' } else { 'no' }))) -ForegroundColor DarkGray
                    $frameLines += Format-PickerFrameLine -Text ('Description: {0}' -f $currentDescription) -ForegroundColor DarkGray
                    $frameLines += ''
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
                    $frameLines += Format-PickerFrameLine -Text $countText -ForegroundColor White

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
                        }
                        'Enter'
                        {
                            Clear-PickerFrame

                            $selectedPackages = @($allPackages | Where-Object { $selectedKeys.Contains((Get-PackagePickerKey -Package $_)) })

                            if ($selectedPackages.Count -eq 0)
                            {
                                $selectedPackages = @($visiblePackages[$cursor])
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
                    CapturedOutput = @()
                    InformationalOutput = @()
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
                    CapturedOutput = @()
                    InformationalOutput = @()
                }
            }

            Write-Host ''
            Write-Host "Installing $targetDescription with $($Manager.DisplayName)..." -ForegroundColor White

            $installArguments = Get-PackageInstallArguments -Manager $Manager -Package $Package
            $invocation = Resolve-PackageManagerInvocation -Manager $Manager -Arguments $installArguments
            $result = Invoke-PackageManagerCommand -Command $invocation.Command -Arguments $invocation.Arguments -StreamOutput -PreserveConsoleOutput:($Manager.Name -eq 'winget')

            if ($result.ExitCode -eq 0)
            {
                $informationalOutput = @(Get-PackageInformationalOutput -Output $result.Output)
                return [PSCustomObject]@{
                    Name = $Package.Name
                    Id = $Package.Id
                    Version = $Package.Version
                    Status = 'Installed'
                    ExitCode = $result.ExitCode
                    Message = 'Installation completed'
                    CapturedOutput = @($result.Output)
                    InformationalOutput = @($informationalOutput)
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
                CapturedOutput = @($result.Output)
                InformationalOutput = @()
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
                    Find-PlatformPackage -NonInteractive -Query $Query -ExcludePackage $ExcludePackage -Top $Top -PackageManager $manager.Name -SkipDescriptionEnrichment:($manager.Name -eq 'winget') -CommandRunner $CommandRunner
                )
                $totalMatched = $candidatePackages.Count

                if ($candidatePackages.Count -eq 0)
                {
                    Write-Host 'No packages matched the requested query.' -ForegroundColor White
                }
                else
                {
                    $selectedPackages = @(Select-AvailablePackageRecords -AvailablePackages $candidatePackages -KeyReader $KeyReader -PageSize $PickerPageSize -SourceFilter $FilterSource -TreatKeyReaderAsConsoleKeyReader:$TreatKeyReaderAsConsoleKeyReader -TerminalEchoController $TerminalEchoController)
                    $notSelected = $candidatePackages.Count - $selectedPackages.Count
                    if ($selectedPackages.Count -eq 0)
                    {
                        Write-Host 'No packages selected for installation.' -ForegroundColor White
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
                            Publisher = ''
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
                            Publisher = ''
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

        return [PSCustomObject]@{
            PackageManager = if ($manager) { $manager.Name } else { '' }
            PackageManagerDisplayName = if ($manager) { $manager.DisplayName } else { '' }
            TotalMatched = $totalMatched
            Selected = $selectedPackages.Count
            NotSelected = $notSelected
            Installed = $installedCount
            Failed = $failedCount
            Skipped = $skippedCount
            InformationalResults = @($informationalResults)
            Results = @($results)
        }
    }
}
