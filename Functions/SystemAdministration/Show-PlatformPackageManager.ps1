function Show-PlatformPackageManager
{
    <#
    .SYNOPSIS
        Opens a unified console UI for native platform package management.

    .DESCRIPTION
        Provides one interactive entry point for the platform package management commands
        backed by winget on Windows, Homebrew on macOS, and apt or apk on Linux.

        The manager delegates to the existing package functions so their object output and
        automation behavior remain available:
        - Show-InstalledPlatformPackage for installed package browsing and export.
        - Find-PlatformPackage for remote registry search.
        - Install-PlatformPackage for search-driven installs.
        - Upgrade-PlatformPackage for package upgrades.
        - Remove-PlatformPackage for package removal.
        - Get-PlatformPackageDependency for dependency inspection.

    .PARAMETER PackageManager
        Package manager to use. Auto detects the current platform package manager.

    .PARAMETER Top
        Maximum number of search results to retrieve for search-driven package actions.

    .PARAMETER SkipRefresh
        Skips registry refresh when launching the upgrade workflow.

    .PARAMETER UninstallPrevious
        Passes winget --uninstall-previous when launching the upgrade workflow. Using this
        parameter with another package manager throws an unsupported-parameter error.

    .PARAMETER Interactive
        Initially enables winget --interactive for install and upgrade picker rows. Press I
        in either picker to toggle interactive mode for the current package. Using this
        parameter with another package manager throws an unsupported-parameter error.

    .PARAMETER Purge
        Requests package-manager-specific purge or zap behavior when launching removal.

    .PARAMETER NoSudo
        With apt or apk, does not automatically prefix install, upgrade, or removal commands
        with sudo. Using this parameter with winget or Homebrew throws an unsupported-parameter error.

    .PARAMETER FilterSource
        Sets the initial source filter for delegated interactive pickers that support
        source selection. Press S inside those pickers to cycle available sources.

    .PARAMETER WhatIf
        Shows what install, upgrade, or removal commands would run without invoking the
        platform package manager.

    .PARAMETER Confirm
        Prompts before delegated install, upgrade, or removal commands are invoked.

    .EXAMPLE
        PS > Show-PlatformPackageManager

        Opens the unified package management menu.

    .EXAMPLE
        PS > Show-PlatformPackageManager -PackageManager brew

        Opens the unified package management menu using Homebrew.

    .EXAMPLE
        PS > Show-PlatformPackageManager -SkipRefresh -NoSudo

        Opens the menu and forwards SkipRefresh and NoSudo to workflows that support them.

    .OUTPUTS
        None. Results emitted by underlying package workflows are rendered inside the
        manager UI as formatted tables.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Show-PlatformPackageManager.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Show-PlatformPackageManager.ps1
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()]
        [ValidateSet('Auto', 'winget', 'brew', 'apt', 'apk')]
        [String]$PackageManager = 'Auto',

        [Parameter()]
        [ValidateRange(0, 500)]
        [Int32]$Top = 50,

        [Parameter()]
        [Switch]$SkipRefresh,

        [Parameter()]
        [Switch]$UninstallPrevious,

        [Parameter()]
        [Switch]$Interactive,

        [Parameter()]
        [Switch]$Purge,

        [Parameter()]
        [Switch]$NoSudo,

        [Parameter()]
        [String]$FilterSource = '',

        [Parameter(DontShow = $true)]
        [ScriptBlock]$CommandRunner,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$KeyReader,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$PromptReader,

        [Parameter(DontShow = $true)]
        [ValidateRange(0, 500)]
        [Int32]$PickerPageSize = 0
    )

    begin
    {
        $packageThemeEscape = [String][Char]27
        $packageThemeAccent = $packageThemeEscape + '[38;5;37m'
        $packageThemeMuted = $packageThemeEscape + '[38;5;244m'
        $packageThemeWarning = $packageThemeEscape + '[33m'
        $packageThemeCritical = $packageThemeEscape + '[91m'
        $packageThemeReset = $packageThemeEscape + '[0m'
        $packageThemeHorizontal = [String][Char]0x2500
        $packageThemeVertical = [String][Char]0x2502
        $packageThemeTopLeft = [String][Char]0x256D
        $packageThemeTopRight = [String][Char]0x256E
        $packageThemeBottomLeft = [String][Char]0x2570
        $packageThemeBottomRight = [String][Char]0x256F
        $packageThemeStatus = [String][Char]0x25CF
        $packageThemeBullet = [String][Char]0x2022
        $packageThemeCursor = [String][Char]0x203A
        $packageThemeArrow = [String][Char]0x2192
        $packageThemeKeyboard = [String][Char]0x2328

        function Write-PackageThemeText
        {
            param(
                [Parameter(Position = 0)]
                [AllowNull()]
                [Object]$Object = '',

                [Parameter()]
                [Switch]$NoNewline,

                [Parameter()]
                [AllowNull()]
                [Object]$ForegroundColor
            )

            $text = if ($null -eq $Object) { '' } else { [String]$Object }
            $color = switch ([String]$ForegroundColor)
            {
                { $_ -in 'Green', 'DarkGreen', 'Cyan', 'DarkCyan' } { $packageThemeAccent; break }
                { $_ -in 'Gray', 'DarkGray' } { $packageThemeMuted; break }
                { $_ -in 'Yellow', 'DarkYellow' } { $packageThemeWarning; break }
                { $_ -in 'Red', 'DarkRed' } { $packageThemeCritical; break }
                default { '' }
            }

            if (-not $color)
            {
                Write-Host $text -NoNewline:$NoNewline.IsPresent
                return
            }

            Write-Host -Object @($color, $text, $packageThemeReset) -Separator '' -NoNewline:$NoNewline.IsPresent
        }

        function Get-PlatformPackageManagerDashboardWidth
        {
            $dashboardWidth = 96
            try
            {
                $bufferWidth = [Console]::BufferWidth
                if ($bufferWidth -gt 0)
                {
                    $dashboardWidth = [Math]::Min(104, [Math]::Max(60, $bufferWidth - 1))
                }
            }
            catch
            {
                Write-Verbose "Unable to determine the console buffer width; using $dashboardWidth characters. $($_.Exception.Message)"
            }

            return $dashboardWidth
        }

        function Write-PlatformPackageManagerPanelBorder
        {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('Top', 'Bottom')]
                [String]$Position,

                [Parameter()]
                [String]$Title = ''
            )

            $width = Get-PlatformPackageManagerDashboardWidth
            if ($Position -eq 'Bottom')
            {
                Write-PackageThemeText ($packageThemeBottomLeft + ($packageThemeHorizontal * ($width - 2)) + $packageThemeBottomRight) -ForegroundColor Cyan
                return
            }

            if ([String]::IsNullOrWhiteSpace($Title))
            {
                Write-PackageThemeText ($packageThemeTopLeft + ($packageThemeHorizontal * ($width - 2)) + $packageThemeTopRight) -ForegroundColor Cyan
                return
            }

            $titleToken = " $packageThemeStatus $($Title.ToUpperInvariant()) "
            $titleToken = $titleToken.Substring(0, [Math]::Min($titleToken.Length, $width - 4))
            $ruleWidth = [Math]::Max(0, $width - $titleToken.Length - 3)
            Write-PackageThemeText ($packageThemeTopLeft + $packageThemeHorizontal + $titleToken + ($packageThemeHorizontal * $ruleWidth) + $packageThemeTopRight) -ForegroundColor Cyan
        }

        function Write-PlatformPackageManagerPanelLine
        {
            param(
                [Parameter()]
                [AllowEmptyCollection()]
                [Object[]]$Segment = @()
            )

            $contentWidth = (Get-PlatformPackageManagerDashboardWidth) - 4
            $remainingWidth = $contentWidth
            Write-PackageThemeText "$packageThemeVertical " -NoNewline -ForegroundColor Cyan

            foreach ($item in @($Segment))
            {
                if ($remainingWidth -le 0)
                {
                    break
                }

                $segmentText = if ($null -eq $item)
                {
                    ''
                }
                elseif ($item -is [String])
                {
                    [String]$item
                }
                elseif ($item.PSObject.Properties['Text'])
                {
                    [String]$item.Text
                }
                else
                {
                    [String]$item
                }

                if ($segmentText.Length -gt $remainingWidth)
                {
                    if ($remainingWidth -eq 1)
                    {
                        $segmentText = $segmentText.Substring(0, 1)
                    }
                    else
                    {
                        $segmentText = $segmentText.Substring(0, $remainingWidth - 1) + [String][Char]0x2026
                    }
                }

                $segmentColor = if ($item -isnot [String] -and $item.PSObject.Properties['Color'])
                {
                    $item.Color
                }
                else
                {
                    $null
                }

                if ($null -eq $segmentColor)
                {
                    Write-PackageThemeText $segmentText -NoNewline
                }
                else
                {
                    Write-PackageThemeText $segmentText -NoNewline -ForegroundColor $segmentColor
                }
                $remainingWidth -= $segmentText.Length
            }

            if ($remainingWidth -gt 0)
            {
                Write-PackageThemeText (' ' * $remainingWidth) -NoNewline
            }
            Write-PackageThemeText " $packageThemeVertical" -ForegroundColor Cyan
        }

        function Get-PlatformPackageManagerDependencyPath
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$FunctionName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$FileName
            )

            if (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue)
            {
                Write-Verbose "$FunctionName is already loaded"
                return $null
            }

            $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath $FileName
            $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)
            if (-not (Test-Path -Path $dependencyPath -PathType Leaf))
            {
                throw "Required function '$FunctionName' could not be found. Expected location: $dependencyPath"
            }

            return $dependencyPath
        }

        function Invoke-PlatformPackageManagerFunction
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$FunctionName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$FileName,

                [Parameter(Mandatory)]
                [ScriptBlock]$Invocation,

                [Parameter()]
                [Hashtable]$Parameters = @{}
            )

            $dependencyPath = Get-PlatformPackageManagerDependencyPath -FunctionName $FunctionName -FileName $FileName
            if (-not [String]::IsNullOrWhiteSpace($dependencyPath))
            {
                try
                {
                    . $dependencyPath
                    Write-Verbose "Loaded $FunctionName from: $dependencyPath"
                }
                catch
                {
                    throw "Failed to load required dependency '$FunctionName' from '$dependencyPath': $($_.Exception.Message)"
                }
            }

            & $Invocation $Parameters
        }

        function Read-PlatformPackageManagerInput
        {
            param(
                [Parameter(Mandatory)]
                [String]$Prompt
            )

            if ($PromptReader)
            {
                $value = & $PromptReader -Prompt $Prompt
                if ($null -eq $value)
                {
                    return $null
                }

                return "$value"
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
                throw 'Interactive package management requires an attached console.'
            }

            return Read-PlatformPackageManagerLineInput -Prompt $Prompt
        }

        function Read-PlatformPackageManagerLineInput
        {
            param(
                [Parameter(Mandatory)]
                [String]$Prompt
            )

            function Write-PlatformPackageManagerPromptText
            {
                param(
                    [Parameter(Mandatory)]
                    [String]$Text
                )

                $pattern = '\([^\)]*\? for help[^\)]*\)|\[[^\]]*\? for help[^\]]*\]'
                $promptMatches = [regex]::Matches($Text, $pattern)
                if ($promptMatches.Count -eq 0)
                {
                    [Console]::Write($Text)
                    return
                }

                $cursor = 0
                foreach ($match in $promptMatches)
                {
                    if ($match.Index -gt $cursor)
                    {
                        [Console]::Write($Text.Substring($cursor, $match.Index - $cursor))
                    }

                    Write-PackageThemeText $match.Value -NoNewline -ForegroundColor DarkGray
                    $cursor = $match.Index + $match.Length
                }

                if ($cursor -lt $Text.Length)
                {
                    [Console]::Write($Text.Substring($cursor))
                }
            }

            Write-PlatformPackageManagerPromptText -Text $Prompt
            [Console]::Write(': ')
            $buffer = [System.Text.StringBuilder]::new()

            while ($true)
            {
                $key = [Console]::ReadKey($true)

                if ($key.Key -eq [ConsoleKey]::Enter)
                {
                    [Console]::WriteLine()
                    return $buffer.ToString()
                }

                if ($key.Key -eq [ConsoleKey]::Escape)
                {
                    [Console]::WriteLine()
                    return $null
                }

                if ($key.Key -eq [ConsoleKey]::Backspace)
                {
                    if ($buffer.Length -gt 0)
                    {
                        $buffer.Length = $buffer.Length - 1
                        [Console]::Write("`b `b")
                    }
                    continue
                }

                if ($key.KeyChar -ge [char]32)
                {
                    $buffer.Append($key.KeyChar) | Out-Null
                    [Console]::Write($key.KeyChar)
                }
            }
        }

        function Read-PlatformPackageManagerKey
        {
            if ($KeyReader)
            {
                return (& $KeyReader)
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
                throw 'Interactive package management requires an attached console.'
            }

            $previousTreatControlCAsInput = [Console]::TreatControlCAsInput
            [Console]::TreatControlCAsInput = $true
            try
            {
                return [Console]::ReadKey($true)
            }
            finally
            {
                [Console]::TreatControlCAsInput = $previousTreatControlCAsInput
            }
        }

        function Test-PlatformPackageManagerCancelKey
        {
            param(
                [Parameter(Mandatory)]
                [ConsoleKeyInfo]$KeyInfo
            )

            $isControlC = $KeyInfo.Key -eq [ConsoleKey]::C -and (($KeyInfo.Modifiers -band [ConsoleModifiers]::Control) -eq [ConsoleModifiers]::Control)
            return $KeyInfo.Key -in @([ConsoleKey]::Escape, [ConsoleKey]::Q) -or $isControlC
        }

        function Test-PlatformPackageManagerExportCancelRequested
        {
            try
            {
                if ([Console]::IsInputRedirected)
                {
                    return $false
                }

                while ([Console]::KeyAvailable)
                {
                    $cancelKey = [Console]::ReadKey($true)
                    if (Test-PlatformPackageManagerCancelKey -KeyInfo $cancelKey)
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

        function Test-PlatformPackageManagerHelpKey
        {
            param(
                [Parameter(Mandatory)]
                [ConsoleKeyInfo]$KeyInfo
            )

            return $KeyInfo.KeyChar -eq '?'
        }

        function Show-PlatformPackageManagerHelp
        {
            param(
                [Parameter()]
                [ValidateSet('Menu', 'Result', 'SearchQuery', 'ExportPath', 'ExportFormat', 'ExportDependencyMode', 'DependencyPackage', 'DependencyDirection', 'YesNo')]
                [String]$Topic = 'Menu'
            )

            Clear-Host

            $subtitle = switch ($Topic)
            {
                'Result' { 'Result screen shortcuts' }
                'SearchQuery' { 'Search prompt help' }
                'ExportPath' { 'Export path prompt help' }
                'ExportFormat' { 'Export format help' }
                'ExportDependencyMode' { 'Export dependency help' }
                'DependencyPackage' { 'Dependency package prompt help' }
                'DependencyDirection' { 'Dependency direction help' }
                'YesNo' { 'Confirmation prompt help' }
                default { 'Keyboard shortcuts' }
            }

            Write-PlatformPackageManagerHeader -Title 'Platform Package Manager Help' -Subtitle $subtitle

            function Get-PlatformPackageManagerHelpItem
            {
                param(
                    [Parameter(Mandatory)]
                    [String]$Shortcut,

                    [Parameter(Mandatory)]
                    [String]$Description
                )

                [PSCustomObject]@{
                    Shortcut = $Shortcut
                    Description = $Description
                }
            }

            function Write-PlatformPackageManagerHelpItem
            {
                param(
                    [Parameter(Mandatory)]
                    [PSCustomObject]$Item
                )

                Write-PackageThemeText '  - ' -NoNewline -ForegroundColor White
                Write-PackageThemeText "$($Item.Shortcut): " -NoNewline -ForegroundColor White
                Write-PackageThemeText $Item.Description -ForegroundColor DarkGray
            }

            $helpItems = switch ($Topic)
            {
                'Result'
                {
                    @(
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Any key or Enter' -Description 'return to the manager menu'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Q, Esc, or Ctrl+C' -Description 'quit the manager'
                        Get-PlatformPackageManagerHelpItem -Shortcut '?' -Description 'show this help'
                    )
                }
                'SearchQuery'
                {
                    @(
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Text' -Description 'enter a package name, package id, or registry search term'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Blank' -Description 'cancel the search workflow'
                        Get-PlatformPackageManagerHelpItem -Shortcut '?' -Description 'show this help'
                    )
                }
                'ExportPath'
                {
                    @(
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Text' -Description 'enter a .json or .csv export path'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Blank' -Description 'cancel the export workflow'
                        Get-PlatformPackageManagerHelpItem -Shortcut '?' -Description 'show this help'
                    )
                }
                'ExportFormat'
                {
                    @(
                        Get-PlatformPackageManagerHelpItem -Shortcut '1 or JSON' -Description 'write JSON records'
                        Get-PlatformPackageManagerHelpItem -Shortcut '2 or CSV' -Description 'write CSV records'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Blank' -Description 'cancel the export workflow'
                        Get-PlatformPackageManagerHelpItem -Shortcut '?' -Description 'show this help'
                    )
                }
                'ExportDependencyMode'
                {
                    @(
                        Get-PlatformPackageManagerHelpItem -Shortcut '1 or None' -Description 'export package records only'
                        Get-PlatformPackageManagerHelpItem -Shortcut '2 or DependsOn' -Description 'include direct dependencies'
                        Get-PlatformPackageManagerHelpItem -Shortcut '3 or Both' -Description 'include direct and required-by relationships'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Blank' -Description 'export package records only'
                        Get-PlatformPackageManagerHelpItem -Shortcut '?' -Description 'show this help'
                    )
                }
                'DependencyPackage'
                {
                    @(
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Text' -Description 'enter one or more package names or ids'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Comma' -Description 'separate multiple packages in one lookup'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Blank' -Description 'cancel the dependency workflow'
                        Get-PlatformPackageManagerHelpItem -Shortcut '?' -Description 'show this help'
                    )
                }
                'DependencyDirection'
                {
                    @(
                        Get-PlatformPackageManagerHelpItem -Shortcut '1 or DependsOn' -Description 'show packages required by the requested package'
                        Get-PlatformPackageManagerHelpItem -Shortcut '2 or RequiredBy' -Description 'show packages that depend on the requested package'
                        Get-PlatformPackageManagerHelpItem -Shortcut '3 or Both' -Description 'show both relationship directions'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Blank' -Description 'use DependsOn'
                        Get-PlatformPackageManagerHelpItem -Shortcut '?' -Description 'show this help'
                    )
                }
                'YesNo'
                {
                    @(
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Y or Yes' -Description 'accept the prompt'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'N or No' -Description 'decline the prompt'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Blank' -Description 'use the displayed default'
                        Get-PlatformPackageManagerHelpItem -Shortcut '?' -Description 'show this help'
                    )
                }
                default
                {
                    @(
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Up/Down' -Description 'choose an action'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Home/End' -Description 'move to the first or last action'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Enter' -Description 'run the selected action'
                        Get-PlatformPackageManagerHelpItem -Shortcut '1-6' -Description 'jump to a numbered workflow'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'B' -Description 'browse installed packages'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'E' -Description 'export installed packages'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'S or I' -Description 'search and install packages'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'U' -Description 'upgrade packages'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'R' -Description 'remove packages'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'D' -Description 'inspect dependencies'
                        Get-PlatformPackageManagerHelpItem -Shortcut 'Q, Esc, or Ctrl+C' -Description 'quit'
                        Get-PlatformPackageManagerHelpItem -Shortcut '?' -Description 'show this help'
                    )
                }
            }

            foreach ($item in $helpItems)
            {
                Write-PlatformPackageManagerHelpItem -Item $item
            }

            Write-PackageThemeText ''
            if ($KeyReader -or -not $PromptReader)
            {
                Write-PackageThemeText 'Press any key to return to the menu. Q/Esc/Ctrl+C quits.' -ForegroundColor DarkGray
                $null = Read-PlatformPackageManagerKey
            }
            else
            {
                $null = Read-PlatformPackageManagerInput -Prompt 'Press Enter to return'
            }
        }

        function ConvertFrom-PlatformPackageManagerListInput
        {
            param(
                [Parameter()]
                [String]$Value
            )

            if ([String]::IsNullOrWhiteSpace($Value))
            {
                return @()
            }

            return @(
                $Value -split ',' |
                ForEach-Object { "$_".Trim() } |
                Where-Object { -not [String]::IsNullOrWhiteSpace($_) }
            )
        }

        function Read-PlatformPackageManagerList
        {
            param(
                [Parameter(Mandatory)]
                [String]$Prompt,

                [Parameter()]
                [ValidateSet('DependencyPackage')]
                [String]$HelpTopic = 'DependencyPackage'
            )

            while ($true)
            {
                $value = Read-PlatformPackageManagerInput -Prompt "$Prompt (? for help)"
                if ($null -eq $value)
                {
                    return @()
                }

                if ($value.Trim() -eq '?')
                {
                    Show-PlatformPackageManagerHelp -Topic $HelpTopic
                    continue
                }

                return @(ConvertFrom-PlatformPackageManagerListInput -Value $value)
            }
        }

        function Get-PlatformPackageExportFormatFromPath
        {
            param(
                [Parameter(Mandatory)]
                [String]$Path
            )

            $extension = [System.IO.Path]::GetExtension($Path)
            if ([String]::IsNullOrWhiteSpace($extension))
            {
                return 'Auto'
            }

            switch ($extension.ToLowerInvariant())
            {
                '.json' { return 'Json' }
                '.csv' { return 'Csv' }
                default { return 'Auto' }
            }
        }

        function Read-PlatformPackageExportPath
        {
            while ($true)
            {
                $value = Read-PlatformPackageManagerInput -Prompt 'Export path (.json or .csv, ? for help)'
                if ($null -eq $value -or [String]::IsNullOrWhiteSpace($value))
                {
                    return $null
                }

                $value = $value.Trim()
                if ($value -eq '?')
                {
                    Show-PlatformPackageManagerHelp -Topic ExportPath
                    continue
                }

                return $value
            }
        }

        function Read-PlatformPackageExportFormat
        {
            param(
                [Parameter(Mandatory)]
                [String]$Path
            )

            while ($true)
            {
                Write-PackageThemeText 'Export format:' -ForegroundColor White
                Write-PackageThemeText '  1. JSON' -ForegroundColor White
                Write-PackageThemeText '  2. CSV' -ForegroundColor White
                Write-PackageThemeText '  ?. Help' -ForegroundColor DarkGray

                $value = Read-PlatformPackageManagerInput -Prompt "Select format for $Path [1, ? for help]"
                if ($null -eq $value)
                {
                    return $null
                }

                $value = $value.Trim()
                if ([String]::IsNullOrWhiteSpace($value))
                {
                    return $null
                }

                switch ($value.ToLowerInvariant())
                {
                    { $_ -in @('1', 'j', 'json') } { return 'Json' }
                    { $_ -in @('2', 'c', 'csv') } { return 'Csv' }
                    '?' { Show-PlatformPackageManagerHelp -Topic ExportFormat }
                    default { Write-PackageThemeText 'Choose 1 or 2.' -ForegroundColor DarkGray }
                }
            }
        }

        function Read-PlatformPackageExportDependencyMode
        {
            while ($true)
            {
                Write-PackageThemeText 'Dependency export:' -ForegroundColor White
                Write-PackageThemeText '  1. Packages only' -ForegroundColor White
                Write-PackageThemeText '  2. Direct dependencies' -ForegroundColor White
                Write-PackageThemeText '  3. Direct + required-by relationships' -ForegroundColor White
                Write-PackageThemeText '  ?. Help' -ForegroundColor DarkGray

                $value = Read-PlatformPackageManagerInput -Prompt 'Select dependency mode [1, ? for help]'
                if ($null -eq $value)
                {
                    return $null
                }

                $value = $value.Trim()
                if ([String]::IsNullOrWhiteSpace($value))
                {
                    return 'None'
                }

                switch ($value.ToLowerInvariant())
                {
                    { $_ -in @('1', 'n', 'no', 'none') } { return 'None' }
                    { $_ -in @('2', 'd', 'dependson', 'depends on', 'dependencies') } { return 'DependsOn' }
                    { $_ -in @('3', 'b', 'both', 'all') } { return 'Both' }
                    '?' { Show-PlatformPackageManagerHelp -Topic ExportDependencyMode }
                    default { Write-PackageThemeText 'Choose 1, 2, or 3.' -ForegroundColor DarkGray }
                }
            }
        }

        function Read-PlatformPackageManagerYesNo
        {
            param(
                [Parameter(Mandatory)]
                [String]$Prompt,

                [Parameter()]
                [Switch]$DefaultYes
            )

            $suffix = if ($DefaultYes) { 'Y/n' } else { 'y/N' }

            while ($true)
            {
                $value = Read-PlatformPackageManagerInput -Prompt "$Prompt [$suffix, ? for help]"
                if ($null -eq $value)
                {
                    return $null
                }

                $value = $value.Trim()
                if ([String]::IsNullOrWhiteSpace($value))
                {
                    return $DefaultYes.IsPresent
                }

                switch ($value.ToLowerInvariant())
                {
                    { $_ -in @('y', 'yes') } { return $true }
                    { $_ -in @('n', 'no') } { return $false }
                    '?' { Show-PlatformPackageManagerHelp -Topic YesNo }
                    default { Write-PackageThemeText 'Enter y or n.' -ForegroundColor DarkGray }
                }
            }
        }

        function Read-PlatformPackageDependencyDirection
        {
            while ($true)
            {
                Write-PackageThemeText 'Dependency direction:' -ForegroundColor White
                Write-PackageThemeText '  1. Depends on' -ForegroundColor White
                Write-PackageThemeText '  2. Required by' -ForegroundColor White
                Write-PackageThemeText '  3. Both' -ForegroundColor White
                Write-PackageThemeText '  ?. Help' -ForegroundColor DarkGray

                $value = Read-PlatformPackageManagerInput -Prompt 'Select direction [1, ? for help]'
                if ($null -eq $value)
                {
                    return $null
                }

                $value = $value.Trim()
                if ([String]::IsNullOrWhiteSpace($value))
                {
                    return 'DependsOn'
                }

                switch ($value.ToLowerInvariant())
                {
                    { $_ -in @('1', 'depends', 'dependson', 'depends on') } { return 'DependsOn' }
                    { $_ -in @('2', 'requiredby', 'required by', 'uses') } { return 'RequiredBy' }
                    { $_ -in @('3', 'both', 'all') } { return 'Both' }
                    '?' { Show-PlatformPackageManagerHelp -Topic DependencyDirection }
                    default { Write-PackageThemeText 'Choose 1, 2, or 3.' -ForegroundColor DarkGray }
                }
            }
        }

        function Get-PlatformPackageManagerCommonParameters
        {
            $parameters = @{
                PackageManager = $PackageManager
            }

            if ($CommandRunner)
            {
                $parameters.CommandRunner = $CommandRunner
            }

            return $parameters
        }

        function Add-PlatformPackageManagerPickerParameters
        {
            param(
                [Parameter(Mandatory)]
                [Hashtable]$Parameters
            )

            if ($KeyReader)
            {
                $Parameters.KeyReader = $KeyReader
            }

            $Parameters.ReturnToPlatformPackageManagerOnBackKey = $true

            if ($PickerPageSize -gt 0)
            {
                $Parameters.PickerPageSize = $PickerPageSize
            }

            if (-not [String]::IsNullOrWhiteSpace($FilterSource))
            {
                $Parameters.FilterSource = $FilterSource
            }
        }

        function Get-PlatformPackageManagerStatusText
        {
            $flags = @()
            if ($NoSudo)
            {
                $flags += 'NoSudo'
            }

            if ($SkipRefresh)
            {
                $flags += 'SkipRefresh'
            }

            if ($UninstallPrevious)
            {
                $flags += 'UninstallPrevious'
            }

            if ($Interactive)
            {
                $flags += 'Interactive'
            }

            if ($Purge)
            {
                $flags += 'Purge'
            }

            if (-not [String]::IsNullOrWhiteSpace($FilterSource))
            {
                $flags += "FilterSource=$FilterSource"
            }

            $managerText = if ($PackageManager -eq 'Auto')
            {
                "Auto $packageThemeArrow $(Get-PlatformPackageManagerDetectedName)"
            }
            else
            {
                $PackageManager
            }

            $flagText = if ($flags.Count -gt 0) { $flags -join ', ' } else { 'none' }
            return "Manager: $managerText  $packageThemeBullet  Top: $Top  $packageThemeBullet  Flags: $flagText"
        }

        function Test-PlatformPackageManagerCommandAvailable
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Name
            )

            if ($CommandRunner)
            {
                return $PackageManager -ne 'Auto' -and $PackageManager -eq $Name
            }

            return $null -ne (Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1)
        }

        function Get-PlatformPackageManagerDetectedName
        {
            if ($PackageManager -ne 'Auto')
            {
                return $PackageManager
            }

            $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { [Bool]$IsWindows }
            $isMacOSPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $false } else { [Bool]$IsMacOS }
            $isLinuxPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $false } else { [Bool]$IsLinux }

            if ($isWindowsPlatform -and (Test-PlatformPackageManagerCommandAvailable -Name 'winget'))
            {
                return 'winget'
            }

            if ($isMacOSPlatform -and (Test-PlatformPackageManagerCommandAvailable -Name 'brew'))
            {
                return 'brew'
            }

            if ($isLinuxPlatform)
            {
                if (Test-PlatformPackageManagerCommandAvailable -Name 'apt')
                {
                    return 'apt'
                }

                if (Test-PlatformPackageManagerCommandAvailable -Name 'apk')
                {
                    return 'apk'
                }
            }

            foreach ($fallbackManager in @('brew', 'winget', 'apt', 'apk'))
            {
                if (Test-PlatformPackageManagerCommandAvailable -Name $fallbackManager)
                {
                    return $fallbackManager
                }
            }

            return 'unresolved'
        }

        function Assert-PlatformPackageManagerParameterSupport
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$ManagerName
            )

            if ($ManagerName -eq 'unresolved')
            {
                return
            }

            if ($UninstallPrevious -and $ManagerName -ne 'winget')
            {
                throw "Parameter -UninstallPrevious is not supported by package manager '$ManagerName'. It is only supported by winget."
            }

            if ($Interactive -and $ManagerName -ne 'winget')
            {
                throw "Parameter -Interactive is not supported by package manager '$ManagerName'. It is only supported by winget."
            }

            if ($NoSudo -and $ManagerName -notin @('apt', 'apk'))
            {
                throw "Parameter -NoSudo is not supported by package manager '$ManagerName'. It is only supported by apt and apk."
            }
        }

        function Write-PlatformPackageManagerHeader
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Title,

                [Parameter()]
                [String]$Subtitle
            )

            Write-PlatformPackageManagerPanelBorder -Position Top
            Write-PlatformPackageManagerPanelLine -Segment @(
                [PSCustomObject]@{ Text = $Title; Color = 'Cyan' }
            )
            if (-not [String]::IsNullOrWhiteSpace($Subtitle))
            {
                Write-PlatformPackageManagerPanelLine -Segment @(
                    [PSCustomObject]@{ Text = $Subtitle; Color = 'White' }
                )
            }

            $statusParts = (Get-PlatformPackageManagerStatusText) -split [Regex]::Escape("  $packageThemeBullet  Flags: "), 2
            Write-PlatformPackageManagerPanelLine -Segment @(
                [PSCustomObject]@{ Text = "$packageThemeStatus READY  "; Color = 'Cyan' }
                [PSCustomObject]@{ Text = $statusParts[0]; Color = 'DarkGray' }
            )
            if ($statusParts.Count -gt 1)
            {
                Write-PlatformPackageManagerPanelLine -Segment @(
                    [PSCustomObject]@{ Text = "$packageThemeBullet OPTIONS  "; Color = 'Cyan' }
                    [PSCustomObject]@{ Text = "Flags: $($statusParts[1])"; Color = 'DarkGray' }
                )
            }
            Write-PlatformPackageManagerPanelBorder -Position Bottom
            Write-PackageThemeText ''
        }

        function Format-PlatformPackageManagerTableMessage
        {
            param(
                [Parameter()]
                [AllowEmptyString()]
                [String]$Text = '',

                [Parameter()]
                [ValidateRange(4, 4096)]
                [Int32]$MaximumLength = 80
            )

            if ($Text.Length -le $MaximumLength)
            {
                return $Text
            }

            return $Text.Substring(0, $MaximumLength - 3) + '...'
        }

        function Format-PlatformPackageManagerResultTable
        {
            param(
                [Parameter()]
                [Object[]]$InputObject = @(),

                [Parameter()]
                [ValidateRange(40, 32767)]
                [Int32]$MaximumWidth = 4096
            )

            $records = @($InputObject | Where-Object { $null -ne $_ })
            if ($records.Count -eq 0)
            {
                return ''
            }

            $displayRecords = @(
                foreach ($record in $records)
                {
                    $excludeProperties = @('Results', 'CapturedOutput', 'InformationalOutput', 'InformationalResults')
                    $displayRecord = $record | Select-Object -Property * -ExcludeProperty $excludeProperties
                    if ($displayRecord.PSObject.Properties['Message'])
                    {
                        $displayRecord.Message = Format-PlatformPackageManagerTableMessage -Text "$($displayRecord.Message)"
                    }

                    $displayRecord
                }
            )

            return ($displayRecords | Format-Table -AutoSize | Out-String -Width $MaximumWidth).TrimEnd()
        }

        function Get-PlatformPackageManagerNestedResults
        {
            param(
                [Parameter()]
                [Object[]]$InputObject = @()
            )

            @(
                foreach ($record in @($InputObject | Where-Object { $null -ne $_ }))
                {
                    if ($record.PSObject.Properties['Results'] -and $null -ne $record.Results)
                    {
                        @($record.Results | Where-Object { $null -ne $_ })
                    }
                }
            )
        }

        function Get-PlatformPackageManagerInformationalResults
        {
            param(
                [Parameter()]
                [Object[]]$Records = @()
            )

            @(
                foreach ($record in @($Records | Where-Object { $null -ne $_ }))
                {
                    if ($record.PSObject.Properties['InformationalResults'] -and $null -ne $record.InformationalResults)
                    {
                        @($record.InformationalResults | Where-Object { $null -ne $_ })
                    }
                }
            )
        }

        function Get-PlatformPackageManagerActionResult
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Title,

                [Parameter()]
                [String]$Message,

                [Parameter()]
                [Object[]]$Records = @(),

                [Parameter()]
                [Switch]$AutoReturn
            )

            $recordList = @($Records | Where-Object { $null -ne $_ })
            return [PSCustomObject]@{
                PSTypeName = 'PlatformPackageManager.ActionResult'
                Title = $Title
                Message = $Message
                Records = $recordList
                RecordCount = $recordList.Count
                AutoReturn = $AutoReturn.IsPresent
            }
        }

        function Test-PlatformPackageManagerShouldShowResultScreen
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Result
            )

            # Explicitly flagged as a no-op / cancel: go straight back to the menu
            if ($Result.AutoReturn)
            {
                return $false
            }

            # No records but has an informational message — show it
            if ($Result.RecordCount -eq 0)
            {
                return $true
            }

            # Records that are not operation summaries (e.g. dependency rows) — always show
            $hasNonSummaryRecords = @(
                $Result.Records | Where-Object {
                    $null -ne $_ -and -not $_.PSObject.Properties['Selected']
                }
            ).Count -gt 0

            if ($hasNonSummaryRecords)
            {
                return $true
            }

            # All records are operation summaries: only show when something was actually selected
            $maxSelected = @(
                $Result.Records |
                Where-Object { $null -ne $_ -and $_.PSObject.Properties['Selected'] } |
                ForEach-Object { [Int32]$_.Selected }
            ) | Measure-Object -Maximum

            return ($null -ne $maxSelected.Maximum -and [Int32]$maxSelected.Maximum -gt 0)
        }

        function Get-PlatformPackageManagerOperationStatusIndicator
        {
            param(
                [Parameter()]
                [Object[]]$Records = @()
            )

            $summaryRecord = @(
                $Records |
                Where-Object {
                    $null -ne $_ -and
                    $_.PSObject.Properties['Results'] -and
                    (
                        $_.PSObject.Properties['Installed'] -or
                        $_.PSObject.Properties['Upgraded'] -or
                        $_.PSObject.Properties['Removed']
                    )
                } |
                Select-Object -First 1
            )

            if ($summaryRecord.Count -eq 0)
            {
                return $null
            }

            $record = $summaryRecord[0]
            $parts = [System.Collections.Generic.List[String]]::new()
            $failedCount = if ($record.PSObject.Properties['Failed']) { [Int32]$record.Failed } else { 0 }
            $skippedCount = if ($record.PSObject.Properties['Skipped']) { [Int32]$record.Skipped } else { 0 }

            if ($record.PSObject.Properties['Installed'])
            {
                $parts.Add("Installed: $([Int32]$record.Installed)")
            }

            if ($record.PSObject.Properties['Upgraded'])
            {
                $parts.Add("Upgraded: $([Int32]$record.Upgraded)")
            }

            if ($record.PSObject.Properties['Removed'])
            {
                $parts.Add("Removed: $([Int32]$record.Removed)")
            }

            $parts.Add("Failed: $failedCount")
            $parts.Add("Skipped: $skippedCount")

            $color = if ($failedCount -gt 0) { 'Red' } elseif ($skippedCount -gt 0) { 'Yellow' } else { 'Green' }

            return [PSCustomObject]@{
                Text = $parts -join '  |  '
                Color = $color
            }
        }

        function Show-PlatformPackageManagerResultScreen
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Result
            )

            while ($true)
            {
                Clear-Host

                $recordSummary = if ($Result.RecordCount -eq 1) { '1 record' } else { "$($Result.RecordCount) records" }
                Write-PlatformPackageManagerHeader -Title $Result.Title -Subtitle "Result: $recordSummary"

                if (-not [String]::IsNullOrWhiteSpace($Result.Message))
                {
                    Write-PackageThemeText $Result.Message -ForegroundColor White
                    Write-PackageThemeText ''
                }

                if ($Result.RecordCount -gt 0)
                {
                    $allSummaries = @(
                        $Result.Records | Where-Object { $null -ne $_ -and -not $_.PSObject.Properties['Results'] }
                    ).Count -eq 0

                    if (-not $allSummaries)
                    {
                        $table = Format-PlatformPackageManagerResultTable -InputObject $Result.Records
                        if (-not [String]::IsNullOrWhiteSpace($table))
                        {
                            Write-PackageThemeText $table
                            Write-PackageThemeText ''
                        }
                    }

                    $detailRecords = @(Get-PlatformPackageManagerNestedResults -InputObject $Result.Records)
                    if ($detailRecords.Count -gt 0)
                    {
                        Write-PackageThemeText 'Details' -ForegroundColor Cyan
                        $sepWidth = 78
                        try
                        {
                            $w = [Console]::BufferWidth
                            if ($w -gt 0)
                            {
                                $sepWidth = [Math]::Max(40, $w - 1)
                            }
                        }
                        catch
                        {
                            Write-Verbose "Unable to determine the console buffer width; using $sepWidth characters. $($_.Exception.Message)"
                        }

                        Write-PackageThemeText ('-' * $sepWidth) -ForegroundColor DarkGray
                        $detailTable = Format-PlatformPackageManagerResultTable -InputObject $detailRecords -MaximumWidth $sepWidth
                        if (-not [String]::IsNullOrWhiteSpace($detailTable))
                        {
                            Write-PackageThemeText $detailTable
                            Write-PackageThemeText ''
                        }
                    }

                    $informationalResults = @(Get-PlatformPackageManagerInformationalResults -Records $Result.Records)
                    if ($informationalResults.Count -gt 0)
                    {
                        Write-PackageThemeText 'Additional output' -ForegroundColor Cyan
                        $sepWidth = 78
                        try
                        {
                            $w = [Console]::BufferWidth
                            if ($w -gt 0)
                            {
                                $sepWidth = [Math]::Max(40, $w - 1)
                            }
                        }
                        catch
                        {
                            Write-Verbose "Unable to determine the console buffer width; using $sepWidth characters. $($_.Exception.Message)"
                        }

                        Write-PackageThemeText ('-' * $sepWidth) -ForegroundColor DarkGray

                        foreach ($informationalResult in $informationalResults)
                        {
                            $label = if (-not [String]::IsNullOrWhiteSpace($informationalResult.Id) -and $informationalResult.Id -ne $informationalResult.Name)
                            {
                                "$($informationalResult.Name) ($($informationalResult.Id))"
                            }
                            else
                            {
                                $informationalResult.Name
                            }

                            if (-not [String]::IsNullOrWhiteSpace($label))
                            {
                                Write-PackageThemeText $label -ForegroundColor White
                            }

                            foreach ($line in @($informationalResult.Lines | Where-Object { -not [String]::IsNullOrWhiteSpace("$($_)") }))
                            {
                                Write-PackageThemeText "  $line" -ForegroundColor DarkGray
                            }

                            Write-PackageThemeText ''
                        }
                    }
                }

                $statusIndicator = Get-PlatformPackageManagerOperationStatusIndicator -Records $Result.Records
                if ($null -ne $statusIndicator)
                {
                    Write-PackageThemeText $statusIndicator.Text -ForegroundColor $statusIndicator.Color
                    Write-PackageThemeText ''
                }

                Write-PackageThemeText 'Any key: return to menu  Q/Esc/Ctrl+C: quit  ?: help' -ForegroundColor DarkGray

                $isQuit = $false
                if ($KeyReader -or -not $PromptReader)
                {
                    $pauseKey = Read-PlatformPackageManagerKey
                    if (Test-PlatformPackageManagerHelpKey -KeyInfo $pauseKey)
                    {
                        Show-PlatformPackageManagerHelp -Topic Result
                        continue
                    }

                    $isQuit = Test-PlatformPackageManagerCancelKey -KeyInfo $pauseKey
                }
                else
                {
                    $rawValue = (Read-PlatformPackageManagerInput -Prompt 'Press Enter to return to menu (? for help)').Trim()
                    if ($rawValue -eq '?')
                    {
                        Show-PlatformPackageManagerHelp -Topic Result
                        continue
                    }

                    $isQuit = $rawValue.ToLowerInvariant() -in @('q', 'quit', 'exit')
                }

                if ($isQuit)
                {
                    return [PSCustomObject]@{
                        Command = 'Quit'
                        Choice = ''
                    }
                }

                return [PSCustomObject]@{
                    Command = 'Menu'
                    Choice = ''
                }
            }
        }

        function Invoke-PlatformPackageManagerInstalledBrowser
        {
            $parameters = Get-PlatformPackageManagerCommonParameters
            Add-PlatformPackageManagerPickerParameters -Parameters $parameters

            $result = @(Invoke-PlatformPackageManagerFunction -FunctionName 'Show-InstalledPlatformPackage' -FileName 'Show-InstalledPlatformPackage.ps1' -Parameters $parameters -Invocation {
                    param([Hashtable]$InvocationParameters)
                    Show-InstalledPlatformPackage @InvocationParameters
                })
            if ($result.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Installed Packages' -Message 'Installed package browser closed.' -AutoReturn)
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Installed Packages' -Records $result)
        }

        function Invoke-PlatformPackageManagerExport
        {
            $exportPath = Read-PlatformPackageExportPath
            if ([String]::IsNullOrWhiteSpace($exportPath))
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Export Installed Packages' -Message 'Export cancelled; file path is required.' -AutoReturn)
            }

            $exportFormat = Get-PlatformPackageExportFormatFromPath -Path $exportPath
            if ($exportFormat -eq 'Auto')
            {
                $exportFormat = Read-PlatformPackageExportFormat -Path $exportPath
                if ([String]::IsNullOrWhiteSpace($exportFormat))
                {
                    return (Get-PlatformPackageManagerActionResult -Title 'Export Installed Packages' -Message 'Export cancelled; format is required.' -AutoReturn)
                }
            }

            $dependencyMode = Read-PlatformPackageExportDependencyMode
            if ($null -eq $dependencyMode)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Export Installed Packages' -Message 'Export cancelled.' -AutoReturn)
            }

            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.ExportPath = $exportPath
            $parameters.ExportFormat = $exportFormat
            $parameters.ExportDependencyMode = $dependencyMode
            $parameters.NonInteractive = $true
            $parameters.ShowExportProgress = $true
            $parameters.ExportCancelRequested = ${function:Test-PlatformPackageManagerExportCancelRequested}.GetNewClosure()

            try
            {
                $result = @(Invoke-PlatformPackageManagerFunction -FunctionName 'Show-InstalledPlatformPackage' -FileName 'Show-InstalledPlatformPackage.ps1' -Parameters $parameters -Invocation {
                        param([Hashtable]$InvocationParameters)
                        Show-InstalledPlatformPackage @InvocationParameters
                    })
            }
            catch
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Export Installed Packages' -Message "Export failed: $($_.Exception.Message)")
            }

            if ($result.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Export Installed Packages' -Message 'Export completed with no result records.' -AutoReturn)
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Export Installed Packages' -Message 'Export completed.' -Records $result)
        }

        function Invoke-PlatformPackageManagerSearch
        {
            while ($true)
            {
                $query = Read-PlatformPackageManagerInput -Prompt 'Search query (? for help)'
                if ($null -eq $query -or [String]::IsNullOrWhiteSpace($query))
                {
                    return (Get-PlatformPackageManagerActionResult -Title 'Search and Install Packages' -Message 'Search cancelled; query is required.' -AutoReturn)
                }

                if ($query.Trim() -eq '?')
                {
                    Show-PlatformPackageManagerHelp -Topic SearchQuery
                    continue
                }

                $query = $query.Trim()
                break
            }

            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.Query = $query
            $parameters.Top = $Top
            Add-PlatformPackageManagerPickerParameters -Parameters $parameters

            if ($NoSudo)
            {
                $parameters.NoSudo = $true
            }

            if ($Interactive)
            {
                $parameters.Interactive = $true
            }

            $result = @(Invoke-PlatformPackageManagerFunction -FunctionName 'Install-PlatformPackage' -FileName 'Install-PlatformPackage.ps1' -Parameters $parameters -Invocation {
                    param([Hashtable]$InvocationParameters)
                    Install-PlatformPackage @InvocationParameters
                })
            if ($result.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Search and Install Packages' -Message 'Search completed with no result records.' -AutoReturn)
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Search and Install Packages' -Records $result)
        }

        function Invoke-PlatformPackageManagerUpgrade
        {
            $parameters = Get-PlatformPackageManagerCommonParameters
            Add-PlatformPackageManagerPickerParameters -Parameters $parameters

            if ($SkipRefresh)
            {
                $parameters.SkipRefresh = $true
            }

            if ($UninstallPrevious)
            {
                $parameters.UninstallPrevious = $true
            }

            if ($Interactive)
            {
                $parameters.Interactive = $true
            }

            if ($NoSudo)
            {
                $parameters.NoSudo = $true
            }

            $result = @(Invoke-PlatformPackageManagerFunction -FunctionName 'Upgrade-PlatformPackage' -FileName 'Upgrade-PlatformPackage.ps1' -Parameters $parameters -Invocation {
                    param([Hashtable]$InvocationParameters)
                    Upgrade-PlatformPackage @InvocationParameters
                })
            if ($result.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Upgrade Packages' -Message 'Upgrade completed with no result records.' -AutoReturn)
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Upgrade Packages' -Records $result)
        }

        function Invoke-PlatformPackageManagerRemoval
        {
            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.Purge = $Purge.IsPresent
            Add-PlatformPackageManagerPickerParameters -Parameters $parameters

            if ($NoSudo)
            {
                $parameters.NoSudo = $true
            }

            $result = @(Invoke-PlatformPackageManagerFunction -FunctionName 'Remove-PlatformPackage' -FileName 'Remove-PlatformPackage.ps1' -Parameters $parameters -Invocation {
                    param([Hashtable]$InvocationParameters)
                    Remove-PlatformPackage @InvocationParameters
                })
            if ($result.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Remove Packages' -Message 'Removal completed with no result records.' -AutoReturn)
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Remove Packages' -Records $result)
        }

        function Invoke-PlatformPackageManagerDependencyView
        {
            $package = @(Read-PlatformPackageManagerList -Prompt 'Package name or id (comma-separated)')
            if ($package.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Message 'Dependency lookup cancelled; at least one package is required.' -AutoReturn)
            }

            $direction = Read-PlatformPackageDependencyDirection
            if ($null -eq $direction)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Message 'Dependency lookup cancelled.' -AutoReturn)
            }

            $installedOnly = Read-PlatformPackageManagerYesNo -Prompt 'Limit related packages to installed packages?' -DefaultYes
            if ($null -eq $installedOnly)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Message 'Dependency lookup cancelled.' -AutoReturn)
            }

            $resolvedManagerName = Get-PlatformPackageManagerDetectedName
            if ($resolvedManagerName -eq 'winget' -and $direction -ne 'DependsOn')
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Message "Direction '$direction' is not supported by winget. winget does not expose reverse dependency metadata; choose DependsOn.")
            }

            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.Package = $package
            $parameters.Direction = $direction
            $parameters.InstalledOnly = $installedOnly

            $records = @(Invoke-PlatformPackageManagerFunction -FunctionName 'Get-PlatformPackageDependency' -FileName 'Get-PlatformPackageDependency.ps1' -Parameters $parameters -Invocation {
                    param([Hashtable]$InvocationParameters)
                    Get-PlatformPackageDependency @InvocationParameters
                })
            if ($records.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Message 'No dependency relationships were found.')
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Records $records)
        }

        function Get-PlatformPackageManagerAutoReturnNotification
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Result
            )

            # Explicit cancels (empty query, browser closed, etc.) need no notification
            if ($Result.AutoReturn)
            {
                return ''
            }

            $summaryRecord = @(
                $Result.Records |
                Where-Object { $null -ne $_ -and $_.PSObject.Properties['Selected'] }
            ) | Select-Object -First 1

            if ($null -eq $summaryRecord)
            {
                return ''
            }

            # Nothing available to upgrade
            if ($summaryRecord.PSObject.Properties['TotalAvailable'] -and [Int32]$summaryRecord.TotalAvailable -eq 0)
            {
                return 'No packages are currently available for upgrade.'
            }

            # Nothing matched for removal
            if ($summaryRecord.PSObject.Properties['TotalMatched'] -and [Int32]$summaryRecord.TotalMatched -eq 0 -and $summaryRecord.PSObject.Properties['Removed'])
            {
                return 'No installed packages matched the requested filters.'
            }

            # Nothing matched for search/install
            if ($summaryRecord.PSObject.Properties['TotalMatched'] -and [Int32]$summaryRecord.TotalMatched -eq 0 -and $summaryRecord.PSObject.Properties['Installed'])
            {
                return 'No packages matched the requested search query.'
            }

            # User dismissed the picker without selecting — intentional, no notification needed
            return ''
        }

        function Get-PlatformPackageManagerMenuOptions
        {
            @(
                [PSCustomObject]@{
                    Choice = '1'
                    Symbol = [String][Char]0x2191
                    Workflow = 'Upgrade packages'
                    Purpose = 'Review or upgrade outdated packages'
                }
                [PSCustomObject]@{
                    Choice = '2'
                    Symbol = '+'
                    Workflow = 'Search and install'
                    Purpose = 'Search the registry and optionally install results'
                }
                [PSCustomObject]@{
                    Choice = '3'
                    Symbol = [String][Char]0x25A6
                    Workflow = 'Installed packages'
                    Purpose = 'Browse or filter installed package records'
                }
                [PSCustomObject]@{
                    Choice = '4'
                    Symbol = [String][Char]0x2212
                    Workflow = 'Remove packages'
                    Purpose = 'Review or remove installed packages'
                }
                [PSCustomObject]@{
                    Choice = '5'
                    Symbol = [String][Char]0x25C7
                    Workflow = 'Dependencies'
                    Purpose = 'Inspect dependency relationships'
                }
                [PSCustomObject]@{
                    Choice = '6'
                    Symbol = [String][Char]0x2193
                    Workflow = 'Export installed'
                    Purpose = 'Write installed package records to JSON or CSV'
                }
                [PSCustomObject]@{
                    Choice = 'Q'
                    Symbol = [String][Char]0x00D7
                    Workflow = 'Quit'
                    Purpose = 'Exit the manager'
                }
            )
        }

        function Write-PlatformPackageManagerMenu
        {
            param(
                [Parameter()]
                [Object[]]$Options = @(Get-PlatformPackageManagerMenuOptions),

                [Parameter()]
                [Int32]$SelectedIndex = -1,

                [Parameter()]
                [String]$Notification = ''
            )

            Clear-Host
            Write-PlatformPackageManagerHeader -Title 'Platform Package Manager' -Subtitle 'Unified native package management workflows'
            Write-PlatformPackageManagerPanelBorder -Position Top -Title 'Workflows'
            Write-PlatformPackageManagerPanelLine -Segment @(
                [PSCustomObject]@{ Text = ('{0,-4} {1,-7} {2,-3} {3,-24} {4}' -f '', 'Action', '', 'Workflow', 'Purpose'); Color = 'DarkGray' }
            )
            for ($i = 0; $i -lt $Options.Count; $i++)
            {
                $marker = if ($i -eq $SelectedIndex) { $packageThemeCursor } else { ' ' }
                $accentColor = if ($i -eq $SelectedIndex) { 'Cyan' } else { 'DarkGray' }
                $workflowColor = if ($i -eq $SelectedIndex) { 'Cyan' } else { 'White' }
                Write-PlatformPackageManagerPanelLine -Segment @(
                    [PSCustomObject]@{ Text = ('{0,-4} ' -f $marker); Color = $accentColor }
                    [PSCustomObject]@{ Text = ('{0,-7} ' -f "[$($Options[$i].Choice)]"); Color = $accentColor }
                    [PSCustomObject]@{ Text = ('{0,-3} ' -f $Options[$i].Symbol); Color = $accentColor }
                    [PSCustomObject]@{ Text = ('{0,-24} ' -f $Options[$i].Workflow); Color = $workflowColor }
                    [PSCustomObject]@{ Text = $Options[$i].Purpose; Color = 'DarkGray' }
                )
            }
            Write-PlatformPackageManagerPanelBorder -Position Bottom

            Write-PackageThemeText ''
            if (-not [String]::IsNullOrWhiteSpace($Notification))
            {
                Write-PlatformPackageManagerPanelBorder -Position Top -Title 'Notice'
                Write-PlatformPackageManagerPanelLine -Segment @(
                    [PSCustomObject]@{ Text = "$packageThemeStatus "; Color = 'DarkYellow' }
                    [PSCustomObject]@{ Text = $Notification; Color = 'DarkYellow' }
                )
                Write-PlatformPackageManagerPanelBorder -Position Bottom
                Write-PackageThemeText ''
            }

            if ($SelectedIndex -ge 0)
            {
                Write-PlatformPackageManagerPanelBorder -Position Top -Title 'Controls'
                Write-PlatformPackageManagerPanelLine -Segment @(
                    [PSCustomObject]@{ Text = "$packageThemeKeyboard  "; Color = 'Cyan' }
                    [PSCustomObject]@{ Text = 'Up/Down choose  '; Color = 'DarkGray' }
                    [PSCustomObject]@{ Text = 'Enter run  '; Color = 'White' }
                    [PSCustomObject]@{ Text = '1-6/Q jump  ?: help'; Color = 'DarkGray' }
                )
                Write-PlatformPackageManagerPanelBorder -Position Bottom
                Write-PackageThemeText ''
            }
        }

        function Read-PlatformPackageManagerMenuChoice
        {
            param(
                [Parameter()]
                [String]$Notification = ''
            )

            $options = @(Get-PlatformPackageManagerMenuOptions)
            if ($PromptReader -and -not $KeyReader)
            {
                while ($true)
                {
                    Write-PlatformPackageManagerMenu -Options $options -Notification $Notification
                    $promptChoice = (Read-PlatformPackageManagerInput -Prompt 'Select an action (? for help)').Trim()
                    if ($promptChoice -eq '?')
                    {
                        Show-PlatformPackageManagerHelp -Topic Menu
                        continue
                    }

                    return $promptChoice
                }
            }

            $selectedIndex = 0
            while ($true)
            {
                Write-PlatformPackageManagerMenu -Options $options -SelectedIndex $selectedIndex -Notification $Notification
                $key = Read-PlatformPackageManagerKey
                if (Test-PlatformPackageManagerCancelKey -KeyInfo $key)
                {
                    return 'q'
                }

                if (Test-PlatformPackageManagerHelpKey -KeyInfo $key)
                {
                    Show-PlatformPackageManagerHelp -Topic Menu
                    continue
                }

                switch ($key.Key)
                {
                    'UpArrow'
                    {
                        if ($selectedIndex -le 0)
                        {
                            $selectedIndex = $options.Count - 1
                        }
                        else
                        {
                            $selectedIndex--
                        }
                    }
                    'DownArrow'
                    {
                        if ($selectedIndex -ge ($options.Count - 1))
                        {
                            $selectedIndex = 0
                        }
                        else
                        {
                            $selectedIndex++
                        }
                    }
                    'Home'
                    {
                        $selectedIndex = 0
                    }
                    'End'
                    {
                        $selectedIndex = $options.Count - 1
                    }
                    'Enter'
                    {
                        return $options[$selectedIndex].Choice
                    }
                    default
                    {
                        $keyChar = "$($key.KeyChar)".Trim()
                        if ([String]::IsNullOrWhiteSpace($keyChar))
                        {
                            continue
                        }

                        $matchingOption = @($options | Where-Object { $_.Choice -eq $keyChar.ToUpperInvariant() } | Select-Object -First 1)
                        if ($matchingOption.Count -gt 0)
                        {
                            return $matchingOption[0].Choice
                        }

                        switch ($keyChar.ToLowerInvariant())
                        {
                            'b' { return '3' }
                            'e' { return '6' }
                            's' { return '2' }
                            'i' { return '2' }
                            'u' { return '1' }
                            'r' { return '4' }
                            'd' { return '5' }
                        }
                    }
                }
            }
        }

        function Invoke-PlatformPackageManagerAction
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Choice
            )

            switch ($Choice.Trim().ToLowerInvariant())
            {
                { $_ -in @('1', 'upgrade', 'update') } { Invoke-PlatformPackageManagerUpgrade; break }
                { $_ -in @('2', 'search', 'find', 'install') } { Invoke-PlatformPackageManagerSearch; break }
                { $_ -in @('3', 'installed', 'browse') } { Invoke-PlatformPackageManagerInstalledBrowser; break }
                { $_ -in @('4', 'remove', 'uninstall') } { Invoke-PlatformPackageManagerRemoval; break }
                { $_ -in @('5', 'deps', 'dependencies', 'dependency') } { Invoke-PlatformPackageManagerDependencyView; break }
                { $_ -in @('6', 'export') } { Invoke-PlatformPackageManagerExport; break }
                default { Get-PlatformPackageManagerActionResult -Title 'Platform Package Manager' -Message 'Choose 1-6 or Q.' }
            }
        }

    }

    process
    {
        Assert-PlatformPackageManagerParameterSupport -ManagerName (Get-PlatformPackageManagerDetectedName)
        $notification = ''

        while ($true)
        {
            $choice = Read-PlatformPackageManagerMenuChoice -Notification $notification
            $notification = ''

            if ($choice.ToLowerInvariant() -in @('q', 'quit', 'exit'))
            {
                return
            }

            if ([String]::IsNullOrWhiteSpace($choice))
            {
                continue
            }

            $actionResult = Invoke-PlatformPackageManagerAction -Choice $choice
            if ($null -eq $actionResult)
            {
                continue
            }

            if (Test-PlatformPackageManagerShouldShowResultScreen -Result $actionResult)
            {
                $nextAction = Show-PlatformPackageManagerResultScreen -Result $actionResult
                if ($nextAction.Command -eq 'Quit')
                {
                    return
                }
            }
            else
            {
                $notification = Get-PlatformPackageManagerAutoReturnNotification -Result $actionResult
            }
        }
    }
}

# Create 'ppm' alias only if it doesn't already exist
if (-not (Get-Alias -Name 'ppm' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'ppm' alias for Show-PlatformPackageManager"
        Set-Alias -Name 'ppm' -Value 'Show-PlatformPackageManager' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Show-PlatformPackageManager: Could not create 'ppm' alias: $($_.Exception.Message)"
    }
}
