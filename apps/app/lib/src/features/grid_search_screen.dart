import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import '../auth/auth_provider.dart';
import '../location/location_service.dart';
import '../location/geocoding_service.dart';
import '../places/places_service.dart';
import '../places/roam_service.dart';
import '../travel/travel_pass_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../premium/premium_gate.dart';
import '../premium/premium_service.dart';
import '../settings/settings_providers.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'navegar_screen.dart' show NearbyUser;

/// Default tribe options (hardcoded fallback if the API is unreachable).
const _kDefaultTribes = [
  'Bear', 'Otter', 'Twink', 'Jock', 'Daddy', 'Geek',
  'Muscle', 'Chub', 'Leather', 'Trans', 'Queer',
];

/// Geocoding suggestion displayed in the dropdown.
class _GeocodingSuggestion {
  final String label;
  final double lat;
  final double lon;

  const _GeocodingSuggestion({
    required this.label,
    required this.lat,
    required this.lon,
  });
}

/// Key for persisting recent city searches in SharedPreferences.
const _kRecentSearchesKey = 'explore_recent_searches';
const _kMaxRecentSearches = 5;
const _kSearchDebounceMs = Duration(milliseconds: 500);

/// Explore — global user grid with Roam support backed by real places,
/// plus city search via native geocoding and an optional mini-map.
class GridSearchScreen extends ConsumerStatefulWidget {
  const GridSearchScreen({super.key});

  @override
  ConsumerState<GridSearchScreen> createState() => _GridSearchScreenState();
}

class _GridSearchScreenState extends ConsumerState<GridSearchScreen> {
  late Future<List<NearbyUser>> _globalUsersFuture;

  // Existing: user name search
  final TextEditingController _searchController = TextEditingController();

  // New: city search
  final TextEditingController _cityController = TextEditingController();
  final FocusNode _cityFocus = FocusNode();

  // Roam location state — defaults used until /me/location is fetched.
  double _roamLat = 19.4326;
  double _roamLon = -99.1332;
  bool _isRoam = false;
  String _roamName = '';
  bool _hasAppliedPersistedRoam = false;

  // Travel Pass state
  TravelPass? _travelPass;
  bool _travelPassLoaded = false;

  // Tribe filter chips state
  Set<String> _selectedTribes = {};
  List<String> _tribes = _kDefaultTribes;

  // City search state
  latlong2.LatLng? _searchCenter;
  String _selectedLocationName = '';
  List<_GeocodingSuggestion> _suggestions = [];
  bool _showSuggestions = false;
  bool _isGeocoding = false;
  String? _geocodeError;
  Timer? _debounceTimer;
  List<String> _recentSearches = [];
  bool _recentSearchesLoaded = false;

  @override
  void initState() {
    super.initState();
    _globalUsersFuture = _fetchGlobalUsers();
    _applyRealLocationDefault();
    _loadRecentSearches();
    _loadFilterOptions();
    _loadTravelPass();

    // Listen for city text changes for debounced geocoding
    _cityController.addListener(_onCityTextChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _cityController.removeListener(_onCityTextChanged);
    _cityController.dispose();
    _cityFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Re-run the global query with the current search text.
  void _applySearch() {
    setState(() {
      _globalUsersFuture = _fetchGlobalUsers();
    });
  }

  /// On first load, if the user has NOT set a persisted Roam location, use the
  /// device's real GPS as the default center instead of the hardcoded fallback.
  Future<void> _applyRealLocationDefault() async {
    final pos = await ref.read(currentPositionProvider.future);
    if (pos == null || !mounted) return;
    if (_hasAppliedPersistedRoam && _isRoam) return;
    setState(() {
      _roamLat = pos.latitude;
      _roamLon = pos.longitude;
      if (_searchCenter == null) {
        _globalUsersFuture = _fetchGlobalUsers(
          lat: pos.latitude,
          lon: pos.longitude,
        );
      }
    });
  }

  /// Load recent city searches from SharedPreferences.
  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recentSearches =
          prefs.getStringList(_kRecentSearchesKey) ?? [];
      _recentSearchesLoaded = true;
    });
  }

  /// Load the current active travel pass from the server.
  Future<void> _loadTravelPass() async {
    try {
      final service = ref.read(travelPassServiceProvider);
      final tp = await service.getCurrent();
      if (!mounted) return;
      setState(() {
        _travelPass = tp;
        _travelPassLoaded = true;
        // If travel pass is active, use its location for the grid.
        if (tp != null) {
          _globalUsersFuture = _fetchGlobalUsers(lat: tp.lat, lon: tp.lon);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _travelPassLoaded = true);
    }
  }

  /// Set the travel pass to a specific city's coordinates.
  Future<void> _setTravelPass(double lat, double lon, String? cityName) async {
    try {
      final service = ref.read(travelPassServiceProvider);
      final tp = await service.set(lat: lat, lon: lon, cityName: cityName);
      if (!mounted) return;
      setState(() {
        _travelPass = tp;
        _globalUsersFuture = _fetchGlobalUsers(lat: tp.lat, lon: tp.lon);
      });
      final l10n = AppLocalizations.of(context);
      if (l10n != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.travelPassSetSuccess(cityName ?? '')),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.travelPassFailedToSet(e.toString()) ??
                'Failed to set travel pass: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Cancel the active travel pass and return to real GPS.
  Future<void> _cancelTravelPass() async {
    try {
      final service = ref.read(travelPassServiceProvider);
      await service.delete();
      if (!mounted) return;
      setState(() {
        _travelPass = null;
        _searchCenter = null;
        _cityController.clear();
        // Re-fetch with GPS location
        _globalUsersFuture = _fetchGlobalUsers();
      });
      final l10n = AppLocalizations.of(context);
      if (l10n != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.travelPassCancelled)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.travelPassFailedToCancel ?? 'Failed to cancel travel pass',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Load tribe filter options (with hardcoded defaults if API unreachable).
  Future<void> _loadFilterOptions() async {
    try {
      await ref.read(authReadyProvider.future);
      final dio = ref.read(dioProvider);
      final resp = await dio.get<Map<String, dynamic>>('/meta/filters');
      final data = resp.data!;
      if (mounted) {
        setState(() {
          _tribes = (data['tribes'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              _kDefaultTribes;
        });
      }
    } catch (_) {
      debugPrint('[GridSearchScreen] error: loading tribe options failed');
      // API unreachable — keep the hardcoded defaults.
    }
  }

  /// Persist a city search to the recent list (max 5, deduped).
  Future<void> _saveRecentSearch(String query) async {
    final updated = [
      query,
      ..._recentSearches.where((s) => s != query),
    ].take(_kMaxRecentSearches).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kRecentSearchesKey, updated);
    if (!mounted) return;
    setState(() => _recentSearches = updated);
  }

  /// Debounced geocoding handler.
  void _onCityTextChanged() {
    _debounceTimer?.cancel();
    final text = _cityController.text.trim();
    if (text.length < 2) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
        _geocodeError = null;
      });
      return;
    }
    _debounceTimer = Timer(_kSearchDebounceMs, () => _geocode(text));
  }

  /// Call the native geocoder and update suggestions.
  Future<void> _geocode(String query) async {
    setState(() {
      _isGeocoding = true;
      _geocodeError = null;
    });
    try {
      final service = ref.read(geocodingServiceProvider);
      final locations = await service.search(query);
      if (!mounted) return;
      if (_cityController.text.trim() != query) return; // stale response

      // The native geocoding Location type only exposes lat/lon, so we use the
      // query text (which is the city/place name the user typed) as the label.
      final suggestions = locations
          .take(5)
          .map((loc) => _GeocodingSuggestion(
                label: query,
                lat: loc.latitude,
                lon: loc.longitude,
              ))
          .toList();

      setState(() {
        _isGeocoding = false;
        _suggestions = suggestions;
        _showSuggestions = suggestions.isNotEmpty;
        _geocodeError = suggestions.isEmpty ? 'exploreNoResults' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeocoding = false;
        _suggestions = [];
        _showSuggestions = false;
        _geocodeError = 'exploreNoResults';
      });
    }
  }

  /// Select a geocoding suggestion: center the grid on the coordinates.
  void _selectSuggestion(_GeocodingSuggestion suggestion) {
    _cityController.text = suggestion.label;
    _saveRecentSearch(suggestion.label);
    setState(() {
      _searchCenter = latlong2.LatLng(suggestion.lat, suggestion.lon);
      _selectedLocationName = suggestion.label;
      _showSuggestions = false;
      // Refresh grid with new center
      _globalUsersFuture = _fetchGlobalUsers(
        lat: suggestion.lat,
        lon: suggestion.lon,
      );
    });
    _cityFocus.unfocus();
  }

  /// Toggle a tribe chip on/off and refresh the grid.
  void _toggleTribe(String tribe) {
    setState(() {
      if (_selectedTribes.contains(tribe)) {
        _selectedTribes.remove(tribe);
      } else {
        _selectedTribes.add(tribe);
      }
      _globalUsersFuture = _fetchGlobalUsers();
    });
  }

  /// Clear the search center and return to GPS/roam-based location.
  void _backToMyLocation() {
    if (_travelPass != null) {
      _cancelTravelPass();
      return;
    }
    setState(() {
      _searchCenter = null;
      _selectedLocationName = '';
      _cityController.clear();
      _suggestions = [];
      _showSuggestions = false;
      _globalUsersFuture = _fetchGlobalUsers();
    });
  }

  /// Select a recent search from the history list.
  void _selectRecentSearch(String recent) {
    // Parse the label back to coordinates if possible, or re-geocode
    _cityController.text = _cityController.text = recent;
    // Trigger geocoding for the recent query
    final match = RegExp(r'\(([\d.-]+),\s*([\d.-]+)\)').firstMatch(recent);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lon = double.tryParse(match.group(2)!);
      if (lat != null && lon != null) {
        _selectSuggestion(_GeocodingSuggestion(
          label: recent,
          lat: lat,
          lon: lon,
        ));
        return;
      }
    }
    _geocode(recent);
  }

  Future<List<NearbyUser>> _fetchGlobalUsers({double? lat, double? lon}) async {
    final dio = ref.read(dioProvider);
    final effectiveLat = _searchCenter?.latitude ?? lat ?? _roamLat;
    final effectiveLon = _searchCenter?.longitude ?? lon ?? _roamLon;
    final queryParams = <String, dynamic>{
      'lat': effectiveLat,
      'lon': effectiveLon,
      'radius_m': 500000,
      'limit': 50,
    };
    final q = _searchController.text.trim();
    if (q.isNotEmpty) queryParams['q'] = q;
    if (_selectedTribes.isNotEmpty) {
      queryParams['tribe'] = _selectedTribes.join(',');
    }

    final response = await dio.get<Map<String, dynamic>>(
      '/grid/nearby',
      queryParameters: queryParams,
    );

    final data = response.data!;
    final usersJson = data['users'] as List<dynamic>;
    return usersJson
        .map((u) => NearbyUser.fromJson(u as Map<String, dynamic>))
        .toList();
  }

  /// Apply a new roam location and refresh the grid.
  void _applyRoam({
    required double lat,
    required double lon,
    String? name,
    bool isRoam = true,
  }) {
    setState(() {
      _roamLat = lat;
      _roamLon = lon;
      _roamName = name ?? '';
      _isRoam = isRoam;
      _searchCenter = null; // roam overrides city search
      _cityController.clear();
      _globalUsersFuture = _fetchGlobalUsers(lat: lat, lon: lon);
    });
  }

  void _showRoamSheet() {
    final outerMessenger = ScaffoldMessenger.of(context);
    final outerContext = context;
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VibraTheme.kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _RoamBottomSheet(
        onPickPlace: (place) async {
          try {
            final roam = ref.read(roamServiceProvider);
            await roam.set(
              lat: place.lat,
              lon: place.lon,
              name: place.name,
              isRoam: true,
            );
            ref.invalidate(roamLocationProvider);
            if (!outerContext.mounted) return;
            Navigator.of(ctx).pop();
            _applyRoam(
              lat: place.lat,
              lon: place.lon,
              name: place.name,
              isRoam: true,
            );
            outerMessenger.showSnackBar(
              SnackBar(content: Text(l10n.roamRoamingTo(place.name))),
            );
          } catch (e) {
            if (outerContext.mounted) {
              outerMessenger.showSnackBar(
                SnackBar(
                  content: Text(l10n.roamFailedToSet(e.toString())),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        onUseRealLocation: () async {
          try {
            final pos = await ref.read(currentPositionProvider.future);
            if (pos == null) {
              if (outerContext.mounted) {
                Navigator.of(ctx).pop();
                outerMessenger.showSnackBar(
                  SnackBar(
                    content: Text(
                        l10n.roamLocationUnavailable),
                  ),
                );
              }
              return;
            }
            final lat = pos.latitude;
            final lon = pos.longitude;
            final roam = ref.read(roamServiceProvider);
            await roam.setRealLocation(lat: lat, lon: lon);
            ref.invalidate(roamLocationProvider);
            if (!outerContext.mounted) return;
            Navigator.of(ctx).pop();
            _applyRoam(lat: lat, lon: lon, name: '', isRoam: false);
            outerMessenger.showSnackBar(
              SnackBar(content: Text(l10n.roamUsingRealLocation)),
            );
          } catch (e) {
            if (outerContext.mounted) {
              outerMessenger.showSnackBar(
                SnackBar(
                  content: Text(l10n.roamFailedGeneric(e.toString())),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // Load persisted roam on first build, then apply once.
    ref.listen<AsyncValue<RoamLocation?>>(roamLocationProvider, (prev, next) {
      if (_hasAppliedPersistedRoam) return;
      if (next is AsyncData<RoamLocation?>) {
        _hasAppliedPersistedRoam = true;
        final loc = next.value;
        if (loc != null) {
          _applyRoam(
            lat: loc.lat,
            lon: loc.lon,
            name: loc.name,
            isRoam: loc.isRoam,
          );
        }
      }
    });

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        titleSpacing: 0,
        title: Container(
          height: 44,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: VibraTheme.kChip,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: l10n.explorarMasPerfiles,
                    hintStyle:
                        const TextStyle(color: VibraTheme.kTextSecondary),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _applySearch(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_isRoam && _roamName.isNotEmpty)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: VibraTheme.kChip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _roamName,
                  style: const TextStyle(
                      color: VibraTheme.kYellow,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.explore_outlined,
              color: _isRoam ? VibraTheme.kYellow : Colors.white,
            ),
            tooltip: l10n.roamTooltip,
            onPressed: () {
              // Gate Travel Pass behind Xtra/Unlimited tier
              final premiumAsync = ref.read(premiumStatusProvider);
              final data = premiumAsync is AsyncData ? premiumAsync.value : null;
              if (data == null || !data.features.travelPass) {
                showPremiumComparisonSheet(context);
                return;
              }
              _showRoamSheet();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── City search bar ──────────────────────────────────────────────
          _buildCitySearchBar(l10n),

          // ── Suggestions / recent searches overlay ────────────────────────
          if (_showSuggestions || _recentSearchesLoaded)
            _buildSuggestionOverlay(l10n),

          // ── Mini-map when a city is selected ─────────────────────────────
          if (_searchCenter != null) _buildMiniMap(),

          // ── Location indicator + back button ─────────────────────────────
          if (_searchCenter != null) _buildLocationIndicator(l10n),

          // ── Travel Pass banner ───────────────────────────────────────────
          if (_travelPass != null) _buildTravelPassBanner(l10n),

          // ── Tribe filter chips ───────────────────────────────────────────
          if (_tribes.isNotEmpty)
            _buildTribeChips(l10n),

          // ── User grid ────────────────────────────────────────────────────
          Expanded(child: _buildGrid(theme, l10n)),
        ],
      ),
    );
  }

  Widget _buildCitySearchBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        controller: _cityController,
        focusNode: _cityFocus,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: l10n.exploreSearchHint,
          hintStyle: const TextStyle(color: VibraTheme.kTextSecondary),
          prefixIcon:
              const Icon(Icons.location_city, color: VibraTheme.kTextSecondary),
          suffixIcon: _isGeocoding
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : (_cityController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _cityController.clear();
                          if (_searchCenter != null) _backToMyLocation();
                        },
                      )
                    : null),
          filled: true,
          fillColor: VibraTheme.kChip,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (value) {
          if (value.trim().length >= 2) {
            _geocode(value.trim());
          }
        },
      ),
    );
  }

  Widget _buildSuggestionOverlay(AppLocalizations l10n) {
    final hasSuggestions = _showSuggestions && _suggestions.isNotEmpty;
    final hasRecent = _recentSearches.isNotEmpty &&
        _cityController.text.isEmpty &&
        _cityFocus.hasFocus;

    if (!hasSuggestions && !hasRecent && _geocodeError == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: VibraTheme.kSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: const BoxConstraints(maxHeight: 260),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          type: MaterialType.transparency,
          child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: [
            // Geocoding error message
            if (_geocodeError != null && !hasSuggestions)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.exploreNoResults,
                  style: const TextStyle(
                    color: VibraTheme.kTextSecondary,
                    fontSize: 14,
                  ),
                ),
              ),

            // Recent searches header
            if (hasRecent)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: Text(
                  l10n.exploreRecentSearches,
                  style: const TextStyle(
                    color: VibraTheme.kTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            // Recent searches items
            if (hasRecent)
              ...List.generate(_recentSearches.length, (i) {
                final recent = _recentSearches[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, size: 18,
                      color: VibraTheme.kTextSecondary),
                  title: Text(recent,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  onTap: () => _selectRecentSearch(recent),
                );
              }),

            // Geocoding suggestions
            if (hasSuggestions)
              ...List.generate(_suggestions.length, (i) {
                final s = _suggestions[i];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place, size: 18,
                          color: VibraTheme.kAccent),
                      title: Text(s.label,
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${s.lat.toStringAsFixed(4)}, ${s.lon.toStringAsFixed(4)}',
                        style: const TextStyle(fontSize: 11,
                            color: VibraTheme.kTextSecondary),
                      ),
                      onTap: () => _selectSuggestion(s),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 44, right: 12, bottom: 4),
                      child: SizedBox(
                        height: 32,
                        child: OutlinedButton.icon(
                          onPressed: () => _setTravelPass(s.lat, s.lon, s.label),
                          icon: const Icon(Icons.flight_takeoff, size: 16),
                          label: Text(
                            AppLocalizations.of(context)!.travelPassSet(s.label),
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: VibraTheme.kYellow,
                            side: const BorderSide(color: VibraTheme.kYellow),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildMiniMap() {
    final center = _searchCenter!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VibraTheme.kDivider),
      ),
      clipBehavior: Clip.antiAlias,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: 12,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.vibra.app',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: center,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_on,
                  color: VibraTheme.kAccent,
                  size: 36,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationIndicator(AppLocalizations l10n) {
    final label = _selectedLocationName.isNotEmpty
        ? _selectedLocationName
        : '${_searchCenter!.latitude.toStringAsFixed(4)}, '
            '${_searchCenter!.longitude.toStringAsFixed(4)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          const Icon(Icons.location_on, size: 16, color: VibraTheme.kAccent),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: VibraTheme.kAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: _backToMyLocation,
            icon: const Icon(Icons.my_location, size: 16),
            label: Text(
              l10n.exploreBackToMyLocation,
              style: const TextStyle(fontSize: 12),
            ),
            style: TextButton.styleFrom(
              foregroundColor: VibraTheme.kTextSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  /// Travel Pass banner showing active travel location and expiry.
  Widget _buildTravelPassBanner(AppLocalizations l10n) {
    final tp = _travelPass;
    if (tp == null) return const SizedBox.shrink();
    final cityLabel = tp.cityName ?? '${tp.lat.toStringAsFixed(4)}, ${tp.lon.toStringAsFixed(4)}';
    final hoursRemaining = tp.expiresInHours.toStringAsFixed(1);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VibraTheme.kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VibraTheme.kYellow.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.flight_takeoff, size: 18, color: VibraTheme.kYellow),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.travelPassBanner(cityLabel),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  l10n.travelPassExpires(hoursRemaining),
                  style: const TextStyle(
                    color: VibraTheme.kTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _cancelTravelPass,
            icon: const Icon(Icons.close, size: 16),
            label: Text(
              l10n.travelPassBackToMyLocation,
              style: const TextStyle(fontSize: 11),
            ),
            style: TextButton.styleFrom(
              foregroundColor: VibraTheme.kAccent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontal tribe filter chip bar.
  Widget _buildTribeChips(AppLocalizations l10n) {
    if (_tribes.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _tribes.map((tribe) {
          final selected = _selectedTribes.contains(tribe);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                tribe,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              selected: selected,
              selectedColor: VibraTheme.kAccent,
              checkmarkColor: Colors.black,
              backgroundColor: VibraTheme.kChip,
              side: BorderSide(
                color: selected ? VibraTheme.kAccent : VibraTheme.kDivider,
              ),
              onSelected: (_) => _toggleTribe(tribe),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGrid(ThemeData theme, AppLocalizations l10n) {
    return FutureBuilder<List<NearbyUser>>(
        future: _globalUsersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    l10n.gridFailedToLoad,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() {
                      _globalUsersFuture = _fetchGlobalUsers();
                    }),
                    child: Text(l10n.reintentar),
                  ),
                ],
              ),
            );
          }

          final users = snapshot.data ?? [];
          if (users.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: VibraTheme.kSurface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.explore_outlined,
                        size: 36,
                        color: VibraTheme.kAccent,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.gridNoUsersTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: VibraTheme.kTextPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.gridNoUsersSubtitle,
                      style: VibraTheme.bodySecondary,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => setState(() {
              _globalUsersFuture = _fetchGlobalUsers();
            }),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.zero,
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.91,
                          crossAxisSpacing: 1.5,
                          mainAxisSpacing: 1.5,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final user = users[index];
                            final units = ref.watch(unitsProvider);
                            return _ExploreUserCard(user: user, units: units);
                          },
                          childCount: users.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
  }
}

/// Full-bleed photo card matching the Cascade grid style (no online dot
/// since Explore shows global users where real-time status is less relevant).
class _ExploreUserCard extends StatelessWidget {
  final NearbyUser user;
  final int units; // 0=metric, 1=imperial (from unitsProvider)

  const _ExploreUserCard({required this.user, required this.units});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/profile/${user.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background: network photo or gradient placeholder
            if (user.profilePhotoUrl != null)
              Image.network(
                user.profilePhotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildPlaceholder(),
              )
            else
              _buildPlaceholder(),

            // Bottom gradient scrim
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 72,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0xD9000000),
                    ],
                  ),
                ),
              ),
            ),

            // Name + distance overlay (bottom)
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.displayName ?? user.email,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(blurRadius: 4, color: Color(0x99000000)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    user.distanceLabel(units),
                    style: const TextStyle(
                      color: VibraTheme.kTextSecondary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),

            // Verified badge (top right)
            if (user.isVerified)
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: VibraTheme.kAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.black, size: 11),
                ),
              ),

            // NUEVO badge (top left)
            if (user.isNew)
              Positioned(
                top: 5,
                left: 5,
                child: const NUEVOBadge.small(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [VibraTheme.kSurface, VibraTheme.kSurfaceElevated],
        ),
      ),
      child: Center(
        child: Text(
          (user.displayName ?? user.email)[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 28,
            color: VibraTheme.kTextMuted,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Roam bottom sheet: lists saved places + add-new form + use-real button.
class _RoamBottomSheet extends ConsumerStatefulWidget {
  final void Function(Place place) onPickPlace;
  final VoidCallback onUseRealLocation;

  const _RoamBottomSheet({
    required this.onPickPlace,
    required this.onUseRealLocation,
  });

  @override
  ConsumerState<_RoamBottomSheet> createState() => _RoamBottomSheetState();
}

class _RoamBottomSheetState extends ConsumerState<_RoamBottomSheet> {
  bool _showAddForm = false;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  Future<void> _submitNewPlace() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final lat = double.tryParse(_latController.text.trim());
    final lon = double.tryParse(_lonController.text.trim());
    if (lat == null || lon == null) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() => _submitting = true);
    try {
      final service = ref.read(placesServiceProvider);
      final place = await service.add(_nameController.text.trim(), lat, lon);
      ref.invalidate(placesProvider);
      if (!mounted) return;
      setState(() {
        _showAddForm = false;
        _nameController.clear();
        _latController.clear();
        _lonController.clear();
      });
      widget.onPickPlace(place);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.roamFailedToAddPlace(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final placesAsync = ref.watch(placesProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.explore, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    l10n.roamTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.roamSubtitle,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: widget.onUseRealLocation,
                icon: const Icon(Icons.my_location),
                label: Text(l10n.roamUseRealLocation),
              ),
              const SizedBox(height: 16),
              const Divider(color: VibraTheme.kDivider),
              const SizedBox(height: 8),
              placesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Failed to load places: $e',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
                data: (places) {
                  if (places.isEmpty && !_showAddForm) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l10n.roamNoSavedPlaces,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  if (places.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    children: places
                        .map(
                          (p) => ListTile(
                            leading: const Icon(Icons.place, color: Colors.white70),
                            title: Text(p.name),
                            subtitle: Text(
                              '${p.lat.toStringAsFixed(4)}, ${p.lon.toStringAsFixed(4)}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            onTap: () => widget.onPickPlace(p),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 8),
              if (!_showAddForm)
                TextButton.icon(
                  onPressed: () => setState(() => _showAddForm = true),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.roamAddNewPlace),
                )
              else
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: l10n.roamNameLabel,
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return l10n.roamNameRequired;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _latController,
                        decoration: InputDecoration(
                          labelText: l10n.roamLatitudeLabel,
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null) return l10n.roamMustBeNumber;
                          if (n < -90 || n > 90) return l10n.roamLatRange;
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _lonController,
                        decoration: InputDecoration(
                          labelText: l10n.roamLongitudeLabel,
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null) return l10n.roamMustBeNumber;
                          if (n < -180 || n > 180) return l10n.roamLonRange;
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _submitting
                                  ? null
                                  : () => setState(() {
                                        _showAddForm = false;
                                        _nameController.clear();
                                        _latController.clear();
                                        _lonController.clear();
                                      }),
                              child: Text(l10n.cancelar),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed:
                                  _submitting ? null : _submitNewPlace,
                              child: _submitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(l10n.roamAddAndRoam),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
