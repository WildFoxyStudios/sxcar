import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat/chat_service.dart';

// ---------------------------------------------------------------------------
// Call state
// ---------------------------------------------------------------------------

/// Possible states of a WebRTC call.
enum CallState {
  /// No call active.
  idle,

  /// Outgoing call: offer sent, waiting for answer.
  calling,

  /// Incoming call: received call_start, ringing.
  ringing,

  /// Call is connected (media flowing).
  connected,

  /// Call ended (cleanup done).
  ended,
}

// ---------------------------------------------------------------------------
// Incoming call notification
// ---------------------------------------------------------------------------

/// Payload delivered via the [onIncomingCall] stream when a peer calls us.
class IncomingCall {
  final String conversationId;
  final String callerId;
  final String? callerName;
  final String sdp;
  final bool video;

  const IncomingCall({
    required this.conversationId,
    required this.callerId,
    this.callerName,
    required this.sdp,
    this.video = false,
  });
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final callServiceProvider = Provider<CallService>((ref) {
  final chatService = ref.watch(chatServiceProvider);
  final service = CallService(chatService);
  ref.onDispose(() => service.dispose());
  return service;
});

// ---------------------------------------------------------------------------
// CallService
// ---------------------------------------------------------------------------

/// Manages a single P2P WebRTC call over the existing chat WebSocket.
///
/// All signaling messages (call_start, call_answer, ice_candidate, call_end)
/// are sent via [ChatService.sendViaWebSocket] and received through
/// [ChatService.messageStream].
class CallService {
  final ChatService _chatService;

  // ── PeerConnection ──────────────────────────────────────────────────────
  RTCPeerConnection? _peerConnection;

  /// Exposed for mute/unmute and speaker routing.
  MediaStream? _localStream;
  MediaStream? get localStream => _localStream;

  // ── Renderers ───────────────────────────────────────────────────────────
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  RTCVideoRenderer get remoteRenderer => _remoteRenderer;
  RTCVideoRenderer get localRenderer => _localRenderer;

  // ── State ───────────────────────────────────────────────────────────────
  CallState _state = CallState.idle;
  String? _currentConversationId;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  /// Stream of [CallState] changes.
  final _stateController = StreamController<CallState>.broadcast();
  Stream<CallState> get callStateStream => _stateController.stream;

  /// Stream of incoming call events.
  final _incomingController = StreamController<IncomingCall>.broadcast();
  Stream<IncomingCall> get onIncomingCall => _incomingController.stream;

  /// Whether a call is currently active or ringing.
  bool get isActive => _state != CallState.idle && _state != CallState.ended;

  CallState get state => _state;

  CallService(this._chatService) {
    _initRenderers();
    _listenWs();
  }

  // ── Initialization ──────────────────────────────────────────────────────

  Future<void> _initRenderers() async {
    try {
      await _remoteRenderer.initialize();
      await _localRenderer.initialize();
    } catch (_) {
      // Test environments without platform channels: renderers stay inert.
    }
  }

  /// Start listening to the chat WS for signaling messages.
  void _listenWs() {
    _wsSub = _chatService.messageStream.listen((json) {
      final type = json['type'] as String?;
      final convId = json['conversation_id'] as String?;
      if (convId == null) return;

      switch (type) {
        case 'call_start':
          _onCallStart(json, convId);
          break;
        case 'call_answer':
          _onCallAnswer(json);
          break;
        case 'ice_candidate':
          _onIceCandidate(json);
          break;
        case 'call_end':
          _onCallEnd(json, convId);
          break;
      }
    });
  }

  // ── Factory helpers ─────────────────────────────────────────────────────

  /// Create an RTCPeerConfiguration with free Google STUN.
  static Map<String, dynamic> _stunConfig() => {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      };

  /// Get local media stream (mic, optionally camera).
  Future<MediaStream> _getLocalMedia({bool video = false}) async {
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': video,
    };
    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    return stream;
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Start an outgoing call in [conversationId].
  ///
  /// Creates a peer connection, captures local media, creates an SDP offer,
  /// and sends it via the WebSocket relay.
  Future<void> startCall(String conversationId, {bool video = false}) async {
    if (isActive) return;

    _currentConversationId = conversationId;
    _updateState(CallState.calling);

    try {
      _localStream = await _getLocalMedia(video: video);
      await _localRenderer.setSrcObject(stream: _localStream!);

      _peerConnection = await _createPeerConnection();
      final localStream = _localStream!;
      localStream.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, localStream);
      });

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      _chatService.sendViaWebSocket({
        'type': 'call_start',
        'conversation_id': conversationId,
        'sdp': offer.sdp,
        'video': video,
      });
    } catch (e) {
      _updateState(CallState.ended);
      rethrow;
    }
  }

  /// Accept an incoming call: set remote SDP, create answer, send via WS.
  Future<void> acceptCall(String conversationId, String sdp,
      {bool video = false}) async {
    if (isActive) return;

    _currentConversationId = conversationId;

    try {
      _localStream = await _getLocalMedia(video: video);
      await _localRenderer.setSrcObject(stream: _localStream!);

      _peerConnection = await _createPeerConnection();
      final localStream = _localStream!;
      localStream.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, localStream);
      });

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, 'offer'),
      );

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      _chatService.sendViaWebSocket({
        'type': 'call_answer',
        'conversation_id': conversationId,
        'sdp': answer.sdp,
      });

      _updateState(CallState.connected);
    } catch (e) {
      _updateState(CallState.ended);
      rethrow;
    }
  }

  /// Set a remote SDP description on the active peer connection.
  Future<void> setRemoteSdp(String sdp) async {
    if (_peerConnection == null) return;
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, 'answer'),
    );
    _updateState(CallState.connected);
  }

  /// Add an ICE candidate received via signaling.
  Future<void> addIceCandidate(dynamic candidate) async {
    if (_peerConnection == null) return;
    try {
      await _peerConnection!.addCandidate(
        RTCIceCandidate(
          candidate['candidate'],
          candidate['sdpMid'],
          candidate['sdpMLineIndex'],
        ),
      );
    } catch (_) {
      // Ignore invalid candidates (common during call teardown).
    }
  }

  /// End the current call: close PC, release media, notify peer.
  Future<void> endCall() async {
    if (_state == CallState.idle) return;

    // Notify peer unless already ended.
    if (_currentConversationId != null && _state != CallState.ended) {
      _chatService.sendViaWebSocket({
        'type': 'call_end',
        'conversation_id': _currentConversationId,
      });
    }

    await _cleanup();
    _updateState(CallState.ended);
  }

  /// Reject an incoming call (end without answer).
  Future<void> rejectCall() async {
    if (_currentConversationId != null) {
      _chatService.sendViaWebSocket({
        'type': 'call_end',
        'conversation_id': _currentConversationId,
      });
    }
    await _cleanup();
    _updateState(CallState.ended);
  }

  // ── Internal message handlers ───────────────────────────────────────────

  void _onCallStart(Map<String, dynamic> json, String convId) {
    final sdp = json['sdp'] as String?;
    final callerId = json['user_id'] as String? ?? '';
    final video = json['video'] as bool? ?? false;
    if (sdp == null) return;

    _currentConversationId = convId;
    _updateState(CallState.ringing);
    _incomingController.add(IncomingCall(
      conversationId: convId,
      callerId: callerId,
      sdp: sdp,
      video: video,
    ));
  }

  Future<void> _onCallAnswer(Map<String, dynamic> json) async {
    final sdp = json['sdp'] as String?;
    if (sdp == null) return;
    await setRemoteSdp(sdp);
  }

  Future<void> _onIceCandidate(Map<String, dynamic> json) async {
    final candidate = json['candidate'];
    if (candidate == null) return;
    await addIceCandidate(candidate);
  }

  void _onCallEnd(Map<String, dynamic> json, String convId) {
    if (_currentConversationId != convId) return;
    // Peer hung up — clean up and notify listeners.
    _cleanup();
    _updateState(CallState.ended);
  }

  // ── PeerConnection lifecycle ────────────────────────────────────────────

  Future<RTCPeerConnection> _createPeerConnection() async {
    final pc = await createPeerConnection(_stunConfig());

    pc.onIceCandidate = (candidate) {
      if (_currentConversationId == null) return;
      _chatService.sendViaWebSocket({
        'type': 'ice_candidate',
        'conversation_id': _currentConversationId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onTrack = (event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        _remoteRenderer.setSrcObject(stream: event.streams[0]);
      }
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _cleanup();
        _updateState(CallState.ended);
      }
    };

    return pc;
  }

  Future<void> _cleanup() async {
    _currentConversationId = null;
    try {
      await _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;

    try {
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) => track.stop());
        _localStream!.dispose();
      }
    } catch (_) {}
    _localStream = null;
  }

  void _updateState(CallState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  // ── Disposal ────────────────────────────────────────────────────────────

  void dispose() {
    _wsSub?.cancel();
    _cleanup();
    _remoteRenderer.dispose();
    _localRenderer.dispose();
    _stateController.close();
    _incomingController.close();
  }
}
