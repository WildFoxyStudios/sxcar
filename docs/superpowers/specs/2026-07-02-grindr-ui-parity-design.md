# Spec: Grindr UI Parity — rediseño visual + arquitectura de navegación

**Fuente de verdad visual:** 34 capturas reales de Grindr Android en `Mobile/` (analizadas 2026-07-02).
**Decisiones del usuario:** (1) IA de navegación Grindr exacta; (2) Tienda con UI real + compra simulada vía backend (sin Google Play Billing); (3) i18n ES + EN con flutter_localizations.

## Objetivo

Que `apps/app` se vea y navegue como Grindr real: mismo lenguaje visual (negro puro, amarillo brillante, grids full-bleed, CTAs pill), misma arquitectura (drawer de perfil, 5 tabs Navegar/Right Now/Interest/Buzón/Tienda) y mismas pantallas, usando SOLO datos y endpoints reales del backend Vibra. Nada simulado salvo la compra (explícitamente marcada como simulada hasta integrar Play Billing).

**Restricción legal:** cero assets/marcas de Grindr (logo máscara, wordmark "XTRA"/"Grindr"). Se replican layout, espaciados y paleta; los nombres de tiers vienen de nuestros planes del backend (p. ej. "Vibra+", "Unlimited") y los iconos son de Material o propios.

## Design system (VibraTheme v3)

Tokens verbatim:
- `kBg = #000000` (fondo), `kSurface = #1A1A1A` (cards/bio), `kChip = #2A2A2A` (pills/chips/inputs), `kDivider = #333333`
- `kYellow = #FFCC00` (CTA, toggles ON, tab seleccionado, badge no-leídos), texto sobre amarillo SIEMPRE negro
- `kText = #FFFFFF`, `kTextSecondary = #8E8E8E`, `kTextTertiary = #666666`
- `kOnline = #1BD75E` (punto verde), `kBoost = #26D944` (rayo), `kRightNow = #9B51E0` (gotas), `kBadgeRed = #FF3B30` (dot notificaciones)
- Tipografía: Inter (google_fonts), pesos bold generosos; headers de sección: 13px, CAPS, letterspacing 1.2, kTextSecondary

Componentes compartidos (lib/src/theme/ o lib/src/widgets/):
- `YellowPillButton` — CTA full-width rounded-full amarillo, texto negro bold 18, usable flotante (sticky) sobre scroll
- `VibraSegmented` — segmented control pill: fondo kChip, opción activa blanca con texto negro (XTRA/UNLIMITED, Online/Incógnito, DESACTIVADA/ACTIVADO/AUTOMÁTICO)
- `SectionBand` — banda negra full-width con icono + título gris CAPS (separador de secciones en formularios/perfil)
- `UnderlineField` — campo estilo Grindr: label bold blanca arriba, valor/hint, subrayado gris, contador "n/max" abajo-derecha opcional
- `FilterChipPill` — chip rounded-full kChip texto blanco; estado activo: fondo blanco texto negro
- Switch amarillo global en ThemeData; scaffoldBackground kBg

## Arquitectura de navegación

Bottom nav (labels l10n): **Navegar** (grid_view) / **Right Now** (water_drop) / **Interest** (local_fire_department) / **Buzón** (chat_bubble) / **Tienda** (badge redondeado amarillo estilo tag). Seleccionado amarillo, no-seleccionado #777. Badges: dot rojo en Interest (views nuevos) y contador en Buzón (existente).

- Desaparece el tab **You** → su contenido se reparte: perfil/menú → **drawer**, Viewed Me → tab Interest.
- Desaparece el tab **Explore** → su grid global se convierte en la búsqueda del header de Navegar; su feed Right Now ya es el tab Right Now.
- **Drawer lateral** (se abre con el avatar del header de Navegar): foto cuadrada centrada, pill de nombre + lápiz (→ editar perfil), `VibraSegmented` Online/Incógnito (Incógnito real = pausa heartbeat → apareces offline; se documenta la limitación), sección COMPLEMENTOS (fila Boost → boost real; fila Right Now → tab), sección ELEGIR UN PLAN (card amarilla del plan destacado + cards oscuras de pases → Tienda), menú: Editar perfil, Mis álbumes, Salud sexual (→ sección salud de editar perfil), Centro de seguridad y privacidad (→ ajustes/privacidad), Ajustes.
- Rutas: `/navegar`, `/right-now`, `/interest`, `/inbox`(+`/:conversationId`), `/tienda`; fuera del shell: `/profile/:userId`, `/edit-profile`, `/settings...`, `/albums...`. Redirects legacy: `/cascade`→`/navegar`, `/you`→`/navegar` (+abre drawer no requerido), `/explore`→`/right-now`.

## Pantallas

### Navegar (grid)
Header: avatar circular (con dot online) que abre el drawer + pill de búsqueda kChip "Explorar más perfiles" (abre búsqueda sobre grid global = antiguo Explore) + fila horizontal de chips: [tune] Filtros (sheet existente; blanco cuando hay filtros activos), ⭐ (filtra favoritos reales), "En línea" (online_only), "Right Now" (→ tab). Grid 3 columnas full-bleed: gaps 1.5px, SIN border radius, tiles ~1:1.1, overlay inferior-izquierda: dot verde + nombre blanco 13 bold con sombra. Fila upsell intercalada tras ~6 filas: banda con logo del plan + "Ver más perfiles" → Tienda. FABs apilados abajo-derecha: pill negra "Boost ⚡" (rayo kBoost) y pill negra "Right Now 💧" (gotas kRightNow). Paginación/carga existente se mantiene.

### Perfil detalle
Hero foto full-bleed ~65% alto con overlay: ← atrás, iconos perfil-reportar y ⭐ favorito (real) arriba-derecha; indicador de paginación de fotos borde derecho (si >1 foto: swipe horizontal). Bajo el hero: nombre 34 bold + fila "● Conectado/Visto hace X" + stats rápidos `↓ Rol | 📏 altura | peso | cuerpo` (solo los campos presentes). Secciones con header gris CAPS: ACERCA DE MÍ (bio en card kSurface radius 24), ESTADÍSTICAS (filas icono gris + valor bold: altura/peso/cuerpo, pronombres+(i), rol, etnia, estado civil), EXPECTATIVAS (En busca de **...**, Encuentro en **...**), SALUD (VIH, último análisis, prácticas — datos reales Tier 1). TE PODRÍA INTERESAR + badge NUEVO amarillo: grid 2×2 de sugeridos (nearby real excluyendo el perfil actual; estos tiles SÍ con radius 12 + nombre overlay). Barra sticky inferior: input pill kChip "Di algo..." (envía primer mensaje real: createConversation+sendMessage → navega al chat), botón llama (tap real) y botón burbuja (→ chat) en amarillo outline. Al scrollear el nombre+dot aparecen en la top bar.

### Interest
Título grande izquierda + 2 tabs de texto con subrayado: **Views N** (dot rojo si hay nuevos) / **Taps N**. Views = GET /profile/views real: cards con foto, nombre+dot, "¡Ahora mismo!/hace X · Y km" (eye icon). Taps = lista actual restyled a cards. Sin gating (mostramos todo; el CTA amarillo inferior "Desbloquear todo sin límites" → Tienda queda como entrada de upsell). FAB Boost. Favoritos DEJAN de ser tab (viven en el chip ⭐ de Navegar).

### Buzón
2 tabs texto: **Bandeja de entrada** / **Álbumes** (contenido = pantalla Mis álbumes actual). Chips: ⭐ (conversaciones con favoritos si el dato existe; si no, omitir), "No Leído", "En línea" — filtros client-side sobre la lista real. Carrusel horizontal de actualizaciones de álbum: mi avatar con "+" ("Actualiza tu álbum" → mis álbumes) + avatares de álbumes compartidos conmigo (endpoint real de shares; si no existe listado, el implementador lo añade backend); vacío: texto gris. Filas: thumb cuadrado 72 radius 10, nombre bold (o preview), prefijo ➤ si el último mensaje es mío, columna derecha fecha corta + badge circular AMARILLO con contador no-leídos. FAB Boost.

### Tienda
Título centrado "Elija la actualización" + `VibraSegmented` con los 2 tiers reales (desde backend). Hero bg oscuro. Cards de duración horizontales: seleccionada = borde amarillo 2px + tinte amarillo oscuro; tag "POPULAR" gris; "Ahorra n%" calculado vs precio base. Lista de features por tier (icono círculo amarillo + título bold + subtítulo gris; contenido estático definido en la app por tier). Línea resumen "€X.XX/día por N, total Y €" + `YellowPillButton` "Continuar" → **POST /billing/simulate-purchase** (crea entitlement real en backend, sin cobro; respuesta muestra estado "Plan activo ✓"). Si ya hay entitlement activo: banner "Ya tienes [plan]" y Continuar deshabilitado. Legal text gris pequeño.

Backend: exponer `GET /billing/plans` público-auth (planes activos con precios/periodos desde admin) si no existe, `POST /billing/simulate-purchase {plan_id, period}` → inserta entitlement (marcado source='simulated'), `GET /billing/me` → entitlement activo. Tests de integración.

### Editar perfil
Header fotos: slot grande izquierda + 4 slots en 2×2 (fotos reales del perfil; + para añadir; long-press reordenar opcional). `UnderlineField` Nombre (contador /15) y Acerca de mí (multiline /255) + Mis etiquetas (chips de texto libre). Bandas: ESTADÍSTICAS (toggle "Mostrar edad" + explicación gris; Edad(read-only de dob), Altura, Peso, Etnia, Tipo de cuerpo, toggle "Mostrar rol", Rol, Estado de la relación), VIAJES (omitida en v1), PREFERENCIAS (toggle Mostrar mis tribes, Mis tribes, En busca de, Quedar en, Aceptar fotos NSFW), IDENTIDAD (Género, Pronombres), SALUD (los campos reales Tier 1: VIH, último análisis, recordatorio), RED SOCIAL (Instagram, X, Facebook — solo handles de texto). Selects → bottom sheets con opciones fijas. `YellowPillButton` Guardar sticky.

Backend: migración `0027_profile_details.sql` → `ALTER TABLE profiles ADD COLUMN IF NOT EXISTS details jsonb NOT NULL DEFAULT '{}'`; GET/PUT del perfil propio hacen passthrough del objeto `details` (height, weight, ethnicity, body_type, role, relationship, gender, pronouns, tribes[], looking_for[], meet_at[], accept_nsfw, tags[], social {instagram,x,facebook}, show_age, show_role, show_tribes). El detalle de perfil público expone `details` filtrado por los flags show_*.

### Ajustes
Estilo Grindr: headers gris CAPS, filas de texto bold (sin ListTile con iconos), toggles amarillos, `VibraSegmented` para 3-opciones. Secciones y mapeo REAL: CUENTA (Actualizar suscripción → Tienda; ID de usuario (id corto); Cerrar sesión), NOTIFICACIONES (prefs reales existentes; recordatorio de análisis Tier 3), CHAT (Confirmaciones de lectura — informativo), SEGURIDAD Y PRIVACIDAD (Alertas de captura de pantalla toggle real Tier 3; Desbloquear usuarios → lista real de bloqueados con acción unblock; Recordatorio inactividad Tier 3), PREFERENCIAS DE PANTALLA (Sistema de unidades mi/km — pref local aplicada a TODAS las distancias mostradas), SÍGUENOS (links estáticos). Lo que no tiene backend NO aparece.

## i18n

flutter_localizations + intl, `l10n.yaml`, `lib/l10n/app_es.arb` (plantilla) + `app_en.arb`. Locale del sistema con fallback ES. Las pantallas rediseñadas usan `AppLocalizations` desde el día 1; las no tocadas migran cuando se toquen. Los textos de las capturas son la referencia ES.

## Testing y gates

Por tarea: `flutter analyze` 0, tests dirigidos + suite completa verde. `flutter build apk --debug` en la tarea de navegación y en la final. Backend: `cargo build` + tests de integración de los endpoints nuevos. El cambio de router romperá widget tests existentes: arreglarlos es parte de la tarea de navegación, no deuda. Gate final: revisión whole-branch + deploy backend al VPS + smoke live.

## Fuera de alcance (v1)

Google Play Billing real; sección VIAJES; feed "Grindr Presents"; PIN de app; modo incógnito server-side (solo pausa heartbeat); traducción de chat; typing indicator; carrusel de álbumes con actualizaciones en tiempo real (solo lista de shares); icono de app discreto.
