#Requires -Version 5.1
# Разовая доделка машинной регистрации с логом (запускается с правами администратора).
$ErrorActionPreference = 'Stop'
$script:fail = 0
$log = Join-Path $PSScriptRoot 'register.log'
function L($m) { "$((Get-Date).ToString('HH:mm:ss'))  $m" | Out-File -FilePath $log -Append -Encoding UTF8 }
"" | Out-File -FilePath $log -Encoding UTF8

$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") | Out-Null
    exit 0
}

$clsid  = '{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}'
$progid = 'AndroidArchive.ProjectPacker'
$dll    = Join-Path $PSScriptRoot 'AndroidArchiveCmd.dll'
$script = Join-Path $PSScriptRoot 'Archive-Android.ps1'
$root   = 'HKLM:\SOFTWARE\Classes'
$verb   = 'AndroidArchiveSource'
$label  = 'Архивировать проект (без сборки)'
$icon   = "$env:SystemRoot\System32\imageres.dll,-102"

L "elevated = $isAdmin"

# COM-класс
try {
    $inproc = "$root\CLSID\$clsid\InprocServer32"
    New-Item -Path $inproc -Force | Out-Null
    Set-ItemProperty -Path $inproc -Name '(default)' -Value $dll -Type String
    Set-ItemProperty -Path $inproc -Name 'ThreadingModel' -Value 'Both' -Type String
    Set-ItemProperty -Path "$root\CLSID\$clsid" -Name '(default)' -Value $progid -Type String
    New-Item -Path "$root\$progid\CLSID" -Force | Out-Null
    Set-ItemProperty -Path "$root\$progid\CLSID" -Name '(default)' -Value $clsid -Type String
    L 'OK  COM-класс зарегистрирован'
} catch { $script:fail++; L "ERR COM: $($_.Exception.Message)" }

# обработчики меню
$handlers = @('*', 'Directory', 'Directory\Background', 'Drive', 'AllFilesystemObjects')
foreach ($h in $handlers) {
    $k = "$root\$h\shellex\ContextMenuHandlers\AndroidArchive"
    try {
        New-Item -Path $k -Force | Out-Null
        Set-ItemProperty -Path $k -Name '(default)' -Value $clsid -Type String
        L "OK  handler: $h"
    } catch { $script:fail++; L "ERR handler $h : $($_.Exception.Message)" }
}

# список Approved
try {
    $ap = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved'
    New-Item -Path $ap -Force | Out-Null
    New-ItemProperty -Path $ap -Name 'AndroidArchive.ProjectPacker' -Value $clsid -PropertyType String -Force | Out-Null
    L 'OK  Approved'
} catch { $script:fail++; L "ERR Approved: $($_.Exception.Message)" }

# запасные legacy-пункты
function Set-LegacyVerb([string] $keyPath, [string] $cmdArgs) {
    try {
        New-Item -Path $keyPath -Force | Out-Null
        Set-ItemProperty -Path $keyPath -Name 'MUIVerb' -Value $label -Type String
        Set-ItemProperty -Path $keyPath -Name 'Icon' -Value $icon -Type String
        $ck = Join-Path $keyPath 'command'
        New-Item -Path $ck -Force | Out-Null
        $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$script`" $cmdArgs"
        [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($ck + '\').SetValue('', $cmd)
        L "OK  legacy: $keyPath"
    } catch { $script:fail++; L "ERR legacy $keyPath : $($_.Exception.Message)" }
}
Set-LegacyVerb "$root\Directory\shell\$verb" '"%1"'
Set-LegacyVerb "$root\Directory\Background\shell\$verb" '"%V"'
Set-LegacyVerb "$root\Drive\shell\$verb" '"%1"'

# уведомить оболочку
try {
    Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class N2{[DllImport("shell32.dll")]public static extern void SHChangeNotify(int e,uint f,IntPtr i,IntPtr j);}'
    [N2]::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
    L 'OK  SHChangeNotify'
} catch { $script:fail++; L "ERR notify: $($_.Exception.Message)" }

L "ГОТОВО, ошибок: $script:fail"