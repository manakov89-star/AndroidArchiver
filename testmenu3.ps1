# Тест контекстного меню Проводника (без закрытия чужих окон).
#  powershell -File testmenu3.ps1 multi|folder
param([Parameter(Mandatory=$true)][ValidateSet('multi','folder')][string]$Mode)

$ErrorActionPreference = 'Stop'
$LogFile = 'C:\projects\AndroidArchiver\menu-' + $Mode + '-step.log'
'=== start ' + (Get-Date -Format 'HH:mm:ss') + ' mode=' + $Mode + ' ===' | Set-Content -LiteralPath $LogFile -Encoding UTF8
function Log([string]$m) { Add-Content -LiteralPath $LogFile -Value ((Get-Date -Format 'HH:mm:ss') + '  ' + $m) -Encoding UTF8 }
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class N {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  public const uint LD = 0x0002, LU = 0x0004, RD = 0x0008, RU = 0x0010;
  public const uint SWP_NOSIZE = 1, SWP_NOMOVE = 2, SWP_SHOWWINDOW = 0x40;
}
'@

$root = 'C:\projects\_menutest'
$parent = Join-Path $root 'parent'
$child = Join-Path $parent 'child'
[void][System.IO.Directory]::CreateDirectory($child)
[IO.File]::WriteAllText((Join-Path $child 'f1.txt'), 'test1')
[IO.File]::WriteAllText((Join-Path $child 'f2.txt'), 'test2')

$openPath = if ($Mode -eq 'multi') { $child } else { $parent }
Start-Process explorer.exe -ArgumentList "`"$openPath`""
Start-Sleep 3

$rootEl = [System.Windows.Automation.AutomationElement]::RootElement
$cw = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'CabinetWClass')
$wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $cw)
# выбрать окно с нужным заголовком
$win = $null
foreach ($w in $wins) { if ($w.Current.Name -match 'child|parent') { $win = $w } }
if (-not $win) { Write-Host 'FAIL: окно не найдено'; Log 'FAIL: окно не найдено'; exit 1 }
Write-Host ('окно: [' + $win.Current.Name + ']')
Log ('окно: [' + $win.Current.Name + ']')

$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$list = $null
$stack = New-Object System.Collections.Stack
$stack.Push($win)
while ($stack.Count -gt 0 -and -not $list) {
    $el = $stack.Pop()
    try { if ($el.Current.ControlType -eq [System.Windows.Automation.ControlType]::List) { $list = $el; break } } catch {}
    try { $c = $walker.GetFirstChild($el); while ($c) { $stack.Push($c); $c = $walker.GetNextSibling($c) } } catch {}
}
if (-not $list) { Write-Host 'FAIL: список не найден'; Log 'FAIL: список не найден'; exit 1 }
$items = $list.FindAll([System.Windows.Automation.TreeScope]::Children,
    [System.Windows.Automation.Condition]::TrueCondition)
Write-Host ('элементов: ' + $items.Count)
Log ('элементов: ' + $items.Count)
foreach ($it in $items) { Write-Host ('   - [' + $it.Current.Name + ']'); Log ('   - [' + $it.Current.Name + ']') }
Log 'активация окна...'

$hwnd = [IntPtr]$win.Current.NativeWindowHandle
[void][N]::ShowWindow($hwnd, 9)
[void][N]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, [N]::SWP_NOSIZE -bor [N]::SWP_NOMOVE -bor [N]::SWP_SHOWWINDOW)
[void][N]::SetForegroundWindow($hwnd)
Start-Sleep 800
Log 'окно активировано'

function Click([double]$x, [double]$y, [uint32]$d, [uint32]$u) {
    Log ('click ' + [int]$x + ',' + [int]$y + ' f=' + $d)
    [void][N]::SetCursorPos([int]$x, [int]$y)
    Start-Sleep -Milliseconds 300
    [N]::mouse_event($d, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 90
    [N]::mouse_event($u, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 500
}

if ($items.Count -eq 0) { Write-Host 'FAIL: пустой список'; exit 1 }

$r0 = $items[0].Current.BoundingRectangle
if ($Mode -eq 'folder') {
    Click ($r0.X + 20) ($r0.Y + 5) ([N]::LD) ([N]::LU)     # левый клик = выделить
} else {
    Click ($r0.X + 20) ($r0.Y + 5) ([N]::LD) ([N]::LU)     # первый файл
    if ($items.Count -ge 2) {
        $r1 = $items[1].Current.BoundingRectangle
        [N]::keybd_event(0x11, 0, 0, [IntPtr]::Zero)        # Ctrl down
        Start-Sleep -Milliseconds 200
        Click ($r1.X + 20) ($r1.Y + 5) ([N]::LD) ([N]::LU)  # второй файл
        [N]::keybd_event(0x11, 0, 2, [IntPtr]::Zero)        # Ctrl up
        Start-Sleep -Milliseconds 300
    }
}

# проверить выделение
Log 'проверка выделения...'
$sel = $list.FindAll([System.Windows.Automation.TreeScope]::Children,
    (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::IsSelectedProperty, $true)))
Write-Host ('выделено: ' + $sel.Count)
Log ('выделено: ' + $sel.Count)
foreach ($s in $sel) { Write-Host ('   * [' + $s.Current.Name + ']'); Log ('   * [' + $s.Current.Name + ']') }

# снимок окон до меню
function Snap {
    $h = @{}
    foreach ($w in $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition)) {
        try { $h[[int]$w.Current.NativeWindowHandle] = $w.Current.ClassName } catch {}
    }
    $h
}
$before = Snap
Log ('снимок окон: ' + $before.Count + ' шт')

# правый клик по последнему выделенному
$rt = $items[[Math]::Min(1, $items.Count - 1)].Current.BoundingRectangle
Write-Host ('правый клик: ' + [int]($rt.X + 20) + ',' + [int]($rt.Y + 5))
Log ('правый клик: ' + [int]($rt.X + 20) + ',' + [int]($rt.Y + 5))
Click ($rt.X + 20) ($rt.Y + 5) ([N]::RD) ([N]::RU)
Start-Sleep 2
Log 'правый клик выполнен'

$after = Snap
Write-Host '=== новые окна ==='
$menuWins = @()
foreach ($k in $after.Keys) {
    if (-not $before.ContainsKey($k)) {
        Write-Host ('   NEW class=' + $after[$k] + ' hwnd=' + $k)
        Log ('   NEW class=' + $after[$k] + ' hwnd=' + $k)
        $menuWins += $k
    }
}
Log ('новых окон: ' + $menuWins.Count)

function Dump($scope) {
    $res = @()
    $st = New-Object System.Collections.Stack
    $st.Push($scope)
    $n = 0
    while ($st.Count -gt 0 -and $n -lt 5000) {
        $el = $st.Pop(); $n++
        try {
            $ct = $el.Current.ControlType
            if ($ct -eq [System.Windows.Automation.ControlType]::MenuItem -or
                $ct -eq [System.Windows.Automation.ControlType]::ListItem) {
                $res += ($ct.ProgrammaticName.Replace('ControlType.','') + ': [' + $el.Current.Name + ']')
            }
        } catch {}
        try {
            $w = [System.Windows.Automation.TreeWalker]::RawViewWalker
            $c = $w.GetFirstChild($el)
            while ($c) { $st.Push($c); $c = $w.GetNextSibling($c) }
        } catch {}
    }
    $res
}

$found = @()
foreach ($mh in $menuWins) {
    try {
        $mw = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty, $mh)))
        if ($mw) {
            Write-Host ('--- пункты окна ' + $mw.Current.ClassName + ' [' + $mw.Current.Name + '] ---')
            Log ('--- пункты окна ' + $mw.Current.ClassName + ' ---')
            $its = Dump $mw
            foreach ($i in $its) { Write-Host ('    ' + $i); Log ('    ' + $i) }
            $found += $its
        }
    } catch { Write-Host ('чтение окна: ' + $_.Exception.Message) }
}

if ($found.Count -eq 0) {
    Write-Host '=== ключевые слова в дереве ==='
    foreach ($kw in @('*Архивировать*', '*WinRAR*', '*Show more options*', '*Показать дополнительные*')) {
        $c2 = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $kw)
        try {
            $res = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Subtree, $c2)
            foreach ($e in $res) {
                try { Write-Host ('    ' + $e.Current.ControlType.ProgrammaticName + ': [' + $e.Current.Name + ']'); Log ('    ' + $e.Current.ControlType.ProgrammaticName + ': [' + $e.Current.Name + ']'); $found += $e.Current.Name } catch {}
            }
        } catch { Write-Host ('поиск ' + $kw + ': ' + $_.Exception.Message) }
    }
    if ($found.Count -eq 0) { Write-Host '    (меню не найдено)' }
}

[N]::keybd_event(0x1B, 0, 0, [IntPtr]::Zero)
Start-Sleep 100
[N]::keybd_event(0x1B, 0, 2, [IntPtr]::Zero)
Write-Host ('=== MODE=' + $Mode + ' итог: ' + $found.Count + ' ===')
Log ('=== итог: ' + $found.Count + ' ===')
