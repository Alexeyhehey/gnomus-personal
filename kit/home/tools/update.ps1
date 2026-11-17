# Личный Гномус: обновление без SSH. Ставит новые версии прошивки, навыков и инструментов,
# НЕ трогая память (life/), входящие (inbox/) и любые файлы, которые человек или Гномус меняли.
#   powershell -NoProfile -ExecutionPolicy Bypass -File update.ps1 -Source <папка | zip | адрес latest.json>
#   powershell -NoProfile -ExecutionPolicy Bypass -File update.ps1 -Check            # только показать, что изменится
#   powershell -NoProfile -ExecutionPolicy Bypass -File update.ps1 -Adopt -Source …  # принять текущие файлы как установленные (один раз, после ручной установки)
# Источник по умолчанию — адрес из Gnomus\tools\update_source.txt.
# Учёт установленного — Gnomus\.gnomus-state.json: какой файл какой версии мы записали (sha256 записанного).
# Правило: файл совпадает с тем, что мы записали в прошлый раз → заменяем; файл менялся → кладём рядом <имя>.new и сообщаем.
param([string]$Source, [switch]$Check, [switch]$Adopt, [string]$HomeDir = $HOME)  # HomeDir — только для проверки на макете
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$HOME_ = $HomeDir
$G = "$HOME_\Gnomus"; $C = "$HOME_\.claude"; $StateFile = "$G\.gnomus-state.json"
$utf8 = New-Object Text.UTF8Encoding $false
if (-not (Test-Path $G)) { "Гномус не установлен (нет $G) — нужен install.ps1"; exit 1 }

function Sha([byte[]]$b) { ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($b))).Replace('-', '').ToLower() }
function Fill([byte[]]$b, [string]$src) {  # подставить пути пользователя в текстовые файлы
    if ($src -notmatch '\.(md|txt)$') { return ,$b }
    $t = [Text.Encoding]::UTF8.GetString($b)
    if ($t -notmatch '\{\{(GNOMUS_HOME|USER_HOME)\}\}') { return ,$b }
    $bom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    $t = $t.Replace('{{GNOMUS_HOME}}', $G).Replace('{{USER_HOME}}', $HOME_)
    $out = $utf8.GetBytes($t.TrimStart([char]0xFEFF))
    if ($bom) { $out = [byte[]](0xEF, 0xBB, 0xBF) + $out }
    return ,$out
}
function Target([string]$dst) {
    $p = $dst -split '/', 2
    $base = switch ($p[0]) { 'gnomus' { $G } 'skills' { "$C\skills" } 'claude' { $C } default { throw "неизвестное место $dst" } }
    Join-Path $base ($p[1] -replace '/', '\')
}

# --- источник: папка, zip или адрес latest.json ---
if (-not $Source) { $sf = "$G\tools\update_source.txt"; if (Test-Path $sf) { $Source = (Get-Content $sf -TotalCount 1).Trim() } }
if (-not $Source) { "Не знаю, откуда обновляться: нет -Source и нет tools\update_source.txt"; exit 1 }
$work = Join-Path $env:TEMP ("gnomus-update-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $work | Out-Null
try {
    if ($Source -match '^https?://') {
        $base = $Source.Substring(0, $Source.LastIndexOf('/') + 1)
        $zipUrl = $Source
        if ($Source -match '\.json$') { $l = Invoke-RestMethod $Source -UseBasicParsing -TimeoutSec 30; $zipUrl = $base + $l.zip }
        Invoke-WebRequest $zipUrl -OutFile "$work\kit.zip" -UseBasicParsing -TimeoutSec 120
        Expand-Archive "$work\kit.zip" "$work\kit"; $kit = "$work\kit"
    } elseif ($Source -match '\.zip$') { Expand-Archive $Source "$work\kit"; $kit = "$work\kit" }
    else { $kit = $Source }
    $m = Get-Content "$kit\manifest.json" -Raw -Encoding UTF8 | ConvertFrom-Json

    $state = @{ version = ''; files = @{} }
    if (Test-Path $StateFile) {
        $s = Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $state.version = $s.version; foreach ($p in $s.files.PSObject.Properties) { $state.files[$p.Name] = $p.Value }
    }
    $done = @{ new = @(); updated = @(); same = @(); kept = @(); seeded = @() }
    foreach ($e in $m.files) {
        $srcBytes = [IO.File]::ReadAllBytes((Join-Path $kit ($e.src -replace '/', '\')))
        if ((Sha $srcBytes) -ne $e.sha256) { throw "повреждён файл в комплекте: $($e.src)" }
        $bytes = Fill $srcBytes $e.src; $want = Sha $bytes
        $dst = Target $e.dst; $exists = Test-Path -LiteralPath $dst
        $cur = if ($exists) { Sha ([IO.File]::ReadAllBytes($dst)) } else { $null }
        if ($Adopt) { if ($exists) { $state.files[$e.dst] = $cur }; continue }
        if ($e.mode -eq 'seed') { if (-not $exists) { $done.seeded += $e.dst; if (-not $Check) { New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null; [IO.File]::WriteAllBytes($dst, $bytes) } }; continue }
        if ($cur -eq $want) { $done.same += $e.dst; $state.files[$e.dst] = $want; continue }
        if (-not $exists) { $done.new += $e.dst }
        elseif ($state.files.ContainsKey($e.dst) -and $state.files[$e.dst] -eq $cur) { $done.updated += $e.dst }
        else { $done.kept += $e.dst; if (-not $Check) { [IO.File]::WriteAllBytes("$dst.new", $bytes) }; continue }
        if (-not $Check) { New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null; [IO.File]::WriteAllBytes($dst, $bytes); $state.files[$e.dst] = $want }
    }
    if (-not $Check) {
        $state.version = $m.version
        [IO.File]::WriteAllText($StateFile, (@{ version = $state.version; updated = (Get-Date).ToString('s'); files = $state.files } | ConvertTo-Json -Depth 4), $utf8)
        if ($done.new.Count -or $done.updated.Count -or $done.kept.Count) {  # журнал для Гномуса: что сказать хозяйке
            $line = "{0} обновлено до версии {1}: новые {2}; обновлены {3}; изменены вручную (лежат .new) {4}`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $m.version, (($done.new | ForEach-Object { $_ -replace '^[^/]+/' }) -join ', '), (($done.updated | ForEach-Object { $_ -replace '^[^/]+/' }) -join ', '), ($done.kept -join ', ')
            [IO.File]::AppendAllText("$G\tools\update.log", $line, $utf8)
        }
        $desk = [Environment]::GetFolderPath('Desktop')
        if ($HomeDir -eq $HOME -and $done.updated -contains 'gnomus/ПРОЧТИ.md') { Copy-Item "$G\ПРОЧТИ.md" "$desk\ГНОМУС — прочти меня.txt" -Force }
        if ($HomeDir -eq $HOME -and ($done.updated -contains 'gnomus/ШПАРГАЛКА.md' -or $done.new -contains 'gnomus/ШПАРГАЛКА.md')) { Copy-Item "$G\ШПАРГАЛКА.md" "$desk\ГНОМУС — шпаргалка.txt" -Force }
    }
    $verb = if ($Check) { 'будет' } else { 'готово' }
    if ($Adopt) { "приняты как установленные: $($state.files.Count) файлов, версия $($m.version)"; exit 0 }
    "версия: $(if ($state.version) { $state.version } else { 'неизвестна' }) -> $($m.version) ($verb)"
    "новые: $($done.new.Count); обновлены: $($done.updated.Count); без изменений: $($done.same.Count); новые файлы памяти: $($done.seeded.Count)"
    foreach ($k in $done.new + $done.updated) { "  + $k" }
    if ($done.kept.Count) { "ИЗМЕНЕНЫ ВРУЧНУЮ, не тронуты (новая версия лежит рядом с окончанием .new):"; foreach ($k in $done.kept) { "  ! $k" } }
} finally { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
