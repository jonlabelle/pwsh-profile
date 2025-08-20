function Get-DotNetVersion
{
    <#
    .SYNOPSIS
        Gets installed .NET Framework and .NET Core/.NET versions from local or remote computers.

    .DESCRIPTION
        Retrieves comprehensive information about installed .NET versions including both .NET Framework
        and .NET Core/.NET 5+ versions. Always shows results for both runtime types, indicating when
        a particular type is not installed. Supports both local and remote computer queries.
        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER ComputerName
        Target computers to retrieve .NET versions from. Accepts an array of computer names or IP addresses.
        If not specified, 'localhost' is used as the default.
        Supports pipeline input by property name for object-based input.

    .PARAMETER All
        Show all installed versions of .NET Framework and .NET Core/.NET 5+.
        If not specified, only the latest version of each type is returned.

    .PARAMETER Credential
        Specifies credentials for remote computer access. Required for remote computers that need authentication.

    .PARAMETER Timeout
        Sets a timeout (in milliseconds) for remote operations.
        The default is 30000 (30 seconds). Valid range: 5000-300000.

    .PARAMETER IncludeSDKs
        Include .NET SDK versions in addition to runtime versions for .NET Core/.NET 5+.

    .EXAMPLE
        PS > Get-DotNetVersion

        Gets the latest .NET Framework and .NET Core versions from the local computer.

    .EXAMPLE
        PS > Get-DotNetVersion -All

        Gets all installed .NET Framework and .NET Core versions from the local computer.

    .EXAMPLE
        PS > Get-DotNetVersion -ComputerName 'server01' -Credential (Get-Credential)

        Gets .NET versions from a remote computer using specified credentials.

    .EXAMPLE
        PS > 'server01','server02' | Get-DotNetVersion -All

        Gets all .NET versions from multiple computers using pipeline input.

    .EXAMPLE
        PS > Get-DotNetVersion -ComputerName 'devmachine' -IncludeSDKs -All

        Gets all .NET versions including SDK versions from a remote development machine.

    .OUTPUTS
        System.Object[]
        Returns custom objects with ComputerName, RuntimeType, Version, Release, InstallPath, and IsLatest properties.

    .NOTES
        Name: Get-DotNetVersion.ps1
        Author: Jon LaBelle
        Created: 8/20/2025
        Enhanced cross-platform support for .NET detection

        .NET Framework detection uses Windows Registry (Windows only)
        .NET Core/.NET 5+ detection uses dotnet CLI when available, falls back to directory scanning

    .LINK
        https://docs.microsoft.com/en-us/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed

    .LINK
        https://jonlabelle.com/snippets/view/powershell/get-installed-net-versions-in-powershell

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Get-DotNetVersion.ps1
    #>
    [CmdletBinding(ConfirmImpact = 'Low')]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = 'Target computers to query')]
        [Alias('Cn', 'PSComputerName', 'Server', 'Target')]
        [String[]]$ComputerName,

        [Parameter(HelpMessage = 'Show all installed versions instead of just the latest')]
        [Switch]$All,

        [Parameter(HelpMessage = 'Credentials for remote computer access')]
        [PSCredential]$Credential,

        [Parameter(HelpMessage = 'Timeout for remote operations in milliseconds (5000-300000)')]
        [ValidateRange(5000, 300000)]
        [Int]$Timeout = 30000,

        [Parameter(HelpMessage = 'Include .NET SDK versions in addition to runtime versions')]
        [Switch]$IncludeSDKs
    )

    begin
    {
        # Initialize results collection
        $results = New-Object System.Collections.ArrayList

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
            533320 = '4.8.1'
        }
    }

    process
    {
        # Handle pipeline input and set default if empty
        if (-not $ComputerName -or $ComputerName.Count -eq 0)
        {
            $ComputerName = @('localhost')
        }

        foreach ($computer in $ComputerName)
        {
            # Skip empty/null computer names
            if ([string]::IsNullOrWhiteSpace($computer))
            {
                continue
            }

            try
            {
                if ($computer -eq 'localhost' -or $computer -eq $env:COMPUTERNAME -or $computer -eq '.')
                {
                    # Local computer processing
                    Write-Verbose 'Querying local computer for .NET versions'

                    $computerResults = @()

                    Write-Verbose "Processing .NET versions for $computer"

                    # Get .NET Framework versions (Windows only)
                    $frameworkVersions = @()

                    if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop')
                    {
                        try
                        {
                            $ndpKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\NET Framework Setup\NDP')

                            if ($ndpKey)
                            {
                                # Get legacy versions (1.x - 3.x)
                                foreach ($versionKeyName in $ndpKey.GetSubKeyNames())
                                {
                                    if ($versionKeyName -match '^v[1-3]\.')
                                    {
                                        $versionKey = $ndpKey.OpenSubKey($versionKeyName)
                                        if ($versionKey -and $versionKey.GetValue('Install') -eq 1)
                                        {
                                            $version = $versionKey.GetValue('Version', $versionKeyName -replace '^v')
                                            $frameworkVersions += [PSCustomObject]@{
                                                Version = $version
                                                Release = $null
                                                InstallPath = $versionKey.GetValue('InstallPath', '')
                                            }
                                        }
                                        if ($versionKey) { $versionKey.Close() }
                                    }
                                }

                                # Get .NET Framework 4.x versions
                                $v4Key = $ndpKey.OpenSubKey('v4\Full')
                                if ($v4Key)
                                {
                                    $release = [int]$v4Key.GetValue('Release', 0)
                                    $version = $v4Key.GetValue('Version', '4.0')
                                    $installPath = $v4Key.GetValue('InstallPath', '')

                                    if ($release -gt 0)
                                    {
                                        # Map release number to version
                                        $mappedVersion = $FrameworkVersionTable[$release]
                                        if (-not $mappedVersion)
                                        {
                                            # Find the highest known version that's less than or equal to this release
                                            $knownReleases = $FrameworkVersionTable.Keys | Sort-Object -Descending
                                            $matchedRelease = $knownReleases | Where-Object { $_ -le $release } | Select-Object -First 1
                                            if ($matchedRelease)
                                            {
                                                $mappedVersion = "$($FrameworkVersionTable[$matchedRelease])+"
                                            }
                                            else
                                            {
                                                $mappedVersion = '4.5+'
                                            }
                                        }

                                        $frameworkVersions += [PSCustomObject]@{
                                            Version = $mappedVersion
                                            Release = $release
                                            InstallPath = $installPath
                                        }
                                    }
                                    $v4Key.Close()
                                }
                                $ndpKey.Close()
                            }
                        }
                        catch
                        {
                            Write-Verbose "Error accessing .NET Framework registry: $($_.Exception.Message)"
                        }
                    }

                    # Process Framework results
                    if ($frameworkVersions -and $frameworkVersions.Count -gt 0)
                    {
                        $latestFramework = $frameworkVersions | Sort-Object { [version]($_.Version -replace '[^\d\.]', '') } -Descending | Select-Object -First 1

                        if ($All)
                        {
                            foreach ($fw in $frameworkVersions)
                            {
                                $computerResults += [PSCustomObject]@{
                                    PSTypeName = 'DotNetVersion.Result'
                                    ComputerName = $computer
                                    RuntimeType = '.NET Framework'
                                    Version = $fw.Version
                                    Release = $fw.Release
                                    InstallPath = $fw.InstallPath
                                    IsLatest = ($fw.Version -eq $latestFramework.Version)
                                    Type = 'Runtime'
                                }
                            }
                        }
                        else
                        {
                            $computerResults += [PSCustomObject]@{
                                PSTypeName = 'DotNetVersion.Result'
                                ComputerName = $computer
                                RuntimeType = '.NET Framework'
                                Version = $latestFramework.Version
                                Release = $latestFramework.Release
                                InstallPath = $latestFramework.InstallPath
                                IsLatest = $true
                                Type = 'Runtime'
                            }
                        }
                    }
                    else
                    {
                        # No .NET Framework detected
                        $computerResults += [PSCustomObject]@{
                            PSTypeName = 'DotNetVersion.Result'
                            ComputerName = $computer
                            RuntimeType = '.NET Framework'
                            Version = 'Not installed'
                            Release = $null
                            InstallPath = $null
                            IsLatest = $null
                            Type = 'Runtime'
                        }
                    }

                    # Get .NET Core/.NET 5+ versions
                    $coreVersions = @()

                    # Try using dotnet CLI first
                    try
                    {
                        $dotnetAvailable = $false
                        $null = Get-Command dotnet -ErrorAction SilentlyContinue
                        if ($?)
                        {
                            $dotnetAvailable = $true

                            # Get runtimes
                            $runtimeOutput = & dotnet --list-runtimes 2>$null
                            if ($LASTEXITCODE -eq 0 -and $runtimeOutput)
                            {
                                foreach ($line in $runtimeOutput)
                                {
                                    if ($line -match '^(Microsoft\.NETCore\.App|Microsoft\.AspNetCore\.App|Microsoft\.WindowsDesktop\.App)\s+(\d+\.\d+\.\d+(?:-\w+\.\d+\.\d+)?)\s+\[(.+)\]')
                                    {
                                        $runtime = $matches[1]
                                        $version = $matches[2]
                                        $path = $matches[3]

                                        $coreVersions += [PSCustomObject]@{
                                            Type = 'Runtime'
                                            Runtime = $runtime
                                            Version = $version
                                            InstallPath = $path
                                        }
                                    }
                                }
                            }

                            # Get SDKs if requested
                            if ($IncludeSDKs)
                            {
                                $sdkOutput = & dotnet --list-sdks 2>$null
                                if ($LASTEXITCODE -eq 0 -and $sdkOutput)
                                {
                                    foreach ($line in $sdkOutput)
                                    {
                                        if ($line -match '^(\d+\.\d+\.\d+(?:-\w+\.\d+\.\d+)?)\s+\[(.+)\]')
                                        {
                                            $version = $matches[1]
                                            $path = $matches[2]

                                            $coreVersions += [PSCustomObject]@{
                                                Type = 'SDK'
                                                Runtime = 'Microsoft.NETCore.SDK'
                                                Version = $version
                                                InstallPath = $path
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        # If dotnet CLI is not available, try directory scanning as fallback
                        if (-not $dotnetAvailable)
                        {
                            $commonPaths = @()

                            if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop')
                            {
                                $commonPaths += @(
                                    "${env:ProgramFiles}\dotnet\shared\Microsoft.NETCore.App",
                                    "${env:ProgramFiles}\dotnet\shared\Microsoft.AspNetCore.App",
                                    "${env:ProgramFiles}\dotnet\shared\Microsoft.WindowsDesktop.App"
                                )
                            }
                            elseif ($IsLinux)
                            {
                                $commonPaths += @(
                                    '/usr/share/dotnet/shared/Microsoft.NETCore.App',
                                    '/usr/share/dotnet/shared/Microsoft.AspNetCore.App'
                                )
                            }
                            elseif ($IsMacOS)
                            {
                                $commonPaths += @(
                                    '/usr/local/share/dotnet/shared/Microsoft.NETCore.App',
                                    '/usr/local/share/dotnet/shared/Microsoft.AspNetCore.App'
                                )
                            }

                            foreach ($path in $commonPaths)
                            {
                                if (Test-Path $path)
                                {
                                    $runtime = Split-Path $path -Leaf
                                    $versions = Get-ChildItem $path -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+' }

                                    foreach ($versionDir in $versions)
                                    {
                                        $coreVersions += [PSCustomObject]@{
                                            Type = 'Runtime'
                                            Runtime = $runtime
                                            Version = $versionDir.Name
                                            InstallPath = $versionDir.FullName
                                        }
                                    }
                                }
                            }
                        }
                    }
                    catch
                    {
                        Write-Verbose "Error detecting .NET Core versions: $($_.Exception.Message)"
                    }

                    # Process Core results
                    if ($coreVersions -and $coreVersions.Count -gt 0)
                    {
                        # Group by runtime type
                        $runtimeGroups = $coreVersions | Group-Object Runtime

                        foreach ($group in $runtimeGroups)
                        {
                            $runtimeName = switch ($group.Name)
                            {
                                'Microsoft.NETCore.App' { '.NET Core' }
                                'Microsoft.AspNetCore.App' { 'ASP.NET Core' }
                                'Microsoft.WindowsDesktop.App' { '.NET Desktop' }
                                'Microsoft.NETCore.SDK' { '.NET SDK' }
                                default { $group.Name }
                            }

                            $sortedVersions = $group.Group | Sort-Object { [version]($_.Version -replace '-.*$', '') } -Descending
                            $latestVersion = $sortedVersions | Select-Object -First 1

                            if ($All)
                            {
                                foreach ($version in $sortedVersions)
                                {
                                    $computerResults += [PSCustomObject]@{
                                        PSTypeName = 'DotNetVersion.Result'
                                        ComputerName = $computer
                                        RuntimeType = $runtimeName
                                        Version = $version.Version
                                        Release = $null
                                        InstallPath = $version.InstallPath
                                        IsLatest = ($version.Version -eq $latestVersion.Version)
                                        Type = $version.Type
                                    }
                                }
                            }
                            else
                            {
                                $computerResults += [PSCustomObject]@{
                                    PSTypeName = 'DotNetVersion.Result'
                                    ComputerName = $computer
                                    RuntimeType = $runtimeName
                                    Version = $latestVersion.Version
                                    Release = $null
                                    InstallPath = $latestVersion.InstallPath
                                    IsLatest = $true
                                    Type = $latestVersion.Type
                                }
                            }
                        }
                    }
                    else
                    {
                        # No .NET Core detected
                        $computerResults += [PSCustomObject]@{
                            PSTypeName = 'DotNetVersion.Result'
                            ComputerName = $computer
                            RuntimeType = '.NET Core'
                            Version = 'Not installed'
                            Release = $null
                            InstallPath = $null
                            IsLatest = $null
                            Type = 'Runtime'
                        }
                    }

                    foreach ($result in $computerResults)
                    {
                        [void]$results.Add($result)
                    }
                }
                else
                {
                    # Remote computer processing
                    Write-Verbose "Querying remote computer '$computer' for .NET versions"

                    $sessionParams = @{
                        ComputerName = $computer
                        ErrorAction = 'Stop'
                    }

                    if ($Credential)
                    {
                        $sessionParams.Credential = $Credential
                    }

                    # Create session options with timeout
                    # OperationTimeout expects milliseconds, IdleTimeout expects seconds (minimum 60)
                    $idleTimeoutSeconds = [Math]::Max(60, [Math]::Ceiling($Timeout / 1000))
                    $sessionOption = New-PSSessionOption -OperationTimeout $Timeout -IdleTimeout $idleTimeoutSeconds
                    $sessionParams.SessionOption = $sessionOption

                    $session = $null
                    try
                    {
                        $session = New-PSSession @sessionParams

                        $remoteResults = Invoke-Command -Session $session -ScriptBlock {
                            param($Computer, $All, $IncludeSDKs, $FrameworkVersionTable)

                            $computerResults = @()

                            Write-Verbose "Processing .NET versions for $Computer"

                            # Get .NET Framework versions (Windows only)
                            $frameworkVersions = @()

                            if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop')
                            {
                                try
                                {
                                    $ndpKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\NET Framework Setup\NDP')

                                    if ($ndpKey)
                                    {
                                        # Get legacy versions (1.x - 3.x)
                                        foreach ($versionKeyName in $ndpKey.GetSubKeyNames())
                                        {
                                            if ($versionKeyName -match '^v[1-3]\.')
                                            {
                                                $versionKey = $ndpKey.OpenSubKey($versionKeyName)
                                                if ($versionKey -and $versionKey.GetValue('Install') -eq 1)
                                                {
                                                    $version = $versionKey.GetValue('Version', $versionKeyName -replace '^v')
                                                    $frameworkVersions += [PSCustomObject]@{
                                                        Version = $version
                                                        Release = $null
                                                        InstallPath = $versionKey.GetValue('InstallPath', '')
                                                    }
                                                }
                                                if ($versionKey) { $versionKey.Close() }
                                            }
                                        }

                                        # Get .NET Framework 4.x versions
                                        $v4Key = $ndpKey.OpenSubKey('v4\Full')
                                        if ($v4Key)
                                        {
                                            $release = [int]$v4Key.GetValue('Release', 0)
                                            $version = $v4Key.GetValue('Version', '4.0')
                                            $installPath = $v4Key.GetValue('InstallPath', '')

                                            if ($release -gt 0)
                                            {
                                                # Map release number to version
                                                $mappedVersion = $FrameworkVersionTable[$release]
                                                if (-not $mappedVersion)
                                                {
                                                    # Find the highest known version that's less than or equal to this release
                                                    $knownReleases = $FrameworkVersionTable.Keys | Sort-Object -Descending
                                                    $matchedRelease = $knownReleases | Where-Object { $_ -le $release } | Select-Object -First 1
                                                    if ($matchedRelease)
                                                    {
                                                        $mappedVersion = "$($FrameworkVersionTable[$matchedRelease])+"
                                                    }
                                                    else
                                                    {
                                                        $mappedVersion = '4.5+'
                                                    }
                                                }

                                                $frameworkVersions += [PSCustomObject]@{
                                                    Version = $mappedVersion
                                                    Release = $release
                                                    InstallPath = $installPath
                                                }
                                            }
                                            $v4Key.Close()
                                        }
                                        $ndpKey.Close()
                                    }
                                }
                                catch
                                {
                                    Write-Verbose "Error accessing .NET Framework registry: $($_.Exception.Message)"
                                }
                            }

                            # Process Framework results
                            if ($frameworkVersions -and $frameworkVersions.Count -gt 0)
                            {
                                $latestFramework = $frameworkVersions | Sort-Object { [version]($_.Version -replace '[^\d\.]', '') } -Descending | Select-Object -First 1

                                if ($All)
                                {
                                    foreach ($fw in $frameworkVersions)
                                    {
                                        $computerResults += [PSCustomObject]@{
                                            PSTypeName = 'DotNetVersion.Result'
                                            ComputerName = $Computer
                                            RuntimeType = '.NET Framework'
                                            Version = $fw.Version
                                            Release = $fw.Release
                                            InstallPath = $fw.InstallPath
                                            IsLatest = ($fw.Version -eq $latestFramework.Version)
                                            Type = 'Runtime'
                                        }
                                    }
                                }
                                else
                                {
                                    $computerResults += [PSCustomObject]@{
                                        PSTypeName = 'DotNetVersion.Result'
                                        ComputerName = $Computer
                                        RuntimeType = '.NET Framework'
                                        Version = $latestFramework.Version
                                        Release = $latestFramework.Release
                                        InstallPath = $latestFramework.InstallPath
                                        IsLatest = $true
                                        Type = 'Runtime'
                                    }
                                }
                            }
                            else
                            {
                                # No .NET Framework detected
                                $computerResults += [PSCustomObject]@{
                                    PSTypeName = 'DotNetVersion.Result'
                                    ComputerName = $Computer
                                    RuntimeType = '.NET Framework'
                                    Version = 'Not installed'
                                    Release = $null
                                    InstallPath = $null
                                    IsLatest = $null
                                    Type = 'Runtime'
                                }
                            }

                            # Get .NET Core/.NET 5+ versions
                            $coreVersions = @()

                            # Try using dotnet CLI first
                            try
                            {
                                $dotnetAvailable = $false
                                $null = Get-Command dotnet -ErrorAction SilentlyContinue
                                if ($?)
                                {
                                    $dotnetAvailable = $true

                                    # Get runtimes
                                    $runtimeOutput = & dotnet --list-runtimes 2>$null
                                    if ($LASTEXITCODE -eq 0 -and $runtimeOutput)
                                    {
                                        foreach ($line in $runtimeOutput)
                                        {
                                            if ($line -match '^(Microsoft\.NETCore\.App|Microsoft\.AspNetCore\.App|Microsoft\.WindowsDesktop\.App)\s+(\d+\.\d+\.\d+(?:-\w+\.\d+\.\d+)?)\s+\[(.+)\]')
                                            {
                                                $runtime = $matches[1]
                                                $version = $matches[2]
                                                $path = $matches[3]

                                                $coreVersions += [PSCustomObject]@{
                                                    Type = 'Runtime'
                                                    Runtime = $runtime
                                                    Version = $version
                                                    InstallPath = $path
                                                }
                                            }
                                        }
                                    }

                                    # Get SDKs if requested
                                    if ($IncludeSDKs)
                                    {
                                        $sdkOutput = & dotnet --list-sdks 2>$null
                                        if ($LASTEXITCODE -eq 0 -and $sdkOutput)
                                        {
                                            foreach ($line in $sdkOutput)
                                            {
                                                if ($line -match '^(\d+\.\d+\.\d+(?:-\w+\.\d+\.\d+)?)\s+\[(.+)\]')
                                                {
                                                    $version = $matches[1]
                                                    $path = $matches[2]

                                                    $coreVersions += [PSCustomObject]@{
                                                        Type = 'SDK'
                                                        Runtime = 'Microsoft.NETCore.SDK'
                                                        Version = $version
                                                        InstallPath = $path
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                # If dotnet CLI is not available, try directory scanning as fallback
                                if (-not $dotnetAvailable)
                                {
                                    $commonPaths = @()

                                    if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop')
                                    {
                                        $commonPaths += @(
                                            "${env:ProgramFiles}\dotnet\shared\Microsoft.NETCore.App",
                                            "${env:ProgramFiles}\dotnet\shared\Microsoft.AspNetCore.App",
                                            "${env:ProgramFiles}\dotnet\shared\Microsoft.WindowsDesktop.App"
                                        )
                                    }
                                    elseif ($IsLinux)
                                    {
                                        $commonPaths += @(
                                            '/usr/share/dotnet/shared/Microsoft.NETCore.App',
                                            '/usr/share/dotnet/shared/Microsoft.AspNetCore.App'
                                        )
                                    }
                                    elseif ($IsMacOS)
                                    {
                                        $commonPaths += @(
                                            '/usr/local/share/dotnet/shared/Microsoft.NETCore.App',
                                            '/usr/local/share/dotnet/shared/Microsoft.AspNetCore.App'
                                        )
                                    }

                                    foreach ($path in $commonPaths)
                                    {
                                        if (Test-Path $path)
                                        {
                                            $runtime = Split-Path $path -Leaf
                                            $versions = Get-ChildItem $path -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+' }

                                            foreach ($versionDir in $versions)
                                            {
                                                $coreVersions += [PSCustomObject]@{
                                                    Type = 'Runtime'
                                                    Runtime = $runtime
                                                    Version = $versionDir.Name
                                                    InstallPath = $versionDir.FullName
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Error detecting .NET Core versions: $($_.Exception.Message)"
                            }

                            # Process Core results
                            if ($coreVersions -and $coreVersions.Count -gt 0)
                            {
                                # Group by runtime type
                                $runtimeGroups = $coreVersions | Group-Object Runtime

                                foreach ($group in $runtimeGroups)
                                {
                                    $runtimeName = switch ($group.Name)
                                    {
                                        'Microsoft.NETCore.App' { '.NET Core' }
                                        'Microsoft.AspNetCore.App' { 'ASP.NET Core' }
                                        'Microsoft.WindowsDesktop.App' { '.NET Desktop' }
                                        'Microsoft.NETCore.SDK' { '.NET SDK' }
                                        default { $group.Name }
                                    }

                                    $sortedVersions = $group.Group | Sort-Object { [version]($_.Version -replace '-.*$', '') } -Descending
                                    $latestVersion = $sortedVersions | Select-Object -First 1

                                    if ($All)
                                    {
                                        foreach ($version in $sortedVersions)
                                        {
                                            $computerResults += [PSCustomObject]@{
                                                PSTypeName = 'DotNetVersion.Result'
                                                ComputerName = $Computer
                                                RuntimeType = $runtimeName
                                                Version = $version.Version
                                                Release = $null
                                                InstallPath = $version.InstallPath
                                                IsLatest = ($version.Version -eq $latestVersion.Version)
                                                Type = $version.Type
                                            }
                                        }
                                    }
                                    else
                                    {
                                        $computerResults += [PSCustomObject]@{
                                            PSTypeName = 'DotNetVersion.Result'
                                            ComputerName = $Computer
                                            RuntimeType = $runtimeName
                                            Version = $latestVersion.Version
                                            Release = $null
                                            InstallPath = $latestVersion.InstallPath
                                            IsLatest = $true
                                            Type = $latestVersion.Type
                                        }
                                    }
                                }
                            }
                            else
                            {
                                # No .NET Core detected
                                $computerResults += [PSCustomObject]@{
                                    PSTypeName = 'DotNetVersion.Result'
                                    ComputerName = $Computer
                                    RuntimeType = '.NET Core'
                                    Version = 'Not installed'
                                    Release = $null
                                    InstallPath = $null
                                    IsLatest = $null
                                    Type = 'Runtime'
                                }
                            }

                            return $computerResults

                        } -ArgumentList $computer, $All.IsPresent, $IncludeSDKs.IsPresent, $FrameworkVersionTable

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
            }
            catch
            {
                Write-Warning "Failed to query computer '$computer': $($_.Exception.Message)"

                # Add error entries for both runtime types
                foreach ($runtimeType in @('.NET Framework', '.NET Core'))
                {
                    $errorResult = [PSCustomObject]@{
                        PSTypeName = 'DotNetVersion.Result'
                        ComputerName = $computer
                        RuntimeType = $runtimeType
                        Version = 'Error'
                        Release = $null
                        InstallPath = $null
                        IsLatest = $null
                        Type = 'Runtime'
                        Error = $_.Exception.Message
                    }
                    [void]$results.Add($errorResult)
                }
            }
        }
    }

    end
    {
        return $results.ToArray()
    }
}
