function Start-KeepAlive
{
    <#
    .SYNOPSIS
        Prevents system inactivity timeout by simulating key-presses at regular intervals.

    .DESCRIPTION
        This function runs a background job that simulates key-press activity to keep
        a computer awake and prevent sleep, screensaver activation, or session timeout.
        By default, it sends an F15 key press every 1 minute for a specified duration.

        PLATFORM COMPATIBILITY: This function only works on Windows platforms as it relies
        on Windows-specific COM objects (WScript.Shell) for keystroke simulation. On macOS
        and Linux, use platform-specific alternatives:

        - macOS: 'caffeinate -d' (prevent display sleep) or 'caffeinate -i' (prevent system sleep)
        - Linux: 'xset s off', 'xdotool', or 'systemd-inhibit' for similar functionality

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
        The key to simulate pressing. Uses WScript.Shell SendKeys syntax.
        Common options: '^' (Ctrl), '{TAB}', '{F15}' (non-interfering function key)
        Default is '{F15}' (F15 key - least likely to interfere with applications).
        Note that the {F15} key simulation is handled entirely by software, not hardware. The WScript.Shell.SendKeys() method sends a virtual keystroke to Windows, which doesn't require the physical key to exist.
        Reference: https://docs.microsoft.com/en-us/office/vba/language/reference/user-interface-help/sendkeys-statement

    .EXAMPLE
        PS > Start-KeepAlive

        Starts a keep-alive job that will run for 12 hours, pressing the F15 key every 1 minute.

    .EXAMPLE
        PS > Start-KeepAlive -KeepAliveHours 3 -SleepSeconds 300

        Starts a keep-alive job that will run for 3 hours, pressing the F15 key every 5 minutes.

    .EXAMPLE
        PS > Start-KeepAlive -KeyToPress '{TAB}'

        Starts a keep-alive job that simulates pressing the Tab key instead of F15.

    .EXAMPLE
        PS > Start-KeepAlive -Query

        Displays the status of the current keep-alive job without starting a new one.

    .EXAMPLE
        PS > Start-KeepAlive -EndJob

        Stops the running keep-alive job and removes it from the job queue.

    .EXAMPLE
        PS > Start-KeepAlive -JobName 'LongDownload' -KeepAliveHours 8

        Starts a custom-named keep-alive job for an 8-hour period.

    .OUTPUTS
        System.Management.Automation.Job
        Returns a background job object when starting a new keep-alive job.

    .NOTES
        CLEANUP: Jobs are automatically cleaned up when they complete. For manual cleanup
        of orphaned jobs, use: Get-Job -Name $JobName | Remove-Job -Force

        PLATFORM: Windows only - requires WScript.Shell COM object for keystroke simulation.

        VERSION COMPATIBILITY: Compatible with PowerShell 5.1+ on Windows systems.
    #>
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

        # Platform detection for cross-platform compatibility
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # PowerShell 5.1 - Windows only
            $script:IsWindowsPlatform = $true
            $script:IsMacOSPlatform = $false
            $script:IsLinuxPlatform = $false
        }
        else
        {
            # PowerShell Core - use built-in platform variables
            $script:IsWindowsPlatform = $IsWindows
            $script:IsMacOSPlatform = $IsMacOS
            $script:IsLinuxPlatform = $IsLinux
        }

        # Validate Windows platform requirement
        if (-not $script:IsWindowsPlatform)
        {
            $platformName = if ($script:IsMacOSPlatform)
            {
                'macOS - try: caffeinate -d (prevent display sleep) or caffeinate -i (prevent system sleep)'
            }
            elseif ($script:IsLinuxPlatform)
            {
                'Linux - try: xset s off, systemd-inhibit, or xdotool for similar functionality'
            }
            else
            {
                'this platform'
            }

            $errorMessage = "Start-KeepAlive requires Windows due to dependency on WScript.Shell COM objects. Current platform: $platformName"
            Write-Error $errorMessage -Category NotImplemented -ErrorAction Stop
        }

        # Calculate end time for Start parameter set
        if ($PSCmdlet.ParameterSetName -eq 'Start')
        {
            $endTime = (Get-Date).AddHours($KeepAliveHours)
            Write-Verbose "Keep-alive job will run until: $endTime"
        }
    } # end begin

    process
    {
        switch ($PSCmdlet.ParameterSetName)
        {
            'End'
            {
                Write-Verbose "Attempting to stop and remove job: $JobName"

                $existingJob = Get-Job -Name $JobName -ErrorAction SilentlyContinue
                if ($existingJob)
                {
                    try
                    {
                        if ($existingJob.State -eq 'Running')
                        {
                            Write-Verbose "Stopping running job: $JobName"
                            Stop-Job -Name $JobName -PassThru | Out-Null
                        }

                        Write-Verbose "Removing job: $JobName"
                        Remove-Job -Name $JobName -Force
                        Write-Host "Keep-alive job '$JobName' has been stopped and removed." -ForegroundColor Green
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

                $existingJob = Get-Job -Name $JobName -ErrorAction SilentlyContinue
                if ($existingJob)
                {
                    try
                    {
                        Write-Host "Job Status for '$JobName':" -ForegroundColor Cyan
                        Write-Host "  State: $($existingJob.State)" -ForegroundColor Yellow
                        Write-Host "  Started: $($existingJob.PSBeginTime)" -ForegroundColor Yellow

                        if ($existingJob.State -eq 'Completed')
                        {
                            Write-Host "  Completed: $($existingJob.PSEndTime)" -ForegroundColor Yellow
                            Write-Verbose 'Job completed, retrieving final output and cleaning up'

                            $jobOutput = Receive-Job -Name $JobName -ErrorAction SilentlyContinue
                            if ($jobOutput)
                            {
                                Write-Host "`nJob Output:" -ForegroundColor Cyan
                                $jobOutput | Write-Host
                            }

                            Remove-Job -Name $JobName -Force
                            Write-Host "`nCompleted job '$JobName' has been cleaned up." -ForegroundColor Green
                        }
                        elseif ($existingJob.State -eq 'Running')
                        {
                            Write-Host '  Status: Job is actively running' -ForegroundColor Green

                            # Get recent output without removing it
                            $recentOutput = Receive-Job -Name $JobName -Keep -ErrorAction SilentlyContinue
                            if ($recentOutput)
                            {
                                Write-Host "`nRecent Output:" -ForegroundColor Cyan
                                ($recentOutput | Select-Object -Last 5) | Write-Host
                            }
                        }
                        else
                        {
                            Write-Host "  Status: Job is in '$($existingJob.State)' state" -ForegroundColor Yellow

                            # Check for any errors
                            if ($existingJob.ChildJobs[0].Error.Count -gt 0)
                            {
                                Write-Host "`nJob Errors:" -ForegroundColor Red
                                $existingJob.ChildJobs[0].Error | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
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
                    $allKeepAliveJobs = Get-Job | Where-Object { $_.Name -like '*KeepAlive*' }
                    if ($allKeepAliveJobs)
                    {
                        Write-Host "`nOther keep-alive jobs found:" -ForegroundColor Cyan
                        $allKeepAliveJobs | Format-Table Name, State, PSBeginTime -AutoSize | Out-Host
                    }
                }
                break
            }

            'Start'
            {
                Write-Verbose "Starting new keep-alive job: $JobName"

                # Check if job already exists
                $existingJob = Get-Job -Name $JobName -ErrorAction SilentlyContinue
                if ($existingJob)
                {
                    if ($existingJob.State -eq 'Running')
                    {
                        Write-Warning "Keep-alive job '$JobName' is already running. Use -Query to check status or -EndJob to stop it first."
                        return
                    }
                    else
                    {
                        Write-Verbose "Cleaning up previous job '$JobName' in state: $($existingJob.State)"
                        Remove-Job -Name $JobName -Force -ErrorAction SilentlyContinue
                    }
                }

                # Validate COM object availability before starting job
                try
                {
                    Write-Verbose 'Testing WScript.Shell COM object availability'
                    $testCOM = New-Object -ComObject WScript.Shell
                    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($testCOM) | Out-Null
                    Write-Verbose 'COM object test successful'
                }
                catch
                {
                    Write-Error "WScript.Shell COM object not available: $($_.Exception.Message)" -ErrorAction Stop
                }

                # Create the background job script
                $jobScript = {
                    param ($EndTime, $SleepSeconds, $JobName, $KeyToPress)

                    try
                    {
                        Write-Output "Keep-alive job '$JobName' started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                        Write-Output "Job will end at: $(Get-Date $EndTime -Format 'yyyy-MM-dd HH:mm:ss')"
                        Write-Output "Key simulation interval: $SleepSeconds seconds"
                        Write-Output "Key to simulate: $KeyToPress`n"

                        $iterationCount = 0

                        # Create COM object once and reuse it (more efficient and reliable)
                        $wshell = New-Object -ComObject WScript.Shell

                        while ((Get-Date) -le $EndTime)
                        {
                            # Wait SleepSeconds before pressing key (should be less than screensaver timeout)
                            # This matches the original behavior where sleep happens before each keystroke
                            Start-Sleep -Seconds $SleepSeconds

                            $current = Get-Date
                            $remaining = [Math]::Round((($EndTime - $current).TotalMinutes), 2)

                            # Only show progress every 5 iterations to reduce output volume
                            if (($iterationCount % 5) -eq 0)
                            {
                                Write-Output "$(Get-Date -Format 'HH:mm:ss') - Iteration $($iterationCount + 1), $remaining minutes remaining"
                            }

                            # Send the keystroke using the existing COM object
                            try
                            {
                                $wshell.SendKeys($KeyToPress)
                            }
                            catch
                            {
                                Write-Error "Failed to send keystroke: $($_.Exception.Message)"
                                break
                            }

                            $iterationCount++
                        }

                        Write-Output "`nKeep-alive job '$JobName' completed successfully at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                        Write-Output "Total keystrokes sent: $iterationCount"
                    }
                    catch
                    {
                        Write-Error "Keep-alive job '$JobName' encountered an error: $($_.Exception.Message)"
                        throw $_
                    }
                    finally
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
                } # end jobScript

                # Start the background job
                try
                {
                    $job = Start-Job -ScriptBlock $jobScript -Name $JobName -ArgumentList $endTime, $SleepSeconds, $JobName, $KeyToPress

                    Write-Host "Keep-alive job '$JobName' started successfully." -ForegroundColor Green
                    Write-Host "  Job ID: $($job.Id)" -ForegroundColor Cyan
                    Write-Host "  Duration: $KeepAliveHours hours" -ForegroundColor Cyan
                    Write-Host "  End time: $(Get-Date $endTime -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
                    Write-Host "  Interval: $SleepSeconds seconds" -ForegroundColor Cyan
                    Write-Host "  Key: $KeyToPress" -ForegroundColor Cyan
                    Write-Host "`nUse 'Start-KeepAlive -Query -JobName $JobName' to check status" -ForegroundColor Yellow

                    return $job
                }
                catch
                {
                    Write-Error "Failed to start keep-alive job: $($_.Exception.Message)" -ErrorAction Stop
                }
                break
            }
        }
    } # end process
    end
    {
        Write-Verbose 'Start-KeepAlive function completed'
    } # end end
} # end function Start-KeepAlive
