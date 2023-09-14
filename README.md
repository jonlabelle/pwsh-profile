# PowerShell Profile

[![ci](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml)

> My personal PowerShell profile.

## Install

~~Overlay~~ Overwrite [this repository](https://github.com/jonlabelle/pwsh-profile) your existing [PowerShell profile path](https://gist.github.com/jonlabelle/f2a4fdd989dbfe59e444e0beaf07bcc9).

Choose the appropriate platform:

- [Linux/macOS](#linux-macos)
- [Windows](#windows)
  - [PowerShell Desktop](#powershell-desktop)
  - [PowerShell Core](#powershell-core)

### Linux/macOS

```powershell
git clone https://github.com/jonlabelle/pwsh-profile.git $HOME/.config/powershell
```

### Windows

#### PowerShell Desktop

```powershell
git clone https://github.com/jonlabelle/pwsh-profile.git $HOME\Documents\WindowsPowerShell
```

#### PowerShell Core

```powershell
git clone https://github.com/jonlabelle/pwsh-profile.git $HOME\Documents\PowerShell
```

## Update

To pull in the latest updates from the [Git repo](https://github.com/jonlabelle/pwsh-profile):

```powershell
Update-Profile
```
