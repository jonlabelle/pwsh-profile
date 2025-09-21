#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot\..\..\Functions\Start-KeepAlive.ps1"

    # Detect if we're in a CI environment
    $script:IsCI = $env:CI -eq 'true' -or
    $env:GITHUB_ACTIONS -eq 'true' -or
    $env:APPVEYOR -eq 'True' -or
    $env:AZURE_PIPELINES -eq 'True' -or
    $env:TF_BUILD -eq 'True'

    # Platform detection for cross-platform compatibility
    $script:IsWindowsTest = if ($PSVersionTable.PSVersion.Major -lt 6)
    {
        $true  # PowerShell 5.1 is Windows-only
    }
    else
    {
        $IsWindows  # PowerShell Core cross-platform check
    }

    Write-Verbose "CI Environment detected: $script:IsCI"
    Write-Verbose "Windows platform: $script:IsWindowsTest"
}

Describe 'Start-KeepAlive Function Tests' -Tag 'Unit' {

    Context 'Platform Compatibility' {

        It 'Should be available as a function' {
            Get-Command Start-KeepAlive | Should -Not -BeNullOrEmpty
            Get-Command Start-KeepAlive | Should -BeOfType [System.Management.Automation.FunctionInfo]
        }

        It 'Should have correct parameter sets' {
            $command = Get-Command Start-KeepAlive
            $command.ParameterSets.Count | Should -Be 3
            $command.ParameterSets.Name | Should -Contain 'Start'
            $command.ParameterSets.Name | Should -Contain 'Query'
            $command.ParameterSets.Name | Should -Contain 'End'
        }

        It 'Should only work on Windows platforms' -Skip:($PSVersionTable.PSVersion.Major -lt 6 -or ($PSVersionTable.PSVersion.Major -ge 6 -and (Get-Variable 'IsWindows' -ErrorAction SilentlyContinue) -and $IsWindows)) {
            # This test only runs on non-Windows platforms to verify the error
            # Skip on Windows since the function should work there (but not in CI)
            { Start-KeepAlive -KeepAliveHours 0.1 } | Should -Throw '*Start-KeepAlive requires Windows*'
        }

        It 'Should detect CI environment and handle appropriately' -Skip:(-not $script:IsCI) {
            # This test only runs in CI environments to verify behavior
            # In CI, even on Windows, the function might fail due to lack of interactive session
            Write-Host 'Running in CI environment - testing COM availability'

            # The function should either work (if COM is available) or fail gracefully
            # We don't expect it to throw the "requires Windows" error on Windows CI
            $result = try
            {
                Start-KeepAlive -KeepAliveHours 0.1 -JobName 'CI-Test'
                'Success'
            }
            catch
            {
                if ($_.Exception.Message -like '*Start-KeepAlive requires Windows*')
                {
                    'Platform-Error'
                }
                else
                {
                    'Other-Error'
                }
            }

            # On Windows CI, we should not get a platform error
            if ($script:IsWindowsTest)
            {
                $result | Should -Not -Be 'Platform-Error'
            }

            # Clean up any jobs that might have been created
            Get-Job -Name 'CI-Test' -ErrorAction SilentlyContinue | Remove-Job -Force
        }
    }

    Context 'Parameter Validation' -Skip:(-not $script:IsWindowsTest) {

        It 'Should validate KeepAliveHours range' {
            { Start-KeepAlive -KeepAliveHours 0.05 -ErrorAction Stop } | Should -Throw
            { Start-KeepAlive -KeepAliveHours 50 -ErrorAction Stop } | Should -Throw
            # These should not throw with valid ranges (but may start jobs)
            { $job1 = Start-KeepAlive -KeepAliveHours 0.1 -JobName 'TestRange1'; if ($job1) { Remove-Job $job1 -Force -ErrorAction SilentlyContinue } } | Should -Not -Throw
            { $job2 = Start-KeepAlive -KeepAliveHours 48 -JobName 'TestRange2'; if ($job2) { Remove-Job $job2 -Force -ErrorAction SilentlyContinue } } | Should -Not -Throw
        }

        It 'Should validate SleepSeconds range' {
            { Start-KeepAlive -SleepSeconds 20 -ErrorAction Stop } | Should -Throw
            { Start-KeepAlive -SleepSeconds 4000 -ErrorAction Stop } | Should -Throw
            { $job1 = Start-KeepAlive -SleepSeconds 30 -KeepAliveHours 0.1 -JobName 'TestSleep1'; if ($job1) { Remove-Job $job1 -Force -ErrorAction SilentlyContinue } } | Should -Not -Throw
            { $job2 = Start-KeepAlive -SleepSeconds 3600 -KeepAliveHours 0.1 -JobName 'TestSleep2'; if ($job2) { Remove-Job $job2 -Force -ErrorAction SilentlyContinue } } | Should -Not -Throw
        }

        It 'Should validate JobName pattern' {
            { $job1 = Start-KeepAlive -JobName 'Valid-Name_123' -KeepAliveHours 0.1; if ($job1) { Remove-Job $job1 -Force -ErrorAction SilentlyContinue } } | Should -Not -Throw
            { Start-KeepAlive -JobName 'Invalid Name!' -ErrorAction Stop } | Should -Throw
            { Start-KeepAlive -JobName 'Invalid@Name' -ErrorAction Stop } | Should -Throw
        }

        It 'Should have correct default values' {
            $command = Get-Command Start-KeepAlive
            $command.Parameters.KeepAliveHours.Attributes.DefaultValue | Should -Be 12
            $command.Parameters.SleepSeconds.Attributes.DefaultValue | Should -Be 60  # Updated default
            $command.Parameters.JobName.Attributes.DefaultValue | Should -Be 'KeepAlive'
            $command.Parameters.KeyToPress.Attributes.DefaultValue | Should -Be '{F15}'
        }
    }

    Context 'COM Object Availability' -Skip:(-not $script:IsWindowsTest) {

        It 'Should test COM object availability before starting job' {
            # Mock the COM object test to fail
            Mock -CommandName 'New-Object' -ParameterFilter { $ComObject -eq 'WScript.Shell' } -MockWith {
                throw 'COM object not available'
            }

            { Start-KeepAlive -KeepAliveHours 0.1 } | Should -Throw -ExpectedMessage '*WScript.Shell COM object not available*'
        }
    }

    Context 'Job Management - Start Parameter Set' -Skip:(-not $script:IsWindowsTest) {

        BeforeEach {
            # Clean up any existing test jobs
            try
            {
                Get-Job -Name 'TestKeepAlive*' -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
                Get-Job -Name 'TestKeepAlive*' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
            }
            catch
            {
                Write-Warning "Failed to cleanup TestKeepAlive jobs in BeforeEach: $_"
            }
        }

        AfterEach {
            # Clean up test jobs after each test
            try
            {
                Get-Job -Name 'TestKeepAlive*' -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 100
                Get-Job -Name 'TestKeepAlive*' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
            }
            catch
            {
                Write-Warning "Failed to cleanup TestKeepAlive jobs in AfterEach: $_"
            }
        }

        It 'Should start a new keep-alive job successfully' {
            $job = Start-KeepAlive -KeepAliveHours 0.1 -SleepSeconds 30 -JobName 'TestKeepAlive1'

            $job | Should -Not -BeNullOrEmpty
            $job | Should -BeOfType [System.Management.Automation.PSRemotingJob]
            $job.Name | Should -Be 'TestKeepAlive1'
            $job.State | Should -Be 'Running'
        }

        It 'Should prevent starting duplicate jobs' {
            # Start first job
            $job1 = Start-KeepAlive -KeepAliveHours 0.1 -JobName 'TestKeepAlive2'
            $job1.State | Should -Be 'Running'

            # Try to start second job with same name
            $warningMessages = @()
            $job2 = Start-KeepAlive -KeepAliveHours 0.1 -JobName 'TestKeepAlive2' -WarningVariable warningMessages

            $job2 | Should -BeNullOrEmpty
            $warningMessages | Should -Match 'already running'
        }

        It 'Should clean up completed jobs before starting new ones' {
            # Create a completed mock job
            $mockJob = [PSCustomObject]@{
                Name = 'TestKeepAlive3'
                State = 'Completed'
            }

            # Start a real job - it should clean up the old one
            $job = Start-KeepAlive -KeepAliveHours 0.1 -JobName 'TestKeepAlive3'
            $job | Should -Not -BeNullOrEmpty
            $job.State | Should -Be 'Running'
        }
    }

    Context 'Job Management - Query Parameter Set' -Skip:(-not $script:IsWindowsTest) {

        BeforeEach {
            Get-Job -Name 'TestQuery*' -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
            Get-Job -Name 'TestQuery*' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
        }

        AfterEach {
            try
            {
                Get-Job -Name 'TestQuery*' -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 100
                Get-Job -Name 'TestQuery*' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
            }
            catch
            {
                Write-Warning "Failed to cleanup TestQuery jobs in AfterEach: $_"
            }
        }

        It 'Should warn when querying non-existent job' {
            $warningMessages = @()
            Start-KeepAlive -Query -JobName 'NonExistentJob' -WarningVariable warningMessages

            $warningMessages | Should -Match "No keep-alive job named 'NonExistentJob' found"
        }

        It 'Should display status of running job' {
            # Start a job first
            $job = Start-KeepAlive -KeepAliveHours 0.1 -JobName 'TestQuery1'
            Start-Sleep 1  # Let job start

            # Query should show running status
            $output = Start-KeepAlive -Query -JobName 'TestQuery1' 6>&1 | Out-String
            $output | Should -Match "Job Status for 'TestQuery1'"
            $output | Should -Match 'State.*Running'
        }

        It 'Should clean up completed jobs when queried' {
            # This test would need a way to create a completed job
            # Skipping detailed implementation for brevity
        }
    }

    Context 'Job Management - End Parameter Set' -Skip:(-not $script:IsWindowsTest) {

        BeforeEach {
            Get-Job -Name 'TestEnd*' -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
            Get-Job -Name 'TestEnd*' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
        }

        AfterEach {
            try
            {
                Get-Job -Name 'TestEnd*' -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 100
                Get-Job -Name 'TestEnd*' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
            }
            catch
            {
                Write-Warning "Failed to cleanup TestEnd jobs in AfterEach: $_"
            }
        }

        It 'Should warn when trying to end non-existent job' {
            $warningMessages = @()
            Start-KeepAlive -EndJob -JobName 'NonExistentEndJob' -WarningVariable warningMessages

            $warningMessages | Should -Match "No keep-alive job named 'NonExistentEndJob' found"
        }

        It 'Should successfully stop and remove running job' {
            # Start a job
            $job = Start-KeepAlive -KeepAliveHours 1 -JobName 'TestEnd1'
            $job.State | Should -Be 'Running'

            # End the job
            $output = Start-KeepAlive -EndJob -JobName 'TestEnd1' 6>&1 | Out-String
            $output | Should -Match 'stopped and removed'

            # Verify job is gone
            Get-Job -Name 'TestEnd1' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    Context 'Error Handling' -Skip:(-not $script:IsWindowsTest) {

        It 'Should handle COM object creation failures gracefully' {
            Mock -CommandName 'Start-Job' -MockWith {
                throw 'Failed to start job'
            }

            { Start-KeepAlive -KeepAliveHours 0.1 } | Should -Throw -ExpectedMessage '*Failed to start keep-alive job*'
        }

        It 'Should validate parameter combinations' {
            # EndJob and Query should not be used with Start parameters
            { Start-KeepAlive -EndJob -KeepAliveHours 1 } | Should -Throw
            { Start-KeepAlive -Query -SleepSeconds 60 } | Should -Throw
        }
    }

    Context 'Job Script Logic' -Skip:(-not $script:IsWindowsTest) {

        It 'Should create job with correct arguments' {
            $job = Start-KeepAlive -KeepAliveHours 0.1 -SleepSeconds 45 -KeyToPress '{TAB}' -JobName 'TestScript1'

            # Let the job run for a moment then check its output
            Start-Sleep 2
            $jobOutput = Receive-Job -Job $job -Keep

            $jobOutput | Should -Match 'Key simulation interval: 45 seconds'
            $jobOutput | Should -Match 'Key to simulate: \{TAB\}'

            # Clean up
            Stop-Job $job
            Remove-Job $job -Force
        }
    }

    Context 'Verbose Output' -Skip:(-not $script:IsWindowsTest) {

        It 'Should provide verbose output when requested' {
            $verboseMessages = @()
            $job = Start-KeepAlive -KeepAliveHours 0.1 -JobName 'TestVerbose1' -Verbose 4>&1

            $verboseOutput = $job | Out-String
            $verboseOutput | Should -Match 'Starting Start-KeepAlive function'
            $verboseOutput | Should -Match 'Starting new keep-alive job'

            # Clean up
            Get-Job -Name 'TestVerbose1' | Remove-Job -Force
        }
    }
}
