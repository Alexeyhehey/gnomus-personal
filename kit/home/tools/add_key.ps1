# Гномус: подключить ОДИН бесплатный ключ. Ввод скрытый — ключ не виден на экране и не попадает в чат.
#   tools\add_key.cmd GROQ_API_KEY        (или OPENROUTER_API_KEY, GEMINI_API_KEY)
# Открывает страницу сервиса, ждёт ключ, проверяет его и сохраняет в переменные пользователя Windows.
param([Parameter(Mandatory = $true)][string]$Name)

$Known = @{
    GROQ_API_KEY       = @{ Url = "https://console.groq.com/keys"; Test = "https://api.groq.com/openai/v1/models"; Hdr = "Bearer"; Hint = "Войди (можно через Google) -> Create API Key -> Copy. Ключ начинается с gsk_" }
    OPENROUTER_API_KEY = @{ Url = "https://openrouter.ai/settings/keys"; Test = "https://openrouter.ai/api/v1/key"; Hdr = "Bearer"; Hint = "Войди (можно через Google) -> Create Key -> Copy. Ключ начинается с sk-or-" }
    GEMINI_API_KEY     = @{ Url = "https://aistudio.google.com/app/apikey"; Test = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1"; Hdr = "x-goog-api-key"; Hint = "Войди через Google -> Create API key -> Copy. Ключ начинается с AIza" }
}
if (-not $Known.ContainsKey($Name)) { Write-Host "Неизвестное имя $Name. Знаю: $($Known.Keys -join ', ')" -ForegroundColor Red; Read-Host "Enter — закрыть"; exit 1 }
$k = $Known[$Name]

function Read-Secret([string]$prompt) {
    $secure = Read-Host -AsSecureString $prompt
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

Write-Host ""
Write-Host "=== Подключаем бесплатную модель: $Name ===" -ForegroundColor Cyan
Write-Host "Сейчас откроется страница. $($k.Hint)."
Write-Host "Это бесплатно, карта не нужна. Если сайт просит карту или оплату — закрой его и скажи Гномусу." -ForegroundColor Yellow
Start-Process $k.Url
while ($true) {
    $key = Read-Secret "Скопируй ключ, вернись сюда, нажми правую кнопку мыши (вставить) и Enter. Пустой Enter — выйти"
    if (-not $key) { Write-Host "Вышли без изменений."; break }
    $h = @{}
    if ($k.Hdr -eq "Bearer") { $h.Authorization = "Bearer $key" } else { $h[$k.Hdr] = $key }
    try {
        Invoke-WebRequest -UseBasicParsing -Headers $h -UserAgent "gnomus-personal/1.0" -TimeoutSec 20 $k.Test | Out-Null
        [Environment]::SetEnvironmentVariable($Name, $key, 'User')
        Write-Host "Ключ работает и сохранён. Скажи Гномусу: «готово»." -ForegroundColor Green
        break
    } catch { Write-Host "Ключ не подошёл. Проверь, что скопировала целиком, и попробуй ещё раз." -ForegroundColor Red }
}
Read-Host "Enter — закрыть окно"
