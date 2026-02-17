# Superlatives Next Steps Detailed Phased Plan

## Status
Draft v1, February 17, 2026.

## Goal
Implement all items in `design/superlatives-next-steps.md` using incremental phases that keep the game runnable and testable after each phase.

## Delivery Strategy
- Land server model and behavior first.
- Stabilize projection contract second.
- Implement player UI against finalized payloads.
- Keep display client compatible but prioritize player UX requirements.

## Phase 0: Confirm Product Decisions (Blocking Clarifications)
Deliverables:
- Resolved and documented product decisions:
  - `setInputSeconds = 45` for all sets.
  - Reveal cadence is once per set.
  - Elimination cutoff keeps ties together.
  - When only 2 active entries remain, self-vote is allowed.
  - Round summary always shows original entry text, including eliminated entries.
  - First accepted lobby start event wins host assignment.

Tasks:
- Copy resolved decisions into spec/config defaults.
- Encode decisions as explicit acceptance criteria and tests.

Exit criteria:
- Product decision section is resolved and copied into config defaults/tests.

## Phase 1: Expand Domain Model to Set-Based Round Structure
Deliverables:
- `RoundInstance` supports `VoteSet` and cumulative `roundPointsByEntry`.
- Config supports set-level timer and fixed set/prompt counts (3x3 default).

Tasks:
- Add `VoteSet` and `VotePromptState` types in `bin/superlatives_game.dart`.
- Extend `RoomConfig` with `setCount`, `promptsPerSet`, `setInputSeconds`.
- Update constructors and invariants.

Tests:
- Update or add model invariants in `test/superlatives_phase1_test.dart`.

Exit criteria:
- `dart test` passes for model/tests with no runtime behavior switched yet.

## Phase 2: Content Validation for 9 Superlatives Per Category
Deliverables:
- Provider enforces minimum prompt availability per category for current config.

Tasks:
- Update `bin/content_provider.dart` validation:
  - category superlatives >= `setCount * promptsPerSet`.
- Ensure round selection produces 9 unique prompts.

Tests:
- Extend `test/superlatives_content_provider_test.dart` for min-length and uniqueness.

Exit criteria:
- Invalid data fails fast at startup/provider init.

## Phase 3: Engine Flow Rewrite from Vote-Phase to Vote-Set
Deliverables:
- Engine advances through set/prompt progression with asynchronous per-player prompt advancement.

Tasks:
- Replace `openVotePhase`/`closeVotePhase` logic with set orchestration in `bin/superlatives_engine.dart`.
- Track per-player prompt completion in active set.
- Resolve set on all-complete or timeout.
- Ensure missing prompt votes on timeout stay empty.

Tests:
- Add set lifecycle coverage in `test/superlatives_engine_test.dart`.

Exit criteria:
- One full round can run in memory with 3 sets x 3 prompts.

## Phase 4: Deferred Scoring and Round Points Accumulation
Deliverables:
- Prompt scoring feeds cumulative round entry points.
- Game scoreboard updates only once per round end.

Tasks:
- Keep existing `bin/scoring.dart` prompt math.
- Aggregate prompt results into `roundPointsByEntry` in engine.
- Move player-score application to round completion path.

Tests:
- Extend `test/superlatives_scoring_test.dart` and engine tests for deferred application.

Exit criteria:
- During round: global scoreboard unchanged.
- After round summary transition: totals updated correctly.

## Phase 5: Elimination Twist Implementation
Deliverables:
- Automatic elimination after set 1 and set 2 with minimum remaining entry constraints.

Tasks:
- Implement elimination selector in `bin/superlatives_engine.dart`:
  - Set 1: remove bottom third, keep >=3.
  - Set 2: remove bottom half, keep >=2.
- Mark `EntryStatus.eliminated`.
- Prevent voting for eliminated entries.

Tests:
- Add elimination scenarios including tie boundaries in `test/superlatives_engine_test.dart`.

Exit criteria:
- Entry pools shrink per policy and remain deterministic.

## Phase 6: Lobby Start Semantics (Any Player Can Start, Starter Becomes Host)
Deliverables:
- Start-game handling no longer requires pre-existing host; starter becomes host.

Tasks:
- Update control checks in `bin/superlatives_state_machine.dart` and `bin/superlatives_server.dart`.
- On accepted `startGame`, set `hostPlayerId` to starter.
- Keep host-only behavior for post-start controls.

Tests:
- Update `test/superlatives_room_runtime_test.dart` for start control and host assignment.

Exit criteria:
- Any active lobby player can start; winner of first accepted start is host.

## Phase 7: State Projection and Privacy Contract Update
Deliverables:
- Payloads expose set progress and round-point reveal while hiding owner identity pre-summary.

Tasks:
- Update `bin/state_projector.dart`:
  - Remove `ownerDisplayName` pre-summary.
  - Add set-level progress/timer fields.
  - Add summary `playerRoundResults`.
- Ensure display/player role scoping remains correct.

Tests:
- Extend `test/superlatives_state_projector_test.dart` for privacy and summary contract.

Exit criteria:
- No owner identity leaks before round summary.

## Phase 8: Player UI Redesign and Interaction Changes
Deliverables:
- `web/player.js`, `web/index.html`, `web/client.css` implement requested usability/UI behavior.

Tasks:
- Remove phase label display.
- Hide logout/leave when not in-room.
- Implement unobtrusive progress bar timer.
- Keep timer bar empty during entry timeout extensions.
- Simplify entry screen copy and layout.
- Add Enter-to-submit on entry input.
- Hide entries until entry phase closes.
- Remove vote number heading, update prompt text format.
- Hide player attribution until round summary.
- Show reveal as cumulative round points by entry.
- Show round summary rows with total score, entry text, points this round.

Tests:
- Add/update UI-focused assertions in runtime integration tests where feasible.
- Manual validation with 3+ browser sessions.

Exit criteria:
- All UX bullets in next-steps doc verified manually.

## Phase 9: Integration Hardening and Regression Sweep
Deliverables:
- Updated integration test suite for new flow.
- Documentation refresh and rollout notes.

Tasks:
- Update `test/superlatives_integration_test.dart` for set flow and deferred scoring.
- Re-run full `dart test`.
- Update relevant design docs if payload fields changed during implementation.

Exit criteria:
- Green test suite and successful full multiplayer manual playthrough.

## Suggested Commit Slices
1. Model/config + content validation.
2. Engine set flow + deferred scoring.
3. Elimination policy.
4. Host start semantics.
5. State projector changes.
6. Player UI changes.
7. Integration updates/docs.

## Risks and Mitigations
- Risk: set-flow complexity introduces timer race conditions.
  - Mitigation: centralize set timeout resolution in server runtime; add deterministic tests.
- Risk: privacy regressions leak owner names in payload.
  - Mitigation: projector tests that assert absence of owner fields pre-summary.
- Risk: unclear tie/elimination policy causes rework.
  - Mitigation: resolve clarifications in Phase 0 before Phase 5.
