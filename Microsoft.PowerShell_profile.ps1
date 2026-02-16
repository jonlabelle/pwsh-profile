# Dot source all functions
$functions = @(Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Functions') -Filter '*-*.ps1' -File -Recurse)
foreach ($function in $functions)
{
    Write-Verbose ('Loading profile function: {0}' -f $function.FullName)
    . $function.FullName
}

# Custom prompt function
function Prompt
{
    # Set window title if RawUI is available (ConsoleHost and similar hosts)
    if ($Host.UI -and $Host.UI.RawUI)
    {
        try
        {
            $psVersionTitle = "PowerShell $($PSEdition) $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
            $Host.UI.RawUI.WindowTitle = "$psVersionTitle"
        }
        catch
        {
            Write-Verbose "Unable to set window title: $($_.Exception.Message)"
        }
    }

    Write-Host 'PS' -ForegroundColor 'Cyan' -NoNewline
    return ' > '
}

# Set up PSReadLine key handlers in interactive sessions (when available).
# Supports ConsoleHost (Windows/Linux/macOS), Windows PowerShell ISE, and VS Code terminal.
if ([Environment]::UserInteractive)
{
    # Ensure PSReadLine is imported if it is installed so key handlers can be configured.
    if (-not (Get-Module -Name PSReadLine -ErrorAction SilentlyContinue))
    {
        $psReadLineModule = Get-Module -Name PSReadLine -ListAvailable -ErrorAction SilentlyContinue
        if ($psReadLineModule)
        {
            try
            {
                Import-Module -Name PSReadLine -ErrorAction Stop
                Write-Verbose 'Imported PSReadLine module for key handler configuration.'
            }
            catch
            {
                Write-Warning "PSReadLine module found but could not be imported: $($_.Exception.Message)"
            }
        }
        else
        {
            Write-Verbose 'PSReadLine module not found; skipping key handler configuration.'
        }
    }

    # If PSReadLine commands are available, bind Up/Down to search history based on the current input.
    if (Get-Command -Name Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)
    {
        try
        {
            # Searching for commands with up/down arrow is really handy. The
            # option "moves to end" is useful if you want the cursor at the end
            # of the line while cycling through history like it does w/o searching,
            # without that option, the cursor will remain at the position it was
            # when you used up arrow, which can be useful if you forget the exact
            # string you started the search on.
            # Source: PSReadLine sample profile
            # https://github.com/PowerShell/PSReadLine/blob/master/PSReadLine/SamplePSReadLineProfile.ps1
            Set-PSReadLineOption -HistorySearchCursorMovesToEnd -ErrorAction Stop
            Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward -ErrorAction Stop
            Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward -ErrorAction Stop

            Write-Verbose 'PSReadLine module detected and up/down key handlers set.'
        }
        catch
        {
            Write-Warning "PSReadLine module detected but up/down key handler setup failed: $($_.Exception.Message)"
        }
    }
}
