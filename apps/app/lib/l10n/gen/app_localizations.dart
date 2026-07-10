import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// Bottom nav tab: Browse/Explore grid
  ///
  /// In es, this message translates to:
  /// **'Navegar'**
  String get navegar;

  /// Bottom nav tab: Right Now feed
  ///
  /// In es, this message translates to:
  /// **'Right Now'**
  String get rightNow;

  /// Bottom nav tab: Views & Taps
  ///
  /// In es, this message translates to:
  /// **'Interest'**
  String get interest;

  /// Bottom nav tab: Inbox / Chat list
  ///
  /// In es, this message translates to:
  /// **'Buzón'**
  String get buzon;

  /// Bottom nav tab: Shop / Plans
  ///
  /// In es, this message translates to:
  /// **'Tienda'**
  String get tienda;

  /// Search pill placeholder in Navegar header
  ///
  /// In es, this message translates to:
  /// **'Explorar más perfiles'**
  String get explorarMasPerfiles;

  /// Online filter chip label
  ///
  /// In es, this message translates to:
  /// **'En línea'**
  String get enLinea;

  /// Filters chip / sheet title
  ///
  /// In es, this message translates to:
  /// **'Filtros'**
  String get filtros;

  /// Favorites filter chip / tab label
  ///
  /// In es, this message translates to:
  /// **'Favoritos'**
  String get favoritos;

  /// Upsell band CTA in Navegar grid
  ///
  /// In es, this message translates to:
  /// **'Ver más perfiles'**
  String get verMasPerfiles;

  /// Boost FAB / feature label
  ///
  /// In es, this message translates to:
  /// **'Boost'**
  String get boost;

  /// Save button label (edit profile, settings)
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get guardar;

  /// Edit profile action label
  ///
  /// In es, this message translates to:
  /// **'Editar perfil'**
  String get editarPerfil;

  /// My albums menu item
  ///
  /// In es, this message translates to:
  /// **'Mis álbumes'**
  String get misAlbumes;

  /// Settings menu item / screen title
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get ajustes;

  /// Online presence mode label in drawer segmented
  ///
  /// In es, this message translates to:
  /// **'En línea'**
  String get online;

  /// Incognito presence mode label in drawer segmented
  ///
  /// In es, this message translates to:
  /// **'Incógnito'**
  String get incognito;

  /// About Me profile section header
  ///
  /// In es, this message translates to:
  /// **'Acerca de mí'**
  String get acercaDeMi;

  /// Stats profile section header
  ///
  /// In es, this message translates to:
  /// **'Estadísticas'**
  String get estadisticas;

  /// Expectations profile section header
  ///
  /// In es, this message translates to:
  /// **'Expectativas'**
  String get expectativas;

  /// Health profile section header
  ///
  /// In es, this message translates to:
  /// **'Salud'**
  String get salud;

  /// You might like section header on profile detail
  ///
  /// In es, this message translates to:
  /// **'Te podría interesar'**
  String get tePodriaInteresar;

  /// New badge label (e.g., on PODRÍA INTERESAR)
  ///
  /// In es, this message translates to:
  /// **'Nuevo'**
  String get nuevo;

  /// Placeholder for message input on profile detail
  ///
  /// In es, this message translates to:
  /// **'Di algo...'**
  String get diAlgo;

  /// Connected / online status label
  ///
  /// In es, this message translates to:
  /// **'Conectado'**
  String get conectado;

  /// Inbox tab label in chat list
  ///
  /// In es, this message translates to:
  /// **'Bandeja de entrada'**
  String get bandejaDeEntrada;

  /// Albums tab label in chat list
  ///
  /// In es, this message translates to:
  /// **'Álbumes'**
  String get albumes;

  /// Unread filter chip in chat list
  ///
  /// In es, this message translates to:
  /// **'No leído'**
  String get noLeido;

  /// Views tab label in Interest screen
  ///
  /// In es, this message translates to:
  /// **'Views'**
  String get views;

  /// Taps tab label in Interest screen
  ///
  /// In es, this message translates to:
  /// **'Taps'**
  String get taps;

  /// No description provided for @tapsReceived.
  ///
  /// In es, this message translates to:
  /// **'Recibidos'**
  String get tapsReceived;

  /// No description provided for @tapsSent.
  ///
  /// In es, this message translates to:
  /// **'Enviados'**
  String get tapsSent;

  /// Unlock everything CTA (Interest screen bottom bar)
  ///
  /// In es, this message translates to:
  /// **'Desbloquear todo'**
  String get desbloquearTodo;

  /// Shop screen title: Choose your upgrade
  ///
  /// In es, this message translates to:
  /// **'Elija la actualización'**
  String get elijaLaActualizacion;

  /// Continue CTA button (shop / onboarding)
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get continuar;

  /// Save X% label on plan duration cards
  ///
  /// In es, this message translates to:
  /// **'Ahorra {percent}%'**
  String ahorra(int percent);

  /// Popular badge on a plan duration card
  ///
  /// In es, this message translates to:
  /// **'Popular'**
  String get popular;

  /// Add-ons section on shop screen
  ///
  /// In es, this message translates to:
  /// **'Complementos'**
  String get complementos;

  /// Choose a plan CTA in drawer
  ///
  /// In es, this message translates to:
  /// **'Elegir un plan'**
  String get elegirUnPlan;

  /// Update your album label in chat list carousel
  ///
  /// In es, this message translates to:
  /// **'Actualiza tu álbum'**
  String get actualizaTuAlbum;

  /// Looking For field label on profile
  ///
  /// In es, this message translates to:
  /// **'En busca de'**
  String get enBuscaDe;

  /// Meet At field label on profile
  ///
  /// In es, this message translates to:
  /// **'Quedar en'**
  String get quedarEn;

  /// Log out action label in settings / drawer
  ///
  /// In es, this message translates to:
  /// **'Cerrar sesión'**
  String get cerrarSesion;

  /// Sexual health menu item in drawer
  ///
  /// In es, this message translates to:
  /// **'Salud sexual'**
  String get saludSexual;

  /// Safety & privacy center menu item in drawer
  ///
  /// In es, this message translates to:
  /// **'Centro de seguridad y privacidad'**
  String get seguridadPrivacidad;

  /// See plans CTA on secondary plan card in drawer
  ///
  /// In es, this message translates to:
  /// **'Ver planes'**
  String get verPlanes;

  /// Placeholder plan CTA in drawer (T7 wires real plan name)
  ///
  /// In es, this message translates to:
  /// **'Obtener Premium'**
  String get obtenerPremium;

  /// Plan card subtitle in drawer
  ///
  /// In es, this message translates to:
  /// **'Chatear con más lugareños'**
  String get chatearMasLugarenos;

  /// Shop screen title variant - alt spelling (legacy Compat)
  ///
  /// In es, this message translates to:
  /// **'Elija la actualización'**
  String get elijeLaActualizacion;

  /// Week period label on shop duration cards
  ///
  /// In es, this message translates to:
  /// **'SEMANA'**
  String get semana;

  /// Month period label on shop duration cards
  ///
  /// In es, this message translates to:
  /// **'MES'**
  String get mes;

  /// Months period label on shop duration cards
  ///
  /// In es, this message translates to:
  /// **'MESES'**
  String get meses;

  /// Purchase a day pass CTA
  ///
  /// In es, this message translates to:
  /// **'Compra Pase de día'**
  String get compraPaseDia;

  /// Purchase Unlimited 7 days CTA
  ///
  /// In es, this message translates to:
  /// **'Compra Unlimited 7 días'**
  String get compraIlimitado7Dias;

  /// Free tier label
  ///
  /// In es, this message translates to:
  /// **'GRATIS'**
  String get gratis;

  /// Hero subtitle on Tienda top
  ///
  /// In es, this message translates to:
  /// **'Encuentra más, más rápido'**
  String get encuentraMasMasRapido;

  /// Hero subtitle on Tienda for Unlimited tier
  ///
  /// In es, this message translates to:
  /// **'Más acceso. Más atención.'**
  String get masAccesoMasAtencion;

  /// XTRA tier label (legacy / Compat)
  ///
  /// In es, this message translates to:
  /// **'Pulse'**
  String get xtra;

  /// Unlimited tier label
  ///
  /// In es, this message translates to:
  /// **'Aura'**
  String get unlimited;

  /// Unlimited chats feature bullet
  ///
  /// In es, this message translates to:
  /// **'Chats ilimitados en Explorar'**
  String get chatIlimitados;

  /// Unlimited photos feature bullet
  ///
  /// In es, this message translates to:
  /// **'Fotos ilimitadas sin caducidad'**
  String get fotosIlimitadasSinCaducidad;

  /// Chat translation feature bullet
  ///
  /// In es, this message translates to:
  /// **'Traducción en chat'**
  String get traduccionChat;

  /// Typing indicator feature bullet
  ///
  /// In es, this message translates to:
  /// **'Indicador \"escribiendo…\"'**
  String get estadoEscribiendo;

  /// Unlimited features label
  ///
  /// In es, this message translates to:
  /// **'Funciones ilimitadas'**
  String get funcionesIlimitadas;

  /// Unlimited profiles feature bullet
  ///
  /// In es, this message translates to:
  /// **'Perfiles ilimitados'**
  String get perfilesIlimitados;

  /// Incognito browsing feature bullet
  ///
  /// In es, this message translates to:
  /// **'Navegar en modo incógnito'**
  String get navegarIncognito;

  /// Ad-free feature bullet
  ///
  /// In es, this message translates to:
  /// **'Sin interrupciones de anuncios'**
  String get sinInterrupciones;

  /// See who viewed me feature bullet
  ///
  /// In es, this message translates to:
  /// **'Ver quién me ha visto'**
  String get quienMeHaVisto;

  /// TiendaScreen summary line under the plan hero (e.g. €0.30/día por 30 días)
  ///
  /// In es, this message translates to:
  /// **'{price}/día por {days} días'**
  String precioContinuar(String price, int days);

  /// TiendaScreen total price label (e.g. Total €8.99)
  ///
  /// In es, this message translates to:
  /// **'Total {total}'**
  String precioTotal(String total);

  /// TiendaScreen fine-print disclaimer under the Continue CTA
  ///
  /// In es, this message translates to:
  /// **'Compra simulada (sin cargo)'**
  String get compraSimulada;

  /// Short label for active subscription banner (drawer + Tienda top)
  ///
  /// In es, this message translates to:
  /// **'Plan activo ✓'**
  String get planActivo;

  /// Settings → Account section header
  ///
  /// In es, this message translates to:
  /// **'Cuenta'**
  String get cuenta;

  /// Settings → Multimedia section header
  ///
  /// In es, this message translates to:
  /// **'Multimedia'**
  String get multimedia;

  /// Privacy pref toggle for showing album updates
  ///
  /// In es, this message translates to:
  /// **'Mostrar actualizaciones de mis álbumes'**
  String get mostrarActualizacionesAlbumes;

  /// Privacy pref toggle for the inbox carousel
  ///
  /// In es, this message translates to:
  /// **'Mostrar carrusel en la bandeja'**
  String get mostrarCarruselBandeja;

  /// Settings link to Security Center (placeholder)
  ///
  /// In es, this message translates to:
  /// **'Centro de seguridad'**
  String get centroSeguridad;

  /// Settings toggle for discreet app icon
  ///
  /// In es, this message translates to:
  /// **'Icono de aplicación discreto'**
  String get iconoAplicacionDiscreto;

  /// Settings row label for PIN lock
  ///
  /// In es, this message translates to:
  /// **'PIN'**
  String get pin;

  /// Settings link to blocked users list
  ///
  /// In es, this message translates to:
  /// **'Desbloquear usuarios'**
  String get desbloquearUsuarios;

  /// Hidden users action (companion to blocks)
  ///
  /// In es, this message translates to:
  /// **'Dejar de ocultar usuarios'**
  String get dejarOcultarUsuarios;

  /// Settings link to consent preferences (placeholder)
  ///
  /// In es, this message translates to:
  /// **'Preferencias de consentimiento'**
  String get preferenciasConsentimiento;

  /// Settings link to data export (placeholder)
  ///
  /// In es, this message translates to:
  /// **'Descargar mis datos'**
  String get descargarDatos;

  /// DND pref label
  ///
  /// In es, this message translates to:
  /// **'No molestar'**
  String get noMolestar;

  /// Privacy pref toggle for chat-mark-chatted
  ///
  /// In es, this message translates to:
  /// **'Marcar con quién he chateado'**
  String get marcarConQuienChateeado;

  /// Privacy pref toggle for message sync
  ///
  /// In es, this message translates to:
  /// **'Sincronización de mensajes'**
  String get sincronizacionMensajes;

  /// Settings → Location section header
  ///
  /// In es, this message translates to:
  /// **'Ubicación'**
  String get ubicacion;

  /// Settings → Home section header (or sub-section)
  ///
  /// In es, this message translates to:
  /// **'Inicio'**
  String get inicio;

  /// Settings row for visitor status (off/enabled/auto)
  ///
  /// In es, this message translates to:
  /// **'Estado de visitante'**
  String get estadoVisitante;

  /// Visitor status: disabled option label
  ///
  /// In es, this message translates to:
  /// **'Desactivada'**
  String get desactivada;

  /// Visitor status: enabled option label
  ///
  /// In es, this message translates to:
  /// **'Activado'**
  String get activado;

  /// Visitor status: auto option label
  ///
  /// In es, this message translates to:
  /// **'Automático'**
  String get automatico;

  /// Settings → Screen preferences section header
  ///
  /// In es, this message translates to:
  /// **'Preferencias de pantalla'**
  String get preferenciasPantalla;

  /// Privacy pref toggle for screen keep-unlocked
  ///
  /// In es, this message translates to:
  /// **'Mantener la pantalla desbloqueada'**
  String get mantenerPantallaDesbloqueada;

  /// Settings row for unit system (metric/imperial)
  ///
  /// In es, this message translates to:
  /// **'Sistema de unidades'**
  String get sistemaUnidades;

  /// Unit system: metric option
  ///
  /// In es, this message translates to:
  /// **'Métrico'**
  String get metrico;

  /// Unit system: imperial option
  ///
  /// In es, this message translates to:
  /// **'Imperial'**
  String get imperial;

  /// Settings → Social section header
  ///
  /// In es, this message translates to:
  /// **'Síguenos'**
  String get siguenos;

  /// Settings link to delete account (placeholder)
  ///
  /// In es, this message translates to:
  /// **'Eliminar cuenta'**
  String get eliminarCuenta;

  /// Delete account confirmation dialog title
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar cuenta?'**
  String get confirmarEliminar;

  /// Snackbar when a notification-pref PUT fails
  ///
  /// In es, this message translates to:
  /// **'Error guardando preferencia'**
  String get errorGuardandoPreferencia;

  /// Retry button on error state
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get reintentar;

  /// Settings → Notifications/Sessions section header
  ///
  /// In es, this message translates to:
  /// **'Notificaciones y sesiones'**
  String get notificacionesYSesiones;

  /// Notification toggle for new message alerts
  ///
  /// In es, this message translates to:
  /// **'Mensajes nuevos'**
  String get mensajesNuevos;

  /// Notification toggle for new tap alerts
  ///
  /// In es, this message translates to:
  /// **'Taps nuevos'**
  String get tapsNuevos;

  /// Notification toggle for promotional pushes
  ///
  /// In es, this message translates to:
  /// **'Promociones'**
  String get promociones;

  /// Settings row linking to saved phrases
  ///
  /// In es, this message translates to:
  /// **'Frases guardadas'**
  String get frasesGuardadas;

  /// Settings row linking to active sessions
  ///
  /// In es, this message translates to:
  /// **'Sesiones activas'**
  String get sesionesActivas;

  /// Coming-soon placeholder body text
  ///
  /// In es, this message translates to:
  /// **'Próximamente.'**
  String get proximamente;

  /// OK button on placeholder dialogs
  ///
  /// In es, this message translates to:
  /// **'OK'**
  String get ok;

  /// Cancel button on dialogs (delete account, etc.)
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get cancelar;

  /// Delete button on delete-account confirm dialog
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get eliminar;

  /// Delete account confirm dialog body text
  ///
  /// In es, this message translates to:
  /// **'Esta acción no se puede deshacer.'**
  String get accionNoSePuedeDeshacer;

  /// Distance label used in chat list / interest rows
  ///
  /// In es, this message translates to:
  /// **'Distancia'**
  String get distancia;

  /// Online-only filter chip on chat list
  ///
  /// In es, this message translates to:
  /// **'En línea'**
  String get enLineaFiltro;

  /// Empty state for AlbumUpdatesEmptyState widget
  ///
  /// In es, this message translates to:
  /// **'No hay actualizaciones de álbum'**
  String get noHayActualizaciones;

  /// NUEVO badge CTA on Interest screen when count > 6
  ///
  /// In es, this message translates to:
  /// **'Desbloquear GRATIS'**
  String get desbloquearGratis;

  /// Tienda upsell subtitle on Interest screen
  ///
  /// In es, this message translates to:
  /// **'Desbloquea todo sin límites'**
  String get desbloquearTodoSinLimites;

  /// Boost FAB on Interest screen
  ///
  /// In es, this message translates to:
  /// **'Boost tu Interest'**
  String get boostTuInterest;

  /// Right-now filter chip / state label
  ///
  /// In es, this message translates to:
  /// **'Ahora mismo'**
  String get ahoraMismo;

  /// Share album action in albums grid
  ///
  /// In es, this message translates to:
  /// **'Compartir álbum'**
  String get compartirAlbum;

  /// User picker prompt when sharing album
  ///
  /// In es, this message translates to:
  /// **'Seleccionar usuarios'**
  String get seleccionarUsuarios;

  /// Success toast when album is shared
  ///
  /// In es, this message translates to:
  /// **'Álbum compartido'**
  String get archivoCompartido;

  /// Delete-album action in album options
  ///
  /// In es, this message translates to:
  /// **'Eliminar álbum'**
  String get eliminarAlbum;

  /// Albums-screen section header for albums I have shared
  ///
  /// In es, this message translates to:
  /// **'Mis compartidos'**
  String get misShares;

  /// View action button (album / share)
  ///
  /// In es, this message translates to:
  /// **'Ver'**
  String get ver;

  /// Generic 'do' action button (e.g. 'Hacer tap')
  ///
  /// In es, this message translates to:
  /// **'Hacer'**
  String get hacer;

  /// AlbumUpdateBanner label for count = 1
  ///
  /// In es, this message translates to:
  /// **'1 álbum actualizado'**
  String get albumActualizadoSingular;

  /// AlbumUpdateBanner label for count > 1
  ///
  /// In es, this message translates to:
  /// **'{count} álbumes actualizados'**
  String albumesActualizadosPlural(int count);

  /// ChatListScreen Bandeja error state message
  ///
  /// In es, this message translates to:
  /// **'Error cargando conversaciones'**
  String get errorCargandoConversaciones;

  /// ChatListScreen Álbumes error state message
  ///
  /// In es, this message translates to:
  /// **'Error cargando álbumes compartidos'**
  String get errorCargandoAlbumesCompartidos;

  /// Interest screen sticky CTA label
  ///
  /// In es, this message translates to:
  /// **'Desbloquear sin límites'**
  String get desbloquearSinLimites;

  /// Interest screen Views tab error message
  ///
  /// In es, this message translates to:
  /// **'Error cargando vistas'**
  String get errorCargandoVistas;

  /// Interest screen Taps tab empty state
  ///
  /// In es, this message translates to:
  /// **'Sin taps aún'**
  String get sinTaps;

  /// Interest screen Taps tab error message
  ///
  /// In es, this message translates to:
  /// **'Error cargando taps'**
  String get errorCargandoTaps;

  /// Interest screen Views row subtitle (placeholder fecha is YYYY-MM-DD)
  ///
  /// In es, this message translates to:
  /// **'Visto el {fecha}'**
  String vistoEl(String fecha);

  /// Interest screen Taps row subtitle
  ///
  /// In es, this message translates to:
  /// **'Tipo: {tipo}'**
  String tipoTap(String tipo);

  /// Interest screen Views tab empty state
  ///
  /// In es, this message translates to:
  /// **'Nadie ha visto tu perfil aún'**
  String get nadieHaVistoPerfil;

  /// Albums screen empty state title
  ///
  /// In es, this message translates to:
  /// **'No tienes álbumes aún'**
  String get noTienesAlbumes;

  /// Albums screen empty state subtitle
  ///
  /// In es, this message translates to:
  /// **'Toca + para crear tu primer álbum'**
  String get tocaMasParaCrearAlbum;

  /// Albums screen share error snackbar prefix
  ///
  /// In es, this message translates to:
  /// **'Error al compartir'**
  String get errorAlCompartir;

  /// Albums screen delete error snackbar prefix
  ///
  /// In es, this message translates to:
  /// **'Error al eliminar'**
  String get errorAlEliminar;

  /// Albums screen delete confirmation dialog body
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar este álbum?'**
  String get confirmarEliminarAlbum;

  /// Albums screen share sheet TextField hint
  ///
  /// In es, this message translates to:
  /// **'user_id (UUID)'**
  String get userIdHint;

  /// Albums screen 'my albums' section header (separate from AppBar misShares title)
  ///
  /// In es, this message translates to:
  /// **'Mis álbumes'**
  String get misAlbumesHeader;

  /// Edit profile screen section header: Basic info
  ///
  /// In es, this message translates to:
  /// **'Datos básicos'**
  String get editProfileSectionBasics;

  /// Edit profile screen section header: Appearance
  ///
  /// In es, this message translates to:
  /// **'Apariencia'**
  String get editProfileSectionAppearance;

  /// Edit profile screen section header: Tribes
  ///
  /// In es, this message translates to:
  /// **'Tribus'**
  String get editProfileSectionTribes;

  /// Edit profile screen section header: What I'm looking for
  ///
  /// In es, this message translates to:
  /// **'Lo que busco'**
  String get editProfileSectionLookingFor;

  /// Edit profile screen section header: What I like
  ///
  /// In es, this message translates to:
  /// **'Lo que me gusta'**
  String get editProfileSectionLikes;

  /// Edit profile screen section header: Health
  ///
  /// In es, this message translates to:
  /// **'Salud'**
  String get editProfileSectionHealth;

  /// Edit profile screen section header: What I do (practices)
  ///
  /// In es, this message translates to:
  /// **'Lo que hago'**
  String get editProfileSectionPractices;

  /// Edit profile screen section header: Privacy
  ///
  /// In es, this message translates to:
  /// **'Privacidad'**
  String get editProfileSectionPrivacy;

  /// Selector sheet title: choose ethnicity
  ///
  /// In es, this message translates to:
  /// **'Selecciona etnia'**
  String get sheetSelectEthnicity;

  /// Selector sheet title: choose body type
  ///
  /// In es, this message translates to:
  /// **'Tipo de cuerpo'**
  String get sheetSelectBodyType;

  /// Selector sheet title: choose sexual position
  ///
  /// In es, this message translates to:
  /// **'Posición'**
  String get sheetSelectPosition;

  /// Selector sheet title: choose pronouns
  ///
  /// In es, this message translates to:
  /// **'Pronombres'**
  String get sheetSelectPronouns;

  /// Selector sheet title: choose relationship status
  ///
  /// In es, this message translates to:
  /// **'Estado civil'**
  String get sheetSelectRelationship;

  /// Selector sheet title: choose role (top/bottom/versatile etc.)
  ///
  /// In es, this message translates to:
  /// **'Rol'**
  String get sheetSelectRole;

  /// Selector sheet title: choose what user is looking for
  ///
  /// In es, this message translates to:
  /// **'Busco'**
  String get sheetSelectLookingFor;

  /// Selector sheet title: choose meet-at preference
  ///
  /// In es, this message translates to:
  /// **'Quedamos en'**
  String get sheetSelectMeetAt;

  /// Selector sheet title: choose interests/tags
  ///
  /// In es, this message translates to:
  /// **'Intereses'**
  String get sheetSelectTags;

  /// Selector sheet title: enter height in cm
  ///
  /// In es, this message translates to:
  /// **'Altura (cm)'**
  String get sheetSelectHeight;

  /// Selector sheet title: enter weight in kg
  ///
  /// In es, this message translates to:
  /// **'Peso (kg)'**
  String get sheetSelectWeight;

  /// Edit profile Save button
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get editProfileSave;

  /// Edit profile Cancel button
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get editProfileCancel;

  /// Edit profile Add action (e.g. add tribe / tag)
  ///
  /// In es, this message translates to:
  /// **'Añadir'**
  String get editProfileAdd;

  /// Edit profile Remove action (e.g. remove tribe / tag)
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get editProfileRemove;

  /// Edit profile save error snackbar
  ///
  /// In es, this message translates to:
  /// **'No se pudo guardar. Inténtalo de nuevo.'**
  String get editProfileSaveError;

  /// Edit profile saved confirmation snackbar
  ///
  /// In es, this message translates to:
  /// **'Perfil actualizado'**
  String get editProfileSaved;

  /// Profile details sub-field label: Vaccines (HIV PrEP / vaccine list)
  ///
  /// In es, this message translates to:
  /// **'Vacunas'**
  String get detailsVaccines;

  /// Profile details sub-field label: Trip count
  ///
  /// In es, this message translates to:
  /// **'Viajes'**
  String get detailsTripCount;

  /// Profile details sub-field label: Sexual practices selection
  ///
  /// In es, this message translates to:
  /// **'Prácticas'**
  String get detailsPractices;

  /// Profile details sub-field label: Social links
  ///
  /// In es, this message translates to:
  /// **'Redes sociales'**
  String get detailsSocial;

  /// Edit profile field label: Height
  ///
  /// In es, this message translates to:
  /// **'Altura'**
  String get editProfileFieldHeight;

  /// Edit profile field label: Weight
  ///
  /// In es, this message translates to:
  /// **'Peso'**
  String get editProfileFieldWeight;

  /// Edit profile field label: Body Type
  ///
  /// In es, this message translates to:
  /// **'Tipo de cuerpo'**
  String get editProfileFieldBodyType;

  /// Edit profile field label: Ethnicity
  ///
  /// In es, this message translates to:
  /// **'Etnia'**
  String get editProfileFieldEthnicity;

  /// Edit profile field label: Pronouns
  ///
  /// In es, this message translates to:
  /// **'Pronombres'**
  String get editProfileFieldPronouns;

  /// Edit profile field label: Looking For
  ///
  /// In es, this message translates to:
  /// **'Busco'**
  String get editProfileFieldLookingFor;

  /// Edit profile field label: Meet At
  ///
  /// In es, this message translates to:
  /// **'Lugar de encuentro'**
  String get editProfileFieldMeetAt;

  /// Edit profile field label: Position
  ///
  /// In es, this message translates to:
  /// **'Posición'**
  String get editProfileFieldPosition;

  /// Edit profile field label: Relationship Status
  ///
  /// In es, this message translates to:
  /// **'Estado civil'**
  String get editProfileFieldRelationshipStatus;

  /// Edit profile placeholder: Select height
  ///
  /// In es, this message translates to:
  /// **'Seleccionar altura'**
  String get editProfilePlaceholderHeight;

  /// Edit profile placeholder: Select weight
  ///
  /// In es, this message translates to:
  /// **'Seleccionar peso'**
  String get editProfilePlaceholderWeight;

  /// Edit profile placeholder: Select body type
  ///
  /// In es, this message translates to:
  /// **'Seleccionar tipo de cuerpo'**
  String get editProfilePlaceholderBodyType;

  /// Edit profile placeholder: Select ethnicity
  ///
  /// In es, this message translates to:
  /// **'Seleccionar etnia'**
  String get editProfilePlaceholderEthnicity;

  /// Edit profile placeholder: Select pronouns
  ///
  /// In es, this message translates to:
  /// **'Seleccionar pronombres'**
  String get editProfilePlaceholderPronouns;

  /// Edit profile placeholder: Select what you are looking for
  ///
  /// In es, this message translates to:
  /// **'Seleccionar lo que buscas'**
  String get editProfilePlaceholderLookingFor;

  /// Edit profile placeholder: Select where to meet
  ///
  /// In es, this message translates to:
  /// **'Seleccionar lugar de encuentro'**
  String get editProfilePlaceholderMeetAt;

  /// Edit profile placeholder: Select position
  ///
  /// In es, this message translates to:
  /// **'Seleccionar posición'**
  String get editProfilePlaceholderPosition;

  /// Edit profile placeholder: Select relationship status
  ///
  /// In es, this message translates to:
  /// **'Seleccionar estado civil'**
  String get editProfilePlaceholderRelationshipStatus;

  /// Edit profile placeholder: Select vaccines
  ///
  /// In es, this message translates to:
  /// **'Seleccionar vacunas'**
  String get editProfilePlaceholderVaccines;

  /// Edit profile placeholder: Add recent trips
  ///
  /// In es, this message translates to:
  /// **'Añadir viajes recientes'**
  String get editProfilePlaceholderTrips;

  /// Edit profile placeholder: Select practices
  ///
  /// In es, this message translates to:
  /// **'Seleccionar prácticas'**
  String get editProfilePlaceholderPractices;

  /// Edit profile count label: N selected
  ///
  /// In es, this message translates to:
  /// **'{count} seleccionados'**
  String editProfileCountSelected(int count);

  /// Edit profile count label: N trips
  ///
  /// In es, this message translates to:
  /// **'{count} viajes'**
  String editProfileCountTrips(int count);

  /// Profile detail age suffix, e.g. '35 años' / '35 yrs'
  ///
  /// In es, this message translates to:
  /// **'años'**
  String get profileAgeSuffix;

  /// Profile detail label for relationship status row
  ///
  /// In es, this message translates to:
  /// **'Estado civil'**
  String get profileRelationshipLabel;

  /// Profile detail social block label: Follow me on
  ///
  /// In es, this message translates to:
  /// **'Sígueme en'**
  String get profileFollowOn;

  /// Profile detail tap action for opening a social link externally
  ///
  /// In es, this message translates to:
  /// **'Abrir enlace externo'**
  String get profileOpenExternalLink;

  /// Distance unit: kilometers (metric)
  ///
  /// In es, this message translates to:
  /// **'km'**
  String get unitKilometers;

  /// Distance unit: meters (metric, sub-1km)
  ///
  /// In es, this message translates to:
  /// **'m'**
  String get unitMeters;

  /// Distance unit: miles (imperial)
  ///
  /// In es, this message translates to:
  /// **'mi'**
  String get unitMiles;

  /// Distance unit: feet (imperial, sub-1mi)
  ///
  /// In es, this message translates to:
  /// **'ft'**
  String get unitFeet;

  /// Cascade/GridSearch filter chip: only favorited users
  ///
  /// In es, this message translates to:
  /// **'Favoritos'**
  String get filterFavoritesOnly;

  /// Cascade/GridSearch filter chip: only recently-online users (last 5min)
  ///
  /// In es, this message translates to:
  /// **'En línea'**
  String get filterOnlineOnly;

  /// Cascade/GridSearch filter chip: recently active users (last 30min)
  ///
  /// In es, this message translates to:
  /// **'Ahora'**
  String get filterRightNow;

  /// Cascade filter chip: only users with a profile photo
  ///
  /// In es, this message translates to:
  /// **'Con foto'**
  String get filterPhotosOnly;

  /// Cascade filter chip: only users not yet chatted with
  ///
  /// In es, this message translates to:
  /// **'Sin chatear'**
  String get filterNotChatted;

  /// Cascade filter chip: filter by sexual position
  ///
  /// In es, this message translates to:
  /// **'Posición'**
  String get filterPosition;

  /// NUEVO badge on accounts created within the last 7 days
  ///
  /// In es, this message translates to:
  /// **'NUEVO'**
  String get badgeNew;

  /// Typing indicator shown in chat when the peer is composing a message
  ///
  /// In es, this message translates to:
  /// **'escribiendo…'**
  String get chatTyping;

  /// Action button to unsend/delete a sent message
  ///
  /// In es, this message translates to:
  /// **'Anular envío'**
  String get chatUnsend;

  /// Placeholder shown in place of an unsent message
  ///
  /// In es, this message translates to:
  /// **'[Mensaje anulado]'**
  String get chatUnsentMessage;

  /// Label for voice message audio bubble
  ///
  /// In es, this message translates to:
  /// **'Mensaje de voz'**
  String get chatVoiceMessage;

  /// Label shown while recording a voice message
  ///
  /// In es, this message translates to:
  /// **'Grabando…'**
  String get chatRecording;

  /// City search placeholder in Explore screen search bar
  ///
  /// In es, this message translates to:
  /// **'Buscar ciudad…'**
  String get exploreSearchHint;

  /// Button to return to GPS-based location after city search
  ///
  /// In es, this message translates to:
  /// **'Volver a mi ubicación'**
  String get exploreBackToMyLocation;

  /// Empty state when geocoding returns no results
  ///
  /// In es, this message translates to:
  /// **'Sin resultados'**
  String get exploreNoResults;

  /// Label for recent city searches list
  ///
  /// In es, this message translates to:
  /// **'Recientes'**
  String get exploreRecentSearches;

  /// Call screen: outgoing call status label
  ///
  /// In es, this message translates to:
  /// **'Llamando…'**
  String get callOutgoing;

  /// Call screen: incoming call notification label
  ///
  /// In es, this message translates to:
  /// **'Te está llamando…'**
  String get callIncoming;

  /// Call screen: accept incoming call button
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get callAccept;

  /// Call screen: reject incoming call button
  ///
  /// In es, this message translates to:
  /// **'Rechazar'**
  String get callReject;

  /// Call screen: call ended status label
  ///
  /// In es, this message translates to:
  /// **'Llamada finalizada'**
  String get callEnded;

  /// Circles (group chats) screen title
  ///
  /// In es, this message translates to:
  /// **'Círculos'**
  String get circlesTitle;

  /// Create group action button / screen title
  ///
  /// In es, this message translates to:
  /// **'Crear grupo'**
  String get createGroup;

  /// Group name label / TextField hint
  ///
  /// In es, this message translates to:
  /// **'Nombre del grupo'**
  String get groupName;

  /// Add members action / section title
  ///
  /// In es, this message translates to:
  /// **'Añadir miembros'**
  String get addMembers;

  /// Group info screen title
  ///
  /// In es, this message translates to:
  /// **'Info del grupo'**
  String get groupInfo;

  /// Leave group action button
  ///
  /// In es, this message translates to:
  /// **'Salir del grupo'**
  String get leaveGroup;

  /// Empty state when user has no groups
  ///
  /// In es, this message translates to:
  /// **'No tienes círculos aún'**
  String get noGroupsYet;

  /// Success toast after creating a group
  ///
  /// In es, this message translates to:
  /// **'Grupo creado'**
  String get groupCreated;

  /// Group member count label
  ///
  /// In es, this message translates to:
  /// **'{count} miembros'**
  String memberCount(int count);

  /// Stories / Spotlight section title
  ///
  /// In es, this message translates to:
  /// **'Historias'**
  String get storiesTitle;

  /// Button to create a new story
  ///
  /// In es, this message translates to:
  /// **'Añadir historia'**
  String get addStory;

  /// Caption text field placeholder for stories
  ///
  /// In es, this message translates to:
  /// **'Escribe un pie…'**
  String get storyCaption;

  /// Hint text for story avatars
  ///
  /// In es, this message translates to:
  /// **'Toca para ver'**
  String get tapToView;

  /// No description provided for @onboarding_title.
  ///
  /// In es, this message translates to:
  /// **'Configura tu perfil'**
  String get onboarding_title;

  /// No description provided for @onboarding_subtitle.
  ///
  /// In es, this message translates to:
  /// **'Cuenta a otros sobre ti'**
  String get onboarding_subtitle;

  /// No description provided for @onboarding_required_progress.
  ///
  /// In es, this message translates to:
  /// **'{done} de {total} obligatorios completados'**
  String onboarding_required_progress(int done, int total);

  /// No description provided for @onboarding_optional_progress.
  ///
  /// In es, this message translates to:
  /// **'{done} de {total} opcionales completados'**
  String onboarding_optional_progress(int done, int total);

  /// No description provided for @onboarding_next.
  ///
  /// In es, this message translates to:
  /// **'Siguiente'**
  String get onboarding_next;

  /// No description provided for @onboarding_skip.
  ///
  /// In es, this message translates to:
  /// **'Omitir'**
  String get onboarding_skip;

  /// No description provided for @onboarding_close.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get onboarding_close;

  /// No description provided for @onboarding_skip_all.
  ///
  /// In es, this message translates to:
  /// **'Saltar todo el wizard'**
  String get onboarding_skip_all;

  /// No description provided for @onboarding_skip_all_confirm_title.
  ///
  /// In es, this message translates to:
  /// **'¿Saltar todo el wizard?'**
  String get onboarding_skip_all_confirm_title;

  /// No description provided for @onboarding_skip_all_confirm_body.
  ///
  /// In es, this message translates to:
  /// **'Tu perfil no será visible para otros hasta que completes los campos obligatorios. Puedes volver luego desde tu perfil.'**
  String get onboarding_skip_all_confirm_body;

  /// No description provided for @onboarding_skip_all_confirm_yes.
  ///
  /// In es, this message translates to:
  /// **'Saltar'**
  String get onboarding_skip_all_confirm_yes;

  /// No description provided for @onboarding_skip_all_confirm_no.
  ///
  /// In es, this message translates to:
  /// **'Seguir'**
  String get onboarding_skip_all_confirm_no;

  /// No description provided for @onboarding_required.
  ///
  /// In es, this message translates to:
  /// **'Obligatorio'**
  String get onboarding_required;

  /// No description provided for @onboarding_optional.
  ///
  /// In es, this message translates to:
  /// **'Opcional'**
  String get onboarding_optional;

  /// No description provided for @onboarding_done.
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get onboarding_done;

  /// No description provided for @onboarding_error_required.
  ///
  /// In es, this message translates to:
  /// **'Este campo es obligatorio'**
  String get onboarding_error_required;

  /// No description provided for @onboarding_error_offline.
  ///
  /// In es, this message translates to:
  /// **'Parece que estás sin conexión. Intenta de nuevo cuando tengas conexión.'**
  String get onboarding_error_offline;

  /// No description provided for @onboarding_card_profile_photo_label.
  ///
  /// In es, this message translates to:
  /// **'Foto de perfil'**
  String get onboarding_card_profile_photo_label;

  /// No description provided for @onboarding_card_profile_photo_cta.
  ///
  /// In es, this message translates to:
  /// **'Añadir una foto'**
  String get onboarding_card_profile_photo_cta;

  /// No description provided for @onboarding_card_display_name_label.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get onboarding_card_display_name_label;

  /// No description provided for @onboarding_card_display_name_cta.
  ///
  /// In es, this message translates to:
  /// **'Elige tu nombre'**
  String get onboarding_card_display_name_cta;

  /// No description provided for @onboarding_card_age_label.
  ///
  /// In es, this message translates to:
  /// **'Edad'**
  String get onboarding_card_age_label;

  /// No description provided for @onboarding_card_age_cta.
  ///
  /// In es, this message translates to:
  /// **'Confirma tu edad'**
  String get onboarding_card_age_cta;

  /// No description provided for @onboarding_card_gender_position_label.
  ///
  /// In es, this message translates to:
  /// **'Género y posición'**
  String get onboarding_card_gender_position_label;

  /// No description provided for @onboarding_card_gender_position_cta.
  ///
  /// In es, this message translates to:
  /// **'Define tu género y posición'**
  String get onboarding_card_gender_position_cta;

  /// No description provided for @onboarding_card_looking_for_label.
  ///
  /// In es, this message translates to:
  /// **'Busco'**
  String get onboarding_card_looking_for_label;

  /// No description provided for @onboarding_card_looking_for_cta.
  ///
  /// In es, this message translates to:
  /// **'¿Qué buscas?'**
  String get onboarding_card_looking_for_cta;

  /// No description provided for @onboarding_card_tribes_label.
  ///
  /// In es, this message translates to:
  /// **'Tribus'**
  String get onboarding_card_tribes_label;

  /// No description provided for @onboarding_card_tribes_cta.
  ///
  /// In es, this message translates to:
  /// **'Elige tus tribus'**
  String get onboarding_card_tribes_cta;

  /// No description provided for @onboarding_card_vaccines_label.
  ///
  /// In es, this message translates to:
  /// **'Salud y vacunas'**
  String get onboarding_card_vaccines_label;

  /// No description provided for @onboarding_card_vaccines_cta.
  ///
  /// In es, this message translates to:
  /// **'Comparte tu información de salud'**
  String get onboarding_card_vaccines_cta;

  /// No description provided for @onboarding_card_practices_label.
  ///
  /// In es, this message translates to:
  /// **'Prácticas'**
  String get onboarding_card_practices_label;

  /// No description provided for @onboarding_card_practices_cta.
  ///
  /// In es, this message translates to:
  /// **'Añade tus prácticas'**
  String get onboarding_card_practices_cta;

  /// No description provided for @onboarding_card_about_me_label.
  ///
  /// In es, this message translates to:
  /// **'Sobre mí'**
  String get onboarding_card_about_me_label;

  /// No description provided for @onboarding_card_about_me_cta.
  ///
  /// In es, this message translates to:
  /// **'Escribe una bio breve'**
  String get onboarding_card_about_me_cta;

  /// No description provided for @onboarding_card_height_label.
  ///
  /// In es, this message translates to:
  /// **'Altura'**
  String get onboarding_card_height_label;

  /// No description provided for @onboarding_card_height_cta.
  ///
  /// In es, this message translates to:
  /// **'Añade tu altura'**
  String get onboarding_card_height_cta;

  /// No description provided for @onboarding_card_weight_label.
  ///
  /// In es, this message translates to:
  /// **'Peso'**
  String get onboarding_card_weight_label;

  /// No description provided for @onboarding_card_weight_cta.
  ///
  /// In es, this message translates to:
  /// **'Añade tu peso'**
  String get onboarding_card_weight_cta;

  /// No description provided for @onboarding_card_relationship_status_label.
  ///
  /// In es, this message translates to:
  /// **'Estado sentimental'**
  String get onboarding_card_relationship_status_label;

  /// No description provided for @onboarding_card_relationship_status_cta.
  ///
  /// In es, this message translates to:
  /// **'Define tu estado'**
  String get onboarding_card_relationship_status_cta;

  /// No description provided for @onboarding_card_position_preference_label.
  ///
  /// In es, this message translates to:
  /// **'Preferencia de posición'**
  String get onboarding_card_position_preference_label;

  /// No description provided for @onboarding_card_position_preference_cta.
  ///
  /// In es, this message translates to:
  /// **'Define tu posición'**
  String get onboarding_card_position_preference_cta;

  /// No description provided for @onboarding_card_ethnicity_label.
  ///
  /// In es, this message translates to:
  /// **'Etnia'**
  String get onboarding_card_ethnicity_label;

  /// No description provided for @onboarding_card_ethnicity_cta.
  ///
  /// In es, this message translates to:
  /// **'Añade tu etnia'**
  String get onboarding_card_ethnicity_cta;

  /// Mensaje de éxito tras eliminar la cuenta
  ///
  /// In es, this message translates to:
  /// **'Cuenta programada para eliminación'**
  String get deleteAccountSuccess;

  /// Mensaje de error al fallar la eliminación de cuenta
  ///
  /// In es, this message translates to:
  /// **'Error al eliminar la cuenta. Intenta de nuevo.'**
  String get deleteAccountError;

  /// Título de la pantalla Right Now y etiqueta del FAB
  ///
  /// In es, this message translates to:
  /// **'Right Now'**
  String get right_now_title;

  /// Título del bottom sheet para crear una publicación en Right Now
  ///
  /// In es, this message translates to:
  /// **'Publicar en Right Now'**
  String get right_now_post;

  /// Placeholder del campo de texto de Right Now
  ///
  /// In es, this message translates to:
  /// **'¿Qué estás haciendo ahora mismo?'**
  String get right_now_hint;

  /// Etiqueta de duración antes del desplegable en Right Now
  ///
  /// In es, this message translates to:
  /// **'Expira en:'**
  String get right_now_expires_label;

  /// Opción de duración: 30 minutos
  ///
  /// In es, this message translates to:
  /// **'30 min'**
  String get right_now_duration_30min;

  /// Opción de duración: 1 hora
  ///
  /// In es, this message translates to:
  /// **'1 hora'**
  String get right_now_duration_1h;

  /// Opción de duración: 2 horas
  ///
  /// In es, this message translates to:
  /// **'2 horas'**
  String get right_now_duration_2h;

  /// Opción de duración: 4 horas
  ///
  /// In es, this message translates to:
  /// **'4 horas'**
  String get right_now_duration_4h;

  /// Opción de duración: 6 horas
  ///
  /// In es, this message translates to:
  /// **'6 horas'**
  String get right_now_duration_6h;

  /// Botón de publicar en Right Now
  ///
  /// In es, this message translates to:
  /// **'Publicar'**
  String get right_now_publish;

  /// Snackbar de éxito al publicar en Right Now
  ///
  /// In es, this message translates to:
  /// **'Publicado en Right Now'**
  String get right_now_published;

  /// Snackbar de error al publicar en Right Now
  ///
  /// In es, this message translates to:
  /// **'No se pudo publicar'**
  String get right_now_publish_error;

  /// Snackbar de error al eliminar una publicación de Right Now
  ///
  /// In es, this message translates to:
  /// **'No se pudo eliminar'**
  String get right_now_delete_error;

  /// Botón de reintentar en estado de error de Right Now
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get right_now_retry;

  /// Mensaje de error cuando falla la carga del feed de Right Now
  ///
  /// In es, this message translates to:
  /// **'No se pudo cargar el feed'**
  String get right_now_error;

  /// Título de estado vacío de Right Now
  ///
  /// In es, this message translates to:
  /// **'Nadie por aquí ahora mismo'**
  String get right_now_empty_title;

  /// Subtítulo de estado vacío de Right Now
  ///
  /// In es, this message translates to:
  /// **'Sé el primero en publicar'**
  String get right_now_empty_subtitle;

  /// Etiqueta de ubicación no disponible en Right Now
  ///
  /// In es, this message translates to:
  /// **'Sin ubicación'**
  String get right_now_no_location;

  /// Mensaje de permiso de ubicación en Right Now
  ///
  /// In es, this message translates to:
  /// **'Permiso de ubicación requerido'**
  String get right_now_location_permission;

  /// Error de álbum no encontrado en la pantalla de detalle
  ///
  /// In es, this message translates to:
  /// **'Álbum no encontrado'**
  String get album_not_found;

  /// Error al cargar el álbum en la pantalla de detalle
  ///
  /// In es, this message translates to:
  /// **'Error al cargar el álbum: {error}'**
  String album_load_error(String error);

  /// Error al añadir fotos al álbum
  ///
  /// In es, this message translates to:
  /// **'Error al añadir fotos: {error}'**
  String album_add_error(String error);

  /// Botón de reintentar en pantalla de detalle de álbum
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get album_retry;

  /// Título por defecto del álbum cuando falta el nombre
  ///
  /// In es, this message translates to:
  /// **'Álbum'**
  String get album_title_fallback;

  /// Estado vacío cuando el álbum no tiene fotos
  ///
  /// In es, this message translates to:
  /// **'Sin fotos aún'**
  String get album_no_photos;

  /// Tooltip y botón para añadir fotos al álbum
  ///
  /// In es, this message translates to:
  /// **'Añadir fotos'**
  String get album_add_photos;

  /// Botón de cerrar en la vista previa de foto
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get album_close;

  /// Etiqueta de acción eliminar álbum
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get album_delete;

  /// Confirmación de eliminación de álbum
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar este álbum?'**
  String get album_delete_confirm;

  /// Etiqueta de acción compartir álbum
  ///
  /// In es, this message translates to:
  /// **'Compartir'**
  String get album_share;

  /// Etiqueta de enlace para compartir álbum
  ///
  /// In es, this message translates to:
  /// **'Compartir enlace'**
  String get album_share_link;

  /// Título de la barra de la pantalla Tú
  ///
  /// In es, this message translates to:
  /// **'Tú'**
  String get you_title;

  /// Encabezado de sección de configuración en pantalla Tú
  ///
  /// In es, this message translates to:
  /// **'CONFIGURACIÓN'**
  String get you_settings_header;

  /// Fila de configuración: notificaciones
  ///
  /// In es, this message translates to:
  /// **'Notificaciones'**
  String get you_notifications;

  /// Fila de configuración: privacidad
  ///
  /// In es, this message translates to:
  /// **'Privacidad'**
  String get you_privacy;

  /// Fila de configuración: usuarios bloqueados
  ///
  /// In es, this message translates to:
  /// **'Usuarios bloqueados'**
  String get you_blocked_users;

  /// Título del diálogo de confirmación de cierre de sesión
  ///
  /// In es, this message translates to:
  /// **'Cerrar sesión'**
  String get you_logout_title;

  /// Cuerpo del diálogo de confirmación de cierre de sesión
  ///
  /// In es, this message translates to:
  /// **'¿Estás seguro de que quieres cerrar sesión?'**
  String get you_logout_confirm;

  /// Snackbar de boost activado
  ///
  /// In es, this message translates to:
  /// **'¡Boost activado por 30 min!'**
  String get you_boosted_snackbar;

  /// Snackbar de error al activar boost
  ///
  /// In es, this message translates to:
  /// **'Error al activar boost: {error}'**
  String you_boost_failed(String error);

  /// Etiqueta del botón boost mientras se activa
  ///
  /// In es, this message translates to:
  /// **'Activando boost...'**
  String get you_boosting;

  /// Etiqueta de boost activo con minutos restantes
  ///
  /// In es, this message translates to:
  /// **'BOOST · {minutes}m restantes'**
  String you_boost_active(int minutes);

  /// Texto de la insignia de boost en la foto de perfil
  ///
  /// In es, this message translates to:
  /// **'BOOST'**
  String get you_boosted_badge;

  /// Encabezado de sección 'Te han visto' en pantalla Tú
  ///
  /// In es, this message translates to:
  /// **'TE HAN VISTO'**
  String get you_viewed_me;

  /// Mensaje de error de 'Te han visto'
  ///
  /// In es, this message translates to:
  /// **'No se pudieron cargar los visitantes'**
  String get you_viewers_error;

  /// Mensaje de error al cargar el perfil
  ///
  /// In es, this message translates to:
  /// **'Error al cargar el perfil: {error}'**
  String you_profile_load_error(String error);

  /// Tiempo relativo: hace menos de 1 minuto
  ///
  /// In es, this message translates to:
  /// **'Ahora mismo'**
  String get justNow;

  /// Tiempo relativo: hace minutos. Ejemplo: Hace 5m
  ///
  /// In es, this message translates to:
  /// **'Hace {count}m'**
  String minAgo(int count);

  /// Tiempo relativo: el día calendario anterior
  ///
  /// In es, this message translates to:
  /// **'Ayer'**
  String get yesterday;

  /// Tiempo relativo: hace días. Ejemplo: Hace 3d
  ///
  /// In es, this message translates to:
  /// **'Hace {count}d'**
  String daysAgo(int count);

  /// Título de la barra de inicio de sesión
  ///
  /// In es, this message translates to:
  /// **'Iniciar sesión'**
  String get login_title;

  /// Etiqueta del campo de correo electrónico en inicio de sesión
  ///
  /// In es, this message translates to:
  /// **'Correo electrónico'**
  String get login_email_label;

  /// Error de validación: campo de correo vacío en inicio de sesión
  ///
  /// In es, this message translates to:
  /// **'Por favor, introduce tu correo electrónico'**
  String get login_email_empty_error;

  /// Error de validación: formato de correo inválido en inicio de sesión
  ///
  /// In es, this message translates to:
  /// **'Formato de correo electrónico no válido'**
  String get login_email_invalid_error;

  /// Etiqueta del campo de contraseña en inicio de sesión
  ///
  /// In es, this message translates to:
  /// **'Contraseña'**
  String get login_password_label;

  /// Error de validación: campo de contraseña vacío en inicio de sesión
  ///
  /// In es, this message translates to:
  /// **'Por favor, introduce tu contraseña'**
  String get login_password_empty_error;

  /// Botón de inicio de sesión
  ///
  /// In es, this message translates to:
  /// **'Iniciar sesión'**
  String get login_button;

  /// Texto del divisor 'o' entre métodos de inicio de sesión
  ///
  /// In es, this message translates to:
  /// **'o'**
  String get login_or_divider;

  /// Botón de inicio de sesión con Google
  ///
  /// In es, this message translates to:
  /// **'Iniciar sesión con Google'**
  String get login_google_button;

  /// Subtítulo bajo el logo en login
  ///
  /// In es, this message translates to:
  /// **'Conecta con quien tienes cerca'**
  String get login_subtitle;

  /// Enlace a recuperar contraseña
  ///
  /// In es, this message translates to:
  /// **'¿Olvidaste tu contraseña?'**
  String get login_forgot_password;

  /// Prefijo antes del enlace de registro
  ///
  /// In es, this message translates to:
  /// **'¿No tienes cuenta?'**
  String get login_no_account;

  /// Enlace a la pantalla de registro desde inicio de sesión
  ///
  /// In es, this message translates to:
  /// **'Regístrate'**
  String get login_register_link;

  /// Subtítulo bajo el logo en registro
  ///
  /// In es, this message translates to:
  /// **'Crea tu cuenta en un momento'**
  String get register_subtitle;

  /// Prefijo antes del enlace de login
  ///
  /// In es, this message translates to:
  /// **'¿Ya tienes cuenta?'**
  String get register_have_account;

  /// Título pantalla recuperar contraseña
  ///
  /// In es, this message translates to:
  /// **'Recuperar contraseña'**
  String get recover_title;

  /// Subtítulo recuperar contraseña
  ///
  /// In es, this message translates to:
  /// **'Te enviaremos un código a tu correo'**
  String get recover_subtitle;

  /// Botón enviar código de recuperación
  ///
  /// In es, this message translates to:
  /// **'Enviar código'**
  String get recover_send_code;

  /// Campo del código de recuperación
  ///
  /// In es, this message translates to:
  /// **'Código de 6 dígitos'**
  String get recover_code_label;

  /// Campo de nueva contraseña
  ///
  /// In es, this message translates to:
  /// **'Nueva contraseña'**
  String get recover_new_password_label;

  /// Botón para confirmar el cambio de contraseña
  ///
  /// In es, this message translates to:
  /// **'Cambiar contraseña'**
  String get recover_reset_button;

  /// Confirmación de envío de código
  ///
  /// In es, this message translates to:
  /// **'Si el correo existe, te enviamos un código.'**
  String get recover_code_sent;

  /// Éxito al cambiar contraseña
  ///
  /// In es, this message translates to:
  /// **'Contraseña cambiada. Inicia sesión.'**
  String get recover_success;

  /// Error genérico de recuperación
  ///
  /// In es, this message translates to:
  /// **'No se pudo completar. Revisa el código e inténtalo de nuevo.'**
  String get recover_error;

  /// Validación: código vacío
  ///
  /// In es, this message translates to:
  /// **'Introduce el código'**
  String get recover_code_empty;

  /// Mensaje de error genérico de Google Sign-In
  ///
  /// In es, this message translates to:
  /// **'Error al iniciar sesión con Google. Inténtalo de nuevo.'**
  String get login_error_google;

  /// Mensaje de error genérico de inicio de sesión
  ///
  /// In es, this message translates to:
  /// **'Error al iniciar sesión. Inténtalo de nuevo.'**
  String get login_error_network;

  /// Título de la barra de registro
  ///
  /// In es, this message translates to:
  /// **'Registrarse'**
  String get register_title;

  /// Etiqueta del campo de correo electrónico en registro
  ///
  /// In es, this message translates to:
  /// **'Correo electrónico'**
  String get register_email_label;

  /// Error de validación: campo de correo vacío en registro
  ///
  /// In es, this message translates to:
  /// **'Por favor, introduce tu correo electrónico'**
  String get register_email_empty_error;

  /// Error de validación: formato de correo inválido en registro
  ///
  /// In es, this message translates to:
  /// **'Formato de correo electrónico no válido'**
  String get register_email_invalid_error;

  /// Etiqueta del campo de contraseña en registro
  ///
  /// In es, this message translates to:
  /// **'Contraseña (mín. 8 caracteres)'**
  String get register_password_label;

  /// Error de validación: campo de contraseña vacío en registro
  ///
  /// In es, this message translates to:
  /// **'Por favor, introduce una contraseña'**
  String get register_password_empty_error;

  /// Error de validación: longitud mínima de contraseña
  ///
  /// In es, this message translates to:
  /// **'La contraseña debe tener al menos 8 caracteres'**
  String get register_password_min_length_error;

  /// Etiqueta del campo de fecha de nacimiento en registro
  ///
  /// In es, this message translates to:
  /// **'Fecha de nacimiento'**
  String get register_dob_label;

  /// Texto de ayuda del campo de fecha de nacimiento
  ///
  /// In es, this message translates to:
  /// **'Toca para seleccionar'**
  String get register_dob_hint;

  /// Texto de ayuda del selector de fecha
  ///
  /// In es, this message translates to:
  /// **'Selecciona tu fecha de nacimiento'**
  String get register_dob_picker_help;

  /// Etiqueta del campo del selector de fecha
  ///
  /// In es, this message translates to:
  /// **'Fecha de nacimiento'**
  String get register_dob_picker_field_label;

  /// Error de validación: fecha de nacimiento vacía
  ///
  /// In es, this message translates to:
  /// **'Por favor, selecciona tu fecha de nacimiento'**
  String get register_dob_empty_error;

  /// Error de validación: restricción de edad mínima
  ///
  /// In es, this message translates to:
  /// **'Debes tener al menos 18 años'**
  String get register_age_gate;

  /// Etiqueta del checkbox de consentimiento en registro
  ///
  /// In es, this message translates to:
  /// **'Acepto los términos y la política de privacidad (soy mayor de 18 años)'**
  String get register_consent_label;

  /// Error de validación: consentimiento no aceptado
  ///
  /// In es, this message translates to:
  /// **'Debes aceptar los términos y la política de privacidad'**
  String get register_consent_error;

  /// Botón de registro
  ///
  /// In es, this message translates to:
  /// **'Registrarse'**
  String get register_button;

  /// Mensaje de error: correo electrónico ya registrado
  ///
  /// In es, this message translates to:
  /// **'El correo electrónico ya está registrado'**
  String get register_error_email_taken;

  /// Mensaje de error genérico de registro
  ///
  /// In es, this message translates to:
  /// **'Error al registrarse. Inténtalo de nuevo.'**
  String get register_error_network;

  /// Enlace a la pantalla de inicio de sesión desde registro
  ///
  /// In es, this message translates to:
  /// **'Inicia sesión'**
  String get register_login_link;

  /// Título de la barra de perfil propio
  ///
  /// In es, this message translates to:
  /// **'Mi perfil'**
  String get profile_title_self;

  /// Título de la barra de perfil de otro usuario
  ///
  /// In es, this message translates to:
  /// **'Perfil'**
  String get profile_title_other;

  /// Mensaje de error al cargar el perfil
  ///
  /// In es, this message translates to:
  /// **'Error al cargar el perfil: {error}'**
  String profile_load_error(String error);

  /// Botón de reintentar en estado de error del perfil
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get profile_retry;

  /// Estado vacío cuando no hay datos de perfil
  ///
  /// In es, this message translates to:
  /// **'Sin datos de perfil'**
  String get profile_no_data;

  /// Etiqueta de altura en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Altura'**
  String get profile_height_label;

  /// Etiqueta de peso en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Peso'**
  String get profile_weight_label;

  /// Etiqueta de tipo de cuerpo en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Tipo de cuerpo'**
  String get profile_body_type_label;

  /// Etiqueta de estado civil en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Estado civil'**
  String get profile_relationship_label;

  /// Etiqueta de posición en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Posición'**
  String get profile_position_label;

  /// Etiqueta de etnia en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Etnia'**
  String get profile_ethnicity_label;

  /// Etiqueta de pronombres en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Pronombres'**
  String get profile_pronouns_label;

  /// Etiqueta de fecha de nacimiento en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Fecha de nacimiento'**
  String get profile_birthdate_label;

  /// Encabezado de sección tribus en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Tribus'**
  String get profile_tribes_header;

  /// Encabezado de sección intereses en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Intereses'**
  String get profile_tags_header;

  /// Encabezado de sección 'busco' en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Busco'**
  String get profile_looking_for_label;

  /// Encabezado de sección 'quedar en' en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Quedar en'**
  String get profile_meet_at_header;

  /// Botón de editar perfil en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Editar perfil'**
  String get profile_edit_button;

  /// Formato de valor de altura con unidad en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'{value} cm'**
  String profile_height_value(String value);

  /// Formato de valor de peso con unidad en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'{value} kg'**
  String profile_weight_value(String value);

  /// Etiqueta de estado de carga en la pantalla de perfil
  ///
  /// In es, this message translates to:
  /// **'Cargando...'**
  String get profile_loading;

  /// Edit profile screen AppBar title
  ///
  /// In es, this message translates to:
  /// **'Editar perfil'**
  String get editProfileTitle;

  /// Edit profile field label: Display Name
  ///
  /// In es, this message translates to:
  /// **'Nombre para mostrar'**
  String get editProfileFieldDisplayName;

  /// Edit profile text field hint: Your display name
  ///
  /// In es, this message translates to:
  /// **'Tu nombre para mostrar'**
  String get editProfilePlaceholderDisplayName;

  /// Edit profile field label: Bio
  ///
  /// In es, this message translates to:
  /// **'Biografía'**
  String get editProfileFieldBio;

  /// Edit profile text field hint: Tell people about yourself
  ///
  /// In es, this message translates to:
  /// **'Cuéntale a la gente sobre ti'**
  String get editProfilePlaceholderBio;

  /// Edit profile health section label: HIV Status
  ///
  /// In es, this message translates to:
  /// **'Estado de VIH'**
  String get editProfileFieldHivStatus;

  /// Edit profile HIV Status dropdown hint
  ///
  /// In es, this message translates to:
  /// **'Seleccionar estado'**
  String get editProfilePlaceholderSelectStatus;

  /// Edit profile health section label: Last Tested On
  ///
  /// In es, this message translates to:
  /// **'Última prueba'**
  String get editProfileFieldLastTestedOn;

  /// Edit profile date picker default text when no date is set
  ///
  /// In es, this message translates to:
  /// **'No establecido'**
  String get editProfileNotSet;

  /// Edit profile health section label: On PrEP
  ///
  /// In es, this message translates to:
  /// **'En PrEP'**
  String get editProfileFieldOnPrep;

  /// Edit profile photo upload progress text
  ///
  /// In es, this message translates to:
  /// **'Subiendo...'**
  String get editProfileUploading;

  /// Edit profile button text to change profile photo
  ///
  /// In es, this message translates to:
  /// **'Cambiar foto'**
  String get editProfileChangePhoto;

  /// Edit profile privacy toggle label: Show age on profile
  ///
  /// In es, this message translates to:
  /// **'Mostrar edad'**
  String get editProfileShowAge;

  /// Edit profile privacy toggle label: Show role on profile
  ///
  /// In es, this message translates to:
  /// **'Mostrar rol'**
  String get editProfileShowRole;

  /// Edit profile privacy toggle label: Show tribes on profile
  ///
  /// In es, this message translates to:
  /// **'Mostrar tribus'**
  String get editProfileShowTribes;

  /// Edit profile privacy toggle label: Show position on profile
  ///
  /// In es, this message translates to:
  /// **'Mostrar posición'**
  String get editProfileShowPosition;

  /// Edit profile privacy toggle label: Show ethnicity on profile
  ///
  /// In es, this message translates to:
  /// **'Mostrar etnia'**
  String get editProfileShowEthnicity;

  /// Edit profile privacy toggle label: Show relationship status on profile
  ///
  /// In es, this message translates to:
  /// **'Mostrar estado civil'**
  String get editProfileShowRelationshipStatus;

  /// Edit profile privacy toggle value: On
  ///
  /// In es, this message translates to:
  /// **'Sí'**
  String get editProfileOn;

  /// Edit profile privacy toggle value: Off
  ///
  /// In es, this message translates to:
  /// **'No'**
  String get editProfileOff;

  /// Security screen tip card title: Block and Report
  ///
  /// In es, this message translates to:
  /// **'Bloquear y reportar'**
  String get securityBlockReportTitle;

  /// Security screen tip card body for Block and Report
  ///
  /// In es, this message translates to:
  /// **'Toca el menú ⋮ en cualquier perfil para bloquear o reportar a un usuario. Los usuarios bloqueados no pueden ver tu perfil ni contactarte.'**
  String get securityBlockReportBody;

  /// Security screen tip card title: Incognito Mode
  ///
  /// In es, this message translates to:
  /// **'Modo incógnito'**
  String get securityIncognitoTitle;

  /// Security screen tip card body for Incognito Mode
  ///
  /// In es, this message translates to:
  /// **'Navega perfiles sin aparecer en su lista de Te han visto. Disponible con planes Vibra+ y Unlimited.'**
  String get securityIncognitoBody;

  /// Security screen tip card title: PIN Lock
  ///
  /// In es, this message translates to:
  /// **'Bloqueo PIN'**
  String get securityPinLockTitle;

  /// Security screen tip card body for PIN Lock
  ///
  /// In es, this message translates to:
  /// **'Establece un PIN de 4 dígitos para bloquear la app al abrirse. Configúralo en Ajustes → PIN.'**
  String get securityPinLockBody;

  /// Security screen tip card title: Discreet App Icon
  ///
  /// In es, this message translates to:
  /// **'Icono de aplicación discreto'**
  String get securityDiscreetIconTitle;

  /// Security screen tip card body for Discreet App Icon
  ///
  /// In es, this message translates to:
  /// **'Cambia el icono de la app a uno genérico para que Vibra no sea reconocible en tu pantalla de inicio. Configúralo en Ajustes → Icono discreto.'**
  String get securityDiscreetIconBody;

  /// Security screen tip card title: Screenshot Alerts
  ///
  /// In es, this message translates to:
  /// **'Alertas de captura de pantalla'**
  String get securityScreenshotAlertsTitle;

  /// Security screen tip card body for Screenshot Alerts
  ///
  /// In es, this message translates to:
  /// **'Recibirás una notificación cuando alguien tome una captura de pantalla de tu perfil o chat. Activado por defecto.'**
  String get securityScreenshotAlertsBody;

  /// Security screen tip card title: NSFW Blur
  ///
  /// In es, this message translates to:
  /// **'Desenfoque NSFW'**
  String get securityNsfwBlurTitle;

  /// Security screen tip card body for NSFW Blur
  ///
  /// In es, this message translates to:
  /// **'Las fotos de perfil marcadas como explícitas se difuminan automáticamente. Esto usa IA en el dispositivo — ninguna imagen sale de tu teléfono.'**
  String get securityNsfwBlurBody;

  /// Pin screen validation error when PIN is not exactly 4 digits
  ///
  /// In es, this message translates to:
  /// **'Ingresa exactamente 4 dígitos'**
  String get pinEnterExactly4Digits;

  /// Pin screen success snackbar after activating PIN
  ///
  /// In es, this message translates to:
  /// **'PIN activado'**
  String get pinActivated;

  /// Pin screen remove PIN confirmation dialog title
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar PIN?'**
  String get pinRemoveTitle;

  /// Pin screen remove PIN confirmation dialog body
  ///
  /// In es, this message translates to:
  /// **'La app ya no estará bloqueada.'**
  String get pinRemoveBody;

  /// Pin screen remove PIN confirmation button
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get pinRemoveConfirm;

  /// Pin screen success snackbar after removing PIN
  ///
  /// In es, this message translates to:
  /// **'PIN eliminado'**
  String get pinRemoved;

  /// Pin screen section title when PIN is already set
  ///
  /// In es, this message translates to:
  /// **'Cambiar tu PIN'**
  String get pinChangeYourPin;

  /// Pin screen section title when no PIN is set
  ///
  /// In es, this message translates to:
  /// **'Establecer un PIN'**
  String get pinSetAPin;

  /// Pin screen description when changing an existing PIN
  ///
  /// In es, this message translates to:
  /// **'Ingresa un nuevo PIN de 4 dígitos o elimina el actual.'**
  String get pinEnterNewPinDesc;

  /// Pin screen description when setting a new PIN
  ///
  /// In es, this message translates to:
  /// **'Ingresa un PIN de 4 dígitos para bloquear la app al abrirse.'**
  String get pinEnterPinDesc;

  /// Pin screen button text to update an existing PIN
  ///
  /// In es, this message translates to:
  /// **'Actualizar PIN'**
  String get pinUpdatePin;

  /// Pin screen button text to activate a new PIN
  ///
  /// In es, this message translates to:
  /// **'Activar PIN'**
  String get pinActivatePin;

  /// Pin screen button text to remove PIN
  ///
  /// In es, this message translates to:
  /// **'Eliminar PIN'**
  String get pinRemovePin;

  /// Chat screen error state title when messages fail to load
  ///
  /// In es, this message translates to:
  /// **'Error al cargar mensajes'**
  String get chatFailedToLoad;

  /// Chat screen empty state title
  ///
  /// In es, this message translates to:
  /// **'Sin mensajes aún'**
  String get chatNoMessagesYet;

  /// Chat screen empty state subtitle
  ///
  /// In es, this message translates to:
  /// **'¡Saluda para empezar la conversación!'**
  String get chatSayHi;

  /// Chat screen input field placeholder
  ///
  /// In es, this message translates to:
  /// **'Escribe un mensaje...'**
  String get chatTypeMessage;

  /// Chat screen photo send sheet toggle label
  ///
  /// In es, this message translates to:
  /// **'Ver una vez'**
  String get chatViewOnce;

  /// Chat screen send button label
  ///
  /// In es, this message translates to:
  /// **'Enviar'**
  String get chatSend;

  /// Chat screen ephemeral photo bubble prompt
  ///
  /// In es, this message translates to:
  /// **'Toca para ver una vez'**
  String get chatTapToViewOnce;

  /// Chat screen sender confirmation for view-once photo
  ///
  /// In es, this message translates to:
  /// **'Foto de un solo uso enviada'**
  String get chatViewOnceSent;

  /// Chat screen label for expired view-once photo
  ///
  /// In es, this message translates to:
  /// **'Foto expirada'**
  String get chatPhotoExpired;

  /// Chat screen error snackbar when unsend fails
  ///
  /// In es, this message translates to:
  /// **'Error al anular el mensaje'**
  String get chatFailedToUnsend;

  /// Chat screen tooltip for voice call button
  ///
  /// In es, this message translates to:
  /// **'Llamada de voz'**
  String get chatVoiceCall;

  /// Chat screen NSFW warning when photo is rejected
  ///
  /// In es, this message translates to:
  /// **'Esta imagen parece violar nuestras pautas de contenido.'**
  String get chatNsfwContent;

  /// Roam bottom sheet title
  ///
  /// In es, this message translates to:
  /// **'Vagar'**
  String get roamTitle;

  /// Roam bottom sheet subtitle
  ///
  /// In es, this message translates to:
  /// **'Elige un lugar guardado o usa tu ubicación real.'**
  String get roamSubtitle;

  /// Roam bottom sheet button to use real GPS location
  ///
  /// In es, this message translates to:
  /// **'Usar ubicación real'**
  String get roamUseRealLocation;

  /// Roam bottom sheet empty state when no places saved
  ///
  /// In es, this message translates to:
  /// **'Sin lugares guardados aún.'**
  String get roamNoSavedPlaces;

  /// Roam bottom sheet button to add a new place
  ///
  /// In es, this message translates to:
  /// **'Agregar nuevo lugar'**
  String get roamAddNewPlace;

  /// Roam add-place form label for name field
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get roamNameLabel;

  /// Roam add-place form validation error for empty name
  ///
  /// In es, this message translates to:
  /// **'El nombre es obligatorio'**
  String get roamNameRequired;

  /// Roam add-place form label for latitude field
  ///
  /// In es, this message translates to:
  /// **'Latitud'**
  String get roamLatitudeLabel;

  /// Roam add-place form label for longitude field
  ///
  /// In es, this message translates to:
  /// **'Longitud'**
  String get roamLongitudeLabel;

  /// Roam add-place form validation error for non-numeric input
  ///
  /// In es, this message translates to:
  /// **'Debe ser un número'**
  String get roamMustBeNumber;

  /// Roam add-place form validation error for out-of-range latitude
  ///
  /// In es, this message translates to:
  /// **'Rango: -90..90'**
  String get roamLatRange;

  /// Roam add-place form validation error for out-of-range longitude
  ///
  /// In es, this message translates to:
  /// **'Rango: -180..180'**
  String get roamLonRange;

  /// Roam bottom sheet submit button for new place
  ///
  /// In es, this message translates to:
  /// **'Agregar y Vagar'**
  String get roamAddAndRoam;

  /// Roam bottom sheet error snackbar when adding a place fails
  ///
  /// In es, this message translates to:
  /// **'Error al agregar lugar: {error}'**
  String roamFailedToAddPlace(String error);

  /// Grid search screen snackbar when roaming to a new place
  ///
  /// In es, this message translates to:
  /// **'Viajando a {name}'**
  String roamRoamingTo(String name);

  /// Grid search screen error snackbar when roam fails
  ///
  /// In es, this message translates to:
  /// **'Error al establecer ubicación: {error}'**
  String roamFailedToSet(String error);

  /// Grid search screen snackbar when GPS location is unavailable
  ///
  /// In es, this message translates to:
  /// **'Ubicación no disponible — activa el permiso GPS en ajustes'**
  String get roamLocationUnavailable;

  /// Grid search screen snackbar when real GPS location is set
  ///
  /// In es, this message translates to:
  /// **'Usando tu ubicación real'**
  String get roamUsingRealLocation;

  /// Grid search screen generic error snackbar for roam failures
  ///
  /// In es, this message translates to:
  /// **'Error: {error}'**
  String roamFailedGeneric(String error);

  /// Grid search screen roam button tooltip
  ///
  /// In es, this message translates to:
  /// **'Vagar'**
  String get roamTooltip;

  /// Albums screen create album dialog title
  ///
  /// In es, this message translates to:
  /// **'Crear álbum'**
  String get albumCreateTitle;

  /// Albums screen create dialog album name field label
  ///
  /// In es, this message translates to:
  /// **'Nombre del álbum'**
  String get albumNameLabel;

  /// Albums screen create dialog description field label
  ///
  /// In es, this message translates to:
  /// **'Descripción (opcional)'**
  String get albumDescriptionOptional;

  /// Albums screen create dialog private album checkbox label
  ///
  /// In es, this message translates to:
  /// **'Álbum privado'**
  String get albumPrivateLabel;

  /// Albums screen create dialog submit button
  ///
  /// In es, this message translates to:
  /// **'Crear'**
  String get albumCreateButton;

  /// Albums screen error snackbar when album creation fails
  ///
  /// In es, this message translates to:
  /// **'Error al crear álbum: {error}'**
  String albumFailedToCreate(String error);

  /// Albums screen generic error snackbar for album creation
  ///
  /// In es, this message translates to:
  /// **'Error al crear álbum'**
  String get albumFailedToCreateSimple;

  /// Albums tile fallback when album name is null
  ///
  /// In es, this message translates to:
  /// **'Sin título'**
  String get albumSinTitulo;

  /// Create story screen share/submit button label
  ///
  /// In es, this message translates to:
  /// **'Compartir'**
  String get storyShare;

  /// Create story screen generic error snackbar
  ///
  /// In es, this message translates to:
  /// **'Error: {error}'**
  String storyError(String error);

  /// Create story screen upload error snackbar
  ///
  /// In es, this message translates to:
  /// **'Error de subida: {error}'**
  String storyUploadError(String error);

  /// Circles screen fallback name when group has no name
  ///
  /// In es, this message translates to:
  /// **'Grupo'**
  String get circleGroupFallback;

  /// Circles screen member count label under group name
  ///
  /// In es, this message translates to:
  /// **'{count} miembros'**
  String circleMembers(int count);

  /// Call screen button label to unmute microphone
  ///
  /// In es, this message translates to:
  /// **'Activar micrófono'**
  String get callUnmute;

  /// Call screen button label to mute microphone
  ///
  /// In es, this message translates to:
  /// **'Silenciar'**
  String get callMute;

  /// Call screen button label to enable speakerphone
  ///
  /// In es, this message translates to:
  /// **'Altavoz'**
  String get callSpeaker;

  /// Call screen button label to switch to earpiece
  ///
  /// In es, this message translates to:
  /// **'Auricular'**
  String get callEarpiece;

  /// Call screen button label to end/hang up the call
  ///
  /// In es, this message translates to:
  /// **'Colgar'**
  String get callHangup;

  /// Shop card POPULAR badge label
  ///
  /// In es, this message translates to:
  /// **'POPULAR'**
  String get badgePopular;

  /// Grid search screen empty state title when no users found
  ///
  /// In es, this message translates to:
  /// **'No se encontraron usuarios en esta área'**
  String get gridNoUsersTitle;

  /// Grid search screen empty state subtitle suggesting roam
  ///
  /// In es, this message translates to:
  /// **'¡Prueba a viajar a otra ubicación!'**
  String get gridNoUsersSubtitle;

  /// Grid search screen error state message
  ///
  /// In es, this message translates to:
  /// **'Error al cargar usuarios'**
  String get gridFailedToLoad;

  /// Discover section header in Navegar screen
  ///
  /// In es, this message translates to:
  /// **'Descubrir'**
  String get discover;

  /// Travel Pass button/section label
  ///
  /// In es, this message translates to:
  /// **'Travel Pass'**
  String get travelPass;

  /// Button to set travel location to a specific city
  ///
  /// In es, this message translates to:
  /// **'Viajar a {city}'**
  String travelPassSet(String city);

  /// Banner label showing the travel pass active city
  ///
  /// In es, this message translates to:
  /// **'Estas explorando {city}'**
  String travelPassBanner(String city);

  /// Travel pass banner showing remaining hours
  ///
  /// In es, this message translates to:
  /// **'Expira en {hours}h'**
  String travelPassExpires(String hours);

  /// Button to cancel travel pass and return to real GPS location
  ///
  /// In es, this message translates to:
  /// **'Volver a mi ubicacion'**
  String get travelPassBackToMyLocation;

  /// Error snackbar when setting travel pass fails
  ///
  /// In es, this message translates to:
  /// **'Error al activar Travel Pass: {error}'**
  String travelPassFailedToSet(String error);

  /// Error snackbar when cancelling travel pass fails
  ///
  /// In es, this message translates to:
  /// **'Error al cancelar Travel Pass'**
  String get travelPassFailedToCancel;

  /// Success snackbar when travel pass is cancelled
  ///
  /// In es, this message translates to:
  /// **'Travel Pass cancelado — de vuelta a tu ubicacion'**
  String get travelPassCancelled;

  /// Success snackbar when travel pass is activated
  ///
  /// In es, this message translates to:
  /// **'Travel Pass activado — explorando {city}'**
  String travelPassSetSuccess(String city);

  /// Insignia del nivel gratuito
  ///
  /// In es, this message translates to:
  /// **'Gratis'**
  String get premiumTierFree;

  /// Insignia del nivel Xtra
  ///
  /// In es, this message translates to:
  /// **'Pulse'**
  String get premiumTierXtra;

  /// Insignia del nivel Unlimited
  ///
  /// In es, this message translates to:
  /// **'Aura'**
  String get premiumTierUnlimited;

  /// Mensaje para actualizar en funciones bloqueadas
  ///
  /// In es, this message translates to:
  /// **'Actualiza para usar {feature}'**
  String premiumUpgradePrompt(String feature);

  /// Título de la hoja comparativa de planes
  ///
  /// In es, this message translates to:
  /// **'Comparar Planes'**
  String get premiumComparisonTitle;

  /// Función del nivel gratuito: cuadrícula limitada
  ///
  /// In es, this message translates to:
  /// **'Cuadrícula básica (50 perfiles)'**
  String get premiumFeatureBasicGrid;

  /// Función del nivel gratuito: solo filtros básicos
  ///
  /// In es, this message translates to:
  /// **'Filtros básicos'**
  String get premiumFeatureBasicFilters;

  /// Función del nivel gratuito: límite de una tribu
  ///
  /// In es, this message translates to:
  /// **'1 tribu'**
  String get premiumFeatureOneTribe;

  /// Función del nivel Xtra+: cuadrícula ilimitada
  ///
  /// In es, this message translates to:
  /// **'Perfiles ilimitados'**
  String get premiumFeatureUnlimitedGrid;

  /// Función del nivel Xtra: filtros avanzados
  ///
  /// In es, this message translates to:
  /// **'Filtros avanzados'**
  String get premiumFeatureAdvancedFilters;

  /// Función del nivel Xtra: hasta 3 tribus
  ///
  /// In es, this message translates to:
  /// **'Hasta 3 tribus'**
  String get premiumFeatureTribes3;

  /// Función del nivel Unlimited: tribus ilimitadas
  ///
  /// In es, this message translates to:
  /// **'Tribus ilimitadas'**
  String get premiumFeatureUnlimitedTribes;

  /// Función del nivel Xtra+: sin anuncios
  ///
  /// In es, this message translates to:
  /// **'Sin anuncios'**
  String get premiumFeatureNoAds;

  /// Función del nivel Xtra: Travel Pass
  ///
  /// In es, this message translates to:
  /// **'Travel Pass'**
  String get premiumFeatureTravelPass;

  /// Función del nivel Xtra: confirmaciones de lectura
  ///
  /// In es, this message translates to:
  /// **'Confirmaciones de lectura'**
  String get premiumFeatureReadReceipts;

  /// Función del nivel Unlimited: navegación incógnita
  ///
  /// In es, this message translates to:
  /// **'Modo incógnito'**
  String get premiumFeatureIncognito;

  /// Función del nivel Unlimited: soporte prioritario
  ///
  /// In es, this message translates to:
  /// **'Soporte prioritario'**
  String get premiumFeaturePrioritySupport;

  /// Etiqueta de función de chat para confirmaciones de lectura
  ///
  /// In es, this message translates to:
  /// **'Confirmaciones de lectura'**
  String get chatReadReceipts;

  /// Título de la AppBar de la pantalla Eventos
  ///
  /// In es, this message translates to:
  /// **'Eventos'**
  String get events_title;

  /// Título de la AppBar de la pantalla de detalle de evento
  ///
  /// In es, this message translates to:
  /// **'Evento'**
  String get events_detail_title;

  /// Botón crear de la pantalla Eventos
  ///
  /// In es, this message translates to:
  /// **'Crear'**
  String get events_create;

  /// Mensaje de estado de error de la pantalla Eventos
  ///
  /// In es, this message translates to:
  /// **'No se pudieron cargar los eventos'**
  String get events_load_error;

  /// Título de estado vacío de la pantalla Eventos
  ///
  /// In es, this message translates to:
  /// **'No hay eventos cerca'**
  String get events_empty_title;

  /// Subtítulo de estado vacío de la pantalla Eventos
  ///
  /// In es, this message translates to:
  /// **'Sé el primero en crear uno!'**
  String get events_empty_subtitle;

  /// Etiqueta de conteo de asistentes al evento
  ///
  /// In es, this message translates to:
  /// **'{count} asistiendo'**
  String events_attendee_count(int count);

  /// Estado RSVP de asistencia al evento
  ///
  /// In es, this message translates to:
  /// **'Asistiré'**
  String get events_going;

  /// Estado RSVP de tal vez al evento
  ///
  /// In es, this message translates to:
  /// **'Tal vez'**
  String get events_maybe;

  /// Botón de reintentar de eventos
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get events_retry;

  /// Snackbar de éxito después de crear evento
  ///
  /// In es, this message translates to:
  /// **'Evento creado!'**
  String get events_created;

  /// Snackbar de error cuando falla la creación del evento
  ///
  /// In es, this message translates to:
  /// **'No se pudo crear el evento'**
  String get events_create_error;

  /// Etiqueta del campo de título del formulario de evento
  ///
  /// In es, this message translates to:
  /// **'Título del evento'**
  String get events_form_title;

  /// Sugerencia del campo de título del formulario de evento
  ///
  /// In es, this message translates to:
  /// **'Dale un nombre a tu evento'**
  String get events_form_title_hint;

  /// Etiqueta del campo de descripción del formulario de evento
  ///
  /// In es, this message translates to:
  /// **'Descripción'**
  String get events_form_description;

  /// Etiqueta del campo de ubicación del formulario de evento
  ///
  /// In es, this message translates to:
  /// **'Ubicación'**
  String get events_form_location;

  /// Sugerencia del campo de ubicación del formulario de evento
  ///
  /// In es, this message translates to:
  /// **'Dónde ocurrirá?'**
  String get events_form_location_hint;

  /// Etiqueta del campo de fecha del formulario de evento
  ///
  /// In es, this message translates to:
  /// **'Fecha'**
  String get events_form_date;

  /// Etiqueta del campo de hora del formulario de evento
  ///
  /// In es, this message translates to:
  /// **'Hora'**
  String get events_form_time;

  /// Botón de enviar del formulario de evento
  ///
  /// In es, this message translates to:
  /// **'Crear Evento'**
  String get events_form_create;

  /// Etiqueta de hora de fin en detalle de evento
  ///
  /// In es, this message translates to:
  /// **'Termina'**
  String get events_ends;

  /// Encabezado de sección de asistentes en detalle de evento
  ///
  /// In es, this message translates to:
  /// **'Asistentes'**
  String get events_attendees;

  /// Insignia RSVP del usuario actual: asistirá
  ///
  /// In es, this message translates to:
  /// **'Asistirás'**
  String get events_you_are_going;

  /// Insignia RSVP del usuario actual: tal vez
  ///
  /// In es, this message translates to:
  /// **'Tal vez asistas'**
  String get events_you_are_maybe;

  /// Botón de cancelar RSVP en detalle de evento
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get events_cancel;

  /// Botón RSVP en detalle de evento: asistiré
  ///
  /// In es, this message translates to:
  /// **'Asistiré'**
  String get events_rsvp_going;

  /// Botón RSVP en detalle de evento: tal vez
  ///
  /// In es, this message translates to:
  /// **'Tal vez'**
  String get events_rsvp_maybe;

  /// Snackbar de error RSVP en detalle de evento
  ///
  /// In es, this message translates to:
  /// **'Error al confirmar asistencia'**
  String get events_rsvp_error;

  /// Título del diálogo de confirmación de cancelación RSVP
  ///
  /// In es, this message translates to:
  /// **'Cancelar RSVP?'**
  String get events_cancel_confirm_title;

  /// Cuerpo del diálogo de confirmación de cancelación RSVP
  ///
  /// In es, this message translates to:
  /// **'Ya no aparecerás como asistente.'**
  String get events_cancel_confirm_body;

  /// Botón negativo del diálogo de cancelación RSVP
  ///
  /// In es, this message translates to:
  /// **'Mantener RSVP'**
  String get events_cancel_no;

  /// Botón positivo del diálogo de cancelación RSVP
  ///
  /// In es, this message translates to:
  /// **'Cancelar RSVP'**
  String get events_cancel_yes;

  /// Snackbar de RSVP cancelado
  ///
  /// In es, this message translates to:
  /// **'RSVP cancelado'**
  String get events_cancelled;

  /// Snackbar de error al eliminar evento
  ///
  /// In es, this message translates to:
  /// **'No se pudo eliminar el evento'**
  String get events_delete_error;

  /// Título de la AppBar de la pantalla Tienda
  ///
  /// In es, this message translates to:
  /// **'Tienda'**
  String get shopTitle;

  /// Mensaje de estado de error de la pantalla Tienda
  ///
  /// In es, this message translates to:
  /// **'No se pudo cargar la tienda'**
  String get shopLoadError;

  /// Mensaje de estado vacío de la pantalla Tienda
  ///
  /// In es, this message translates to:
  /// **'No hay productos disponibles'**
  String get shopEmpty;

  /// Cuerpo del diálogo de confirmación de compra
  ///
  /// In es, this message translates to:
  /// **'Comprar {name} por {price}?'**
  String shopConfirmPurchase(String name, String price);

  /// Snackbar de éxito después de la compra
  ///
  /// In es, this message translates to:
  /// **'{name} comprado!'**
  String shopPurchaseSuccess(String name);

  /// Snackbar de error cuando falla la compra
  ///
  /// In es, this message translates to:
  /// **'Compra fallida'**
  String get shopPurchaseError;

  /// Elemento del menú Tienda en el cajón de perfil
  ///
  /// In es, this message translates to:
  /// **'Tienda'**
  String get shopMenuItem;

  /// Gallery editor: add photo tile label
  ///
  /// In es, this message translates to:
  /// **'Añadir foto'**
  String get galleryAddPhoto;

  /// Gallery editor: set photo as primary action
  ///
  /// In es, this message translates to:
  /// **'Hacer principal'**
  String get gallerySetPrimary;

  /// Gallery editor: delete photo action
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get galleryDelete;

  /// Gallery editor: delete photo confirmation dialog body
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar esta foto de tu galería?'**
  String get galleryDeleteConfirm;

  /// Gallery editor: shown when photo limit (6) is reached
  ///
  /// In es, this message translates to:
  /// **'Límite de 6 fotos alcanzado'**
  String get galleryMaxReached;

  /// Gallery editor: badge on the primary photo tile
  ///
  /// In es, this message translates to:
  /// **'Principal'**
  String get galleryPrimaryBadge;

  /// Verification screen title and drawer menu item
  ///
  /// In es, this message translates to:
  /// **'Verificar perfil'**
  String get verifyProfileTitle;

  /// Verification screen explanation text shown before the user submits
  ///
  /// In es, this message translates to:
  /// **'Verifica tu identidad tomándote una selfie. Nuestro equipo la revisará y añadirá un sello azul a tu perfil en 24-48 horas.'**
  String get verifyProfileIntro;

  /// Primary CTA button on the verification screen
  ///
  /// In es, this message translates to:
  /// **'Tomar selfie de verificación'**
  String get verifyTakeSelfie;

  /// Message shown when verification has been submitted but is still pending review
  ///
  /// In es, this message translates to:
  /// **'Tu verificación está en revisión. Te avisaremos cuando esté lista.'**
  String get verifyPending;

  /// Message shown when the user's profile has been verified (blue-check granted)
  ///
  /// In es, this message translates to:
  /// **'¡Perfil verificado!'**
  String get verifyVerified;

  /// Snackbar error message when the verification upload or submit fails
  ///
  /// In es, this message translates to:
  /// **'Error al enviar la verificación. Inténtalo de nuevo.'**
  String get verifySubmitError;

  /// Drawer menu item label for the profile verification screen
  ///
  /// In es, this message translates to:
  /// **'Verificar perfil'**
  String get verifyProfileMenuItem;

  /// Banner shown in chat when another member took a screenshot
  ///
  /// In es, this message translates to:
  /// **'Alguien hizo una captura de este chat'**
  String get screenshotAlertBanner;

  /// Navegar screen error state when nearby user load fails
  ///
  /// In es, this message translates to:
  /// **'Error al cargar usuarios cercanos'**
  String get navegarFailedToLoad;

  /// Navegar screen empty state title when no nearby users
  ///
  /// In es, this message translates to:
  /// **'Nadie cerca todavía'**
  String get navegarNoOneNearby;

  /// Navegar screen empty state subtitle suggesting broader filters
  ///
  /// In es, this message translates to:
  /// **'Amplía tu radio o ajusta los filtros'**
  String get navegarExpandRadius;

  /// Navegar location-denied banner message
  ///
  /// In es, this message translates to:
  /// **'Activa la ubicación para ver personas cercanas'**
  String get navegarEnableLocation;

  /// Button to open system app settings (e.g. from location-denied banner)
  ///
  /// In es, this message translates to:
  /// **'Abrir ajustes'**
  String get abrirAjustes;

  /// Filter sheet distance slider label showing current km value
  ///
  /// In es, this message translates to:
  /// **'Distancia: {km} km'**
  String filterDistanceLabel(int km);

  /// Filter sheet age range slider label
  ///
  /// In es, this message translates to:
  /// **'Rango de edad: {min} - {max}'**
  String filterAgeRange(int min, int max);

  /// Filter sheet section label for tribe selection
  ///
  /// In es, this message translates to:
  /// **'Tribu'**
  String get filterTribeLabel;

  /// Dropdown hint when no filter value is selected (Any)
  ///
  /// In es, this message translates to:
  /// **'Cualquiera'**
  String get filterAny;

  /// Filter sheet section label for text search
  ///
  /// In es, this message translates to:
  /// **'Buscar'**
  String get filterSearchLabel;

  /// Filter sheet text search field hint
  ///
  /// In es, this message translates to:
  /// **'Nombre, bio...'**
  String get filterSearchHint;

  /// Filter sheet Reset button label
  ///
  /// In es, this message translates to:
  /// **'Restablecer'**
  String get filterReset;

  /// Filter sheet Apply button label
  ///
  /// In es, this message translates to:
  /// **'Aplicar'**
  String get filterApply;

  /// Fallback display name when a user has no name set
  ///
  /// In es, this message translates to:
  /// **'Usuario'**
  String get usuarioFallback;

  /// Label for the current user (e.g. own story avatar, group member)
  ///
  /// In es, this message translates to:
  /// **'Tú'**
  String get tuLabel;

  /// Story viewer delete story dialog title and popup menu item
  ///
  /// In es, this message translates to:
  /// **'Eliminar historia'**
  String get eliminarHistoria;

  /// Generic confirmation dialog body asking if the user is sure
  ///
  /// In es, this message translates to:
  /// **'¿Estás seguro?'**
  String get estaSeguro;

  /// Snackbar shown after successfully sending a tap on profile detail
  ///
  /// In es, this message translates to:
  /// **'¡Tap enviado!'**
  String get tapEnviado;

  /// Snackbar shown when sending a tap fails on profile detail
  ///
  /// In es, this message translates to:
  /// **'Error al enviar tap: {error}'**
  String tapFallido(String error);

  /// Generic action-failed snackbar (e.g. favorite toggle error)
  ///
  /// In es, this message translates to:
  /// **'Error: {error}'**
  String accionFallida(String error);

  /// Profile detail report sheet title
  ///
  /// In es, this message translates to:
  /// **'Reportar a este usuario'**
  String get reportarEsteUsuario;

  /// Profile detail snackbar after successfully submitting a report
  ///
  /// In es, this message translates to:
  /// **'Reporte enviado. Gracias.'**
  String get reporteEnviado;

  /// Profile detail snackbar when report submission fails
  ///
  /// In es, this message translates to:
  /// **'Error al enviar el reporte'**
  String get reporteFallido;

  /// Profile detail snackbar when starting a chat fails
  ///
  /// In es, this message translates to:
  /// **'Error al iniciar chat: {error}'**
  String chatInicioFallido(String error);

  /// Badge text shown on a verified profile photo
  ///
  /// In es, this message translates to:
  /// **'Verificado'**
  String get verificadoBadge;

  /// Tooltip for the pronouns stat row in profile detail
  ///
  /// In es, this message translates to:
  /// **'Pronombres'**
  String get pronounsTooltip;

  /// Tooltip for the HIV status stat row in profile detail (health section)
  ///
  /// In es, this message translates to:
  /// **'Estado de VIH'**
  String get hivTooltip;

  /// Profile detail social section header label (all caps)
  ///
  /// In es, this message translates to:
  /// **'REDES SOCIALES'**
  String get redesSocialesHeader;

  /// Profile detail age display (e.g. '35 años')
  ///
  /// In es, this message translates to:
  /// **'{age} años'**
  String profileAge(int age);

  /// Snackbar shown after successfully unblocking a user in blocks list
  ///
  /// In es, this message translates to:
  /// **'Usuario desbloqueado'**
  String get usuarioDesbloqueado;

  /// Blocks list empty state message
  ///
  /// In es, this message translates to:
  /// **'No hay usuarios bloqueados'**
  String get noHayUsuariosBloqueados;

  /// Button label to unblock a user in the blocks list
  ///
  /// In es, this message translates to:
  /// **'Desbloquear'**
  String get desbloquear;

  /// Fallback display name for a blocked user with no name
  ///
  /// In es, this message translates to:
  /// **'Usuario desconocido'**
  String get usuarioDesconocido;

  /// Generic error snackbar with an error message
  ///
  /// In es, this message translates to:
  /// **'Error: {error}'**
  String errorGenerico(String error);

  /// Settings screen error when notification preferences fail to load
  ///
  /// In es, this message translates to:
  /// **'Error cargando notificaciones'**
  String get errorCargandoNotificaciones;

  /// Settings screen success snackbar after data export is requested
  ///
  /// In es, this message translates to:
  /// **'Exportación completada. Revisa tu correo.'**
  String get exporteDatosCompleto;

  /// Settings screen error snackbar when data export fails
  ///
  /// In es, this message translates to:
  /// **'Error al exportar: {error}'**
  String exporteFallido(String error);

  /// Settings screen error snackbar when account deletion fails
  ///
  /// In es, this message translates to:
  /// **'Error al eliminar: {error}'**
  String eliminarFallido(String error);

  /// Settings screen consent preferences dialog body text
  ///
  /// In es, this message translates to:
  /// **'Aceptaste los Términos de servicio y la Política de privacidad durante el registro. Tus datos se procesan de acuerdo con el RGPD. Puedes solicitar una exportación completa de datos o la eliminación de la cuenta en cualquier momento.'**
  String get consentDialogBody;

  /// Verify email screen AppBar title
  ///
  /// In es, this message translates to:
  /// **'Verificar correo'**
  String get verificarEmail;

  /// Verify email screen instructional text shown above the code field
  ///
  /// In es, this message translates to:
  /// **'Introduce el código de verificación de 6 dígitos enviado a tu correo'**
  String get verificarEmailInstrucciones;

  /// Verify email screen text field label
  ///
  /// In es, this message translates to:
  /// **'Código de verificación'**
  String get codigoVerificacion;

  /// Verify email screen validation error when code is not 6 digits
  ///
  /// In es, this message translates to:
  /// **'Por favor introduce un código de 6 dígitos'**
  String get errorCodigo6Digitos;

  /// Verify email screen error when verification API call fails
  ///
  /// In es, this message translates to:
  /// **'Verificación fallida. Inténtalo de nuevo.'**
  String get verificacionFallida;

  /// Verify email screen snackbar after successfully resending the code
  ///
  /// In es, this message translates to:
  /// **'Código de verificación enviado a tu correo'**
  String get codigoEnviado;

  /// Verify email screen submit button label
  ///
  /// In es, this message translates to:
  /// **'Verificar'**
  String get verificar;

  /// Verify email screen button to resend the verification code
  ///
  /// In es, this message translates to:
  /// **'Reenviar código'**
  String get reenviarCodigo;

  /// Verify email screen error when resending the code fails
  ///
  /// In es, this message translates to:
  /// **'Error al reenviar el código. Inténtalo de nuevo.'**
  String get errorReenviarCodigo;

  /// Group info screen snackbar when adding a member fails
  ///
  /// In es, this message translates to:
  /// **'Error al añadir miembro: {error}'**
  String errorAnadirMiembro(String error);

  /// Group info screen snackbar when removing a member fails
  ///
  /// In es, this message translates to:
  /// **'Error al eliminar miembro: {error}'**
  String errorEliminarMiembro(String error);

  /// Create group screen group name text field hint
  ///
  /// In es, this message translates to:
  /// **'p. ej. Amigos del gym'**
  String get groupNameHint;

  /// Add trip sheet title
  ///
  /// In es, this message translates to:
  /// **'Nuevo viaje'**
  String get nuevoViaje;

  /// Add trip form date text field label
  ///
  /// In es, this message translates to:
  /// **'Fecha (ej. Mar 2024)'**
  String get tripFechaLabel;

  /// Add trip form validation error when date is empty
  ///
  /// In es, this message translates to:
  /// **'Fecha requerida'**
  String get tripFechaRequerida;

  /// Add trip form location text field label
  ///
  /// In es, this message translates to:
  /// **'Localización'**
  String get tripLocalizacion;

  /// Add trip form validation error when location is empty
  ///
  /// In es, this message translates to:
  /// **'Localización requerida'**
  String get tripLocalizacionRequerida;

  /// Add trip form notes text field label
  ///
  /// In es, this message translates to:
  /// **'Notas (opcional)'**
  String get tripNotas;

  /// Edit profile screen photos section header label
  ///
  /// In es, this message translates to:
  /// **'FOTOS'**
  String get fotosSectionHeader;

  /// Create-story capture button label for taking a photo
  ///
  /// In es, this message translates to:
  /// **'Foto'**
  String get capturePhoto;

  /// Create-story capture button label for recording a video
  ///
  /// In es, this message translates to:
  /// **'Vídeo'**
  String get captureVideo;

  /// Register screen confirm-password field label
  ///
  /// In es, this message translates to:
  /// **'Confirma tu contraseña'**
  String get registerConfirmPassword;

  /// Register screen validator error when confirm password differs
  ///
  /// In es, this message translates to:
  /// **'Las contraseñas no coinciden'**
  String get registerPasswordMismatch;

  /// Edit profile discard-unsaved-changes dialog title
  ///
  /// In es, this message translates to:
  /// **'¿Descartar cambios?'**
  String get discardChangesTitle;

  /// Edit profile discard-unsaved-changes dialog body
  ///
  /// In es, this message translates to:
  /// **'Tienes cambios sin guardar. ¿Seguro que quieres salir?'**
  String get discardChangesBody;

  /// Edit profile discard-unsaved-changes dialog confirm button
  ///
  /// In es, this message translates to:
  /// **'Descartar'**
  String get discardVerb;

  /// Chat list empty state when there are no conversations
  ///
  /// In es, this message translates to:
  /// **'Aún no hay conversaciones'**
  String get noConversationsYet;

  /// Tienda feature list subtitle for unlimited_chats
  ///
  /// In es, this message translates to:
  /// **'Match sin espera'**
  String get tiendaFeatureUnlimitedChatsSubtitle;

  /// Tienda feature list title for no_ads
  ///
  /// In es, this message translates to:
  /// **'Sin anuncios'**
  String get tiendaFeatureNoAdsTitle;

  /// Tienda feature list subtitle for no_ads
  ///
  /// In es, this message translates to:
  /// **'Interfaz limpia'**
  String get tiendaFeatureNoAdsSubtitle;

  /// Tienda feature list subtitle for see_who_viewed
  ///
  /// In es, this message translates to:
  /// **'Lista completa'**
  String get tiendaFeatureSeeWhoViewedSubtitle;

  /// Tienda feature list subtitle for incognito_mode
  ///
  /// In es, this message translates to:
  /// **'Navega sin aparecer'**
  String get tiendaFeatureIncognitoSubtitle;

  /// Tienda feature list title for boost_discount
  ///
  /// In es, this message translates to:
  /// **'Boost descuento'**
  String get tiendaFeatureBoostDiscountTitle;

  /// Tienda feature list subtitle for boost_discount
  ///
  /// In es, this message translates to:
  /// **'Más visibilidad por menos'**
  String get tiendaFeatureBoostDiscountSubtitle;

  /// Tienda feature list subtitle for unlimited_profiles
  ///
  /// In es, this message translates to:
  /// **'Sin restricciones'**
  String get tiendaFeatureUnlimitedProfilesSubtitle;

  /// Tienda screen empty state when no tiered plans are returned
  ///
  /// In es, this message translates to:
  /// **'No hay planes disponibles'**
  String get tiendaNoPlansAvailable;

  /// Tienda screen error state message when plans fail to load
  ///
  /// In es, this message translates to:
  /// **'Error cargando planes'**
  String get tiendaLoadError;

  /// Tienda screen empty state when a plan has no prices
  ///
  /// In es, this message translates to:
  /// **'Sin precios disponibles'**
  String get tiendaNoPricesAvailable;

  /// Tienda screen retry button on error/empty states
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get tiendaRetry;

  /// Tienda screen snackbar when the user cancels the RC purchase flow
  ///
  /// In es, this message translates to:
  /// **'Compra cancelada'**
  String get tiendaPurchaseCancelled;

  /// Tienda screen generic purchase error snackbar
  ///
  /// In es, this message translates to:
  /// **'Error: {error}'**
  String tiendaPurchaseError(String error);

  /// Albums screen error state message when album list fails to load
  ///
  /// In es, this message translates to:
  /// **'Error al cargar álbumes: {error}'**
  String albumsLoadError(String error);

  /// Events create sheet snackbar when GPS location is unavailable
  ///
  /// In es, this message translates to:
  /// **'Ubicación no disponible. Activa el acceso a la ubicación e inténtalo de nuevo.'**
  String get eventsLocationUnavailable;

  /// Shop screen retry button on error state
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get shopRetry;

  /// Shop product card badge label for boost-type products
  ///
  /// In es, this message translates to:
  /// **'BOOST'**
  String get shopBadgeBoost;

  /// Shop product card badge label for highlight-type products
  ///
  /// In es, this message translates to:
  /// **'HIGHLIGHT'**
  String get shopBadgeHighlight;

  /// Shop product card badge label for tribe-slot products
  ///
  /// In es, this message translates to:
  /// **'TRIBE'**
  String get shopBadgeTribe;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
