# Читает контекстное меню Проводника через UI Automation.
# Использование:  powershell -File testmenu.ps1 multi   (несколько файлов)
#                 powershell -File testmenu.ps1 folder  (одна папка)
param([Parameter(Mandatory=$true)][ValidateSet('multi','folder')][string]$Mode)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

$root = 'C:\projects\_menutest'
$parent = Join-Path $root 'parent'
$child = Join-Path $parent 'child'
[void][System.IO.Directory]::CreateDirectory($child)
[IO.File]::WriteAllText((Join-Path $child 'f1.txt'), 'test1')
[IO.File]::WriteAllText((Join-Path $child 'f2.txt'), 'test2')

function Close-ExplorerWindows {
    Get-Process explorer -EA SilentlyContinue | ForEach-Object {
        try { if ($_.MainWindowTitle) { $_.CloseMainWindow() | Out-Null } } catch {}
    }
}

# --- открыть нужную папку
Close-ExplorerWindows
Start-Sleep 1
$openPath = if ($Mode -eq 'multi') { $child } else { $parent }
Start-Process explorer.exe -ArgumentList "`"$openPath`""
Start-Sleep 2.5

# --- выделить всё и открыть меню клавиатурой
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class W {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
}
'@
$exp = Get-Process explorer -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -ne '' } | Select-Object -First 1
if ($exp) {
    $h = $exp.MainWindowHandle
    [void][W]::ShowWindow($h, 9)        # SW_RESTORE
    [void][W]::BringWindowToTop($h)
    $fgThread = [W]::GetWindowThreadProcessId([W]::GetForegroundWindow(), [IntPtr]::Zero)
    $myThread = [W]::GetCurrentThreadId()
    [void][W]::AttachThreadInput($myThread, $fgThread, $true)
    [void][W]::SetForegroundWindow($h)
    [void][W]::AttachThreadInput($myThread, $fgThread, $false)
}
Start-Sleep 1
$fg = [W]::GetForegroundWindow()
$sb = New-Object System.Text.StringBuilder 256
[void][W]::GetClassName($fg, $sb, 256)
Write-Host ("foreground class=" + $sb.ToString())
[System.Windows.Forms.SendKeys]::SendWait('^a')
Start-Sleep 0.6
[System.Windows.Forms.SendKeys]::SendWait('+{F10}')
Start-Sleep 2

# --- найти окно меню
$rootEl = [System.Windows.Automation.AutomationElement]::RootElement
$all = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition)
Write-Host "=== верхнеуровневые окна ==="
$menus = @()
foreach ($w in $all) {
    $cn = $w.Current.ClassName
    $nm = $w.Current.Name
    $ct = $w.Current.ControlType.ProgrammaticName
    Write-Host ("  win: class=$cn name=[$nm] ct=$ct")
    if ($cn -match '32768|CoreWindow|Xaml|Menu|ShellFlyout' -or $ct -match 'Menu') {
        $menus += $w
    }
}

# --- вычитать пункты меню из всех кандидатов + глубокий поиск по всему дереву
function Get-MenuItems([System.Windows.Automation.AutomationElement]$scope, [int]$maxDepth) {
    $res = @()
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($scope, 0))
    while ($stack.Count -gt 0) {
        $pair = $stack.Pop()
        $el = $pair[0]; $depth = $pair[1]
        if ($depth -gt $maxDepth) { continue }
        try {
            $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
            $child = $walker.GetFirstChild($el)
            while ($child) {
                try {
                    if ($child.Current.ControlType -eq [System.Windows.Automation.ControlType]::MenuItem -or
                        $child.Current.ControlType -eq [System.Windows.Automation.ControlType]::ListItem) {
                        $res += $child.Current.Name
                    } elseif ($child.Current.ControlType -eq [System.Windows.Automation.ControlType]::Menu) {
                        $res += ('<MENU ' + $child.Current.Name + '>')
                    }
                    $stack.Push(@($child, $depth + 1))
                } catch {}
                try { $child = $walker.GetNextSibling($child) } catch { $child = $null }
            }
        } catch {}
    }
    return $res
}

$found = @()
foreach ($m in $menus) {
    Write-Host ("--- пункты в окне " + $m.Current.ClassName + " [" + $m.Current.Name + "] ---")
    $items = Get-MenuItems $m 12
    foreach ($i in $items) { Write-Host ("    " + $i) }
    $found += $items
}

# --- если меню не найдено среди окон, искать по всему дереву по имени
if ($found.Count -eq 0) {
    Write-Host '=== глобальный поиск пунктов по имени ==='
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, '*Архивировать*')
    $cond2 = New-Object System.Windows.Automation.AndCondition(
        $cond,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::MenuItem)))
    $items = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Subtree, $cond2)
    foreach ($i in $items) { Write-Host ("    НАЙДЕН ПУНТ: " + $i.Current.Name) ; $found += $i.Current.Name }
    if ($items.Count -eq 0) { Write-Host '    (пункт "Архивировать" НЕ найден в открытом меню)' }
}

[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep 0.5
Write-Host "=== MODE=$Mode итог: найдено пунктов меню: $($found.Count) ==="
