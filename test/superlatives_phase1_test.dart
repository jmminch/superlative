import 'package:test/test.dart';

import '../bin/superlatives_game.dart';

void main() {
  group('RoomConfig defaults', () {
    test('uses spec defaults', () {
      var config = const RoomConfig();

      expect(config.roundCount, 3);
      expect(config.votePhasesPerRound, 3);
      expect(config.entryInputSeconds, 30);
      expect(config.voteInputSeconds, 20);
      expect(config.revealSeconds, 12);
      expect(config.scorePoolPerVote, 1000);
      expect(config.allowSelfVote, isTrue);
      expect(config.maxEntryLength, 40);
      expect(config.minPlayersToStart, 3);
    });
  });

  group('Validation helpers', () {
    test('normalizes entry text by trimming and collapsing spaces', () {
      var normalized = SuperlativesValidation.normalizeEntryText(
        '   giant    panda   ',
      );

      expect(normalized, 'giant panda');
    });

    test('rejects empty entry after normalization', () {
      var result = SuperlativesValidation.validateEntryText(
        '    \n\t   ',
        config: const RoomConfig(),
      );

      expect(result.ok, isFalse);
      expect(result.message, isNotNull);
    });

    test('rejects overlength entry', () {
      var config = const RoomConfig(maxEntryLength: 5);
      var result =
          SuperlativesValidation.validateEntryText('abcdef', config: config);

      expect(result.ok, isFalse);
    });

    test('accepts valid entry', () {
      var result = SuperlativesValidation.validateEntryText(
        'raccoon',
        config: const RoomConfig(maxEntryLength: 10),
      );

      expect(result.ok, isTrue);
      expect(result.message, isNull);
    });
  });

  group('Vote eligibility', () {
    var activePlayer = const PlayerSession(
      playerId: 'p1',
      displayName: 'NOEL',
      state: PlayerSessionState.active,
    );

    var selfEntry = const Entry(
      entryId: 'e1',
      ownerPlayerId: 'p1',
      textOriginal: 'RACCOON',
      textNormalized: 'RACCOON',
    );

    var otherEntry = const Entry(
      entryId: 'e2',
      ownerPlayerId: 'p2',
      textOriginal: 'OTTER',
      textNormalized: 'OTTER',
    );

    test('allows self vote when configured', () {
      var allowed = SuperlativesValidation.canPlayerVoteForEntry(
        config: const RoomConfig(allowSelfVote: true),
        voter: activePlayer,
        entry: selfEntry,
      );

      expect(allowed, isTrue);
    });

    test('denies self vote when disabled', () {
      var allowed = SuperlativesValidation.canPlayerVoteForEntry(
        config: const RoomConfig(allowSelfVote: false),
        voter: activePlayer,
        entry: selfEntry,
      );

      expect(allowed, isFalse);
    });

    test('denies non-active players', () {
      var idlePlayer = const PlayerSession(
        playerId: 'p1',
        displayName: 'NOEL',
        state: PlayerSessionState.idle,
      );

      var allowed = SuperlativesValidation.canPlayerVoteForEntry(
        config: const RoomConfig(),
        voter: idlePlayer,
        entry: otherEntry,
      );

      expect(allowed, isFalse);
    });

    test('denies display sessions', () {
      var displaySession = const PlayerSession(
        playerId: 'd1',
        displayName: 'DISPLAY',
        role: SessionRole.display,
        state: PlayerSessionState.active,
      );

      var allowed = SuperlativesValidation.canPlayerVoteForEntry(
        config: const RoomConfig(),
        voter: displaySession,
        entry: otherEntry,
      );

      expect(allowed, isFalse);
    });
  });

  group('Phase and snapshot model', () {
    test('phase identity strings are stable', () {
      var phase = const LobbyPhase();
      expect(phase.phase, 'Lobby');
    });

    test('snapshot rejects empty room code', () {
      expect(
        () => SuperlativesRoomSnapshot(
          roomCode: '   ',
          hostPlayerId: null,
          config: const RoomConfig(),
          players: const {},
          currentGame: null,
          phase: const LobbyPhase(),
          updatedAt: DateTime.now(),
        ),
        throwsArgumentError,
      );
    });

    test('snapshot active player count only includes active state', () {
      var snapshot = SuperlativesRoomSnapshot(
        roomCode: 'ABCD',
        hostPlayerId: 'p1',
        config: const RoomConfig(),
        players: const {
          'p1': PlayerSession(
            playerId: 'p1',
            displayName: 'A',
            state: PlayerSessionState.active,
          ),
          'p2': PlayerSession(
            playerId: 'p2',
            displayName: 'B',
            state: PlayerSessionState.pending,
          ),
        },
        currentGame: null,
        phase: const LobbyPhase(),
        updatedAt: DateTime.now(),
      );

      expect(snapshot.activePlayerCount, 1);
    });
  });
}
