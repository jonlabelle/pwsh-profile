BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    $functionPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Functions\NetworkAndDns\Show-NetworkLatencyGraph.ps1'
    $functionPath = [System.IO.Path]::GetFullPath($functionPath)
    . $functionPath
}

Describe 'Show-NetworkLatencyGraph (Data mode)' {
    It 'returns non-empty string (Sparkline)' {
        $data = @(10, 20, 30, 40, 50)
        $result = Show-NetworkLatencyGraph -Data $data -GraphType 'Sparkline'

        $result | Should-HaveType ([System.String])
        $result.Length | Should-BeGreaterThan 0
    }

    It 'includes stats when -ShowStats is set' {
        $data = @(20, 25, 30, 35, 40)
        $result = Show-NetworkLatencyGraph -Data $data -GraphType 'Sparkline' -ShowStats

        $result | Should-MatchString 'min:'
        $result | Should-MatchString 'max:'
        $result | Should-MatchString 'avg:'
    }

    Context 'Console theme' {
        BeforeAll {
            $script:EscapeCharacter = [String][Char]27
            $script:AnsiPattern = "$script:EscapeCharacter\[[0-9;]*m"
        }

        It 'uses only the accent, muted, and reset codes for healthy sparkline data' {
            $result = Show-NetworkLatencyGraph -Data @(10, 12, 14, 16) -GraphType 'Sparkline' -ShowStats
            $codes = [Regex]::Matches($result, $script:AnsiPattern).Value | Sort-Object -Unique

            $codes.Count | Should-Be 3
            $codes | Should-ContainCollection "$script:EscapeCharacter[38;5;37m"
            $codes | Should-ContainCollection "$script:EscapeCharacter[38;5;244m"
            $codes | Should-ContainCollection "$script:EscapeCharacter[0m"
        }

        It 'uses the same monochrome palette in time-series and distribution graphs' {
            foreach ($graphType in 'TimeSeries', 'Distribution')
            {
                $parameters = @{
                    Data = @(10, 12, 14, 16)
                    GraphType = $graphType
                }
                if ($graphType -eq 'TimeSeries')
                {
                    $parameters.Width = 20
                    $parameters.Height = 5
                    $parameters.ShowStats = $true
                }

                $result = Show-NetworkLatencyGraph @parameters
                $codes = [Regex]::Matches($result, $script:AnsiPattern).Value | Sort-Object -Unique

                $codes.Count | Should-Be 3
                $codes | Should-ContainCollection "$script:EscapeCharacter[38;5;37m"
                $codes | Should-ContainCollection "$script:EscapeCharacter[38;5;244m"
                $codes | Should-ContainCollection "$script:EscapeCharacter[0m"
            }
        }

        It 'emits no ANSI sequences when NoColor is requested' {
            $result = Show-NetworkLatencyGraph -Data @(10, 20, 30, 40) -GraphType 'Sparkline' -ShowStats -NoColor

            $result | Should-NotMatchString ([Regex]::Escape($script:EscapeCharacter))
        }

        It 'preserves readable graph text after ANSI sequences are removed' {
            $result = Show-NetworkLatencyGraph -Data @(10, 20, 30, 40) -GraphType 'Sparkline' -ShowStats
            $plainText = [Regex]::Replace($result, $script:AnsiPattern, '')

            $plainText | Should-MatchString 'min:'
            $plainText | Should-MatchString 'max:'
            $plainText | Should-MatchString 'avg:'
            $plainText | Should-MatchString 'jitter:'
        }
    }
}
