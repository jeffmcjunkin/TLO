#requires -version 5
<#
  setup_agent.ps1 — run the TeamCity build agent as the deploy service account.

  The agent MUST execute builds under a Domain-Admin-privileged account so the
  post-build deploy hook (net group "Domain Admins" ...) succeeds — this is the
  intended over-privilege of the CI build agent. We run agent.bat via a scheduled
  task whose principal is that account, then authorize the agent over REST.

  Idempotent: safe to re-run.
#>
[CmdletBinding()]
param(
  [string]$InstallDir = 'C:\TeamCity',
  [int]   $Port       = 8111,
  [string]$AgentName  = 'ALPHA-BUILD-01',
  [string]$AgentUser  = 'alpha\svc_build',   # the DA build service account
  [string]$AgentPass  = 'Bu1ld.Agent.2025!'
)
$ErrorActionPreference = 'Stop'
# Fresh Windows Server: IE engine not initialized, so force basic parsing for all web calls.
$PSDefaultParameterValues['Invoke-WebRequest:UseBasicParsing']  = $true
$PSDefaultParameterValues['Invoke-RestMethod:UseBasicParsing'] = $true
$base = "http://localhost:$Port"
function Log($m){ Write-Host "[setup_agent] $m" }

# ---- point the agent at the local server ----
$conf = Join-Path $InstallDir 'buildAgent\conf\buildAgent.properties'
$dist = Join-Path $InstallDir 'buildAgent\conf\buildAgent.dist.properties'
if (-not (Test-Path $conf) -and (Test-Path $dist)) { Copy-Item $dist $conf }
if (Test-Path $conf) {
  $t = Get-Content $conf
  if ($t -match '^serverUrl=') { $t = $t -replace '^serverUrl=.*',"serverUrl=$base" } else { $t += "serverUrl=$base" }
  if ($t -match '^name=')      { $t = $t -replace '^name=.*',"name=$AgentName" }        else { $t += "name=$AgentName" }
  Set-Content $conf $t
}

# ---- grant the account "log on as a service", then run agent.bat via a scheduled task ----
$agentBat = Join-Path $InstallDir 'buildAgent\bin\agent.bat'
if (-not (Get-ScheduledTask -TaskName 'BuildAgent' -ErrorAction SilentlyContinue)) {
  Log "creating BuildAgent scheduled task as $AgentUser"
  & schtasks.exe /Create /TN BuildAgent /TR "cmd /c `"$agentBat`" start" /SC ONSTART /RU $AgentUser /RP $AgentPass /RL HIGHEST /F | Out-Null
}
# start it if the agent process is not already running
if (-not (Get-CimInstance Win32_Process -Filter "name='java.exe'" | Where-Object { $_.CommandLine -match 'buildAgent' })) {
  Log "starting build agent"
  & schtasks.exe /Run /TN BuildAgent | Out-Null
}

# ---- wait for the agent to register, then authorize it (super-user token) ----
$log = Join-Path $InstallDir 'logs\teamcity-server.log'
$token = $null
$m = Select-String -Path $log -Pattern 'Super user authentication token:\s*(\d+)' -AllMatches -ErrorAction SilentlyContinue
if ($m) { $token = ($m.Matches | Select-Object -Last 1).Groups[1].Value }
if (-not $token) { Log "no super-user token yet; agent will remain unauthorized until authorized manually"; return }
$H = @{ Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$token")) }

$agentId = $null
for ($i=0; $i -lt 25 -and -not $agentId; $i++) {
  try {
    $r = Invoke-RestMethod "$base/app/rest/agents?locator=authorized:any" -Headers ($H + @{Accept='application/json'}) -TimeoutSec 8
    $a = $r.agent | Where-Object { $_.name -eq $AgentName } | Select-Object -First 1
    if ($a) { $agentId = $a.id }
  } catch {}
  if (-not $agentId) { Start-Sleep 12 }
}
if ($agentId) {
  Log "authorizing agent id:$agentId"
  try {
    Invoke-WebRequest "$base/app/rest/agents/id:$agentId/authorized" -Method PUT `
      -Headers ($H + @{'Content-Type'='text/plain'}) -Body 'true' -UseBasicParsing -TimeoutSec 10 | Out-Null
    Log "agent authorized"
  } catch { Log "authorize failed: $_" }
} else { Log "agent did not register in time; authorize manually in the UI" }
