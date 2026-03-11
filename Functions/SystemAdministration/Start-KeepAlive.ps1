function Start-KeepAlive
{
    <#
    .SYNOPSIS
        Prevents the system and display from sleeping.

    .DESCRIPTION
        This function runs a background job that prevents system sleep, screensaver activation,
        and session timeout by keeping the system active. Works cross-platform with automatic
        platform detection.

        PLATFORM COMPATIBILITY:
        This function works cross-platform with different implementations:

        - Windows: Uses WScript.Shell COM objects to simulate F15 key presses (default: every 60 seconds)
        - macOS: Uses the built-in 'caffeinate' command to prevent system sleep
        - Linux: Uses 'systemd-inhibit' if available, otherwise falls back to 'xdotool' for mouse activity simulation

        The function automatically detects the platform and uses the appropriate method.

    .PARAMETER KeepAliveHours
        The number of hours the keep-alive job will run.
        Valid range: 0.1 to 48 hours.
        Default is 12 hours.

    .PARAMETER SleepSeconds
        The number of seconds between each key-press.
        Valid range: 30 to 3600 seconds (30 seconds to 1 hour).
        Default is 60 seconds (1 minute).

    .PARAMETER JobName
        The name of the background job.
        Must be a valid job name (no special characters except hyphens and underscores).
        Default is 'KeepAlive'.

    .PARAMETER EndJob
        When specified, stops any running keep-alive job and removes it.
        Cannot be combined with other operational parameters.

    .PARAMETER Query
        When specified, displays the status of the keep-alive job and cleans up completed jobs.
        Cannot be combined with other operational parameters.

    .PARAMETER KeyToPress
        (Windows only) The key to simulate pressing. Uses WScript.Shell SendKeys syntax.
        Common options: '^' (Ctrl), '{TAB}', '{F15}' (non-interfering function key)
        Default is '{F15}' (F15 key - least likely to interfere with applications).
        Note that the {F15} key simulation is handled entirely by software, not hardware. The WScript.Shell.SendKeys() method sends a virtual keystroke to Windows, which doesn't require the physical key to exist.
        This parameter is ignored on macOS and Linux platforms.
        Reference: https://docs.microsoft.com/en-us/office/vba/language/reference/user-interface-help/sendkeys-statement

    .EXAMPLE
        PS > Start-KeepAlive

        Starts a keep-alive job that will run for 12 hours.
        On Windows: Simulates F15 key presses every 60 seconds
        On macOS: Uses caffeinate to prevent sleep
        On Linux: Uses systemd-inhibit or xdotool for activity simulation

    .EXAMPLE
        PS > Start-KeepAlive -KeepAliveHours 3 -SleepSeconds 300

        Starts a keep-alive job for 3 hours with activity every 5 minutes.
        Note: SleepSeconds is only used on Windows and Linux (with xdotool).
        macOS and Linux (with systemd-inhibit) run continuously.

    .EXAMPLE
        PS > Start-KeepAlive -KeyToPress '{TAB}'

        (Windows only) Starts a keep-alive job that simulates Tab key instead of F15.
        This parameter is ignored on macOS and Linux.

    .EXAMPLE
        PS > Start-KeepAlive -Query

        Displays the status of the current keep-alive job without starting a new one.
        Works on all platforms.

    .EXAMPLE
        PS > Start-KeepAlive -EndJob

        Stops the running keep-alive job and removes it from the job queue.
        Properly cleans up platform-specific processes (caffeinate on macOS,
        systemd-inhibit on Linux, COM objects on Windows).

    .EXAMPLE
        PS > Start-KeepAlive -JobName 'LongDownload' -KeepAliveHours 8

        Starts a custom-named keep-alive job for an 8-hour period.
        Useful when running multiple keep-alive jobs for different purposes.

    .EXAMPLE
        PS > Start-KeepAlive -KeepAliveHours 2 -Verbose

        Starts a keep-alive job with verbose output showing platform detection
        and initialization details. Useful for troubleshooting.

    .OUTPUTS
        System.Management.Automation.Job
        Returns a background job object when starting a new keep-alive job.

    .NOTES
        CLEANUP:
        Jobs are automatically cleaned up when they complete. For manual cleanup
        of orphaned jobs, use: Get-Job -Name $JobName | Remove-Job -Force

        PLATFORM REQUIREMENTS:
        - Windows: No additional requirements (uses built-in WScript.Shell COM object)
        - macOS: Uses built-in 'caffeinate' command (no additional installation required)
        - Linux: Requires either 'systemd-inhibit' (systemd-based systems) or 'xdotool' (X11 systems)
          Install on Debian/Ubuntu: sudo apt-get install xdotool
          Install on RHEL/Fedora: sudo dnf install xdotool
          Install on Arch: sudo pacman -S xdotool

        VERSION COMPATIBILITY:
        Compatible with PowerShell 5.1+ on Windows, PowerShell Core 6.2+ on macOS and Linux.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Start-KeepAlive.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Start-KeepAlive.ps1
    #>
    #
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '', Justification = '')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'EndJob', Justification = 'Switch parameter is used to select the End parameter set.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Query', Justification = 'Switch parameter is used to select the Query parameter set.')]
    [CmdletBinding(DefaultParameterSetName = 'Start')]
    [OutputType([System.Management.Automation.Job], ParameterSetName = 'Start')]
    [OutputType([System.Void], ParameterSetName = 'Query')]
    [OutputType([System.Void], ParameterSetName = 'End')]
    param (
        [Parameter(ParameterSetName = 'Start')]
        [ValidateRange(0.1, 48)]
        [Double]$KeepAliveHours = 12,

        [Parameter(ParameterSetName = 'Start')]
        [ValidateRange(30, 3600)]
        [Int32]$SleepSeconds = 60,

        [Parameter(ParameterSetName = 'Start')]
        [Parameter(ParameterSetName = 'Query')]
        [Parameter(ParameterSetName = 'End')]
        [ValidatePattern('^[a-zA-Z0-9_-]+$')]
        [ValidateLength(1, 50)]
        [String]$JobName = 'KeepAlive',

        [Parameter(Mandatory, ParameterSetName = 'End')]
        [Switch]$EndJob,

        [Parameter(Mandatory, ParameterSetName = 'Query')]
        [Switch]$Query,

        [Parameter(ParameterSetName = 'Start')]
        [ValidateNotNullOrEmpty()]
        [String]$KeyToPress = '{F15}' # F15 key - least likely to interfere with applications
    )

    begin
    {
        Write-Verbose "Starting Start-KeepAlive function with ParameterSet: $($PSCmdlet.ParameterSetName)"

        function Write-KeepAliveInfo
        {
            param (
                [Parameter(Mandatory)]
                [AllowEmptyString()]
                [String]$Message
            )

            Write-Information -MessageData $Message -InformationAction Continue
        }

        function Get-KeepAliveJobsByName
        {
            param (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Name
            )

            @(Get-Job -Name $Name -ErrorAction SilentlyContinue |
                Sort-Object -Property @(
                    @{ Expression = { if ($_.PSBeginTime) { $_.PSBeginTime } else { [DateTime]::MinValue } }; Descending = $true },
                    @{ Expression = { $_.Id }; Descending = $true }
                ))
        }

        function Get-RelatedKeepAliveJob
        {
            @(Get-Job -ErrorAction SilentlyContinue | Where-Object {
                    $_.Name -like '*KeepAlive*' -or
                    ($null -ne $_.PSObject.Properties['KeepAliveJob'] -and $_.KeepAliveJob)
                } | Sort-Object -Property @(
                    @{ Expression = { $_.Name }; Descending = $false },
                    @{ Expression = { if ($_.PSBeginTime) { $_.PSBeginTime } else { [DateTime]::MinValue } }; Descending = $true },
                    @{ Expression = { $_.Id }; Descending = $true }
                ))
        }

        # Platform detection for cross-platform compatibility
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # PowerShell 5.1 - Windows only
            $isWindowsPlatform = $true
            $isMacOSPlatform = $false
            $isLinuxPlatform = $false
        }
        else
        {
            # PowerShell Core - use built-in platform variables
            $isWindowsPlatform = $IsWindows
            $isMacOSPlatform = $IsMacOS
            $isLinuxPlatform = $IsLinux
        }

        # Validate platform-specific requirements
        if ($PSCmdlet.ParameterSetName -eq 'Start')
        {
            if ($isLinuxPlatform)
            {
                # Check for required Linux tools
                $hasSystemdInhibit = $null -ne (Get-Command systemd-inhibit -ErrorAction SilentlyContinue)
                $hasXdotool = $null -ne (Get-Command xdotool -ErrorAction SilentlyContinue)

                if (-not $hasSystemdInhibit -and -not $hasXdotool)
                {
                    Write-Error "Linux platform requires either 'systemd-inhibit' or 'xdotool' to be installed. Install with: sudo apt-get install xdotool (Debian/Ubuntu) or sudo dnf install xdotool (RHEL/Fedora)" -Category NotInstalled -ErrorAction Stop
                }

                if ($hasSystemdInhibit)
                {
                    $platformMethod = 'LinuxSystemdInhibit'
                    $platformDescription = 'Linux (using systemd-inhibit)'
                }
                else
                {
                    $platformMethod = 'LinuxXdotool'
                    $platformDescription = 'Linux (using xdotool)'
                }

                Write-Verbose "Linux keep-alive method: $(if ($hasSystemdInhibit) { 'systemd-inhibit' } else { 'xdotool' })"
            }
            elseif ($isMacOSPlatform)
            {
                # macOS has caffeinate built-in, verify it's available
                if ($null -eq (Get-Command caffeinate -ErrorAction SilentlyContinue))
                {
                    Write-Error "macOS 'caffeinate' command not found. This should be built-in to macOS." -Category NotInstalled -ErrorAction Stop
                }

                $platformMethod = 'MacOSCaffeinate'
                $platformDescription = 'macOS (using caffeinate)'
                Write-Verbose 'macOS keep-alive method: caffeinate'
            }
            elseif ($isWindowsPlatform)
            {
                # Windows - validate COM object availability
                try
                {
                    Write-Verbose 'Testing WScript.Shell COM object availability'
                    $testCOM = New-Object -ComObject WScript.Shell
                    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($testCOM) | Out-Null
                    $platformMethod = 'WindowsSendKeys'
                    $platformDescription = 'Windows'
                    Write-Verbose 'Windows keep-alive method: WScript.Shell COM object'
                }
                catch
                {
                    Write-Error "WScript.Shell COM object not available: $($_.Exception.Message)" -ErrorAction Stop
                }
            }
            else
            {
                Write-Error 'Unable to determine the current operating system platform.' -Category InvalidOperation -ErrorAction Stop
            }
        }

        # Calculate end time for Start parameter set
        if ($PSCmdlet.ParameterSetName -eq 'Start')
        {
            $endTime = (Get-Date).AddHours($KeepAliveHours)
            Write-Verbose "Keep-alive job will run until: $endTime"
        }
    }

    process
    {
        switch ($PSCmdlet.ParameterSetName)
        {
            'End'
            {
                Write-Verbose "Attempting to stop and remove job: $JobName"

                $matchingJobs = @(Get-KeepAliveJobsByName -Name $JobName)
                if ($matchingJobs.Count -gt 0)
                {
                    if ($matchingJobs.Count -gt 1)
                    {
                        Write-Warning "Multiple jobs named '$JobName' were found. Stopping and removing all matching jobs."
                    }

                    try
                    {
                        foreach ($jobRecord in $matchingJobs)
                        {
                            if ($jobRecord.State -in @('Running', 'NotStarted', 'Blocked', 'Suspended'))
                            {
                                try
                                {
                                    Write-Verbose "Stopping job '$($jobRecord.Name)' (Id: $($jobRecord.Id)) in state '$($jobRecord.State)'"
                                    Stop-Job -Job $jobRecord -ErrorAction Stop | Out-Null
                                }
                                catch
                                {
                                    Write-Verbose "Stop-Job for '$($jobRecord.Name)' (Id: $($jobRecord.Id)) reported: $($_.Exception.Message)"
                                }
                            }

                            Write-Verbose "Removing job '$($jobRecord.Name)' (Id: $($jobRecord.Id))"
                            Remove-Job -Job $jobRecord -Force -ErrorAction Stop
                        }

                        Write-KeepAliveInfo "Keep-alive job '$JobName' has been stopped and removed."
                        if ($matchingJobs.Count -gt 1)
                        {
                            Write-KeepAliveInfo "Removed $($matchingJobs.Count) matching jobs named '$JobName'."
                        }
                    }
                    catch
                    {
                        Write-Error "Failed to stop/remove job '$JobName': $($_.Exception.Message)" -ErrorAction Stop
                    }
                }
                else
                {
                    Write-Warning "No keep-alive job named '$JobName' found."
                }
                break
            }

            'Query'
            {
                Write-Verbose "Querying status of job: $JobName"

                $matchingJobs = @(Get-KeepAliveJobsByName -Name $JobName)
                if ($matchingJobs.Count -gt 0)
                {
                    if ($matchingJobs.Count -gt 1)
                    {
                        Write-Warning "Multiple jobs named '$JobName' were found. Displaying the most recent job (Id: $($matchingJobs[0].Id))."
                    }

                    $existingJob = $matchingJobs[0]

                    try
                    {
                        Write-KeepAliveInfo "Job Status for '$JobName':"
                        Write-KeepAliveInfo "  State: $($existingJob.State)"
                        Write-KeepAliveInfo "  Started: $($existingJob.PSBeginTime)"

                        if ($null -ne $existingJob.PSObject.Properties['KeepAliveEndTime'])
                        {
                            Write-KeepAliveInfo "  Scheduled End: $($existingJob.KeepAliveEndTime)"
                        }

                        if ($existingJob.State -eq 'Completed')
                        {
                            Write-KeepAliveInfo "  Completed: $($existingJob.PSEndTime)"
                            Write-Verbose 'Job completed, retrieving final output and cleaning up'

                            $jobOutput = @(Receive-Job -Job $existingJob -ErrorAction SilentlyContinue)
                            if ($jobOutput)
                            {
                                Write-KeepAliveInfo ''
                                Write-KeepAliveInfo 'Job Output:'
                                foreach ($line in $jobOutput)
                                {
                                    Write-KeepAliveInfo ([String]$line)
                                }
                            }

                            Remove-Job -Job $existingJob -Force
                            Write-KeepAliveInfo ''
                            Write-KeepAliveInfo "Completed job '$JobName' has been cleaned up."
                        }
                        elseif ($existingJob.State -eq 'Running')
                        {
                            Write-KeepAliveInfo '  Status: Job is actively running'

                            # Get recent output without removing it
                            $recentOutput = @(Receive-Job -Job $existingJob -Keep -ErrorAction SilentlyContinue)
                            if ($recentOutput)
                            {
                                Write-KeepAliveInfo ''
                                Write-KeepAliveInfo 'Recent Output:'
                                foreach ($line in ($recentOutput | Select-Object -Last 5))
                                {
                                    Write-KeepAliveInfo ([String]$line)
                                }
                            }
                        }
                        else
                        {
                            Write-KeepAliveInfo "  Status: Job is in '$($existingJob.State)' state"

                            # Check for any errors
                            $jobErrors = @($existingJob.ChildJobs | ForEach-Object { $_.Error } | Where-Object { $_ })
                            if ($jobErrors.Count -gt 0)
                            {
                                Write-KeepAliveInfo ''
                                Write-KeepAliveInfo 'Job Errors:'
                                foreach ($jobError in $jobErrors)
                                {
                                    Write-KeepAliveInfo "  $jobError"
                                }
                            }
                        }
                    }
                    catch
                    {
                        Write-Error "Error querying job '$JobName': $($_.Exception.Message)"
                    }
                }
                else
                {
                    Write-Warning "No keep-alive job named '$JobName' found."

                    # Check for other keep-alive jobs
                    $allKeepAliveJobs = @(Get-RelatedKeepAliveJob)
                    if ($allKeepAliveJobs.Count -gt 0)
                    {
                        Write-KeepAliveInfo ''
                        Write-KeepAliveInfo 'Other keep-alive jobs found:'
                        foreach ($line in ($allKeepAliveJobs | Select-Object Name, State, PSBeginTime | Format-Table -AutoSize | Out-String -Stream))
                        {
                            if (-not [String]::IsNullOrWhiteSpace($line))
                            {
                                Write-KeepAliveInfo $line.TrimEnd()
                            }
                        }
                    }
                }
                break
            }

            'Start'
            {
                Write-Verbose "Starting new keep-alive job: $JobName"

                # Check if job already exists
                $existingJobs = @(Get-KeepAliveJobsByName -Name $JobName)
                if ($existingJobs.Count -gt 0)
                {
                    $runningJobs = @($existingJobs | Where-Object { $_.State -eq 'Running' })
                    if ($runningJobs.Count -gt 0)
                    {
                        Write-Warning "Keep-alive job '$JobName' is already running. Use -Query to check status or -EndJob to stop it first."
                        return
                    }
                    else
                    {
                        Write-Verbose "Cleaning up $($existingJobs.Count) previous job(s) named '$JobName'"
                        foreach ($jobRecord in $existingJobs)
                        {
                            Remove-Job -Job $jobRecord -Force -ErrorAction SilentlyContinue
                        }
                    }
                }

                # Create the background job script
                $jobScript = {
                    param ($EndTime, $SleepSeconds, $JobName, $KeyToPress, $PlatformMethod)

                    try
                    {
                        function Get-RemainingSleepInterval
                        {
                            param (
                                [Parameter(Mandatory)]
                                [DateTime]$TargetTime,

                                [Parameter(Mandatory)]
                                [Int32]$IntervalSeconds
                            )

                            $remainingMilliseconds = [Math]::Floor(($TargetTime - (Get-Date)).TotalMilliseconds)
                            if ($remainingMilliseconds -le 0)
                            {
                                return 0
                            }

                            return [Int32][Math]::Min(($IntervalSeconds * 1000), $remainingMilliseconds)
                        }

                        Write-Output "Keep-alive job '$JobName' started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                        Write-Output "Job will end at: $(Get-Date $EndTime -Format 'yyyy-MM-dd HH:mm:ss')"

                        # Platform-specific initialization
                        switch ($PlatformMethod)
                        {
                            'WindowsSendKeys'
                            {
                                Write-Output 'Platform: Windows (using WScript.Shell for keystroke simulation)'
                                Write-Output "Key simulation interval: $SleepSeconds seconds"
                                Write-Output "Key to simulate: $KeyToPress`n"

                                # Create COM object once and reuse it (more efficient and reliable)
                                $wshell = New-Object -ComObject WScript.Shell
                            }
                            'MacOSCaffeinate'
                            {
                                Write-Output 'Platform: macOS (using caffeinate to prevent sleep)'
                                Write-Output "Note: caffeinate runs continuously, no interval needed`n"

                                # Start caffeinate in the background
                                # -d prevents display sleep, -i prevents system idle sleep
                                $caffeinateProcess = Start-Process -FilePath 'caffeinate' -ArgumentList '-di' -PassThru -NoNewWindow -ErrorAction Stop
                            }
                            'LinuxSystemdInhibit'
                            {
                                Write-Output 'Platform: Linux (using systemd-inhibit to prevent sleep)'
                                Write-Output "Note: systemd-inhibit runs continuously, no interval needed`n"

                                # Start systemd-inhibit to block idle and sleep.
                                # Use a one-second minimum in case the job starts just before the requested end time.
                                $durationSeconds = [Math]::Max([Int32][Math]::Ceiling(($EndTime - (Get-Date)).TotalSeconds), 1)
                                $inhibitProcess = Start-Process -FilePath 'systemd-inhibit' -ArgumentList @(
                                    '--what=idle:sleep',
                                    '--who=PowerShell',
                                    '--why=Keep-alive job active',
                                    'sleep',
                                    $durationSeconds
                                ) -PassThru -NoNewWindow -ErrorAction Stop
                            }
                            'LinuxXdotool'
                            {
                                Write-Output 'Platform: Linux (using xdotool for mouse movement simulation)'
                                Write-Output "Activity simulation interval: $SleepSeconds seconds`n"
                            }
                            default
                            {
                                throw "Unsupported keep-alive platform method: $PlatformMethod"
                            }
                        }

                        $iterationCount = 0

                        # Main keep-alive loop
                        while ((Get-Date) -lt $EndTime)
                        {
                            $remaining = [Math]::Round((($EndTime - (Get-Date)).TotalMinutes), 2)

                            # Only show progress every 5 iterations to reduce output volume
                            if (($iterationCount % 5) -eq 0)
                            {
                                Write-Output "$(Get-Date -Format 'HH:mm:ss') - Iteration $($iterationCount + 1), $remaining minutes remaining"
                            }

                            # Platform-specific activity simulation
                            try
                            {
                                switch ($PlatformMethod)
                                {
                                    'WindowsSendKeys'
                                    {
                                        # Send keystroke using COM object
                                        $wshell.SendKeys($KeyToPress)
                                    }
                                    'MacOSCaffeinate'
                                    {
                                        # caffeinate runs continuously, just check if it's still running
                                        if ($caffeinateProcess.HasExited)
                                        {
                                            throw 'caffeinate process has unexpectedly exited'
                                        }
                                    }
                                    'LinuxSystemdInhibit'
                                    {
                                        # systemd-inhibit runs continuously, check if it's still running
                                        if ($inhibitProcess.HasExited)
                                        {
                                            throw 'systemd-inhibit process has unexpectedly exited'
                                        }
                                    }
                                    'LinuxXdotool'
                                    {
                                        # Simulate minimal mouse movement (move cursor 1 pixel and back)
                                        # This is less intrusive than key presses
                                        $null = & xdotool mousemove_relative --sync -- 1 0
                                        if ($LASTEXITCODE -ne 0)
                                        {
                                            throw "xdotool returned exit code $LASTEXITCODE while moving the cursor"
                                        }

                                        $null = & xdotool mousemove_relative --sync -- -1 0
                                        if ($LASTEXITCODE -ne 0)
                                        {
                                            throw "xdotool returned exit code $LASTEXITCODE while restoring the cursor position"
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                Write-Error "Failed to simulate activity: $($_.Exception.Message)"
                                break
                            }

                            $iterationCount++

                            $sleepMilliseconds = Get-RemainingSleepInterval -TargetTime $EndTime -IntervalSeconds $SleepSeconds
                            if ($sleepMilliseconds -le 0)
                            {
                                break
                            }

                            Start-Sleep -Milliseconds $sleepMilliseconds
                        }

                        Write-Output ''
                        Write-Output "Keep-alive job '$JobName' completed successfully at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                        if ($PlatformMethod -eq 'WindowsSendKeys')
                        {
                            Write-Output "Total keystrokes sent: $iterationCount"
                        }
                        elseif ($PlatformMethod -eq 'LinuxXdotool')
                        {
                            Write-Output "Total activity simulations: $iterationCount"
                        }
                        else
                        {
                            Write-Output "Total iterations: $iterationCount"
                        }
                    }
                    catch
                    {
                        Write-Error "Keep-alive job '$JobName' encountered an error: $($_.Exception.Message)"
                        throw $_
                    }
                    finally
                    {
                        # Platform-specific cleanup
                        switch ($PlatformMethod)
                        {
                            'WindowsSendKeys'
                            {
                                # Clean up COM object
                                if ($wshell)
                                {
                                    try
                                    {
                                        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wshell) | Out-Null
                                    }
                                    catch
                                    {
                                        # Ignore cleanup errors
                                    }
                                }
                            }
                            'MacOSCaffeinate'
                            {
                                # Stop caffeinate process
                                if ($caffeinateProcess -and -not $caffeinateProcess.HasExited)
                                {
                                    try
                                    {
                                        $caffeinateProcess.Kill()
                                        $caffeinateProcess.WaitForExit(5000)  # Wait up to 5 seconds
                                    }
                                    catch
                                    {
                                        # Ignore cleanup errors
                                    }
                                }
                            }
                            'LinuxSystemdInhibit'
                            {
                                # Stop systemd-inhibit process if it's still running
                                if ($inhibitProcess -and -not $inhibitProcess.HasExited)
                                {
                                    try
                                    {
                                        $inhibitProcess.Kill()
                                        $inhibitProcess.WaitForExit(5000)  # Wait up to 5 seconds
                                    }
                                    catch
                                    {
                                        # Ignore cleanup errors
                                    }
                                }
                            }
                        }
                    }
                }

                # Start the background job
                try
                {
                    # Initialization script to set working directory to a known-good location
                    $initScript = {
                        # Set to user's home directory to avoid directory-not-found errors
                        # This is safer than using the current directory which may be temporary
                        try
                        {
                            Set-Location -Path ([Environment]::GetFolderPath('UserProfile')) -ErrorAction Stop
                        }
                        catch
                        {
                            # Fallback to root if home directory fails
                            Set-Location -Path ([System.IO.Path]::GetPathRoot($PWD)) -ErrorAction SilentlyContinue
                        }
                    }

                    $job = Start-Job -ScriptBlock $jobScript -Name $JobName -InitializationScript $initScript -ArgumentList $endTime, $SleepSeconds, $JobName, $KeyToPress, $platformMethod
                    $job | Add-Member -NotePropertyName 'KeepAliveJob' -NotePropertyValue $true -Force
                    $job | Add-Member -NotePropertyName 'KeepAlivePlatformMethod' -NotePropertyValue $platformMethod -Force
                    $job | Add-Member -NotePropertyName 'KeepAliveEndTime' -NotePropertyValue $endTime -Force

                    Write-KeepAliveInfo "Keep-alive job '$JobName' started successfully."
                    Write-KeepAliveInfo "  Job ID: $($job.Id)"
                    Write-KeepAliveInfo "  Duration: $KeepAliveHours hours"
                    Write-KeepAliveInfo "  End time: $(Get-Date $endTime -Format 'yyyy-MM-dd h:mm:ss tt')"
                    Write-KeepAliveInfo "  Platform: $platformDescription"

                    if ($platformMethod -eq 'WindowsSendKeys')
                    {
                        Write-KeepAliveInfo "  Interval: $SleepSeconds seconds"
                        Write-KeepAliveInfo "  Key: $KeyToPress"
                    }
                    elseif ($platformMethod -eq 'LinuxXdotool')
                    {
                        Write-KeepAliveInfo "  Interval: $SleepSeconds seconds"
                    }

                    Write-KeepAliveInfo ''
                    Write-KeepAliveInfo "Use 'Start-KeepAlive -Query -JobName $JobName' to check status"

                    return $job
                }
                catch
                {
                    Write-Error "Failed to start keep-alive job: $($_.Exception.Message)" -ErrorAction Stop
                }
                break
            }
        }
    }

    end
    {
        Write-Verbose 'Start-KeepAlive function completed'
    }
}

# Create alias 'keepalive' if it doesn't conflict
if (-not (Get-Command -Name 'keepalive' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'keepalive' alias for Start-KeepAlive"
        Set-Alias -Name 'keepalive' -Value 'Start-KeepAlive' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Start-KeepAlive: Could not create 'keepalive' alias: $($_.Exception.Message)"
    }
}
