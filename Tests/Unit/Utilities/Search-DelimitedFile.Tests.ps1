#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Search-DelimitedFile.
#>

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Utilities/Search-DelimitedFile.ps1"

    function Initialize-DelimitedTestFile
    {
        param(
            [Parameter(Mandatory)]
            [String]$Name,

            [Parameter(Mandatory)]
            [String]$Content
        )

        $path = Join-Path -Path $TestDrive -ChildPath $Name
        Set-Content -LiteralPath $path -Value $Content -Encoding UTF8
        return $path
    }

    $script:csvPath = Initialize-DelimitedTestFile -Name 'people.csv' -Content @'
Name,City,Status,Note
Alice,Boston,Active,a+b
Bob,Seattle,Pending,plain
Carol,Boston,Inactive,A+B
'@

    $script:archivePath = Initialize-DelimitedTestFile -Name 'people-archive.csv' -Content @'
Name,City,Status,Note
Dave,Denver,Active,archived
'@
}

Describe 'Search-DelimitedFile' {
    Context 'Parameter metadata' {
        It 'Declares Path and Criteria as mandatory parameters' {
            $command = Get-Command -Name Search-DelimitedFile

            $command.Parameters.Path.Attributes.Mandatory | Should -Contain $true
            $command.Parameters.Criteria.Attributes.Mandatory | Should -Contain $true
        }

        It 'Accepts Path from the pipeline and by property name' {
            $pathParameter = (Get-Command -Name Search-DelimitedFile).Parameters.Path

            $pathParameter.Attributes.ValueFromPipeline | Should -Contain $true
            $pathParameter.Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            $pathParameter.Aliases | Should -Contain 'FullName'
        }

        It 'Declares object output' {
            (Get-Command -Name Search-DelimitedFile).OutputType.Name | Should -Contain 'System.Management.Automation.PSObject'
        }
    }

    Context 'CSV matching with headers' {
        It 'Requires every criterion to match the same row by default' {
            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{
                    City = '^Boston$'
                    Status = '^Active$'
                })

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'Alice'
        }

        It 'matches regular expressions case-insensitively by default' {
            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = '^alice$' })

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'Alice'
        }

        It 'supports case-sensitive regular expressions' {
            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = '^alice$' } -CaseSensitive)

            $result.Count | Should -Be 0
        }

        It 'treats patterns as literal substrings with Literal' {
            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{ Note = 'a+b' } -Literal)

            $result.Count | Should -Be 2
        }

        It 'supports exact literal matching' {
            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{ Status = 'Active' } -Literal -Exact)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'Alice'
        }

        It 'supports alternative patterns for one column' {
            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{
                    Status = @('^Active$', '^Pending$')
                })

            $result.Count | Should -Be 2
            $result.Name | Should -Contain 'Alice'
            $result.Name | Should -Contain 'Bob'
        }

        It 'returns rows matching any criterion with Any' {
            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{
                    City = '^Boston$'
                    Status = '^Pending$'
                } -Any)

            $result.Count | Should -Be 3
        }

        It 'can address a headered file by zero-based column index' {
            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{ 1 = '^Seattle$'; 2 = '^Pending$' })

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'Bob'
        }

        It 'returns only searched columns in file order' {
            $criteria = [Ordered]@{
                Status = '^Active$'
                City = '^Boston$'
            }
            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria $criteria -MatchColumnsOnly)

            $result.Count | Should -Be 1
            @($result[0].PSObject.Properties.Name) | Should -Be @('City', 'Status')
        }
    }

    Context 'Delimited formats and headers' {
        It 'infers a tab delimiter for TSV files' {
            $tsvPath = Initialize-DelimitedTestFile -Name 'events.tsv' -Content "Id`tLevel`tMessage`n1`tError`tTimed out`n2`tInfo`tStarted"

            $result = @(Search-DelimitedFile -Path $tsvPath -Criteria @{ Level = '^Error$'; Message = 'out$' })

            $result.Count | Should -Be 1
            $result[0].Id | Should -Be '1'
        }

        It 'supports an arbitrary delimiter character' {
            $pipePath = Initialize-DelimitedTestFile -Name 'items.txt' -Content "Name|State|Count`nAlice|NY|2`nBob|WA|3"

            $result = @(Search-DelimitedFile -Path $pipePath -Criteria @{ State = 'NY' } -Delimiter '|' -Literal -Exact)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'Alice'
        }

        It 'generates zero-based names for a headerless file' {
            $path = Initialize-DelimitedTestFile -Name 'headerless.psv' -Content '"Alice|A"|42|NY`nBob|35|WA'
            # Use a double-quoted replacement so the test data contains a real newline.
            (Get-Content -LiteralPath $path -Raw).Replace('`n', [Environment]::NewLine) | Set-Content -LiteralPath $path -Encoding UTF8

            $result = @(Search-DelimitedFile -Path $path -Criteria @{ 0 = '^Alice\|A$'; 2 = '^NY$' } -Delimiter '|' -NoHeader)

            $result.Count | Should -Be 1
            @($result[0].PSObject.Properties.Name) | Should -Be @('Column0', 'Column1', 'Column2')
            $result[0].Column0 | Should -Be 'Alice|A'
        }

        It 'applies custom names to a headerless file' {
            $path = Initialize-DelimitedTestFile -Name 'custom-header.txt' -Content "Alice;42;NY`nBob;35;WA"

            $result = @(Search-DelimitedFile -Path $path -Criteria @{ Name = '^Alice$'; State = '^NY$' } -Delimiter ';' -Header Name, Age, State)

            $result.Count | Should -Be 1
            $result[0].Age | Should -Be '42'
        }

        It 'preserves delimiters inside quoted fields' {
            $path = Initialize-DelimitedTestFile -Name 'quoted.csv' -Content 'Name,Note`nAlice,"one,two"'
            (Get-Content -LiteralPath $path -Raw).Replace('`n', [Environment]::NewLine) | Set-Content -LiteralPath $path -Encoding UTF8

            $result = @(Search-DelimitedFile -Path $path -Criteria @{ Note = '^one,two$' })

            $result.Count | Should -Be 1
            $result[0].Note | Should -Be 'one,two'
        }
    }

    Context 'Multiple files and source information' {
        It 'searches multiple path values' {
            $result = @(Search-DelimitedFile -Path $script:csvPath, $script:archivePath -Criteria @{ Status = '^Active$' })

            $result.Count | Should -Be 2
            $result.Name | Should -Contain 'Alice'
            $result.Name | Should -Contain 'Dave'
        }

        It 'expands wildcard paths without returning duplicate files' {
            $pattern = Join-Path -Path $TestDrive -ChildPath 'people*.csv'
            $result = @(Search-DelimitedFile -Path $pattern, $script:csvPath -Criteria @{ Status = '^Active$' })

            $result.Count | Should -Be 2
        }

        It 'accepts FileInfo objects from the pipeline' {
            $result = @(Get-Item -LiteralPath $script:archivePath | Search-DelimitedFile -Criteria @{ Status = '^Active$' })

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'Dave'
        }

        It 'adds the source file name and absolute path on request' {
            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = '^Alice$' } -IncludeFileName -IncludeFilePath -MatchColumnsOnly)

            @($result[0].PSObject.Properties.Name) | Should -Be @('FileName', 'FilePath', 'Name')
            $result[0].FileName | Should -Be 'people.csv'
            $result[0].FilePath | Should -Be $script:csvPath
        }
    }

    Context 'Validation and error handling' {
        It 'rejects empty criteria' {
            { Search-DelimitedFile -Path $script:csvPath -Criteria @{} } | Should -Throw '*at least one*'
        }

        It 'rejects invalid regular expressions' {
            { Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = '(unclosed' } } | Should -Throw '*Invalid regular expression*'
        }

        It 'requires Literal when Exact is used' {
            { Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = 'Alice' } -Exact } | Should -Throw '*requires Literal*'
        }

        It 'rejects NoHeader combined with Header' {
            { Search-DelimitedFile -Path $script:csvPath -Criteria @{ 0 = 'Alice' } -NoHeader -Header Name, City, Status, Note } | Should -Throw '*cannot be used together*'
        }

        It 'rejects unknown column names' {
            { Search-DelimitedFile -Path $script:csvPath -Criteria @{ Missing = 'value' } -ErrorAction Stop } | Should -Throw '*was not found*'
        }

        It 'rejects out-of-range column indexes' {
            { Search-DelimitedFile -Path $script:csvPath -Criteria @{ 10 = 'value' } -ErrorAction Stop } | Should -Throw '*outside the valid range*'
        }

        It 'rejects a custom header with the wrong field count' {
            $path = Initialize-DelimitedTestFile -Name 'header-count.txt' -Content 'Alice,42,NY'

            { Search-DelimitedFile -Path $path -Criteria @{ Name = 'Alice' } -Header Name, Age -ErrorAction Stop } | Should -Throw '*contains 3 fields*'
        }

        It 'rejects duplicate custom header names' {
            { Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = 'Alice' } -Header Name, Name, Status, Note } | Should -Throw '*duplicate column name*'
        }

        It 'protects source metadata from input column collisions' {
            $path = Initialize-DelimitedTestFile -Name 'filename-column.csv' -Content "FileName,Value`noriginal.csv,one"

            { Search-DelimitedFile -Path $path -Criteria @{ Value = 'one' } -IncludeFileName -ErrorAction Stop } | Should -Throw '*already contains a FileName column*'
        }

        It 'reports missing paths' {
            $missingPath = Join-Path -Path $TestDrive -ChildPath 'missing.csv'

            { Search-DelimitedFile -Path $missingPath -Criteria @{ Name = 'Alice' } -ErrorAction Stop } | Should -Throw
        }
    }
}
