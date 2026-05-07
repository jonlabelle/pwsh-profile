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
        - Show-InstalledPlatformPackage for installed package browsing.
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
        Passes winget --uninstall-previous when launching the upgrade workflow.

    .PARAMETER Purge
        Requests package-manager-specific purge or zap behavior when launching removal.

    .PARAMETER NoSudo
        On Linux package managers that normally require elevated privileges, do not
        automatically prefix install, upgrade, or removal commands with sudo.

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
        [Switch]$Purge,

        [Parameter()]
        [Switch]$NoSudo,

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

            [Console]::Write("$Prompt`: ")
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
                [String]$Prompt
            )

            $value = Read-PlatformPackageManagerInput -Prompt $Prompt
            return @(ConvertFrom-PlatformPackageManagerListInput -Value $value)
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
                $value = Read-PlatformPackageManagerInput -Prompt "$Prompt [$suffix]"
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
                    default { Write-Host 'Enter y or n.' -ForegroundColor DarkGray }
                }
            }
        }

        function Read-PlatformPackageDependencyDirection
        {
            while ($true)
            {
                Write-Host 'Dependency direction:' -ForegroundColor White
                Write-Host '  1. Depends on' -ForegroundColor White
                Write-Host '  2. Required by' -ForegroundColor White
                Write-Host '  3. Both' -ForegroundColor White

                $value = Read-PlatformPackageManagerInput -Prompt 'Select direction [1]'
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
                    default { Write-Host 'Choose 1, 2, or 3.' -ForegroundColor DarkGray }
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

            if ($PickerPageSize -gt 0)
            {
                $Parameters.PickerPageSize = $PickerPageSize
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

            if ($Purge)
            {
                $flags += 'Purge'
            }

            $managerText = if ($PackageManager -eq 'Auto')
            {
                "Auto -> $(Get-PlatformPackageManagerDetectedName)"
            }
            else
            {
                $PackageManager
            }

            $flagText = if ($flags.Count -gt 0) { $flags -join ', ' } else { 'none' }
            return "Manager: $managerText | Search limit: $Top | Flags: $flagText"
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

        function Write-PlatformPackageManagerHeader
        {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Title,

                [Parameter()]
                [String]$Subtitle
            )

            $rule = '=' * 78
            Write-Host $rule -ForegroundColor DarkGray
            Write-Host $Title -ForegroundColor Cyan
            if (-not [String]::IsNullOrWhiteSpace($Subtitle))
            {
                Write-Host $Subtitle -ForegroundColor White
            }

            Write-Host (Get-PlatformPackageManagerStatusText) -ForegroundColor DarkGray
            Write-Host $rule -ForegroundColor DarkGray
            Write-Host ''
        }

        function Format-PlatformPackageManagerResultTable
        {
            param(
                [Parameter()]
                [Object[]]$InputObject = @()
            )

            $records = @($InputObject | Where-Object { $null -ne $_ })
            if ($records.Count -eq 0)
            {
                return ''
            }

            $displayRecords = @(
                foreach ($record in $records)
                {
                    if ($record.PSObject.Properties['Results'])
                    {
                        $record | Select-Object -Property * -ExcludeProperty Results
                    }
                    else
                    {
                        $record
                    }
                }
            )

            return ($displayRecords | Format-Table -AutoSize | Out-String -Width 4096).TrimEnd()
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

            Clear-Host

            $recordSummary = if ($Result.RecordCount -eq 1) { '1 record' } else { "$($Result.RecordCount) records" }
            Write-PlatformPackageManagerHeader -Title $Result.Title -Subtitle "Result: $recordSummary"

            if (-not [String]::IsNullOrWhiteSpace($Result.Message))
            {
                Write-Host $Result.Message -ForegroundColor White
                Write-Host ''
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
                        Write-Host $table
                        Write-Host ''
                    }
                }

                $detailRecords = @(Get-PlatformPackageManagerNestedResults -InputObject $Result.Records)
                if ($detailRecords.Count -gt 0)
                {
                    Write-Host 'Details' -ForegroundColor Cyan
                    Write-Host ('-' * 78) -ForegroundColor DarkGray
                    $detailTable = Format-PlatformPackageManagerResultTable -InputObject $detailRecords
                    if (-not [String]::IsNullOrWhiteSpace($detailTable))
                    {
                        Write-Host $detailTable
                        Write-Host ''
                    }
                }
            }

            $statusIndicator = Get-PlatformPackageManagerOperationStatusIndicator -Records $Result.Records
            if ($null -ne $statusIndicator)
            {
                Write-Host $statusIndicator.Text -ForegroundColor $statusIndicator.Color
                Write-Host ''
            }

            Write-Host 'Any key: return to menu  Q/Esc: quit' -ForegroundColor DarkGray

            $isQuit = $false
            if ($KeyReader -or -not $PromptReader)
            {
                $pauseKey = Read-PlatformPackageManagerKey
                $isQuit = Test-PlatformPackageManagerCancelKey -KeyInfo $pauseKey
            }
            else
            {
                $rawValue = (Read-PlatformPackageManagerInput -Prompt 'Press Enter to return to menu').Trim()
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

        function Invoke-PlatformPackageManagerSearch
        {
            $query = Read-PlatformPackageManagerInput -Prompt 'Search query'
            if ($null -eq $query -or [String]::IsNullOrWhiteSpace($query))
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Search and Install Packages' -Message 'Search cancelled; query is required.' -AutoReturn)
            }
            $query = $query.Trim()

            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.Query = $query
            $parameters.Top = $Top
            Add-PlatformPackageManagerPickerParameters -Parameters $parameters

            if ($NoSudo)
            {
                $parameters.NoSudo = $true
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

            if ($PackageManager -eq 'winget' -and $direction -eq 'RequiredBy')
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Message 'winget does not expose reverse dependency metadata, so RequiredBy dependency lookup is unavailable.')
            }

            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.Package = $package
            $parameters.Direction = $direction
            $parameters.InstalledOnly = $installedOnly

            $records = @(Invoke-PlatformPackageManagerFunction -FunctionName 'Get-PlatformPackageDependency' -FileName 'Get-PlatformPackageDependency.ps1' -Parameters $parameters -Invocation {
                    param([Hashtable]$InvocationParameters)
                    Get-PlatformPackageDependency @InvocationParameters
                })
            $wingetReverseDependencyNote = ''
            if ($PackageManager -eq 'winget' -and $direction -eq 'Both')
            {
                $wingetReverseDependencyNote = 'winget does not expose reverse dependency metadata; RequiredBy results are unavailable.'
            }

            if ($records.Count -eq 0)
            {
                $message = 'No dependency relationships were found.'
                if (-not [String]::IsNullOrWhiteSpace($wingetReverseDependencyNote))
                {
                    $message = "$message $wingetReverseDependencyNote"
                }

                return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Message $message)
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Message $wingetReverseDependencyNote -Records $records)
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

            # User dismissed the picker without selecting — intentional, no notification needed
            return ''
        }

        function Get-PlatformPackageManagerMenuOptions
        {
            @(
                [PSCustomObject]@{
                    Choice = '1'
                    Workflow = 'Installed packages'
                    Purpose = 'Browse or filter installed package records'
                }
                [PSCustomObject]@{
                    Choice = '2'
                    Workflow = 'Search and install'
                    Purpose = 'Search the registry and optionally install results'
                }
                [PSCustomObject]@{
                    Choice = '3'
                    Workflow = 'Upgrade packages'
                    Purpose = 'Review or upgrade outdated packages'
                }
                [PSCustomObject]@{
                    Choice = '4'
                    Workflow = 'Remove packages'
                    Purpose = 'Review or remove installed packages'
                }
                [PSCustomObject]@{
                    Choice = '5'
                    Workflow = 'Dependencies'
                    Purpose = 'Inspect dependency relationships'
                }
                [PSCustomObject]@{
                    Choice = 'Q'
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
            Write-Host ('{0,-3} {1,-7} {2,-24} {3}' -f '', 'Action', 'Workflow', 'Purpose') -ForegroundColor DarkGray
            Write-Host ('{0,-3} {1,-7} {2,-24} {3}' -f '', '------', '--------', '-------') -ForegroundColor DarkGray
            for ($i = 0; $i -lt $Options.Count; $i++)
            {
                $marker = if ($i -eq $SelectedIndex) { '>' } else { ' ' }
                $accentColor = if ($i -eq $SelectedIndex) { 'Cyan' } else { 'DarkGray' }
                $workflowColor = if ($i -eq $SelectedIndex) { 'Cyan' } else { 'White' }
                Write-Host ('{0,-3} ' -f $marker) -NoNewline -ForegroundColor $accentColor
                Write-Host ('{0,-7} ' -f "[$($Options[$i].Choice)]") -NoNewline -ForegroundColor $accentColor
                Write-Host ('{0,-24} ' -f $Options[$i].Workflow) -NoNewline -ForegroundColor $workflowColor
                Write-Host $Options[$i].Purpose -ForegroundColor DarkGray
            }

            Write-Host ''
            if (-not [String]::IsNullOrWhiteSpace($Notification))
            {
                Write-Host "  ! $Notification" -ForegroundColor DarkYellow
                Write-Host ''
            }

            if ($SelectedIndex -ge 0)
            {
                Write-Host 'Up/Down: choose  Enter: run  Number/Q: jump' -ForegroundColor DarkGray
                Write-Host ''
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
                Write-PlatformPackageManagerMenu -Options $options -Notification $Notification
                return ((Read-PlatformPackageManagerInput -Prompt 'Select an action').Trim())
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
                            'b' { return '1' }
                            's' { return '2' }
                            'i' { return '2' }
                            'u' { return '3' }
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
                { $_ -in @('1', 'installed', 'browse') } { Invoke-PlatformPackageManagerInstalledBrowser; break }
                { $_ -in @('2', 'search', 'find', 'install') } { Invoke-PlatformPackageManagerSearch; break }
                { $_ -in @('3', 'upgrade', 'update') } { Invoke-PlatformPackageManagerUpgrade; break }
                { $_ -in @('4', 'remove', 'uninstall') } { Invoke-PlatformPackageManagerRemoval; break }
                { $_ -in @('5', 'deps', 'dependencies', 'dependency') } { Invoke-PlatformPackageManagerDependencyView; break }
                default { Get-PlatformPackageManagerActionResult -Title 'Platform Package Manager' -Message 'Choose 1-5 or Q.' }
            }
        }

    }

    process
    {
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
