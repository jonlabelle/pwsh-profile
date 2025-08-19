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
        Checks if the local computer has pending reboots.

    .EXAMPLE
        PS> Test-PendingReboot -ComputerName 'Server01', 'Server02'
        Checks if Server01 and Server02 have pending reboots.

    .EXAMPLE
        PS> Test-PendingReboot -ComputerName 'Server01' -Credential (Get-Credential)
        Checks if Server01 has pending reboots using the provided credentials.

    .EXAMPLE
        PS> Test-PendingReboot -Verbose
        VERBOSE: Pending reboot detected: PendingFileRenameOperations exists

        ComputerName IsPendingReboot
        ------------ ---------------
        localhost               True

        Checks the local computer with verbose output showing which condition triggered the pending reboot detection.

    .EXAMPLE
        PS> Test-PendingReboot -ComputerName 'NonExistentServer'
        Write-Error: Failed to check pending reboot status for 'NonExistentServer': [WinRM cannot complete the operation...]

        ComputerName       IsPendingReboot
        ------------       ---------------
        NonExistentServer

        Shows error handling when a computer cannot be reached. The IsPendingReboot property will be $null for failed connections.

    .OUTPUTS
        PSCustomObject
        Returns a PSCustomObject for each computer with the following properties:
        - ComputerName: [string] The name of the computer that was checked
        - IsPendingReboot: [bool] True if a reboot is pending, False if not, $null if an error occurred

    .NOTES
        Author: Based on inspiration from Adam Bertram
        Version: 2.0 (Optimized)

        Inspiration from: https://gallery.technet.microsoft.com/scriptcenter/Get-PendingReboot-Query-bdb79542

        Performance Optimizations:
        - Local execution bypasses PowerShell remoting overhead for significant performance gains
        - Streamlined registry checking with better error handling
        - Proper session management for remote connections
        - Individual error handling prevents one failed check from stopping all checks

        This function only works on Windows systems as it relies on Windows registry checks.
        On macOS, check for pending updates with 'softwareupdate -l' or system preferences.
        On Linux, check with package managers like 'apt list --upgradable' or '/var/run/reboot-required'.

        Error Handling:
        - Returns IsPendingReboot = $null when a computer cannot be reached
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
        [OutputType([bool])]
        param()

        # Registry paths that indicate pending reboot
        $regPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting'
            'HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttempts'
        )

        # Check for registry keys that indicate pending reboot
        foreach ($path in $regPaths)
        {
            if (Test-Path -Path $path -PathType Container)
            {
                Write-Verbose "Pending reboot detected: Registry key exists - $path"
                return $true
            }
        }

        # Check for pending file rename operations
        try
        {
            $sessionManager = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
            $pendingOps = @('PendingFileRenameOperations', 'PendingFileRenameOperations2')

            foreach ($op in $pendingOps)
            {
                $value = Get-ItemProperty -Path $sessionManager -Name $op -ErrorAction SilentlyContinue
                if ($value -and $value.$op)
                {
                    Write-Verbose "Pending reboot detected: $op exists"
                    return $true
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
                        return $true
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
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Value = 'DVDRebootSignal' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon'; Value = 'JoinDomain' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon'; Value = 'AvoidSpnSet' }
        )

        foreach ($check in $registryChecks)
        {
            try
            {
                if (Get-ItemProperty -Path $check.Path -Name $check.Value -ErrorAction SilentlyContinue)
                {
                    Write-Verbose "Pending reboot detected: Registry value exists - $($check.Path)\$($check.Value)"
                    return $true
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
                return $true
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
                return $true
            }
        }
        catch
        {
            Write-Verbose "Could not check Windows Update pending services: $($_.Exception.Message)"
        }

        return $false
    }

    # Remote scriptblock for PS remoting
    $remoteScriptBlock = {
        # Registry paths that indicate pending reboot
        $regPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting'
            'HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttempts'
        )

        # Check for registry keys that indicate pending reboot
        foreach ($path in $regPaths)
        {
            if (Test-Path -Path $path -PathType Container)
            {
                Write-Verbose "Pending reboot detected: Registry key exists - $path"
                return $true
            }
        }

        # Check for pending file rename operations
        try
        {
            $sessionManager = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
            $pendingOps = @('PendingFileRenameOperations', 'PendingFileRenameOperations2')

            foreach ($op in $pendingOps)
            {
                $value = Get-ItemProperty -Path $sessionManager -Name $op -ErrorAction SilentlyContinue
                if ($value -and $value.$op)
                {
                    Write-Verbose "Pending reboot detected: $op exists"
                    return $true
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
                        return $true
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
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Value = 'DVDRebootSignal' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon'; Value = 'JoinDomain' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon'; Value = 'AvoidSpnSet' }
        )

        foreach ($check in $registryChecks)
        {
            try
            {
                if (Get-ItemProperty -Path $check.Path -Name $check.Value -ErrorAction SilentlyContinue)
                {
                    Write-Verbose "Pending reboot detected: Registry value exists - $($check.Path)\$($check.Value)"
                    return $true
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
                return $true
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
                return $true
            }
        }
        catch
        {
            Write-Verbose "Could not check Windows Update pending services: $($_.Exception.Message)"
        }

        return $false
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
                IsPendingReboot = $false
            }

            # Check if this is a local computer
            $isLocal = $computer -in @('.', 'localhost', $env:COMPUTERNAME, [System.Net.Dns]::GetHostName())

            if ($isLocal)
            {
                # Use optimized local function for better performance
                $output.IsPendingReboot = Test-LocalPendingReboot
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
                    $output.IsPendingReboot = Invoke-Command -Session $session -ScriptBlock $remoteScriptBlock
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
                IsPendingReboot = $null
            }
        }
    }
}
