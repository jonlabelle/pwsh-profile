BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . $PSScriptRoot/../../../Functions/Utilities/Format-Bytes.ps1
}

Describe 'Format-Bytes' {

    Context 'Storage conversions (IEC 1024)' {
        It 'Converts 1048576 bytes to 1 MB (IEC)' {
            $result = Format-Bytes -Value 1048576 -Base 1024
            $result.Bytes | Should -Be 1048576
            $result.Kilobytes | Should -Be 1024
            $result.Megabytes | Should -Be 1
        }
        It 'Parses string "1 MB" as megabytes (IEC base)' {
            $result = Format-Bytes -Value '1 MB' -Base 1024
            $result.Megabytes | Should -Be 1
            $result.Bytes | Should -Be 1048576
        }
        It 'Parses "1 MiB" using IEC units correctly' {
            $result = Format-Bytes -Value '1 MiB' -Base 1024
            $result.Megabytes | Should -Be 1
            $result.Bytes | Should -Be 1048576
        }
    }

    Context 'Storage conversions (SI 1000)' {
        It 'Converts 1000000 bytes to 1 MB (SI)' {
            $r = Format-Bytes -Value 1000000 -Base 1000
            $r.Megabytes | Should -Be 1
        }
    }

    Context 'Bandwidth conversions' {
        It 'BandwidthOnly returns bits units for "10 Mbps"' {
            $r = Format-Bytes -Value '10 Mbps' -BandwidthOnly
            $r.Bits | Should -Be 10000000
            $r.Megabits | Should -Be 10
            $r.Kilobits | Should -Be 10000
        }
        It 'Accepts no-space unit for "10Mbps"' {
            $r = Format-Bytes -Value '10Mbps' -BandwidthOnly
            $r.Bits | Should -Be 10000000
            $r.Megabits | Should -Be 10
        }
        It 'Parses spaced "1 Gbps" correctly' {
            $r = Format-Bytes -Value '1 Gbps' -BandwidthOnly
            $r.Gigabits | Should -Be 1
            $r.Megabits | Should -Be 1000
            $r.Kilobits | Should -Be 1000000
            $r.Bits | Should -Be 1000000000
        }
        It 'Parses no-space "1Gbps" correctly' {
            $r = Format-Bytes -Value '1Gbps' -BandwidthOnly
            $r.Gigabits | Should -Be 1
            $r.Megabits | Should -Be 1000
            $r.Kilobits | Should -Be 1000000
            $r.Bits | Should -Be 1000000000
        }
        It 'IncludeBandwidth adds bits alongside bytes' {
            $r = Format-Bytes -Value 1048576 -IncludeBandwidth -Base 1024
            $r.Bytes | Should -Be 1048576
            $r.Bits | Should -Be 8388608
            $r.Megabytes | Should -Be 1
            $r.Megabits | Should -BeGreaterThan 0
        }
    }

    Context 'Input parsing robustness' {
        It 'Accepts "1MB" (no space)' {
            $r = Format-Bytes -Value '1MB' -Base 1024
            $r.Bytes | Should -Be 1048576
        }
        It 'Accepts spelled out "1 megabyte"' {
            $r = Format-Bytes -Value '1 megabyte' -Base 1024
            $r.Bytes | Should -Be 1048576
        }
        It 'Throws on negative numeric input' {
            { Format-Bytes -Value -1 } | Should -Throw
        }
        It 'Throws on negative string input' {
            { Format-Bytes -Value '-10 MB' } | Should -Throw
        }
        It 'Throws on unknown unit' {
            { Format-Bytes -Value '1 XB' } | Should -Throw
        }
    }

    Context 'Parameter validation' {
        It 'Throws when IncludeBandwidth and BandwidthOnly together' {
            { Format-Bytes -Value 1 -IncludeBandwidth -BandwidthOnly } | Should -Throw
        }
    }
}
