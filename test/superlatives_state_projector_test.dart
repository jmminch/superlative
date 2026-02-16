import 'package:test/test.dart';

import '../bin/state_projector.dart';
import '../bin/superlatives_game.dart';

DateTime _baseNow = DateTime.utc(2026, 2, 16, 12, 0, 0);

RoundInstance _round({VoteResults? results}) {
  return RoundInstance(
    roundId: 'round_1',
    categoryId: 'animals',
    categoryLabel: 'Animals',
    entries: const [
      Entry(
        entryId: 'e1',
        ownerPlayerId: 'p1',
        textOriginal: 'RACCOON',
        textNormalized: 'RACCOON',
      ),
      Entry(
        entryId: 'e2',
        ownerPlayerId: 'p2',
        textOriginal: 'OTTER',
        textNormalized: 'OTTER',
      ),
    ],
    votePhases: [
      VotePhase(
        voteIndex: 0,
        superlativeId: 's1',
        promptText: 'Cutest',
        votesByPlayer: const {'p1': 'e1'},
        results: results,
      ),
    ],
    status: RoundStatus.active,
  );
}

SuperlativesRoomSnapshot _snapshotForPhase(GamePhaseState phase) {
  return SuperlativesRoomSnapshot(
    roomCode: 'ABCD',
    hostPlayerId: 'p1',
    config: const RoomConfig(minPlayersToStart: 2),
    players: const {
      'p1': PlayerSession(
        playerId: 'p1',
        displayName: 'ALPHA',
        state: PlayerSessionState.active,
      ),
      'p2': PlayerSession(
        playerId: 'p2',
        displayName: 'BETA',
        state: PlayerSessionState.active,
      ),
      'd1': PlayerSession(
        playerId: 'd1',
        displayName: 'DISPLAY',
        role: SessionRole.display,
        state: PlayerSessionState.active,
      ),
    },
    currentGame: GameInstance(
      gameId: 'g1',
      roundIndex: 0,
      rounds: [
        _round(results: phase is VoteRevealPhase ? phase.results : null)
      ],
      scoreboard: const {'p1': 1200, 'p2': 800},
    ),
    phase: phase,
    updatedAt: _baseNow,
  );
}

void main() {
  var projector = StateProjector(now: () => _baseNow);

  group('StateProjector role-scoped payloads', () {
    test('player projection includes private submission flag in EntryInput',
        () {
      var phase = EntryInputPhase(
        roundIndex: 0,
        roundId: 'round_1',
        categoryLabel: 'Animals',
        superlatives: const [
          SuperlativePrompt(superlativeId: 's1', promptText: 'Cutest')
        ],
        endsAt: _baseNow.add(const Duration(seconds: 20)),
        submittedPlayerIds: const {'p1'},
      );

      var snapshot = _snapshotForPhase(phase);
      var playerPayload = projector.projectForPlayer(
        playerId: 'p1',
        snapshot: snapshot,
      );
      var displayPayload = projector.projectForDisplay(snapshot: snapshot);

      expect(playerPayload['phase'], 'EntryInput');
      expect(playerPayload['youSubmitted'], isTrue);
      expect(playerPayload.containsKey('youVoted'), isFalse);
      expect(displayPayload.containsKey('youSubmitted'), isFalse);
      expect(displayPayload.containsKey('youVoted'), isFalse);
    });

    test('player projection includes vote private flags in VoteInput', () {
      var phase = VoteInputPhase(
        roundIndex: 0,
        roundId: 'round_1',
        voteIndex: 0,
        superlativeId: 's1',
        promptText: 'Cutest',
        roundSuperlatives: const [
          SuperlativePrompt(superlativeId: 's1', promptText: 'Cutest')
        ],
        endsAt: _baseNow.add(const Duration(seconds: 20)),
        votesByPlayer: const {'p1': 'e2'},
      );

      var snapshot = _snapshotForPhase(phase);
      var playerPayload = projector.projectForPlayer(
        playerId: 'p1',
        snapshot: snapshot,
      );
      var displayPayload = projector.projectForDisplay(snapshot: snapshot);

      expect(playerPayload['youVoted'], isTrue);
      expect(playerPayload['yourVoteEntryId'], 'e2');
      expect(displayPayload.containsKey('youVoted'), isFalse);
      expect(displayPayload.containsKey('yourVoteEntryId'), isFalse);
    });

    test('display projection includes reveal results and leaderboard', () {
      var phase = VoteRevealPhase(
        roundIndex: 0,
        roundId: 'round_1',
        voteIndex: 0,
        superlativeId: 's1',
        promptText: 'Cutest',
        roundSuperlatives: const [
          SuperlativePrompt(superlativeId: 's1', promptText: 'Cutest')
        ],
        results: VoteResults(
          voteCountByEntry: const {'e1': 1, 'e2': 1},
          pointsByEntry: const {'e1': 500, 'e2': 500},
          pointsByPlayer: const {'p1': 500, 'p2': 500},
        ),
        endsAt: _baseNow.add(const Duration(seconds: 10)),
      );

      var snapshot = _snapshotForPhase(phase);
      var displayPayload = projector.projectForDisplay(snapshot: snapshot);

      expect(displayPayload['phase'], 'VoteReveal');
      expect(displayPayload['reveal'], isNotNull);
      expect(displayPayload['reveal']['results']['pointsByPlayer'],
          {'p1': 500, 'p2': 500});

      var leaderboard = displayPayload['leaderboard'] as List<dynamic>;
      expect(leaderboard.first['playerId'], 'p1');
      expect(leaderboard.first['score'], 1200);
    });

    test('game summary payload includes game metadata and no private flags',
        () {
      var phase = const GameSummaryPhase(gameId: 'g1');
      var snapshot = _snapshotForPhase(phase);

      var playerPayload = projector.projectForPlayer(
        playerId: 'p2',
        snapshot: snapshot,
      );
      var displayPayload = projector.projectForDisplay(snapshot: snapshot);

      expect(playerPayload['gameSummary']['gameId'], 'g1');
      expect(displayPayload['gameSummary']['gameId'], 'g1');
      expect(playerPayload.containsKey('youSubmitted'), isFalse);
      expect(displayPayload.containsKey('youSubmitted'), isFalse);
    });
  });
}
