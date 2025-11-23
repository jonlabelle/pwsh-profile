function Set-TlsSecurityProtocol
{
    <#
    .SYNOPSIS
        Configures TLS security protocol settings for secure network connections.

    .DESCRIPTION
        This function intelligently configures the .NET ServicePointManager SecurityProtocol
        setting to ensure secure TLS connections. It supports both PowerShell Desktop (5.1)
        and PowerShell Core (6+).

        On modern systems, it's often best to let the operating system decide the best
        security protocol by not setting a specific version. This function defaults to
        letting the operating system decide the best security protocol, but can be used
        to enforce other versions.

    .PARAMETER Protocol
        The TLS protocol configuration to apply.
        Valid values: SystemDefault, Tls, Tls11, Tls12, Tls13.
        Default is SystemDefault. 'SystemDefault' allows the OS to choose the best protocol.

    .PARAMETER Force
        Forces the security protocol to be set, even if a secure version is already configured.
        This is useful for overwriting an existing configuration.

    .PARAMETER PassThru
        Returns the current security protocol setting after any changes are made.

    .EXAMPLE
        PS > Set-TlsSecurityProtocol

        Sets the security protocol to the operating system default for the current session.

    .EXAMPLE
        PS > Set-TlsSecurityProtocol -Protocol Tls13 -Verbose

        VERBOSE: Current security protocol: Tls12
        VERBOSE: TLS 1.3 is available on this system.
        VERBOSE: Updating security protocol to include Tls12, Tls13.

        Adds TLS 1.3 to the existing security protocols.

    .EXAMPLE
        PS > Set-TlsSecurityProtocol -Protocol Tls12

        Ensures at least TLS 1.2 is enabled, useful for older systems or specific compatibility requirements.

    .OUTPUTS
        System.Net.SecurityProtocolType
        When PassThru is specified, returns the current SecurityProtocol setting.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Set-TlsSecurityProtocol.ps1

        - PowerShell Desktop (5.1) on older Windows supports up to TLS 1.2.
        - PowerShell Core (6+) and modern Windows versions may support TLS 1.3.
        - Using 'SystemDefault' is recommended for forward compatibility.
        - Changes apply globally to the current PowerShell session.
    #>
    [CmdletBinding()]
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

        # Create a mapping of protocol names to their enum values and strength
        $protocolMap = @{
            'Tls' = @{ Value = 0; Strength = 1 }
            'Tls11' = @{ Value = 0; Strength = 2 }
            'Tls12' = @{ Value = 0; Strength = 3 }
            'Tls13' = @{ Value = 0; Strength = 4 }
            'SystemDefault' = @{ Value = 0; Strength = 99 } # Highest strength
        }

        # Populate enum values dynamically to avoid errors on older systems
        foreach ($name in $protocolMap.Keys)
        {
            try
            {
                $protocolMap[$name].Value = [Net.SecurityProtocolType]::$name
                Write-Verbose "Protocol '$name' is available on this system."
            }
            catch
            {
                Write-Verbose "Protocol '$name' is not available on this system."
                $protocolMap.Remove($name)
            }
        }
    }

    process
    {
        try
        {
            $currentProtocol = [Net.ServicePointManager]::SecurityProtocol
            Write-Verbose "Current security protocol: $currentProtocol"

            # Handle SystemDefault as a special case
            if ($Protocol -eq 'SystemDefault')
            {
                if ($Force -or $currentProtocol -ne $protocolMap.SystemDefault.Value)
                {
                    [Net.ServicePointManager]::SecurityProtocol = $protocolMap.SystemDefault.Value
                    Write-Verbose 'Updated security protocol to: SystemDefault'
                }
                else
                {
                    Write-Verbose 'Security protocol is already set to SystemDefault.'
                }
            }
            else
            {
                # Determine if the current configuration is already sufficient
                $isSufficient = $false
                $minStrength = $protocolMap[$Protocol].Strength
                foreach ($protocolName in $protocolMap.Keys)
                {
                    if ($protocolMap[$protocolName].Strength -ge $minStrength)
                    {
                        if (($currentProtocol -band $protocolMap[$protocolName].Value) -ne 0)
                        {
                            $isSufficient = $true
                            break
                        }
                    }
                }

                if (-not $isSufficient -or $Force)
                {
                    # Build the new protocol by combining all available protocols >= minimum
                    $newProtocol = [Net.SecurityProtocolType]0
                    foreach ($protocolName in $protocolMap.Keys)
                    {
                        if ($protocolMap[$protocolName].Strength -ge $minStrength -and $protocolName -ne 'SystemDefault')
                        {
                            $newProtocol = $newProtocol -bor $protocolMap[$protocolName].Value
                        }
                    }

                    # If forcing, this becomes the new value. Otherwise, add to existing.
                    if (-not $Force -and $currentProtocol -ne 'SystemDefault')
                    {
                        $newProtocol = $currentProtocol -bor $newProtocol
                    }

                    if ($newProtocol -ne $currentProtocol)
                    {
                        [Net.ServicePointManager]::SecurityProtocol = $newProtocol
                        Write-Verbose "Updated security protocol to: $newProtocol"
                    }
                    else
                    {
                        Write-Verbose 'Security protocol already meets the requirements. No change needed.'
                    }
                }
                else
                {
                    Write-Verbose "Security protocol already configured with $Protocol or higher."
                }
            }

            if ($PassThru)
            {
                return [Net.ServicePointManager]::SecurityProtocol
            }
        }
        catch
        {
            Write-Error "Failed to configure TLS security protocol: $($_.Exception.Message)"
            throw
        }
    }

    end
    {
        Write-Verbose 'TLS security protocol configuration completed'
    }
}
