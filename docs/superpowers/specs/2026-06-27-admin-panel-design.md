# Panel de administración (staff) — Flutter web · Design

**Fecha:** 2026-06-27
**Tipo:** Componente nuevo (app de staff). Complementa el spec de frontend Flutter+FRB.
**Estado:** SPEC — no se escribe código hasta aprobación.

## 0. Objetivo
Un panel **potente, versátil y "altamente intrusivo"** en **Flutter web** (`apps/admin`) para que administradores y staff (soporte, moderación, T&S) trabajen — **con guardarraíles obligatorios** (RBAC mínimo-privilegio, **audit log inmutable**, 2FA) que protegen al usuario y al negocio de abuso interno y de responsabilidad legal (GDPR). Construido sobre el backend y esquema existentes; reutiliza tablas de trust/safety ya presentes.

## 1. Decisiones
- **Flutter web** (`apps/admin`), solo-staff, `noindex`, comparte el crate `core`. SEO irrelevante.
- **Identidad de staff SEPARADA** de los usuarios finales (tabla `staff`, no `users`); JWT con *audience* distinto; **2FA obligatorio (TOTP)**.
- **APIs admin en `/admin/*`** con middleware **RBAC + auditoría**; idealmente subdominio propio (`admin.turnend.win`) + **allowlist de IP** opcional.
- Reutiliza `audit_log`, `reports`, `moderation_actions`, `csam_hits`, `blocks`, `data_requests`, `entitlements`, `subscriptions`, `devices`, `verifications` (ya en el esquema F0.2). **Añade**: `staff`, `staff_roles`/`permissions`, `feature_flags`, `staff_sessions`.

## 2. Identidad de staff & RBAC
- **Roles (jerárquicos, mínimo privilegio):** `support` < `moderator` < `admin` < `superadmin`. Permisos **por acción** (no solo por rol) → matriz `permission` (p.ej. `user.ban`, `user.impersonate`, `media.takedown`, `report.resolve`, `refund.issue`, `flag.toggle`, `staff.manage`, `audit.read`).
- **Login staff:** email + password (argon2, como users) **+ TOTP obligatorio**; emite JWT con claim `aud=admin` y `roles`/`perms`. Sesiones cortas (`staff_sessions`), revocables.
- **Asignación de roles:** solo `superadmin`; toda alta/baja de staff y cambio de rol → audit.

## 3. Capacidades por dominio (tabla existente que usa)
- **Usuarios** (`users`,`profiles`,`devices`,`verifications`): buscar/ver perfil completo; estado; **ban/suspensión/shadowban**, force-logout (revocar `refresh_tokens`), reset; **impersonación-para-soporte** (sesión limitada, justificación obligatoria, **auditada**, idealmente visible para el usuario); ver/forzar verificaciones.
- **Moderación** (`reports`,`moderation_actions`,`photos`,`albums`): cola de **reportes**; cola **NSFW** (fotos marcadas por el motor cliente); **takedown** de media de perfil; aplicar acciones (warn/suspend/ban) → registra en `moderation_actions`; apelaciones.
- **Trust & Safety** (`csam_hits`,`blocks`,`safety_zones`): **hits CSAM** del escaneo automático (cola prioritaria + flujo de reporte legal); señales de abuso, inteligencia device/IP, velocity; gestión de bloqueos/zonas.
- **Soporte** (`subscriptions`,`entitlements`): estado de cuenta; suscripciones/entitlements (RevenueCat); **reembolsos**; plantillas de respuesta; sesiones de soporte.
- **GDPR/CCPA** (`data_requests`,`consent_records`): gestionar **export/borrado** de datos (derecho de acceso/olvido); ver consentimientos. Acciones sensibles → audit + (opcional) doble aprobación.
- **Respuesta a Fuerzas del Orden (LER) / divulgación legal** — capacidad dedicada y muy restringida para cooperar con la policía cuando ocurre un incidente:
  - **Export legal por-usuario** con TODO lo que el servidor almacena: identidad y datos de registro, **historial de login/IP/dispositivos**, ubicación (geo declarada/última conocida), media de perfil, reportes y acciones de moderación, suscripciones/pagos (referencias, **no** datos de tarjeta), consentimientos, y metadatos de actividad. Empaqueta un dossier descargable + hash de integridad.
  - **Permiso `legal.export`** restringido a `superadmin`/equipo legal; **MFA**; toda exportación al `audit_log` con **base legal obligatoria** (referencia del requerimiento, agencia, instrumento: orden/citación/solicitud de emergencia).
  - **Base de divulgación (cumplimiento):** solo ante (a) **proceso legal válido** (orden judicial/citación), (b) **emergencia** (amenaza inminente a la vida), o (c) **reporte obligatorio CSAM** a la autoridad (NCMEC en EE.UU. / equivalente). Recomendado: revisión por asesoría legal antes de entregar.
  - **Techo E2E:** el contenido de chat E2E **no es descifrable** → no se puede entregar su texto; sí los **metadatos** disponibles (quién/cuándo) y todo lo no-E2E.
  - Esto es "intrusivo" al máximo de lo **lícito**: maximiza lo que se puede entregar, con base legal + auditoría que te protegen de responsabilidad.
- **Analítica:** dashboards (DAU/MAU, embudos registro→activación, ingresos, métricas de moderación, cohortes). Lectura agregada; evitar PII innecesaria.
- **Operación:** **feature flags / remote config** (`feature_flags`); **broadcast/notificaciones** (push vía FCM / email); **visor de audit log** (solo lectura, con filtros).
- **Planes & entitlements (free/premium) — configurables SIN deploy:** catálogo de **planes** (free, premium/tiers), **matriz feature↔plan** (qué desbloquea cada plan), **precios por plan**, todo editable desde el panel; el gating se lee **server-authoritative** (el backend consulta esta config, no se confía en el cliente). Mapea a productos/entitlements de **RevenueCat**. "Cambiar qué es free vs premium" = editar config, no recompilar. (Tablas nuevas `plans`/`plan_features`.)
- **Administración por países/regiones:** config **por país** — disponibilidad de features, **precios/planes** por país, requisitos **legales/cumplimiento** (edad de consentimiento, GDPR/CCPA, age-verification), **geo-restricciones** (bloquear/limitar features por país), colas de moderación y **analítica por país**, y **seguridad regional**: en países donde ser LGBTQ+ es ilegal/peligroso → **modo discreto forzado**, ocultar datos sensibles, avisos a viajeros (función real y crítica de este nicho). **Staff con scope geográfico** (un moderador limitado a su región). (Tabla `country_config`.)
- **Catálogo enterprise (objetivo, por fases):** experimentos/**A-B testing** + rollout gradual; **i18n/traducciones** gestionables; **CMS** in-app (banners, anuncios, versiones de documentos legales); **campañas** push/email con **segmentación**; **motor de reglas** antifraude/abuso; **centro de cumplimiento** (GDPR/CCPA, retención, consentimientos, LER); **SSO/SAML** para staff; **webhooks/integraciones**; reportes de auditoría/compliance; salud del sistema y uso de features.

## 4. Guardarraíles (OBLIGATORIOS)
- **RBAC mínimo privilegio** + permisos por acción.
- **Audit log inmutable** (`audit_log`): quién, qué acción, sobre qué entidad/usuario, cuándo, **por qué** (justificación en acciones intrusivas), IP/sesión. Append-only; nadie lo edita; `audit.read` restringido.
- **2FA (TOTP) obligatorio** para todo staff; allowlist de IP opcional; sesiones cortas + revocables.
- **PII acotada por propósito** (GDPR): el acceso a datos personales se registra; vistas mínimas necesarias.
- **Rate-limit** de acciones admin; **doble aprobación ("cuatro ojos")** opcional para destructivas (borrado masivo, ban masivo).
- **Acciones destructivas reversibles** donde sea posible (soft-delete, suspensión vs borrado).
- **Divulgación legal (LER):** solo con `legal.export` + **base legal registrada** + auditoría; nunca entrega ad-hoc sin proceso legal/emergencia/CSAM (te protege de responsabilidad). Ver §3.

## 5. Techo técnico + legal de "intrusivo"
- Si el **chat es E2E**, los admins **no** leen mensajes privados en silencio (rompería E2E + GDPR + confianza). Moderación de chat = **basada en reportes** (el reportante divulga) + **CSAM automático** por hash (sobre bytes, edge/server). 
- Todo lo que el **servidor almacena** (perfiles, media de perfil, metadatos, reportes) **sí** es accesible por staff con scope + auditoría.
- La impersonación es para **soporte**, no vigilancia: limitada, justificada, auditada.

## 6. Backend: APIs admin
- Router `/admin/*` separado, detrás de:
  1. `StaffAuth` extractor (JWT `aud=admin` + TOTP verificado),
  2. middleware **RBAC** (chequea permiso por endpoint),
  3. middleware **audit** (registra toda mutación con actor+justificación).
- Reutiliza repos existentes; añade repos `staff`/`audit`/`flags`. Mantiene la autoridad en el servidor (no contradice "carga al cliente": las ops admin son inherentemente server-side).
- Exposición: subdominio `admin.turnend.win` (otro hostname en el túnel cloudflared → mismo API o un binario admin aparte), o ruta `/admin` del API con allowlist. Decisión: **hostname admin separado** vía el túnel + allowlist de IP (defensa en profundidad; el panel es un objetivo de alto valor).

## 7. Esquema: reutilizar vs añadir
- **Reutiliza (ya existe, F0.2):** `audit_log`, `reports`, `moderation_actions`, `csam_hits`, `blocks`, `data_requests`, `consent_records`, `entitlements`, `subscriptions`, `devices`, `verifications`, `refresh_tokens`.
- **Añadir (migraciones nuevas):**
  - `staff` (id, email, password_hash, totp_secret, status, created_at…).
  - `staff_roles` + `permissions` (o `role` enum + tabla `role_permissions` para granularidad).
  - `staff_sessions` (sesiones revocables).
  - `feature_flags` (key, value/jsonb, audiencia/rollout, updated_by…).
  - `plans` (code, nombre, tier, activo…) + `plan_features` (plan→feature→límite/booleano) + `plan_prices` (plan×país/moneda) — **planes free/premium y matriz de features configurables**; el backend lee esto para el gating (server-authoritative) y mapea a entitlements/RevenueCat.
  - `country_config` (country_code, features habilitadas, plan/precio override, flags legales/edad, geo-restricción, **safety_override** [modo discreto forzado], staff_scope…) — **administración por país**.
  - `experiments` (A-B/rollout), `translations` (i18n gestionable), `announcements`/`cms_content` (banners/anuncios/versiones legales) — catálogo enterprise (por fases).
  - `access_events` (user_id, ip, user_agent, device_id, evento login/refresh, timestamp) — **historial de acceso/IP** para responder a fuerzas del orden; **retención acotada** (p.ej. 90–180 días) por minimización GDPR.
  - `legal_holds` (opcional): marcar cuentas bajo requerimiento legal para **suspender el borrado** mientras dure el proceso.
  - (Verificar campos de `audit_log` existente; ampliar si falta `actor_staff_id`/`justification`/`legal_basis`.)

## 8. Despliegue (Flutter web)
- `apps/admin` (Flutter web) → estático; hosting en Vercel (proyecto separado, `noindex`, password/SSO) o servido tras el túnel. Comparte `core`; opcionalmente `native` para validación.
- Acceso restringido (staff + 2FA + IP allowlist). HTTPS del edge (Cloudflare).

## 9. Riesgos
- **Objetivo de alto valor:** un panel intrusivo comprometido = brecha masiva. Mitigación: 2FA, allowlist, RBAC, auditoría, superficie mínima, secretos fuera de git, revisiones de seguridad.
- **Abuso interno:** mitigado con audit inmutable + mínimo privilegio + (cuatro ojos en destructivas).
- **Legal (GDPR/CCPA):** acceso a PII con propósito + registro; export/borrado correctos; CSAM con flujo legal.
- **Coste:** componente grande; se construye por fases tras el núcleo de la app.

## 10. Fases (sugeridas, tras el núcleo de la app)
- **AD1:** identidad staff + RBAC + 2FA + audit middleware + `/admin/auth`.
- **AD2:** usuarios (ver/buscar/ban/suspend/force-logout) + visor de audit.
- **AD3:** moderación (reportes + NSFW queue + takedown) + CSAM queue.
- **AD4:** soporte (entitlements/RevenueCat/refunds) + GDPR (export/borrado) + **LER/divulgación legal** (`legal.export`, `access_events`, `legal_holds`).
- **AD5:** analítica + feature flags + broadcast.
- **AD6:** **planes free/premium + matriz de features configurables** (`plans`/`plan_features`/`plan_prices`) + **administración por país** (`country_config`, geo-restricción, safety_override, staff con scope geográfico).
- **AD7:** catálogo enterprise por fases (A-B/experiments, i18n, CMS/anuncios, campañas+segmentación, motor antifraude, SSO/SAML, webhooks).

## 11. Fuera de alcance
- Lectura de chats E2E (imposible por diseño). Reglas de moderación automática avanzada (ML server-side). BI/warehouse externo. Todo se especifica/prioriza aparte.
