$ErrorActionPreference = 'Continue'
$dll = 'C:\projects\AndroidArchiver\AndroidArchiveCmd.dll'

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

public static class Act {
    [DllImport("ole32.dll")] public static extern int CoInitializeEx(IntPtr p, uint f);
    [DllImport("ole32.dll")] public static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint ctx, ref Guid iid, out IntPtr ppv);
    [DllImport("ole32.dll")] public static extern void CoUninitialize();
    [DllImport("ole32.dll")] public static extern int CoCreateInstanceEx(ref Guid clsid, IntPtr outer, uint ctx, IntPtr pServers, uint cnt, IntPtr pScores);
}
public static class Qi {
    [DllImport("ole32.dll")] public static extern int QueryInterface(IntPtr p, ref Guid iid, out IntPtr ppv);
    [DllImport("ole32.dll")] public static extern uint Release(IntPtr p);
}
'@
Add-Type -TypeDefinition $src

$hr = [Act]::CoInitializeEx([IntPtr]::Zero, 2)
Write-Host ("CoInitializeEx      = 0x" + ('{0:X8}' -f $hr))

$clsid = [Guid]'a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60'
$iidEc = [Guid]'a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9'
$p = [IntPtr]::Zero
$hr2 = [Act]::CoCreateInstance([ref]$clsid, [IntPtr]::Zero, 1, [ref]$iidEc, [ref]$p)
Write-Host ("CoCreateInstance    = 0x" + ('{0:X8}' -f $hr2))
if ($hr2 -ne 0) { Write-Host 'FAIL: класс не активируется'; exit 1 }

# 1) сырой QueryInterface(IID_IExplorerCommand) на выданном IUnknown
$iidEc = [Guid]'a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9'
$pEc = [Runtime.InteropServices.Marshal]::QueryInterface($p, [ref]$iidEc)
Write-Host ("QI(IExplorerCommand) ptr=" + $pEc)
[void][Runtime.InteropServices.Marshal]::Release($p)
if ($pEc -eq [IntPtr]::Zero) { Write-Host 'FAIL: QI IExplorerCommand'; exit 1 }

# 2) vtable-вызовы
$vt = [Runtime.InteropServices.Marshal]::ReadIntPtr($pEc)
function Get-Fn([int]$idx) { [Runtime.InteropServices.Marshal]::ReadIntPtr($vt, 8 * $idx) }

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class VT {
  [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int GetTitleDel(IntPtr self, IntPtr psi, out IntPtr ppsz);
  [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int GetStateDel(IntPtr self, IntPtr psi, bool slow, out uint st);
  [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int GetFlagsDel(IntPtr self, out uint fl);
  [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int GetCanonDel(IntPtr self, out Guid g);
}
'@
$fnTitle = Get-Fn 3
$dTitle = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($fnTitle, [VT+GetTitleDel])
$s2 = [IntPtr]::Zero
$hrT = $dTitle.Call($pEc, [IntPtr]::Zero, [ref]$s2)
$title = [Runtime.InteropServices.Marshal]::PtrToStringUni($s2)
if ($s2 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeCoTaskMem($s2) }
Write-Host ("GetTitle hr=0x" + ('{0:X8}' -f $hrT) + "  title=[$title]")

$fnState = Get-Fn 7
$dState = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($fnState, [VT+GetStateDel])
$st = [uint32]0
$hrS = $dState.Call($pEc, [IntPtr]::Zero, $false, [ref]$st)
Write-Host ("GetState hr=0x" + ('{0:X8}' -f $hrS) + "  state=0x" + ('{0:X}' -f $st) + "  (0=ENABLED,1=DISABLED,2=HIDDEN)")

$fnFlags = Get-Fn 10
$dFlags = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($fnFlags, [VT+GetFlagsDel])
$fl = [uint32]0
$hrF = $dFlags.Call($pEc, [ref]$fl)
Write-Host ("GetFlags hr=0x" + ('{0:X8}' -f $hrF) + "  flags=0x" + ('{0:X}' -f $fl))

$fnCanon = Get-Fn 6
$dCanon = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($fnCanon, [VT+GetCanonDel])
$g = [Guid]::Empty
$hrC = $dCanon.Call($pEc, [ref]$g)
Write-Host ("GetCanonicalName hr=0x" + ('{0:X8}' -f $hrC) + "  guid=" + $g)

[void][Runtime.InteropServices.Marshal]::Release($pEc)
[Act]::CoUninitialize()
