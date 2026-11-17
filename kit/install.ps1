# Личный Гномус: установка на ПК человека (запускать на ЕГО компьютере, от его пользователя, без админа).
#   powershell -NoProfile -ExecutionPolicy Bypass -File personal\install.ps1
# Только добавляет: папка %USERPROFILE%\Gnomus, скиллы в ~/.claude/skills, ~/.claude/CLAUDE.md (если нет),
# права на папку в ~/.claude/settings.json (бэкап settings.json.bak-before-gnomus), ярлыки на рабочем столе.
# Существующее не перезаписывает. Файл сохранён в UTF-8 с BOM: PowerShell 5.1 иначе портит кириллицу.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$kit = $PSScriptRoot; $G = "$HOME\Gnomus"; $C = "$HOME\.claude"
$utf8 = New-Object Text.UTF8Encoding $false; $utf8bom = New-Object Text.UTF8Encoding $true
if (Test-Path $G) { "ОТМЕНА: $G уже существует — личные данные не трогаю"; exit 1 }

function Fill([string]$path) {  # подставить пути этого пользователя вместо токенов
    $t = [IO.File]::ReadAllText($path)
    if ($t -match '\{\{(GNOMUS_HOME|USER_HOME)\}\}') { [IO.File]::WriteAllText($path, $t.Replace('{{GNOMUS_HOME}}', $G).Replace('{{USER_HOME}}', $HOME), $utf8) }
}

Copy-Item "$kit\home" $G -Recurse
Rename-Item "$G\README_RU.md" "ПРОЧТИ.md"
Rename-Item "$G\CHEATSHEET_RU.md" "ШПАРГАЛКА.md"
New-Item -ItemType Directory -Force "$G\inbox\разобрано" | Out-Null
[IO.File]::WriteAllText("$G\inbox\ЧТО_СЮДА_КЛАСТЬ.txt", "Сюда можно класть файлы для Гномуса: анализы, чеки, фото рецептов, документы. Или просто перетаскивай их в чат.", $utf8bom)
Get-ChildItem $G -Recurse -File -Include *.md | ForEach-Object { Fill $_.FullName }

New-Item -ItemType Directory -Force "$C\skills" | Out-Null
foreach ($s in Get-ChildItem "$kit\skills" -Directory) {
    $d = "$C\skills\$($s.Name)"
    if (Test-Path $d) { "скилл $($s.Name): уже есть, пропущен" } else { Copy-Item $s.FullName $d -Recurse; Fill "$d\SKILL.md"; "скилл $($s.Name): установлен" }
}
if (Test-Path "$C\CLAUDE.md") { "~/.claude/CLAUDE.md уже есть — не тронут; добавь в него вручную блок из personal\global\CLAUDE.md" }
else { Copy-Item "$kit\global\CLAUDE.md" "$C\CLAUDE.md"; Fill "$C\CLAUDE.md"; "~/.claude/CLAUDE.md: установлен" }

$sp = "$C\settings.json"
if (Test-Path $sp) { Copy-Item $sp "$sp.bak-before-gnomus" -Force; $j = Get-Content $sp -Raw | ConvertFrom-Json } else { $j = [pscustomobject]@{} }
$allow = @("Read(~/Gnomus/**)", "Edit(~/Gnomus/**)", "Bash(python tools/ask_local.py:*)", "Bash(python tools/ask_free.py:*)", "Bash(python tools/doctor.py)")
if (-not $j.permissions) { $j | Add-Member permissions ([pscustomobject]@{ allow = $allow }) }
elseif (-not $j.permissions.allow) { $j.permissions | Add-Member allow $allow }
else { $j.permissions.allow = @($j.permissions.allow) + ($allow | Where-Object { $j.permissions.allow -notcontains $_ }) }
# авто-режим: обычные действия без окон «разрешить?», рискованные отсекает встроенная проверка; оплата/отправка/удаление — по прошивке, через её «да»
if (-not $j.permissions.defaultMode) { $j.permissions | Add-Member defaultMode 'auto' }
[IO.File]::WriteAllText($sp, ($j | ConvertTo-Json -Depth 10), $utf8)  # без BOM: Claude Code не читает JSON с BOM

$desk = [Environment]::GetFolderPath('Desktop')
Copy-Item "$G\ПРОЧТИ.md" "$desk\ГНОМУС — прочти меня.txt" -Force
Copy-Item "$G\ШПАРГАЛКА.md" "$desk\ГНОМУС — шпаргалка.txt" -Force
# ежедневная копия памяти life/ в %USERPROFILE%\Gnomus-backup (14 дней, наружу не уходит)
Register-ScheduledTask -TaskName GnomusBackup -Force -Action (New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$G\tools\backup_life.ps1`"") -Trigger (New-ScheduledTaskTrigger -Daily -At 21:00) -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) | Out-Null
"задача GnomusBackup: копия памяти каждый день в 21:00"
# ночное автообновление из публичного репозитория (адрес — tools\update_source.txt)
Register-ScheduledTask -TaskName GnomusUpdate -Force -Action (New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$G\tools\auto_update.ps1`"") -Trigger (New-ScheduledTaskTrigger -Daily -At 04:30) -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) | Out-Null
"задача GnomusUpdate: обновление каждую ночь в 04:30 (или при включении, если ПК был выключен)"
$app = Get-StartApps | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1
if ($app) {
    $l = (New-Object -ComObject WScript.Shell).CreateShortcut("$desk\Гномус.lnk")
    $l.TargetPath = "$env:WINDIR\explorer.exe"; $l.Arguments = "shell:AppsFolder\$($app.AppID)"; $l.Description = 'Гномус — личный помощник'; $l.Save()
} else { "приложение Claude не найдено: https://claude.ai/download" }

# локальная модель (бесплатный черновик): нужен Ollama и хотя бы одна модель
$ol = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ol) { "Ollama нет — tools\ask_local.py работать не будет (не обязательно): winget install Ollama.Ollama; ollama pull qwen3:8b" }
elseif (-not (Get-ScheduledTask GnomusOllama -ErrorAction SilentlyContinue)) {
    Register-ScheduledTask -TaskName GnomusOllama -Action (New-ScheduledTaskAction -Execute $ol.Source -Argument 'serve') -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME) -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable) | Out-Null
    "задача GnomusOllama: сервер локальной модели при входе"
}
# запомнить установленные версии файлов, чтобы tools\update.ps1 потом отличал правки человека от старых версий
if (Test-Path "$kit\manifest.json") { & powershell -NoProfile -ExecutionPolicy Bypass -File "$kit\update.ps1" -Source $kit -Adopt }
else { "manifest.json нет (комплект не из build.py) — перед первым обновлением запусти update.ps1 -Adopt" }
"ГОТОВО. Дальше человек сам: Claude -> вкладка Code -> вход в СВОЙ аккаунт -> написать «привет»."
