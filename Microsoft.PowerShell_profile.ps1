# Track profile startup duration for verbose diagnostics.
$profileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Resolve-ProfileRoot
{
    $candidatePaths = @()

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot))
    {
        $candidatePaths += $PSScriptRoot
    }

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath))
    {
        $candidatePaths += (Split-Path -Path $PSCommandPath -Parent)
    }

    if ($PROFILE -and -not [string]::IsNullOrWhiteSpace($PROFILE.ToString()))
    {
        $candidatePaths += (Split-Path -Path $PROFILE.ToString() -Parent)
    }

    foreach ($candidatePath in ($candidatePaths | Select-Object -Unique))
    {
        if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and (Test-Path -LiteralPath $candidatePath -PathType Container))
        {
            return $candidatePath
        }
    }

    return $null
}

function Get-ProfileFunctionFiles
{
    param (
        [Parameter()]
        [String]$ProfileRoot
    )

    if ([string]::IsNullOrWhiteSpace($ProfileRoot))
    {
        Write-Verbose 'Profile root path is unavailable; skipping function auto-load.'
        return @()
    }

    $functionsPath = Join-Path -Path $ProfileRoot -ChildPath 'Functions'
    if (-not (Test-Path -LiteralPath $functionsPath -PathType Container))
    {
        Write-Verbose ('Functions directory not found: {0}' -f $functionsPath)
        return @()
    }

    return @(Get-ChildItem -LiteralPath $functionsPath -Filter '*-*.ps1' -File -Recurse)
}

function Initialize-ProfileOutputEncoding
{
    # Use UTF-8 output encoding (no BOM) when supported by the host.
    try
    {
        $utf8OutputEncoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
        $OutputEncoding = $utf8OutputEncoding

        $canSetConsoleEncoding = [Environment]::UserInteractive -and
        ($null -eq $PSSenderInfo) -and
        ($Host.Name -eq 'ConsoleHost') -and
        $Host.UI -and
        $Host.UI.RawUI

        if ($canSetConsoleEncoding)
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
        Remove-Variable -Name utf8OutputEncoding, canSetConsoleEncoding -ErrorAction SilentlyContinue
    }
}

function Initialize-ProfilePSReadLine
{
    if (-not [Environment]::UserInteractive)
    {
        return
    }

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

# Custom prompt function.
function Prompt
{
    # Set window title if RawUI is available (ConsoleHost and similar hosts).
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

$profileRoot = Resolve-ProfileRoot
$functionFiles = @(Get-ProfileFunctionFiles -ProfileRoot $profileRoot)
$failedFunctionCount = 0

foreach ($functionFile in $functionFiles)
{
    try
    {
        Write-Verbose ('Loading profile function: {0}' -f $functionFile.FullName)
        . $functionFile.FullName
    }
    catch
    {
        $failedFunctionCount++
        Write-Warning ("Failed to load profile function '{0}': {1}" -f $functionFile.Name, $_.Exception.Message)
    }
}

$loadedFunctionCount = $functionFiles.Count - $failedFunctionCount
Write-Verbose ('Loaded {0} profile function(s) in {1:N0} ms' -f $loadedFunctionCount, $profileStopwatch.Elapsed.TotalMilliseconds)

if ($failedFunctionCount -gt 0)
{
    Write-Warning ('{0} profile function(s) failed to load. Run with -Verbose for details.' -f $failedFunctionCount)
}

Initialize-ProfileOutputEncoding
Initialize-ProfilePSReadLine

$profileStopwatch.Stop()
Write-Verbose ('Profile loaded in {0:N0} ms' -f $profileStopwatch.Elapsed.TotalMilliseconds)

# Prevent internal helpers and vars from leaking into the global scope.
Remove-Variable -Name profileRoot, functionFiles, functionFile, failedFunctionCount, loadedFunctionCount, profileStopwatch -ErrorAction SilentlyContinue
Remove-Item -LiteralPath Function:\Resolve-ProfileRoot -ErrorAction SilentlyContinue
Remove-Item -LiteralPath Function:\Get-ProfileFunctionFiles -ErrorAction SilentlyContinue
Remove-Item -LiteralPath Function:\Initialize-ProfileOutputEncoding -ErrorAction SilentlyContinue
Remove-Item -LiteralPath Function:\Initialize-ProfilePSReadLine -ErrorAction SilentlyContinue
