import 'dart:convert';
import 'dart:math';

import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../bin/content_provider.dart';
import '../bin/protocol.dart';
import '../bin/superlatives_server.dart';

class _Sink implements WebSocketSink {
  final List<dynamic> sent = [];

  @override
  Future<void> addStream(Stream stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<void> get done async => Future.value();

  @override
  void add(dynamic data) {
    sent.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
}

class _Channel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final _Sink _sink = _Sink();
  final Stream<dynamic> _stream = const Stream.empty();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  WebSocketSink get sink => _sink;

  _Sink get testSink => _sink;

  @override
  Stream get stream => _stream;

  @override
  Future<void> get ready async => Future.value();
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
  - id: foods
    label: Foods
    superlatives:
      - Tastiest
      - Messiest
      - Spiciest
  - id: movies
    label: Movies
    superlatives:
      - Best ending
      - Most quotable
      - Most rewatchable
''');
}

void _submitRound(RoomRuntime room, String p1, String p2, String p3) {
  expect(room.handleEvent(playerId: p1, event: const AdvanceEvent()), isTrue);
  expect(room.stateMachine.snapshot.phase.phase, 'EntryInput');

  expect(room.handleEvent(playerId: p1, event: const SubmitEntryEvent('A1')),
      isTrue);
  expect(room.handleEvent(playerId: p2, event: const SubmitEntryEvent('B1')),
      isTrue);
  expect(room.handleEvent(playerId: p3, event: const SubmitEntryEvent('C1')),
      isTrue);

  // Integration tests bypass timer wait and move to voting directly.
  expect(room.stateMachine.onEntryTimeout(), isTrue);
  room.broadcastState();
  expect(room.stateMachine.snapshot.phase.phase, 'VoteInput');

  for (var i = 0; i < 3; i++) {
    var round = room.stateMachine.snapshot.currentGame!.rounds.last;
    var p3Entry = round.entries.firstWhere((e) => e.ownerPlayerId == p3);
    expect(
        room.handleEvent(playerId: p1, event: SubmitVoteEvent(p3Entry.entryId)),
        isTrue);
    expect(
        room.handleEvent(playerId: p2, event: SubmitVoteEvent(p3Entry.entryId)),
        isTrue);
    expect(
        room.handleEvent(playerId: p3, event: SubmitVoteEvent(p3Entry.entryId)),
        isTrue);

    expect(room.stateMachine.snapshot.phase.phase, 'VoteReveal');
    expect(room.handleEvent(playerId: p1, event: const AdvanceEvent()), isTrue);
  }

  expect(room.stateMachine.snapshot.phase.phase, 'RoundSummary');
}

void main() {
  test('integration: complete game lifecycle through final summary', () {
    var room = RoomRuntime(
      roomCode: 'I1',
      contentProvider: _provider(),
      random: Random(2),
    );

    var c1 = _Channel();
    var c2 = _Channel();
    var c3 = _Channel();
    var d1 = _Channel();

    var l1 = room.loginPlayer(displayName: 'alpha', socket: c1);
    var l2 = room.loginPlayer(displayName: 'beta', socket: c2);
    var l3 = room.loginPlayer(displayName: 'delta', socket: c3);
    var ld = room.loginDisplay(socket: d1);

    expect(l1.ok, isTrue);
    expect(l2.ok, isTrue);
    expect(l3.ok, isTrue);
    expect(ld.ok, isTrue);

    var p1 = l1.playerId!;
    var p2 = l2.playerId!;
    var p3 = l3.playerId!;

    expect(
        room.handleEvent(playerId: p1, event: const StartGameEvent()), isTrue);
    expect(room.stateMachine.snapshot.phase.phase, 'RoundIntro');

    _submitRound(room, p1, p2, p3);
    expect(room.handleEvent(playerId: p1, event: const AdvanceEvent()), isTrue);

    _submitRound(room, p1, p2, p3);
    expect(room.handleEvent(playerId: p1, event: const AdvanceEvent()), isTrue);

    _submitRound(room, p1, p2, p3);
    expect(room.handleEvent(playerId: p1, event: const AdvanceEvent()), isTrue);

    expect(room.stateMachine.snapshot.phase.phase, 'GameSummary');

    var score = room.stateMachine.snapshot.currentGame!.scoreboard[p3];
    expect(score, 9000);

    // Display receives state envelopes.
    expect(d1.testSink.sent.isNotEmpty, isTrue);
    var last =
        jsonDecode(d1.testSink.sent.last as String) as Map<String, dynamic>;
    expect(last['event'], 'state');
    expect((last['payload'] as Map<String, dynamic>)['role'], 'display');
  });
}
