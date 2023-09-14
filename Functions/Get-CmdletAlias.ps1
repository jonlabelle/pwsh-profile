function Get-CmdletAlias ($cmdletname)
{
    # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.2#add-a-function-that-lists-the-aliases-for-any-cmdlet
    Get-Alias |
    Where-Object -FilterScript {$_.Definition -like "$cmdletname"} |
    Format-Table -Property Definition, Name -AutoSize
}
