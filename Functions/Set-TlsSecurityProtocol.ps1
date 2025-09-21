function Set-TlsSecurityProtocol {
    <#
    .SYNOPSIS
        Configures TLS security protocol settings for secure network connections.

    .DESCRIPTION
        This function intelligently configures the .NET ServicePointManager SecurityProtocol
        setting to ensure secure TLS connections. It only updates the protocol if it's not
        already set to TLS 1.2 or higher, preserving existing secure configurations.

        The function supports both PowerShell Desktop (5.1) and PowerShell Core (6+),
        automatically detecting available TLS versions based on the PowerShell version.

    .PARAMETER MinimumVersion
        The minimum TLS version to ensure is enabled. Valid values are Tls, Tls11, Tls12, and Tls13.
        Default is Tls12. Note that Tls13 is only available on PowerShell Core 6+ and supported systems.

    .PARAMETER Force
        Forces the security protocol to be set even if a secure version is already configured.
        Use this parameter to ensure specific TLS versions are enabled.

    .PARAMETER PassThru
        Returns the current security protocol setting after any changes are made.

    .EXAMPLE
        PS > Set-TlsSecurityProtocol
        Configures TLS 1.2 as the minimum security protocol if not already set.

    .EXAMPLE
        PS > Set-TlsSecurityProtocol -MinimumVersion Tls12 -Verbose
        VERBOSE: Current security protocol: Ssl3, Tls
        VERBOSE: Updated security protocol to include TLS 1.2 for secure connections
        Configures TLS 1.2 with verbose output showing the changes made.

    .EXAMPLE
        PS > Set-TlsSecurityProtocol -Force -PassThru
        Tls12
        Forces TLS 1.2 configuration and returns the resulting security protocol.

    .EXAMPLE
        PS > Set-TlsSecurityProtocol -MinimumVersion Tls13 -Verbose
        VERBOSE: Current security protocol: Tls12
        VERBOSE: TLS 1.3 not available on this system, using TLS 1.2 as minimum
        VERBOSE: Security protocol already configured with TLS 1.2 or higher
        Attempts to configure TLS 1.3 but falls back to TLS 1.2 if not available.

    .OUTPUTS
        System.Net.SecurityProtocolType
        When PassThru is specified, returns the current SecurityProtocol setting.

    .NOTES
        - PowerShell Desktop (5.1) supports up to TLS 1.2
        - PowerShell Core (6+) may support TLS 1.3 depending on the underlying system
        - Changes are made to the global ServicePointManager settings
        - The function preserves existing secure configurations by default
    #>
    [CmdletBinding()]
    [OutputType([System.Net.SecurityProtocolType])]
    param(
        [Parameter()]
        [ValidateSet('Tls', 'Tls11', 'Tls12', 'Tls13')]
        [String]$MinimumVersion = 'Tls12',

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Switch]$PassThru
    )

    begin {
        Write-Verbose "Starting TLS security protocol configuration (Minimum: $MinimumVersion)"
    }

    process {
        try {
            $currentProtocol = [Net.ServicePointManager]::SecurityProtocol
            Write-Verbose "Current security protocol: $currentProtocol"

            # Build the desired protocol flags
            try {
                $desiredProtocol = [Net.SecurityProtocolType]::$MinimumVersion
            } catch {
                # If the requested protocol is not available, fall back to TLS 1.2
                Write-Verbose "Requested protocol $MinimumVersion not available, falling back to TLS 1.2"
                $desiredProtocol = [Net.SecurityProtocolType]::Tls12
            }

            # Add TLS 1.3 support if available and requested
            if ($MinimumVersion -eq 'Tls13' -and $PSVersionTable.PSVersion.Major -ge 6) {
                try {
                    $tls13 = [Net.SecurityProtocolType]::Tls13
                    $desiredProtocol = $desiredProtocol -bor $tls13
                    Write-Verbose 'TLS 1.3 support added to desired protocol'
                } catch {
                    Write-Verbose 'TLS 1.3 not available on this system, using TLS 1.2 as minimum'
                    $desiredProtocol = [Net.SecurityProtocolType]::Tls12
                }
            }

            # Check if we need to update the protocol
            $needsUpdate = $Force -or (($currentProtocol -band $desiredProtocol) -eq 0)

            if ($needsUpdate) {
                # Preserve existing secure protocols and add the minimum required
                if (-not $Force -and $currentProtocol -ne [Net.SecurityProtocolType]::SystemDefault) {
                    # Keep existing protocols that are TLS 1.2 or higher
                    $secureProtocols = @('Tls12', 'Tls13')
                    foreach ($protocol in $secureProtocols) {
                        try {
                            $protocolValue = [Net.SecurityProtocolType]::$protocol
                            if (($currentProtocol -band $protocolValue) -ne 0) {
                                $desiredProtocol = $desiredProtocol -bor $protocolValue
                            }
                        } catch {
                            # Protocol not available on this system
                            continue
                        }
                    }
                }

                [Net.ServicePointManager]::SecurityProtocol = $desiredProtocol
                Write-Verbose "Updated security protocol to: $desiredProtocol"
            } else {
                Write-Verbose "Security protocol already configured with $MinimumVersion or higher"
            }

            if ($PassThru) {
                return [Net.ServicePointManager]::SecurityProtocol
            }
        }
        catch {
            Write-Error "Failed to configure TLS security protocol: $($_.Exception.Message)"
            throw
        }
    }

    end {
        Write-Verbose 'TLS security protocol configuration completed'
    }
}
