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
        System.Management.Automation.PSCustomObject
        Returns summary objects emitted by the underlying install, upgrade, remove, or
        dependency commands. Menu-only and cancelled interactive workflows return no output.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Show-PlatformPackageManager.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Show-PlatformPackageManager.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [PSCustomObject[]], [Object[]])]
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

        function Write-PlatformPackageManagerResultTable
        {
            param(
                [Parameter()]
                [Object[]]$InputObject = @()
            )

            $records = @($InputObject | Where-Object { $null -ne $_ })
            if ($records.Count -eq 0)
            {
                return
            }

            $records | Format-Table -AutoSize | Out-String | Write-Host
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
            Write-PlatformPackageManagerResultTable -InputObject $result
        }

        function Invoke-PlatformPackageManagerSearch
        {
            $query = (Read-PlatformPackageManagerInput -Prompt 'Search query').Trim()
            if ([String]::IsNullOrWhiteSpace($query))
            {
                Write-Host 'Search cancelled; query is required.'
                return
            }

            $excludePackage = @(Read-PlatformPackageManagerList -Prompt 'Exclude search results (comma-separated, optional)')

            $parameters = Get-PlatformPackageManagerCommonParameters
            $parameters.Query = $query
            $parameters.ExcludePackage = $excludePackage
            $parameters.Top = $Top
            Add-PlatformPackageManagerPickerParameters -Parameters $parameters

            $result = @(Find-PlatformPackage @parameters)
            Write-PlatformPackageManagerResultTable -InputObject $result
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
                Write-Host 'Install cancelled; at least one package is required.'
                return
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
            Write-PlatformPackageManagerResultTable -InputObject $result
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
            Write-PlatformPackageManagerResultTable -InputObject $result
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
            Write-PlatformPackageManagerResultTable -InputObject $result
        }

        function Invoke-PlatformPackageManagerDependencyView
        {
            $package = @(Read-PlatformPackageManagerList -Prompt 'Package name or id (comma-separated)')
            if ($package.Count -eq 0)
            {
                Write-Host 'Dependency lookup cancelled; at least one package is required.'
                return
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
                Write-Host 'No dependency relationships were found.'
                return @()
            }

            Write-PlatformPackageManagerResultTable -InputObject $records
        }

        function Write-PlatformPackageManagerMenu
        {
            Clear-Host
            Write-Host 'Show-PlatformPackageManager'
            Write-Host ''
            Write-Host '  1. Browse installed packages'
            Write-Host '  2. Search packages and install from results'
            Write-Host '  3. Install package by name or id'
            Write-Host '  4. Upgrade packages'
            Write-Host '  5. Remove packages'
            Write-Host '  6. Inspect package dependencies'
            Write-Host '  Q. Quit'
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
                default { Write-Host 'Choose 1-6 or Q.' }
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
        while ($true)
        {
            Write-PlatformPackageManagerMenu
            $choice = (Read-PlatformPackageManagerInput -Prompt 'Select an action').Trim()

            if ($choice.ToLowerInvariant() -in @('q', 'quit', 'exit'))
            {
                return
            }

            if ([String]::IsNullOrWhiteSpace($choice))
            {
                continue
            }

            Invoke-PlatformPackageManagerAction -Choice $choice
        }
    }
}
