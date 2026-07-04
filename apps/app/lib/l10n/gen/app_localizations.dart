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
