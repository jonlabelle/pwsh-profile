Describe 'New-RandomAlphaNumericString' {
    BeforeAll {
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
        $func = Join-Path -Path (Join-Path -Path $root -ChildPath 'Functions') -ChildPath 'New-RandomAlphaNumericString.ps1'
        . $func
    }

    It 'generates default length of 32' {
        $s = New-RandomAlphaNumericString
        $s | Should -BeOfType [string]
        $s.Length | Should -Be 32
    }

    It 'respects Length parameter' {
        $s = New-RandomAlphaNumericString -Length 8
        $s.Length | Should -Be 8
    }

    It 'excludes ambiguous characters when requested' {
    $s = New-RandomAlphaNumericString -Length 128 -ExcludeAmbiguous
    # Check exact characters (case-sensitive) so we don't fail on allowed case variants
    $excluded = '0','O','1','l','I'
    foreach ($c in $excluded) { $s.Contains($c) | Should -BeFalse }
    }

    It 'includes symbols when requested' {
        $s = New-RandomAlphaNumericString -Length 64 -IncludeSymbols
        $s | Should -Match '[!@#$%^&*]'
    }

    It 'Secure mode returns correct length and is reproducible type' {
        $s = New-RandomAlphaNumericString -Length 16 -Secure
        $s | Should -BeOfType [string]
        $s.Length | Should -Be 16
    }
}
