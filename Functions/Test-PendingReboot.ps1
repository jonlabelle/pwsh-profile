function Test-PendingReboot
{
    <#
    .SYNOPSIS
        Tests various registry values to see if the local computer is pending a reboot.

    .DESCRIPTION
        This function checks multiple registry locations to determine if a Windows system
        needs to be rebooted due to pending changes from Windows updates, component-based
        servicing, computer name changes, domain joins, or other system modifications.

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

    .OUTPUTS
        PSCustomObject
        Returns an object with ComputerName and IsPendingReboot properties.

    .NOTES
        Inspiration from: https://gallery.technet.microsoft.com/scriptcenter/Get-PendingReboot-Query-bdb79542

    .LINK
        https://github.com/adbertram/Random-PowerShell-Work/blob/master/Random%20Stuff/Test-PendingReboot.ps1
    #>
    [CmdletBinding()]
    param(
        # ComputerName is optional. If not specified, localhost is used.
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$Credential
    )

    $ErrorActionPreference = 'Stop'

    $scriptBlock = {
        if ($null -ne $using)
        {
            # $using is only available if this is being called with a remote session
            $VerbosePreference = $using:VerbosePreference
        }

        function Test-RegistryKey
        {
            [OutputType('bool')]
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Key
            )

            $ErrorActionPreference = 'Stop'

            if (Get-Item -Path $Key -ErrorAction Ignore)
            {
                $true
            }
        }

        function Test-RegistryValue
        {
            [OutputType('bool')]
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Key,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Value
            )

            $ErrorActionPreference = 'Stop'

            if (Get-ItemProperty -Path $Key -Name $Value -ErrorAction Ignore)
            {
                $true
            }
        }

        function Test-RegistryValueNotNull
        {
            [OutputType('bool')]
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Key,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Value
            )

            $ErrorActionPreference = 'Stop'

            if (($regVal = Get-ItemProperty -Path $Key -Name $Value -ErrorAction Ignore) -and $regVal.($Value))
            {
                $true
            }
        }

        # Added "test-path" to each test that did not leverage a custom function from above since
        # an exception is thrown when Get-ItemProperty or Get-ChildItem are passed a none-existent key path
        $tests = @(
            { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' }
            { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress' }
            { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' }
            { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending' }
            { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting' }
            { Test-RegistryValueNotNull -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Value 'PendingFileRenameOperations' }
            { Test-RegistryValueNotNull -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Value 'PendingFileRenameOperations2' }
            {
                # Added test to check first if key exists, using "ErrorAction ignore" will incorrectly return $true
                'HKLM:\SOFTWARE\Microsoft\Updates' | Where-Object { Test-Path $_ -PathType Container } | ForEach-Object {
                    if (Test-Path "$_\UpdateExeVolatile" )
                    {
                    (Get-ItemProperty -Path $_ -Name 'UpdateExeVolatile' | Select-Object -ExpandProperty UpdateExeVolatile) -ne 0
                    }
                    else
                    {
                        $false
                    }
                }
            }
            { Test-RegistryValue -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Value 'DVDRebootSignal' }
            { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttempts' }
            { Test-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon' -Value 'JoinDomain' }
            { Test-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon' -Value 'AvoidSpnSet' }
            {
                # Added test to check first if keys exists, if not each group will return $Null
                # May need to evaluate what it means if one or both of these keys do not exist
            ( 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' | Where-Object { Test-Path $_ } | ForEach-Object { (Get-ItemProperty -Path $_ ).ComputerName } ) -ne
            ( 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' | Where-Object { Test-Path $_ } | ForEach-Object { (Get-ItemProperty -Path $_ ).ComputerName } )
            }
            {
                # Added test to check first if key exists
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending' | Where-Object {
                (Test-Path $_) -and (Get-ChildItem -Path $_) } | ForEach-Object { $true }
            }
        )

        foreach ($test in $tests)
        {
            Write-Verbose "Running scriptblock: [$($test.ToString())]"
            if (& $test)
            {
                $true
                break
            }
        }
    }

    # if ComputerName was not specified, then use localhost
    # to ensure that we don't create a Session.
    if ($null -eq $ComputerName)
    {
        $ComputerName = 'localhost'
    }

    foreach ($computer in $ComputerName)
    {
        try
        {
            $connParams = @{
                'ComputerName' = $computer
            }
            if ($PSBoundParameters.ContainsKey('Credential'))
            {
                $connParams.Credential = $Credential
            }

            $output = @{
                ComputerName = $computer
                IsPendingReboot = $false
            }

            if ($computer -in '.', 'localhost', $env:COMPUTERNAME )
            {
                if (-not ($output.IsPendingReboot = Invoke-Command -ScriptBlock $scriptBlock))
                {
                    $output.IsPendingReboot = $false
                }
            }
            else
            {
                $psRemotingSession = New-PSSession @connParams

                if (-not ($output.IsPendingReboot = Invoke-Command -Session $psRemotingSession -ScriptBlock $scriptBlock))
                {
                    $output.IsPendingReboot = $false
                }
            }
            [PSCustomObject]$output
        }
        catch
        {
            Write-Error -Message $_.Exception.Message
        }
        finally
        {
            if (Get-Variable -Name 'psRemotingSession' -ErrorAction Ignore)
            {
                $psRemotingSession | Remove-PSSession
            }
        }
    }
}
