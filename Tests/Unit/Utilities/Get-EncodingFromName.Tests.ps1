#Requires -Modules Pester

BeforeAll {
    # Suppress progress bars to prevent freezing in non-interactive environments
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Utilities/Get-EncodingFromName.ps1"
}

Describe 'Get-EncodingFromName' -Tag 'Unit' {
    It 'Returns null for Auto' {
        $result = Get-EncodingFromName -EncodingName 'Auto'
        $result | Should -BeNullOrEmpty
    }

    It 'Resolves UTF8 and UTF8BOM with correct BOM behavior' {
        $utf8 = Get-EncodingFromName -EncodingName 'UTF8'
        $utf8Bom = Get-EncodingFromName -EncodingName 'UTF8BOM'

        $utf8.CodePage | Should -Be 65001
        $utf8.GetPreamble().Length | Should -Be 0
        $utf8Bom.CodePage | Should -Be 65001
        $utf8Bom.GetPreamble().Length | Should -Be 3
    }

    It 'Resolves UTF16LE and UTF16BE' {
        $utf16Le = Get-EncodingFromName -EncodingName 'UTF16LE'
        $utf16Be = Get-EncodingFromName -EncodingName 'UTF16BE'

        $utf16Le.CodePage | Should -Be 1200
        $utf16Be.CodePage | Should -Be 1201
    }

    It 'Returns null and writes error for unsupported encoding' {
        $output = & { Get-EncodingFromName -EncodingName 'Nope' } 2>&1
        $errorRecords = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        $result = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

        $result | Should -BeNullOrEmpty
        $errorRecords | Should -Not -BeNullOrEmpty
        $errorRecords[0].ToString() | Should -Match 'Unsupported encoding'
    }
}
