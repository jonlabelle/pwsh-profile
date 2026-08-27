#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Private/GetPlatformPackagePickerEmptyState.ps1"
}

Describe 'GetPlatformPackagePickerEmptyState' {
    It 'returns frame line objects exposing Text and ForegroundColor properties' {
        $lines = @(GetPlatformPackagePickerEmptyState -Message 'No matching packages' -FrameWidth 80)

        $lines.Count | Should-BeGreaterThan 0
        foreach ($line in $lines)
        {
            $line.PSObject.Properties.Name | Should-ContainCollection 'Text'
            $line.PSObject.Properties.Name | Should-ContainCollection 'ForegroundColor'
        }
    }

    It 'renders the empty-set glyph and message in the warning color' {
        $glyph = [String][Char]0x25CB
        $lines = @(GetPlatformPackagePickerEmptyState -Message 'No matching packages' -FrameWidth 80)

        $glyphLine = @($lines | Where-Object { $_.Text.Trim() -eq $glyph })
        $glyphLine.Count | Should-Be 1
        $glyphLine[0].ForegroundColor | Should-Be ([ConsoleColor]::DarkYellow)

        $messageLine = @($lines | Where-Object { $_.Text.Trim() -eq 'No matching packages' })
        $messageLine.Count | Should-Be 1
        $messageLine[0].ForegroundColor | Should-Be ([ConsoleColor]::DarkYellow)
    }

    It 'renders hint lines in the muted color' {
        $lines = @(GetPlatformPackagePickerEmptyState -Message 'No matching packages' -Hint 'Press S to cycle sources.' -FrameWidth 80)

        $hintLine = @($lines | Where-Object { $_.Text.Trim() -eq 'Press S to cycle sources.' })
        $hintLine.Count | Should-Be 1
        $hintLine[0].ForegroundColor | Should-Be ([ConsoleColor]::DarkGray)
    }

    It 'skips blank and whitespace-only hint lines' {
        $lines = @(GetPlatformPackagePickerEmptyState -Message 'No matching packages' -Hint @('', '   ', 'Valid hint') -FrameWidth 80)

        $mutedLines = @($lines | Where-Object { $_.ForegroundColor -eq [ConsoleColor]::DarkGray })
        $mutedLines.Count | Should-Be 1
        $mutedLines[0].Text.Trim() | Should-Be 'Valid hint'
    }

    It 'pads the callout with blank spacer lines above and below' {
        $lines = @(GetPlatformPackagePickerEmptyState -Message 'No matching packages' -Hint 'Press S to cycle sources.' -FrameWidth 80)

        $lines[0].Text | Should-Be ''
        $lines[-1].Text | Should-Be ''
    }

    It 'horizontally centers the message within the frame width' {
        $message = 'No matching packages'
        $lines = @(GetPlatformPackagePickerEmptyState -Message $message -FrameWidth 80)

        $messageLine = @($lines | Where-Object { $_.Text.Trim() -eq $message })[0]
        $leadingPadding = $messageLine.Text.Length - $messageLine.Text.TrimStart().Length
        $expectedPadding = [Int32]((80 - $message.Length) / 2)

        $leadingPadding | Should-Be $expectedPadding
    }
}
