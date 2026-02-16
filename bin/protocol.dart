import 'dart:convert';

enum ClientEventKind {
  login,
  startGame,
  submitEntry,
  submitVote,
  advance,
  endGame,
  pong,
  logout,
}

enum LoginRole {
  player,
  display,
}

abstract class ClientEvent {
  ClientEventKind get kind;
}

class LoginEvent implements ClientEvent {
  final String room;
  final String? name;
  final LoginRole role;

  const LoginEvent({
    required this.room,
    required this.name,
    required this.role,
  });

  @override
  ClientEventKind get kind => ClientEventKind.login;
}

class StartGameEvent implements ClientEvent {
  const StartGameEvent();

  @override
  ClientEventKind get kind => ClientEventKind.startGame;
}

class SubmitEntryEvent implements ClientEvent {
  final String text;

  const SubmitEntryEvent(this.text);

  @override
  ClientEventKind get kind => ClientEventKind.submitEntry;
}

class SubmitVoteEvent implements ClientEvent {
  final String entryId;

  const SubmitVoteEvent(this.entryId);

  @override
  ClientEventKind get kind => ClientEventKind.submitVote;
}

class AdvanceEvent implements ClientEvent {
  const AdvanceEvent();

  @override
  ClientEventKind get kind => ClientEventKind.advance;
}

class EndGameEvent implements ClientEvent {
  const EndGameEvent();

  @override
  ClientEventKind get kind => ClientEventKind.endGame;
}

class PongEvent implements ClientEvent {
  const PongEvent();

  @override
  ClientEventKind get kind => ClientEventKind.pong;
}

class LogoutEvent implements ClientEvent {
  const LogoutEvent();

  @override
  ClientEventKind get kind => ClientEventKind.logout;
}

class ProtocolError {
  final String code;
  final String message;
  final Map<String, dynamic> details;

  const ProtocolError({
    required this.code,
    required this.message,
    this.details = const {},
  });

  Map<String, dynamic> toPayload() {
    return {
      'code': code,
      'message': message,
      'details': details,
    };
  }
}

class ProtocolDecodeResult {
  final ClientEvent? event;
  final ProtocolError? error;

  const ProtocolDecodeResult._({this.event, this.error});

  const ProtocolDecodeResult.success(ClientEvent event) : this._(event: event);

  const ProtocolDecodeResult.failure(ProtocolError error)
      : this._(error: error);

  bool get ok => event != null;
}

class ProtocolAdapter {
  static const int protocolVersion = 1;

  static ProtocolDecodeResult decodeClientMessage(String raw) {
    dynamic decoded;

    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const ProtocolDecodeResult.failure(
        ProtocolError(
          code: 'bad_json',
          message: 'Message must be valid JSON.',
        ),
      );
    }

    if (decoded is! Map) {
      return const ProtocolDecodeResult.failure(
        ProtocolError(
          code: 'malformed_message',
          message: 'Message must be a JSON object.',
        ),
      );
    }

    var message = Map<String, dynamic>.from(decoded);
    var eventName = message['event'];

    if (eventName is! String || eventName.trim().isEmpty) {
      return const ProtocolDecodeResult.failure(
        ProtocolError(
          code: 'malformed_event',
          message: 'Field "event" is required and must be a string.',
        ),
      );
    }

    switch (eventName) {
      case 'login':
        return _decodeLogin(message);
      case 'startGame':
        return const ProtocolDecodeResult.success(StartGameEvent());
      case 'submitEntry':
        return _decodeSubmitEntry(message);
      case 'submitVote':
        return _decodeSubmitVote(message);
      case 'advance':
        return const ProtocolDecodeResult.success(AdvanceEvent());
      case 'endGame':
        return const ProtocolDecodeResult.success(EndGameEvent());
      case 'pong':
        return const ProtocolDecodeResult.success(PongEvent());
      case 'logout':
        return const ProtocolDecodeResult.success(LogoutEvent());
      default:
        return ProtocolDecodeResult.failure(
          ProtocolError(
            code: 'unknown_event',
            message: 'Unsupported event "$eventName".',
            details: {'event': eventName},
          ),
        );
    }
  }

  static ProtocolDecodeResult _decodeLogin(Map<String, dynamic> msg) {
    var room = _requiredTrimmedString(msg, 'room');
    if (room == null) {
      return const ProtocolDecodeResult.failure(
        ProtocolError(
          code: 'invalid_login',
          message: 'Login requires non-empty "room".',
        ),
      );
    }

    var role = LoginRole.player;
    if (msg.containsKey('role')) {
      var roleRaw = msg['role'];
      if (roleRaw is! String) {
        return const ProtocolDecodeResult.failure(
          ProtocolError(
            code: 'invalid_login',
            message: 'Login field "role" must be a string when provided.',
          ),
        );
      }

      if (roleRaw == 'player') {
        role = LoginRole.player;
      } else if (roleRaw == 'display') {
        role = LoginRole.display;
      } else {
        return ProtocolDecodeResult.failure(
          ProtocolError(
            code: 'invalid_login',
            message: 'Login role "$roleRaw" is not supported.',
            details: {'role': roleRaw},
          ),
        );
      }
    }

    String? name;
    if (role == LoginRole.player) {
      name = _requiredTrimmedString(msg, 'name');
      if (name == null) {
        return const ProtocolDecodeResult.failure(
          ProtocolError(
            code: 'invalid_login',
            message: 'Player login requires non-empty "name".',
          ),
        );
      }
    }

    return ProtocolDecodeResult.success(
      LoginEvent(
        room: room,
        name: name,
        role: role,
      ),
    );
  }

  static ProtocolDecodeResult _decodeSubmitEntry(Map<String, dynamic> msg) {
    var text = _requiredTrimmedString(msg, 'text');
    if (text == null) {
      return const ProtocolDecodeResult.failure(
        ProtocolError(
          code: 'invalid_submit_entry',
          message: 'submitEntry requires non-empty "text".',
        ),
      );
    }

    return ProtocolDecodeResult.success(SubmitEntryEvent(text));
  }

  static ProtocolDecodeResult _decodeSubmitVote(Map<String, dynamic> msg) {
    var entryId = _requiredTrimmedString(msg, 'entryId');
    if (entryId == null) {
      return const ProtocolDecodeResult.failure(
        ProtocolError(
          code: 'invalid_submit_vote',
          message: 'submitVote requires non-empty "entryId".',
        ),
      );
    }

    return ProtocolDecodeResult.success(SubmitVoteEvent(entryId));
  }

  static String? _requiredTrimmedString(Map<String, dynamic> msg, String key) {
    var raw = msg[key];
    if (raw is! String) {
      return null;
    }

    var value = raw.trim();
    if (value.isEmpty) {
      return null;
    }

    return value;
  }

  static Map<String, dynamic> buildServerEnvelope({
    required String event,
    required Map<String, dynamic> payload,
  }) {
    return {
      'protocolVersion': protocolVersion,
      'event': event,
      'payload': payload,
    };
  }

  static String encodeServerEvent({
    required String event,
    required Map<String, dynamic> payload,
  }) {
    return jsonEncode(buildServerEnvelope(event: event, payload: payload));
  }

  static Map<String, dynamic> buildErrorPayload(ProtocolError error) {
    return error.toPayload();
  }
}
