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
        'canStart':
            snapshot.activePlayerCount >= snapshot.config.minPlayersToStart
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
      };
      return;
    }

    if (phase is EntryInputPhase) {
      payload['round'] = {
        'roundIndex': phase.roundIndex,
        'roundId': phase.roundId,
        'categoryLabel': phase.categoryLabel,
        'entries': _entriesView(snapshot, round),
        'timeoutSeconds': _remainingSeconds(phase.endsAt),
      };

      if (role == 'player' && viewer != null) {
        payload['youSubmitted'] =
            phase.submittedPlayerIds.contains(viewer.playerId);
      }
      return;
    }

    if (phase is VoteInputPhase) {
      payload['vote'] = {
        'roundId': phase.roundId,
        'voteIndex': phase.voteIndex,
        'superlativeId': phase.superlativeId,
        'promptText': phase.promptText,
        'entries': _entriesView(snapshot, round),
        'timeoutSeconds': _remainingSeconds(phase.endsAt),
      };

      if (role == 'player' && viewer != null) {
        payload['youVoted'] = phase.votesByPlayer.containsKey(viewer.playerId);
        payload['yourVoteEntryId'] = phase.votesByPlayer[viewer.playerId];
      }
      return;
    }

    if (phase is VoteRevealPhase) {
      payload['reveal'] = {
        'roundId': phase.roundId,
        'voteIndex': phase.voteIndex,
        'superlativeId': phase.superlativeId,
        'promptText': phase.promptText,
        'entries': _entriesView(snapshot, round),
        'results': {
          'voteCountByEntry': phase.results.voteCountByEntry,
          'pointsByEntry': phase.results.pointsByEntry,
          'pointsByPlayer': phase.results.pointsByPlayer,
        },
        'timeoutSeconds': _remainingSeconds(phase.endsAt),
      };
      return;
    }

    if (phase is RoundSummaryPhase) {
      payload['roundSummary'] = {
        'roundIndex': phase.roundIndex,
        'roundId': phase.roundId,
        'timeoutSeconds': _remainingSeconds(phase.endsAt),
      };
      return;
    }

    if (phase is GameSummaryPhase) {
      payload['gameSummary'] = {
        'gameId': phase.gameId,
        'timeoutSeconds':
            phase.endsAt == null ? null : _remainingSeconds(phase.endsAt!),
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
    RoundInstance? round,
  ) {
    if (round == null) {
      return const [];
    }

    var entries = List<Entry>.of(round.entries)
      ..sort((a, b) => a.entryId.compareTo(b.entryId));

    return entries
        .map((e) => {
              'entryId': e.entryId,
              'ownerPlayerId': e.ownerPlayerId,
              'ownerDisplayName':
                  snapshot.players[e.ownerPlayerId]?.displayName ??
                      e.ownerPlayerId,
              'text': e.textOriginal,
              'status': e.status.name,
            })
        .toList(growable: false);
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
}
