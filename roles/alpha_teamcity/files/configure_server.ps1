#requires -version 5
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff McJunkin and contributors
# Configure the installed Tomcat distribution without redistributing its configuration.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [ValidateRange(1, 65535)][int]$Port = 8111
)
$ErrorActionPreference = 'Stop'
$conf = Join-Path $InstallDir 'conf'
$serverXml = Join-Path $conf 'server.xml'
if (Test-Path -LiteralPath $serverXml -PathType Leaf) {
    Write-Output 'preserved existing conf/server.xml'
    return
}
$source = Join-Path $conf 'server-https-proxy.xml'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Cannot configure Tomcat: neither server.xml nor server-https-proxy.xml exists in $conf. Check the TeamCity installation."
}

$document = New-Object System.Xml.XmlDocument
$document.PreserveWhitespace = $true
$document.XmlResolver = $null
$settings = New-Object System.Xml.XmlReaderSettings
$settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
$settings.XmlResolver = $null
$reader = $null
try {
    $reader = [System.Xml.XmlReader]::Create($source, $settings)
    $document.Load($reader)
} catch {
    throw "Cannot parse installed Tomcat configuration at ${source}: $($_.Exception.Message)"
} finally {
    if ($null -ne $reader) { $reader.Dispose() }
}

# Select the single non-TLS HTTP connector; leave AJP and TLS connectors alone.
$connectors = @($document.SelectNodes('/Server/Service/Connector') | Where-Object {
    $protocol = $_.GetAttribute('protocol')
    ($protocol -eq '' -or $protocol -match '^(HTTP/1\.[01]|org\.apache\.coyote\.http11\.[A-Za-z0-9]+)$') -and
        $_.GetAttribute('SSLEnabled') -ne 'true'
})
if ($connectors.Count -ne 1) {
    throw "Expected exactly one non-TLS HTTP connector in $source; found $($connectors.Count). Configure server.xml manually."
}
$connector = $connectors[0]
$connector.SetAttribute('port', [string]$Port)
foreach ($attribute in @('scheme', 'secure', 'proxyName', 'proxyPort')) {
    $connector.RemoveAttribute($attribute)
}

# Preserve upstream comments/notices, and do not publish a partially written file.
$temporary = Join-Path $conf ('.server.xml.' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    $document.Save($temporary)
    Move-Item -LiteralPath $temporary -Destination $serverXml -ErrorAction Stop
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
}
Write-Output "configured conf/server.xml for HTTP port $Port"
