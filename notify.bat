@echo off
setlocal
set "LOG=C:\projects\AndroidArchiver\comtest.log"
echo start %date% %time% > "%LOG%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System; $hr = [uint32]0; [void]::SHChangeNotify(0x08000000,0x0000,[IntPtr]::Zero,[IntPtr]::Zero); 'OK notify' | Out-File -FilePath '%LOG%' -Append -Encoding UTF8 } catch { (\"ERR $($_.Exception.Message)\") | Out-File -FilePath '%LOG%' -Append -Encoding UTF8 }"
echo DONE >> "%LOG%"