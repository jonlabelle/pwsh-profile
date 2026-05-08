# Remote Sessions

<!-- <p align="center">
  <a href="troubleshooting.md">← Troubleshooting</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="README.md">Docs</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="../README.md">Project README →</a>
</p> -->

> PowerShell profiles do not load automatically in remote sessions, and `$PROFILE` is not populated there. Load the profile explicitly only after the WinRM or SSH remoting connection already works.

SSH-based remoting requires PowerShell 6+ and SSH on both computers. See Microsoft's [PowerShell remoting over SSH](https://learn.microsoft.com/en-us/powershell/scripting/security/remoting/ssh-remoting-in-powershell) documentation for setup details. This page only covers loading this profile into an existing remote session.

## Contents

- [Load the Remote Computer's Profile](#load-the-remote-computers-profile)
- [Run the Local Profile File Remotely](#run-the-local-profile-file-remotely)

## Load the Remote Computer's Profile

Prefer dot-sourcing the remote computer's own installed profile. `Invoke-Command -FilePath $PROFILE` sends the local profile script content to the remote computer, but it does not copy sibling folders such as `Functions`.

This snippet probes standard profile paths because remote sessions do not populate `$PROFILE`:

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

<p align="center">
  <a href="troubleshooting.md">← Troubleshooting</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="README.md">Docs</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="../README.md">Project README →</a>
</p>
