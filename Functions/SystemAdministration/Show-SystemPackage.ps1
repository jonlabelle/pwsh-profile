function Show-SystemPackage
{
    <#
    .SYNOPSIS
        Displays installed packages from the native platform package manager.

    .DESCRIPTION
        Gets installed packages by calling Get-SystemPackage and renders them in a
        read-only interactive browser when a console is available. The browser supports
        paging and navigation across installed packages on winget, Homebrew, apt, and apk.

        Use -NonInteractive to bypass the interactive browser and return package objects
        directly. Use -PassThru to select one or more packages in the browser and return
        them when Enter is pressed.

    .PARAMETER Name
        Optional package names or wildcard patterns to include. Matches package Name or Id.

    .PARAMETER ExcludePackage
        Optional package names or wildcard patterns to exclude. Matches package Name or Id.

    .PARAMETER NonInteractive
        Returns installed package records without opening the interactive browser. The
        previous -AsObject spelling is retained as an alias.

    .PARAMETER PassThru
        Allows packages to be selected in the interactive browser and returns the selected
        package records when Enter is pressed.

    .EXAMPLE
        PS > Show-SystemPackage

        Opens the interactive installed package browser for the detected package manager.

    .EXAMPLE
        PS > Show-SystemPackage -Name 'git*'

        Opens the browser filtered to packages whose name or id matches git*.

    .EXAMPLE
        PS > Show-SystemPackage -ExcludePackage '*preview*'

        Opens the browser excluding packages whose name or id matches *preview*.

    .EXAMPLE
        PS > Show-SystemPackage -NonInteractive

        Returns installed packages as objects without opening the browser.

    .EXAMPLE
        PS > Show-SystemPackage -NonInteractive | Format-Table Name, InstalledVersion, Source

        Returns installed packages and formats them as a table.

    .EXAMPLE
        PS > Show-SystemPackage -PassThru

        Opens the browser, lets you select packages with the spacebar, and returns the
        selected records when Enter is pressed.

    .EXAMPLE
        PS > Show-SystemPackage -PassThru -Name 'node*' | Format-Table

        Opens the browser for matching node packages and formats the selected results.

    .EXAMPLE
        PS > Show-SystemPackage -PackageManager winget

        Opens the browser using winget.

    .EXAMPLE
        PS > Show-SystemPackage -PackageManager brew

        Opens the browser using Homebrew.

    .EXAMPLE
        PS > Show-SystemPackage -Verbose

        Opens the browser and writes dependency-loading details to verbose output.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Show-SystemPackage.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Show-SystemPackage.ps1
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

        $getSystemPackageDependencyPath = Get-DependencyPathIfNeeded -FunctionName 'Get-SystemPackage' -RelativePath 'Get-SystemPackage.ps1'
        if (-not [String]::IsNullOrWhiteSpace($getSystemPackageDependencyPath))
        {
            try
            {
                . $getSystemPackageDependencyPath
                Write-Verbose "Loaded Get-SystemPackage from: $getSystemPackageDependencyPath"
            }
            catch
            {
                throw "Failed to load required dependency 'Get-SystemPackage' from '$getSystemPackageDependencyPath': $($_.Exception.Message)"
            }
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
                [Switch]$EnableSelection
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
                    throw 'Interactive package browsing requires an attached console. Use Get-SystemPackage or Show-SystemPackage -NonInteractive in non-interactive sessions.'
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
            $versionWidth = [Math]::Min(20, [Math]::Max(7, (($InstalledPackages | ForEach-Object { $_.InstalledVersion.Length } | Measure-Object -Maximum).Maximum)))
            $typeWidth = [Math]::Min(12, [Math]::Max(4, (($InstalledPackages | ForEach-Object { $_.Type.Length } | Measure-Object -Maximum).Maximum)))
            $sourceWidth = [Math]::Min(18, [Math]::Max(6, (($InstalledPackages | ForEach-Object { $_.Source.Length } | Measure-Object -Maximum).Maximum)))
            $pageSize = Get-PackagePickerPageSize -RequestedPageSize $PageSize -ItemCount $InstalledPackages.Count

            $selected = New-Object 'System.Boolean[]' $InstalledPackages.Count
            $cursor = 0
            $topIndex = 0
            $restoreTreatControlCAsInput = $false
            $previousTreatControlCAsInput = $false
            $pickerRenderState = @{
                UseInPlaceRedraw = $false
                ConsoleBufferWidth = 0
                RenderedLineCount = 0
            }

            function Write-PickerFrame
            {
                param(
                    [Parameter()]
                    [String[]]$Lines = @()
                )

                if (-not $pickerRenderState.UseInPlaceRedraw)
                {
                    Clear-Host
                    foreach ($line in $Lines)
                    {
                        Write-Host $line
                    }

                    return
                }

                $frameWidth = [Math]::Max(1, [Int32]$pickerRenderState.ConsoleBufferWidth)
                $blankLine = ''.PadRight($frameWidth)
                $frameLines = @(
                    foreach ($line in $Lines)
                    {
                        $text = if ($null -eq $line) { '' } else { "$line" }
                        if ($text.Length -ge $frameWidth)
                        {
                            if ($frameWidth -eq 1)
                            {
                                $text.Substring(0, 1)
                            }
                            else
                            {
                                $text.Substring(0, $frameWidth - 1) + '~'
                            }
                        }
                        else
                        {
                            $text.PadRight($frameWidth)
                        }
                    }
                )

                while ($frameLines.Count -lt $pickerRenderState.RenderedLineCount)
                {
                    $frameLines += $blankLine
                }

                try
                {
                    [Console]::SetCursorPosition(0, 0)
                    [Console]::Write(($frameLines -join "`r`n"))
                    $pickerRenderState.RenderedLineCount = $frameLines.Count
                }
                catch
                {
                    $pickerRenderState.UseInPlaceRedraw = $false
                    Clear-Host
                    foreach ($fallbackLine in $Lines)
                    {
                        Write-Host $fallbackLine
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

                    $maxTopIndex = [Math]::Max(0, $InstalledPackages.Count - $pageSize)
                    if ($topIndex -gt $maxTopIndex)
                    {
                        $topIndex = $maxTopIndex
                    }

                    $bottomIndex = [Math]::Min($InstalledPackages.Count - 1, $topIndex + $pageSize - 1)
                    $currentPackage = $InstalledPackages[$cursor]

                    $frameLines = @(
                        "Show-SystemPackage - $($InstalledPackages[0].PackageManagerDisplayName)"
                    )

                    if ($EnableSelection)
                    {
                        $frameLines += 'Spacebar: select  Enter: return selected  A: toggle all  Arrow keys/Home/End/PgUp/PgDn: navigate  Ctrl+C/Q/Esc: exit'
                        $frameLines += ''
                        $frameLines += ('  {0} {1} {2} {3} {4}' -f 'Sel', (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Version' -Width $versionWidth), (Format-PickerCell -Text 'Type' -Width $typeWidth), (Format-PickerCell -Text 'Source' -Width $sourceWidth))
                        $frameLines += ('  {0} {1} {2} {3} {4}' -f '---', ('-' * $nameWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth))
                    }
                    else
                    {
                        $frameLines += 'Arrow keys/Home/End/PgUp/PgDn: navigate  Ctrl+C/Q/Esc: exit'
                        $frameLines += ''
                        $frameLines += ('  {0} {1} {2} {3}' -f (Format-PickerCell -Text 'Name' -Width $nameWidth), (Format-PickerCell -Text 'Version' -Width $versionWidth), (Format-PickerCell -Text 'Type' -Width $typeWidth), (Format-PickerCell -Text 'Source' -Width $sourceWidth))
                        $frameLines += ('  {0} {1} {2} {3}' -f ('-' * $nameWidth), ('-' * $versionWidth), ('-' * $typeWidth), ('-' * $sourceWidth))
                    }

                    for ($i = $topIndex; $i -le $bottomIndex; $i++)
                    {
                        $package = $InstalledPackages[$i]
                        $cursorMarker = if ($i -eq $cursor) { '>' } else { ' ' }

                        if ($EnableSelection)
                        {
                            $selectedMarker = if ($selected[$i]) { '[x]' } else { '[ ]' }
                            $frameLines += ('{0} {1} {2} {3} {4} {5}' -f $cursorMarker, $selectedMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $versionWidth), (Format-PickerCell -Text $package.Type -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                        }
                        else
                        {
                            $frameLines += ('{0} {1} {2} {3} {4}' -f $cursorMarker, (Format-PickerCell -Text $package.Name -Width $nameWidth), (Format-PickerCell -Text $package.InstalledVersion -Width $versionWidth), (Format-PickerCell -Text $package.Type -Width $typeWidth), (Format-PickerCell -Text $package.Source -Width $sourceWidth))
                        }
                    }

                    $currentVersion = if ([String]::IsNullOrWhiteSpace($currentPackage.InstalledVersion)) { 'n/a' } else { $currentPackage.InstalledVersion }
                    $currentSource = if ([String]::IsNullOrWhiteSpace($currentPackage.Source)) { 'n/a' } else { $currentPackage.Source }

                    $frameLines += ''
                    $frameLines += ("Current: {0} | Id: {1} | Version: {2} | Source: {3}" -f $currentPackage.Name, $currentPackage.Id, $currentVersion, $currentSource)
                    if ($EnableSelection)
                    {
                        $frameLines += "$(@($selected | Where-Object { $_ }).Count) of $($InstalledPackages.Count) package(s) selected."
                    }

                    Write-PickerFrame -Lines $frameLines

                    $key = & $KeyReader
                    if (Test-PackagePickerCancelKey -KeyInfo $key)
                    {
                        Clear-PickerFrame
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
                            if (-not $EnableSelection)
                            {
                                break
                            }

                            Clear-PickerFrame

                            $selectedPackages = @()
                            for ($i = 0; $i -lt $InstalledPackages.Count; $i++)
                            {
                                if ($selected[$i])
                                {
                                    $selectedPackages += $InstalledPackages[$i]
                                }
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
        $installedPackages = @(
            Get-SystemPackage -PackageManager $PackageManager -Name $Name -ExcludePackage $ExcludePackage -CommandRunner $CommandRunner
        )

        if ($NonInteractive)
        {
            return $installedPackages
        }

        if ($installedPackages.Count -eq 0)
        {
            Write-Host 'No installed packages matched the requested filters.'
            return @()
        }

        $selectedPackages = @(
            Select-InstalledPackageRecords -InstalledPackages $installedPackages -KeyReader $KeyReader -PageSize $PickerPageSize -EnableSelection:$PassThru.IsPresent
        )

        if ($PassThru)
        {
            return $selectedPackages
        }

        return @()
    }
}
