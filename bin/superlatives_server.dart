import 'dart:async';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'content_provider.dart';
import 'protocol.dart';
import 'state_projector.dart';
import 'superlatives_engine.dart';
import 'superlatives_game.dart';
import 'superlatives_state_machine.dart';

class SuperlativesServer {
  final Map<String, RoomRuntime> rooms = <String, RoomRuntime>{};
  final ContentProvider contentProvider;
  final Random _random = Random();

  SuperlativesServer._(this.contentProvider);

  static Future<SuperlativesServer> load({
    String contentPath = './data/superlatives.yaml',
  }) async {
    var provider = await YamlContentProvider.fromFile(contentPath);
    return SuperlativesServer._(provider);
  }

  Future<void> connectSocket(WebSocketChannel socket) async {
    RoomRuntime? room;
    String? sessionId;
    ConnectionSession? connection;
    Timer? pingTimer;

    void sendEvent(String event, Map<String, dynamic> payload) {
      socket.sink.add(ProtocolAdapter.encodeServerEvent(
        event: event,
        payload: payload,
      ));
    }

    void sendError(ProtocolError error) {
      sendEvent('error', ProtocolAdapter.buildErrorPayload(error));
    }

    void startPingLoop() {
      pingTimer?.cancel();
      pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (connection == null) {
          return;
        }

        connection.missedPing++;
        if (connection.missedPing >= 3) {
          socket.sink.close();
          return;
        }

        sendEvent('ping', const {'message': 'ping'});
      });
    }

    try {
      await for (var data in socket.stream) {
        if (data is! String) {
          sendError(const ProtocolError(
            code: 'malformed_message',
            message: 'WebSocket payload must be text JSON.',
          ));
          continue;
        }

        if (data.length > 4096) {
          sendError(const ProtocolError(
            code: 'message_too_large',
            message: 'Incoming message exceeded max size.',
          ));
          socket.sink.close();
          break;
        }

        var decoded = ProtocolAdapter.decodeClientMessage(data);
        if (!decoded.ok || decoded.event == null) {
          sendError(decoded.error ??
              const ProtocolError(
                code: 'decode_error',
                message: 'Failed to decode message.',
              ));
          continue;
        }

        var event = decoded.event!;

        if (sessionId == null) {
          if (event is! LoginEvent) {
            sendError(const ProtocolError(
              code: 'not_authenticated',
              message: 'You must login before sending game events.',
            ));
            continue;
          }

          var roomCode = sanitizeIdentifier(event.room);
          if (roomCode.isEmpty) {
            sendError(const ProtocolError(
              code: 'invalid_login',
              message: 'Room code is invalid after sanitization.',
            ));
            continue;
          }

          room = lookupRoom(roomCode);

          LoginOutcome outcome;
          if (event.role == LoginRole.player) {
            outcome = room.loginPlayer(
              displayName: event.name ?? '',
              socket: socket,
            );
          } else {
            outcome = room.loginDisplay(socket: socket);
          }

          if (!outcome.ok || outcome.playerId == null) {
            sendError(outcome.error ??
                const ProtocolError(
                  code: 'invalid_login',
                  message: 'Login failed.',
                ));
            continue;
          }

          sessionId = outcome.playerId;
          connection = room.connections[sessionId!];

          startPingLoop();
          sendEvent('success', const {'message': 'Login successful.'});
          room.broadcastState();
          continue;
        }

        // Logged-in path.
        if (connection == null || room == null) {
          sendError(const ProtocolError(
            code: 'session_error',
            message: 'Session state is not initialized.',
          ));
          continue;
        }

        if (event is PongEvent) {
          connection.missedPing = 0;
          continue;
        }

        var handled = room.handleEvent(playerId: sessionId, event: event);
        if (!handled) {
          sendError(const ProtocolError(
            code: 'event_rejected',
            message: 'Event was rejected for current state/permissions.',
          ));
          continue;
        }

        if (event is LogoutEvent) {
          socket.sink.close();
          break;
        }
      }
    } finally {
      pingTimer?.cancel();

      if (room != null && sessionId != null) {
        room.disconnect(sessionId, socket);
      }

      socket.sink.close();
    }
  }

  RoomRuntime lookupRoom(String roomCode) {
    var room = rooms[roomCode];
    if (room == null || room.isDefunct()) {
      room = RoomRuntime(
        roomCode: roomCode,
        contentProvider: contentProvider,
        random: Random(_random.nextInt(1 << 31)),
      );
      rooms[roomCode] = room;
    }
    return room;
  }
}

class ConnectionSession {
  final WebSocketChannel socket;
  int missedPing = 0;

  ConnectionSession(this.socket);
}

class LoginOutcome {
  final bool ok;
  final String? playerId;
  final ProtocolError? error;

  LoginOutcome.success(this.playerId)
      : ok = true,
        error = null;

  LoginOutcome.failure(this.error)
      : ok = false,
        playerId = null;
}

class RoomRuntime {
  final String roomCode;
  final ContentProvider _contentProvider;
  final Random _random;

  late RoomStateMachine stateMachine;
  late GameEngine engine;
  late StateProjector projector;

  final Map<String, String> _nameToPlayerId = <String, String>{};
  final Map<String, ConnectionSession> connections =
      <String, ConnectionSession>{};

  int _playerSeq = 0;
  int _displaySeq = 0;

  RoomRuntime({
    required this.roomCode,
    required ContentProvider contentProvider,
    required Random random,
  })  : _contentProvider = contentProvider,
        _random = random {
    var now = DateTime.now();

    stateMachine = RoomStateMachine(
      snapshot: SuperlativesRoomSnapshot(
        roomCode: roomCode,
        hostPlayerId: null,
        config: const RoomConfig(),
        players: const {},
        currentGame: null,
        phase: const LobbyPhase(),
        updatedAt: now,
      ),
      now: DateTime.now,
      onAutoTransition: (_) => broadcastState(),
      onAutoTimeout: (phase) {
        if (phase is EntryInputPhase) {
          var ok = _handleEntryInputTimeout();
          if (ok) {
            broadcastState();
          }
          return ok;
        }
        if (phase is VoteInputPhase) {
          var ok = _closeVoteInputPhase();
          if (ok) {
            broadcastState();
          }
          return ok;
        }
        if (phase is RoundSummaryPhase) {
          var ok = _advanceFromRoundSummary();
          if (ok) {
            broadcastState();
          }
          return ok;
        }
        return false;
      },
    );

    engine = GameEngine(
      stateMachine: stateMachine,
      random: _random,
      now: DateTime.now,
    );

    projector = StateProjector(now: DateTime.now);
  }

  bool isDefunct() {
    if (connections.isNotEmpty) {
      return false;
    }

    var hasConnectedPlayers = stateMachine.snapshot.players.values.any(
      (p) => p.role == SessionRole.player,
    );

    return !hasConnectedPlayers;
  }

  LoginOutcome loginPlayer({
    required String displayName,
    required WebSocketChannel socket,
  }) {
    var sanitizedName = sanitizeIdentifier(displayName);
    if (sanitizedName.isEmpty) {
      return LoginOutcome.failure(const ProtocolError(
        code: 'invalid_login',
        message: 'Player name is invalid after sanitization.',
      ));
    }

    var playerId = _nameToPlayerId[sanitizedName];
    var players =
        Map<String, PlayerSession>.from(stateMachine.snapshot.players);

    if (playerId == null) {
      playerId = 'p${++_playerSeq}';
      _nameToPlayerId[sanitizedName] = playerId;

      var initialState = stateMachine.snapshot.phase is LobbyPhase
          ? PlayerSessionState.active
          : PlayerSessionState.pending;

      players[playerId] = PlayerSession(
        playerId: playerId,
        displayName: sanitizedName,
        role: SessionRole.player,
        state: initialState,
      );

      var hostId = stateMachine.snapshot.hostPlayerId ?? playerId;
      stateMachine.snapshot = stateMachine.snapshot.copyWith(
        players: players,
        hostPlayerId: hostId,
        updatedAt: DateTime.now(),
      );
    } else {
      var existing = players[playerId];
      if (existing == null) {
        return LoginOutcome.failure(const ProtocolError(
          code: 'session_error',
          message: 'Existing player mapping had no session record.',
        ));
      }

      players[playerId] = existing.copyWith(
        displayName: sanitizedName,
        state: stateMachine.snapshot.phase is LobbyPhase
            ? PlayerSessionState.active
            : existing.state == PlayerSessionState.pending
                ? PlayerSessionState.pending
                : PlayerSessionState.active,
      );

      stateMachine.snapshot = stateMachine.snapshot.copyWith(
        players: players,
        updatedAt: DateTime.now(),
      );
      stateMachine.onPlayerReconnected(playerId);
    }

    _attachConnection(playerId, socket);
    return LoginOutcome.success(playerId);
  }

  LoginOutcome loginDisplay({required WebSocketChannel socket}) {
    var displayId = 'd${++_displaySeq}';

    var players =
        Map<String, PlayerSession>.from(stateMachine.snapshot.players);
    players[displayId] = PlayerSession(
      playerId: displayId,
      displayName: 'DISPLAY-$displayId',
      role: SessionRole.display,
      state: PlayerSessionState.active,
    );

    stateMachine.snapshot = stateMachine.snapshot.copyWith(
      players: players,
      updatedAt: DateTime.now(),
    );

    _attachConnection(displayId, socket);
    return LoginOutcome.success(displayId);
  }

  void _attachConnection(String playerId, WebSocketChannel socket) {
    var existing = connections[playerId];
    if (existing != null && existing.socket != socket) {
      existing.socket.sink.add(ProtocolAdapter.encodeServerEvent(
        event: 'disconnect',
        payload: const {'message': 'Replaced by a new login.'},
      ));
      existing.socket.sink.close();
    }

    connections[playerId] = ConnectionSession(socket);
  }

  void disconnect(String playerId, WebSocketChannel socket) {
    var existing = connections[playerId];
    if (existing == null || existing.socket != socket) {
      return;
    }

    connections.remove(playerId);

    var player = stateMachine.snapshot.players[playerId];
    if (player == null) {
      return;
    }

    if (player.role == SessionRole.display) {
      var players =
          Map<String, PlayerSession>.from(stateMachine.snapshot.players);
      players.remove(playerId);
      stateMachine.snapshot = stateMachine.snapshot.copyWith(
        players: players,
        updatedAt: DateTime.now(),
      );
    } else {
      stateMachine.onPlayerDisconnected(playerId);
    }

    broadcastState();
  }

  bool handleEvent({
    required String playerId,
    required ClientEvent event,
  }) {
    var player = stateMachine.snapshot.players[playerId];
    if (player == null) {
      return false;
    }

    var handled = false;

    if (event is StartGameEvent) {
      handled = _handleStartGame(playerId);
    } else if (event is SubmitEntryEvent) {
      handled = engine.submitEntry(playerId: playerId, text: event.text);
    } else if (event is SubmitVoteEvent) {
      handled = engine.submitVote(playerId: playerId, entryId: event.entryId);
      if (handled && _allActivePlayersVoted()) {
        handled = _closeVoteInputPhase();
      }
    } else if (event is AdvanceEvent) {
      handled = _handleAdvance(playerId);
    } else if (event is EndGameEvent) {
      handled = stateMachine.onHostControl(playerId, HostControlEvent.endGame);
    } else if (event is LogoutEvent) {
      handled = true;
    } else if (event is PongEvent) {
      handled = true;
    }

    if (handled) {
      broadcastState();
    }

    return handled;
  }

  bool _handleStartGame(String hostPlayerId) {
    var roundContent = _contentProvider.selectRoundContent(
      config: stateMachine.snapshot.config,
      random: _random,
    );

    return engine.startGame(
      hostPlayerId: hostPlayerId,
      firstRoundCategoryId: roundContent.categoryId,
      firstRoundCategoryLabel: roundContent.categoryLabel,
      firstRoundSuperlatives: roundContent.superlatives,
    );
  }

  bool _handleAdvance(String playerId) {
    var phase = stateMachine.snapshot.phase;

    if (phase is RoundSummaryPhase) {
      return _advanceFromRoundSummary();
    }

    return stateMachine.onHostControl(playerId, HostControlEvent.advance);
  }

  bool _advanceFromRoundSummary() {
    if (stateMachine.snapshot.currentGame == null) {
      return false;
    }

    var roundCount = stateMachine.snapshot.currentGame!.rounds.length;
    if (roundCount >= stateMachine.snapshot.config.roundCount) {
      return engine.completeRound();
    }

    var usedCategoryIds = stateMachine.snapshot.currentGame!.rounds
        .map((r) => r.categoryId)
        .toSet();

    var nextRound = _contentProvider.selectRoundContent(
      config: stateMachine.snapshot.config,
      random: _random,
      excludeCategoryIds: usedCategoryIds,
    );

    return engine.completeRound(
      nextCategoryId: nextRound.categoryId,
      nextCategoryLabel: nextRound.categoryLabel,
      nextRoundSuperlatives: nextRound.superlatives,
    );
  }

  bool _allActivePlayersVoted() {
    var phase = stateMachine.snapshot.phase;
    if (phase is! VoteInputPhase) {
      return false;
    }

    var activePlayerIds = stateMachine.snapshot.activePlayerSessions
        .map((p) => p.playerId)
        .toSet();
    if (activePlayerIds.isEmpty) {
      return false;
    }

    return phase.votesByPlayer.keys.toSet().containsAll(activePlayerIds);
  }

  bool _closeVoteInputPhase() {
    var phase = stateMachine.snapshot.phase;
    if (phase is! VoteInputPhase) {
      return false;
    }

    return engine.closeVotePhase();
  }

  bool _handleEntryInputTimeout() {
    var phase = stateMachine.snapshot.phase;
    if (phase is! EntryInputPhase) {
      return false;
    }

    var game = stateMachine.snapshot.currentGame;
    var round = (game == null || game.rounds.isEmpty) ? null : game.rounds.last;
    var entryCount = round?.entries.length ?? 0;

    if (entryCount < 2) {
      return _extendEntryInputTimeout(const Duration(seconds: 5));
    }

    if (phase.earliestVoteAt != null &&
        DateTime.now().isBefore(phase.earliestVoteAt!)) {
      return _setEntryInputTimeout(phase.earliestVoteAt!);
    }

    return engine.closeEntryInput();
  }

  bool _extendEntryInputTimeout(Duration by) {
    var phase = stateMachine.snapshot.phase;
    if (phase is! EntryInputPhase) {
      return false;
    }

    return _setEntryInputTimeout(DateTime.now().add(by));
  }

  bool _setEntryInputTimeout(DateTime endsAt) {
    var phase = stateMachine.snapshot.phase;
    if (phase is! EntryInputPhase) {
      return false;
    }

    var nextEndsAt = endsAt;
    if (nextEndsAt.isBefore(DateTime.now())) {
      nextEndsAt = DateTime.now();
    }

    return stateMachine.replaceCurrentPhase(
      EntryInputPhase(
        roundIndex: phase.roundIndex,
        roundId: phase.roundId,
        categoryLabel: phase.categoryLabel,
        superlatives: phase.superlatives,
        endsAt: nextEndsAt,
        earliestVoteAt: phase.earliestVoteAt,
        submittedPlayerIds: phase.submittedPlayerIds,
      ),
    );
  }

  void broadcastState() {
    var snapshot = stateMachine.snapshot;

    var staleIds = <String>[];
    for (var entry in connections.entries) {
      var playerId = entry.key;
      var conn = entry.value;
      var player = snapshot.players[playerId];
      if (player == null) {
        staleIds.add(playerId);
        continue;
      }

      Map<String, dynamic> payload;
      if (player.role == SessionRole.display) {
        payload = projector.projectForDisplay(snapshot: snapshot);
      } else {
        payload = projector.projectForPlayer(
          playerId: playerId,
          snapshot: snapshot,
        );
      }

      conn.socket.sink.add(
        ProtocolAdapter.encodeServerEvent(
          event: 'state',
          payload: payload,
        ),
      );
    }

    for (var id in staleIds) {
      connections.remove(id);
    }
  }
}

String sanitizeIdentifier(String input) {
  var s = input.toUpperCase();
  s = s.replaceAll(RegExp(r'[^\x20-\x7e]'), '');
  s = s.replaceAll(RegExp(r'[\x22\x26\x27\x3c\x3e]'), '');
  s = s.trim();
  return s;
}
