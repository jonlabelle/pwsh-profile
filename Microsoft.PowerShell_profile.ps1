#
# Dot source all functions
$functions = @(Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot 'Functions') -Filter '*.ps1' -File -Depth 1 -ErrorAction 'SilentlyContinue')
foreach ($function in $functions)
{
    Write-Verbose ("Loading function(s) '{0}'" -f $function.FullName)
    . $function.FullName
}

#
# Function to update the profile from the git repository
function Update-Profile
{
    <#
    .SYNOPSIS
        Updates PowerShell profile to the latest version.

    .LINK
        https://github.com/jonlabelle/pwsh-profile
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param([switch] $Verbose)

    Write-Host -ForegroundColor Cyan 'Updating PowerShell profile...'

    # CD to this script's directory and update
    Push-Location -Path $PSScriptRoot
    git pull
    Pop-Location

    . Reload-Profile -Verbose:$Verbose
}

#
# Custom prompt function
function Prompt
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()

    # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.2#add-a-customized-powershell-prompt
    # "PS > "
    Write-Host 'PS' -ForegroundColor 'Cyan' -NoNewline
    return ' > '
}

# (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

Write-Host -ForegroundColor DarkBlue -NoNewline 'User profile loaded: '
Write-Host -ForegroundColor Gray "$PSCommandPath"

#
# Check for profile updates in background (non-blocking)
try
{
    $updateJob = Test-ProfileUpdate -Async -ErrorAction SilentlyContinue
    if ($updateJob)
    {
        # Register an event to handle the job completion
        Register-ObjectEvent -InputObject $updateJob -EventName StateChanged -Action {
            $job = $Event.Sender
            if ($job.State -eq 'Completed')
            {
                $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

                if ($result -eq $true)
                {
                    Write-Host -ForegroundColor Yellow "Profile updates available! Run 'Update-Profile' to get the latest changes."
                }
            }
            elseif ($job.State -eq 'Failed')
            {
                # Clean up failed job silently
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        } | Out-Null
    }
}
catch
{
    # Silently ignore any errors during update check to avoid disrupting profile load
    Write-Debug "Profile update check failed: $($_.Exception.Message)"
}
