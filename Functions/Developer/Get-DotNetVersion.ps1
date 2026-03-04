function Get-DotNetVersion
{
    <#
    .SYNOPSIS
        Gets installed .NET Framework and .NET (formerly .NET Core) versions from local or remote computers.

    .DESCRIPTION
        Retrieves comprehensive information about installed .NET versions including both .NET Framework
        and .NET versions. By default, shows results for both runtime types, indicating when
        a particular type is not installed. Use -FrameworkOnly or -DotNetOnly to filter results to specific
        runtime types. Supports both local and remote computer queries.

        Detects .NET Framework versions from 1.0 through 4.8.1, including .NET Framework 4.0 Client
        and Full profiles. Also detects .NET (Core) versions and associated runtimes.
        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER ComputerName
        Target computers to retrieve .NET versions from. Accepts an array of computer names or IP addresses.
        If not specified, 'localhost' is used as the default.
        Supports pipeline input by property name for object-based input.

    .PARAMETER All
        Show all installed versions of .NET Framework and .NET, including SDK versions.
        If not specified, only the latest version of each type is returned.

    .PARAMETER Credential
        Specifies credentials for remote computer access. Required for remote computers that need authentication.

    .PARAMETER IncludeSDKs
        Include .NET SDK versions in addition to runtime versions for .NET.
        Not applicable when -FrameworkOnly is specified since .NET Framework does not have separate SDK releases.

    .PARAMETER FrameworkOnly
        Show only .NET Framework versions. Cannot be used with -DotNetOnly parameter.

    .PARAMETER DotNetOnly
        Show only .NET versions. Cannot be used with -FrameworkOnly parameter.

    .EXAMPLE
        PS > Get-DotNetVersion

        ComputerName : localhost
        RuntimeType  : .NET Framework
        Version      : Not installed
        Release      :
        InstallPath  :
        IsLatest     :
        Type         : Runtime

        ComputerName : localhost
        RuntimeType  : ASP.NET Core
        Version      : 9.0.10
        Release      :
        InstallPath  : /usr/local/share/dotnet/shared/Microsoft.AspNetCore.App
        IsLatest     : True
        Type         : Runtime

        ComputerName : localhost
        RuntimeType  : .NET
        Version      : 9.0.10
        Release      :
        InstallPath  : /usr/local/share/dotnet/shared/Microsoft.NETCore.App
        IsLatest     : True
        Type         : Runtime

        Gets the latest .NET Framework and .NET versions from the local computer.

    .EXAMPLE
        PS > Get-DotNetVersion -All

        Gets all installed .NET Framework and .NET versions (including SDKs) from the local computer.

    .EXAMPLE
        PS > Get-DotNetVersion -ComputerName 'server01' -Credential (Get-Credential)

        Gets .NET versions from a remote computer using specified credentials.

    .EXAMPLE
        PS > 'server01','server02' | Get-DotNetVersion -All

        Gets all .NET versions from multiple computers using pipeline input.

    .EXAMPLE
        PS > Get-DotNetVersion -ComputerName 'devmachine' -All

        Gets all .NET versions including SDK versions from a remote development machine.
        (Note: -IncludeSDKs is implied by -All and can be omitted.)

    .EXAMPLE
        PS > Get-DotNetVersion -FrameworkOnly

        Gets only .NET Framework versions from the local computer.

    .EXAMPLE
        PS > Get-DotNetVersion -DotNetOnly -All

        Gets all .NET versions from the local computer.

    .EXAMPLE
        PS > Get-DotNetVersion -DotNetOnly -IncludeSDKs

        Gets the latest .NET version and all SDK versions from the local computer.

    .EXAMPLE
        PS > Get-DotNetVersion -ComputerName 'server01' -FrameworkOnly -All

        Gets all .NET Framework versions from a remote server.

    .OUTPUTS
        System.Object[]
        Returns custom objects with ComputerName, RuntimeType, Version, Release, InstallPath, and IsLatest properties.

    .NOTES
        .NET Framework detection uses Windows Registry (Windows only)
        .NET detection uses dotnet CLI when available, falls back to directory scanning

        - Remote execution uses PowerShell remoting (WinRM) and requires appropriate permissions
        - By default returns results for both .NET Framework and .NET, indicating "Not installed" when absent
        - Use -FrameworkOnly or -DotNetOnly to filter results to specific runtime types
        - The -IncludeSDKs parameter can be used with -DotNetOnly or the default parameter set, but not with -FrameworkOnly

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Get-DotNetVersion.ps1

    .LINK
        https://docs.microsoft.com/en-us/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed

    .LINK
        https://learn.microsoft.com/en-us/dotnet/core/install/how-to-detect-installed-versions

    .LINK
        https://jonlabelle.com/snippets/view/powershell/get-installed-net-versions-in-powershell

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Get-DotNetVersion.ps1
    #>
    [CmdletBinding(DefaultParameterSetName = 'All', ConfirmImpact = 'Low')]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = 'Target computers to query')]
        [Alias('Cn', 'PSComputerName', 'Server', 'Target')]
        [String[]]$ComputerName,

        [Parameter(HelpMessage = 'Show all installed versions instead of just the latest')]
        [Switch]$All,

        [Parameter(HelpMessage = 'Credentials for remote computer access')]
        [PSCredential]$Credential,

        [Parameter(ParameterSetName = 'All', HelpMessage = 'Include .NET SDK versions in addition to runtime versions')]
        [Parameter(ParameterSetName = 'DotNetOnly', HelpMessage = 'Include .NET SDK versions in addition to runtime versions')]
        [Switch]$IncludeSDKs,

        [Parameter(ParameterSetName = 'FrameworkOnly', HelpMessage = 'Show only .NET Framework versions')]
        [Switch]$FrameworkOnly,

        [Parameter(ParameterSetName = 'DotNetOnly', HelpMessage = 'Show only .NET versions')]
        [Switch]$DotNetOnly
    )

    begin
    {
        $results = [System.Collections.Generic.List[object]]::new()

        # Although parameter sets should prevent this, add an extra validation check
        if ($FrameworkOnly -and $IncludeSDKs)
        {
            Write-Warning 'The -IncludeSDKs parameter is not applicable with -FrameworkOnly since .NET Framework does not have separate SDK releases.'
        }

        # .NET Framework version mapping (Windows only)
        $FrameworkVersionTable = @{
            378389 = '4.5'
            378675 = '4.5.1'
            378758 = '4.5.1'
            379893 = '4.5.2'
            393295 = '4.6'
            393297 = '4.6'
            394254 = '4.6.1'
            394271 = '4.6.1'
            394802 = '4.6.2'
            394806 = '4.6.2'
            460798 = '4.7'
            460805 = '4.7'
            461308 = '4.7.1'
            461310 = '4.7.1'
            461808 = '4.7.2'
            461814 = '4.7.2'
            528040 = '4.8'
            528049 = '4.8'
            528372 = '4.8'
            528449 = '4.8'
            533320 = '4.8.1'
            533325 = '4.8.1'
        }

        $localComputerNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($localName in @('localhost', '.', '127.0.0.1', '::1', $env:COMPUTERNAME, $env:HOSTNAME))
        {
            if (-not [string]::IsNullOrWhiteSpace($localName))
            {
                [void]$localComputerNames.Add($localName.Trim())
            }
        }

        try
        {
            $dnsHostName = [System.Net.Dns]::GetHostName()
            if (-not [string]::IsNullOrWhiteSpace($dnsHostName))
            {
                [void]$localComputerNames.Add($dnsHostName.Trim())
            }
        }
        catch
        {
            Write-Verbose "Unable to resolve local DNS hostname: $($_.Exception.Message)"
        }

        function Test-IsLocalTarget
        {
            param(
                [string]$Computer,
                [System.Collections.Generic.HashSet[string]]$KnownLocalNames
            )

            if ([string]::IsNullOrWhiteSpace($Computer))
            {
                return $false
            }

            $trimmedComputer = $Computer.Trim()
            if ($KnownLocalNames.Contains($trimmedComputer))
            {
                return $true
            }

            if ($trimmedComputer -match '^127(\.\d{1,3}){3}$')
            {
                return $true
            }

            try
            {
                $address = [System.Net.IPAddress]::Parse($trimmedComputer)
                return $address.Equals([System.Net.IPAddress]::Loopback) -or $address.Equals([System.Net.IPAddress]::IPv6Loopback)
            }
            catch
            {
                return $false
            }
        }
        $collectDotNetVersions = {
            param(
                [string]$TargetComputer,
                [bool]$ReturnAll,
                [bool]$DetectSDKs,
                [hashtable]$ReleaseTable,
                [bool]$OnlyFramework,
                [bool]$OnlyDotNet
            )

            $computerResults = [System.Collections.Generic.List[object]]::new()

            function ConvertTo-DotNetVersionResult
            {
                param(
                    [string]$ComputerName,
                    [string]$RuntimeType,
                    [string]$Version,
                    $Release,
                    [string]$InstallPath,
                    $IsLatest,
                    [string]$Type
                )

                return [PSCustomObject]@{
                    PSTypeName = 'DotNetVersion.Result'
                    ComputerName = $ComputerName
                    RuntimeType = $RuntimeType
                    Version = $Version
                    Release = $Release
                    InstallPath = $InstallPath
                    IsLatest = $IsLatest
                    Type = $Type
                }
            }

            function Write-DotNetVersionResultEntry
            {
                param(
                    [System.Collections.Generic.List[object]]$Collection,
                    [string]$ComputerName,
                    [string]$RuntimeType,
                    [string]$Version,
                    $Release,
                    [string]$InstallPath,
                    $IsLatest,
                    [string]$Type
                )

                [void]$Collection.Add((ConvertTo-DotNetVersionResult -ComputerName $ComputerName -RuntimeType $RuntimeType -Version $Version -Release $Release -InstallPath $InstallPath -IsLatest $IsLatest -Type $Type))
            }

            function Add-CoreVersionEntry
            {
                param(
                    [System.Collections.Generic.List[object]]$Collection,
                    [hashtable]$SeenEntries,
                    [string]$EntryType,
                    [string]$Runtime,
                    [string]$Version,
                    [string]$InstallPath
                )

                if ([string]::IsNullOrWhiteSpace($Runtime) -or [string]::IsNullOrWhiteSpace($Version))
                {
                    return
                }

                $key = "$EntryType|$Runtime|$Version|$InstallPath"
                if (-not $SeenEntries.ContainsKey($key))
                {
                    $SeenEntries[$key] = $true
                    [void]$Collection.Add([PSCustomObject]@{
                            Type = $EntryType
                            Runtime = $Runtime
                            Version = $Version
                            InstallPath = $InstallPath
                        })
                }
            }

            Write-Verbose "Processing .NET versions for $TargetComputer"

            # Get .NET Framework versions (Windows only) - Skip if DotNetOnly
            if (-not $OnlyDotNet)
            {
                $frameworkVersions = [System.Collections.Generic.List[object]]::new()

                if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop')
                {
                    $ndpKey = $null
                    try
                    {
                        $ndpKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\NET Framework Setup\NDP')

                        if ($ndpKey)
                        {
                            # Get legacy versions (1.x - 3.x)
                            foreach ($versionKeyName in $ndpKey.GetSubKeyNames())
                            {
                                if ($versionKeyName -notmatch '^v[1-3]\.')
                                {
                                    continue
                                }

                                $versionKey = $ndpKey.OpenSubKey($versionKeyName)
                                if (-not $versionKey)
                                {
                                    continue
                                }

                                try
                                {
                                    if ($versionKey.GetValue('Install') -eq 1)
                                    {
                                        [void]$frameworkVersions.Add([PSCustomObject]@{
                                                Version = $versionKey.GetValue('Version', $versionKeyName -replace '^v')
                                                Release = $null
                                                InstallPath = $versionKey.GetValue('InstallPath', '')
                                            })
                                    }
                                }
                                finally
                                {
                                    $versionKey.Close()
                                }
                            }
                            # Check for .NET Framework 4.0 (Client and Full profiles)
                            $v4ClientKey = $ndpKey.OpenSubKey('v4\Client')
                            if ($v4ClientKey)
                            {
                                try
                                {
                                    if ($v4ClientKey.GetValue('Install') -eq 1)
                                    {
                                        [void]$frameworkVersions.Add([PSCustomObject]@{
                                                Version = "$($v4ClientKey.GetValue('Version', '4.0')) (Client Profile)"
                                                Release = $null
                                                InstallPath = $v4ClientKey.GetValue('InstallPath', '')
                                            })
                                    }
                                }
                                finally
                                {
                                    $v4ClientKey.Close()
                                }
                            }

                            $v4FullKey = $ndpKey.OpenSubKey('v4\Full')
                            if ($v4FullKey)
                            {
                                try
                                {
                                    $release = [int]$v4FullKey.GetValue('Release', 0)
                                    $install = $v4FullKey.GetValue('Install')
                                    $version = $v4FullKey.GetValue('Version', '4.0')
                                    $installPath = $v4FullKey.GetValue('InstallPath', '')

                                    if ($release -eq 0 -and $install -eq 1)
                                    {
                                        [void]$frameworkVersions.Add([PSCustomObject]@{
                                                Version = $version
                                                Release = $null
                                                InstallPath = $installPath
                                            })
                                    }
                                    elseif ($release -gt 0)
                                    {
                                        $mappedVersion = $ReleaseTable[$release]
                                        if (-not $mappedVersion)
                                        {
                                            $knownReleases = $ReleaseTable.Keys | Sort-Object -Descending
                                            $matchedRelease = $knownReleases | Where-Object { $_ -le $release } | Select-Object -First 1
                                            if ($matchedRelease)
                                            {
                                                $mappedVersion = "$($ReleaseTable[$matchedRelease])+"
                                            }
                                            else
                                            {
                                                $mappedVersion = '4.5+'
                                            }
                                        }

                                        [void]$frameworkVersions.Add([PSCustomObject]@{
                                                Version = $mappedVersion
                                                Release = $release
                                                InstallPath = $installPath
                                            })
                                    }
                                }
                                finally
                                {
                                    $v4FullKey.Close()
                                }
                            }
                        }
                    }
                    catch
                    {
                        Write-Verbose "Error accessing .NET Framework registry: $($_.Exception.Message)"
                    }
                    finally
                    {
                        if ($ndpKey)
                        {
                            $ndpKey.Close()
                        }
                    }
                }

                # Process Framework results
                if ($frameworkVersions.Count -gt 0)
                {
                    $latestFramework = $frameworkVersions | Sort-Object `
                    @{ Expression = {
                            $normalizedVersion = $_.Version -replace '[^\d\.]', ''
                            try { [version]$normalizedVersion } catch { [version]'0.0.0.0' }
                        }; Descending = $true
                    }, `
                    @{ Expression = { if ($null -eq $_.Release) { -1 } else { [int]$_.Release } }; Descending = $true } |
                    Select-Object -First 1

                    if ($ReturnAll)
                    {
                        foreach ($frameworkVersion in $frameworkVersions)
                        {
                            Write-DotNetVersionResultEntry -Collection $computerResults `
                                -ComputerName $TargetComputer `
                                -RuntimeType '.NET Framework' `
                                -Version $frameworkVersion.Version `
                                -Release $frameworkVersion.Release `
                                -InstallPath $frameworkVersion.InstallPath `
                                -IsLatest ($frameworkVersion.Version -eq $latestFramework.Version -and $frameworkVersion.Release -eq $latestFramework.Release) `
                                -Type 'Runtime'
                        }
                    }
                    else
                    {
                        Write-DotNetVersionResultEntry -Collection $computerResults `
                            -ComputerName $TargetComputer `
                            -RuntimeType '.NET Framework' `
                            -Version $latestFramework.Version `
                            -Release $latestFramework.Release `
                            -InstallPath $latestFramework.InstallPath `
                            -IsLatest $true `
                            -Type 'Runtime'
                    }
                }
                else
                {
                    Write-DotNetVersionResultEntry -Collection $computerResults `
                        -ComputerName $TargetComputer `
                        -RuntimeType '.NET Framework' `
                        -Version 'Not installed' `
                        -Release $null `
                        -InstallPath $null `
                        -IsLatest $null `
                        -Type 'Runtime'
                }
            }

            # Get .NET versions - Skip if FrameworkOnly
            if (-not $OnlyFramework)
            {
                $coreVersions = [System.Collections.Generic.List[object]]::new()
                $coreVersionIndex = @{}

                # Try using dotnet CLI first
                try
                {
                    $dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
                    if ($dotnetCommand)
                    {
                        $runtimeOutput = & $dotnetCommand.Source --list-runtimes 2>$null
                        if ($LASTEXITCODE -eq 0 -and $runtimeOutput)
                        {
                            foreach ($line in $runtimeOutput)
                            {
                                if ($line -match '^(Microsoft\.NETCore\.App|Microsoft\.AspNetCore\.App|Microsoft\.WindowsDesktop\.App)\s+(\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z\.-]*)?)\s+\[(.+)\]')
                                {
                                    Add-CoreVersionEntry -Collection $coreVersions -SeenEntries $coreVersionIndex -EntryType 'Runtime' -Runtime $matches[1] -Version $matches[2] -InstallPath $matches[3]
                                }
                            }
                        }

                        if ($DetectSDKs)
                        {
                            $sdkOutput = & $dotnetCommand.Source --list-sdks 2>$null
                            if ($LASTEXITCODE -eq 0 -and $sdkOutput)
                            {
                                foreach ($line in $sdkOutput)
                                {
                                    if ($line -match '^(\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z\.-]*)?)\s+\[(.+)\]')
                                    {
                                        Add-CoreVersionEntry -Collection $coreVersions -SeenEntries $coreVersionIndex -EntryType 'SDK' -Runtime 'Microsoft.NETCore.SDK' -Version $matches[1] -InstallPath $matches[2]
                                    }
                                }
                            }
                        }
                    }

                    $runtimeEntryCount = ($coreVersions | Where-Object { $_.Type -eq 'Runtime' } | Measure-Object).Count
                    $sdkEntryCount = ($coreVersions | Where-Object { $_.Type -eq 'SDK' } | Measure-Object).Count
                    $needRuntimeFallback = (-not $dotnetCommand -or $runtimeEntryCount -eq 0)
                    $needSdkFallback = ($DetectSDKs -and (-not $dotnetCommand -or $sdkEntryCount -eq 0))

                    # If CLI data is incomplete, use directory scanning to fill gaps.
                    if ($needRuntimeFallback -or $needSdkFallback)
                    {
                        $dotnetRoots = [System.Collections.Generic.List[string]]::new()

                        if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop')
                        {
                            if ($env:ProgramFiles)
                            {
                                [void]$dotnetRoots.Add((Join-Path -Path $env:ProgramFiles -ChildPath 'dotnet'))
                            }
                            if (${env:ProgramFiles(x86)})
                            {
                                [void]$dotnetRoots.Add((Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'dotnet'))
                            }
                        }
                        else
                        {
                            [void]$dotnetRoots.Add('/usr/share/dotnet')
                            [void]$dotnetRoots.Add('/usr/local/share/dotnet')
                        }

                        if ($env:DOTNET_ROOT)
                        {
                            [void]$dotnetRoots.Add($env:DOTNET_ROOT)
                        }
                        if (${env:DOTNET_ROOT(x86)})
                        {
                            [void]$dotnetRoots.Add(${env:DOTNET_ROOT(x86)})
                        }

                        $versionPattern = '^\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z\.-]*)?$'
                        foreach ($dotnetRoot in ($dotnetRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique))
                        {
                            if ($needRuntimeFallback)
                            {
                                $sharedPath = Join-Path -Path $dotnetRoot -ChildPath 'shared'
                                foreach ($runtime in @('Microsoft.NETCore.App', 'Microsoft.AspNetCore.App', 'Microsoft.WindowsDesktop.App'))
                                {
                                    $runtimePath = Join-Path -Path $sharedPath -ChildPath $runtime
                                    if (-not (Test-Path -Path $runtimePath))
                                    {
                                        continue
                                    }

                                    $versionDirectories = Get-ChildItem -Path $runtimePath -Directory -ErrorAction SilentlyContinue
                                    foreach ($versionDirectory in $versionDirectories)
                                    {
                                        if ($versionDirectory.Name -match $versionPattern)
                                        {
                                            Add-CoreVersionEntry -Collection $coreVersions -SeenEntries $coreVersionIndex -EntryType 'Runtime' -Runtime $runtime -Version $versionDirectory.Name -InstallPath $versionDirectory.FullName
                                        }
                                    }
                                }
                            }

                            if ($needSdkFallback)
                            {
                                $sdkPath = Join-Path -Path $dotnetRoot -ChildPath 'sdk'
                                if (Test-Path -Path $sdkPath)
                                {
                                    $sdkDirectories = Get-ChildItem -Path $sdkPath -Directory -ErrorAction SilentlyContinue
                                    foreach ($sdkDirectory in $sdkDirectories)
                                    {
                                        if ($sdkDirectory.Name -match $versionPattern)
                                        {
                                            Add-CoreVersionEntry -Collection $coreVersions -SeenEntries $coreVersionIndex -EntryType 'SDK' -Runtime 'Microsoft.NETCore.SDK' -Version $sdkDirectory.Name -InstallPath $sdkDirectory.FullName
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                catch
                {
                    Write-Verbose "Error detecting .NET versions: $($_.Exception.Message)"
                }

                # Process Core results
                if ($coreVersions.Count -gt 0)
                {
                    $runtimeGroups = $coreVersions | Group-Object Runtime
                    foreach ($group in $runtimeGroups)
                    {
                        $runtimeName = switch ($group.Name)
                        {
                            'Microsoft.NETCore.App' { '.NET' }
                            'Microsoft.AspNetCore.App' { 'ASP.NET Core' }
                            'Microsoft.WindowsDesktop.App' { '.NET Desktop' }
                            'Microsoft.NETCore.SDK' { '.NET SDK' }
                            default { $group.Name }
                        }

                        $sortedVersions = $group.Group | Sort-Object `
                        @{ Expression = {
                                try { [version]($_.Version -replace '-.*$', '') } catch { [version]'0.0.0.0' }
                            }; Descending = $true
                        }, `
                        @{ Expression = { -not ($_.Version -match '-') }; Descending = $true }, `
                        @{ Expression = { $_.Version }; Descending = $true }
                        $latestVersion = $sortedVersions | Select-Object -First 1

                        if ($ReturnAll)
                        {
                            foreach ($versionEntry in $sortedVersions)
                            {
                                Write-DotNetVersionResultEntry -Collection $computerResults `
                                    -ComputerName $TargetComputer `
                                    -RuntimeType $runtimeName `
                                    -Version $versionEntry.Version `
                                    -Release $null `
                                    -InstallPath $versionEntry.InstallPath `
                                    -IsLatest ($versionEntry.Version -eq $latestVersion.Version) `
                                    -Type $versionEntry.Type
                            }
                        }
                        else
                        {
                            Write-DotNetVersionResultEntry -Collection $computerResults `
                                -ComputerName $TargetComputer `
                                -RuntimeType $runtimeName `
                                -Version $latestVersion.Version `
                                -Release $null `
                                -InstallPath $latestVersion.InstallPath `
                                -IsLatest $true `
                                -Type $latestVersion.Type
                        }
                    }
                }
                else
                {
                    Write-DotNetVersionResultEntry -Collection $computerResults `
                        -ComputerName $TargetComputer `
                        -RuntimeType '.NET' `
                        -Version 'Not installed' `
                        -Release $null `
                        -InstallPath $null `
                        -IsLatest $null `
                        -Type 'Runtime'
                }
            }

            return $computerResults
        }
    }

    process
    {
        # Handle pipeline input and set default if empty
        $targetComputers = if (-not $ComputerName -or $ComputerName.Count -eq 0) { @('localhost') } else { $ComputerName }

        foreach ($computer in $targetComputers)
        {
            if ([string]::IsNullOrWhiteSpace($computer))
            {
                continue
            }

            $targetComputer = $computer.Trim()
            try
            {
                if (Test-IsLocalTarget -Computer $targetComputer -KnownLocalNames $localComputerNames)
                {
                    Write-Verbose 'Querying local computer for .NET versions'
                    $localResults = & $collectDotNetVersions $targetComputer $All.IsPresent ($All.IsPresent -or $IncludeSDKs.IsPresent) $FrameworkVersionTable $FrameworkOnly.IsPresent $DotNetOnly.IsPresent
                    foreach ($result in $localResults)
                    {
                        [void]$results.Add($result)
                    }
                    continue
                }

                Write-Verbose "Querying remote computer '$targetComputer' for .NET versions"
                $sessionParams = @{
                    ComputerName = $targetComputer
                    ErrorAction = 'Stop'
                }
                if ($Credential)
                {
                    $sessionParams.Credential = $Credential
                }

                $session = $null
                try
                {
                    $session = New-PSSession @sessionParams
                    $remoteResults = Invoke-Command -Session $session -ScriptBlock $collectDotNetVersions -ArgumentList $targetComputer, $All.IsPresent, ($All.IsPresent -or $IncludeSDKs.IsPresent), $FrameworkVersionTable, $FrameworkOnly.IsPresent, $DotNetOnly.IsPresent
                    foreach ($result in $remoteResults)
                    {
                        [void]$results.Add($result)
                    }
                }
                finally
                {
                    if ($session)
                    {
                        Remove-PSSession $session -ErrorAction SilentlyContinue
                    }
                }
            }
            catch
            {
                Write-Warning "Failed to query computer '$targetComputer': $($_.Exception.Message)"

                $runtimeTypes = [System.Collections.Generic.List[string]]::new()
                if (-not $DotNetOnly)
                {
                    [void]$runtimeTypes.Add('.NET Framework')
                }
                if (-not $FrameworkOnly)
                {
                    [void]$runtimeTypes.Add('.NET')
                }

                foreach ($runtimeType in $runtimeTypes)
                {
                    [void]$results.Add([PSCustomObject]@{
                            PSTypeName = 'DotNetVersion.Result'
                            ComputerName = $targetComputer
                            RuntimeType = $runtimeType
                            Version = 'Error'
                            Release = $null
                            InstallPath = $null
                            IsLatest = $null
                            Type = 'Runtime'
                            Error = $_.Exception.Message
                        })
                }
            }
        }
    }

    end
    {
        return $results.ToArray()
    }
}
