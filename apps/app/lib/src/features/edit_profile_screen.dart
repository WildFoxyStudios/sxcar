import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/auth_provider.dart';
import '../health/health_service.dart';
import '../media/media_service.dart';
import 'profile_screen.dart' show UserProfile;

/// Full editing form for the user's own profile at route /edit-profile.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  UserProfile? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  String? _error;

  // Controllers
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _ethnicityController = TextEditingController();
  final _pronounsController = TextEditingController();

  // Dropdown values
  String? _bodyType;
  String? _position;
  String? _relationshipStatus;

  // Multi-select values
  final Set<String> _selectedTribes = {};
  final Set<String> _selectedLookingFor = {};

  // Health fields
  String? _hivStatus;
  DateTime? _lastTestedOn;
  bool? _prep;
  bool _isSavingHealth = false;

  static const List<String> _bodyTypes = [
    'Slim',
    'Average',
    'Athletic',
    'Muscular',
    'Stocky',
    'Large',
    'Other',
  ];

  static const List<String> _positions = [
    'Top',
    'Bottom',
    'Versatile',
    'Side',
    'Not Sure',
  ];

  static const List<String> _relationshipStatuses = [
    'Single',
    'Dating',
    'Open Relationship',
    'Committed',
    'Married',
    'Poly',
  ];

  static const List<String> _tribeOptions = [
    'Bear',
    'Twink',
    'Jock',
    'Otter',
    'Daddy',
    'Geek',
    'Leather',
    'Pup',
    'Muscle',
    'Chub',
    'Trans',
    'Queer',
    'Drag',
    'Furry',
    'Military',
    'Poz',
    'Clean',
    'Discreet',
  ];

  static const List<String> _lookingForOptions = [
    'Chat',
    'Dates',
    'Friends',
    'Networking',
    'Relationship',
    'Right Now',
    'Open to Explore',
  ];

  static const List<String> _hivStatusOptions = [
    'Unknown',
    'Negative',
    'Positive',
    'Prefer not to say',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _ethnicityController.dispose();
    _pronounsController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, dynamic>>('/profile');
      final userJson = response.data!['user'] as Map<String, dynamic>;
      final profile = UserProfile.fromJson(userJson);

      setState(() {
        _profile = profile;
        _isLoading = false;

        // Pre-fill controllers
        _displayNameController.text = profile.displayName ?? '';
        _bioController.text = profile.bio ?? '';
        _heightController.text = profile.heightCm?.toString() ?? '';
        _weightController.text = profile.weightKg?.toString() ?? '';
        _ethnicityController.text = profile.ethnicity ?? '';
        _pronounsController.text = profile.pronouns ?? '';

        // Pre-fill dropdowns
        _bodyType = profile.bodyType;
        _position = profile.position;
        _relationshipStatus = profile.relationshipStatus;

        // Pre-fill multi-select
        _selectedTribes.addAll(profile.tribes);
        _selectedLookingFor.addAll(profile.lookingFor);

        // Load health fields separately; ignore failures so the main
        // profile form still works if /profile/health is unreachable.
        unawaited(_loadHealth());
      });
    } on DioException catch (e) {
      setState(() {
        _isLoading = false;
        _error =
            'Failed to load profile: ${e.response?.statusCode ?? e.message}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load profile: $e';
      });
    }
  }

  Future<void> _loadHealth() async {
    try {
      final service = ref.read(healthServiceProvider);
      final info = await service.fetchHealth();
      if (!mounted) return;
      setState(() {
        _hivStatus = info.hivStatus;
        _prep = info.prep;
        if (info.lastTestedOn != null) {
          try {
            _lastTestedOn = DateTime.parse(info.lastTestedOn!);
          } catch (_) {
            _lastTestedOn = null;
          }
        }
      });
    } catch (_) {
      // Best-effort — leave fields null if endpoint fails.
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (picked == null) return;

      setState(() => _isUploadingPhoto = true);

      final bytes = await picked.readAsBytes();

      final mediaService = MediaService(ref.read(dioProvider));
      final uploadUrl = await mediaService.getUploadUrl(kind: 'profile_photo');
      await mediaService.uploadToR2(uploadUrl.putUrl, bytes);
      // Update profile via API with the new photo key
      final dio = ref.read(dioProvider);
      final updateResponse = await dio.put<Map<String, dynamic>>(
        '/profile',
        data: {'profile_photo_key': uploadUrl.key},
      );
      final userJson = updateResponse.data!['user'] as Map<String, dynamic>;
      final updatedProfile = UserProfile.fromJson(userJson);

      setState(() {
        _profile = updatedProfile;
        _isUploadingPhoto = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } on DioException catch (e) {
      setState(() => _isUploadingPhoto = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Photo upload failed: ${e.response?.statusCode ?? e.message}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploadingPhoto = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        'height_cm': _heightController.text.isEmpty
            ? null
            : int.tryParse(_heightController.text),
        'weight_kg': _weightController.text.isEmpty
            ? null
            : int.tryParse(_weightController.text),
        'body_type': _bodyType,
        'relationship_status': _relationshipStatus,
        'position': _position,
        'ethnicity': _ethnicityController.text.isEmpty
            ? null
            : _ethnicityController.text,
        'pronouns': _pronounsController.text.isEmpty
            ? null
            : _pronounsController.text,
        'tribes': _selectedTribes.toList(),
        'looking_for': _selectedLookingFor.toList(),
      };

      final response = await dio.put<Map<String, dynamic>>(
        '/profile',
        data: body,
      );

      final userJson = response.data!['user'] as Map<String, dynamic>;
      final updatedProfile = UserProfile.fromJson(userJson);

      // Also save the health fields. If this fails, still consider the
      // main profile save a success and surface a warning snackbar.
      await _saveHealth(silent: true);

      setState(() {
        _profile = updatedProfile;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        context.pop();
      }
    } on DioException catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save: ${e.response?.statusCode ?? e.message}',
            ),
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

  /// PUT /profile/health with the current form values.
  /// Returns true on success, false on failure. When [silent] is true, no
  /// snackbar is shown — used by the main Save flow so the user only sees
  /// one confirmation even if both requests succeed.
  Future<bool> _saveHealth({bool silent = false}) async {
    setState(() => _isSavingHealth = true);
    try {
      final service = ref.read(healthServiceProvider);
      final lastTestedStr = _lastTestedOn == null
          ? null
          : '${_lastTestedOn!.year.toString().padLeft(4, '0')}-${_lastTestedOn!.month.toString().padLeft(2, '0')}-${_lastTestedOn!.day.toString().padLeft(2, '0')}';
      await service.updateHealth(HealthInfo(
        hivStatus: _hivStatus,
        lastTestedOn: lastTestedStr,
        prep: _prep,
      ));
      setState(() => _isSavingHealth = false);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Health info saved!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
      return true;
    } on DioException catch (e) {
      setState(() => _isSavingHealth = false);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save health: ${e.response?.statusCode ?? e.message}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } catch (e) {
      setState(() => _isSavingHealth = false);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save health: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _pickLastTestedDate() async {
    final now = DateTime.now();
    final initial = _lastTestedOn ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1980),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _lastTestedOn = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loadProfile,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _buildForm(theme),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Photo section
        Center(
          child: Stack(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.grey.shade800,
                backgroundImage: _profile?.profilePhotoUrl != null
                    ? NetworkImage(_profile!.profilePhotoUrl!)
                    : null,
                child: _profile?.profilePhotoUrl == null
                    ? Text(
                        (_profile?.displayName ?? _profile?.email ?? 'U')[0]
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 32,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : null,
              ),
              if (_isUploadingPhoto)
                CircleAvatar(
                  radius: 48,
                  backgroundColor: Colors.black54,
                  child: const CircularProgressIndicator(
                    color: Color(0xFFF4C542),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: _isUploadingPhoto
              ? const Text(
                  'Uploading...',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                )
              : TextButton.icon(
                  onPressed: _pickAndUploadPhoto,
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Change Photo'),
                ),
        ),
        const SizedBox(height: 24),

        // Display Name
        _buildLabel('Display Name'),
        const SizedBox(height: 4),
        TextField(
          controller: _displayNameController,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('Your display name'),
        ),
        const SizedBox(height: 16),

        // Bio
        _buildLabel('Bio'),
        const SizedBox(height: 4),
        TextField(
          controller: _bioController,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('Tell people about yourself'),
        ),
        const SizedBox(height: 16),

        // Height + Weight row
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Height (cm)'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _heightController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('cm'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Weight (kg)'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _weightController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('kg'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Body Type dropdown
        _buildLabel('Body Type'),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _bodyType,
          dropdownColor: const Color(0xFF1A1A1A),
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('Select body type'),
          items: _bodyTypes
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (val) => setState(() => _bodyType = val),
        ),
        const SizedBox(height: 16),

        // Position dropdown
        _buildLabel('Position'),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _position,
          dropdownColor: const Color(0xFF1A1A1A),
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('Select position'),
          items: _positions
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: (val) => setState(() => _position = val),
        ),
        const SizedBox(height: 16),

        // Relationship Status dropdown
        _buildLabel('Relationship Status'),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _relationshipStatus,
          dropdownColor: const Color(0xFF1A1A1A),
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('Select relationship status'),
          items: _relationshipStatuses
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: (val) => setState(() => _relationshipStatus = val),
        ),
        const SizedBox(height: 16),

        // Ethnicity
        _buildLabel('Ethnicity'),
        const SizedBox(height: 4),
        TextField(
          controller: _ethnicityController,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('e.g. Caucasian, Latino, Asian'),
        ),
        const SizedBox(height: 16),

        // Pronouns
        _buildLabel('Pronouns'),
        const SizedBox(height: 4),
        TextField(
          controller: _pronounsController,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('e.g. He/Him, They/Them'),
        ),
        const SizedBox(height: 20),

        // Tribes multi-select
        _buildSectionHeader('Tribes'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _tribeOptions.map((tribe) {
            final selected = _selectedTribes.contains(tribe);
            return FilterChip(
              label: Text(tribe),
              selected: selected,
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _selectedTribes.add(tribe);
                  } else {
                    _selectedTribes.remove(tribe);
                  }
                });
              },
              selectedColor: theme.colorScheme.primary.withValues(alpha: 0.3),
              checkmarkColor: theme.colorScheme.primary,
              backgroundColor: Colors.grey.shade800,
              labelStyle: TextStyle(
                color: selected ? theme.colorScheme.primary : Colors.white70,
                fontSize: 13,
              ),
              side: BorderSide(
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.grey.shade700,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Looking For multi-select
        _buildSectionHeader('Looking For'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _lookingForOptions.map((lf) {
            final selected = _selectedLookingFor.contains(lf);
            return FilterChip(
              label: Text(lf),
              selected: selected,
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _selectedLookingFor.add(lf);
                  } else {
                    _selectedLookingFor.remove(lf);
                  }
                });
              },
              selectedColor: theme.colorScheme.primary.withValues(alpha: 0.3),
              checkmarkColor: theme.colorScheme.primary,
              backgroundColor: Colors.grey.shade800,
              labelStyle: TextStyle(
                color: selected ? theme.colorScheme.primary : Colors.white70,
                fontSize: 13,
              ),
              side: BorderSide(
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.grey.shade700,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 32),

        // Health section
        _buildSectionHeader('Health'),
        const SizedBox(height: 12),

        // HIV status dropdown
        _buildLabel('HIV Status'),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _hivStatus,
          dropdownColor: const Color(0xFF1A1A1A),
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('Select status'),
          items: _hivStatusOptions
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (val) => setState(() => _hivStatus = val),
        ),
        const SizedBox(height: 16),

        // Last tested on date picker
        _buildLabel('Last Tested On'),
        const SizedBox(height: 4),
        InkWell(
          onTap: _pickLastTestedDate,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _lastTestedOn == null
                        ? 'Not set'
                        : '${_lastTestedOn!.year.toString().padLeft(4, '0')}-${_lastTestedOn!.month.toString().padLeft(2, '0')}-${_lastTestedOn!.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: _lastTestedOn == null
                          ? Colors.grey
                          : Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Icon(Icons.calendar_today, color: Colors.grey, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // PrEP toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'On PrEP',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              Switch(
                value: _prep ?? false,
                activeThumbColor: const Color(0xFFF4C542),
                onChanged: (val) => setState(() => _prep = val),
              ),
            ],
          ),
        ),
        if (_isSavingHealth)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        const SizedBox(height: 32),

        // Save button
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isSaving ? null : _saveProfile,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => context.pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey,
              side: const BorderSide(color: Colors.grey),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.grey,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildSectionHeader(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.grey,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF333333)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF333333)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFF4C542), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
