# Гномус: ежедневная копия памяти (папка life) в %USERPROFILE%\Gnomus-backup, хранятся 14 последних.
# Копия остаётся на этом же ПК и никуда не отправляется. Спасает от случайной порчи и удаления файлов,
# но не от поломки диска. Запускает задача Планировщика GnomusBackup; вручную:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_life.ps1
$ErrorActionPreference = 'Stop'
$src = Join-Path (Split-Path $PSScriptRoot -Parent) 'life'
$dst = Join-Path $HOME 'Gnomus-backup'
if (-not (Test-Path $src)) { Write-Output "нет папки $src"; exit 1 }
New-Item -ItemType Directory -Force $dst | Out-Null
$zip = Join-Path $dst ("life-{0}.zip" -f (Get-Date -Format 'yyyy-MM-dd'))
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $src '*') -DestinationPath $zip
Get-ChildItem $dst -Filter 'life-*.zip' | Sort-Object Name -Descending | Select-Object -Skip 14 | Remove-Item -Force
Write-Output ("копия: {0} ({1:N0} КБ)" -f $zip, ((Get-Item $zip).Length / 1KB))
