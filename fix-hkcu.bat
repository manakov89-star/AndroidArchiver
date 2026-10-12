@echo off
setlocal
set "LOG=C:\projects\AndroidArchiver\fix-hkcu.log"
echo start %date% %time% > "%LOG%"
set "NEW=C:\projects\AndroidArchiver\AndroidArchiveCmd.dll"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $k='HKCU:\Software\Classes\CLSID\{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}\InprocServer32'; Set-ItemProperty -Path $k -Name '(default)' -Value '%NEW%' -Type String; 'OK HKCU Inproc' | Out-File -FilePath '%LOG%' -Append -Encoding UTF8 } catch { (\"ERR $($_.Exception.Message)\") | Out-File -FilePath '%LOG%' -Append -Encoding UTF8 }"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $k='HKCU:\Software\Classes\CLSID\{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}'; Set-ItemProperty -Path $k -Name '(default)' -Value 'AndroidArchive.ProjectPacker' -Type String; 'OK HKCU CLSID' | Out-File -FilePath '%LOG%' -Append -Encoding UTF8 } catch { (\"ERR $($_.Exception.Message)\") | Out-File -FilePath '%LOG%' -Append -Encoding UTF8 }"
echo DONE >> "%LOG%"