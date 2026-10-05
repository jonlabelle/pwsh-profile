function ConvertToPlatformPackagePickerLayout
{
    <#
    .SYNOPSIS
        Formats platform package picker lines into a framed layout.

    .DESCRIPTION
        Builds the structured lines used to render a platform package picker's header,
        body, and optional controls footer. Header and footer lines are placed inside
        borders, while body lines remain plain. Text is wrapped to fit the frame; when
        requested, the frame width expands to accommodate the supplied lines. Optional
        line segments preserve per-fragment foreground colors for rows that fit without
        wrapping. The result contains line objects rather than writing anything to the
        console.

        Each input line can be a string or an object with a Text property. An optional
        ForegroundColor property is carried through to the corresponding output line.

    .PARAMETER HeaderLines
        Lines to place inside the top framed panel.

    .PARAMETER BodyLines
        Plain lines to place between the header and footer. A blank line is inserted
        before body lines beginning with the package status dot when the preceding output
        line contains text.

    .PARAMETER FooterLines
        Optional lines to place inside a framed panel titled CONTROLS.

    .PARAMETER FrameWidth
        Initial width of the layout frame. Must be between 40 and 32767 characters.

    .PARAMETER MinimumLineCount
        Minimum number of output lines. Blank lines are appended when needed; defaults
        to 0.

    .PARAMETER AllowWidthExpansion
        Expands the frame width as needed to fit the longest supplied header, footer, or
        body line.

    .EXAMPLE
        $layout = ConvertToPlatformPackagePickerLayout -HeaderLines @('Packages') `
            -BodyLines @('No packages found') -FrameWidth 60

        Creates a framed header and a wrapped plain-text body, returning layout line
        objects in $layout.

    .OUTPUTS
        System.Object[]. An array of line objects with Kind, Text, and ForegroundColor
        properties, and an optional Segments property. Kind is Border, Panel, or Plain.
    #>
    [CmdletBinding()]
    [OutputType([Object[]])]
    param(
        [Parameter()]
        [Object[]]$HeaderLines = @(),

        [Parameter()]
        [Object[]]$BodyLines = @(),

        [Parameter()]
        [Object[]]$FooterLines = @(),

        [Parameter(Mandatory)]
        [ValidateRange(40, 32767)]
        [Int32]$FrameWidth,

        [Parameter()]
        [ValidateRange(0, 32767)]
        [Int32]$MinimumLineCount = 0,

        [Parameter()]
        [Switch]$AllowWidthExpansion
    )

    if ($AllowWidthExpansion)
    {
        foreach ($line in @($HeaderLines) + @($FooterLines))
        {
            $lineText = if ($null -ne $line -and $line.PSObject.Properties['Text']) { "$($line.Text)" } else { "$line" }
            $FrameWidth = [Math]::Max($FrameWidth, $lineText.Length + 4)
        }

        foreach ($line in @($BodyLines))
        {
            $lineText = if ($null -ne $line -and $line.PSObject.Properties['Text']) { "$($line.Text)" } else { "$line" }
            $FrameWidth = [Math]::Max($FrameWidth, $lineText.Length)
        }
    }

    $horizontal = [String][Char]0x2500
    $topLeft = [String][Char]0x256D
    $topRight = [String][Char]0x256E
    $bottomLeft = [String][Char]0x2570
    $bottomRight = [String][Char]0x256F
    $statusDot = [String][Char]0x25CF
    $contentWidth = $FrameWidth - 4
    $outputLines = New-Object 'System.Collections.Generic.List[Object]'

    function Get-LineText
    {
        param([AllowNull()][Object]$Line)

        if ($null -eq $Line)
        {
            return ''
        }

        $textProperty = @($Line.PSObject.Properties.Match('Text'))[0]
        if ($null -ne $textProperty)
        {
            return "$($textProperty.Value)"
        }

        return "$Line"
    }

    function Get-LineColor
    {
        param([AllowNull()][Object]$Line)

        if ($null -eq $Line)
        {
            return $null
        }

        $colorProperty = @($Line.PSObject.Properties.Match('ForegroundColor'))[0]
        if ($null -eq $colorProperty)
        {
            return $null
        }

        return $colorProperty.Value
    }

    function Add-OutputLine
    {
        param(
            [Parameter(Mandatory)]
            [ValidateSet('Border', 'Panel', 'Plain')]
            [String]$Kind,

            [Parameter()]
            [AllowEmptyString()]
            [String]$Text = '',

            [Parameter()]
            [AllowNull()]
            [Object]$ForegroundColor,

            [Parameter()]
            [Object[]]$Segments = @()
        )

        [void]$outputLines.Add([PSCustomObject]@{
                Kind = $Kind
                Text = $Text
                ForegroundColor = $ForegroundColor
                Segments = @($Segments)
            })
    }

    function Add-WrappedLines
    {
        param(
            [Parameter()]
            [Object[]]$Lines = @(),

            [Parameter(Mandatory)]
            [ValidateSet('Panel', 'Plain')]
            [String]$Kind,

            [Parameter(Mandatory)]
            [Int32]$Width
        )

        foreach ($line in $Lines)
        {
            $text = Get-LineText -Line $line
            $color = Get-LineColor -Line $line
            if ($Kind -eq 'Plain' -and
                $text.StartsWith($statusDot) -and
                $outputLines.Count -gt 0 -and
                -not [String]::IsNullOrEmpty($outputLines[$outputLines.Count - 1].Text))
            {
                Add-OutputLine -Kind Plain
            }

            if ([String]::IsNullOrEmpty($text))
            {
                Add-OutputLine -Kind $Kind -ForegroundColor $color
                continue
            }

            $segmentProperty = if ($null -ne $line) { $line.PSObject.Properties['Segments'] } else { $null }
            $segments = if ($null -ne $segmentProperty) { @($segmentProperty.Value) } else { @() }
            if ($segments.Count -gt 0 -and $text.Length -le $Width)
            {
                Add-OutputLine -Kind $Kind -Text $text -ForegroundColor $color -Segments $segments
                continue
            }

            $remaining = $text
            while ($remaining.Length -gt $Width)
            {
                Add-OutputLine -Kind $Kind -Text $remaining.Substring(0, $Width) -ForegroundColor $color
                $remaining = $remaining.Substring($Width)
            }

            Add-OutputLine -Kind $Kind -Text $remaining -ForegroundColor $color
        }
    }

    function Add-Panel
    {
        param(
            [Parameter()]
            [Object[]]$Lines = @(),

            [Parameter()]
            [String]$Title = ''
        )

        $topBorder = if ([String]::IsNullOrWhiteSpace($Title))
        {
            $topLeft + ($horizontal * ($FrameWidth - 2)) + $topRight
        }
        else
        {
            $titleToken = " $($Title.ToUpperInvariant()) "
            $ruleWidth = [Math]::Max(0, $FrameWidth - $titleToken.Length - 3)
            $topLeft + $horizontal + $titleToken + ($horizontal * $ruleWidth) + $topRight
        }

        Add-OutputLine -Kind Border -Text $topBorder -ForegroundColor Cyan
        Add-WrappedLines -Lines $Lines -Kind Panel -Width $contentWidth
        Add-OutputLine -Kind Border -Text ($bottomLeft + ($horizontal * ($FrameWidth - 2)) + $bottomRight) -ForegroundColor Cyan
    }

    Add-Panel -Lines $HeaderLines
    Add-OutputLine -Kind Plain
    Add-WrappedLines -Lines $BodyLines -Kind Plain -Width $FrameWidth
    if ($FooterLines.Count -gt 0)
    {
        Add-OutputLine -Kind Plain
        Add-Panel -Lines $FooterLines -Title 'Controls'
    }

    while ($outputLines.Count -lt $MinimumLineCount)
    {
        Add-OutputLine -Kind Plain
    }

    return [Object[]]$outputLines.ToArray()
}
