function Start-KeepAlive
{
    <#
    .SYNOPSIS
        Prevents system inactivity timeout by simulating key-presses at regular intervals.

    .DESCRIPTION
        This function runs a background job that simulates key-press activity to keep
        a computer awake and prevent sleep, screensaver activation, or session timeout.
        By default, it sends a Ctrl key press every 3 minutes for a specified duration.

        CAUTION: This function should only be used in secure environments when you need
        to prevent timeout during long operations like file downloads.

    .PARAMETER KeepAliveHours
        The number of hours the keep-alive job will run.
        Default is 12 hours.

    .PARAMETER SleepSeconds
        The number of seconds between each key-press.
        Default is 180 seconds (3 minutes).

    .PARAMETER JobName
        The name of the background job.
        Default is 'KeepAlive'.

    .PARAMETER EndJob
        When specified, stops any running keep-alive job and removes it.

    .PARAMETER Query
        When specified, displays the status of the keep-alive job and cleans up completed jobs.

    .PARAMETER KeyToPress
        The key to simulate pressing.
        Default is '^' (Ctrl key).
        Reference for other keys: http://msdn.microsoft.com/en-us/library/office/aa202943(v=office.10).aspx

    .EXAMPLE
        PS> Start-KeepAlive
        Starts a keep-alive job that will run for 12 hours, pressing the Ctrl key every 3 minutes.

    .EXAMPLE
        PS> Start-KeepAlive -KeepAliveHours 3 -SleepSeconds 300
        Starts a keep-alive job that will run for 3 hours, pressing the Ctrl key every 5 minutes.

    .EXAMPLE
        PS> Start-KeepAlive -KeyToPress '{TAB}'
        Starts a keep-alive job that simulates pressing the Tab key instead of Ctrl.

    .EXAMPLE
        PS> Start-KeepAlive -Query
        Displays the status of the current keep-alive job.

    .EXAMPLE
        PS> Start-KeepAlive -EndJob
        Stops the running keep-alive job and removes it.

    .OUTPUTS
        System.Management.Automation.PSRemotingJob
        Returns a background job object when starting a new keep-alive job.

    .NOTES
        This function should only be used when your computer is locked in a secure location.
        It is intended as a temporary workaround for specific scenarios where system timeout
        would interfere with important tasks.

        If you don't manually end the job using -EndJob, use Get-Job | Remove-Job to clean up old jobs.
    #>
    param (
        $KeepAliveHours = 12,
        $SleepSeconds = 180,
        $JobName = 'KeepAlive',
        [Switch]$EndJob,
        [Switch]$Query,
        $KeyToPress = '^' # Default key-press is <Ctrl>
        # Reference for other keys: http://msdn.microsoft.com/en-us/library/office/aa202943(v=office.10).aspx
    )

    begin
    {
        $Endtime = (Get-Date).AddHours($KeepAliveHours)
    }#begin

    process
    {

        # Manually end the job and stop the KeepAlive.
        if ($EndJob)
        {
            if (Get-Job -Name $JobName -ErrorAction SilentlyContinue)
            {
                Stop-Job -Name $JobName
                Remove-Job -Name $JobName
                "`n$JobName has now ended..."
            }
            else
            {
                "`nNo job $JobName."
            }
        }
        # Query the current status of the KeepAlive job.
        elseif ($Query)
        {
            try
            {
                if ((Get-Job -Name $JobName -ErrorAction Stop).PSEndTime)
                {
                    Receive-Job -Name $JobName
                    Remove-Job -Name $JobName
                    "`n$JobName has now completed."
                }
                else
                {
                    Receive-Job -Name $JobName -Keep
                }
            }
            catch
            {
                Receive-Job -Name $JobName -ErrorAction SilentlyContinue
                "`n$JobName has ended.."
                Get-Job -Name $JobName -ErrorAction SilentlyContinue | Remove-Job
            }
        }
        # Start the KeepAlive job.
        elseif (Get-Job -Name $JobName -ErrorAction SilentlyContinue)
        {
            "`n$JobName already started, please use: Start-Keepalive -Query"
        }
        else
        {
            $Job = {
                param ($Endtime, $SleepSeconds, $JobName, $KeyToPress)

                "`nStarted at..: $(Get-Date)"
                "Ends at.....: $(Get-Date $EndTime)`n"

                While ((Get-Date) -le (Get-Date $EndTime))
                {
                    # Wait SleepSeconds to press (This should be less than the screensaver timeout)
                    Start-Sleep -Seconds $SleepSeconds

                    $Remaining = [Math]::Round( ( (Get-Date $Endtime) - (Get-Date) | Select-Object -ExpandProperty TotalMinutes ), 2 )
                    "Job will run until $EndTime + $([Math]::Round( $SleepSeconds/60 ,2 )) minutes, around $Remaining Minutes"

                    # This is the sending of the KeyStroke
                    $x = New-Object -COM WScript.Shell
                    $x.SendKeys($KeyToPress)
                }

                try
                {
                    "`n$JobName has now completed.... job will be cleaned up."

                    # Would be nice if the job could remove itself, below will not work.
                    # Receive-Job -AutoRemoveJob -Force
                    # Still working on a way to automatically remove the job
                }
                Catch
                {
                    "Something went wrong, manually remove job $JobName"
                }

            } #Job

            $JobProperties = @{
                ScriptBlock = $Job
                Name = $JobName
                ArgumentList = $Endtime, $SleepSeconds, $JobName, $KeyToPress
            }

            Start-Job @JobProperties

            "`nKeepAlive set to run until $EndTime"
        }
    }#Process
}#Start-KeepAlive

# ## Usage
# Start-KeepAlive -KeepAliveHours 8 -SleepSeconds 180 -KeyToPress '{TAB}'

# # To end the job:
# Start-KeepAlive -EndJob
# # or
# Get-Job -Name KeepAlive | Remove-Job
