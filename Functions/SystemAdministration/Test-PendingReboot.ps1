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
        - SCCM/ConfigMgr client reboot state (CCM_ClientUtilities)
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
        PS > Test-PendingReboot

        ComputerName PendingReboot Reason
        ------------ ------------- ------
        localhost               True Pending File Rename Operations

        Checks if the local computer has pending reboots and shows the reason.

    .EXAMPLE
        PS > Test-PendingReboot -ComputerName 'Server01', 'Server02'

        ComputerName PendingReboot Reason
        ------------ ------------- ------
        Server01                True Windows Update - Reboot Required
        Server02               False

        Checks if Server01 and Server02 have pending reboots and shows the reasons.

    .EXAMPLE
        PS > Test-PendingReboot -ComputerName 'Server01' -Credential (Get-Credential)

        ComputerName PendingReboot Reason
        ------------ ------------- ------
        Server01                True Component Based Servicing - Packages Pending

        Checks if Server01 has pending reboots using the provided credentials.

    .EXAMPLE
        PS > Test-PendingReboot -Verbose

        VERBOSE: Pending reboot detected: Registry key exists - HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager
        VERBOSE: Pending reboot detected: PendingFileRenameOperations exists

        ComputerName PendingReboot Reason
        ------------ ------------- ------
        localhost               True Pending File Rename Operations

        Checks the local computer with verbose output showing which conditions triggered the pending reboot detection.

    .EXAMPLE
        PS > Test-PendingReboot -ComputerName 'NonExistentServer'

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
        Based on inspiration from Adam Bertram
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

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Test-PendingReboot.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Test-PendingReboot.ps1

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

    # Shared scriptblock for both local and remote execution
    $pendingRebootCheckScriptBlock = {
        param(
            [bool]$EnableVerbose = $false
        )

        if ($EnableVerbose)
        {
            $VerbosePreference = 'Continue'
        }

        $reasons = @()

        function Test-RegistryValuePresent
        {
            param(
                [Parameter(Mandatory = $true)]
                [string]$Path,

                [Parameter(Mandatory = $true)]
                [string]$Name
            )

            try
            {
                $registryValue = Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop
            }
            catch
            {
                return $false
            }

            if ($null -eq $registryValue)
            {
                return $false
            }

            if ($registryValue -is [string])
            {
                return -not [string]::IsNullOrWhiteSpace($registryValue)
            }

            if ($registryValue -is [System.Array])
            {
                $nonEmpty = @($registryValue | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                return $nonEmpty.Count -gt 0
            }

            return $true
        }

        # Registry paths that indicate pending reboot
        $regPaths = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'; Reason = 'Component Based Servicing - Reboot Pending' }
            @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'; Reason = 'Component Based Servicing - Reboot In Progress' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'; Reason = 'Windows Update - Reboot Required' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting'; Reason = 'Windows Update - Post Reboot Reporting' }
            @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'; Reason = 'Component Based Servicing - Packages Pending' }
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

        # Check for Windows Update Services Pending (requires child subkeys - empty container is not a pending reboot)
        try
        {
            $servicesPendingPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending'
            if (Test-Path -Path $servicesPendingPath -PathType Container)
            {
                $pendingServices = @(Get-ChildItem -Path $servicesPendingPath -ErrorAction SilentlyContinue)
                if ($pendingServices.Count -gt 0)
                {
                    Write-Verbose "Pending reboot detected: Windows Update Services\Pending has $($pendingServices.Count) pending service(s)"
                    $reasons += 'Windows Update - Services Pending'
                }
            }
        }
        catch
        {
            Write-Verbose "Could not check Windows Update Services Pending: $($_.Exception.Message)"
        }

        # Check for pending file rename operations
        # PendingFileRenameOperations is a REG_MULTI_SZ with pairs of strings:
        #   even-indexed: source path (prefixed with \??\)
        #   odd-indexed:  destination path (empty string means delete)
        # After a reboot, stale entries can remain for files that were already processed.
        # Only flag as pending if at least one source file still exists on disk.
        $sessionManager = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        $pendingOps = @(
            @{ Name = 'PendingFileRenameOperations'; Reason = 'Pending File Rename Operations' }
            @{ Name = 'PendingFileRenameOperations2'; Reason = 'Pending File Rename Operations 2' }
        )

        foreach ($pendingOperation in $pendingOps)
        {
            try
            {
                $entries = Get-ItemPropertyValue -Path $sessionManager -Name $pendingOperation.Name -ErrorAction Stop
            }
            catch
            {
                continue
            }

            if ($null -eq $entries) { continue }

            $hasRealPendingOp = $false
            for ($i = 0; $i -lt $entries.Count; $i += 2)
            {
                $source = $entries[$i]
                if ([string]::IsNullOrWhiteSpace($source)) { continue }

                # Strip \??\ device path prefix to get a usable filesystem path
                $filePath = $source -replace '^\\\?\?\\', ''
                if (Test-Path -Path $filePath -PathType Leaf)
                {
                    $hasRealPendingOp = $true
                    break
                }
            }

            if ($hasRealPendingOp)
            {
                Write-Verbose "Pending reboot detected: $($pendingOperation.Name) has active file operations"
                $reasons += $pendingOperation.Reason
            }
            else
            {
                Write-Verbose "Skipping $($pendingOperation.Name): all referenced source files no longer exist on disk (stale entries)"
            }
        }

        # Check for Windows Update volatile operations
        try
        {
            $updatesPath = 'HKLM:\SOFTWARE\Microsoft\Updates'
            if (Test-Path $updatesPath -PathType Container)
            {
                $volatileValue = Get-ItemPropertyValue -Path $updatesPath -Name 'UpdateExeVolatile' -ErrorAction SilentlyContinue
                $volatileInt = 0
                if ($null -ne $volatileValue -and [int]::TryParse("$volatileValue", [ref]$volatileInt) -and $volatileInt -ne 0)
                {
                    Write-Verbose "Pending reboot detected: UpdateExeVolatile = $volatileInt"
                    $reasons += 'Windows Update - Volatile Operations'
                }
            }
        }
        catch
        {
            Write-Verbose "Could not check Windows Update volatile operations: $($_.Exception.Message)"
        }

        # Check for Server Manager reboot attempts (only when attempts is a non-zero value)
        try
        {
            $serverManagerPath = 'HKLM:\SOFTWARE\Microsoft\ServerManager'
            if (Test-Path $serverManagerPath -PathType Container)
            {
                $currentRebootAttempts = Get-ItemPropertyValue -Path $serverManagerPath -Name 'CurrentRebootAttempts' -ErrorAction SilentlyContinue
                $attemptsInt = 0
                if ($null -ne $currentRebootAttempts -and [int]::TryParse("$currentRebootAttempts", [ref]$attemptsInt) -and $attemptsInt -gt 0)
                {
                    Write-Verbose "Pending reboot detected: Server Manager reboot attempts = $attemptsInt"
                    $reasons += 'Server Manager - Reboot Attempts'
                }
            }
        }
        catch
        {
            Write-Verbose "Could not check Server Manager reboot attempts: $($_.Exception.Message)"
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
                if (Test-RegistryValuePresent -Path $check.Path -Name $check.Value)
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

        # Check for SCCM/ConfigMgr client reboot state
        try
        {
            $ccmResult = $null

            if (Get-Command -Name Invoke-CimMethod -ErrorAction SilentlyContinue)
            {
                $ccmResult = Invoke-CimMethod -Namespace 'ROOT\ccm\ClientSDK' -ClassName 'CCM_ClientUtilities' -MethodName 'DetermineIfRebootPending' -ErrorAction SilentlyContinue
            }

            if (-not $ccmResult -and (Get-Command -Name Invoke-WmiMethod -ErrorAction SilentlyContinue))
            {
                $ccmResult = Invoke-WmiMethod -Namespace 'ROOT\ccm\ClientSDK' -Class 'CCM_ClientUtilities' -Name 'DetermineIfRebootPending' -ErrorAction SilentlyContinue
            }

            if ($ccmResult)
            {
                $softPending = $false
                $hardPending = $false

                if ($null -ne $ccmResult.PSObject.Properties['RebootPending'])
                {
                    $softPending = [bool]$ccmResult.RebootPending
                }

                if ($null -ne $ccmResult.PSObject.Properties['IsHardRebootPending'])
                {
                    $hardPending = [bool]$ccmResult.IsHardRebootPending
                }

                if ($softPending -or $hardPending)
                {
                    Write-Verbose "Pending reboot detected: SCCM reboot state (RebootPending=$softPending, IsHardRebootPending=$hardPending)"
                    $reasons += 'SCCM Client - Reboot Pending'
                }
            }
        }
        catch
        {
            Write-Verbose "Could not check SCCM reboot status: $($_.Exception.Message)"
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

        # Return result with reasons
        $uniqueReasons = $reasons | Select-Object -Unique
        return [PSCustomObject]@{
            PendingReboot = $uniqueReasons.Count -gt 0
            Reason = if ($uniqueReasons.Count -gt 0) { $uniqueReasons -join '; ' } else { $null }
        }
    }

    # Default to localhost if no ComputerName specified
    if (-not $ComputerName)
    {
        $ComputerName = @('localhost')
    }

    $isVerboseRequested = $PSBoundParameters.ContainsKey('Verbose')

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
                # Local execution without remoting overhead
                $result = & $pendingRebootCheckScriptBlock -EnableVerbose:$isVerboseRequested
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
                    $result = Invoke-Command -Session $session -ScriptBlock $pendingRebootCheckScriptBlock -ArgumentList $isVerboseRequested -Verbose:$isVerboseRequested
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
