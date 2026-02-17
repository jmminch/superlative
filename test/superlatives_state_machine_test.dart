import 'package:test/test.dart';

import '../bin/superlatives_game.dart';
import '../bin/superlatives_state_machine.dart';

class _FakeTimer {
  final Duration delay;
  final void Function() callback;
  bool cancelled = false;

  _FakeTimer(this.delay, this.callback);
}

class _FakeScheduler implements PhaseTimerScheduler {
  final List<_FakeTimer> timers = [];

  @override
  CancelTimer schedule(Duration delay, void Function() callback) {
    var timer = _FakeTimer(delay, callback);
    timers.add(timer);
    return () {
      timer.cancelled = true;
    };
  }

  int get activeTimerCount => timers.where((t) => !t.cancelled).length;

  bool fireMostRecentActive() {
    for (var i = timers.length - 1; i >= 0; i--) {
      var timer = timers[i];
      if (!timer.cancelled) {
        timer.cancelled = true;
        timer.callback();
        return true;
      }
    }
    return false;
  }
}

DateTime _baseNow = DateTime.utc(2026, 2, 16, 12, 0, 0);

SuperlativesRoomSnapshot _buildLobbySnapshot({
  String hostId = 'p1',
  Map<String, PlayerSession>? players,
}) {
  return SuperlativesRoomSnapshot(
    roomCode: 'ABCD',
    hostPlayerId: hostId,
    config: const RoomConfig(
      minPlayersToStart: 2,
      setCount: 2,
      promptsPerSet: 1,
    ),
    players: players ??
        const {
          'p1': PlayerSession(
            playerId: 'p1',
            displayName: 'ALPHA',
            state: PlayerSessionState.active,
          ),
          'p2': PlayerSession(
            playerId: 'p2',
            displayName: 'BETA',
            state: PlayerSessionState.active,
          ),
        },
    currentGame: null,
    phase: const LobbyPhase(),
    updatedAt: _baseNow,
  );
}

List<SuperlativePrompt> _superlatives() {
  return const [
    SuperlativePrompt(superlativeId: 's1', promptText: 'Cutest'),
    SuperlativePrompt(superlativeId: 's2', promptText: 'Loudest'),
  ];
}

void main() {
  group('transition guards', () {
    test('rejects invalid transition from lobby to entry input', () {
      var scheduler = _FakeScheduler();
      var machine = RoomStateMachine(
        snapshot: _buildLobbySnapshot(),
        timerScheduler: scheduler,
        now: () => _baseNow,
      );

      var ok = machine.transitionTo(
        EntryInputPhase(
          roundIndex: 0,
          roundId: 'r1',
          categoryLabel: 'Animals',
          superlatives: _superlatives(),
          endsAt: _baseNow.add(const Duration(seconds: 30)),
          submittedPlayerIds: const {},
        ),
      );

      expect(ok, isFalse);
      expect(machine.snapshot.phase, isA<LobbyPhase>());
    });

    test('host start game enters round intro and schedules timer', () {
      var scheduler = _FakeScheduler();
      var machine = RoomStateMachine(
        snapshot: _buildLobbySnapshot(),
        timerScheduler: scheduler,
        now: () => _baseNow,
      );

      var ok = machine.onHostControl(
        'p1',
        HostControlEvent.startGame,
        roundId: 'r1',
        categoryLabel: 'Animals',
        superlatives: _superlatives(),
        roundIntroEndsAt: _baseNow.add(const Duration(seconds: 5)),
      );

      expect(ok, isTrue);
      expect(machine.snapshot.phase, isA<RoundIntroPhase>());
      expect(scheduler.activeTimerCount, 1);
    });
  });

  group('timeout handlers', () {
    test('entry timeout -> vote input, vote timeout -> vote reveal', () {
      var scheduler = _FakeScheduler();
      var machine = RoomStateMachine(
        snapshot: _buildLobbySnapshot().copyWith(
          phase: EntryInputPhase(
            roundIndex: 0,
            roundId: 'r1',
            categoryLabel: 'Animals',
            superlatives: _superlatives(),
            endsAt: _baseNow.add(const Duration(seconds: 30)),
            submittedPlayerIds: const {},
          ),
        ),
        timerScheduler: scheduler,
        now: () => _baseNow,
      );

      expect(machine.onEntryTimeout(), isTrue);
      expect(machine.snapshot.phase, isA<VoteInputPhase>());

      expect(machine.onVoteTimeout(), isTrue);
      expect(machine.snapshot.phase, isA<VoteRevealPhase>());
    });

    test('reveal timeout advances vote index then round summary', () {
      var scheduler = _FakeScheduler();
      var revealPhase = VoteRevealPhase(
        roundIndex: 0,
        roundId: 'r1',
        voteIndex: 0,
        superlativeId: 's1',
        promptText: 'Cutest',
        roundSuperlatives: _superlatives(),
        results: VoteResults(
          voteCountByEntry: const {},
          pointsByEntry: const {},
          pointsByPlayer: const {},
        ),
        endsAt: _baseNow.add(const Duration(seconds: 12)),
      );

      var machine = RoomStateMachine(
        snapshot: _buildLobbySnapshot().copyWith(phase: revealPhase),
        timerScheduler: scheduler,
        now: () => _baseNow,
      );

      expect(machine.onRevealTimeout(), isTrue);
      expect(machine.snapshot.phase, isA<VoteInputPhase>());
      var voteInput = machine.snapshot.phase as VoteInputPhase;
      expect(voteInput.voteIndex, 1);

      expect(machine.onVoteTimeout(), isTrue);
      expect(machine.snapshot.phase, isA<VoteRevealPhase>());

      expect(machine.onRevealTimeout(), isTrue);
      expect(machine.snapshot.phase, isA<RoundSummaryPhase>());
    });
  });

  group('timer scheduling and cancellation', () {
    test('changing phase cancels previous phase timer', () {
      var scheduler = _FakeScheduler();
      var machine = RoomStateMachine(
        snapshot: _buildLobbySnapshot().copyWith(
          phase: RoundIntroPhase(
            roundIndex: 0,
            roundId: 'r1',
            categoryLabel: 'Animals',
            superlatives: _superlatives(),
            endsAt: _baseNow.add(const Duration(seconds: 10)),
          ),
        ),
        timerScheduler: scheduler,
        now: () => _baseNow,
      );

      expect(scheduler.activeTimerCount, 1);

      var ok = machine.transitionTo(const LobbyPhase());
      expect(ok, isTrue);
      expect(scheduler.activeTimerCount, 0);
    });

    test('phase timer firing triggers matching timeout handler', () {
      var scheduler = _FakeScheduler();
      var autoTransitions = 0;
      var machine = RoomStateMachine(
        snapshot: _buildLobbySnapshot().copyWith(
          phase: EntryInputPhase(
            roundIndex: 0,
            roundId: 'r1',
            categoryLabel: 'Animals',
            superlatives: _superlatives(),
            endsAt: _baseNow.add(const Duration(seconds: 1)),
            submittedPlayerIds: const {},
          ),
        ),
        timerScheduler: scheduler,
        now: () => _baseNow,
        onAutoTransition: (_) {
          autoTransitions++;
        },
      );

      expect(machine.snapshot.phase, isA<EntryInputPhase>());
      expect(scheduler.fireMostRecentActive(), isTrue);
      expect(machine.snapshot.phase, isA<VoteInputPhase>());
      expect(autoTransitions, 1);
    });

    test('vote input timeout can be intercepted by custom timeout handler', () {
      var scheduler = _FakeScheduler();
      var autoTransitions = 0;
      var customTimeoutCalls = 0;

      var machine = RoomStateMachine(
        snapshot: _buildLobbySnapshot().copyWith(
          phase: VoteInputPhase(
            roundIndex: 0,
            roundId: 'r1',
            voteIndex: 0,
            superlativeId: 's1',
            promptText: 'Cutest',
            roundSuperlatives: _superlatives(),
            endsAt: _baseNow.add(const Duration(seconds: 1)),
            votesByPlayer: const {},
          ),
        ),
        timerScheduler: scheduler,
        now: () => _baseNow,
        onAutoTransition: (_) {
          autoTransitions++;
        },
        onAutoTimeout: (phase) {
          if (phase is VoteInputPhase) {
            customTimeoutCalls++;
            return true;
          }
          return false;
        },
      );

      expect(machine.snapshot.phase, isA<VoteInputPhase>());
      expect(scheduler.fireMostRecentActive(), isTrue);
      expect(customTimeoutCalls, 1);
      expect(autoTransitions, 0);
      expect(machine.snapshot.phase, isA<VoteInputPhase>());
    });
  });

  group('host controls and failover', () {
    test('any active lobby player can start and becomes host', () {
      var scheduler = _FakeScheduler();
      var machine = RoomStateMachine(
        snapshot: _buildLobbySnapshot(),
        timerScheduler: scheduler,
        now: () => _baseNow,
      );

      var ok = machine.onHostControl(
        'p2',
        HostControlEvent.startGame,
        roundId: 'r1',
        categoryLabel: 'Animals',
        superlatives: _superlatives(),
        roundIntroEndsAt: _baseNow.add(const Duration(seconds: 5)),
      );

      expect(ok, isTrue);
      expect(machine.snapshot.phase, isA<RoundIntroPhase>());
      expect(machine.snapshot.hostPlayerId, 'p2');
    });

    test('host failover elects active player after grace timeout', () {
      var scheduler = _FakeScheduler();
      var machine = RoomStateMachine(
        snapshot: _buildLobbySnapshot(),
        timerScheduler: scheduler,
        now: () => _baseNow,
        hostGraceDuration: const Duration(seconds: 10),
      );

      expect(machine.onPlayerDisconnected('p1'), isTrue);
      expect(scheduler.fireMostRecentActive(), isTrue);
      expect(machine.snapshot.hostPlayerId, 'p2');
    });

    test('host reconnect before grace keeps original host', () {
      var scheduler = _FakeScheduler();
      var machine = RoomStateMachine(
        snapshot: _buildLobbySnapshot(),
        timerScheduler: scheduler,
        now: () => _baseNow,
        hostGraceDuration: const Duration(seconds: 10),
      );

      expect(machine.onPlayerDisconnected('p1'), isTrue);
      expect(machine.onPlayerReconnected('p1'), isTrue);
      expect(machine.snapshot.hostPlayerId, 'p1');

      // Host grace timer was cancelled on reconnect, so there should be no
      // active timer left to fire for failover.
      expect(scheduler.fireMostRecentActive(), isFalse);
      expect(machine.snapshot.hostPlayerId, 'p1');
    });
  });
}
