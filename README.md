# Архиватор Android-проектов

Личный архиватор для проектов из Android Studio (Kotlin / Java).
Архивирует выбранное, **исключая сборочный мусор** — `build/`, `.gradle/`, логи, IDE-папки, `.apk`, `.aab`, `.jar` и т.п.
Ключ подписи `*.keystore` / `*.jks` сохраняется всегда.

## Требования

- Windows 10 / 11
- PowerShell 5.1
- Visual Studio 2022 Build Tools (C++ workload) — для сборки `AndroidArchiveCmd.dll`
- Права администратора — для регистрации в `HKLM` (как WinRAR / 7-Zip)

## Установка

### 1. Сборка helper-DLL

```bat
build.bat
```

Ожидается файл `AndroidArchiveCmd.dll` рядом со скриптами.

### 2. Регистрация в системе

**Вариант A — автоматический (рекоменду):**

```powershell
.\Install.ps1
```

Появится запрос UAC — согласитесь. Скрипт:

1. Находит `AndroidArchiveCmd.dll` и `Archive-Android.ps1` в текущей папке.
2. Регистрирует COM-класс `AndroidArchive.ProjectPacker` в `HKLM\SOFTWARE\Classes\CLSID\{a9c1e4f7-...}`.
3. Добавляет контекст-хендлер во вкладках `*`, `Directory`, `Directory\Background`, `Drive`, `AllFilesystemObjects`.
4. Записывает расширение в реестр `Approved`.
5. Создаёт «запасные» legacy-пункты меню для `Directory`, `Directory\Background` и `Drive` (с флагом `-STA`).
6. Вызывает `SHChangeNotify`, чтобы оболочка увидела изменения без перезагрузки.

**Вариант B — ручная машиночная регистрация (только админ):**

```powershell
Register-Machine.ps1
```

Пишет лог в `register.log`.

Название пункта меню: **«Архивировать проект (без сборки)»**.

## Использование

| Способ | Что делает |
|---|---|
| ПКМ по папке проекта | Архивирует всю папку |
| Выделить файлы / папки (`Ctrl+A`) → ПКМ | Архивирует ровно то, что выделено |
| Выделен один файл | Архивирует его, исключая мусор |

Перед архивацией появляется **диалог имени файла** (как в WinRAR).

### Ручной запуск

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Archive-Android.ps1 "C:\projects\MyApp"
powershell -NoProfile -ExecutionPolicy Bypass -File .\Archive-Android.ps1 -OutName "MyArchive" "C:\projects\MyApp"
```

## Что архивируется

| Категория | Включено | Исключено |
|---|---|---|
| Исходники | `.kt`, `.java`, `.cpp`, `.h` | — |
| Ресурсы | `.xml`, `.png`, `.svg`, `.mp3` | — |
| Gradle | `gradle.properties`, `build.gradle*` | `gradle/wrapper/gradle-wrapper.jar`\* |
| Сборка | — | `build/`, `.gradle/`, `obj/` |
| Билд-артефакты | — | `.apk`, `.aab`, `.aar`, `.ap_`, `.so`, `.dll` |
| Логи | — | `*.log`, `*.tmp` |
| IDE | — | `.idea/`, `.vscode/` |
| OS | — | `.DS_Store`, `Thumbs.db` |
| Старые архивы | — | `*_src_*.zip`, `*_selected_*.zip` |
| Keystore | `*.keystore`, `*.jks` | (только без флага `-ExcludeKeys`) |

> \* `gradle-wrapper.jar` всегда сохраняется в архиве — без него нельзя собрать проект на другом ПК.

## Удаление

```powershell
.\Install.ps1 -Uninstall
```

## Структура проекта

| Путь | Описание |
|---|---|
| `Archive-Android.ps1` | Основной скрипт архиватора |
| `Install.ps1` | Установка / удаление (авто-elevate) |
| `Register-Machine.ps1` | Только машиночная регистрация (только админ) |
| `Register-Handlers.ps1` | (устаревший) отдельные хендлеры |
| `src/AndroidArchiveCommand.cpp` | C++ shell-extension — COM-обёртка над `Archive-Android.ps1` |
| `src/AndroidArchiveCmd.def` | Экспорт символов DLL |
| `build.bat` | Сборка DLL через MSVC |
| `pkg/` | Manifest и иконки для MSIX-пакета |
| `install-elevated.bat` | Elevating wrapper для legacy-версий |
| `fix-hkcu.bat`, `fix-tm.bat` | Исправление прав доступа к реестру |

## Коммиты

Пиши на русском — только я читаю 😎
