@echo off
setlocal
set "LOG=C:\projects\AndroidArchiver\approved.log"
echo start %date% %time% > "%LOG%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $ap='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved'; New-Item -Path $ap -Force | Out-Null; New-ItemProperty -Path $ap -Name 'AndroidArchive.ProjectPacker' -Value '{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}' -PropertyType String -Force | Out-Null; 'OK Approved' | Out-File -FilePath '%LOG%' -Append -Encoding UTF8 } catch { (\"ERR $($_.Exception.Message)\") | Out-File -FilePath '%LOG%' -Append -Encoding UTF8 }"
echo DONE >> "%LOG%"