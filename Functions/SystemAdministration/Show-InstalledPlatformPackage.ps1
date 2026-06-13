function Show-InstalledPlatformPackage
{
    <#
    .SYNOPSIS
        Displays installed packages from the native platform package manager.

    .DESCRIPTION
        Gets installed packages by calling Get-PlatformPackage and renders them in a
        interactive browser when a console is available. The browser supports paging,
        source and name filtering, dependency inspection, JSON/CSV export, and package
        actions on winget, Homebrew, apt, and apk.

        Use -NonInteractive to bypass the interactive browser and return package objects
        directly. Use -ExportPath to bypass the interactive browser and write installed
        package records to JSON or CSV. Use -PassThru to select one or more packages in
        the browser and return them when Enter is pressed. If nothing is selected, Enter
        returns the current package.

    .PARAMETER Name
        Optional package names or wildcard patterns to include. Matches package Name or Id.

    .PARAMETER ExcludePackage
        Optional package names or wildcard patterns to exclude. Matches package Name or Id.

    .PARAMETER FilterSource
        Sets the initial source filter in the interactive browser. When specified, the browser
        opens showing only packages from this source. Press S in the browser to cycle through
        available sources. Only applicable when multiple package sources are present.

    .PARAMETER NonInteractive
        Returns installed package records without opening the interactive browser. The
        previous -AsObject spelling is retained as an alias.

    .PARAMETER PassThru
        Allows packages to be selected in the interactive browser and returns the selected
        package records when Enter is pressed. If nothing is selected, returns the current
        package record.

    .PARAMETER ExportPath
        Writes matching installed package records to this file without opening the
        interactive browser.

    .PARAMETER ExportFormat
        Export format. Auto infers JSON or CSV from the ExportPath extension.

    .PARAMETER ExportDependencyMode
        Dependency relationships to include in the export. None exports package records
        only. DependsOn includes direct dependencies. Both includes direct dependencies
        and required-by relationships where supported.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage

        Opens the interactive installed package browser for the detected package manager.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage -Name 'git*'

        Opens the browser filtered to packages whose name or id matches git*.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage -ExcludePackage '*preview*'

        Opens the browser excluding packages whose name or id matches *preview*.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage -NonInteractive

        Returns installed packages as objects without opening the browser.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage -NonInteractive | Format-Table Name, InstalledVersion, Source

        Returns installed packages and formats them as a table.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage -ExportPath ./installed-packages.json

        Exports installed packages to JSON without opening the browser.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage -Name 'git' -ExportPath ./git.csv -ExportDependencyMode Both

        Exports matching packages to CSV with direct and required-by dependency
        relationships.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage -PassThru

        Opens the browser, lets you select packages with Space, and returns the selected
        records when Enter is pressed. If nothing is selected, Enter returns the current
        package.

        Press E in the browser to export the visible packages, or the selected packages
        when selection mode has active selections, to JSON or CSV.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage -PassThru -Name 'node*' | Format-Table

        Opens the browser for matching node packages and formats the selected results.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage -PackageManager winget

        Opens the browser using winget.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage -PackageManager brew

        Opens the browser using Homebrew.

    .EXAMPLE
        PS > Show-InstalledPlatformPackage -Verbose

        Opens the browser and writes dependency-loading details to verbose output.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Show-InstalledPlatformPackage.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Show-InstalledPlatformPackage.ps1
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

        [Parameter()]
        [String]$FilterSource = '',

        [Parameter()]
        [Alias('AsObject')]
        [Switch]$NonInteractive,

        [Parameter()]
        [Switch]$PassThru,

        [Parameter()]
        [String]$ExportPath = '',

        [Parameter()]
        [ValidateSet('Auto', 'Json', 'Csv')]
        [String]$ExportFormat = 'Auto',

        [Parameter()]
        [ValidateSet('None', 'DependsOn', 'Both')]
        [String]$ExportDependencyMode = 'None',

        [Parameter(DontShow = $true)]
        [ValidateSet('Auto', 'winget', 'brew', 'apt', 'apk')]
        [String]$PackageManager = 'Auto',

        [Parameter(DontShow = $true)]
        [ScriptBlock]$CommandRunner,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$KeyReader,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$ExportCancelRequested,

        [Parameter(DontShow = $true)]
        [Switch]$ShowExportProgress,

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

        $getPlatformPackagePath = Get-DependencyPathIfNeeded -FunctionName 'Get-PlatformPackage' -RelativePath 'Get-PlatformPackage.ps1'
        if (-not [String]::IsNullOrWhiteSpace($getPlatformPackagePath))
        {
            try
            {
                . $getPlatformPackagePath
                Write-Verbose "Loaded Get-PlatformPackage from: $getPlatformPackagePath"
            }
            catch
            {
                throw "Failed to load required dependency 'Get-PlatformPackage' from '$getPlatformPackagePath': $($_.Exception.Message)"
            }
        }

        $getPlatformPackageDependencyPath = Get-DependencyPathIfNeeded -FunctionName 'Get-PlatformPackageDependency' -RelativePath 'Get-PlatformPackageDependency.ps1'
        if (-not [String]::IsNullOrWhiteSpace($getPlatformPackageDependencyPath))
        {
            try
            {
                . $getPlatformPackageDependencyPath
                Write-Verbose "Loaded Get-PlatformPackageDependency from: $getPlatformPackageDependencyPath"
            }
            catch
            {
                throw "Failed to load required dependency 'Get-PlatformPackageDependency' from '$getPlatformPackageDependencyPath': $($_.Exception.Message)"
            }
        }

        $exportInstalledPlatformPackagePath = Get-DependencyPathIfNeeded -FunctionName 'Export-InstalledPlatformPackage' -RelativePath 'Export-InstalledPlatformPackage.ps1'
        if (-not [String]::IsNullOrWhiteSpace($exportInstalledPlatformPackagePath))
        {
            try
            {
                . $exportInstalledPlatformPackagePath
                Write-Verbose "Loaded Export-InstalledPlatformPackage from: $exportInstalledPlatformPackagePath"
            }
            catch
            {
                throw "Failed to load required dependency 'Export-InstalledPlatformPackage' from '$exportInstalledPlatformPackagePath': $($_.Exception.Message)"
            }
        }

        $removePlatformPackagePath = Get-DependencyPathIfNeeded -FunctionName 'Remove-PlatformPackage' -RelativePath 'Remove-PlatformPackage.ps1'
        if (-not [String]::IsNullOrWhiteSpace($removePlatformPackagePath))
        {
            try
            {
                . $removePlatformPackagePath
                Write-Verbose "Loaded Remove-PlatformPackage from: $removePlatformPackagePath"
            }
            catch
            {
                throw "Failed to load required dependency 'Remove-PlatformPackage' from '$removePlatformPackagePath': $($_.Exception.Message)"
            }
        }

        $upgradePlatformPackagePath = Get-DependencyPathIfNeeded -FunctionName 'Upgrade-PlatformPackage' -RelativePath 'Upgrade-PlatformPackage.ps1'
        if (-not [String]::IsNullOrWhiteSpace($upgradePlatformPackagePath))
        {
            try
            {
                . $upgradePlatformPackagePath
                Write-Verbose "Loaded Upgrade-PlatformPackage from: $upgradePlatformPackagePath"
            }
            catch
            {
                throw "Failed to load required dependency 'Upgrade-PlatformPackage' from '$upgradePlatformPackagePath': $($_.Exception.Message)"
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

        function Test-InteractiveWingetDescriptionEnrichmentShouldBeSkipped
        {
            $requestedManager = $PackageManager.ToLowerInvariant()
            if ($requestedManager -eq 'winget')
            {
                return $true
            }

            if ($requestedManager -ne 'auto')
            {
                return $false
            }

            $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { [Bool]$IsWindows }
            return $isWindowsPlatform -and (Test-PackageManagerCommandAvailable -Name 'winget')
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

        function Select-InstalledPackageRecords
        {
            param(
                [Parameter()]
                [PSCustomObject[]]$InstalledPackages = @(),

                [Parameter()]
                [ScriptBlock]$KeyReader,

                [Parameter()]
                [Int32]$PageSize = 0,

                [Parameter()]
                [Switch]$EnableSelection,

                [Parameter()]
                [String]$SourceFilter = '',

                [Parameter()]
                [ScriptBlock]$CommandRunner,

                [Parameter()]
                [Switch]$ReturnToPlatformPackageManagerOnBackKey
            )

            function Get-PackageActionFirstFailureMessage
            {
                param(
                    [Parameter()]
                    [Object]$ActionResult
                )

                if ($null -eq $ActionResult)
                {
                    return ''
                }

                $resultProperty = $ActionResult.PSObject.Properties['Results']
                if ($resultProperty)
                {
                    foreach ($result in @($resultProperty.Value))
                    {
                        if ($null -eq $result)
                        {
                            continue
                        }

                        $status = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $result -PropertyName @('Status'))
                        if ($status -ne 'Failed')
                        {
                            continue
                        }

                        $message = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $result -PropertyName @('Message', 'ErrorMessage', 'Error'))
                        if (-not [String]::IsNullOrWhiteSpace($message))
                        {
                            return $message
                        }

                        $informationalOutput = Get-FirstPropertyValue -InputObject $result -PropertyName @('InformationalOutput')
                        $informationalMessage = ConvertTo-PackageText -Value $informationalOutput
                        if (-not [String]::IsNullOrWhiteSpace($informationalMessage))
                        {
                            return $informationalMessage
                        }
                    }
                }

                $informationalResultsProperty = $ActionResult.PSObject.Properties['InformationalResults']
                if ($informationalResultsProperty)
                {
                    foreach ($informationalResult in @($informationalResultsProperty.Value))
                    {
                        if ($null -eq $informationalResult)
                        {
                            continue
                        }

                        $status = ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $informationalResult -PropertyName @('Status'))
                        if ($status -ne 'Failed')
                        {
                            continue
                        }

                        $lines = Get-FirstPropertyValue -InputObject $informationalResult -PropertyName @('Lines')
                        $message = ConvertTo-PackageText -Value $lines
                        if (-not [String]::IsNullOrWhiteSpace($message))
                        {
                            return $message
                        }
                    }
                }

                return ConvertTo-PackageText -Value (Get-FirstPropertyValue -InputObject $ActionResult -PropertyName @('Message', 'ErrorMessage', 'Error'))
            }

            if ($InstalledPackages.Count -eq 0)
            {
                return @()
            }

            $allPackages = $InstalledPackages
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
            elseif ($hasSourceFilter)
            {
                $isWingetContext = @($allPackages | Where-Object { "$($_.PackageManager)" -ieq 'winget' }).Count -gt 0
                if ($isWingetContext)
                {
                    for ($si = 1; $si -lt $availableSources.Count; $si++)
                    {
                        if ($availableSources[$si] -ieq 'winget')
                        {
                            $sourceFilterIndex = $si
                            break
                        }
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
                        Write-Host 'Filter installed packages' -ForegroundColor Cyan
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
                    throw 'Interactive package browsing requires an attached console. Use Get-PlatformPackage or Show-InstalledPlatformPackage -NonInteractive in non-interactive sessions.'
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
                        $reservedRows = 17
                        return [Math]::Min([Math]::Max(1, $windowHeight - $reservedRows), [Math]::Max(1, $ItemCount))
                    }
                }
                catch
                {
                    Write-Verbose "Unable to determine console height for package browser: $($_.Exception.Message)"
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
                    [Switch]$IncludesSelection
                )

                $prefixWidth = if ($IncludesSelection) { 6 } else { 2 }
                return $prefixWidth + [Int32]$ColumnWidths.Name + 1 + [Int32]$ColumnWidths.Id + 1 + [Int32]$ColumnWidths.Version + 1 + [Int32]$ColumnWidths.Type + 1 + [Int32]$ColumnWidths.Source
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
                Name = Get-PackagePickerTextMaximum -Values @($InstalledPackages | ForEach-Object { $_.Name }) -Minimum 12 -Maximum 30
                Id = Get-PackagePickerTextMaximum -Values @($InstalledPackages | ForEach-Object { $_.Id }) -Minimum 14 -Maximum 32
                Version = Get-PackagePickerTextMaximum -Values @($InstalledPackages | ForEach-Object { $_.InstalledVersion }) -Minimum 8 -Maximum 16
                Type = Get-PackagePickerTextMaximum -Values @($InstalledPackages | ForEach-Object { Get-PackageTypeDisplay -Type $_.Type }) -Minimum 3 -Maximum 7
                Source = Get-PackagePickerTextMaximum -Values @($InstalledPackages | ForEach-Object { $_.Source }) -Minimum 5 -Maximum 32
            }
            $columnWidths = Compress-PackagePickerTableWidths -ColumnWidths $columnWidths -MaximumWidth $pickerFrameWidth -IncludesSelection:$EnableSelection.IsPresent
            $nameWidth = [Int32]$columnWidths.Name
            $idWidth = [Int32]$columnWidths.Id
            $versionWidth = [Int32]$columnWidths.Version
            $typeWidth = [Int32]$columnWidths.Type
            $sourceWidth = [Int32]$columnWidths.Source
            $pageSize = Get-PackagePickerPageSize -RequestedPageSize $PageSize -ItemCount $InstalledPackages.Count

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

            function Format-PickerColumnText
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
                    if ($Width -le 1)
                    {
                        return $value.Substring(0, 1)
                    }

                    return $value.Substring(0, [Math]::Max(1, $Width - 1)) + '~'
                }

                return $value.PadRight($Width)
            }

            function Get-SideBySideFrameLines
            {
                param(
                    [Parameter(Mandatory)]
                    [Object[]]$LeftLines,

                    [Parameter(Mandatory)]
                    [Object[]]$RightLines
                )

                $consoleWidth = if ($pickerRenderState.ConsoleBufferWidth -gt 0) { $pickerRenderState.ConsoleBufferWidth } else { 120 }
                $gapWidth = 4
                $usableWidth = [Math]::Max(40, $consoleWidth - $gapWidth)
                $leftWidth = [Math]::Max(38, [Int32][Math]::Floor($usableWidth * 0.62))
                if ($leftWidth -gt ($usableWidth - 20))
                {
                    $leftWidth = [Math]::Max(20, $usableWidth - 20)
                }

                $rightWidth = [Math]::Max(20, $usableWidth - $leftWidth)
                if (($leftWidth + $rightWidth) -gt $usableWidth)
                {
                    $leftWidth = [Math]::Max(20, $usableWidth - $rightWidth)
                }

                $lineCount = [Math]::Max($LeftLines.Count, $RightLines.Count)
                $combinedLines = @()

                for ($lineIndex = 0; $lineIndex -lt $lineCount; $lineIndex++)
                {
                    $leftLine = if ($lineIndex -lt $LeftLines.Count) { $LeftLines[$lineIndex] } else { $null }
                    $rightLine = if ($lineIndex -lt $RightLines.Count) { $RightLines[$lineIndex] } else { $null }

                    $leftText = Format-PickerColumnText -Text (Get-PickerFrameLineText -Line $leftLine) -Width $leftWidth
                    $rightText = Format-PickerColumnText -Text (Get-PickerFrameLineText -Line $rightLine) -Width $rightWidth
                    $combinedText = $leftText + (' ' * $gapWidth) + $rightText

                    $combinedColor = Get-PickerFrameLineColor -Line $leftLine
                    if ($null -eq $combinedColor)
                    {
                        $combinedColor = Get-PickerFrameLineColor -Line $rightLine
                    }

                    $combinedLines += Format-PickerFrameLine -Text $combinedText -ForegroundColor $combinedColor
                }

                return $combinedLines
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
                if (-not $usingConsoleKeyReader)
                {
                    return $null
                }

                $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { [Bool]$IsWindows }
                if ($isWindowsPlatform)
                {
                    return $null
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
                Write-Host 'Show-InstalledPlatformPackage Help' -ForegroundColor Cyan
                Write-Host ''
                Write-Host 'Navigation' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'Up/Down' -Description 'move one package'
                Write-PackagePickerHelpItem -Shortcut 'PageUp/PageDown' -Description 'move one page'
                Write-PackagePickerHelpItem -Shortcut 'Home/End' -Description 'move to the first or last package'

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
                Write-Host 'Actions' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'D' -Description 'open or close the dependency view for the current package'
                Write-PackagePickerHelpItem -Shortcut 'B' -Description 'return to the package list from the dependency view'
                Write-PackagePickerHelpItem -Shortcut 'V' -Description 'load a missing winget description when available'
                Write-PackagePickerHelpItem -Shortcut 'E' -Description 'export visible packages, or selected packages when any are selected, to JSON or CSV'
                Write-PackagePickerHelpItem -Shortcut 'R' -Description 'remove the current package (with confirmation)'
                Write-PackagePickerHelpItem -Shortcut 'U' -Description 'upgrade the current package (with confirmation)'
                Write-PackagePickerHelpItem -Shortcut 'Q, Esc, or Ctrl+C' -Description 'exit the browser'
                Write-PackagePickerHelpItem -Shortcut '?' -Description 'show this help'

                if ($EnableSelection)
                {
                    Write-PackagePickerHelpItem -Shortcut 'Space' -Description 'select or clear the current package'
                    Write-PackagePickerHelpItem -Shortcut 'A' -Description 'select or clear all visible packages'
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

            function Read-PackageActionConfirmation
            {
                param(
                    [Parameter(Mandatory)]
                    [String]$Action,

                    [Parameter(Mandatory)]
                    [PSCustomObject]$Package
                )

                $restoreInPlaceRedraw = $pickerRenderState.UseInPlaceRedraw
                $pickerRenderState.UseInPlaceRedraw = $false
                $pickerRenderState.RenderedLineCount = 0

                try
                {
                    while ($true)
                    {
                        Clear-Host
                        Write-Host "$Action package" -ForegroundColor Cyan
                        Write-Host ''
                        Write-Host "Package: $($Package.Name)" -ForegroundColor White
                        Write-Host "Id: $($Package.Id)" -ForegroundColor White
                        Write-Host "Source: $($Package.Source)" -ForegroundColor White
                        Write-Host ''
                        Write-Host "Press Y to $($Action.ToLowerInvariant()) this package, or N to cancel." -ForegroundColor DarkGray

                        $confirmKey = & $KeyReader
                        if ($confirmKey.Key -eq [ConsoleKey]::Y)
                        {
                            return $true
                        }

                        if ($confirmKey.Key -eq [ConsoleKey]::N -or (Test-PackagePickerCancelKey -KeyInfo $confirmKey))
                        {
                            return $false
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

            function Test-PackageTextPromptCancelKey
            {
                param(
                    [Parameter(Mandatory)]
                    [ConsoleKeyInfo]$KeyInfo
                )

                $isControlC = $KeyInfo.Key -eq [ConsoleKey]::C -and (($KeyInfo.Modifiers -band [ConsoleModifiers]::Control) -eq [ConsoleModifiers]::Control)
                $isControlC = $isControlC -or ([Int32][Char]$KeyInfo.KeyChar -eq 3)

                return $KeyInfo.Key -eq [ConsoleKey]::Escape -or $isControlC
            }

            function Read-PackageExportPath
            {
                param(
                    [Parameter(Mandatory)]
                    [String]$ScopeDescription
                )

                $restoreInPlaceRedraw = $pickerRenderState.UseInPlaceRedraw
                $pickerRenderState.UseInPlaceRedraw = $false
                $pickerRenderState.RenderedLineCount = 0

                $workingPath = ''
                $validationMessage = ''
                try
                {
                    while ($true)
                    {
                        Clear-Host
                        Write-Host 'Export installed packages' -ForegroundColor Cyan
                        Write-Host ''
                        Write-Host "Scope: $ScopeDescription" -ForegroundColor White
                        Write-Host 'Formats: .json and .csv are supported. The format is inferred from the file extension.' -ForegroundColor DarkGray
                        Write-Host ''
                        Write-Host "File: $workingPath" -ForegroundColor White
                        if (-not [String]::IsNullOrWhiteSpace($validationMessage))
                        {
                            Write-Host $validationMessage -ForegroundColor DarkYellow
                        }
                        Write-Host ''
                        Write-Host 'Enter: continue  Backspace: delete  Ctrl+U: clear  Esc/Ctrl+C: cancel' -ForegroundColor DarkGray

                        $pathKey = & $KeyReader
                        if (Test-PackageTextPromptCancelKey -KeyInfo $pathKey)
                        {
                            return $null
                        }

                        if ($pathKey.Key -eq [ConsoleKey]::Enter)
                        {
                            $candidatePath = $workingPath.Trim()
                            if ([String]::IsNullOrWhiteSpace($candidatePath))
                            {
                                $validationMessage = 'File path is required.'
                                continue
                            }

                            return $candidatePath
                        }

                        if ($pathKey.Key -eq [ConsoleKey]::Backspace)
                        {
                            if ($workingPath.Length -gt 0)
                            {
                                $workingPath = $workingPath.Substring(0, $workingPath.Length - 1)
                            }

                            $validationMessage = ''
                            continue
                        }

                        $isCtrlU = $pathKey.Key -eq [ConsoleKey]::U -and (($pathKey.Modifiers -band [ConsoleModifiers]::Control) -eq [ConsoleModifiers]::Control)
                        if ($isCtrlU)
                        {
                            $workingPath = ''
                            $validationMessage = ''
                            continue
                        }

                        if (-not [Char]::IsControl($pathKey.KeyChar))
                        {
                            $workingPath += $pathKey.KeyChar
                            $validationMessage = ''
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

            function Get-PackageExportFormatFromPath
            {
                param(
                    [Parameter(Mandatory)]
                    [String]$Path
                )

                $extension = [System.IO.Path]::GetExtension($Path)
                if ([String]::IsNullOrWhiteSpace($extension))
                {
                    return ''
                }

                switch ($extension.ToLowerInvariant())
                {
                    '.json' { return 'Json' }
                    '.csv' { return 'Csv' }
                    default { return '' }
                }
            }

            function Read-PackageExportFormat
            {
                param(
                    [Parameter(Mandatory)]
                    [String]$Path
                )

                $restoreInPlaceRedraw = $pickerRenderState.UseInPlaceRedraw
                $pickerRenderState.UseInPlaceRedraw = $false
                $pickerRenderState.RenderedLineCount = 0

                try
                {
                    while ($true)
                    {
                        Clear-Host
                        Write-Host 'Choose export format' -ForegroundColor Cyan
                        Write-Host ''
                        Write-Host "File: $Path" -ForegroundColor White
                        Write-Host 'The file extension does not identify a supported format.' -ForegroundColor DarkYellow
                        Write-Host ''
                        Write-Host 'J: JSON  C: CSV  Esc/Ctrl+C: cancel' -ForegroundColor DarkGray

                        $formatKey = & $KeyReader
                        if (Test-PackageTextPromptCancelKey -KeyInfo $formatKey)
                        {
                            return ''
                        }

                        if ($formatKey.Key -eq [ConsoleKey]::J)
                        {
                            return 'Json'
                        }

                        if ($formatKey.Key -eq [ConsoleKey]::C)
                        {
                            return 'Csv'
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

            function Read-PackageExportDependencyChoice
            {
                param(
                    [Parameter(Mandatory)]
                    [String]$Format,

                    [Parameter(Mandatory)]
                    [String]$ScopeDescription
                )

                $restoreInPlaceRedraw = $pickerRenderState.UseInPlaceRedraw
                $pickerRenderState.UseInPlaceRedraw = $false
                $pickerRenderState.RenderedLineCount = 0

                try
                {
                    while ($true)
                    {
                        Clear-Host
                        Write-Host 'Export installed packages' -ForegroundColor Cyan
                        Write-Host ''
                        Write-Host "Scope: $ScopeDescription" -ForegroundColor White
                        Write-Host "Format: $Format" -ForegroundColor White
                        Write-Host ''
                        Write-Host 'Include dependency relationships in the export?' -ForegroundColor White
                        Write-Host 'Dependency lookup can be slow for large exports.' -ForegroundColor DarkYellow
                        Write-Host 'D/Y: direct dependencies  B: direct + required-by  N/Enter: packages only  Esc/Ctrl+C: cancel' -ForegroundColor DarkGray

                        $dependencyKey = & $KeyReader
                        if (Test-PackageTextPromptCancelKey -KeyInfo $dependencyKey)
                        {
                            return [PSCustomObject]@{
                                Canceled = $true
                                Include = $false
                                Mode = 'None'
                            }
                        }

                        if ($dependencyKey.Key -eq [ConsoleKey]::D -or $dependencyKey.Key -eq [ConsoleKey]::Y)
                        {
                            return [PSCustomObject]@{
                                Canceled = $false
                                Include = $true
                                Mode = 'DependsOn'
                            }
                        }

                        if ($dependencyKey.Key -eq [ConsoleKey]::B)
                        {
                            return [PSCustomObject]@{
                                Canceled = $false
                                Include = $true
                                Mode = 'Both'
                            }
                        }

                        if ($dependencyKey.Key -eq [ConsoleKey]::N -or $dependencyKey.Key -eq [ConsoleKey]::Enter)
                        {
                            return [PSCustomObject]@{
                                Canceled = $false
                                Include = $false
                                Mode = 'None'
                            }
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

            function Get-PackageExportTarget
            {
                if ($EnableSelection -and $selectedKeys.Count -gt 0)
                {
                    $selectedPackages = @($allPackages | Where-Object { $selectedKeys.Contains((Get-PackagePickerKey -Package $_)) })
                    return [PSCustomObject]@{
                        Packages = $selectedPackages
                        ScopeDescription = "$($selectedPackages.Count) selected package(s)"
                    }
                }

                return [PSCustomObject]@{
                    Packages = @($visiblePackages)
                    ScopeDescription = "$($visiblePackages.Count) visible package(s)"
                }
            }

            function Test-PackageExportCancelRequested
            {
                if (-not $usingConsoleKeyReader)
                {
                    return $false
                }

                try
                {
                    if ([Console]::IsInputRedirected)
                    {
                        return $false
                    }

                    while ([Console]::KeyAvailable)
                    {
                        $cancelKey = [Console]::ReadKey($true)
                        if ($cancelKey.Key -eq [ConsoleKey]::Escape)
                        {
                            return $true
                        }

                        $isControlC = $cancelKey.Key -eq [ConsoleKey]::C -and (($cancelKey.Modifiers -band [ConsoleModifiers]::Control) -eq [ConsoleModifiers]::Control)
                        $isControlC = $isControlC -or ([Int32][Char]$cancelKey.KeyChar -eq 3)
                        if ($isControlC)
                        {
                            return $true
                        }
                    }
                }
                catch
                {
                    Write-Verbose "Unable to inspect pending export cancel keys: $($_.Exception.Message)"
                }

                return $false
            }

            function Invoke-PackageExportPrompt
            {
                $exportTarget = Get-PackageExportTarget
                if (@($exportTarget.Packages).Count -eq 0)
                {
                    return [PSCustomObject]@{
                        Succeeded = $false
                        Message = 'Export failed: no packages are available for the current scope'
                    }
                }

                $exportPath = Read-PackageExportPath -ScopeDescription $exportTarget.ScopeDescription
                if ([String]::IsNullOrWhiteSpace($exportPath))
                {
                    return $null
                }

                $exportFormat = Get-PackageExportFormatFromPath -Path $exportPath
                if ([String]::IsNullOrWhiteSpace($exportFormat))
                {
                    $exportFormat = Read-PackageExportFormat -Path $exportPath
                    if ([String]::IsNullOrWhiteSpace($exportFormat))
                    {
                        return $null
                    }
                }

                $dependencyChoice = Read-PackageExportDependencyChoice -Format $exportFormat.ToUpperInvariant() -ScopeDescription $exportTarget.ScopeDescription
                if ($dependencyChoice.Canceled)
                {
                    return $null
                }

                try
                {
                    Clear-Host
                    Write-Host 'Exporting installed packages...' -ForegroundColor Cyan
                    Write-Host "Scope: $($exportTarget.ScopeDescription)" -ForegroundColor White
                    Write-Host "File: $exportPath" -ForegroundColor White
                    if ($dependencyChoice.Include)
                    {
                        Write-Host 'Resolving dependencies...' -ForegroundColor DarkGray
                    }

                    $exportTreatControlCAsInputChanged = $false
                    $exportPreviousTreatControlCAsInput = $false
                    if ($usingConsoleKeyReader)
                    {
                        try
                        {
                            $exportPreviousTreatControlCAsInput = [Console]::TreatControlCAsInput
                            [Console]::TreatControlCAsInput = $false
                            $exportTreatControlCAsInputChanged = $true
                        }
                        catch
                        {
                            Write-Verbose "Unable to enable Ctrl+C interruption during export: $($_.Exception.Message)"
                        }
                    }

                    try
                    {
                        $packageExportCancelRequested = ${function:Test-PackageExportCancelRequested}.GetNewClosure()
                        $exportParameters = @{
                            Package = @($exportTarget.Packages)
                            Path = $exportPath
                            Format = $exportFormat
                            DependencyMode = $dependencyChoice.Mode
                            ShowProgress = $true
                            CancelRequested = $packageExportCancelRequested
                        }
                        if ($CommandRunner)
                        {
                            $exportParameters.CommandRunner = $CommandRunner
                        }

                        $exportResult = Export-InstalledPlatformPackage @exportParameters
                    }
                    finally
                    {
                        if ($exportTreatControlCAsInputChanged)
                        {
                            try
                            {
                                [Console]::TreatControlCAsInput = $exportPreviousTreatControlCAsInput
                            }
                            catch
                            {
                                Write-Verbose "Unable to restore Ctrl+C picker handling after export: $($_.Exception.Message)"
                            }
                        }
                    }

                    $dependencyText = switch ($exportResult.DependencyMode)
                    {
                        'DependsOn' { ' with dependencies' }
                        'Both' { ' with dependencies and required-by relationships' }
                        default { '' }
                    }
                    return [PSCustomObject]@{
                        Succeeded = $true
                        Message = "Exported $($exportResult.Count) package(s)$dependencyText to $($exportResult.Path) ($($exportResult.Format))"
                    }
                }
                catch [System.OperationCanceledException]
                {
                    return [PSCustomObject]@{
                        Succeeded = $false
                        Message = 'Export canceled.'
                    }
                }
                catch [System.Management.Automation.PipelineStoppedException]
                {
                    return [PSCustomObject]@{
                        Succeeded = $false
                        Message = 'Export canceled.'
                    }
                }
                catch
                {
                    return [PSCustomObject]@{
                        Succeeded = $false
                        Message = "Export failed: $($_.Exception.Message)"
                    }
                }
                finally
                {
                    Clear-Host
                    $pickerRenderState.RenderedLineCount = 0
                }
            }

            function Get-DependencyPanelSections
            {
                param(
                    [Parameter(Mandatory)]
                    [PSCustomObject]$Package
                )

                $sections = @()
                foreach ($direction in @('DependsOn', 'RequiredBy'))
                {
                    $parameters = @{
                        Package = @($Package)
                        Direction = $direction
                        PackageManager = $Package.PackageManager
                    }
                    if ($CommandRunner)
                    {
                        $parameters.CommandRunner = $CommandRunner
                    }

                    try
                    {
                        $records = @(Get-PlatformPackageDependency @parameters)
                        if ($records.Count -eq 0)
                        {
                            $sections += [PSCustomObject]@{
                                Direction = $direction
                                Error = ''
                                Lines = @('(none found)')
                            }
                            continue
                        }

                        $lines = @()
                        foreach ($record in $records | Select-Object -First 8)
                        {
                            $installedMarker = if ($record.Installed) { ' [installed]' } else { '' }
                            $lines += "- $($record.RelatedPackage) ($($record.DependencyType))$installedMarker"
                        }

                        if ($records.Count -gt $lines.Count)
                        {
                            $lines += "... and $($records.Count - $lines.Count) more"
                        }

                        $sections += [PSCustomObject]@{
                            Direction = $direction
                            Error = ''
                            Lines = $lines
                        }
                    }
                    catch
                    {
                        $sections += [PSCustomObject]@{
                            Direction = $direction
                            Error = $_.Exception.Message
                            Lines = @()
                        }
                    }
                }

                return $sections
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

                $showDependencyPanel = $false
                $dependencyPanelRestoreInPlaceRedraw = $null
                $dependencyPanelPackageKey = ''
                $dependencyPanelSections = @()
                $pendingDependencyPanelPackage = $null
                $actionStatus = ''
                $actionStatusColor = [ConsoleColor]::DarkGray

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

                    $frameLines = @(
                        (Format-PickerFrameLine -Text "Show-InstalledPlatformPackage - $($InstalledPackages[0].PackageManagerDisplayName)" -ForegroundColor Cyan)
                    )

                    if ($showDependencyPanel -and $null -ne $currentPackage -and $dependencyPanelPackageKey -ne $currentPackageLookupKey)
                    {
                        $pendingDependencyPanelPackage = $currentPackage
                        $dependencyPanelSections = @(
                            [PSCustomObject]@{
                                Direction = 'Resolving'
                                Error = ''
                                Lines = @('Resolving dependencies...')
                            }
                        )
                    }

                    $sourceHint = if ($hasSourceFilter) { "S: [$($availableSources[$sourceFilterIndex])]  " } else { '' }
                    $nameFilterHintValue = if ([String]::IsNullOrWhiteSpace($nameFilterText)) { 'all' } else { $nameFilterText }
                    $nameFilterHint = "F: [$nameFilterHintValue]  "

                    if ($showDependencyPanel)
                    {
                        $currentVersion = if ([String]::IsNullOrWhiteSpace($currentPackage.InstalledVersion)) { 'n/a' } else { $currentPackage.InstalledVersion }
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

                        $dependencyFilterSummary = @("filter: $nameFilterHintValue")
                        if ($hasSourceFilter)
                        {
                            $dependencyFilterSummary += "source: $($availableSources[$sourceFilterIndex])"
                        }

                        $frameLines = @(
                            (Format-PickerFrameLine -Text "Show-InstalledPlatformPackage Dependencies - $($InstalledPackages[0].PackageManagerDisplayName)" -ForegroundColor Cyan)
                            (Format-PickerFrameLine -Text (Get-PickerViewportSummary -TopIndex $topIndex -BottomIndex $bottomIndex -VisibleCount $visiblePackages.Count -TotalCount $allPackages.Count -SelectedCount (-1) -FilterText ($dependencyFilterSummary -join "  $([char]0x00B7)  ")) -ForegroundColor White)
                            ''
                            (Format-PickerFrameLine -Text "Keys: B/Backspace/Delete/LeftArrow back  V details  E export  ${nameFilterHint}" -ForegroundColor DarkGray)
                            (Format-PickerFrameLine -Text "Nav: ${sourceHint}Home/End/PgUp/PgDn  ?: help  Q/Esc/Ctrl+C exit" -ForegroundColor DarkGray)
                            ''
                            (Format-PickerFrameLine -Text ('Current: {0}' -f $currentPackage.Name) -ForegroundColor DarkGray)
                            (Format-PickerFrameLine -Text ('Id: {0} | Source: {1} | Publisher: {2}' -f $currentPackage.Id, $currentSource, $currentPublisher) -ForegroundColor DarkGray)
                            (Format-PickerFrameLine -Text ('Version: {0}' -f $currentVersion) -ForegroundColor DarkGray)
                            (Format-PickerFrameLine -Text ('Description: {0}' -f $currentDescription) -ForegroundColor DarkGray)
                            ''
                            (Format-PickerFrameLine -Text 'Dependencies [DependsOn + RequiredBy]' -ForegroundColor White)
                        )

                        foreach ($dependencySection in $dependencyPanelSections)
                        {
                            if ($dependencySection.Direction -eq 'Resolving')
                            {
                                $frameLines += ''
                                foreach ($dependencyLine in $dependencySection.Lines)
                                {
                                    $frameLines += Format-PickerFrameLine -Text $dependencyLine -ForegroundColor DarkGray
                                }

                                continue
                            }

                            $frameLines += ''
                            $frameLines += Format-PickerFrameLine -Text ("Dependencies [$($dependencySection.Direction)]") -ForegroundColor White

                            if (-not [String]::IsNullOrWhiteSpace($dependencySection.Error))
                            {
                                $frameLines += Format-PickerFrameLine -Text ("Dependency lookup failed: $($dependencySection.Error)") -ForegroundColor DarkYellow
                                continue
                            }

                            foreach ($dependencyLine in $dependencySection.Lines)
                            {
                                $frameLines += $dependencyLine
                            }
                        }

                        $frameLines += ''
                        $frameLines += Format-PickerFrameLine -Text 'Press B/Backspace/Delete/LeftArrow to return to the package list.' -ForegroundColor DarkGray
                        Write-PickerFrame -Lines $frameLines

                        if ($null -ne $pendingDependencyPanelPackage)
                        {
                            $terminalEchoState = Disable-PickerTerminalEcho
                            try
                            {
                                $dependencyPanelSections = @(Get-DependencyPanelSections -Package $pendingDependencyPanelPackage)
                            }
                            finally
                            {
                                Restore-PickerTerminalEcho -State $terminalEchoState
                            }

                            $dependencyPanelPackageKey = $currentPackageLookupKey
                            $pendingDependencyPanelPackage = $null
                            Clear-PendingConsoleInput
                            continue
                        }
                    }
                    else
                    {
                        if ($EnableSelection)
                        {
                            $filterSummary = @("filter: $nameFilterHintValue")
                            if ($hasSourceFilter)
                            {
                                $filterSummary += "source: $($availableSources[$sourceFilterIndex])"
                            }
                            $frameLines += Format-PickerFrameLine -Text (Get-PickerViewportSummary -TopIndex $topIndex -BottomIndex $bottomIndex -VisibleCount $visiblePackages.Count -TotalCount $allPackages.Count -SelectedCount $selectedKeys.Count -FilterText ($filterSummary -join "  $([char]0x00B7)  ")) -ForegroundColor White
                            $frameLines += Format-PickerFrameLine -Text "Keys: Space select  Enter return  D deps  V details  E export  R remove  U upgrade  A toggle all  F: [$nameFilterHintValue]" -ForegroundColor DarkGray
                            $frameLines += Format-PickerFrameLine -Text "Nav: ${sourceHint}Home/End/PgUp/PgDn  ?: help  Q/Esc/Ctrl+C exit" -ForegroundColor DarkGray
                            if ($ReturnToPlatformPackageManagerOnBackKey)
                            {
                                $frameLines += Format-PickerFrameLine -Text 'Backspace/Delete: manager menu' -ForegroundColor DarkGray
                            }
                            $frameLines += ''
                            $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4} {5}' -f 'Sel', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Id' -Width $idWidth), (Format-PickerCell -Text 'Ver' -Width $versionWidth), (Format-PickerCell -Text 'Typ' -Width $typeWidth), (Format-PickerCell -Text 'Src' -Width $sourceWidth)) -ForegroundColor DarkGray
                            $frameLines += Format-PickerFrameLine -Text ('- {0} {1} {2} {3} {4} {5}' -f '---', ('-' * $nameWidth), ('-' * $idWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth)) -ForegroundColor DarkGray
                        }
                        else
                        {
                            $filterSummary = @("filter: $nameFilterHintValue")
                            if ($hasSourceFilter)
                            {
                                $filterSummary += "source: $($availableSources[$sourceFilterIndex])"
                            }
                            $frameLines += Format-PickerFrameLine -Text (Get-PickerViewportSummary -TopIndex $topIndex -BottomIndex $bottomIndex -VisibleCount $visiblePackages.Count -TotalCount $allPackages.Count -FilterText ($filterSummary -join "  $([char]0x00B7)  ")) -ForegroundColor White
                            $frameLines += Format-PickerFrameLine -Text "Keys: D deps  V details  E export  R remove  U upgrade  F: [$nameFilterHintValue]" -ForegroundColor DarkGray
                            $frameLines += Format-PickerFrameLine -Text "Nav: ${sourceHint}Home/End/PgUp/PgDn  ?: help  Q/Esc/Ctrl+C exit" -ForegroundColor DarkGray
                            if ($ReturnToPlatformPackageManagerOnBackKey)
                            {
                                $frameLines += Format-PickerFrameLine -Text 'Backspace/Delete: manager menu' -ForegroundColor DarkGray
                            }
                            $frameLines += ''
                            $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4}' -f (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Id' -Width $idWidth), (Format-PickerCell -Text 'Ver' -Width $versionWidth), (Format-PickerCell -Text 'Typ' -Width $typeWidth), (Format-PickerCell -Text 'Src' -Width $sourceWidth)) -ForegroundColor DarkGray
                            $frameLines += Format-PickerFrameLine -Text ('- {0} {1} {2} {3} {4}' -f ('-' * $nameWidth), ('-' * $idWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth)) -ForegroundColor DarkGray
                        }

                        if ($visiblePackages.Count -eq 0)
                        {
                            $frameLines += ''
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
                                if (Show-PackagePickerHelp) { Clear-PickerFrame; return @() }
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

                        for ($i = $topIndex; $i -le $bottomIndex; $i++)
                        {
                            $package = $visiblePackages[$i]
                            $pkgKey = Get-PackagePickerKey -Package $package
                            $cursorMarker = if ($i -eq $cursor) { '>' } else { ' ' }

                            if ($EnableSelection)
                            {
                                $selectedMarker = if ($selectedKeys.Contains($pkgKey)) { '[x]' } else { '[ ]' }
                                $packageLine = ('{0} {1} {2} {3} {4} {5} {6}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Id -Width $idWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $versionWidth), (Format-PickerCell -Text (Get-PackageTypeDisplay -Type $package.Type) -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                            }
                            else
                            {
                                $packageLine = ('{0} {1} {2} {3} {4} {5}' -f $cursorMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Id -Width $idWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $versionWidth), (Format-PickerCell -Text (Get-PackageTypeDisplay -Type $package.Type) -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
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
                            else
                            {
                                $frameLines += $packageLine
                            }
                        }

                        $currentVersion = if ([String]::IsNullOrWhiteSpace($currentPackage.InstalledVersion)) { 'n/a' } else { $currentPackage.InstalledVersion }
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

                        $frameLines += ''
                        $frameLines += Format-PickerFrameLine -Text ('Current: {0}' -f $currentPackage.Name) -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('Id: {0} | Source: {1} | Publisher: {2}' -f $currentPackage.Id, $currentSource, $currentPublisher) -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('Version: {0}' -f $currentVersion) -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('Description: {0}' -f $currentDescription) -ForegroundColor DarkGray

                        if (-not [String]::IsNullOrWhiteSpace($actionStatus))
                        {
                            $frameLines += ''
                            $frameLines += Format-PickerFrameLine -Text ("Status: $actionStatus") -ForegroundColor $actionStatusColor
                        }

                        if ($EnableSelection)
                        {
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
                        }

                        Write-PickerFrame -Lines $frameLines
                    }

                    if ($isCurrentWingetDescriptionPending)
                    {
                        $wingetDescriptionAttempted[$currentPackageLookupKey] = $true
                        $resolvedDescription = Get-WingetPackageDescription -Manager ([PSCustomObject]@{
                                Name = $currentPackage.PackageManager
                                DisplayName = $currentPackage.PackageManagerDisplayName
                                Command = $currentPackage.PackageManager
                            }) -Package $currentPackage

                        if (-not [String]::IsNullOrWhiteSpace($resolvedDescription))
                        {
                            $currentPackage.Description = $resolvedDescription
                        }

                        $pendingWingetDescriptionLookupKey = ''
                        continue
                    }

                    $key = & $KeyReader
                    if (-not $showDependencyPanel -and (Test-PackagePickerManagerBackKey -KeyInfo $key))
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
                            if ($EnableSelection)
                            {
                                $pkgKey = Get-PackagePickerKey -Package $visiblePackages[$cursor]
                                if ($selectedKeys.Contains($pkgKey)) { $null = $selectedKeys.Remove($pkgKey) }
                                else { $null = $selectedKeys.Add($pkgKey) }
                            }
                        }
                        'A'
                        {
                            if ($EnableSelection)
                            {
                                $allVisibleSelected = @($visiblePackages | Where-Object { -not $selectedKeys.Contains((Get-PackagePickerKey -Package $_)) }).Count -eq 0
                                if ($allVisibleSelected)
                                {
                                    foreach ($vp in $visiblePackages) { $null = $selectedKeys.Remove((Get-PackagePickerKey -Package $vp)) }
                                }
                                else
                                {
                                    foreach ($vp in $visiblePackages) { $null = $selectedKeys.Add((Get-PackagePickerKey -Package $vp)) }
                                }
                            }
                        }
                        'D'
                        {
                            $showDependencyPanel = -not $showDependencyPanel
                            if ($showDependencyPanel)
                            {
                                $dependencyPanelRestoreInPlaceRedraw = $pickerRenderState.UseInPlaceRedraw
                                $pickerRenderState.UseInPlaceRedraw = $false
                                $pickerRenderState.RenderedLineCount = 0
                                $dependencyPanelPackageKey = ''
                                $pendingDependencyPanelPackage = $null
                            }
                            elseif ($null -ne $dependencyPanelRestoreInPlaceRedraw)
                            {
                                $pickerRenderState.UseInPlaceRedraw = $dependencyPanelRestoreInPlaceRedraw
                                $dependencyPanelRestoreInPlaceRedraw = $null
                                $pickerRenderState.RenderedLineCount = 0
                                $pendingDependencyPanelPackage = $null
                            }
                        }
                        'B'
                        {
                            if ($showDependencyPanel)
                            {
                                $showDependencyPanel = $false
                                if ($null -ne $dependencyPanelRestoreInPlaceRedraw)
                                {
                                    $pickerRenderState.UseInPlaceRedraw = $dependencyPanelRestoreInPlaceRedraw
                                    $dependencyPanelRestoreInPlaceRedraw = $null
                                    $pickerRenderState.RenderedLineCount = 0
                                    $pendingDependencyPanelPackage = $null
                                }
                            }
                        }
                        'Backspace'
                        {
                            if ($showDependencyPanel)
                            {
                                $showDependencyPanel = $false
                                if ($null -ne $dependencyPanelRestoreInPlaceRedraw)
                                {
                                    $pickerRenderState.UseInPlaceRedraw = $dependencyPanelRestoreInPlaceRedraw
                                    $dependencyPanelRestoreInPlaceRedraw = $null
                                    $pickerRenderState.RenderedLineCount = 0
                                    $pendingDependencyPanelPackage = $null
                                }
                            }
                        }
                        'Delete'
                        {
                            if ($showDependencyPanel)
                            {
                                $showDependencyPanel = $false
                                if ($null -ne $dependencyPanelRestoreInPlaceRedraw)
                                {
                                    $pickerRenderState.UseInPlaceRedraw = $dependencyPanelRestoreInPlaceRedraw
                                    $dependencyPanelRestoreInPlaceRedraw = $null
                                    $pickerRenderState.RenderedLineCount = 0
                                    $pendingDependencyPanelPackage = $null
                                }
                            }
                        }
                        'LeftArrow'
                        {
                            if ($showDependencyPanel)
                            {
                                $showDependencyPanel = $false
                                if ($null -ne $dependencyPanelRestoreInPlaceRedraw)
                                {
                                    $pickerRenderState.UseInPlaceRedraw = $dependencyPanelRestoreInPlaceRedraw
                                    $dependencyPanelRestoreInPlaceRedraw = $null
                                    $pickerRenderState.RenderedLineCount = 0
                                    $pendingDependencyPanelPackage = $null
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
                        'E'
                        {
                            $exportResult = Invoke-PackageExportPrompt
                            if ($null -ne $exportResult)
                            {
                                $actionStatus = $exportResult.Message
                                $actionStatusColor = if ($exportResult.Succeeded) { [ConsoleColor]::Green } else { [ConsoleColor]::DarkYellow }
                            }
                        }
                        'R'
                        {
                            if ($null -ne $currentPackage -and (Read-PackageActionConfirmation -Action 'Remove' -Package $currentPackage))
                            {
                                $targetPackage = if (-not [String]::IsNullOrWhiteSpace($currentPackage.Id)) { $currentPackage.Id } else { $currentPackage.Name }
                                $removeParameters = @{
                                    PackageManager = $currentPackage.PackageManager
                                    IncludePackage = @($targetPackage)
                                    All = $true
                                    FilterSource = $currentPackage.Source
                                    Confirm = $false
                                }
                                if ($CommandRunner)
                                {
                                    $removeParameters.CommandRunner = $CommandRunner
                                }

                                $removeResult = Remove-PlatformPackage @removeParameters
                                $actionStatus = "Removed: $($removeResult.Removed), Failed: $($removeResult.Failed), Skipped: $($removeResult.Skipped)"
                                $actionStatusColor = if ([Int32]$removeResult.Failed -gt 0) { [ConsoleColor]::DarkYellow } else { [ConsoleColor]::Green }
                            }
                        }
                        'U'
                        {
                            if ($null -ne $currentPackage -and (Read-PackageActionConfirmation -Action 'Upgrade' -Package $currentPackage))
                            {
                                $targetPackage = if (-not [String]::IsNullOrWhiteSpace($currentPackage.Id)) { $currentPackage.Id } else { $currentPackage.Name }
                                $upgradeParameters = @{
                                    PackageManager = $currentPackage.PackageManager
                                    IncludePackage = @($targetPackage)
                                    All = $true
                                    FilterSource = $currentPackage.Source
                                    SkipRefresh = $true
                                    Confirm = $false
                                }
                                if ($CommandRunner)
                                {
                                    $upgradeParameters.CommandRunner = $CommandRunner
                                }

                                $upgradeResult = Upgrade-PlatformPackage @upgradeParameters
                                $actionStatus = "Upgraded: $($upgradeResult.Upgraded), Failed: $($upgradeResult.Failed), Skipped: $($upgradeResult.Skipped)"
                                if ([Int32]$upgradeResult.Failed -gt 0)
                                {
                                    $failureMessage = Get-PackageActionFirstFailureMessage -ActionResult $upgradeResult
                                    if (-not [String]::IsNullOrWhiteSpace($failureMessage))
                                    {
                                        $actionStatus = "$actionStatus; First failure: $failureMessage"
                                    }
                                }
                                $actionStatusColor = if ([Int32]$upgradeResult.Failed -gt 0) { [ConsoleColor]::DarkYellow } else { [ConsoleColor]::Green }
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
                            if (-not $EnableSelection)
                            {
                                break
                            }

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
    }

    process
    {
        $getPlatformPackageParameters = @{
            PackageManager = $PackageManager
            Name = $Name
            ExcludePackage = $ExcludePackage
            CommandRunner = $CommandRunner
        }
        if (-not $NonInteractive -and (Test-InteractiveWingetDescriptionEnrichmentShouldBeSkipped))
        {
            $getPlatformPackageParameters.SkipDescriptionEnrichment = $true
        }

        if (-not [String]::IsNullOrWhiteSpace($ExportPath) -and -not $CommandRunner)
        {
            Write-Host 'Loading packages...' -ForegroundColor Cyan
        }

        $installedPackages = @(Get-PlatformPackage @getPlatformPackageParameters)

        if (-not [String]::IsNullOrWhiteSpace($ExportPath))
        {
            $exportParameters = @{
                Package = $installedPackages
                Path = $ExportPath
                Format = $ExportFormat
                DependencyMode = $ExportDependencyMode
            }
            if ($ShowExportProgress)
            {
                $exportParameters.ShowProgress = $true
            }
            if ($ExportCancelRequested)
            {
                $exportParameters.CancelRequested = $ExportCancelRequested
            }
            if ($CommandRunner)
            {
                $exportParameters.CommandRunner = $CommandRunner
            }

            return (Export-InstalledPlatformPackage @exportParameters)
        }

        if ($NonInteractive)
        {
            return $installedPackages
        }

        if ($installedPackages.Count -eq 0)
        {
            $hasInputFilter = $Name.Count -gt 0 -or $ExcludePackage.Count -gt 0 -or -not [String]::IsNullOrWhiteSpace($FilterSource)
            Write-Host (if ($hasInputFilter) { 'No installed packages matched the requested filters.' } else { 'No installed packages found.' }) -ForegroundColor White
            return @()
        }

        $selectedPackages = @(
            Select-InstalledPackageRecords -InstalledPackages $installedPackages -KeyReader $KeyReader -PageSize $PickerPageSize -EnableSelection:$PassThru.IsPresent -SourceFilter $FilterSource -CommandRunner $CommandRunner -ReturnToPlatformPackageManagerOnBackKey:$ReturnToPlatformPackageManagerOnBackKey
        )

        if ($PassThru)
        {
            return $selectedPackages
        }

        return @()
    }
}
