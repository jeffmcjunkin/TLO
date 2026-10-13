#requires -version 5
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff McJunkin and contributors
# Isolated file-level regression tests; no TeamCity installation or services required.
$ErrorActionPreference = 'Stop'
$configure = Join-Path (Split-Path $PSScriptRoot -Parent) 'roles/alpha_teamcity/files/configure_server.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('teamcity-config-' + [guid]::NewGuid().ToString('N'))
$script:cases = 0

function Assert($condition, [string]$message) {
    if (-not $condition) { throw $message }
}
function New-Installation([string]$name, [string]$xml) {
    $path = Join-Path $root $name
    $conf = Join-Path $path 'conf'
    New-Item -ItemType Directory -Path $conf -Force | Out-Null
    if ($xml) { [IO.File]::WriteAllText((Join-Path $conf 'server-https-proxy.xml'), $xml) }
    return $path
}
function Expect-Failure([scriptblock]$action, [string]$pattern, [string]$path) {
    $message = $null
    try { & $action | Out-Null } catch { $message = $_.Exception.Message }
    Assert ($null -ne $message -and $message -match $pattern) "Expected failure matching '$pattern', got '$message'"
    Assert (-not (Test-Path (Join-Path $path 'conf/server.xml'))) 'Failure left a server.xml behind'
    Assert (@(Get-ChildItem (Join-Path $path 'conf') -Filter '*.tmp' -Force).Count -eq 0) 'Temporary output leaked'
    $script:cases++
}

# Small original fixtures, not copied vendor configuration.
$fixture = @'
<?xml version="1.0" encoding="utf-8"?>
<!-- Preserve this upstream notice. -->
<Server><Service name="ConfigRegression">
  <Connector secure="true" proxyPort="443" port="8111" proxyName="proxy.invalid"
    protocol="org.apache.coyote.http11.Http11NioProtocol" scheme="https" connectionTimeout="12345" />
  <Connector protocol="AJP/1.3" port="9009" />
  <Connector protocol="HTTP/1.1" SSLEnabled="true" port="9443" scheme="https" secure="true" />
</Service></Server>
'@
try {
    $path = New-Installation 'default' $fixture
    & $configure -InstallDir $path | Out-Null
    [xml]$doc = Get-Content (Join-Path $path 'conf/server.xml') -Raw
    Assert ($doc.Server.Service.Connector[0].port -eq '8111') 'Wrong default port'
    $script:cases++

    $path = New-Installation 'custom-port' $fixture
    $source = Join-Path $path 'conf/server-https-proxy.xml'
    $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($source))
    & $configure -InstallDir $path -Port 8222 | Out-Null
    $target = Join-Path $path 'conf/server.xml'
    $text = Get-Content $target -Raw
    [xml]$doc = $text
    $http = $doc.Server.Service.Connector[0]
    Assert ($http.port -eq '8222') 'Configured port was ignored'
    foreach ($name in @('scheme', 'secure', 'proxyName', 'proxyPort')) {
        Assert (-not $http.HasAttribute($name)) "Proxy attribute $name survived"
    }
    Assert ($http.connectionTimeout -eq '12345') 'Unrelated HTTP setting changed'
    Assert ($doc.Server.Service.Connector[1].port -eq '9009') 'AJP connector changed'
    Assert ($doc.Server.Service.Connector[2].secure -eq 'true' -and $doc.Server.Service.Connector[2].port -eq '9443') 'TLS connector changed'
    Assert ($text.Contains('Preserve this upstream notice.')) 'Notice was lost'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($source)) -eq $before) 'Installed source was modified'
    $script:cases++

    $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($target))
    Remove-Item $source
    & $configure -InstallDir $path -Port 8333 | Out-Null
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) -eq $before) 'Existing configuration was overwritten'
    $script:cases++

    $path = New-Installation 'missing' ''
    Expect-Failure { & $configure -InstallDir $path } 'neither server.xml nor' $path
    $path = New-Installation 'malformed' '<Server>'
    Expect-Failure { & $configure -InstallDir $path } 'Cannot parse' $path
    $path = New-Installation 'ambiguous' '<Server><Service><Connector port="8111"/><Connector port="8222"/></Service></Server>'
    Expect-Failure { & $configure -InstallDir $path } 'exactly one.*found 2' $path
    $path = New-Installation 'no-http' '<Server><Service><Connector protocol="AJP/1.3" port="9009"/></Service></Server>'
    Expect-Failure { & $configure -InstallDir $path } 'exactly one.*found 0' $path
    $path = New-Installation 'invalid-port' $fixture
    Expect-Failure { & $configure -InstallDir $path -Port 65536 } '65535' $path
    $path = New-Installation 'dtd' '<!DOCTYPE Server [<!ENTITY external SYSTEM "file:///not-a-real-file">]><Server>&external;</Server>'
    Expect-Failure { & $configure -InstallDir $path } 'Cannot parse' $path
    Write-Output "PASS: $script:cases TeamCity configuration scenarios"
} finally {
    if (Test-Path $root) { Remove-Item $root -Recurse -Force }
}
