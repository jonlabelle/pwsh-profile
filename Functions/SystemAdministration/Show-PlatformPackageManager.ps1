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
        - Find-PlatformPackage for remote registry search and search-driven installs.
        - Install-PlatformPackage for direct name or id installs.
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
    [CmdletBinding()]
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
                    return ''
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

            return (Read-Host -Prompt $Prompt)
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
                $value = (Read-PlatformPackageManagerInput -Prompt "$Prompt [$suffix]").Trim()
                if ([String]::IsNullOrWhiteSpace($value))
                {
                    return $DefaultYes.IsPresent
                }

                switch ($value.ToLowerInvariant())
                {
                    { $_ -in @('y', 'yes') } { return $true }
                    { $_ -in @('n', 'no') } { return $false }
                    default { Write-Host 'Enter y or n.' }
                }
            }
        }

        function Read-PlatformPackageDependencyDirection
        {
            while ($true)
            {
                Write-Host 'Dependency direction:'
                Write-Host '  1. Depends on'
                Write-Host '  2. Required by'
                Write-Host '  3. Both'

                $value = (Read-PlatformPackageManagerInput -Prompt 'Select direction [1]').Trim()
                if ([String]::IsNullOrWhiteSpace($value))
                {
                    return 'DependsOn'
                }

                switch ($value.ToLowerInvariant())
                {
                    { $_ -in @('1', 'depends', 'dependson', 'depends on') } { return 'DependsOn' }
                    { $_ -in @('2', 'requiredby', 'required by', 'uses') } { return 'RequiredBy' }
                    { $_ -in @('3', 'both', 'all') } { return 'Both' }
                    default { Write-Host 'Choose 1, 2, or 3.' }
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

            $flagText = if ($flags.Count -gt 0) { $flags -join ', ' } else { 'none' }
            return "Manager: $PackageManager | Search limit: $Top | Flags: $flagText"
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
            Write-Host $rule
            Write-Host $Title
            if (-not [String]::IsNullOrWhiteSpace($Subtitle))
            {
                Write-Host $Subtitle
            }

            Write-Host (Get-PlatformPackageManagerStatusText)
            Write-Host $rule
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

            return ($records | Format-Table -AutoSize | Out-String -Width 4096).TrimEnd()
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
                [Object[]]$Records = @()
            )

            $recordList = @($Records | Where-Object { $null -ne $_ })
            return [PSCustomObject]@{
                PSTypeName = 'PlatformPackageManager.ActionResult'
                Title = $Title
                Message = $Message
                Records = $recordList
                RecordCount = $recordList.Count
            }
        }

        function Read-PlatformPackageManagerNextAction
        {
            while ($true)
            {
                $value = (Read-PlatformPackageManagerInput -Prompt 'Next action').Trim()
                if ([String]::IsNullOrWhiteSpace($value) -or $value.ToLowerInvariant() -in @('m', 'menu'))
                {
                    return [PSCustomObject]@{
                        Command = 'Menu'
                        Choice = ''
                    }
                }

                if ($value.ToLowerInvariant() -in @('q', 'quit', 'exit'))
                {
                    return [PSCustomObject]@{
                        Command = 'Quit'
                        Choice = ''
                    }
                }

                if ($value.ToLowerInvariant() -in @('1', '2', '3', '4', '5', '6', 'installed', 'browse', 'search', 'find', 'install', 'upgrade', 'update', 'remove', 'uninstall', 'deps', 'dependencies', 'dependency'))
                {
                    return [PSCustomObject]@{
                        Command = 'Action'
                        Choice = $value
                    }
                }

                Write-Host 'Choose Enter/M for menu, 1-6 for another action, or Q to quit.'
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
                Write-Host $Result.Message
                Write-Host ''
            }

            if ($Result.RecordCount -gt 0)
            {
                $table = Format-PlatformPackageManagerResultTable -InputObject $Result.Records
                if (-not [String]::IsNullOrWhiteSpace($table))
                {
                    Write-Host $table
                    Write-Host ''
                }
            }

            Write-Host 'Enter/M: menu  1-6: run another action  Q: quit'
            return (Read-PlatformPackageManagerNextAction)
        }

        function Invoke-PlatformPackageManagerInstalledBrowser
        {
            $includePackage = @(Read-PlatformPackageManagerList -Prompt 'Installed package filter (comma-separated, optional)')
            $excludePackage = @(Read-PlatformPackageManagerList -Prompt 'Exclude installed packages (comma-separated, optional)')

            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.Name = $includePackage
            $parameters.ExcludePackage = $excludePackage
            Add-PlatformPackageManagerPickerParameters -Parameters $parameters

            $result = @(Show-InstalledPlatformPackage @parameters)
            if ($result.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Installed Packages' -Message 'Installed package browser closed.')
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Installed Packages' -Records $result)
        }

        function Invoke-PlatformPackageManagerSearch
        {
            $query = (Read-PlatformPackageManagerInput -Prompt 'Search query').Trim()
            if ([String]::IsNullOrWhiteSpace($query))
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Search Packages' -Message 'Search cancelled; query is required.')
            }

            $excludePackage = @(Read-PlatformPackageManagerList -Prompt 'Exclude search results (comma-separated, optional)')

            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.Query = $query
            $parameters.ExcludePackage = $excludePackage
            $parameters.Top = $Top
            Add-PlatformPackageManagerPickerParameters -Parameters $parameters

            $result = @(Find-PlatformPackage @parameters)
            if ($result.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Search Packages' -Message 'Search completed with no result records.')
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Search Packages' -Records $result)
        }

        function Invoke-PlatformPackageManagerDirectInstall
        {
            $installMode = ''
            while ([String]::IsNullOrWhiteSpace($installMode))
            {
                $value = (Read-PlatformPackageManagerInput -Prompt 'Install by name or id? [name]').Trim()
                if ([String]::IsNullOrWhiteSpace($value))
                {
                    $installMode = 'name'
                    break
                }

                switch ($value.ToLowerInvariant())
                {
                    { $_ -in @('name', 'n') } { $installMode = 'name' }
                    { $_ -in @('id', 'i') } { $installMode = 'id' }
                    default { Write-Host 'Enter name or id.' }
                }
            }

            $targetPrompt = if ($installMode -eq 'id') { 'Package id(s), comma-separated' } else { 'Package name(s), comma-separated' }
            $targets = @(Read-PlatformPackageManagerList -Prompt $targetPrompt)
            if ($targets.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Install Packages' -Message 'Install cancelled; at least one package is required.')
            }

            $parameters = Get-PlatformPackageManagerCommonParameters
            if ($installMode -eq 'id')
            {
                $parameters.Id = $targets
            }
            else
            {
                $parameters.Name = $targets
            }

            if ($NoSudo)
            {
                $parameters.NoSudo = $true
            }

            $result = @(Install-PlatformPackage @parameters)
            if ($result.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Install Packages' -Message 'Install completed with no result records.')
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Install Packages' -Records $result)
        }

        function Invoke-PlatformPackageManagerUpgrade
        {
            $includePackage = @(Read-PlatformPackageManagerList -Prompt 'Upgrade package filter (comma-separated, optional)')
            $excludePackage = @(Read-PlatformPackageManagerList -Prompt 'Exclude upgrades (comma-separated, optional)')
            $all = Read-PlatformPackageManagerYesNo -Prompt 'Upgrade all matching packages without the picker?'

            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.IncludePackage = $includePackage
            $parameters.ExcludePackage = $excludePackage
            $parameters.All = $all
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

            $result = @(Upgrade-PlatformPackage @parameters)
            if ($result.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Upgrade Packages' -Message 'Upgrade completed with no result records.')
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Upgrade Packages' -Records $result)
        }

        function Invoke-PlatformPackageManagerRemoval
        {
            $includePackage = @(Read-PlatformPackageManagerList -Prompt 'Remove package filter (comma-separated, optional)')
            $excludePackage = @(Read-PlatformPackageManagerList -Prompt 'Exclude removals (comma-separated, optional)')
            $all = Read-PlatformPackageManagerYesNo -Prompt 'Remove all matching packages without the picker?'

            if ($all -and $includePackage.Count -eq 0)
            {
                Write-Host 'Remove all requires an include filter; opening the picker instead.'
                $all = $false
            }

            $usePurge = $Purge -or (Read-PlatformPackageManagerYesNo -Prompt 'Request purge/zap cleanup?')

            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.IncludePackage = $includePackage
            $parameters.ExcludePackage = $excludePackage
            $parameters.All = $all
            $parameters.Purge = $usePurge
            Add-PlatformPackageManagerPickerParameters -Parameters $parameters

            if ($NoSudo)
            {
                $parameters.NoSudo = $true
            }

            $result = @(Remove-PlatformPackage @parameters)
            if ($result.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Remove Packages' -Message 'Removal completed with no result records.')
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Remove Packages' -Records $result)
        }

        function Invoke-PlatformPackageManagerDependencyView
        {
            $package = @(Read-PlatformPackageManagerList -Prompt 'Package name or id (comma-separated)')
            if ($package.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Message 'Dependency lookup cancelled; at least one package is required.')
            }

            $direction = Read-PlatformPackageDependencyDirection
            $installedOnly = Read-PlatformPackageManagerYesNo -Prompt 'Limit related packages to installed packages?'

            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.Package = $package
            $parameters.Direction = $direction
            $parameters.InstalledOnly = $installedOnly

            $records = @(Get-PlatformPackageDependency @parameters)
            if ($records.Count -eq 0)
            {
                return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Message 'No dependency relationships were found.')
            }

            return (Get-PlatformPackageManagerActionResult -Title 'Package Dependencies' -Records $records)
        }

        function Write-PlatformPackageManagerMenu
        {
            Clear-Host
            Write-PlatformPackageManagerHeader -Title 'Platform Package Manager' -Subtitle 'Unified native package management workflows'
            Write-Host ('{0,-7} {1,-24} {2}' -f 'Action', 'Workflow', 'Purpose')
            Write-Host ('{0,-7} {1,-24} {2}' -f '------', '--------', '-------')
            Write-Host ('{0,-7} {1,-24} {2}' -f '[1]', 'Installed packages', 'Browse or filter installed package records')
            Write-Host ('{0,-7} {1,-24} {2}' -f '[2]', 'Search and install', 'Search the registry and optionally install results')
            Write-Host ('{0,-7} {1,-24} {2}' -f '[3]', 'Direct install', 'Install package names or ids directly')
            Write-Host ('{0,-7} {1,-24} {2}' -f '[4]', 'Upgrade packages', 'Review or upgrade outdated packages')
            Write-Host ('{0,-7} {1,-24} {2}' -f '[5]', 'Remove packages', 'Review or remove installed packages')
            Write-Host ('{0,-7} {1,-24} {2}' -f '[6]', 'Dependencies', 'Inspect dependency relationships')
            Write-Host ('{0,-7} {1,-24} {2}' -f '[Q]', 'Quit', 'Exit the manager')
            Write-Host ''
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
                { $_ -in @('2', 'search', 'find') } { Invoke-PlatformPackageManagerSearch; break }
                { $_ -in @('3', 'install') } { Invoke-PlatformPackageManagerDirectInstall; break }
                { $_ -in @('4', 'upgrade', 'update') } { Invoke-PlatformPackageManagerUpgrade; break }
                { $_ -in @('5', 'remove', 'uninstall') } { Invoke-PlatformPackageManagerRemoval; break }
                { $_ -in @('6', 'deps', 'dependencies', 'dependency') } { Invoke-PlatformPackageManagerDependencyView; break }
                default { Get-PlatformPackageManagerActionResult -Title 'Platform Package Manager' -Message 'Choose 1-6 or Q.' }
            }
        }

        $dependencyFiles = @(
            @{ FunctionName = 'Get-PlatformPackage'; FileName = 'Get-PlatformPackage.ps1' }
            @{ FunctionName = 'Find-PlatformPackage'; FileName = 'Find-PlatformPackage.ps1' }
            @{ FunctionName = 'Install-PlatformPackage'; FileName = 'Install-PlatformPackage.ps1' }
            @{ FunctionName = 'Upgrade-PlatformPackage'; FileName = 'Upgrade-PlatformPackage.ps1' }
            @{ FunctionName = 'Remove-PlatformPackage'; FileName = 'Remove-PlatformPackage.ps1' }
            @{ FunctionName = 'Get-PlatformPackageDependency'; FileName = 'Get-PlatformPackageDependency.ps1' }
            @{ FunctionName = 'Show-InstalledPlatformPackage'; FileName = 'Show-InstalledPlatformPackage.ps1' }
        )

        foreach ($dependencyFile in $dependencyFiles)
        {
            $dependencyPath = Get-PlatformPackageManagerDependencyPath -FunctionName $dependencyFile.FunctionName -FileName $dependencyFile.FileName
            if ([String]::IsNullOrWhiteSpace($dependencyPath))
            {
                continue
            }

            try
            {
                . $dependencyPath
                Write-Verbose "Loaded $($dependencyFile.FunctionName) from: $dependencyPath"
            }
            catch
            {
                throw "Failed to load required dependency '$($dependencyFile.FunctionName)' from '$dependencyPath': $($_.Exception.Message)"
            }
        }
    }

    process
    {
        $pendingChoice = ''

        while ($true)
        {
            if ([String]::IsNullOrWhiteSpace($pendingChoice))
            {
                Write-PlatformPackageManagerMenu
                $choice = (Read-PlatformPackageManagerInput -Prompt 'Select an action').Trim()
            }
            else
            {
                $choice = $pendingChoice
                $pendingChoice = ''
            }

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

            $nextAction = Show-PlatformPackageManagerResultScreen -Result $actionResult
            switch ($nextAction.Command)
            {
                'Quit'
                {
                    return
                }
                'Action'
                {
                    $pendingChoice = $nextAction.Choice
                }
                default
                {
                    $pendingChoice = ''
                }
            }
        }
    }
}
