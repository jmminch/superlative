import 'superlatives_game.dart';

class ScoringEngine {
  static VoteResults scoreVotePhase({
    required List<Entry> entries,
    required Map<String, String> votesByPlayer,
    required int scorePoolPerVote,
  }) {
    var eligibleEntries =
        entries.where(SuperlativesValidation.isVoteEligibleEntry).toList();

    var voteCountByEntry = <String, int>{};
    for (var entry in eligibleEntries) {
      voteCountByEntry[entry.entryId] = 0;
    }

    for (var entryId in votesByPlayer.values) {
      if (voteCountByEntry.containsKey(entryId)) {
        voteCountByEntry[entryId] = voteCountByEntry[entryId]! + 1;
      }
    }

    var totalValidVotes = 0;
    for (var votes in voteCountByEntry.values) {
      totalValidVotes += votes;
    }

    var pointsByEntry = <String, int>{};
    for (var entry in eligibleEntries) {
      pointsByEntry[entry.entryId] = 0;
    }

    if (totalValidVotes > 0 &&
        scorePoolPerVote > 0 &&
        eligibleEntries.isNotEmpty) {
      var floorPoints = <String, int>{};
      var remainders = <String, int>{};
      var allocated = 0;

      for (var entry in eligibleEntries) {
        var votes = voteCountByEntry[entry.entryId] ?? 0;
        var numerator = scorePoolPerVote * votes;
        var floorValue = numerator ~/ totalValidVotes;
        var remainder = numerator % totalValidVotes;

        floorPoints[entry.entryId] = floorValue;
        remainders[entry.entryId] = remainder;
        allocated += floorValue;
      }

      var leftover = scorePoolPerVote - allocated;

      var order = eligibleEntries.map((e) => e.entryId).toList(growable: false)
        ..sort((a, b) {
          var remCmp = (remainders[b] ?? 0).compareTo(remainders[a] ?? 0);
          if (remCmp != 0) {
            return remCmp;
          }
          return a.compareTo(b);
        });

      for (var i = 0; i < order.length; i++) {
        pointsByEntry[order[i]] = floorPoints[order[i]] ?? 0;
      }

      for (var i = 0; i < leftover; i++) {
        var entryId = order[i % order.length];
        pointsByEntry[entryId] = (pointsByEntry[entryId] ?? 0) + 1;
      }
    }

    var pointsByPlayer = <String, int>{};
    for (var entry in eligibleEntries) {
      var points = pointsByEntry[entry.entryId] ?? 0;
      pointsByPlayer[entry.ownerPlayerId] =
          (pointsByPlayer[entry.ownerPlayerId] ?? 0) + points;
    }

    return VoteResults(
      voteCountByEntry: voteCountByEntry,
      pointsByEntry: pointsByEntry,
      pointsByPlayer: pointsByPlayer,
    );
  }
}
