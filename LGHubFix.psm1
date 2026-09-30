Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ShortcutName = 'LGHUB Run Fix.lnk'
$script:ShortcutMarker = 'lghubrunfix: user startup v2'

function Assert-Windows {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This tool requires Windows.' }
}
function Get-Context {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    [pscustomobject]@{ Sid = $identity.User.Value; Session = (Get-Process -Id $PID).SessionId
        Elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
}
function Get-Installations {
    param([string]$InstallPath)
    $candidates = @()
    if ($InstallPath) { $candidates = @($InstallPath) }
    else {
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
            if ($root) { $candidates += Join-Path $root 'LGHUB' }
        }
        foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
            Get-ItemProperty $key -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.PSObject.Properties['DisplayName'] -and $_.DisplayName -match 'Logitech G HUB' -and
                    $_.PSObject.Properties['InstallLocation'] -and $_.InstallLocation) { $candidates += $_.InstallLocation }
            }
        }
    }
    $seen = @{}
    foreach ($candidate in $candidates) {
        $exe = Join-Path $candidate 'lghub.exe'
        if (Test-Path -LiteralPath $exe -PathType Leaf) {
            $file = Get-Item -LiteralPath $exe
            if (-not $seen.ContainsKey($file.FullName)) {
                $seen[$file.FullName] = $true
                [pscustomobject]@{ Path = $file.DirectoryName; Executable = $file.FullName; Version = $file.VersionInfo.FileVersion }
            }
        }
    }
}
function Select-Installation {
    param([object[]]$Installations)
    if ($Installations.Count -eq 0) { throw 'G HUB was not found. Install it first or specify -InstallPath with its installation folder.' }
    if ($Installations.Count -ne 1) { throw 'Multiple G HUB installations found. Choose one with -InstallPath.' }
    $Installations[0]
}
function Test-OwnedProcess {
    param($Process, $Context, [string]$Directory, [string]$OwnerSid)
    if ($Process.SessionId -ne $Context.Session -or $OwnerSid -ne $Context.Sid -or -not $Process.ExecutablePath) { return $false }
    if ($Process.Name -notin @('lghub_agent.exe', 'lghub.exe')) { return $false }
    return [string]::Equals($Process.ExecutablePath, (Join-Path $Directory $Process.Name), [StringComparison]::OrdinalIgnoreCase)
}
function Get-OwnedProcesses {
    param($Context, [string]$Directory)
    foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name='lghub.exe' OR Name='lghub_agent.exe'")) {
        try {
            $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
            if ($owner.ReturnValue -eq 0 -and (Test-OwnedProcess $process $Context $Directory $owner.Sid)) { $process }
        } catch { Write-Verbose "Could not verify process $($process.ProcessId); leaving it untouched." }
    }
}
function Stop-OwnedProcess {
    param($Process)
    # Recheck identity after discovery, reducing PID reuse risk. Never kill by image name.
    # CIM timestamps have microsecond precision; .NET timestamps can have finer precision.
    $live = Get-Process -Id $Process.ProcessId -ErrorAction SilentlyContinue
    if (-not $live) { return }
    if (-not [string]::Equals($live.Path, $Process.ExecutablePath, [StringComparison]::OrdinalIgnoreCase) -or
        [math]::Abs(($live.StartTime.ToUniversalTime() - $Process.CreationDate.ToUniversalTime()).Ticks) -gt 10) {
        throw "Process $($Process.ProcessId) changed identity; restart cancelled."
    }
    Stop-Process -InputObject $live -ErrorAction Stop
}
function Start-Hub {
    param($Installation)
    Start-Process -FilePath $Installation.Executable -WorkingDirectory $Installation.Path -ErrorAction Stop | Out-Null
}
function Wait-Hub {
    param($Context, $Installation, [int]$TimeoutSeconds)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $stable = 0
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $names = @(Get-OwnedProcesses $Context $Installation.Path | ForEach-Object { $_.Name })
        if ('lghub.exe' -in $names -and 'lghub_agent.exe' -in $names) { $stable++ } else { $stable = 0 }
        if ($stable -ge 3) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}
function Get-ShortcutPath { Join-Path ([Environment]::GetFolderPath('Startup')) $script:ShortcutName }
function Read-Shortcut {
    param([string]$Path)
    $shell = New-Object -ComObject WScript.Shell
    try { $shell.CreateShortcut($Path) } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
}
function Release-Shortcut {
    param($Shortcut)
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Shortcut)
}
function Set-HubStartup {
    param($Installation, [switch]$Remove)
    $path = Get-ShortcutPath
    if (Test-Path -LiteralPath $path) {
        $existing = Read-Shortcut $path
        try {
            if ($existing.Description -ne $script:ShortcutMarker) { throw "Refusing to replace or remove an unowned shortcut: $path" }
        } finally { Release-Shortcut $existing }
    } elseif ($Remove) { return 'NotInstalled' }
    if ($Remove) { Remove-Item -LiteralPath $path -ErrorAction Stop; return 'Removed' }
    $shortcut = Read-Shortcut $path
    try {
        $shortcut.TargetPath = $Installation.Executable
        $shortcut.WorkingDirectory = $Installation.Path
        $shortcut.Arguments = ''
        $shortcut.Description = $script:ShortcutMarker
        $shortcut.WindowStyle = 1
        $shortcut.Save()
    } finally { Release-Shortcut $shortcut }
    if (-not (Test-Path -LiteralPath $path)) { throw 'Windows did not save the startup shortcut.' }
    return 'Installed'
}
function Get-Audit {
    param($Context, [object[]]$Installations)
    $service = Get-Service -Name LGHUBUpdaterService -ErrorAction SilentlyContinue
    $legacy = @()
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $legacy = @(Get-ScheduledTask -TaskName LGHUBAutoStart -ErrorAction SilentlyContinue)
    }
    [pscustomobject]@{
        Action = 'Diagnose'; Installations = $Installations; Elevated = $Context.Elevated
        UpdaterService = $(if ($service) { [string]$service.Status } else { 'NotFound' })
        LegacyTaskDetected = ($legacy.Count -gt 0); StartupShortcutPresent = (Test-Path -LiteralPath (Get-ShortcutPath))
        Processes = @($Installations | ForEach-Object { Get-OwnedProcesses $Context $_.Path } |
            Select-Object Name, ProcessId, ExecutablePath)
        Health = 'NotAssessed'; Note = 'Process presence does not prove that the UI, profiles or devices work.'
    }
}
function Invoke-LGHubFix {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [ValidateSet('Diagnose','Restart','InstallStartup','RemoveStartup')][string]$Action = 'Diagnose',
        [string]$InstallPath,
        [ValidateRange(5,300)][int]$TimeoutSeconds = 30
    )
    Assert-Windows
    $context = Get-Context
    $installations = @(Get-Installations $InstallPath)
    if ($Action -eq 'Diagnose') { return Get-Audit $context $installations }
    # Elevated G HUB is not a general startup repair. Use the logged-in user's ordinary token.
    if ($context.Elevated) { throw 'Run this action in a normal PowerShell window, not as administrator.' }
    if ($Action -eq 'RemoveStartup') {
        if ($PSCmdlet.ShouldProcess((Get-ShortcutPath), 'Remove this tool''s startup shortcut')) {
            return [pscustomobject]@{ Action = $Action; Result = (Set-HubStartup -Remove) }
        }
        return
    }
    $installation = Select-Installation $installations
    if ($Action -eq 'InstallStartup') {
        Write-Warning 'Disable duplicate G HUB startup entries yourself first. This adds a normal per-user logon shortcut, not an elevated task.'
        if ($PSCmdlet.ShouldProcess((Get-ShortcutPath), "Create startup shortcut for $($installation.Executable)")) {
            return [pscustomobject]@{ Action = $Action; Result = (Set-HubStartup $installation) }
        }
        return
    }
    Write-Warning 'Restarting G HUB interrupts profiles/macros. Save changes and quit its tray icon first. Updater service will be left untouched.'
    if (-not $PSCmdlet.ShouldProcess($installation.Path, 'Stop this user/session''s G HUB agent and UI, then relaunch')) { return }
    foreach ($name in @('lghub_agent.exe','lghub.exe')) {
        foreach ($process in @(Get-OwnedProcesses $context $installation.Path | Where-Object { $_.Name -eq $name })) {
            Stop-OwnedProcess $process
        }
    }
    $stopTimer = [Diagnostics.Stopwatch]::StartNew()
    while (@(Get-OwnedProcesses $context $installation.Path).Count -gt 0) {
        if ($stopTimer.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw 'G HUB processes did not stop (or are respawning). Close duplicate startup tools and retry.' }
        Start-Sleep -Milliseconds 200
    }
    Start-Hub $installation
    if (-not (Wait-Hub $context $installation $TimeoutSeconds)) {
        throw 'G HUB UI and agent were not both observed running stably before timeout. Run Diagnose and consult the README; no service or data was changed.'
    }
    [pscustomobject]@{ Action = $Action; Result = 'ProcessesObserved'; Version = $installation.Version
        Note = 'UI and agent observed in 3 consecutive polls. Open G HUB and check loading, devices and profiles yourself.' }
}
Export-ModuleMember -Function Invoke-LGHubFix
