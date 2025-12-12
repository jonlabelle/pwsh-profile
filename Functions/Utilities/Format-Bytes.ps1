function Format-Bytes
{
    <#
    .SYNOPSIS
        Formats byte or bit quantities into human-friendly unit conversions.

    .DESCRIPTION
        Parses values like 1048576, '1 MB', '1MB', '1 megabyte', '10 Mbps', or '8 Mb' and
        returns a PSCustomObject containing conversions across storage (bytes) and/or
        bandwidth (bits) units depending on parameters.

        Supports SI (base 1000) and IEC (base 1024) scaling.
        By default, IEC (1024) is used for storage. Bandwidth (bits) typically uses SI (1000),
        but you can override with -Base.

        Use -IncludeBandwidth to add bit-based conversions alongside storage conversions.
        Use -BandwidthOnly to return only bit-based conversions. -IncludeBandwidth and
        -BandwidthOnly are mutually exclusive.

    .PARAMETER Value
        The input quantity to format. Accepts numeric values (treated as bytes by default)
        or strings that include a unit like 'MB', 'MiB', 'megabyte', 'Gb', 'Mbps', etc.

        .PARAMETER Base
                Scaling base to use: 1000 (SI) or 1024 (IEC). Defaults to 1024.

                - 1000 (SI): Decimal multiples (kB, MB, GB, TB).
                    Common in networking (e.g., Mbps) and many storage vendor specifications.
                    Prefer this for bandwidth/transmission rates and when you want decimal scaling.
                - 1024 (IEC): Binary multiples (KiB, MiB, GiB, TiB).
                    Common in operating systems and file size reporting.
                    Prefer this for disk and file size calculations.

                Note: If -Base is not specified, the function uses sensible defaults:
                - Storage (bytes) conversions use 1024
                - Bandwidth (bits) conversions use 1000

                If you do specify -Base, that value is used for both storage and bandwidth to keep
                results consistent in mixed outputs.

    .PARAMETER IncludeBandwidth
        Adds bandwidth/bit conversions in the result along with storage conversions.

    .PARAMETER BandwidthOnly
        Returns only bandwidth/bit conversions. Cannot be used with -IncludeBandwidth.

    .PARAMETER Precision
        Number of decimal places to round display values. Default 2.

    .EXAMPLE
        PS > Format-Bytes -Value 1048576

        Bytes     : 1048576
        Kilobytes : 1024
        Megabytes : 1
        Gigabytes : 0
        Terabytes : 0
        Petabytes : 0

        Bytes: 1048576, Kilobytes: 1024, Megabytes: 1, Gigabytes: 0.00, ...

    .EXAMPLE
        PS > Format-Bytes -Value '10 Mbps' -BandwidthOnly

        Bits     : 10000000
        Kilobits : 10000
        Megabits : 10
        Gigabits : 0.01
        Terabits : 0

        Bits: 10000000, Kilobits: 10000, Megabits: 10, ...

    .EXAMPLE
        PS > Format-Bytes -Value '1MB' -IncludeBandwidth

        Bytes     : 1048576
        Kilobytes : 1024
        Megabytes : 1
        Gigabytes : 0
        Terabytes : 0
        Petabytes : 0
        Bits      : 8388608
        Kilobits  : 8388.61
        Megabits  : 8.39
        Gigabits  : 0.01
        Terabits  : 0

        Returns both storage (bytes) and bandwidth (bits) conversions for 1 megabyte.

    .EXAMPLE
        PS > Format-Bytes -Value '1 megabyte'

        Bytes     : 1048576
        Kilobytes : 1024
        Megabytes : 1
        Gigabytes : 0
        Terabytes : 0
        Petabytes : 0

        Parses the spelled-out unit and returns all storage conversions.

    .EXAMPLE
        PS > Format-Bytes -Value 1000000 -Base 1000

        Bytes     : 1000000
        Kilobytes : 1000
        Megabytes : 1
        Gigabytes : 0
        Terabytes : 0
        Petabytes : 0

        Uses SI scaling to show 1 MB from 1,000,000 bytes.

    .EXAMPLE
        PS > Format-Bytes -Value '1 GiB'

        Bytes     : 1073741824
        Kilobytes : 1048576
        Megabytes : 1024
        Gigabytes : 1
        Terabytes : 0
        Petabytes : 0

        Treats GiB as IEC (1024-based) and returns storage conversions.

    .EXAMPLE
        PS > Format-Bytes -Value '100 Mb' -BandwidthOnly

        Bits     : 838860800
        Kilobits : 838860.8
        Megabits : 838.86
        Gigabits : 0.84
        Terabits : 0

        Returns conversions for 100 megabits.

    .EXAMPLE
        PS > Format-Bytes -Value '2.5 GB' -Base 1000 -Precision 3

        Bytes     : 2500000000
        Kilobytes : 2500000
        Megabytes : 2500
        Gigabytes : 2.5
        Terabytes : 0.002
        Petabytes : 0

        Shows fractional gigabytes with 3 decimal places using SI scaling.

    .EXAMPLE
        PS > 1048576, 2097152 | Format-Bytes

        Bytes     : 1048576
        Kilobytes : 1024
        Megabytes : 1
        Gigabytes : 0
        Terabytes : 0
        Petabytes : 0

        Bytes     : 2097152
        Kilobytes : 2048
        Megabytes : 2
        Gigabytes : 0
        Terabytes : 0
        Petabytes : 0

        Accepts pipeline input of numeric bytes, returning a PSCustomObject for each.

    .EXAMPLE
        PS > Format-Bytes -Value 1048576 -IncludeBandwidth

        Bytes     : 1048576
        Kilobytes : 1024
        Megabytes : 1
        Gigabytes : 0
        Terabytes : 0
        Petabytes : 0
        Bits      : 8388608
        Kilobits  : 8388.61
        Megabits  : 8.39
        Gigabits  : 0.01
        Terabits  : 0

        Useful to compare file size (bytes) with equivalent link speed (bits).

    .EXAMPLE
        PS > Format-Bytes -Value '10 Mbps' -BandwidthOnly -Base 1024

        Bits     : 10000000
        Kilobits : 9765.62
        Megabits : 9.54
        Gigabits : 0.01
        Terabits : 0

        Overrides default SI scaling for bandwidth to use 1024 if you need binary steps.

    .EXAMPLE
        PS > Format-Bytes -Value 1234567 -Base 1000 -Precision 4

        Bytes     : 1234567
        Kilobytes : 1234.567
        Megabytes : 1.2346
        Gigabytes : 0.0012
        Terabytes : 0
        Petabytes : 0

        Adjusts rounding precision to 4 decimals for finer-grained results.

    .OUTPUTS
        [PSCustomObject]

    .NOTES
        Cross-platform, no Windows-only cmdlets. Follows repository conventions.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Format-Bytes.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Input', 'Quantity')]
        [object]$Value,

        [Parameter()]
        [ValidateSet('1000', '1024')]
        [string]$Base = '1024',

        [Parameter()]
        [int]$Precision = 2,

        [Parameter()]
        [switch]$IncludeBandwidth,

        [Parameter()]
        [switch]$BandwidthOnly
    )

    begin
    {
        if ($IncludeBandwidth.IsPresent -and $BandwidthOnly.IsPresent)
        {
            throw '-IncludeBandwidth and -BandwidthOnly cannot be used together.'
        }

        $baseInt = [int]$Base
        $explicitBase = $PSBoundParameters.ContainsKey('Base')
        $storageBase = if ($explicitBase) { $baseInt } else { 1024 }
        $bandwidthBase = if ($explicitBase) { $baseInt } else { 1000 }

        function Resolve-InputQuantity
        {
            param([object]$Raw)

            # Returns hashtable: @{ kind = 'storage' | 'bandwidth'; bytes = <int64>; bits = <int64>; base = <int>; }
            # Universal negative check (works for both numeric and string inputs)
            $rawString = [string]$Raw
            if ($rawString.Trim().StartsWith('-'))
            {
                throw 'Value cannot be negative.'
            }
            if ($Raw -is [double] -or $Raw -is [int] -or $Raw -is [long])
            {
                # Numeric: treat as bytes by default
                if ([double]$Raw -lt 0) { throw 'Value cannot be negative.' }
                return @{ kind = 'storage'; bytes = [int64]$Raw; bits = ([int64]$Raw * 8); base = $baseInt }
            }

            $s = [string]$Raw
            $s = $s.Trim()

            # Capture number (int/float) and optional unit word(s)
            # Examples handled: "1 MB", "1MB", "1 megabyte", "10 Mbps", "8 Mb", "1 MiB"
            $numPattern = '(?<num>\d+(?:\.\d+)?)\s*(?<unit>[A-Za-z]+)?(?:\s*(?<word>bytes|byte|bits|bit|per\s*second|ps|/s))?'
            $m = [regex]::Match($s, $numPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if (-not $m.Success)
            {
                throw "Unrecognized value: '$s'"
            }

            $num = [double]$m.Groups['num'].Value
            if ($num -lt 0) { throw 'Value cannot be negative.' }
            $unitToken = ($m.Groups['unit'].Value).ToLower()
            $wordToken = ($m.Groups['word'].Value).ToLower()

            # Normalize unit intent
            $isBitContext = $false
            if ($wordToken -match 'bit') { $isBitContext = $true }
            if ($s -match '\bmbps\b|\bkbps\b|\bps\b|megabits|kilobits|gigabits') { $isBitContext = $true }
            # Also infer bit context from unit token (e.g., 'Mbps', 'Gbps', 'kbps')
            if ($unitToken -match 'bps' -or $unitToken -match 'bit') { $isBitContext = $true }

            # Map unit prefixes for storage/bandwidth
            $units = @{
                storage = @{
                    'b' = 1; 'byte' = 1; 'bytes' = 1
                    'kb' = $storageBase; 'kib' = 1024
                    'mb' = [math]::Pow($storageBase, 2); 'mib' = [math]::Pow(1024, 2)
                    'gb' = [math]::Pow($storageBase, 3); 'gib' = [math]::Pow(1024, 3)
                    'tb' = [math]::Pow($storageBase, 4); 'tib' = [math]::Pow(1024, 4)
                    'pb' = [math]::Pow($storageBase, 5); 'pib' = [math]::Pow(1024, 5)
                }
                bandwidth = @{
                    'b' = 1; 'bit' = 1; 'bits' = 1
                    'kb' = $bandwidthBase; 'kib' = 1024; 'kbps' = 1000
                    'mb' = [math]::Pow($bandwidthBase, 2); 'mib' = [math]::Pow(1024, 2); 'mbps' = 1000000
                    'gb' = [math]::Pow($bandwidthBase, 3); 'gib' = [math]::Pow(1024, 3); 'gbps' = 1000000000
                    'tb' = [math]::Pow($bandwidthBase, 4); 'tib' = [math]::Pow(1024, 4)
                }
            }

            # Determine kind and multiplier
            $kind = if ($isBitContext) { 'bandwidth' } else { 'storage' }
            $multiplier = 1
            if ([string]::IsNullOrEmpty($unitToken))
            {
                $multiplier = 1
            }
            else
            {
                $ut = $unitToken
                # Accept common words
                switch ($ut)
                {
                    'byte' { $ut = 'b' }
                    'bytes' { $ut = 'b' }
                    'megabyte' { $ut = 'mb' }
                    'kilobyte' { $ut = 'kb' }
                    'gigabyte' { $ut = 'gb' }
                    'terabyte' { $ut = 'tb' }
                    'petabyte' { $ut = 'pb' }
                    'megabit' { $ut = 'mb' ; $kind = 'bandwidth' }
                    'kilobit' { $ut = 'kb' ; $kind = 'bandwidth' }
                    'gigabit' { $ut = 'gb' ; $kind = 'bandwidth' }
                    'terabit' { $ut = 'tb' ; $kind = 'bandwidth' }
                }

                if ($kind -eq 'storage')
                {
                    if ($units.storage.ContainsKey($ut)) { $multiplier = [double]$units.storage[$ut] } else { throw "Unknown unit '$unitToken' for storage." }
                }
                else
                {
                    if ($units.bandwidth.ContainsKey($ut)) { $multiplier = [double]$units.bandwidth[$ut] } else { throw "Unknown unit '$unitToken' for bandwidth." }
                }
            }

            if ($kind -eq 'storage')
            {
                $bytes = [int64]([math]::Round($num * $multiplier))
                return @{ kind = 'storage'; bytes = $bytes; bits = ($bytes * 8); base = $baseInt }
            }
            else
            {
                $bits = [int64]([math]::Round($num * $multiplier))
                return @{ kind = 'bandwidth'; bits = $bits; bytes = [int64]([math]::Floor($bits / 8)); base = $baseInt }
            }
        }

        function Build-StorageObject
        {
            param([int64]$Bytes, [int]$Base, [int]$Prec)
            $k = [double]$Base
            $kb = [math]::Round($Bytes / $k, $Prec)
            $mb = [math]::Round($Bytes / [math]::Pow($k, 2), $Prec)
            $gb = [math]::Round($Bytes / [math]::Pow($k, 3), $Prec)
            $tb = [math]::Round($Bytes / [math]::Pow($k, 4), $Prec)
            $pb = [math]::Round($Bytes / [math]::Pow($k, 5), $Prec)
            [PSCustomObject]@{
                Bytes = $Bytes
                Kilobytes = $kb
                Megabytes = $mb
                Gigabytes = $gb
                Terabytes = $tb
                Petabytes = $pb
            }
        }

        function Build-BandwidthObject
        {
            param([int64]$Bits, [int]$Base, [int]$Prec)
            $k = [double]$Base
            $kb = [math]::Round($Bits / $k, $Prec)
            $mb = [math]::Round($Bits / [math]::Pow($k, 2), $Prec)
            $gb = [math]::Round($Bits / [math]::Pow($k, 3), $Prec)
            $tb = [math]::Round($Bits / [math]::Pow($k, 4), $Prec)
            [PSCustomObject]@{
                Bits = $Bits
                Kilobits = $kb
                Megabits = $mb
                Gigabits = $gb
                Terabits = $tb
            }
        }
    }

    process
    {
        $parsed = Resolve-InputQuantity -Raw $Value

        if ($BandwidthOnly.IsPresent)
        {
            $bw = Build-BandwidthObject -Bits $parsed.bits -Base $bandwidthBase -Prec $Precision
            return $bw
        }

        # Storage object
        $st = Build-StorageObject -Bytes $parsed.bytes -Base $storageBase -Prec $Precision

        if ($IncludeBandwidth.IsPresent)
        {
            $bw = Build-BandwidthObject -Bits $parsed.bits -Base $bandwidthBase -Prec $Precision
            # Merge objects
            $merged = [ordered]@{}
            foreach ($p in $st.PSObject.Properties) { $merged[$p.Name] = $p.Value }
            foreach ($p in $bw.PSObject.Properties) { $merged[$p.Name] = $p.Value }
            return [PSCustomObject]$merged
        }
        else
        {
            return $st
        }
    }

    end
    {
        # No-op
    }
}
