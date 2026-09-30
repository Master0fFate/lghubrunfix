# Dependency-free behavioral tests. No real G HUB/system operations are performed.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../LGHubFix.psm1') -Force
$module = Get-Module LGHubFix
& $module {
    $script:passed = 0
    function Assert($Condition, [string]$Message) {
        if (-not $Condition) { throw "FAIL: $Message" }
        $script:passed++; Write-Host "PASS: $Message"
    }
    function Assert-Throws([scriptblock]$Code, [string]$Message) {
        $failed = $false; try { & $Code } catch { $failed = $true }; Assert $failed $Message
    }
    $context = [pscustomobject]@{ Sid = 'S-1-test'; Session = 2; Elevated = $false }
    $directory = Join-Path ([IO.Path]::GetTempPath()) 'LG HUB Test'
    $process = [pscustomobject]@{ Name = 'lghub.exe'; SessionId = 2; ExecutablePath = (Join-Path $directory 'lghub.exe') }
    Assert (Test-OwnedProcess $process $context $directory 'S-1-test') 'Exact user, session and installation accepted'
    Assert (-not (Test-OwnedProcess $process $context $directory 'S-1-other')) 'Other users excluded'
    $process.SessionId = 3
    Assert (-not (Test-OwnedProcess $process $context $directory 'S-1-test')) 'Other sessions excluded'
    $process.SessionId = 2; $process.ExecutablePath = Join-Path $directory 'other/lghub.exe'
    Assert (-not (Test-OwnedProcess $process $context $directory 'S-1-test')) 'Same-name executable in another directory excluded'
    $process.ExecutablePath = $null
    Assert (-not (Test-OwnedProcess $process $context $directory 'S-1-test')) 'Unknown executable path excluded'
    $process.Name = 'lghub_updater.exe'; $process.ExecutablePath = Join-Path $directory $process.Name
    Assert (-not (Test-OwnedProcess $process $context $directory 'S-1-test')) 'Updater never targeted'
    Assert-Throws { Select-Installation @() } 'Missing installation rejected'
    Assert-Throws { Select-Installation @(1,2) } 'Ambiguous installation rejected'
    Assert ((Select-Installation @('only')) -eq 'only') 'Single installation selected'
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Path $testRoot | Out-Null
        New-Item -ItemType File -Path (Join-Path $testRoot 'lghub.exe') | Out-Null
        Assert (@(Get-Installations $testRoot).Count -eq 1) 'Explicit path discovery works with literal paths'
        Assert (@(Get-Installations (Join-Path $testRoot 'missing')).Count -eq 0) 'Nonexistent explicit path returns no installation'
    } finally { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    # Test shortcut ownership and persistence through a fake COM/file boundary.
    $script:exists = $false
    $script:shortcut = [pscustomobject]@{ TargetPath=''; WorkingDirectory=''; Arguments='old'; Description=''; WindowStyle=0 }
    $script:shortcut | Add-Member ScriptMethod Save { $script:exists = $true }
    function Get-ShortcutPath { 'fake-startup.lnk' }
    function Read-Shortcut { $script:shortcut }
    function Release-Shortcut {}
    function Test-Path { param([string]$LiteralPath); if ($LiteralPath -eq 'fake-startup.lnk') { $script:exists } else { Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath } }
    function Remove-Item { param([string]$LiteralPath); if ($LiteralPath -ne 'fake-startup.lnk') { throw 'Unexpected removal' }; $script:exists = $false }
    $install = [pscustomobject]@{ Executable='C:\Program Files\LGHUB\lghub.exe'; Path='C:\Program Files\LGHUB' }
    Assert ((Set-HubStartup $install) -eq 'Installed') 'Startup shortcut saved'
    Assert ($script:shortcut.TargetPath -eq $install.Executable -and $script:shortcut.Arguments -eq '') 'Shortcut points directly to app with no shell arguments'
    Assert ((Set-HubStartup $install) -eq 'Installed') 'Repeated startup installation is idempotent'
    $script:shortcut.Description = 'foreign'
    Assert-Throws { Set-HubStartup $install } 'Foreign shortcut cannot be overwritten'
    Assert-Throws { Set-HubStartup -Remove } 'Foreign shortcut cannot be removed'
    $script:shortcut.Description = $script:ShortcutMarker
    Assert ((Set-HubStartup -Remove) -eq 'Removed') 'Owned shortcut removal succeeds'
    Assert ((Set-HubStartup -Remove) -eq 'NotInstalled') 'Repeated removal is harmless'
    # Exercise process identity recheck without ever stopping a real process.
    $script:stopped = $false
    $created = [datetime]::UtcNow
    $script:live = [pscustomobject]@{ Path = 'expected'; StartTime = $created }
    function Get-Process { $script:live }
    function Stop-Process { $script:stopped = $true }
    $snapshot = [pscustomobject]@{ ProcessId = 123; ExecutablePath = 'expected'; CreationDate = $created }
    Stop-OwnedProcess $snapshot
    Assert $script:stopped 'Verified process object is passed to termination boundary'
    $script:stopped = $false; $script:live.StartTime = $created.AddSeconds(1)
    Assert-Throws { Stop-OwnedProcess $snapshot } 'Reused process ID rejected by creation time'
    Assert (-not $script:stopped) 'Changed process is never stopped'
    $script:live = $null
    Stop-OwnedProcess $snapshot
    Assert (-not $script:stopped) 'Already exited process is harmless'
    $script:healthPolls = 0
    function Get-OwnedProcesses {
        $script:healthPolls++
        if ($script:healthPolls -ne 2) { @([pscustomobject]@{Name='lghub.exe'},[pscustomobject]@{Name='lghub_agent.exe'}) }
    }
    Assert (Wait-Hub $context ([pscustomobject]@{Path=$directory}) 10) 'Health observation tolerates an interrupted startup'
    Assert ($script:healthPolls -eq 5) 'Health requires three consecutive successful polls'
    function Get-OwnedProcesses { @([pscustomobject]@{Name='lghub.exe'}) }
    Assert (-not (Wait-Hub $context ([pscustomobject]@{Path=$directory}) 1)) 'UI without agent times out'
    # Mock all platform and side-effect boundaries before invoking the orchestration.
    function Assert-Windows {}
    $script:context = $context
    $script:installation = [pscustomobject]@{ Path = $directory; Executable = (Join-Path $directory 'lghub.exe'); Version = 'test' }
    $script:events = [Collections.Generic.List[string]]::new()
    function Get-Context { $script:context }
    function Get-Installations { $script:installation }
    function Get-Audit { param($Context,$Installations); [pscustomobject]@{ Action = 'Diagnose'; Count = $Installations.Count } }
    function Get-ShortcutPath { 'fake-startup.lnk' }
    function Set-HubStartup { param($Installation,[switch]$Remove); $script:events.Add("startup:$Remove"); 'ok' }
    function Get-OwnedProcesses { @() }
    function Stop-OwnedProcess { param($Process); $script:events.Add("stop:$($Process.Name)") }
    function Start-Hub { $script:events.Add('start') }
    function Wait-Hub { $true }
    Assert ((Invoke-LGHubFix).Action -eq 'Diagnose') 'No arguments defaults to read-only diagnosis'
    foreach ($action in @('Restart','InstallStartup','RemoveStartup')) { Invoke-LGHubFix -Action $action -WhatIf }
    Assert ($script:events.Count -eq 0) 'WhatIf performs no restart or startup mutations'
    $script:context.Elevated = $true
    Assert-Throws { Invoke-LGHubFix -Action Restart } 'Elevated restart rejected'
    $script:context.Elevated = $false
    Invoke-LGHubFix -Action InstallStartup -Confirm:$false | Out-Null
    Invoke-LGHubFix -Action RemoveStartup -Confirm:$false | Out-Null
    Assert (($script:events -join ',') -eq 'startup:False,startup:True') 'Install/remove are explicit and reversible actions'
    $script:events.Clear()
    $script:queries = 0
    function Get-OwnedProcesses {
        $script:queries++
        if ($script:queries -le 2) { @([pscustomobject]@{Name='lghub.exe'},[pscustomobject]@{Name='lghub_agent.exe'}) }
    }
    $result = Invoke-LGHubFix -Action Restart -Confirm:$false
    Assert (($script:events -join ',') -eq 'stop:lghub_agent.exe,stop:lghub.exe,start') 'Restart stops agent before UI and launches once'
    Assert ($result.Result -eq 'ProcessesObserved') 'Success describes only observed process health'
    function Wait-Hub { $false }
    Assert-Throws { Invoke-LGHubFix -Action Restart -Confirm:$false } 'Health timeout is a failure'
    function Start-Hub { throw 'launch failed' }
    Assert-Throws { Invoke-LGHubFix -Action Restart -Confirm:$false } 'Launch failures propagate'
    function Get-Installations { @() }
    Assert-Throws { Invoke-LGHubFix -Action InstallStartup -Confirm:$false } 'Missing install blocks startup creation'
    Invoke-LGHubFix -Action RemoveStartup -Confirm:$false | Out-Null
    Assert ($script:events[$script:events.Count - 1] -eq 'startup:True') 'Uninstall works even after G HUB removal'
    Write-Host "Passed $script:passed behavioral assertions"
}
