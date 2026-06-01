function Update-DotNetTool
{
    <#
    .SYNOPSIS
        Updates local or global .NET tools based on the current directory context.

    .DESCRIPTION
        Searches the specified directory and its parent directories for a local .NET
        tool manifest at .config/dotnet-tools.json. In the default Auto scope, every
        tool in that local manifest is updated when a manifest is found. When no local
        manifest is found, every globally installed .NET tool for the current user is
        updated.

        Use -Scope Local or -Scope Global to explicitly choose which tool scope to
        inspect or update. Use -ListOutdated to perform a read-only check that displays
        only tools where the installed version differs from the latest version returned
        by 'dotnet tool search' or the NuGet flat-container metadata fallback.

        The function lists installed tools first and updates each package explicitly,
        which provides per-tool status information and keeps behavior consistent across
        .NET SDK versions. Cross-platform compatible with PowerShell 5.1+ on Windows,
        macOS, and Linux. Requires the dotnet CLI to be installed and available in PATH.

    .PARAMETER Path
        The directory used to discover a local .NET tool manifest. Defaults to the
        current directory. If no manifest is found in this directory or any parent
        directory, global tools are updated.

    .PARAMETER Scope
        Controls which .NET tool scope is used:
        - Auto   : Use local tools when a local manifest exists; otherwise use global tools.
        - Local  : Require a local tool manifest and use local tools.
        - Global : Use global tools even when a local tool manifest exists.

    .PARAMETER ListOutdated
        Displays only outdated tools and does not update anything. Latest versions are
        resolved with 'dotnet tool search' first, then the NuGet flat-container metadata
        API when the dotnet search command fails. Use -Scope to choose Local or Global
        explicitly, or leave Scope as Auto to use local tools when a manifest exists.

    .PARAMETER Prerelease
        Includes prerelease packages when updating tools.

    .PARAMETER Interactive
        Allows dotnet to stop and wait for user input or action, such as completing
        authentication for a package source.

    .PARAMETER IgnoreFailedSources
        Treats package source failures as warnings during tool updates.

    .PARAMETER NoHttpCache
        Prevents dotnet from using HTTP cache data during tool updates.

    .PARAMETER DisableParallel
        Prevents dotnet restore from restoring multiple projects in parallel during
        tool updates.

    .PARAMETER Framework
        The target framework to use when updating each tool. Passed directly to
        'dotnet tool update --framework'.

    .PARAMETER AdditionalArgs
        Additional arguments to pass directly to each 'dotnet tool update' invocation.
        Use this for less common dotnet options such as --verbosity or --add-source.

    .EXAMPLE
        PS > Update-DotNetTool

        Updates all local tools when a .config/dotnet-tools.json manifest exists in the
        current directory tree; otherwise updates all global tools.

    .EXAMPLE
        PS > Update-DotNetTool -Path ~/src/myapp

        Uses ~/src/myapp as the starting directory for local tool manifest discovery.

    .EXAMPLE
        PS > Update-DotNetTool -Scope Local

        Updates local tools and throws if no local .NET tool manifest exists in the
        current directory tree.

    .EXAMPLE
        PS > Update-DotNetTool -Scope Global

        Updates globally installed .NET tools even when the current directory tree has
        a local .NET tool manifest.

    .EXAMPLE
        PS > Update-DotNetTool -ListOutdated

        Displays only outdated tools in the automatically selected local or global scope
        without updating anything.

    .EXAMPLE
        PS > Update-DotNetTool -Scope Local -ListOutdated

        Displays only outdated local tools from the nearest .NET tool manifest.

    .EXAMPLE
        PS > Update-DotNetTool -Verbose

        Updates the appropriate local or global tools and writes detailed progress.

    .EXAMPLE
        PS > Update-DotNetTool -WhatIf

        Shows which local or global tools would be updated without running updates.

    .EXAMPLE
        PS > Update-DotNetTool -Prerelease

        Updates tools while allowing prerelease tool package versions.

    .EXAMPLE
        PS > Update-DotNetTool -Interactive

        Updates tools and allows interactive package source authentication prompts.

    .EXAMPLE
        PS > Update-DotNetTool -IgnoreFailedSources

        Updates tools while treating unavailable package sources as warnings.

    .EXAMPLE
        PS > Update-DotNetTool -NoHttpCache

        Updates tools without using cached HTTP package metadata.

    .EXAMPLE
        PS > Update-DotNetTool -DisableParallel

        Updates tools with parallel restore disabled.

    .EXAMPLE
        PS > Update-DotNetTool -Framework net10.0

        Updates tools targeting the net10.0 framework.

    .EXAMPLE
        PS > Get-ChildItem -Path ~/src -Directory | Update-DotNetTool

        Updates local tools for each project directory that has a local manifest in
        its directory tree; otherwise updates global tools for that input directory.

    .EXAMPLE
        PS > Update-DotNetTool -AdditionalArgs '--verbosity', 'minimal'

        Updates tools and passes additional dotnet update arguments through to each
        update command.

    .OUTPUTS
        [PSCustomObject]

        Returns an object with summary information:

        - Scope            : Local when a local tool manifest is found; otherwise Global
        - WorkingDirectory : Directory used for manifest discovery and dotnet invocation
        - ManifestPath     : Local tool manifest path, or $null for global updates
        - ToolsFound       : Number of tools discovered before updating
        - Updated          : Number of tools updated successfully
        - Skipped          : Number of tools skipped by -WhatIf or -Confirm
        - Failed           : Number of tools that failed to update
        - ExitCode         : 0 when all updates succeeded; otherwise 1
        - Results          : Per-tool result objects with PackageId, Version, Status, and Message

        When -ListOutdated is specified, returns one object per outdated tool with
        Scope, PackageId, CurrentVersion, LatestVersion, WorkingDirectory, and ManifestPath.

    .NOTES
        - Requires dotnet CLI in PATH
        - Local tool manifest discovery walks from -Path up to the filesystem root
        - Auto scope uses global tools only when no local .config/dotnet-tools.json manifest is found
        - Outdated checks use 'dotnet tool search' and fall back to NuGet flat-container metadata
        - Respects -WhatIf and -Confirm through SupportsShouldProcess

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Update-DotNetTool.ps1

    .LINK
        https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-tool-update

    .LINK
        https://learn.microsoft.com/en-us/dotnet/core/tools/local-tools-how-to-use

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Update-DotNetTool.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$Path = (Get-Location).Path,

        [Parameter()]
        [ValidateSet('Auto', 'Local', 'Global')]
        [String]$Scope = 'Auto',

        [Parameter()]
        [Switch]$ListOutdated,

        [Parameter()]
        [Switch]$Prerelease,

        [Parameter()]
        [Switch]$Interactive,

        [Parameter()]
        [Switch]$IgnoreFailedSources,

        [Parameter()]
        [Switch]$NoHttpCache,

        [Parameter()]
        [Switch]$DisableParallel,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$Framework,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$AdditionalArgs
    )

    begin
    {
        Write-Verbose 'Starting .NET tool update'

        $dotnetCommand = Get-Command -Name 'dotnet' -ErrorAction SilentlyContinue
        if (-not $dotnetCommand)
        {
            throw 'dotnet CLI is not installed or not available in PATH. Install the .NET SDK and try again.'
        }

        Write-Verbose "dotnet found at: $($dotnetCommand.Source)"

        function Find-DotNetToolManifest
        {
            param(
                [Parameter(Mandatory)]
                [String]$StartPath
            )

            $directory = [System.IO.DirectoryInfo]::new($StartPath)
            while ($directory)
            {
                $configPath = Join-Path -Path $directory.FullName -ChildPath '.config'
                $manifestPath = Join-Path -Path $configPath -ChildPath 'dotnet-tools.json'

                if (Test-Path -LiteralPath $manifestPath -PathType Leaf)
                {
                    return $manifestPath
                }

                $directory = $directory.Parent
            }

            return $null
        }

        function ConvertFrom-DotNetToolJson
        {
            param(
                [Parameter(Mandatory)]
                [String[]]$Output
            )

            $jsonText = ($Output | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join "`n"
            if ([string]::IsNullOrWhiteSpace($jsonText))
            {
                return @()
            }

            $parsed = $jsonText | ConvertFrom-Json
            if (-not $parsed.PSObject.Properties.Name.Contains('data') -or -not $parsed.data)
            {
                return @()
            }

            $tools = @()
            foreach ($tool in @($parsed.data))
            {
                if (-not [string]::IsNullOrWhiteSpace($tool.packageId))
                {
                    $tools += [PSCustomObject]@{
                        PackageId = [String]$tool.packageId
                        Version = [String]$tool.version
                    }
                }
            }

            return $tools
        }

        function ConvertFrom-DotNetToolTable
        {
            param(
                [Parameter(Mandatory)]
                [String[]]$Output
            )

            $tools = @()
            foreach ($line in $Output)
            {
                $trimmedLine = "$line".Trim()
                if ([string]::IsNullOrWhiteSpace($trimmedLine))
                {
                    continue
                }

                if ($trimmedLine -match '^(Package Id|[-]+)')
                {
                    continue
                }

                $columns = $trimmedLine -split '\s{2,}'
                if ($columns.Count -lt 2 -or [string]::IsNullOrWhiteSpace($columns[0]))
                {
                    continue
                }

                $tools += [PSCustomObject]@{
                    PackageId = [String]$columns[0]
                    Version = [String]$columns[1]
                }
            }

            return $tools
        }

        function ConvertFrom-DotNetToolSearchTable
        {
            param(
                [Parameter(Mandatory)]
                [String[]]$Output
            )

            $tools = @()
            foreach ($line in $Output)
            {
                $trimmedLine = "$line".Trim()
                if ([string]::IsNullOrWhiteSpace($trimmedLine))
                {
                    continue
                }

                if ($trimmedLine -match '^(Package ID|[-]+)')
                {
                    continue
                }

                $columns = $trimmedLine -split '\s{2,}'
                if ($columns.Count -lt 2 -or [string]::IsNullOrWhiteSpace($columns[0]))
                {
                    continue
                }

                $tools += [PSCustomObject]@{
                    PackageId = [String]$columns[0]
                    LatestVersion = [String]$columns[1]
                }
            }

            return $tools
        }

        function Get-DotNetToolList
        {
            param(
                [Parameter(Mandatory)]
                [String]$DotNetCommandName,

                [Parameter(Mandatory)]
                [ValidateSet('Local', 'Global')]
                [String]$Scope
            )

            if ($Scope -eq 'Local')
            {
                $scopeArgument = '--local'
            }
            else
            {
                $scopeArgument = '--global'
            }

            $listArgs = @('tool', 'list', $scopeArgument, '--format', 'json')
            Write-Verbose "Listing .NET $($Scope.ToLowerInvariant()) tools: dotnet $($listArgs -join ' ')"

            $listOutput = @(& $DotNetCommandName @listArgs 2>&1)
            $listExitCode = $LASTEXITCODE

            if ($listExitCode -eq 0)
            {
                try
                {
                    return @(ConvertFrom-DotNetToolJson -Output $listOutput)
                }
                catch
                {
                    Write-Verbose "Unable to parse JSON tool list output, falling back to table output: $($_.Exception.Message)"
                }
            }
            else
            {
                Write-Verbose "JSON tool list failed with exit code $listExitCode, falling back to table output."
            }

            $fallbackListArgs = @('tool', 'list', $scopeArgument)
            Write-Verbose "Listing .NET $($Scope.ToLowerInvariant()) tools: dotnet $($fallbackListArgs -join ' ')"

            $fallbackOutput = @(& $DotNetCommandName @fallbackListArgs 2>&1)
            $fallbackExitCode = $LASTEXITCODE
            if ($fallbackExitCode -ne 0)
            {
                $message = ($fallbackOutput | Where-Object { $_ }) -join ' '
                throw "Failed to list .NET $($Scope.ToLowerInvariant()) tools: $message"
            }

            return @(ConvertFrom-DotNetToolTable -Output $fallbackOutput)
        }

        function Get-DotNetToolLatestVersion
        {
            param(
                [Parameter(Mandatory)]
                [String]$DotNetCommandName,

                [Parameter(Mandatory)]
                [String]$PackageId,

                [Parameter()]
                [Switch]$IncludePrerelease
            )

            $searchFailureMessage = $null
            $searchArgs = @('tool', 'search', $PackageId, '--take', '20')
            if ($IncludePrerelease.IsPresent)
            {
                $searchArgs += '--prerelease'
            }

            Write-Verbose "Searching latest .NET tool version: dotnet $($searchArgs -join ' ')"

            $searchOutput = @(& $DotNetCommandName @searchArgs 2>&1)
            $searchExitCode = $LASTEXITCODE
            if ($searchExitCode -ne 0)
            {
                $searchFailureMessage = ($searchOutput | Where-Object { $_ }) -join ' '
                Write-Verbose "dotnet tool search failed for '$PackageId': $searchFailureMessage"
            }
            else
            {
                $searchResults = @(ConvertFrom-DotNetToolSearchTable -Output $searchOutput)
                $exactMatch = $searchResults |
                    Where-Object { [String]::Equals($_.PackageId, $PackageId, [StringComparison]::OrdinalIgnoreCase) } |
                    Select-Object -First 1

                if ($exactMatch)
                {
                    return [String]$exactMatch.LatestVersion
                }

                Write-Verbose "No exact latest-version search result found for .NET tool '$PackageId'."
            }

            $packageIdForUrl = $PackageId.ToLowerInvariant()
            $packageIndexUri = 'https://api.nuget.org/v3-flatcontainer/{0}/index.json' -f ([System.Uri]::EscapeDataString($packageIdForUrl))
            $fallbackFailureMessage = $null

            try
            {
                Write-Verbose "Searching NuGet flat-container latest .NET tool version: $packageIndexUri"
                $packageIndex = Invoke-RestMethod -Uri $packageIndexUri -ErrorAction Stop
                $versions = @($packageIndex.versions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

                if (-not $IncludePrerelease.IsPresent)
                {
                    $versions = @($versions | Where-Object { $_ -notmatch '-' })
                }

                if ($versions.Count -gt 0)
                {
                    return [String]$versions[-1]
                }

                Write-Verbose "NuGet flat-container metadata did not include usable versions for .NET tool '$PackageId'."
                $fallbackFailureMessage = 'No usable versions were returned.'
            }
            catch
            {
                $fallbackFailureMessage = $_.Exception.Message
            }

            if ($searchFailureMessage)
            {
                Write-Warning "Failed to determine latest version for .NET tool '$PackageId'. dotnet tool search failed: $searchFailureMessage. NuGet metadata fallback failed: $fallbackFailureMessage"
            }
            else
            {
                Write-Warning "Failed to determine latest version for .NET tool '$PackageId'. NuGet metadata fallback failed: $fallbackFailureMessage"
            }

            return $null
        }

        function Format-DotNetToolUpdateResult
        {
            param(
                [Parameter(Mandatory)]
                [String]$PackageId,

                [String]$Version,

                [Parameter(Mandatory)]
                [String]$Status,

                [String]$Message
            )

            [PSCustomObject]@{
                PackageId = $PackageId
                Version = $Version
                Status = $Status
                Message = $Message
            }
        }

        function Format-DotNetToolOutdatedResult
        {
            param(
                [Parameter(Mandatory)]
                [String]$Scope,

                [Parameter(Mandatory)]
                [String]$PackageId,

                [Parameter(Mandatory)]
                [String]$CurrentVersion,

                [Parameter(Mandatory)]
                [String]$LatestVersion,

                [Parameter(Mandatory)]
                [String]$WorkingDirectory,

                [String]$ManifestPath
            )

            [PSCustomObject]@{
                Scope = $Scope
                PackageId = $PackageId
                CurrentVersion = $CurrentVersion
                LatestVersion = $LatestVersion
                WorkingDirectory = $WorkingDirectory
                ManifestPath = $ManifestPath
            }
        }
    }

    process
    {
        try
        {
            $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        }
        catch
        {
            Write-Error "Unable to resolve path '$Path': $($_.Exception.Message)"
            return
        }

        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container))
        {
            Write-Error "Path not found or is not a directory: $resolvedPath"
            return
        }

        $manifestPath = Find-DotNetToolManifest -StartPath $resolvedPath
        if ($Scope -eq 'Auto')
        {
            if ($manifestPath)
            {
                $effectiveScope = 'Local'
                Write-Verbose "Found local .NET tool manifest: $manifestPath"
            }
            else
            {
                $effectiveScope = 'Global'
                Write-Verbose 'No local .NET tool manifest found; using global tool scope.'
            }
        }
        elseif ($Scope -eq 'Local')
        {
            if (-not $manifestPath)
            {
                Write-Error "No local .NET tool manifest found from '$resolvedPath' or its parent directories."
                return
            }

            $effectiveScope = 'Local'
            Write-Verbose "Using requested local .NET tool scope with manifest: $manifestPath"
        }
        else
        {
            $effectiveScope = 'Global'
            $manifestPath = $null
            Write-Verbose 'Using requested global .NET tool scope.'
        }

        Push-Location -LiteralPath $resolvedPath
        try
        {
            $tools = @(Get-DotNetToolList -DotNetCommandName $dotnetCommand.Name -Scope $effectiveScope)
        }
        finally
        {
            Pop-Location
        }

        $updatedCount = 0
        $skippedCount = 0
        $failedCount = 0
        $results = @()

        if ($tools.Count -eq 0)
        {
            Write-Verbose "No .NET $($effectiveScope.ToLowerInvariant()) tools found."

            if ($ListOutdated.IsPresent)
            {
                return
            }

            return [PSCustomObject]@{
                Scope = $effectiveScope
                WorkingDirectory = $resolvedPath
                ManifestPath = $manifestPath
                ToolsFound = 0
                Updated = 0
                Skipped = 0
                Failed = 0
                ExitCode = 0
                Results = @()
            }
        }

        if ($ListOutdated.IsPresent)
        {
            $outdatedTools = @()
            foreach ($tool in $tools)
            {
                $packageId = [String]$tool.PackageId
                $currentVersion = [String]$tool.Version
                $latestVersion = Get-DotNetToolLatestVersion -DotNetCommandName $dotnetCommand.Name -PackageId $packageId -IncludePrerelease:$Prerelease

                if ([string]::IsNullOrWhiteSpace($latestVersion))
                {
                    continue
                }

                if (-not [String]::Equals($currentVersion, $latestVersion, [StringComparison]::OrdinalIgnoreCase))
                {
                    $outdatedTools += Format-DotNetToolOutdatedResult `
                        -Scope $effectiveScope `
                        -PackageId $packageId `
                        -CurrentVersion $currentVersion `
                        -LatestVersion $latestVersion `
                        -WorkingDirectory $resolvedPath `
                        -ManifestPath $manifestPath
                }
            }

            return $outdatedTools
        }

        foreach ($tool in $tools)
        {
            $packageId = [String]$tool.PackageId
            $version = [String]$tool.Version

            $updateArgs = @('tool', 'update', $packageId)
            if ($effectiveScope -eq 'Local')
            {
                $updateArgs += '--local'
                $updateArgs += '--tool-manifest'
                $updateArgs += $manifestPath
            }
            else
            {
                $updateArgs += '--global'
            }

            if ($Prerelease.IsPresent)
            {
                $updateArgs += '--prerelease'
            }
            if ($Interactive.IsPresent)
            {
                $updateArgs += '--interactive'
            }
            if ($IgnoreFailedSources.IsPresent)
            {
                $updateArgs += '--ignore-failed-sources'
            }
            if ($NoHttpCache.IsPresent)
            {
                $updateArgs += '--no-http-cache'
            }
            if ($DisableParallel.IsPresent)
            {
                $updateArgs += '--disable-parallel'
            }
            if ($Framework)
            {
                $updateArgs += '--framework'
                $updateArgs += $Framework
            }
            if ($AdditionalArgs)
            {
                $updateArgs += $AdditionalArgs
            }

            $target = "$effectiveScope .NET tool '$packageId'"
            if (-not $PSCmdlet.ShouldProcess($target, 'Update'))
            {
                $skippedCount++
                $results += Format-DotNetToolUpdateResult -PackageId $packageId -Version $version -Status 'Skipped' -Message 'Skipped by ShouldProcess'
                continue
            }

            Write-Verbose "Updating .NET $($effectiveScope.ToLowerInvariant()) tool '$packageId': dotnet $($updateArgs -join ' ')"

            Push-Location -LiteralPath $resolvedPath
            try
            {
                $updateOutput = @(& $dotnetCommand.Name @updateArgs 2>&1)
                $updateExitCode = $LASTEXITCODE
            }
            finally
            {
                Pop-Location
            }

            $message = ($updateOutput | Where-Object { $_ }) -join "`n"
            if ($updateExitCode -eq 0)
            {
                $updatedCount++
                $results += Format-DotNetToolUpdateResult -PackageId $packageId -Version $version -Status 'Success' -Message $message
            }
            else
            {
                $failedCount++
                $results += Format-DotNetToolUpdateResult -PackageId $packageId -Version $version -Status 'Failed' -Message $message
                Write-Warning "Failed to update .NET $($effectiveScope.ToLowerInvariant()) tool '$packageId': $message"
            }
        }

        $exitCode = if ($failedCount -gt 0) { 1 } else { 0 }
        [PSCustomObject]@{
            Scope = $effectiveScope
            WorkingDirectory = $resolvedPath
            ManifestPath = $manifestPath
            ToolsFound = $tools.Count
            Updated = $updatedCount
            Skipped = $skippedCount
            Failed = $failedCount
            ExitCode = $exitCode
            Results = $results
        }
    }
}
