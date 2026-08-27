function GetPlatformPackagePickerEmptyState
{
    <#
    .SYNOPSIS
        Builds a centered empty-state callout for the platform package pickers.

    .DESCRIPTION
        Produces a consistent, visually distinct empty-state block for the interactive
        package pickers (search, install, upgrade, remove, and installed browsing). The
        block is composed of picker frame line objects (Text and ForegroundColor) so it
        can be appended directly to a picker's body or frame line collection.

        The callout centers an empty-set glyph and message using the warning color, with
        optional muted hint lines describing how to recover (for example, cycling source
        filters). Centering is calculated from the picker frame width so the callout aligns
        with the surrounding frame.

    .PARAMETER Message
        Primary empty-state message rendered in the warning color.

    .PARAMETER Hint
        Optional muted hint lines rendered below the message. Blank entries are skipped.

    .PARAMETER FrameWidth
        Picker frame width used to horizontally center the callout text.

    .OUTPUTS
        System.Object[]. An array of picker frame line objects with Text and
        ForegroundColor properties.
    #>
    [CmdletBinding()]
    [OutputType([Object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter()]
        [AllowEmptyCollection()]
        [String[]]$Hint = @(),

        [Parameter(Mandatory)]
        [ValidateRange(20, 32767)]
        [Int32]$FrameWidth
    )

    $emptyGlyph = [String][Char]0x25CB
    $centerWidth = [Math]::Max(1, $FrameWidth)

    function Get-CenteredEmptyStateLine
    {
        param(
            [Parameter()]
            [AllowEmptyString()]
            [String]$Text = ''
        )

        if ([String]::IsNullOrEmpty($Text) -or $Text.Length -ge $centerWidth)
        {
            return $Text
        }

        $padding = [Math]::Max(0, [Int32](($centerWidth - $Text.Length) / 2))
        return (' ' * $padding) + $Text
    }

    $lines = New-Object 'System.Collections.Generic.List[Object]'
    [void]$lines.Add([PSCustomObject]@{ Text = ''; ForegroundColor = $null })
    [void]$lines.Add([PSCustomObject]@{ Text = (Get-CenteredEmptyStateLine -Text $emptyGlyph); ForegroundColor = [ConsoleColor]::DarkYellow })
    [void]$lines.Add([PSCustomObject]@{ Text = (Get-CenteredEmptyStateLine -Text $Message); ForegroundColor = [ConsoleColor]::DarkYellow })

    foreach ($hintLine in $Hint)
    {
        if ([String]::IsNullOrWhiteSpace($hintLine))
        {
            continue
        }

        [void]$lines.Add([PSCustomObject]@{ Text = (Get-CenteredEmptyStateLine -Text $hintLine); ForegroundColor = [ConsoleColor]::DarkGray })
    }

    [void]$lines.Add([PSCustomObject]@{ Text = ''; ForegroundColor = $null })

    return [Object[]]$lines.ToArray()
}
