import 'dart:convert';

import 'package:test/test.dart';

import '../bin/protocol.dart';

void main() {
  group('decodeClientMessage', () {
    test('rejects non-JSON payload', () {
      var result = ProtocolAdapter.decodeClientMessage('{not-json');
      expect(result.ok, isFalse);
      expect(result.error?.code, 'bad_json');
    });

    test('rejects non-object JSON payload', () {
      var result = ProtocolAdapter.decodeClientMessage('[1, 2, 3]');
      expect(result.ok, isFalse);
      expect(result.error?.code, 'malformed_message');
    });

    test('rejects missing event field', () {
      var result = ProtocolAdapter.decodeClientMessage('{"room":"ABCD"}');
      expect(result.ok, isFalse);
      expect(result.error?.code, 'malformed_event');
    });

    test('rejects unknown event', () {
      var result =
          ProtocolAdapter.decodeClientMessage('{"event":"mysteryEvent"}');
      expect(result.ok, isFalse);
      expect(result.error?.code, 'unknown_event');
    });

    test('decodes login player event', () {
      var result = ProtocolAdapter.decodeClientMessage(
        '{"event":"login","room":"ABCD","name":"NOEL"}',
      );

      expect(result.ok, isTrue);
      expect(result.event, isA<LoginEvent>());

      var event = result.event as LoginEvent;
      expect(event.role, LoginRole.player);
      expect(event.room, 'ABCD');
      expect(event.name, 'NOEL');
    });

    test('decodes login display event without name', () {
      var result = ProtocolAdapter.decodeClientMessage(
        '{"event":"login","room":"ABCD","role":"display"}',
      );

      expect(result.ok, isTrue);
      var event = result.event as LoginEvent;
      expect(event.role, LoginRole.display);
      expect(event.name, isNull);
    });

    test('rejects player login with missing name', () {
      var result = ProtocolAdapter.decodeClientMessage(
        '{"event":"login","room":"ABCD"}',
      );

      expect(result.ok, isFalse);
      expect(result.error?.code, 'invalid_login');
    });

    test('rejects login with invalid role', () {
      var result = ProtocolAdapter.decodeClientMessage(
        '{"event":"login","room":"ABCD","role":"spectator"}',
      );

      expect(result.ok, isFalse);
      expect(result.error?.code, 'invalid_login');
    });

    test('decodes startGame', () {
      var result = ProtocolAdapter.decodeClientMessage('{"event":"startGame"}');
      expect(result.ok, isTrue);
      expect(result.event, isA<StartGameEvent>());
    });

    test('decodes submitEntry', () {
      var result = ProtocolAdapter.decodeClientMessage(
        '{"event":"submitEntry","text":"RACCOON"}',
      );
      expect(result.ok, isTrue);
      expect(result.event, isA<SubmitEntryEvent>());
      expect((result.event as SubmitEntryEvent).text, 'RACCOON');
    });

    test('rejects submitEntry with missing text', () {
      var result =
          ProtocolAdapter.decodeClientMessage('{"event":"submitEntry"}');
      expect(result.ok, isFalse);
      expect(result.error?.code, 'invalid_submit_entry');
    });

    test('decodes submitVote', () {
      var result = ProtocolAdapter.decodeClientMessage(
        '{"event":"submitVote","entryId":"e_12"}',
      );
      expect(result.ok, isTrue);
      expect(result.event, isA<SubmitVoteEvent>());
      expect((result.event as SubmitVoteEvent).entryId, 'e_12');
    });

    test('rejects submitVote with missing entryId', () {
      var result =
          ProtocolAdapter.decodeClientMessage('{"event":"submitVote"}');
      expect(result.ok, isFalse);
      expect(result.error?.code, 'invalid_submit_vote');
    });

    test('decodes advance, endGame, pong, logout', () {
      var advance = ProtocolAdapter.decodeClientMessage('{"event":"advance"}');
      var endGame = ProtocolAdapter.decodeClientMessage('{"event":"endGame"}');
      var pong = ProtocolAdapter.decodeClientMessage('{"event":"pong"}');
      var logout = ProtocolAdapter.decodeClientMessage('{"event":"logout"}');

      expect(advance.event, isA<AdvanceEvent>());
      expect(endGame.event, isA<EndGameEvent>());
      expect(pong.event, isA<PongEvent>());
      expect(logout.event, isA<LogoutEvent>());
    });
  });

  group('server encoding', () {
    test('buildServerEnvelope includes protocol version and payload', () {
      var envelope = ProtocolAdapter.buildServerEnvelope(
        event: 'state',
        payload: {'phase': 'Lobby'},
      );

      expect(envelope['protocolVersion'], ProtocolAdapter.protocolVersion);
      expect(envelope['event'], 'state');
      expect(envelope['payload'], {'phase': 'Lobby'});
    });

    test('encodeServerEvent returns JSON with expected shape', () {
      var encoded = ProtocolAdapter.encodeServerEvent(
        event: 'success',
        payload: {'message': 'ok'},
      );

      var decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['protocolVersion'], ProtocolAdapter.protocolVersion);
      expect(decoded['event'], 'success');
      expect(decoded['payload'], {'message': 'ok'});
    });

    test('buildErrorPayload returns structured protocol error', () {
      var error = const ProtocolError(
        code: 'invalid_login',
        message: 'Bad login',
        details: {'field': 'name'},
      );

      var payload = ProtocolAdapter.buildErrorPayload(error);
      expect(payload['code'], 'invalid_login');
      expect(payload['message'], 'Bad login');
      expect(payload['details'], {'field': 'name'});
    });
  });
}
