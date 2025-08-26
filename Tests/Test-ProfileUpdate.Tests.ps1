Describe 'Test-ProfileUpdate function' {
    BeforeAll {
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
        $funcDir = Join-Path -Path $root -ChildPath 'Functions'
        $func = Join-Path -Path $funcDir -ChildPath 'Test-ProfileUpdate.ps1'
        . $func
    }

    It 'returns a Job object when run with -Async' {
        $res = Test-ProfileUpdate -Async
        # Diagnostic: output the returned object type and some properties to aid debugging
        Write-Verbose "Returned object type: $($res.GetType().FullName)"
        Write-Verbose "Returned object: $res"

        # Accept Job or any subclass (PSRemotingJob, etc.) - assert assignability
        [System.Management.Automation.Job].IsAssignableFrom($res.GetType()) | Should -BeTrue

        # Clean up job if it exists - be defensive to avoid failing the test due to cleanup errors
        try
        {
            if ($res -and $res.Id)
            {
                Stop-Job -Id $res.Id -ErrorAction SilentlyContinue
                Remove-Job -Id $res.Id -ErrorAction SilentlyContinue
            }
        }
        catch
        {
            Write-Verbose "Cleanup failed: $($_.Exception.Message)"
        }
    }

    It 'returns $false when .disable-profile-update-check exists in profile root' {
        $tmp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try
        {
            $functionsDir = Join-Path -Path $tmp -ChildPath 'Functions'
            New-Item -ItemType Directory -Path $functionsDir -Force | Out-Null

            # Copy the Test-ProfileUpdate.ps1 into the temp Functions folder so its $PSScriptRoot resolves to our temp path
            $origRoot = Join-Path -Path $PSScriptRoot -ChildPath '..'
            $origFunctions = Join-Path -Path $origRoot -ChildPath 'Functions'
            $orig = Join-Path -Path $origFunctions -ChildPath 'Test-ProfileUpdate.ps1'
            Copy-Item -LiteralPath $orig -Destination (Join-Path $functionsDir 'Test-ProfileUpdate.ps1') -Force

            # Create the opt-out file
            New-Item -ItemType File -Path (Join-Path $tmp '.disable-profile-update-check') -Force | Out-Null

            # Dot-source the copied function so $PSScriptRoot inside the function file points to $functionsDir
            . (Join-Path $functionsDir 'Test-ProfileUpdate.ps1')

            # Run the check synchronously from within the temp profile root
            Push-Location -Path $tmp
            try
            {
                $res = Test-ProfileUpdate -ErrorAction SilentlyContinue
                $res | Should -BeFalse
            }
            finally
            {
                Pop-Location
            }
        }
        finally
        {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
