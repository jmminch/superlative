import 'dart:async';

import 'superlatives_game.dart';

typedef CancelTimer = void Function();

abstract class PhaseTimerScheduler {
  CancelTimer schedule(Duration delay, void Function() callback);
}

class DartPhaseTimerScheduler implements PhaseTimerScheduler {
  @override
  CancelTimer schedule(Duration delay, void Function() callback) {
    var timer = Timer(delay, callback);
    return () {
      if (timer.isActive) {
        timer.cancel();
      }
    };
  }
}

enum HostControlEvent {
  startGame,
  advance,
  endGame,
}

class RoomStateMachine {
  SuperlativesRoomSnapshot snapshot;

  final PhaseTimerScheduler _timerScheduler;
  final DateTime Function() _now;
  final Duration hostGraceDuration;
  final void Function(SuperlativesRoomSnapshot snapshot)? onAutoTransition;
  final bool Function(GamePhaseState phase)? onAutoTimeout;

  CancelTimer? _cancelPhaseTimer;
  CancelTimer? _cancelHostGraceTimer;

  RoomStateMachine({
    required this.snapshot,
    PhaseTimerScheduler? timerScheduler,
    DateTime Function()? now,
    Duration? hostGraceDuration,
    this.onAutoTransition,
    this.onAutoTimeout,
  })  : _timerScheduler = timerScheduler ?? DartPhaseTimerScheduler(),
        _now = now ?? DateTime.now,
        hostGraceDuration = hostGraceDuration ?? const Duration(seconds: 10) {
    _schedulePhaseTimerForCurrentState();
  }

  bool transitionTo(GamePhaseState newPhase) {
    if (!_isValidTransition(snapshot.phase, newPhase)) {
      return false;
    }

    _applyPhase(newPhase);
    return true;
  }

  bool replaceCurrentPhase(GamePhaseState newPhase) {
    if (snapshot.phase.runtimeType != newPhase.runtimeType) {
      return false;
    }

    _applyPhase(newPhase);
    return true;
  }

  bool canPlayerControl(String playerId, HostControlEvent event) {
    if (event == HostControlEvent.startGame && snapshot.phase is LobbyPhase) {
      var starter = snapshot.players[playerId];
      if (starter == null || starter.role != SessionRole.player) {
        return false;
      }
      return starter.state == PlayerSessionState.active;
    }

    var hostId = snapshot.hostPlayerId;
    if (hostId == null) {
      return false;
    }

    if (playerId != hostId) {
      return false;
    }

    var host = snapshot.players[hostId];
    if (host == null || host.role != SessionRole.player) {
      return false;
    }

    return true;
  }

  bool onHostControl(
    String playerId,
    HostControlEvent event, {
    String? roundId,
    String? categoryLabel,
    List<SuperlativePrompt>? superlatives,
    DateTime? gameStartingEndsAt,
    bool? showGameStartingInstructions,
    DateTime? roundIntroEndsAt,
  }) {
    if (!canPlayerControl(playerId, event)) {
      return false;
    }

    switch (event) {
      case HostControlEvent.startGame:
        if (snapshot.phase is! LobbyPhase) {
          return false;
        }
        if (snapshot.activePlayerSessions.length <
            snapshot.config.minPlayersToStart) {
          return false;
        }
        var effectiveGameStartingEndsAt =
            gameStartingEndsAt ?? roundIntroEndsAt;
        var effectiveShowInstructions = showGameStartingInstructions ?? true;
        if (roundId == null ||
            categoryLabel == null ||
            superlatives == null ||
            superlatives.isEmpty ||
            effectiveGameStartingEndsAt == null) {
          return false;
        }

        snapshot = snapshot.copyWith(
          hostPlayerId: playerId,
          updatedAt: _now(),
        );

        return transitionTo(
          GameStartingPhase(
            roundIndex: 0,
            roundId: roundId,
            categoryLabel: categoryLabel,
            superlatives: superlatives,
            endsAt: effectiveGameStartingEndsAt,
            showInstructions: effectiveShowInstructions,
          ),
        );

      case HostControlEvent.advance:
        if (snapshot.phase is GameStartingPhase) {
          return onGameStartingTimeout();
        }
        if (snapshot.phase is RoundIntroPhase) {
          return onRoundIntroTimeout();
        }
        if (snapshot.phase is VoteRevealPhase) {
          return onRevealTimeout();
        }
        if (snapshot.phase is GameSummaryPhase) {
          return transitionTo(const LobbyPhase());
        }
        return false;

      case HostControlEvent.endGame:
        if (snapshot.phase is LobbyPhase) {
          return false;
        }
        _forcePhase(const LobbyPhase());
        return true;
    }
  }

  bool onRoundIntroTimeout() {
    var phase = snapshot.phase;
    if (phase is! RoundIntroPhase) {
      return false;
    }

    var entryEndsAt =
        _now().add(Duration(seconds: snapshot.config.entryInputSeconds));
    return transitionTo(
      EntryInputPhase(
        roundIndex: phase.roundIndex,
        roundId: phase.roundId,
        categoryLabel: phase.categoryLabel,
        superlatives: phase.superlatives,
        initialEndsAt: entryEndsAt,
        endsAt: entryEndsAt,
        submittedPlayerIds: <String>{},
      ),
    );
  }

  bool onGameStartingTimeout() {
    var phase = snapshot.phase;
    if (phase is! GameStartingPhase) {
      return false;
    }

    return transitionTo(
      RoundIntroPhase(
        roundIndex: phase.roundIndex,
        roundId: phase.roundId,
        categoryLabel: phase.categoryLabel,
        superlatives: phase.superlatives,
        endsAt: _now().add(const Duration(seconds: 5)),
      ),
    );
  }

  bool onEntryTimeout() {
    var phase = snapshot.phase;
    if (phase is! EntryInputPhase) {
      return false;
    }

    var firstSetSuperlatives =
        _superlativesForSet(phase.superlatives, setIndex: 0);
    if (firstSetSuperlatives.isEmpty) {
      return false;
    }
    var firstSuperlative = firstSetSuperlatives.first;
    return transitionTo(
      VoteInputPhase(
        roundIndex: phase.roundIndex,
        roundId: phase.roundId,
        voteIndex: 0,
        setIndex: 0,
        superlativeId: firstSuperlative.superlativeId,
        promptText: firstSuperlative.promptText,
        roundSuperlatives: phase.superlatives,
        setSuperlatives: firstSetSuperlatives,
        endsAt: _now().add(Duration(seconds: snapshot.config.setInputSeconds)),
        votesByPlayer: const {},
        promptIndexByPlayer: const {},
      ),
    );
  }

  bool onVoteTimeout() {
    var phase = snapshot.phase;
    if (phase is! VoteInputPhase) {
      return false;
    }

    return transitionTo(
      VoteRevealPhase(
        roundIndex: phase.roundIndex,
        roundId: phase.roundId,
        voteIndex: phase.voteIndex,
        setIndex: phase.setIndex,
        superlativeId: phase.superlativeId,
        promptText: 'Set ${phase.setIndex + 1} results',
        roundSuperlatives: phase.roundSuperlatives,
        setSuperlatives: phase.setSuperlatives,
        results: VoteResults(
          voteCountByEntry: const {},
          pointsByEntry: const {},
          pointsByPlayer: const {},
        ),
        endsAt: _now().add(Duration(seconds: snapshot.config.revealSeconds)),
      ),
    );
  }

  bool onRevealTimeout() {
    var phase = snapshot.phase;
    if (phase is! VoteRevealPhase) {
      return false;
    }

    var nextSetIndex = phase.setIndex + 1;
    var nextSetSuperlatives = _superlativesForSet(
      phase.roundSuperlatives,
      setIndex: nextSetIndex,
    );
    if (nextSetSuperlatives.isNotEmpty) {
      var nextSuperlative = nextSetSuperlatives.first;
      return transitionTo(
        VoteInputPhase(
          roundIndex: phase.roundIndex,
          roundId: phase.roundId,
          voteIndex: nextSetIndex,
          setIndex: nextSetIndex,
          superlativeId: nextSuperlative.superlativeId,
          promptText: nextSuperlative.promptText,
          roundSuperlatives: phase.roundSuperlatives,
          setSuperlatives: nextSetSuperlatives,
          endsAt:
              _now().add(Duration(seconds: snapshot.config.setInputSeconds)),
          votesByPlayer: const {},
          promptIndexByPlayer: const {},
        ),
      );
    }

    return transitionTo(
      RoundSummaryPhase(
        roundIndex: phase.roundIndex,
        roundId: phase.roundId,
        endsAt: _now().add(Duration(seconds: snapshot.config.revealSeconds)),
      ),
    );
  }

  bool onPlayerDisconnected(String playerId) {
    var player = snapshot.players[playerId];
    if (player == null) {
      return false;
    }

    if (player.state == PlayerSessionState.disconnected) {
      return true;
    }

    var updatedPlayers = Map<String, PlayerSession>.from(snapshot.players);
    updatedPlayers[playerId] =
        player.copyWith(state: PlayerSessionState.disconnected);

    snapshot = snapshot.copyWith(players: updatedPlayers, updatedAt: _now());

    if (snapshot.hostPlayerId == playerId) {
      _scheduleHostGraceTimer();
    }

    return true;
  }

  bool onPlayerReconnected(String playerId) {
    var player = snapshot.players[playerId];
    if (player == null) {
      return false;
    }

    var updatedPlayers = Map<String, PlayerSession>.from(snapshot.players);
    updatedPlayers[playerId] =
        player.copyWith(state: PlayerSessionState.active);

    snapshot = snapshot.copyWith(players: updatedPlayers, updatedAt: _now());

    if (snapshot.hostPlayerId == playerId) {
      _cancelHostGraceTimer?.call();
      _cancelHostGraceTimer = null;
    }

    return true;
  }

  bool _isValidTransition(GamePhaseState from, GamePhaseState to) {
    if (from is LobbyPhase) {
      return to is GameStartingPhase;
    }
    if (from is GameStartingPhase) {
      return to is RoundIntroPhase || to is LobbyPhase;
    }
    if (from is RoundIntroPhase) {
      return to is EntryInputPhase || to is LobbyPhase;
    }
    if (from is EntryInputPhase) {
      return to is VoteInputPhase || to is LobbyPhase;
    }
    if (from is VoteInputPhase) {
      return to is VoteRevealPhase || to is LobbyPhase;
    }
    if (from is VoteRevealPhase) {
      return to is VoteInputPhase ||
          to is RoundSummaryPhase ||
          to is LobbyPhase;
    }
    if (from is RoundSummaryPhase) {
      return to is RoundIntroPhase ||
          to is GameSummaryPhase ||
          to is LobbyPhase;
    }
    if (from is GameSummaryPhase) {
      return to is LobbyPhase;
    }
    return false;
  }

  void _applyPhase(GamePhaseState newPhase) {
    _cancelPhaseTimer?.call();
    _cancelPhaseTimer = null;

    snapshot = snapshot.copyWith(phase: newPhase, updatedAt: _now());
    _schedulePhaseTimerForCurrentState();
  }

  void _forcePhase(GamePhaseState newPhase) {
    _cancelPhaseTimer?.call();
    _cancelPhaseTimer = null;
    snapshot = snapshot.copyWith(phase: newPhase, updatedAt: _now());
    _schedulePhaseTimerForCurrentState();
  }

  void _schedulePhaseTimerForCurrentState() {
    var endsAt = _phaseEndsAt(snapshot.phase);
    if (endsAt == null) {
      return;
    }

    var delay = endsAt.difference(_now());
    if (delay.isNegative) {
      delay = Duration.zero;
    }

    _cancelPhaseTimer = _timerScheduler.schedule(delay, _onPhaseTimerExpired);
  }

  DateTime? _phaseEndsAt(GamePhaseState phase) {
    if (phase is GameStartingPhase) {
      return phase.endsAt;
    }
    if (phase is RoundIntroPhase) {
      return phase.endsAt;
    }
    if (phase is EntryInputPhase) {
      return phase.endsAt;
    }
    if (phase is VoteInputPhase) {
      return phase.endsAt;
    }
    if (phase is VoteRevealPhase) {
      return phase.endsAt;
    }
    if (phase is RoundSummaryPhase) {
      return phase.endsAt;
    }
    if (phase is GameSummaryPhase) {
      return phase.endsAt;
    }
    return null;
  }

  void _onPhaseTimerExpired() {
    _cancelPhaseTimer = null;

    var phase = snapshot.phase;
    if (onAutoTimeout != null && onAutoTimeout!(phase)) {
      return;
    }

    if (phase is GameStartingPhase) {
      if (onGameStartingTimeout()) {
        onAutoTransition?.call(snapshot);
      }
      return;
    }
    if (phase is RoundIntroPhase) {
      if (onRoundIntroTimeout()) {
        onAutoTransition?.call(snapshot);
      }
      return;
    }
    if (phase is EntryInputPhase) {
      if (onEntryTimeout()) {
        onAutoTransition?.call(snapshot);
      }
      return;
    }
    if (phase is VoteInputPhase) {
      if (onVoteTimeout()) {
        onAutoTransition?.call(snapshot);
      }
      return;
    }
    if (phase is VoteRevealPhase) {
      if (onRevealTimeout()) {
        onAutoTransition?.call(snapshot);
      }
      return;
    }
  }

  void _scheduleHostGraceTimer() {
    _cancelHostGraceTimer?.call();
    _cancelHostGraceTimer =
        _timerScheduler.schedule(hostGraceDuration, _onHostGraceTimeout);
  }

  void _onHostGraceTimeout() {
    _cancelHostGraceTimer = null;

    var hostId = snapshot.hostPlayerId;
    if (hostId == null) {
      return;
    }

    var host = snapshot.players[hostId];
    if (host != null && host.state == PlayerSessionState.active) {
      return;
    }

    var candidates = snapshot.activePlayerSessions.toList()
      ..sort((a, b) => a.playerId.compareTo(b.playerId));

    if (candidates.isEmpty) {
      return;
    }

    snapshot = snapshot.copyWith(
      hostPlayerId: candidates.first.playerId,
      updatedAt: _now(),
    );
    onAutoTransition?.call(snapshot);
  }

  List<SuperlativePrompt> _superlativesForSet(
    List<SuperlativePrompt> all, {
    required int setIndex,
  }) {
    if (setIndex < 0 || setIndex >= snapshot.config.setCount || all.isEmpty) {
      return const [];
    }

    var promptsPerSet = snapshot.config.promptsPerSet;
    var start = setIndex * promptsPerSet;
    if (start >= all.length) {
      return const [];
    }

    var end = start + promptsPerSet;
    if (end > all.length) {
      end = all.length;
    }
    return List<SuperlativePrompt>.unmodifiable(all.sublist(start, end));
  }
}
