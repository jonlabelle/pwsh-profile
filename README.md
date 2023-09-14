# PowerShell Profile

> My personal PowerShell profile.

## Install

1. Overlay [this repository](http://github.com/jonlabelle/pwsh-profile) on top of your [PowerShell profile path](#powershell-profile-paths).

   ```console
   git clone http://github.com/jonlabelle/pwsh-profile.git '~/.config/powershell'
   ```

## PowerShell Profile Paths

### Windows PowerShell 5.1 (e.g. PowerShell Desktop)

| Profile                     | Path                                                                     |
| --------------------------- | ------------------------------------------------------------------------ |
| Current User - Current Host | `$Home\[My]Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` |
| Current User - All Hosts    | `$Home\[My]Documents\WindowsPowerShell\Profile.ps1`                      |
| All Users - Current Host    | `$PSHOME\Microsoft.PowerShell_profile.ps1`                               |
| All Users - All Hosts       | `$PSHOME\Profile.ps1`                                                    |

### PowerShell 7.x (e.g. PowerShell Core)

#### Windows

| Profile                     | Path                                                              |
| --------------------------- | ----------------------------------------------------------------- |
| Current User - Current Host | `$Home\[My]Documents\Powershell\Microsoft.Powershell_profile.ps1` |
| Current User - All Hosts    | `$Home\[My]Documents\Powershell\Profile.ps1`                      |
| All Users - Current Host    | `$PSHOME\Microsoft.Powershell_profile.ps1`                        |
| All Users - All Hosts       | `$PSHOME\Profile.ps1`                                             |

#### Linux/macOS

| Profile                     | Path                                                                 |
| --------------------------- | -------------------------------------------------------------------- |
| Current User - Current Host | `~/.config/powershell/Microsoft.Powershell_profile.ps1`              |
| Current User - All Hosts    | `~/.config/powershell/profile.ps1`                                   |
| All Users - Current Host    | `/usr/local/microsoft/powershell/7/Microsoft.Powershell_profile.ps1` |
| All Users - All Hosts       | `/usr/local/microsoft/powershell/7/profile.ps1`                      |
