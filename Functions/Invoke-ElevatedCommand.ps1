function Invoke-ElevatedCommand
{
    <#
    .SYNOPSIS
        Runs a script block with elevated privileges and passes pipeline input.

    .DESCRIPTION
        This function executes the provided script block in an elevated PowerShell session
        while maintaining pipeline functionality. It provides a way to run commands with
        administrator privileges without losing the context of the current session.

        NOTE: This function only works on Windows platforms as it relies on Windows UAC
        elevation mechanisms. On macOS and Linux, use sudo directly instead.

    .PARAMETER Scriptblock
        The script block to execute with elevated privileges.
        This parameter is mandatory.

    .PARAMETER InputObject
        Input to provide to the elevated process via the pipeline.
        This parameter accepts pipeline input.

    .PARAMETER EnableProfile
        When specified, loads the PowerShell profile in the elevated session.
        By default, profiles are not loaded.

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

    .OUTPUTS
        System.Object
        The output from the elevated script block is returned to the calling session.

    .NOTES
        From Windows PowerShell Cookbook (O'Reilly)
        by Lee Holmes (http://www.leeholmes.com/guide)

        This function creates temporary files to stream input and output between sessions.
        These files are automatically cleaned up when the function completes.

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
        [switch] $EnableProfile
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
        ## Create some temporary files for streaming input and output
        $outputFile = [IO.Path]::GetTempFileName()
        $inputFile = [IO.Path]::GetTempFileName()

        ## Stream the input into the input file
        $inputItems.ToArray() | Export-Clixml -Depth 1 $inputFile

        ## Start creating the command line for the elevated PowerShell session
        $commandLine = ''
        if (-not $EnableProfile) { $commandLine += '-NoProfile ' }

        ## Convert the command into an encoded command for PowerShell
        $commandString = "Set-Location '$($pwd.Path)'; " +
        "`$output = Import-CliXml '$inputFile' | " +
        '& {' + $scriptblock.ToString() + '} 2>&1; ' +
        "`$output | Export-CliXml -Depth 1 '$outputFile'"

        $commandBytes = [System.Text.Encoding]::Unicode.GetBytes($commandString)
        $encodedCommand = [Convert]::ToBase64String($commandBytes)
        $commandLine += "-EncodedCommand $encodedCommand"

        ## Start the new PowerShell process
        $process = Start-Process -FilePath (Get-Command powershell).Definition `
            -ArgumentList $commandLine -Verb RunAs `
            -WindowStyle Hidden `
            -PassThru
        $process.WaitForExit()

        ## Return the output to the user
        if ((Get-Item $outputFile).Length -gt 0)
        {
            Import-Clixml $outputFile
        }

        ## Clean up
        [Console]::WriteLine($outputFile)
        # Remove-Item $outputFile
        Remove-Item $inputFile
    }
}
