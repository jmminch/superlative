import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../bin/content_provider.dart';
import '../bin/protocol.dart';
import '../bin/superlatives_game.dart';
import '../bin/superlatives_server.dart';

class _TestWebSocketSink implements WebSocketSink {
  final List<dynamic> sent = [];
  final Completer<void> _done = Completer<void>();

  int? closeCode;

  String? closeReason;

  bool get closed => _done.isCompleted;

  @override
  void add(dynamic data) {
    sent.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (var item in stream) {
      add(item);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    this.closeCode = closeCode;
    this.closeReason = closeReason;
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> get done => _done.future;
}

class _TestWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> _inbound =
      StreamController<dynamic>.broadcast();
  final _TestWebSocketSink _sink = _TestWebSocketSink();

  @override
  Stream<dynamic> get stream => _inbound.stream;

  @override
  WebSocketSink get sink => _sink;

  _TestWebSocketSink get testSink => _sink;

  @override
  int? get closeCode => _sink.closeCode;

  @override
  String? get closeReason => _sink.closeReason;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  Future<void> dispose() async {
    await _inbound.close();
  }
}

YamlContentProvider _provider() {
  return YamlContentProvider.fromYamlString('''
categories:
  - id: animals
    label: Animals
    superlatives:
      - Cutest
      - Loudest
      - Fastest
      - Most chaotic
  - id: foods
    label: Foods
    superlatives:
      - Tastiest
      - Messiest
      - Spiciest
      - Crunchiest
''');
}

Map<String, dynamic> _decodeEnvelope(dynamic raw) {
  return jsonDecode(raw as String) as Map<String, dynamic>;
}

void main() {
  group('RoomRuntime', () {
    test('supports multiplayer start and vote progression', () {
      var room = RoomRuntime(
        roomCode: 'TEST1',
        contentProvider: _provider(),
        random: Random(1234),
      );

      var p1 = _TestWebSocketChannel();
      var p2 = _TestWebSocketChannel();
      var p3 = _TestWebSocketChannel();
      var d1 = _TestWebSocketChannel();

      var l1 = room.loginPlayer(displayName: 'alpha', socket: p1);
      var l2 = room.loginPlayer(displayName: 'beta', socket: p2);
      var l3 = room.loginPlayer(displayName: 'delta', socket: p3);
      var ld = room.loginDisplay(socket: d1);

      expect(l1.ok, isTrue);
      expect(l2.ok, isTrue);
      expect(l3.ok, isTrue);
      expect(ld.ok, isTrue);

      var hostId = l1.playerId!;
      var p2Id = l2.playerId!;
      var p3Id = l3.playerId!;
      var d1Id = ld.playerId!;

      expect(room.handleEvent(playerId: hostId, event: const StartGameEvent()),
          isTrue);
      expect(room.stateMachine.snapshot.phase.phase, 'RoundIntro');

      expect(room.handleEvent(playerId: hostId, event: const AdvanceEvent()),
          isTrue);
      expect(room.stateMachine.snapshot.phase.phase, 'EntryInput');

      expect(
        room.handleEvent(
            playerId: hostId, event: const SubmitEntryEvent('RACCOON')),
        isTrue,
      );
      expect(
        room.handleEvent(
            playerId: p2Id, event: const SubmitEntryEvent('STUFF')),
        isTrue,
      );
      expect(
        room.handleEvent(
            playerId: p3Id, event: const SubmitEntryEvent('THINGS')),
        isTrue,
      );

      expect(room.stateMachine.snapshot.phase.phase, 'VoteInput');

      var round = room.stateMachine.snapshot.currentGame!.rounds.last;
      var p3Entry = round.entries.firstWhere((e) => e.ownerPlayerId == p3Id);

      expect(
        room.handleEvent(
            playerId: hostId, event: SubmitVoteEvent(p3Entry.entryId)),
        isTrue,
      );
      expect(
        room.handleEvent(
            playerId: p2Id, event: SubmitVoteEvent(p3Entry.entryId)),
        isTrue,
      );
      expect(
        room.handleEvent(
            playerId: p3Id, event: SubmitVoteEvent(p3Entry.entryId)),
        isTrue,
      );

      expect(room.stateMachine.snapshot.phase.phase, 'VoteReveal');
      expect(room.stateMachine.snapshot.currentGame!.scoreboard[p3Id], 1000);

      // Broadcast happened for all connected sessions, including display.
      expect(p1.testSink.sent.isNotEmpty, isTrue);
      expect(d1.testSink.sent.isNotEmpty, isTrue);

      // Display payload should be role-scoped and not include private flags.
      var displayLast = _decodeEnvelope(d1.testSink.sent.last);
      expect(displayLast['event'], 'state');
      var displayPayload = displayLast['payload'] as Map<String, dynamic>;
      expect(displayPayload['role'], 'display');
      expect(displayPayload.containsKey('youVoted'), isFalse);

      // Player payload should include player role and private flags during vote input.
      var playerLast = _decodeEnvelope(p1.testSink.sent.last);
      expect(playerLast['event'], 'state');
      var playerPayload = playerLast['payload'] as Map<String, dynamic>;
      expect(playerPayload['role'], 'player');

      // Non-host advance should be rejected.
      expect(room.handleEvent(playerId: p2Id, event: const AdvanceEvent()),
          isFalse);

      // Display session cannot start game.
      expect(room.handleEvent(playerId: d1Id, event: const StartGameEvent()),
          isFalse);
    });

    test('duplicate player login disconnects prior socket', () {
      var room = RoomRuntime(
        roomCode: 'TEST1',
        contentProvider: _provider(),
        random: Random(42),
      );

      var first = _TestWebSocketChannel();
      var second = _TestWebSocketChannel();

      var login1 = room.loginPlayer(displayName: 'alpha', socket: first);
      expect(login1.ok, isTrue);

      var login2 = room.loginPlayer(displayName: 'alpha', socket: second);
      expect(login2.ok, isTrue);
      expect(login2.playerId, login1.playerId);

      expect(first.testSink.sent.isNotEmpty, isTrue);
      var disconnectMsg = _decodeEnvelope(first.testSink.sent.last);
      expect(disconnectMsg['event'], 'disconnect');
    });

    test('does not increment missed actions when entry phase timeout extends', () {
      var room = RoomRuntime(
        roomCode: 'TEST1',
        contentProvider: _provider(),
        random: Random(9),
      );

      var p1 = _TestWebSocketChannel();
      var p2 = _TestWebSocketChannel();
      var p3 = _TestWebSocketChannel();

      var l1 = room.loginPlayer(displayName: 'alpha', socket: p1);
      var l2 = room.loginPlayer(displayName: 'beta', socket: p2);
      var l3 = room.loginPlayer(displayName: 'delta', socket: p3);

      var hostId = l1.playerId!;
      var p2Id = l2.playerId!;
      var p3Id = l3.playerId!;

      expect(room.handleEvent(playerId: hostId, event: const StartGameEvent()),
          isTrue);
      expect(room.handleEvent(playerId: hostId, event: const AdvanceEvent()),
          isTrue);
      expect(room.stateMachine.snapshot.phase.phase, 'EntryInput');

      expect(
        room.handleEvent(
            playerId: hostId, event: const SubmitEntryEvent('RACCOON')),
        isTrue,
      );
      expect(
        room.handleEvent(playerId: p2Id, event: const SubmitEntryEvent('OTTER')),
        isTrue,
      );

      expect(room.processAutoTimeoutForCurrentPhase(), isTrue);
      expect(room.stateMachine.snapshot.phase.phase, 'EntryInput');
      expect(room.stateMachine.snapshot.players[p3Id]!.missedActions, 0);
    });

    test('force disconnects player after 3 consecutive missed actions', () {
      var room = RoomRuntime(
        roomCode: 'TEST1',
        contentProvider: _provider(),
        random: Random(5),
      );

      var p1 = _TestWebSocketChannel();
      var p2 = _TestWebSocketChannel();
      var p3 = _TestWebSocketChannel();

      var l1 = room.loginPlayer(displayName: 'alpha', socket: p1);
      var l2 = room.loginPlayer(displayName: 'beta', socket: p2);
      var l3 = room.loginPlayer(displayName: 'delta', socket: p3);

      var hostId = l1.playerId!;
      var p2Id = l2.playerId!;
      var p3Id = l3.playerId!;

      expect(room.handleEvent(playerId: hostId, event: const StartGameEvent()),
          isTrue);
      expect(room.handleEvent(playerId: hostId, event: const AdvanceEvent()),
          isTrue);
      expect(room.stateMachine.snapshot.phase.phase, 'EntryInput');

      // Two players submit; p3 misses.
      expect(
        room.handleEvent(
            playerId: hostId, event: const SubmitEntryEvent('RACCOON')),
        isTrue,
      );
      expect(
        room.handleEvent(
            playerId: p2Id, event: const SubmitEntryEvent('OTTER')),
        isTrue,
      );
      var phase = room.stateMachine.snapshot.phase as EntryInputPhase;
      expect(
        room.stateMachine.replaceCurrentPhase(
          EntryInputPhase(
            roundIndex: phase.roundIndex,
            roundId: phase.roundId,
            categoryLabel: phase.categoryLabel,
            superlatives: phase.superlatives,
            endsAt: DateTime.now(),
            earliestVoteAt: DateTime.now(),
            submittedPlayerIds: phase.submittedPlayerIds,
          ),
        ),
        isTrue,
      );
      expect(room.processAutoTimeoutForCurrentPhase(), isTrue);
      expect(room.stateMachine.snapshot.phase.phase, 'VoteInput');
      expect(room.stateMachine.snapshot.players[p3Id]!.missedActions, 1);

      var round = room.stateMachine.snapshot.currentGame!.rounds.last;
      var targetEntryId = round.entries.first.entryId;
      expect(
        room.handleEvent(
            playerId: hostId, event: SubmitVoteEvent(targetEntryId)),
        isTrue,
      );
      expect(
        room.handleEvent(playerId: p2Id, event: SubmitVoteEvent(targetEntryId)),
        isTrue,
      );
      expect(room.processAutoTimeoutForCurrentPhase(), isTrue);
      expect(room.stateMachine.snapshot.phase.phase, 'VoteReveal');
      expect(room.stateMachine.snapshot.players[p3Id]!.missedActions, 2);

      expect(room.handleEvent(playerId: hostId, event: const AdvanceEvent()),
          isTrue);
      expect(room.stateMachine.snapshot.phase.phase, 'VoteInput');
      expect(
        room.handleEvent(
            playerId: hostId, event: SubmitVoteEvent(targetEntryId)),
        isTrue,
      );
      expect(
        room.handleEvent(playerId: p2Id, event: SubmitVoteEvent(targetEntryId)),
        isTrue,
      );
      expect(room.processAutoTimeoutForCurrentPhase(), isTrue);

      // Third missed action disconnects p3.
      expect(
        room.stateMachine.snapshot.players[p3Id]!.state,
        PlayerSessionState.disconnected,
      );
      expect(room.connections.containsKey(p3Id), isFalse);

      // Player got an explicit disconnect event.
      expect(p3.testSink.sent.isNotEmpty, isTrue);
      var last = _decodeEnvelope(p3.testSink.sent.last);
      expect(last['event'], 'disconnect');
    });
  });
}
