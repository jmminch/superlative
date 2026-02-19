import 'package:test/test.dart';

import '../bin/state_projector.dart';
import '../bin/superlatives_game.dart';

DateTime _baseNow = DateTime.utc(2026, 2, 16, 12, 0, 0);

RoundInstance _round({
  VoteResults? results,
  List<VotePromptState>? setPrompts,
}) {
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
        prompts: setPrompts ??
            [
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
    roundPointsByPlayerPending: const {},
    status: RoundStatus.active,
  );
}

SuperlativesRoomSnapshot _snapshotForPhase(
  GamePhaseState phase, {
  RoundInstance? round,
}) {
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
        round ??
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
      expect(displayPayload['round']['superlatives'], isA<List<dynamic>>());
      expect(
          displayPayload['round']['submittedPlayerIds'], equals(const ['p1']));
    });

    test('display EntryInput timer stays anchored to initial deadline', () {
      var initialEndsAt = _baseNow.add(const Duration(seconds: 30));
      var phase = EntryInputPhase(
        roundIndex: 0,
        roundId: 'round_1',
        categoryLabel: 'Animals',
        superlatives: const [
          SuperlativePrompt(superlativeId: 's1', promptText: 'Cutest')
        ],
        initialEndsAt: initialEndsAt,
        endsAt: _baseNow.add(const Duration(seconds: 45)),
        submittedPlayerIds: const {'p1'},
      );

      var snapshot = _snapshotForPhase(phase);
      var displayPayload = projector.projectForDisplay(snapshot: snapshot);

      expect(
        displayPayload['round']['timeoutAtMs'],
        initialEndsAt.millisecondsSinceEpoch,
      );
      expect(displayPayload['round']['timeoutSeconds'], 30);
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
      expect(playerPayload['yourVoteEntryId'], isNull);
      expect(playerPayload['round']['currentSetIndex'], 0);
      expect(playerPayload['round']['setPromptCount'], 1);
      expect(playerPayload['round']['currentPromptIndexForYou'], 1);
      expect(displayPayload.containsKey('youVoted'), isFalse);
      expect(displayPayload.containsKey('yourVoteEntryId'), isFalse);
      expect(
        displayPayload['round']['completedPlayerIds'],
        equals(const ['p1']),
      );
      expect(displayPayload['round']['setSuperlatives'], isA<List<dynamic>>());
      var voteEntries = displayPayload['vote']['entries'] as List<dynamic>;
      expect(voteEntries.first.containsKey('ownerPlayerId'), isFalse);
      expect(voteEntries.first.containsKey('ownerDisplayName'), isFalse);
    });

    test('player vote prompt projection is independent per player', () {
      var phase = VoteInputPhase(
        roundIndex: 0,
        roundId: 'round_1',
        voteIndex: 0,
        superlativeId: 's1',
        promptText: 'Cutest',
        roundSuperlatives: const [
          SuperlativePrompt(superlativeId: 's1', promptText: 'Cutest'),
          SuperlativePrompt(superlativeId: 's2', promptText: 'Bravest'),
        ],
        endsAt: _baseNow.add(const Duration(seconds: 20)),
        votesByPlayer: const {'p1': 'e2'},
        setSuperlatives: const [
          SuperlativePrompt(superlativeId: 's1', promptText: 'Cutest'),
          SuperlativePrompt(superlativeId: 's2', promptText: 'Bravest'),
        ],
        promptIndexByPlayer: const {'p1': 1, 'p2': 0},
      );
      var snapshot = _snapshotForPhase(
        phase,
        round: _round(
          setPrompts: [
            VotePromptState(
              promptIndex: 0,
              superlativeId: 's1',
              promptText: 'Cutest',
              votesByPlayer: {'p1': 'e2'},
            ),
            VotePromptState(
              promptIndex: 1,
              superlativeId: 's2',
              promptText: 'Bravest',
              votesByPlayer: {},
            ),
          ],
        ),
      );

      var p1Payload =
          projector.projectForPlayer(playerId: 'p1', snapshot: snapshot);
      var p2Payload =
          projector.projectForPlayer(playerId: 'p2', snapshot: snapshot);

      expect(p1Payload['vote']['promptText'], 'Bravest');
      expect(p1Payload['round']['currentPromptIndexForYou'], 1);
      expect(p1Payload['youVoted'], isFalse);
      expect(p1Payload['yourVoteEntryId'], isNull);

      expect(p2Payload['vote']['promptText'], 'Cutest');
      expect(p2Payload['round']['currentPromptIndexForYou'], 0);
      expect(p2Payload['youVoted'], isFalse);
      expect(p2Payload['yourVoteEntryId'], isNull);
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
      expect(rows.first['totalScore'], 1700);
      expect(rows.first['entryText'], 'RACCOON');
      expect(rows.first['pointsThisRound'], 500);
    });

    test('round summary includes top 3 winners per superlative', () {
      var phase = RoundSummaryPhase(
        roundIndex: 0,
        roundId: 'round_1',
        endsAt: _baseNow.add(const Duration(seconds: 8)),
      );

      var snapshot = SuperlativesRoomSnapshot(
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
          'p3': PlayerSession(
            playerId: 'p3',
            displayName: 'GAMMA',
            state: PlayerSessionState.active,
          ),
          'p4': PlayerSession(
            playerId: 'p4',
            displayName: 'DELTA',
            state: PlayerSessionState.active,
          ),
        },
        currentGame: GameInstance(
          gameId: 'g1',
          roundIndex: 0,
          rounds: [
            RoundInstance(
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
                Entry(
                  entryId: 'e3',
                  ownerPlayerId: 'p3',
                  textOriginal: 'PANDA',
                  textNormalized: 'PANDA',
                ),
                Entry(
                  entryId: 'e4',
                  ownerPlayerId: 'p4',
                  textOriginal: 'WOLF',
                  textNormalized: 'WOLF',
                  status: EntryStatus.eliminated,
                ),
              ],
              votePhases: const [],
              voteSets: [
                VoteSet(
                  setIndex: 0,
                  prompts: [
                    VotePromptState(
                      promptIndex: 0,
                      superlativeId: 's1',
                      promptText: 'Cutest',
                      votesByPlayer: {
                        'p1': 'e4',
                        'p2': 'e4',
                        'p3': 'e1',
                        'p4': 'e2',
                      },
                    ),
                    VotePromptState(
                      promptIndex: 1,
                      superlativeId: 's2',
                      promptText: 'Bravest',
                      votesByPlayer: {
                        'p1': 'e1',
                        'p2': 'e2',
                        'p3': 'e3',
                        'p4': 'e4',
                      },
                    ),
                  ],
                ),
              ],
              roundPointsByEntry: const {
                'e1': 200,
                'e2': 200,
                'e3': 100,
                'e4': 400
              },
              roundPointsByPlayerPending: const {},
              status: RoundStatus.active,
            ),
          ],
          scoreboard: const {'p1': 1000, 'p2': 800, 'p3': 700, 'p4': 600},
        ),
        phase: phase,
        updatedAt: _baseNow,
      );

      var payload = projector.projectForDisplay(snapshot: snapshot);
      var results =
          payload['roundSummary']['superlativeResults'] as List<dynamic>;
      expect(results.length, 2);

      var cutest = results[0] as Map<String, dynamic>;
      var cutestTop = cutest['topEntries'] as List<dynamic>;
      expect(cutestTop.length, 3);
      expect(cutestTop[0]['entryId'], 'e4');
      expect(cutestTop[0]['ownerDisplayName'], 'DELTA');
      expect(cutestTop[0]['voteCount'], 2);
      expect(cutestTop.any((e) => e['entryId'] == 'e3'), isFalse);

      var bravest = results[1] as Map<String, dynamic>;
      var bravestTop = bravest['topEntries'] as List<dynamic>;
      expect(bravestTop.length, 3);
      expect(bravestTop[0]['entryId'], 'e1');
      expect(bravestTop[1]['entryId'], 'e2');
      expect(bravestTop[2]['entryId'], 'e3');
      expect(bravestTop.any((e) => e['entryId'] == 'e4'), isFalse);
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
