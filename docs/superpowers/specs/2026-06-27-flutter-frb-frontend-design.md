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
  app/                  # Flutter (producto, móvil+web)  [reemplaza apps/mobile]
    lib/ … (UI Dart)
    native/             # crate Rust del puente FRB (cdylib/staticlib), dep path → core
    assets/models/      # modelo ONNX NSFW
  marketing/            # Next.js (SEO) — sin cambios
backend/
  crates/
    core/               # NUEVO: lógica pura compartida (modelos+validación)
    api/ db/ auth/      # backend; api/auth pasan a depender de core
```
- `apps/mobile` (RN/Expo de F0.4) queda **deprecado**; se elimina cuando el slice de auth en Flutter esté verde (no antes, para no perder referencia).
- `core` vive en el workspace del backend; `apps/app/native` es un crate independiente con dep `path` a `../../backend/crates/core` (no se fuerza un workspace raíz, menos invasivo).

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
- App Flutter en `apps/app` (deprecando `apps/mobile`). Estado: **Riverpod** + **go_router**.
- `core` en el workspace del backend; `native` como crate independiente con dep path.
- NSFW: `tract`+ONNX, arranque con modelo linaje GantMan/open_nsfw (pequeño, wasm-friendly).
- WASM **single-thread** (sin COOP/COEP) para simplificar el deploy web.
- Codegen FRB **en build** (script), no commiteado.
- Slice inicial = **auth en los 3 targets**.

## Fuentes (verificación 2026-06-27)
- nsfw_detector_flutter (TFLite/open_nsfw, móvil): https://pub.dev/packages/nsfw_detector_flutter
- FRB v2 web/WASM: https://cjycode.com/flutter_rust_bridge/manual/miscellaneous/web-cross-origin · https://github.com/fzyzcjy/flutter_rust_bridge
- NSFW en Rust: https://github.com/Fyko/nsfw (GantMan/tract) · https://huggingface.co/AdamCodd/vit-base-nsfw-detector
