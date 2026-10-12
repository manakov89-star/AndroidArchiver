$root = 'HKLM:\SOFTWARE\Classes'
$clsid = '{a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60}'
$log = 'C:\Users\Youra3\Tools\AndroidArchiver\handlers.log'
$errlog = 'C:\Users\Youra3\Tools\AndroidArchiver\handlers.err'
$handlers = @('*','Directory','Directory\Background','Drive','AllFilesystemObjects')
$fail = 0
"" | Out-File -FilePath $log -Encoding UTF8
"start $(Get-Date)" | Out-File -FilePath $log -Append -Encoding UTF8
"" | Out-File -FilePath $errlog -Encoding UTF8
foreach ($h in $handlers) {
    $k = "$root\$h\shellex\ContextMenuHandlers\AndroidArchive"
    try {
        New-Item -Path $k -Force | Out-Null
        Set-ItemProperty -Path $k -Name '(default)' -Value $clsid -Type String
        "OK  handler: $h" | Out-File -FilePath $log -Append -Encoding UTF8
    } catch {
        $fail++
        "ERR handler $h : $($_.Exception.Message)" | Out-File -FilePath $log -Append -Encoding UTF8
        $($_.Exception | Out-String) | Out-File -FilePath $errlog -Append -Encoding UTF8
    }
}
"DONE errors: $fail" | Out-File -FilePath $log -Append -Encoding UTF8