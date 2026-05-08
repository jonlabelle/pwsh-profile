function Show-InstalledPlatformPackage
{
    <#
    .SYNOPSIS
        Displays installed packages from the native platform package manager.

    .DESCRIPTION
        Gets installed packages by calling Get-PlatformPackage and renders them in a
        read-only interactive browser when a console is available. The browser supports
        paging and navigation across installed packages on winget, Homebrew, apt, and apk.

        Use -NonInteractive to bypass the interactive browser and return package objects
        directly. Use -PassThru to select one or more packages in the browser and return
        them when Enter is pressed. If nothing is selected, Enter returns the current
        package.

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
        PS > Show-InstalledPlatformPackage -PassThru

        Opens the browser, lets you select packages with the spacebar, and returns the
        selected records when Enter is pressed. If nothing is selected, Enter returns the
        current package.

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
                [String]$SourceFilter = ''
            )

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
                        $reservedRows = 9
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

            $nameWidth = [Math]::Min(36, [Math]::Max(4, (($InstalledPackages | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)))
            $idWidth = [Math]::Min(34, [Math]::Max(2, (($InstalledPackages | ForEach-Object { "$($_.Id)".Length } | Measure-Object -Maximum).Maximum)))
            $versionWidth = [Math]::Min(20, [Math]::Max(7, (($InstalledPackages | ForEach-Object { $_.InstalledVersion.Length } | Measure-Object -Maximum).Maximum)))
            $typeWidth = [Math]::Min(12, [Math]::Max(4, (($InstalledPackages | ForEach-Object { $_.Type.Length } | Measure-Object -Maximum).Maximum)))
            $sourceWidth = [Math]::Min(18, [Math]::Max(6, (($InstalledPackages | ForEach-Object { $_.Source.Length } | Measure-Object -Maximum).Maximum)))
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
                Write-Host 'Actions' -ForegroundColor White
                Write-PackagePickerHelpItem -Shortcut 'D' -Description 'load a missing winget description when available'
                Write-PackagePickerHelpItem -Shortcut 'Q, Esc, or Ctrl+C' -Description 'exit the browser'
                Write-PackagePickerHelpItem -Shortcut '?' -Description 'show this help'

                if ($EnableSelection)
                {
                    Write-PackagePickerHelpItem -Shortcut 'Spacebar' -Description 'select or clear the current package'
                    Write-PackagePickerHelpItem -Shortcut 'A' -Description 'toggle all visible packages'
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

                    $frameLines = @(
                        (Format-PickerFrameLine -Text "Show-InstalledPlatformPackage - $($InstalledPackages[0].PackageManagerDisplayName)" -ForegroundColor Cyan)
                        ''
                    )

                    $sourceHint = if ($hasSourceFilter) { "S: [$($availableSources[$sourceFilterIndex])]  " } else { '' }
                    if ($EnableSelection)
                    {
                        $frameLines += Format-PickerFrameLine -Text "Spacebar: select  Enter: return current/selected  A: toggle all  ${sourceHint}Arrow keys/Home/End/PgUp/PgDn: navigate  ?: help  Ctrl+C/Q/Esc: exit" -ForegroundColor DarkGray
                        $frameLines += ''
                        $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4} {5}' -f 'Sel', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Id' -Width $idWidth), (Format-PickerCell -Text 'Version' -Width $versionWidth), (Format-PickerCell -Text 'Type' -Width $typeWidth), (Format-PickerCell -Text 'Source' -Width $sourceWidth)) -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4} {5}' -f '---', ('-' * $nameWidth), ('-' * $idWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth)) -ForegroundColor DarkGray
                    }
                    else
                    {
                        $frameLines += Format-PickerFrameLine -Text "${sourceHint}Arrow keys/Home/End/PgUp/PgDn: navigate  ?: help  Ctrl+C/Q/Esc: exit" -ForegroundColor DarkGray
                        $frameLines += ''
                        $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4}' -f (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Id' -Width $idWidth), (Format-PickerCell -Text 'Version' -Width $versionWidth), (Format-PickerCell -Text 'Type' -Width $typeWidth), (Format-PickerCell -Text 'Source' -Width $sourceWidth)) -ForegroundColor DarkGray
                        $frameLines += Format-PickerFrameLine -Text ('  {0} {1} {2} {3} {4}' -f ('-' * $nameWidth), ('-' * $idWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth)) -ForegroundColor DarkGray
                    }

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
                        $pkgKey = "$($package.Id)::$($package.Name)"
                        $cursorMarker = if ($i -eq $cursor) { '>' } else { ' ' }

                        if ($EnableSelection)
                        {
                            $selectedMarker = if ($selectedKeys.Contains($pkgKey)) { '[x]' } else { '[ ]' }
                            $packageLine = ('{0} {1} {2} {3} {4} {5} {6}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Id -Width $idWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $versionWidth), (Format-PickerCell -Text $package.Type -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                        }
                        else
                        {
                            $packageLine = ('{0} {1} {2} {3} {4} {5}' -f $cursorMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.Id -Width $idWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $versionWidth), (Format-PickerCell -Text $package.Type -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                        }

                        if ($i -eq $cursor)
                        {
                            $frameLines += Format-PickerFrameLine -Text $packageLine -ForegroundColor Cyan
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
                        if ($wingetDescriptionAttempted.ContainsKey($currentPackageLookupKey)) { 'description unavailable' } else { '<press D to load>' }
                    }
                    else
                    {
                        'n/a'
                    }

                    $frameLines += ''
                    $frameLines += Format-PickerFrameLine -Text ('Current: {0} | Id: {1} | Publisher: {2} | Version: {3} | Source: {4}' -f $currentPackage.Name, $currentPackage.Id, $currentPublisher, $currentVersion, $currentSource) -ForegroundColor White
                    $frameLines += Format-PickerFrameLine -Text ('Description: {0}' -f $currentDescription) -ForegroundColor White
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
                                $pkgKey = "$($visiblePackages[$cursor].Id)::$($visiblePackages[$cursor].Name)"
                                if ($selectedKeys.Contains($pkgKey)) { $null = $selectedKeys.Remove($pkgKey) }
                                else { $null = $selectedKeys.Add($pkgKey) }
                            }
                        }
                        'A'
                        {
                            if ($EnableSelection)
                            {
                                $allVisibleSelected = @($visiblePackages | Where-Object { -not $selectedKeys.Contains("$($_.Id)::$($_.Name)") }).Count -eq 0
                                if ($allVisibleSelected)
                                {
                                    foreach ($vp in $visiblePackages) { $null = $selectedKeys.Remove("$($vp.Id)::$($vp.Name)") }
                                }
                                else
                                {
                                    foreach ($vp in $visiblePackages) { $null = $selectedKeys.Add("$($vp.Id)::$($vp.Name)") }
                                }
                            }
                        }
                        'D'
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
                            if (-not $EnableSelection)
                            {
                                break
                            }

                            Clear-PickerFrame

                            $selectedPackages = @($allPackages | Where-Object { $selectedKeys.Contains("$($_.Id)::$($_.Name)") })
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

        $installedPackages = @(Get-PlatformPackage @getPlatformPackageParameters)

        if ($NonInteractive)
        {
            return $installedPackages
        }

        if ($installedPackages.Count -eq 0)
        {
            Write-Host 'No installed packages matched the requested filters.' -ForegroundColor White
            return @()
        }

        $selectedPackages = @(
            Select-InstalledPackageRecords -InstalledPackages $installedPackages -KeyReader $KeyReader -PageSize $PickerPageSize -EnableSelection:$PassThru.IsPresent -SourceFilter $FilterSource
        )

        if ($PassThru)
        {
            return $selectedPackages
        }

        return @()
    }
}
