function Get-WhichCommand
{
    <#
    .SYNOPSIS
        Locates a command and displays its location or type (mimics POSIX which).

    .DESCRIPTION
        Cross-platform function that mimics the behavior of the POSIX 'which' command.
        Searches for commands in the following order:
        1. PowerShell aliases
        2. PowerShell functions
        3. PowerShell cmdlets
        4. External executables in PATH

        Returns the full path for executables or the definition/type for PowerShell commands.
        Supports multiple command names and pipeline input.

        Aliases:
        The 'which' alias is created only if it doesn't already exist in the current environment.

    .PARAMETER Name
        The name of the command(s) to locate. Accepts multiple values and pipeline input.

    .PARAMETER All
        Display all matches instead of just the first one found.
        By default, only the first match is returned (mimics POSIX 'which' behavior).

    .PARAMETER Simple
        Return only the path for executables (mimics POSIX which behavior).
        Only applies to Application and ExternalScript command types.

    .EXAMPLE
        PS > Get-WhichCommand git

        CommandType     Name                           Definition
        -----------     ----                           ----------
        Application     git                            C:\Program Files\Git\cmd\git.exe

        Locates the git executable in PATH.

    .EXAMPLE
        PS > Get-WhichCommand ls

        CommandType     Name                           Definition
        -----------     ----                           ----------
        Alias           ls -> Get-ChildItem

        Shows that 'ls' is an alias for Get-ChildItem.

    .EXAMPLE
        PS > 'git', 'pwsh', 'Get-Process' | Get-WhichCommand

        Locates multiple commands via pipeline input.

    .EXAMPLE
        PS > Get-WhichCommand python -All

        CommandType     Name                           Definition
        -----------     ----                           ----------
        Application     python                         C:\Python39\python.exe
        Application     python                         C:\Python310\python.exe

        Shows all python executables found in PATH.

    .EXAMPLE
        PS > Get-WhichCommand git -Simple

        C:\Program Files\Git\cmd\git.exe

        Returns just the path string (POSIX which behavior).

    .OUTPUTS
        PSCustomObject with command details, or String when using -Simple switch.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [String])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String[]]$Name,

        [Parameter()]
        [Switch]$All,

        [Parameter()]
        [Switch]$Simple
    )

    begin
    {
        Write-Verbose 'Starting Get-WhichCommand'
    }

    process
    {
        foreach ($cmdName in $Name)
        {
            Write-Verbose "Searching for command: $cmdName"
            $found = $false

            try
            {
                # Get all matching commands
                $commands = Get-Command -Name $cmdName -ErrorAction SilentlyContinue

                if (-not $commands)
                {
                    Write-Verbose "Command not found: $cmdName"
                    Write-Warning "Command not found: $cmdName"
                    continue
                }

                # If not using -All, take only the first match (default behavior)
                # This mimics POSIX 'which' which returns the first executable found in PATH
                if (-not $All)
                {
                    $commands = @($commands)[0]
                }

                foreach ($cmd in $commands)
                {
                    $found = $true

                    switch ($cmd.CommandType)
                    {
                        'Alias'
                        {
                            $resolvedCommand = $cmd.ResolvedCommand
                            $definition = if ($resolvedCommand)
                            {
                                "$($cmd.Name) -> $($resolvedCommand.Name)"
                            }
                            else
                            {
                                "$($cmd.Name) -> $($cmd.Definition)"
                            }

                            [PSCustomObject]@{
                                CommandType = 'Alias'
                                Name = $cmdName
                                Definition = $definition
                                Source = $cmd.Source
                            }
                        }
                        'Function'
                        {
                            [PSCustomObject]@{
                                CommandType = 'Function'
                                Name = $cmd.Name
                                Definition = if ($cmd.ScriptBlock.File)
                                {
                                    $cmd.ScriptBlock.File
                                }
                                else
                                {
                                    '<ScriptBlock>'
                                }
                                Source = $cmd.Source
                            }
                        }
                        'Cmdlet'
                        {
                            [PSCustomObject]@{
                                CommandType = 'Cmdlet'
                                Name = $cmd.Name
                                Definition = $cmd.Source
                                Module = $cmd.ModuleName
                            }
                        }
                        'Application'
                        {
                            if ($Simple)
                            {
                                $cmd.Source
                            }
                            else
                            {
                                [PSCustomObject]@{
                                    CommandType = 'Application'
                                    Name = $cmd.Name
                                    Definition = $cmd.Source
                                    Source = $cmd.Source
                                }
                            }
                        }
                        'ExternalScript'
                        {
                            if ($Simple)
                            {
                                $cmd.Source
                            }
                            else
                            {
                                # PowerShell scripts
                                $cmd.Source
                            }
                        }
                        default
                        {
                            [PSCustomObject]@{
                                CommandType = $cmd.CommandType
                                Name = $cmd.Name
                                Definition = $cmd.Definition
                                Source = $cmd.Source
                            }
                        }
                    }
                }

                if (-not $found)
                {
                    Write-Verbose "No results for: $cmdName"
                }
            }
            catch
            {
                Write-Verbose "Error processing command '$cmdName': $($_.Exception.Message)"
                throw $_
            }
        }
    }

    end
    {
        Write-Verbose 'Get-WhichCommand completed'
    }
}

# Create 'which' alias only if the native which command doesn't exist
if (-not (Get-Command -Name 'which' -CommandType Application -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'which' alias for Get-WhichCommand"
        Set-Alias -Name 'which' -Value 'Get-WhichCommand' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Get-WhichCommand: Could not create 'which' alias: $($_.Exception.Message)"
    }
}
