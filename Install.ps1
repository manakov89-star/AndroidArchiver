#Requires -Version 5.1
<#
    Установка / снятие личного архиватора Android-проектов.

        .\Install.ps1              - поставить
        .\Install.ps1 -Uninstall   - снять

    Регистрируется МАШИННО (HKLM), как у WinRAR и 7-Zip: новое контекстное
    меню Windows 11 не показывает пункты, зарегистрированные только в HKCU.
    Поэтому при первом запуске нужен один запрос прав администратора (UAC).

    Пункт появляется в НОВОМ меню, рядом с WinRAR, без
    "Показать дополнительные параметры".
#>
[CmdletBinding()]
param([switch] $Uninstall, [switch] $Elevated, [switch] $Silent)

$ErrorActionPreference = 'Stop'
$base   = $PSScriptRoot
$dll    = Join-Path $base 'AndroidArchiveCmd.dll'
$script = Join-Path $base 'Archive-Android.ps1'
$clsid  = '{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}'
$progid = 'AndroidArchive.ProjectPacker'
$verb   = 'AndroidArchiveSource'
$label  = 'Архивировать проект (без сборки)'
$icon   = "$env:SystemRoot\System32\imageres.dll,-102"

# ---------------------------------------------------------------- повышение прав
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr  = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $Elevated) {
    Write-Host 'Нужны права администратора для регистрации в HKLM (как у WinRAR).' -ForegroundColor Yellow
    Write-Host 'Сейчас появится запрос Windows - нажмите "Да".' -ForegroundColor Yellow
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Elevated')
    if ($Uninstall) { $args += '-Uninstall' }
    if ($Silent) { $args += '-Silent' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait
    exit 0
}

$root = if ($isAdmin) { 'HKLM:\SOFTWARE\Classes' } else { 'HKCU:\Software\Classes' }
Write-Host "Регистрация в: $root" -ForegroundColor DarkGray

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class KiloShell {
  [DllImport("shell32.dll")] public static extern void SHChangeNotify(int e, uint f, IntPtr i, IntPtr j);
}
'@ -ErrorAction SilentlyContinue

$handlerKeys = @(
    "$root\*\shellex\ContextMenuHandlers\AndroidArchive",
    "$root\Directory\shellex\ContextMenuHandlers\AndroidArchive",
    "$root\Directory\Background\shellex\ContextMenuHandlers\AndroidArchive",
    "$root\Drive\shellex\ContextMenuHandlers\AndroidArchive",
    "$root\AllFilesystemObjects\shellex\ContextMenuHandlers\AndroidArchive"
)
$legacyKeys = @(
    "$root\*\shell\$verb",
    "$root\Directory\shell\$verb",
    "$root\Directory\Background\shell\$verb",
    "$root\Drive\shell\$verb"
)

if ($Uninstall) {
    foreach ($k in ($handlerKeys + $legacyKeys + @("$root\CLSID\$clsid", "$root\$progid")))
    { if (Test-Path -LiteralPath $k) { Remove-Item -LiteralPath $k -Recurse -Force } }
    [KiloShell]::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
    Write-Host 'Пункт меню снят.' -ForegroundColor Yellow
    exit 0
}

foreach ($f in @($dll, $script)) { if (-not (Test-Path -LiteralPath $f)) { throw "Не найден $f" } }
Unblock-File -LiteralPath $script -EA SilentlyContinue
Unblock-File -LiteralPath $dll -EA SilentlyContinue

# ---------------------------------------------------------------- COM-расширение
$inproc = "$root\CLSID\$clsid\InprocServer32"
New-Item -Path $inproc -Force | Out-Null
Set-ItemProperty -Path $inproc -Name '(default)'        -Value $dll -Type String
Set-ItemProperty -Path $inproc -Name 'ThreadingModel' -Value 'Both' -Type String
Set-ItemProperty -Path "$root\CLSID\$clsid" -Name '(default)' -Value $progid -Type String

New-Item -Path "$root\$progid\CLSID" -Force | Out-Null
Set-ItemProperty -Path "$root\$progid\CLSID" -Name '(default)' -Value $clsid -Type String

# обработчики контекстного меню: *  покрывает и файлы, и папки, и выделение many
foreach ($t in $handlerKeys) {
    New-Item -Path $t -Force | Out-Null
    Set-ItemProperty -Path $t -Name '(default)' -Value $clsid -Type String
}

# ---------------------------------------------------------------- запасной путь (Shift+F10)
function Set-LegacyVerb([string] $keyPath, [string] $cmdArgs) {
    New-Item -Path $keyPath -Force | Out-Null
    Set-ItemProperty -Path $keyPath -Name 'MUIVerb'  -Value $label -Type String
    Set-ItemProperty -Path $keyPath -Name 'Icon'     -Value $icon  -Type String
    Set-ItemProperty -Path $keyPath -Name 'Position' -Value 'Top'   -Type String
    $ck = Join-Path $keyPath 'command'
    New-Item -Path $ck -Force | Out-Null
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$script`" $cmdArgs"
    [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($ck + '\').SetValue('', $cmd)
    if ($isAdmin) {
        $ck2 = Join-Path $keyPath 'command'
        New-Item -Path $ck2 -Force | Out-Null
        [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($ck2 + '\').SetValue('', $cmd)
    }
}
Set-LegacyVerb "$root\Directory\shell\$verb"            '"%1"'
Set-LegacyVerb "$root\Directory\Background\shell\$verb" '"%V"'
Set-LegacyVerb "$root\Drive\shell\$verb"                '"%1"'

# Windows 11 сверяет COM-расширения со списком Approved
if ($isAdmin) {
    $approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved'
    New-Item -Path $approved -Force | Out-Null
    New-ItemProperty -Path $approved -Name 'AndroidArchive.ProjectPacker' -Value $clsid -PropertyType String -Force | Out-Null
}

[KiloShell]::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)

Write-Host ''
Write-Host "Готово. Пункт: $label" -ForegroundColor Green
Write-Host "Зарегистрировано обработчиков меню: $($handlerKeys.Count)"
Write-Host ''
Write-Host 'Новое COM-расширение Windows подхватывает только после перезапуска'
Write-Host 'Проводника - это единственный раз, когда нужен рестарт.'

if ($Silent) { exit 0 }

Write-Host ''
Write-Host 'Выполнять сейчас? (две открытые папки закроются)'
$ans = Read-Host 'введите Y - перезапустить, Enter - позже'
if ($ans -match '^[YyДд]') {
    Stop-Process -Name explorer -Force -EA SilentlyContinue
    Start-Sleep 2
    Start-Process explorer.exe
    Write-Host 'Проводник перезапущен.' -ForegroundColor Green
}