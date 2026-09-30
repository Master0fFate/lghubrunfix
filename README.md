# G HUB startup diagnosis and recovery

A small Windows PowerShell tool for investigating G HUB startup, restarting **your current session's** G HUB processes, and optionally adding a normal per-user startup shortcut. It does not promise to fix every loading loop.

## Start here

Download/extract the repository and keep `lghubfix.ps1` beside `LGHubFix.psm1`. Open a **normal, non-administrator PowerShell** window in that folder. Windows PowerShell 5.1 and PowerShell 7 are supported targets.

```powershell
# Read-only; also the default with no arguments
.\lghubfix.ps1 -Action Diagnose | ConvertTo-Json -Depth 5

# Preview the restart without stopping or launching anything
.\lghubfix.ps1 -Action Restart -WhatIf

# Save edits, quit G HUB from its tray icon, then recover the user processes
.\lghubfix.ps1 -Action Restart
```

Follow your organization's script-signing/execution policy. This tool does not change policy, bypass it, request elevation, or hide failures. If Windows blocks a downloaded script, inspect it and follow your administrator's approved procedure rather than blindly bypassing the warning.

Discovery checks common installation directories and G HUB uninstall registry records. For a custom location, or if more than one installation is found, pass the **folder**, not the executable:

```powershell
.\lghubfix.ps1 -Action Diagnose -InstallPath 'D:\Apps\LGHUB'
.\lghubfix.ps1 -Action Restart -InstallPath 'D:\Apps\LGHUB' -TimeoutSeconds 60
```

Diagnosis lists paths/versions, this user's matching processes, updater service state, the old `LGHUBAutoStart` task, and presence of this tool's shortcut. Logs are not uploaded or saved automatically. Paths may contain your username; review diagnostic output before sharing it. `Health = NotAssessed` is intentional.

## What restart does

- Verifies executable path, current user SID, and current interactive session before considering a process
- Stops `lghub_agent.exe`, then `lghub.exe`; rechecks process creation time/path before stopping each process object
- Leaves updater, services, other users, other installations, profiles, settings and device data untouched
- Waits for termination with a deadline, launches the discovered `lghub.exe` with its own working directory, then observes UI and agent in three consecutive one-second polls
- Fails with a nonzero exit code on launch errors or timeout; reports `ProcessesObserved`, never “fully repaired”

The stop and health-observation phases each have their own timeout (default 30 seconds, range 5–300). OS calls themselves may take longer. Process presence cannot establish that the UI has finished loading or your device profiles work. Open G HUB and check both. Processes whose ownership/path cannot be inspected are left alone; this can prevent recovery and should be investigated manually. Restarting can interrupt macros/profile switching and unsaved changes.

### Still stuck?

Run diagnosis. A stopped/missing `LGHUBUpdaterService`, a spinning UI despite both processes, or immediately respawning processes needs further investigation. Logitech's current procedure includes restarting its updater service manually. This tool deliberately does not change services, reinstall software, delete caches, or edit security settings. Use [Logitech's loading-loop guide](https://support.logi.com/hc/en-ca/articles/360036179173-G-HUB-freezes-while-loading-and-logo-animation-loops) and [official support](https://support.logi.com/). Its current Windows guidance leaves the updater process running; outdated recipes that kill every Logitech process are not followed here.

## Optional automatic launch at sign-in

Prefer G HUB's own startup setting first. Disable duplicate entries yourself before using this fallback. It launches G HUB normally when **you sign in**, not at machine boot, and does not run the recovery routine repeatedly.

```powershell
.\lghubfix.ps1 -Action InstallStartup -WhatIf
.\lghubfix.ps1 -Action InstallStartup
# Undo only this tool's shortcut (works even if G HUB has been uninstalled)
.\lghubfix.ps1 -Action RemoveStartup
```

The shortcut is `LGHUB Run Fix.lnk` in your Windows Startup folder (`Win+R`, `shell:startup`). Installation updates an existing shortcut only when its description has this tool's ownership marker; removal uses the same check. A foreign shortcut with that name causes an error. No scheduled task, background repair script or administrator token is installed. Windows Startup settings can disable it; confirm after signing out and in. If you move G HUB, rerun installation with the new path. You can also delete this one shortcut manually.

## Migrating from the old script

The old version silently elevated, hardcoded `C:\Program Files\LGHUB\lghub.exe`, overwrote a global task, and printed task registration as success without verifying G HUB. Its README described SYSTEM/boot execution, while the actual task used an interactive user at logon. It also depended on a hidden VBScript launcher. Those design flaws do not establish the cause of every user's failure.

The new script **does not automatically delete legacy setup**. If diagnosis reports `LegacyTaskDetected`, open Task Scheduler and inspect/export `LGHUBAutoStart`. Confirm that its action points to the old `LGHUBWorker.vbs`, then disable the old task to avoid duplicate/elevated launches. After testing the new setup, you may delete that old task and its old `%ProgramData%\LGHUBWorker.vbs` file yourself. Do not remove an unrelated task just because its name matches. Administrative access may be required for legacy cleanup.

## Tests and validation limits

```powershell
.\tests\Run-Tests.ps1
```

The dependency-free suite tests process scope, missing/ambiguous installs, real temporary-file discovery, reused PIDs, consecutive health observations, dry-run, restart ordering, failure propagation, startup action routing and removal after uninstall. Process/platform/startup side effects are mocked: tests never stop real applications or alter Windows startup. CI runs the suite and syntax parsing on Windows PowerShell 5.1 and PowerShell 7.

Development verification: PowerShell 7.4.7 on Linux, with Windows integration boundaries mocked. Native CIM ownership, exact process timestamps, COM shortcut persistence, registry discovery and actual G HUB loading require a Windows machine with G HUB. Before treating the draft as production-ready, verify:

1. Diagnose on default/custom paths, standard/elevated terminals, and absent installations
2. `-WhatIf` changes nothing for all three mutating actions
3. Restart with G HUB running, hung, absent, and in another user/session; updater remains untouched
4. Inspect UI/devices/profiles after restart, including failure/timeout cases
5. Install twice, sign out/in, remove twice, and test a foreign shortcut name collision
6. Test old-task migration and duplicate G HUB startup settings

## Implementation references

- [PowerShell ShouldProcess / WhatIf](https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-shouldprocess)
- [Start-Process](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process)
- [Stop-Process](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/stop-process)
- [Windows startup folders](https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid)
- [Win32_Process](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-process)
