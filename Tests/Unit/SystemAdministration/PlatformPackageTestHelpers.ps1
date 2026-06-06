# Shared helpers for platform package unit tests.

function Get-TestCommandResponse
{
    param(
        [Parameter()]
        [Int32]$ExitCode = 0,

        [Parameter()]
        [String[]]$Output = @()
    )

    [PSCustomObject]@{
        ExitCode = $ExitCode
        Output = @($Output)
    }
}

$script:NewTestCommandResponse = {
    param(
        [Parameter()]
        [Int32]$ExitCode = 0,

        [Parameter()]
        [String[]]$Output = @()
    )

    Get-TestCommandResponse -ExitCode $ExitCode -Output $Output
}

$script:NewPackageCommandRunner = {
    param(
        [Parameter(Mandatory)]
        [Hashtable]$Responses
    )

    $localResponses = $Responses
    $localInvocations = $script:Invocations

    return {
        param(
            [Parameter(Mandatory)]
            [String]$Command,

            [Parameter()]
            [String[]]$Arguments = @(),

            [Parameter()]
            [Switch]$StreamOutput
        )

        $key = "$Command $($Arguments -join ' ')".Trim()
        $localInvocations.Add([PSCustomObject]@{
                Command = $Command
                Arguments = @($Arguments)
                Key = $key
                StreamOutput = $StreamOutput.IsPresent
            })

        if ($localResponses.ContainsKey($key))
        {
            return $localResponses[$key]
        }

        return Get-TestCommandResponse -ExitCode 127 -Output @("Unexpected command: $key")
    }.GetNewClosure()
}

$script:NewNativeBrewCommand = {
    param(
        [Parameter(Mandatory)]
        [String]$Directory
    )

    New-Item -Path $Directory -ItemType Directory -Force | Out-Null

    $isWindowsPlatform = if ($PSVersionTable.PSVersion.Major -lt 6)
    {
        $true
    }
    else
    {
        [Bool]$IsWindows
    }

    if ($isWindowsPlatform)
    {
        $brewPath = Join-Path -Path $Directory -ChildPath 'brew.cmd'
        $content = @'
@echo off
if not "%UPGRADE_TEST_BREW_LOG_PATH%"=="" echo %*>>"%UPGRADE_TEST_BREW_LOG_PATH%"

if /I "%*"=="update --quiet" (
    echo brew update stdout
    1>&2 echo brew update stderr
    exit /b 0
)

if /I "%*"=="outdated --json=v2 --greedy" (
    echo {"formulae":[{"name":"git","installed_versions":["2.43.0"],"current_version":"2.44.0","pinned":false,"desc":"Git SCM"}],"casks":[]}
    exit /b 0
)

if /I "%*"=="upgrade git" (
    echo brew upgrade stdout
    1>&2 echo brew upgrade stderr
    exit /b 0
)

1>&2 echo Unexpected brew command: %*
exit /b 64
'@
    }
    else
    {
        $brewPath = Join-Path -Path $Directory -ChildPath 'brew'
        $content = @'
#!/bin/sh
if [ -n "$UPGRADE_TEST_BREW_LOG_PATH" ]; then
    printf '%s\n' "$*" >> "$UPGRADE_TEST_BREW_LOG_PATH"
fi

if [ "$1" = "update" ] && [ "$2" = "--quiet" ]; then
    echo "brew update stdout"
    echo "brew update stderr" >&2
    exit 0
fi

if [ "$1" = "outdated" ] && [ "$2" = "--json=v2" ] && [ "$3" = "--greedy" ]; then
    echo '{"formulae":[{"name":"git","installed_versions":["2.43.0"],"current_version":"2.44.0","pinned":false,"desc":"Git SCM"}],"casks":[]}'
    exit 0
fi

if [ "$1" = "upgrade" ] && [ "$2" = "git" ]; then
    echo "brew upgrade stdout"
    echo "brew upgrade stderr" >&2
    exit 0
fi

echo "Unexpected brew command: $*" >&2
exit 64
'@
    }

    [System.IO.File]::WriteAllText($brewPath, $content, [System.Text.UTF8Encoding]::new($false))

    if (-not $isWindowsPlatform)
    {
        $chmodCommand = Get-Command -Name 'chmod' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
        if ($chmodCommand)
        {
            & $chmodCommand.Source 755 $brewPath
        }
    }

    return $brewPath
}

$script:NewPromptReader = {
    param(
        [Parameter()]
        [String[]]$Values
    )

    $queue = [System.Collections.Generic.Queue[String]]::new()
    $Values | ForEach-Object { $queue.Enqueue($_) }

    return {
        param(
            [Parameter()]
            [String]$Prompt
        )

        if ($queue.Count -eq 0)
        {
            throw "Unexpected prompt: $Prompt"
        }

        return $queue.Dequeue()
    }.GetNewClosure()
}

$script:NewKeyReader = {
    param(
        [Parameter()]
        [System.ConsoleKeyInfo[]]$Values
    )

    $queue = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
    $Values | ForEach-Object { $queue.Enqueue($_) }

    return {
        if ($queue.Count -eq 0)
        {
            throw 'Unexpected key read'
        }

        return $queue.Dequeue()
    }.GetNewClosure()
}

$script:NewTerminalEchoController = {
    param(
        [Parameter()]
        [System.Collections.Generic.List[Object]]$Actions,

        [Parameter()]
        [String]$SavedState = 'saved-stty-state'
    )

    if ($null -eq $Actions)
    {
        $Actions = New-Object 'System.Collections.Generic.List[Object]'
    }

    $localActions = $Actions
    $localSavedState = $SavedState

    return {
        param(
            [Parameter()]
            [String]$Action,

            [Parameter()]
            [String]$State
        )

        switch ($Action)
        {
            'Disable'
            {
                $localActions.Add('Disable')
                return $localSavedState
            }
            'Restore'
            {
                $localActions.Add("Restore:$State")
                return
            }
            default
            {
                throw "Unexpected terminal echo action: $Action"
            }
        }
    }.GetNewClosure()
}

function Get-TestPickerLineLimit
{
    $limit = 0
    try
    {
        if (-not [Console]::IsOutputRedirected)
        {
            $limit = [Console]::BufferWidth - 1
        }
    }
    catch
    {
        $limit = 0
    }

    if ($limit -le 0)
    {
        try
        {
            $limit = $Host.UI.RawUI.BufferSize.Width - 1
        }
        catch
        {
            $limit = 0
        }
    }

    if ($limit -le 0)
    {
        $limit = 119
    }

    return [Math]::Max(60, $limit)
}
