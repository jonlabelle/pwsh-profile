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

    .PARAMETER Protocol
        The TLS protocol configuration to apply.
        Valid values: SystemDefault, Tls, Tls11, Tls12, Tls13.
        Default is SystemDefault. 'SystemDefault' allows the OS to choose the best protocol.

    .PARAMETER Force
        Replaces the current explicit protocol set with the resolved target protocol,
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

    .OUTPUTS
        System.Net.SecurityProtocolType
        When PassThru is specified, returns the current SecurityProtocol setting.

    .NOTES
        - PowerShell Desktop (5.1) on older Windows supports up to TLS 1.2.
        - PowerShell Core (6+) and modern Windows versions may support TLS 1.3.
        - Using 'SystemDefault' is recommended for forward compatibility.
        - When SystemDefault is unavailable, the function falls back to the best
          explicit protocol set available on the current platform.
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

        $protocolDefinitions = @(
            [PSCustomObject]@{ Name = 'Tls'; Strength = 1 }
            [PSCustomObject]@{ Name = 'Tls11'; Strength = 2 }
            [PSCustomObject]@{ Name = 'Tls12'; Strength = 3 }
            [PSCustomObject]@{ Name = 'Tls13'; Strength = 4 }
            [PSCustomObject]@{ Name = 'SystemDefault'; Strength = 99 }
        )

        $protocolDefinitionsByName = @{}
        $availableProtocols = @{}

        foreach ($definition in $protocolDefinitions)
        {
            $protocolDefinitionsByName[$definition.Name] = $definition

            try
            {
                $protocolValue = [Net.SecurityProtocolType]::$($definition.Name)
                $availableProtocols[$definition.Name] = [PSCustomObject]@{
                    Name = $definition.Name
                    Strength = $definition.Strength
                    Value = [System.Net.SecurityProtocolType]$protocolValue
                }

                Write-Verbose "Protocol '$($definition.Name)' is available on this system."
            }
            catch
            {
                Write-Verbose "Protocol '$($definition.Name)' is not available on this system."
            }
        }

        $availableExplicitProtocols = @(
            $availableProtocols.Values |
            Where-Object { $_.Name -ne 'SystemDefault' } |
            Sort-Object -Property Strength
        )

        if ($availableExplicitProtocols.Count -eq 0)
        {
            throw 'No supported TLS protocol values are available on this system.'
        }

        $securePreservationFloor = $protocolDefinitionsByName['Tls12'].Strength
        $systemDefaultInfo = if ($availableProtocols.ContainsKey('SystemDefault')) { $availableProtocols['SystemDefault'] } else { $null }

        function Format-ProtocolDisplay
        {
            param(
                [Parameter(Mandatory)]
                [System.Net.SecurityProtocolType]$Value
            )

            if ($systemDefaultInfo -and $Value -eq $systemDefaultInfo.Value)
            {
                return 'SystemDefault'
            }

            $enabledNames = New-Object 'System.Collections.Generic.List[string]'
            $matchedValue = [System.Net.SecurityProtocolType]0

            foreach ($definition in $availableExplicitProtocols)
            {
                if (($Value -band $definition.Value) -ne 0)
                {
                    $enabledNames.Add($definition.Name)
                    $matchedValue = $matchedValue -bor $definition.Value
                }
            }

            if ($enabledNames.Count -eq 0)
            {
                return $Value.ToString()
            }

            if ($matchedValue -ne $Value)
            {
                return $Value.ToString()
            }

            return ($enabledNames -join ', ')
        }

        function Get-ResolvedProtocolInfo
        {
            param(
                [Parameter(Mandatory)]
                [String]$RequestedProtocol
            )

            if ($availableProtocols.ContainsKey($RequestedProtocol))
            {
                return [PSCustomObject]@{
                    Protocol = $availableProtocols[$RequestedProtocol]
                    IsFallback = $false
                    Direction = $null
                }
            }

            $requestedDefinition = $protocolDefinitionsByName[$RequestedProtocol]
            $strongerProtocol = @(
                $availableExplicitProtocols |
                Where-Object { $_.Strength -gt $requestedDefinition.Strength } |
                Select-Object -First 1
            )

            if ($strongerProtocol.Count -gt 0)
            {
                return [PSCustomObject]@{
                    Protocol = $strongerProtocol[0]
                    IsFallback = $true
                    Direction = 'Higher'
                }
            }

            $lowerProtocol = @(
                $availableExplicitProtocols |
                Where-Object { $_.Strength -lt $requestedDefinition.Strength } |
                Sort-Object -Property Strength -Descending |
                Select-Object -First 1
            )

            if ($lowerProtocol.Count -gt 0)
            {
                return [PSCustomObject]@{
                    Protocol = $lowerProtocol[0]
                    IsFallback = $true
                    Direction = 'Lower'
                }
            }

            return $null
        }

        function Get-BestExplicitDefaultProtocol
        {
            $secureProtocols = @(
                $availableExplicitProtocols |
                Where-Object { $_.Strength -ge $securePreservationFloor }
            )

            if ($secureProtocols.Count -gt 0)
            {
                $protocolValue = [System.Net.SecurityProtocolType]0

                foreach ($protocolInfo in $secureProtocols)
                {
                    $protocolValue = $protocolValue -bor $protocolInfo.Value
                }

                return $protocolValue
            }

            $strongestProtocol = @(
                $availableExplicitProtocols |
                Sort-Object -Property Strength -Descending |
                Select-Object -First 1
            )

            return $strongestProtocol[0].Value
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

            if (-not $Force)
            {
                if ($currentState.FallbackUsed)
                {
                    if ($Protocol -eq 'SystemDefault')
                    {
                        Write-Verbose "SystemDefault is not available on this system. Falling back to: $($currentState.TargetProtocolDisplay)"
                    }
                    elseif ($currentState.FallbackDirection -eq 'Higher')
                    {
                        Write-Verbose "Requested protocol '$Protocol' is not available on this system. Using stronger available protocol '$($currentState.ResolvedProtocol)'."
                    }
                    else
                    {
                        Write-Verbose "Requested protocol '$Protocol' is not available on this system. Falling back to '$($currentState.ResolvedProtocol)'."
                    }
                }

                if (-not $currentState.ChangeRequired)
                {
                    Write-Verbose 'Security protocol already meets the requested requirements.'

                    if ($PassThru)
                    {
                        return $currentProtocol
                    }

                    return
                }

                $targetProtocol = $currentState.TargetProtocol
                $targetDisplay = $currentState.TargetProtocolDisplay
            }
            elseif ($Protocol -eq 'SystemDefault')
            {
                if ($systemDefaultInfo)
                {
                    $targetProtocol = $systemDefaultInfo.Value
                    $targetDisplay = 'SystemDefault'
                }
                else
                {
                    $targetProtocol = Get-BestExplicitDefaultProtocol
                    $targetDisplay = Format-ProtocolDisplay -Value $targetProtocol
                    Write-Verbose "SystemDefault is not available on this system. Falling back to: $targetDisplay"
                }
            }
            else
            {
                $resolvedProtocolInfo = Get-ResolvedProtocolInfo -RequestedProtocol $Protocol
                if (-not $resolvedProtocolInfo)
                {
                    throw "Requested protocol '$Protocol' is not available on this system."
                }

                $effectiveProtocol = $resolvedProtocolInfo.Protocol
                if ($resolvedProtocolInfo.IsFallback)
                {
                    if ($resolvedProtocolInfo.Direction -eq 'Higher')
                    {
                        Write-Verbose "Requested protocol '$Protocol' is not available on this system. Using stronger available protocol '$($effectiveProtocol.Name)'."
                    }
                    else
                    {
                        Write-Verbose "Requested protocol '$Protocol' is not available on this system. Falling back to '$($effectiveProtocol.Name)'."
                    }
                }

                $targetProtocol = $effectiveProtocol.Value
                $targetDisplay = Format-ProtocolDisplay -Value $targetProtocol
            }

            if ($Force -or $currentProtocol -ne $targetProtocol)
            {
                if ($PSCmdlet.ShouldProcess('Net.ServicePointManager.SecurityProtocol', "Set TLS protocols to $targetDisplay"))
                {
                    [Net.ServicePointManager]::SecurityProtocol = $targetProtocol
                    Write-Verbose "Updated security protocol to: $targetDisplay"
                }
            }
            else
            {
                Write-Verbose 'Security protocol already meets the requested requirements.'
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
