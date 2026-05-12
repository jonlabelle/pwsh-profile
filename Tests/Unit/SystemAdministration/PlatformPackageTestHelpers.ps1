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
