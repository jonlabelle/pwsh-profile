function Test-PendingReboot
{
    <#
    .SYNOPSIS
        Tests various registry values to see if the local computer is pending a reboot.

    .DESCRIPTION
        This function checks multiple registry locations to determine if a Windows system
        needs to be rebooted due to pending changes from Windows updates, component-based
        servicing, computer name changes, domain joins, or other system modifications.

        The function is optimized for performance with dedicated local execution path that
        bypasses PowerShell remoting overhead when checking the local computer. For remote
        computers, it uses PowerShell remoting with proper session management.

        Registry locations checked include:
        - Component Based Servicing (RebootPending, RebootInProgress, PackagesPending)
        - Windows Update (RebootRequired, PostRebootReporting, Services\Pending)
        - Session Manager (PendingFileRenameOperations)
        - Computer name changes
        - Domain join operations
        - Server Manager reboot attempts

        NOTE: This function only works on Windows platforms as it relies on Windows-specific
        registry locations and Windows Update mechanisms. On macOS and Linux, use
        platform-specific methods to check for pending updates or reboots.

    .PARAMETER ComputerName
        The computer(s) to check for pending reboots. If not specified, the local computer is checked.
        This parameter accepts an array of computer names for checking multiple systems.

    .PARAMETER Credential
        The credentials to use when connecting to remote computers.
        Not required when checking the local computer.

    .EXAMPLE
        PS> Test-PendingReboot
        ComputerName PendingReboot Reason
        ------------ ------------- ------
        localhost               True Pending File Rename Operations

        Checks if the local computer has pending reboots and shows the reason.

    .EXAMPLE
        PS> Test-PendingReboot -ComputerName 'Server01', 'Server02'
        ComputerName PendingReboot Reason
        ------------ ------------- ------
        Server01                True Windows Update - Reboot Required
        Server02               False

        Checks if Server01 and Server02 have pending reboots and shows the reasons.

    .EXAMPLE
        PS> Test-PendingReboot -ComputerName 'Server01' -Credential (Get-Credential)
        ComputerName PendingReboot Reason
        ------------ ------------- ------
        Server01                True Component Based Servicing - Packages Pending

        Checks if Server01 has pending reboots using the provided credentials.

    .EXAMPLE
        PS> Test-PendingReboot -Verbose
        VERBOSE: Pending reboot detected: Registry key exists - HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager
        VERBOSE: Pending reboot detected: PendingFileRenameOperations exists

        ComputerName PendingReboot Reason
        ------------ ------------- ------
        localhost               True Pending File Rename Operations

        Checks the local computer with verbose output showing which conditions triggered the pending reboot detection.

    .EXAMPLE
        PS> Test-PendingReboot -ComputerName 'NonExistentServer'
        Write-Error: Failed to check pending reboot status for 'NonExistentServer': [WinRM cannot complete the operation...]

        ComputerName       PendingReboot Reason
        ------------       ------------- ------
        NonExistentServer

        Shows error handling when a computer cannot be reached. Both PendingReboot and Reason will be $null for failed connections.

    .OUTPUTS
        PSCustomObject
        Returns a PSCustomObject for each computer with the following properties:
        - ComputerName: [string] The name of the computer that was checked
        - PendingReboot: [bool] True if a reboot is pending, False if not, $null if an error occurred
        - Reason: [string] Descriptive reason(s) why a reboot is pending, $null if no reboot needed or error occurred

    .NOTES
        Author: Based on inspiration from Adam Bertram
        Version: 3.0 (Enhanced with Reason Detection)

        Inspiration from: https://gallery.technet.microsoft.com/scriptcenter/Get-PendingReboot-Query-bdb79542

        Performance Optimizations:
        - Local execution bypasses PowerShell remoting overhead for significant performance gains
        - Streamlined registry checking with better error handling
        - Proper session management for remote connections
        - Individual error handling prevents one failed check from stopping all checks

        Enhanced Features:
        - Returns specific reasons for pending reboots for better troubleshooting
        - Multiple reasons are concatenated with semicolon separator
        - Detailed verbose output shows exactly which conditions were detected

        This function only works on Windows systems as it relies on Windows registry checks.
        On macOS, check for pending updates with 'softwareupdate -l' or system preferences.
        On Linux, check with package managers like 'apt list --upgradable' or '/var/run/reboot-required'.

        Error Handling:
        - Returns PendingReboot = $null when a computer cannot be reached
        - Returns Reason = $null when no reboot needed or error occurred
        - Individual registry checks are wrapped in try-catch blocks for resilience
        - Verbose output shows exactly which condition triggered pending reboot detection

    .LINK
        https://github.com/adbertram/Random-PowerShell-Work/blob/master/Random%20Stuff/Test-PendingReboot.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # ComputerName is optional. If not specified, localhost is used.
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$Credential
    )

    # Check if running on Windows - simplified platform detection
    $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { $IsWindows }

    if (-not $isWindowsPlatform)
    {
        $platformName = if ($PSVersionTable.PSVersion.Major -ge 6 -and $IsMacOS) { 'macOS' }
        elseif ($PSVersionTable.PSVersion.Major -ge 6 -and $IsLinux) { 'Linux' }
        else { 'this platform' }
        throw "Test-PendingReboot is only supported on Windows. On $platformName, use platform-specific methods to check for pending updates or required reboots."
    }

    $ErrorActionPreference = 'Stop'

    # Optimized function to test for pending reboots locally
    function Test-LocalPendingReboot
    {
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param()

        $reasons = @()

        # Registry paths that indicate pending reboot
        $regPaths = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'; Reason = 'Component Based Servicing - Reboot Pending' }
            @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'; Reason = 'Component Based Servicing - Reboot In Progress' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'; Reason = 'Windows Update - Reboot Required' }
            @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'; Reason = 'Component Based Servicing - Packages Pending' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting'; Reason = 'Windows Update - Post Reboot Reporting' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttempts'; Reason = 'Server Manager - Reboot Attempts' }
        )

        # Check for registry keys that indicate pending reboot
        foreach ($regPath in $regPaths)
        {
            if (Test-Path -Path $regPath.Path -PathType Container)
            {
                Write-Verbose "Pending reboot detected: Registry key exists - $($regPath.Path)"
                $reasons += $regPath.Reason
            }
        }

        # Check for pending file rename operations
        try
        {
            $sessionManager = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
            $pendingOps = @(
                @{ Name = 'PendingFileRenameOperations'; Reason = 'Pending File Rename Operations' }
                @{ Name = 'PendingFileRenameOperations2'; Reason = 'Pending File Rename Operations 2' }
            )

            foreach ($op in $pendingOps)
            {
                $value = Get-ItemProperty -Path $sessionManager -Name $op.Name -ErrorAction SilentlyContinue
                if ($value -and $value.($op.Name))
                {
                    Write-Verbose "Pending reboot detected: $($op.Name) exists"
                    $reasons += $op.Reason
                }
            }
        }
        catch
        {
            Write-Verbose "Could not check pending file operations: $($_.Exception.Message)"
        }

        # Check for Windows Update volatile operations
        try
        {
            $updatesPath = 'HKLM:\SOFTWARE\Microsoft\Updates'
            if (Test-Path $updatesPath -PathType Container)
            {
                $volatilePath = Join-Path $updatesPath 'UpdateExeVolatile'
                if (Test-Path $volatilePath)
                {
                    $volatileValue = Get-ItemProperty -Path $updatesPath -Name 'UpdateExeVolatile' -ErrorAction SilentlyContinue
                    if ($volatileValue -and $volatileValue.UpdateExeVolatile -ne 0)
                    {
                        Write-Verbose "Pending reboot detected: UpdateExeVolatile = $($volatileValue.UpdateExeVolatile)"
                        $reasons += 'Windows Update - Volatile Operations'
                    }
                }
            }
        }
        catch
        {
            Write-Verbose "Could not check Windows Update volatile operations: $($_.Exception.Message)"
        }

        # Check for registry values that indicate pending operations
        $registryChecks = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Value = 'DVDRebootSignal'; Reason = 'DVD Reboot Signal' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon'; Value = 'JoinDomain'; Reason = 'Domain Join Operations' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon'; Value = 'AvoidSpnSet'; Reason = 'Netlogon SPN Operations' }
        )

        foreach ($check in $registryChecks)
        {
            try
            {
                if (Get-ItemProperty -Path $check.Path -Name $check.Value -ErrorAction SilentlyContinue)
                {
                    Write-Verbose "Pending reboot detected: Registry value exists - $($check.Path)\$($check.Value)"
                    $reasons += $check.Reason
                }
            }
            catch
            {
                Write-Verbose "Could not check registry path $($check.Path): $($_.Exception.Message)"
            }
        }

        # Check for computer name changes
        try
        {
            $activeComputer = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name 'ComputerName' -ErrorAction SilentlyContinue
            $pendingComputer = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name 'ComputerName' -ErrorAction SilentlyContinue

            if ($activeComputer -and $pendingComputer -and ($activeComputer.ComputerName -ne $pendingComputer.ComputerName))
            {
                Write-Verbose "Pending reboot detected: Computer name change from '$($activeComputer.ComputerName)' to '$($pendingComputer.ComputerName)'"
                $reasons += "Computer Name Change ($($activeComputer.ComputerName) -> $($pendingComputer.ComputerName))"
            }
        }
        catch
        {
            Write-Verbose "Could not check computer name changes: $($_.Exception.Message)"
        }

        # Check for pending Windows Update services
        try
        {
            $pendingServicesPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending'
            if ((Test-Path $pendingServicesPath -PathType Container) -and (Get-ChildItem -Path $pendingServicesPath -ErrorAction SilentlyContinue))
            {
                Write-Verbose 'Pending reboot detected: Windows Update services pending'
                $reasons += 'Windows Update - Services Pending'
            }
        }
        catch
        {
            Write-Verbose "Could not check Windows Update pending services: $($_.Exception.Message)"
        }

        # Return result with reasons
        return [PSCustomObject]@{
            PendingReboot = $reasons.Count -gt 0
            Reason = if ($reasons.Count -gt 0) { $reasons -join '; ' } else { $null }
        }
    }

    # Remote scriptblock for PS remoting
    $remoteScriptBlock = {
        $reasons = @()

        # Registry paths that indicate pending reboot
        $regPaths = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'; Reason = 'Component Based Servicing - Reboot Pending' }
            @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'; Reason = 'Component Based Servicing - Reboot In Progress' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'; Reason = 'Windows Update - Reboot Required' }
            @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'; Reason = 'Component Based Servicing - Packages Pending' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting'; Reason = 'Windows Update - Post Reboot Reporting' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttempts'; Reason = 'Server Manager - Reboot Attempts' }
        )

        # Check for registry keys that indicate pending reboot
        foreach ($regPath in $regPaths)
        {
            if (Test-Path -Path $regPath.Path -PathType Container)
            {
                Write-Verbose "Pending reboot detected: Registry key exists - $($regPath.Path)"
                $reasons += $regPath.Reason
            }
        }

        # Check for pending file rename operations
        try
        {
            $sessionManager = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
            $pendingOps = @(
                @{ Name = 'PendingFileRenameOperations'; Reason = 'Pending File Rename Operations' }
                @{ Name = 'PendingFileRenameOperations2'; Reason = 'Pending File Rename Operations 2' }
            )

            foreach ($op in $pendingOps)
            {
                $value = Get-ItemProperty -Path $sessionManager -Name $op.Name -ErrorAction SilentlyContinue
                if ($value -and $value.($op.Name))
                {
                    Write-Verbose "Pending reboot detected: $($op.Name) exists"
                    $reasons += $op.Reason
                }
            }
        }
        catch
        {
            Write-Verbose "Could not check pending file operations: $($_.Exception.Message)"
        }

        # Check for Windows Update volatile operations
        try
        {
            $updatesPath = 'HKLM:\SOFTWARE\Microsoft\Updates'
            if (Test-Path $updatesPath -PathType Container)
            {
                $volatilePath = Join-Path $updatesPath 'UpdateExeVolatile'
                if (Test-Path $volatilePath)
                {
                    $volatileValue = Get-ItemProperty -Path $updatesPath -Name 'UpdateExeVolatile' -ErrorAction SilentlyContinue
                    if ($volatileValue -and $volatileValue.UpdateExeVolatile -ne 0)
                    {
                        Write-Verbose "Pending reboot detected: UpdateExeVolatile = $($volatileValue.UpdateExeVolatile)"
                        $reasons += 'Windows Update - Volatile Operations'
                    }
                }
            }
        }
        catch
        {
            Write-Verbose "Could not check Windows Update volatile operations: $($_.Exception.Message)"
        }

        # Check for registry values that indicate pending operations
        $registryChecks = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Value = 'DVDRebootSignal'; Reason = 'DVD Reboot Signal' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon'; Value = 'JoinDomain'; Reason = 'Domain Join Operations' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon'; Value = 'AvoidSpnSet'; Reason = 'Netlogon SPN Operations' }
        )

        foreach ($check in $registryChecks)
        {
            try
            {
                if (Get-ItemProperty -Path $check.Path -Name $check.Value -ErrorAction SilentlyContinue)
                {
                    Write-Verbose "Pending reboot detected: Registry value exists - $($check.Path)\$($check.Value)"
                    $reasons += $check.Reason
                }
            }
            catch
            {
                Write-Verbose "Could not check registry path $($check.Path): $($_.Exception.Message)"
            }
        }

        # Check for computer name changes
        try
        {
            $activeComputer = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name 'ComputerName' -ErrorAction SilentlyContinue
            $pendingComputer = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name 'ComputerName' -ErrorAction SilentlyContinue

            if ($activeComputer -and $pendingComputer -and ($activeComputer.ComputerName -ne $pendingComputer.ComputerName))
            {
                Write-Verbose "Pending reboot detected: Computer name change from '$($activeComputer.ComputerName)' to '$($pendingComputer.ComputerName)'"
                $reasons += "Computer Name Change ($($activeComputer.ComputerName) -> $($pendingComputer.ComputerName))"
            }
        }
        catch
        {
            Write-Verbose "Could not check computer name changes: $($_.Exception.Message)"
        }

        # Check for pending Windows Update services
        try
        {
            $pendingServicesPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending'
            if ((Test-Path $pendingServicesPath -PathType Container) -and (Get-ChildItem -Path $pendingServicesPath -ErrorAction SilentlyContinue))
            {
                Write-Verbose 'Pending reboot detected: Windows Update services pending'
                $reasons += 'Windows Update - Services Pending'
            }
        }
        catch
        {
            Write-Verbose "Could not check Windows Update pending services: $($_.Exception.Message)"
        }

        # Return result with reasons
        return [PSCustomObject]@{
            PendingReboot = $reasons.Count -gt 0
            Reason = if ($reasons.Count -gt 0) { $reasons -join '; ' } else { $null }
        }
    }

    # Default to localhost if no ComputerName specified
    if (-not $ComputerName)
    {
        $ComputerName = @('localhost')
    }

    foreach ($computer in $ComputerName)
    {
        try
        {
            $output = [PSCustomObject]@{
                ComputerName = $computer
                PendingReboot = $false
                Reason = $null
            }

            # Check if this is a local computer
            $isLocal = $computer -in @('.', 'localhost', $env:COMPUTERNAME, [System.Net.Dns]::GetHostName())

            if ($isLocal)
            {
                # Use optimized local function for better performance
                $result = Test-LocalPendingReboot
                $output.PendingReboot = $result.PendingReboot
                $output.Reason = $result.Reason
            }
            else
            {
                # Use PS remoting for remote computers
                $sessionParams = @{
                    ComputerName = $computer
                    ErrorAction = 'Stop'
                }

                if ($PSBoundParameters.ContainsKey('Credential'))
                {
                    $sessionParams.Credential = $Credential
                }

                $session = New-PSSession @sessionParams
                try
                {
                    $result = Invoke-Command -Session $session -ScriptBlock $remoteScriptBlock
                    $output.PendingReboot = $result.PendingReboot
                    $output.Reason = $result.Reason
                }
                finally
                {
                    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                }
            }

            $output
        }
        catch
        {
            Write-Error -Message "Failed to check pending reboot status for '$computer': $($_.Exception.Message)"

            # Return object with error indication
            [PSCustomObject]@{
                ComputerName = $computer
                PendingReboot = $null
                Reason = $null
            }
        }
    }
}
