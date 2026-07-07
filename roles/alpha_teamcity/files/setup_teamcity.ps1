#requires -version 5
<#
  setup_teamcity.ps1 — idempotently bring up the TeamCity server + build config on
  XY1-ALPHA after the NSIS installer has extracted TeamCity to $InstallDir.

  The NSIS /S silent install only lays down files: it does NOT create conf/server.xml,
  register the Windows services, or complete the first-run wizard. This script does all
  of that unattended:
    1. writes conf/server.xml (plain-HTTP :8111) if missing
    2. installs + starts the "TeamCity" server service via TeamCityService.exe
    3. drives the first-run maintenance wizard (data dir -> internal HSQLDB -> EULA)
    4. creates a system admin, the build project + config + MSBuild step (super-user token)
  The build agent (as the deploy service account) is handled by setup_agent.ps1.

  Idempotent: safe to re-run. All parameters are passed by the Ansible role.
#>
[CmdletBinding()]
param(
  [string]$InstallDir  = 'C:\TeamCity',
  [int]   $Port        = 8111,
  [string]$SvcUser     = 'localuser',      # local account the server service logs on as
  [string]$SvcPass     = 'password',
  [string]$AdminUser   = 'admin',
  [string]$AdminPass   = 'Alpha#CI#Adm1n2026',
  [string]$ProjectName = 'PaymentService',
  [string]$BuildCmd    = 'C:\Projects\payment-service\build.cmd'
)
$ErrorActionPreference = 'Stop'
$base = "http://localhost:$Port"
function Log($m){ Write-Host "[setup_teamcity] $m" }

# ---- 1. server.xml (role copies files/server.xml to conf\; fallback: derive from sample) ----
$serverXml = Join-Path $InstallDir 'conf\server.xml'
if (-not (Test-Path $serverXml)) {
  $sample = Join-Path $InstallDir 'conf\server-https-proxy.xml'
  if (Test-Path $sample) {
    (Get-Content $sample -Raw) -replace '\s*scheme="https"\s*secure="true"','' | Set-Content $serverXml -Encoding UTF8
    Log "generated conf\server.xml from sample"
  } else { throw "no server.xml and no sample to derive it from" }
}

# ---- 2. install + start the server service ----
if (-not (Get-Service -Name 'TeamCity' -ErrorAction SilentlyContinue)) {
  $svcXml = Join-Path $InstallDir 'conf\teamcity-server-service.xml'
  Log "installing TeamCity server service"
  & (Join-Path $InstallDir 'bin\TeamCityService.exe') install /settings=$svcXml /user=$SvcUser /password=$SvcPass | Out-Null
}
if ((Get-Service TeamCity).Status -ne 'Running') { Start-Service TeamCity; Log "started TeamCity service" }

function Get-Stage {
  try { (Invoke-WebRequest "$base/mnt" -UseBasicParsing -TimeoutSec 8).Content } catch { '' }
}
function Http-Code([string]$path){
  try { (Invoke-WebRequest "$base$path" -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 0).StatusCode }
  catch { if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 } }
}

# wait for Tomcat to answer at all (503 during startup is fine)
$sess = $null
for ($i=0; $i -lt 60; $i++) {
  try { Invoke-WebRequest "$base/mnt" -UseBasicParsing -TimeoutSec 6 -SessionVariable sess | Out-Null; $script:S=$sess; break } catch { }
  try { $c=[int]$_.Exception.Response.StatusCode; if ($c){ $script:S=$sess; break } } catch {}
  Start-Sleep 5
}
if (-not $sess) { $sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession }

# ---- 3. first-run wizard (only if it is showing) ----
$body = Get-Stage
if ($body -match 'FIRST_START_SCREEN') {
  Log "confirming data directory"
  Invoke-WebRequest "$base/mnt/do/goNewInstallation" -Method POST -WebSession $sess -TimeoutSec 20 `
    -Body @{ dataDirPath='C:\ProgramData\JetBrains\TeamCity'; restore='false' } | Out-Null
  Start-Sleep 6
}
for ($i=0; $i -lt 20; $i++){ if ((Get-Stage) -match 'DB_SETTINGS_SCREEN'){ break }; Start-Sleep 6 }
if ((Get-Stage) -match 'DB_SETTINGS_SCREEN') {
  Log "selecting internal (HSQLDB) database"
  Invoke-WebRequest "$base/mnt/do/goNewDatabase" -Method POST -WebSession $sess -TimeoutSec 30 -Body @{ dbType='HSQLDB2' } | Out-Null
}
# wait for the app to come up (login.html stops 503-ing)
for ($i=0; $i -lt 40; $i++){ if ((Http-Code '/login.html') -in 200,302,401){ break }; Start-Sleep 8 }

# ---- 3b. accept the EULA if it is being shown ----
if ((Http-Code '/login.html') -eq 302) {
  try {
    $ag = Invoke-WebRequest "$base/showAgreement.html" -UseBasicParsing -WebSession $sess -TimeoutSec 8
    if ($ag.Content -match 'name="tc-csrf-token" content="([0-9a-f-]{36})"') {
      $csrf = $Matches[1]
      Log "accepting license agreement"
      Invoke-WebRequest "$base/showAgreement.html" -Method POST -WebSession $sess -TimeoutSec 10 `
        -Headers @{ 'X-TC-CSRF-Token'=$csrf } -Body @{ accept='true'; 'tc-csrf-token'=$csrf } | Out-Null
    }
  } catch { }
}

# ---- 4. super-user token -> admin + project + build config ----
$log = Join-Path $InstallDir 'logs\teamcity-server.log'
$token = $null
for ($i=0; $i -lt 12 -and -not $token; $i++) {
  if (Test-Path $log) {
    $m = Select-String -Path $log -Pattern 'Super user authentication token:\s*(\d+)' -AllMatches
    if ($m) { $token = ($m.Matches | Select-Object -Last 1).Groups[1].Value }
  }
  if (-not $token) { Start-Sleep 5 }
}
if (-not $token) { throw "no super-user token in $log" }
$pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$token"))
$H = @{ Authorization = "Basic $pair"; 'Content-Type'='application/json'; Accept='application/json' }
function Rest($method,$path,$json){
  try { Invoke-WebRequest "$base$path" -Method $method -Headers $H -Body $json -UseBasicParsing -TimeoutSec 15 | Out-Null; return 200 }
  catch { if ($_.Exception.Response){ return [int]$_.Exception.Response.StatusCode } else { return 0 } }
}
Log "creating admin user (idempotent)"
Rest POST '/app/rest/users' ('{"username":"'+$AdminUser+'","password":"'+$AdminPass+'","roles":{"role":[{"roleId":"SYSTEM_ADMIN","scope":"g"}]}}') | Out-Null
Log "creating project + build config"
Rest POST '/app/rest/projects'   ('{"name":"'+$ProjectName+'","id":"'+$ProjectName+'"}') | Out-Null
Rest POST '/app/rest/buildTypes' ('{"name":"Build","project":{"id":"'+$ProjectName+'"}}') | Out-Null
$bt = "$($ProjectName)_Build"
$step = '{"name":"MSBuild payment-service","type":"simpleRunner","properties":{"property":[' +
        '{"name":"use.custom.script","value":"true"},' +
        '{"name":"script.content","value":"' + ($BuildCmd -replace '\\','\\') + '"},' +
        '{"name":"teamcity.step.mode","value":"default"}]}}'
Rest POST "/app/rest/buildTypes/id:$bt/steps" $step | Out-Null
Log "server setup complete"
