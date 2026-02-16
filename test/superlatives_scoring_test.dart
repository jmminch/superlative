import 'package:test/test.dart';

import '../bin/scoring.dart';
import '../bin/superlatives_game.dart';

List<Entry> _entries() {
  return const [
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
  ];
}

void main() {
  group('ScoringEngine', () {
    test('no votes gives zero points to all entries', () {
      var results = ScoringEngine.scoreVotePhase(
        entries: _entries(),
        votesByPlayer: const {},
        scorePoolPerVote: 1000,
      );

      expect(results.voteCountByEntry, {'e1': 0, 'e2': 0, 'e3': 0});
      expect(results.pointsByEntry, {'e1': 0, 'e2': 0, 'e3': 0});
      expect(results.pointsByPlayer, {'p1': 0, 'p2': 0, 'p3': 0});
    });

    test('one vote allocates full pool to selected entry owner', () {
      var results = ScoringEngine.scoreVotePhase(
        entries: _entries(),
        votesByPlayer: const {'v1': 'e2'},
        scorePoolPerVote: 1000,
      );

      expect(results.voteCountByEntry, {'e1': 0, 'e2': 1, 'e3': 0});
      expect(results.pointsByEntry, {'e1': 0, 'e2': 1000, 'e3': 0});
      expect(results.pointsByPlayer, {'p1': 0, 'p2': 1000, 'p3': 0});
    });

    test('tie with remainder uses deterministic entryId tiebreak', () {
      var entries = const [
        Entry(
          entryId: 'eA',
          ownerPlayerId: 'p1',
          textOriginal: 'A',
          textNormalized: 'A',
        ),
        Entry(
          entryId: 'eB',
          ownerPlayerId: 'p2',
          textOriginal: 'B',
          textNormalized: 'B',
        ),
        Entry(
          entryId: 'eC',
          ownerPlayerId: 'p3',
          textOriginal: 'C',
          textNormalized: 'C',
        ),
      ];

      // 1 vote each => 333 each plus 1 leftover goes to eA by entryId sort.
      var results = ScoringEngine.scoreVotePhase(
        entries: entries,
        votesByPlayer: const {'v1': 'eA', 'v2': 'eB', 'v3': 'eC'},
        scorePoolPerVote: 1000,
      );

      expect(results.pointsByEntry['eA'], 334);
      expect(results.pointsByEntry['eB'], 333);
      expect(results.pointsByEntry['eC'], 333);

      var totalPoints =
          results.pointsByEntry.values.fold<int>(0, (a, b) => a + b);
      expect(totalPoints, 1000);
    });

    test('all votes one entry gives all points to that entry', () {
      var results = ScoringEngine.scoreVotePhase(
        entries: _entries(),
        votesByPlayer: const {'v1': 'e3', 'v2': 'e3', 'v3': 'e3', 'v4': 'e3'},
        scorePoolPerVote: 1000,
      );

      expect(results.voteCountByEntry, {'e1': 0, 'e2': 0, 'e3': 4});
      expect(results.pointsByEntry, {'e1': 0, 'e2': 0, 'e3': 1000});
      expect(results.pointsByPlayer, {'p1': 0, 'p2': 0, 'p3': 1000});
    });

    test('invalid votes are ignored', () {
      var results = ScoringEngine.scoreVotePhase(
        entries: _entries(),
        votesByPlayer: const {'v1': 'nope', 'v2': 'e1'},
        scorePoolPerVote: 1000,
      );

      expect(results.voteCountByEntry, {'e1': 1, 'e2': 0, 'e3': 0});
      expect(results.pointsByEntry, {'e1': 1000, 'e2': 0, 'e3': 0});
    });
  });
}
