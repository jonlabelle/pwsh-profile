# Dot source all functions
$profileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$functionsPath = Join-Path -Path $PSScriptRoot -ChildPath 'Functions'

if (Test-Path -LiteralPath $functionsPath -PathType Container)
{
    $functions = @(Get-ChildItem -LiteralPath $functionsPath -Filter '*-*.ps1' -File -Recurse)
    $failedCount = 0

    foreach ($function in $functions)
    {
        try
        {
            Write-Verbose ('Loading profile function: {0}' -f $function.FullName)
            . $function.FullName
        }
        catch
        {
            $failedCount++
            Write-Warning ("Failed to load profile function '{0}': {1}" -f $function.Name, $_.Exception.Message)
        }
    }

    Write-Verbose ('Loaded {0} profile function(s) in {1:N0} ms' -f ($functions.Count - $failedCount), $profileStopwatch.Elapsed.TotalMilliseconds)

    if ($failedCount -gt 0)
    {
        Write-Warning ('{0} profile function(s) failed to load. Run with -Verbose for details.' -f $failedCount)
    }
}
else
{
    Write-Verbose ('Functions directory not found: {0}' -f $functionsPath)
}

# Prevent ths script's vars from leaking into the global scope
Remove-Variable -Name functionsPath, functions, function, failedCount -ErrorAction SilentlyContinue

# Use UTF-8 output encoding (no bom) when supported by the host.
try
{
    $utf8OutputEncoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    $OutputEncoding = $utf8OutputEncoding

    if ($Host.UI -and $Host.UI.RawUI)
    {
        [Console]::OutputEncoding = $utf8OutputEncoding
    }
}
catch
{
    Write-Warning "Unable to set UTF-8 output encoding: $($_.Exception.Message)"
}
finally
{
    Remove-Variable -Name utf8OutputEncoding -ErrorAction SilentlyContinue
}

# Custom prompt function
function Prompt
{
    # Set window title if RawUI is available (ConsoleHost and similar hosts)
    if ($Host.UI -and $Host.UI.RawUI)
    {
        try
        {
            $Host.UI.RawUI.WindowTitle = "PowerShell $($PSEdition) $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
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
        if (Get-Module -Name PSReadLine -ListAvailable -ErrorAction SilentlyContinue)
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

$profileStopwatch.Stop()
Write-Verbose ('Profile loaded in {0:N0} ms' -f $profileStopwatch.Elapsed.TotalMilliseconds)
Remove-Variable -Name profileStopwatch -ErrorAction SilentlyContinue
