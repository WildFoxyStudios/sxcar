import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';
import '../theme/app_theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'story_service.dart';

// Base URL for all media endpoints — keeps the domain in one place.
const String _kMediaBase = 'https://api.turnend.win/media/get-url';

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
    if (!mounted) return;
  }

  void _startProgress() {
    _timer?.cancel();
    _progress = 0.0;
    _paused = false;

    final duration = _getStoryDuration();
    if (duration == Duration.zero) return;

    const interval = Duration(milliseconds: 50);
    final steps = duration.inMilliseconds / 50;
    final increment = 1.0 / steps;

    _timer = Timer.periodic(interval, (timer) {
      if (_paused) return;
      setState(() {
        _progress += increment;
      });
      if (_progress >= 1.0) {
        _advanceToNext();
      }
    });
  }

  /// Minimum sensible duration for any story segment — guards against
  /// zero/very-short video durations that would otherwise flash past.
  static const Duration _kMinDuration = Duration(seconds: 3);

  Duration _getStoryDuration() {
    if (_currentStory.mediaType == 'video') {
      // Fallback while the real video duration hasn't been reported yet
      // (or on error). `_onVideoDurationLoaded` recalibrates the timer once
      // the controller finishes initializing.
      return const Duration(seconds: 15);
    }
    // Photo: 5 seconds
    return const Duration(seconds: 5);
  }

  /// Called by `_VideoStory` once its controller has finished initializing.
  /// If the user is still on the story that reported the duration, restart
  /// the progress timer so the bar tracks the real video length instead of
  /// the flat 15s fallback.
  void _onVideoDurationLoaded(Duration duration) {
    if (_currentStory.mediaType != 'video') return;
    final clamped =
        duration < _kMinDuration ? _kMinDuration : duration;
    _startProgressWith(clamped);
  }

  /// Same as `_startProgress` but with an explicit duration, used once the
  /// real video length is known.
  void _startProgressWith(Duration duration) {
    _timer?.cancel();
    _progress = 0.0;

    const interval = Duration(milliseconds: 50);
    final steps = duration.inMilliseconds / 50;
    if (steps <= 0) return;
    final increment = 1.0 / steps;

    _timer = Timer.periodic(interval, (timer) {
      if (_paused) return;
      setState(() {
        _progress += increment;
      });
      if (_progress >= 1.0) {
        _advanceToNext();
      }
    });
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
                  ? _VideoStory(
                      mediaKey: story.mediaKey,
                      onLoaded: _onVideoDurationLoaded,
                    )
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
                                    '$_kMediaBase?key=${group.avatarKey}&kind=profile')
                                : null,
                            child: group.avatarKey == null
                                ? const Icon(Icons.person,
                                    color: Colors.white, size: 20)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              group.displayName ?? AppLocalizations.of(context)!.usuarioFallback,
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

            // Options button for own stories
            Positioned(
              top: 80,
              right: 12,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    color: Colors.white70, size: 20),
                color: VibraTheme.kSurface,
                onSelected: (value) async {
                  if (value == 'delete') {
                    final l10n = AppLocalizations.of(context)!;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: VibraTheme.kSurface,
                        title: Text(l10n.eliminarHistoria, style: const TextStyle(color: Colors.white)),
                        content: Text(
                            l10n.estaSeguro, style: const TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text(l10n.cancelar),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text(l10n.eliminar,
                                style: const TextStyle(color: VibraTheme.kError)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      await ref
                          .read(storyServiceProvider)
                          .deleteStory(_currentStory.id);
                      // Invalidate the stories list so the parent (navegar_screen,
                      // which watches storiesListProvider) drops the deleted
                      // story's avatar immediately. Mirrors create_story_screen.
                      ref.invalidate(storiesListProvider);
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  }
                },
                itemBuilder: (context) {
                  final userId = ref.read(authStateProvider).userId;
                  final isOwnStory = userId == _currentStory.userId;
                  return [
                    if (isOwnStory)
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: const Icon(Icons.delete, color: VibraTheme.kError, size: 20),
                          title: Text(AppLocalizations.of(context)!.eliminarHistoria,
                              style: const TextStyle(color: VibraTheme.kError)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ];
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
                    : const SizedBox.shrink(),
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
      '$_kMediaBase?key=$mediaKey&kind=story',
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

  /// Invoked once the underlying video controller has finished
  /// initializing, carrying the real media duration. The parent uses it to
  /// recalibrate the story progress timer.
  final ValueChanged<Duration>? onLoaded;

  const _VideoStory({
    required this.mediaKey,
    this.onLoaded,
  });

  @override
  State<_VideoStory> createState() => _VideoStoryState();
}

class _VideoStoryState extends State<_VideoStory> {
  VideoPlayerController? _controller;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final url =
        '$_kMediaBase?key=${widget.mediaKey}&kind=story';
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
      if (!mounted) return;
      setState(() => _loaded = true);
      // Report the real duration to the parent so the progress bar can be
      // recalibrated. Read from the controller value for accuracy.
      final dur = controller.value.duration;
      if (dur > Duration.zero) {
        widget.onLoaded?.call(dur);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
      // On error the parent keeps the 15s fallback — no callback fired.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Icon(Icons.videocam_off, color: Colors.white54, size: 64),
      );
    }
    final controller = _controller;
    if (!_loaded || controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }
}
