# Check if the script is running with admin privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Restart the script with admin permissions
    Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
    exit
}

$TaskName = "LGHUBAutoStart"
$TaskDescription = "Autostart lghub_system_tray as admin on PC startup"
$TaskPath = "\"
$TaskExecutable = "C:\Program Files\LGHUB\system_tray.exe"

# Remove existing task if it exists
Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false

try {
    $Action = New-ScheduledTaskAction -Execute $TaskExecutable
    $Trigger = New-ScheduledTaskTrigger -AtLogon
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName -Description $TaskDescription -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -TaskPath $TaskPath
    Write-Host "Task created successfully"
}
catch {
    Write-Host "Error creating task: $_"
}
