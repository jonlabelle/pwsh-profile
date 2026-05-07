# Remote Sessions

[Docs home](README.md) | Previous: [Troubleshooting](troubleshooting.md) | Next: [Project README](../README.md)

PowerShell profiles do not load automatically in remote sessions created with `Enter-PSSession`, `New-PSSession`, or `Invoke-Command`. This is consistent across Windows, macOS, and Linux, whether you use WinRM or SSH-based remoting.

SSH-based remoting requires PowerShell 6+ and SSH on both computers. See Microsoft's [PowerShell remoting over SSH](https://learn.microsoft.com/en-us/powershell/scripting/security/remoting/ssh-remoting-in-powershell) documentation for setup details.

## Contents

- [Load the Remote Computer's Profile](#load-the-remote-computers-profile)
- [Run the Local Profile File Remotely](#run-the-local-profile-file-remotely)

## Load the Remote Computer's Profile

Prefer dot-sourcing the remote computer's own profile. `Invoke-Command -FilePath $PROFILE` sends only the local profile file content and does not copy sibling folders such as `Functions`.

This snippet probes standard profile paths because some non-interactive remoting endpoints leave `$PROFILE` unset:

```powershell
$session = New-PSSession -HostName RemoteHost -UserName YourUser
Invoke-Command -Session $session -ScriptBlock {
    $profileCandidates = @()
    $profileVar = $PROFILE

    if (-not [string]::IsNullOrWhiteSpace($profileVar))
    {
        $profileCandidates += $profileVar
    }

    $documents = [Environment]::GetFolderPath('MyDocuments')
    if (-not [string]::IsNullOrWhiteSpace($documents))
    {
        $profileCandidates += (Join-Path -Path $documents -ChildPath 'WindowsPowerShell/Microsoft.PowerShell_profile.ps1')
        $profileCandidates += (Join-Path -Path $documents -ChildPath 'PowerShell/Microsoft.PowerShell_profile.ps1')
    }

    if (-not [string]::IsNullOrWhiteSpace($HOME))
    {
        $profileCandidates += (Join-Path -Path $HOME -ChildPath '.config/powershell/Microsoft.PowerShell_profile.ps1')
    }

    $profilePath = $profileCandidates |
        Select-Object -Unique |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1

    if (-not $profilePath)
    {
        throw ('Remote profile not found. Tried: {0}' -f ($profileCandidates -join '; '))
    }

    . $profilePath
}
```

After the profile loads, the profile's functions and aliases are available inside `$session`.

```powershell
Invoke-Command -Session $session -ScriptBlock { Test-Port -ComputerName bing.com -Port 443 }

Enter-PSSession $session
Test-DnsNameResolution example.com
Exit-PSSession
```

## Run the Local Profile File Remotely

Use `-FilePath` only when the remote endpoint has a compatible profile layout and the same dependent files are already present remotely:

```powershell
$session = New-PSSession -HostName RemoteHost -UserName YourUser
Invoke-Command -Session $session -FilePath $PROFILE
```

For more information, see Microsoft's [Profiles and Remote Sessions](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles#profiles-and-remote-sessions) documentation.

---

[Docs home](README.md) | Previous: [Troubleshooting](troubleshooting.md) | Next: [Project README](../README.md)
