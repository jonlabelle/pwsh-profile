function Get-SystemInfo
{
    <#
    .SYNOPSIS
        Gets basic system information from local or remote computers.

    .DESCRIPTION
        Retrieves comprehensive system information including CPU architecture, processor speed,
        operating system details, computer model and name, memory information, GPU/video card
        details, physical disk specifications, audio devices, monitor/display information,
        input devices (keyboard and mouse), network adapters, and other hardware specifications.
        Supports both local and remote computer queries.

        Remote computer queries are only available on Windows systems via PowerShell remoting (WinRM).
        On macOS and Linux, only local computer queries are supported.

        Hardware information includes:
        - GPU/Video card name and memory
        - Physical disks (embedded drives only, excludes USB and removable media)
        - Audio devices
        - Monitors/displays with resolution information
        - Keyboard devices
        - Mouse/pointing devices
        - Network adapters (physical adapters only)

        Compatible with PowerShell Desktop 5.1 and PowerShell Core 6.2+ on Windows, macOS, and Linux.

    .PARAMETER ComputerName
        Target computers to retrieve system information from. Accepts an array of computer names or IP addresses.
        If not specified, 'localhost' is used as the default.
        Supports pipeline input by property name for object-based input.

        Note: Remote computer queries require Windows and PowerShell remoting (WinRM) to be enabled.

    .PARAMETER Credential
        Specifies credentials for remote computer access. Required for remote computers that need authentication.
        Only applicable on Windows systems with PowerShell remoting enabled.

    .PARAMETER NoPII
        Excludes private and personally identifiable information from the output. When specified, the following
        properties will be omitted: ComputerName, HostName, Domain, IPAddresses, SerialNumber, BIOSVersion,
        TimeZone, LastBootTime, and Uptime.

    .PARAMETER NoEmptyProps
        Excludes properties with null or empty values from the output. This provides cleaner results by only
        showing properties that have actual values, which is particularly useful for cross-platform scenarios
        where certain properties may not be available on all operating systems.

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
        LastBootTime         : 1/1/2025 5:42:29 PM
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

    .EXAMPLE
        PS > Get-SystemInfo -NoPII

        OperatingSystem      : Microsoft Windows 11 Pro
        OSArchitecture       : 64-bit
        CPUArchitecture      : x64
        CPUName              : Intel(R) Core(TM) i7-8665U CPU @ 1.90GHz
        CPUCores             : 4
        CPULogicalProcessors : 8
        CPUSpeedMHz          : 2112
        GPUName              : Intel(R) UHD Graphics 620 (1 GB)
        GPUMemoryGB          : 1
        Monitors             : IVO Unknown Monitor (1536x864)
        Keyboard             : USB Input Device, Standard 101/102-Key or Microsoft Natural PS/2 Keyboard for HP Hotkey Support
        Mouse                : HID-compliant mouse, Synaptics Pointing Device, USB Input Device, Synaptics HID ClickPad
        NetworkAdapters      : Intel(R) Wi-Fi 6 AX200 160MHz (827 Mbps), Intel(R) Ethernet Connection (6) I219-LM (8796093022208 Mbps)
        TotalMemoryGB        : 15.81
        FreeMemoryGB         : 7.72
        SystemDriveTotalGB   : 930.27
        SystemDriveUsedGB    : 204.2
        SystemDriveFreeGB    : 726.07
        PhysicalDisks        : CT1000MX500SSD4 (931.51 GB, IDE)
        AudioDevices         : Intel(R) Display Audio
        Manufacturer         : HP
        Model                : HP ZBook 15u G6

        Gets system information while excluding private and personally identifiable information
        such as computer name, hostname, IP addresses, serial number, and BIOS version.

    .EXAMPLE
        PS > Get-SystemInfo -NoEmptyProps

        Gets system information and excludes any properties that have null or empty values,
        resulting in a cleaner output showing only populated properties.

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
        - HyperthreadingEnabled: Whether hyperthreading/SMT is enabled
        - CPUSpeedMHz: Processor speed in MHz
        - GPUName: GPU/video card name(s)
        - GPUMemoryGB: Total GPU memory in GB (when available)
        - Monitors: Monitor/display information with resolution
        - Keyboard: Keyboard device name(s)
        - Mouse: Mouse/pointing device name(s)
        - NetworkAdapters: Network adapter information (physical adapters only)
        - TotalMemoryGB: Total physical memory in GB
        - FreeMemoryGB: Available physical memory in GB
        - SystemDriveTotalGB: Total system drive capacity in GB
        - SystemDriveUsedGB: Used space on system drive in GB
        - SystemDriveFreeGB: Free space on system drive in GB
        - PhysicalDisks: Physical disk information (embedded drives only, excludes USB/removable)
        - AudioDevices: Audio device names
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
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Cn', 'PSComputerName', 'Server', 'Target')]
        [String[]]$ComputerName,

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [Switch]$NoPII,

        [Parameter()]
        [Switch]$NoEmptyProps
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
        # Helper function to translate Windows CPU architecture codes
        function ConvertFrom-CpuArchitectureCode
        {
            param([int]$Code)

            switch ($Code)
            {
                0 { 'x86' }
                1 { 'MIPS' }
                2 { 'Alpha' }
                3 { 'PowerPC' }
                5 { 'ARM' }
                6 { 'ia64' }
                9 { 'x64' }
                12 { 'ARM64' }
                default { "Unknown ($Code)" }
            }
        }

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
                        HyperthreadingEnabled = $null
                        CPUSpeedMHz = $null
                        GPUName = $null
                        GPUMemoryGB = $null
                        Monitors = $null
                        Keyboard = $null
                        Mouse = $null
                        NetworkAdapters = $null
                        TotalMemoryGB = $null
                        FreeMemoryGB = $null
                        SystemDriveTotalGB = $null
                        SystemDriveUsedGB = $null
                        SystemDriveFreeGB = $null
                        PhysicalDisks = $null
                        AudioDevices = $null
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
                            $systemInfo.CPUArchitecture = ConvertFrom-CpuArchitectureCode -Code $cpu.Architecture
                            $systemInfo.CPUName = $cpu.Name.Trim()
                            $systemInfo.CPUCores = $cpu.NumberOfCores
                            $systemInfo.CPULogicalProcessors = $cpu.NumberOfLogicalProcessors

                            # Detect hyperthreading/SMT (if logical processors > cores, HT is enabled)
                            if ($cpu.NumberOfLogicalProcessors -gt $cpu.NumberOfCores)
                            {
                                $systemInfo.HyperthreadingEnabled = $true
                            }
                            else
                            {
                                $systemInfo.HyperthreadingEnabled = $false
                            }

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

                            # Get time zone with DST awareness
                            $timeZone = [System.TimeZoneInfo]::Local
                            $isDst = $timeZone.IsDaylightSavingTime((Get-Date))
                            $offset = $timeZone.GetUtcOffset((Get-Date))
                            $offsetString = if ($offset.TotalHours -ge 0) { "+$($offset.Hours)" } else { "$($offset.Hours)" }

                            if ($isDst -and $timeZone.DaylightName)
                            {
                                $systemInfo.TimeZone = "$($timeZone.DaylightName) (UTC$offsetString)"
                            }
                            else
                            {
                                $systemInfo.TimeZone = "$($timeZone.StandardName) (UTC$offsetString)"
                            }

                            # Get video card information
                            try
                            {
                                $videoCards = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
                                Where-Object { $_.Status -eq 'OK' -or $_.Status -eq $null }

                                if ($videoCards)
                                {
                                    $gpuInfo = @()
                                    foreach ($gpu in $videoCards)
                                    {
                                        $gpuName = $gpu.Name
                                        $gpuMemoryBytes = $gpu.AdapterRAM

                                        if ($gpuMemoryBytes -and $gpuMemoryBytes -gt 0)
                                        {
                                            $gpuMemoryGB = [Math]::Round($gpuMemoryBytes / 1GB, 2)
                                            $gpuInfo += "$gpuName ($gpuMemoryGB GB)"
                                        }
                                        else
                                        {
                                            $gpuInfo += $gpuName
                                        }
                                    }

                                    $systemInfo.GPUName = $gpuInfo -join ', '

                                    # Set GPUMemoryGB to total memory if available
                                    $totalGpuMemory = ($videoCards | Where-Object { $_.AdapterRAM -gt 0 } |
                                        Measure-Object -Property AdapterRAM -Sum).Sum
                                    if ($totalGpuMemory -gt 0)
                                    {
                                        $systemInfo.GPUMemoryGB = [Math]::Round($totalGpuMemory / 1GB, 2)
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve video card information: $($_.Exception.Message)"
                            }

                            # Get physical disk information (embedded drives only - exclude USB/removable)
                            try
                            {
                                $physicalDisks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop |
                                Where-Object {
                                    $_.MediaType -notmatch 'Removable' -and
                                    $_.InterfaceType -notmatch 'USB' -and
                                    $_.Size -gt 0
                                }

                                if ($physicalDisks)
                                {
                                    $diskInfo = @()
                                    foreach ($disk in $physicalDisks)
                                    {
                                        $diskModel = $disk.Model
                                        $diskSizeGB = [Math]::Round($disk.Size / 1GB, 2)
                                        $diskInterface = $disk.InterfaceType

                                        $diskInfo += "$diskModel ($diskSizeGB GB, $diskInterface)"
                                    }

                                    $systemInfo.PhysicalDisks = $diskInfo -join ', '
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve physical disk information: $($_.Exception.Message)"
                            }

                            # Get audio device information
                            try
                            {
                                $audioDevices = Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction Stop |
                                Where-Object { $_.Status -eq 'OK' -or $_.Status -eq $null }

                                if ($audioDevices)
                                {
                                    $audioInfo = @()
                                    foreach ($audio in $audioDevices)
                                    {
                                        $audioInfo += $audio.Name
                                    }

                                    $systemInfo.AudioDevices = $audioInfo -join ', '
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve audio device information: $($_.Exception.Message)"
                            }

                            # Get monitor information
                            try
                            {
                                $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop

                                if ($monitors)
                                {
                                    $monitorInfo = @()
                                    foreach ($monitor in $monitors)
                                    {
                                        # Decode manufacturer name
                                        $mfgName = if ($monitor.ManufacturerName)
                                        {
                                            -join ($monitor.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
                                        }
                                        else { 'Unknown' }

                                        # Decode user-friendly name
                                        $monitorName = if ($monitor.UserFriendlyName)
                                        {
                                            -join ($monitor.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
                                        }
                                        else { 'Unknown Monitor' }

                                        # Get resolution using WMI
                                        try
                                        {
                                            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
                                            $screen = [System.Windows.Forms.Screen]::AllScreens | Select-Object -First 1
                                            $resolution = "$($screen.Bounds.Width)x$($screen.Bounds.Height)"
                                        }
                                        catch
                                        {
                                            $resolution = $null
                                        }

                                        if ($resolution)
                                        {
                                            $monitorInfo += "$mfgName $monitorName ($resolution)"
                                        }
                                        else
                                        {
                                            $monitorInfo += "$mfgName $monitorName"
                                        }
                                    }

                                    $systemInfo.Monitors = $monitorInfo -join ', '
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve monitor information: $($_.Exception.Message)"
                            }

                            # Get keyboard information
                            try
                            {
                                $keyboards = Get-CimInstance -ClassName Win32_Keyboard -ErrorAction Stop

                                if ($keyboards)
                                {
                                    $keyboardInfo = @()
                                    foreach ($kb in $keyboards)
                                    {
                                        if ($kb.Description)
                                        {
                                            $keyboardInfo += $kb.Description
                                        }
                                    }

                                    if ($keyboardInfo.Count -gt 0)
                                    {
                                        $systemInfo.Keyboard = $keyboardInfo -join ', '
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve keyboard information: $($_.Exception.Message)"
                            }

                            # Get mouse information
                            try
                            {
                                $mice = Get-CimInstance -ClassName Win32_PointingDevice -ErrorAction Stop

                                if ($mice)
                                {
                                    $mouseInfo = @()
                                    foreach ($mouse in $mice)
                                    {
                                        if ($mouse.Name)
                                        {
                                            $mouseInfo += $mouse.Name
                                        }
                                    }

                                    if ($mouseInfo.Count -gt 0)
                                    {
                                        $systemInfo.Mouse = $mouseInfo -join ', '
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve mouse information: $($_.Exception.Message)"
                            }

                            # Get network adapter information (physical adapters only)
                            try
                            {
                                $netAdapters = Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop |
                                Where-Object {
                                    $_.PhysicalAdapter -eq $true -and
                                    $_.AdapterType -notmatch 'Tunnel|Loopback|Virtual' -and
                                    $_.Name -notmatch 'Virtual|Bluetooth|TAP|VPN'
                                }

                                if ($netAdapters)
                                {
                                    $networkInfo = @()
                                    foreach ($adapter in $netAdapters)
                                    {
                                        $adapterName = $adapter.Name
                                        $speed = $adapter.Speed

                                        if ($speed -and $speed -gt 0)
                                        {
                                            $speedMbps = [Math]::Round($speed / 1MB, 0)
                                            $networkInfo += "$adapterName ($speedMbps Mbps)"
                                        }
                                        else
                                        {
                                            $networkInfo += $adapterName
                                        }
                                    }

                                    if ($networkInfo.Count -gt 0)
                                    {
                                        $systemInfo.NetworkAdapters = $networkInfo -join ', '
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve network adapter information: $($_.Exception.Message)"
                            }
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

                            # Detect hyperthreading/SMT
                            if ($cpuCores -and $cpuLogical)
                            {
                                $coresInt = [int]$cpuCores
                                $logicalInt = [int]$cpuLogical
                                if ($logicalInt -gt $coresInt)
                                {
                                    $systemInfo.HyperthreadingEnabled = $true
                                }
                                else
                                {
                                    $systemInfo.HyperthreadingEnabled = $false
                                }
                            }

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
                                $timeZone = [System.TimeZoneInfo]::Local
                                $isDst = $timeZone.IsDaylightSavingTime((Get-Date))
                                $offset = $timeZone.GetUtcOffset((Get-Date))
                                $offsetString = if ($offset.TotalHours -ge 0) { "+$($offset.Hours)" } else { "$($offset.Hours)" }

                                if ($isDst -and $timeZone.DaylightName)
                                {
                                    $systemInfo.TimeZone = "$($timeZone.DaylightName) (UTC$offsetString)"
                                }
                                else
                                {
                                    $systemInfo.TimeZone = "$($timeZone.StandardName) (UTC$offsetString)"
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve timezone: $($_.Exception.Message)"
                            }

                            # Get GPU information using system_profiler
                            try
                            {
                                $displayProfile = system_profiler SPDisplaysDataType 2>$null
                                if ($displayProfile)
                                {
                                    # Parse GPU chipset model
                                    $chipsetLines = $displayProfile | Select-String 'Chipset Model:'
                                    if ($chipsetLines)
                                    {
                                        $gpuInfo = @()
                                        foreach ($line in $chipsetLines)
                                        {
                                            $gpuName = ($line -replace '.*Chipset Model:\s*', '').Trim()

                                            # Try to get VRAM for this GPU
                                            # Find the line number and look for VRAM in subsequent lines
                                            $lineIndex = [array]::IndexOf($displayProfile, $line.Line)
                                            $vramLine = $displayProfile[($lineIndex + 1)..($lineIndex + 10)] |
                                            Select-String 'VRAM.*:' | Select-Object -First 1

                                            if ($vramLine)
                                            {
                                                $vramText = ($vramLine -replace '.*VRAM.*:\s*', '').Trim()
                                                # Extract numeric value and convert to GB
                                                if ($vramText -match '(\d+)\s*GB')
                                                {
                                                    $vramGB = [int]$matches[1]
                                                    $gpuInfo += "$gpuName ($vramGB GB)"
                                                }
                                                elseif ($vramText -match '(\d+)\s*MB')
                                                {
                                                    $vramMB = [int]$matches[1]
                                                    $vramGB = [Math]::Round($vramMB / 1024, 2)
                                                    $gpuInfo += "$gpuName ($vramGB GB)"
                                                }
                                                else
                                                {
                                                    $gpuInfo += "$gpuName ($vramText)"
                                                }
                                            }
                                            else
                                            {
                                                $gpuInfo += $gpuName
                                            }
                                        }

                                        $systemInfo.GPUName = $gpuInfo -join ', '
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve GPU information: $($_.Exception.Message)"
                            }

                            # Get physical disk information using diskutil (embedded drives only)
                            try
                            {
                                $diskList = diskutil list 2>$null
                                if ($diskList)
                                {
                                    $diskInfo = @()

                                    # Parse disk list to find physical disks (disk0, disk1, etc., but not external)
                                    $currentDisk = $null
                                    foreach ($line in $diskList)
                                    {
                                        # Match disk identifiers like /dev/disk0
                                        if ($line -match '/dev/(disk\d+)\s+\(([^)]+)\)')
                                        {
                                            $diskId = $matches[1]
                                            $diskType = $matches[2]

                                            # Skip external/removable drives
                                            if ($diskType -notmatch 'external|removable')
                                            {
                                                $currentDisk = $diskId

                                                # Get detailed disk info
                                                $diskInfo_detailed = diskutil info $diskId 2>$null
                                                if ($diskInfo_detailed)
                                                {
                                                    $deviceName = $diskInfo_detailed | Select-String 'Device / Media Name:' |
                                                    ForEach-Object { ($_ -replace '.*Device / Media Name:\s*', '').Trim() }

                                                    $diskSize = $diskInfo_detailed | Select-String 'Disk Size:' |
                                                    ForEach-Object { ($_ -replace '.*Disk Size:\s*', '').Trim() }

                                                    $protocol = $diskInfo_detailed | Select-String 'Protocol:' |
                                                    ForEach-Object { ($_ -replace '.*Protocol:\s*', '').Trim() }

                                                    if ($deviceName -and $diskSize)
                                                    {
                                                        # Extract size in GB from the size string (e.g., "500.1 GB")
                                                        if ($diskSize -match '([\d.]+)\s*GB')
                                                        {
                                                            $sizeGB = [Math]::Round([double]$matches[1], 2)
                                                            if ($protocol)
                                                            {
                                                                $diskInfo += "$deviceName ($sizeGB GB, $protocol)"
                                                            }
                                                            else
                                                            {
                                                                $diskInfo += "$deviceName ($sizeGB GB)"
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    if ($diskInfo.Count -gt 0)
                                    {
                                        $systemInfo.PhysicalDisks = $diskInfo -join ', '
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve physical disk information: $($_.Exception.Message)"
                            }

                            # Get audio device information
                            try
                            {
                                $audioProfile = system_profiler SPAudioDataType 2>$null
                                if ($audioProfile)
                                {
                                    # Parse audio device names (look for device names under different categories)
                                    $deviceLines = $audioProfile | Select-String '^\s{4}\w.*:$' |
                                    Where-Object { $_ -notmatch 'Devices:|Audio ID' }

                                    if ($deviceLines)
                                    {
                                        $audioInfo = @()
                                        foreach ($line in $deviceLines)
                                        {
                                            $deviceName = ($line -replace ':\s*$', '').Trim()
                                            if ($deviceName -and $deviceName -notmatch '^(Input|Output)')
                                            {
                                                $audioInfo += $deviceName
                                            }
                                        }

                                        # Remove duplicates
                                        $audioInfo = $audioInfo | Select-Object -Unique

                                        if ($audioInfo.Count -gt 0)
                                        {
                                            $systemInfo.AudioDevices = $audioInfo -join ', '
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve audio device information: $($_.Exception.Message)"
                            }

                            # Get monitor/display information
                            try
                            {
                                $displayProfile = system_profiler SPDisplaysDataType 2>$null
                                if ($displayProfile)
                                {
                                    $monitorInfo = @()
                                    # Parse display information
                                    $displayLines = $displayProfile | Select-String '^\s{6}\w.*:$'

                                    foreach ($line in $displayLines)
                                    {
                                        $displayName = ($line -replace ':\s*$', '').Trim()

                                        # Get resolution for this display
                                        $lineIndex = [array]::IndexOf($displayProfile, $line.Line)
                                        $resolutionLine = $displayProfile[($lineIndex + 1)..($lineIndex + 10)] |
                                        Select-String 'Resolution:' | Select-Object -First 1

                                        if ($resolutionLine)
                                        {
                                            $resolution = ($resolutionLine -replace '.*Resolution:\s*', '').Trim()
                                            $monitorInfo += "$displayName ($resolution)"
                                        }
                                        else
                                        {
                                            $monitorInfo += $displayName
                                        }
                                    }

                                    if ($monitorInfo.Count -gt 0)
                                    {
                                        $systemInfo.Monitors = $monitorInfo -join ', '
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve monitor information: $($_.Exception.Message)"
                            }

                            # Get keyboard information
                            try
                            {
                                $usbProfile = system_profiler SPUSBDataType 2>$null
                                if ($usbProfile)
                                {
                                    $keyboardLines = $usbProfile | Select-String 'Keyboard'
                                    if ($keyboardLines)
                                    {
                                        $keyboardInfo = @()
                                        foreach ($line in $keyboardLines)
                                        {
                                            # Extract keyboard name
                                            if ($line -match '([^:]+Keyboard[^:]*):')
                                            {
                                                $kbName = $matches[1].Trim()
                                                if ($kbName -and $keyboardInfo -notcontains $kbName)
                                                {
                                                    $keyboardInfo += $kbName
                                                }
                                            }
                                        }

                                        if ($keyboardInfo.Count -gt 0)
                                        {
                                            $systemInfo.Keyboard = $keyboardInfo -join ', '
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve keyboard information: $($_.Exception.Message)"
                            }

                            # Get mouse/pointing device information
                            try
                            {
                                $usbProfile = system_profiler SPUSBDataType 2>$null
                                if ($usbProfile)
                                {
                                    $mouseLines = $usbProfile | Select-String 'Mouse|Trackpad|Pointing'
                                    if ($mouseLines)
                                    {
                                        $mouseInfo = @()
                                        foreach ($line in $mouseLines)
                                        {
                                            # Extract mouse/trackpad name
                                            if ($line -match '([^:]+(?:Mouse|Trackpad|Pointing)[^:]*):')
                                            {
                                                $mouseName = $matches[1].Trim()
                                                if ($mouseName -and $mouseInfo -notcontains $mouseName)
                                                {
                                                    $mouseInfo += $mouseName
                                                }
                                            }
                                        }

                                        if ($mouseInfo.Count -gt 0)
                                        {
                                            $systemInfo.Mouse = $mouseInfo -join ', '
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve mouse information: $($_.Exception.Message)"
                            }

                            # Get network adapter information
                            try
                            {
                                $networkProfile = system_profiler SPNetworkDataType 2>$null
                                if ($networkProfile)
                                {
                                    $networkInfo = @()
                                    # Get Ethernet and Wi-Fi interfaces
                                    $interfaceLines = $networkProfile | Select-String '^\s{4}(Ethernet|Wi-Fi|Thunderbolt).*:$'

                                    foreach ($line in $interfaceLines)
                                    {
                                        $interfaceName = ($line -replace ':\s*$', '').Trim()

                                        # Try to get hardware info
                                        $lineIndex = [array]::IndexOf($networkProfile, $line.Line)
                                        $hardwareLine = $networkProfile[($lineIndex + 1)..($lineIndex + 10)] |
                                        Select-String 'Hardware:' | Select-Object -First 1

                                        if ($hardwareLine)
                                        {
                                            $hardware = ($hardwareLine -replace '.*Hardware:\s*', '').Trim()
                                            $networkInfo += "$interfaceName ($hardware)"
                                        }
                                        else
                                        {
                                            $networkInfo += $interfaceName
                                        }
                                    }

                                    if ($networkInfo.Count -gt 0)
                                    {
                                        $systemInfo.NetworkAdapters = $networkInfo -join ', '
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve network adapter information: $($_.Exception.Message)"
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

                                # Detect hyperthreading/SMT
                                if ($systemInfo.CPUCores -and $systemInfo.CPULogicalProcessors)
                                {
                                    if ($systemInfo.CPULogicalProcessors -gt $systemInfo.CPUCores)
                                    {
                                        $systemInfo.HyperthreadingEnabled = $true
                                    }
                                    else
                                    {
                                        $systemInfo.HyperthreadingEnabled = $false
                                    }
                                }
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
                                $timeZone = [System.TimeZoneInfo]::Local
                                $isDst = $timeZone.IsDaylightSavingTime((Get-Date))
                                $offset = $timeZone.GetUtcOffset((Get-Date))
                                $offsetString = if ($offset.TotalHours -ge 0) { "+$($offset.Hours)" } else { "$($offset.Hours)" }

                                if ($isDst -and $timeZone.DaylightName)
                                {
                                    $systemInfo.TimeZone = "$($timeZone.DaylightName) (UTC$offsetString)"
                                }
                                else
                                {
                                    $systemInfo.TimeZone = "$($timeZone.StandardName) (UTC$offsetString)"
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve timezone: $($_.Exception.Message)"
                            }

                            # Get GPU information using lspci (requires pciutils package)
                            try
                            {
                                $lspciAvailable = Get-Command lspci -ErrorAction SilentlyContinue
                                if ($lspciAvailable)
                                {
                                    $gpuDevices = lspci 2>$null | Select-String 'VGA|3D|Display'
                                    if ($gpuDevices)
                                    {
                                        $gpuInfo = @()
                                        foreach ($gpu in $gpuDevices)
                                        {
                                            # Extract GPU name from lspci output
                                            # Format: "00:02.0 VGA compatible controller: Intel Corporation Device"
                                            if ($gpu -match ':\s*(.+)')
                                            {
                                                $gpuName = $matches[1].Trim()
                                                # Clean up the name (remove "VGA compatible controller:" prefix)
                                                $gpuName = $gpuName -replace '^(VGA compatible controller|3D controller|Display controller):\s*', ''
                                                $gpuInfo += $gpuName
                                            }
                                        }

                                        if ($gpuInfo.Count -gt 0)
                                        {
                                            $systemInfo.GPUName = $gpuInfo -join ', '
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve GPU information: $($_.Exception.Message)"
                            }

                            # Get physical disk information using lsblk (embedded drives only)
                            try
                            {
                                $lsblkAvailable = Get-Command lsblk -ErrorAction SilentlyContinue
                                if ($lsblkAvailable)
                                {
                                    # Get block devices that are disks (not partitions) and not removable
                                    $diskList = lsblk -d -o NAME, SIZE, TYPE, TRAN, MODEL -n 2>$null |
                                    Where-Object { $_ -match '\bdisk\b' -and $_ -notmatch '\busb\b' }

                                    if ($diskList)
                                    {
                                        $diskInfo = @()
                                        foreach ($disk in $diskList)
                                        {
                                            # Parse lsblk output: NAME SIZE TYPE TRAN MODEL
                                            $parts = $disk -split '\s+' | Where-Object { $_ }
                                            if ($parts.Count -ge 3)
                                            {
                                                $diskSize = $parts[1]
                                                $diskTran = if ($parts.Count -ge 4) { $parts[3] } else { $null }
                                                $diskModel = if ($parts.Count -ge 5) { $parts[4..($parts.Count - 1)] -join ' ' } else { 'Unknown' }

                                                # Skip if transport is USB
                                                if ($diskTran -eq 'usb')
                                                {
                                                    continue
                                                }

                                                if ($diskTran)
                                                {
                                                    $diskInfo += "$diskModel ($diskSize, $diskTran)"
                                                }
                                                else
                                                {
                                                    $diskInfo += "$diskModel ($diskSize)"
                                                }
                                            }
                                        }

                                        if ($diskInfo.Count -gt 0)
                                        {
                                            $systemInfo.PhysicalDisks = $diskInfo -join ', '
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve physical disk information: $($_.Exception.Message)"
                            }

                            # Get audio device information using aplay (ALSA)
                            try
                            {
                                $aplayAvailable = Get-Command aplay -ErrorAction SilentlyContinue
                                if ($aplayAvailable)
                                {
                                    $audioDevices = aplay -l 2>$null | Select-String 'card \d+:'
                                    if ($audioDevices)
                                    {
                                        $audioInfo = @()
                                        foreach ($device in $audioDevices)
                                        {
                                            # Parse output: "card 0: PCH [HDA Intel PCH], device 0: ..."
                                            if ($device -match 'card \d+:\s*([^\[,]+)')
                                            {
                                                $audioName = $matches[1].Trim()
                                                if ($audioName -and $audioInfo -notcontains $audioName)
                                                {
                                                    $audioInfo += $audioName
                                                }
                                            }
                                        }

                                        if ($audioInfo.Count -gt 0)
                                        {
                                            $systemInfo.AudioDevices = $audioInfo -join ', '
                                        }
                                    }
                                }
                                else
                                {
                                    # Try PulseAudio as fallback
                                    $pacmdAvailable = Get-Command pactl -ErrorAction SilentlyContinue
                                    if ($pacmdAvailable)
                                    {
                                        $audioSinks = pactl list sinks short 2>$null
                                        if ($audioSinks)
                                        {
                                            $audioInfo = @()
                                            foreach ($sink in $audioSinks)
                                            {
                                                # Parse pactl output
                                                $parts = $sink -split '\t' | Where-Object { $_ }
                                                if ($parts.Count -ge 2)
                                                {
                                                    $sinkName = $parts[1]
                                                    if ($sinkName -and $audioInfo -notcontains $sinkName)
                                                    {
                                                        $audioInfo += $sinkName
                                                    }
                                                }
                                            }

                                            if ($audioInfo.Count -gt 0)
                                            {
                                                $systemInfo.AudioDevices = $audioInfo -join ', '
                                            }
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve audio device information: $($_.Exception.Message)"
                            }

                            # Get monitor/display information using xrandr
                            try
                            {
                                $xrandrAvailable = Get-Command xrandr -ErrorAction SilentlyContinue
                                if ($xrandrAvailable)
                                {
                                    $displayOutput = xrandr 2>$null
                                    if ($displayOutput)
                                    {
                                        $monitorInfo = @()
                                        $connectedDisplays = $displayOutput | Select-String ' connected'

                                        foreach ($display in $connectedDisplays)
                                        {
                                            # Parse xrandr output: "HDMI-1 connected 1920x1080+0+0 ..."
                                            if ($display -match '^(\S+)\s+connected\s+(?:primary\s+)?(\d+x\d+)')
                                            {
                                                $displayName = $matches[1]
                                                $resolution = $matches[2]
                                                $monitorInfo += "$displayName ($resolution)"
                                            }
                                            elseif ($display -match '^(\S+)\s+connected')
                                            {
                                                $displayName = $matches[1]
                                                $monitorInfo += $displayName
                                            }
                                        }

                                        if ($monitorInfo.Count -gt 0)
                                        {
                                            $systemInfo.Monitors = $monitorInfo -join ', '
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve monitor information: $($_.Exception.Message)"
                            }

                            # Get keyboard information
                            try
                            {
                                $xinputAvailable = Get-Command xinput -ErrorAction SilentlyContinue
                                if ($xinputAvailable)
                                {
                                    $inputDevices = xinput list 2>$null
                                    if ($inputDevices)
                                    {
                                        $keyboardLines = $inputDevices | Select-String 'keyboard|Keyboard'
                                        if ($keyboardLines)
                                        {
                                            $keyboardInfo = @()
                                            foreach ($line in $keyboardLines)
                                            {
                                                # Parse xinput output: "↳ Keyboard Name    id=X [slave keyboard (Y)]"
                                                if ($line -match '(?:↳\s+)?([^↳]+?)\s+id=\d+')
                                                {
                                                    $kbName = $matches[1].Trim()
                                                    if ($kbName -and $kbName -notmatch 'Virtual|XTEST' -and $keyboardInfo -notcontains $kbName)
                                                    {
                                                        $keyboardInfo += $kbName
                                                    }
                                                }
                                            }

                                            if ($keyboardInfo.Count -gt 0)
                                            {
                                                $systemInfo.Keyboard = $keyboardInfo -join ', '
                                            }
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve keyboard information: $($_.Exception.Message)"
                            }

                            # Get mouse/pointing device information
                            try
                            {
                                $xinputAvailable = Get-Command xinput -ErrorAction SilentlyContinue
                                if ($xinputAvailable)
                                {
                                    $inputDevices = xinput list 2>$null
                                    if ($inputDevices)
                                    {
                                        $pointerLines = $inputDevices | Select-String 'pointer|Mouse|Touchpad|Trackpad'
                                        if ($pointerLines)
                                        {
                                            $mouseInfo = @()
                                            foreach ($line in $pointerLines)
                                            {
                                                # Parse xinput output
                                                if ($line -match '(?:↳\s+)?([^↳]+?)\s+id=\d+')
                                                {
                                                    $mouseName = $matches[1].Trim()
                                                    if ($mouseName -and $mouseName -notmatch 'Virtual|XTEST|pointer' -and $mouseInfo -notcontains $mouseName)
                                                    {
                                                        $mouseInfo += $mouseName
                                                    }
                                                }
                                            }

                                            if ($mouseInfo.Count -gt 0)
                                            {
                                                $systemInfo.Mouse = $mouseInfo -join ', '
                                            }
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve mouse information: $($_.Exception.Message)"
                            }

                            # Get network adapter information
                            try
                            {
                                $ipAvailable = Get-Command ip -ErrorAction SilentlyContinue
                                if ($ipAvailable)
                                {
                                    # Get network interfaces
                                    $interfaceOutput = ip link show 2>$null
                                    if ($interfaceOutput)
                                    {
                                        $networkInfo = @()
                                        $interfaces = $interfaceOutput | Select-String '^\d+:\s+(\w+):' | ForEach-Object {
                                            if ($_ -match '^\d+:\s+(\w+):')
                                            {
                                                $matches[1]
                                            }
                                        }

                                        foreach ($interface in $interfaces)
                                        {
                                            # Skip virtual, loopback, and docker interfaces
                                            if ($interface -match '^(lo|docker|veth|br-|virbr)')
                                            {
                                                continue
                                            }

                                            # Get interface details
                                            $ethtoolAvailable = Get-Command ethtool -ErrorAction SilentlyContinue
                                            if ($ethtoolAvailable)
                                            {
                                                $speedInfo = ethtool $interface 2>$null | Select-String 'Speed:'
                                                if ($speedInfo -and $speedInfo -match 'Speed:\s*(\d+)Mb/s')
                                                {
                                                    $speed = $matches[1]
                                                    $networkInfo += "$interface ($speed Mbps)"
                                                }
                                                else
                                                {
                                                    $networkInfo += $interface
                                                }
                                            }
                                            else
                                            {
                                                $networkInfo += $interface
                                            }
                                        }

                                        if ($networkInfo.Count -gt 0)
                                        {
                                            $systemInfo.NetworkAdapters = $networkInfo -join ', '
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve network adapter information: $($_.Exception.Message)"
                            }
                        }
                        catch
                        {
                            Write-Warning "Failed to retrieve some Linux system information: $($_.Exception.Message)"
                        }
                    }

                    # Apply privacy filter if requested
                    if ($NoPII)
                    {
                        $systemInfo.PSObject.Properties.Remove('ComputerName')
                        $systemInfo.PSObject.Properties.Remove('HostName')
                        $systemInfo.PSObject.Properties.Remove('Domain')
                        $systemInfo.PSObject.Properties.Remove('IPAddresses')
                        $systemInfo.PSObject.Properties.Remove('SerialNumber')
                        $systemInfo.PSObject.Properties.Remove('BIOSVersion')
                        $systemInfo.PSObject.Properties.Remove('TimeZone')
                        $systemInfo.PSObject.Properties.Remove('LastBootTime')
                        $systemInfo.PSObject.Properties.Remove('Uptime')
                    }

                    # Remove null/empty properties if requested
                    if ($NoEmptyProps)
                    {
                        $propertiesToRemove = @()
                        foreach ($prop in $systemInfo.PSObject.Properties)
                        {
                            if ($null -eq $prop.Value -or
                                ($prop.Value -is [string] -and [string]::IsNullOrWhiteSpace($prop.Value)))
                            {
                                $propertiesToRemove += $prop.Name
                            }
                        }

                        foreach ($propName in $propertiesToRemove)
                        {
                            $systemInfo.PSObject.Properties.Remove($propName)
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
                            HyperthreadingEnabled = $null
                            CPUSpeedMHz = $null
                            GPUName = $null
                            GPUMemoryGB = $null
                            Monitors = $null
                            Keyboard = $null
                            Mouse = $null
                            NetworkAdapters = $null
                            TotalMemoryGB = $null
                            FreeMemoryGB = $null
                            SystemDriveTotalGB = $null
                            SystemDriveUsedGB = $null
                            SystemDriveFreeGB = $null
                            PhysicalDisks = $null
                            AudioDevices = $null
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
                            # Translate CPU architecture code to readable string
                            $cpuArchCode = $cpu.Architecture
                            $cpuArchString = switch ($cpuArchCode)
                            {
                                0 { 'x86' }
                                1 { 'MIPS' }
                                2 { 'Alpha' }
                                3 { 'PowerPC' }
                                5 { 'ARM' }
                                6 { 'ia64' }
                                9 { 'x64' }
                                12 { 'ARM64' }
                                default { "Unknown ($cpuArchCode)" }
                            }
                            $systemInfo.CPUArchitecture = $cpuArchString
                            $systemInfo.CPUName = $cpu.Name.Trim()
                            $systemInfo.CPUCores = $cpu.NumberOfCores
                            $systemInfo.CPULogicalProcessors = $cpu.NumberOfLogicalProcessors

                            # Detect hyperthreading/SMT (if logical processors > cores, HT is enabled)
                            if ($cpu.NumberOfLogicalProcessors -gt $cpu.NumberOfCores)
                            {
                                $systemInfo.HyperthreadingEnabled = $true
                            }
                            else
                            {
                                $systemInfo.HyperthreadingEnabled = $false
                            }

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

                            # Get time zone with DST awareness
                            $timeZone = [System.TimeZoneInfo]::Local
                            $isDst = $timeZone.IsDaylightSavingTime((Get-Date))
                            $offset = $timeZone.GetUtcOffset((Get-Date))
                            $offsetString = if ($offset.TotalHours -ge 0) { "+$($offset.Hours)" } else { "$($offset.Hours)" }

                            if ($isDst -and $timeZone.DaylightName)
                            {
                                $systemInfo.TimeZone = "$($timeZone.DaylightName) (UTC$offsetString)"
                            }
                            else
                            {
                                $systemInfo.TimeZone = "$($timeZone.StandardName) (UTC$offsetString)"
                            }

                            # Get video card information
                            try
                            {
                                $videoCards = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
                                Where-Object { $_.Status -eq 'OK' -or $_.Status -eq $null }

                                if ($videoCards)
                                {
                                    $gpuInfo = @()
                                    foreach ($gpu in $videoCards)
                                    {
                                        $gpuName = $gpu.Name
                                        $gpuMemoryBytes = $gpu.AdapterRAM

                                        if ($gpuMemoryBytes -and $gpuMemoryBytes -gt 0)
                                        {
                                            $gpuMemoryGB = [Math]::Round($gpuMemoryBytes / 1GB, 2)
                                            $gpuInfo += "$gpuName ($gpuMemoryGB GB)"
                                        }
                                        else
                                        {
                                            $gpuInfo += $gpuName
                                        }
                                    }

                                    $systemInfo.GPUName = $gpuInfo -join ', '

                                    # Set GPUMemoryGB to total memory if available
                                    $totalGpuMemory = ($videoCards | Where-Object { $_.AdapterRAM -gt 0 } |
                                        Measure-Object -Property AdapterRAM -Sum).Sum
                                    if ($totalGpuMemory -gt 0)
                                    {
                                        $systemInfo.GPUMemoryGB = [Math]::Round($totalGpuMemory / 1GB, 2)
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve video card information: $($_.Exception.Message)"
                            }

                            # Get physical disk information (embedded drives only - exclude USB/removable)
                            try
                            {
                                $physicalDisks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop |
                                Where-Object {
                                    $_.MediaType -notmatch 'Removable' -and
                                    $_.InterfaceType -notmatch 'USB' -and
                                    $_.Size -gt 0
                                }

                                if ($physicalDisks)
                                {
                                    $diskInfo = @()
                                    foreach ($disk in $physicalDisks)
                                    {
                                        $diskModel = $disk.Model
                                        $diskSizeGB = [Math]::Round($disk.Size / 1GB, 2)
                                        $diskInterface = $disk.InterfaceType

                                        $diskInfo += "$diskModel ($diskSizeGB GB, $diskInterface)"
                                    }

                                    $systemInfo.PhysicalDisks = $diskInfo -join ', '
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve physical disk information: $($_.Exception.Message)"
                            }

                            # Get audio device information
                            try
                            {
                                $audioDevices = Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction Stop |
                                Where-Object { $_.Status -eq 'OK' -or $_.Status -eq $null }

                                if ($audioDevices)
                                {
                                    $audioInfo = @()
                                    foreach ($audio in $audioDevices)
                                    {
                                        $audioInfo += $audio.Name
                                    }

                                    $systemInfo.AudioDevices = $audioInfo -join ', '
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve audio device information: $($_.Exception.Message)"
                            }

                            # Get monitor information
                            try
                            {
                                $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop

                                if ($monitors)
                                {
                                    $monitorInfo = @()
                                    foreach ($monitor in $monitors)
                                    {
                                        # Decode manufacturer name
                                        $mfgName = if ($monitor.ManufacturerName)
                                        {
                                            -join ($monitor.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
                                        }
                                        else { 'Unknown' }

                                        # Decode user-friendly name
                                        $monitorName = if ($monitor.UserFriendlyName)
                                        {
                                            -join ($monitor.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
                                        }
                                        else { 'Unknown Monitor' }

                                        # Get resolution using WMI
                                        try
                                        {
                                            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
                                            $screen = [System.Windows.Forms.Screen]::AllScreens | Select-Object -First 1
                                            $resolution = "$($screen.Bounds.Width)x$($screen.Bounds.Height)"
                                        }
                                        catch
                                        {
                                            $resolution = $null
                                        }

                                        if ($resolution)
                                        {
                                            $monitorInfo += "$mfgName $monitorName ($resolution)"
                                        }
                                        else
                                        {
                                            $monitorInfo += "$mfgName $monitorName"
                                        }
                                    }

                                    $systemInfo.Monitors = $monitorInfo -join ', '
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve monitor information: $($_.Exception.Message)"
                            }

                            # Get keyboard information
                            try
                            {
                                $keyboards = Get-CimInstance -ClassName Win32_Keyboard -ErrorAction Stop

                                if ($keyboards)
                                {
                                    $keyboardInfo = @()
                                    foreach ($kb in $keyboards)
                                    {
                                        if ($kb.Description)
                                        {
                                            $keyboardInfo += $kb.Description
                                        }
                                    }

                                    if ($keyboardInfo.Count -gt 0)
                                    {
                                        $systemInfo.Keyboard = $keyboardInfo -join ', '
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve keyboard information: $($_.Exception.Message)"
                            }

                            # Get mouse information
                            try
                            {
                                $mice = Get-CimInstance -ClassName Win32_PointingDevice -ErrorAction Stop

                                if ($mice)
                                {
                                    $mouseInfo = @()
                                    foreach ($mouse in $mice)
                                    {
                                        if ($mouse.Name)
                                        {
                                            $mouseInfo += $mouse.Name
                                        }
                                    }

                                    if ($mouseInfo.Count -gt 0)
                                    {
                                        $systemInfo.Mouse = $mouseInfo -join ', '
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve mouse information: $($_.Exception.Message)"
                            }

                            # Get network adapter information (physical adapters only)
                            try
                            {
                                $netAdapters = Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop |
                                Where-Object {
                                    $_.PhysicalAdapter -eq $true -and
                                    $_.AdapterType -notmatch 'Tunnel|Loopback|Virtual' -and
                                    $_.Name -notmatch 'Virtual|Bluetooth|TAP|VPN'
                                }

                                if ($netAdapters)
                                {
                                    $networkInfo = @()
                                    foreach ($adapter in $netAdapters)
                                    {
                                        $adapterName = $adapter.Name
                                        $speed = $adapter.Speed

                                        if ($speed -and $speed -gt 0)
                                        {
                                            $speedMbps = [Math]::Round($speed / 1MB, 0)
                                            $networkInfo += "$adapterName ($speedMbps Mbps)"
                                        }
                                        else
                                        {
                                            $networkInfo += $adapterName
                                        }
                                    }

                                    if ($networkInfo.Count -gt 0)
                                    {
                                        $systemInfo.NetworkAdapters = $networkInfo -join ', '
                                    }
                                }
                            }
                            catch
                            {
                                Write-Verbose "Could not retrieve network adapter information: $($_.Exception.Message)"
                            }
                        }
                        catch
                        {
                            Write-Warning "Failed to retrieve some system information: $($_.Exception.Message)"
                        }

                        return $systemInfo
                    }

                    if ($remoteResults)
                    {
                        # Apply privacy filter if requested
                        if ($NoPII)
                        {
                            $remoteResults.PSObject.Properties.Remove('ComputerName')
                            $remoteResults.PSObject.Properties.Remove('HostName')
                            $remoteResults.PSObject.Properties.Remove('Domain')
                            $remoteResults.PSObject.Properties.Remove('IPAddresses')
                            $remoteResults.PSObject.Properties.Remove('SerialNumber')
                            $remoteResults.PSObject.Properties.Remove('BIOSVersion')
                            $remoteResults.PSObject.Properties.Remove('TimeZone')
                            $remoteResults.PSObject.Properties.Remove('LastBootTime')
                            $remoteResults.PSObject.Properties.Remove('Uptime')
                        }

                        # Remove null/empty properties if requested
                        if ($NoEmptyProps)
                        {
                            $propertiesToRemove = @()
                            foreach ($prop in $remoteResults.PSObject.Properties)
                            {
                                if ($null -eq $prop.Value -or
                                    ($prop.Value -is [string] -and [string]::IsNullOrWhiteSpace($prop.Value)))
                                {
                                    $propertiesToRemove += $prop.Name
                                }
                            }

                            foreach ($propName in $propertiesToRemove)
                            {
                                $remoteResults.PSObject.Properties.Remove($propName)
                            }
                        }

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
