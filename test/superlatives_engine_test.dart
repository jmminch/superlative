import 'dart:math';

import 'package:test/test.dart';

import '../bin/superlatives_engine.dart';
import '../bin/superlatives_game.dart';
import '../bin/superlatives_state_machine.dart';

DateTime _now = DateTime.utc(2026, 2, 16, 12, 0, 0);

SuperlativesRoomSnapshot _baseSnapshot({
  RoomConfig config = const RoomConfig(minPlayersToStart: 2, roundCount: 3),
  Map<String, PlayerSession>? players,
}) {
  return SuperlativesRoomSnapshot(
    roomCode: 'ABCD',
    hostPlayerId: 'p1',
    config: config,
    players: players ??
        const {
          'p1': PlayerSession(
            playerId: 'p1',
            displayName: 'A',
            state: PlayerSessionState.active,
          ),
          'p2': PlayerSession(
            playerId: 'p2',
            displayName: 'B',
            state: PlayerSessionState.active,
          ),
        },
    currentGame: null,
    phase: const LobbyPhase(),
    updatedAt: _now,
  );
}

List<SuperlativePrompt> _roundPrompts() {
  return const [
    SuperlativePrompt(superlativeId: 's1', promptText: 'Cutest'),
    SuperlativePrompt(superlativeId: 's2', promptText: 'Bravest'),
    SuperlativePrompt(superlativeId: 's3', promptText: 'Most chaotic'),
  ];
}

void _playRoundToSummary(GameEngine engine) {
  expect(engine.openEntryInput(), isTrue);
  expect(engine.submitEntry(playerId: 'p1', text: 'RACCOON'), isTrue);
  expect(engine.submitEntry(playerId: 'p2', text: 'OTTER'), isTrue);

  for (var i = 0; i < 3; i++) {
    expect(engine.snapshot.phase, isA<VoteInputPhase>());
    var round = engine.snapshot.currentGame!.rounds.last;
    var entryP1 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p1');

    expect(engine.submitVote(playerId: 'p1', entryId: entryP1.entryId), isTrue);
    expect(engine.submitVote(playerId: 'p2', entryId: entryP1.entryId), isTrue);

    expect(engine.closeVotePhase(), isTrue);
    expect(engine.snapshot.phase, isA<VoteRevealPhase>());
    expect(engine.closeReveal(), isTrue);
  }

  expect(engine.snapshot.phase, isA<RoundSummaryPhase>());
}

void main() {
  group('GameEngine progression', () {
    test('plays 3 rounds and reaches game summary', () {
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(),
        now: () => _now,
      );
      var engine = GameEngine(
        stateMachine: machine,
        random: Random(1234),
        now: () => _now,
      );

      expect(
        engine.startGame(
          hostPlayerId: 'p1',
          firstRoundCategoryId: 'animals',
          firstRoundCategoryLabel: 'Animals',
          firstRoundSuperlatives: _roundPrompts(),
          roundIntroEndsAt: _now.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );

      _playRoundToSummary(engine);

      expect(
        engine.completeRound(
          nextCategoryId: 'foods',
          nextCategoryLabel: 'Foods',
          nextRoundSuperlatives: _roundPrompts(),
          nextRoundIntroEndsAt: _now.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );

      _playRoundToSummary(engine);

      expect(
        engine.completeRound(
          nextCategoryId: 'movies',
          nextCategoryLabel: 'Movies',
          nextRoundSuperlatives: _roundPrompts(),
          nextRoundIntroEndsAt: _now.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );

      _playRoundToSummary(engine);

      expect(engine.completeRound(), isTrue);
      expect(engine.snapshot.phase, isA<GameSummaryPhase>());
      expect(engine.snapshot.currentGame!.rounds.length, 3);
    });
  });

  group('Pending player policy', () {
    test('pending player joins at next round, not mid-round', () {
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(),
        now: () => _now,
      );
      var engine = GameEngine(
        stateMachine: machine,
        random: Random(1),
        now: () => _now,
      );

      expect(
        engine.startGame(
          hostPlayerId: 'p1',
          firstRoundCategoryId: 'animals',
          firstRoundCategoryLabel: 'Animals',
          firstRoundSuperlatives: _roundPrompts(),
        ),
        isTrue,
      );

      var playersMidRound =
          Map<String, PlayerSession>.from(engine.snapshot.players)
            ..['p3'] = const PlayerSession(
              playerId: 'p3',
              displayName: 'C',
              state: PlayerSessionState.pending,
            );
      machine.snapshot = engine.snapshot.copyWith(players: playersMidRound);

      expect(engine.openEntryInput(), isTrue);
      expect(engine.submitEntry(playerId: 'p1', text: 'RACCOON'), isTrue);
      expect(engine.submitEntry(playerId: 'p2', text: 'OTTER'), isTrue);
      expect(engine.submitEntry(playerId: 'p3', text: 'PANDA'), isFalse);

      // Finish round quickly.
      for (var i = 0; i < 3; i++) {
        var round = engine.snapshot.currentGame!.rounds.last;
        var entryP1 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p1');
        expect(engine.submitVote(playerId: 'p1', entryId: entryP1.entryId),
            isTrue);
        expect(engine.submitVote(playerId: 'p2', entryId: entryP1.entryId),
            isTrue);
        expect(engine.closeVotePhase(), isTrue);
        expect(engine.closeReveal(), isTrue);
      }

      expect(engine.snapshot.players['p3']!.state, PlayerSessionState.pending);

      expect(
        engine.completeRound(
          nextCategoryId: 'foods',
          nextCategoryLabel: 'Foods',
          nextRoundSuperlatives: _roundPrompts(),
        ),
        isTrue,
      );

      expect(engine.snapshot.players['p3']!.state, PlayerSessionState.active);
    });
  });

  group('Vote constraints', () {
    test('rejects vote for unknown entry', () {
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(),
        now: () => _now,
      );
      var engine = GameEngine(
        stateMachine: machine,
        random: Random(7),
        now: () => _now,
      );

      expect(
        engine.startGame(
          hostPlayerId: 'p1',
          firstRoundCategoryId: 'animals',
          firstRoundCategoryLabel: 'Animals',
          firstRoundSuperlatives: _roundPrompts(),
        ),
        isTrue,
      );
      expect(engine.openEntryInput(), isTrue);
      expect(engine.submitEntry(playerId: 'p1', text: 'RACCOON'), isTrue);
      expect(engine.submitEntry(playerId: 'p2', text: 'OTTER'), isTrue);

      expect(engine.submitVote(playerId: 'p1', entryId: 'missing'), isFalse);
    });

    test('rejects self vote when config disallows it', () {
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(
          config: const RoomConfig(
            minPlayersToStart: 2,
            allowSelfVote: false,
          ),
        ),
        now: () => _now,
      );
      var engine = GameEngine(
        stateMachine: machine,
        random: Random(9),
        now: () => _now,
      );

      expect(
        engine.startGame(
          hostPlayerId: 'p1',
          firstRoundCategoryId: 'animals',
          firstRoundCategoryLabel: 'Animals',
          firstRoundSuperlatives: _roundPrompts(),
        ),
        isTrue,
      );
      expect(engine.openEntryInput(), isTrue);
      expect(engine.submitEntry(playerId: 'p1', text: 'RACCOON'), isTrue);
      expect(engine.submitEntry(playerId: 'p2', text: 'OTTER'), isTrue);

      var round = engine.snapshot.currentGame!.rounds.last;
      var entryP1 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p1');
      expect(
          engine.submitVote(playerId: 'p1', entryId: entryP1.entryId), isFalse);
    });
  });

  group('Entry input gating', () {
    test('does not auto-close entry input before second-entry grace', () {
      var now = _now;
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(),
        now: () => now,
      );
      var engine = GameEngine(
        stateMachine: machine,
        random: Random(11),
        now: () => now,
      );

      expect(
        engine.startGame(
          hostPlayerId: 'p1',
          firstRoundCategoryId: 'animals',
          firstRoundCategoryLabel: 'Animals',
          firstRoundSuperlatives: _roundPrompts(),
        ),
        isTrue,
      );
      expect(engine.openEntryInput(), isTrue);

      expect(engine.submitEntry(playerId: 'p1', text: 'RACCOON'), isTrue);
      expect(engine.submitEntry(playerId: 'p2', text: 'OTTER'), isTrue);

      // Both active players submitted, but less than 5s since second entry.
      expect(engine.snapshot.phase, isA<EntryInputPhase>());

      now = now.add(const Duration(seconds: 5));
      expect(engine.closeEntryInput(), isTrue);
      expect(engine.snapshot.phase, isA<VoteInputPhase>());
    });
  });

  group('Deterministic seeded behavior', () {
    test('superlative selection is deterministic with the same seed', () {
      var pool = const [
        SuperlativePrompt(superlativeId: 'a', promptText: 'A'),
        SuperlativePrompt(superlativeId: 'b', promptText: 'B'),
        SuperlativePrompt(superlativeId: 'c', promptText: 'C'),
        SuperlativePrompt(superlativeId: 'd', promptText: 'D'),
      ];

      var engine1 = GameEngine(
        stateMachine:
            RoomStateMachine(snapshot: _baseSnapshot(), now: () => _now),
        random: Random(42),
      );
      var engine2 = GameEngine(
        stateMachine:
            RoomStateMachine(snapshot: _baseSnapshot(), now: () => _now),
        random: Random(42),
      );

      var s1 = engine1.selectRoundSuperlatives(pool, count: 3);
      var s2 = engine2.selectRoundSuperlatives(pool, count: 3);

      expect(s1.map((p) => p.superlativeId).toList(),
          s2.map((p) => p.superlativeId).toList());
    });
  });

  group('Scoring integration', () {
    test('closing vote phase applies points to game scoreboard', () {
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(
          config:
              const RoomConfig(minPlayersToStart: 2, scorePoolPerVote: 1000),
        ),
        now: () => _now,
      );
      var engine = GameEngine(
        stateMachine: machine,
        random: Random(5),
        now: () => _now,
      );

      expect(
        engine.startGame(
          hostPlayerId: 'p1',
          firstRoundCategoryId: 'animals',
          firstRoundCategoryLabel: 'Animals',
          firstRoundSuperlatives: _roundPrompts(),
        ),
        isTrue,
      );
      expect(engine.openEntryInput(), isTrue);
      expect(engine.submitEntry(playerId: 'p1', text: 'RACCOON'), isTrue);
      expect(engine.submitEntry(playerId: 'p2', text: 'OTTER'), isTrue);

      var round = engine.snapshot.currentGame!.rounds.last;
      var entryP1 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p1');
      var entryP2 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p2');

      expect(
          engine.submitVote(playerId: 'p1', entryId: entryP1.entryId), isTrue);
      expect(
          engine.submitVote(playerId: 'p2', entryId: entryP2.entryId), isTrue);

      expect(engine.closeVotePhase(), isTrue);

      // 1 vote each: 500 points each.
      var scoreboard = engine.snapshot.currentGame!.scoreboard;
      expect(scoreboard['p1'], 500);
      expect(scoreboard['p2'], 500);

      expect(engine.snapshot.phase, isA<VoteRevealPhase>());
      var reveal = engine.snapshot.phase as VoteRevealPhase;
      expect(reveal.results.pointsByEntry.values.fold<int>(0, (a, b) => a + b),
          1000);
    });
  });
}
