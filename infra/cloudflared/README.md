# Cloudflare Tunnel — backend API (turnend.win)

Expone el API Rust local a Internet vía `api.turnend.win` **sin abrir puertos** y con
HTTPS del edge de Cloudflare. Coste 0. La PC de desarrollo actúa de servidor "por ahora".

```
Internet ──HTTPS──> Cloudflare edge (api.turnend.win)
            │
            └──QUIC──> cloudflared (esta PC) ──> http://localhost:8081 (API Rust) ──> Postgres
```

## Estado actual
- Túnel: `proyectox` (id `71025a02-45aa-414b-83c0-3dce38eeefcc`), remotely/locally-managed con `config.yml`.
- DNS: CNAME `api.turnend.win` → `<uuid>.cfargotunnel.com` (proxied) — creado con `cloudflared tunnel route dns`.
- Ingress: `api.turnend.win` → `http://localhost:8081`.
- Verificado: `GET https://api.turnend.win/health` → `{"status":"ok","db":"up"}`.

## Archivos (NO en git — son secretos)
- `~/.cloudflared/cert.pem` — credencial de cuenta (de `cloudflared tunnel login`).
- `~/.cloudflared/config.yml` — config real (ver `config.example.yml`).
- `~/.cloudflared/<uuid>.json` — credenciales del túnel.

## Arrancar / reiniciar (manual, sin admin)
```powershell
# 1) DB local + API (ver infra/run-local-server.ps1)
# 2) túnel:
cloudflared tunnel run proyectox
```
O todo de una: `infra/run-local-server.ps1`.

## Hacerlo persistente (servicio de Windows — requiere admin)
```powershell
# Ejecuta una terminal COMO ADMINISTRADOR:
cloudflared service install      # instala el servicio que corre ~/.cloudflared/config.yml
Start-Service cloudflared
```
El API también debe autoarrancar (tarea programada o contenedor) para sobrevivir reinicios.

## Seguridad
- No hay puertos entrantes abiertos en el router/firewall; el túnel sale en QUIC.
- Postgres/Redis nunca se exponen; solo el API (con JWT + rate-limit + tarpit) vía el túnel.
- Para revocar: `cloudflared tunnel delete proyectox` (borra credenciales) + borrar el CNAME.

## Migración a producción (luego)
Cuando se pase al VPS AWS (ver `infra/terraform/`), el ingress apunta al servicio del VPS
y/o se mantiene el túnel desde el VPS. El dominio definitivo ya está en Cloudflare.
