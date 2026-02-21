import 'superlatives_game.dart';

class StateProjector {
  final DateTime Function() _now;

  StateProjector({DateTime Function()? now}) : _now = now ?? DateTime.now;

  Map<String, dynamic> projectForPlayer({
    required String playerId,
    required SuperlativesRoomSnapshot snapshot,
  }) {
    var player = snapshot.players[playerId];
    if (player == null) {
      throw ArgumentError('Unknown playerId: $playerId');
    }

    var payload = _buildBasePayload(snapshot: snapshot, role: 'player');
    payload['playerId'] = player.playerId;
    payload['displayName'] = player.displayName;
    payload['host'] = (snapshot.hostPlayerId == playerId);
    payload['pending'] = player.state == PlayerSessionState.pending;

    _augmentPhasePayload(
      payload: payload,
      snapshot: snapshot,
      viewer: player,
      role: 'player',
    );

    return payload;
  }

  Map<String, dynamic> projectForDisplay({
    required SuperlativesRoomSnapshot snapshot,
  }) {
    var payload = _buildBasePayload(snapshot: snapshot, role: 'display');

    _augmentPhasePayload(
      payload: payload,
      snapshot: snapshot,
      viewer: null,
      role: 'display',
    );

    return payload;
  }

  Map<String, dynamic> _buildBasePayload({
    required SuperlativesRoomSnapshot snapshot,
    required String role,
  }) {
    return {
      'room': snapshot.roomCode,
      'phase': snapshot.phase.phase,
      'role': role,
      'hostPlayerId': snapshot.hostPlayerId,
      'updatedAt': snapshot.updatedAt.toIso8601String(),
      'players': _playerList(snapshot),
      'leaderboard': _leaderboard(snapshot),
    };
  }

  void _augmentPhasePayload({
    required Map<String, dynamic> payload,
    required SuperlativesRoomSnapshot snapshot,
    required PlayerSession? viewer,
    required String role,
  }) {
    var phase = snapshot.phase;
    var round = _currentRound(snapshot);

    if (phase is LobbyPhase) {
      payload['lobby'] = {
        'canStart': snapshot.activePlayerSessions.length >=
            snapshot.config.minPlayersToStart
      };
      return;
    }

    if (phase is RoundIntroPhase) {
      payload['round'] = {
        'roundIndex': phase.roundIndex,
        'roundId': phase.roundId,
        'categoryLabel': phase.categoryLabel,
        'superlatives': _superlativesList(phase.superlatives),
        'timeoutSeconds': _remainingSeconds(phase.endsAt),
        'timeoutAtMs': phase.endsAt.millisecondsSinceEpoch,
      };
      return;
    }

    if (phase is GameStartingPhase) {
      payload['gameStarting'] = {
        'roundIndex': phase.roundIndex,
        'roundId': phase.roundId,
        'categoryLabel': phase.categoryLabel,
        'showInstructions': phase.showInstructions,
        'timeoutSeconds': _remainingSeconds(phase.endsAt),
        'timeoutAtMs': phase.endsAt.millisecondsSinceEpoch,
      };
      return;
    }

    if (phase is EntryInputPhase) {
      payload['round'] = {
        'roundIndex': phase.roundIndex,
        'roundId': phase.roundId,
        'categoryLabel': phase.categoryLabel,
        'superlatives': _superlativesList(phase.superlatives),
        // Player identities stay hidden until round summary.
        'entries': const [],
        'timeoutSeconds': _remainingSeconds(phase.initialEndsAt),
        'timeoutAtMs': phase.initialEndsAt.millisecondsSinceEpoch,
      };
      if (role == 'display') {
        var submittedPlayerIds = phase.submittedPlayerIds.toList()..sort();
        payload['round']['submittedPlayerIds'] = submittedPlayerIds;
      }

      if (role == 'player' && viewer != null) {
        payload['youSubmitted'] =
            phase.submittedPlayerIds.contains(viewer.playerId);
      }
      return;
    }

    if (phase is VoteInputPhase) {
      var setPromptCount = phase.setSuperlatives.length;
      if (setPromptCount == 0) {
        payload['vote'] = {
          'roundId': phase.roundId,
          'voteIndex': phase.voteIndex,
          'superlativeId': phase.superlativeId,
          'promptText': phase.promptText,
          'entries': _entriesView(
            snapshot,
            round,
            includeOwner: false,
            includeEliminated: role != 'player',
          ),
          'timeoutSeconds': _remainingSeconds(phase.endsAt),
          'timeoutAtMs': phase.endsAt.millisecondsSinceEpoch,
        };
        payload['round'] = {
          'roundId': phase.roundId,
          'categoryLabel': round?.categoryLabel ?? '',
          'currentSetIndex': phase.setIndex,
          'setPromptCount': 0,
          'setSuperlatives': const <Map<String, dynamic>>[],
          'completedPlayerIds': const <String>[],
          'setTimeoutSeconds': _remainingSeconds(phase.endsAt),
          'setTimeoutAtMs': phase.endsAt.millisecondsSinceEpoch,
        };
        if (role == 'player' && viewer != null) {
          payload['youVoted'] = true;
          payload['yourVoteEntryId'] = null;
          payload['round']['currentPromptIndexForYou'] = 0;
        }
        return;
      }
      var promptIndex = _projectedPromptIndex(
        phase: phase,
        snapshot: snapshot,
        viewer: viewer,
        role: role,
      );
      var isDone = promptIndex >= setPromptCount;
      var activePromptIndex = isDone ? setPromptCount - 1 : promptIndex;
      var currentPrompt = phase.setSuperlatives[activePromptIndex];
      payload['vote'] = {
        'roundId': phase.roundId,
        'voteIndex': phase.voteIndex,
        'superlativeId': currentPrompt.superlativeId,
        'promptText': currentPrompt.promptText,
        'entries': _entriesView(
          snapshot,
          round,
          includeOwner: false,
          includeEliminated: role != 'player',
        ),
        'timeoutSeconds': _remainingSeconds(phase.endsAt),
        'timeoutAtMs': phase.endsAt.millisecondsSinceEpoch,
      };
      payload['round'] = {
        'roundId': phase.roundId,
        'categoryLabel': round?.categoryLabel ?? '',
        'currentSetIndex': phase.setIndex,
        'setPromptCount': setPromptCount,
        'setSuperlatives': _superlativesList(phase.setSuperlatives),
        'setTimeoutSeconds': _remainingSeconds(phase.endsAt),
        'setTimeoutAtMs': phase.endsAt.millisecondsSinceEpoch,
      };
      if (role == 'display') {
        var completedPlayerIds = <String>[];
        for (var player in snapshot.activePlayerSessions) {
          var promptIndex = phase.promptIndexByPlayer[player.playerId] ?? 0;
          if (promptIndex >= setPromptCount) {
            completedPlayerIds.add(player.playerId);
          }
        }
        completedPlayerIds.sort();
        payload['round']['completedPlayerIds'] = completedPlayerIds;
      }

      if (role == 'player' && viewer != null) {
        payload['youVoted'] = isDone;
        payload['yourVoteEntryId'] = isDone
            ? null
            : _voteSelectionForPrompt(
                round: round,
                setIndex: phase.setIndex,
                promptIndex: activePromptIndex,
                playerId: viewer.playerId,
              );
        payload['round']['currentPromptIndexForYou'] = promptIndex;
      }
      return;
    }

    if (phase is VoteRevealPhase) {
      payload['reveal'] = {
        'roundId': phase.roundId,
        'voteIndex': phase.voteIndex,
        'setIndex': phase.setIndex,
        'superlativeId': phase.superlativeId,
        'promptText': phase.promptText,
        'entries': _entriesView(snapshot, round, includeOwner: false),
        'promptResults': _voteRevealPromptResults(
          round: round,
          phase: phase,
        ),
        'roundPointsByEntry':
            round?.roundPointsByEntry ?? const <String, int>{},
        'results': {
          'voteCountByEntry': phase.results.voteCountByEntry,
          'pointsByEntry': phase.results.pointsByEntry,
          'pointsByPlayer': phase.results.pointsByPlayer,
        },
        'timeoutSeconds': _remainingSeconds(phase.endsAt),
        'timeoutAtMs': phase.endsAt.millisecondsSinceEpoch,
      };
      return;
    }

    if (phase is RoundSummaryPhase) {
      payload['roundSummary'] = {
        'roundIndex': phase.roundIndex,
        'roundId': phase.roundId,
        'playerRoundResults': _roundSummaryRows(snapshot, round),
        'superlativeResults': _roundSummarySuperlativeResults(snapshot, round),
        'timeoutSeconds': _remainingSeconds(phase.endsAt),
        'timeoutAtMs': phase.endsAt.millisecondsSinceEpoch,
      };
      return;
    }

    if (phase is GameSummaryPhase) {
      payload['gameSummary'] = {
        'gameId': phase.gameId,
        'timeoutSeconds':
            phase.endsAt == null ? null : _remainingSeconds(phase.endsAt!),
        'timeoutAtMs':
            phase.endsAt == null ? null : phase.endsAt!.millisecondsSinceEpoch,
      };
      return;
    }
  }

  List<Map<String, dynamic>> _playerList(SuperlativesRoomSnapshot snapshot) {
    var players = snapshot.players.values.toList()
      ..sort((a, b) => a.playerId.compareTo(b.playerId));

    return players
        .map((p) => {
              'playerId': p.playerId,
              'displayName': p.displayName,
              'role': p.role.name,
              'state': p.state.name,
              'currentEntryId': p.currentEntryId,
            })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _leaderboard(SuperlativesRoomSnapshot snapshot) {
    var scores =
        Map<String, int>.from(snapshot.currentGame?.scoreboard ?? const {});

    for (var p
        in snapshot.players.values.where((p) => p.role == SessionRole.player)) {
      scores[p.playerId] ??= 0;
    }

    var rows = scores.entries
        .map((e) => {
              'playerId': e.key,
              'displayName': snapshot.players[e.key]?.displayName ?? e.key,
              'score': e.value,
            })
        .toList();

    rows.sort((a, b) {
      var scoreCmp = (b['score'] as int).compareTo(a['score'] as int);
      if (scoreCmp != 0) {
        return scoreCmp;
      }
      return (a['playerId'] as String).compareTo(b['playerId'] as String);
    });

    return rows;
  }

  List<Map<String, dynamic>> _entriesView(
    SuperlativesRoomSnapshot snapshot,
    RoundInstance? round, {
    required bool includeOwner,
    bool includeEliminated = true,
  }) {
    if (round == null) {
      return const [];
    }

    var entries = List<Entry>.of(round.entries)
      ..removeWhere((e) => !includeEliminated && e.status != EntryStatus.active)
      ..sort((a, b) => a.entryId.compareTo(b.entryId));

    return entries.map((e) {
      var row = <String, dynamic>{
        'entryId': e.entryId,
        'text': e.textOriginal,
        'status': e.status.name,
      };
      if (includeOwner) {
        row['ownerPlayerId'] = e.ownerPlayerId;
        row['ownerDisplayName'] =
            snapshot.players[e.ownerPlayerId]?.displayName ?? e.ownerPlayerId;
      }
      return row;
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> _superlativesList(
      List<SuperlativePrompt> prompts) {
    return prompts
        .map((p) => {
              'superlativeId': p.superlativeId,
              'promptText': p.promptText,
            })
        .toList(growable: false);
  }

  RoundInstance? _currentRound(SuperlativesRoomSnapshot snapshot) {
    var game = snapshot.currentGame;
    if (game == null || game.rounds.isEmpty) {
      return null;
    }

    return game.rounds.last;
  }

  int _remainingSeconds(DateTime endsAt) {
    var millis = endsAt.difference(_now()).inMilliseconds;
    if (millis <= 0) {
      return 0;
    }

    return (millis + 999) ~/ 1000;
  }

  int _projectedPromptIndex({
    required VoteInputPhase phase,
    required SuperlativesRoomSnapshot snapshot,
    required PlayerSession? viewer,
    required String role,
  }) {
    var setPromptCount = phase.setSuperlatives.length;
    if (role == 'player' && viewer != null) {
      return phase.promptIndexByPlayer[viewer.playerId] ?? 0;
    }

    var min = setPromptCount;
    for (var player in snapshot.activePlayerSessions) {
      var value = phase.promptIndexByPlayer[player.playerId] ?? 0;
      if (value < min) {
        min = value;
      }
    }
    if (min == setPromptCount) {
      return setPromptCount - 1;
    }
    return min;
  }

  String? _voteSelectionForPrompt({
    required RoundInstance? round,
    required int setIndex,
    required int promptIndex,
    required String playerId,
  }) {
    if (round == null ||
        setIndex < 0 ||
        setIndex >= round.voteSets.length ||
        promptIndex < 0 ||
        promptIndex >= round.voteSets[setIndex].prompts.length) {
      return null;
    }
    return round
        .voteSets[setIndex].prompts[promptIndex].votesByPlayer[playerId];
  }

  List<Map<String, dynamic>> _roundSummaryRows(
    SuperlativesRoomSnapshot snapshot,
    RoundInstance? round,
  ) {
    if (round == null) {
      return const [];
    }

    var entryByOwner = <String, Entry>{};
    for (var entry in round.entries) {
      entryByOwner[entry.ownerPlayerId] = entry;
    }
    var roundPointsByPlayer = _roundPointsByPlayer(round);

    var rows = snapshot.players.values
        .where((p) => p.role == SessionRole.player)
        .map((p) {
      var scoreBeforeRound = snapshot.currentGame?.scoreboard[p.playerId] ?? 0;
      var entry = entryByOwner[p.playerId];
      var pointsThisRound = roundPointsByPlayer[p.playerId] ?? 0;
      return <String, dynamic>{
        'playerId': p.playerId,
        'displayName': p.displayName,
        'totalScore': scoreBeforeRound + pointsThisRound,
        'entryText': entry?.textOriginal,
        'pointsThisRound': pointsThisRound,
      };
    }).toList();

    rows.sort((a, b) {
      var scoreCmp = (b['totalScore'] as int).compareTo(a['totalScore'] as int);
      if (scoreCmp != 0) {
        return scoreCmp;
      }
      return (a['playerId'] as String).compareTo(b['playerId'] as String);
    });

    return rows;
  }

  List<Map<String, dynamic>> _roundSummarySuperlativeResults(
    SuperlativesRoomSnapshot snapshot,
    RoundInstance? round,
  ) {
    if (round == null) {
      return const [];
    }

    var rows = <Map<String, dynamic>>[];
    for (var set in round.voteSets) {
      for (var prompt in set.prompts) {
        var voteCountByEntry = <String, int>{};
        for (var entryId in prompt.votesByPlayer.values) {
          voteCountByEntry[entryId] = (voteCountByEntry[entryId] ?? 0) + 1;
        }

        var ranked = round.entries
            .map((entry) => {
                  'entryId': entry.entryId,
                  'entryText': entry.textOriginal,
                  'ownerDisplayName':
                      snapshot.players[entry.ownerPlayerId]?.displayName ??
                          entry.ownerPlayerId,
                  'voteCount': voteCountByEntry[entry.entryId] ?? 0,
                })
            .where((row) => (row['voteCount'] as int) > 0)
            .toList();

        ranked.sort((a, b) {
          var countCmp =
              (b['voteCount'] as int).compareTo(a['voteCount'] as int);
          if (countCmp != 0) {
            return countCmp;
          }
          return (a['entryId'] as String).compareTo(b['entryId'] as String);
        });

        var top = ranked.take(3).toList(growable: false);
        for (var i = 0; i < top.length; i++) {
          top[i]['rank'] = i + 1;
        }

        rows.add({
          'superlativeId': prompt.superlativeId,
          'promptText': prompt.promptText,
          'topEntries': top,
        });
      }
    }

    return rows;
  }

  Map<String, int> _roundPointsByPlayer(RoundInstance round) {
    var entryOwnerById = <String, String>{};
    for (var entry in round.entries) {
      entryOwnerById[entry.entryId] = entry.ownerPlayerId;
    }

    var pointsByPlayer = <String, int>{};
    for (var entry in round.roundPointsByEntry.entries) {
      var owner = entryOwnerById[entry.key];
      if (owner == null) {
        continue;
      }
      pointsByPlayer[owner] = (pointsByPlayer[owner] ?? 0) + entry.value;
    }
    return pointsByPlayer;
  }

  List<Map<String, dynamic>> _voteRevealPromptResults({
    required RoundInstance? round,
    required VoteRevealPhase phase,
  }) {
    if (round == null ||
        phase.setIndex < 0 ||
        phase.setIndex >= round.voteSets.length) {
      return _fallbackVoteRevealPromptResults(phase);
    }

    var prompts = round.voteSets[phase.setIndex].prompts;
    if (prompts.isEmpty) {
      return _fallbackVoteRevealPromptResults(phase);
    }

    var rows = prompts.map((prompt) {
      var results = prompt.results;
      return <String, dynamic>{
        'promptIndex': prompt.promptIndex,
        'superlativeId': prompt.superlativeId,
        'promptText': prompt.promptText,
        'results': {
          'voteCountByEntry': results?.voteCountByEntry ?? const <String, int>{},
          'pointsByEntry': results?.pointsByEntry ?? const <String, int>{},
          'pointsByPlayer': results?.pointsByPlayer ?? const <String, int>{},
        },
      };
    }).toList(growable: false);

    rows.sort((a, b) =>
        (a['promptIndex'] as int).compareTo(b['promptIndex'] as int));
    return rows;
  }

  List<Map<String, dynamic>> _fallbackVoteRevealPromptResults(
      VoteRevealPhase phase) {
    var prompts = phase.setSuperlatives;
    if (prompts.isEmpty) {
      return const [];
    }

    return prompts.asMap().entries.map((entry) {
      var prompt = entry.value;
      var index = entry.key;
      var results = index == 0 ? phase.results : null;
      return <String, dynamic>{
        'promptIndex': index,
        'superlativeId': prompt.superlativeId,
        'promptText': prompt.promptText,
        'results': {
          'voteCountByEntry': results?.voteCountByEntry ?? const <String, int>{},
          'pointsByEntry': results?.pointsByEntry ?? const <String, int>{},
          'pointsByPlayer': results?.pointsByPlayer ?? const <String, int>{},
        },
      };
    }).toList(growable: false);
  }
}
