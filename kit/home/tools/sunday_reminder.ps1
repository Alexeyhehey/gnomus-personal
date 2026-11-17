# Гномус: напоминание «итоги недели» по воскресеньям — окошко на экране. Ставит модуль itogi по её «да».
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\sunday_reminder.ps1 [-At 19:00] [-Remove]
param([string]$At = "19:00", [switch]$Remove)
$ErrorActionPreference = 'Stop'
if ($Remove) { Unregister-ScheduledTask -TaskName GnomusSunday -Confirm:$false; "напоминание выключено"; exit 0 }
$text = "Воскресенье! Открой Claude и скажи Гномусу: итоги недели."
$a = New-ScheduledTaskAction -Execute msg.exe -Argument "$env:USERNAME /TIME:3600 `"$text`""
$t = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $At
$p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
Register-ScheduledTask -TaskName GnomusSunday -Action $a -Trigger $t -Principal $p -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable) -Force | Out-Null
"напоминание: каждое воскресенье в $At"
