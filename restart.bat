@echo off
setlocal
set "LOG=C:\projects\AndroidArchiver\restart.log"
echo start %date% %time% > "%LOG%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.Runtime.InteropServices; [Runtime.InteropServices.DllImport('shell32.dll')]::extern void SHChangeNotify(uint dwEventFlags, uint uFlags, IntPtr dwItem1, IntPtr dwItem2); [void]::SHChangeNotify(0x08000000,0x0000,[IntPtr]::Zero,[IntPtr]::Zero); [void]::SHChangeNotify(0x00000008,0x0000,[IntPtr]::Zero,[IntPtr]::Zero); 'OK notify' | Out-File -FilePath '%LOG%' -Append -Encoding UTF8 } catch { (\"ERR $($_.Exception.Message)\") | Out-File -FilePath '%LOG%' -Append -Encoding UTF8 }"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Sleep 3; Start-Process explorer.exe; 'OK restart' | Out-File -FilePath '%LOG%' -Append -Encoding UTF8"
echo DONE >> "%LOG%"