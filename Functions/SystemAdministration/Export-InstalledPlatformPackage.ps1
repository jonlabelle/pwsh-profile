function Export-InstalledPlatformPackage
{
    <#
    .SYNOPSIS
        Exports installed platform package records to JSON or CSV.

    .DESCRIPTION
        Writes normalized package records to a JSON or CSV file. Package records can be
        piped from Get-PlatformPackage or supplied through -Package. The export format is
        inferred from the file extension by default, or can be supplied explicitly with
        -Format.

        Use -DependencyMode DependsOn to include direct dependency relationships, or
        -DependencyMode Both to include direct and reverse dependency relationships where
        the selected package manager supports them.

    .PARAMETER Package
        Installed package records to export. Objects returned by Get-PlatformPackage or
        Show-InstalledPlatformPackage can be piped directly into this function.

    .PARAMETER Path
        Output file path. .json and .csv extensions are inferred when -Format is Auto.

    .PARAMETER Format
        Export format. Auto infers the format from the output path extension.

    .PARAMETER DependencyMode
        Dependency relationships to include. None exports package records only. DependsOn
        includes direct dependencies. Both includes direct dependencies and packages that
        require each exported package.

    .PARAMETER ShowProgress
        Writes progress while dependency relationships are resolved.

    .EXAMPLE
        PS > Get-PlatformPackage | Export-InstalledPlatformPackage -Path ./packages.json

        Exports installed packages to JSON.

    .EXAMPLE
        PS > Get-PlatformPackage -Name 'git' | Export-InstalledPlatformPackage -Path ./git.csv -DependencyMode Both

        Exports the matching package to CSV with direct and reverse dependency
        relationships.

    .EXAMPLE
        PS > Get-PlatformPackage | Export-InstalledPlatformPackage -Path ./packages -Format Csv

        Exports installed packages to CSV when the path does not have a .csv extension.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Export-InstalledPlatformPackage.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Export-InstalledPlatformPackage.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [PSCustomObject[]]$Package = @(),

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Path,

        [Parameter()]
        [ValidateSet('Auto', 'Json', 'Csv')]
        [String]$Format = 'Auto',

        [Parameter()]
        [ValidateSet('None', 'DependsOn', 'Both')]
        [String]$DependencyMode = 'None',

        [Parameter(DontShow = $true)]
        [ScriptBlock]$CommandRunner,

        [Parameter(DontShow = $true)]
        [ScriptBlock]$CancelRequested,

        [Parameter(DontShow = $true)]
        [Switch]$ShowProgress
    )

    begin
    {
        $packageRecords = New-Object 'System.Collections.Generic.List[PSCustomObject]'

        function Get-ExportDependencyPathIfNeeded
        {
            param(
                [Parameter(Mandatory)]
                [String]$FunctionName,

                [Parameter(Mandatory)]
                [String]$RelativePath
            )

            if (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue)
            {
                return $null
            }

            $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath $RelativePath
            $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)
            if (Test-Path -Path $dependencyPath -PathType Leaf)
            {
                return $dependencyPath
            }

            throw "Required function '$FunctionName' could not be found. Expected location: $dependencyPath"
        }

        function Get-PackageExportFormatFromPath
        {
            param(
                [Parameter(Mandatory)]
                [String]$ExportPath
            )

            $extension = [System.IO.Path]::GetExtension($ExportPath)
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

        function Resolve-PackageExportFormat
        {
            param(
                [Parameter(Mandatory)]
                [String]$ExportPath,

                [Parameter(Mandatory)]
                [ValidateSet('Auto', 'Json', 'Csv')]
                [String]$RequestedFormat
            )

            if ($RequestedFormat -ne 'Auto')
            {
                return $RequestedFormat
            }

            $inferredFormat = Get-PackageExportFormatFromPath -ExportPath $ExportPath
            if (-not [String]::IsNullOrWhiteSpace($inferredFormat))
            {
                return $inferredFormat
            }

            throw "Export format could not be inferred from '$ExportPath'. Use -Format Json or -Format Csv."
        }

        function Resolve-PackageExportPath
        {
            param(
                [Parameter(Mandatory)]
                [String]$ExportPath
            )

            $expandedPath = [Environment]::ExpandEnvironmentVariables($ExportPath.Trim())
            try
            {
                $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($expandedPath)
            }
            catch
            {
                throw "Invalid export path '$ExportPath': $($_.Exception.Message)"
            }

            if (Test-Path -LiteralPath $resolvedPath -PathType Container)
            {
                throw "Export path points to a directory: $resolvedPath"
            }

            $parentPath = Split-Path -Path $resolvedPath -Parent
            if (-not [String]::IsNullOrWhiteSpace($parentPath) -and -not (Test-Path -LiteralPath $parentPath -PathType Container))
            {
                throw "Export directory does not exist: $parentPath"
            }

            return $resolvedPath
        }

        function Test-PackageExportCancelRequested
        {
            if ($CancelRequested)
            {
                return [Bool](& $CancelRequested)
            }

            return $false
        }

        function Write-PackageExportProgress
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$PackageRecord,

                [Parameter()]
                [Int32]$PackageIndex = 0,

                [Parameter()]
                [Int32]$PackageCount = 0,

                [Parameter()]
                [String]$Direction = '',

                [Parameter()]
                [String]$ExportPath = ''
            )

            if (-not $ShowProgress)
            {
                return
            }

            Clear-Host
            Write-Host 'Exporting installed packages...' -ForegroundColor Cyan
            if ($PackageCount -gt 0 -and $PackageIndex -gt 0)
            {
                Write-Host "Package: $PackageIndex of $PackageCount - $($PackageRecord.Name)" -ForegroundColor White
            }
            else
            {
                Write-Host "Package: $($PackageRecord.Name)" -ForegroundColor White
            }

            if (-not [String]::IsNullOrWhiteSpace($Direction))
            {
                Write-Host "Resolving: $Direction" -ForegroundColor White
            }

            if (-not [String]::IsNullOrWhiteSpace($ExportPath))
            {
                Write-Host "File: $ExportPath" -ForegroundColor DarkGray
            }

            Write-Host ''
            if ($CancelRequested)
            {
                Write-Host 'Esc cancels between dependency lookups. Ctrl+C stops the current lookup.' -ForegroundColor DarkGray
            }
            else
            {
                Write-Host 'Ctrl+C stops the current lookup.' -ForegroundColor DarkGray
            }
        }

        function Get-PackageExportDependencyData
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$PackageRecord,

                [Parameter(Mandatory)]
                [ValidateSet('DependsOn', 'Both')]
                [String]$RequestedDependencyMode,

                [Parameter()]
                [Int32]$PackageIndex = 0,

                [Parameter()]
                [Int32]$PackageCount = 0,

                [Parameter()]
                [String]$ExportPath = ''
            )

            $dependencyPath = Get-ExportDependencyPathIfNeeded -FunctionName 'Get-PlatformPackageDependency' -RelativePath 'Get-PlatformPackageDependency.ps1'
            if (-not [String]::IsNullOrWhiteSpace($dependencyPath))
            {
                try
                {
                    . $dependencyPath
                }
                catch
                {
                    throw "Failed to load required dependency 'Get-PlatformPackageDependency' from '$dependencyPath': $($_.Exception.Message)"
                }
            }

            $dependencyRecords = @()
            $dependencyErrors = @()
            $directions = if ($RequestedDependencyMode -eq 'Both') { @('DependsOn', 'RequiredBy') } else { @('DependsOn') }

            foreach ($direction in $directions)
            {
                if (Test-PackageExportCancelRequested)
                {
                    throw [System.OperationCanceledException]::new('Export canceled.')
                }

                Write-PackageExportProgress -PackageRecord $PackageRecord -PackageIndex $PackageIndex -PackageCount $PackageCount -Direction $direction -ExportPath $ExportPath

                $parameters = @{
                    Package = @($PackageRecord)
                    Direction = $direction
                    PackageManager = $PackageRecord.PackageManager
                }
                if ($CommandRunner)
                {
                    $parameters.CommandRunner = $CommandRunner
                }

                try
                {
                    foreach ($dependencyRecord in @(Get-PlatformPackageDependency @parameters))
                    {
                        $dependencyRecords += [PSCustomObject]@{
                            Direction = $dependencyRecord.Direction
                            Relationship = $dependencyRecord.Relationship
                            RelatedPackage = $dependencyRecord.RelatedPackage
                            DependencyType = $dependencyRecord.DependencyType
                            Installed = $dependencyRecord.Installed
                            Notes = $dependencyRecord.Notes
                        }
                    }
                }
                catch
                {
                    if ($_.Exception -is [System.OperationCanceledException])
                    {
                        throw
                    }

                    $dependencyErrors += "$direction`: $($_.Exception.Message)"
                }

                if (Test-PackageExportCancelRequested)
                {
                    throw [System.OperationCanceledException]::new('Export canceled.')
                }
            }

            return [PSCustomObject]@{
                Records = @($dependencyRecords)
                Error = ($dependencyErrors -join '; ')
            }
        }

        function ConvertTo-PackageExportRecord
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$PackageRecord,

                [Parameter(Mandatory)]
                [ValidateSet('Json', 'Csv')]
                [String]$ResolvedFormat,

                [Parameter()]
                [ValidateSet('None', 'DependsOn', 'Both')]
                [String]$RequestedDependencyMode = 'None',

                [Parameter()]
                [Int32]$PackageIndex = 0,

                [Parameter()]
                [Int32]$PackageCount = 0,

                [Parameter()]
                [String]$ExportPath = ''
            )

            $dependencyRecords = @()
            $dependencyLookupError = ''
            if ($RequestedDependencyMode -ne 'None')
            {
                $dependencyData = Get-PackageExportDependencyData -PackageRecord $PackageRecord -RequestedDependencyMode $RequestedDependencyMode -PackageIndex $PackageIndex -PackageCount $PackageCount -ExportPath $ExportPath
                $dependencyRecords = @($dependencyData.Records)
                $dependencyLookupError = "$($dependencyData.Error)"
            }

            $baseRecord = [Ordered]@{
                Name = $PackageRecord.Name
                Id = $PackageRecord.Id
                PackageManager = $PackageRecord.PackageManager
                PackageManagerDisplayName = $PackageRecord.PackageManagerDisplayName
                Type = $PackageRecord.Type
                InstalledVersion = $PackageRecord.InstalledVersion
                Source = $PackageRecord.Source
                Publisher = $PackageRecord.Publisher
                Description = $PackageRecord.Description
                Notes = $PackageRecord.Notes
            }

            if ($ResolvedFormat -eq 'Csv')
            {
                $baseRecord['DependsOn'] = (($dependencyRecords | Where-Object { $_.Direction -eq 'DependsOn' } | ForEach-Object { $_.RelatedPackage }) -join '; ')
                $baseRecord['RequiredBy'] = (($dependencyRecords | Where-Object { $_.Direction -eq 'RequiredBy' } | ForEach-Object { $_.RelatedPackage }) -join '; ')
                $baseRecord['DependencyLookupError'] = $dependencyLookupError
                return [PSCustomObject]$baseRecord
            }

            $baseRecord['Dependencies'] = @($dependencyRecords)
            $baseRecord['DependencyLookupError'] = $dependencyLookupError
            return [PSCustomObject]$baseRecord
        }
    }

    process
    {
        foreach ($packageRecord in @($Package | Where-Object { $null -ne $_ }))
        {
            $packageRecords.Add($packageRecord)
        }
    }

    end
    {
        if ($packageRecords.Count -eq 0)
        {
            throw 'no packages are available for the current scope'
        }

        $resolvedPath = Resolve-PackageExportPath -ExportPath $Path
        $resolvedFormat = Resolve-PackageExportFormat -ExportPath $resolvedPath -RequestedFormat $Format

        $exportRecords = @()
        for ($packageIndex = 0; $packageIndex -lt $packageRecords.Count; $packageIndex++)
        {
            if (Test-PackageExportCancelRequested)
            {
                throw [System.OperationCanceledException]::new('Export canceled.')
            }

            $packageRecord = $packageRecords[$packageIndex]
            $exportRecords += ConvertTo-PackageExportRecord -PackageRecord $packageRecord -ResolvedFormat $resolvedFormat -RequestedDependencyMode $DependencyMode -PackageIndex ($packageIndex + 1) -PackageCount $packageRecords.Count -ExportPath $resolvedPath
        }

        switch ($resolvedFormat)
        {
            'Json'
            {
                $jsonText = ConvertTo-Json -InputObject @($exportRecords) -Depth 8
                Set-Content -LiteralPath $resolvedPath -Value $jsonText -Encoding UTF8
            }
            'Csv'
            {
                $exportRecords | Export-Csv -LiteralPath $resolvedPath -NoTypeInformation -Encoding UTF8
            }
        }

        return [PSCustomObject]@{
            PSTypeName = 'InstalledPlatformPackage.ExportResult'
            Path = $resolvedPath
            Format = $resolvedFormat.ToUpperInvariant()
            Count = $exportRecords.Count
            DependencyMode = $DependencyMode
            IncludeDependencies = $DependencyMode -ne 'None'
        }
    }
}
