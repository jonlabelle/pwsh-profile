#Requires -Modules Pester

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Utilities/ConvertTo-TimeZone.ps1"
}

Describe 'ConvertTo-TimeZone' -Tag 'Unit', 'Utilities' {
    Context 'Flexible time-zone resolution' {
        It 'Converts US Eastern time to India time using informal aliases' {
            $result = ConvertTo-TimeZone '2026-07-04 12:00' -FromTimeZone Eastern -ToTimeZone India

            $result.TimeZone | Should -Be 'India'
            $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-07-04 21:30:00 +05:30'
            $result.SourceDateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-07-04 12:00:00 -04:00'
            $result.SourceTimeZone | Should -Be 'Eastern'
            $result.Abbreviation | Should -Be 'IST'
        }

        It 'Accepts IANA time-zone ids on supported platforms' {
            $result = ConvertTo-TimeZone '2026-01-15 12:00' -FromTimeZone America/New_York -ToTimeZone Asia/Kolkata

            $result.TimeZone | Should -Be 'India'
            $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-01-15 22:30:00 +05:30'
        }

        It 'Accepts Windows time-zone ids' {
            $result = ConvertTo-TimeZone '2026-01-15 12:00' -FromTimeZone 'Eastern Standard Time' -ToTimeZone 'India Standard Time'

            $result.TimeZone | Should -Be 'India'
            $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-01-15 22:30:00 +05:30'
        }

        It 'Accepts normalized informal names' {
            $result = ConvertTo-TimeZone '2026-01-15T12:00:00Z' -ToTimeZone 'india_time'

            $result.TimeZone | Should -Be 'India'
            $result.UtcOffsetString | Should -Be 'UTC+05:30'
        }

        It 'Accepts a strongly typed TimeZoneInfo object' {
            $result = ConvertTo-TimeZone '2026-01-15T12:00:00Z' -ToTimeZone ([System.TimeZoneInfo]::Utc)

            $result.TimeZoneId | Should -Be ([System.TimeZoneInfo]::Utc.Id)
            $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-01-15 12:00:00 +00:00'
        }
    }

    Context 'Input interpretation' {
        It 'Uses FromTimeZone for a timezone-less string' {
            $result = ConvertTo-TimeZone '2026-01-15 18:00' -FromTimeZone India -ToTimeZone Eastern

            $result.SourceKind | Should -Be 'TimeZoneAssumed'
            $result.SourceOffset | Should -Be 'UTC+05:30'
            $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-01-15 07:30:00 -05:00'
        }

        It 'Reports UtcAssumed when UTC is the source of a timezone-less string' {
            $result = ConvertTo-TimeZone '2026-01-15 18:00' -FromTimeZone UTC -ToTimeZone Eastern

            $result.SourceKind | Should -Be 'UtcAssumed'
            $result.SourceOffset | Should -Be 'UTC+00:00'
        }

        It 'Preserves offset-aware input instead of applying FromTimeZone' {
            $result = ConvertTo-TimeZone '2026-01-15T12:00:00-08:00' -FromTimeZone India -ToTimeZone Eastern

            $result.SourceKind | Should -Be 'OffsetSpecified'
            $result.SourceTimeZone | Should -BeNullOrEmpty
            $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-01-15 15:00:00 -05:00'
        }

        It 'Preserves DateTime values whose Kind is UTC' {
            $inputObject = [DateTime]::SpecifyKind([DateTime]'2026-01-15 12:00', [DateTimeKind]::Utc)
            $result = ConvertTo-TimeZone $inputObject -FromTimeZone India -ToTimeZone Eastern

            $result.SourceKind | Should -Be 'Utc'
            $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss zzz') | Should -Be '2026-01-15 07:00:00 -05:00'
        }

        It 'Rejects a nonexistent source clock time during spring-forward' {
            {
                ConvertTo-TimeZone '2026-03-08 02:30' -FromTimeZone Eastern -ToTimeZone UTC
            } | Should -Throw '*does not exist*'
        }
    }

    Context 'Output behavior' {
        It 'Converts the current instant when InputObject is omitted' {
            $before = [DateTimeOffset]::UtcNow
            $result = ConvertTo-TimeZone -ToTimeZone UTC
            $after = [DateTimeOffset]::UtcNow

            $result.SourceKind | Should -Be 'Utc'
            $result.SourceDateTime.UtcDateTime | Should -BeGreaterThan $before.UtcDateTime.AddSeconds(-1)
            $result.SourceDateTime.UtcDateTime | Should -BeLessThan $after.UtcDateTime.AddSeconds(1)
        }

        It 'Returns targets in requested order' {
            $results = @(ConvertTo-TimeZone '2026-01-15T12:00:00Z' -ToTimeZone India, Eastern, Japan)

            $results.Count | Should -Be 3
            (($results | Select-Object -ExpandProperty TimeZone) -join ',') | Should -Be 'India,Eastern,Japan'
        }

        It 'Converts each pipeline input' {
            $results = @('2026-01-15T12:00:00Z', '2026-01-15T13:00:00Z') |
                ConvertTo-TimeZone -ToTimeZone India

            $results.Count | Should -Be 2
            $results[0].DateTime24 | Should -Be '17:30:00'
            $results[1].DateTime24 | Should -Be '18:30:00'
        }

        It 'Returns source and destination metadata' {
            $result = ConvertTo-TimeZone '2026-07-04 12:00' -FromTimeZone Eastern -ToTimeZone India
            $propertyNames = @($result.PSObject.Properties.Name)

            $propertyNames | Should -Contain 'TimeZoneId'
            $propertyNames | Should -Contain 'UtcOffset'
            $propertyNames | Should -Contain 'IsDaylightSavingTime'
            $propertyNames | Should -Contain 'SourceTimeZoneId'
            $propertyNames | Should -Contain 'SourceOffset'
        }
    }

    Context 'Error handling' {
        It 'Throws for an invalid date string' {
            { ConvertTo-TimeZone 'not-a-date' -ToTimeZone UTC } | Should -Throw
        }

        It 'Throws for an unknown source time zone' {
            { ConvertTo-TimeZone '2026-01-15 12:00' -FromTimeZone Mars -ToTimeZone UTC } | Should -Throw '*Unknown time zone*'
        }

        It 'Throws for an unknown destination time zone' {
            { ConvertTo-TimeZone '2026-01-15T12:00:00Z' -ToTimeZone Mars } | Should -Throw '*Unknown time zone*'
        }

        It 'Throws for an unsupported input type' {
            { ConvertTo-TimeZone 42 -ToTimeZone UTC } | Should -Throw '*String, DateTime, or DateTimeOffset*'
        }
    }
}
