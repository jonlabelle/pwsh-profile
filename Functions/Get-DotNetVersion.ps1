function Get-DotNetVersion
{
    <#
    .SYNOPSIS
        Gets installed .NET Framework and .NET (formally .NET Core) versions from local or remote computers.

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
        Show all installed versions of .NET Framework and .NET.
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

        Gets the latest .NET Framework and .NET versions from the local computer.

    .EXAMPLE
        PS > Get-DotNetVersion -All

        Gets all installed .NET Framework and .NET versions from the local computer.

    .EXAMPLE
        PS > Get-DotNetVersion -ComputerName 'server01' -Credential (Get-Credential)

        Gets .NET versions from a remote computer using specified credentials.

    .EXAMPLE
        PS > 'server01','server02' | Get-DotNetVersion -All

        Gets all .NET versions from multiple computers using pipeline input.

    .EXAMPLE
        PS > Get-DotNetVersion -ComputerName 'devmachine' -IncludeSDKs -All

        Gets all .NET versions including SDK versions from a remote development machine.

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
        Name: Get-DotNetVersion.ps1
        Author: Jon LaBelle
        Created: 8/20/2025
        Enhanced cross-platform support for .NET detection

        .NET Framework detection uses Windows Registry (Windows only)
        .NET detection uses dotnet CLI when available, falls back to directory scanning

        - Remote execution uses PowerShell remoting (WinRM) and requires appropriate permissions
        - By default returns results for both .NET Framework and .NET, indicating "Not installed" when absent
        - Use -FrameworkOnly or -DotNetOnly to filter results to specific runtime types
        - The -IncludeSDKs parameter can be used with -DotNetOnly or the default parameter set, but not with -FrameworkOnly

    .LINK
        https://docs.microsoft.com/en-us/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed

    .LINK
        https://jonlabelle.com/snippets/view/powershell/get-installed-net-versions-in-powershell

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Get-DotNetVersion.ps1
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
        # Initialize results collection
        $results = New-Object System.Collections.ArrayList

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

                    # Get .NET Framework versions (Windows only) - Skip if DotNetOnly
                    if (-not $DotNetOnly)
                    {
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

                                    # Check for .NET Framework 4.0 (Client and Full profiles)
                                    $v4ClientKey = $ndpKey.OpenSubKey('v4\Client')
                                    $v4FullKey = $ndpKey.OpenSubKey('v4\Full')

                                    # .NET Framework 4.0 detection
                                    if ($v4ClientKey -and $v4ClientKey.GetValue('Install') -eq 1)
                                    {
                                        $version = $v4ClientKey.GetValue('Version', '4.0')
                                        $installPath = $v4ClientKey.GetValue('InstallPath', '')

                                        $frameworkVersions += [PSCustomObject]@{
                                            Version = "$version (Client Profile)"
                                            Release = $null
                                            InstallPath = $installPath
                                        }
                                        $v4ClientKey.Close()
                                    }

                                    if ($v4FullKey)
                                    {
                                        $release = [int]$v4FullKey.GetValue('Release', 0)
                                        $version = $v4FullKey.GetValue('Version', '4.0')
                                        $installPath = $v4FullKey.GetValue('InstallPath', '')
                                        $install = $v4FullKey.GetValue('Install')

                                        # Handle .NET Framework 4.0 (no release number)
                                        if ($release -eq 0 -and $install -eq 1)
                                        {
                                            $frameworkVersions += [PSCustomObject]@{
                                                Version = $version
                                                Release = $null
                                                InstallPath = $installPath
                                            }
                                        }
                                        # Handle .NET Framework 4.5+ (with release number)
                                        elseif ($release -gt 0)
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
                                        $v4FullKey.Close()
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
                    }

                    # Get .NET versions - Skip if FrameworkOnly
                    if (-not $FrameworkOnly)
                    {
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
                            Write-Verbose "Error detecting .NET versions: $($_.Exception.Message)"
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
                                    'Microsoft.NETCore.App' { '.NET' }
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
                            # No .NET detected
                            $computerResults += [PSCustomObject]@{
                                PSTypeName = 'DotNetVersion.Result'
                                ComputerName = $computer
                                RuntimeType = '.NET'
                                Version = 'Not installed'
                                Release = $null
                                InstallPath = $null
                                IsLatest = $null
                                Type = 'Runtime'
                            }
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

                    $session = $null
                    try
                    {
                        $session = New-PSSession @sessionParams

                        $remoteResults = Invoke-Command -Session $session -ScriptBlock {
                            param($Computer, $All, $IncludeSDKs, $FrameworkVersionTable, $FrameworkOnly, $DotNetOnly)

                            $computerResults = @()

                            Write-Verbose "Processing .NET versions for $Computer"

                            # Get .NET Framework versions (Windows only) - Skip if DotNetOnly
                            if (-not $DotNetOnly)
                            {
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

                                            # Check for .NET Framework 4.0 (Client and Full profiles)
                                            $v4ClientKey = $ndpKey.OpenSubKey('v4\Client')
                                            $v4FullKey = $ndpKey.OpenSubKey('v4\Full')

                                            # .NET Framework 4.0 detection
                                            if ($v4ClientKey -and $v4ClientKey.GetValue('Install') -eq 1)
                                            {
                                                $version = $v4ClientKey.GetValue('Version', '4.0')
                                                $installPath = $v4ClientKey.GetValue('InstallPath', '')

                                                $frameworkVersions += [PSCustomObject]@{
                                                    Version = "$version (Client Profile)"
                                                    Release = $null
                                                    InstallPath = $installPath
                                                }
                                                $v4ClientKey.Close()
                                            }

                                            if ($v4FullKey)
                                            {
                                                $release = [int]$v4FullKey.GetValue('Release', 0)
                                                $version = $v4FullKey.GetValue('Version', '4.0')
                                                $installPath = $v4FullKey.GetValue('InstallPath', '')
                                                $install = $v4FullKey.GetValue('Install')

                                                # Handle .NET Framework 4.0 (no release number)
                                                if ($release -eq 0 -and $install -eq 1)
                                                {
                                                    $frameworkVersions += [PSCustomObject]@{
                                                        Version = $version
                                                        Release = $null
                                                        InstallPath = $installPath
                                                    }
                                                }
                                                # Handle .NET Framework 4.5+ (with release number)
                                                elseif ($release -gt 0)
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
                                                $v4FullKey.Close()
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
                            }

                            # Get .NET versions - Skip if FrameworkOnly
                            if (-not $FrameworkOnly)
                            {
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
                                    Write-Verbose "Error detecting .NET versions: $($_.Exception.Message)"
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
                                            'Microsoft.NETCore.App' { '.NET' }
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
                                    # No .NET detected
                                    $computerResults += [PSCustomObject]@{
                                        PSTypeName = 'DotNetVersion.Result'
                                        ComputerName = $Computer
                                        RuntimeType = '.NET'
                                        Version = 'Not installed'
                                        Release = $null
                                        InstallPath = $null
                                        IsLatest = $null
                                        Type = 'Runtime'
                                    }
                                }
                            }

                            return $computerResults

                        } -ArgumentList $computer, $All.IsPresent, $IncludeSDKs.IsPresent, $FrameworkVersionTable, $FrameworkOnly.IsPresent, $DotNetOnly.IsPresent

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
                foreach ($runtimeType in @('.NET Framework', '.NET'))
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
