# Remove manual (unpackaged) ContextMenuHandlers registration.
# The sparse MSIX package now provides the same item for both the new Win11 menu
# and the classic menu; keeping both caused TWO identical menu items.
# Must run elevated (HKLM part). All messages are ASCII-only: no BOM issues.
$ErrorActionPreference = 'Continue'
$log = 'C:\Users\Youra3\AppData\Local\Temp\opencode\unregister.log'
function L($m) { Add-Content -Path $log -Value ((Get-Date -Format 'HH:mm:ss') + '  ' + $m) -Encoding UTF8 }
Set-Content -Path $log -Value ('=== unregister manual handlers  ' + (Get-Date) + ' ===') -Encoding UTF8

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ('started, admin=' + $isAdmin)

$types = @('*', 'AllFilesystemObjects', 'Directory', 'Directory\Background', 'Directory\background', 'Drive')
$roots = @('HKLM:\SOFTWARE\Classes', 'HKCU:\Software\Classes')

foreach ($root in $roots) {
    foreach ($t in $types) {
        $k = $root + '\' + $t + '\shellex\ContextMenuHandlers\AndroidArchive'
        try {
            if (Test-Path -LiteralPath $k) {
                Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction Stop
                L ('removed: ' + $k)
            } else {
                L ('absent:  ' + $k)
            }
        } catch { L ('FAILED ' + $k + ': ' + $_.Exception.Message) }
    }
}

# Report what still references the CLSID in ContextMenuHandlers
L '--- remaining ContextMenuHandlers refs ---'
$refs = & reg query 'HKLM\SOFTWARE\Classes' /f 'AndroidArchive' /k /s 2>$null
$refs | ForEach-Object { if ($_ -match 'ContextMenuHandlers') { L ('still: ' + $_.Trim()) } }

# Restart Explorer so it reloads the shell extensions
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe; Start-Sleep -Seconds 3 }
L ('explorer restarted, running=' + [bool](Get-Process explorer -ErrorAction SilentlyContinue))

L '=== DONE ==='
