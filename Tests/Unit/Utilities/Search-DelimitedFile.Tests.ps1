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
        It 'Declares Criteria as mandatory and Path as optional' {
            $command = Get-Command -Name Search-DelimitedFile

            $command.Parameters.Path.Attributes.Mandatory | Should -Not -Contain $true
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

        It 'exposes recursive directory search and multiple filters' {
            $command = Get-Command -Name Search-DelimitedFile

            $command.Parameters.ContainsKey('Recurse') | Should -BeTrue
            $command.Parameters.Filter.ParameterType | Should -Be ([String[]])
            $command.Parameters.Filter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] } | Should -Not -BeNullOrEmpty
        }

        It 'documents the duplicate-header index workaround in command examples' {
            $examples = Get-Help -Name Search-DelimitedFile -Examples | Out-String

            $examples | Should -Match 'duplicate-headers\.tsv'
            $examples | Should -Match '\-NoHeader'
        }

        It 'exposes OutputFile as a string parameter with an OutFile alias' {
            $outputParameter = (Get-Command -Name Search-DelimitedFile).Parameters.OutputFile

            $outputParameter.ParameterType | Should -Be ([String])
            $outputParameter.Aliases | Should -Contain 'OutFile'
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

        It 'infers a tab delimiter for TSV files discovered by directory filter' {
            $directory = Join-Path -Path $TestDrive -ChildPath 'filtered-tsv'
            New-Item -ItemType Directory -Path $directory | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'connections.tsv') -Value "Connection`tName`tData`nA`tWest`t1" -Encoding UTF8

            $result = @(Search-DelimitedFile -Path $directory -Filter '*.tsv' -Criteria @{ Name = @('West') })

            $result.Count | Should -Be 1
            $result[0].Connection | Should -Be 'A'
            $result[0].Name | Should -Be 'West'
        }

        It 'infers a tab delimiter for .tab files' {
            $tabPath = Initialize-DelimitedTestFile -Name 'events.tab' -Content "Id`tLevel`tMessage`n1`tError`tTimed out`n2`tInfo`tStarted"

            $result = @(Search-DelimitedFile -Path $tabPath -Criteria @{ Level = '^Error$'; Message = 'out$' })

            $result.Count | Should -Be 1
            $result[0].Id | Should -Be '1'
        }

        It 'detects tab-delimited headers when delimiter inference would otherwise choose comma' {
            $path = Initialize-DelimitedTestFile -Name 'connections.txt' -Content "Connection`tName`tData`nA`tWest`t1"

            $result = @(Search-DelimitedFile -Path $path -Criteria @{ Name = @('West') })

            $result.Count | Should -Be 1
            $result[0].Connection | Should -Be 'A'
            $result[0].Name | Should -Be 'West'
        }

        It 'detects tab-delimited headers in TXT files discovered by wildcard path' {
            $directory = Join-Path -Path $TestDrive -ChildPath 'wildcard-txt'
            New-Item -ItemType Directory -Path $directory | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'connections.txt') -Value "Connection`tName`tData`nA`tWest`t1" -Encoding UTF8
            $pathPattern = Join-Path -Path $directory -ChildPath '*.txt'

            $result = @(Search-DelimitedFile -Path $pathPattern -Criteria @{ Name = @('West') })

            $result.Count | Should -Be 1
            $result[0].Connection | Should -Be 'A'
            $result[0].Name | Should -Be 'West'
        }

        It 'honors an explicit comma delimiter even when the first record contains tabs' {
            $path = Initialize-DelimitedTestFile -Name 'explicit-comma.tsv' -Content "Connection`tName`tData`nA`tWest`t1"

            { Search-DelimitedFile -Path $path -Delimiter ',' -Criteria @{ Name = @('West') } -ErrorAction Stop } |
            Should -Throw "*Available columns: Connection`tName`tData*"
        }

        It 'preserves empty TSV fields from adjacent and trailing tabs' {
            $tsvPath = Initialize-DelimitedTestFile -Name 'empty-fields.tsv' -Content "Name`tMiddle`tStatus`tNote`nAlice`t`tActive`t`nBob`tQ`tPending`tDone"

            $result = @(Search-DelimitedFile -Path $tsvPath -Criteria @{
                    Middle = '^$'
                    Status = '^Active$'
                    Note = '^$'
                })

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'Alice'
            $result[0].Middle | Should -Be ''
            $result[0].Note | Should -Be ''
        }

        It 'preserves tabs inside quoted TSV fields' {
            $tsvPath = Initialize-DelimitedTestFile -Name 'quoted-tab.tsv' -Content "Name`tNote`nAlice`t`"one`ttwo`""

            $result = @(Search-DelimitedFile -Path $tsvPath -Criteria @{ Note = "one`ttwo" } -Literal -Exact)

            $result.Count | Should -Be 1
            $result[0].Note | Should -Be "one`ttwo"
        }

        It 'validates criteria against header-only TSV files' {
            $tsvPath = Initialize-DelimitedTestFile -Name 'header-only.tsv' -Content "Name`tStatus"

            { Search-DelimitedFile -Path $tsvPath -Criteria @{ Missing = 'value' } -ErrorAction Stop } |
            Should -Throw "*Column 'Missing' was not found*"
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

        It 'rejects blank TSV headers with index-search guidance' {
            $path = Initialize-DelimitedTestFile -Name 'blank-headers.tsv' -Content "Name`t`tStatus`nAlice`tmiddle`tActive"
            $searchErrors = @()

            $result = @(Search-DelimitedFile -Path $path -Criteria @{ Status = 'Active' } -Literal -ErrorAction SilentlyContinue -ErrorVariable searchErrors)

            $result.Count | Should -Be 0
            $searchErrors.Count | Should -Be 1
            $searchErrors[0].ToString() | Should -Match 'empty column headers'
            $searchErrors[0].ToString() | Should -Match 'zero-based indexes: 1'
            $searchErrors[0].ToString() | Should -Match '\-NoHeader and integer Criteria keys'
        }

        It 'rejects duplicate file headers with index-search guidance' {
            $path = Initialize-DelimitedTestFile -Name 'duplicate-headers.tsv' -Content "Name`tStatus`tname`nAlice`tPassed`tAlias"
            $searchErrors = @()

            $result = @(Search-DelimitedFile -Path $path -Criteria @{ Name = 'Alice' } -Literal -ErrorAction SilentlyContinue -ErrorVariable searchErrors)

            $result.Count | Should -Be 0
            $searchErrors.Count | Should -Be 1
            $searchErrors[0].ToString() | Should -Match 'duplicate column headers'
            $searchErrors[0].ToString() | Should -Match "'name' \(zero-based indexes: 0, 2\)"
            $searchErrors[0].ToString() | Should -Match '\-NoHeader and integer Criteria keys'
            $searchErrors[0].ToString() | Should -Match 'Get-Help Search-DelimitedFile -Examples'
        }

        It 'searches a duplicate-header file by index when NoHeader is used' {
            $path = Initialize-DelimitedTestFile -Name 'duplicate-headers-index.tsv' -Content "Name`tStatus`tName`nAlice`tPassed`tAlias`nBob`tFailed`tOther"

            $result = @(Search-DelimitedFile -Path $path -Criteria @{ 0 = 'Alice'; 1 = 'Passed' } -NoHeader -Literal -Exact)

            $result.Count | Should -Be 1
            $result[0].Column0 | Should -Be 'Alice'
            $result[0].Column2 | Should -Be 'Alias'
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

        It 'searches a directory non-recursively using the default filters' {
            $directory = Join-Path -Path $TestDrive -ChildPath 'directory-default'
            $nestedDirectory = Join-Path -Path $directory -ChildPath 'nested'
            New-Item -ItemType Directory -Path $directory | Out-Null
            New-Item -ItemType Directory -Path $nestedDirectory | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'people.csv') -Value "Name,Status`nRoot,Active" -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $directory 'ignored.txt') -Value "Name,Status`nText,Active" -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $nestedDirectory 'nested.csv') -Value "Name,Status`nNested,Active" -Encoding UTF8

            $result = @(Search-DelimitedFile -Path $directory -Criteria @{ Status = '^Active$' } -IncludeFileName)

            $result.FileName | Should -Contain 'people.csv'
            $result.FileName | Should -Not -Contain 'ignored.txt'
            $result.FileName | Should -Not -Contain 'nested.csv'
        }

        It 'searches directories recursively with multiple filters' {
            $directory = Join-Path -Path $TestDrive -ChildPath 'directory-filters'
            $nestedDirectory = Join-Path -Path $directory -ChildPath 'nested'
            New-Item -ItemType Directory -Path $directory | Out-Null
            New-Item -ItemType Directory -Path $nestedDirectory | Out-Null
            Set-Content -LiteralPath (Join-Path $nestedDirectory 'first.txt') -Value "Name|Status`nText|Active" -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $nestedDirectory 'second.log') -Value "Name|Status`nLog|Active" -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $nestedDirectory 'ignored.csv') -Value "Name|Status`nCsv|Active" -Encoding UTF8

            $result = @(Search-DelimitedFile -Path $directory -Criteria @{ Status = 'Active' } -Filter '*.txt', '*.log' -Delimiter '|' -Literal -Exact -Recurse -IncludeFileName)

            $result.Count | Should -Be 2
            $result.FileName | Should -Contain 'first.txt'
            $result.FileName | Should -Contain 'second.log'
        }

        It 'excludes matching directory names during recursive searches' {
            $directory = Join-Path -Path $TestDrive -ChildPath 'directory-exclude'
            $excludedDirectory = Join-Path -Path $directory -ChildPath 'node_modules'
            $includedDirectory = Join-Path -Path $directory -ChildPath 'included'
            New-Item -ItemType Directory -Path $directory | Out-Null
            New-Item -ItemType Directory -Path $excludedDirectory | Out-Null
            New-Item -ItemType Directory -Path $includedDirectory | Out-Null
            Set-Content -LiteralPath (Join-Path $excludedDirectory 'excluded.csv') -Value "Name,Status`nExcluded,Active" -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $includedDirectory 'included.csv') -Value "Name,Status`nIncluded,Active" -Encoding UTF8

            $result = @(Search-DelimitedFile -Path $directory -Criteria @{ Name = 'Included|Excluded' } -Recurse -IncludeFileName)

            $result.FileName | Should -Contain 'included.csv'
            $result.FileName | Should -Not -Contain 'excluded.csv'
        }

        It 'does not apply Filter to explicit file paths' {
            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = '^Alice$' } -Filter '*.tsv')

            $result.Count | Should -Be 1
        }

        It 'does not return duplicates from overlapping filters' {
            $directory = Join-Path -Path $TestDrive -ChildPath 'directory-overlap'
            New-Item -ItemType Directory -Path $directory | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'people.csv') -Value "Name,Status`nAlice,Active" -Encoding UTF8

            $result = @(Search-DelimitedFile -Path $directory -Criteria @{ Name = '^Alice$' } -Filter '*.csv', 'people.csv')

            $result.Count | Should -Be 1
        }
    }

    Context 'Output file export' {
        It 'writes matching rows to CSV instead of the pipeline' {
            $outputPath = Join-Path -Path $TestDrive -ChildPath 'matches.csv'

            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{ City = '^Boston$' } -OutputFile $outputPath)

            $result.Count | Should -Be 0
            $exportedRows = @(Import-Csv -LiteralPath $outputPath)
            $exportedRows.Count | Should -Be 2
            $exportedRows.Name | Should -Contain 'Alice'
            $exportedRows.Name | Should -Contain 'Carol'
        }

        It 'writes matching rows to a JSON array' {
            $outputPath = Join-Path -Path $TestDrive -ChildPath 'matches.JSON'

            $result = @(Search-DelimitedFile -Path $script:csvPath -Criteria @{ Status = '^Active$' } -MatchColumnsOnly -IncludeFileName -OutputFile $outputPath)

            $result.Count | Should -Be 0
            $jsonText = Get-Content -LiteralPath $outputPath -Raw
            $jsonText.TrimStart() | Should -Match '^\['
            [Array]$exportedRows = $jsonText | ConvertFrom-Json
            $exportedRows.Count | Should -Be 1
            @($exportedRows[0].PSObject.Properties.Name) | Should -Be @('FileName', 'Status')
        }

        It 'aggregates results from multiple input files into one output file' {
            $outputPath = Join-Path -Path $TestDrive -ChildPath 'combined.json'

            Search-DelimitedFile -Path $script:csvPath, $script:archivePath -Criteria @{ Status = '^Active$' } -OutputFile $outputPath

            [Array]$exportedRows = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
            $exportedRows.Count | Should -Be 2
            $exportedRows.Name | Should -Contain 'Alice'
            $exportedRows.Name | Should -Contain 'Dave'
        }

        It 'writes an empty JSON array when no rows match' {
            $outputPath = Join-Path -Path $TestDrive -ChildPath 'empty.json'

            Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = '^Missing$' } -OutputFile $outputPath

            (Get-Content -LiteralPath $outputPath -Raw).Trim() | Should -Be '[]'
        }

        It 'creates an empty CSV file when no rows match' {
            $outputPath = Join-Path -Path $TestDrive -ChildPath 'empty.csv'

            Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = '^Missing$' } -OutputFile $outputPath

            Test-Path -LiteralPath $outputPath -PathType Leaf | Should -BeTrue
            (Get-Item -LiteralPath $outputPath).Length | Should -Be 0
        }

        It 'overwrites an existing output file' {
            $outputPath = Join-Path -Path $TestDrive -ChildPath 'overwrite.json'
            'old content' | Set-Content -LiteralPath $outputPath

            Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = '^Alice$' } -OutputFile $outputPath

            [Array]$exportedRows = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
            $exportedRows.Count | Should -Be 1
            $exportedRows[0].Name | Should -Be 'Alice'
        }

        It 'skips an existing output file found during directory discovery' {
            $directory = Join-Path -Path $TestDrive -ChildPath 'output-discovery'
            New-Item -ItemType Directory -Path $directory | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'input.csv') -Value "Name,Status`nAlice,Active" -Encoding UTF8
            $outputPath = Join-Path -Path $directory -ChildPath 'results.csv'
            Set-Content -LiteralPath $outputPath -Value "unrelated,columns`nold,data" -Encoding UTF8

            Search-DelimitedFile -Path $directory -Criteria @{ Status = '^Active$' } -OutputFile $outputPath

            $exportedRows = @(Import-Csv -LiteralPath $outputPath)
            $exportedRows.Count | Should -Be 1
            $exportedRows[0].Name | Should -Be 'Alice'
        }

        It 'skips an existing output file matched by an input wildcard' {
            $directory = Join-Path -Path $TestDrive -ChildPath 'output-wildcard'
            New-Item -ItemType Directory -Path $directory | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'input.csv') -Value "Name,Status`nAlice,Active" -Encoding UTF8
            $outputPath = Join-Path -Path $directory -ChildPath 'results.csv'
            Set-Content -LiteralPath $outputPath -Value "unrelated,columns`nold,data" -Encoding UTF8
            $inputPattern = Join-Path -Path $directory -ChildPath '*.csv'

            Search-DelimitedFile -Path $inputPattern -Criteria @{ Status = '^Active$' } -OutputFile $outputPath

            $exportedRows = @(Import-Csv -LiteralPath $outputPath)
            $exportedRows.Count | Should -Be 1
            $exportedRows[0].Name | Should -Be 'Alice'
        }

        It 'rejects unsupported output file extensions' {
            $outputPath = Join-Path -Path $TestDrive -ChildPath 'matches.txt'

            { Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = '^Alice$' } -OutputFile $outputPath } |
            Should -Throw '*must use a .csv or .json extension*'
        }

        It 'rejects an output path whose parent directory does not exist' {
            $outputPath = Join-Path -Path (Join-Path -Path $TestDrive -ChildPath 'missing') -ChildPath 'matches.json'

            { Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = '^Alice$' } -OutputFile $outputPath } |
            Should -Throw '*directory does not exist*'
        }

        It 'rejects using the same explicit file as input and output' {
            { Search-DelimitedFile -Path $script:csvPath -Criteria @{ Name = '^Alice$' } -OutputFile $script:csvPath } |
            Should -Throw '*cannot also be an explicit input file*'
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
