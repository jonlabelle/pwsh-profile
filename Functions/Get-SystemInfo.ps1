function Get-SystemInfo
{
    <#
    .SYNOPSIS
        Gets basic system information from local or remote computers.

    .DESCRIPTION
        Retrieves comprehensive system information including CPU architecture, processor speed,
        operating system details, computer model and name, memory information, and other
        hardware specifications. Supports both local and remote computer queries.

        Remote computer queries are only available on Windows systems via PowerShell remoting (WinRM).
        On macOS and Linux, only local computer queries are supported.

        Compatible with PowerShell Desktop 5.1 and PowerShell Core 6.2+ on Windows, macOS, and Linux.

    .PARAMETER ComputerName
        Target computers to retrieve system information from. Accepts an array of computer names or IP addresses.
        If not specified, 'localhost' is used as the default.
        Supports pipeline input by property name for object-based input.

        Note: Remote computer queries require Windows and PowerShell remoting (WinRM) to be enabled.

    .PARAMETER Credential
        Specifies credentials for remote computer access. Required for remote computers that need authentication.
        Only applicable on Windows systems with PowerShell remoting enabled.

    .EXAMPLE
        PS > Get-SystemInfo

        ComputerName         : localhost
        HostName             : something.local
        Domain               :
        IPAddresses          : {127.0.0.1, ::1, 172.0.10.39}
        OperatingSystem      : macOS Sequoia 15.6.1
        OSArchitecture       : arm64
        CPUArchitecture      : arm64
        CPUName              : Apple M4 Pro
        CPUCores             : 12
        CPULogicalProcessors : 12
        CPUSpeedMHz          :
        TotalMemoryGB        : 24
        FreeMemoryGB         : 10.33
        SystemDriveTotalGB   : 460.43
        SystemDriveUsedGB    : 11.21
        SystemDriveFreeGB    : 324.07
        Manufacturer         : Apple Inc.
        Model                : Mac16,8
        SerialNumber         : XXXXXXXXXXX
        BIOSVersion          : 13822.1.2
        TimeZone             : (UTC-05:00) Eastern Time (New York)
        LastBootTime         : 1/1/2025 5:42:29 PM
        Uptime               : 17:39:59.8442180

        Gets system information from the local computer.

    .EXAMPLE
        PS > Get-SystemInfo -ComputerName 'server01'

        Gets system information from a remote computer (Windows only).

    .EXAMPLE
        PS > Get-SystemInfo -ComputerName 'server01' -Credential (Get-Credential)

        Gets system information from a remote computer using specified credentials (Windows only).

    .EXAMPLE
        PS > 'server01','server02' | Get-SystemInfo

        Gets system information from multiple computers using pipeline input (Windows only).

    .EXAMPLE
        PS > Get-SystemInfo | Format-Table -AutoSize

        Gets system information and displays it in a formatted table.

    .OUTPUTS
        System.Object[]

        Returns custom objects with system information properties including:

        - ComputerName: Name of the computer
        - HostName: Fully qualified domain name or hostname
        - Domain: Domain name (Windows only, null for workgroup or non-Windows)
        - IPAddresses: Array of IP addresses assigned to the computer
        - OperatingSystem: Operating system name and version
        - OSArchitecture: Operating system architecture (32-bit/64-bit)
        - CPUArchitecture: Processor architecture
        - CPUName: Processor name/model
        - CPUCores: Number of processor cores
        - CPULogicalProcessors: Number of logical processors
        - CPUSpeedMHz: Processor speed in MHz
        - TotalMemoryGB: Total physical memory in GB
        - FreeMemoryGB: Available physical memory in GB
        - SystemDriveTotalGB: Total system drive capacity in GB
        - SystemDriveUsedGB: Used space on system drive in GB
        - SystemDriveFreeGB: Free space on system drive in GB
        - Manufacturer: Computer manufacturer
        - Model: Computer model
        - SerialNumber: Computer serial number (when available)
        - BIOSVersion: BIOS version
        - TimeZone: System time zone
        - LastBootTime: Last system boot time
        - Uptime: System uptime as a timespan

    .NOTES
        Name: Get-SystemInfo.ps1
        Author: Jon LaBelle
        Created: 10/10/2025

        Remote execution uses PowerShell remoting (WinRM) and requires:
        - Windows operating system
        - Appropriate permissions
        - PowerShell remoting enabled on target computers

        On macOS and Linux:
        - Only local computer queries are supported
        - Remote queries will generate a warning and skip non-local targets

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Get-SystemInfo.ps1
    #>
    [CmdletBinding(ConfirmImpact = 'Low')]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = 'Target computers to query')]
        [Alias('Cn', 'PSComputerName', 'Server', 'Target')]
        [String[]]$ComputerName,

        [Parameter(HelpMessage = 'Credentials for remote computer access')]
        [PSCredential]$Credential
    )

    begin
    {
        # Initialize results collection
        $results = New-Object System.Collections.ArrayList

        # Platform detection
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # PowerShell 5.1 - Windows only
            $script:IsWindowsPlatform = $true
            $script:IsMacOSPlatform = $false
            $script:IsLinuxPlatform = $false
        }
        else
        {
            # PowerShell Core - cross-platform
            $script:IsWindowsPlatform = $IsWindows
            $script:IsMacOSPlatform = $IsMacOS
            $script:IsLinuxPlatform = $IsLinux
        }

        # Default to localhost if no computer name specified
        if (-not $ComputerName)
        {
            $ComputerName = @('localhost')
        }

        Write-Verbose "Platform detection: Windows=$script:IsWindowsPlatform, macOS=$script:IsMacOSPlatform, Linux=$script:IsLinuxPlatform"
    }

    process
    {
        foreach ($computer in $ComputerName)
        {
            Write-Verbose "Processing computer: $computer"

            # Determine if this is a local or remote query
            $isLocal = ($computer -eq 'localhost' -or $computer -eq '127.0.0.1' -or $computer -eq $env:COMPUTERNAME -or $computer -eq [System.Net.Dns]::GetHostName())

            if ($isLocal)
            {
                # Local computer processing
                Write-Verbose 'Querying local computer for system information'

                try
                {
                    $systemInfo = [PSCustomObject]@{
                        PSTypeName = 'SystemInfo.Result'
                        ComputerName = $computer
                        HostName = $null
                        Domain = $null
                        IPAddresses = $null
                        OperatingSystem = $null
                        OSArchitecture = $null
                        CPUArchitecture = $null
                        CPUName = $null
                        CPUCores = $null
                        CPULogicalProcessors = $null
                        CPUSpeedMHz = $null
                        TotalMemoryGB = $null
                        FreeMemoryGB = $null
                        SystemDriveTotalGB = $null
                        SystemDriveUsedGB = $null
                        SystemDriveFreeGB = $null
                        Manufacturer = $null
                        Model = $null
                        SerialNumber = $null
                        BIOSVersion = $null
                        TimeZone = $null
                        LastBootTime = $null
                        Uptime = $null
                    }

                    # Get hostname and IP addresses (cross-platform)
                    try
                    {
                        $systemInfo.HostName = [System.Net.Dns]::GetHostName()

                        # Get all IP addresses for the local host
                        $hostEntry = [System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName())
                        $ipAddresses = $hostEntry.AddressList | Where-Object {
                            # Filter out IPv6 link-local addresses
                            $_.AddressFamily -eq 'InterNetwork' -or
                            ($_.AddressFamily -eq 'InterNetworkV6' -and -not $_.IsIPv6LinkLocal)
                        } | ForEach-Object { $_.IPAddressToString }

                        $systemInfo.IPAddresses = $ipAddresses
                    }
                    catch
                    {
                        Write-Verbose "Could not retrieve hostname or IP addresses: $($_.Exception.Message)"
                    }

                    # Get OS information
                    if ($script:IsWindowsPlatform)
                    {
                        # Windows-specific information using CIM/WMI
                        Write-Verbose 'Using CIM/WMI for Windows system information'

                        try
                        {
                            # Get OS information
                            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                            $systemInfo.OperatingSystem = $os.Caption
                            $systemInfo.OSArchitecture = $os.OSArchitecture
                            $systemInfo.TotalMemoryGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
                            $systemInfo.FreeMemoryGB = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
                            $systemInfo.LastBootTime = $os.LastBootUpTime
                            $systemInfo.Uptime = (Get-Date) - $os.LastBootUpTime

                            # Get system drive information (Windows)
                            try
                            {
                                $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
                                if ($systemDrive)
                                {
                                    $systemInfo.SystemDriveTotalGB = [Math]::Round($systemDrive.Size / 1GB, 2)
                                    $systemInfo.SystemDriveFreeGB = [Math]::Round($systemDrive.FreeSpace / 1GB, 2)
                                    $systemInfo.SystemDriveUsedGB = [Math]::Round(($systemDrive.Size - $systemDrive.FreeSpace) / 1GB, 2)
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve system drive information: $($_.Exception.Message)"
                            }

                            # Get processor information
                            $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
                            $systemInfo.CPUArchitecture = $cpu.Architecture
                            $systemInfo.CPUName = $cpu.Name.Trim()
                            $systemInfo.CPUCores = $cpu.NumberOfCores
                            $systemInfo.CPULogicalProcessors = $cpu.NumberOfLogicalProcessors
                            $systemInfo.CPUSpeedMHz = $cpu.MaxClockSpeed

                            # Get computer system information
                            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
                            $systemInfo.Manufacturer = $cs.Manufacturer
                            $systemInfo.Model = $cs.Model

                            # Get domain information (null if workgroup)
                            if ($cs.PartOfDomain)
                            {
                                $systemInfo.Domain = $cs.Domain
                            }
                            else
                            {
                                $systemInfo.Domain = $null  # Workgroup
                            }

                            # Get BIOS information
                            $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
                            $systemInfo.SerialNumber = $bios.SerialNumber
                            $systemInfo.BIOSVersion = $bios.SMBIOSBIOSVersion

                            # Get time zone
                            $systemInfo.TimeZone = (Get-TimeZone).Id
                        }
                        catch
                        {
                            Write-Warning "Failed to retrieve some Windows system information: $($_.Exception.Message)"
                        }
                    }
                    elseif ($script:IsMacOSPlatform)
                    {
                        # macOS-specific information using system commands
                        Write-Verbose 'Using system commands for macOS system information'

                        try
                        {
                            # Get OS version and name
                            $osVersion = sw_vers -productVersion 2>$null
                            $osName = sw_vers -productName 2>$null

                            # Try to get the macOS release name (e.g., Sequoia, Sonoma, Ventura)
                            $osReleaseName = $null
                            try
                            {
                                $licenseFile = '/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/en.lproj/OSXSoftwareLicense.rtf'
                                if (Test-Path $licenseFile)
                                {
                                    $licenseContent = Get-Content $licenseFile -Raw -ErrorAction SilentlyContinue
                                    if ($licenseContent -match 'SOFTWARE LICENSE AGREEMENT FOR macOS\s+(\w+)')
                                    {
                                        $osReleaseName = $matches[1]
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve macOS release name: $($_.Exception.Message)"
                            }

                            # Build the OS string with release name if available
                            if ($osReleaseName)
                            {
                                $systemInfo.OperatingSystem = "$osName $osReleaseName $osVersion".Trim()
                            }
                            else
                            {
                                $systemInfo.OperatingSystem = "$osName $osVersion".Trim()
                            }

                            # Get architecture
                            $arch = uname -m 2>$null
                            $systemInfo.OSArchitecture = $arch
                            $systemInfo.CPUArchitecture = $arch

                            # Get CPU information using sysctl
                            $cpuBrand = sysctl -n machdep.cpu.brand_string 2>$null
                            $systemInfo.CPUName = $cpuBrand

                            $cpuCores = sysctl -n hw.physicalcpu 2>$null
                            if ($cpuCores) { $systemInfo.CPUCores = [int]$cpuCores }

                            $cpuLogical = sysctl -n hw.logicalcpu 2>$null
                            if ($cpuLogical) { $systemInfo.CPULogicalProcessors = [int]$cpuLogical }

                            # CPU frequency: Only available on Intel Macs via hw.cpufrequency
                            # Apple Silicon Macs use dynamic frequency scaling and don't expose a fixed value
                            $cpuFreq = sysctl -n hw.cpufrequency 2>$null
                            if ($cpuFreq -and $cpuFreq -match '^\d+$')
                            {
                                $systemInfo.CPUSpeedMHz = [Math]::Round([int64]$cpuFreq / 1MB, 0)
                            }

                            # Get memory information (in bytes, convert to GB)
                            $totalMem = sysctl -n hw.memsize 2>$null
                            if ($totalMem) { $systemInfo.TotalMemoryGB = [Math]::Round([int64]$totalMem / 1GB, 2) }

                            # Get available memory using vm_stat
                            # On macOS, "available" memory includes free + inactive + speculative + purgeable pages
                            $vmStat = vm_stat 2>$null
                            if ($vmStat)
                            {
                                # Get actual page size from vm_stat output
                                $pageSizeLine = $vmStat | Select-String 'page size of (\d+) bytes'
                                $pageSize = if ($pageSizeLine -and $pageSizeLine.Matches.Groups.Count -gt 1)
                                {
                                    [int64]$pageSizeLine.Matches.Groups[1].Value
                                }
                                else
                                {
                                    16384  # Default for Apple Silicon, 4096 for Intel
                                }

                                # Parse memory page counts
                                $freePages = 0
                                $inactivePages = 0
                                $speculativePages = 0
                                $purgeablePages = 0

                                $freePagesLine = $vmStat | Select-String 'Pages free:\s+(\d+)'
                                if ($freePagesLine -and $freePagesLine.Matches.Groups.Count -gt 1)
                                {
                                    $freePages = [int64]$freePagesLine.Matches.Groups[1].Value
                                }

                                $inactivePagesLine = $vmStat | Select-String 'Pages inactive:\s+(\d+)'
                                if ($inactivePagesLine -and $inactivePagesLine.Matches.Groups.Count -gt 1)
                                {
                                    $inactivePages = [int64]$inactivePagesLine.Matches.Groups[1].Value
                                }

                                $speculativePagesLine = $vmStat | Select-String 'Pages speculative:\s+(\d+)'
                                if ($speculativePagesLine -and $speculativePagesLine.Matches.Groups.Count -gt 1)
                                {
                                    $speculativePages = [int64]$speculativePagesLine.Matches.Groups[1].Value
                                }

                                $purgeablePagesLine = $vmStat | Select-String 'Pages purgeable:\s+(\d+)'
                                if ($purgeablePagesLine -and $purgeablePagesLine.Matches.Groups.Count -gt 1)
                                {
                                    $purgeablePages = [int64]$purgeablePagesLine.Matches.Groups[1].Value
                                }

                                # Calculate available memory (free + inactive + speculative + purgeable)
                                $availablePages = $freePages + $inactivePages + $speculativePages + $purgeablePages
                                $systemInfo.FreeMemoryGB = [Math]::Round(($availablePages * $pageSize) / 1GB, 2)
                            }

                            # Get hardware model
                            $model = sysctl -n hw.model 2>$null
                            $systemInfo.Model = $model

                            # Get system manufacturer (Apple)
                            $systemInfo.Manufacturer = 'Apple Inc.'

                            # Get serial number and firmware version from system_profiler
                            $hardwareProfile = system_profiler SPHardwareDataType 2>$null

                            $serial = $hardwareProfile | Select-String 'Serial Number'
                            if ($serial)
                            {
                                $systemInfo.SerialNumber = ($serial -replace '.*:\s*', '').Trim()
                            }

                            # Get firmware version (macOS equivalent of BIOS version)
                            $firmware = $hardwareProfile | Select-String 'System Firmware Version'
                            if ($firmware)
                            {
                                $systemInfo.BIOSVersion = ($firmware -replace '.*:\s*', '').Trim()
                            }

                            # Get boot time
                            $bootTime = sysctl -n kern.boottime 2>$null
                            if ($bootTime -match 'sec = (\d+)')
                            {
                                $bootEpoch = [int64]$matches[1]
                                $systemInfo.LastBootTime = [DateTimeOffset]::FromUnixTimeSeconds($bootEpoch).LocalDateTime
                                $systemInfo.Uptime = (Get-Date) - $systemInfo.LastBootTime
                            }

                            # Get system drive information (macOS)
                            try
                            {
                                $dfOutput = df -k / 2>$null | Select-Object -Skip 1
                                if ($dfOutput)
                                {
                                    # Parse df output: Filesystem 1K-blocks Used Available Capacity iused ifree %iused Mounted
                                    $parts = $dfOutput -split '\s+' | Where-Object { $_ }
                                    if ($parts.Count -ge 4)
                                    {
                                        $totalKB = [int64]$parts[1]
                                        $usedKB = [int64]$parts[2]
                                        $availKB = [int64]$parts[3]

                                        $systemInfo.SystemDriveTotalGB = [Math]::Round($totalKB / 1MB, 2)
                                        $systemInfo.SystemDriveUsedGB = [Math]::Round($usedKB / 1MB, 2)
                                        $systemInfo.SystemDriveFreeGB = [Math]::Round($availKB / 1MB, 2)
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve system drive information: $($_.Exception.Message)"
                            }

                            # Get time zone using .NET (cross-platform, no admin required)
                            try
                            {
                                $systemInfo.TimeZone = [System.TimeZoneInfo]::Local.DisplayName
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve timezone: $($_.Exception.Message)"
                            }
                        }
                        catch
                        {
                            Write-Warning "Failed to retrieve some macOS system information: $($_.Exception.Message)"
                        }
                    }
                    elseif ($script:IsLinuxPlatform)
                    {
                        # Linux-specific information using system commands
                        Write-Verbose 'Using system commands for Linux system information'

                        try
                        {
                            # Get OS information from /etc/os-release
                            if (Test-Path '/etc/os-release')
                            {
                                $osRelease = Get-Content '/etc/os-release' -ErrorAction SilentlyContinue
                                $prettyName = $osRelease | Where-Object { $_ -match '^PRETTY_NAME=' }
                                if ($prettyName)
                                {
                                    $systemInfo.OperatingSystem = ($prettyName -replace 'PRETTY_NAME=', '' -replace '"', '').Trim()
                                }
                            }

                            # Get architecture
                            $arch = uname -m 2>$null
                            $systemInfo.OSArchitecture = $arch
                            $systemInfo.CPUArchitecture = $arch

                            # Get CPU information from /proc/cpuinfo
                            if (Test-Path '/proc/cpuinfo')
                            {
                                $cpuInfo = Get-Content '/proc/cpuinfo' -ErrorAction SilentlyContinue

                                # Get CPU model name
                                $modelName = $cpuInfo | Where-Object { $_ -match '^model name' } | Select-Object -First 1
                                if ($modelName)
                                {
                                    $systemInfo.CPUName = ($modelName -replace 'model name\s*:\s*', '').Trim()
                                }

                                # Get CPU frequency
                                $cpuMhz = $cpuInfo | Where-Object { $_ -match '^cpu MHz' } | Select-Object -First 1
                                if ($cpuMhz)
                                {
                                    $freq = ($cpuMhz -replace 'cpu MHz\s*:\s*', '').Trim()
                                    $systemInfo.CPUSpeedMHz = [Math]::Round([double]$freq, 0)
                                }

                                # Count physical and logical processors
                                $physicalIds = $cpuInfo | Where-Object { $_ -match '^physical id' } | ForEach-Object { ($_ -split ':')[1].Trim() } | Select-Object -Unique
                                $coresPerSocket = $cpuInfo | Where-Object { $_ -match '^cpu cores' } | Select-Object -First 1
                                if ($coresPerSocket)
                                {
                                    $coresCount = [int]($coresPerSocket -replace 'cpu cores\s*:\s*', '').Trim()
                                    $socketCount = if ($physicalIds.Count -gt 0) { $physicalIds.Count } else { 1 }
                                    $systemInfo.CPUCores = $coresCount * $socketCount
                                }

                                $processors = $cpuInfo | Where-Object { $_ -match '^processor' }
                                $systemInfo.CPULogicalProcessors = $processors.Count
                            }

                            # Remove duplicate CPU cores calculation
                            # Already handled above with PowerShell 5.1 compatible syntax

                            # Get memory information from /proc/meminfo
                            if (Test-Path '/proc/meminfo')
                            {
                                $memInfo = Get-Content '/proc/meminfo' -ErrorAction SilentlyContinue

                                $totalMem = $memInfo | Where-Object { $_ -match '^MemTotal:' }
                                if ($totalMem)
                                {
                                    $totalKb = [int64](($totalMem -replace '[^\d]', '').Trim())
                                    $systemInfo.TotalMemoryGB = [Math]::Round($totalKb / 1MB, 2)
                                }

                                $availMem = $memInfo | Where-Object { $_ -match '^MemAvailable:' }
                                if ($availMem)
                                {
                                    $availKb = [int64](($availMem -replace '[^\d]', '').Trim())
                                    $systemInfo.FreeMemoryGB = [Math]::Round($availKb / 1MB, 2)
                                }
                            }

                            # Get system manufacturer and model using dmidecode (requires sudo)
                            $dmidecodeAvailable = Get-Command dmidecode -ErrorAction SilentlyContinue
                            if ($dmidecodeAvailable)
                            {
                                try
                                {
                                    $systemManufacturer = dmidecode -s system-manufacturer 2>$null
                                    if ($systemManufacturer) { $systemInfo.Manufacturer = $systemManufacturer.Trim() }

                                    $systemProduct = dmidecode -s system-product-name 2>$null
                                    if ($systemProduct) { $systemInfo.Model = $systemProduct.Trim() }

                                    $systemSerial = dmidecode -s system-serial-number 2>$null
                                    if ($systemSerial) { $systemInfo.SerialNumber = $systemSerial.Trim() }

                                    $biosVersion = dmidecode -s bios-version 2>$null
                                    if ($biosVersion) { $systemInfo.BIOSVersion = $biosVersion.Trim() }
                                }
                                catch
                                {
                                    Write-Verbose 'dmidecode commands require elevated privileges for full information'
                                }
                            }

                            # Get uptime
                            if (Test-Path '/proc/uptime')
                            {
                                $uptimeContent = Get-Content '/proc/uptime' -ErrorAction SilentlyContinue
                                if ($uptimeContent)
                                {
                                    $uptimeSeconds = [Math]::Floor([double]($uptimeContent -split ' ')[0])
                                    $systemInfo.LastBootTime = (Get-Date).AddSeconds(-$uptimeSeconds)
                                    $systemInfo.Uptime = New-TimeSpan -Seconds $uptimeSeconds
                                }
                            }

                            # Get system drive information (Linux)
                            try
                            {
                                $dfOutput = df -k / 2>$null | Select-Object -Skip 1
                                if ($dfOutput)
                                {
                                    # Parse df output: Filesystem 1K-blocks Used Available Use% Mounted
                                    $parts = $dfOutput -split '\s+' | Where-Object { $_ }
                                    if ($parts.Count -ge 4)
                                    {
                                        $totalKB = [int64]$parts[1]
                                        $usedKB = [int64]$parts[2]
                                        $availKB = [int64]$parts[3]

                                        $systemInfo.SystemDriveTotalGB = [Math]::Round($totalKB / 1MB, 2)
                                        $systemInfo.SystemDriveUsedGB = [Math]::Round($usedKB / 1MB, 2)
                                        $systemInfo.SystemDriveFreeGB = [Math]::Round($availKB / 1MB, 2)
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve system drive information: $($_.Exception.Message)"
                            }

                            # Get time zone using .NET (cross-platform, consistent with other platforms)
                            try
                            {
                                $systemInfo.TimeZone = [System.TimeZoneInfo]::Local.DisplayName
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve timezone: $($_.Exception.Message)"
                            }
                        }
                        catch
                        {
                            Write-Warning "Failed to retrieve some Linux system information: $($_.Exception.Message)"
                        }
                    }

                    [void]$results.Add($systemInfo)
                }
                catch
                {
                    $errorMessage = $_.Exception.Message
                    Write-Error "Failed to retrieve system information for $computer`: $errorMessage"
                }
            }
            else
            {
                # Remote computer processing - Windows only via PowerShell Remoting
                if (-not $script:IsWindowsPlatform)
                {
                    Write-Warning "Remote computer queries are only supported on Windows. Skipping remote computer: $computer"
                    continue
                }

                Write-Verbose "Querying remote computer '$computer' for system information"

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
                        $systemInfo = [PSCustomObject]@{
                            PSTypeName = 'SystemInfo.Result'
                            ComputerName = $env:COMPUTERNAME
                            HostName = $null
                            Domain = $null
                            IPAddresses = $null
                            OperatingSystem = $null
                            OSArchitecture = $null
                            CPUArchitecture = $null
                            CPUName = $null
                            CPUCores = $null
                            CPULogicalProcessors = $null
                            CPUSpeedMHz = $null
                            TotalMemoryGB = $null
                            FreeMemoryGB = $null
                            SystemDriveTotalGB = $null
                            SystemDriveUsedGB = $null
                            SystemDriveFreeGB = $null
                            Manufacturer = $null
                            Model = $null
                            SerialNumber = $null
                            BIOSVersion = $null
                            TimeZone = $null
                            LastBootTime = $null
                            Uptime = $null
                        }

                        try
                        {
                            # Get hostname and IP addresses
                            try
                            {
                                $systemInfo.HostName = [System.Net.Dns]::GetHostName()

                                # Get all IP addresses for the local host
                                $hostEntry = [System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName())
                                $ipAddresses = $hostEntry.AddressList | Where-Object {
                                    # Filter out IPv6 link-local addresses
                                    $_.AddressFamily -eq 'InterNetwork' -or
                                    ($_.AddressFamily -eq 'InterNetworkV6' -and -not $_.IsIPv6LinkLocal)
                                } | ForEach-Object { $_.IPAddressToString }

                                $systemInfo.IPAddresses = $ipAddresses
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve hostname or IP addresses: $($_.Exception.Message)"
                            }

                            # Get OS information
                            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                            $systemInfo.OperatingSystem = $os.Caption
                            $systemInfo.OSArchitecture = $os.OSArchitecture
                            $systemInfo.TotalMemoryGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
                            $systemInfo.FreeMemoryGB = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
                            $systemInfo.LastBootTime = $os.LastBootUpTime
                            $systemInfo.Uptime = (Get-Date) - $os.LastBootUpTime

                            # Get system drive information (Windows remote)
                            try
                            {
                                $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
                                if ($systemDrive)
                                {
                                    $systemInfo.SystemDriveTotalGB = [Math]::Round($systemDrive.Size / 1GB, 2)
                                    $systemInfo.SystemDriveFreeGB = [Math]::Round($systemDrive.FreeSpace / 1GB, 2)
                                    $systemInfo.SystemDriveUsedGB = [Math]::Round(($systemDrive.Size - $systemDrive.FreeSpace) / 1GB, 2)
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve system drive information: $($_.Exception.Message)"
                            }

                            # Get processor information
                            $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
                            $systemInfo.CPUArchitecture = $cpu.Architecture
                            $systemInfo.CPUName = $cpu.Name.Trim()
                            $systemInfo.CPUCores = $cpu.NumberOfCores
                            $systemInfo.CPULogicalProcessors = $cpu.NumberOfLogicalProcessors
                            $systemInfo.CPUSpeedMHz = $cpu.MaxClockSpeed

                            # Get computer system information
                            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
                            $systemInfo.Manufacturer = $cs.Manufacturer
                            $systemInfo.Model = $cs.Model

                            # Get domain information (null if workgroup)
                            if ($cs.PartOfDomain)
                            {
                                $systemInfo.Domain = $cs.Domain
                            }
                            else
                            {
                                $systemInfo.Domain = $null  # Workgroup
                            }

                            # Get BIOS information
                            $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
                            $systemInfo.SerialNumber = $bios.SerialNumber
                            $systemInfo.BIOSVersion = $bios.SMBIOSBIOSVersion

                            # Get time zone
                            $systemInfo.TimeZone = (Get-TimeZone).Id
                        }
                        catch
                        {
                            Write-Warning "Failed to retrieve some system information: $($_.Exception.Message)"
                        }

                        return $systemInfo
                    }

                    if ($remoteResults)
                    {
                        [void]$results.Add($remoteResults)
                    }
                }
                catch
                {
                    $errorMessage = $_.Exception.Message
                    Write-Error "Failed to connect to remote computer $computer`: $errorMessage"
                }
                finally
                {
                    if ($session)
                    {
                        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    end
    {
        # Return all collected results
        return $results.ToArray()
    }
}
