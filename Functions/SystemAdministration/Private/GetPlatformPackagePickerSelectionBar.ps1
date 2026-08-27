function GetPlatformPackagePickerSelectionBar
{
    <#
    .SYNOPSIS
        Builds a compact selection-progress bar for the platform package pickers.

    .DESCRIPTION
        Produces a single-line, at-a-glance selection indicator for the interactive
        package pickers that support multi-select (search, install, upgrade, remove, and
        installed browsing). The bar renders as a filled/empty block gauge followed by the
        selected and total counts, for example: 'Selected [########........] 4/12'.

        The returned text is plain (no ANSI). Callers wrap it in a picker frame line and
        apply the accent color so the block characters inherit the frame's monochrome theme.
        When at least one package is selected, the bar always shows a minimum of one filled
        cell so selection progress is visible even for large package sets.

    .PARAMETER SelectedCount
        Number of currently selected packages.

    .PARAMETER TotalCount
        Total number of selectable packages.

    .PARAMETER BarWidth
        Number of cells in the gauge. Defaults to 16.

    .OUTPUTS
        System.String. The formatted selection bar text.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [Int32]$SelectedCount,

        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [Int32]$TotalCount,

        [Parameter()]
        [ValidateRange(4, 64)]
        [Int32]$BarWidth = 16
    )

    $filledChar = [String][Char]0x2588
    $emptyChar = [String][Char]0x2591

    $clampedSelected = [Math]::Min([Math]::Max(0, $SelectedCount), [Math]::Max(0, $TotalCount))

    $filledCells = if ($TotalCount -le 0)
    {
        0
    }
    else
    {
        [Int32][Math]::Round(($clampedSelected / $TotalCount) * $BarWidth)
    }

    if ($clampedSelected -gt 0 -and $filledCells -le 0)
    {
        $filledCells = 1
    }

    $filledCells = [Math]::Min([Math]::Max(0, $filledCells), $BarWidth)
    $emptyCells = $BarWidth - $filledCells

    $bar = ($filledChar * $filledCells) + ($emptyChar * $emptyCells)

    return "Selected [$bar] $clampedSelected/$TotalCount"
}
