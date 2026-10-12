#Requires -Version 5.1
<#
    Личный архиватор Android-проектов.

    Работает так:
      - Правый клик по папке            -> архивирует всю папку (проект)
      - Выделили файлы/папки (Ctrl+A)   -> архивирует ровно то, что выделено
      - Выделен один файл внутри проекта -> архивирует его, исключая мусор

    Перед архивацией показывается диалог имени файла (как в WinRAR).
    После архивации окно «Открыть папку?» НЕ показывается.

    Что отбрасывается: build, .gradle, node_modules, кэши, IDE-папки, логи, .apk/.aab/.so/.jar.
    Что НЕ отбрасывается: *.keystore / *.jks (ключ подписи Google Play), исходники, ресурсы.

    Ручной запуск:
        powershell -NoProfile -ExecutionPolicy Bypass -File .\Archive-Android.ps1 "C:\projects\MyApp"
        powershell -NoProfile -ExecutionPolicy Bypass -File .\Archive-Android.ps1 "C:\a" "C:\b" "c.kt"
        powershell -NoProfile -ExecutionPolicy Bypass -File .\Archive-Android.ps1 -OutName "MyArchive" "C:\projects\MyApp"
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Path,

    [switch] $UseSelection,
    [string] $OutDir,
    [switch] $KeepGit,
    [switch] $Fast,
    [switch] $NoUi,
    [switch] $Quiet,
    [switch] $DebugList,
    [switch] $ExcludeKeys,
    [switch] $StaRelaunched,
    [switch] $NoNameDialog,
    [string] $OutName,
    [string[]] $ExtraExclude
)

$ErrorActionPreference = 'Stop'
$Script:Base = $PSScriptRoot

# ---------------------------------------------------------------- перезапуск в STA (нужно для COM и WinForms)
if (-not $StaRelaunched -and -not $NoUi) {
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        $self = Join-Path $Script:Base 'Archive-Android.ps1'
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-STA', '-File', $self, '-StaRelaunched')
        if ($UseSelection) { $argList += '-UseSelection' }
        if ($OutDir) { $argList += ('-OutDir "' + $OutDir + '"') }
        if ($KeepGit) { $argList += '-KeepGit' }
        if ($Fast) { $argList += '-Fast' }
        if ($Quiet) { $argList += '-Quiet' }
        if ($ExcludeKeys) { $argList += '-ExcludeKeys' }
        if ($NoNameDialog) { $argList += '-NoNameDialog' }
        if ($OutName) { $argList += ('-OutName "' + $OutName + '"') }
        if ($ExtraExclude) { foreach ($x in $ExtraExclude) { $argList += ('-ExtraExclude "' + $x + '"') } }
        # пути — позиционные (несколько штук), иначе PowerShell жалуется на повтор -Path
        foreach ($p in $Path) { if ($p) { $argList += ('"' + $p + '"') } }
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden
        exit 0
    }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Windows.Forms

# Win32-вызовы, нужные чтобы ГАРАНТИРОВАННО показать окно прогресса
# (подробно - в комментарии перед блоком ShowDialog ниже).
if (-not ('KiloNative.Ui' -as [type])) {
    Add-Type -Namespace KiloNative -Name Ui -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
'@
}

# ---------------------------------------------------------------- чтение выделения в Проводнике
function Get-ExplorerSelection {
    try {
        Add-Type -Namespace KiloNative -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
'@ -ErrorAction SilentlyContinue
        $fg = [KiloNative.Win]::GetForegroundWindow()
        if ($fg -eq [IntPtr]::Zero) { return @() }
        $shell = New-Object -ComObject Shell.Application
        foreach ($w in $shell.Windows()) {
            if ([int64]($w.HWND) -eq [int64]$fg) {
                $out = @()
                try {
                    $doc = $w.Document
                    if ($doc) {
                        foreach ($si in $doc.SelectedItems()) {
                            if ($si.Path) { $out += $si.Path }
                        }
                    }
                } catch { }
                if ($out.Count -gt 0) { return $out }
            }
        }
    } catch { }
    return @()
}

# ---------------------------------------------------------------- списки исключений
$script:ExclDirs = @(
    # сборка
    'build', 'Build', 'out', 'output', 'outputs', '.output', 'dist-newstyle',
    'intermediates', 'CMakeFiles', 'cmake-build-debug', 'cmake-build-release',
    'merged.dir', 'stripped.dir', 'dexBuilder', 'packageDebugResources', 'generateDebugRFile',
    '.cxx', '.externalNativeBuild', '.externalNativeBuildOutput',
    # gradle / kotlin / android кэши
    '.gradle', '.kotlin', '.konan', '.caches', 'captures',
    # зависимости
    'node_modules', 'Pods', '.symlinks', 'bower_components', '.pub-cache', '.pub',
    # flutter / dart
    '.dart_tool', '.flutter-plugins', '.flutter-plugins-dependencies', '.packages', '.fvm',
    # кэши инструментов
    '.cache', '.npm', '.nyc_output', 'coverage', '.firebase', '.expo', '.angular', '.parcel-cache',
    '.turbo', '.svelte-kit', '.next', '.nuxt', '.vercel', '.netlify', '.pytest_cache', '.mypy_cache',
    '__pycache__', '.tox', '.ipynb_checkpoints', '.sass-cache', '.terraform', '.serverless',
    # IDE / ОС
    '.git', '.idea', '.vs', '.vscode', '.fleet', '.history', '.gradle-cache',
    # временное
    'tmp', 'temp', 'logs', 'log', '.logs', 'tmp-cache', 'zip-cache', 'screenshots', '__screenshots__'
)
if ($KeepGit) { $script:ExclDirs = $script:ExclDirs | Where-Object { $_ -ne '.git' } }
if ($ExcludeKeys) { $script:ExclFilesExtra = @('*.keystore', '*.jks', '*.p12', '*.pfx', 'key.properties') }
else { $script:ExclFilesExtra = @() }

$script:ExclFiles = @(
    'local.properties', 'local.defaults.properties',
    '.DS_Store', 'Thumbs.db', 'desktop.ini', 'ehthumbs.db', '.env.local',
    'npm-debug.log*', 'yarn-error.log*', 'yarn-debug.log*', 'firebase-debug*.log*',
    '*.log', '*.tmp', '*.temp', '*.bak', '*.old', '*.orig', '*.rej', '*.pid', '*.seed', '*.pid.lock',
    '*.hprof', '*.gcda', '*.gcno', '*.prof', '*.trace',
    '*.apk', '*.aab', '*.ap_', '*.aar', '*.ipa', '*.msi', '*.exe', '*.dll', '*.so', '*.dylib', '*.jar',
    # свои прошлые архивы — иначе старые zip попадут в новый
    '*_src_*.zip', '*_selected_*.zip'
) + $script:ExclFilesExtra
# ВАЖНО: *.keystore / *.jks / *.p12 / *.pfx исключаются только с ключом -ExcludeKeys.
# Это ключ подписи для Google Play: без него обновить приложение в Play нельзя.

$script:ExclPaths = @(
    '**/node_modules/*', '.git/*', 'ios/Pods/*', 'macos/Pods/*'
)

function Import-ProjectExcludes([string] $baseDir) {
    $f = Join-Path $baseDir '.android-archive-exclude.txt'
    if (-not (Test-Path -LiteralPath $f)) { return }
    foreach ($line in [System.IO.File]::ReadAllLines($f)) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        if ($l.EndsWith('/')) { $script:ExclDirs += $l.TrimEnd('/').Split('/')[-1] }
        else { $script:ExclFiles += $l }
    }
}

function ConvertTo-Wildcard([string] $pattern) {
    $p = $pattern -replace '^\*\*/', ''
    $p = $p -replace '\*\*', '*'
    return $p
}
$script:ExclPathWc = $script:ExclPaths | ForEach-Object { ConvertTo-Wildcard $_ }

function Test-ExcludedDir([string] $name) {
    foreach ($d in $script:ExclDirs) { if ($name -ieq $d) { return $true } }
    return $false
}
function Test-ExcludedFile([string] $name, [string] $rel) {
    # gradle-wrapper.jar нужен для пересборки на другом ПК — не исключаем даже при *.jar
    if ($name -eq 'gradle-wrapper.jar') { return $false }
    foreach ($p in $script:ExclFiles) { if ($name -like $p) { return $true } }
    $relWc = $rel -replace '\\', '/'
    foreach ($p in $script:ExclPathWc) { if ($relWc -like $p) { return $true } }
    return $false
}

# ---------------------------------------------------------------- progress UI
$script:UI = $null
$script:Cancelled = $false
$script:WorkDone = $false
$script:WorkStarted = $false
function New-ProgressUi {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Архиватор Android-проектов'
    $f.ClientSize = New-Object System.Drawing.Size(560, 160)
    $f.StartPosition = 'CenterScreen'
    $f.TopMost = $true
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false

    $l1 = New-Object System.Windows.Forms.Label
    $l1.Text = 'Сканирование...'
    $l1.AutoSize = $true; $l1.Location = New-Object System.Drawing.Point(16, 18)
    $l1.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $pb = New-Object System.Windows.Forms.ProgressBar
    $pb.Location = New-Object System.Drawing.Point(16, 52)
    $pb.Size = New-Object System.Drawing.Size(528, 22)
    $pb.Style = 'Marquee'; $pb.MarqueeAnimationSpeed = 30

    $l2 = New-Object System.Windows.Forms.Label
    $l2.Text = ''
    $l2.AutoSize = $false
    $l2.Location = New-Object System.Drawing.Point(16, 84)
    $l2.Size = New-Object System.Drawing.Size(528, 44)

    $cb = New-Object System.Windows.Forms.Button
    $cb.Text = 'Отмена'
    $cb.Size = New-Object System.Drawing.Size(110, 30)
    $cb.Location = New-Object System.Drawing.Point(434, 128)

    $f.Controls.AddRange(@($l1, $pb, $l2, $cb))
    $cb.Add_Click({ $script:Cancelled = $true; if ($script:UI) { $script:UI.Cancelling = $true } })
    # Крестик = отмена: окно открывается модально, поэтому закрыть его
    # можно только через "Отмена" или крестик - и то с остановкой работы.
    $f.Add_FormClosing({
        if (-not $script:WorkDone) {
            $script:Cancelled = $true
            if ($script:UI) { $script:UI.Cancelling = $true }
        }
    })
    $ui = [pscustomobject]@{ Form = $f; Title = $l1; Bar = $pb; Detail = $l2; Cancelling = $false }
    $script:UI = $ui
    # Окно НЕ показываем здесь: оно откроется модально через ShowDialog()
    # сразу после регистрации Add_Shown (иначе Work не успеет подцепиться).
    return $ui
}
function Update-ProgressUi([string] $title, [long] $current, [long] $total, [string] $detail) {
    if (-not $script:UI) { return }
    try {
        $ui = $script:UI
        if ($total -gt 0) {
            $ui.Bar.Style = 'Continuous'
            $ui.Bar.Maximum = 1000
            $pct = [int](1000.0 * $current / $total)
            $ui.Bar.Value = [Math]::Max(0, [Math]::Min(1000, $pct))
        }
        $ui.Title.Text = $title
        if ($detail) { $ui.Detail.Text = $detail }
        [System.Windows.Forms.Application]::DoEvents()
    } catch { }
}
function Close-ProgressUi {
    if ($script:UI) { try { $script:UI.Form.Close(); $script:UI.Form.Dispose() } catch { }; $script:UI = $null }
}

# ---------------------------------------------------------------- диалог имени файла (как в WinRAR)
function Show-NameDialog([string] $defaultName) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Сохранение архива'
    $form.ClientSize = New-Object System.Drawing.Size(420, 130)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.ShowInTaskbar = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Имя файла архива:'
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(12, 12)
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(12, 36)
    $textBox.Size = New-Object System.Drawing.Size(396, 25)
    $textBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $textBox.Text = $defaultName
    $textBox.SelectAll()

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Файл сохранится в ту же папку'
    $hint.AutoSize = $true
    $hint.ForeColor = [System.Drawing.Color]::Gray
    $hint.Location = New-Object System.Drawing.Point(12, 66)
    $hint.Font = New-Object System.Drawing.Font('Segoe UI', 8)

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = 'Сохранить'
    $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $okBtn.Location = New-Object System.Drawing.Point(220, 92)
    $okBtn.Size = New-Object System.Drawing.Size(95, 30)
    $okBtn.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = 'Отмена'
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelBtn.Location = New-Object System.Drawing.Point(313, 92)
    $cancelBtn.Size = New-Object System.Drawing.Size(95, 30)
    $cancelBtn.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $form.Controls.AddRange(@($label, $textBox, $hint, $okBtn, $cancelBtn))
    $form.AcceptButton = $okBtn
    $form.CancelButton = $cancelBtn

    $result = $form.ShowDialog()
    $form.Dispose()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $textBox.Text
    }
    return $null
}

# ---------------------------------------------------------------- сбор файлов
function Get-ArchiveFiles([string[]] $roots, [string] $baseFull, [string] $outDirFull) {
    $files = [System.Collections.Generic.List[object]]::new()
    $emptyDirs = [System.Collections.Generic.List[string]]::new()
    $skipped = 0
    $dirsSeen = 0
    $bytesSeen = 0L
    $lastUi = [DateTime]::MinValue
    $baseFull = $baseFull.TrimEnd('\') + '\'
    $stack = [System.Collections.Generic.Stack[string]]::new()
    foreach ($r in $roots) {
        # корень-файл (выделен конкретный файл) — добавляем сразу, рекурсии нет
        if ([System.IO.File]::Exists($r)) {
            $fname = [System.IO.Path]::GetFileName($r)
            if ($r.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                $frel = $r.Substring($baseFull.Length).Replace('\', '/')
                if (-not (Test-ExcludedFile $fname $frel)) {
                    $fi = $null
                    try { $fi = New-Object System.IO.FileInfo $r } catch { }
                    if ($fi) {
                        $files.Add([pscustomobject]@{
                            Full = $fi.FullName; Rel = $frel; Size = $fi.Length; Time = $fi.LastWriteTime
                        })
                        $bytesSeen += $fi.Length
                    }
                } else { $skipped++ }
            }
            continue
        }
        $stack.Push($r)
    }

    # Архив создаётся ПОСЛЕ сканирования, а прошлые архивы отсекаются по маске
    # (*_src_*.zip / *_selected_*.zip) — поэтому рекурсию ничего резать не нужно.

    while ($stack.Count -gt 0) {
        if ($script:Cancelled) { break }
        $dir = $stack.Pop()
        $dirFull = $dir + '\'

        $filesHere = 0
        try { $entries = [System.IO.Directory]::EnumerateFileSystemEntries($dir) } catch { continue }
        foreach ($e in $entries) {
            if ($script:Cancelled) { break }
            try { $attr = [System.IO.File]::GetAttributes($e) } catch { continue }
            if ($attr -band [System.IO.FileAttributes]::ReparsePoint) { continue }

            if ($attr -band [System.IO.FileAttributes]::Directory) {
                $name = [System.IO.Path]::GetFileName($e)
                if (Test-ExcludedDir $name) { $skipped++; continue }
                $stack.Push($e)
            } else {
                $name = [System.IO.Path]::GetFileName($e)
                if (-not $e.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $rel = $e.Substring($baseFull.Length).Replace('\', '/')
                if (Test-ExcludedFile $name $rel) { $skipped++; continue }
                $fi = $null
                try { $fi = New-Object System.IO.FileInfo $e } catch { }
                if (-not $fi) { continue }
                $files.Add([pscustomobject]@{
                    Full = $e; Rel = $rel; Size = $fi.Length; Time = $fi.LastWriteTime
                })
                $bytesSeen += $fi.Length
                $filesHere++
            }
        }
        $dirsSeen++
        # Периодически "оживляем" окно: без DoEvents прогресс-бар замирает
        # и создаётся впечатление, что скрипт завис.
        if ($script:UI) {
            $now = [DateTime]::Now
            if (($now - $lastUi).TotalMilliseconds -ge 150) {
                $lastUi = $now
                $cur = $dir
                if ($cur.Length -gt 58) { $cur = '...' + $cur.Substring($cur.Length - 55) }
                $elapsed = if ($script:sw) { [Math]::Round($script:sw.Elapsed.TotalSeconds, 1) } else { 0 }
                $line1 = 'Папок: {0}    Файлов: {1}    Пропущено: {2}    {3} МБ    {4} с' -f `
                    $dirsSeen, $files.Count, $skipped, [Math]::Round($bytesSeen / 1MB, 1), $elapsed
                Update-ProgressUi 'Сканирование проекта...' 0 0 ($line1 + "`r`n" + $cur)
            }
        }
        if ($filesHere -eq 0 -and $dirFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            $emptyDirs.Add($dirFull.Substring($baseFull.Length).Replace('\', '/').TrimEnd('/'))
        }
    }

    return [pscustomobject]@{ Files = $files; EmptyDirs = $emptyDirs; Skipped = $skipped }
}

function Get-CommonParent([string[]] $paths) {
    $split = @()
    foreach ($p in $paths) {
        $dir = if ($p.EndsWith('\')) { $p.TrimEnd('\') } else { [System.IO.Path]::GetDirectoryName($p) }
        $split += , @(if ($dir) { $dir -split '\\' } else { @() })
    }
    $common = @()
    for ($i = 0; $i -lt $split[0].Count; $i++) {
        $seg = $split[0][$i]
        $same = $true
        foreach ($s in $split) {
            if ($i -ge $s.Count -or $s[$i] -ine $seg) { $same = $false; break }
        }
        if (-not $same) { break }
        $common += $seg
    }
    return ($common -join '\')
}

# ---------------------------------------------------------------- основной сценарий
$inputs = @()
if ($UseSelection) {
    $sel = Get-ExplorerSelection
    if ($sel.Count -gt 0) { $inputs = $sel }
}
foreach ($p in $Path) { if ($p) { $inputs += $p } }

$items = @()
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($p in $inputs) {
    try { $it = Get-Item -LiteralPath $p -ErrorAction Stop } catch { continue }
    $full = $it.FullName
    if ($seen.Add($full)) { $items += $it }
}
if ($items.Count -eq 0) { throw 'Нечего архивировать: не найдено ни одного файла или папки.' }

# --- определяем базу и корни
$dirItems = @($items | Where-Object { $_.PSIsContainer })
$fileItems = @($items | Where-Object { -not $_.PSIsContainer })

$rulesBase = if ($items[0].PSIsContainer) { $items[0].Parent.FullName } else { [System.IO.Path]::GetDirectoryName($items[0].FullName) }
if (-not $rulesBase) { $rulesBase = [System.IO.Path]::GetDirectoryName($items[0].FullName) }
Import-ProjectExcludes $rulesBase
if ($ExtraExclude) {
    foreach ($x in $ExtraExclude) {
        if ($x.EndsWith('/')) { $script:ExclDirs += $x.TrimEnd('/').Split('/')[-1] }
        else { $script:ExclFiles += $x }
    }
}

$projectMode = $false
if ($dirItems.Count -eq 1 -and $fileItems.Count -eq 0) {
    # ровно одна папка -> архивируем её целиком как проект
    $projectMode = $true
    $base = $dirItems[0].FullName.TrimEnd('\')
    $roots = @($dirItems[0].FullName)
    $prefix = $dirItems[0].Name
} else {
    $all = @()
    foreach ($i in $items) { $all += $i.FullName }
    $parent = Get-CommonParent $all
    if (-not $parent) { $parent = [System.IO.Path]::GetDirectoryName($all[0]) }
    $base = $parent.TrimEnd('\')
    $prefix = ''
    $roots = @()
    foreach ($d in $dirItems) { if (-not (Test-ExcludedDir $d.Name)) { $roots += $d.FullName } }
    foreach ($f in $fileItems) {
        $rel = $f.FullName.Substring($base.Length).TrimStart('\').Replace('\', '/')
        if (-not (Test-ExcludedFile $f.Name $rel)) { $roots += $f.FullName }
    }
    if ($roots.Count -eq 0) { throw 'Всё выделенное попало под исключения (сборка/кэш/мусор).' }
}

$now = Get-Date
$ruMonths = @('ЯНВ','ФЕВ','МАР','АПР','МАЙ','ИЮН','ИЮЛ','АВГ','СЕН','ОКТ','НБР','ДЕК')
$stamp = '{0} {1} {2}г {3}ч {4}мин' -f $now.Day, $ruMonths[$now.Month - 1], $now.ToString('yy'), $now.Hour, $now.Minute
# Имя архива по умолчанию: имя папки + дата (без слова "selected")
if ($projectMode) {
    $zipName = '{0}_{1}.zip' -f [System.IO.Path]::GetFileName($base), $stamp
} elseif ($items.Count -eq 1) {
    $it0 = $items[0]
    $nm = if ($it0.PSIsContainer) { $it0.Name } else { $it0.BaseName }
    $zipName = '{0}_{1}.zip' -f $nm, $stamp
} else {
    $zipName = '{0}_{1}.zip' -f [System.IO.Path]::GetFileName($base), $stamp
}

# Диалог имени файла (как в WinRAR) — пользователь может переименовать
if ($OutName) {
    $zipName = $OutName
    if (-not $zipName.EndsWith('.zip', [System.StringComparison]::OrdinalIgnoreCase)) { $zipName += '.zip' }
} elseif (-not $NoNameDialog -and -not $NoUi -and -not $Quiet -and -not $DebugList) {
    $entered = Show-NameDialog $zipName
    if ($null -eq $entered -or $entered.Trim() -eq '') { exit 0 }
    $zipName = $entered.Trim()
    if (-not $zipName.EndsWith('.zip', [System.StringComparison]::OrdinalIgnoreCase)) { $zipName += '.zip' }
}
# Архив кладём В ту же папку, откуда выделили (или внутрь проекта при клике по папке)
$targetDir = if ($OutDir) { $OutDir } else { $base }
if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
$zipPath = Join-Path $targetDir $zipName
$outDirFull = (Get-Item -LiteralPath $targetDir).FullName

if (-not $NoUi) { [void](New-ProgressUi) }

# Вся работа идёт ВНУТРИ модального окна (ShowDialog + Add_Shown):
# окно показывается первым, дальше крутится прогресс, сообщения обрабатываются
# через DoEvents, поэтому окно живое и всегда сверху, пока идёт архивация.
$script:Work = {
$script:sw = [System.Diagnostics.Stopwatch]::StartNew()
$sw = $script:sw
$script:errors = [System.Collections.Generic.List[string]]::new()
$errors = $script:errors
$script:scan = $null
$zip = $null
$fs = $null

try {
    Update-ProgressUi 'Сканирование проекта...' 0 0 ("Выделено: " + $items.Count + "  элем.")
    $scan = Get-ArchiveFiles $roots $base $outDirFull
    $script:scan = $scan
    if ($DebugList) {
        $scan.Files | ForEach-Object { Write-Host "  $($_.Rel)" }
        $script:WorkDone = $true
        if ($script:UI) { $script:UI.Form.Close() }
        return
    }
    $files = $scan.Files
    $totalBytes = 0L
    foreach ($f in $files) { $totalBytes += $f.Size }
    Update-ProgressUi 'Упаковка...' 0 $totalBytes (
        ('Найдено файлов: {0}    {1} МБ    Сканирование: {2} с' -f $files.Count, [Math]::Round($totalBytes / 1MB, 1), [Math]::Round($sw.Elapsed.TotalSeconds, 1)) +
        "`r`nПропущено мусора: $($scan.Skipped)")

    $level = if ($Fast) { [System.IO.Compression.CompressionLevel]::Fastest } else { [System.IO.Compression.CompressionLevel]::Optimal }
    $fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create, $true)

    $done = 0L; $lastUi = [DateTime]::MinValue; $i = 0
    # Один общий буфер на все файлы: раньше он выделялся на КАЖДЫЙ файл,
    # то есть 52000 аллокаций по 1 МБ - сильное давление на сборщик мусора.
    $buf = New-Object byte[] 1048576
    foreach ($f in $files) {
        if ($script:Cancelled) { break }
        if ($script:UI -and $script:UI.Cancelling) { $script:Cancelled = $true; break }
        $i++
        $entryName = if ($prefix) { "$prefix/$($f.Rel)" } else { $f.Rel }
        try {
            $entry = $zip.CreateEntry($entryName, $level)
            if ($f.Time -and $f.Time.Year -gt 1980) { try { $entry.LastWriteTime = $f.Time } catch { } }
            $es = $entry.Open()
            $src = [System.IO.File]::Open($f.Full, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                while (($read = $src.Read($buf, 0, $buf.Length)) -gt 0) { $es.Write($buf, 0, $read) }
            } finally { $src.Dispose(); $es.Dispose() }
        } catch {
            if ($errors.Count -lt 40) { $errors.Add($f.Rel + ' :: ' + $_.Exception.Message) }
        }
        $done += $f.Size
        $now = [DateTime]::Now
        if (($now - $lastUi).TotalMilliseconds -ge 120) {
            $lastUi = $now
            $short = if ($f.Rel.Length -gt 70) { '...' + $f.Rel.Substring($f.Rel.Length - 67) } else { $f.Rel }
            $line1 = 'Файл {0} из {1}    {2} из {3} МБ    {4}%    {5} с' -f `
                $i, $files.Count, [Math]::Round($done / 1MB, 1), [Math]::Round($totalBytes / 1MB, 1), `
                $(if ($totalBytes -gt 0) { [int](100 * $done / $totalBytes) } else { 0 }), `
                [Math]::Round($sw.Elapsed.TotalSeconds, 1)
            Update-ProgressUi ('Упаковка {0}/{1}' -f $i, $files.Count) $done $totalBytes ($line1 + "`r`n" + $short)
        }
    }

    foreach ($d in $scan.EmptyDirs) {
        if ($script:Cancelled) { break }
        if (-not $d) { continue }
        $dn = if ($prefix) { "$prefix/$d" } else { $d }
        try { [void]$zip.CreateEntry($dn.TrimEnd('/') + '/') } catch { }
    }

    $infoName = if ($prefix) { "$prefix/_ARCHIVE_INFO.txt" } else { '_ARCHIVE_INFO.txt' }
    $info = $zip.CreateEntry($infoName)
    $hasKey = [bool](@($files | Where-Object { $_.Rel -match '\.(keystore|jks|p12|pfx)$' }).Count -gt 0)
    $txt = @"
Личный архиватор Android-проектов
Дата:        $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Источник:    $base
Выделено:    $($items.Count) элем. -> архивировано файлов: $($files.Count)
Пропущено:   $($scan.Skipped) (сборка/кэш/IDE/логи/мусор)
Git-история: $(if ($KeepGit) { 'сохранена' } else { 'НЕ включена (.git исключён)' })
Ключ подписи Google Play (.keystore/.jks): $(if ($hasKey) { 'НАЙДЕН и ВКЛЮЧЁН в архив' } else { 'в архиве НЕ найден' })

Ключ подписи (.keystore / .jks) НЕ отбрасывается архиватором: без него
нельзя выпустить обновление в Google Play. Если его нет - поищите в
C:\Users\%USERNAME%\.android\ или в резервной копии.

Как восстановить:
  1. Распакуйте архив в пустую папку.
  2. Появится $(if ($prefix) { "папка `"$prefix`"" } else { 'содержимое с теми же именами' }) и структурой.
  3. Откройте проект в Android Studio и дождитесь первой сборки - все
     сборочные папки (build, .gradle, node_modules) скачаются заново само.
  4. Если не собирается - удалите local.properties (не архивируется,
     содержит абсолютные пути к SDK этого компьютера) или откройте проект заново.
"@
    $is = $info.Open()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($txt)
    $is.Write($bytes, 0, $bytes.Length)
    $is.Dispose()
}
catch { $errors.Add('FATAL: ' + $_.Exception.Message) }
finally {
    # WorkDone ставим ДО закрытия окна, иначе FormClosing решит,
    # что крестик нажали для отмены, и готовый архив удалят.
    $script:WorkDone = $true
    if ($zip) { try { $zip.Dispose() } catch { } }
    if ($fs) { try { $fs.Dispose() } catch { } }
    $sw.Stop()
    Close-ProgressUi
}
}   # конец $script:Work

# Модальный показ окна.
#
# ПОЧЕМУ РАБОТА СТАРТУЕТ С ТАЙМЕРА, А НЕ ИЗ Add_Shown:
# ShowDialog() сначала вызывает SetVisibleCore(true), внутри которого срабатывает
# событие Shown, и только ПОТОМ делает ShowWindow и входит в цикл сообщений.
# Раньше вся архивация выполнялась внутри Shown, из-за чего:
#   * окно уже существовало, но НЕ БЫЛО ВИДНО на экране (ShowWindow ещё не зван) -
#     пользователь вообще не видел ни окно, ни прогресс-бар;
#   * Close() в finally вызывался вне цикла сообщений, и после готовности архива
#     процесс висел десятки минут (факт: ~4000 с при 9 минутах работы).
# Тик таймера приходит уже из цикла сообщений ShowDialog, то есть строго после
# того, как окно показано. Плюс явный ShowWindow - страховка на случай, если
# WinForms "решил", что окно и так видимо (ранний выход из SetVisibleCore).
if ($script:UI) {
    $uiTimer = New-Object System.Windows.Forms.Timer
    $uiTimer.Interval = 50
    $uiTimer.Add_Tick({
        $uiTimer.Stop()
        $uiTimer.Dispose()
        $script:WorkStarted = $true
        if ($script:UI) {
            try {
                $h = $script:UI.Form.Handle
                [KiloNative.Ui]::ShowWindow($h, 5) | Out-Null           # SW_SHOW
                [KiloNative.Ui]::SetForegroundWindow($h) | Out-Null
            } catch { }
        }
        & $script:Work
    })
    $uiTimer.Start()
    try { [void]$script:UI.Form.ShowDialog() } catch { }
    try { $uiTimer.Dispose() } catch { }
    # страховка: ShowDialog вернулся, а работа так и не началась
    if (-not $script:WorkStarted) { $script:WorkStarted = $true; & $script:Work }
} else {
    $script:WorkStarted = $true
    & $script:Work
}

if ($script:Cancelled) {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue }
    if (-not $Quiet) { [System.Windows.Forms.MessageBox]::Show('Архивирование отменено.', 'Архиватор', 'OK', 'Information') | Out-Null }
    exit 1
}

if ($script:errors -and $script:errors.Count -gt 0) {
    $logDir = Join-Path $targetDir 'archive-logs'
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logFile = Join-Path $logDir ('{0}_{1}.log' -f $zipName, $stamp)
    (@("Ошибки архивирования: $base", ('-' * 60)) + $script:errors) | Set-Content -LiteralPath $logFile -Encoding UTF8
}

if (-not $script:scan) { Write-Host 'Архив не создан: сканирование не дало результатов.'; exit 1 }
$zipInfo = Get-Item -LiteralPath $zipPath
$mb = [Math]::Round($zipInfo.Length / 1MB, 1)
$sec = [Math]::Round($script:sw.Elapsed.TotalSeconds, 1)
Write-Host ''
Write-Host "Готово: $zipPath  ($mb МБ, $sec с)"
exit 0