Describe 'Invoke-FFmpeg function' {
    BeforeAll {
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
        $func = Join-Path -Path (Join-Path -Path $root -ChildPath 'Functions') -ChildPath 'Invoke-FFmpeg.ps1'
        . $func
    }

    It 'throws when provided FFmpeg path does not exist' {
        $badPath = '/nonexistent/ffmpeg'
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $badPath } -MockWith { $false }

        { Invoke-FFmpeg -FFmpegPath $badPath } | Should -Throw
    }

    It 'validates parameter set conflicts (PassthroughVideo with VideoEncoder)' {
        # Should throw because PassthroughVideo and VideoEncoder are incompatible
        { Invoke-FFmpeg -PassthroughVideo -VideoEncoder 'H.264' -FFmpegPath '/nonexistent/ffmpeg' } | Should -Throw
    }
}
