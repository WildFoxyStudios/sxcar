# Frontend Flutter + FRB v2 + Panel admin · Plan de ejecución

Specs:
- `docs/superpowers/specs/2026-06-27-flutter-frb-frontend-design.md`
- `docs/superpowers/specs/2026-06-27-admin-panel-design.md`

Método: subagent-driven (implementador + revisor por tarea; revisión final por fase). **Spec/plan antes de código.** Backend/infra (Lightsail+Neon, R2, túnel, CORS, media) y marketing Next.js **intactos**.

## Prerrequisitos del toolchain (verificar/instalar en F1.1)
- Flutter SDK (canal stable) + soporte web habilitado.
- Rust targets: `aarch64-linux-android` `armv7-linux-androideabi` `x86_64-linux-android` (Android), `aarch64-apple-ios` `aarch64-apple-ios-sim` (iOS), `wasm32-unknown-unknown` (web).
- `cargo-ndk` (Android), Xcode (iOS, requiere macOS + cuenta Apple Developer del usuario — fuera de banda), `flutter_rust_bridge_codegen` v2, `wasm-pack`/`build-web` de FRB.
- Estado: **Riverpod** + **go_router**.

## Roadmap por fases
| Fase | Entregable |
|---|---|
| **F1.0** | crate `core` extraído (backend verde, sin cambio de comportamiento) |
| **F1.1** | scaffold `apps/app` + `native` + FRB v2 "hola tipado" en Android/iOS/Web |
| **F1.2** | slice **auth** (register/login/verify) en 3 targets contra backend en vivo |
| **F1.3** | motor **NSFW** (tract+ONNX) + API FRB + integración en subida |
| **F1.4** | **imagen** (resize/encode/thumbnail/blur preview) + presigned PUT a R2 |
| **F1.5** | **MessagePack** + content-negotiation (backend+cliente), 1 endpoint hot primero |
| **F1.6** | **deeplinks** Universal/App Links + go_router + AASA/assetlinks |
| **F1.7** | **ads** (capa `AdProvider` + AdMob native móvil, entitlement-gated, verificación de política) |
| **F2.x** | **panel admin** (AD1–AD5 del spec del admin) |
> Luego: features de producto (grid+geo, perfiles, chat, notificaciones FCM, renditions blur/clear server-side, CSAM).

---

## F1.0 — Crate `core` (camino crítico, detallado)
**Objetivo:** una sola fuente de verdad de modelos+validación, compartida backend↔app, cross-compilable (host + wasm + móvil). Sin cambiar el comportamiento del backend.
- **T1:** crear `backend/crates/core` (lib; deps: `serde` derive, `time` si hace falta; **prohibido** `sqlx`/`tokio`/red). Añadir al workspace.
- **T2:** mover a `core` los DTOs de auth (`RegisterReq`,`LoginReq`,`TokenPair`,`RefreshReq`,`CodeReq`) y la **validación** (`valid_email`, age-gate `is_adult`, reglas de password). `api`/`auth` importan desde `core` (re-export para no romper rutas internas).
- **T3:** verificación: `cargo build` + **todos los tests existentes verdes** + clippy `-D warnings` + `cargo audit`. Además `cargo build -p core --target wasm32-unknown-unknown` (prueba que cross-compila).
- **Acept.:** comportamiento backend idéntico (suite verde); `core` compila a host y wasm; 0 deps de runtime en `core`.

## F1.1 — Scaffold Flutter + FRB v2 (detallado)
**Objetivo:** probar el camino más arriesgado (FRB v2 + WASM + cross-compile) con un "hola" tipado, en los 3 targets.
- **T1:** `flutter create apps/app` (plataformas: ios, android, web). Estructura `lib/` + Riverpod + go_router base.
- **T2:** `apps/app/native` (crate Rust cdylib+staticlib) con dep `path` → `core`; exponer 1 función FRB real, p.ej. `validate_email(s: String) -> bool` (usa `core`).
- **T3:** integrar `flutter_rust_bridge_codegen` v2 (script `tool/codegen`); generar bindings (+`--wasm`). Llamar la función desde Dart y mostrar el resultado en una pantalla.
- **T4:** construir/ejecutar: **Android** (cargo-ndk), **Web** (`build-web`, WASM single-thread), **iOS** (xcframework; si no hay runner mac, dejar documentado el paso y validar al menos que compila la lib iOS). 
- **T5:** scripts de build (`melos`/Makefile) + doc DX (codegen + run por target).
- **Acept.:** `validate_email` se llama desde Dart y da el mismo resultado en Android y Web (iOS si hay mac); CI compila web+android.

## F1.2 — Slice auth en 3 targets (detallado)
**Objetivo:** flujo auth real contra `api.turnend.win` (ya con CORS), validando todo el pipeline antes de features.
- **T1:** capa de red Dart (`dio`) → `https://api.turnend.win`; almacenamiento seguro de tokens (`flutter_secure_storage`); interceptor **401→refresh→retry**.
- **T2:** validación pre-submit vía FRB/`core` (`validate_register`: email/edad 18+/password).
- **T3:** pantallas **login / register (age-gate + consentimientos) / verify-email** + gating de sesión (go_router redirect).
- **T4:** ejecutar en Android/iOS/Web; **E2E**: register → (código del log/flujo dev) → verify → login, contra Lightsail+Neon.
- **T5:** tests: widget/golden de pantallas + integration_test del flujo; unit de la capa de red.
- **Acept.:** auth completo funcional en los 3 targets contra el backend en vivo; tests verdes.

---

## F1.3 — NSFW (outline; se detalla al llegar)
`apps/app/native`: `tract-onnx` + modelo ONNX (linaje GantMan/open_nsfw, pequeño, asset). API FRB `nsfw_classify(bytes)->veredicto`, fuera del isolate de UI. Integrar en el flujo de subida de foto de perfil (marcar NSFW). Tests con fixtures sfw/nsfw. Acept.: mismo veredicto en los 3 targets; sin jank.

## F1.4 — Imagen (outline)
`image` crate en `native`: resize/recompress/reencode + thumbnail + blur de preview + strip EXIF, **antes** de subir. Integrar con `POST /media/upload-url` (presigned PUT a R2, ya existe). Acept.: subida directa a R2 desde la app con imagen procesada en cliente.

## F1.5 — Protocolo MessagePack (outline)
Backend axum: content-negotiation (`Accept`/`Content-Type`: `application/json` ↔ `application/msgpack` con `rmp-serde`) sobre los DTOs de `core`. Cliente: Dart pasa bytes, `core` (de)serializa msgpack. Empezar por **1 endpoint hot** (p.ej. el futuro grid) y JSON de fallback. Disciplina de versionado aditivo. Acept.: el endpoint responde JSON o msgpack según cabecera; payload msgpack más pequeño; clientes viejos (JSON) siguen funcionando.

## F1.6 — Deeplinks (outline)
AASA (`apple-app-site-association`) + `assetlinks.json` servidos en `turnend.win`/`app.turnend.win` (Vercel y/o API). go_router maneja rutas; links de marketing/perfil/share abren la app si está instalada. Acept.: un link de perfil abre la app nativa (iOS/Android) y la ruta correcta en web.

## F1.7 — Ads (outline)
Capa **`AdProvider`** agnóstica; impl **AdMob** (`google_mobile_ads`) con **native ads** en la cascada, **entitlement-gated** (cero ads para pago). **Paso explícito: verificar política AdMob** para el nicho adult/dating ANTES de integrar a fondo; fallback a red/mediación dating-friendly si rechaza. Web sin ads. Acept.: free ve native ads no intrusivos en móvil; pago no ve ninguno; gating server-authoritative.

## F2.x — Panel admin (outline; ver spec dedicado)
AD1 identidad staff+RBAC+2FA+audit → AD2 usuarios+audit viewer → AD3 moderación+CSAM → AD4 soporte+GDPR → AD5 analítica+flags+broadcast. `apps/admin` Flutter web; APIs `/admin/*` (RBAC+audit); migraciones nuevas (`staff`/roles/`feature_flags`/`staff_sessions`). Guardarraíles obligatorios.

## Gates / riesgos
- **F1.1 es gate de viabilidad** del toolchain (FRB v2 + WASM + cross-compile). Si algo del WASM no cuadra, se decide ahí (single-thread ya elegido para evitar COOP/COEP).
- iOS requiere macOS + cuenta Apple Developer del usuario (fuera de banda) — Android+Web se validan en CI; iOS cuando haya runner.
- Cada fase: tests + (donde aplique) E2E contra el backend en vivo + revisión.
