function Clear-Clipboard
{
    <#
    .SYNOPSIS
        Empties the active system clipboard.

    .DESCRIPTION
        Removes every format from the current clipboard, including text, images,
        rich content, and file references. Clipboard history and synced copies
        are managed separately by the OS or clipboard manager.

        Run this command from a graphical desktop session. Windows uses the
        Win32 clipboard API and macOS uses AppKit. Linux requires wl-copy from
        wl-clipboard on Wayland or xsel on X11.

        Note that Windows history (Win + V), macOS Spotlight history, and
        third-party clipboard managers are NOT affected by this command.

    .EXAMPLE
        PS > Clear-Clipboard

        Empties the active clipboard without producing output.

    .EXAMPLE
        PS > Clear-Clipboard -WhatIf

        Previews the operation without accessing the clipboard.

    .EXAMPLE
        PS > Clear-Clipboard -Confirm

        Prompts before clearing the clipboard.

    .EXAMPLE
        PS > Clear-Clipboard -Confirm:$false

        Clears the clipboard without prompting, even in a session configured
        to prompt for medium-impact operations.

    .EXAMPLE
        PS > Clear-Clipboard -Verbose

        Shows which clipboard tool or API is used.

    .EXAMPLE
        PS > . ./Functions/Utilities/Clear-Clipboard.ps1
        PS > Clear-Clipboard

        Loads the function from a checkout and clears the clipboard.

    .EXAMPLE
        PS > powershell.exe -NoProfile -Command '. ./Functions/Utilities/Clear-Clipboard.ps1; Clear-Clipboard'

        Runs the function in Windows PowerShell 5.1 from the repository root.

    .EXAMPLE
        PS > Set-Clipboard -Value 'Temporary text'
        PS > Clear-Clipboard

        Copies sample text and then empties the clipboard.

    .EXAMPLE
        PS > try {
        >>     Clear-Clipboard
        >> } catch {
        >>     Write-Warning $_.Exception.Message
        >> }

        Reports a clipboard error as a warning when continuing is acceptable.

    .EXAMPLE
        PS > try {
        >>     $copiedText = Get-Clipboard -Raw -ErrorAction Stop
        >> } finally {
        >>     Clear-Clipboard
        >> }

        Captures copied text in a variable and clears the clipboard even if
        reading it fails.

    .OUTPUTS
        None.

    .LINK
        Get-Clipboard

    .LINK
        Set-Clipboard
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([Void])]
    param()

    if (-not $PSCmdlet.ShouldProcess('system clipboard', 'Clear all clipboard formats'))
    {
        return
    }

    if ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows)
    {
        Write-Verbose 'Clearing the clipboard with the Win32 API.'
        $clipboardType = 'PowerShellProfile.Win32Clipboard' -as [Type]
        if (-not $clipboardType)
        {
            $clipboardType = Add-Type -PassThru -ErrorAction Stop -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;

namespace PowerShellProfile
{
    public static class Win32Clipboard
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool OpenClipboard(IntPtr owner);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool EmptyClipboard();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool CloseClipboard();

        public static void Clear()
        {
            // Another application can briefly hold the clipboard open.
            const int maxAttempts = 5;
            for (int attempt = 1; !OpenClipboard(IntPtr.Zero); attempt++)
            {
                if (attempt == maxAttempts)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                Thread.Sleep(25);
            }

            try
            {
                if (!EmptyClipboard())
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
            }
            finally
            {
                CloseClipboard();
            }
        }
    }
}
'@
        }
        $clipboardType::Clear()
        return
    }

    $packageName = $null
    if ($IsMacOS)
    {
        $toolName = 'osascript'
        # The Objective-C bridge invokes zero-argument methods on access.
        $clearPasteboard = @'
ObjC.import("AppKit");
var pasteboard = $.NSPasteboard.generalPasteboard;
if (pasteboard.isNil()) {
    throw new Error("The macOS pasteboard is unavailable in this session.");
}
void pasteboard.clearContents;
'@
        $arguments = @('-l', 'JavaScript', '-e', $clearPasteboard)
    }
    elseif ($IsLinux)
    {
        if ($env:WAYLAND_DISPLAY -or $env:WAYLAND_SOCKET -or $env:XDG_SESSION_TYPE -eq 'wayland')
        {
            $toolName = 'wl-copy'
            $packageName = 'wl-clipboard'
            $arguments = @('--clear')
        }
        elseif ($env:DISPLAY)
        {
            $toolName = 'xsel'
            $packageName = 'xsel'
            $arguments = @('--clipboard', '--clear')
        }
        else
        {
            throw 'Clearing the clipboard on Linux requires a graphical Wayland or X11 session.'
        }
    }
    else
    {
        throw [System.PlatformNotSupportedException]::new('Clear-Clipboard supports Windows, macOS, and Linux.')
    }

    $tool = Get-Command -Name $toolName -CommandType Application -TotalCount 1 -ErrorAction SilentlyContinue
    if (-not $tool)
    {
        $message = "'$toolName' is required to clear the clipboard in this session."
        if ($packageName)
        {
            $message += " On a supported package manager, run 'Install-PlatformPackage -Name $packageName' (./Functions/SystemAdministration/Install-PlatformPackage.ps1)."
        }
        throw $message
    }

    Write-Verbose "Clearing the clipboard with '$toolName'."
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $tool.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $arguments)
    {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    try
    {
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        # A Wayland compositor can withhold the focus wl-copy needs to finish.
        if (-not $process.WaitForExit(5000))
        {
            $process.Kill()
            throw "'$toolName' timed out while clearing the clipboard. Check that the desktop session is accessible."
        }

        if ($process.ExitCode -ne 0)
        {
            $details = ($standardError.Result, $standardOutput.Result -join [Environment]::NewLine).Trim()
            throw "'$toolName' failed to clear the clipboard (exit code $($process.ExitCode)). $details"
        }
    }
    finally
    {
        $process.Dispose()
    }
}
