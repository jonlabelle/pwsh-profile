BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments.
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Utilities/Clear-Clipboard.ps1"
}

Describe 'Clear-Clipboard' -Tag 'Unit', 'Utilities' {
    It 'previews the clear without resolving a clipboard backend' {
        Mock -CommandName Add-Type { throw 'Unexpected native clipboard call.' }
        Mock -CommandName Get-Command -ParameterFilter { $Name -in 'osascript', 'wl-copy', 'xsel' } {
            throw 'Unexpected clipboard tool lookup.'
        }

        Clear-Clipboard -WhatIf -ErrorAction Stop

        Should -Invoke -CommandName Add-Type -Times 0 -Exactly
        Should -Invoke -CommandName Get-Command -Times 0 -Exactly -ParameterFilter { $Name -in 'osascript', 'wl-copy', 'xsel' }
    }

    Context 'Windows' -Skip:($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
        BeforeAll {
            if (-not ('PowerShellProfile.Tests.ClipboardFixture' -as [Type]))
            {
                Add-Type -ErrorAction Stop -TypeDefinition @'
namespace PowerShellProfile.Tests
{
    public static class ClipboardFixture
    {
        public static int ClearCount;

        public static void Clear()
        {
            ClearCount++;
        }
    }
}
'@
            }
        }

        It 'calls the native clear method and emits no output' {
            if ('PowerShellProfile.Win32Clipboard' -as [Type])
            {
                Set-ItResult -Skipped -Because 'the real clipboard type is already loaded in this process'
                return
            }

            [PowerShellProfile.Tests.ClipboardFixture]::ClearCount = 0
            Mock -CommandName Add-Type { [PowerShellProfile.Tests.ClipboardFixture] }

            @(Clear-Clipboard -ErrorAction Stop).Count | Should-Be 0
            [PowerShellProfile.Tests.ClipboardFixture]::ClearCount | Should-Be 1
            Should -Invoke -CommandName Add-Type -Times 1 -Exactly
        }
    }

    Context 'Unix clipboard tools' -Skip:($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) {
        BeforeAll {
            $script:clipboardToolPath = Join-Path -Path $TestDrive -ChildPath 'clipboard-tool'
            $script:clipboardArgsPath = "$script:clipboardToolPath.args"
        }

        BeforeEach {
            $script:savedDisplay = $env:DISPLAY
            $script:savedWaylandDisplay = $env:WAYLAND_DISPLAY
            $script:savedWaylandSocket = $env:WAYLAND_SOCKET
            $script:savedSessionType = $env:XDG_SESSION_TYPE
            $env:DISPLAY = ':99'
            $env:WAYLAND_DISPLAY = $null
            $env:WAYLAND_SOCKET = $null
            $env:XDG_SESSION_TYPE = $null

            Set-Content -LiteralPath $script:clipboardToolPath -Encoding ASCII -Value @'
#!/bin/sh
printf '%s\n' "$@" > "$0.args"
printf '%s\n' 'Tool output'
'@
            & /bin/chmod +x $script:clipboardToolPath
            Mock -CommandName Get-Command -ParameterFilter { $Name -in 'osascript', 'wl-copy', 'xsel' } {
                [PSCustomObject]@{ Source = $script:clipboardToolPath }
            }
        }

        AfterEach {
            $env:DISPLAY = $script:savedDisplay
            $env:WAYLAND_DISPLAY = $script:savedWaylandDisplay
            $env:WAYLAND_SOCKET = $script:savedWaylandSocket
            $env:XDG_SESSION_TYPE = $script:savedSessionType
        }

        It 'uses AppKit to clear the general pasteboard on macOS' -Skip:(-not $IsMacOS) {
            @(Clear-Clipboard -ErrorAction Stop).Count | Should-Be 0

            Should -Invoke -CommandName Get-Command -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'osascript' -and $CommandType -eq 'Application'
            }
            $toolArguments = Get-Content -LiteralPath $script:clipboardArgsPath
            ($toolArguments[0..2] -join ' ') | Should-Be '-l JavaScript -e'
            $scriptBody = $toolArguments[3..($toolArguments.Count - 1)] -join "`n"
            $scriptBody | Should -Match 'NSPasteboard\.generalPasteboard'
            $scriptBody | Should -Match 'pasteboard\.clearContents'
        }

        It 'uses the Wayland clear operation when XWayland is also available' -Skip:(-not $IsLinux) {
            $env:WAYLAND_DISPLAY = 'wayland-0'

            @(Clear-Clipboard -ErrorAction Stop).Count | Should-Be 0

            (Get-Content -LiteralPath $script:clipboardArgsPath -Raw).Trim() | Should-Be '--clear'
            Should -Invoke -CommandName Get-Command -Times 1 -Exactly -ParameterFilter { $Name -eq 'wl-copy' }
            Should -Invoke -CommandName Get-Command -Times 0 -Exactly -ParameterFilter { $Name -eq 'xsel' }
        }

        It 'clears the clipboard selection on X11' -Skip:(-not $IsLinux) {
            Clear-Clipboard -ErrorAction Stop

            ((Get-Content -LiteralPath $script:clipboardArgsPath) -join ' ') | Should-Be '--clipboard --clear'
            Should -Invoke -CommandName Get-Command -Times 1 -Exactly -ParameterFilter { $Name -eq 'xsel' }
        }

        It 'reports the package to install when the Wayland tool is missing' -Skip:(-not $IsLinux) {
            $env:XDG_SESSION_TYPE = 'wayland'
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'wl-copy' } { }

            { Clear-Clipboard } | Should -Throw '*Install-PlatformPackage -Name wl-clipboard*'
            Should -Invoke -CommandName Get-Command -Times 0 -Exactly -ParameterFilter { $Name -eq 'xsel' }
        }

        It 'reports when Linux has no desktop session' -Skip:(-not $IsLinux) {
            $env:DISPLAY = $null

            { Clear-Clipboard } | Should -Throw '*requires a graphical Wayland or X11 session*'
        }

        It 'reports a native failure with the exit code and diagnostic' {
            Set-Content -LiteralPath $script:clipboardToolPath -Encoding ASCII -Value @'
#!/bin/sh
printf '%s\n' 'Test clipboard service unavailable' >&2
exit 3
'@

            { Clear-Clipboard } | Should -Throw '*exit code 3*Test clipboard service unavailable*'
        }
    }
}
