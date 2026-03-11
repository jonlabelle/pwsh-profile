function Set-TlsSecurityProtocol
{
    <#
    .SYNOPSIS
        Configures TLS security protocol settings for secure network connections.

    .DESCRIPTION
        This function configures the .NET ServicePointManager SecurityProtocol setting
        for the current PowerShell session. It supports both PowerShell Desktop (5.1)
        and PowerShell Core (6+).

        On modern systems, it's often best to let the operating system decide the best
        security protocol by not setting a specific version. This function defaults to
        letting the operating system decide the best security protocol, but can also
        ensure a specific protocol is enabled while trimming weaker legacy protocols.

        When the current session is already using SystemDefault, the function leaves
        that OS-managed configuration unchanged unless -Force is specified to pin an
        explicit protocol value.

    .PARAMETER Protocol
        The TLS protocol configuration to apply.
        Valid values: SystemDefault, Tls, Tls11, Tls12, Tls13.
        Default is SystemDefault. 'SystemDefault' allows the OS to choose the best protocol.

    .PARAMETER Force
        Replaces the current protocol setting with the resolved target protocol,
        even if the current session is already using an acceptable configuration.

        By default, secure protocols already enabled for the current session are preserved
        when they still make sense for the requested configuration.

    .PARAMETER PassThru
        Returns the current security protocol setting after any changes are made.

    .EXAMPLE
        PS > Set-TlsSecurityProtocol

        Sets the security protocol to the operating system default for the current session.

    .EXAMPLE
        PS > Set-TlsSecurityProtocol -Protocol Tls13 -Verbose

        VERBOSE: Current security protocol: Tls12
        VERBOSE: TLS 1.3 is available on this system.
        VERBOSE: Updated security protocol to: Tls12, Tls13

        Enables TLS 1.3 while preserving already-enabled secure protocols.

    .EXAMPLE
        PS > Set-TlsSecurityProtocol -Protocol Tls12

        Ensures at least TLS 1.2 is enabled, useful for older systems or specific compatibility requirements.

        If the current session is already using SystemDefault, no change is made unless
        -Force is specified.

    .OUTPUTS
        System.Net.SecurityProtocolType
        When PassThru is specified, returns the current SecurityProtocol setting.

    .NOTES
        - PowerShell Desktop (5.1) on older Windows supports up to TLS 1.2.
        - PowerShell Core (6+) and modern Windows versions may support TLS 1.3.
        - Using 'SystemDefault' is recommended for forward compatibility.
        - When SystemDefault is unavailable, the function falls back to the best
          explicit protocol set available on the current platform.
        - When the current session already uses SystemDefault, explicit protocol
          requests are informational by default; use -Force to pin a value.
        - Changes apply globally to the current PowerShell session.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Set-TlsSecurityProtocol.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Set-TlsSecurityProtocol.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Net.SecurityProtocolType])]
    param(
        [Parameter()]
        [ValidateSet('SystemDefault', 'Tls', 'Tls11', 'Tls12', 'Tls13')]
        [String]$Protocol = 'SystemDefault',

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        Write-Verbose "Starting TLS security protocol configuration (Protocol: $Protocol)"

        if (-not (Get-Command -Name 'Get-TlsSecurityProtocol' -CommandType Function -ErrorAction SilentlyContinue))
        {
            $getTlsSecurityProtocolPath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-TlsSecurityProtocol.ps1'
            if (-not (Test-Path -LiteralPath $getTlsSecurityProtocolPath))
            {
                throw "Required dependency not found: $getTlsSecurityProtocolPath"
            }

            . $getTlsSecurityProtocolPath
        }

    }

    process
    {
        try
        {
            $currentState = Get-TlsSecurityProtocol -Protocol $Protocol
            $currentProtocol = $currentState.CurrentProtocol
            $currentDisplay = $currentState.CurrentProtocolDisplay
            Write-Verbose "Current security protocol: $currentDisplay"

            if ($currentState.FallbackUsed)
            {
                if ($Protocol -eq 'SystemDefault')
                {
                    Write-Verbose "SystemDefault is not available on this system. Falling back to: $($currentState.TargetProtocolDisplay)"
                }
                elseif ($currentState.FallbackDirection -eq 'Higher')
                {
                    Write-Verbose "Requested protocol '$Protocol' is not available on this system. Using stronger available protocol '$($currentState.ForceTargetProtocolDisplay)'."
                }
                else
                {
                    Write-Verbose "Requested protocol '$Protocol' is not available on this system. Falling back to '$($currentState.ForceTargetProtocolDisplay)'."
                }
            }

            if (-not $Force)
            {
                if (-not $currentState.ChangeRequired)
                {
                    if ($currentState.IsSystemDefault -and $Protocol -ne 'SystemDefault')
                    {
                        Write-Verbose "Current session uses SystemDefault. Leaving the OS-managed TLS configuration unchanged. Use -Force to pin '$($currentState.ForceTargetProtocolDisplay)'."
                    }
                    else
                    {
                        Write-Verbose 'Security protocol already meets the requested requirements.'
                    }

                    if ($PassThru)
                    {
                        return $currentProtocol
                    }

                    return
                }

                $targetProtocol = $currentState.TargetProtocol
                $targetDisplay = $currentState.TargetProtocolDisplay
            }
            else
            {
                $targetProtocol = $currentState.ForceTargetProtocol
                $targetDisplay = $currentState.ForceTargetProtocolDisplay

                if ($null -eq $targetProtocol)
                {
                    throw "No force target protocol could be resolved for request '$Protocol'."
                }
            }

            if ($currentProtocol -eq $targetProtocol -and -not $Force)
            {
                Write-Verbose 'Security protocol already meets the requested requirements.'

                if ($PassThru)
                {
                    return [Net.ServicePointManager]::SecurityProtocol
                }

                return
            }

            if ($PSCmdlet.ShouldProcess('Net.ServicePointManager.SecurityProtocol', "Set TLS protocols to $targetDisplay"))
            {
                [Net.ServicePointManager]::SecurityProtocol = $targetProtocol
                Write-Verbose "Updated security protocol to: $targetDisplay"
            }

            if ($PassThru)
            {
                return [Net.ServicePointManager]::SecurityProtocol
            }
        }
        catch
        {
            $message = "Failed to configure TLS security protocol: $($_.Exception.Message)"
            $exception = New-Object System.InvalidOperationException($message, $_.Exception)
            $errorRecord = New-Object System.Management.Automation.ErrorRecord(
                $exception,
                'SetTlsSecurityProtocolFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                [Net.ServicePointManager]
            )

            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    end
    {
        Write-Verbose 'TLS security protocol configuration completed'
    }
}
