import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// Full profile model matching the backend's UserFullRow + arrays.
class UserProfile {
  final String id;
  final String email;
  final bool emailVerified;
  final String status;
  final String role;
  final String createdAt;
  final String? displayName;
  final String? bio;
  final String? birthdate;
  final int? heightCm;
  final int? weightKg;
  final String? bodyType;
  final String? relationshipStatus;
  final String? position;
  final String? ethnicity;
  final String? pronouns;
  final String? profilePhotoId;
  final String? profilePhotoKey;
  final String? profilePhotoUrl;
  final bool isVerified;
  final List<String> tribes;
  final List<String> lookingFor;
  final List<String> meetAt;
  final List<String> tags;
  final Map<String, dynamic> details;
  final bool showAge;
  final bool showRole;
  final bool showTribes;
  final bool showPosition;
  final bool showEthnicity;
  final bool showRelationshipStatus;
  final bool showSocialLinks;

  const UserProfile({
    required this.id,
    required this.email,
    required this.emailVerified,
    required this.status,
    required this.role,
    required this.createdAt,
    this.displayName,
    this.bio,
    this.birthdate,
    this.heightCm,
    this.weightKg,
    this.bodyType,
    this.relationshipStatus,
    this.position,
    this.ethnicity,
    this.pronouns,
    this.profilePhotoId,
    this.profilePhotoKey,
    this.profilePhotoUrl,
    this.isVerified = false,
    this.tribes = const [],
    this.lookingFor = const [],
    this.meetAt = const [],
    this.tags = const [],
    this.details = const {},
    this.showAge = true,
    this.showRole = true,
    this.showTribes = true,
    this.showPosition = true,
    this.showEthnicity = true,
    this.showRelationshipStatus = true,
    this.showSocialLinks = true,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      emailVerified: json['email_verified'] as bool,
      status: json['status'] as String,
      role: json['role'] as String,
      createdAt: json['created_at'] as String,
      displayName: json['display_name'] as String?,
      bio: json['bio'] as String?,
      birthdate: json['birthdate'] as String?,
      heightCm: json['height_cm'] as int?,
      weightKg: json['weight_kg'] as int?,
      bodyType: json['body_type'] as String?,
      relationshipStatus: json['relationship_status'] as String?,
      position: json['position'] as String?,
      ethnicity: json['ethnicity'] as String?,
      pronouns: json['pronouns'] as String?,
      profilePhotoId: json['profile_photo_id'] as String?,
      profilePhotoKey: json['profile_photo_key'] as String?,
      profilePhotoUrl: json['profile_photo_url'] as String?,
      isVerified: json['verified'] == true,
      tribes: (json['tribes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      lookingFor: (json['looking_for'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      meetAt: (json['meet_at'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      details: (json['details'] as Map<String, dynamic>?) ?? const {},
      showAge: json['show_age'] != false,
      showRole: json['show_role'] != false,
      showTribes: json['show_tribes'] != false,
      showPosition: json['show_position'] != false,
      showEthnicity: json['show_ethnicity'] != false,
      showRelationshipStatus: json['show_relationship_status'] != false,
      showSocialLinks: json['show_social_links'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'display_name': displayName,
        'bio': bio,
        'birthdate': birthdate,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'body_type': bodyType,
        'relationship_status': relationshipStatus,
        'position': position,
        'ethnicity': ethnicity,
        'pronouns': pronouns,
        'tribes': tribes,
        'looking_for': lookingFor,
        'meet_at': meetAt,
        'tags': tags,
      };
}

/// Screen for viewing/editing a user profile.
///
/// When [userId] is null, loads the authenticated user's own profile
/// from GET /profile. When [userId] is provided, loads that user's
/// public profile from GET /profile/:id.
class ProfileScreen extends ConsumerStatefulWidget {
  final String? userId;

  const ProfileScreen({super.key, this.userId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  UserProfile? _profile;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final uri = widget.userId != null ? '/profile/${widget.userId}' : '/profile';
      final response = await dio.get<Map<String, dynamic>>(uri);
      final userJson = response.data!['user'] as Map<String, dynamic>;
      final profile = UserProfile.fromJson(userJson);

      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load profile: ${e.response?.statusCode ?? e.message}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load profile: $e';
      });
    }
  }

  void _navigateToEditProfile() {
    Navigator.of(context).pushNamed('/edit-profile');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userId == null ? 'My Profile' : 'Profile'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadProfile,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_profile == null) {
      return const Center(child: Text('No profile data'));
    }

    return _buildView();
  }

  Widget _buildView() {
    final p = _profile!;
    final theme = Theme.of(context);
    final isOwn = widget.userId == null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Avatar / photo
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              (p.displayName ?? p.email)[0].toUpperCase(),
              style: TextStyle(
                fontSize: 32,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Display name
        if (p.displayName != null && p.displayName!.isNotEmpty)
          Center(
            child: Text(
              p.displayName!,
              style: theme.textTheme.headlineSmall,
            ),
          ),
        if (p.displayName != null && p.displayName!.isNotEmpty)
          const SizedBox(height: 8),

        // Bio
        if (p.bio != null && p.bio!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              p.bio!,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),

        const Divider(),

        // Stats section
        _buildStatRow(theme, 'Height', p.heightCm != null ? '${p.heightCm} cm' : null),
        _buildStatRow(theme, 'Weight', p.weightKg != null ? '${p.weightKg} kg' : null),
        _buildStatRow(theme, 'Body Type', p.bodyType),
        _buildStatRow(theme, 'Relationship', p.relationshipStatus),
        _buildStatRow(theme, 'Position', p.position),
        _buildStatRow(theme, 'Ethnicity', p.ethnicity),
        _buildStatRow(theme, 'Pronouns', p.pronouns),
        _buildStatRow(theme, 'Birthdate', p.birthdate),

        if (p.tribes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Tribes', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: p.tribes
                .map((t) => Chip(
                      label: Text(t),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
        ],

        if (p.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Tags', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: p.tags
                .map((t) => Chip(
                      label: Text(t),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
        ],

        if (p.lookingFor.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Looking for', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: p.lookingFor
                .map((t) => Chip(
                      label: Text(t),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
        ],

        if (p.meetAt.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Meet at', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: p.meetAt
                .map((t) => Chip(
                      label: Text(t),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
        ],

        // Edit Profile button for own profile
        if (isOwn) ...[
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: _navigateToEditProfile,
              icon: const Icon(Icons.edit),
              label: const Text('Edit Profile'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatRow(ThemeData theme, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            )),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // _buildEditForm and _buildTextField removed — editing now handled by /edit-profile
}
