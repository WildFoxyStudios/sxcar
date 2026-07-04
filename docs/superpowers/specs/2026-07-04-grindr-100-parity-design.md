# Spec: Grindr 100% Parity — Sistema completo

**Fecha:** 2026-07-04
**Fuente de verdad visual:** 34 capturas reales de Grindr Android en `Mobile/` (catálogo completo en sección "Catálogo").
**Reemplaza / extiende:** `2026-07-02-grindr-ui-parity-design.md` (10 tasks T1–T10) que cubre T1–T6 básicos; este spec los cierra + añade épicas de Billing, Ajustes rediseñado, Editar perfil completo, Buzón/Interest completos y cierre Navegar con filtros server-side.

## Objetivo

Que `apps/app` se vea, navegue y comporte como Grindr real: paridad 100% visual Y funcional, usando datos reales del backend Vibra. Cero deuda técnica. Cero contenido simulado salvo la compra (explícitamente marcada como simulada hasta integrar Google Play Billing).

**Restricciones invariantes:**
- **Tokens verbatim VibraTheme v3**: kBg `#000000`, kSurface `#1A1A1A`, kChip `#2A2A2A`, kDivider `#333333`, kYellow `#FFCC00` (texto sobre amarillo SIEMPRE negro), kText `#FFFFFF`, kTextSecondary `#8E8E8E`, kTextTertiary `#666666`, kOnline `#1BD75E`, kBoost `#26D944`, kRightNow `#9B51E0`, kBadgeRed `#FF3B30`.
- **Cero marcas Grindr** (sin logo máscara, sin "XTRA", sin "Grindr"). Nombres de tiers desde backend; iconos Material o propios.
- **i18n desde día 1**: ES + EN, ES plantilla (textos de las capturas). Locale del sistema con fallback ES.
- **Sin colores hardcoded**: revisar toda la app; arreglar lo existente (`Color(0xFFF4C542)` y similares).
- **Tests por épica**: dirigidos + suite completa verde.
- **Commit directo a main** (decisión del dueño); NO push (lo hace el controlador). Reporte por checkpoint en `.superpowers/sdd/grindr-100/checkpoint-N-report.md`.

## Catálogo de capturas (referencia)

30 capturas numeradas (`Mobile/1000144698.jpg` a `1000144727.jpg`) + 4 screenshots (`Mobile/Screenshot_2026-07-02-22-57-*.jpg`). Agrupadas por feature:

| Capturas | Feature | Elementos clave |
|---|---|---|
| 698, 700, 703, 704 | Ajustes | Lista plana con secciones: Cuenta, Multimedia, Seguridad y privacidad, Notificaciones, Chat, Ubicación, Preferencias de pantalla |
| 701, 702 | Navegar | Grid 3-col full-bleed, dots online, etiqueta distancia, search pill, chips filtro, banda upsell, FABs Boost/Right Now |
| 705-715 | Editar perfil | Hero photo + 5 slots, Etiquetas, Estadísticas con toggles "Mostrar…", Rol, Estado relación, Viajes, Tribes (3 subsecciones), En busca de, Quedar en, NSFW, Identidad, Salud (VIH/Último/Recordar/Prácticas/Vacunas), Red social (Instagram/X/Facebook/Spotify) |
| 714 | Interest | Título, contadores Views N / Taps N, card foto único con badge "Desbloquear GRATIS", pill Boost, CTA "Desbloquear todo sin límites" |
| 716 | Buzón | TabBar Bandeja de entrada/Álbumes, filtros (No Leído/Distancia/En línea), carrusel "Actualiza tu álbum" + 5 placeholders, sponsored row, lista conversaciones |
| 717-727 | Tienda | XTRA/UNLIMITED segmented, 3 cards de duración (1 semana, 1 mes "Ahorra 66%", 3 meses "Ahorra 83%"), foto fondo por plan, lista features con bullets amarillos, resumen precio, botón Continuar, Términos, nav inferior |
| 699 | Profile Drawer | 180×180 foto, pill nombre, Online/Incógnito, NUEVAS OPCIONES, COMPLEMENTOS, ELEGIR UN PLAN, +495 avatars row, menú |
| 715 | Profile Detail | Header con name + online dot, hero 65%, secciones (Acerca de mí, Estadísticas, Expectativas, Salud), "Te podría interesar" con NUEVO badge |
| 4× Screenshot_2026-07-02 | Album detail + login + grid-search | Distintos estados de UI ya cubiertos en otros renglones |

## Estado actual del Flutter app (snapshot 2026-07-04)

| Feature | Archivo | Tokens v3 | Estado funcional | Gaps principales |
|---|---|---|---|---|
| Navegar | `cascade_screen.dart` (1108 LoC) | Sí | Grid + header + chips básicos | Falta etiqueta distancia, NUEVO badge, favorites filter server-side |
| Profile Detail | `profile_detail_screen.dart` (1119 LoC, WIP) | Sí | T4 base hecha, WIP añade PageController/details | Falta age, relationship, social row, NUEVO badge en sugerencias |
| Profile Drawer | `profile_drawer.dart` (513 LoC) | Sí | Online/Incógnito, drawer completo | Falta NUEVAS OPCIONES, +495 avatares, cards Pase/7d, "Ver todos los planes", Grindr Presents |
| Ajustes | `settings_screen.dart` (692 LoC) | Parcial | TabBar con bloques existentes | Estructura entera a reescribir (TabBar → Single ListView + 7 secciones) |
| Editar perfil | `edit_profile_screen.dart` (902 LoC) | **NO** (color hardcoded) | Foto + height/weight/body/position | Falta migración a VibraTheme, Identidad, Vacunas, Prácticas, Social, Viajes, NSFW, Mostrar toggles, tags |
| Interest | `interest_screen.dart` (379 LoC) | Sí | TabBar Taps/Favorites básico | Falta tab Views, contadores, badge "Desbloquear GRATIS", CTA sticky |
| Right Now | `right_now_screen.dart` (282 LoC) | Sí | Feed vertical con FAB púrpura | Faltan cards con foto, stats V/T, proximidad |
| Buzón | `chat_list_screen.dart` (201 LoC) | Sí | AppBar + Dismissible + badges rojos | Falta TabBar Bandeja/Álbumes, carrusel "Actualiza", filtros (No Leído/Distancia/En línea), Boost pill |
| Chat | `chat_screen.dart` (881 LoC) | Sí | Burbujas + adjuntar + NSFW | Faltan "Typing…", traducción, expiración visual |
| Álbumes | `albums_screen.dart` (297 LoC) | Sí | ListView con Cards | Falta grid de fotos, tab "Shared with me" |
| Album detail | `album_detail_screen.dart` (311 LoC) | Sí | Viewer | Faltan tokens revisión, compartir sheet |
| Tienda | — (placeholder en main.dart) | Sí | Solo `Center(Text("Tienda"))` | **Implementación completa ausente** |
| Profile (legacy) | `profile_screen.dart` (579 LoC) | **NO** | AppBar + CircleAvatar | Migrar a VibraTheme; añadir grid de fotos |
| Theme | `app_theme.dart` + `widgets.dart` | v3 | Tokens + 5 widgets | Faltan: UpsellCard, PlanDurationCard, AlbumCarousel, NUEVOBadge, StatRow, ChipMultiSelect, SettingRow, Segmented3 |

## Épicas

### ÉPICA 1 — Billing + Tienda + Drawer planes (L: 3-4 sesiones)

**Objetivo**: desbloquea monetización. Tienda real con compra simulada, drawer renovado.

**Backend:**
- **Migración `0029_subscriptions.sql`**: tabla `subscriptions` (id, user_id, plan_id, period_days, source, status, started_at, expires_at, created_at) + índices parciales.
- **Nuevo crate `backend/crates/billing/`**:
  ```
  src/
    lib.rs           # re-exports
    plans.rs         # GET /billing/plans
    subscriptions.rs # GET /billing/me
    simulate.rs      # POST /billing/simulate-purchase
    error.rs         # BillingError enum + IntoResponse
  ```
- **Endpoints** (público-auth):
  - `GET /billing/plans` → lista planes activos agrupados por tier (`{id, name, tier, period_days, price_cents, currency, features: [{key,label}], popular: bool}`)
  - `POST /billing/simulate-purchase` → body `{plan_id}`. Validaciones: plan existe (404), no doble compra mismo tier (409). Inserta subscription con `source='simulated'`. Devuelve subscription completa.
  - `GET /billing/me` → subscription activa más reciente (ORDER BY expires_at DESC LIMIT 1 WHERE status='active' AND expires_at > now()) o `{subscription: null}`.
- **Wire-up**: añadir `billing::router()` a `backend/crates/api/src/lib.rs`.
- **Tests integración** (`backend/crates/api/tests/billing.rs`):
  1. `plans_list_returns_active_sorted`
  2. `me_returns_null_when_no_subscription`
  3. `simulate_purchase_creates_active_subscription`
  4. `simulate_purchase_double_same_tier_returns_409`
  5. `simulate_purchase_unknown_plan_returns_404`
  6. `me_returns_active_subscription_after_purchase`
  7. Auth requerida: 401 sin cookie

**Flutter:**
- `apps/app/lib/src/billing/`:
  - `tienda_service.dart` — BillingService con `getPlans()`, `getMySubscription()`, `simulatePurchase(int)`
  - `providers.dart` — `billingPlansProvider` (FutureProvider), `activeSubscriptionProvider` (FutureProvider keepAlive), `simulatePurchaseProvider`
  - `tier_features.dart` — contenido estático features por tier (l10n)
- `apps/app/lib/src/tienda/tienda_screen.dart` (NUEVO): estructura detallada en Chunk 2 del chat.
- Componentes nuevos en `theme/widgets.dart`: `UpsellCard`, `PlanDurationCard`, `NUEVOBadge`.
- Drawer (`profile_drawer.dart`) modificaciones:
  - Sección NUEVAS OPCIONES (Container amarillo claro) con 2 features rotando
  - ELEGIR UN PLAN: card amarilla (UpsellCard) destacada + 2 cards oscuras (Pase de día, 7 días)
  - Menú: filas "Ver todos los planes" (→ /tienda), "Grindr Presents" (deshabilitado "Próximamente")
  - +495 avatares row (placeholder hasta conectar stat real)
- i18n: ~45 keys nuevas (xtra, unlimited, elijeLaActualizacion, ahorra, popular, semana, mes, meses, yaTienes, planActivo, verPlanes, compraPaseDia, compraIlimitado7Dias, gratis, nuevasOpciones, perfilesCerca, etc.)

**Tests Flutter:**
- `widgets_test.dart`: YellowPillButton enabled/disabled, UpsellCard render, PlanDurationCard selección
- `tienda_screen_test.dart`: render con planes fake, selección cambia resumen, Continuar llama service, banner entitlement visible
- `profile_drawer_test.dart`: NUEVAS OPCIONES visible, Ver planes navega

**Checkpoint "hecho":**
- `cargo build -p api` 0
- `cargo test -p api --test billing` 7/7 verde
- Deploy al VPS, `curl https://api.turnend.win/billing/plans` (con cookie auth) → 200 con 2 tiers
- `flutter analyze` 0, `flutter test` verde, `flutter build apk --debug` ok
- Commit: `feat(epic1): billing backend + tienda + drawer planes`

---

### ÉPICA 2 — Ajustes rediseñado (L: 2-3 sesiones)

**Objetivo**: pantalla de Ajustes como lista plana single-list estilo Grindr, 7 secciones, toggles/pickers reales.

**Backend:**
- **Migración `0030_privacy_preferences.sql`**: ALTER TABLE notification_preferences añadiendo columnas: `multimedia_show_album_updates` (bool), `multimedia_show_carousel` (bool), `chat_mark_chatted` (bool), `chat_sync` (bool), `screen_keep_unlocked` (bool), `visitor_status` (smallint 0/1/2), `units` (smallint 0=metric/1=imperial). Defaults "experiencia Grindr".
- **Endpoints** (público-auth):
  - `GET /privacy/preferences` → devuelve todas las prefs unificadas (las notification_preferences existentes + las nuevas)
  - `PUT /privacy/preferences` → roundtrip con validación de enums
- **Tests** (`backend/crates/api/tests/privacy_preferences.rs`):
  1. `prefs_defaults`
  2. `prefs_put_roundtrip`
  3. `prefs_units_validation`
  4. `prefs_visitor_status_validation`

**Flutter:**
- **Rewrite `settings_screen.dart`**: de TabBar a `ListView` con `SectionBand` separador. AppBar transparente. Scaffold kBg.
- **7 secciones** (orden Grindr):
  1. **CUENTA**: Actualizar suscripción (→ /tienda), ID de usuario (botón copiar), Desactivar (deshabilitado "Próximamente"), Restaurar compra (SnackBar no-op)
  2. **MULTIMEDIA**: Mostrar actualizaciones de álbumes en bandeja toggle, Mostrar carrusel de actualizaciones en bandeja toggle
  3. **SEGURIDAD Y PRIVACIDAD**: Configuración privacidad (ancla a lista existente), Centro seguridad (sheet estático), Icono aplicación discreto toggle (→ DiscreetIconPicker), PIN (→ PinScreen), Desbloquear usuarios (→ BlocksListScreen con unblock real), Dejar de ocultar usuarios, Preferencias consentimiento (sheet), Descargar mis datos (stub), Eliminar cuenta (rojo, diálogo confirmación)
  4. **NOTIFICACIONES**: Mensajes nuevos/Taps/Promociones/Recordatorio análisis (existentes) + No molestar toggle (sin schedule)
  5. **CHAT**: Confirmaciones de lectura (sheet), Marcar con quién he chateado toggle (nuevo), Sincronización toggle (nuevo)
  6. **UBICACIÓN**: Inicio (city picker sheet), Estado visitante `VibraSegmented` DESACTIVADA/ACTIVADO/AUTOMÁTICO
  7. **PREFERENCIAS DE PANTALLA**: Mantener pantalla desbloqueada toggle, Sistema de unidades `VibraSegmented` MÉTRICO/IMPERIAL (provider `unitsProvider` aplicado a TODAS las distancias en profile_detail, interest, cascade), Síguenos Instagram/Facebook (url_launcher)
- **Pantallas nuevas**: `DiscreetIconPickerScreen` (grid 3×2 iconos placeholder), `PinScreen` (4 input boxes PIN local SharedPreferences hash)
- **Providers nuevos**: `unitsProvider`, `discreetIconProvider`, `pinEnabledProvider`, `visitorStatusProvider`
- **Componentes nuevos en widgets.dart**: `SettingRow({label, value?, trailing?, onTap})`, `Segmented3({options, selectedIndex, onChanged})`
- i18n: ~35 keys (cuenta, multimedia, mostrarActualizacionesAlbumes, centroSeguridad, iconoAplicacionDiscreto, pin, desbloquearUsuarios, descargarDatos, noMolestar, sincronizacionMensajes, ubicacion, estadoVisitante, desactivada, activado, automatico, sistemaUnidades, metrico, imperial, siguenos, eliminarCuenta, etc.)

**Checkpoint "hecho":**
- `cargo test -p api --test privacy_preferences` 4/4 verde
- Smoke live `curl /privacy/preferences` PUT + GET roundtrip
- Build apk debug ok
- Commit: `feat(epic2): settings redesign + privacy preferences + units`

---

### ÉPICA 3 — Editar perfil + Profile details (L: 3-4 sesiones)

**Objetivo**: pantalla de Editar perfil completa estilo Grindr, todos los campos reales, persistencia correcta en backend.

**Backend:**
- **Migración `0028_profile_details_ext.sql`** (extiende 0027): ALTER TABLE profiles con `details jsonb NOT NULL DEFAULT '{}'`. Mantener compatibilidad con campos ya existentes.
- **Endpoints** (público-auth):
  - `GET /profile` → devuelve `details` entero
  - `PUT /profile` → body extendido: `details: Option<serde_json::Value>`. Validar (1) es objeto, (2) ≤8KB serializado, (3) ∈8KB → 400
  - `GET /profile/:id` (público) → filtra `details` por `show_*`:
    - Si `!details.show_age` → quitar age calculada (`born → n años`)
    - Si `!details.show_role` → quitar `role`
    - Si `!details.show_tribes` → quitar `tribes` y `tribes_in`
    - Defaults: `show_age/show_role/show_tribes = true` (compatibilidad con perfiles existentes)
- Estructura esperada de `details`:
  ```json
  {
    "height_cm": 180, "weight_kg": 75, "body_type": "average", "role": "top",
    "relationship": "single", "ethnicity": "hispanic_latino",
    "pronouns": ["he_him"], "gender": "man",
    "tribes": ["bear", "otter"], "tribes_in": ["twink"],
    "looking_for": ["chat", "friends"], "meet_at": ["cafes", "gyms"],
    "tags": ["coffee", "movies"], "accept_nsfw_photos": true,
    "show_age": true, "show_role": true, "show_tribes": true,
    "social": {"instagram": "@handle", "x": "@handle", "facebook": "handle", "spotify": "user"},
    "vaccinations": ["hepatitis_b", "covid"], "healthy_practices": ["prEP", "testing"],
    "travels": [{"city": "Madrid", "from": "2026-08-01", "to": "2026-08-15"}]
  }
  ```
- Health sigue con su endpoint separado (`/profile/health`) sin cambios.
- **Tests** (`backend/crates/api/tests/profile_details.rs`):
  1. `put_profile_persists_details`
  2. `get_own_profile_returns_full_details`
  3. `get_public_profile_filters_by_show_age_false`
  4. `get_public_profile_filters_by_show_role_false`
  5. `get_public_profile_filters_by_show_tribes_false`
  6. `put_profile_rejects_details_over_8kb`
  7. `put_profile_rejects_details_not_object`
  8. `put_profile_accepts_8kb_exactly`

**Flutter:**
- **Rewrite completo `edit_profile_screen.dart`** con VibraTheme (eliminar `Color(0xFFF4C542)` hardcoded):
  1. **Header fotos**: slot grande + 4 slots 2×2. Fotos reales del perfil. Tap slot vacío abre PhotoPicker (flujo NSFW+upload). Long-press reordenar.
  2. **UnderlineField**: Nombre (/15), Acerca de mí (/255 multiline contador visible), Mis etiquetas (chips input/delete)
  3. **SectionBand ESTADÍSTICAS**: Toggle mostrar mi edad, Edad (read-only derivada), Altura cm, Peso kg, Etnia (selector), Tipo de cuerpo, Toggle mostrar mi rol, Rol, Estado relación
  4. **SectionBand PREFERENCIAS**: Toggle mostrar mis tribes, Mis tribes (chips multi), Tribes en las que estoy NUEVO (chips), En busca de (chips), Quedar en (chips), Aceptar fotos NSFW (toggle)
  5. **SectionBand IDENTIDAD**: Género (selector), Pronombres (chips)
  6. **SectionBand SALUD** (mantener wiring Tier 1): Estado VIH, Último análisis (date picker), Recordarme análisis (toggle + periodicidad), Prácticas saludables (multi-select), Vacunas (multi-select)
  7. **SectionBand RED SOCIAL**: Instagram, X, Facebook, Spotify (UnderlineField URL/handle)
  8. **SectionBand VIAJES** (opcional, si feature flag activado): lista de travels + botón "+" → AddTripScreen
  9. **Guardar** `YellowPillButton` sticky: single llamada PUT /profile con details + PUT /profile/health, todo en transacción lógica (secuencial con rollback si segunda falla → SnackBar error).
- **Pantallas nuevas**: `AddTripScreen` (city + date pickers), `VaccinesScreen` (multi-select 6 opciones), `PracticesScreen` (multi-select 8 opciones)
- **Provider**: `profileEditProvider` que coordina las dos llamadas. Validación local de contadores antes de enviar.
- i18n: ~25 keys (misEtiquetas, acercaDeMi, mostrarMiEdad, mostrarMiRol, anadirViaje, mostrarMisTribes, tribesEnLasQueEstoy, aceptarFotosNSFW, identidad, genero, redesSociales, instagram, facebookX, spotify, vacunas, recordarAnalisis, practicasSaludables, etnia, tipoCuerpo, pronombres, estadoRelacion, viajes, eliminarFoto, reordenarFotos)
- **Profile detail E5 coordinación**: leer `details` ya cableado (T4 WIP) → mostrar Edad (con "(oculto)" si show_age=false), Relación, Red social (iconos tappables con url_launcher). El fallback seguro: si `show_*` viene false, ocultar el bloque entero.

**Tests Flutter:**
- `edit_profile_screen_test.dart` actualizado: form guarda details correctamente, selectors abren sheets, contadores UI, chips input/delete
- `profile_detail_screen_test.dart` actualizado: render con perfil completo (todas las secciones), "Di algo" envía y navega, favorito toggle, NUEVO badge en sugerencias, social links no crashean si faltan
- `add_trip_screen_test.dart`, `vaccines_screen_test.dart`, `practices_screen_test.dart`

**Checkpoint "hecho":**
- `cargo test -p api --test profile_details` 8/8 verde
- Smoke live: PUT /profile con details completo, GET /profile/:id de otro usuario con `show_age=false` → respuesta sin age
- Build apk debug ok
- Commit: `feat(epic3): edit profile redesign + details backend`

---

### ÉPICA 4 — Buzón + Interest completa (M: 2 sesiones)

**Objetivo**: Buzón estilo Grindr con TabBar + carrusel álbum-updates. Interest con Views/Taps reales + CTA + "Desbloquear GRATIS".

**Backend:**
- **Verificar** `GET /albums/shared` (debería existir desde Explore). Si no, añadir.
- **Nuevos endpoints contadores**:
  - `GET /profile/views/count` → `{count: i64}` para el propio user
  - `GET /taps/count` → `{count: i64, types: {friendly: n, looking: m, ...}}` para tabs counter
- **Wire-up** al router.
- **Tests** (`backend/crates/api/tests/counters.rs`):
  1. `views_count_returns_zero_initially`
  2. `views_count_increments_on_new_view`
  3. `taps_count_groups_by_type`

**Flutter:**
- **Buzón (`chat_list_screen.dart` rewrite)**:
  - AppBar transparente con 2 tabs texto: "Bandeja de entrada" (w800 24 blanco) / "Álbumes" (gris)
  - **Tab Bandeja**: chips ⭐ (cruza con favoritesProvider client-side), "No Leído", "En línea" (cruza con `userStatusProvider` por participant id). Carrusel horizontal 96dp NUEVO: primer item = mi avatar 64 + botón "+" + label "Actualiza tu álbum" (→ /albums); siguientes = items de `sharedAlbumsProvider` (consume `GET /albums/shared`). Si vacío: solo el primer item + texto gris "No hay actualizaciones de álbum compartidas; vuelve pronto". Filas conversación 88dp: thumb 72 radius 10 (foto real del participante), nombre w700 + preview gris con prefijo ➤ si last_message.sender_id == me, columna derecha fecha corta + badge circular 24 kYellow número. Swipe-to-delete existente. FAB pill negra "Boost ⚡" (acción boost existente). NO sponsored row (sin ads).
  - **Tab Álbumes**: embebe contenido `albums_screen.dart` sin su Scaffold (reutiliza).
- **Interest (`interest_screen.dart` rewrite)**:
  - Título 32 w800 left + TabBar texto "Views N"/"Taps N" (N = `profileViewsCountProvider` + `tapsCountProvider`)
  - Indicador subrayado blanco 2px, labelColor blanco/unselected gris
  - Dot kBadgeRed 8px junto a "Views" si hay views nuevos (provider ya existente del T2)
  - **Views tab**: grid 2 columnas cards radius 12. Foto del viewer, overlay inferior nombre + dot online, subtítulo 👁 "¡Ahora mismo!"/"hace Xh" + "· Y km" (usar `unitsProvider` para formateo). Si count > 6 y NO hay entitlement activo (`activeSubscriptionProvider`): primera card con NUEVOBadge "Desbloquear GRATIS" sobre foto borrosa + tap → sheet "Suscríbete para ver todos" → /tienda.
  - **Taps tab**: lista actual restyled a cards (foto, nombre, emoji tap grande, hace X).
  - CTA bottom sticky (ambos tabs): `YellowPillButton` "Desbloquear todo sin límites" → /tienda. FAB pill "Boost ⚡" arriba del CTA.
- **Álbumes (`albums_screen.dart`)**: añadir grid interno 3 columnas con thumbnails + tap → `album_detail_screen`. Botón compartir con sheet de usuarios.
- i18n: ~20 keys (bandejaDeEntrada, albumes, noLeido, distancia, enLineaFiltro, actualizaTuAlbum, noHayActualizaciones, desbloquearGratis, desbloquearTodoSinLimites, boostTuInterest, views, taps, ahoraMismo, compartirAlbum, seleccionarUsuarios, etc.)

**Componentes nuevos en widgets.dart**: `AlbumCarousel({items})`, `AlbumUpdateBanner({album})`, `AlbumUpdatesEmptyState()`.

**Tests Flutter:**
- `chat_list_screen_test.dart`: filtros client-side, render de filas (unread badge, ➤ mio), carrusel con shared albums fake, tab Álbumes
- `interest_screen_test.dart`: contadores V/T, badge "Desbloquear GRATIS" cuando no hay entitlement, CTA sticky navega a /tienda
- `albums_screen_test.dart`: grid de fotos, botón compartir

**Checkpoint "hecho":**
- `cargo test -p api --test counters` 3/3 verde
- Smoke live `curl /profile/views/count` y `/taps/count`
- Build apk debug ok
- Commit: `feat(epic4): buzon + interest polish + counters backend`

---

### ÉPICA 5 — Cierre T4 + Navegar server-side (M: 1-2 sesiones)

**Objetivo**: cerrar el T4 (PageView + details) que está WIP, añadir etiqueta distancia + NUEVO badge en Navegar, mover filtros ⭐/En línea/Right Now a server-side.

**Pasos:**
1. **Commit del WIP actual** en `profile_detail_screen.dart` (PageController, _photoIndex, _details wiring) con tests verdes ANTES de añadir nada más. Si rompe, fix primero. Commit: `feat(app): T4 PageView + details wiring (closes T4)`.

2. **Profile detail extensions**:
   - Edad: si `details.birthdate` o response.user.dob disponible, mostrar "🎂 X años" en fila de stats. Si `details.show_age === false`, mostrar "(oculto)" en gris.
   - Relationship status: row en stats rápidos si `details.relationship` existe.
   - Red social: leer `details.social.{instagram,x,facebook,spotify}`, renderizar como row de iconos tappables (url_launcher). Si todo vacío, no renderizar el row.
   - NUEVO badge en sugerencias "Te podría interesar": si `user.created_at` o `details.created_at` <7 días, mostrar chip kYellow "NUEVO" (el `NUEVOBadge` añadido en E1).

3. **Navegar (`cascade_screen.dart` + `grid_search_screen.dart`)**:
   - Etiqueta distancia: " · X km" añadido al overlay inferior (gris, formatDistance helper con `unitsProvider`).
   - NUEVO badge (esquina sup-derecha) si perfil creado <7d.
   - Filtros server-side:
     - Backend: extender `NearbyQuery` con `favorites_only: Option<bool>`, `online_only: Option<bool>` (vía JOIN heartbeats <5min), `right_now: Option<bool>` (vía JOIN heartbeats <30min).
     - Modificar `find_nearby_users` con LEFT JOIN a `favorites` y `heartbeats`.
     - `cargo sqlx prepare --workspace` si hay queries nuevas.
     - Tests (`backend/crates/api/tests/grid_filters.rs`): `nearby_filters_favorites_only`, `nearby_filters_online_only`, `nearby_filters_right_now`.
   - Flutter: sheet de filtros pasa los 3 como query params; chips ⭐, "En línea", "Right Now" consumen directo del backend (mantener fallback client-side por si falla).

4. **Helper distancia** (`apps/app/lib/src/utils/distance_format.dart`):
   - `formatDistance(meters, unitsProvider)` → "X km" si métrico, "X mi" si imperial
   - Aplicar en profile_detail (E3 coord), interest (E4), cascade (E5)

**i18n**: ~10 keys (miEdad, estadoRelacion, sigueloEn, abrirEnlaceExterno, kilometros, millas, filtroFavoritos, filtroEnLinea, filtroRightNow, nuevo).

**Checkpoint "hecho":**
- `cargo test -p api --test grid_filters` 3/3 verde
- Smoke live: `curl /grid/nearby?favorites_only=1&online_only=1&right_now=1` cada uno con datos
- `flutter analyze` 0, tests verdes, build apk ok
- Commit: `feat(epic5): T4 close + navegate server-side filters`

---

## Componentes compartidos consolidados en `theme/widgets.dart`

| Componente | Épica | Descripción |
|---|---|---|
| `YellowPillButton` | T1 (existente) | CTA full-width rounded-full amarillo, texto negro 18 w700 |
| `VibraSegmented` | T1 (existente) | segmented pill kChip, activa blanca con texto negro |
| `SectionBand` | T1 (existente) | banda negra 48dp icono + título CAPS |
| `UnderlineField` | T1 (existente) | label bold + valor + underline + contador |
| `FilterChipPill` | T1 (existente) | chip rounded-full kChip; activo fondo blanco |
| `UpsellCard` | **E1 NUEVO** | card gradiente oscuro 160×100 con CTA pill pequeña |
| `PlanDurationCard` | **E1 NUEVO** | card 128×150 borde 2px, seleccionado kYellow, contenido duración+precio+badges |
| `NUEVOBadge` | **E1 NUEVO** | chip kYellow radius 6 "NUEVO" 11 w800 negro |
| `StatRow` | **E1 NUEVO** | 44dp icono 22 + label/value (perfil detalle) |
| `SettingRow` | **E2 NUEVO** | label w700 + value/trailing (texto, no ListTile) |
| `Segmented3` | **E2 NUEVO** | vibra segmented con 3 opciones |
| `AlbumCarousel` | **E4 NUEVO** | carrusel horizontal 96dp actualiza-tu-album |
| `AlbumUpdateBanner` | **E4 NUEVO** | banner con NUEVO badge para álbum nuevo |
| `AlbumUpdatesEmptyState` | **E4 NUEVO** | texto gris "No hay actualizaciones…" |

## i18n consolidado (140+ keys nuevas)

ES plantilla. Cambios: SÓLO añadir a `app_es.arb` y `app_en.arb`. `flutter gen-l10n` después de cada cambio.

**Grupos:**
- Tienda (45): xtra, unlimited, elijeLaActualizacion, encuentraMasMasRapido, masAccesoMasAtencion, semana, mes, meses, mesesGratis, ahorra, popular, planActivo, verPlanes, compraPaseDia, compraIlimitado7Dias, gratis, gratisBadge, precioContinuar, precioTotal, renovacionAutomatica, nuevasOpciones, perfilesCerca, grindrPresents, proximamente, verTodosLosPlanes, masConexiones, masAtencion, destaque, forYouChats, chatIlimitadosExplore, fotosIlimitadasCaducidad, traduccionChat, estadoEscribiendo, funcionesIlimitadas, perfilesIlimitados, navegarIncognito, sinInterrupciones, quienMeHaVisto, saludSexualFAQ, preguntasFrecuentesSaludSexual, yaTienes, compraSimulada, destacado, etc.
- Ajustes (35): cuenta, actualizarSuscripcion, idUsuario, desactivar, restaurarCompra, multimedia, mostrarActualizacionesAlbumes, mostrarCarruselBandeja, centroSeguridad, iconoAplicacionDiscreto, pin, desbloquearUsuarios, dejarOcultarUsuarios, preferenciasConsentimiento, descargarDatos, noMolestar, marcarConQuienChateeado, sincronizacionMensajes, ubicacion, inicio, estadoVisitante, desactivada, activado, automatico, preferenciasPantalla, mantenerPantallaDesbloqueada, sistemaUnidades, metrico, imperial, siguenos, eliminarCuenta, confirmarEliminar, seleccionaIcono, cambiarPin, verificarPin
- Editar perfil (25): misEtiquetas, acercaDeMi, mostrarMiEdad, mostrarMiRol, anadirViaje, mostrarMisTribes, tribesEnLasQueEstoy, aceptarFotosNSFW, identidad, genero, redesSociales, instagram, facebookX, spotify, vacunas, recordarAnalisis, practicasSaludables, etnia, tipoCuerpo, pronombres, estadoRelacion, viajes, eliminarFoto, reordenarFotos, ocultar
- Buzón/Interest/Álbumes (20): bandejaDeEntrada, albumes, noLeido, distancia, enLineaFiltro, actualizaTuAlbum, noHayActualizaciones, patrocinado, desbloquearGratis, desbloquearTodoSinLimites, boostTuInterest, views, taps, ahoraMismo, compartirAlbum, seleccionarUsuarios, archivoCompartido, eliminarAlbum, misShares, ver
- Cierre (10): miEdad, sigueloEn, abrirEnlaceExterno, kilometros, millas, filtroFavoritos, filtroEnLinea, filtroRightNow, nuevo, relaciones

## Plan de ejecución (orden de checkpoints)

1. **E1 Billing + Tienda + Drawer** — 3-4 sesiones
2. **E2 Ajustes rediseñado** — 2-3 sesiones (paralelo-friendly con E1 pero secuencial por gate)
3. **E4 Buzón + Interest** — 2 sesiones (sin cambios backend profundos + E1 ya da entitlement provider)
4. **E3 Editar perfil + Profile details** — 3-4 sesiones (el más grande en backend)
5. **E5 Cierre T4 + Navegar** — 1-2 sesiones

Total: 12-16 sesiones. Reportes de progreso por checkpoint en `.superpowers/sdd/grindr-100/checkpoint-{1..5}-report.md`.

## Testing y gates globales

**Cada checkpoint:**
- `flutter analyze` 0
- `flutter test` 100% verde (incluye nuevos tests)
- `flutter build apk --debug` ok
- `cargo build -p api` 0
- `cargo test -p api` verde (solo los tests del checkpoint)
- Deploy backend al VPS + smoke `curl` a los endpoints nuevos
- Commit en main con mensaje `feat(epicN): ...`

**Final (tras E5):**
- Suite completa
- APK debug construido
- Migraciones 0028+0029+0030 aplicadas en producción
- Smoke live de los 7 endpoints nuevos/modificados
- Reporte whole-branch diff completo
- Memoria actualizada + ledger cerrado

## Fuera de alcance (v1)

- Google Play Billing real (compra queda simulada)
- Sección VIAJES con gestión completa de travels (solo si feature flag)
- Feed "Grindr Presents"
- PIN sync entre devices (solo local)
- Icono app discreto real (alternar app icon necesita plugin platform-channel que se omite; placeholder grid)
- Traducción de chat con servicio externo
- Typing indicator en chat
- Reveal progresivo de fotos blurred con subscription real (badge "Desbloquear GRATIS" es CTA, no reveal real)
- Sponsored row en Buzón (sin ads)
- Persistencia del carrusel álbum-updates en tiempo real (solo fetch inicial)

## Riesgos identificados

| Riesgo | Mitigación |
|---|---|
| Migración 0027 ya existe, conflicto con 0028 | Revisar migraciones previas; 0028 solo añade defaults y validadores, no rompe nada |
| Backend live en producción; cambios requieren deploy cuidadoso | Checkpoint backend con `docker compose up -d --force-recreate api` después de migrar localmente primero |
| 140+ strings i18n nuevos pueden divergir ES/EN | Plantilla ES obligatoria; EN revisado al final de cada checkpoint antes de commit |
| Profile detail T4 WIP rompió algo | E5 arranca con commit del WIP actual + fix de lo que esté roto; sin eso no se añade |
| AppState del backend puede no tener slot para billing | Extender `backend/crates/api/src/state.rs` con `BillingState` antes de wire-up |
| 100 archivos tocados en 5 checkpoints genera conflictos inevitables | Cada checkpoint commitea y se reinicia desde main limpio antes del siguiente |
