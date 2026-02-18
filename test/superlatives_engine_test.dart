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
    SuperlativePrompt(superlativeId: 's4', promptText: 'Smartest'),
    SuperlativePrompt(superlativeId: 's5', promptText: 'Loudest'),
    SuperlativePrompt(superlativeId: 's6', promptText: 'Fastest'),
    SuperlativePrompt(superlativeId: 's7', promptText: 'Sleepiest'),
    SuperlativePrompt(superlativeId: 's8', promptText: 'Most social'),
    SuperlativePrompt(superlativeId: 's9', promptText: 'Most curious'),
  ];
}

void _playRoundToSummary(GameEngine engine) {
  expect(engine.openEntryInput(), isTrue);
  expect(engine.submitEntry(playerId: 'p1', text: 'RACCOON'), isTrue);
  expect(engine.submitEntry(playerId: 'p2', text: 'OTTER'), isTrue);
  expect(engine.snapshot.phase, isA<VoteInputPhase>());

  var config = engine.snapshot.config;
  for (var setIndex = 0; setIndex < config.setCount; setIndex++) {
    for (var promptIndex = 0;
        promptIndex < config.promptsPerSet;
        promptIndex++) {
      expect(engine.snapshot.phase, isA<VoteInputPhase>());
      var round = engine.snapshot.currentGame!.rounds.last;
      var entryP1 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p1');

      expect(engine.submitVote(playerId: 'p1', entryId: entryP1.entryId),
          isTrue);
      expect(engine.submitVote(playerId: 'p2', entryId: entryP1.entryId),
          isTrue);
    }

    expect(engine.closeVotePhase(), isTrue);
    expect(engine.snapshot.phase, isA<VoteRevealPhase>());
    expect(engine.closeReveal(), isTrue);

    if (setIndex < config.setCount - 1) {
      expect(engine.snapshot.phase, isA<VoteInputPhase>());
    }
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
      expect(engine.snapshot.phase, isA<VoteInputPhase>());

      // Finish round quickly.
      var config = engine.snapshot.config;
      for (var setIndex = 0; setIndex < config.setCount; setIndex++) {
        for (var promptIndex = 0;
            promptIndex < config.promptsPerSet;
            promptIndex++) {
          var round = engine.snapshot.currentGame!.rounds.last;
          var entryP1 =
              round.entries.firstWhere((e) => e.ownerPlayerId == 'p1');
          expect(engine.submitVote(playerId: 'p1', entryId: entryP1.entryId),
              isTrue);
          expect(engine.submitVote(playerId: 'p2', entryId: entryP1.entryId),
              isTrue);
        }
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

    test('does not advance shared prompt until all active players vote', () {
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(
          config: const RoomConfig(
            minPlayersToStart: 2,
            setCount: 1,
            promptsPerSet: 2,
          ),
        ),
        now: () => _now,
      );
      var engine = GameEngine(
        stateMachine: machine,
        random: Random(77),
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
      expect(engine.snapshot.phase, isA<VoteInputPhase>());

      var round = engine.snapshot.currentGame!.rounds.last;
      var entryP1 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p1');
      var entryP2 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p2');

      var phaseBefore = engine.snapshot.phase as VoteInputPhase;
      expect(phaseBefore.promptText, 'Cutest');

      expect(engine.submitVote(playerId: 'p1', entryId: entryP2.entryId), isTrue);
      var phaseAfterOneVote = engine.snapshot.phase as VoteInputPhase;
      expect(phaseAfterOneVote.promptText, 'Cutest');

      expect(engine.submitVote(playerId: 'p2', entryId: entryP1.entryId), isTrue);
      var phaseAfterBothVoted = engine.snapshot.phase as VoteInputPhase;
      expect(phaseAfterBothVoted.promptText, 'Bravest');
    });

    test('rejects self vote when config disallows it and >2 entries remain',
        () {
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(
          config: const RoomConfig(
            minPlayersToStart: 3,
            allowSelfVote: false,
          ),
          players: const {
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
            'p3': PlayerSession(
              playerId: 'p3',
              displayName: 'C',
              state: PlayerSessionState.active,
            ),
          },
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
      expect(engine.submitEntry(playerId: 'p3', text: 'PANDA'), isTrue);
      expect(engine.snapshot.phase, isA<VoteInputPhase>());

      var round = engine.snapshot.currentGame!.rounds.last;
      var entryP1 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p1');
      expect(
          engine.submitVote(playerId: 'p1', entryId: entryP1.entryId), isFalse);
    });

    test('allows self vote when only 2 active entries remain', () {
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(
          config: const RoomConfig(
            minPlayersToStart: 2,
            allowSelfVote: false,
            setCount: 1,
            promptsPerSet: 1,
          ),
        ),
        now: () => _now,
      );
      var engine = GameEngine(
        stateMachine: machine,
        random: Random(10),
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
      expect(engine.submitVote(playerId: 'p1', entryId: entryP1.entryId), isTrue);
    });
  });

  group('Elimination twist', () {
    test('after set 1 removes bottom third while keeping at least 3', () {
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(
          config: const RoomConfig(
            minPlayersToStart: 4,
            setCount: 2,
            promptsPerSet: 1,
          ),
          players: const {
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
            'p3': PlayerSession(
              playerId: 'p3',
              displayName: 'C',
              state: PlayerSessionState.active,
            ),
            'p4': PlayerSession(
              playerId: 'p4',
              displayName: 'D',
              state: PlayerSessionState.active,
            ),
          },
        ),
        now: () => _now,
      );
      var engine = GameEngine(
        stateMachine: machine,
        random: Random(12),
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
      expect(engine.submitEntry(playerId: 'p1', text: 'A1'), isTrue);
      expect(engine.submitEntry(playerId: 'p2', text: 'A2'), isTrue);
      expect(engine.submitEntry(playerId: 'p3', text: 'A3'), isTrue);
      expect(engine.submitEntry(playerId: 'p4', text: 'A4'), isTrue);

      var round = engine.snapshot.currentGame!.rounds.last;
      var e1 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p1').entryId;
      var e2 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p2').entryId;
      var e3 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p3').entryId;

      expect(engine.submitVote(playerId: 'p1', entryId: e1), isTrue);
      expect(engine.submitVote(playerId: 'p2', entryId: e1), isTrue);
      expect(engine.submitVote(playerId: 'p3', entryId: e2), isTrue);
      expect(engine.submitVote(playerId: 'p4', entryId: e3), isTrue);
      expect(engine.closeVotePhase(), isTrue);

      round = engine.snapshot.currentGame!.rounds.last;
      var active = round.entries.where((e) => e.status == EntryStatus.active);
      expect(active.length, 3);
      var eliminated = round.entries.where((e) => e.status == EntryStatus.eliminated);
      expect(eliminated.length, 1);
      expect(eliminated.first.ownerPlayerId, 'p4');
    });

    test('after set 2 keeps ties together at cutoff', () {
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(
          config: const RoomConfig(
            minPlayersToStart: 3,
            setCount: 2,
            promptsPerSet: 1,
          ),
          players: const {
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
            'p3': PlayerSession(
              playerId: 'p3',
              displayName: 'C',
              state: PlayerSessionState.active,
            ),
          },
        ),
        now: () => _now,
      );
      var engine = GameEngine(
        stateMachine: machine,
        random: Random(13),
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
      expect(engine.submitEntry(playerId: 'p1', text: 'A1'), isTrue);
      expect(engine.submitEntry(playerId: 'p2', text: 'A2'), isTrue);
      expect(engine.submitEntry(playerId: 'p3', text: 'A3'), isTrue);

      var round = engine.snapshot.currentGame!.rounds.last;
      var e1 = round.entries.firstWhere((e) => e.ownerPlayerId == 'p1').entryId;

      // Set 1: all votes to p1, min keep=3 => no elimination yet.
      expect(engine.submitVote(playerId: 'p1', entryId: e1), isTrue);
      expect(engine.submitVote(playerId: 'p2', entryId: e1), isTrue);
      expect(engine.submitVote(playerId: 'p3', entryId: e1), isTrue);
      expect(engine.closeVotePhase(), isTrue);
      expect(engine.closeReveal(), isTrue);

      // Set 2: all votes to p1 again, p2/p3 tie at cutoff; ties are kept.
      expect(engine.submitVote(playerId: 'p1', entryId: e1), isTrue);
      expect(engine.submitVote(playerId: 'p2', entryId: e1), isTrue);
      expect(engine.submitVote(playerId: 'p3', entryId: e1), isTrue);
      expect(engine.closeVotePhase(), isTrue);

      round = engine.snapshot.currentGame!.rounds.last;
      var active = round.entries.where((e) => e.status == EntryStatus.active);
      expect(active.length, 3);
    });
  });

  group('Entry input gating', () {
    test('does not auto-close entry input until all active players submit', () {
      var now = _now;
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(
          config: const RoomConfig(minPlayersToStart: 3),
          players: const {
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
            'p3': PlayerSession(
              playerId: 'p3',
              displayName: 'C',
              state: PlayerSessionState.active,
            ),
          },
        ),
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

      // Not all active players submitted, so input stays open.
      expect(engine.snapshot.phase, isA<EntryInputPhase>());

      // Host/runtime can still force-close the phase.
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
    test('set scoring accumulates during round and applies at round end', () {
      var machine = RoomStateMachine(
        snapshot: _baseSnapshot(
          config:
              const RoomConfig(
                minPlayersToStart: 2,
                scorePoolPerVote: 1000,
                setCount: 1,
                promptsPerSet: 1,
                roundCount: 1,
              ),
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

      // Mid-round scoreboard does not change until round completion.
      var scoreboard = engine.snapshot.currentGame!.scoreboard;
      expect(scoreboard['p1'], 0);
      expect(scoreboard['p2'], 0);

      expect(engine.snapshot.phase, isA<VoteRevealPhase>());
      var reveal = engine.snapshot.phase as VoteRevealPhase;
      expect(reveal.results.pointsByEntry.values.fold<int>(0, (a, b) => a + b),
          1000);
      expect(
          engine
              .snapshot.currentGame!.rounds.last.roundPointsByEntry[entryP1.entryId],
          500);
      expect(
          engine
              .snapshot.currentGame!.rounds.last.roundPointsByEntry[entryP2.entryId],
          500);

      expect(engine.closeReveal(), isTrue);
      expect(engine.snapshot.phase, isA<RoundSummaryPhase>());
      expect(engine.completeRound(), isTrue);
      expect(engine.snapshot.phase, isA<GameSummaryPhase>());

      // 1 vote each: 500 points each, applied after round end.
      scoreboard = engine.snapshot.currentGame!.scoreboard;
      expect(scoreboard['p1'], 500);
      expect(scoreboard['p2'], 500);
    });
  });
}
