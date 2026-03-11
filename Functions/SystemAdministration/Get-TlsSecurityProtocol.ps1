function Get-TlsSecurityProtocol
{
    <#
    .SYNOPSIS
        Gets the current TLS security protocol configuration for the PowerShell session.

    .DESCRIPTION
        Inspects the .NET ServicePointManager SecurityProtocol setting for the current
        PowerShell session and reports which TLS protocol values are available on the
        current system.

        When -Protocol is specified, the function also evaluates how
        Set-TlsSecurityProtocol would treat that request without -Force. This includes
        protocol fallback behavior when a requested version is unavailable and whether a
        change would be required for the current session.

    .PARAMETER Protocol
        Optional TLS protocol request to evaluate against the current session.
        Valid values: SystemDefault, Tls, Tls11, Tls12, Tls13.

    .EXAMPLE
        PS > Get-TlsSecurityProtocol

        Returns the current TLS security protocol setting for the session and the
        protocol values available on the current system.

    .EXAMPLE
        PS > Get-TlsSecurityProtocol -Protocol Tls12

        Returns the current setting plus evaluation details showing whether the session
        already satisfies a TLS 1.2 request and what target configuration would be used.

    .EXAMPLE
        PS > Get-TlsSecurityProtocol -Protocol SystemDefault | Select-Object CurrentProtocolDisplay, TargetProtocolDisplay, ChangeRequired

        Shows whether changing the current session to the operating system default would
        require an update.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        - PowerShell Desktop (5.1) on older Windows supports up to TLS 1.2.
        - PowerShell Core (6+) and modern Windows versions may support TLS 1.3.
        - Using 'SystemDefault' is recommended for forward compatibility when available.
        - Results apply to the current PowerShell session only.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Get-TlsSecurityProtocol.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Get-TlsSecurityProtocol.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/SystemAdministration/Set-TlsSecurityProtocol.ps1
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('SystemDefault', 'Tls', 'Tls11', 'Tls12', 'Tls13')]
        [String]$Protocol
    )

    begin
    {
        Write-Verbose 'Starting TLS security protocol inspection'

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

        function Get-EnabledProtocolNames
        {
            param(
                [Parameter(Mandatory)]
                [System.Net.SecurityProtocolType]$Value
            )

            if ($systemDefaultInfo -and $Value -eq $systemDefaultInfo.Value)
            {
                return @('SystemDefault')
            }

            $enabledNames = New-Object 'System.Collections.Generic.List[string]'

            foreach ($definition in $availableExplicitProtocols)
            {
                if (($Value -band $definition.Value) -ne 0)
                {
                    $enabledNames.Add($definition.Name)
                }
            }

            if ($enabledNames.Count -gt 0)
            {
                return $enabledNames.ToArray()
            }

            return @($Value.ToString())
        }

        function Format-ProtocolDisplay
        {
            param(
                [Parameter(Mandatory)]
                [System.Net.SecurityProtocolType]$Value
            )

            $enabledNames = @(Get-EnabledProtocolNames -Value $Value)
            if ($enabledNames.Count -eq 1)
            {
                return $enabledNames[0]
            }

            if ($enabledNames.Count -gt 1)
            {
                return ($enabledNames -join ', ')
            }

            return $Value.ToString()
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
            $currentProtocol = [Net.ServicePointManager]::SecurityProtocol
            $currentDisplay = Format-ProtocolDisplay -Value $currentProtocol
            $availableProtocolNames = @(
                $protocolDefinitions |
                Where-Object { $availableProtocols.ContainsKey($_.Name) } |
                ForEach-Object { $_.Name }
            )

            $result = [ordered]@{
                CurrentProtocol        = $currentProtocol
                CurrentProtocolDisplay = $currentDisplay
                EnabledProtocols       = [String[]]@(Get-EnabledProtocolNames -Value $currentProtocol)
                AvailableProtocols     = [String[]]$availableProtocolNames
                SupportsSystemDefault  = [Boolean]$systemDefaultInfo
                IsSystemDefault        = [Boolean]($systemDefaultInfo -and $currentProtocol -eq $systemDefaultInfo.Value)
            }

            if ($PSBoundParameters.ContainsKey('Protocol'))
            {
                $requestedProtocol = $Protocol
                $requestedAvailable = $availableProtocols.ContainsKey($requestedProtocol)
                $fallbackUsed = $false
                $fallbackDirection = $null

                if ($requestedProtocol -eq 'SystemDefault')
                {
                    if ($systemDefaultInfo)
                    {
                        $resolvedProtocol = 'SystemDefault'
                        $targetProtocol = $systemDefaultInfo.Value
                        $targetDisplay = 'SystemDefault'
                    }
                    else
                    {
                        $fallbackUsed = $true
                        $fallbackDirection = 'Explicit'
                        $targetProtocol = Get-BestExplicitDefaultProtocol
                        $targetDisplay = Format-ProtocolDisplay -Value $targetProtocol
                        $resolvedProtocol = $targetDisplay
                    }
                }
                else
                {
                    $resolvedProtocolInfo = Get-ResolvedProtocolInfo -RequestedProtocol $requestedProtocol
                    if (-not $resolvedProtocolInfo)
                    {
                        throw "Requested protocol '$requestedProtocol' is not available on this system."
                    }

                    $fallbackUsed = $resolvedProtocolInfo.IsFallback
                    $fallbackDirection = $resolvedProtocolInfo.Direction
                    $resolvedProtocol = $resolvedProtocolInfo.Protocol.Name
                    $targetProtocol = $resolvedProtocolInfo.Protocol.Value

                    $requestedStrength = $protocolDefinitionsByName[$requestedProtocol].Strength
                    $preservationFloor = [Math]::Min($requestedStrength, $securePreservationFloor)

                    foreach ($protocolInfo in $availableExplicitProtocols)
                    {
                        if ($protocolInfo.Strength -lt $preservationFloor)
                        {
                            continue
                        }

                        if (($currentProtocol -band $protocolInfo.Value) -ne 0)
                        {
                            $targetProtocol = $targetProtocol -bor $protocolInfo.Value
                        }
                    }

                    $targetDisplay = Format-ProtocolDisplay -Value $targetProtocol
                }

                $result['RequestedProtocol'] = $requestedProtocol
                $result['RequestedProtocolAvailable'] = $requestedAvailable
                $result['ResolvedProtocol'] = $resolvedProtocol
                $result['TargetProtocol'] = $targetProtocol
                $result['TargetProtocolDisplay'] = $targetDisplay
                $result['FallbackUsed'] = $fallbackUsed
                $result['FallbackDirection'] = $fallbackDirection
                $result['ChangeRequired'] = ($currentProtocol -ne $targetProtocol)
            }

            [PSCustomObject]$result
        }
        catch
        {
            $message = "Failed to inspect TLS security protocol: $($_.Exception.Message)"
            $exception = New-Object System.InvalidOperationException($message, $_.Exception)
            $errorRecord = New-Object System.Management.Automation.ErrorRecord(
                $exception,
                'GetTlsSecurityProtocolFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                [Net.ServicePointManager]
            )

            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    end
    {
        Write-Verbose 'TLS security protocol inspection completed'
    }
}
