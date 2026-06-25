# Spec Maestro — App tipo Grindr (paridad 100%)

- **Proyecto:** proyecto-X
- **Fecha:** 2026-06-25
- **Estado:** Diseño aprobado (pendiente de revisión del documento)
- **Autor:** Equipo / Claude Code (brainstorming superpowers)

> Este es el **spec maestro**: define la visión, arquitectura, modelo de datos, catálogo completo de funcionalidades con paridad 100% frente a Grindr, los pilares transversales (coste, seguridad, SEO) y el roadmap por fases. **Cada fase (F0–F6) tendrá su propio spec → plan → implementación** derivado de este documento.

---

## 1. Resumen ejecutivo

Construir una aplicación de citas/social geolocalizada para la comunidad LGBTQ+ con **paridad funcional del 100%** frente a Grindr (todas las funciones implementadas completas, sin stubs), multiplataforma (iOS, Android, Web), con foco innegociable en: **coste de producción mínimo**, **seguridad (0 vulnerabilidades conocidas)** y **SEO superior** para la captación orgánica.

### Objetivos
1. **Paridad total** con el set de funciones de Grindr (2025/2026), incluyendo IA (Wingman), Roam/Explore, premium (XTRA/Unlimited) y álbumes privados.
2. **Multiplataforma con una sola base de producto** en React Native (móvil + web) + sitio de marketing en Next.js.
3. **Backend Rust de alto rendimiento** en VPS propio de AWS, eficiente en recursos para minimizar coste.
4. **Privacidad y seguridad de grado producción** desde el día 1 (población vulnerable + datos sensibles + geolocalización).

### No-objetivos (de momento)
- Funciones que Grindr no tiene (no añadimos scope propio hasta lograr paridad).
- Federación/descentralización.
- Cliente de escritorio nativo (la web cubre desktop).

---

## 2. Decisiones fijadas

| Área | Decisión |
|---|---|
| **Móvil** | React Native (Expo) → iOS + Android |
| **Web app (producto)** | React Native Web (Expo) → mismo código que móvil |
| **Web marketing/SEO** | Next.js (App Router) en **Vercel** (SSR/SSG/ISR) |
| **Backend** | **Rust** (`axum` + `tokio`), binarios dockerizados en **VPS de AWS (EC2)** |
| **Base de datos** | **Neon** (PostgreSQL + PostGIS), fuente de verdad |
| **Caché / tiempo real / geo en caliente** | **Redis** autoalojado en el VPS |
| **Almacenamiento de media** | **Cloudflare R2** (egress gratis) + CDN Cloudflare |
| **Pagos / suscripciones** | **RevenueCat** (App Store + Google Play + Stripe web) |
| **Moderación NSFW** | **NSFWJS** (infinitered/nsfwjs) **solo cliente**; modelo de **desenfoque** (ver §10) |
| **Contenido ilegal** | Hash-matching en **toda** imagen (incl. chat) — **Cloudflare CSAM Scanning Tool** |
| **Chats** | **Nunca se moderan** por contenido (solo el hash-match legal de imágenes) |
| **Mercado** | Global (GDPR + CCPA + verificación de edad 18+) |
| **Monetización** | Freemium completo (Free / XTRA / Unlimited) |
| **IA** | Claude (Anthropic) para Wingman/ice-breakers/resúmenes (F6) |

---

## 3. Arquitectura del sistema

```
                         ┌───────────────────────────────────────┐
                         │            CLIENTES                     │
                         │  Expo RN: iOS · Android · Web (app)      │
                         │  Next.js (Vercel): marketing + SEO       │
                         └───────────┬───────────────┬─────────────┘
                                     │ HTTPS REST     │ WSS (realtime)
                  ┌──────────────────▼──┐      ┌──────▼──────────────┐
   Cloudflare ─── │  api  (axum)         │      │ realtime (axum/ws)  │   binarios Rust
   WAF/CDN/DDoS   │  REST + auth + lógica│      │ presencia + chat    │   en VPS de AWS (EC2)
                  └───┬───────┬──────────┘      └──────┬──────────────┘
                      │       │                        │
        ┌─────────────▼┐  ┌───▼────────┐         ┌─────▼──────┐    ┌─────────────────┐
        │ Neon Postgres│  │ Cloudflare │         │   Redis    │    │ worker (Rust)    │
        │  + PostGIS    │  │    R2      │         │ presencia  │    │ jobs · push ·    │
        │ (fuente verdad)│  │  media     │◀──CSAM─┤ pub/sub    │    │ media · CSAM ·   │
        └──────────────┘  └────────────┘  scan   │ geo · ratel│    │ moderación cola  │
                                                  └────────────┘    └─────────────────┘
```

### Componentes
- **`api` (Rust/axum):** REST API stateless. Auth, perfiles, grid, álbumes, suscripciones/entitlements, reportes, ajustes. Escala horizontal tras ALB.
- **`realtime` (Rust/axum WebSocket):** conexiones WSS persistentes, presencia (heartbeat→Redis TTL), entrega de chat (Redis pub/sub fan-out), typing/visto, actualizaciones de grid.
- **`worker` (Rust):** consumidores de cola (Redis streams): generación de renditions de imagen (thumbnail/blur), envío de push (APNs/FCM), hash-match CSAM, procesamiento de reportes/moderación, jobs de retención GDPR, recordatorios de salud.
- **Crates lib compartidas:** `domain` (tipos + reglas de negocio), `db` (repositorios sqlx + migraciones), `storage` (cliente R2/S3), `auth` (JWT/OAuth/argon2), `geo` (PostGIS + Redis GEO), `realtime-proto` (mensajes WS).

### Despliegue
- **VPS AWS:** instancia(s) EC2 **Graviton (ARM, p. ej. `c7g`/`t4g`)** por precio/rendimiento. Docker Compose inicial (api + realtime + worker + redis + nginx/caddy TLS). Escalado: vertical primero; luego ALB + Auto Scaling Group para `api`/`realtime` (stateless).
- **Cloudflare delante:** DNS, CDN, WAF, mitigación DDoS, Turnstile (anti-bot en flujos web), CSAM scanning sobre media en R2.
- **Vercel:** sitio Next.js de marketing (ISR/SSG, edge caching, `next/image`).
- **Neon:** Postgres gestionado con **scale-to-zero** en dev y autoscaling de cómputo en prod; ramas de DB por entorno.

---

## 4. Stack tecnológico

### Cliente (Expo / React Native)
- Expo SDK (RN), `react-native-web` para la web app.
- Navegación: **expo-router**.
- Estado servidor: **TanStack Query**; estado local: **Zustand**.
- Realtime: cliente WebSocket propio (reconexión, backoff).
- Geolocalización: `expo-location`.
- Push: `expo-notifications` (APNs/FCM).
- Pagos: **RevenueCat SDK**.
- NSFW: **nsfwjs** + `@tensorflow/tfjs` (web) / `@tensorflow/tfjs-react-native` (móvil).
- Almacenamiento seguro: `expo-secure-store` (Keychain/Keystore) para tokens.
- App lock: `expo-local-authentication` (biometría) + PIN.

### Marketing web (Next.js en Vercel)
- Next.js App Router, SSG/ISR, `next/image`, `next-intl` (i18n + hreflang), JSON-LD, sitemap dinámico.

### Backend (Rust)
- `axum`, `tokio`, `tower` (middleware), `tokio-tungstenite` (WS).
- `sqlx` (queries verificadas en compilación, async, Postgres).
- `argon2` (hashing), `jsonwebtoken` (JWT), `oauth2` (Apple/Google).
- `redis` (presencia, pub/sub, GEO, rate-limit), `aws-sdk-s3` (R2 vía API S3-compatible).
- `serde` + `validator` (validación), `image` (renditions/blur), `tracing` (observabilidad).
- `cargo-audit`, `cargo-deny`, `clippy` en CI.

### Infra / DevOps
- Docker, GitHub Actions (CI/CD), Terraform (IaC para EC2/red/IAM), Cloudflare API.
- Observabilidad: OpenTelemetry → (Grafana/Tempo/Loki autoalojado o SaaS económico).

---

## 5. Estructura del monorepo

```
proyecto-X/
├── apps/
│   ├── mobile/                 # Expo RN → iOS, Android, Web app (react-native-web)
│   └── marketing/              # Next.js (Vercel) → SEO, landing, blog, soporte
├── packages/
│   ├── ui/                     # design system RN compartido
│   ├── api-client/             # cliente TS tipado (generado desde OpenAPI del backend)
│   ├── shared/                 # tipos, validaciones, constantes (taxonomías)
│   └── config/                 # eslint, tsconfig, tailwind base
├── backend/                    # Cargo workspace (Rust)
│   ├── crates/
│   │   ├── api/                # binario REST
│   │   ├── realtime/           # binario WebSocket
│   │   ├── worker/             # binario de jobs
│   │   ├── domain/  db/  storage/  auth/  geo/  realtime-proto/   # libs
│   └── migrations/             # SQL (sqlx)
├── infra/                      # Terraform, Docker Compose, Nginx/Caddy, CI scripts
└── docs/superpowers/specs/     # este spec + specs por fase
```
- **JS:** pnpm workspaces + **Turborepo**.
- **Rust:** Cargo workspace.
- **Contrato API:** el backend expone **OpenAPI**; `api-client` se genera desde ahí (tipos compartidos cliente↔servidor sin duplicar).

---

## 6. Modelo de datos (núcleo)

PostgreSQL + PostGIS. Resumen de tablas (columnas clave; las migraciones detallan tipos/índices/constraints):

**Identidad & cuenta**
- `users`(id, email, phone, password_hash, email_verified, phone_verified, dob, age_verified, status[active|suspended|banned|deleted], role[user|moderator|admin], created_at, deleted_at)
- `auth_identities`(user_id, provider[apple|google|password], provider_uid) — login social
- `sessions`/`refresh_tokens`(id, user_id, device_id, token_hash, expires_at, revoked_at)
- `devices`(id, user_id, platform[ios|android|web], push_token, last_seen)
- `consent_records`(user_id, type[tos|privacy|age|marketing], version, granted_at) — GDPR
- `data_requests`(user_id, type[export|delete], status, requested_at, completed_at) — GDPR/CCPA

**Perfil**
- `profiles`(user_id, display_name, about, position, body_type, height_cm, weight_kg, relationship_status, gender_identity, pronouns, hiv_status, last_tested_on, prep, accept_nsfw_view, created_at, updated_at)
- `profile_tribes`(user_id, tribe) · `profile_looking_for`(user_id, intent) · `profile_meet_at`(user_id, place) · `profile_tags`(user_id, tag) — N:M
- `profile_ethnicities`(user_id, ethnicity)
- `social_links`(user_id, kind, value)
- `photos`(id, user_id, r2_key, blur_key, position, is_primary, is_nsfw, moderation_status, created_at)
- `verifications`(user_id, kind[photo|id], status, verified_at)

**Geo & presencia**
- `locations`(user_id, geog GEOGRAPHY(Point), accuracy_m, show_distance, roam_geog, updated_at) — espejo caliente en Redis GEO
- `safety_zones`(user_id, geog, radius_m, action[hide_distance|hide_profile])

**Social & mensajería**
- `taps`(id, from_user, to_user, type, created_at)
- `favorites`(user_id, target_id, created_at) · `blocks`(user_id, target_id, created_at)
- `profile_views`(viewer_id, target_id, viewed_at) — "Viewed Me"
- `conversations`(id, created_at) · `conversation_members`(conversation_id, user_id, last_read_at, muted)
- `messages`(id, conversation_id, sender_id, kind[text|photo|ephemeral_photo|audio|location|album_share], body, media_key, expires_after_view, view_seconds, viewed_at, unsent_at, created_at)

**Álbumes**
- `albums`(id, owner_id, name, created_at) · `album_photos`(album_id, photo_id, position)
- `album_shares`(album_id, shared_with_user_id, granted_at, revoked_at, expires_at)

**Monetización**
- `subscriptions`(user_id, tier[free|xtra|unlimited], store[appstore|playstore|stripe], revenuecat_id, status, current_period_end)
- `entitlements`(user_id, feature, enabled) — cache derivada de la suscripción

**Confianza & seguridad**
- `reports`(id, reporter_id, target_user_id, target_kind[profile|photo|message], reason, status, created_at, resolved_at)
- `moderation_actions`(id, moderator_id, target_user_id, action[warn|suspend|ban|clear], note, created_at)
- `csam_hits`(id, photo_id, source, hash, reported_to_authority_at) — gestión legal del hash-match
- `audit_log`(actor_id, action, target, metadata, created_at)

**Notas de modelado**
- Borrado de cuenta = soft-delete + job de purga (cascada PG + limpieza R2) por GDPR.
- Datos de **salud sexual** (HIV/PrEP) tratados como categoría especial GDPR Art. 9: cifrado a nivel de campo + acceso auditado.
- `blocks` se aplica **en servidor** en cada consulta de grid/chat/perfil (nunca solo en cliente).

---

## 7. Catálogo de funcionalidades (paridad 100%)

Leyenda de tier: **F** = Free · **X** = XTRA · **U** = Unlimited.

### 7.1 Onboarding & cuenta (F0)
- Registro con email+contraseña, **Apple Sign-In**, **Google Sign-In** (obligatorios para stores).
- Verificación de **email** y de **teléfono (SMS OTP)**.
- **Age-gate 18+** (fecha de nacimiento + atestación) y captura de consentimientos (ToS/privacidad/edad).
- Login, logout, reseteo de contraseña, recuperación de cuenta, sesiones multi-dispositivo.
- **App lock**: PIN + biometría. **Icono discreto** de la app (cambio de icono).
- Borrado de cuenta y **exportación de datos** (GDPR/CCPA).

### 7.2 Perfil (F1)
- Nombre, edad (derivada de DOB), **About me**, fotos múltiples ordenadas + foto principal.
- **Stats**: altura, peso, body type, **posición/rol** (Top, Vers Top, Versatile, Vers Bottom, Bottom, Side).
- **Tribes** (multiselección): Bear, Clean-Cut, Daddy, Discreet, Geek, Jock, Leather, Otter, Poz, Rugged, Trans, Twink, Sober, etc.
- **Etnia**, **identidad de género + pronombres** (set expansivo), **estado de relación**.
- **Looking For** (multi): Right Now, Hookups, Dates, Friends, Networking, Relationship, Chats.
- **Meet At** (multi): My place, Your place, Bar, Café, etc.
- **Salud sexual** (opcional): estado VIH, última prueba, PrEP, recordatorios de testeo.
- **Tags/intereses** (buscables), **enlaces sociales**, **insignia verificado**.

### 7.3 Grid & descubrimiento (F2)
- **Cascada/grid** de perfiles cercanos ordenados por proximidad; **online now**; **Right Now** (activos para quedar ya).
- **Distancia** con opción **ocultar distancia**.
- **Filtros**: Free (edad, online, posición, looking-for, tribes) · **Avanzados (X)**: altura, peso, body type, estado de relación, "con foto", "no chateados aún", verificados, fresh faces.
- Límite de perfiles: Free (limitado) · **X** (hasta 600) · **U** (ilimitado).
- **Explore / Roam (F6)**: situar tu perfil en otra ubicación para viajes. **Discover** (curado).
- **For You** y **A-List** (recomendaciones IA, F6).
- **Favoritos** (vista), **Viewed Me** (**X**), búsqueda por tags.

### 7.4 Interacciones (F2)
- **Taps** (tipos configurables tipo "Looking/Hot/Friendly").
- **Favorito (star)**, **Bloquear**, **Reportar** (aplicados en servidor).

### 7.5 Chat en tiempo real (F3)
- Mensajería 1:1 en tiempo real: **texto/emoji**, **fotos privadas**, **fotos efímeras (1 vista / 10s)**, **audio**, **ubicación**, **compartir álbum**.
- **Typing indicator** y **read receipts** (ver typing = **U**).
- **Unsend** mensaje/foto (**U**), **traducción de chat** (**U**), frases guardadas/quick replies.
- Lista de conversaciones, badges de no leídos, **push** por mensaje.
- Bloquear/reportar desde el chat, filtro de spam/solicitudes.
- **Chat Summaries** (IA, F6).
- **Los chats no se moderan por contenido** (solo hash-match legal de imágenes, §10).

### 7.6 Álbumes privados (F5)
- Crear álbumes de fotos privadas; **compartir/dejar de compartir** con usuarios concretos; shares con expiración; ver a quién compartiste / quién te compartió.

### 7.7 Premium & pagos (F4)
- **XTRA**: sin ads, 600 perfiles, filtros avanzados, Viewed Me, envío multi-foto, ver solo online/con foto.
- **Unlimited**: todo XTRA + **Incógnito**, **Unsend**, lista **Views** completa, **traducción**, **ver typing**, perfiles ilimitados.
- **Free**: límites de perfiles, ads, filtros básicos.
- Compra/restauración, upgrade/downgrade, gestión de suscripción (**RevenueCat**); **gates verificados en servidor**.

### 7.8 Seguridad, privacidad y ajustes (transversal, base en F0)
- **Ocultar distancia**, **Incógnito (U)**, **Safety zones** (enmascarar ubicación en zonas sensibles), avisos de seguridad en regiones hostiles.
- **Icono discreto**, **PIN/biometría**, gestión de bloqueados, aviso de capturas.
- Preferencias de notificaciones, idioma, borrado/exportación de datos.

### 7.9 Notificaciones (F3)
- **Push** (APNs/FCM): mensajes, taps, álbumes compartidos. Email e in-app. Preferencias granulares.

### 7.10 Moderación & confianza (F1 base → F5 avanzada)
- Reportes de usuarios/contenido → **cola de moderación** → acciones (warn/suspend/ban).
- **Moderación NSFW de fotos** (modelo de desenfoque, §10) · **verificación de perfil**.
- **Hash-match de contenido ilegal** en toda imagen (§10).

### 7.11 IA — Wingman (F6)
- Asistente de **creación de perfil**, **ice-breakers**, **resúmenes de chat**, **For You**, **A-List**. Motor: **Claude (Anthropic)**.

---

## 8. Diseño de tiempo real

- **Conexión:** cliente abre WSS a `realtime`, autentica con JWT de acceso. Registro de **presencia** en Redis con clave TTL refrescada por heartbeat; al expirar → offline.
- **Chat:** mensaje entrante → `api`/`realtime` lo **persiste en Postgres** y **publica** en canal Redis `conv:{id}`. Los nodos `realtime` suscritos entregan a los miembros conectados; si el destinatario está offline → el `worker` envía **push**.
- **Typing/visto:** eventos efímeros vía Redis pub/sub (no se persisten salvo `last_read_at`).
- **Grid en vivo:** updates de ubicación → Redis `GEOADD` + Postgres; "cercanos" vía `GEOSEARCH` (radio/orden por distancia) con overlay de presencia. Re-fetch incremental + eventos de "nuevo cercano".
- **Escala:** múltiples nodos `realtime` sin estado compartido salvo Redis (pub/sub + presencia). Sticky no requerido.

---

## 9. Geolocalización

- **Fuente de verdad:** PostGIS (`GEOGRAPHY(Point,4326)`) para persistencia y consultas complejas.
- **Camino caliente:** Redis GEO para el grid "quién está cerca ahora" (sub-ms, evita golpear PG).
- **Privacidad:** redondeo/*fuzzing* de coordenadas según ajustes; `show_distance`; **safety zones** que enmascaran o cancelan la publicación de ubicación; auto-ocultar en regiones de riesgo.
- **Roam (F6):** `roam_geog` sobreescribe la ubicación publicada sin tocar la real.

---

## 10. Moderación de imágenes (definición precisa)

### 10.1 NSFW (modelo de desenfoque) — detección solo cliente
1. Al subir una **foto de perfil**, **NSFWJS corre en el dispositivo** (web: tfjs; móvil: tfjs-react-native). Coste de inferencia en servidor = **0**.
2. Si se clasifica como NSFW (Porn/Hentai/Sexy según umbral), la foto **no se rechaza**: se marca `is_nsfw=true` al subir.
3. El **servidor** genera dos renditions en R2: **`blur_key`** (versión borrosa) y la **nítida** (original). *(La generación del blur/entitlement es un asunto de servido, no re-clasificación: respeta "detección solo cliente".)*
4. **Servido según plataforma + entitlement:**
   - **Móvil (iOS/Android):** NSFW → **siempre borrosa** (cumplimiento App Store/Play).
   - **Web + usuario Free:** **borrosa**.
   - **Web + usuario con suscripción:** **nítida**.
   - SFW → nítida en todas partes.
5. **Seguridad:** la URL de la versión nítida es **firmada y de corta vida**, entregada **solo** a viewers con derecho. El bucket R2 es privado. Un cliente manipulado **no** puede obtener la nítida (nunca se le envía).

> Nota de riesgo aceptada por el equipo: como la *detección* NSFW es client-side, un cliente manipulado podría subir una foto NSFW marcándola como SFW. Mitigación: re-evaluación bajo demanda en `worker` ante **reportes**, y el grid público asume "perfil SFW por defecto". No hay re-clasificación proactiva en servidor (decisión de coste).

### 10.2 Contenido ilegal (hash-match) — servidor, toda imagen
- **Toda** imagen subida (perfil, álbum y **chat**) pasa por **hash-matching** contra listas de material ilegal conocido. Implementación recomendada: **Cloudflare CSAM Scanning Tool** (gratis, integra con R2/CDN Cloudflare); interfaz `IllegalContentScanner` desacoplada para sustituir por PhotoDNA/NCMEC/Thorn Safer si hiciera falta.
- Esto **no** es moderación de conversaciones: no se lee texto ni se juzga contenido adulto consentido. Es un salvaguarda legal estrecho.
- Hit → bloqueo inmediato + registro en `csam_hits` + flujo de reporte a la autoridad correspondiente (NCMEC u homólogo) según jurisdicción.

---

## 11. Monetización & entitlements

- **RevenueCat** como capa única sobre **App Store**, **Google Play** y **Stripe** (web).
- Webhooks de RevenueCat → backend actualiza `subscriptions` → deriva `entitlements`.
- **Gates verificados en servidor** en cada función premium (filtros avanzados, incógnito, viewed-me, unsend, límite de grid, NSFW nítida en web). El cliente nunca decide por sí solo.
- Restauración de compras, upgrade/downgrade, periodos de gracia, reintentos de cobro.

---

## 12. Seguridad — programa de "0 vulnerabilidades conocidas"

> Cero vulnerabilidades *garantizadas* es imposible en cualquier software; el objetivo real y alcanzable es **0 vulnerabilidades conocidas** mediante defensa en profundidad y auditoría continua. Estándar guía: **OWASP ASVS L2** + OWASP Top 10 (Web/API/Mobile).

- **Auth:** argon2id; JWT de acceso corto + refresh rotatorio con revocación; OAuth con **PKCE**; tokens en Keychain/Keystore; 2FA opcional; detección de login sospechoso.
- **Transporte:** TLS 1.3, HSTS, **cert pinning** en móvil.
- **AuthZ:** comprobaciones por recurso; **bloqueos/visibilidad/entitlements siempre en servidor**.
- **Entrada:** validación estricta (`serde` + `validator`); **sqlx** con queries parametrizadas verificadas en compilación (sin SQL crudo).
- **Media:** R2 privado; URLs prefirmadas de corta vida; nítida NSFW solo a entitled.
- **Secretos:** AWS Secrets Manager / SSM; nada en el repo; inyección por entorno.
- **Borde:** Cloudflare **WAF** + **DDoS** + **Turnstile** (anti-bot en flujos web); rate-limiting (Redis) por IP/usuario/acción.
- **Supply chain:** `cargo audit` + `cargo deny` + `pnpm audit` + Renovate/Dependabot; lockfiles; **Trivy** (escaneo de imágenes).
- **SAST/DAST:** `clippy` + **Semgrep**; **OWASP ZAP**; **pentest** antes de producción; bug bounty post-launch.
- **Privacidad:** cifrado en reposo (Neon/R2); **cifrado a nivel de campo** para datos de salud (GDPR Art. 9); fuzzing de ubicación; minimización y retención mínima de datos; `audit_log`.
- **Abuso/DoS:** límites de conexión WS, rate-limit por acción (taps/mensajes), anti-evasión de baneos por device fingerprint.

---

## 13. Privacidad & cumplimiento (global)

- **Edad:** verificación 18+ obligatoria; age-gate; bloqueo de menores.
- **GDPR/CCPA:** consentimiento granular versionado; **derecho de acceso/exportación**; **derecho al olvido** (purga en cascada PG + R2); base legal documentada; DPA con subprocesadores (Neon, Cloudflare, AWS, RevenueCat, Anthropic).
- **Datos especiales (salud sexual):** cifrado + acceso auditado + consentimiento explícito.
- **Ubicación:** controles de usuario, fuzzing, safety zones, avisos en regiones hostiles.
- **Transparencia:** política de privacidad, centro de confianza, registro de subprocesadores.
- **Stores:** cumplir App Store Review Guidelines y Google Play (NSFW siempre borroso en móvil, age-gate, reporte/bloqueo accesibles).

---

## 14. Optimización de costes (principio transversal)

| Palanca | Ahorro |
|---|---|
| **R2 (egress gratis)** + CDN Cloudflare | Servir media (lo más pesado) **no** genera coste de salida |
| **Rust** (baja RAM/CPU, alta concurrencia async) | Menos instancias / instancias más pequeñas en EC2 |
| **EC2 Graviton (ARM)** | Mejor precio/rendimiento que x86 |
| **Neon scale-to-zero** (dev) + autoscaling (prod) | No se paga cómputo ocioso |
| **Redis autoalojado** en el VPS | Sin tarifa de Redis gestionado (datos reconstruibles: presencia/geo/caché) |
| **NSFWJS en cliente** | Coste de inferencia de moderación = 0 |
| **Cloudflare CSAM tool** | Hash-match legal **gratis** |
| **Subidas prefirmadas cliente→R2** | El VPS no transporta media (sin coste de ancho de banda de subida) |
| **Renditions/blur una sola vez** + caché; **AVIF/WebP** | Menos almacenamiento y transferencia |
| **Next.js ISR/SSG** en Vercel | Páginas cacheadas, menos cómputo |
| **Caché de lecturas calientes** (perfiles/grid) en Redis | Menos carga a Neon |
| **Rate-limiting + anti-abuso** | Evita coste inducido por abuso/bots |
| **APNs/FCM** | Push gratuito |

---

## 15. SEO superior (sitio Next.js de marketing)

> La **app de producto va detrás de login → `noindex`** (privacidad). El SEO se concentra en el **sitio Next.js** (marketing/landing/blog/soporte) en Vercel.

- **Render:** SSR/SSG/ISR para todo lo público → HTML completo para crawlers.
- **Metadatos:** Metadata API de Next (title/description/canonical/OG/Twitter) por página.
- **Datos estructurados (JSON-LD):** Organization, WebSite, SoftwareApplication, FAQ, BreadcrumbList.
- **Sitemap.xml** + **robots.txt** dinámicos; URLs canónicas.
- **i18n + hreflang** (`next-intl`) para alcance global; **SEO programático** de landings por ciudad/región ("gay dating en {ciudad}").
- **Core Web Vitals:** LCP/INP/CLS optimizados; `next/image`; fuentes optimizadas; presupuesto de performance.
- **Contenido:** blog/centro de contenidos para keywords; enlaces a stores + deep links + smart banners.
- **Accesibilidad** (a11y) y **Search Console** + analítica respetuosa con la privacidad.

---

## 16. Observabilidad & operaciones

- **Logs/Trazas/Métricas:** `tracing` + OpenTelemetry → stack económico (Grafana/Loki/Tempo autoalojado o SaaS barato).
- **Health checks** + readiness para ALB; **alertas** (latencia, errores, saturación WS, cola del worker).
- **Backups:** Neon PITR; export periódico; runbooks de incidente; rotación de secretos.
- **CI/CD:** GitHub Actions → build/test/audit → imágenes Docker → despliegue a EC2 (blue/green) y Vercel.

---

## 17. Testing & QA

- **Backend:** unit (lógica de dominio), integración (sqlx contra Postgres efímero), contract tests del OpenAPI, carga (WS/grid), `cargo test` + cobertura.
- **Cliente:** unit (lógica/hooks), componentes (RN Testing Library), E2E (Detox móvil / Playwright web), pruebas de NSFWJS y de gates premium.
- **Seguridad:** SAST/DAST en CI, pentest pre-launch.
- **TDD** como práctica por defecto en cada fase (superpowers:test-driven-development).

---

## 18. Roadmap por fases

> **Core primero.** Cada fase produce su **propio spec → plan → implementación**. La paridad 100% se alcanza al completar F1–F6.

- **F0 — Fundaciones:** monorepo + CI; Terraform EC2/Cloudflare; esquema Neon + migraciones base; workspace Rust (api/realtime/worker + libs); auth (email + Apple/Google) + verificación + age-gate + consentimientos; app shell RN + Next.js marketing base; observabilidad y security baseline.
- **F1 — Perfiles & fotos:** campos completos de perfil + taxonomías; subida prefirmada a R2; **NSFWJS cliente + modelo de desenfoque**; hash-match CSAM; ajustes y privacidad base; verificación de perfil.
- **F2 — Grid geolocalizado:** ubicación + Redis GEO + PostGIS; grid por proximidad + presencia online; filtros free; vista de perfil; taps/favoritos/bloquear/reportar.
- **F3 — Chat tiempo real:** gateway WS; conversaciones; mensajes texto/foto/efímera/audio/ubicación; typing/visto; push (APNs/FCM); spam/solicitudes.
- **F4 — Premium & pagos:** RevenueCat + entitlements server-side; XTRA/Unlimited; filtros avanzados; incógnito; viewed-me; unsend; NSFW nítida en web para suscriptores.
- **F5 — Álbumes & moderación avanzada:** álbumes + shares con expiración; cola/dashboard de moderación; safety zones; export/borrado GDPR completos.
- **F6 — Roam/Explore & IA Wingman:** roam/discover; For You/A-List; perfil-IA, ice-breakers y resúmenes de chat con **Claude**.

---

## 19. Riesgos & mitigaciones

| Riesgo | Mitigación |
|---|---|
| NSFW client-side es saltable | Servido entitlement-gated (nítida nunca se filtra) + re-evaluación ante reportes; SFW por defecto en grid |
| Single VPS = punto único de fallo | Migrar a ALB + ASG multi-AZ al escalar; Neon/R2 ya gestionados/replicados |
| Obligaciones legales CSAM | Hash-match en toda imagen + flujo de reporte a autoridades documentado |
| Regiones hostiles a LGBTQ+ | Safety zones, ocultar distancia automático, avisos, icono discreto |
| Cumplimiento de stores (NSFW) | Móvil siempre borroso + age-gate + reporte/bloqueo visibles |
| Coste descontrolado por abuso | Rate-limiting, WAF, Turnstile, anti-evasión de baneo |
| Paridad incompleta | Catálogo §7 como checklist de aceptación por fase |

---

## 20. Apéndice — taxonomías (valores iniciales, ajustables)

- **Posición:** Top · Vers Top · Versatile · Vers Bottom · Bottom · Side.
- **Tribes:** Bear · Clean-Cut · Daddy · Discreet · Geek · Jock · Leather · Otter · Poz · Rugged · Trans · Twink · Sober.
- **Looking For:** Right Now · Hookups · Dates · Friends · Networking · Relationship · Chats.
- **Meet At:** My place · Your place · Bar · Café · Public.
- **Body type:** Slim · Average · Athletic · Muscular · Stocky · Large.
- **Relación:** Single · Dating · Partnered · Married · Open · Exclusive · Committed.
- **HIV status:** Negative · Negative on PrEP · Positive · Positive Undetectable · No responde.
- **Tap types:** Looking · Hot · Friendly.
- **Tiers:** Free · XTRA · Unlimited.

*(Identidad de género, pronombres y etnia: usar sets expansivos definidos en `packages/shared` y revisados con criterio inclusivo.)*

---

### Fuentes de investigación (Grindr 2025/2026)
- Grindr 2025 Product Roadmap (grindr.com/blog) · Grindr XTRA y Unlimited (Help Center) · Build Your Profile / Filters (Help Center) · In-app privacy features (Help Center) · Bloomberg: Grindr + Anthropic Claude (Wingman).
