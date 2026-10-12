# Тест контекстного меню Проводника: открывает меню кликом мыши и читает пункты.
#  powershell -File testmenu2.ps1 multi   - несколько выделенных файлов
#  powershell -File testmenu2.ps1 folder  - одна папка
param([Parameter(Mandatory=$true)][ValidateSet('multi','folder')][string]$Mode)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Native {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
  public const uint RIGHTDOWN = 0x0008;
  public const uint RIGHTUP = 0x0010;
  public const uint LEFTDOWN = 0x0002;
  public const uint LEFTUP = 0x0004;
  public const uint SWP_NOSIZE = 0x0001;
  public const uint SWP_NOMOVE = 0x0002;
  public const uint SWP_SHOWWINDOW = 0x0040;
}
'@

$root = 'C:\projects\_menutest'
$parent = Join-Path $root 'parent'
$child = Join-Path $parent 'child'
[void][System.IO.Directory]::CreateDirectory($child)
[IO.File]::WriteAllText((Join-Path $child 'f1.txt'), 'test1')
[IO.File]::WriteAllText((Join-Path $child 'f2.txt'), 'test2')

# закрыть прежние окна Проводника
Get-Process explorer -EA SilentlyContinue | ForEach-Object {
    try { if ($_.MainWindowTitle) { $_.CloseMainWindow() | Out-Null } } catch {}
}
Start-Sleep 1.5

$openPath = if ($Mode -eq 'multi') { $child } else { $parent }
Start-Process explorer.exe -ArgumentList "`"$openPath`""
Start-Sleep 3

$rootEl = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'CabinetWClass')
$win = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
if (-not $win) { Write-Host 'FAIL: окно Проводника не найдено'; exit 1 }
Write-Host ('окно: [' + $win.Current.Name + ']')

# найти список файлов (элемент List или Tree)
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$list = $null
$stack = New-Object System.Collections.Stack
$stack.Push($win)
while ($stack.Count -gt 0 -and -not $list) {
    $el = $stack.Pop()
    try {
        if ($el.Current.ControlType -eq [System.Windows.Automation.ControlType]::List) { $list = $el; break }
    } catch {}
    try {
        $c = $walker.GetFirstChild($el)
        while ($c) { $stack.Push($c); $c = $walker.GetNextSibling($c) }
    } catch {}
}
if (-not $list) { Write-Host 'FAIL: список файлов не найден'; exit 1 }

# элементы списка
$items = $list.FindAll([System.Windows.Automation.TreeScope]::Children,
    [System.Windows.Automation.Condition]::TrueCondition)
Write-Host ('элементов в списке: ' + $items.Count)
foreach ($it in $items) { Write-Host ('   - [' + $it.Current.Name + ']') }

# активировать окно и поднять наверх
$hwnd = [IntPtr]$win.Current.NativeWindowHandle
[void][Native]::ShowWindow($hwnd, 9)
[void][Native]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0,
    [Native]::SWP_NOSIZE -bor [Native]::SWP_NOMOVE -bor [Native]::SWP_SHOWWINDOW)
[void][Native]::SetForegroundWindow($hwnd)
Start-Sleep 1

function Click-At([double]$x, [double]$y, [uint32]$down, [uint32]$up) {
    [void][Native]::SetCursorPos([int]$x, [int]$y)
    Start-Sleep -Milliseconds 250
    [Native]::mouse_event($down, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [Native]::mouse_event($up, 0, 0, 0, [IntPtr]::Zero)
}

if ($Mode -eq 'multi' -and $items.Count -ge 2) {
    try {
        $si1 = $items[0].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $si1.Select()
        Start-Sleep 400
        $si2 = $items[1].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $si2.AddToSelection()
        Start-Sleep 400
    } catch { Write-Host ('выделение: ' + $_.Exception.Message) }
    # подтвердить выделение кликом по уже выделенному элементу (не сбрасывает)
    try {
        $sel = $list.FindAll([System.Windows.Automation.TreeScope]::Children,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::IsSelectedProperty, $true)))
        Write-Host ('выделено элементов: ' + $sel.Count)
        foreach ($s in $sel) { Write-Host ('   * [' + $s.Current.Name + ']') }
    } catch {}
}
if ($Mode -eq 'folder' -and $items.Count -ge 1) {
    try {
        $si = $items[0].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $si.Select()
        Start-Sleep 300
    } catch {}
}

# целевой элемент для правого клика
$target = if ($Mode -eq 'multi') { $items[[Math]::Min(1, $items.Count - 1)] } else { $items[0] }
$r = $target.Current.BoundingRectangle
if ($r.Width -le 0) { Write-Host 'FAIL: элемент не имеет экранных координат'; exit 1 }
Write-Host ('правый клик по [' + $target.Current.Name + '] at ' + [int]($r.X + 20) + ',' + [int]($r.Y + 5))

# снимок окон ДО открытия меню
function Get-WinSnapshot {
    $s = @{}
    foreach ($w in $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition)) {
        try { $s[$w.Current.NativeWindowHandle] = $w.Current.ClassName } catch {}
    }
    return $s
}
$before = Get-WinSnapshot

Click-At ($r.X + 20) ($r.Y + 5) ([Native]::RIGHTDOWN) ([Native]::RIGHTUP)
Start-Sleep 2.5

# какие окна появились
$after = Get-WinSnapshot
Write-Host '=== новые окна после правого клика ==='
$menuWins = @()
foreach ($k in $after.Keys) {
    if (-not $before.ContainsKey($k)) {
        Write-Host ('   NEW: class=' + $after[$k] + ' handle=' + $k)
        $menuWins += $k
    }
}

# прочитать пункты меню: из новых окон + глобальный поиск по имени
function Get-MenuItems([System.Windows.Automation.AutomationElement]$scope) {
    $res = @()
    $st = New-Object System.Collections.Stack
    $st.Push($scope)
    $depth = 0
    while ($st.Count -gt 0 -and $depth -lt 4000) {
        $el = $st.Pop(); $depth++
        try {
            $ct = $el.Current.ControlType
            if ($ct -eq [System.Windows.Automation.ControlType]::MenuItem -or
                $ct -eq [System.Windows.Automation.ControlType]::ListItem -or
                $ct -eq [System.Windows.Automation.ControlType]::Button) {
                $res += ($ct.ProgrammaticName.Replace('ControlType.','') + ': ' + $el.Current.Name)
            }
        } catch {}
        try {
            $w = [System.Windows.Automation.TreeWalker]::RawViewWalker
            $c = $w.GetFirstChild($el)
            while ($c) { $st.Push($c); $c = $w.GetNextSibling($c) }
        } catch {}
    }
    return $res
}

$found = @()
foreach ($mh in $menuWins) {
    try {
        $mw = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty, [int]$mh)))
        if ($mw) {
            Write-Host ('--- пункты окна class=' + $mw.Current.ClassName + ' ---')
            $its = Get-MenuItems $mw
            foreach ($i in $its) { Write-Host ('    ' + $i) }
            $found += $its
        }
    } catch {}
}

# глобальный поиск по ключевым словам
if ($found.Count -eq 0) {
    Write-Host '=== глобальный поиск ==='
    foreach ($kw in @('*Архивировать*', '*Show more options*', '*Показать дополнительные*')) {
        $c2 = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $kw)
        $res = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Subtree, $c2)
        foreach ($e in $res) {
            try { Write-Host ('    ' + $e.Current.ControlType.ProgrammaticName + ': [' + $e.Current.Name + ']') ; $found += $e.Current.Name } catch {}
        }
    }
    if ($found.Count -eq 0) { Write-Host '    (ничего не найдено - меню не открылось или пустое)' }
}

# закрыть меню клавишей ESC (клик может случайно выбрать пункт)
[Native]::keybd_event(0x1B, 0, 0, [IntPtr]::Zero)
Start-Sleep 100
[Native]::keybd_event(0x1B, 0, 2, [IntPtr]::Zero)
Write-Host ('=== MODE=' + $Mode + ' найдено: ' + $found.Count + ' ===')
