#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    $script:FunctionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../Functions/SystemAdministration/Get-SystemInfo.ps1'
    . $script:FunctionPath

    $script:DefaultSystemInfo = @(Get-SystemInfo -WarningAction SilentlyContinue)[0]
    $script:VolumeSystemInfo = @(Get-SystemInfo -AllVolumes -WarningAction SilentlyContinue)[0]
    $script:PrivateVolumeSystemInfo = @(Get-SystemInfo -AllVolumes -NoPII -WarningAction SilentlyContinue)[0]
}

Describe 'Get-SystemInfo volume details' -Tag 'Unit' {
    It 'exposes AllVolumes as a switch with the AllDrives alias' {
        $command = Get-Command -Name Get-SystemInfo
        $parameter = $command.Parameters['AllVolumes']

        $parameter | Should -Not -BeNullOrEmpty
        $parameter.ParameterType | Should-Be ([System.Management.Automation.SwitchParameter])
        $parameter.Aliases | Should-ContainCollection 'AllDrives'
    }

    It 'documents the AllVolumes usage example' {
        $examples = Get-Help -Name Get-SystemInfo -Examples | Out-String

        $examples | Should-MatchString 'Get-SystemInfo -AllVolumes'
        $examples | Should-MatchString 'Volumes \| Format-List'
    }

    It 'does not change the default result property set' {
        $script:DefaultSystemInfo | Should -Not -BeNullOrEmpty
        $script:DefaultSystemInfo.PSObject.Properties.Name | Should-NotContainCollection 'Volumes'
    }

    It 'adds a structured Volumes collection when AllVolumes is specified' {
        $script:VolumeSystemInfo | Should -Not -BeNullOrEmpty
        $script:VolumeSystemInfo.PSObject.Properties.Name | Should-ContainCollection 'Volumes'

        $volumes = @($script:VolumeSystemInfo.Volumes)
        $volumes.Count | Should-BeGreaterThan 0

        $expectedProperties = @(
            'Name'
            'MountPoint'
            'VolumeLabel'
            'FileSystem'
            'DriveType'
            'IsReady'
            'TotalSizeGB'
            'UsedSpaceGB'
            'FreeSpaceGB'
            'AvailableFreeSpaceGB'
            'UsedPercent'
            'FreePercent'
        )

        foreach ($volume in $volumes)
        {
            $volume.PSObject.TypeNames[0] | Should-Be 'SystemInfo.Volume'

            foreach ($propertyName in $expectedProperties)
            {
                $volume.PSObject.Properties.Name | Should-ContainCollection $propertyName
            }
        }
    }

    It 'reports internally consistent capacity and percentage values for ready volumes' {
        $readyVolume = @(
            $script:VolumeSystemInfo.Volumes |
                Where-Object { $_.IsReady -and $null -ne $_.TotalSizeGB -and $_.TotalSizeGB -gt 0 }
        ) | Select-Object -First 1

        $readyVolume | Should -Not -BeNullOrEmpty
        [Math]::Abs($readyVolume.TotalSizeGB - ($readyVolume.UsedSpaceGB + $readyVolume.FreeSpaceGB)) |
            Should-BeLessThanOrEqual 0.02
        [Math]::Abs(100 - ($readyVolume.UsedPercent + $readyVolume.FreePercent)) |
            Should-BeLessThanOrEqual 0.02
        $readyVolume.AvailableFreeSpaceGB | Should-BeLessThanOrEqual $readyVolume.FreeSpaceGB
    }

    It 'removes identifying volume fields when NoPII is specified' {
        $volumes = @($script:PrivateVolumeSystemInfo.Volumes)
        $volumes.Count | Should-BeGreaterThan 0

        foreach ($volume in $volumes)
        {
            $volume.PSObject.Properties.Name | Should-NotContainCollection 'Name'
            $volume.PSObject.Properties.Name | Should-NotContainCollection 'MountPoint'
            $volume.PSObject.Properties.Name | Should-NotContainCollection 'VolumeLabel'
            $volume.PSObject.Properties.Name | Should-ContainCollection 'TotalSizeGB'
            $volume.PSObject.Properties.Name | Should-ContainCollection 'UsedPercent'
        }
    }
}
