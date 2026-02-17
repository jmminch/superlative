import 'dart:collection';

/* Core room-level configuration for a Superlatives game. */
class RoomConfig {
  final int roundCount;
  final int votePhasesPerRound;
  final int setCount;
  final int promptsPerSet;
  final int setInputSeconds;
  final int entryInputSeconds;
  final int voteInputSeconds;
  final int revealSeconds;
  final int scorePoolPerVote;
  final bool allowSelfVote;
  final int maxEntryLength;
  final int minPlayersToStart;

  const RoomConfig({
    this.roundCount = 3,
    this.votePhasesPerRound = 3,
    this.setCount = 3,
    this.promptsPerSet = 3,
    this.setInputSeconds = 45,
    this.entryInputSeconds = 30,
    this.voteInputSeconds = 20,
    this.revealSeconds = 12,
    this.scorePoolPerVote = 1000,
    this.allowSelfVote = true,
    this.maxEntryLength = 40,
    this.minPlayersToStart = 3,
  })  : assert(roundCount > 0),
        assert(votePhasesPerRound > 0),
        assert(setCount > 0),
        assert(promptsPerSet > 0),
        assert(setInputSeconds > 0),
        assert(entryInputSeconds > 0),
        assert(voteInputSeconds > 0),
        assert(revealSeconds > 0),
        assert(scorePoolPerVote > 0),
        assert(maxEntryLength > 0),
        assert(minPlayersToStart > 0);
}

enum PlayerSessionState {
  active,
  pending,
  idle,
  disconnected,
}

enum SessionRole {
  player,
  display,
}

enum EntryStatus {
  active,
  eliminated,
  stolen,
}

enum RoundStatus {
  pending,
  active,
  complete,
}

class SuperlativePrompt {
  final String superlativeId;
  final String promptText;

  const SuperlativePrompt({
    required this.superlativeId,
    required this.promptText,
  })  : assert(superlativeId != ''),
        assert(promptText != '');
}

class PlayerSession {
  final String playerId;
  final String displayName;
  final PlayerSessionState state;
  final SessionRole role;
  final int scoreTotal;
  final String? currentEntryId;
  final int missedActions;

  const PlayerSession({
    required this.playerId,
    required this.displayName,
    this.state = PlayerSessionState.pending,
    this.role = SessionRole.player,
    this.scoreTotal = 0,
    this.currentEntryId,
    this.missedActions = 0,
  })  : assert(playerId != ''),
        assert(displayName != ''),
        assert(scoreTotal >= 0),
        assert(missedActions >= 0);

  PlayerSession copyWith({
    String? playerId,
    String? displayName,
    PlayerSessionState? state,
    SessionRole? role,
    int? scoreTotal,
    String? currentEntryId,
    int? missedActions,
  }) {
    return PlayerSession(
      playerId: playerId ?? this.playerId,
      displayName: displayName ?? this.displayName,
      state: state ?? this.state,
      role: role ?? this.role,
      scoreTotal: scoreTotal ?? this.scoreTotal,
      currentEntryId: currentEntryId ?? this.currentEntryId,
      missedActions: missedActions ?? this.missedActions,
    );
  }
}

class Entry {
  final String entryId;
  final String ownerPlayerId;
  final String textOriginal;
  final String textNormalized;
  final EntryStatus status;

  const Entry({
    required this.entryId,
    required this.ownerPlayerId,
    required this.textOriginal,
    required this.textNormalized,
    this.status = EntryStatus.active,
  })  : assert(entryId != ''),
        assert(ownerPlayerId != ''),
        assert(textOriginal != ''),
        assert(textNormalized != '');
}

class VoteResults {
  final Map<String, int> voteCountByEntry;
  final Map<String, int> pointsByEntry;
  final Map<String, int> pointsByPlayer;

  VoteResults({
    required Map<String, int> voteCountByEntry,
    required Map<String, int> pointsByEntry,
    required Map<String, int> pointsByPlayer,
  })  : voteCountByEntry = UnmodifiableMapView(Map.of(voteCountByEntry)),
        pointsByEntry = UnmodifiableMapView(Map.of(pointsByEntry)),
        pointsByPlayer = UnmodifiableMapView(Map.of(pointsByPlayer));
}

class VotePhase {
  final int voteIndex;
  final String superlativeId;
  final String promptText;
  final Map<String, String> votesByPlayer;
  final VoteResults? results;

  VotePhase({
    required this.voteIndex,
    required this.superlativeId,
    required this.promptText,
    required Map<String, String> votesByPlayer,
    this.results,
  })  : votesByPlayer = UnmodifiableMapView(Map.of(votesByPlayer)),
        assert(voteIndex >= 0),
        assert(superlativeId != ''),
        assert(promptText != '');
}

enum VoteSetStatus {
  pending,
  active,
  reveal,
  complete,
}

class VotePromptState {
  final int promptIndex;
  final String superlativeId;
  final String promptText;
  final Map<String, String> votesByPlayer;
  final VoteResults? results;

  VotePromptState({
    required this.promptIndex,
    required this.superlativeId,
    required this.promptText,
    required Map<String, String> votesByPlayer,
    this.results,
  })  : votesByPlayer = UnmodifiableMapView(Map.of(votesByPlayer)),
        assert(promptIndex >= 0),
        assert(superlativeId != ''),
        assert(promptText != '');
}

class VoteSet {
  final int setIndex;
  final List<VotePromptState> prompts;
  final VoteSetStatus status;

  VoteSet({
    required this.setIndex,
    required List<VotePromptState> prompts,
    this.status = VoteSetStatus.pending,
  })  : prompts = List.unmodifiable(List.of(prompts)),
        assert(setIndex >= 0),
        assert(prompts.isNotEmpty);
}

class RoundInstance {
  final String roundId;
  final String categoryId;
  final String categoryLabel;
  final List<Entry> entries;
  final List<VotePhase> votePhases;
  final List<VoteSet> voteSets;
  final Map<String, int> roundPointsByEntry;
  final Map<String, int> roundPointsByPlayerPending;
  final RoundStatus status;

  RoundInstance({
    required this.roundId,
    required this.categoryId,
    required this.categoryLabel,
    required List<Entry> entries,
    required List<VotePhase> votePhases,
    List<VoteSet>? voteSets,
    Map<String, int>? roundPointsByEntry,
    Map<String, int>? roundPointsByPlayerPending,
    this.status = RoundStatus.pending,
  })  : entries = List.unmodifiable(List.of(entries)),
        votePhases = List.unmodifiable(List.of(votePhases)),
        voteSets = List.unmodifiable(List.of(voteSets ?? const [])),
        roundPointsByEntry =
            UnmodifiableMapView(Map.of(roundPointsByEntry ?? const {})),
        roundPointsByPlayerPending = UnmodifiableMapView(
            Map.of(roundPointsByPlayerPending ?? const {})),
        assert(roundId != ''),
        assert(categoryId != ''),
        assert(categoryLabel != '');
}

class GameInstance {
  final String gameId;
  final int roundIndex;
  final List<RoundInstance> rounds;
  final Map<String, int> scoreboard;

  GameInstance({
    required this.gameId,
    this.roundIndex = 0,
    required List<RoundInstance> rounds,
    required Map<String, int> scoreboard,
  })  : rounds = List.unmodifiable(List.of(rounds)),
        scoreboard = UnmodifiableMapView(Map.of(scoreboard)),
        assert(gameId != ''),
        assert(roundIndex >= 0);
}

/* Phase model for the top-level room lifecycle. */
abstract class GamePhaseState {
  const GamePhaseState();

  String get phase;
}

class LobbyPhase extends GamePhaseState {
  const LobbyPhase();

  @override
  String get phase => 'Lobby';
}

class GameStartingPhase extends GamePhaseState {
  const GameStartingPhase();

  @override
  String get phase => 'GameStarting';
}

class RoundIntroPhase extends GamePhaseState {
  final int roundIndex;
  final String roundId;
  final String categoryLabel;
  final List<SuperlativePrompt> superlatives;
  final DateTime endsAt;

  RoundIntroPhase({
    required this.roundIndex,
    required this.roundId,
    required this.categoryLabel,
    required List<SuperlativePrompt> superlatives,
    required this.endsAt,
  })  : superlatives = List.unmodifiable(List.of(superlatives)),
        assert(roundIndex >= 0),
        assert(roundId != ''),
        assert(categoryLabel != ''),
        assert(superlatives.isNotEmpty);

  @override
  String get phase => 'RoundIntro';
}

class EntryInputPhase extends GamePhaseState {
  final int roundIndex;
  final String roundId;
  final String categoryLabel;
  final List<SuperlativePrompt> superlatives;
  final DateTime endsAt;
  final DateTime? earliestVoteAt;
  final Set<String> submittedPlayerIds;

  EntryInputPhase({
    required this.roundIndex,
    required this.roundId,
    required this.categoryLabel,
    required List<SuperlativePrompt> superlatives,
    required this.endsAt,
    this.earliestVoteAt,
    required Set<String> submittedPlayerIds,
  })  : superlatives = List.unmodifiable(List.of(superlatives)),
        submittedPlayerIds = Set.unmodifiable(Set.of(submittedPlayerIds)),
        assert(roundIndex >= 0),
        assert(roundId != ''),
        assert(categoryLabel != ''),
        assert(superlatives.isNotEmpty);

  @override
  String get phase => 'EntryInput';
}

class VoteInputPhase extends GamePhaseState {
  final int roundIndex;
  final String roundId;
  final int voteIndex;
  final int setIndex;
  final String superlativeId;
  final String promptText;
  final List<SuperlativePrompt> roundSuperlatives;
  final List<SuperlativePrompt> setSuperlatives;
  final DateTime endsAt;
  final Map<String, String> votesByPlayer;
  final Map<String, int> promptIndexByPlayer;

  VoteInputPhase({
    required this.roundIndex,
    required this.roundId,
    required this.voteIndex,
    int? setIndex,
    required this.superlativeId,
    required this.promptText,
    required List<SuperlativePrompt> roundSuperlatives,
    List<SuperlativePrompt>? setSuperlatives,
    required this.endsAt,
    required Map<String, String> votesByPlayer,
    Map<String, int>? promptIndexByPlayer,
  })  : roundSuperlatives = List.unmodifiable(List.of(roundSuperlatives)),
        setIndex = setIndex ?? voteIndex,
        setSuperlatives = List.unmodifiable(
          List.of(setSuperlatives ?? roundSuperlatives),
        ),
        votesByPlayer = UnmodifiableMapView(Map.of(votesByPlayer)),
        promptIndexByPlayer = UnmodifiableMapView(
          Map.of(promptIndexByPlayer ?? const {}),
        ),
        assert(roundIndex >= 0),
        assert(roundId != ''),
        assert(voteIndex >= 0),
        assert(superlativeId != ''),
        assert(promptText != ''),
        assert(roundSuperlatives.isNotEmpty),
        assert(setSuperlatives == null || setSuperlatives.isNotEmpty);

  @override
  String get phase => 'VoteInput';
}

class VoteRevealPhase extends GamePhaseState {
  final int roundIndex;
  final String roundId;
  final int voteIndex;
  final int setIndex;
  final String superlativeId;
  final String promptText;
  final List<SuperlativePrompt> roundSuperlatives;
  final List<SuperlativePrompt> setSuperlatives;
  final VoteResults results;
  final DateTime endsAt;

  VoteRevealPhase({
    required this.roundIndex,
    required this.roundId,
    required this.voteIndex,
    int? setIndex,
    required this.superlativeId,
    required this.promptText,
    required List<SuperlativePrompt> roundSuperlatives,
    List<SuperlativePrompt>? setSuperlatives,
    required this.results,
    required this.endsAt,
  })  : roundSuperlatives = List.unmodifiable(List.of(roundSuperlatives)),
        setIndex = setIndex ?? voteIndex,
        setSuperlatives = List.unmodifiable(
          List.of(setSuperlatives ?? roundSuperlatives),
        ),
        assert(roundIndex >= 0),
        assert(roundId != ''),
        assert(voteIndex >= 0),
        assert(superlativeId != ''),
        assert(promptText != ''),
        assert(roundSuperlatives.isNotEmpty),
        assert(setSuperlatives == null || setSuperlatives.isNotEmpty);

  @override
  String get phase => 'VoteReveal';
}

class RoundSummaryPhase extends GamePhaseState {
  final int roundIndex;
  final String roundId;
  final DateTime endsAt;

  const RoundSummaryPhase({
    required this.roundIndex,
    required this.roundId,
    required this.endsAt,
  })  : assert(roundIndex >= 0),
        assert(roundId != '');

  @override
  String get phase => 'RoundSummary';
}

class GameSummaryPhase extends GamePhaseState {
  final String gameId;
  final DateTime? endsAt;

  const GameSummaryPhase({
    required this.gameId,
    this.endsAt,
  }) : assert(gameId != '');

  @override
  String get phase => 'GameSummary';
}

/* Canonical room snapshot for state projection and protocol output. */
class SuperlativesRoomSnapshot {
  final String roomCode;
  final String? hostPlayerId;
  final RoomConfig config;
  final Map<String, PlayerSession> players;
  final GameInstance? currentGame;
  final GamePhaseState phase;
  final DateTime updatedAt;

  SuperlativesRoomSnapshot({
    required this.roomCode,
    required this.hostPlayerId,
    required this.config,
    required Map<String, PlayerSession> players,
    required this.currentGame,
    required this.phase,
    required this.updatedAt,
  }) : players = UnmodifiableMapView(Map.of(players)) {
    if (roomCode.trim().isEmpty) {
      throw ArgumentError('roomCode must not be empty');
    }
  }

  Iterable<PlayerSession> get activePlayers =>
      players.values.where((p) => p.state == PlayerSessionState.active);

  int get activePlayerCount => activePlayers.length;

  Iterable<PlayerSession> get activePlayerSessions =>
      players.values.where((p) =>
          p.state == PlayerSessionState.active && p.role == SessionRole.player);

  SuperlativesRoomSnapshot copyWith({
    String? roomCode,
    String? hostPlayerId,
    RoomConfig? config,
    Map<String, PlayerSession>? players,
    GameInstance? currentGame,
    GamePhaseState? phase,
    DateTime? updatedAt,
  }) {
    return SuperlativesRoomSnapshot(
      roomCode: roomCode ?? this.roomCode,
      hostPlayerId: hostPlayerId ?? this.hostPlayerId,
      config: config ?? this.config,
      players: players ?? this.players,
      currentGame: currentGame ?? this.currentGame,
      phase: phase ?? this.phase,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ValidationResult {
  final bool ok;
  final String? message;

  const ValidationResult._(this.ok, this.message);

  const ValidationResult.valid() : this._(true, null);

  const ValidationResult.invalid(String message) : this._(false, message);
}

class SuperlativesValidation {
  static String normalizeEntryText(String raw) {
    var normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized;
  }

  static ValidationResult validateEntryText(String raw,
      {required RoomConfig config}) {
    var normalized = normalizeEntryText(raw);

    if (normalized.isEmpty) {
      return const ValidationResult.invalid('Entry is empty.');
    }

    if (normalized.length > config.maxEntryLength) {
      return ValidationResult.invalid(
          'Entry exceeds max length ${config.maxEntryLength}.');
    }

    return const ValidationResult.valid();
  }

  static bool isVoteEligibleEntry(Entry entry) {
    return entry.status == EntryStatus.active;
  }

  static bool canPlayerVoteForEntry({
    required RoomConfig config,
    required PlayerSession voter,
    required Entry entry,
  }) {
    if (voter.role != SessionRole.player) {
      return false;
    }

    if (voter.state != PlayerSessionState.active) {
      return false;
    }

    if (!isVoteEligibleEntry(entry)) {
      return false;
    }

    if (!config.allowSelfVote && voter.playerId == entry.ownerPlayerId) {
      return false;
    }

    return true;
  }
}
