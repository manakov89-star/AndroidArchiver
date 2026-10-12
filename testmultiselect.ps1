# Тест IExplorerCommand с РЕАЛЬНЫМ IShellItemArray из нескольких файлов -
# точно так новый меню Win11 строит пункт для множественного выделения.
$ErrorActionPreference = 'Stop'
$src = @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IExplorerCommand {
    [PreserveSig] int GetTitle(IntPtr psi, out IntPtr psz);
    [PreserveSig] int GetIcon(IntPtr psi, out IntPtr psz);
    [PreserveSig] int GetToolTip(IntPtr psi, out IntPtr psz);
    [PreserveSig] int GetCanonicalName(out Guid pguid);
    [PreserveSig] int GetState(IntPtr psi, bool fOkToBeSlow, out uint pCmdState);
    [PreserveSig] int Invoke(IntPtr psi, IntPtr pbc);
    [PreserveSig] int GetFlags(out uint pFlags);
    [PreserveSig] int EnumSubCommands(out IntPtr ppEnum);
}

public static class Native {
    [DllImport("ole32.dll")] public static extern int CoInitializeEx(IntPtr p, uint f);
    [DllImport("ole32.dll")] public static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint ctx, ref Guid iid, out IntPtr ppv);
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    public static extern int SHParseDisplayName(string name, IntPtr pbc, out IntPtr ppidl, uint sfgaoIn, out uint sfgaoOut);
    [DllImport("shell32.dll")]
    public static extern int SHCreateShellItemArrayFromIDLists(uint cidl, IntPtr[] apidl, out IntPtr pArray);
    [DllImport("ole32.dll")] public static extern void CoTaskMemFree(IntPtr p);
}
'@
Add-Type -TypeDefinition $src

$hr = [Native]::CoInitializeEx([IntPtr]::Zero, 2)   # STA
Write-Host ("CoInitializeEx      = 0x" + ('{0:X8}' -f $hr))

# --- собрать PIDL для каждого файла (multi-select)
$files = @(
    'C:\projects\_menutest\parent\child\f1.txt',
    'C:\projects\_menutest\parent\child\f2.txt',
    'C:\projects\AndroidArchiver\build.bat'
)
$pidls = New-Object 'System.Collections.Generic.List[IntPtr]'
foreach ($f in $files) {
    $p = [IntPtr]::Zero; $q = [uint32]0
    $hr = [Native]::SHParseDisplayName($f, [IntPtr]::Zero, [ref]$p, 0, [ref]$q)
    if ($hr -ne 0 -or $p -eq [IntPtr]::Zero) { throw ("SHParseDisplayName failed for " + $f + " hr=0x" + ('{0:X8}' -f $hr)) }
    $pidls.Add($p)
}
Write-Host ("PIDL готово: " + $pidls.Count)

$arr = [IntPtr]::Zero
$apidl = $pidls.ToArray()
$hr = [Native]::SHCreateShellItemArrayFromIDLists([uint32]$apidl.Length, $apidl, [ref]$arr)
foreach ($p in $pidls) { [Native]::CoTaskMemFree($p) }
Write-Host ("SHCreateShellItemArrayFromIDLists = 0x" + ('{0:X8}' -f $hr) + "  ptr=" + $arr)
if ($hr -ne 0) { throw 'не удалось создать IShellItemArray' }

# --- активировать наш COM-класс (тот же код, что грузит Explorer)
$clsid = [Guid]'a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60'
$iid = [Guid]'a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9'
$p = [IntPtr]::Zero
$hr = [Native]::CoCreateInstance([ref]$clsid, [IntPtr]::Zero, 1, [ref]$iid, [ref]$p)
Write-Host ("CoCreateInstance    = 0x" + ('{0:X8}' -f $hr))
if ($hr -ne 0) { throw 'COM-класс не активируется' }

$ec = [Runtime.InteropServices.Marshal]::GetObjectForIUnknown($p) -as [IExplorerCommand]
if (-not $ec) { throw 'QI IExplorerCommand failed' }

# GetState с массивом из 3 файлов (ECS: 0=ENABLED, 1=DISABLED, 2=HIDDEN)
$st = [uint32]99
$hrS = $ec.GetState($arr, $true, [ref]$st)
$stateTxt = switch ($st) { 0 {'ENABLED (виден и активен)'} 1 {'DISABLED (СЕРЫЙ!)'} 2 {'HIDDEN (НЕ ВИДЕН!)'} default {"неизвестно 0x$('{0:X}' -f $st)"} }
Write-Host ("GetState(multi)     = hr 0x" + ('{0:X8}' -f $hrS) + "  state=$st -> $stateTxt")

# GetTitle с массивом
$s = [IntPtr]::Zero
$hrT = $ec.GetTitle($arr, [ref]$s)
$title = if ($s -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::PtrToStringUni($s) } else { '' }
if ($s -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeCoTaskMem($s) }
Write-Host ("GetTitle(multi)     = hr 0x" + ('{0:X8}' -f $hrT) + "  title=[$title]")

# GetState без массива (одиночный выбор)
$st2 = [uint32]99
$hrS2 = $ec.GetState([IntPtr]::Zero, $true, [ref]$st2)
Write-Host ("GetState(single)    = hr 0x" + ('{0:X8}' -f $hrS2) + "  state=$st2")

$fl = [uint32]0
$hrF = $ec.GetFlags([ref]$fl)
Write-Host ("GetFlags            = hr 0x" + ('{0:X8}' -f $hrF) + "  flags=0x" + ('{0:X}' -f $fl))

# QI IContextMenu (классическое меню)
$icm = [Guid]'000214E4-0000-0000-C000-000000000046'
$pm = [IntPtr]::Zero
$hrI = [Native]::CoCreateInstance([ref]$clsid, [IntPtr]::Zero, 1, [ref]$icm, [ref]$pm)
Write-Host ("QI IContextMenu     = 0x" + ('{0:X8}' -f $hrI))

[void][Runtime.InteropServices.Marshal]::Release($p)
[Runtime.InteropServices.Marshal]::ReleaseComObject($ec) 2>$null | Out-Null
[Native]::CoTaskMemFree($arr)
[Native]::CoInitializeEx([IntPtr]::Zero, 0) | Out-Null

# --- ИТОГ
if ($st -eq 0 -and $title -match 'Архивировать') {
    Write-Host ''
    Write-Host 'PASS: для МНОЖЕСТВЕННОГО выделения пункт ВИДЕН и АКТИВЕН, заголовок корректен.' -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host "FAIL: state=$st title=[$title]" -ForegroundColor Red
    exit 1
}
