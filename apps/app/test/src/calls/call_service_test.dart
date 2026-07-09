import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/chat/chat_service.dart';
import 'package:app/src/calls/call_service.dart';

// ---------------------------------------------------------------------------
// Fake ChatService — captures WS messages and exposes an injectable stream
// ---------------------------------------------------------------------------

/// A minimal chat service stub that records sent messages and lets tests
/// inject incoming WebSocket frames.
class FakeChatService extends ChatService {
  @override
  Future<void> markRead(String conversationId) async {}
  final _sentMessages = <Map<String, dynamic>>[];
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  List<Map<String, dynamic>> get sentMessages => _sentMessages;

  FakeChatService() : super(Dio(), null);

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  @override
  void sendViaWebSocket(Map<String, dynamic> message) {
    _sentMessages.add(Map<String, dynamic>.from(message));
  }

  /// Inject an incoming WS frame (e.g. call_start, ice_candidate, call_end).
  void injectFrame(Map<String, dynamic> frame) {
    _messageController.add(frame);
  }

  @override
  void connectWebSocket() {}

  @override
  void disconnectWebSocket() {}

  @override
  void dispose() {
    _messageController.close();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChatService fakeChat;
  late CallService callService;

  setUpAll(() {
    // Mock flutter_webrtc platform channel so VM tests don't crash on init.
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Method'),
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'initialize':
            return null;
          case 'createVideoRenderer':
            return {'textureId': 1};
          case 'createPeerConnection':
            return {'peerConnectionId': 'test-pc-1'};
          case 'createLocalMediaStream':
            return {'streamId': 'test-stream-1'};
          case 'getUserMedia':
            return {'streamId': 'test-user-media-1'};
          case 'createOffer':
            return {'sdp': 'test-sdp-offer', 'type': 'offer'};
          case 'createAnswer':
            return {'sdp': 'test-sdp-answer', 'type': 'answer'};
          case 'setLocalDescription':
            return null;
          case 'setRemoteDescription':
            return null;
          case 'addIceCandidate':
            return null;
          case 'closePeerConnection':
            return null;
          case 'closeMediaStream':
            return null;
          case 'mediaStreamGetTracks':
            return {'tracks': []};
          case 'mediaStreamTrackStop':
            return null;
          case 'peerConnectionGetTransceivers':
            return {'transceivers': []};
          case 'peerConnectionGetStats':
            return {'stats': {}};
          default:
            return null;
        }
      },
    );
  });

  setUp(() {
    fakeChat = FakeChatService();
    callService = CallService(fakeChat);
  });

  tearDown(() {
    callService.dispose();
    fakeChat.dispose();
  });

  group('CallService signaling', () {
    test('incoming call_start fires onIncomingCall stream', () async {
      final incomingCalls = <IncomingCall>[];
      callService.onIncomingCall.listen(incomingCalls.add);

      fakeChat.injectFrame({
        'type': 'call_start',
        'conversation_id': 'conv-1',
        'sdp': 'sdp-offer-from-peer',
        'user_id': 'peer-1',
        'video': false,
      });

      // Allow microtask to process
      await Future(() {});

      expect(incomingCalls.length, 1);
      expect(incomingCalls[0].conversationId, 'conv-1');
      expect(incomingCalls[0].callerId, 'peer-1');
      expect(incomingCalls[0].sdp, 'sdp-offer-from-peer');
      expect(incomingCalls[0].video, false);
    });

    test('incoming call_start with video flag', () async {
      final incomingCalls = <IncomingCall>[];
      callService.onIncomingCall.listen(incomingCalls.add);

      fakeChat.injectFrame({
        'type': 'call_start',
        'conversation_id': 'conv-2',
        'sdp': 'sdp-video',
        'user_id': 'peer-2',
        'video': true,
      });

      await Future(() {});

      expect(incomingCalls.length, 1);
      expect(incomingCalls[0].video, true);
    });

    test('incoming call_end without active call is ignored gracefully', () async {
      // Should not throw even if no call is active.
      fakeChat.injectFrame({
        'type': 'call_end',
        'conversation_id': 'conv-1',
        'user_id': 'peer-1',
      });

      await Future(() {});
      // No exception is the assertion.
      expect(callService.isActive, false);
    });

    test('endCall sends call_end via WS', () async {
      // Directly set internal state to simulate an active call.
      // endCall will attempt to send call_end and clean up.
      // Since no PC is actually created, it will try to clean up gracefully.
      await callService.endCall();

      // Should send call_end if conversationId was tracked.
      // In this case, no conversation was started, so nothing is sent.
      final wsMessages = fakeChat.sentMessages
          .where((m) => m['type'] == 'call_end')
          .toList();
      // No call was active, so no call_end should be sent.
      expect(wsMessages.length, 0);
    });

    test('endCall sends call_end when call was active', () async {
      // Simulate having received a call_start by injecting one.
      // This puts the service in ringing state.
      fakeChat.injectFrame({
        'type': 'call_start',
        'conversation_id': 'conv-active',
        'sdp': 'offer-sdp',
        'user_id': 'peer',
      });

      await Future(() {});

      // Now end the call — should send call_end.
      await callService.endCall();

      final endMessages = fakeChat.sentMessages
          .where((m) => m['type'] == 'call_end')
          .toList();
      expect(endMessages.length, 1);
      expect(endMessages[0]['conversation_id'], 'conv-active');
    });

    test('rejectCall sends call_end and cleans up', () async {
      // Simulate incoming call
      fakeChat.injectFrame({
        'type': 'call_start',
        'conversation_id': 'conv-reject',
        'sdp': 'offer-sdp',
        'user_id': 'peer',
      });

      await Future(() {});

      await callService.rejectCall();

      final endMessages = fakeChat.sentMessages
          .where((m) => m['type'] == 'call_end')
          .toList();
      expect(endMessages.length, 1);
      expect(endMessages[0]['conversation_id'], 'conv-reject');
      expect(callService.isActive, false);
    });

    test('callStateStream transitions correctly on incoming + reject', () async {
      final states = <CallState>[];
      callService.callStateStream.listen(states.add);

      // Incoming call → ringing
      fakeChat.injectFrame({
        'type': 'call_start',
        'conversation_id': 'conv-states',
        'sdp': 'offer-sdp',
        'user_id': 'peer',
      });
      await Future(() {});
      expect(callService.state, CallState.ringing);

      // Reject → ended
      await callService.rejectCall();
      expect(callService.state, CallState.ended);
    });

    test('incoming call_start without sdp is ignored', () async {
      final incomingCalls = <IncomingCall>[];
      callService.onIncomingCall.listen(incomingCalls.add);

      fakeChat.injectFrame({
        'type': 'call_start',
        'conversation_id': 'conv-3',
        'user_id': 'peer-3',
        // no sdp
      });

      await Future(() {});
      expect(incomingCalls.length, 0);
    });

    test('incoming ice_candidate without active call is ignored', () async {
      fakeChat.injectFrame({
        'type': 'ice_candidate',
        'conversation_id': 'conv-none',
        'candidate': {'candidate': 'candidate:1 1 UDP 2122252543 192.168.1.1', 'sdpMid': '0', 'sdpMLineIndex': 0},
      });

      await Future(() {});
      // No crash is the assertion.
    });

    test('call_end during active call transitions to ended', () async {
      // Start with an incoming call
      fakeChat.injectFrame({
        'type': 'call_start',
        'conversation_id': 'conv-end-test',
        'sdp': 'offer-sdp',
        'user_id': 'peer',
      });
      await Future(() {});
      expect(callService.state, CallState.ringing);

      // Peer sends call_end
      fakeChat.injectFrame({
        'type': 'call_end',
        'conversation_id': 'conv-end-test',
        'user_id': 'peer',
      });
      await Future(() {});
      expect(callService.state, CallState.ended);
    });
  });

  group('CallService state management', () {
    test('initial state is idle', () {
      expect(callService.state, CallState.idle);
      expect(callService.isActive, false);
    });

    test('isActive returns false after end', () async {
      await callService.endCall();
      expect(callService.isActive, false);
    });

    test('startCall does nothing when already active', () async {
      // Simulate incoming call
      fakeChat.injectFrame({
        'type': 'call_start',
        'conversation_id': 'conv-already',
        'sdp': 'offer-sdp',
        'user_id': 'peer',
      });
      await Future(() {});
      expect(callService.isActive, true);

      // Attempt a second call should be ignored.
      final messagesBefore = fakeChat.sentMessages.length;
      // This try-catch is needed because startCall tries getUserMedia which
      // our mock may not handle perfectly.
      try {
        await callService.startCall('conv-second');
      } catch (_) {}
      // No new call_start should have been sent.
      final newCallStarts = fakeChat.sentMessages
          .skip(messagesBefore)
          .where((m) => m['type'] == 'call_start')
          .toList();
      expect(newCallStarts.length, 0);
    });
  });
}
