import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'story_service.dart';

/// Full-screen story viewer with auto-advancing progress timer.
/// Swipe down to close, tap left/right to navigate between stories.
class StoryViewerScreen extends ConsumerStatefulWidget {
  final List<StoryGroup> groups;
  final int initialGroupIndex;

  const StoryViewerScreen({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
  });

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen> {
  late int _groupIndex;
  late int _storyIndex;
  Timer? _timer;
  double _progress = 0.0;
  bool _paused = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<StoryGroup> get _groups => widget.groups;
  StoryGroup get _currentGroup => _groups[_groupIndex];
  StoryJson get _currentStory => _currentGroup.stories[_storyIndex];

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex;
    _storyIndex = 0;
    _markViewed();
    _startProgress();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _markViewed() async {
    if (!_currentStory.viewed) {
      try {
        await ref.read(storyServiceProvider).viewStory(_currentStory.id);
      } catch (_) {
        // Silently ignore — viewing is best-effort
      }
    }
  }

  void _startProgress() {
    _timer?.cancel();
    _progress = 0.0;
    _paused = false;

    final duration = _getStoryDuration();
    if (duration <= 0) return;

    const interval = Duration(milliseconds: 50);
    final steps = duration.inMilliseconds / 50;
    final increment = 1.0 / steps;

    _timer = Timer.periodic(interval, (timer) {
      if (_paused) return;
      setState(() {
        _progress += increment;
        if (_progress >= 1.0) {
          _advanceToNext();
        }
      });
    });
  }

  Duration _getStoryDuration() {
    if (_currentStory.mediaType == 'video') {
      // Use a default 15s for video (actual duration would come from metadata)
      return const Duration(seconds: 15);
    }
    // Photo: 5 seconds
    return const Duration(seconds: 5);
  }

  void _advanceToNext() {
    final stories = _currentGroup.stories;
    if (_storyIndex + 1 < stories.length) {
      setState(() {
        _storyIndex++;
      });
      _markViewed();
      _startProgress();
    } else {
      _goToNextGroup();
    }
  }

  void _goToPrevious() {
    if (_storyIndex > 0) {
      setState(() {
        _storyIndex--;
      });
      _markViewed();
      _startProgress();
    } else if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _storyIndex = _groups[_groupIndex].stories.length - 1;
      });
      _markViewed();
      _startProgress();
    }
  }

  void _goToNextGroup() {
    if (_groupIndex + 1 < _groups.length) {
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      _markViewed();
      _startProgress();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onTapDown(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (details.localPosition.dx < screenWidth / 3) {
      _goToPrevious();
    } else if (details.localPosition.dx > screenWidth * 2 / 3) {
      _advanceToNext();
    } else {
      setState(() => _paused = !_paused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _currentStory;
    final group = _currentGroup;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: _onTapDown,
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 500) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media content
            Positioned.fill(
              child: story.mediaType == 'video'
                  ? _VideoStory(mediaKey: story.mediaKey)
                  : _PhotoStory(mediaKey: story.mediaKey),
            ),

            // Top bar: user info + progress bars + close
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress bars
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: _ProgressBars(
                        count: group.stories.length,
                        currentIndex: _storyIndex,
                        progress: _progress,
                      ),
                    ),
                    // User info + close button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundImage: group.avatarKey != null
                                ? NetworkImage(
                                    'https://api.turnend.win/media/get-url?key=${group.avatarKey}&kind=profile')
                                : null,
                            child: group.avatarKey == null
                                ? const Icon(Icons.person,
                                    color: Colors.white, size: 20)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              group.displayName ?? 'Usuario',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 24),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Caption at bottom
            if (story.caption != null && story.caption!.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      story.caption!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        shadows: [
                          Shadow(
                            blurRadius: 10,
                            color: Colors.black,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Delete button for own stories
            Positioned(
              top: 80,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.more_vert,
                    color: Colors.white70, size: 20),
                onPressed: () {
                  // TODO: show options (delete, etc.)
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress bars widget
// ---------------------------------------------------------------------------

class _ProgressBars extends StatelessWidget {
  final int count;
  final int currentIndex;
  final double progress;

  const _ProgressBars({
    required this.count,
    required this.currentIndex,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        return Expanded(
          child: Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: Colors.white24,
            ),
            child: i < currentIndex
                ? Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.white,
                    ),
                  )
                : i == currentIndex
                    ? FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: Colors.white,
                          ),
                        ),
                      )
                    : null,
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Photo story widget
// ---------------------------------------------------------------------------

class _PhotoStory extends StatelessWidget {
  final String mediaKey;

  const _PhotoStory({required this.mediaKey});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      'https://api.turnend.win/media/get-url?key=$mediaKey&kind=story',
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Video story widget
// ---------------------------------------------------------------------------

class _VideoStory extends StatefulWidget {
  final String mediaKey;

  const _VideoStory({required this.mediaKey});

  @override
  State<_VideoStory> createState() => _VideoStoryState();
}

class _VideoStoryState extends State<_VideoStory> {
  final AudioPlayer _player = AudioPlayer();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final url =
        'https://api.turnend.win/media/get-url?key=${widget.mediaKey}&kind=story';
    await _player.setSource(UrlSource(url));
    await _player.resume();
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    // Video uses same image URL approach since we use NetworkImage
    // The backend serves the video via presigned URL
    return Stack(
      fit: StackFit.expand,
      children: [
        // Placeholder thumbnail - we just show a play button overlay
        Container(color: Colors.black),
        // Audio-only playback for now (video playback would need a video player)
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_circle_outline,
                  color: Colors.white54, size: 64),
              const SizedBox(height: 8),
              Text(
                'Video',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
