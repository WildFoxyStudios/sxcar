# Frontend Flutter + flutter_rust_bridge v2 (app de producto móvil + web) · Design

**Fecha:** 2026-06-27
**Tipo:** Pivot de arquitectura de frontend (reemplaza el shell RN/Expo de F0.4 para la app de producto)
**Estado:** SPEC — no se escribe código hasta aprobación.

## 0. Objetivo
La **app de producto** (móvil iOS+Android **y** web, esta última `noindex` tras login) se construye en **Flutter**, con un **núcleo Rust compartido** vía **`flutter_rust_bridge` v2** (FRB v2). El sitio de **marketing/SEO sigue en Next.js** (ya desplegado, intacto). Todo el backend/infra (Lightsail+Neon, R2, túnel Cloudflare, CORS, auth, media) **no cambia**: la app habla HTTP.

Filosofía: **"cintura fina"** — Flutter/Dart posee UI, estado, navegación y red; Rust posee solo el **núcleo compartido** (modelos/validación/tipos) y el **cómputo pesado** (NSFW, imagen, cripto). No "todo en Rust".

## 1. Decisiones (del usuario, 2026-06-27)
1. **FRB v2** (no v1.82.6 — v1 es legacy).
2. Flutter = app de producto **móvil + web**; Next.js = marketing/SEO.
3. Plataformas desde el inicio: **iOS + Android + Web**.
4. Enfoque "cintura fina" (Rust quirúrgico, no para toda la lógica) — aceptado.
5. **NSFW en Rust** (`tract` + ONNX), **no** `nsfw_detector_flutter` (TFLite, sin web). Orden de módulos Rust: a criterio del autor. Extracción de `core`: a criterio del autor. Primer slice: a criterio del autor, mejores prácticas.

### Por qué NO "todo en Rust por rendimiento"
Dart en release es **AOT a ARM nativo** (no JS interpretado): rápido para lógica de app. Los cuellos de botella de una app social son **red, carga de imágenes y render** (Flutter ya usa GPU/Impeller) — Rust no los arregla. El **puente FFI cuesta** (serializa en cada cruce): para llamadas pequeñas y frecuentes puede ser más lento + más boilerplate, y pierdes hot-reload. El salto de rendimiento vs RN **ya lo da Flutter**. Rust se reserva para **cómputo pesado de grano grueso**.

## 2. Arquitectura "cintura fina"
```
┌───────────────────────── Flutter (Dart) — app de producto ─────────────────────────┐
│  UI / navegación / estado (Riverpod)  ·  HTTP a api.turnend.win (dio)               │
│  almacenamiento seguro de tokens (flutter_secure_storage)  ·  RevenueCat · FCM      │
│                         │  FRB v2 (FFI nativo / WASM en web)                         │
└─────────────────────────┼──────────────────────────────────────────────────────────┘
                          ▼
        ┌──────────────── Rust (compilado dentro de la app) ────────────────┐
        │  crate `app_native` (puente FRB) → expone API de grano grueso     │
        │    • nsfw::classify(bytes) -> veredicto                            │
        │    • imaging::thumbnail/blur_preview(bytes)                        │
        │    • crypto:: (hash/E2E, fase posterior)                           │
        │  depende de →  crate `core` (lógica PURA compartida con backend)   │
        │    • modelos de dominio + DTOs del protocolo (serde)               │
        │    • validación (email, edad 18+, password, etc.)                  │
        └───────────────────────────────────────────────────────────────────┘
                          ▲ (mismo crate `core`)
        ┌─────────────────┴───────────── Backend axum (Lightsail) ──────────┐
        │  crates `api` / `db` / `auth`  →  ahora dependen de `core`         │
        └───────────────────────────────────────────────────────────────────┘
```
**Regla dura:** `core` y `app_native` **no** dependen de `sqlx`/`tokio`/red — solo lógica pura (cross-compilan a móvil y wasm). El backend mantiene su runtime; comparte solo `core`.

### Qué vive dónde
| Responsabilidad | Dueño |
|---|---|
| UI, navegación, estado, formularios, theming | Dart/Flutter |
| HTTP, auth tokens (almacenamiento + refresh), websockets del chat | Dart |
| Modelos de dominio, DTOs del protocolo, validación | **Rust `core`** |
| Detección NSFW (cliente) | **Rust `app_native`** (`tract`+ONNX) |
| Thumbnails / blur de previsualización / reencode | **Rust `app_native`** (`image`) |
| Cripto E2E del chat, hashing (fase posterior) | **Rust `app_native`** |
| Caché/sqlite local | Dart (`drift`) salvo que la lógica pese → Rust |

## 3. Crate `core` (compartido backend ↔ app)
- Nuevo crate en el workspace del backend: `backend/crates/core` (lógica pura).
- **Contenido inicial:** structs de dominio + DTOs de request/response del API (los que hoy viven sueltos en `api`/`auth`, p.ej. `RegisterReq`, `LoginReq`, `TokenPair`), `enum`s de error de validación, y funciones de **validación** (`valid_email`, age-gate 18+, fuerza de password) — hoy duplicables en Dart.
- **Migración no disruptiva:** se mueven tipos/validaciones desde `api`/`auth` a `core`; `api`/`auth` re-exportan o importan de `core`. Sin cambiar el comportamiento del backend (se cubre con los tests existentes).
- **Sin** `serde_json`/HTTP/DB; solo `serde` (derive), `time` si hace falta. Compila a wasm y a móvil.
- La app obtiene **una sola fuente de verdad** de modelos+validación (no se re-implementan en Dart).

## 4. Integración FRB v2
- Crate `apps/app/native` (cdylib + staticlib; depende de `core` por path) — la lib Rust que se compila dentro de Flutter. Expone funciones de **grano grueso** anotadas para FRB.
- **Codegen:** `flutter_rust_bridge_codegen generate` (+ `--wasm` para web). Se commitea el código generado o se genera en build (decisión: generar en build vía script, documentado).
- **Cross-compile:**
  - Android: `cargo-ndk` (arm64-v8a, armeabi-v7a, x86_64).
  - iOS: xcframework (device arm64 + simulador).
  - Web: `flutter_rust_bridge_codegen build-web` (WASM). **WASM single-thread** para NO requerir cabeceras COOP/COEP (cross-origin isolation) — se acepta algo menos de velocidad a cambio de despliegue simple en Vercel/estático. (Si luego se necesita multihilo, se añaden COOP/COEP.)
- **DX:** el ciclo Dart (UI) mantiene hot-reload; solo cambia lento lo que toca Rust (recompilar + codegen). Un script `make codegen` / `melos` orquesta.

## 5. Motor NSFW (Rust, cliente) — requisito *locked*
- **Lib:** `tract-onnx` (Rust puro → compila a nativo y wasm; sin deps C). Alternativa de mayor precisión/peso: ViT NSFW ONNX cuantizado (`AdamCodd/vit-base-nsfw-detector`); arranque con un modelo **MobileNet/GantMan (linaje open_nsfw/NSFWJS)** por tamaño pequeño (apto wasm) y consistencia con la intención original.
- **Modelo** como **asset** del bundle Flutter (cargado por la lib Rust). Documentar licencia del modelo (GantMan/open_nsfw son abiertos).
- **API FRB:** `nsfw_classify(bytes) -> { nsfw_score: f32, verdict: Sfw|Nsfw }` (umbral configurable). Ejecutar **fuera del isolate de UI** (mobile: isolate de FRB; web: en el worker/wasm) → sin jank.
- **Política (alineada con el spec maestro):** la **detección** es **solo cliente**. Al subir una foto de perfil: el cliente la clasifica; si es NSFW se **marca**. Las **renditions blur/clear servidas** las produce el **servidor** (R2, entitlement-gated: en móvil siempre blur por App Store/Play; en web blur para free, clear solo para suscriptor) — el cliente nunca filtra la versión clara a quien no tiene derecho. El chat **no** se modera por contenido (sí hash-match CSAM en todas las imágenes — fase posterior).
- Un mismo motor → **mismo veredicto en iOS, Android y web**.

## 6. Imagen (Rust, cliente)
- `image` crate: thumbnails, blur de **previsualización local** (no autoritativa), reencode/normalización antes de subir a R2 (presigned PUT ya existe: `POST /media/upload-url`).
- La rendición blur/clear **autoritativa** es server-side (fase de media-server posterior).

## 7. Red y auth (Dart)
- `dio` → `https://api.turnend.win` (CORS ya permite la app). Modelos de request/response = los DTOs de `core` (espejados a Dart por FRB o por modelos Dart generados; decisión: exponer (de)serialización vía `core`/FRB para una sola verdad).
- Tokens: `flutter_secure_storage`; lógica de **refresh 401→refresh→retry** en Dart (igual que el shell RN), reusando validaciones de `core` donde aplique.
- Realtime del chat (websockets) = Dart; payloads tipados desde `core`.

## 8. Ecosistema Flutter
- Estado: **Riverpod**. Rutas: **go_router** (deep links + URL web). i18n: `flutter_localizations`/`intl`.
- Pagos: **`purchases_flutter`** (RevenueCat). Push: **`firebase_messaging`** (proyecto Firebase `foxy-85ecb` ya disponible; FCM server-side con el admin SDK en fase de notificaciones). Media: `image_picker`/`file_picker`. Mapas/geo: a decidir (Mapbox/Google) en la feature de grid.

## 9. Estructura del repo
```
apps/
  app/                  # Flutter (producto, móvil+web)
    lib/ … (UI Dart)
    native/             # crate Rust del puente FRB (cdylib/staticlib), dep path → core
    assets/models/      # modelo ONNX NSFW
  admin/                # Flutter web (panel de staff)  [ver §17]
    native/             # (opcional) puente FRB del admin, dep path → core
  marketing/            # Next.js (SEO) — sin cambios
backend/
  crates/
    core/               # NUEVO: lógica pura compartida (modelos+validación)
    api/ db/ auth/      # backend; api/auth pasan a depender de core
```
- `apps/mobile` (RN/Expo de F0.4) **ELIMINADO** (commit del pivot) — queda en el historial git.
- `core` vive en el workspace del backend; `apps/app/native` y `apps/admin/native` son crates independientes con dep `path` a `../../backend/crates/core` (no se fuerza un workspace raíz, menos invasivo).

## 10. Primer slice vertical (valida TODO el toolchain antes de features)
**Auth en Flutter contra el backend en vivo, en iOS+Android+Web:**
1. `core`: extraer `RegisterReq/LoginReq/TokenPair` + validaciones (email/edad/password) y que el backend siga verde.
2. `apps/app/native`: exponer por FRB `validate_register(...)` (usa `core`) — prueba el puente con lógica real compartida.
3. Flutter: pantallas login/registro/verify (Dart) → `dio` a `api.turnend.win`; validación previa vía FRB/`core`; gating + almacenamiento seguro de tokens.
4. Correr en **los 3 targets**: Android (cargo-ndk), iOS (xcframework), Web (WASM single-thread) — confirmando el cross-compile + codegen end-to-end.
5. E2E: registro→verify→login real contra Lightsail+Neon (ya probado a nivel API).

Esto **prueba el camino más arriesgado (FRB v2 + WASM + cross-compile) con la feature más simple** antes de invertir en features grandes.

## 11. Orden de construcción (fases sugeridas)
- **FA**: `core` extraído + backend verde (sin tocar comportamiento).
- **FB**: scaffold Flutter `apps/app` + `native` + FRB v2 "hola mundo" tipado en los 3 targets (incl. WASM).
- **FC**: slice de auth (sección 10) end-to-end en los 3 targets.
- **FD**: motor NSFW Rust (`tract`+modelo) + API FRB + demo de clasificación al subir.
- **FE**: imagen (thumbnails/reencode) + integración con el presigned upload a R2.
- Luego: features de producto (grid+geo, perfiles, chat…) sobre esta base.

## 12. Testing
- Rust: tests unit de `core` (validación), `app_native` (NSFW con imágenes fixture sfw/nsfw, imaging). 
- Dart: widget tests + golden tests de pantallas; integration_test para el flujo auth.
- E2E: contra el backend en vivo (como ya se hace).
- CI: matriz que (a) corre tests Rust+Dart, (b) construye los 3 targets (al menos compila web+android en CI; iOS en runner mac si está disponible).

## 13. Riesgos y mitigaciones
- **Madurez FRB web/WASM**: real pero usable; mitigación = WASM single-thread (sin COOP/COEP), validado en el slice FB antes de comprometerse.
- **Tamaño del modelo NSFW en web**: usar modelo pequeño/cuantizado; cargar perezoso (solo al primer upload).
- **Complejidad de build (3 targets + Rust)**: encapsular en scripts/`melos`; CI por target.
- **iOS signing/certificados**: requiere cuenta Apple Developer del usuario (fuera de banda).
- **Precisión/licencia del modelo NSFW**: validar con set de prueba; documentar licencia; umbral ajustable.
- **Pérdida de hot-reload en Rust**: aceptable (Rust cambia poco; la UI conserva hot-reload).

## 14. Fuera de alcance (de este spec)
- Renditions blur/clear server-side (fase media-server), hash-match CSAM, features de producto (grid/geo/perfiles/chat), notificaciones FCM. Se especifican aparte.

## 15. Decisiones que tomé (confírmalas en revisión)
- App Flutter en `apps/app`; **`apps/mobile` (RN) ELIMINADO**. Estado: **Riverpod** + **go_router**.
- `core` en el workspace del backend; `native` como crate independiente con dep path.
- NSFW: `tract`+ONNX, arranque con modelo linaje GantMan/open_nsfw (pequeño, wasm-friendly).
- WASM **single-thread** (sin COOP/COEP) para simplificar el deploy web.
- Codegen FRB **en build** (script), no commiteado.
- Slice inicial = **auth en los 3 targets**.
- **Carga al cliente** maximizada; servidor solo retiene autoridad/seguridad/legal (§16).
- **Panel admin** = `apps/admin` (Flutter web) con RBAC + audit + 2FA; merece spec propio (§17).
- **Deeplinks** = Universal/App Links nativos + go_router (no Firebase Dynamic Links) (§18).
- **Ads** = AdMob native solo móvil, entitlement-gated — **sujeto a verificar política adult/dating** (§19).
- **Protocolo** = MessagePack + content-negotiation (JSON fallback), por fases en hot paths (§20).

## 16. Principio: máxima carga al cliente (backend delgado)
Delegar al cliente **todo el CÓMPUTO** que no requiera autoridad del servidor → backend más barato (pilar coste) y app más reactiva. Lo hace Rust (`app_native`) fuera del isolate de UI.
- **Al cliente (Rust):** redimensionar/recomprimir/reencode de imagen antes de subir, thumbnails, **detección NSFW**, blur de previsualización, strip de EXIF, hashing perceptual (dedupe local), cálculo de distancia/geo, filtrado/orden/búsqueda de listas cacheadas, cripto E2E.
- **Queda en el servidor (NO delegable — autoridad/seguridad/legal):** authN/authZ, **gating de entitlements** (quién ve clear vs blur), rate-limiting, decisiones de abuso/trust, **hash-match CSAM** (legal: server/edge), validación de pagos (webhooks RevenueCat), integridad y fuente de verdad.
- **Límite de confianza (clave):** el servidor **nunca confía** en afirmaciones del cliente para seguridad. El veredicto NSFW del cliente es UX; el servidor sigue tratando toda subida como no confiable (sirve renditions gated + corre el hash CSAM). "Delegar cómputo" ≠ "delegar confianza".

## 17. Panel de administración (`apps/admin`, Flutter web)
App **Flutter web** separada, solo-staff, tras auth fuerte. Potente y versátil, **con guardarraíles no negociables** (protegen al usuario y al negocio de abuso interno y de responsabilidad legal).
- **Capacidades:** gestión de usuarios (buscar, ver perfil completo, estado, ban/suspensión/shadowban, force-logout, reset, *impersonación-para-soporte* auditada), **moderación** (cola de reportes, cola NSFW, hits CSAM del escaneo automático, aprobar/rechazar/takedown de media de perfil), **trust&safety** (señales de abuso, inteligencia device/IP), **soporte** (estado de cuenta, suscripciones/entitlements de RevenueCat, reembolsos, plantillas), **analítica** (DAU/MAU, embudos, ingresos, métricas de moderación), **feature flags/remote config**, **broadcast/notificaciones**, **visor de audit log**.
- **Guardarraíles (obligatorios):** RBAC con **mínimo privilegio** (support < moderator < admin < superadmin), permisos por acción; **audit log inmutable** (quién, qué, a quién, cuándo, por qué) de toda acción intrusiva; **2FA obligatorio** para staff + (opcional) allowlist de IP + sesiones cortas; acceso a PII **acotado por propósito** y registrado (GDPR).
- **Techo técnico+legal de "intrusivo":** si el chat es **E2E**, los admins **no** pueden leer mensajes privados en silencio (rompería E2E + GDPR + confianza). La moderación de chat es **basada en reportes** (el reportante divulga el contenido) + **CSAM automático** por hash. La intrusividad llega hasta donde es **lícita y técnicamente sólida**; todo lo demás (todo lo que el servidor almacena: perfiles, media, metadatos) sí es accesible por staff con scope+auditoría.
- **Backend:** APIs admin RBAC-gated y auditadas (autoridad de servidor legítima; no contradice §16). 
- Por tamaño, el admin merece **su propio spec detallado**; aquí queda el marco y los guardarraíles.

## 18. Deeplinks web → app móvil
- **iOS Universal Links + Android App Links:** publicar `apple-app-site-association` (AASA) y `assetlinks.json` en el dominio (`turnend.win` y/o `app.turnend.win`), servidos por el sitio Vercel y/o el API.
- **`go_router`** maneja las rutas in-app; la misma estructura de URL sirve en Flutter web y hace deep-link a la app nativa si está instalada (CTAs de marketing, links de perfil compartidos, share sheet).
- Deferred deep-linking (instalar→ruta) opcional; Firebase Dynamic Links está descontinuado → usar Universal/App Links nativos (+ solución propia de diferido si se necesita, no FDL).

## 19. Publicidad de Google (free, no intrusiva, integrada)
- **Móvil (iOS/Android):** **AdMob** (`google_mobile_ads`) con **native ads** integrados en la cascada/grid (cada N tiles) y placements patrocinados — **no** interstitials molestos. **Entitlement-gated:** los suscriptores ven **cero** anuncios.
- **⚠️ RIESGO DE POLÍTICA (importante):** AdMob/AdSense tienen **políticas estrictas sobre contenido sexual/adulto y citas**. Una app LGBTQ+ 18+ tipo ligue puede quedar **restringida o rechazada**, con fill/eCPM bajos o riesgo de suspensión de cuenta. **Decisión pendiente del usuario** (ver preguntas): (a) verificar política AdMob + rating de contenido, (b) usar redes de anuncios **dating/adult-friendly** o mediación que filtre inventario, (c) limitar anuncios a superficies "seguras". No comprometer monetización a AdMob sin validar esto.
- **Web:** `google_mobile_ads` es **solo móvil**; Flutter web no tiene AdMob → web sin anuncios al inicio (o AdSense/GAM aparte, con las mismas restricciones de contenido).

## 20. Protocolo binario (eliminar JSON innecesario) — respuesta a "¿qué crees?"
**Sí, vale la pena y encaja**, porque ambos extremos son Rust+serde compartiendo `core`: adoptar binario es casi gratis y da payloads más pequeños (menos datos móviles/batería) + encode/decode más rápido en hot paths.
- **Recomendado: MessagePack (`rmp-serde`) como formato principal app↔backend, con content-negotiation HTTP (`Accept`/`Content-Type`) y JSON como fallback siempre disponible** (debug, tooling web, terceros: webhooks, RevenueCat, marketing).
- **NO `bincode`/`postcard` para la API pública:** acoplados al esquema y frágiles entre versiones de la app (cliente viejo + server nuevo → corrupción silenciosa). Para una app móvil con muchas versiones en producción hace falta un formato **auto-descriptivo/evolucionable** → MessagePack (como JSON pero binario) o Protobuf. MessagePack+serde es lo de menor fricción dados los DTOs serde de `core`.
- **Dónde más rinde:** tráfico alto/frecuente — grid de cercanos, presencia/typing, updates de geo, mensajes de chat (frames binarios por websocket). En endpoints de baja frecuencia (auth) JSON está bien (debugabilidad).
- **Disciplina de versionado:** evolucionar DTOs **aditivamente** (`#[serde(default)]`, campos opcionales), nunca reppropósito de campos; versionar la API; ambos extremos comparten `core` (lockstep por release) pero **las versiones viejas persisten** → mantener compat hacia atrás siempre.
- **Fases:** ya enviamos JSON (funciona); introducir MessagePack vía content-negotiation cuando lleguen los hot paths (feed/chat). No arrancar JSON de auth prematuramente (poca ganancia, pierdes debug). La media ya es binaria (presigned PUT) — ahí no hay "impuesto JSON".

## Fuentes (verificación 2026-06-27)
- nsfw_detector_flutter (TFLite/open_nsfw, móvil): https://pub.dev/packages/nsfw_detector_flutter
- FRB v2 web/WASM: https://cjycode.com/flutter_rust_bridge/manual/miscellaneous/web-cross-origin · https://github.com/fzyzcjy/flutter_rust_bridge
- NSFW en Rust: https://github.com/Fyko/nsfw (GantMan/tract) · https://huggingface.co/AdamCodd/vit-base-nsfw-detector
