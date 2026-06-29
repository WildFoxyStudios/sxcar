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
  final String? profilePhotoUrl;
  final List<String> tribes;
  final List<String> lookingFor;
  final List<String> meetAt;
  final List<String> tags;

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
    this.profilePhotoUrl,
    this.tribes = const [],
    this.lookingFor = const [],
    this.meetAt = const [],
    this.tags = const [],
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
      profilePhotoUrl: json['profile_photo_url'] as String?,
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
  bool _isEditing = false;
  bool _isSaving = false;

  // Controllers for edit mode
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _birthdateController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _bodyTypeController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _positionController = TextEditingController();
  final _ethnicityController = TextEditingController();
  final _pronounsController = TextEditingController();
  final _tribesController = TextEditingController();
  final _lookingForController = TextEditingController();
  final _meetAtController = TextEditingController();
  final _tagsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _birthdateController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _bodyTypeController.dispose();
    _relationshipController.dispose();
    _positionController.dispose();
    _ethnicityController.dispose();
    _pronounsController.dispose();
    _tribesController.dispose();
    _lookingForController.dispose();
    _meetAtController.dispose();
    _tagsController.dispose();
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
        // Populate edit controllers
        _displayNameController.text = profile.displayName ?? '';
        _bioController.text = profile.bio ?? '';
        _birthdateController.text = profile.birthdate ?? '';
        _heightController.text = profile.heightCm?.toString() ?? '';
        _weightController.text = profile.weightKg?.toString() ?? '';
        _bodyTypeController.text = profile.bodyType ?? '';
        _relationshipController.text = profile.relationshipStatus ?? '';
        _positionController.text = profile.position ?? '';
        _ethnicityController.text = profile.ethnicity ?? '';
        _pronounsController.text = profile.pronouns ?? '';
        _tribesController.text = profile.tribes.join(', ');
        _lookingForController.text = profile.lookingFor.join(', ');
        _meetAtController.text = profile.meetAt.join(', ');
        _tagsController.text = profile.tags.join(', ');
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

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);

    try {
      final dio = ref.read(dioProvider);
      final body = <String, dynamic>{
        'display_name': _displayNameController.text.isEmpty
            ? null
            : _displayNameController.text,
        'bio': _bioController.text.isEmpty ? null : _bioController.text,
        'birthdate': _birthdateController.text.isEmpty
            ? null
            : _birthdateController.text,
        'height_cm': _heightController.text.isEmpty
            ? null
            : int.tryParse(_heightController.text),
        'weight_kg': _weightController.text.isEmpty
            ? null
            : int.tryParse(_weightController.text),
        'body_type': _bodyTypeController.text.isEmpty
            ? null
            : _bodyTypeController.text,
        'relationship_status': _relationshipController.text.isEmpty
            ? null
            : _relationshipController.text,
        'position':
            _positionController.text.isEmpty ? null : _positionController.text,
        'ethnicity':
            _ethnicityController.text.isEmpty ? null : _ethnicityController.text,
        'pronouns':
            _pronounsController.text.isEmpty ? null : _pronounsController.text,
        'tribes': _tribesController.text.isEmpty
            ? []
            : _tribesController.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
        'looking_for': _lookingForController.text.isEmpty
            ? []
            : _lookingForController.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
        'meet_at': _meetAtController.text.isEmpty
            ? []
            : _meetAtController.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
        'tags': _tagsController.text.isEmpty
            ? []
            : _tagsController.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
      };

      final response = await dio.put<Map<String, dynamic>>(
        '/profile',
        data: body,
      );

      final userJson = response.data!['user'] as Map<String, dynamic>;
      final profile = UserProfile.fromJson(userJson);

      setState(() {
        _profile = profile;
        _isEditing = false;
        _isSaving = false;
      });
    } on DioException catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to save: ${e.response?.statusCode ?? e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwn = widget.userId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isOwn ? 'My Profile' : 'Profile'),
        actions: [
          if (isOwn && _profile != null && !_isLoading)
            IconButton(
              icon: Icon(_isEditing ? Icons.check : Icons.edit),
              onPressed: _isEditing ? _saveProfile : () {
                setState(() => _isEditing = true);
              },
            ),
        ],
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

    if (_isEditing) {
      return _buildEditForm();
    }

    return _buildView();
  }

  Widget _buildView() {
    final p = _profile!;
    final theme = Theme.of(context);

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

  Widget _buildEditForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildTextField('Display Name', _displayNameController),
        _buildTextField('Bio', _bioController, maxLines: 3),
        _buildTextField('Birthdate (YYYY-MM-DD)', _birthdateController),
        _buildTextField('Height (cm)', _heightController,
            keyboardType: TextInputType.number),
        _buildTextField('Weight (kg)', _weightController,
            keyboardType: TextInputType.number),
        _buildTextField('Body Type', _bodyTypeController),
        _buildTextField('Relationship Status', _relationshipController),
        _buildTextField('Position', _positionController),
        _buildTextField('Ethnicity', _ethnicityController),
        _buildTextField('Pronouns', _pronounsController),
        _buildTextField('Tribes (comma-separated)', _tribesController),
        _buildTextField('Looking For (comma-separated)', _lookingForController),
        _buildTextField('Meet At (comma-separated)', _meetAtController),
        _buildTextField('Tags (comma-separated)', _tagsController),
        const SizedBox(height: 16),
        if (_isSaving)
          const Center(child: CircularProgressIndicator())
        else
          FilledButton(
            onPressed: _saveProfile,
            child: const Text('Save Changes'),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            // Reset controllers to current profile values
            setState(() {
              _isEditing = false;
            });
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
