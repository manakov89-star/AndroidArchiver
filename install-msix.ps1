# Установка sparse-MSIX для пункта контекстного меню в НОВОМ меню Windows 11.
# Запускать ПОВЫШЕННЫМ (UAC). Всё пишется в msix-install.log.
$ErrorActionPreference = 'Continue'
$log = 'C:\Users\Youra3\AppData\Local\Temp\opencode\msix-install.log'
function L($m) { Add-Content -Path $log -Value ((Get-Date -Format 'HH:mm:ss') + '  ' + $m) -Encoding UTF8 }
Set-Content -Path $log -Value ('=== установка sparse-MSIX  ' + (Get-Date) + ' ===') -Encoding UTF8

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ('запущено, admin=' + $isAdmin)

$msix = 'C:\projects\AndroidArchiver\AndroidArchiverShell.msix'
$ext  = 'C:\projects\AndroidArchiver'
$cer  = 'C:\projects\AndroidArchiver\cert.cer'

# --- 1. Сертификат подписи в доверенные (LocalMachine) ---
try {
    Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
    L 'сертификат -> LocalMachine\TrustedPeople: OK'
} catch { L ('сертификат TrustedPeople ОШИБКА: ' + $_.Exception.Message) }

# --- 2. Установка пакета ---
$hasExt = (Get-Command Add-AppxPackage).Parameters.ContainsKey('ExternalLocation')
L ('Add-AppxPackage умеет -ExternalLocation: ' + $hasExt)

$installed = $false
if ($hasExt) {
    try {
        Add-AppxPackage -Path $msix -ExternalLocation $ext -ErrorAction Stop
        L 'Add-AppxPackage -ExternalLocation: OK'
        $installed = $true
    } catch { L ('Add-AppxPackage -ExternalLocation ОШИБКА: ' + $_.Exception.Message) }
}
if (-not $installed) {
    try {
        Add-AppxPackage -Path $msix -ErrorAction Stop
        L 'Add-AppxPackage (без -ExternalLocation): OK'
        $installed = $true
    } catch { L ('Add-AppxPackage ОШИБКА: ' + $_.Exception.Message) }
}
if (-not $installed) {
    # самоподписанный корень может потребоваться в Root
    try {
        Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
        L 'сертификат -> LocalMachine\Root: OK (повторная попытка)'
    } catch { L ('сертификат Root ОШИБКА: ' + $_.Exception.Message) }
    if ($hasExt) {
        try {
            Add-AppxPackage -Path $msix -ExternalLocation $ext -ErrorAction Stop
            L 'Add-AppxPackage (повтор с -ExternalLocation): OK'
            $installed = $true
        } catch { L ('повтор -ExternalLocation ОШИБКА: ' + $_.Exception.Message) }
    }
    if (-not $installed) {
        try {
            Add-AppxPackage -Path $msix -ErrorAction Stop
            L 'Add-AppxPackage (повтор без -ExternalLocation): OK'
            $installed = $true
        } catch { L ('повтор без -ExternalLocation ОШИБКА: ' + $_.Exception.Message) }
    }
}

# --- 3. Проверка ---
try {
    $p = Get-AppxPackage -Name 'Youra3.AndroidArchiverShell' -ErrorAction Stop
    if ($p) { L ('пакет установлен: ' + $p.PackageFullName + '   Status=' + $p.Status + '   Loc=' + $p.InstallLocation) }
    else { L 'пакет НЕ найден в Get-AppxPackage' }
} catch { L ('Get-AppxPackage ОШИБКА: ' + $_.Exception.Message) }

Get-ChildItem 'HKLM:\SOFTWARE\Classes\PackagedCom\Package' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -like 'Youra3*' } |
    ForEach-Object { L ('PackagedCom зарегистрирован: ' + $_.PSChildName) }

# --- 4. Удаление мёртвых legacy-глаголов (у них пустой command) ---
$dead = @(
    'HKLM:\SOFTWARE\Classes\Directory\shell\AndroidArchiveSource',
    'HKLM:\SOFTWARE\Classes\Directory\Background\shell\AndroidArchiveSource',
    'HKLM:\SOFTWARE\Classes\Drive\shell\AndroidArchiveSource',
    'HKLM:\SOFTWARE\Classes\*\shell\AndroidArchiveSource',
    'HKLM:\SOFTWARE\Classes\AllFilesystemObjects\shell\AndroidArchiveSource',
    'HKCU:\Software\Classes\Directory\shell\AndroidArchiveSource',
    'HKCU:\Software\Classes\Directory\Background\shell\AndroidArchiveSource',
    'HKCU:\Software\Classes\Drive\shell\AndroidArchiveSource',
    'HKCU:\Software\Classes\*\shell\AndroidArchiveSource',
    'HKCU:\Software\Classes\AllFilesystemObjects\shell\AndroidArchiveSource'
)
foreach ($k in $dead) {
    try {
        if (Test-Path -LiteralPath $k) {
            Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction Stop
            L ('удалён мёртвый глагол: ' + $k)
        } else { L ('нет (уже удалён): ' + $k) }
    } catch { L ('НЕ УДАЛЁН ' + $k + ': ' + $_.Exception.Message) }
}

# --- 5. Перезапуск Explorer ---
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe; Start-Sleep -Seconds 3 }
L ('Explorer перезапущен, запущен=' + [bool](Get-Process explorer -ErrorAction SilentlyContinue))

L '=== ГОТОВО ==='
