function Invoke-ElevatedCommand
{
    <#
    .SYNOPSIS
        Runs a script block with elevated privileges and passes pipeline input.

    .DESCRIPTION
        This function executes the provided script block in an elevated PowerShell session
        while maintaining pipeline functionality. It provides a way to run commands with
        administrator privileges without losing the context of the current session.

        The function automatically detects the appropriate PowerShell executable (powershell.exe
        for Windows PowerShell or pwsh.exe for PowerShell Core) and handles cross-session
        communication using temporary XML files.

        NOTE: This function only works on Windows platforms as it relies on Windows UAC
        elevation mechanisms. On macOS and Linux, use sudo directly instead.

    .PARAMETER Scriptblock
        The script block to execute with elevated privileges.
        This parameter is mandatory and supports complex multi-line script blocks.

    .PARAMETER InputObject
        Input to provide to the elevated process via the pipeline.
        This parameter accepts pipeline input and can handle complex objects.

    .PARAMETER EnableProfile
        When specified, loads the PowerShell profile in the elevated session.
        By default, profiles are not loaded for faster startup times.

    .PARAMETER TimeoutSeconds
        The maximum time in seconds to wait for the elevated process to complete.
        Default is 300 seconds (5 minutes). Use 0 for no timeout.

    .EXAMPLE
        PS> Invoke-ElevatedCommand { Get-Service | Where-Object Status -eq 'Running' }
        Runs an elevated PowerShell session to get running services.

    .EXAMPLE
        PS> Get-Process | Invoke-ElevatedCommand { $input | Where-Object Handles -gt 500 } | Sort-Object Handles
        Gets all processes, pipes them to an elevated session that filters for processes with more than 500 handles,
        and then sorts the results by handle count.

    .EXAMPLE
        PS> Invoke-ElevatedCommand -EnableProfile { Import-Module ActiveDirectory; Get-ADUser -Filter * }
        Runs an elevated PowerShell session with profile loaded, imports the ActiveDirectory module,
        and retrieves all AD users.

    .EXAMPLE
        PS> Invoke-ElevatedCommand -TimeoutSeconds 60 {
            Get-WmiObject -Class Win32_ComputerSystem | Select-Object Name, Domain, TotalPhysicalMemory
        }
        Runs an elevated WMI query with a 60-second timeout.

    .EXAMPLE
        PS> Invoke-ElevatedCommand {
            New-Item -Path "C:\Program Files\MyApp" -ItemType Directory -Force
            Copy-Item -Path ".\MyApp.exe" -Destination "C:\Program Files\MyApp\" -Force
        }
        Creates a directory and copies files to Program Files, which requires elevation.

    .EXAMPLE
        PS> "Server01", "Server02" | Invoke-ElevatedCommand {
            $input | ForEach-Object {
                Test-Connection -ComputerName $_ -Count 1 -Quiet
            }
        }
        Tests connectivity to multiple servers using elevated privileges.

    .OUTPUTS
        System.Object
        The output from the elevated script block is returned to the calling session.
        If the elevated process fails, a terminating error is thrown.

    .NOTES
        Enhanced version based on Windows PowerShell Cookbook (O'Reilly)
        by Lee Holmes (http://www.leeholmes.com/guide)

        This function creates temporary files to stream input and output between sessions.
        These files are automatically cleaned up when the function completes, even if
        an error occurs.

        The function automatically detects whether to use Windows PowerShell (powershell.exe)
        or PowerShell Core (pwsh.exe) based on the current session.

    .LINK
        https://www.leeholmes.com/blog/
    #>
    param(
        ## The script block to invoke elevated
        [Parameter(Mandatory = $true)]
        [ScriptBlock] $Scriptblock,

        ## Any input to give the elevated process
        [Parameter(ValueFromPipeline = $true)]
        $InputObject,

        ## Switch to enable the user profile
        [switch] $EnableProfile,

        ## Timeout in seconds for the elevated process (0 = no timeout)
        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $TimeoutSeconds = 300
    )

    begin
    {
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

        # Check if running on Windows
        if (-not $script:IsWindowsPlatform)
        {
            $platformName = if ($script:IsMacOSPlatform) { 'macOS' } elseif ($script:IsLinuxPlatform) { 'Linux' } else { 'this platform' }
            throw "Invoke-ElevatedCommand is only supported on Windows. On $platformName, use 'sudo' to run commands with elevated privileges."
        }

        $inputItems = New-Object System.Collections.ArrayList
    }

    process
    {
        $null = $inputItems.Add($inputObject)
    }

    end
    {
        $outputFile = $null
        $inputFile = $null

        try
        {
            ## Create some temporary files for streaming input and output
            $outputFile = [IO.Path]::GetTempFileName()
            $inputFile = [IO.Path]::GetTempFileName()

            ## Stream the input into the input file
            if ($inputItems.Count -gt 0)
            {
                $inputItems.ToArray() | Export-Clixml -Depth 3 -Path $inputFile
            }
            else
            {
                # Create empty input file
                @() | Export-Clixml -Depth 1 -Path $inputFile
            }

            ## Determine the appropriate PowerShell executable
            $powerShellExecutable = if ($PSVersionTable.PSEdition -eq 'Core' -and (Get-Command 'pwsh' -ErrorAction SilentlyContinue))
            {
                'pwsh'
            }
            else
            {
                'powershell'
            }

            ## Start creating the command line for the elevated PowerShell session
            $commandLine = @()
            if (-not $EnableProfile)
            {
                $commandLine += '-NoProfile'
            }

            ## Create the command string with better error handling
            $commandString = @"
Set-Location '$($pwd.Path -replace "'", "''")'
try {
    `$inputData = if (Test-Path '$($inputFile -replace "'", "''")') { Import-Clixml '$($inputFile -replace "'", "''")' } else { @() }
    `$output = `$inputData | & {$($scriptblock.ToString())} 2>&1
    `$output | Export-Clixml -Depth 3 -Path '$($outputFile -replace "'", "''")'
} catch {
    `$errorOutput = [PSCustomObject]@{
        Exception = `$_.Exception.Message
        ScriptStackTrace = `$_.ScriptStackTrace
        FullyQualifiedErrorId = `$_.FullyQualifiedErrorId
        CategoryInfo = `$_.CategoryInfo.ToString()
        InvocationInfo = `$_.InvocationInfo.PositionMessage
    }
    `$errorOutput | Export-Clixml -Depth 3 -Path '$($outputFile -replace "'", "''")'
    exit 1
}
"@

            $commandBytes = [System.Text.Encoding]::Unicode.GetBytes($commandString)
            $encodedCommand = [Convert]::ToBase64String($commandBytes)
            $commandLine += '-EncodedCommand'
            $commandLine += $encodedCommand

            ## Start the new PowerShell process
            $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processStartInfo.FileName = (Get-Command $powerShellExecutable).Source
            $processStartInfo.Arguments = $commandLine -join ' '
            $processStartInfo.Verb = 'RunAs'
            $processStartInfo.WindowStyle = 'Hidden'
            $processStartInfo.UseShellExecute = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processStartInfo

            if (-not $process.Start())
            {
                throw 'Failed to start elevated PowerShell process. This may happen if the user cancels the UAC prompt.'
            }

            ## Wait for completion with optional timeout
            $processCompleted = if ($TimeoutSeconds -eq 0)
            {
                $process.WaitForExit()
                $true
            }
            else
            {
                $process.WaitForExit($TimeoutSeconds * 1000)
            }

            if (-not $processCompleted)
            {
                $process.Kill()
                $process.WaitForExit(5000) # Give it 5 seconds to clean up
                throw "Elevated PowerShell process timed out after $TimeoutSeconds seconds."
            }

            ## Check exit code
            if ($process.ExitCode -ne 0)
            {
                $errorMessage = "Elevated PowerShell process exited with code $($process.ExitCode)."

                # Try to get error details from output file
                if ((Test-Path $outputFile) -and ((Get-Item $outputFile).Length -gt 0))
                {
                    try
                    {
                        $errorOutput = Import-Clixml $outputFile
                        if ($errorOutput -is [PSCustomObject] -and $errorOutput.Exception)
                        {
                            $errorMessage += " Error: $($errorOutput.Exception)"
                            if ($errorOutput.InvocationInfo)
                            {
                                $errorMessage += "`n$($errorOutput.InvocationInfo)"
                            }
                        }
                    }
                    catch
                    {
                        # If we can't read the error output, just continue with basic error
                        Write-Debug "Failed to parse error output from elevated session: $($_.Exception.Message)"
                    }
                }

                throw $errorMessage
            }

            ## Return the output to the user
            if ((Test-Path $outputFile) -and ((Get-Item $outputFile).Length -gt 0))
            {
                try
                {
                    $result = Import-Clixml $outputFile

                    # Check if the result is an error object
                    if ($result -is [PSCustomObject] -and $result.Exception)
                    {
                        $errorRecord = New-Object System.Management.Automation.ErrorRecord(
                            [System.Exception]::new($result.Exception),
                            $result.FullyQualifiedErrorId,
                            [System.Management.Automation.ErrorCategory]::NotSpecified,
                            $null
                        )
                        throw $errorRecord
                    }

                    return $result
                }
                catch
                {
                    if ($_.Exception -is [System.Management.Automation.ErrorRecord])
                    {
                        throw
                    }
                    throw "Failed to import output from elevated session: $($_.Exception.Message)"
                }
            }
        }
        catch
        {
            # Re-throw the original exception to preserve stack trace
            throw
        }
        finally
        {
            ## Clean up temporary files
            if ($outputFile -and (Test-Path $outputFile))
            {
                try
                {
                    Remove-Item $outputFile -Force -ErrorAction Stop
                }
                catch
                {
                    Write-Debug "Failed to remove temporary output file: $outputFile. Error: $($_.Exception.Message)"
                }
            }
            if ($inputFile -and (Test-Path $inputFile))
            {
                try
                {
                    Remove-Item $inputFile -Force -ErrorAction Stop
                }
                catch
                {
                    Write-Debug "Failed to remove temporary input file: $inputFile. Error: $($_.Exception.Message)"
                }
            }
        }
    }
}
