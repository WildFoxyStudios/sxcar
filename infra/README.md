# infra/ — despliegue de proyecto-X

Dos caminos:

## A) "Servidor por ahora" — esta PC + Cloudflare Tunnel  ✅ ACTIVO
El API Rust corre local y se expone vía `api.turnend.win` con Cloudflare Tunnel (gratis, sin
abrir puertos, HTTPS del edge). Estado verificado: `https://api.turnend.win/health` → `{"status":"ok","db":"up"}`.

- DB/Redis: `docker compose -f infra/docker-compose.yml up -d` (Postgres PostGIS en `localhost:5433`, ya migrado 10/10).
- API: binario en `:8081` (el `8080` lo ocupa Apache/XAMPP). Secreto en `infra/.env.local` (gitignored).
- Túnel: ver `infra/cloudflared/`. Arranque todo-en-uno: `pwsh -File infra/run-local-server.ps1`.

> Persistencia (sobrevivir reinicios) = servicio de Windows para cloudflared (admin) + autoarranque
> del API. Ver `infra/cloudflared/README.md`.

## B) Producción — AWS VPS (Terraform)  ⏳ AUTORÍA LISTA, APPLY DIFERIDO
`infra/terraform/` levanta un EC2 `t4g.small` (ARM, us-east-1) con Docker, listo para correr
`infra/docker-compose.prod.yml` (caddy + api + redis). Migrar aquí cuando se quiera salir de la PC.

### Rellenar antes del apply (gitignored)
- `infra/terraform/terraform.tfvars` ← copia de `terraform.tfvars.example` (tu IP/32, ruta de tu clave pública SSH).
- Credenciales AWS por entorno: `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (o `aws configure`).
- `infra/.env` ← copia de `.env.example` (Neon `DATABASE_URL`, `JWT_SECRET`, claves R2…).

### Pasos
```bash
cd infra/terraform
terraform init && terraform validate && terraform fmt -check
terraform plan      # revisar
terraform apply     # crea EC2 + SG + key pair
# luego: scp docker-compose.prod.yml Caddyfile .env  ubuntu@<dns>:/opt/proyectox/ ; docker compose up -d
```

## Almacenamiento — Cloudflare R2
3 buckets `proyectox-*` (media/private/verification) — pendientes de crear (vía MCP/CLI). CORS en `infra/r2-cors.json`.

## Marketing — Vercel
`apps/marketing` → proyecto Vercel `proyectox-marketing` (pendiente). Dominio: subdominio de `turnend.win` o `.vercel.app`.

## Seguridad / secretos
NADA de secretos en git: `.env*` (excepto `.env.example`), `*.tfvars` (excepto `.example`), `*.tfstate`, credenciales de túnel — todo gitignored. Ver `.gitignore` raíz.
