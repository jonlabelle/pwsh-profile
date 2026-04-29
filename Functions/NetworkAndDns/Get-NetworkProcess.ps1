function Get-NetworkProcess
{
    <#
    .SYNOPSIS
        Shows local network ports and the processes using them.

    .DESCRIPTION
        Retrieves active TCP and UDP sockets from the local computer and returns
        structured objects that map ports to owning processes. Use -Port to find
        which process is using a specific port, or use -ProcessId/-ProcessName to
        show which ports a process is using.

        On Windows, this function parses netstat -ano output and resolves process
        names with Get-Process. On macOS and Linux, it uses lsof when available,
        falling back to ss on Linux. Some operating systems hide sockets owned by
        other users unless PowerShell is running with elevated privileges.

        Compatible with PowerShell Desktop 5.1+ on Windows and PowerShell Core on
        Windows, macOS, and Linux.

    .PARAMETER Port
        Local port numbers to inspect. Use -IncludeRemotePort to match remote ports as well.

    .PARAMETER ProcessId
        Process IDs to inspect.

    .PARAMETER ProcessName
        Process names to inspect. Wildcards are supported.

    .PARAMETER Protocol
        Protocol to include. Valid values are All, TCP, and UDP.
        The default is All.

    .PARAMETER IncludeRemotePort
        Match -Port values against both local and remote ports.

    .PARAMETER Listening
        Show only listening TCP sockets and bound UDP sockets.

    .PARAMETER Established
        Show only established TCP connections.

    .EXAMPLE
        PS > Get-NetworkProcess -Port 5432

        Shows the process using local port 5432.

    .EXAMPLE
        PS > Get-NetworkProcess -ProcessName 'postgres*'

        Shows ports used by processes with names matching postgres*.

    .EXAMPLE
        PS > Get-NetworkProcess -ProcessId $PID

        Shows network ports used by the current PowerShell process.

    .EXAMPLE
        PS > Get-NetworkProcess -Port 443 -IncludeRemotePort -Established

        Shows established connections where either the local or remote port is 443.

    .EXAMPLE
        PS > 3000, 5000 | Get-NetworkProcess -Listening

        Shows listening sockets for ports 3000 and 5000 using pipeline input.

    .EXAMPLE
        PS > Get-NetworkProcess -Protocol UDP

        Shows UDP sockets and their owning processes.

    .EXAMPLE
        PS > Get-NetworkProcess -Listening | Sort-Object LocalPort

        Shows listening TCP sockets and bound UDP sockets sorted by local port.

    .EXAMPLE
        PS > Get-NetworkProcess -ProcessName 'pwsh' -Protocol TCP

        Shows TCP sockets owned by PowerShell processes.

    .EXAMPLE
        PS > Get-NetworkProcess -Port 53 -Protocol UDP

        Shows UDP processes using local port 53.

    .EXAMPLE
        PS > Get-NetworkProcess -ProcessId 1234 -Established

        Shows established TCP connections owned by process ID 1234.

    .EXAMPLE
        PS > Get-NetworkProcess | Sort-Object LocalPort | Format-Table -AutoSize

        Protocol LocalAddress               LocalPort RemoteAddress              RemotePort State       ProcessName         ProcessId Source
        -------- ------------               --------- -------------              ---------- -----       -----------         --------- ---
        UDP      *                                                                          Unconnected identityservicesd         660 ls...
        UDP      *                                                                          Unconnected sharingd                  668 ls...
        TCP      *                          5000                                            Listen      ControlCenter             613 ls...
        TCP      *                          7000                                            Listen      ControlCenter             613 ls...
        TCP      127.0.0.1                  17600                                           Listen      SomeApp                   856 ls...
        TCP      127.0.0.1                  17603                                           Listen      SomeApp                   856 ls...
        TCP      127.0.0.1                  49275                                           Listen      SomeApp                  9180 ls...
        TCP      127.0.0.1                  49275     127.0.0.1                  49695      Established SomeApp                  9180 ls...
        TCP      127.0.0.1                  49275     127.0.0.1                  49685      Established SomeApp                  9180 ls...

        Shows all network ports and their owning processes, sorted by local port.

    .OUTPUTS
        PSCustomObject
        Returns objects with Protocol, LocalAddress, LocalPort, RemoteAddress,
        RemotePort, State, ProcessName, ProcessId, and Source properties.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-NetworkProcess.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Get-NetworkProcess.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('LocalPort')]
        [ValidateRange(1, 65535)]
        [Int[]]
        $Port,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Alias('PID')]
        [ValidateRange(0, 2147483647)]
        [Int[]]
        $ProcessId,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $ProcessName,

        [Parameter()]
        [ValidateSet('All', 'TCP', 'UDP')]
        [String]
        $Protocol = 'All',

        [Parameter()]
        [Switch]
        $IncludeRemotePort,

        [Parameter()]
        [Switch]
        $Listening,

        [Parameter()]
        [Switch]$Established,

        [Parameter(DontShow = $true)]
        [String[]]
        $RawConnectionOutput,

        [Parameter(DontShow = $true)]
        [ValidateSet('Auto', 'Lsof', 'Netstat', 'Ss')]
        [String]
        $InputFormat = 'Auto'
    )

    begin
    {
        if ($Listening -and $Established)
        {
            throw '-Listening and -Established cannot be used together.'
        }

        $requestedPorts = New-Object System.Collections.ArrayList
        $processNameById = @{}

        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $isWindowsPlatform = $true
            $isMacOSPlatform = $false
            $isLinuxPlatform = $false
        }
        else
        {
            $isWindowsPlatform = $IsWindows
            $isMacOSPlatform = $IsMacOS
            $isLinuxPlatform = $IsLinux
        }

        function ConvertFrom-NetworkEndpoint
        {
            param(
                [AllowNull()]
                [String]$Endpoint
            )

            $address = ''
            $port = $null

            if ([String]::IsNullOrWhiteSpace($Endpoint))
            {
                return [PSCustomObject]@{
                    Address = $address
                    Port = $port
                }
            }

            $endpointText = $Endpoint.Trim()
            $portText = ''

            if ($endpointText -match '^\[(?<Address>.+)\]:(?<Port>[^:]+)$')
            {
                $address = $Matches.Address
                $portText = $Matches.Port
            }
            else
            {
                $separatorIndex = $endpointText.LastIndexOf(':')

                if ($separatorIndex -ge 0)
                {
                    $address = $endpointText.Substring(0, $separatorIndex)
                    $portText = $endpointText.Substring($separatorIndex + 1)
                }
                else
                {
                    $address = $endpointText
                }
            }

            $address = $address.Trim()
            if ($address.StartsWith('[') -and $address.EndsWith(']') -and $address.Length -gt 1)
            {
                $address = $address.Substring(1, $address.Length - 2)
            }

            if ([String]::IsNullOrWhiteSpace($address))
            {
                $address = '*'
            }

            if (-not [String]::IsNullOrWhiteSpace($portText) -and $portText -ne '*')
            {
                $parsedPort = 0
                if ([Int]::TryParse($portText, [ref]$parsedPort))
                {
                    $port = $parsedPort
                }
                else
                {
                    $port = $portText
                }
            }

            [PSCustomObject]@{
                Address = $address
                Port = $port
            }
        }

        function ConvertTo-NetworkPortState
        {
            param(
                [AllowNull()]
                [String]$State,

                [AllowNull()]
                [String]$Protocol
            )

            if ([String]::IsNullOrWhiteSpace($State))
            {
                if ($Protocol -and $Protocol.ToUpperInvariant() -eq 'UDP')
                {
                    return 'Unconnected'
                }

                return ''
            }

            $stateText = $State.Trim()
            $normalizedState = $stateText.ToUpperInvariant().Replace('-', '_')

            switch -Regex ($normalizedState)
            {
                '^LISTEN(ING)?$' { return 'Listen' }
                '^ESTAB(LISHED)?$' { return 'Established' }
                '^UNCONN(ECTED)?$' { return 'Unconnected' }
                '^TIME_WAIT$' { return 'TimeWait' }
                '^CLOSE_WAIT$' { return 'CloseWait' }
                '^SYN_SENT$' { return 'SynSent' }
                '^SYN_RECV$' { return 'SynReceived' }
                '^FIN_WAIT_?1$' { return 'FinWait1' }
                '^FIN_WAIT_?2$' { return 'FinWait2' }
                '^LAST_ACK$' { return 'LastAck' }
                '^CLOSING$' { return 'Closing' }
                '^CLOSED$' { return 'Closed' }
                default { return $stateText }
            }
        }

        function Get-ProcessNameById
        {
            param(
                [Int]$Id
            )

            if ($Id -le 0)
            {
                return ''
            }

            if ($processNameById.ContainsKey($Id))
            {
                return $processNameById[$Id]
            }

            try
            {
                $process = Get-Process -Id $Id -ErrorAction Stop | Select-Object -First 1
                $resolvedName = if ($process) { $process.ProcessName } else { '' }
            }
            catch
            {
                $resolvedName = ''
            }

            $processNameById[$Id] = $resolvedName
            return $resolvedName
        }

        function ConvertTo-NetworkPortProcessObject
        {
            param(
                [AllowNull()]
                [String]$Protocol,

                [AllowNull()]
                [String]$LocalEndpoint,

                [AllowNull()]
                [String]$RemoteEndpoint,

                [AllowNull()]
                [String]$State,

                [Int]$ProcessId,

                [AllowNull()]
                [String]$ProcessName,

                [String]$Source
            )

            $protocolText = if ($Protocol) { $Protocol.ToUpperInvariant() } else { '' }
            $local = ConvertFrom-NetworkEndpoint -Endpoint $LocalEndpoint
            $remote = ConvertFrom-NetworkEndpoint -Endpoint $RemoteEndpoint

            [PSCustomObject]@{
                PSTypeName = 'Network.PortProcess'
                Protocol = $protocolText
                LocalAddress = $local.Address
                LocalPort = $local.Port
                RemoteAddress = $remote.Address
                RemotePort = $remote.Port
                State = ConvertTo-NetworkPortState -State $State -Protocol $protocolText
                ProcessName = if ($ProcessName) { $ProcessName } else { Get-ProcessNameById -Id $ProcessId }
                ProcessId = $ProcessId
                Source = $Source
            }
        }

        function ConvertFrom-LsofConnectionOutput
        {
            param(
                [String[]]$InputObject
            )

            $currentProcessId = 0
            $currentProcessName = ''
            $currentProtocol = ''
            $currentEndpoint = ''
            $currentState = ''

            function Add-LsofConnection
            {
                if ([String]::IsNullOrWhiteSpace($currentProtocol) -or [String]::IsNullOrWhiteSpace($currentEndpoint))
                {
                    return
                }

                $endpointParts = $currentEndpoint -split '->', 2
                $localEndpoint = $endpointParts[0]
                $remoteEndpoint = if ($endpointParts.Count -gt 1) { $endpointParts[1] } else { '' }

                ConvertTo-NetworkPortProcessObject -Protocol $currentProtocol -LocalEndpoint $localEndpoint -RemoteEndpoint $remoteEndpoint -State $currentState -ProcessId $currentProcessId -ProcessName $currentProcessName -Source 'lsof'
            }

            foreach ($line in $InputObject)
            {
                if ([String]::IsNullOrWhiteSpace($line) -or $line.Length -lt 2)
                {
                    continue
                }

                $fieldName = $line.Substring(0, 1)
                $fieldValue = $line.Substring(1)

                switch -CaseSensitive ($fieldName)
                {
                    'p'
                    {
                        Add-LsofConnection

                        $parsedProcessId = 0
                        if ([Int]::TryParse($fieldValue, [ref]$parsedProcessId))
                        {
                            $currentProcessId = $parsedProcessId
                        }
                        else
                        {
                            $currentProcessId = 0
                        }

                        $currentProcessName = ''
                        $currentProtocol = ''
                        $currentEndpoint = ''
                        $currentState = ''
                    }
                    'c'
                    {
                        $currentProcessName = $fieldValue
                    }
                    'P'
                    {
                        Add-LsofConnection
                        $currentProtocol = $fieldValue.ToUpperInvariant()
                        $currentEndpoint = ''
                        $currentState = ''
                    }
                    'n'
                    {
                        $currentEndpoint = $fieldValue
                    }
                    'T'
                    {
                        if ($fieldValue -match '^ST=(.+)$')
                        {
                            $currentState = $Matches[1]
                        }
                    }
                }
            }

            Add-LsofConnection
        }

        function ConvertFrom-NetstatConnectionOutput
        {
            param(
                [String[]]$InputObject
            )

            foreach ($line in $InputObject)
            {
                if ([String]::IsNullOrWhiteSpace($line))
                {
                    continue
                }

                $trimmedLine = $line.Trim()
                if ($trimmedLine -notmatch '^(TCP|UDP)\s+')
                {
                    continue
                }

                $parts = $trimmedLine -split '\s+'
                $protocolText = $parts[0].ToUpperInvariant()

                if ($protocolText -eq 'TCP' -and $parts.Count -ge 5)
                {
                    $parsedProcessId = 0
                    [void][Int]::TryParse($parts[4], [ref]$parsedProcessId)

                    ConvertTo-NetworkPortProcessObject -Protocol $protocolText -LocalEndpoint $parts[1] -RemoteEndpoint $parts[2] -State $parts[3] -ProcessId $parsedProcessId -ProcessName '' -Source 'netstat'
                }
                elseif ($protocolText -eq 'UDP' -and $parts.Count -ge 4)
                {
                    $parsedProcessId = 0
                    [void][Int]::TryParse($parts[$parts.Count - 1], [ref]$parsedProcessId)

                    ConvertTo-NetworkPortProcessObject -Protocol $protocolText -LocalEndpoint $parts[1] -RemoteEndpoint $parts[2] -State '' -ProcessId $parsedProcessId -ProcessName '' -Source 'netstat'
                }
            }
        }

        function ConvertFrom-SsConnectionOutput
        {
            param(
                [String[]]$InputObject
            )

            foreach ($line in $InputObject)
            {
                if ([String]::IsNullOrWhiteSpace($line))
                {
                    continue
                }

                $trimmedLine = $line.Trim()
                if ($trimmedLine -notmatch '^(tcp|udp)\s+')
                {
                    continue
                }

                $parts = $trimmedLine -split '\s+'
                if ($parts.Count -lt 6)
                {
                    continue
                }

                $protocolText = if ($parts[0] -like 'tcp*') { 'TCP' } else { 'UDP' }
                $stateText = $parts[1]
                $localEndpoint = $parts[4]
                $remoteEndpoint = $parts[5]
                $processText = if ($parts.Count -gt 6) { $parts[6..($parts.Count - 1)] -join ' ' } else { '' }
                $parsedProcessId = 0
                $resolvedProcessName = ''

                if ($processText -match '"(?<Name>(?:[^"\\]|\\.)*)",pid=(?<ProcessId>\d+)')
                {
                    $resolvedProcessName = $Matches.Name -replace '\\"', '"'
                    [void][Int]::TryParse($Matches.ProcessId, [ref]$parsedProcessId)
                }
                elseif ($processText -match 'pid=(?<ProcessId>\d+)')
                {
                    [void][Int]::TryParse($Matches.ProcessId, [ref]$parsedProcessId)
                }

                ConvertTo-NetworkPortProcessObject -Protocol $protocolText -LocalEndpoint $localEndpoint -RemoteEndpoint $remoteEndpoint -State $stateText -ProcessId $parsedProcessId -ProcessName $resolvedProcessName -Source 'ss'
            }
        }

        function ConvertFrom-RawConnectionOutput
        {
            param(
                [String[]]$InputObject,
                [String]$Format
            )

            $resolvedFormat = $Format
            if ($resolvedFormat -eq 'Auto')
            {
                if ($InputObject | Where-Object { $_ -match '^p\d+$' } | Select-Object -First 1)
                {
                    $resolvedFormat = 'Lsof'
                }
                elseif ($InputObject | Where-Object { $_ -match '^\s*(TCP|UDP)\s+' } | Select-Object -First 1)
                {
                    $resolvedFormat = 'Netstat'
                }
                else
                {
                    $resolvedFormat = 'Ss'
                }
            }

            switch ($resolvedFormat)
            {
                'Lsof' { ConvertFrom-LsofConnectionOutput -InputObject $InputObject }
                'Netstat' { ConvertFrom-NetstatConnectionOutput -InputObject $InputObject }
                'Ss' { ConvertFrom-SsConnectionOutput -InputObject $InputObject }
            }
        }

        function Get-NativeNetworkPortProcess
        {
            if ($isWindowsPlatform)
            {
                $netstatCommand = Get-Command -Name 'netstat' -CommandType Application -ErrorAction SilentlyContinue
                if (-not $netstatCommand)
                {
                    Write-Error "The 'netstat' command was not found. Cannot inspect local network ports on this Windows system."
                    return
                }

                Write-Verbose 'Inspecting network ports with netstat -ano'
                $netstatOutput = & netstat -ano 2>&1
                ConvertFrom-NetstatConnectionOutput -InputObject $netstatOutput
                return
            }

            $lsofCommand = Get-Command -Name 'lsof' -CommandType Application -ErrorAction SilentlyContinue
            if ($lsofCommand)
            {
                Write-Verbose 'Inspecting network ports with lsof'
                $lsofOutput = & lsof -nP -iTCP -iUDP -F pcPnT 2>&1
                ConvertFrom-LsofConnectionOutput -InputObject $lsofOutput
                return
            }

            if ($isLinuxPlatform)
            {
                $ssCommand = Get-Command -Name 'ss' -CommandType Application -ErrorAction SilentlyContinue
                if ($ssCommand)
                {
                    Write-Verbose 'Inspecting network ports with ss -H -tunap'
                    $ssOutput = & ss -H -tunap 2>&1
                    ConvertFrom-SsConnectionOutput -InputObject $ssOutput
                    return
                }
            }

            $platformName = if ($isMacOSPlatform) { 'macOS' } elseif ($isLinuxPlatform) { 'Linux' } else { 'this platform' }
            Write-Error "No supported network/process inventory command was found on $platformName. Install 'lsof' or, on Linux, 'ss'."
        }

        function Test-NetworkPortProcessMatch
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Connection,

                [Int[]]$PortsToMatch,

                [Int[]]$ProcessIdsToMatch,

                [String[]]$ProcessNamesToMatch
            )

            if ($Protocol -ne 'All' -and $Connection.Protocol -ne $Protocol)
            {
                return $false
            }

            if ($PortsToMatch -and $PortsToMatch.Count -gt 0)
            {
                $portMatches = $false

                if ($null -ne $Connection.LocalPort -and $Connection.LocalPort -is [Int])
                {
                    $portMatches = $PortsToMatch -contains $Connection.LocalPort
                }

                if (-not $portMatches -and $IncludeRemotePort -and $null -ne $Connection.RemotePort -and $Connection.RemotePort -is [Int])
                {
                    $portMatches = $PortsToMatch -contains $Connection.RemotePort
                }

                if (-not $portMatches)
                {
                    return $false
                }
            }

            if ($ProcessIdsToMatch -and $ProcessIdsToMatch.Count -gt 0 -and $ProcessIdsToMatch -notcontains $Connection.ProcessId)
            {
                return $false
            }

            if ($ProcessNamesToMatch -and $ProcessNamesToMatch.Count -gt 0)
            {
                $connectionProcessName = [String]$Connection.ProcessName
                $processNameMatches = $false

                foreach ($processNamePattern in $ProcessNamesToMatch)
                {
                    if ($connectionProcessName -like $processNamePattern)
                    {
                        $processNameMatches = $true
                        break
                    }
                }

                if (-not $processNameMatches)
                {
                    return $false
                }
            }

            if ($Listening -and $Connection.State -ne 'Listen' -and -not ($Connection.Protocol -eq 'UDP' -and $Connection.State -eq 'Unconnected'))
            {
                return $false
            }

            if ($Established -and $Connection.State -ne 'Established')
            {
                return $false
            }

            return $true
        }
    }

    process
    {
        if ($Port)
        {
            foreach ($portNumber in $Port)
            {
                [void]$requestedPorts.Add($portNumber)
            }
        }
    }

    end
    {
        $portsToMatch = @($requestedPorts | Sort-Object -Unique)
        $processIdsToMatch = if ($PSBoundParameters.ContainsKey('ProcessId')) { @($ProcessId | Sort-Object -Unique) } else { @() }
        $processNamesToMatch = if ($PSBoundParameters.ContainsKey('ProcessName')) { @($ProcessName) } else { @() }

        $connections = if ($PSBoundParameters.ContainsKey('RawConnectionOutput'))
        {
            ConvertFrom-RawConnectionOutput -InputObject $RawConnectionOutput -Format $InputFormat
        }
        else
        {
            Get-NativeNetworkPortProcess
        }

        $connections |
        Where-Object {
            Test-NetworkPortProcessMatch -Connection $_ -PortsToMatch $portsToMatch -ProcessIdsToMatch $processIdsToMatch -ProcessNamesToMatch $processNamesToMatch
        } |
        Sort-Object -Property Protocol, LocalAddress, LocalPort, RemoteAddress, RemotePort, State, ProcessName, ProcessId -Unique
    }
}
