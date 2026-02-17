# Superlatives Implementation Plan (Improved Architecture)

## Status
Draft v1, created February 16, 2026.

## Progress
- Completed: Phase 0, Phase 1, Phase 2, Phase 3, Phase 4, Phase 5, Phase 6, Phase 7, Phase 8, Phase 9, Phase 10
- In progress: Phase 11
- Pending: none

## Goal
Implement Superlatives as the sole game in this repository, using existing code only as temporary migration scaffolding, while adopting the recommended improved alternatives:
- phase-based nested state model
- typed protocol messages
- role-scoped state projection
- game configuration object
- content provider abstraction
- componentized server architecture

## Target Architecture
Server components:
- `ProtocolAdapter`: decode/validate inbound events, encode outbound events
- `RoomStateMachine`: legal transitions + timers + host-control guards
- `GameEngine`: round/vote progression and mutation of game data
- `ScoringEngine`: pure deterministic scoring
- `StateProjector`: derive `player` and `display` payloads from canonical room snapshot
- `ContentProvider`: categories + superlatives retrieval

Client components:
- `web/player.js`: player-only input and status views
- `web/display.js`: display-only render path

## Execution Order
1. Domain + phase model skeleton
2. RoomStateMachine (transitions/timers)
3. ProtocolAdapter (typed v1 protocol)
4. GameEngine (entry/vote lifecycle)
5. ScoringEngine (pure scoring + tests)
6. StateProjector (role-scoped payloads)
7. ContentProvider + content file
8. Player client screens
9. Display client screens
10. Integration tests, hardening, Superlatives cutover + What If decommission

## Why This Order
- The nested phase model and state machine define what data exists in each phase.
- Protocol and clients depend on those shapes.
- Scoring and projection are simpler once lifecycle and data model are fixed.
- UI implementation should come after server contracts stabilize.

## Work Plan

## Phase 0: Branch Safety and Baseline
Deliverables:
- Superlatives development flag `SUPERLATIVES_ENABLED` introduced (temporary).
- Baseline server startup verification.

Tasks:
- Confirm server starts and flag is readable from environment.
- Keep flag only as temporary development control while migration is in progress.

Exit criteria:
- Flag is wired and observable; no startup regressions.

## Phase 1: Domain Model and Nested Phase Types
Deliverables:
- New domain types for `RoomConfig`, `GameInstance`, `RoundInstance`, `Entry`, `VotePhase`, `VoteResults`.
- Phase classes (`LobbyPhase`, `RoundIntroPhase`, `EntryInputPhase`, `VoteInputPhase`, `VoteRevealPhase`, `RoundSummaryPhase`, `GameSummaryPhase`).

Tasks:
- Create `bin/superlatives_game.dart` with immutable (or mostly immutable) phase payload types.
- Add canonical room snapshot container.
- Define validation helpers for entry text and voting eligibility.

Exit criteria:
- Compile passes with no behavior wired yet.
- Unit tests for basic constructors/validation invariants.

## Phase 2: RoomStateMachine
Deliverables:
- Transition table and guarded `transitionTo(...)` API.
- Timer scheduling and cancellation policy per phase.

Tasks:
- Implement legal transitions only.
- Add host-only checks for control events.
- Add timeout handlers (`onEntryTimeout`, `onVoteTimeout`, `onRevealTimeout`).
- Add host failover policy (grace window + election).

Exit criteria:
- Unit tests for valid/invalid transitions.
- Unit tests for timeout-driven transitions.

## Phase 3: ProtocolAdapter (Typed Protocol)
Deliverables:
- Typed event envelopes:
  - inbound `{ event, ... }`
  - outbound `{ protocolVersion, event, payload }`
- Decoder/encoder and event-level validation.

Tasks:
- Create `bin/protocol.dart`.
- Parse known inbound events (`login`, `startGame`, `submitEntry`, `submitVote`, `advance`, `endGame`, `pong`, `logout`).
- Reject malformed events with structured `error` payloads.

Exit criteria:
- Protocol unit tests for happy path + malformed payloads.

## Phase 4: GameEngine (Round/Entry/Vote Lifecycle)
Deliverables:
- End-to-end in-memory game progression logic.

Tasks:
- Implement `startGame`, `startRound`, `openEntryInput`, `closeEntryInput`, `openVotePhase`, `closeVotePhase`, `completeRound`, `completeGame`.
- Implement pending-player policy (join next round).
- Enforce vote constraints (entry exists, self-vote setting).

Exit criteria:
- Unit tests for 3-round, 3-vote progression.
- Deterministic behavior with seeded RNG.

## Phase 5: ScoringEngine
Deliverables:
- Pure function(s) that return per-entry/per-player points for a vote phase.

Tasks:
- Implement proportional distribution for `scorePoolPerVote` with deterministic remainder allocation.
- Integrate scoring results into `GameEngine` and scoreboard totals.

Exit criteria:
- Unit tests for edge cases:
  - no votes
  - one vote
  - ties with rounding remainder
  - all votes to one entry

## Phase 6: StateProjector (Role-Scoped Payloads)
Deliverables:
- `projectForPlayer(playerId, snapshot)`
- `projectForDisplay(snapshot)`

Tasks:
- Define shared payload schema fields and role-specific differences.
- Ensure private flags (`youSubmitted`, `youVoted`) only in player payload.
- Ensure display payload includes full reveal data and leaderboard.

Exit criteria:
- Snapshot tests per phase for player + display payload shape.

## Phase 7: ContentProvider and Content Data
Deliverables:
- `data/superlatives.yaml` source file and loader.
- Provider interface abstraction.

Tasks:
- Implement `ContentProvider` with validation:
  - category has >= configured vote count superlatives
  - no empty labels/prompts
- Implement selection without replacement per round.
- Load YAML directly at server startup (no build-time YAML->JSON conversion step).

Exit criteria:
- Unit tests for content loading/validation failures.

## Phase 8: Server Wiring
Deliverables:
- Integrate Superlatives route/room handling into existing socket server.

Tasks:
- Wire `GameServer.connectSocket` directly to Superlatives protocol/engine path.
- Add room registry support for display sessions.
- Preserve keepalive and disconnect handling.

Exit criteria:
- Manual local test: room with multiple players and one display client receives live updates.

## Phase 9: Player Client Implementation
Deliverables:
- `web/player.js` with Superlatives flow screens.

Tasks:
- Add views for lobby, round intro, entry input, vote input, vote reveal, summary, game summary.
- Add submit lock + reconnect-safe local UI state.
- Add timer rendering from server payload.

Exit criteria:
- Manual test with at least 3 browser sessions.

## Phase 10: Display Client Implementation
Deliverables:
- `web/display.html`, `web/display.js`.

Tasks:
- Render room status, prompts, vote reveal visuals, leaderboard.
- Keep display read-only.
- Optimize for large-screen readability.

Exit criteria:
- Manual test on separate display browser window with same room.

## Phase 11: Integration, Hardening, and Rollout
Deliverables:
- Automated integration test coverage for full game loop.
- Operational logs/metrics for key events.
- Superlatives-only cutover complete.
- What If code/assets removed from runtime paths.

Tasks:
- Add integration tests for reconnect, host disconnect, pending joiners.
- Add invalid-event logging counters.
- Playtest and tune timers/scoring defaults.
- Remove temporary feature flag gating from startup/runtime path.
- Delete What If-specific game flow code, content files, and obsolete client screens/assets.
- Update docs (`README.md`, design docs) to Superlatives-only behavior.

Exit criteria:
- Checklist pass, stable multiplayer sessions, and no runtime What If dependencies remaining.

## Test Matrix (Minimum)
- State machine: transition matrix + timeout transitions.
- Protocol: decode/encode + malformed event rejection.
- Engine: full game progression deterministic seed.
- Scoring: arithmetic and tie determinism.
- Projection: role-scoped snapshot correctness.
- Reconnect/failover: host and non-host cases.

## Suggested File Layout
- `bin/superlatives_game.dart`
- `bin/superlatives_state_machine.dart`
- `bin/protocol.dart`
- `bin/superlatives_engine.dart`
- `bin/scoring.dart`
- `bin/state_projector.dart`
- `bin/content_provider.dart`
- `data/superlatives.yaml`
- `web/player.js`
- `web/display.js`
- `web/display.html`
- `test/superlatives_state_machine_test.dart`
- `test/superlatives_phase1_test.dart`
- `test/superlatives_scoring_test.dart`
- `test/superlatives_protocol_test.dart`
- `test/superlatives_engine_test.dart`
- `test/superlatives_state_projector_test.dart`
- `test/superlatives_content_provider_test.dart`
- `test/superlatives_integration_test.dart`

## Risks and Mitigations
- Risk: scope creep from future twists early.
  - Mitigation: freeze v1 rules; leave extension points only.
- Risk: protocol churn breaks clients.
  - Mitigation: protocol version and adapter boundary.
- Risk: timer race conditions.
  - Mitigation: central scheduler in state machine, cancel-on-transition rule.
- Risk: reconnect edge-case bugs.
  - Mitigation: integration tests with scripted disconnect/reconnect.

## Best First Component
Start with **RoomStateMachine + phase data model** (Phases 1 and 2 together).

Reason:
- It defines the canonical lifecycle and valid transitions all other components depend on.
- Protocol payloads, scoring invocation points, and UI screens become straightforward once phase boundaries are fixed.
- It minimizes rework: implementing protocol or UI first would likely be rewritten as phase semantics evolve.
