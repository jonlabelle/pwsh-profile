#Requires -Modules Pester

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Utilities/ConvertTo-USDateTime.ps1"
}

Describe 'ConvertTo-USDateTime' -Tag 'Unit' {
    Context 'Default input behavior' {
        It 'Uses the current UTC date/time when InputObject is omitted' {
            $before = [DateTimeOffset]::UtcNow
            $result = ConvertTo-USDateTime -TimeZone Eastern
            $after = [DateTimeOffset]::UtcNow

            $result.SourceKind | Should -Be 'Utc'
            $result.SourceOffset | Should -Be 'UTC+00:00'
            $result.SourceDateTime.Offset | Should -Be ([TimeSpan]::Zero)
            $result.SourceDateTime.UtcDateTime | Should -BeGreaterThan $before.UtcDateTime.AddSeconds(-1)
            $result.SourceDateTime.UtcDateTime | Should -BeLessThan $after.UtcDateTime.AddSeconds(1)
        }
    }

    Context 'Default US timezone output' {
        It 'Returns the default US timezone set for UTC input' {
            $results = @(ConvertTo-USDateTime -InputObject '2026-07-04T12:00:00Z')

            $results.Count | Should -Be 11
            (($results | Select-Object -ExpandProperty TimeZone) -join ',') | Should -Be 'Atlantic,Eastern,Central,Mountain,Arizona,Pacific,Alaska,Aleutian,Hawaii,Samoa,Chamorro'

            $atlantic = $results | Where-Object TimeZone -eq 'Atlantic'
            $eastern = $results | Where-Object TimeZone -eq 'Eastern'
            $arizona = $results | Where-Object TimeZone -eq 'Arizona'
            $aleutian = $results | Where-Object TimeZone -eq 'Aleutian'
            $hawaii = $results | Where-Object TimeZone -eq 'Hawaii'
            $samoa = $results | Where-Object TimeZone -eq 'Samoa'
            $chamorro = $results | Where-Object TimeZone -eq 'Chamorro'

            $atlantic.UtcOffsetString | Should -Be 'UTC-04:00'
            $atlantic.IsDaylightSavingTime | Should -BeFalse
            $atlantic.ObservesDaylightSavingTime | Should -BeFalse
            $atlantic.Abbreviation | Should -Be 'AST'

            $eastern.UtcOffsetString | Should -Be 'UTC-04:00'
            $eastern.IsDaylightSavingTime | Should -BeTrue
            $eastern.Abbreviation | Should -Be 'EDT'
            $eastern.TimeZoneName | Should -Not -BeNullOrEmpty

            $arizona.UtcOffsetString | Should -Be 'UTC-07:00'
            $arizona.IsDaylightSavingTime | Should -BeFalse
            $arizona.ObservesDaylightSavingTime | Should -BeFalse
            $arizona.Abbreviation | Should -Be 'MST'

            $aleutian.UtcOffsetString | Should -Be 'UTC-09:00'
            $aleutian.IsDaylightSavingTime | Should -BeTrue
            $aleutian.ObservesDaylightSavingTime | Should -BeTrue
            $aleutian.Abbreviation | Should -Be 'HADT'

            $hawaii.UtcOffsetString | Should -Be 'UTC-10:00'
            $hawaii.IsDaylightSavingTime | Should -BeFalse
            $hawaii.ObservesDaylightSavingTime | Should -BeFalse
            $hawaii.Abbreviation | Should -Be 'HST'

            $samoa.UtcOffsetString | Should -Be 'UTC-11:00'
            $samoa.IsDaylightSavingTime | Should -BeFalse
            $samoa.ObservesDaylightSavingTime | Should -BeFalse
            $samoa.Abbreviation | Should -Be 'SST'

            $chamorro.UtcOffsetString | Should -Be 'UTC+10:00'
            $chamorro.IsDaylightSavingTime | Should -BeFalse
            $chamorro.ObservesDaylightSavingTime | Should -BeFalse
            $chamorro.Abbreviation | Should -Be 'ChST'
        }
    }

    Context 'Target timezone selection' {
        It 'Returns only requested timezones and resolves aliases' {
            $results = @(ConvertTo-USDateTime -InputObject '2026-01-15T15:00:00Z' -TimeZone ET, Pacific)

            $results.Count | Should -Be 2
            (($results | Select-Object -ExpandProperty TimeZone) -join ',') | Should -Be 'Eastern,Pacific'

            ($results | Where-Object TimeZone -eq 'Eastern').UtcOffsetString | Should -Be 'UTC-05:00'
            ($results | Where-Object TimeZone -eq 'Pacific').UtcOffsetString | Should -Be 'UTC-08:00'
        }

        It 'Returns properties in the expected display order' {
            $result = ConvertTo-USDateTime -InputObject '2026-04-23T17:14:53Z' -TimeZone Eastern
            $propertyNames = @($result.PSObject.Properties.Name)

            $propertyNames | Should -Be @(
                'TimeZone',
                'DateTime',
                'TimeZoneId',
                'TimeZoneName',
                'Abbreviation',
                'UtcOffset',
                'UtcOffsetString',
                'IsDaylightSavingTime',
                'ObservesDaylightSavingTime',
                'SourceDateTime',
                'SourceKind',
                'SourceOffset',
                'SourceInputType'
            )
        }
    }

    Context 'Input parsing and source metadata' {
        It 'Treats timezone-less strings as UTC when AssumeInputKind Utc is used' {
            $result = ConvertTo-USDateTime -InputObject '2026-01-15 15:00:00' -AssumeInputKind Utc -TimeZone Eastern

            $result.SourceKind | Should -Be 'UtcAssumed'
            $result.SourceOffset | Should -Be 'UTC+00:00'
            $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-01-15 10:00:00 -05:00'
        }

        It 'Preserves DateTime values marked as UTC' {
            $inputObject = [DateTime]::SpecifyKind([DateTime]'2026-01-15 15:00:00', [DateTimeKind]::Utc)

            $result = ConvertTo-USDateTime -InputObject $inputObject -TimeZone Eastern

            $result.SourceKind | Should -Be 'Utc'
            $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-01-15 10:00:00 -05:00'
        }

        It 'Accepts DateTimeOffset input with a non-UTC offset' {
            $inputObject = [DateTimeOffset]'2026-01-15T15:00:00-08:00'

            $result = ConvertTo-USDateTime -InputObject $inputObject -TimeZone Eastern

            $result.SourceKind | Should -Be 'OffsetSpecified'
            $result.SourceOffset | Should -Be 'UTC-08:00'
            $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-01-15 18:00:00 -05:00'
        }

        It 'Recognizes DateTime values marked as local time' {
            $inputObject = [DateTime]::SpecifyKind([DateTime]'2026-04-23 12:00:00', [DateTimeKind]::Local)

            $result = ConvertTo-USDateTime -InputObject $inputObject -TimeZone Eastern

            $result.SourceKind | Should -Be 'Local'
            $result.SourceOffset | Should -Match '^UTC[+-]\d{2}:\d{2}$'
            $result.TimeZoneName | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Pipeline support' {
        It 'Returns one output object per input when a single timezone is requested' {
            $results = @(
                '2026-01-15T12:00:00Z',
                '2026-01-15T13:00:00Z'
            ) | ConvertTo-USDateTime -TimeZone Hawaii

            @($results).Count | Should -Be 2
            $results[0].TimeZone | Should -Be 'Hawaii'
            $results[1].TimeZone | Should -Be 'Hawaii'
            $results[0].DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-01-15 02:00:00 -10:00'
            $results[1].DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-01-15 03:00:00 -10:00'
        }
    }

    Context 'Error handling' {
        It 'Throws for invalid date strings' {
            { ConvertTo-USDateTime -InputObject 'not-a-date' } | Should -Throw
        }

        It 'Throws for unsupported timezone names' {
            { ConvertTo-USDateTime -InputObject '2026-01-15T15:00:00Z' -TimeZone Mars } | Should -Throw
        }
    }
}
