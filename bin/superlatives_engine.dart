import 'dart:math';

import 'scoring.dart';
import 'superlatives_game.dart';
import 'superlatives_state_machine.dart';

class GameEngine {
  final RoomStateMachine stateMachine;
  final Random _random;
  final DateTime Function() _now;
  static const Duration secondEntryGrace = Duration(seconds: 5);

  int _gameSeq = 0;
  int _entrySeq = 0;

  GameEngine({
    required this.stateMachine,
    Random? random,
    DateTime Function()? now,
  })  : _random = random ?? Random(),
        _now = now ?? DateTime.now;

  SuperlativesRoomSnapshot get snapshot => stateMachine.snapshot;

  List<SuperlativePrompt> selectRoundSuperlatives(
    List<SuperlativePrompt> pool, {
    int? count,
  }) {
    var selectCount = count ?? snapshot.config.votePhasesPerRound;
    if (pool.length < selectCount) {
      throw ArgumentError(
          'Pool has ${pool.length} prompts, need $selectCount.');
    }

    var prompts = List<SuperlativePrompt>.of(pool);
    prompts.shuffle(_random);
    return List<SuperlativePrompt>.unmodifiable(prompts.take(selectCount));
  }

  bool startGame({
    required String hostPlayerId,
    required String firstRoundCategoryId,
    required String firstRoundCategoryLabel,
    required List<SuperlativePrompt> firstRoundSuperlatives,
    DateTime? roundIntroEndsAt,
  }) {
    if (snapshot.phase is! LobbyPhase) {
      return false;
    }

    _admitPendingPlayers();

    var activePlayers = snapshot.activePlayerSessions.toList();
    if (activePlayers.length < snapshot.config.minPlayersToStart) {
      return false;
    }

    var scoreboard = <String, int>{};
    for (var player in activePlayers) {
      scoreboard[player.playerId] = 0;
    }

    var game = GameInstance(
      gameId: _newGameId(),
      roundIndex: 0,
      rounds: const [],
      scoreboard: scoreboard,
    );

    stateMachine.snapshot = snapshot.copyWith(
      currentGame: game,
      updatedAt: _now(),
    );

    if (!_appendRound(
      roundIndex: 0,
      categoryId: firstRoundCategoryId,
      categoryLabel: firstRoundCategoryLabel,
      superlatives: firstRoundSuperlatives,
      markActive: true,
    )) {
      return false;
    }

    return stateMachine.onHostControl(
      hostPlayerId,
      HostControlEvent.startGame,
      roundId: _currentRound()!.roundId,
      categoryLabel: firstRoundCategoryLabel,
      superlatives: firstRoundSuperlatives,
      roundIntroEndsAt:
          roundIntroEndsAt ?? _now().add(const Duration(seconds: 5)),
    );
  }

  bool startRound({
    required String categoryId,
    required String categoryLabel,
    required List<SuperlativePrompt> superlatives,
    DateTime? roundIntroEndsAt,
  }) {
    if (snapshot.currentGame == null || snapshot.phase is! RoundSummaryPhase) {
      return false;
    }

    _admitPendingPlayers();

    var roundIndex = snapshot.currentGame!.rounds.length;
    if (!_appendRound(
      roundIndex: roundIndex,
      categoryId: categoryId,
      categoryLabel: categoryLabel,
      superlatives: superlatives,
      markActive: true,
    )) {
      return false;
    }

    return stateMachine.transitionTo(
      RoundIntroPhase(
        roundIndex: roundIndex,
        roundId: _currentRound()!.roundId,
        categoryLabel: categoryLabel,
        superlatives: superlatives,
        endsAt: roundIntroEndsAt ?? _now().add(const Duration(seconds: 5)),
      ),
    );
  }

  bool openEntryInput() {
    return stateMachine.onRoundIntroTimeout();
  }

  bool closeEntryInput() {
    return stateMachine.onEntryTimeout();
  }

  bool openVotePhase({required int voteIndex}) {
    var phase = snapshot.phase;
    if (phase is! EntryInputPhase && phase is! VoteRevealPhase) {
      return false;
    }

    var round = _currentRound();
    if (round == null ||
        voteIndex < 0 ||
        voteIndex >= round.votePhases.length) {
      return false;
    }

    var vote = round.votePhases[voteIndex];
    var roundSuperlatives = round.votePhases
        .map((v) => SuperlativePrompt(
            superlativeId: v.superlativeId, promptText: v.promptText))
        .toList(growable: false);

    return stateMachine.transitionTo(
      VoteInputPhase(
        roundIndex: round.status == RoundStatus.complete
            ? round.votePhases.length
            : snapshot.currentGame!.roundIndex,
        roundId: round.roundId,
        voteIndex: voteIndex,
        superlativeId: vote.superlativeId,
        promptText: vote.promptText,
        roundSuperlatives: roundSuperlatives,
        endsAt: _now().add(Duration(seconds: snapshot.config.voteInputSeconds)),
        votesByPlayer: vote.votesByPlayer,
      ),
    );
  }

  bool submitEntry({required String playerId, required String text}) {
    var phase = snapshot.phase;
    if (phase is! EntryInputPhase) {
      return false;
    }

    var player = snapshot.players[playerId];
    if (player == null ||
        player.role != SessionRole.player ||
        player.state != PlayerSessionState.active) {
      return false;
    }

    var validation =
        SuperlativesValidation.validateEntryText(text, config: snapshot.config);
    if (!validation.ok) {
      return false;
    }

    var normalizedText = SuperlativesValidation.normalizeEntryText(text);

    var round = _currentRound();
    if (round == null) {
      return false;
    }

    var entries = List<Entry>.of(round.entries);
    var existingIndex = entries.indexWhere((e) => e.ownerPlayerId == playerId);

    String entryId;
    if (existingIndex >= 0) {
      entryId = entries[existingIndex].entryId;
      entries[existingIndex] = Entry(
        entryId: entryId,
        ownerPlayerId: playerId,
        textOriginal: normalizedText,
        textNormalized: normalizedText,
      );
    } else {
      entryId = _newEntryId(round.roundId, playerId);
      entries.add(
        Entry(
          entryId: entryId,
          ownerPlayerId: playerId,
          textOriginal: normalizedText,
          textNormalized: normalizedText,
        ),
      );
    }

    var updatedPlayers = Map<String, PlayerSession>.from(snapshot.players);
    updatedPlayers[playerId] = player.copyWith(currentEntryId: entryId);

    var updatedRound = RoundInstance(
      roundId: round.roundId,
      categoryId: round.categoryId,
      categoryLabel: round.categoryLabel,
      entries: entries,
      votePhases: round.votePhases,
      status: round.status,
    );

    _replaceCurrentRound(updatedRound);

    var submitted = Set<String>.of(phase.submittedPlayerIds)..add(playerId);
    var now = _now();
    DateTime? earliestVoteAt = phase.earliestVoteAt;
    if (updatedRound.entries.length >= 2 && earliestVoteAt == null) {
      earliestVoteAt = now.add(secondEntryGrace);
    }

    var nextEndsAt = phase.endsAt;
    if (earliestVoteAt != null && nextEndsAt.isBefore(earliestVoteAt)) {
      nextEndsAt = earliestVoteAt;
    }

    stateMachine.snapshot = snapshot.copyWith(
      players: updatedPlayers,
      phase: EntryInputPhase(
        roundIndex: phase.roundIndex,
        roundId: phase.roundId,
        categoryLabel: phase.categoryLabel,
        superlatives: phase.superlatives,
        endsAt: nextEndsAt,
        earliestVoteAt: earliestVoteAt,
        submittedPlayerIds: submitted,
      ),
      updatedAt: _now(),
    );

    var activePlayerIds =
        snapshot.activePlayerSessions.map((p) => p.playerId).toSet();
    if (updatedRound.entries.length >= 2 &&
        activePlayerIds.isNotEmpty &&
        submitted.containsAll(activePlayerIds)) {
      closeEntryInput();
    }

    return true;
  }

  bool submitVote({required String playerId, required String entryId}) {
    var phase = snapshot.phase;
    if (phase is! VoteInputPhase) {
      return false;
    }

    var voter = snapshot.players[playerId];
    if (voter == null) {
      return false;
    }

    var round = _currentRound();
    if (round == null || phase.voteIndex >= round.votePhases.length) {
      return false;
    }

    Entry? targetEntry;
    for (var entry in round.entries) {
      if (entry.entryId == entryId) {
        targetEntry = entry;
        break;
      }
    }

    if (targetEntry == null) {
      return false;
    }

    if (!SuperlativesValidation.canPlayerVoteForEntry(
      config: snapshot.config,
      voter: voter,
      entry: targetEntry,
    )) {
      return false;
    }

    var votesMap = Map<String, String>.from(phase.votesByPlayer);
    votesMap[playerId] = entryId;

    var updatedVotePhases = List<VotePhase>.of(round.votePhases);
    var existingVote = updatedVotePhases[phase.voteIndex];
    updatedVotePhases[phase.voteIndex] = VotePhase(
      voteIndex: existingVote.voteIndex,
      superlativeId: existingVote.superlativeId,
      promptText: existingVote.promptText,
      votesByPlayer: votesMap,
      results: existingVote.results,
    );

    var updatedRound = RoundInstance(
      roundId: round.roundId,
      categoryId: round.categoryId,
      categoryLabel: round.categoryLabel,
      entries: round.entries,
      votePhases: updatedVotePhases,
      status: round.status,
    );

    _replaceCurrentRound(updatedRound);

    stateMachine.snapshot = snapshot.copyWith(
      phase: VoteInputPhase(
        roundIndex: phase.roundIndex,
        roundId: phase.roundId,
        voteIndex: phase.voteIndex,
        superlativeId: phase.superlativeId,
        promptText: phase.promptText,
        roundSuperlatives: phase.roundSuperlatives,
        endsAt: phase.endsAt,
        votesByPlayer: votesMap,
      ),
      updatedAt: _now(),
    );

    return true;
  }

  bool closeVotePhase() {
    var phase = snapshot.phase;
    if (phase is! VoteInputPhase) {
      return false;
    }

    var round = _currentRound();
    if (round == null || phase.voteIndex >= round.votePhases.length) {
      return false;
    }

    var voteResults = ScoringEngine.scoreVotePhase(
      entries: round.entries,
      votesByPlayer: phase.votesByPlayer,
      scorePoolPerVote: snapshot.config.scorePoolPerVote,
    );

    var updatedVotePhases = List<VotePhase>.of(round.votePhases);
    var existingVote = updatedVotePhases[phase.voteIndex];
    updatedVotePhases[phase.voteIndex] = VotePhase(
      voteIndex: existingVote.voteIndex,
      superlativeId: existingVote.superlativeId,
      promptText: existingVote.promptText,
      votesByPlayer: phase.votesByPlayer,
      results: voteResults,
    );

    var updatedRound = RoundInstance(
      roundId: round.roundId,
      categoryId: round.categoryId,
      categoryLabel: round.categoryLabel,
      entries: round.entries,
      votePhases: updatedVotePhases,
      status: round.status,
    );

    var game = snapshot.currentGame;
    if (game == null) {
      return false;
    }

    var rounds = List<RoundInstance>.of(game.rounds);
    rounds[rounds.length - 1] = updatedRound;

    var updatedScoreboard = Map<String, int>.from(game.scoreboard);
    for (var entry in voteResults.pointsByPlayer.entries) {
      updatedScoreboard[entry.key] =
          (updatedScoreboard[entry.key] ?? 0) + entry.value;
    }

    var updatedGame = GameInstance(
      gameId: game.gameId,
      roundIndex: game.roundIndex,
      rounds: rounds,
      scoreboard: updatedScoreboard,
    );

    stateMachine.snapshot = snapshot.copyWith(
      currentGame: updatedGame,
      updatedAt: _now(),
    );

    return stateMachine.transitionTo(
      VoteRevealPhase(
        roundIndex: phase.roundIndex,
        roundId: phase.roundId,
        voteIndex: phase.voteIndex,
        superlativeId: phase.superlativeId,
        promptText: phase.promptText,
        roundSuperlatives: phase.roundSuperlatives,
        results: voteResults,
        endsAt: _now().add(Duration(seconds: snapshot.config.revealSeconds)),
      ),
    );
  }

  bool closeReveal() {
    return stateMachine.onRevealTimeout();
  }

  bool completeRound({
    String? nextCategoryId,
    String? nextCategoryLabel,
    List<SuperlativePrompt>? nextRoundSuperlatives,
    DateTime? nextRoundIntroEndsAt,
  }) {
    if (snapshot.phase is! RoundSummaryPhase) {
      return false;
    }

    var round = _currentRound();
    if (round == null) {
      return false;
    }

    _replaceCurrentRound(
      RoundInstance(
        roundId: round.roundId,
        categoryId: round.categoryId,
        categoryLabel: round.categoryLabel,
        entries: round.entries,
        votePhases: round.votePhases,
        status: RoundStatus.complete,
      ),
    );

    if (snapshot.currentGame!.rounds.length >= snapshot.config.roundCount) {
      return completeGame();
    }

    if (nextCategoryId == null ||
        nextCategoryLabel == null ||
        nextRoundSuperlatives == null ||
        nextRoundSuperlatives.isEmpty) {
      return false;
    }

    return startRound(
      categoryId: nextCategoryId,
      categoryLabel: nextCategoryLabel,
      superlatives: nextRoundSuperlatives,
      roundIntroEndsAt: nextRoundIntroEndsAt,
    );
  }

  bool completeGame() {
    var game = snapshot.currentGame;
    if (game == null || snapshot.phase is! RoundSummaryPhase) {
      return false;
    }

    return stateMachine.transitionTo(
      GameSummaryPhase(
        gameId: game.gameId,
        endsAt: null,
      ),
    );
  }

  bool _appendRound({
    required int roundIndex,
    required String categoryId,
    required String categoryLabel,
    required List<SuperlativePrompt> superlatives,
    required bool markActive,
  }) {
    var game = snapshot.currentGame;
    if (game == null) {
      return false;
    }

    var votePhases = <VotePhase>[];
    for (var i = 0; i < superlatives.length; i++) {
      var p = superlatives[i];
      votePhases.add(
        VotePhase(
          voteIndex: i,
          superlativeId: p.superlativeId,
          promptText: p.promptText,
          votesByPlayer: const {},
        ),
      );
    }

    var round = RoundInstance(
      roundId: 'round_${roundIndex + 1}',
      categoryId: categoryId,
      categoryLabel: categoryLabel,
      entries: const [],
      votePhases: votePhases,
      status: markActive ? RoundStatus.active : RoundStatus.pending,
    );

    var rounds = List<RoundInstance>.of(game.rounds)..add(round);
    var nextGame = GameInstance(
      gameId: game.gameId,
      roundIndex: roundIndex,
      rounds: rounds,
      scoreboard: game.scoreboard,
    );

    stateMachine.snapshot = snapshot.copyWith(
      currentGame: nextGame,
      updatedAt: _now(),
    );

    return true;
  }

  RoundInstance? _currentRound() {
    var game = snapshot.currentGame;
    if (game == null || game.rounds.isEmpty) {
      return null;
    }

    return game.rounds.last;
  }

  void _replaceCurrentRound(RoundInstance updatedRound) {
    var game = snapshot.currentGame;
    if (game == null || game.rounds.isEmpty) {
      return;
    }

    var rounds = List<RoundInstance>.of(game.rounds);
    rounds[rounds.length - 1] = updatedRound;

    var updatedGame = GameInstance(
      gameId: game.gameId,
      roundIndex: game.roundIndex,
      rounds: rounds,
      scoreboard: game.scoreboard,
    );

    stateMachine.snapshot = snapshot.copyWith(
      currentGame: updatedGame,
      updatedAt: _now(),
    );
  }

  void _admitPendingPlayers() {
    var updatedPlayers = Map<String, PlayerSession>.from(snapshot.players);
    var changed = false;

    for (var entry in snapshot.players.entries) {
      var player = entry.value;
      if (player.role == SessionRole.player &&
          player.state == PlayerSessionState.pending) {
        updatedPlayers[entry.key] =
            player.copyWith(state: PlayerSessionState.active);
        changed = true;
      }
    }

    if (changed) {
      stateMachine.snapshot = snapshot.copyWith(
        players: updatedPlayers,
        updatedAt: _now(),
      );
    }
  }

  String _newGameId() {
    _gameSeq++;
    return 'g_${_gameSeq}_${_random.nextInt(1 << 31)}';
  }

  String _newEntryId(String roundId, String playerId) {
    _entrySeq++;
    return 'e_${roundId}_${playerId}_$_entrySeq';
  }
}
