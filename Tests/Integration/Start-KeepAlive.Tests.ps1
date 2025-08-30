#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    # Import the function under test
    . "$PSScriptRoot\..\..\Functions\Start-KeepAlive.ps1"

    # Detect if we're in a CI environment, we won't run integration tests here
    $script:IsCI = $env:CI -eq 'true' -or $env:GITHUB_ACTIONS

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

Describe 'Start-KeepAlive Integration Tests' -Tag 'Integration' -Skip:($script:IsCI -or -not $script:IsWindowsTest) {

    BeforeAll {
        # Clean up any existing integration test jobs
        Get-Job -Name 'IntegrationTest*' -ErrorAction SilentlyContinue | Remove-Job -Force
    }

    AfterAll {
        # Clean up all integration test jobs
        Get-Job -Name 'IntegrationTest*' -ErrorAction SilentlyContinue | Remove-Job -Force
    }

    Context 'Real Keep-Alive Functionality' {

        It 'Should actually send keystrokes and prevent system timeout' {
            # Start a very short keep-alive job
            $job = Start-KeepAlive -KeepAliveHours 0.02 -SleepSeconds 30 -JobName 'IntegrationTest1' -KeyToPress '{F15}'

            try
            {
                $job | Should -Not -BeNullOrEmpty
                $job.State | Should -Be 'Running'

                # Wait a bit and check that the job is actually doing work
                Start-Sleep 35  # Wait longer than one sleep cycle

                $job = Get-Job -Name 'IntegrationTest1'
                $jobOutput = Receive-Job -Job $job -Keep

                # Should have some output indicating keystrokes were sent
                $jobOutput | Should -Match 'started at'
                $jobOutput | Should -Match 'Key simulation interval: 30 seconds'

                # Wait for job to complete
                $timeout = 120  # 2 minutes max wait
                $elapsed = 0
                while ($job.State -eq 'Running' -and $elapsed -lt $timeout)
                {
                    Start-Sleep 5
                    $elapsed += 5
                    $job = Get-Job -Name 'IntegrationTest1'
                }

                # Job should complete naturally
                $job.State | Should -BeIn @('Completed', 'Failed')

                if ($job.State -eq 'Completed')
                {
                    $finalOutput = Receive-Job -Job $job
                    $finalOutput | Should -Match 'completed successfully'
                    $finalOutput | Should -Match 'Total keystrokes sent'
                }

            }
            finally
            {
                # Ensure cleanup
                Get-Job -Name 'IntegrationTest1' -ErrorAction SilentlyContinue | Remove-Job -Force
            }
        }

        It 'Should handle COM object interactions correctly' {
            # Test that COM objects are properly created and cleaned up
            $job = Start-KeepAlive -KeepAliveHours 0.01 -SleepSeconds 30 -JobName 'IntegrationTest2'

            try
            {
                Start-Sleep 2  # Let it run briefly

                $job = Get-Job -Name 'IntegrationTest2'
                $job.State | Should -Be 'Running'

                # Check that we can still create COM objects in the main session
                # (ensures we're not locking up COM)
                $testCOM = New-Object -ComObject WScript.Shell
                $testCOM | Should -Not -BeNullOrEmpty
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($testCOM) | Out-Null

            }
            finally
            {
                Get-Job -Name 'IntegrationTest2' -ErrorAction SilentlyContinue | Remove-Job -Force
            }
        }

        It 'Should properly handle job lifecycle - start, query, end' {
            # Test the complete lifecycle

            # 1. Start job
            $job = Start-KeepAlive -KeepAliveHours 1 -SleepSeconds 60 -JobName 'IntegrationTest3'
            $job.State | Should -Be 'Running'

            Start-Sleep 2  # Let it initialize

            # 2. Query job status
            $queryOutput = Start-KeepAlive -Query -JobName 'IntegrationTest3' 6>&1 | Out-String
            $queryOutput | Should -Match "Job Status for 'IntegrationTest3'"
            $queryOutput | Should -Match 'State.*Running'

            # 3. End job
            $endOutput = Start-KeepAlive -EndJob -JobName 'IntegrationTest3' 6>&1 | Out-String
            $endOutput | Should -Match 'stopped and removed'

            # 4. Verify job is gone
            Get-Job -Name 'IntegrationTest3' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }

        It 'Should prevent system sleep during operation' {
            # This is a longer test to actually verify sleep prevention
            # Note: This test takes about 2 minutes to run

            Write-Host 'Running sleep prevention test (this takes ~2 minutes)...' -ForegroundColor Yellow

            $job = Start-KeepAlive -KeepAliveHours 0.05 -SleepSeconds 30 -JobName 'IntegrationTest4' -KeyToPress '{F15}'

            try
            {
                # Monitor the job for 90 seconds to ensure it's actively working
                $monitorTime = 90
                $checkInterval = 15
                $checks = $monitorTime / $checkInterval

                for ($i = 1; $i -le $checks; $i++)
                {
                    Start-Sleep $checkInterval

                    $currentJob = Get-Job -Name 'IntegrationTest4'
                    $currentJob.State | Should -Be 'Running' -Because "Job should still be running at check $i"

                    $output = Receive-Job -Job $currentJob -Keep
                    $output | Should -Not -BeNullOrEmpty -Because "Job should be producing output at check $i"

                    Write-Host "Check $i of $checks`: Job still running, keystrokes being sent" -ForegroundColor Green
                }

                # Let job complete naturally
                do
                {
                    Start-Sleep 5
                    $job = Get-Job -Name 'IntegrationTest4'
                } while ($job.State -eq 'Running')

                $finalOutput = Receive-Job -Job $job
                $finalOutput | Should -Match 'completed successfully'

                # Verify multiple keystrokes were sent
                if ($finalOutput -match 'Total keystrokes sent: (\d+)')
                {
                    $keystrokeCount = [int]$matches[1]
                    $keystrokeCount | Should -BeGreaterThan 2 -Because 'Should have sent multiple keystrokes during the test period'
                }

            }
            finally
            {
                Get-Job -Name 'IntegrationTest4' -ErrorAction SilentlyContinue | Remove-Job -Force
            }
        }
    }

    Context 'Error Recovery and Edge Cases' {

        It 'Should handle system interruption gracefully' {
            $job = Start-KeepAlive -KeepAliveHours 0.1 -JobName 'IntegrationTest5'

            Start-Sleep 2  # Let it start

            # Simulate interruption by stopping the job externally
            Stop-Job -Name 'IntegrationTest5'

            # Function should handle this gracefully when queried
            $queryOutput = Start-KeepAlive -Query -JobName 'IntegrationTest5' 3>&1 2>&1 | Out-String
            $queryOutput | Should -Match 'IntegrationTest5'

            # Verify job state after interruption
            $interruptedJob = Get-Job -Name 'IntegrationTest5' -ErrorAction SilentlyContinue
            if ($interruptedJob)
            {
                $interruptedJob.State | Should -BeIn @('Stopped', 'Failed', 'Completed')
            }

            # Clean up
            Get-Job -Name 'IntegrationTest5' -ErrorAction SilentlyContinue | Remove-Job -Force
        }

        It 'Should handle multiple concurrent jobs with different names' {
            # Test running multiple jobs simultaneously
            $job1 = Start-KeepAlive -KeepAliveHours 0.02 -JobName 'IntegrationTestConcurrent1' -SleepSeconds 30
            $job2 = Start-KeepAlive -KeepAliveHours 0.02 -JobName 'IntegrationTestConcurrent2' -SleepSeconds 45

            try
            {
                Start-Sleep 2

                $job1.State | Should -Be 'Running'
                $job2.State | Should -Be 'Running'

                # Both jobs should be working independently
                $output1 = Receive-Job -Name 'IntegrationTestConcurrent1' -Keep
                $output2 = Receive-Job -Name 'IntegrationTestConcurrent2' -Keep

                $output1 | Should -Match 'Key simulation interval: 30 seconds'
                $output2 | Should -Match 'Key simulation interval: 45 seconds'

            }
            finally
            {
                Get-Job -Name 'IntegrationTestConcurrent*' -ErrorAction SilentlyContinue | Remove-Job -Force
            }
        }
    }
}
