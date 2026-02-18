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
      - Most chaotic
      - Smartest
      - Sleepiest
      - Bravest
      - Most social
      - Most curious
  - id: foods
    label: Foods
    superlatives:
      - Tastiest
      - Messiest
      - Spiciest
      - Crunchiest
      - Sweetest
      - Healthiest
      - Least healthy
      - Best road trip snack
      - Most comforting
  - id: movies
    label: Movies
    superlatives:
      - Best ending
      - Most quotable
      - Most rewatchable
      - Funniest
      - Scariest
      - Most action-packed
      - Most mindless
      - Most interesting
      - Least interesting
''');
}

Map<String, dynamic> _decode(dynamic raw) {
  return jsonDecode(raw as String) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _statePayloads(_Sink sink) {
  return sink.sent
      .map(_decode)
      .where((e) => e['event'] == 'state')
      .map((e) => e['payload'] as Map<String, dynamic>)
      .toList(growable: false);
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

  expect(room.stateMachine.snapshot.phase.phase, 'VoteInput');

  var config = room.stateMachine.snapshot.config;
  for (var setIndex = 0; setIndex < config.setCount; setIndex++) {
    for (var promptIndex = 0;
        promptIndex < config.promptsPerSet;
        promptIndex++) {
      var round = room.stateMachine.snapshot.currentGame!.rounds.last;
      var p3Entry = round.entries.firstWhere((e) => e.ownerPlayerId == p3);
      expect(
          room.handleEvent(
              playerId: p1, event: SubmitVoteEvent(p3Entry.entryId)),
          isTrue);
      expect(
          room.handleEvent(
              playerId: p2, event: SubmitVoteEvent(p3Entry.entryId)),
          isTrue);
      expect(
          room.handleEvent(
              playerId: p3, event: SubmitVoteEvent(p3Entry.entryId)),
          isTrue);
      if (promptIndex < config.promptsPerSet - 1) {
        expect(room.stateMachine.snapshot.phase.phase, 'VoteInput');
      }
    }

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
    expect(room.stateMachine.snapshot.phase.phase, 'GameStarting');
    expect(room.handleEvent(playerId: p1, event: const AdvanceEvent()), isTrue);
    expect(room.stateMachine.snapshot.phase.phase, 'RoundIntro');

    _submitRound(room, p1, p2, p3);
    var roundScore =
        room.stateMachine.snapshot.currentGame!.scoreboard[p3] ?? 0;
    expect(roundScore, 0);
    var pointsAfterRound1 = room.stateMachine.snapshot.currentGame!.rounds.last
            .roundPointsByPlayerPending[p3] ??
        0;
    expect(pointsAfterRound1, 0);
    var roundSummaryPayloadsAfterR1 = _statePayloads(c1.testSink)
        .where((p) => p['phase'] == 'RoundSummary')
        .toList();
    expect(roundSummaryPayloadsAfterR1.isNotEmpty, isTrue);
    var roundSummary1 = roundSummaryPayloadsAfterR1.last;
    var superlativeResults1 =
        roundSummary1['roundSummary']['superlativeResults'] as List<dynamic>;
    expect(superlativeResults1.isNotEmpty, isTrue);
    for (var result in superlativeResults1) {
      var topEntries = result['topEntries'] as List<dynamic>;
      expect(topEntries.length <= 3, isTrue);
      for (var row in topEntries) {
        expect(row['voteCount'] > 0, isTrue);
        expect(row['entryText'], isNotEmpty);
        expect(row['ownerDisplayName'], isNotEmpty);
      }
    }
    expect(room.handleEvent(playerId: p1, event: const AdvanceEvent()), isTrue);
    var scoreAfterRound1Advance =
        room.stateMachine.snapshot.currentGame!.scoreboard[p3] ?? 0;
    var config = room.stateMachine.snapshot.config;
    expect(
        scoreAfterRound1Advance, config.setCount * config.promptsPerSet * 1000);

    _submitRound(room, p1, p2, p3);
    expect(room.handleEvent(playerId: p1, event: const AdvanceEvent()), isTrue);

    _submitRound(room, p1, p2, p3);
    expect(room.handleEvent(playerId: p1, event: const AdvanceEvent()), isTrue);

    expect(room.stateMachine.snapshot.phase.phase, 'GameSummary');

    var score = room.stateMachine.snapshot.currentGame!.scoreboard[p3];
    var expectedScore =
        config.roundCount * config.setCount * config.promptsPerSet * 1000;
    expect(score, expectedScore);

    // Display receives state envelopes.
    expect(d1.testSink.sent.isNotEmpty, isTrue);
    var last = _decode(d1.testSink.sent.last);
    expect(last['event'], 'state');
    expect((last['payload'] as Map<String, dynamic>)['role'], 'display');
  });
}
