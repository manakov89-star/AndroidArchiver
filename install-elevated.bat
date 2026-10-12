@echo off
chcp 65001 >nul
echo.
echo ========================================
echo  Установка архиватора Android-проектов
echo ========================================
echo.
echo Шаг 1: Регистрация DLL...
regsvr32 /s "C:\projects\AndroidArchiver\AndroidArchiveCmd.dll"
if %errorlevel% neq 0 (
    echo ОШИБКА: не удалось зарегистрировать DLL. Запустите этот файл от имени администратора.
    pause
    exit /b 1
)
echo DLL зарегистрирована.

echo.
echo Шаг 2: Настройка реестра...
reg add "HKLM\SOFTWARE\Classes\CLSID\{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}\InprocServer32" /ve /t REG_SZ /d "C:\projects\AndroidArchiver\AndroidArchiveCmd.dll" /f >nul
reg add "HKLM\SOFTWARE\Classes\CLSID\{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}" /ve /t REG_SZ /d "AndroidArchive.ProjectPacker" /f >nul
reg add "HKLM\SOFTWARE\Classes\AndroidArchive.ProjectPacker\CLSID" /ve /t REG_SZ /d "{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}" /f >nul

reg add "HKLM\SOFTWARE\Classes\*\shellex\ContextMenuHandlers\AndroidArchive" /ve /t REG_SZ /d "{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}" /f >nul
reg add "HKLM\SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers\AndroidArchive" /ve /t REG_SZ /d "{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}" /f >nul
reg add "HKLM\SOFTWARE\Classes\Directory\Background\shellex\ContextMenuHandlers\AndroidArchive" /ve /t REG_SZ /d "{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}" /f >nul
reg add "HKLM\SOFTWARE\Classes\Drive\shellex\ContextMenuHandlers\AndroidArchive" /ve /t REG_SZ /d "{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}" /f >nul
reg add "HKLM\SOFTWARE\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers\AndroidArchive" /ve /t REG_SZ /d "{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}" /f >nul

reg add "HKLM\SOFTWARE\Classes\Directory\shell\AndroidArchiveSource" /ve /t REG_SZ /d "Архивировать проект (без сборки)" /f >nul
reg add "HKLM\SOFTWARE\Classes\Directory\shell\AndroidArchiveSource" /v Icon /t REG_SZ /d "C:\Windows\System32\imageres.dll,-102" /f >nul
reg add "HKLM\SOFTWARE\Classes\Directory\shell\AndroidArchiveSource\command" /ve /t REG_SZ /d "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"C:\projects\AndroidArchiver\Archive-Android.ps1\" \"%1\"" /f >nul

reg add "HKLM\SOFTWARE\Classes\Directory\Background\shell\AndroidArchiveSource" /ve /t REG_SZ /d "Архивировать проект (без сборки)" /f >nul
reg add "HKLM\SOFTWARE\Classes\Directory\Background\shell\AndroidArchiveSource" /v Icon /t REG_SZ /d "C:\Windows\System32\imageres.dll,-102" /f >nul
reg add "HKLM\SOFTWARE\Classes\Directory\Background\shell\AndroidArchiveSource\command" /ve /t REG_SZ /d "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"C:\projects\AndroidArchiver\Archive-Android.ps1\" \"%V\"" /f >nul

reg add "HKLM\SOFTWARE\Classes\Drive\shell\AndroidArchiveSource" /ve /t REG_SZ /d "Архивировать проект (без сборки)" /f >nul
reg add "HKLM\SOFTWARE\Classes\Drive\shell\AndroidArchiveSource" /v Icon /t REG_SZ /d "C:\Windows\System32\imageres.dll,-102" /f >nul
reg add "HKLM\SOFTWARE\Classes\Drive\shell\AndroidArchiveSource\command" /ve /t REG_SZ /d "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"C:\projects\AndroidArchiver\Archive-Android.ps1\" \"%1\"" /f >nul

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved" /v "AndroidArchive.ProjectPacker" /t REG_SZ /d "{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}" /f >nul

echo Реестр настроен.

echo.
echo Шаг 3: Перезапуск Проводника...
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 2 /nobreak >nul
start explorer.exe

echo.
echo ========================================
echo  ГОТОВО!
echo ========================================
echo.
echo Пункт "Архивировать проект (без сборки)" должен появиться
echo в контекстном меню при правом клике по папке или файлам.
echo.
pause
