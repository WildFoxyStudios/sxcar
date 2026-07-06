import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'story_service.dart';

/// Screen to create a new story by taking a photo or video.
/// Uses image_picker for camera capture.
class CreateStoryScreen extends ConsumerStatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  ConsumerState<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends ConsumerState<CreateStoryScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _mediaFile;
  bool _isVideo = false;
  bool _uploading = false;
  final TextEditingController _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia(ImageSource source, {bool video = false}) async {
    try {
      final XFile? file;
      if (video) {
        file = await _picker.pickVideo(source: source, maxDuration: const Duration(seconds: 60));
      } else {
        file = await _picker.pickImage(source: source, imageQuality: 85);
      }
      if (file != null) {
        setState(() {
          _mediaFile = file;
          _isVideo = video;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _upload() async {
    if (_mediaFile == null) return;

    setState(() => _uploading = true);

    try {
      final bytes = await _mediaFile!.readAsBytes();
      final ext = _mediaFile!.name.split('.').last;
      final contentType = _isVideo ? 'video/mp4' : 'image/jpeg';

      // Step 1: Get presigned URL
      final service = ref.read(storyServiceProvider);
      final uploadUrl = await service.getUploadUrl(ext: ext);

      // Step 2: Upload to R2
      await service.uploadToR2(
        uploadUrl.putUrl,
        bytes,
        contentType: contentType,
      );

      // Step 3: Create story record
      await service.createStory(
        mediaKey: uploadUrl.key,
        mediaType: _isVideo ? 'video' : 'photo',
        caption: _captionController.text.trim(),
      );

      // Step 4: Invalidate stories list to refresh
      ref.invalidate(storiesListProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          loc.addStory,
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_mediaFile != null)
            TextButton(
              onPressed: _uploading ? null : _upload,
              child: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Share',
                      style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _mediaFile == null ? _buildCaptureUI(loc) : _buildPreviewUI(loc),
    );
  }

  Widget _buildCaptureUI(AppLocalizations loc) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Spacer(),
          const Icon(Icons.camera_alt, color: Colors.white54, size: 80),
          const SizedBox(height: 24),
          Text(
            loc.addStory,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CaptureButton(
                icon: Icons.camera_alt,
                label: loc.tapToView,
                onTap: () => _pickMedia(ImageSource.camera),
              ),
              const SizedBox(width: 32),
              _CaptureButton(
                icon: Icons.videocam,
                label: loc.tapToView,
                onTap: () => _pickMedia(ImageSource.camera, video: true),
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildPreviewUI(AppLocalizations loc) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Preview
        _isVideo
            ? Center(
                child: Icon(Icons.play_circle_outline,
                    color: Colors.white54, size: 64))
            : Image.file(
                File(_mediaFile!.path),
                fit: BoxFit.contain,
              ),

        // Caption input
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _captionController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: loc.storyCaption,
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white12,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLength: 120,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CaptureButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CaptureButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: const BoxDecoration(
          color: Colors.white12,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 36),
      ),
    );
  }
}
