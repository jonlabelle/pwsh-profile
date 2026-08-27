function ConvertToPlatformPackagePickerLayout
{
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
            [Object]$ForegroundColor
        )

        [void]$outputLines.Add([PSCustomObject]@{
                Kind = $Kind
                Text = $Text
                ForegroundColor = $ForegroundColor
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
            $titleToken = " $statusDot $($Title.ToUpperInvariant()) "
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
