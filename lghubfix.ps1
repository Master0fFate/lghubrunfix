# LGHUBFIX
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $scriptPath = $MyInvocation.MyCommand.Path
    if (!$scriptPath) { $scriptPath = $PSCommandPath }
    if ($scriptPath) {
        Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    } else {
        Write-Host "Cannot determine script path. Please run the script directly from a file."
    }
    exit
}

$TaskName = "LGHUBAutoStart"
$TaskDescription = "Autostart lghub as admin on PC startup"
$TaskPath = "\"
$TaskExecutable = "C:\Program Files\LGHUB\lghub.exe"
$UserId = "$env:USERDOMAIN\$env:USERNAME"

Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false

try {
    $Action = New-ScheduledTaskAction -Execute $TaskExecutable
    $Trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserId
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
    $Principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName `
                          -Description $TaskDescription `
                          -Action $Action `
                          -Trigger $Trigger `
                          -Settings $Settings `
                          -Principal $Principal `
                          -TaskPath $TaskPath

    Write-Host "Task created successfully"
} catch {
    Write-Host "Error creating task: $_"
}
