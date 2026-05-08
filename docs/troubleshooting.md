<p align="center">
  <a href="functions.md">← Function Catalog</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="README.md">Docs</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="remote-sessions.md">Remote Sessions →</a>
</p>

---

# Troubleshooting

> This page covers the most common profile loading problems and diagnostics.

## Contents

- [Execution Policy Error](#execution-policy-error)
- [Verbose Profile Loading](#verbose-profile-loading)
- [Function-Level Verbose Output](#function-level-verbose-output)

## Execution Policy Error

Execution policies are enforced only on Windows. macOS and Linux systems do not enforce execution policies and will not encounter this error.

If PowerShell starts with an error like this:

```console
Microsoft.PowerShell_profile.ps1 cannot be loaded because running
scripts is disabled on this system.

For more information, see about_Execution_Policies at
https:/go.microsoft.com/fwlink/?LinkID=135170.
```

Your system's execution policy is preventing the profile from loading. Open PowerShell and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

This changes the policy for your user account only, so administrator privileges are not required. It allows locally created scripts to run while still requiring downloaded scripts to be signed.

To set the policy for all users on the computer, run PowerShell as Administrator and use:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```

The `CurrentUser` scope takes precedence over `LocalMachine`, so setting `CurrentUser` is usually sufficient. Restart PowerShell after changing the policy.

For more information, see Microsoft's [about_Execution_Policies](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies) documentation.

## Verbose Profile Loading

If the profile fails to load or you want to see which functions are being loaded, set `$VerbosePreference` before the profile runs.

Start PowerShell with verbose output:

```powershell
# PowerShell Core
pwsh -NoLogo -Command "`$VerbosePreference = 'Continue'; . `$PROFILE"

# Windows PowerShell Desktop
powershell -NoLogo -Command "`$VerbosePreference = 'Continue'; . `$PROFILE"
```

Or start without the profile, set verbose output, and load the profile manually:

```powershell
pwsh -NoProfile

$VerbosePreference = 'Continue'
. $PROFILE

# Optional reset after debugging
$VerbosePreference = 'SilentlyContinue'
```

Verbose output shows each function file as it is dot-sourced:

```console
VERBOSE: Loading function: /Users/username/.config/powershell/Functions/Developer/Get-DotNetVersion.ps1
VERBOSE: Loading function: /Users/username/.config/powershell/Functions/Developer/Import-DotEnv.ps1
VERBOSE: Creating 'dotenv' alias for Import-DotEnv
VERBOSE: Loading function: /Users/username/.config/powershell/Functions/Security/ConvertFrom-JwtToken.ps1
VERBOSE: User profile loaded:
VERBOSE: /Users/username/.config/powershell/Microsoft.PowerShell_profile.ps1
```

This is useful for identifying a failing function file, confirming the profile path, and verifying load order.

## Function-Level Verbose Output

Most functions support `-Verbose` after the profile loads:

```powershell
Get-WhichCommand git -Verbose
Test-Port localhost -Port 80 -Verbose
```

---

<p align="center">
  <a href="functions.md">← Function Catalog</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="README.md">Docs</a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="remote-sessions.md">Remote Sessions →</a>
</p>
