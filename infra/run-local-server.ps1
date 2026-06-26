# run-local-server.ps1 — arranca proyecto-X como "servidor por ahora" en esta PC:
#   Docker (Postgres+Redis) -> API Rust (:8081) -> Cloudflare Tunnel (api.turnend.win)
# Uso:  pwsh -File infra/run-local-server.ps1
# Sin admin. Para persistencia real ver infra/cloudflared/README.md (servicio de Windows).

$ErrorActionPreference = "Stop"
$root    = Split-Path $PSScriptRoot -Parent
$compose = Join-Path $PSScriptRoot "docker-compose.yml"
$envFile = Join-Path $PSScriptRoot ".env.local"
$apiExe  = Join-Path $root "backend\target\debug\api.exe"

# 1) .env.local (genera JWT_SECRET si falta)
if (-not (Test-Path $envFile)) {
  $b = New-Object byte[] 48; [System.Security.Cryptography.RandomNumberGenerator]::Fill($b)
  @(
    "DATABASE_URL=postgres://dev:dev@localhost:5433/appdb",
    "BIND_ADDR=0.0.0.0:8081",
    "JWT_SECRET=$([Convert]::ToBase64String($b))",
    "TARPIT_ENABLED=true"
  ) | Set-Content $envFile -Encoding utf8
  Write-Host "generado $envFile"
}
$envMap = @{}
Get-Content $envFile | ForEach-Object { if ($_ -match '^\s*([^=#]+)=(.*)$') { $envMap[$matches[1].Trim()] = $matches[2] } }

# 2) Docker: Postgres + Redis
Write-Host "==> docker compose up (postgres+redis)"
docker compose -f $compose up -d | Out-Null
for ($i=0; $i -lt 20; $i++) {
  $h = docker inspect --format '{{.State.Health.Status}}' (docker compose -f $compose ps -q postgres) 2>$null
  if ($h -eq 'healthy') { break }; Start-Sleep 3
}
Write-Host "postgres healthy"

# 3) Build + arrancar API en :8081
if (-not (Test-Path $apiExe)) {
  Write-Host "==> compilando api (offline)"
  $env:SQLX_OFFLINE = "true"
  cargo build -p api --manifest-path (Join-Path $root "backend\Cargo.toml")
}
foreach ($k in $envMap.Keys) { Set-Item "env:$k" $envMap[$k] }
$env:SQLX_OFFLINE = "true"
Write-Host "==> API en $($env:BIND_ADDR)"
Start-Process -FilePath $apiExe -WindowStyle Hidden
Start-Sleep 3
try { (Invoke-WebRequest "http://localhost:8081/health" -UseBasicParsing -TimeoutSec 5).Content | Write-Host } catch { Write-Warning "API /health aún no responde" }

# 4) Túnel
Write-Host "==> cloudflared tunnel run proyectox"
Start-Process -FilePath "cloudflared" -ArgumentList "tunnel","run","proyectox" -WindowStyle Hidden
Start-Sleep 6
try { Write-Host "PUBLIC: $((Invoke-WebRequest 'https://api.turnend.win/health' -UseBasicParsing -TimeoutSec 8).Content)" }
catch { Write-Warning "público aún propagando; reintenta en unos segundos" }
Write-Host "Listo. https://api.turnend.win/health"
