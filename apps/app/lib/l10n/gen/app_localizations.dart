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
  /// **'XTRA'**
  String get xtra;

  /// Unlimited tier label
  ///
  /// In es, this message translates to:
  /// **'UNLIMITED'**
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
