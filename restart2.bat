@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Runtime.InteropServices; [Runtime.InteropServices.DllImport('shell32.dll')]::extern void SHChangeNotify(int,uint,IntPtr,IntPtr); [void]::SHChangeNotify(0x08000000,0x0000,[IntPtr]::Zero,[IntPtr]::Zero); [void]::SHChangeNotify(0x08000000,0x0000,[IntPtr]::Zero,[IntPtr]::Zero); Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Sleep 2; Start-Process explorer.exe"
echo DONE