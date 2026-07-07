import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../l10n/gen/app_localizations.dart';
import '../theme/app_theme.dart';
import 'call_service.dart';

/// Full-screen call screen: incoming call overlay OR active call UI.
///
/// Route param [conversationId] is required. When [incomingCall] is provided
/// the screen starts in "ringing" mode with Accept / Reject buttons;
/// otherwise it starts an outgoing call immediately.
class CallScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final IncomingCall? incomingCall;

  const CallScreen({
    super.key,
    required this.conversationId,
    this.incomingCall,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  CallState _callState = CallState.idle;
  StreamSubscription<CallState>? _stateSub;

  // Audio toggles
  bool _muted = false;
  bool _speakerOn = true;

  // Duration
  Stopwatch _stopwatch = Stopwatch();
  Timer? _durationTimer;
  String _duration = '00:00';
  // Ringtone/vibration for incoming calls
  Timer? _ringtoneTimer;

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  @override
  void dispose() {
    final callService = ref.read(callServiceProvider);
    _ringtoneTimer?.cancel();
    if (callService.isActive) {
      callService.endCall();
    }
    _stateSub?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  Future<void> _initCall() async {
    final callService = ref.read(callServiceProvider);

    // Listen for state changes.
    _stateSub = callService.callStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _callState = state;
        if (state == CallState.connected) {
          _startTimer();
          _ringtoneTimer?.cancel();
        } else if (state == CallState.ended) {
          _stopTimer();
          _ringtoneTimer?.cancel();
        }
      });
      // Pop when call ends.
      if (state == CallState.ended) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });

    if (widget.incomingCall != null) {
      // Incoming call — show ringing UI + vibration.
      setState(() => _callState = CallState.ringing);
      _ringtoneTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
        if (mounted) HapticFeedback.heavyImpact();
      });
    } else {
      // Outgoing call.
      try {
        await callService.startCall(widget.conversationId);
        if (mounted) {
          setState(() => _callState = CallState.calling);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to start call: $e')),
          );
          Navigator.of(context).pop();
        }
      }
    }
  }

  void _startTimer() {
    _stopwatch = Stopwatch()..start();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = _stopwatch.elapsed;
      final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
      setState(() => _duration = '$minutes:$seconds');
    });
  }

  void _stopTimer() {
    _stopwatch.stop();
    _durationTimer?.cancel();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _acceptCall() async {
    if (widget.incomingCall == null) return;
    final callService = ref.read(callServiceProvider);
    try {
      await callService.acceptCall(
        widget.conversationId,
        widget.incomingCall!.sdp,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept call: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _rejectCall() async {
    final callService = ref.read(callServiceProvider);
    await callService.rejectCall();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _hangup() async {
    final callService = ref.read(callServiceProvider);
    await callService.endCall();
  }

  void _toggleMute() {
    final callService = ref.read(callServiceProvider);
    final localStream = callService.localStream;
    if (localStream != null) {
      for (final track in localStream.getAudioTracks()) {
        track.enabled = !track.enabled;
      }
    }
    setState(() => _muted = !_muted);
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    Helper.setSpeakerphoneOn(_speakerOn);
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_callState == CallState.ended) {
      return _buildEndedScreen(l10n);
    }

    if (_callState == CallState.ringing && widget.incomingCall != null) {
      return _buildIncomingScreen(l10n);
    }

    return _buildActiveScreen(l10n);
  }

  /// Incoming call screen with Accept / Reject.
  Widget _buildIncomingScreen(AppLocalizations? l10n) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            // Caller avatar placeholder
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: VibraTheme.kSurfaceElevated,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                size: 48,
                color: VibraTheme.kTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.incomingCall?.callerName ?? 'Caller',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n?.callIncoming ?? 'Incoming call…',
              style: const TextStyle(
                color: VibraTheme.kTextSecondary,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            // Action buttons
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Reject
                  _ActionButton(
                    icon: Icons.call_end,
                    color: VibraTheme.kError,
                    label: l10n?.callReject ?? 'Reject',
                    onTap: _rejectCall,
                  ),
                  const SizedBox(width: 64),
                  // Accept
                  _ActionButton(
                    icon: Icons.call,
                    color: VibraTheme.kSuccess,
                    label: l10n?.callAccept ?? 'Accept',
                    onTap: _acceptCall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Active call (connected) or calling (outgoing, waiting for answer).
  Widget _buildActiveScreen(AppLocalizations? l10n) {
    final callService = ref.read(callServiceProvider);
    final isCalling = _callState == CallState.calling;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote video (full background) or avatar placeholder
            if (callService.remoteRenderer.srcObject != null)
              Positioned.fill(
                child: RTCVideoView(
                  callService.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            else
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      color: VibraTheme.kSurfaceElevated,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 64,
                      color: VibraTheme.kTextSecondary,
                    ),
                  ),
                ),
              ),

            // Local video (PiP top-right)
            if (!isCalling &&
                callService.localRenderer.srcObject != null)
              Positioned(
                top: 60,
                right: 16,
                width: 120,
                height: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(
                    callService.localRenderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),

            // Status label at top center
            if (isCalling)
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Text(
                  l10n?.callOutgoing ?? 'Calling…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            // Duration (when connected)
            if (!isCalling)
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Text(
                  _duration,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),

            // Bottom controls
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Mute
                  _ActionButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    color:
                        _muted ? Colors.redAccent : Colors.white.withValues(alpha: 0.8),
                    label: _muted ? (l10n?.callUnmute ?? 'Unmute') : (l10n?.callMute ?? 'Mute'),
                    size: 20,
                    onTap: _toggleMute,
                  ),
                  if (!isCalling) ...[
                    const SizedBox(width: 32),
                    // Speaker
                    _ActionButton(
                      icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                      color: Colors.white.withValues(alpha: 0.8),
                      label: _speakerOn ? (l10n?.callSpeaker ?? 'Speaker') : (l10n?.callEarpiece ?? 'Earpiece'),
                      size: 20,
                      onTap: _toggleSpeaker,
                    ),
                  ],
                  const SizedBox(width: 32),
                  // Hangup
                  _ActionButton(
                    icon: Icons.call_end,
                    color: VibraTheme.kError,
                    label: l10n?.callHangup ?? 'Hang up',
                    onTap: _hangup,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Call ended screen shown briefly before popping.
  Widget _buildEndedScreen(AppLocalizations? l10n) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.call_end, color: VibraTheme.kTextMuted, size: 48),
            const SizedBox(height: 16),
            Text(
              l10n?.callEnded ?? 'Call ended',
              style: const TextStyle(
                color: VibraTheme.kTextSecondary,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action button widget
// ─────────────────────────────────────────────────────────────────────────────

/// Circular action button with icon and label below.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final double size;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    this.size = 28,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: size),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
