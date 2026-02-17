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
    voteSets: [
      VoteSet(
        setIndex: 0,
        prompts: [
          VotePromptState(
            promptIndex: 0,
            superlativeId: 's1',
            promptText: 'Cutest',
            votesByPlayer: {'p1': 'e1'},
          ),
        ],
      ),
    ],
    roundPointsByEntry: const {'e1': 500, 'e2': 250},
    roundPointsByPlayerPending: const {'p1': 500, 'p2': 250},
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
    test('lobby canStart counts active players only (not display sessions)',
        () {
      var snapshot = SuperlativesRoomSnapshot(
        roomCode: 'ABCD',
        hostPlayerId: 'p1',
        config: const RoomConfig(minPlayersToStart: 3),
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
        currentGame: null,
        phase: const LobbyPhase(),
        updatedAt: _baseNow,
      );

      var displayPayload = projector.projectForDisplay(snapshot: snapshot);
      expect(displayPayload['lobby']['canStart'], isFalse);
    });

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
        setSuperlatives: const [
          SuperlativePrompt(superlativeId: 's1', promptText: 'Cutest')
        ],
        promptIndexByPlayer: const {'p1': 1},
      );

      var snapshot = _snapshotForPhase(phase);
      var playerPayload = projector.projectForPlayer(
        playerId: 'p1',
        snapshot: snapshot,
      );
      var displayPayload = projector.projectForDisplay(snapshot: snapshot);

      expect(playerPayload['youVoted'], isTrue);
      expect(playerPayload['yourVoteEntryId'], 'e2');
      expect(playerPayload['round']['currentSetIndex'], 0);
      expect(playerPayload['round']['setPromptCount'], 1);
      expect(playerPayload['round']['currentPromptIndexForYou'], 1);
      expect(displayPayload.containsKey('youVoted'), isFalse);
      expect(displayPayload.containsKey('yourVoteEntryId'), isFalse);
      var voteEntries = displayPayload['vote']['entries'] as List<dynamic>;
      expect(voteEntries.first.containsKey('ownerPlayerId'), isFalse);
      expect(voteEntries.first.containsKey('ownerDisplayName'), isFalse);
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
        setSuperlatives: const [
          SuperlativePrompt(superlativeId: 's1', promptText: 'Cutest')
        ],
        endsAt: _baseNow.add(const Duration(seconds: 10)),
      );

      var snapshot = _snapshotForPhase(phase);
      var displayPayload = projector.projectForDisplay(snapshot: snapshot);

      expect(displayPayload['phase'], 'VoteReveal');
      expect(displayPayload['reveal'], isNotNull);
      expect(displayPayload['reveal']['results']['pointsByPlayer'],
          {'p1': 500, 'p2': 500});
      expect(displayPayload['reveal']['roundPointsByEntry'],
          {'e1': 500, 'e2': 250});
      var revealEntries = displayPayload['reveal']['entries'] as List<dynamic>;
      expect(revealEntries.first.containsKey('ownerPlayerId'), isFalse);
      expect(revealEntries.first.containsKey('ownerDisplayName'), isFalse);

      var leaderboard = displayPayload['leaderboard'] as List<dynamic>;
      expect(leaderboard.first['playerId'], 'p1');
      expect(leaderboard.first['score'], 1200);
    });

    test('round summary includes per-player round results with entry text', () {
      var phase = RoundSummaryPhase(
        roundIndex: 0,
        roundId: 'round_1',
        endsAt: _baseNow.add(const Duration(seconds: 8)),
      );
      var snapshot = _snapshotForPhase(phase);

      var payload = projector.projectForDisplay(snapshot: snapshot);
      var rows = payload['roundSummary']['playerRoundResults'] as List<dynamic>;
      expect(rows.length, 2);
      expect(rows.first['playerId'], 'p1');
      expect(rows.first['entryText'], 'RACCOON');
      expect(rows.first['pointsThisRound'], 500);
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
