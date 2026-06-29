function ConvertTo-USDateTime
{
    <#
    .SYNOPSIS
        Converts a date/time into major US time zones.

    .DESCRIPTION
        Provides backward compatibility for the original US-specific date/time helper.
        New code should use ConvertTo-TimeZone, which supports arbitrary source and target
        time zones, IANA and Windows ids, informal aliases, and System.TimeZoneInfo objects.

        If -InputObject is omitted, the current UTC date/time is used. If -TimeZone is
        omitted, Atlantic, Eastern, Central, Mountain, Arizona, Pacific, Alaska, Aleutian,
        Hawaii, Samoa, and Chamorro are returned.

    .PARAMETER InputObject
        The input date/time value to convert. Accepts String, DateTime, and DateTimeOffset
        values from the pipeline. If omitted, the current UTC date/time is used.

    .PARAMETER TimeZone
        One or more target US time zones. Accepts the aliases and formal ids supported by
        ConvertTo-TimeZone.

    .PARAMETER AssumeInputKind
        Interprets timezone-less strings and unspecified DateTime values as Local or Utc.
        Defaults to Local. Offset-aware values and DateTime values with an intrinsic Kind
        retain their existing meaning.

    .EXAMPLE
        PS > ConvertTo-USDateTime -InputObject '2026-04-23T18:30:00Z'

        Converts the UTC timestamp into the default US time-zone set.

    .EXAMPLE
        PS > ConvertTo-USDateTime

        Converts the current UTC instant into the default US time-zone set.

    .EXAMPLE
        PS > '2026-04-23 18:30' | ConvertTo-USDateTime -AssumeInputKind Utc -TimeZone Eastern, Pacific

        Treats the input as UTC and returns Eastern and Pacific time.

    .OUTPUTS
        [PSCustomObject]

    .NOTES
        ConvertTo-USDateTime is retained as a compatibility wrapper. Prefer
        ConvertTo-TimeZone for new scripts.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-USDateTime.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-TimeZone.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-USDateTime.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, Position = 0)]
        [Alias('Value', 'DateTime', 'Timestamp')]
        [Object]$InputObject,

        [Parameter(Position = 1)]
        [Alias('Zone', 'TargetTimeZone')]
        [String[]]$TimeZone,

        [Parameter()]
        [ValidateSet('Local', 'Utc')]
        [String]$AssumeInputKind = 'Local'
    )

    begin
    {
        if (-not (Get-Command -Name 'ConvertTo-TimeZone' -CommandType Function -ErrorAction SilentlyContinue))
        {
            $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath 'ConvertTo-TimeZone.ps1'
            if (-not (Test-Path -LiteralPath $dependencyPath -PathType Leaf))
            {
                throw "Required function 'ConvertTo-TimeZone' could not be found. Expected location: $dependencyPath"
            }

            try
            {
                . $dependencyPath
            }
            catch
            {
                throw "Failed to load required function 'ConvertTo-TimeZone' from '$dependencyPath': $($_.Exception.Message)"
            }
        }

        $targetTimeZones = if ($TimeZone -and $TimeZone.Count -gt 0)
        {
            $TimeZone
        }
        else
        {
            @(
                'Atlantic',
                'Eastern',
                'Central',
                'Mountain',
                'Arizona',
                'Pacific',
                'Alaska',
                'Aleutian',
                'Hawaii',
                'Samoa',
                'Chamorro'
            )
        }
    }

    process
    {
        $conversionParameters = @{
            ToTimeZone = $targetTimeZones
            FromTimeZone = $AssumeInputKind
        }

        if ($PSBoundParameters.ContainsKey('InputObject'))
        {
            $conversionParameters.InputObject = $InputObject
        }

        foreach ($result in (ConvertTo-TimeZone @conversionParameters))
        {
            [PSCustomObject][ordered]@{
                TimeZone = $result.TimeZone
                DateTime = $result.DateTime
                DateTime24 = $result.DateTime24
                TimeZoneId = $result.TimeZoneId
                TimeZoneName = $result.TimeZoneName
                Abbreviation = $result.Abbreviation
                UtcOffset = $result.UtcOffset
                UtcOffsetString = $result.UtcOffsetString
                IsDaylightSavingTime = $result.IsDaylightSavingTime
                ObservesDaylightSavingTime = $result.ObservesDaylightSavingTime
                SourceDateTime = $result.SourceDateTime
                SourceDateTime24 = $result.SourceDateTime24
                SourceKind = $result.SourceKind
                SourceOffset = $result.SourceOffset
                SourceInputType = $result.SourceInputType
            }
        }
    }
}
