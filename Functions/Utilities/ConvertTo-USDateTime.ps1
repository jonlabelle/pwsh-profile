function ConvertTo-USDateTime
{
    <#
    .SYNOPSIS
        Converts a local, UTC, or offset-aware date/time into major US time zones.

    .DESCRIPTION
        Accepts strings, DateTime, and DateTimeOffset values and returns the corresponding
        date/time for one or more US time zones. If -InputObject is omitted, the function
        uses the current UTC date/time. If -TimeZone is omitted, the function returns
        Atlantic, Eastern, Central, Mountain, Arizona, Pacific, Alaska, Aleutian,
        Hawaii, Samoa, and Chamorro.

        Strings that already include a UTC designator or numeric offset are treated as
        timezone-aware input. Strings without timezone information are interpreted using
        -AssumeInputKind, which defaults to Local. If -InputObject is omitted, the
        function uses the current UTC date/time and -AssumeInputKind does not apply.

        Recommendation: prefer ISO 8601 input such as 2026-04-23T18:30:00Z or
        2026-04-23T18:30:00-04:00 whenever possible so the source timezone is unambiguous.

    .PARAMETER InputObject
        The input date/time value to convert. Accepts pipeline input.
        Supported types are String, DateTime, and DateTimeOffset.
        If omitted, the function uses the current UTC date/time.

    .PARAMETER TimeZone
        One or more target US time zones to return.
        Accepts common aliases such as Eastern, ET, Central, Mountain, Arizona,
        Pacific, Alaska, Aleutian, Hawaii, Atlantic, Samoa, and Chamorro,
        plus matching Windows or IANA timezone ids.

    .PARAMETER AssumeInputKind
        How to interpret strings or DateTime values that do not carry timezone metadata.
        Defaults to Local. Use Utc when the incoming value should be treated as UTC.
        Applies only when InputObject is provided and does not already include timezone
        information. Ignored when InputObject is omitted.

    .EXAMPLE
        PS > ConvertTo-USDateTime -InputObject '2026-04-23T18:30:00Z'

        Converts the UTC timestamp into the default US timezone set.

    .EXAMPLE
        PS > ConvertTo-USDateTime

        Uses the current UTC date/time and converts it to the default US timezone set.

    .EXAMPLE
        PS > '2026-04-23 18:30' | ConvertTo-USDateTime -AssumeInputKind Utc -TimeZone Eastern, Pacific

        Treats the input as UTC, then returns only Eastern and Pacific time.

    .EXAMPLE
        PS > [DateTimeOffset]'2026-04-23T18:30:00-07:00' | ConvertTo-USDateTime -TimeZone Hawaii

        Converts an offset-aware value into Hawaii time.

    .EXAMPLE
        PS > ConvertTo-USDateTime -InputObject '2026-12-15 08:00' -TimeZone Central

        Treats the timezone-less string as local time by default, then converts it to Central time.

    .EXAMPLE
        PS > ConvertTo-USDateTime -InputObject '2026-12-15 08:00' -AssumeInputKind Utc -TimeZone Eastern

        Treats the timezone-less string as UTC instead of local time before converting it.

    .EXAMPLE
        PS > $utc = [DateTime]::SpecifyKind([DateTime]'2026-01-15 15:00:00', [DateTimeKind]::Utc)
        PS > ConvertTo-USDateTime -InputObject $utc -TimeZone Eastern, Alaska

        Converts a DateTime value that is explicitly marked as UTC into selected US time zones.

    .EXAMPLE
        PS > Get-Date | ConvertTo-USDateTime -TimeZone Eastern, Central, Pacific

        Accepts pipeline input from Get-Date and returns only the requested zones.

    .EXAMPLE
        PS > ConvertTo-USDateTime -InputObject '2026-07-04T12:00:00Z' -TimeZone America/Phoenix, Pacific/Honolulu

        Uses direct IANA timezone ids when you want to target a specific system timezone id.

    .EXAMPLE
        PS > ConvertTo-USDateTime -InputObject '2026-07-04T12:00:00Z' |
        >>     Select-Object TimeZone, TimeZoneName, Abbreviation, UtcOffsetString, IsDaylightSavingTime

        Shows a compact summary of the most useful timezone metadata fields.

    .OUTPUTS
        [PSCustomObject]

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-USDateTime.ps1

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
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $isWindowsPlatform = $true
        }
        else
        {
            $isWindowsPlatform = $IsWindows
        }

        $parseCultures = @(
            [System.Globalization.CultureInfo]::CurrentCulture,
            [System.Globalization.CultureInfo]::InvariantCulture
        )

        $defaultTimeZones = @(
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

        $zoneCatalog = [ordered]@{
            Atlantic = @{
                Label = 'Atlantic'
                WindowsId = 'SA Western Standard Time'
                IanaId = 'America/Puerto_Rico'
                Aliases = @(
                    'Atlantic',
                    'Atlantic Time',
                    'AST',
                    'Puerto Rico',
                    'San Juan',
                    'SA Western Standard Time',
                    'America/Puerto_Rico'
                )
                StandardAbbreviation = 'AST'
                DaylightAbbreviation = 'AST'
                GenericAbbreviation = 'AST'
                SortOrder = 1
            }
            Eastern = @{
                Label = 'Eastern'
                WindowsId = 'Eastern Standard Time'
                IanaId = 'America/New_York'
                Aliases = @(
                    'Eastern',
                    'Eastern Time',
                    'ET',
                    'EST',
                    'EDT',
                    'Eastern Standard Time',
                    'America/New_York'
                )
                StandardAbbreviation = 'EST'
                DaylightAbbreviation = 'EDT'
                GenericAbbreviation = 'ET'
                SortOrder = 2
            }
            Central = @{
                Label = 'Central'
                WindowsId = 'Central Standard Time'
                IanaId = 'America/Chicago'
                Aliases = @(
                    'Central',
                    'Central Time',
                    'CT',
                    'CST',
                    'CDT',
                    'Central Standard Time',
                    'America/Chicago'
                )
                StandardAbbreviation = 'CST'
                DaylightAbbreviation = 'CDT'
                GenericAbbreviation = 'CT'
                SortOrder = 3
            }
            Mountain = @{
                Label = 'Mountain'
                WindowsId = 'Mountain Standard Time'
                IanaId = 'America/Denver'
                Aliases = @(
                    'Mountain',
                    'Mountain Time',
                    'MT',
                    'MST',
                    'MDT',
                    'Mountain Standard Time',
                    'America/Denver'
                )
                StandardAbbreviation = 'MST'
                DaylightAbbreviation = 'MDT'
                GenericAbbreviation = 'MT'
                SortOrder = 4
            }
            Arizona = @{
                Label = 'Arizona'
                WindowsId = 'US Mountain Standard Time'
                IanaId = 'America/Phoenix'
                Aliases = @(
                    'Arizona',
                    'Phoenix',
                    'AZ',
                    'MST Arizona',
                    'US Mountain Standard Time',
                    'America/Phoenix'
                )
                StandardAbbreviation = 'MST'
                DaylightAbbreviation = 'MST'
                GenericAbbreviation = 'MST'
                SortOrder = 5
            }
            Pacific = @{
                Label = 'Pacific'
                WindowsId = 'Pacific Standard Time'
                IanaId = 'America/Los_Angeles'
                Aliases = @(
                    'Pacific',
                    'Pacific Time',
                    'PT',
                    'PST',
                    'PDT',
                    'Pacific Standard Time',
                    'America/Los_Angeles'
                )
                StandardAbbreviation = 'PST'
                DaylightAbbreviation = 'PDT'
                GenericAbbreviation = 'PT'
                SortOrder = 6
            }
            Alaska = @{
                Label = 'Alaska'
                WindowsId = 'Alaskan Standard Time'
                IanaId = 'America/Anchorage'
                Aliases = @(
                    'Alaska',
                    'Alaska Time',
                    'AK',
                    'AKST',
                    'AKDT',
                    'Alaskan Standard Time',
                    'America/Anchorage'
                )
                StandardAbbreviation = 'AKST'
                DaylightAbbreviation = 'AKDT'
                GenericAbbreviation = 'AKT'
                SortOrder = 7
            }
            Aleutian = @{
                Label = 'Aleutian'
                WindowsId = 'Aleutian Standard Time'
                IanaId = 'America/Adak'
                Aliases = @(
                    'Aleutian',
                    'Aleutian Time',
                    'Adak',
                    'HAST',
                    'HADT',
                    'Aleutian Standard Time',
                    'America/Adak'
                )
                StandardAbbreviation = 'HAST'
                DaylightAbbreviation = 'HADT'
                GenericAbbreviation = 'HAT'
                SortOrder = 8
            }
            Hawaii = @{
                Label = 'Hawaii'
                WindowsId = 'Hawaiian Standard Time'
                IanaId = 'Pacific/Honolulu'
                Aliases = @(
                    'Hawaii',
                    'Hawaii Time',
                    'HI',
                    'HST',
                    'Hawaiian Standard Time',
                    'Pacific/Honolulu'
                )
                StandardAbbreviation = 'HST'
                DaylightAbbreviation = 'HST'
                GenericAbbreviation = 'HST'
                SortOrder = 9
            }
            Samoa = @{
                Label = 'Samoa'
                WindowsId = 'UTC-11'
                IanaId = 'Pacific/Pago_Pago'
                Aliases = @(
                    'Samoa',
                    'American Samoa',
                    'Pago Pago',
                    'UTC-11',
                    'Pacific/Pago_Pago'
                )
                StandardAbbreviation = 'SST'
                DaylightAbbreviation = 'SST'
                GenericAbbreviation = 'SST'
                SortOrder = 10
            }
            Chamorro = @{
                Label = 'Chamorro'
                WindowsId = 'West Pacific Standard Time'
                IanaId = 'Pacific/Guam'
                Aliases = @(
                    'Chamorro',
                    'Guam',
                    'Guam Time',
                    'ChST',
                    'CHST',
                    'West Pacific Standard Time',
                    'Pacific/Guam'
                )
                StandardAbbreviation = 'ChST'
                DaylightAbbreviation = 'ChST'
                GenericAbbreviation = 'ChST'
                SortOrder = 11
            }
        }

        function Find-TimeZoneInfoById
        {
            param(
                [Parameter(Mandatory)]
                [String[]]$CandidateIds
            )

            foreach ($candidateId in $CandidateIds)
            {
                if ([String]::IsNullOrWhiteSpace($candidateId))
                {
                    continue
                }

                try
                {
                    return [System.TimeZoneInfo]::FindSystemTimeZoneById($candidateId)
                }
                catch
                {
                    continue
                }
            }

            return $null
        }

        function Format-UtcOffset
        {
            param(
                [Parameter(Mandatory)]
                [TimeSpan]$Offset
            )

            $sign = if ($Offset.Ticks -lt 0) { '-' } else { '+' }
            $absoluteOffset = $Offset.Duration()
            return ('UTC{0}{1:00}:{2:00}' -f $sign, $absoluteOffset.Hours, $absoluteOffset.Minutes)
        }

        function Test-ExplicitTimeZoneString
        {
            param(
                [Parameter(Mandatory)]
                [String]$Text
            )

            if ($Text -match '(?i)\b(?:UTC|GMT)\b')
            {
                return $true
            }

            return $Text -match '(?i)[T\s]\d{1,2}:\d{2}(?::\d{2}(?:\.\d{1,7})?)?\s*(?:Z|[+-]\d{2}(?::?\d{2})?)\s*$'
        }

        function Resolve-DateTimeOffset
        {
            param(
                [Parameter(Mandatory)]
                [Object]$Value,

                [Parameter(Mandatory)]
                [String]$DefaultKind
            )

            if ($Value -is [DateTimeOffset])
            {
                $sourceKind = if ($Value.Offset -eq [TimeSpan]::Zero) { 'Utc' } else { 'OffsetSpecified' }

                return [PSCustomObject]@{
                    SourceDateTime = $Value
                    SourceKind = $sourceKind
                    SourceOffset = Format-UtcOffset -Offset $Value.Offset
                    InputType = 'DateTimeOffset'
                }
            }

            if ($Value -is [DateTime])
            {
                switch ($Value.Kind)
                {
                    Utc
                    {
                        $sourceDateTime = [DateTimeOffset]::new($Value)
                        $sourceKind = 'Utc'
                    }
                    Local
                    {
                        $sourceDateTime = [DateTimeOffset]::new($Value)
                        $sourceKind = 'Local'
                    }
                    default
                    {
                        $targetKind = if ($DefaultKind -eq 'Utc')
                        {
                            [DateTimeKind]::Utc
                        }
                        else
                        {
                            [DateTimeKind]::Local
                        }

                        $specifiedDateTime = [DateTime]::SpecifyKind($Value, $targetKind)
                        $sourceDateTime = [DateTimeOffset]::new($specifiedDateTime)
                        $sourceKind = '{0}Assumed' -f $DefaultKind
                    }
                }

                return [PSCustomObject]@{
                    SourceDateTime = $sourceDateTime
                    SourceKind = $sourceKind
                    SourceOffset = Format-UtcOffset -Offset $sourceDateTime.Offset
                    InputType = 'DateTime'
                }
            }

            if ($Value -isnot [String])
            {
                throw 'InputObject must be a String, DateTime, or DateTimeOffset.'
            }

            $trimmedValue = $Value.Trim()
            if ([String]::IsNullOrWhiteSpace($trimmedValue))
            {
                throw 'InputObject cannot be empty or whitespace.'
            }

            if (Test-ExplicitTimeZoneString -Text $trimmedValue)
            {
                $parsedDateTimeOffset = [DateTimeOffset]::MinValue
                foreach ($culture in $parseCultures)
                {
                    if ([DateTimeOffset]::TryParse(
                            $trimmedValue,
                            $culture,
                            [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
                            [ref]$parsedDateTimeOffset))
                    {
                        $sourceKind = if ($parsedDateTimeOffset.Offset -eq [TimeSpan]::Zero) { 'Utc' } else { 'OffsetSpecified' }

                        return [PSCustomObject]@{
                            SourceDateTime = $parsedDateTimeOffset
                            SourceKind = $sourceKind
                            SourceOffset = Format-UtcOffset -Offset $parsedDateTimeOffset.Offset
                            InputType = 'String'
                        }
                    }
                }

                throw "Unable to parse timezone-aware date/time string '$trimmedValue'."
            }

            $parsedDateTime = [DateTime]::MinValue
            $didParse = $false
            foreach ($culture in $parseCultures)
            {
                if ([DateTime]::TryParse(
                        $trimmedValue,
                        $culture,
                        [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
                        [ref]$parsedDateTime))
                {
                    $didParse = $true
                    break
                }
            }

            if (-not $didParse)
            {
                throw "Unable to parse date/time string '$trimmedValue'."
            }

            $assumedKind = if ($DefaultKind -eq 'Utc')
            {
                [DateTimeKind]::Utc
            }
            else
            {
                [DateTimeKind]::Local
            }

            $normalizedDateTime = [DateTime]::SpecifyKind($parsedDateTime, $assumedKind)
            $normalizedDateTimeOffset = [DateTimeOffset]::new($normalizedDateTime)

            return [PSCustomObject]@{
                SourceDateTime = $normalizedDateTimeOffset
                SourceKind = '{0}Assumed' -f $DefaultKind
                SourceOffset = Format-UtcOffset -Offset $normalizedDateTimeOffset.Offset
                InputType = 'String'
            }
        }

        function Test-TimeZoneObservesDaylightSavingTime
        {
            param(
                [Parameter(Mandatory)]
                [System.TimeZoneInfo]$TimeZoneInfo,

                [Parameter(Mandatory)]
                [DateTimeOffset]$ReferenceDateTime
            )

            if (-not $TimeZoneInfo.SupportsDaylightSavingTime)
            {
                return $false
            }

            $referenceDate = $ReferenceDateTime.Date
            foreach ($adjustmentRule in $TimeZoneInfo.GetAdjustmentRules())
            {
                if ($adjustmentRule.DaylightDelta -eq [TimeSpan]::Zero)
                {
                    continue
                }

                if ($adjustmentRule.DateStart.Date -le $referenceDate -and
                    $adjustmentRule.DateEnd.Date -ge $referenceDate)
                {
                    return $true
                }
            }

            return $false
        }

        function Resolve-TimeZoneSelection
        {
            param(
                [AllowNull()]
                [String[]]$RequestedTimeZones
            )

            $aliasLookup = @{}
            foreach ($zoneName in $zoneCatalog.Keys)
            {
                $zoneEntry = $zoneCatalog[$zoneName]
                foreach ($alias in $zoneEntry.Aliases)
                {
                    $aliasLookup[$alias.ToLowerInvariant()] = $zoneName
                }
            }

            $requestedValues = if ($RequestedTimeZones -and $RequestedTimeZones.Count -gt 0)
            {
                $RequestedTimeZones
            }
            else
            {
                $defaultTimeZones
            }

            $resolvedTimeZones = @()
            $seenLabels = @{}

            foreach ($requestedValue in $requestedValues)
            {
                if ([String]::IsNullOrWhiteSpace($requestedValue))
                {
                    continue
                }

                $trimmedValue = $requestedValue.Trim()
                $lookupKey = $trimmedValue.ToLowerInvariant()

                if ($aliasLookup.ContainsKey($lookupKey))
                {
                    $zoneName = $aliasLookup[$lookupKey]
                    if ($seenLabels.ContainsKey($zoneName))
                    {
                        continue
                    }

                    $catalogEntry = $zoneCatalog[$zoneName]
                    $candidateIds = if ($isWindowsPlatform)
                    {
                        @($catalogEntry.WindowsId, $catalogEntry.IanaId)
                    }
                    else
                    {
                        @($catalogEntry.IanaId, $catalogEntry.WindowsId)
                    }

                    $resolvedZone = Find-TimeZoneInfoById -CandidateIds $candidateIds
                    if (-not $resolvedZone)
                    {
                        throw "Unable to resolve timezone '$zoneName' on this platform."
                    }

                    $resolvedTimeZones += [PSCustomObject]@{
                        Label = $catalogEntry.Label
                        SortOrder = $catalogEntry.SortOrder
                        TimeZoneInfo = $resolvedZone
                        StandardAbbreviation = $catalogEntry.StandardAbbreviation
                        DaylightAbbreviation = $catalogEntry.DaylightAbbreviation
                        GenericAbbreviation = $catalogEntry.GenericAbbreviation
                    }

                    $seenLabels[$zoneName] = $true
                    continue
                }

                $directZone = Find-TimeZoneInfoById -CandidateIds @($trimmedValue)
                if ($directZone)
                {
                    if ($seenLabels.ContainsKey($directZone.Id))
                    {
                        continue
                    }

                    $resolvedTimeZones += [PSCustomObject]@{
                        Label = $trimmedValue
                        SortOrder = [Int32]::MaxValue
                        TimeZoneInfo = $directZone
                        StandardAbbreviation = $null
                        DaylightAbbreviation = $null
                        GenericAbbreviation = $null
                    }

                    $seenLabels[$directZone.Id] = $true
                    continue
                }

                throw "Unknown US timezone '$trimmedValue'. Supported names include: $($defaultTimeZones -join ', ')."
            }

            return @($resolvedTimeZones | Sort-Object -Property SortOrder, Label)
        }
    }

    process
    {
        $effectiveInputObject = if ($PSBoundParameters.ContainsKey('InputObject'))
        {
            $InputObject
        }
        else
        {
            [DateTimeOffset]::UtcNow
        }

        $sourceInfo = Resolve-DateTimeOffset -Value $effectiveInputObject -DefaultKind $AssumeInputKind
        $targetTimeZones = Resolve-TimeZoneSelection -RequestedTimeZones $TimeZone

        foreach ($targetTimeZone in $targetTimeZones)
        {
            $timeZoneInfo = $targetTimeZone.TimeZoneInfo
            $convertedDateTime = [System.TimeZoneInfo]::ConvertTime($sourceInfo.SourceDateTime, $timeZoneInfo)
            $localClockTime = [DateTime]::SpecifyKind($convertedDateTime.DateTime, [DateTimeKind]::Unspecified)
            $isDaylightSavingTime = $timeZoneInfo.IsDaylightSavingTime($localClockTime)
            $observesDaylightSavingTime = Test-TimeZoneObservesDaylightSavingTime -TimeZoneInfo $timeZoneInfo -ReferenceDateTime $convertedDateTime

            $timeZoneName = if ($isDaylightSavingTime -and -not [String]::IsNullOrWhiteSpace($timeZoneInfo.DaylightName))
            {
                $timeZoneInfo.DaylightName
            }
            else
            {
                $timeZoneInfo.StandardName
            }

            $abbreviation = if ($targetTimeZone.GenericAbbreviation)
            {
                if ($isDaylightSavingTime -and $targetTimeZone.DaylightAbbreviation)
                {
                    $targetTimeZone.DaylightAbbreviation
                }
                elseif ($targetTimeZone.StandardAbbreviation)
                {
                    $targetTimeZone.StandardAbbreviation
                }
                else
                {
                    $targetTimeZone.GenericAbbreviation
                }
            }
            else
            {
                $null
            }

            [PSCustomObject][ordered]@{
                TimeZone = $targetTimeZone.Label
                DateTime = $convertedDateTime
                TimeZoneId = $timeZoneInfo.Id
                TimeZoneName = $timeZoneName
                Abbreviation = $abbreviation
                UtcOffset = $convertedDateTime.Offset
                UtcOffsetString = Format-UtcOffset -Offset $convertedDateTime.Offset
                IsDaylightSavingTime = $isDaylightSavingTime
                ObservesDaylightSavingTime = $observesDaylightSavingTime
                SourceDateTime = $sourceInfo.SourceDateTime
                SourceKind = $sourceInfo.SourceKind
                SourceOffset = $sourceInfo.SourceOffset
                SourceInputType = $sourceInfo.InputType
            }
        }
    }
}
