function ConvertTo-TimeZone
{
    <#
    .SYNOPSIS
        Converts date/time values from one time zone to one or more other time zones.

    .DESCRIPTION
        Accepts strings, DateTime values, and DateTimeOffset values and returns rich
        objects containing the converted date/time and time-zone metadata. Target and
        source time zones can be supplied as IANA ids, Windows ids, installed time-zone
        names, common aliases, or System.TimeZoneInfo objects.

        Offset-aware input, including ISO 8601 strings ending in Z or a numeric offset,
        already identifies an instant and takes precedence over -FromTimeZone. For a
        timezone-less string or a DateTime whose Kind is Unspecified, -FromTimeZone
        identifies the source clock. It defaults to the local system time zone. A DateTime
        whose Kind is Utc or Local keeps that intrinsic meaning.

        Informal aliases cover commonly used zones, including Eastern, Pacific, India,
        London, Central Europe, Japan, China, and Sydney. Ambiguous abbreviations use the
        documented catalog meaning: IST means India Standard Time and CST means US Central.
        Prefer an IANA id, Windows id, or TimeZoneInfo object when ambiguity matters.

    .PARAMETER InputObject
        The date/time value to convert. Accepts String, DateTime, and DateTimeOffset values
        from the pipeline. If omitted, the current UTC date/time is used.

    .PARAMETER ToTimeZone
        One or more destination time zones. Each value can be an IANA id such as
        Asia/Kolkata, a Windows id such as India Standard Time, an installed time-zone
        name, a common alias such as India, or a System.TimeZoneInfo object.

    .PARAMETER FromTimeZone
        The source time zone for timezone-less strings and DateTime values whose Kind is
        Unspecified. Accepts the same forms as -ToTimeZone and defaults to Local. It is
        ignored for DateTimeOffset values, offset-aware strings, and DateTime values whose
        Kind is already Utc or Local.

    .EXAMPLE
        PS > ConvertTo-TimeZone '2026-07-04 12:00' -FromTimeZone Eastern -ToTimeZone India

        Converts noon US Eastern time to India time using informal aliases.

    .EXAMPLE
        PS > ConvertTo-TimeZone '2026-07-04 12:00' -FromTimeZone America/New_York -ToTimeZone Asia/Kolkata

        Performs the same conversion using IANA time-zone ids.

    .EXAMPLE
        PS > ConvertTo-TimeZone '2026-07-04 12:00' -FromTimeZone 'Eastern Standard Time' -ToTimeZone 'India Standard Time'

        Performs the same conversion using Windows time-zone ids, including on modern
        cross-platform .NET runtimes that support Windows/IANA id conversion.

    .EXAMPLE
        PS > $india = [System.TimeZoneInfo]::FindSystemTimeZoneById('Asia/Kolkata')
        PS > ConvertTo-TimeZone '2026-07-04T16:00:00Z' -ToTimeZone $india

        Supplies a strongly typed TimeZoneInfo destination.

    .EXAMPLE
        PS > ConvertTo-TimeZone '2026-01-15T09:30:00-08:00' -ToTimeZone London

        Converts an offset-aware timestamp; no source time zone is needed.

    .EXAMPLE
        PS > ConvertTo-TimeZone ([DateTimeOffset]::UtcNow) -ToTimeZone Local

        Converts the current UTC instant to the system local time zone.

    .EXAMPLE
        PS > ConvertTo-TimeZone -ToTimeZone Eastern, India, Japan

        Converts the current instant to several destination time zones.

    .EXAMPLE
        PS > '2026-03-01T12:00:00Z', '2026-06-01T12:00:00Z' | ConvertTo-TimeZone -ToTimeZone Pacific

        Converts pipeline input while applying daylight-saving rules for each date.

    .EXAMPLE
        PS > $utc = [DateTime]::SpecifyKind([DateTime]'2026-01-15 18:00', [DateTimeKind]::Utc)
        PS > ConvertTo-TimeZone $utc -ToTimeZone Sydney

        Preserves the intrinsic UTC kind of a DateTime value.

    .EXAMPLE
        PS > ConvertTo-TimeZone '2026-01-15 18:00' -FromTimeZone UTC -ToTimeZone 'Europe/Paris'

        Interprets a timezone-less string as UTC and targets a directly supplied IANA id.

    .EXAMPLE
        PS > ConvertTo-TimeZone '2026-01-15 09:00' -FromTimeZone ET -ToTimeZone UTC

        Uses short aliases for US Eastern time and UTC.

    .OUTPUTS
        [PSCustomObject]

    .NOTES
        Invalid local clock times during a daylight-saving spring transition are rejected.
        For a repeated clock time during a fall transition, .NET's standard-time resolution
        is used. Use DateTimeOffset input to select an exact occurrence explicitly.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-TimeZone.ps1

    .LINK
        https://learn.microsoft.com/dotnet/api/system.timezoneinfo

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-TimeZone.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, Position = 0)]
        [Alias('Value', 'DateTime', 'Timestamp')]
        [Object]$InputObject,

        [Parameter(Mandatory, Position = 1)]
        [Alias('TimeZone', 'TargetTimeZone', 'DestinationTimeZone', 'To')]
        [ValidateNotNullOrEmpty()]
        [Object[]]$ToTimeZone,

        [Parameter()]
        [Alias('SourceTimeZone', 'From')]
        [ValidateNotNullOrEmpty()]
        [Object]$FromTimeZone = 'Local'
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

        $zoneCatalog = [ordered]@{
            Utc = @{
                Label = 'UTC'
                WindowsId = 'UTC'
                IanaId = 'Etc/UTC'
                Aliases = @('UTC', 'GMT', 'Z', 'Zulu', 'Coordinated Universal Time', 'Etc/UTC', 'Etc/GMT')
                StandardAbbreviation = 'UTC'
                DaylightAbbreviation = 'UTC'
            }
            Atlantic = @{
                Label = 'Atlantic'
                WindowsId = 'SA Western Standard Time'
                IanaId = 'America/Puerto_Rico'
                Aliases = @('Atlantic', 'Atlantic Time', 'AST', 'Puerto Rico', 'San Juan')
                StandardAbbreviation = 'AST'
                DaylightAbbreviation = 'AST'
            }
            Eastern = @{
                Label = 'Eastern'
                WindowsId = 'Eastern Standard Time'
                IanaId = 'America/New_York'
                Aliases = @('Eastern', 'Eastern Time', 'US Eastern', 'ET', 'EST', 'EDT', 'New York')
                StandardAbbreviation = 'EST'
                DaylightAbbreviation = 'EDT'
            }
            Central = @{
                Label = 'Central'
                WindowsId = 'Central Standard Time'
                IanaId = 'America/Chicago'
                Aliases = @('Central', 'Central Time', 'US Central', 'CT', 'CST', 'CDT', 'Chicago')
                StandardAbbreviation = 'CST'
                DaylightAbbreviation = 'CDT'
            }
            Mountain = @{
                Label = 'Mountain'
                WindowsId = 'Mountain Standard Time'
                IanaId = 'America/Denver'
                Aliases = @('Mountain', 'Mountain Time', 'MT', 'MST', 'MDT', 'Denver')
                StandardAbbreviation = 'MST'
                DaylightAbbreviation = 'MDT'
            }
            Arizona = @{
                Label = 'Arizona'
                WindowsId = 'US Mountain Standard Time'
                IanaId = 'America/Phoenix'
                Aliases = @('Arizona', 'Arizona Time', 'Phoenix', 'AZ', 'MST Arizona')
                StandardAbbreviation = 'MST'
                DaylightAbbreviation = 'MST'
            }
            Pacific = @{
                Label = 'Pacific'
                WindowsId = 'Pacific Standard Time'
                IanaId = 'America/Los_Angeles'
                Aliases = @('Pacific', 'Pacific Time', 'US Pacific', 'PT', 'PST', 'PDT', 'Los Angeles')
                StandardAbbreviation = 'PST'
                DaylightAbbreviation = 'PDT'
            }
            Alaska = @{
                Label = 'Alaska'
                WindowsId = 'Alaskan Standard Time'
                IanaId = 'America/Anchorage'
                Aliases = @('Alaska', 'Alaska Time', 'AK', 'AKST', 'AKDT', 'Anchorage')
                StandardAbbreviation = 'AKST'
                DaylightAbbreviation = 'AKDT'
            }
            Aleutian = @{
                Label = 'Aleutian'
                WindowsId = 'Aleutian Standard Time'
                IanaId = 'America/Adak'
                Aliases = @('Aleutian', 'Aleutian Time', 'Adak', 'HAST', 'HADT')
                StandardAbbreviation = 'HAST'
                DaylightAbbreviation = 'HADT'
            }
            Hawaii = @{
                Label = 'Hawaii'
                WindowsId = 'Hawaiian Standard Time'
                IanaId = 'Pacific/Honolulu'
                Aliases = @('Hawaii', 'Hawaii Time', 'HI', 'HST', 'Honolulu')
                StandardAbbreviation = 'HST'
                DaylightAbbreviation = 'HST'
            }
            Samoa = @{
                Label = 'Samoa'
                WindowsId = 'UTC-11'
                IanaId = 'Pacific/Pago_Pago'
                Aliases = @('Samoa', 'American Samoa', 'Pago Pago', 'SST')
                StandardAbbreviation = 'SST'
                DaylightAbbreviation = 'SST'
            }
            Chamorro = @{
                Label = 'Chamorro'
                WindowsId = 'West Pacific Standard Time'
                IanaId = 'Pacific/Guam'
                Aliases = @('Chamorro', 'Guam', 'Guam Time', 'ChST')
                StandardAbbreviation = 'ChST'
                DaylightAbbreviation = 'ChST'
            }
            India = @{
                Label = 'India'
                WindowsId = 'India Standard Time'
                IanaId = 'Asia/Kolkata'
                Aliases = @('India', 'India Time', 'Indian Time', 'IST', 'Kolkata', 'Calcutta')
                StandardAbbreviation = 'IST'
                DaylightAbbreviation = 'IST'
            }
            UnitedKingdom = @{
                Label = 'United Kingdom'
                WindowsId = 'GMT Standard Time'
                IanaId = 'Europe/London'
                Aliases = @('United Kingdom', 'UK', 'Britain', 'British Time', 'London', 'BST')
                StandardAbbreviation = 'GMT'
                DaylightAbbreviation = 'BST'
            }
            CentralEurope = @{
                Label = 'Central Europe'
                WindowsId = 'W. Europe Standard Time'
                IanaId = 'Europe/Berlin'
                Aliases = @('Central Europe', 'Central European Time', 'CET', 'CEST', 'Berlin')
                StandardAbbreviation = 'CET'
                DaylightAbbreviation = 'CEST'
            }
            Japan = @{
                Label = 'Japan'
                WindowsId = 'Tokyo Standard Time'
                IanaId = 'Asia/Tokyo'
                Aliases = @('Japan', 'Japan Time', 'JST', 'Tokyo')
                StandardAbbreviation = 'JST'
                DaylightAbbreviation = 'JST'
            }
            China = @{
                Label = 'China'
                WindowsId = 'China Standard Time'
                IanaId = 'Asia/Shanghai'
                Aliases = @('China', 'China Time', 'Chinese Time', 'Beijing', 'Shanghai')
                StandardAbbreviation = 'CST'
                DaylightAbbreviation = 'CST'
            }
            Sydney = @{
                Label = 'Sydney'
                WindowsId = 'AUS Eastern Standard Time'
                IanaId = 'Australia/Sydney'
                Aliases = @('Sydney', 'Sydney Time', 'Australian Eastern', 'AET', 'AEST', 'AEDT')
                StandardAbbreviation = 'AEST'
                DaylightAbbreviation = 'AEDT'
            }
            NewZealand = @{
                Label = 'New Zealand'
                WindowsId = 'New Zealand Standard Time'
                IanaId = 'Pacific/Auckland'
                Aliases = @('New Zealand', 'New Zealand Time', 'NZ', 'NZST', 'NZDT', 'Auckland')
                StandardAbbreviation = 'NZST'
                DaylightAbbreviation = 'NZDT'
            }
        }

        function ConvertTo-NormalizedTimeZoneKey
        {
            param(
                [Parameter(Mandatory)]
                [String]$Value
            )

            return ($Value.Trim().ToLowerInvariant() -replace '[^a-z0-9]', '')
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

        function Resolve-TimeZoneMetadata
        {
            param(
                [Parameter(Mandatory)]
                [System.TimeZoneInfo]$TimeZoneInfo,

                [Parameter(Mandatory)]
                [String]$Label,

                [Parameter()]
                [AllowNull()]
                [String]$StandardAbbreviation,

                [Parameter()]
                [AllowNull()]
                [String]$DaylightAbbreviation
            )

            return [PSCustomObject]@{
                Label = $Label
                TimeZoneInfo = $TimeZoneInfo
                StandardAbbreviation = $StandardAbbreviation
                DaylightAbbreviation = $DaylightAbbreviation
            }
        }

        $aliasLookup = @{}
        foreach ($zoneName in $zoneCatalog.Keys)
        {
            $zoneEntry = $zoneCatalog[$zoneName]
            $catalogNames = @($zoneName, $zoneEntry.Label, $zoneEntry.WindowsId, $zoneEntry.IanaId) + $zoneEntry.Aliases
            foreach ($catalogName in $catalogNames)
            {
                $normalizedName = ConvertTo-NormalizedTimeZoneKey -Value $catalogName
                if (-not $aliasLookup.ContainsKey($normalizedName))
                {
                    $aliasLookup[$normalizedName] = $zoneName
                }
            }
        }

        function Resolve-TimeZoneValue
        {
            param(
                [Parameter(Mandatory)]
                [Object]$Value,

                [Parameter()]
                [Switch]$AllowLocal
            )

            if ($Value -is [System.TimeZoneInfo])
            {
                return Resolve-TimeZoneMetadata -TimeZoneInfo $Value -Label $Value.Id
            }

            if ($Value -isnot [String])
            {
                throw "Time zone values must be strings or System.TimeZoneInfo objects; received '$($Value.GetType().FullName)'."
            }

            $timeZoneText = $Value.Trim()
            if ([String]::IsNullOrWhiteSpace($timeZoneText))
            {
                throw 'Time zone values cannot be empty or whitespace.'
            }

            $normalizedValue = ConvertTo-NormalizedTimeZoneKey -Value $timeZoneText
            if ($normalizedValue -eq 'local' -or $normalizedValue -eq 'systemlocal' -or $normalizedValue -eq 'localtime')
            {
                if (-not $AllowLocal)
                {
                    throw "The special time zone name 'Local' can only be used as a source or destination value."
                }

                return Resolve-TimeZoneMetadata -TimeZoneInfo ([System.TimeZoneInfo]::Local) -Label 'Local'
            }

            if ($aliasLookup.ContainsKey($normalizedValue))
            {
                $catalogEntry = $zoneCatalog[$aliasLookup[$normalizedValue]]
                $candidateIds = if ($isWindowsPlatform)
                {
                    @($catalogEntry.WindowsId, $catalogEntry.IanaId)
                }
                else
                {
                    @($catalogEntry.IanaId, $catalogEntry.WindowsId)
                }

                $timeZoneInfo = Find-TimeZoneInfoById -CandidateIds $candidateIds
                if (-not $timeZoneInfo)
                {
                    throw "Unable to resolve time zone '$timeZoneText' on this platform."
                }

                return Resolve-TimeZoneMetadata `
                    -TimeZoneInfo $timeZoneInfo `
                    -Label $catalogEntry.Label `
                    -StandardAbbreviation $catalogEntry.StandardAbbreviation `
                    -DaylightAbbreviation $catalogEntry.DaylightAbbreviation
            }

            $timeZoneInfo = Find-TimeZoneInfoById -CandidateIds @($timeZoneText)
            if ($timeZoneInfo)
            {
                return Resolve-TimeZoneMetadata -TimeZoneInfo $timeZoneInfo -Label $timeZoneInfo.Id
            }

            $matchingZones = @(
                [System.TimeZoneInfo]::GetSystemTimeZones() | Where-Object {
                    $candidateNames = @($_.Id, $_.StandardName, $_.DaylightName, $_.DisplayName)
                    foreach ($candidateName in $candidateNames)
                    {
                        if (-not [String]::IsNullOrWhiteSpace($candidateName) -and
                            (ConvertTo-NormalizedTimeZoneKey -Value $candidateName) -eq $normalizedValue)
                        {
                            return $true
                        }
                    }

                    return $false
                }
            )

            if ($matchingZones.Count -eq 1)
            {
                return Resolve-TimeZoneMetadata -TimeZoneInfo $matchingZones[0] -Label $matchingZones[0].Id
            }

            if ($matchingZones.Count -gt 1)
            {
                $matchingIds = $matchingZones.Id -join ', '
                throw "Time zone '$timeZoneText' is ambiguous. Use one of these ids: $matchingIds."
            }

            throw "Unknown time zone '$timeZoneText'. Use an IANA id, Windows id, installed time-zone name, common alias, or System.TimeZoneInfo object."
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

        function ConvertFrom-WallClockTime
        {
            param(
                [Parameter(Mandatory)]
                [DateTime]$DateTime,

                [Parameter(Mandatory)]
                [PSCustomObject]$SourceTimeZone,

                [Parameter(Mandatory)]
                [String]$InputType
            )

            $wallClock = [DateTime]::SpecifyKind($DateTime, [DateTimeKind]::Unspecified)
            $sourceZoneInfo = $SourceTimeZone.TimeZoneInfo
            if ($sourceZoneInfo.IsInvalidTime($wallClock))
            {
                throw "The local time '$($wallClock.ToString('yyyy-MM-dd HH:mm:ss'))' does not exist in time zone '$($SourceTimeZone.Label)' because of a daylight-saving transition."
            }

            $utcDateTime = [System.TimeZoneInfo]::ConvertTimeToUtc($wallClock, $sourceZoneInfo)
            $utcOffsetValue = [DateTimeOffset]::new($utcDateTime)
            $sourceDateTime = [System.TimeZoneInfo]::ConvertTime($utcOffsetValue, $sourceZoneInfo)

            $sourceKind = if ($SourceTimeZone.Label -eq 'UTC')
            {
                'UtcAssumed'
            }
            elseif ($SourceTimeZone.Label -eq 'Local')
            {
                'LocalAssumed'
            }
            else
            {
                'TimeZoneAssumed'
            }

            return [PSCustomObject]@{
                SourceDateTime = $sourceDateTime
                SourceKind = $sourceKind
                SourceOffset = Format-UtcOffset -Offset $sourceDateTime.Offset
                SourceInputType = $InputType
                SourceTimeZone = $SourceTimeZone.Label
                SourceTimeZoneId = $sourceZoneInfo.Id
            }
        }

        function Resolve-InputDateTime
        {
            param(
                [Parameter(Mandatory)]
                [Object]$Value,

                [Parameter(Mandatory)]
                [PSCustomObject]$SourceTimeZone
            )

            if ($Value -is [DateTimeOffset])
            {
                $sourceKind = if ($Value.Offset -eq [TimeSpan]::Zero) { 'Utc' } else { 'OffsetSpecified' }
                return [PSCustomObject]@{
                    SourceDateTime = $Value
                    SourceKind = $sourceKind
                    SourceOffset = Format-UtcOffset -Offset $Value.Offset
                    SourceInputType = 'DateTimeOffset'
                    SourceTimeZone = $null
                    SourceTimeZoneId = $null
                }
            }

            if ($Value -is [DateTime])
            {
                if ($Value.Kind -eq [DateTimeKind]::Utc -or $Value.Kind -eq [DateTimeKind]::Local)
                {
                    $sourceDateTime = [DateTimeOffset]::new($Value)
                    return [PSCustomObject]@{
                        SourceDateTime = $sourceDateTime
                        SourceKind = $Value.Kind.ToString()
                        SourceOffset = Format-UtcOffset -Offset $sourceDateTime.Offset
                        SourceInputType = 'DateTime'
                        SourceTimeZone = $Value.Kind.ToString()
                        SourceTimeZoneId = if ($Value.Kind -eq [DateTimeKind]::Utc) { [System.TimeZoneInfo]::Utc.Id } else { [System.TimeZoneInfo]::Local.Id }
                    }
                }

                return ConvertFrom-WallClockTime -DateTime $Value -SourceTimeZone $SourceTimeZone -InputType 'DateTime'
            }

            if ($Value -isnot [String])
            {
                throw 'InputObject must be a String, DateTime, or DateTimeOffset.'
            }

            $dateTimeText = $Value.Trim()
            if ([String]::IsNullOrWhiteSpace($dateTimeText))
            {
                throw 'InputObject cannot be empty or whitespace.'
            }

            if (Test-ExplicitTimeZoneString -Text $dateTimeText)
            {
                $parsedDateTimeOffset = [DateTimeOffset]::MinValue
                foreach ($culture in $parseCultures)
                {
                    if ([DateTimeOffset]::TryParse(
                            $dateTimeText,
                            $culture,
                            [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
                            [ref]$parsedDateTimeOffset))
                    {
                        $sourceKind = if ($parsedDateTimeOffset.Offset -eq [TimeSpan]::Zero) { 'Utc' } else { 'OffsetSpecified' }
                        return [PSCustomObject]@{
                            SourceDateTime = $parsedDateTimeOffset
                            SourceKind = $sourceKind
                            SourceOffset = Format-UtcOffset -Offset $parsedDateTimeOffset.Offset
                            SourceInputType = 'String'
                            SourceTimeZone = $null
                            SourceTimeZoneId = $null
                        }
                    }
                }

                throw "Unable to parse timezone-aware date/time string '$dateTimeText'."
            }

            $parsedDateTime = [DateTime]::MinValue
            $didParse = $false
            foreach ($culture in $parseCultures)
            {
                if ([DateTime]::TryParse(
                        $dateTimeText,
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
                throw "Unable to parse date/time string '$dateTimeText'."
            }

            return ConvertFrom-WallClockTime -DateTime $parsedDateTime -SourceTimeZone $SourceTimeZone -InputType 'String'
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
                if ($adjustmentRule.DaylightDelta -ne [TimeSpan]::Zero -and
                    $adjustmentRule.DateStart.Date -le $referenceDate -and
                    $adjustmentRule.DateEnd.Date -ge $referenceDate)
                {
                    return $true
                }
            }

            return $false
        }

        $resolvedSourceTimeZone = Resolve-TimeZoneValue -Value $FromTimeZone -AllowLocal
        $resolvedTargetTimeZones = @()
        $seenTimeZoneIds = @{}
        foreach ($targetValue in $ToTimeZone)
        {
            $resolvedTarget = Resolve-TimeZoneValue -Value $targetValue -AllowLocal
            if (-not $seenTimeZoneIds.ContainsKey($resolvedTarget.TimeZoneInfo.Id))
            {
                $resolvedTargetTimeZones += $resolvedTarget
                $seenTimeZoneIds[$resolvedTarget.TimeZoneInfo.Id] = $true
            }
        }

        if ($resolvedTargetTimeZones.Count -eq 0)
        {
            throw 'At least one non-empty destination time zone is required.'
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

        $sourceInfo = Resolve-InputDateTime -Value $effectiveInputObject -SourceTimeZone $resolvedSourceTimeZone

        foreach ($targetTimeZone in $resolvedTargetTimeZones)
        {
            $timeZoneInfo = $targetTimeZone.TimeZoneInfo
            $convertedDateTime = [System.TimeZoneInfo]::ConvertTime($sourceInfo.SourceDateTime, $timeZoneInfo)
            $isDaylightSavingTime = $timeZoneInfo.IsDaylightSavingTime($convertedDateTime)
            $observesDaylightSavingTime = Test-TimeZoneObservesDaylightSavingTime -TimeZoneInfo $timeZoneInfo -ReferenceDateTime $convertedDateTime

            $timeZoneName = if ($isDaylightSavingTime -and -not [String]::IsNullOrWhiteSpace($timeZoneInfo.DaylightName))
            {
                $timeZoneInfo.DaylightName
            }
            else
            {
                $timeZoneInfo.StandardName
            }

            $abbreviation = if ($isDaylightSavingTime -and $targetTimeZone.DaylightAbbreviation)
            {
                $targetTimeZone.DaylightAbbreviation
            }
            else
            {
                $targetTimeZone.StandardAbbreviation
            }

            [PSCustomObject][ordered]@{
                TimeZone = $targetTimeZone.Label
                DateTime = $convertedDateTime
                DateTime24 = $convertedDateTime.ToString('HH:mm:ss')
                TimeZoneId = $timeZoneInfo.Id
                TimeZoneName = $timeZoneName
                Abbreviation = $abbreviation
                UtcOffset = $convertedDateTime.Offset
                UtcOffsetString = Format-UtcOffset -Offset $convertedDateTime.Offset
                IsDaylightSavingTime = $isDaylightSavingTime
                ObservesDaylightSavingTime = $observesDaylightSavingTime
                SourceDateTime = $sourceInfo.SourceDateTime
                SourceDateTime24 = $sourceInfo.SourceDateTime.ToString('HH:mm:ss')
                SourceKind = $sourceInfo.SourceKind
                SourceOffset = $sourceInfo.SourceOffset
                SourceInputType = $sourceInfo.SourceInputType
                SourceTimeZone = $sourceInfo.SourceTimeZone
                SourceTimeZoneId = $sourceInfo.SourceTimeZoneId
            }
        }
    }
}
