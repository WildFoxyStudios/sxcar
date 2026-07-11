# Spec: Completitud funcional y de calidad — diseño e identidad propios

**Fecha:** 2026-07-09
**Autor:** revisión asistida sobre el estado real del repo (no basada en inspección de apps de terceros)
**Alcance:** cerrar los huecos funcionales, de seguridad y de calidad de `proyecto-X` como producto **original** de citas geolocalizadas.
**Reemplaza el enfoque de:** los specs previos de "paridad Grindr". Este documento parte de una premisa distinta: construir un producto propio, no replicar la ejecución concreta de un competidor.

---

## 0. Cambio de premisa (leer primero)

Los specs anteriores (`2026-07-02-grindr-ui-parity`, `2026-07-04-grindr-100-parity`) definen la "fuente de verdad" como capturas de una app propietaria y fijan tokens de color y layouts calcados de ella. Eso es reproducción de interfaz y *trade dress* ajenos, y es un riesgo legal real (copyright de UI, marca registrada) además de una mala base de producto: te ata a las decisiones de otro en vez de a las tuyas.

Este spec cambia la fuente de verdad a **tus propias decisiones de producto** y a los **patrones estándar de la categoría** (que no son de nadie: grid por cercanía, chat, filtros, perfiles, monetización). Todo lo que sigue está pensado para diferenciar visual y funcionalmente el producto, no para acercarlo a un clon.

**Regla invariante de este spec:** ningún entregable debe copiar el layout, la nomenclatura de features, los íconos, la paleta ni el flujo pantalla-a-pantalla de una app existente. Cuando haya que decidir UI, se decide desde tu sistema de diseño propio (sección 1).

---

## 1. Identidad y sistema de diseño propios (ÉPICA A)

**Problema actual:** el theme (`app_theme.dart`, `theme/widgets.dart`) usa una paleta derivada de un tercero (negro + amarillo con nombres como `kBoost`, `kRightNow`) y nombres de componentes calcados. Hay además 7 colores hardcoded fuera del theme.

**Objetivo:** una identidad visual propia y consistente.

- Definir una paleta de marca original (primario, secundario, superficies, estados) con nombres neutros (`brandPrimary`, `surface`, `onSurface`, `success`, `danger`…), documentada en un solo archivo de tokens.
- Tipografía y escala propias; sistema de espaciado (4/8pt).
- Renombrar componentes a nombres funcionales genéricos (`PrimaryButton`, `Segmented`, `PlanCard`, `SectionHeader`…).
- Eliminar los 7 `Color(0xFF...)` hardcoded restantes (`edit_profile_screen.dart`, `profile_screen.dart`) y migrarlos a tokens.
- Nombre de producto, logo e iconografía propios (los íconos "discretos" y el naming de tiers deben ser originales).

**Hecho cuando:** `grep -rn "Color(0xFF" lib/src` fuera de `theme/` = 0; no quedan identificadores con nombres de features de terceros; existe `docs/design/identity.md` con la guía de marca.

---

## 2. Trust & Safety — el hueco más grande (ÉPICA B, prioridad máxima)

**Estado actual:** solo `reports/report_service.dart` y `verification/verification_service.dart` (stubs). Para una app de citas —y más con usuarios LGBTQ+ en riesgo— esto no es opcional; es requisito legal (Apple/Google policy, DSA, leyes locales) y ético.

**Backend (nuevo crate `trust_safety/` + migraciones):**
- Reportes: modelo con categoría, evidencia, estado, cola de moderación, resolución y auditoría.
- Bloqueos: mutuos, con exclusión bidireccional en todas las queries de grid/chat/búsqueda.
- Baneos: usuario y dispositivo; shadow-ban; expiración; motivo auditable.
- Detección de contenido de abuso sexual infantil (CSAM) y de imágenes íntimas no consentidas (NCII): integración con hashing (p. ej. PhotoDNA/StopNCII) en el pipeline de subida — **obligatorio antes de lanzar**.
- Verificación de edad 18+ y verificación de perfil (foto-gesto) con almacenamiento mínimo.
- Rate limiting anti-spam y anti-scraping por IP/usuario.

**Flutter:**
- Flujo de reporte completo (categorías, adjuntar evidencia, confirmación).
- Bloquear/desbloquear con lista gestionable.
- Pantalla de verificación de perfil.
- Mensajería de seguridad: consejos, botón de salida rápida ("quick exit"), recursos locales.

**Hecho cuando:** un usuario puede reportar y bloquear end-to-end; el contenido bloqueado desaparece de todas las superficies; existe cola de moderación en el admin; el pipeline de media pasa por hashing de seguridad; hay tests de integración por caso.

---

## 3. Privacidad de ubicación (ÉPICA C)

**Estado actual:** módulo `location/` y migración `0004_geo.sql` presentes; falta la capa de privacidad.

- **Fuzzing de ubicación:** nunca exponer coordenadas exactas al cliente; distancia con ruido configurable.
- Ocultar distancia / modo incógnito / modo viaje con posición manual.
- Opción de "zonas ocultas" (no aparecer cerca de casa/trabajo).
- Nunca cachear ubicación precisa de terceros en el dispositivo.
- Auditar el endpoint de grid: que el servidor calcule distancia y **solo devuelva el valor difuso**, no lat/lng ajenas.

**Hecho cuando:** ningún response de API expone coordenadas de otros usuarios; el fuzzing es verificable en tests; incógnito y zonas ocultas funcionan end-to-end.

---

## 4. Chat en tiempo real — completar (ÉPICA D)

**Estado actual:** `chat/`, `chat_screen.dart` (881 LoC), reacciones, voz y NSFW ya existen (migraciones 0034/0035). Faltan piezas de tiempo real estándar.

- Indicador "escribiendo…" (presencia efímera vía WS).
- Acuses de entrega y lectura.
- Presencia online/última conexión coherente con privacidad.
- Expiración/retención de mensajes y de fotos efímeras (0026) con estado visual.
- Reintentos, cola offline y orden idempotente de mensajes.
- Traducción de mensajes (opcional, tier premium) usando un proveedor propio.

**Hecho cuando:** typing, acuses y presencia funcionan sobre WebSocket con tests; las fotos efímeras caducan de verdad en servidor.

---

## 5. Monetización — endurecer (ÉPICA E)

**Estado actual:** bastante avanzado — crate `billing/` con `plans/simulate/subscriptions/webhook`, Flutter con `revenuecat_service.dart` y `billing_service.dart`, `tienda_screen.dart` (445 LoC), migraciones 0007/0029/0042.

Faltan los bordes que importan en producción:
- Idempotencia y verificación de firma en el webhook de RevenueCat/stores.
- Sincronización de *entitlements* como fuente de verdad server-side (no confiar en el cliente).
- Restaurar compras; periodo de gracia; manejo de reembolsos y expiraciones.
- Nombres de planes/tiers **propios** (no "XTRA"/"UNLIMITED").
- Cumplimiento de reglas de Apple/Google para bienes digitales (no fuera de IAP).

**Hecho cuando:** el entitlement activo se deriva solo del backend; el webhook es idempotente y firmado; hay tests de doble-evento y de restauración.

---

## 6. Media pipeline (ÉPICA F)

**Estado actual:** `media/`, `albums/`, `nsfw/`, fotos efímeras — presentes.

- Subida con validación de tipo/tamaño, thumbnails y transcodificado en R2.
- Moderación automática de NSFW no marcado + gating por consentimiento.
- Álbumes privados compartidos con control de acceso y revocación.
- Watermark opcional y detección de screenshots (ya hay módulo `screenshots/`).

**Hecho cuando:** subir/servir media pasa por validación + moderación; compartir álbum es revocable y auditable.

---

## 7. Notificaciones (ÉPICA G)

**Estado actual:** `notifications/` y migración `0020_notification_prefs.sql`.

- Push (FCM/APNs) con tokens por dispositivo y limpieza de tokens muertos.
- Preferencias granulares respetadas server-side.
- Deep links a la superficie correcta.

**Hecho cuando:** push llega end-to-end respetando preferencias; deep links abren la pantalla correcta.

---

## 8. Calidad de backend (ÉPICA H)

- Resolver/documentar huecos de migración (0027/0028 ya anotados en `GAPS.md`).
- Índices de rendimiento en geoqueries, chat y feeds (revisar `0009_indexes.sql`).
- Rate limiting global y por endpoint sensible.
- Observabilidad: tracing, métricas, logs estructurados, health checks reales.
- Migración de secretos fuera del repo (hay claves de Firebase y `client_secret*.json` versionadas — **rotarlas y sacarlas del control de versiones ya**).

**Hecho cuando:** `cargo test` verde; secretos fuera del repo y rotados; dashboards básicos de métricas.

> ⚠️ Nota de seguridad urgente: en el repo hay credenciales sensibles versionadas (`firebase/*.json`, `client_secret_*.json`, `backend/.env`). Deben rotarse y eliminarse del historial de git antes de cualquier otra cosa.

---

## 9. Accesibilidad, i18n y testing (ÉPICA I)

- i18n: completar ES/EN (ya hay `l10n/`), sin strings hardcoded.
- Accesibilidad: contraste, tamaños de toque ≥44px, labels de screen reader, navegación por teclado en admin/web.
- Testing: subir cobertura por feature; suite E2E de los flujos críticos (registro, grid, chat, compra, reporte); CI que corra `flutter analyze/test` y `cargo test` en cada PR.

**Hecho cuando:** CI verde obligatorio en PR; auditoría de accesibilidad sin bloqueantes; 0 strings hardcoded.

---

## 10. Orden de ejecución sugerido

1. **ÉPICA H (seguridad de secretos)** — rotar y sacar credenciales del repo. Bloqueante, hoy.
2. **ÉPICA B (Trust & Safety)** — sin esto no se puede lanzar una app de citas.
3. **ÉPICA C (privacidad de ubicación)** — riesgo directo para usuarios.
4. **ÉPICA A (identidad propia)** — desacoplarse del diseño calcado.
5. **ÉPICA E (billing hardening)** y **D (chat)** — producto núcleo.
6. **F, G, I** — pulido y escala.

---

## Notas de método

- Cada épica se aterriza en un plan en `docs/superpowers/plans/` antes de tocar código, con checkpoints y tests dirigidos, igual que tu flujo actual.
- Ninguna tarea toma una app de terceros como referencia visual o funcional. Las decisiones de UI salen del sistema de diseño de la sección 1.
