# Гномус: ночное автообновление (задача Планировщика GnomusUpdate). Тихо: ставит новое и неизменённое,
# память и правки не трогает, итог пишет в tools\update.log — утром Гномус одной строкой скажет хозяйке.
# Нет интернета или адрес недоступен — молча выходит, следующей ночью попробует снова.
$ErrorActionPreference = 'Continue'
$tools = $PSScriptRoot
try { & powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\update.ps1" *> "$tools\update-last-run.txt" } catch { }
