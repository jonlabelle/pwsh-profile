#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../../Functions/SystemAdministration/Private/GetPlatformPackagePickerSelectionBar.ps1"

    $script:FilledChar = [String][Char]0x2588
    $script:EmptyChar = [String][Char]0x2591
}

Describe 'GetPlatformPackagePickerSelectionBar' {
    It 'renders an all-empty gauge when nothing is selected' {
        $bar = GetPlatformPackagePickerSelectionBar -SelectedCount 0 -TotalCount 12 -BarWidth 16

        $bar | Should-Be "Selected [$($script:EmptyChar * 16)] 0/12"
    }

    It 'renders a full gauge when everything is selected' {
        $bar = GetPlatformPackagePickerSelectionBar -SelectedCount 12 -TotalCount 12 -BarWidth 16

        $bar | Should-Be "Selected [$($script:FilledChar * 16)] 12/12"
    }

    It 'shows at least one filled cell when the selection rounds below a cell' {
        $bar = GetPlatformPackagePickerSelectionBar -SelectedCount 1 -TotalCount 300 -BarWidth 16

        $bar | Should-Be "Selected [$($script:FilledChar)$($script:EmptyChar * 15)] 1/300"
    }

    It 'fills cells proportionally to the selected ratio' {
        $bar = GetPlatformPackagePickerSelectionBar -SelectedCount 4 -TotalCount 12 -BarWidth 16

        $bar | Should-Be "Selected [$($script:FilledChar * 5)$($script:EmptyChar * 11)] 4/12"
    }

    It 'clamps the selected count to the total' {
        $bar = GetPlatformPackagePickerSelectionBar -SelectedCount 20 -TotalCount 12 -BarWidth 16

        $bar | Should-Be "Selected [$($script:FilledChar * 16)] 12/12"
    }

    It 'handles an empty package set without error' {
        $bar = GetPlatformPackagePickerSelectionBar -SelectedCount 0 -TotalCount 0 -BarWidth 16

        $bar | Should-Be "Selected [$($script:EmptyChar * 16)] 0/0"
    }
}
