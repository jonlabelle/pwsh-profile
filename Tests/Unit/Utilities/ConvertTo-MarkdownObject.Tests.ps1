#Requires -Modules Pester

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Utilities/ConvertTo-MarkdownObject.ps1"
}

Describe 'ConvertTo-MarkdownObject' -Tag 'Unit' {
    Context 'Hashtable and object rendering' {
        It 'Converts an ordered hashtable to markdown' {
            $inputObject = [ordered]@{
                Name = 'Jon'
                Age = 42
            }

            $result = ConvertTo-MarkdownObject -InputObject $inputObject

            $result | Should -Match ([Regex]::Escape('- `Name`: `Jon`'))
            $result | Should -Match ([Regex]::Escape('- `Age`: `42`'))
        }

        It 'Converts a nested PSCustomObject and arrays' {
            $inputObject = [PSCustomObject]@{
                Name = 'Tooling'
                Tags = @('powershell', 'markdown')
                Meta = [PSCustomObject]@{
                    Enabled = $true
                    RetryCount = 3
                }
            }

            $result = ConvertTo-MarkdownObject -InputObject $inputObject

            $result | Should -Match ([Regex]::Escape('- `Name`: `Tooling`'))
            $result | Should -Match ([Regex]::Escape('- `Tags`'))
            $result | Should -Match ([Regex]::Escape('- `[0]`: `powershell`'))
            $result | Should -Match ([Regex]::Escape('- `Meta`'))
            $result | Should -Match ([Regex]::Escape('- `Enabled`: `true`'))
            $result | Should -Match ([Regex]::Escape('- `RetryCount`: `3`'))
        }
    }

    Context 'JSON parsing behavior' {
        It 'Treats JSON input as a plain string by default' {
            $json = '{"name":"Jon","age":42}'

            $result = ConvertTo-MarkdownObject -InputObject $json

            $result | Should -Match ([Regex]::Escape('- `{"name":"Jon","age":42}`'))
        }

        It 'Parses JSON strings when -ParseJsonStrings is used' {
            $json = '{"name":"Jon","roles":["admin","ops"]}'

            $result = ConvertTo-MarkdownObject -InputObject $json -ParseJsonStrings

            $result | Should -Match ([Regex]::Escape('- `name`: `Jon`'))
            $result | Should -Match ([Regex]::Escape('- `roles`'))
            $result | Should -Match ([Regex]::Escape('- `[0]`: `admin`'))
            $result | Should -Match ([Regex]::Escape('- `[1]`: `ops`'))
        }
    }

    Context 'Depth limiting and empty values' {
        It 'Stops recursion at configured depth' {
            $inputObject = [ordered]@{
                Level1 = [ordered]@{
                    Level2 = [ordered]@{
                        Level3 = 'value'
                    }
                }
            }

            $result = ConvertTo-MarkdownObject -InputObject $inputObject -Depth 2

            $result | Should -Match ([Regex]::Escape('- `Level1`'))
            $result | Should -Match ([Regex]::Escape('- `Level2`: `(max depth reached)`'))
        }

        It 'Handles null, empty arrays, and empty objects' {
            $inputObject = [ordered]@{
                EmptyArray = @()
                EmptyObject = [ordered]@{}
                Nothing = $null
            }

            $result = ConvertTo-MarkdownObject -InputObject $inputObject

            $result | Should -Match ([Regex]::Escape('- `EmptyArray`'))
            $result | Should -Match ([Regex]::Escape('- *(empty array)*'))
            $result | Should -Match ([Regex]::Escape('- `EmptyObject`'))
            $result | Should -Match ([Regex]::Escape('- *(empty object)*'))
            $result | Should -Match ([Regex]::Escape('- `Nothing`: `null`'))
        }
    }

    Context 'Pipeline support' {
        It 'Returns one markdown string per piped input object' {
            $results = @(
                [ordered]@{ First = 1 },
                [ordered]@{ Second = 2 }
            ) | ConvertTo-MarkdownObject

            @($results).Count | Should -Be 2
            $results[0] | Should -Match ([Regex]::Escape('- `First`: `1`'))
            $results[1] | Should -Match ([Regex]::Escape('- `Second`: `2`'))
        }
    }
}
