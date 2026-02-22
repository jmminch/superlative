import 'dart:math';

import 'scoring.dart';
import 'superlatives_game.dart';
import 'superlatives_state_machine.dart';

class GameEngine {
  final RoomStateMachine stateMachine;
  final Random _random;
  final DateTime Function() _now;
  static const Duration secondEntryGrace = Duration(seconds: 5);
  static const int nearDuplicateMinLength = 5;
  static const double nearDuplicateSimilarityThreshold = 0.8;
  String? lastRejectReasonCode;
  Map<String, Object?> lastRejectContext = const <String, Object?>{};

  int _gameSeq = 0;
  int _entrySeq = 0;

  GameEngine({
    required this.stateMachine,
    Random? random,
    DateTime Function()? now,
  })  : _random = random ?? Random(),
        _now = now ?? DateTime.now;

  SuperlativesRoomSnapshot get snapshot => stateMachine.snapshot;

  void clearLastReject() {
    lastRejectReasonCode = null;
    lastRejectContext = const <String, Object?>{};
  }

  bool _rejectVote(
    String code, {
    required String playerId,
    required String entryId,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    lastRejectReasonCode = code;
    lastRejectContext = <String, Object?>{
      'playerId': playerId,
      'entryId': entryId,
      ...context,
    };
    return false;
  }

  bool _rejectEntry(
    String code, {
    required String playerId,
    required String text,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    lastRejectReasonCode = code;
    lastRejectContext = <String, Object?>{
      'playerId': playerId,
      'text': text,
      ...context,
    };
    return false;
  }

  List<SuperlativePrompt> selectRoundSuperlatives(
    List<SuperlativePrompt> pool, {
    int? count,
  }) {
    var selectCount =
        count ?? (snapshot.config.setCount * snapshot.config.promptsPerSet);
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
    String? firstRoundCategoryLabelSingular,
    String? firstRoundCategoryLabelPlural,
    required List<SuperlativePrompt> firstRoundSuperlatives,
    DateTime? gameStartingEndsAt,
    bool showGameStartingInstructions = true,
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
      categoryLabelSingular: firstRoundCategoryLabelSingular,
      categoryLabelPlural: firstRoundCategoryLabelPlural,
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
      gameStartingEndsAt: gameStartingEndsAt ??
          roundIntroEndsAt ??
          _now().add(const Duration(seconds: 5)),
      showGameStartingInstructions: showGameStartingInstructions,
    );
  }

  bool startRound({
    required String categoryId,
    required String categoryLabel,
    String? categoryLabelSingular,
    String? categoryLabelPlural,
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
      categoryLabelSingular: categoryLabelSingular,
      categoryLabelPlural: categoryLabelPlural,
      superlatives: superlatives,
      markActive: true,
    )) {
      return false;
    }

    return stateMachine.transitionTo(
      RoundIntroPhase(
        roundIndex: roundIndex,
        roundId: _currentRound()!.roundId,
        categoryLabel: categoryLabelSingular ?? categoryLabel,
        superlatives: superlatives,
        endsAt: roundIntroEndsAt ?? _now().add(const Duration(seconds: 5)),
      ),
    );
  }

  bool openEntryInput() {
    if (snapshot.phase is GameStartingPhase) {
      if (!stateMachine.onGameStartingTimeout()) {
        return false;
      }
    }
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
    if (round == null || voteIndex < 0 || voteIndex >= round.voteSets.length) {
      return false;
    }

    var set = round.voteSets[voteIndex];
    if (set.prompts.isEmpty) {
      return false;
    }
    var firstPrompt = set.prompts.first;
    var roundSuperlatives = round.votePhases
        .map((v) => SuperlativePrompt(
            superlativeId: v.superlativeId, promptText: v.promptText))
        .toList(growable: false);
    var setSuperlatives = set.prompts
        .map(
          (p) => SuperlativePrompt(
              superlativeId: p.superlativeId, promptText: p.promptText),
        )
        .toList(growable: false);

    return stateMachine.transitionTo(
      VoteInputPhase(
        roundIndex: snapshot.currentGame!.roundIndex,
        roundId: round.roundId,
        voteIndex: voteIndex,
        setIndex: voteIndex,
        superlativeId: firstPrompt.superlativeId,
        promptText: firstPrompt.promptText,
        roundSuperlatives: roundSuperlatives,
        setSuperlatives: setSuperlatives,
        endsAt: _now().add(Duration(seconds: snapshot.config.setInputSeconds)),
        votesByPlayer: const {},
        promptIndexByPlayer: const {},
      ),
    );
  }

  bool submitEntry({required String playerId, required String text}) {
    clearLastReject();
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

    var candidateEntryKey =
        SuperlativesValidation.canonicalEntryKey(normalizedText);
    var hasDuplicate = round.entries.any((entry) =>
        entry.ownerPlayerId != playerId &&
        SuperlativesValidation.canonicalEntryKey(entry.textOriginal) ==
            candidateEntryKey);
    if (hasDuplicate) {
      return _rejectEntry(
        'entry_duplicate_exact',
        playerId: playerId,
        text: normalizedText,
      );
    }

    if (candidateEntryKey.length >= nearDuplicateMinLength) {
      for (var entry in round.entries) {
        if (entry.ownerPlayerId == playerId) {
          continue;
        }
        var existingKey =
            SuperlativesValidation.canonicalEntryKey(entry.textOriginal);
        if (existingKey.length < nearDuplicateMinLength) {
          continue;
        }
        var similarity = SuperlativesValidation.normalizedSimilarity(
            existingKey, candidateEntryKey);
        if (similarity >= nearDuplicateSimilarityThreshold) {
          return _rejectEntry(
            'entry_duplicate_near',
            playerId: playerId,
            text: normalizedText,
            context: {
              'similarity': similarity,
              'threshold': nearDuplicateSimilarityThreshold,
            },
          );
        }
      }
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
      categoryLabelSingular: round.categoryLabelSingular,
      categoryLabelPlural: round.categoryLabelPlural,
      entries: entries,
      votePhases: round.votePhases,
      voteSets: round.voteSets,
      roundPointsByEntry: round.roundPointsByEntry,
      roundPointsByPlayerPending: round.roundPointsByPlayerPending,
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
        initialEndsAt: phase.initialEndsAt,
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
    clearLastReject();
    var phase = snapshot.phase;
    if (phase is! VoteInputPhase) {
      return _rejectVote(
        'vote_wrong_phase',
        playerId: playerId,
        entryId: entryId,
        context: {'phase': phase.phase},
      );
    }

    var voter = snapshot.players[playerId];
    if (voter == null) {
      return _rejectVote(
        'vote_unknown_player',
        playerId: playerId,
        entryId: entryId,
      );
    }
    if (voter.role != SessionRole.player ||
        voter.state != PlayerSessionState.active) {
      return _rejectVote(
        'vote_player_not_active',
        playerId: playerId,
        entryId: entryId,
        context: {
          'role': voter.role.name,
          'state': voter.state.name,
        },
      );
    }

    var round = _currentRound();
    if (round == null || phase.setIndex >= round.voteSets.length) {
      return _rejectVote(
        'vote_round_or_set_missing',
        playerId: playerId,
        entryId: entryId,
        context: {'setIndex': phase.setIndex},
      );
    }
    if (phase.setSuperlatives.isEmpty) {
      return _rejectVote(
        'vote_set_has_no_prompts',
        playerId: playerId,
        entryId: entryId,
        context: {'setIndex': phase.setIndex},
      );
    }

    var currentPromptIndex = phase.promptIndexByPlayer[playerId] ?? 0;
    if (currentPromptIndex >= phase.setSuperlatives.length) {
      return _rejectVote(
        'vote_prompt_index_complete',
        playerId: playerId,
        entryId: entryId,
        context: {
          'promptIndex': currentPromptIndex,
          'promptCount': phase.setSuperlatives.length,
        },
      );
    }

    Entry? targetEntry;
    for (var entry in round.entries) {
      if (entry.entryId == entryId) {
        targetEntry = entry;
        break;
      }
    }

    if (targetEntry == null) {
      return _rejectVote(
        'vote_entry_not_found',
        playerId: playerId,
        entryId: entryId,
      );
    }

    if (!SuperlativesValidation.canPlayerVoteForEntry(
      config: snapshot.config,
      voter: voter,
      entry: targetEntry,
    )) {
      var activeEntryCount =
          round.entries.where((e) => e.status == EntryStatus.active).length;
      var canOverrideSelfVote = !snapshot.config.allowSelfVote &&
          activeEntryCount <= 2 &&
          targetEntry.ownerPlayerId == voter.playerId &&
          targetEntry.status == EntryStatus.active;
      if (!canOverrideSelfVote) {
        return _rejectVote(
          'vote_not_allowed_for_entry',
          playerId: playerId,
          entryId: entryId,
          context: {
            'allowSelfVote': snapshot.config.allowSelfVote,
            'targetOwnerPlayerId': targetEntry.ownerPlayerId,
            'activeEntryCount': activeEntryCount,
            'targetEntryStatus': targetEntry.status.name,
          },
        );
      }
    }

    var updatedVoteSets = List<VoteSet>.of(round.voteSets);
    var set = updatedVoteSets[phase.setIndex];
    var prompts = List<VotePromptState>.of(set.prompts);
    var prompt = prompts[currentPromptIndex];
    var promptVotes = Map<String, String>.from(prompt.votesByPlayer);
    promptVotes[playerId] = entryId;
    prompts[currentPromptIndex] = VotePromptState(
      promptIndex: prompt.promptIndex,
      superlativeId: prompt.superlativeId,
      promptText: prompt.promptText,
      votesByPlayer: promptVotes,
      results: prompt.results,
    );
    updatedVoteSets[phase.setIndex] = VoteSet(
      setIndex: set.setIndex,
      prompts: prompts,
      status: VoteSetStatus.active,
    );

    var flatVoteIndex =
        (phase.setIndex * snapshot.config.promptsPerSet) + currentPromptIndex;
    var updatedVotePhases = List<VotePhase>.of(round.votePhases);
    if (flatVoteIndex < updatedVotePhases.length) {
      var existingVote = updatedVotePhases[flatVoteIndex];
      updatedVotePhases[flatVoteIndex] = VotePhase(
        voteIndex: existingVote.voteIndex,
        superlativeId: existingVote.superlativeId,
        promptText: existingVote.promptText,
        votesByPlayer: promptVotes,
        results: existingVote.results,
      );
    }

    var updatedRound = RoundInstance(
      roundId: round.roundId,
      categoryId: round.categoryId,
      categoryLabel: round.categoryLabel,
      categoryLabelSingular: round.categoryLabelSingular,
      categoryLabelPlural: round.categoryLabelPlural,
      entries: round.entries,
      votePhases: updatedVotePhases,
      voteSets: updatedVoteSets,
      roundPointsByEntry: round.roundPointsByEntry,
      roundPointsByPlayerPending: round.roundPointsByPlayerPending,
      status: round.status,
    );

    _replaceCurrentRound(updatedRound);

    var updatedPromptIndexByPlayer =
        Map<String, int>.from(phase.promptIndexByPlayer);
    var nextPromptIndex = currentPromptIndex + 1;
    updatedPromptIndexByPlayer[playerId] = nextPromptIndex;

    var updatedVotesMap = Map<String, String>.from(phase.votesByPlayer);
    updatedVotesMap[playerId] = entryId;

    var displayPromptIndex = _currentDisplayPromptIndex(
      promptIndexByPlayer: updatedPromptIndexByPlayer,
      promptCount: phase.setSuperlatives.length,
      activePlayerIds: snapshot.activePlayerSessions
          .map((session) => session.playerId)
          .toList(growable: false),
    );
    var displayPrompt = phase.setSuperlatives[displayPromptIndex];

    stateMachine.snapshot = snapshot.copyWith(
      phase: VoteInputPhase(
        roundIndex: phase.roundIndex,
        roundId: phase.roundId,
        voteIndex: phase.voteIndex,
        setIndex: phase.setIndex,
        superlativeId: displayPrompt.superlativeId,
        promptText: displayPrompt.promptText,
        roundSuperlatives: phase.roundSuperlatives,
        setSuperlatives: phase.setSuperlatives,
        endsAt: phase.endsAt,
        votesByPlayer: updatedVotesMap,
        promptIndexByPlayer: updatedPromptIndexByPlayer,
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
    if (round == null || phase.setIndex >= round.voteSets.length) {
      return false;
    }
    var activeSet = round.voteSets[phase.setIndex];

    var combinedVoteCounts = <String, int>{};
    var combinedPointsByEntry = <String, int>{};
    var combinedPointsByPlayer = <String, int>{};
    var updatedSetPrompts = <VotePromptState>[];
    var updatedVotePhases = List<VotePhase>.of(round.votePhases);

    for (var prompt in activeSet.prompts) {
      var voteResults = ScoringEngine.scoreVotePhase(
        entries: round.entries,
        votesByPlayer: prompt.votesByPlayer,
        scorePoolPerVote: snapshot.config.scorePoolPerVote,
      );

      updatedSetPrompts.add(
        VotePromptState(
          promptIndex: prompt.promptIndex,
          superlativeId: prompt.superlativeId,
          promptText: prompt.promptText,
          votesByPlayer: prompt.votesByPlayer,
          results: voteResults,
        ),
      );

      for (var e in voteResults.voteCountByEntry.entries) {
        combinedVoteCounts[e.key] = (combinedVoteCounts[e.key] ?? 0) + e.value;
      }
      for (var e in voteResults.pointsByEntry.entries) {
        combinedPointsByEntry[e.key] =
            (combinedPointsByEntry[e.key] ?? 0) + e.value;
      }
      for (var e in voteResults.pointsByPlayer.entries) {
        combinedPointsByPlayer[e.key] =
            (combinedPointsByPlayer[e.key] ?? 0) + e.value;
      }

      var flatVoteIndex =
          (phase.setIndex * snapshot.config.promptsPerSet) + prompt.promptIndex;
      if (flatVoteIndex < updatedVotePhases.length) {
        var existingVote = updatedVotePhases[flatVoteIndex];
        updatedVotePhases[flatVoteIndex] = VotePhase(
          voteIndex: existingVote.voteIndex,
          superlativeId: existingVote.superlativeId,
          promptText: existingVote.promptText,
          votesByPlayer: prompt.votesByPlayer,
          results: voteResults,
        );
      }
    }

    var setResults = VoteResults(
      voteCountByEntry: combinedVoteCounts,
      pointsByEntry: combinedPointsByEntry,
      pointsByPlayer: combinedPointsByPlayer,
    );

    var updatedVoteSets = List<VoteSet>.of(round.voteSets);
    updatedVoteSets[phase.setIndex] = VoteSet(
      setIndex: activeSet.setIndex,
      prompts: updatedSetPrompts,
      status: VoteSetStatus.complete,
    );

    var updatedRoundPointsByEntry =
        Map<String, int>.from(round.roundPointsByEntry);
    for (var entry in setResults.pointsByEntry.entries) {
      updatedRoundPointsByEntry[entry.key] =
          (updatedRoundPointsByEntry[entry.key] ?? 0) + entry.value;
    }
    var updatedEntries = _applyEliminationAfterSet(
      entries: round.entries,
      roundPointsByEntry: updatedRoundPointsByEntry,
      completedSetIndex: phase.setIndex,
    );

    var updatedRound = RoundInstance(
      roundId: round.roundId,
      categoryId: round.categoryId,
      categoryLabel: round.categoryLabel,
      categoryLabelSingular: round.categoryLabelSingular,
      categoryLabelPlural: round.categoryLabelPlural,
      entries: updatedEntries,
      votePhases: updatedVotePhases,
      voteSets: updatedVoteSets,
      roundPointsByEntry: updatedRoundPointsByEntry,
      roundPointsByPlayerPending: round.roundPointsByPlayerPending,
      status: round.status,
    );

    var game = snapshot.currentGame;
    if (game == null) {
      return false;
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

    var voteRevealSeconds =
        _voteRevealPhaseSecondsForPromptCount(phase.setSuperlatives.length);
    return stateMachine.transitionTo(
      VoteRevealPhase(
        roundIndex: phase.roundIndex,
        roundId: phase.roundId,
        voteIndex: phase.setIndex,
        setIndex: phase.setIndex,
        superlativeId: 'set_${phase.setIndex + 1}',
        promptText: 'Set ${phase.setIndex + 1} results',
        roundSuperlatives: phase.roundSuperlatives,
        setSuperlatives: phase.setSuperlatives,
        results: setResults,
        endsAt: _now().add(Duration(seconds: voteRevealSeconds)),
      ),
    );
  }

  bool closeReveal() {
    return stateMachine.onRevealTimeout();
  }

  bool completeRound({
    String? nextCategoryId,
    String? nextCategoryLabel,
    String? nextCategoryLabelSingular,
    String? nextCategoryLabelPlural,
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

    var roundPointsByPlayerPending = _roundPointsByPlayer(round);
    var game = snapshot.currentGame;
    if (game == null) {
      return false;
    }

    var updatedScoreboard = Map<String, int>.from(game.scoreboard);
    for (var entry in roundPointsByPlayerPending.entries) {
      updatedScoreboard[entry.key] =
          (updatedScoreboard[entry.key] ?? 0) + entry.value;
    }

    _replaceCurrentRound(
      RoundInstance(
        roundId: round.roundId,
        categoryId: round.categoryId,
        categoryLabel: round.categoryLabel,
        categoryLabelSingular: round.categoryLabelSingular,
        categoryLabelPlural: round.categoryLabelPlural,
        entries: round.entries,
        votePhases: round.votePhases,
        voteSets: round.voteSets,
        roundPointsByEntry: round.roundPointsByEntry,
        roundPointsByPlayerPending: roundPointsByPlayerPending,
        status: RoundStatus.complete,
      ),
    );

    game = snapshot.currentGame;
    if (game == null) {
      return false;
    }

    stateMachine.snapshot = snapshot.copyWith(
      currentGame: GameInstance(
        gameId: game.gameId,
        roundIndex: game.roundIndex,
        rounds: game.rounds,
        scoreboard: updatedScoreboard,
      ),
      updatedAt: _now(),
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
      categoryLabelSingular: nextCategoryLabelSingular,
      categoryLabelPlural: nextCategoryLabelPlural,
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
    String? categoryLabelSingular,
    String? categoryLabelPlural,
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

    var voteSets = <VoteSet>[];
    for (var setIndex = 0; setIndex < snapshot.config.setCount; setIndex++) {
      var start = setIndex * snapshot.config.promptsPerSet;
      if (start >= superlatives.length) {
        break;
      }
      var end = start + snapshot.config.promptsPerSet;
      if (end > superlatives.length) {
        end = superlatives.length;
      }

      var prompts = <VotePromptState>[];
      for (var i = start; i < end; i++) {
        var p = superlatives[i];
        prompts.add(
          VotePromptState(
            promptIndex: i - start,
            superlativeId: p.superlativeId,
            promptText: p.promptText,
            votesByPlayer: const {},
          ),
        );
      }
      voteSets.add(VoteSet(setIndex: setIndex, prompts: prompts));
    }

    var round = RoundInstance(
      roundId: 'round_${roundIndex + 1}',
      categoryId: categoryId,
      categoryLabel: categoryLabel,
      categoryLabelSingular: categoryLabelSingular,
      categoryLabelPlural: categoryLabelPlural,
      entries: const [],
      votePhases: votePhases,
      voteSets: voteSets,
      roundPointsByEntry: const {},
      roundPointsByPlayerPending: const {},
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

  int _currentDisplayPromptIndex({
    required Map<String, int> promptIndexByPlayer,
    required int promptCount,
    required List<String> activePlayerIds,
  }) {
    var min = promptCount;

    if (activePlayerIds.isEmpty) {
      for (var value in promptIndexByPlayer.values) {
        if (value < min) {
          min = value;
        }
      }
    } else {
      for (var playerId in activePlayerIds) {
        var value = promptIndexByPlayer[playerId] ?? 0;
        if (value < min) {
          min = value;
        }
      }
    }

    if (min >= promptCount) {
      return promptCount - 1;
    }
    return min;
  }

  int _voteRevealPhaseSecondsForPromptCount(int promptCount) {
    var firstEntryRevealMs = 2000;
    var secondEntryRevealMs = 1000;
    var thirdEntryRevealMs = 1000;
    var betweenPromptsMs = 3000;
    var afterAllVotesMs = 5000;
    var standingsHoldMs = 10000;

    if (promptCount <= 0) {
      return snapshot.config.revealSeconds;
    }

    var perPromptRevealMs =
        firstEntryRevealMs + secondEntryRevealMs + thirdEntryRevealMs;
    var interPromptWindowMs = perPromptRevealMs + betweenPromptsMs;
    var totalMs = perPromptRevealMs +
        ((promptCount - 1) * interPromptWindowMs) +
        afterAllVotesMs +
        standingsHoldMs;
    var totalSeconds = (totalMs / 1000).ceil();
    if (totalSeconds < snapshot.config.revealSeconds) {
      return snapshot.config.revealSeconds;
    }
    return totalSeconds;
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

  List<Entry> _applyEliminationAfterSet({
    required List<Entry> entries,
    required Map<String, int> roundPointsByEntry,
    required int completedSetIndex,
  }) {
    int minKeep;
    int desiredKeep;

    var activeEntries =
        entries.where((e) => e.status == EntryStatus.active).toList();
    var activeCount = activeEntries.length;
    if (activeCount == 0) {
      return entries;
    }

    if (completedSetIndex == 0) {
      minKeep = 3;
      desiredKeep = activeCount - (activeCount ~/ 3);
    } else if (completedSetIndex == 1) {
      minKeep = 2;
      desiredKeep = activeCount - (activeCount ~/ 2);
    } else {
      return entries;
    }

    if (desiredKeep < minKeep) {
      desiredKeep = minKeep;
    }
    if (desiredKeep >= activeCount) {
      return entries;
    }

    activeEntries.sort((a, b) {
      var scoreA = roundPointsByEntry[a.entryId] ?? 0;
      var scoreB = roundPointsByEntry[b.entryId] ?? 0;
      var scoreCmp = scoreB.compareTo(scoreA);
      if (scoreCmp != 0) {
        return scoreCmp;
      }
      return a.entryId.compareTo(b.entryId);
    });

    var thresholdScore =
        roundPointsByEntry[activeEntries[desiredKeep - 1].entryId] ?? 0;
    var keepIds = activeEntries
        .where((e) => (roundPointsByEntry[e.entryId] ?? 0) >= thresholdScore)
        .map((e) => e.entryId)
        .toSet();

    var nextEntries = <Entry>[];
    for (var entry in entries) {
      if (entry.status != EntryStatus.active) {
        nextEntries.add(entry);
        continue;
      }

      if (keepIds.contains(entry.entryId)) {
        nextEntries.add(entry);
      } else {
        nextEntries.add(
          Entry(
            entryId: entry.entryId,
            ownerPlayerId: entry.ownerPlayerId,
            textOriginal: entry.textOriginal,
            textNormalized: entry.textNormalized,
            status: EntryStatus.eliminated,
          ),
        );
      }
    }

    return nextEntries;
  }
}
