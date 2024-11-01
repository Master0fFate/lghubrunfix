# LGHUB Silent Admin Autostart
A PowerShell script that creates a scheduled task to automatically run Logitech G HUB with administrative privileges at system startup. The task runs silently in the background using SYSTEM privileges, ensuring all G HUB features work properly without user interaction or UAC prompts.
This also fixes lghub not being able to autostart on elevated priviledges

## Usage
Run the script once as administrator. G HUB will then automatically start with required privileges on subsequent system startups
or run it manually with powershell.

> _if you changed the default installation path, change it in the script to your custom one_
